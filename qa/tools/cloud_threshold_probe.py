#!/usr/bin/env python3
"""B1 probe: is the occlusion arm really on a different density scale from the visible cloud?

Ticket 11.E-9 claims: "the occlusion threshold is always L + 0.04 above the visible
cloud's lower edge" (start offset) and "the shadow edge is ~4.4x harder than the cloud
it comes from" (the 0.05 window against 0.22). Both claims are tested here against the
current source, with the same algebra the shaders evaluate.

Arms, as written (all three read astra_cloud_noise() on the same field):

  visible cloud   global/atmosphere/clouds_planar.glsl:222-225
      threshold    = clamp(|192 - y| / 9, 0.001, 0.999) ^ 8          (:222-223)
      coverageBias = mix(0.20, -0.20, CLOUD_COVERAGE*0.01) - 0.04 - 0.28*rain   (:181)
      continue when noise <= threshold * 0.5 + 0.25 + coverageBias   (:225)

  occlusion arm   global/atmosphere/weather.glsl:132-133
      threshold    = 0.21 + mix(0.20, -0.20, CLOUD_COVERAGE*0.01) - 0.28*rain
      cloud        = smoothstep(threshold - 0.025, threshold + 0.025, n)

  reflection board global/dimension/overworld.glsl:64-66   (A6's object, shown for contrast)
      bias         = mix(0.20, -0.20, CLOUD_COVERAGE*0.01) - 0.04 - 0.28*rain
      coverage     = smoothstep(0.21 + bias, 0.43 + bias, density)

At the sheet's mid-plane (y = 192) threshold -> 1e-24, so threshold*0.5 vanishes and the
visible cloud's lower edge is 0.25 + coverageBias.

Pinned measurement, not a gate. Re-run: python qa/tools/cloud_threshold_probe.py
"""

import math


def mix(a, b, t):
    return a + (b - a) * t


def visible_start(coverage, rain):
    """clouds_planar.glsl:181 + :225 at the sheet mid-plane."""
    coverage_bias = mix(0.20, -0.20, coverage * 0.01) - 0.04 - 0.28 * rain
    return 0.25 + coverage_bias


def occlusion_start(coverage, rain):
    """weather.glsl:132 (no -0.04 term)."""
    return 0.21 + mix(0.20, -0.20, coverage * 0.01) - 0.28 * rain


def reflection_start(coverage, rain):
    """overworld.glsl:64-65 (has the -0.04 term, 0.21 base)."""
    bias = mix(0.20, -0.20, coverage * 0.01) - 0.04 - 0.28 * rain
    return 0.21 + bias


def main():
    print("=== B1 probe: three cloud-density arms, same noise field ===")
    print()
    print("--- Part 1: lower edge in noise units, across coverage and rain ---")
    print("  %8s %6s | %12s %12s %12s | %14s %14s"
          % ("coverage", "rain", "visible", "occlusion", "reflection", "occ - vis", "refl - vis"))
    worst = 0.0
    for coverage in (0, 25, 50, 75, 100):
        for rain in (0.0, 0.5, 1.0):
            v = visible_start(coverage, rain)
            o = occlusion_start(coverage, rain)
            r = reflection_start(coverage, rain)
            worst = max(worst, abs(o - v))
            print("  %8d %6.1f | %12.4f %12.4f %12.4f | %14.6f %14.6f"
                  % (coverage, rain, v, o, r, o - v, r - v))
    print()
    print("  => occlusion - visible is %.6f across the whole grid: the two arms sit on the" % worst)
    print("     SAME lower edge. The 0.04 in the ticket is the gap between the 0.25 base of")
    print("     the visible test and the 0.21 base of the occlusion test, which is exactly")
    print("     cancelled by the -0.04 that coverageBias already carries. Both numbers are")
    print("     real; they are the same number.")
    print()
    print("--- Part 2: which arm the 0.04 really separates ---")
    c, rn = 50, 0.0
    print("  visible start    = %.4f" % visible_start(c, rn))
    print("  occlusion start  = %.4f" % occlusion_start(c, rn))
    print("  reflection start = %.4f" % reflection_start(c, rn))
    print("  => the reflection board is the arm that is 0.04 low, and that is the A6 finding")
    print("     (overworld.glsl:64-66 vs clouds_planar.glsl:225), not an occlusion mismatch.")
    print()
    print("--- Part 3: edge width, measured on the quantity each arm actually shapes ---")
    print("  visible cloud  : a hard `continue` on the march sample; the rendered edge width")
    print("                   is the march step planeDistanceDif/sampleCount (6..64 samples")
    print("                   across the 18-block sheet), i.e. roughly 0.3..3 blocks of world")
    print("                   space - NOT a 0.22-wide smoothstep.")
    print("  occlusion arm  : smoothstep over +/-0.025 = 0.05 noise units.")
    print("  reflection     : smoothstep over 0.22 noise units  <- this is where the 0.22 in")
    print("                   the ticket comes from.")
    print("  => the '4.4x harder' comparison took the reflection board's 0.22 as if it were the")
    print("     visible cloud's edge. Against the visible cloud's actual hard cut, the occlusion")
    print("     window is a softening, not a hardening.")
    print()
    print("Conclusion: 11.E-9's two premises do not hold against the current source, so no")
    print("change is made. The ticket's own acceptance line ('compare the shadow edge with the")
    print("cloud it comes from') stays valid for the CLOUD_SHADOWS option, which is off in all")
    print("three tiers; the reflection-board offset it does describe belongs to A6.")


if __name__ == "__main__":
    main()
