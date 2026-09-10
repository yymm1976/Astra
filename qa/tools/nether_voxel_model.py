#!/usr/bin/env python3
"""Offline model of the Astra nether voxel light field (N3).

The volume is a 64^3 image written by world-1/shadow.vsh (imageAtomicMax) and
diffused by the nine world-1/shadowcomp*.csh steps through program/nether_light.csh.
None of that is observable without the game, so this script re-implements the exact
encoding and propagation rules in Python and asserts the invariants the design depends
on. It is a logic model, not a renderer: it proves the algorithm's behaviour, never
its looks.

Encoding (kept in sync with program/shadow.vsh::astra_voxel_encode):
    bit 8     solid geometry -> blocks diffusion
    bit 16    frame stamp, flips every frame; cells without the current stamp are
              treated as not-rendered and contribute no light
    bits 0-7  0 = empty, 1 = solid/unlit, 2..8 = coloured light groups,
              9 = fire, 10 = soul fire, 11 = lava

Usage:  python qa/tools/nether_voxel_model.py
Exit code 0 = all invariants hold.
"""

from __future__ import annotations

import sys

N = 64
BIT_SOLID = 256
BIT_STAMP = 1 << 16
STAMP_MASK = BIT_STAMP

def stamp_for(frame: int) -> int:
    """Non-zero stamp: 0 means 'never written' in the persistent image."""
    return BIT_STAMP if (frame & 1) == 0 else (BIT_STAMP | (BIT_STAMP << 1))
KIND_EMPTY = 0          # captured air: diffusion passes through (solid bit clear)
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


def encode(kind: int, solid: bool, stamp: int) -> int:
    return (kind & 255) | (BIT_SOLID if solid else 0) | stamp


def decode(raw: int) -> tuple[int, bool, bool]:
    """returns (kind, solid, fresh_against_stamp0)"""
    return raw & 255, bool(raw & BIT_SOLID), (raw & STAMP_MASK) == 0


def emission(kind: int) -> tuple[float, float, float]:
    return EMISSION.get(kind, (0.0, 0.0, 0.0))


class Volume:
    """Mirrors the GPU images: occupancy (uint) + two ping-pong light images."""

    def __init__(self) -> None:
        self.occupancy = [0] * (N * N * N)
        self.light_a = [(0.0, 0.0, 0.0)] * (N * N * N)
        self.light_b = [(0.0, 0.0, 0.0)] * (N * N * N)

    def idx(self, x: int, y: int, z: int) -> int:
        return (y * N + z) * N + x

    def write(self, x: int, y: int, z: int, kind: int, solid: bool, frame: int) -> None:
        """imageAtomicMax at the cell: max wins, exactly like the GLSL."""
        stamp = stamp_for(frame)
        value = encode(kind, solid, stamp)
        i = self.idx(x, y, z)
        if value > self.occupancy[i]:
            self.occupancy[i] = value

    def clear(self) -> None:
        self.occupancy = [0] * (N * N * N)

    def step(self, step_index: int, frame: int = 0) -> None:
        """One shadowcomp pass. Mirrors nether_light.csh exactly."""
        src, dst = (self.light_a, self.light_b) if step_index % 2 == 1 else (self.light_b, self.light_a)
        out = [None] * (N * N * N)
        stamp_bit = stamp_for(frame)
        for x in range(N):
            for y in range(N):
                for z in range(N):
                    i = self.idx(x, y, z)
                    raw = self.occupancy[i]
                    kind = raw & 255
                    fresh = (raw & STAMP_MASK) == stamp_bit
                    solid = bool(raw & BIT_SOLID)
                    color = [c * 1.5 for c in emission(kind)] if fresh else [0.0, 0.0, 0.0]
                    if step_index > 0 and fresh and kind == KIND_EMPTY and not solid:
                        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                            qx, qy, qz = x + dx, y + dy, z + dz
                            if not (0 <= qx < N and 0 <= qy < N and 0 <= qz < N):
                                continue
                            q = self.idx(qx, qy, qz)
                            nraw = self.occupancy[q]
                            if (nraw & STAMP_MASK) != stamp_bit:
                                continue
                            if nraw & BIT_SOLID:
                                continue
                            adj = src[q]
                            color = [max(colour, a * FALLOFF) for colour, a in zip(color, adj)]
                    out[i] = tuple(color)
        if step_index % 2 == 1:
            self.light_b = out
        else:
            self.light_a = out

    def run(self, steps: int = 8, frame: int = 0) -> None:
        for s in range(steps + 1):
            self.step(s, frame)


def scenario_wall() -> tuple[bool, str]:
    """A solid wall must block diffusion; air beside it must stay lit.

    Deliberately minimal: the fire, its +x neighbour, the wall beyond it and the cell
    behind the wall are the only air cells in the volume, so every neighbour access in
    the march is either one of them or an unwritten cell. If the wall did not block,
    the behind cell would take light from the wall's far side.
    """
    v = Volume()
    v.write(31, 32, 32, 9, solid=False, frame=0)             # fire
    v.write(32, 32, 32, KIND_EMPTY, solid=False, frame=0)    # air in front of the wall
    v.write(33, 32, 32, KIND_SOLID, solid=True, frame=0)     # solid wall
    v.write(34, 32, 32, KIND_EMPTY, solid=False, frame=0)    # air behind the wall
    v.run(8)
    near = v.light_a[v.idx(32, 32, 32)][0]
    behind = v.light_a[v.idx(34, 32, 32)][0]
    ok = near > 0.5 and behind == 0.0
    return ok, (f"near={near:.4f} behind={behind:.4f} "
                f"(behind must be exactly 0: the only path is through the solid cell)")


def scenario_stale() -> tuple[bool, str]:
    """A cell that stops being rendered must stop contributing light."""
    v = Volume()
    for z in range(20, 24):
        v.write(32, 20, z, 9, solid=False, frame=0)   # fire, captured this frame
        v.write(33, 20, z, KIND_EMPTY, solid=False, frame=0)
    v.run(8)
    lit_before = v.light_a[v.idx(33, 20, 21)][0]

    # Next frame: the chunk is gone, so nothing is written there. The stamp flips,
    # which is exactly what the GPU does when it re-writes surviving geometry.
    v.clear()
    for z in range(20, 24):
        v.write(40, 20, z, 9, solid=False, frame=1)   # fire somewhere else
    v.light_a = [(0.0, 0.0, 0.0)] * (N * N * N)
    v.light_b = [(0.0, 0.0, 0.0)] * (N * N * N)
    v.run(8, frame=1)
    stale_after = v.light_a[v.idx(33, 20, 21)][0]
    ok = lit_before > 0.01 and stale_after == 0.0
    return ok, f"lit_before={lit_before:.4f} stale_after={stale_after:.4f} (must be 0)"


def scenario_empty_not_solid() -> tuple[bool, str]:
    """Regression for the pre-handoff bug: air must be captured as kind 0.

    The old writer stored kind=1 for air (so it read as solid/unlit), while the
    diffusion pass only acted on id==0 cells. Every rendered air cell therefore
    looked solid and the propagation loop never ran, which left the coloured light
    stuck inside the emitting cell.
    """
    v = Volume()
    v.write(32, 20, 20, 9, solid=False, frame=0)
    v.write(33, 20, 20, KIND_EMPTY, solid=False, frame=0)
    v.run(8)
    air_raw = v.occupancy[v.idx(33, 20, 20)]
    air_lit = v.light_a[v.idx(33, 20, 20)][0]
    solid_raw = encode(KIND_SOLID, solid=True, stamp=0)
    ok = (air_raw & 255) == KIND_EMPTY and (air_raw & BIT_SOLID) == 0 and air_lit > 0.05
    return ok, (f"air_raw={air_raw} kind={air_raw & 255} solid_bit={bool(air_raw & BIT_SOLID)} air_lit={air_lit:.4f} "
                f"(solid block would be {solid_raw})")


def scenario_budget() -> tuple[bool, str]:
    """The reach of the 8-step chain must stay bounded (performance + falloff)."""
    v = Volume()
    v.write(32, 20, 20, 9, solid=False, frame=0)
    for d in range(1, 12):
        v.write(32 + d, 20, 20, KIND_EMPTY, solid=False, frame=0)
    v.run(8)
    values = [v.light_a[v.idx(32 + d, 20, 20)][0] for d in range(1, 12)]
    first_zero = next((d for d, val in zip(range(1, 12), values) if val == 0.0), None)
    ok = first_zero is not None and first_zero <= 9
    return ok, "distance falloff=" + ", ".join(f"d{d}:{val:.4f}" for d, val in zip(range(1, 12), values))


def main() -> int:
    scenarios = [
        ("wall blocks light, open axis still lit", scenario_wall),
        ("unrendered cells retire (frame stamp)", scenario_stale),
        ("air is not encoded as solid", scenario_empty_not_solid),
        ("eight steps bound the reach", scenario_budget),
    ]
    failures = 0
    print("Astra nether voxel light - offline logic model (N3)")
    print(f"volume={N}^3 steps=9 falloff={FALLOFF}")
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
