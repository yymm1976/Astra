#!/usr/bin/env python3
"""Offline model of the Astra nether voxel light field (N3).

This mirrors the SHIPPING GLSL contract, not an idealised one. The contract was
corrected on 2026-09-11 after an independent review showed the previous model had
diverged from the GPU in three ways and therefore "passed" while the shader was broken:

  * the model used frame stamps of 65536/196608 while the GLSL produced 65536/0, so the
    odd-frame path it validated did not exist on the GPU;
  * the model fabricated air cells with an explicit write, but the real producer only
    emits vertices for solid blocks, water, plants and light sources - ordinary air is
    NEVER written and reads back as 0 from the per-frame clear;
  * the model never exercised an opaque emitter, so lava's inability to light anything
    went unnoticed.

Encoding, matching program/shadow.vsh::astra_voxel_encode exactly:
    bits 0-7 : 0 = air, 1 = solid/unlit, 2..8 = coloured light groups, 9..11 = fire,
               soul fire, lava
    bit  8   : opaque geometry. Blocks diffusion, but an EMITTER (kind >= 2) is still
               readable by its neighbours so that lava, which is a full cube, can light.
    no stamp : the image directive declares clear = true, so Iris zeroes the volume every
               frame and 0 already means air.

Usage:  python qa/tools/nether_voxel_model.py
Exit code 0 = all invariants hold.
"""

from __future__ import annotations

import sys

N = 64
BIT_SOLID = 256
KIND_AIR = 0
KIND_SOLID = 1
FALLOFF = 0.72

# Emission model copied from program/nether_light.csh::emission (time terms dropped).
EMISSION = {
    2: (1.0, 0.04, 0.01),
    3: (1.0, 0.30, 0.045),
    4: (1.0, 0.66, 0.22),
    5: (0.32, 1.0, 0.43),
    6: (0.3, 0.85, 1.0),
    7: (0.055, 0.62, 1.0),
    8: (0.64, 0.20, 1.0),
    9: (1.0, 0.30, 0.045),
    10: (0.055, 0.62, 1.0),
    11: (1.0, 0.18, 0.025),
}


def encode(kind: int, solid: bool) -> int:
    return (kind & 255) | (BIT_SOLID if solid else 0)


def emission(kind: int) -> tuple[float, float, float]:
    return EMISSION.get(kind, (0.0, 0.0, 0.0))


class Volume:
    """Mirrors the GPU images: one occupancy image plus two ping-pong light images.

    The occupancy image is cleared at the start of every frame (Iris clear=true), which
    is modelled by constructing a fresh Volume per frame rather than clearing in place.
    """

    def __init__(self) -> None:
        self.occupancy = [0] * (N * N * N)
        self.light_a: list = [(0.0, 0.0, 0.0)] * (N * N * N)
        self.light_b: list = [(0.0, 0.0, 0.0)] * (N * N * N)

    def idx(self, x: int, y: int, z: int) -> int:
        return (y * N + z) * N + x

    # ---- producer side: exactly what shadow.vsh can emit -------------------------
    def write_solid_block(self, x: int, y: int, z: int) -> None:
        """An ordinary opaque block face. This is what most vertices produce."""
        self._atomic_max(x, y, z, encode(KIND_SOLID, solid=True))

    def write_non_solid(self, x: int, y: int, z: int) -> None:
        """Water, plants, torches: a vertex exists but the block is not a full cube."""
        self._atomic_max(x, y, z, encode(KIND_AIR, solid=False))

    def write_emitter(self, x: int, y: int, z: int, kind: int, solid: bool) -> None:
        """Fire / soul fire (solid=False) and lava (solid=True)."""
        self._atomic_max(x, y, z, encode(kind, solid))

    def _atomic_max(self, x: int, y: int, z: int, value: int) -> None:
        i = self.idx(x, y, z)
        if value > self.occupancy[i]:
            self.occupancy[i] = value

    # NOTE: there is deliberately no write_air(). Ordinary air has no vertices, so the
    # producer never touches it; it stays 0 and 0 is air. Adding such a helper is exactly
    # how the previous model drifted away from the GPU.

    # ---- consumer / propagation --------------------------------------------------
    def step(self, step_index: int, reference_reads: bool = False) -> None:
        src = self.light_a if step_index % 2 == 1 else self.light_b
        out: list = [None] * (N * N * N)
        for x in range(N):
            for y in range(N):
                for z in range(N):
                    i = self.idx(x, y, z)
                    raw = self.occupancy[i]
                    kind = raw & 255
                    solid = bool(raw & BIT_SOLID)
                    color = [c * 1.5 for c in emission(kind)]
                    if step_index > 0 and not solid:
                        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                                           (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                            qx, qy, qz = x + dx, y + dy, z + dz
                            if not (0 <= qx < N and 0 <= qy < N and 0 <= qz < N):
                                continue
                            q = self.idx(qx, qy, qz)
                            if reference_reads:
                                nraw = self.occupancy[q]
                                if (nraw & BIT_SOLID) and (nraw & 255) < 2:
                                    continue
                            adj = src[q]
                            color = [max(c, a * FALLOFF) for c, a in zip(color, adj)]
                    out[i] = tuple(color)
        if step_index % 2 == 1:
            self.light_b = out
        else:
            self.light_a = out

    def run(self, steps: int = 8) -> None:
        for s in range(steps + 1):
            self.step(s)


def scenario_air_has_no_vertices() -> tuple[bool, str]:
    """R1: a fire beside never-written air must light it, on every frame parity.

    The producer writes only the fire: the air cell is never touched. Before the fix the
    frame stamp made this cell look stale on one parity and valid on the other, so the
    reading flipped between 0 and 1.08 every other frame.
    """
    results = []
    for _frame in (0, 1, 2, 3):
        v = Volume()                      # fresh volume = the per-frame clear
        v.write_emitter(32, 20, 20, 9, solid=False)
        v.run(8)
        results.append(v.light_a[v.idx(33, 20, 20)][0])
    ok = all(r > 0.5 for r in results) and max(results) - min(results) < 1e-9
    return ok, (f"parities 0..3 -> {[round(r, 4) for r in results]} "
                f"(all must be equal and non-zero; the pre-fix build gave 0 / 1.08 alternating)")


def scenario_lava_is_an_opaque_emitter() -> tuple[bool, str]:
    """R2: lava is a full cube, so it is solid - and must still light its neighbours."""
    v = Volume()
    v.write_emitter(40, 20, 20, 11, solid=True)     # lava
    v.run(8)
    lava = v.light_a[v.idx(40, 20, 20)][0]
    beside = v.light_a[v.idx(41, 20, 20)][0]        # never-written air next to it
    ok = lava > 0.5 and beside > 0.5
    return ok, (f"lava={lava:.4f} neighbour_air={beside:.4f} "
                f"(the pre-fix build gave lava=1.5 but neighbour=0)")


def scenario_solid_wall_blocks() -> tuple[bool, str]:
    """A non-emissive opaque wall must stop the light.

    Under the corrected contract an unwritten cell IS air, so a single isolated block is
    walked around: that is correct behaviour, not a leak. Blocking therefore has to be
    tested with a wall wide enough that no detour fits inside the eight-step reach - the
    plane spans 24 cells in y and z, so going around costs far more than eight steps.
    """
    v = Volume()
    v.write_emitter(30, 32, 32, 9, solid=False)                 # fire
    for dy in range(-12, 12):
        for dz in range(-12, 12):
            v.write_solid_block(32, 32 + dy, 32 + dz)           # full opaque plane
    v.run(8)
    in_front = v.light_a[v.idx(31, 32, 32)][0]
    behind = v.light_a[v.idx(33, 32, 32)][0]
    ok = in_front > 0.5 and behind == 0.0
    return ok, (f"front={in_front:.4f} behind={behind:.4f} "
                f"(behind must be exactly 0: the plane is the only path)")


def scenario_reach_is_bounded() -> tuple[bool, str]:
    v = Volume()
    v.write_emitter(32, 20, 20, 9, solid=False)
    v.run(8)
    values = [v.light_a[v.idx(32 + d, 20, 20)][0] for d in range(1, 12)]
    first_zero = next((d for d, val in zip(range(1, 12), values) if val == 0.0), None)
    ok = first_zero is not None and first_zero <= 9
    return ok, "falloff=" + ", ".join(f"d{d}:{val:.3f}" for d, val in zip(range(1, 12), values))


def scenario_equivalent_reads() -> tuple[bool, str]:
    """Compare every voxel/pass, including stale ping-pong data overwritten by step 0."""
    global N
    previous_n = N
    N = 7
    try:
        a, b = Volume(), Volume()
        import random
        rng = random.Random(20260911)
        occupancy = [encode(rng.choice((0, 1, 2, 9, 10, 11)), rng.choice((False, True)))
                     for _ in range(N ** 3)]
        for v in (a, b):
            v.occupancy = occupancy.copy()
            v.light_a = [(99.0, 99.0, 99.0)] * (N ** 3)
            v.light_b = [(99.0, 99.0, 99.0)] * (N ** 3)
        for s in range(9):
            a.step(s)
            b.step(s, reference_reads=True)
            output_a = a.light_a if s % 2 == 0 else a.light_b
            output_b = b.light_a if s % 2 == 0 else b.light_b
            if output_a != output_b:
                return False, f'neighbour-read removal diverges at step {s}'
        return True, '343 cells x 9 passes identical; opaque non-emitter stays zero'
    finally:
        N = previous_n


def main() -> int:
    scenarios = [
        ("never-written air is lit on every frame parity (R1)", scenario_air_has_no_vertices),
        ("lava lights its neighbours despite being solid (R2)", scenario_lava_is_an_opaque_emitter),
        ("non-emissive solids still block", scenario_solid_wall_blocks),
        ("eight steps bound the reach", scenario_reach_is_bounded),
        ("removing neighbour occupancy reads preserves radiance", scenario_equivalent_reads),
    ]
    failures = 0
    print("Astra nether voxel light - offline model (mirrors the shipping contract)")
    print(f"volume={N}^3 steps=9 falloff={FALLOFF} | no frame stamp; clear=true gives air=0")
    for title, fn in scenarios:
        ok, detail = fn()
        print(f"[{'PASS' if ok else 'FAIL'}] {title}")
        print(f"       . {detail}")
        if not ok:
            failures += 1
    print(f"RESULT\tinvariants={len(scenarios)}\tfailed={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
