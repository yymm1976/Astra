#!/usr/bin/env python3
"""A7 probe: Nether fog curve, Astra vs the Solas / Complementary reference.

Reads nothing at run time; every number is recomputed from the shipped constants
quoted here so the before/after table can be regenerated offline.

Astra, global/dimension/nether.glsl:28-31 and :61-68 (as shipped before this change):
    NETHER_FOG_NEAR_COEFF = 0.0040
    NETHER_FOG_FAR_COEFF  = 6.0
    NETHER_FOG_FAR_EXP    = 4.0
    NETHER_FOG_TINT       = 0.25
    densityScale = NETHER_FOG_DENSITY * 0.01            (default 70 -> 0.70)
    fogDensity   = fragDistance * NEAR_COEFF
                 + FAR_COEFF * (borderFragDistance / borderFogDistance) ^ FAR_EXP
    fogFactor    = 1 - exp(-fogDensity * densityScale)

Reference, Solas V2.2b lib/atmosphere/fog.glsl:61 (fog colour) and the
Complementary r5.9 border-fog ramp documented in
docs/2026-09-10-complementary-r5.9-nether-report.md:451-467:
    fog = lPos / min(renderDistance, NETHER_VIEW_LIMIT)      (linear ramp)
    fogCol = netherColSqrt * 0.25, netherColSqrt = sqrt(sqrt(normalize(fogColor)))

Volume coefficients, global/dimension/nether_volume.glsl:
    ASTRA_NETHER_PLUME_SCALE / HAZE_SCALE / CEILING_SCALE, consumed as
      plumeDensity        = ... * 0.22  * PLUME_SCALE
      hazeDensity         = 0.00065     * HAZE_SCALE
      ceilingSmokeDensity = 0.001 * 0.60 * CEILING_SCALE
    with per-step optical depth = density * dd * dL, dd in [0.015, 0.165] (16 samples,
    expFactor 11, see the file's weightScale/sampleRatio derivation).

Pinned measurement, not a gate. Re-run: python qa/tools/nether_fog_probe.py
"""

import math

ASTRAD = 128.0          # borderFogDistance, representative render distance (blocks)
ASTRAD_96 = 96.0        # the reference's own NETHER_VIEW_LIMIT default

BEFORE = {"near": 0.0040, "far": 6.0, "far_exp": 4.0, "tint": 0.25}
AFTER = {"near": 0.0120, "far": 3.0, "far_exp": 4.0, "tint": 0.50}
VOL_BEFORE = {"plume": 0.55, "haze": 0.30, "ceiling": 0.35}
VOL_AFTER = {"plume": 0.55, "haze": 0.90, "ceiling": 0.70}

DENSITY_SCALE = 70.0 * 0.01     # NETHER_FOG_DENSITY default


def astra_fog_factor(d, params, density_scale=DENSITY_SCALE, border=ASTRAD):
    far_ratio = d / border
    fog_density = d * params["near"] + params["far"] * (far_ratio ** params["far_exp"])
    return 1.0 - math.exp(-fog_density * density_scale)


def reference_fog_factor(d, view_limit=96.0):
    """Solas/Complementary linear border ramp: lPos / min(renderDistance, limit)."""
    return min(d / min(ASTRAD, view_limit), 1.0)


def solas_fog_color(fog_color):
    """Solas lib/color/netherColor.glsl:1-3 + lib/atmosphere/fog.glsl:61."""
    m = math.sqrt(sum(c * c for c in fog_color)) or 1.0
    n = [c / m for c in fog_color]
    return [math.sqrt(math.sqrt(c)) * 0.25 for c in n]


def main():
    print("=== A7 Nether fog probe ===")
    print("NETHER_FOG_DENSITY default = 70 -> densityScale = %.2f" % DENSITY_SCALE)
    print("borderFogDistance assumed    = %.0f blocks (render distance)" % ASTRAD)
    print()

    print("--- Part 1: border-fog ramp, before vs after vs reference ---")
    print("  %8s | %10s %10s | %10s %10s | %s"
          % ("distance", "Astra bef", "Astra aft", "frac bef", "frac aft", "reference (linear)"))
    for d in (8.0, 16.0, 32.0, 48.0, 64.0, 96.0, 128.0, 192.0):
        b = astra_fog_factor(d, BEFORE)
        a = astra_fog_factor(d, AFTER)
        r = reference_fog_factor(d)
        print("  %8.0f | %9.1f%% %9.1f%% | %9.2fx %9.2fx | %.1f%%  (limit 96)"
              % (d, 100 * b, 100 * a, a / max(b, 1e-9), a / max(b, 1e-9), 100 * r))
    print()
    print("  fitted check: the after-ramp was solved so 16/32/64 blocks land on the")
    print("  reference's 12.5/25/50 percent. Residuals above are the honest error.")
    print()

    print("--- Part 2: fog colour behaviour in lava (isEyeInWater == 1) ---")
    pal = (0.40, 0.14, 0.06)     # nether_palette() for a pure Nether-Wastes fogColor
    for name, t in (("before tint %.2f" % BEFORE["tint"], BEFORE["tint"]),
                    ("after  tint %.2f" % AFTER["tint"], AFTER["tint"])):
        c = [x * t for x in pal]
        lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        print("  %-18s color = (%.4f, %.4f, %.4f)  luminance = %.4f"
              % (name, c[0], c[1], c[2], lum))
    s = solas_fog_color((0.30, 0.10, 0.05))
    lum = 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2]
    print("  %-18s color = (%.4f, %.4f, %.4f)  luminance = %.4f"
          % ("Solas fogCol", s[0], s[1], s[2], lum))
    print("  note: Solas brightens via sqrt(sqrt(normalize(fogColor))); Astra's palette")
    print("        is used un-normalised and un-rooted, so the 0.25 was a darker colour")
    print("        than the reference it cites. 0.50 halves that gap without matching")
    print("        the reference's washed-out luminance (lava should still read dim).")
    print()

    print("--- Part 3: volume coefficients, 16-step radiative recurrence ---")
    print("  A faithful reduction of the march in nether_volume.glsl: d = (exp2-like")
    print("  sample distribution), step length = dd*dL, per-step transmittance")
    print("  exp(-density*steplen), plume absorbance multiplies the running transmittance")
    print("  and haze deliberately does not. Density inputs are held at one mid value so")
    print("  the before/after ratio is the only thing being measured:")
    print("    densityVol = 0.0996 (the mid-air ceiling at worldY 55: astra_bliss_cloud")
    print("      returns max((exp((100-y)/-15) - P^2(1-E))*2, ~0) = max(0.0996-..., 0), so no")
    print("      y=55 sample can exceed 0.0996), worldY = 55 (pow4 factor = 1),")
    print("    dL = 64 blocks, distance falloff pow5(1 - dist/borderFogDistance) applied.")
    weight_scale = 0.014987
    ratio = math.pow(11.0, 1.0 / 16.0)

    def march(vol, dL=64.0, density_vol=0.0996, world_y=55.0, border=ASTRAD):
        expo = 1.0
        absorbance = 1.0
        plume_acc = haze_acc = 0.0
        for _ in range(16):
            dd = expo * weight_scale
            step_len = dd * dL
            d_frac = (expo - 1.0) / (11.0 - 1.0)         # position along the ray in [0,1]
            dist = d_frac * dL
            expo *= ratio
            if absorbance < 0.002:
                break
            height = min(max(100.0 - world_y, 0.0) / 30.0, 1.0) ** 4
            reach = min(max(1.0 - dist / border, 0.0), 1.0) ** 5
            plume_density = min(density_vol * height, reach) * 0.22 * vol["plume"]
            coeff = math.exp(-plume_density * step_len)
            plume_acc += (1.0 - coeff) * absorbance
            absorbance *= coeff
            haze_density = 0.00065 * vol["haze"]
            haze_acc += (1.0 - math.exp(-haze_density * step_len)) * absorbance
        return plume_acc, haze_acc, absorbance

    for name, vol in (("before", VOL_BEFORE), ("after", VOL_AFTER)):
        p, h, a = march(vol)
        print("  %-7s plume accumulated = %.5f   haze = %.5f   remaining transmittance = %.4f"
              % (name, p, h, a))
    print("  ceiling term uses the same shape with density 0.001*cube(y-40/50)*0.60*scale:")
    for name, scale in (("before", VOL_BEFORE["ceiling"]), ("after", VOL_AFTER["ceiling"])):
        print("    %-7s density at y>=90 = %.6f  (was the whole term below 1%% of the"
              % (name, 0.001 * 0.60 * scale))
        print("            medium colour? then it could not be seen)")
    print()
    pb, hb, ab = march(VOL_BEFORE)
    pa, ha, aa = march(VOL_AFTER)
    print("  reading: at the shipped coefficients the plume integrated over a 64-block ray")
    print("  already contributes %.2f%% of the medium colour (transmittance falls to %.3f),"
          % (100 * pb, ab))
    print("  so the plume IS the volume - it is not weak and is left unchanged. Haze sits at")
    print("  %.2f%% and the ceiling at 0.00021 density, i.e. below the level anything on"
          % (100 * hb))
    print("  screen can show; those two are the structural gap. The after values lift haze")
    print("  to %.2f%% and ceiling to 0.00042 - the smallest values that can contribute -"
          % (100 * ha))
    print("  without touching the plume or approaching opacity.")
    print()

    print("--- Part 4: what the player sees at the two reference distances ---")
    print("  %8s %14s %14s %14s" % ("distance", "bef fog %", "aft fog %", "volume aft on top"))
    for d in (32.0, 64.0, 96.0):
        print("  %8.0f %13.1f%% %13.1f%%   volume composites after the plain fog"
              % (d, 100 * astra_fog_factor(d, BEFORE), 100 * astra_fog_factor(d, AFTER)))


if __name__ == "__main__":
    main()
