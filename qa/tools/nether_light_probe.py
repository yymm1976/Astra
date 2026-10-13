#!/usr/bin/env python3
"""A5 probe: Nether emissive/block-light intensity, Astra vs the Complementary reference.

Astra side, quoted from source (network of constants to recompute offline):

  program/nether_light.csh:19-34   emission(id) table, then `color = emission(id) * 1.5`
  global/dimension/nether.glsl     nether_block_lighting(): BLOCKLIGHT_COLOR * min(1, I)
                                   I = pow(block, 2.75) * BLOCKLIGHT_STRENGTH*0.01
                                       + pow(held, 2.75)          <- straight sum
  global/dimension/nether.glsl     sceneLighting / lavaDir / minLighting (the :142-152
                                   block the work order names)
  lib/colors.glsl:40               BLOCKLIGHT_COLOR = vec3(4.4, 2.9, 1.7)

Reference side, ComplementaryUnbound r5.8.1 + EuphoriaPatches 1.9.3, read this session:

  lib/vx/blocklightColor.glsl      per-block emission colours WITH their own multipliers
                                   (torch/soul/candle *3.5, shroomlight *4.5,
                                   lava/portal *5.0, glowstone/froglight *5.5,
                                   magma/amethyst *2.0, cave berries *2.5)
  lib/lighting/mainLighting.glsl:765   blockLighting = sqrt(pow2(blockLighting) + heldLighting)
  lib/colors/lightAndAmbientColors.glsl:97
                                   ambientColor = (netherColor + 0.5*lavaLightColor)
                                                 * (0.9 + 0.45*vsBrightness)   <- Astra identical
  lib/lighting/mainLighting.glsl:736   lava term, identical shape to Astra's
  lib/lighting/minimumLighting.glsl:11-22
                                   minLighting, identical to Astra's three factors

Verification of id -> kind mapping in nether_light.csh: comment says
"2..8 = coloured block light (mirrored from block.properties groups), 9-11 = fire, soul
fire, lava"; block.properties:10021-10027 is the R/O/Y/L/T/B/P emissive grouping.

Pinned measurement, not a gate. Re-run: python qa/tools/nether_light_probe.py
"""

# Historical model retained; its constants no longer describe the current pack.

# Astra emission() table, nether_light.csh:19-31 (id -> base colour)
if __name__ == "__main__":
    print("Retired: this historical Nether model no longer describes the current shader. See docs/archive/审查原文.md#record-029.")
    raise SystemExit(2)

ASTRA_EMISSION = {
    "2 red (redstone torch)": (1.0, 0.04, 0.01),
    "3 orange (torch, magma, campfire...)": (1.0, 0.30, 0.045),
    "4 yellow (glowstone, redstone lamp)": (1.0, 0.66, 0.22),
    "5 lime (copper torch, verdant froglight)": (0.32, 1.0, 0.43),
    "6 turquoise (sea lantern-ish)": (0.3, 0.85, 1.0),
    "7 blue": (0.055, 0.62, 1.0),
    "8 purple (amethyst, respawn anchor)": (0.64, 0.20, 1.0),
    "9 fire": (1.0, 0.30, 0.045),
    "10 soul fire": (0.055, 0.62, 1.0),
    "11 lava": (1.0, 0.18, 0.025),
}

# Reference per-kind colours including the reference's own multiplier
REFERENCE = {
    "torch / lantern / campfire / fire": ((1.00, 0.5, 0.15), 3.5),
    "soul torch / soul lantern / soul fire": ((0.10, 0.60, 1.00), 3.5),
    "magma block": ((1.00, 0.20, 0.05), 2.00),
    "lava": ((1.00, 0.18, 0.02), 5.0),
    "glowstone": ((1.00, 0.60, 0.30), 5.5),
    "shroomlight / redstone lamp": ((1.00, 0.30, 0.10), 4.5),
    "sea lantern": ((0.70, 0.90, 1.00), 6.5),
    "cave berries": ((1.00, 0.40, 0.10), 2.5),
    "amethyst": ((0.80, 0.30, 1.00), 2.0),
}

# The change under test
ASTRA_SCALE_BEFORE = 1.5
ASTRA_SCALE_AFTER = 3.5

BLOCKLIGHT_COLOR = (4.4, 2.9, 1.7)
BLOCKLIGHT_EXP = 2.75


def main():
    print("=== A5 Nether emissive / block-light probe ===")
    print("Astra applies ONE multiplier to every species (nether_light.csh:34); the")
    print("reference gives each kind its own (lib/vx/blocklightColor.glsl).")
    print()
    print("--- Part 1: voxel emission, Astra before -> after vs reference ---")
    print("  %-40s %-24s %-24s %s" % ("kind", "Astra x1.5", "Astra x3.5", "reference"))
    pairs = (
        ("3 orange (torch, magma, campfire...)", "torch / lantern / campfire / fire"),
        ("11 lava", "lava"),
        ("4 yellow (glowstone, redstone lamp)", "glowstone"),
        ("10 soul fire", "soul torch / soul lantern / soul fire"),
    )
    for a_key, r_key in pairs:
        base = ASTRA_EMISSION[a_key]
        rb, rm = REFERENCE[r_key]
        b = tuple(c * ASTRA_SCALE_BEFORE for c in base)
        a = tuple(c * ASTRA_SCALE_AFTER for c in base)
        r = tuple(c * rm for c in rb)
        print("  %-40s (%.2f, %.2f, %.3f)   (%.2f, %.2f, %.3f)   (%.2f, %.2f, %.2f)"
              % (a_key, b[0], b[1], b[2], a[0], a[1], a[2], r[0], r[1], r[2]))
    print()
    print("  ratio to reference on the dominant channel, before -> after:")
    for a_key, r_key in pairs:
        base = ASTRA_EMISSION[a_key]
        rb, rm = REFERENCE[r_key]
        r = tuple(c * rm for c in rb)
        f = max(range(3), key=lambda i: r[i])
        before = base[f] * ASTRA_SCALE_BEFORE
        after = base[f] * ASTRA_SCALE_AFTER
        print("    %-40s %.2f -> %.2f" % (a_key, before / r[f], after / r[f]))
    print()
    print("  x3.5 is the reference multiplier for the torch / soul / candle family, the")
    print("  Nether's most common emitters; the single-multiplier design cannot match the")
    print("  *2.0 magma and *5.5 glowstone ends at the same time. Before the change every")
    print("  family sat at 26-43% of the reference; after it the torch family matches and")
    print("  lava reaches 70%.")
    print()

    print("--- Part 2: block light + held light composition ---")
    print("  Astra nether_block_lighting():  I = pow(block,2.75)*B + pow(held,2.75)")
    print("  reference mainLighting.glsl:765: block = sqrt(block^2 + held^2)")
    bc = BLOCKLIGHT_COLOR
    for block_lm, held_lm in ((0.5, 0.0), (1.0, 0.0), (0.5, 0.5), (1.0, 1.0), (0.8, 0.3)):
        b = (block_lm ** BLOCKLIGHT_EXP) if block_lm else 0.0
        h = (held_lm ** BLOCKLIGHT_EXP) if held_lm else 0.0
        astra_sum = min(1.0, b + h)
        astra_sq = min(1.0, (b * b + h * h) ** 0.5)
        print("    block=%.2f held=%.2f | straight sum %.4f -> sqrt-sum %.4f (x%.3f) | "
              "reference %s"
              % (block_lm, held_lm, astra_sum, astra_sq,
                 astra_sq / max(astra_sum, 1e-9), "sqrt-sum" if True else ""))
    print()
    print("  with no hand light the two forms agree exactly (held=0 -> sqrt(b^2) = b), so")
    print("  the change only affects frames where a light source is held: it removes the")
    print("  early saturation to 1.0 and keeps colour separation between the two sources.")
    print("  BLOCKLIGHT_COLOR (%.1f, %.1f, %.1f) is unchanged." % bc)
    print()

    print("--- Part 3: the :142-152 lighting block, Astra vs reference, item by item ---")
    rows = (
        ("sceneLighting base", "(netherColor + 0.5*lavaLightColor)*(0.9+0.45*vs)",
         "(netherCol + 0.5*NETHER_LAVA_LIGHT_COLOR)*(0.9+0.45*VS)", "identical"),
        ("lava direction term", "lavaLightColor * pow2(|NdotN|*0.5 + max0(-NdotU))*(0.7+0.35*vs)",
         "NETHER_LAVA_LIGHT_COLOR * (lavaDir*lavaDir) * (0.7 + 0.35*VS)", "identical"),
        ("min-light base", "0.005625 + vsBrightness * 0.043",
         "0.005625 + NETHER_VS_BRIGHTNESS * 0.043", "identical"),
        ("min-light tint", "vec3(0.45, 0.475, 0.6)", "NETHER_FLOOR_TINT", "identical"),
        ("min-light block fade", "* (1.0 - lightmapYM)", "* (1.0 - blockLight)", "identical"),
        ("night-vision add", "+ nightVision * vec3(0.5, 0.5, 0.75)",
         "+ params.nightVision * NETHER_NIGHT_VISION_TINT_REF", "identical"),
    )
    for name, ref, astra, verdict in rows:
        print("  %-22s %-8s" % (name, verdict))
        print("      reference: %s" % ref)
        print("      Astra    : %s" % astra)
    print()
    print("  => the :142-152 block needs no change: every factor already matches the")
    print("     reference source line by line. The measured gap was in nether_light.csh.")


if __name__ == "__main__":
    main()
