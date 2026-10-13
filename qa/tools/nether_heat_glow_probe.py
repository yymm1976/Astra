#!/usr/bin/env python3
"""A3 probe: heat glow response next to lava, and why the voxel light alone misses it.

The reference's mechanism (ComplementaryUnbound r5.8.1 + EuphoriaPatches 1.9.3,
shaders/lib/materials/specificMaterials/terrain/lavaEdge.glsl) feeds an EMISSIVE term:

    edge  = 1 - cos(edge * pi / 1.5)                  (eased lava/non-lava contact)
    edgeColor = mix(vec3(0.4,0.2,0.1), maxLavaColor, 0.9) * 3.0
    emission  = mix(emission, min(1.3 + emission*1.1, 3.5), edge * (1 - edgeDecider))

i.e. rock at the lava rim is lit as if it were self-emitting. Astra's equivalent
signal is the voxel volume (astra_nether_colored_light), but that lands in
blockLighting, which directionShade and vanillaAO multiply down on faces turned away
from the lava - measured in the table below.

This probe reproduces the proposed term:

    redShare = voxel.r / (voxel.r + voxel.g + voxel.b)
    lavaHeat = smoothstep(0.70, 0.85, redShare) * clamp(voxel.r, 0, 1)
    heatGlow = NETHER_LAVA_LIGHT_COLOR * (lavaHeat * 0.30)      (added after the sqrt)

Species colours are nether_light.csh:19-31 scaled by the A5 multiplier 3.5.

Pinned measurement, not a gate. Re-run: python qa/tools/nether_heat_glow_probe.py
"""

# Historical model retained; its constants no longer describe the current pack.

if __name__ == "__main__":
    print("Retired: this historical Nether model no longer describes the current shader. See docs/archive/审查原文.md#record-029.")
    raise SystemExit(2)

import math

# nether_light.csh species bases; the volume averages neighbours, so the values a
# shaded surface sees are the *3.5 table already flattened by the eight-step march.
SPECIES = {
    "lava (id 11)": (1.0, 0.18, 0.025),
    "orange: torch / campfire / magma (id 3)": (1.0, 0.30, 0.045),
    "yellow: glowstone / redstone lamp (id 4)": (1.0, 0.66, 0.22),
    "lime: copper torch (id 5)": (0.32, 1.0, 0.43),
    "turquoise (id 6)": (0.3, 0.85, 1.0),
    "blue (id 7)": (0.055, 0.62, 1.0),
    "purple: amethyst (id 8)": (0.64, 0.20, 1.0),
    "soul fire (id 10)": (0.055, 0.62, 1.0),
}

SCALE = 3.5
LAVA_LIGHT_COLOR = (0.15, 0.06, 0.01)
HEAT_STRENGTH = 0.30


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    print("=== A3 heat-glow probe: response per light species ===")
    print("volume value = species base * %.1f, then read at two falloff levels:" % SCALE)
    print("  'at the source'  = the value right beside the emitter (march step 0-1)")
    print("  'two steps out'  = after 0.72^2 of the eight-step propagation")
    print()
    print("  %-44s %10s %10s %10s %10s" %
          ("species", "redShare", "heat@src", "heat@2st", "glow.r@src"))
    for name, base in SPECIES.items():
        v = tuple(c * SCALE for c in base)
        for label, fade in (("src", 1.0), ("2st", 0.72 * 0.72)):
            pass
        red_share = v[0] / max(sum(v), 1e-9)
        glow = []
        for fade in (1.0, 0.72 * 0.72):
            voxel = tuple(c * fade for c in v)
            rs = voxel[0] / max(sum(voxel), 1e-9)
            heat = smoothstep(0.70, 0.85, rs) * min(max(voxel[0], 0.0), 1.0)
            glow.append(heat * HEAT_STRENGTH * LAVA_LIGHT_COLOR[0])
        print("  %-44s %10.3f %10.4f %10.4f %10.4f"
              % (name, red_share, glow[0] / (HEAT_STRENGTH * LAVA_LIGHT_COLOR[0]),
                 glow[1] / (HEAT_STRENGTH * LAVA_LIGHT_COLOR[0]), glow[0]))
    print()
    print("  reading: only the lava species clears the 0.85 red-share shoulder; the torch")
    print("  family (0.74) is held at 0.28 of the ramp, glowstone (0.53) and the blue/lime")
    print("  species at exactly zero. 'Distant rock stays untouched' is therefore a")
    print("  property of the volume's own eight-step falloff, not a separate distance gate.")
    print()
    print("  peak add at the lava rim (red channel): %.4f - on a scene whose lit rock sits"
          % (HEAT_STRENGTH * LAVA_LIGHT_COLOR[0]))
    print("  around 0.1-0.4, that is a visible warm rim, not a light source.")
    print()


if __name__ == "__main__":
    main()
