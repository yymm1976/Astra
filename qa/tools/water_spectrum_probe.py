#!/usr/bin/env python3
"""A1 probe: above-water shallow-to-deep water colour chain, Astra vs Steadfast 0.8.0.

Reproduces, in double precision, the exact expressions Astra ships:

  water_surface_absorption()   global/water/absorption.glsl:16-34   (per character)
  appearanceDepth              global/water/absorption.glsl:74      (depth + 1, clamp 24)
  transmission                 global/water/absorption.glsl:75      exp(-depth * sigma)
  water_body_color()           global/water/absorption.glsl:70      (0.020, 0.160, 0.300)
  surface fill                 global/water/absorption.glsl:77-78   radiance*T + body*(1-T)*light
  incident light proxy         program/scene.glsl:65-73             astra_water_incident(skylight)
  per-surface depth            program/water.glsl:41-44             top: depth, side: min(depth,1)

and Steadfast 0.8.0's reference spectra for comparison:

  WaterAbsorption              _refs_extracted/steadfast/.../absorption.glsl:24-33
  normalized water depth       _refs_extracted/steadfast/.../absorption_refraction.glsl:53-56

Everything here is read-only: no shader or config file is touched.

Pinned measurement, not a gate. Re-run: python qa/tools/water_spectrum_probe.py
"""

import math

# --- Astra, as shipped (settings.glsl defaults: WATER_ABSORPTION=100, MIN_AMBIENT=8) ---
WATER_ABSORPTION = 100.0
SKYLIGHT_STRENGTH = 100.0
MIN_AMBIENT = 8.0

# lib/colors.glsl:49-50
MIN_AMBIENT_TINT = (0.33, 0.8, 1.0)
MIN_AMBIENT_COLOR = tuple(MIN_AMBIENT * 0.001 * c for c in MIN_AMBIENT_TINT)

# global/dimension/overworld.glsl:29,35 at noon (sunProgress=1, twilight=1)
DAY_AMBIENT_NOON = (0.36, 0.43, 0.57)
DAY_AMBIENT_DAWN = (0.28, 0.30, 0.35)

# absorption.glsl:23-32, each scaled by WATER_ABSORPTION*0.01
CHARACTERS = {
    "COLD (0)": (1.000, 0.2200, 0.0800),
    "BALANCED (1, default)": (1.000, 0.1000, 0.0600),
    "TROPICAL (2)": (2.000, 0.0800, 0.0550),
}

# absorption.glsl:70
WATER_BODY_COLOR = (0.020, 0.160, 0.300)

# --- Steadfast 0.8.0 reference ---
STEADFAST = {
    "COLD": (16.0, 5.0, 1.0),
    "BALANCED": (16.0, 3.0, 1.0),
    "TROPICAL": (32.0, 2.0, 0.5),
}


def astra_incident(skylight, day_ambient):
    """program/scene.glsl:65-72: ambient-only incident light for the water fill."""
    access = smoothstep(0.0, 0.40, skylight)
    outdoor = tuple(c * (SKYLIGHT_STRENGTH * 0.01) for c in day_ambient)
    return tuple(mix(MIN_AMBIENT_COLOR[i], outdoor[i], access) for i in range(3))


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def astra_transmission(depth_blocks, coefficient):
    """absorption.glsl:72-78 for one character."""
    appearance_depth = min(max(depth_blocks + 1.0, 0.0), 24.0)
    sigma = tuple(c * (WATER_ABSORPTION * 0.01) for c in coefficient)
    return appearance_depth, tuple(math.exp(-appearance_depth * s) for s in sigma)


def astra_surface_color(background, depth_blocks, coefficient, incident):
    """absorption.glsl:77-78."""
    _, T = astra_transmission(depth_blocks, coefficient)
    color = tuple(background[i] * T[i] + WATER_BODY_COLOR[i] * min(max(incident[i], 0.0), 2.0)
                  * (1.0 - T[i]) for i in range(3))
    return T, color


def steadfast_transmission(depth_blocks, coefficient):
    """Steadfast absorption.glsl:33 with the depth normalization at
    absorption_refraction.glsl:53-56 (15 blocks + a 1/16 surface offset, capped at 1)."""
    nd = min(max(depth_blocks * (1.0 / 16.0) + 1.0 / 16.0, 0.0), 1.0)
    return nd, tuple(math.exp(-nd * c) for c in coefficient)


def hue_deg(rgb):
    """Standard HSV hue in degrees; returns None for grey."""
    r, g, b = rgb
    mx, mn = max(rgb), min(rgb)
    d = mx - mn
    if d <= 1e-12:
        return None
    if mx == r:
        h = 60.0 * (((g - b) / d) % 6.0)
    elif mx == g:
        h = 60.0 * ((b - r) / d + 2.0)
    else:
        h = 60.0 * ((r - g) / d + 4.0)
    return h % 360.0


def label(h, rgb):
    if hue_deg(rgb) is None:
        return "grey"
    if h is None:
        return "-"
    if 150.0 <= h < 195.0:
        return "CYAN"
    if 195.0 <= h < 250.0:
        return "BLUE"
    if 90.0 <= h < 150.0:
        return "GREEN"
    if h < 90.0:
        return "warm"
    return "violet"


BACKGROUNDS = {
    "sand (1.00,0.93,0.72)": (1.00, 0.93, 0.72),
    "stone (0.45,0.45,0.45)": (0.45, 0.45, 0.45),
    "white (1,1,1)": (1.0, 1.0, 1.0),
}

DEPTHS = (0.0, 0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 16.0, 20.0, 24.0)


def main():
    print("=== A1 water spectrum probe: above-water bed appearance ===")
    print("Astra defaults in force: WATER_ABSORPTION=%.0f, WATER_CHARACTER=BALANCED(1), "
          "MIN_AMBIENT=%.0f" % (WATER_ABSORPTION, MIN_AMBIENT))
    print()

    noon = astra_incident(1.0, DAY_AMBIENT_NOON)
    print("incident light proxy at skylight=1.0 (noon, open sky): "
          "(%.4f, %.4f, %.4f)" % noon)
    print("MIN_AMBIENT_COLOR = (%.5f, %.5f, %.5f)" % MIN_AMBIENT_COLOR)
    print()

    # ---- Part 1: transmission per character, per depth ----
    print("--- Part 1: appearanceDepth and transmission T = exp(-appearanceDepth * sigma) ---")
    for name, coef in CHARACTERS.items():
        sigma = tuple(c * WATER_ABSORPTION * 0.01 for c in coef)
        print()
        print("  %s   sigma/block = (%.4f, %.4f, %.4f)  g/b sigma ratio = %.3f"
              % (name, sigma[0], sigma[1], sigma[2], sigma[1] / sigma[2]))
        print("  %6s %8s   %-24s %8s %8s  %s"
              % ("depth", "apprDep", "T (r,g,b)", "g/b", "b/g", "verdict on T alone"))
        for d in DEPTHS:
            ad, T = astra_transmission(d, coef)
            h = hue_deg(T)
            print("  %6.2f %8.2f   (%.4f, %.4f, %.4f) %8.3f %8.3f  %s"
                  % (d, ad, T[0], T[1], T[2], T[1] / T[2], T[2] / T[1],
                     "hue %.1f deg" % h if h is not None else "grey"))

    # ---- Part 2: Astra vs Steadfast transmission ----
    print()
    print("--- Part 2: Astra BALANCED vs Steadfast BALANCED, same depths ---")
    print("  %6s | %-22s | %-22s | delta" % ("depth", "Astra T (r,g,b)", "Steadfast T (r,g,b)"))
    for d in DEPTHS:
        _, Ta = astra_transmission(d, CHARACTERS["BALANCED (1, default)"])
        nd, Ts = steadfast_transmission(d, STEADFAST["BALANCED"])
        print("  %6.2f | (%.4f, %.4f, %.4f) | (%.4f, %.4f, %.4f) | dr=%+.4f dg=%+.4f db=%+.4f"
              % (d, Ta[0], Ta[1], Ta[2], Ts[0], Ts[1], Ts[2],
                 Ta[0] - Ts[0], Ta[1] - Ts[1], Ta[2] - Ts[2]))

    # ---- Part 3: composed appearance (bed * T + fill) ----
    print()
    print("--- Part 3: composed above-water bed colour = bed*T + water_body_color*light*(1-T) ---")
    print("incident = noon proxy (%.4f, %.4f, %.4f); fill keeps the spectrum's own hue"
          % noon)
    for bg_name, bg in BACKGROUNDS.items():
        print()
        print("  background %s" % bg_name)
        print("  %6s %-22s %8s %8s  %s" % ("depth", "composed (r,g,b)", "hue", "b/g", "label"))
        for d in DEPTHS:
            T, col = astra_surface_color(bg, d, CHARACTERS["BALANCED (1, default)"], noon)
            h = hue_deg(col)
            lab = label(h, col)
            print("  %6.2f (%.4f, %.4f, %.4f) %8s %8.3f  %s"
                  % (d, col[0], col[1], col[2],
                     "%.1f" % h if h is not None else "grey", col[2] / max(col[1], 1e-9), lab))

    # ---- Part 4: where does the cyan come from? ----
    print()
    print("--- Part 4: cyan attribution at 0 blocks (sand bed) ---")
    sand = BACKGROUNDS["sand (1.00,0.93,0.72)"]
    T, col = astra_surface_color(sand, 0.0, CHARACTERS["BALANCED (1, default)"], noon)
    bed_part = tuple(sand[i] * T[i] for i in range(3))
    fill_part = tuple(col[i] - bed_part[i] for i in range(3))
    print("  bed*T      = (%.4f, %.4f, %.4f)  hue %s  <- the bed's own warm colour, red removed"
          % (bed_part + ("%.1f" % hue_deg(bed_part),)))
    print("  fill       = (%.4f, %.4f, %.4f)  hue %s" % (fill_part + ("%.1f" % hue_deg(fill_part),)))
    print("  total      = (%.4f, %.4f, %.4f)  hue %.1f  (%s)"
          % (col[0], col[1], col[2], hue_deg(col), label(hue_deg(col), col)))
    print()
    print("  Same bed with a NEUTRAL grey background (stone):")
    _, colg = astra_surface_color(BACKGROUNDS["stone (0.45,0.45,0.45)"], 0.0,
                                  CHARACTERS["BALANCED (1, default)"], noon)
    hg = hue_deg(colg)
    print("  total      = (%.4f, %.4f, %.4f)  hue %.1f  (%s)  b/g=%.3f"
          % (colg[0], colg[1], colg[2], hg, label(hg, colg), colg[2] / colg[1]))

    # ---- Part 5: deep end ----
    print()
    print("--- Part 5: deep end at 16 blocks, sand bed ---")
    for name, coef in CHARACTERS.items():
        T, col = astra_surface_color(sand, 16.0, coef, noon)
        h = hue_deg(col)
        print("  %-22s T=(%.5f, %.4f, %.4f)  col=(%.4f, %.4f, %.4f)  hue %6s  b/g=%6.3f  %s"
              % (name, T[0], T[1], T[2], col[0], col[1], col[2],
                 "%.1f" % h if h is not None else "grey", col[2] / col[1], label(h, col)))
    nd, Ts = steadfast_transmission(16.0, STEADFAST["BALANCED"])
    cols = tuple(sand[i] * Ts[i] for i in range(3))
    print("  %-22s T=(%.5f, %.4f, %.4f)  col=(%.4f, %.4f, %.4f)  hue %6.1f  b/g=%6.3f  (no fill in ref)"
          % ("Steadfast BALANCED", Ts[0], Ts[1], Ts[2], cols[0], cols[1], cols[2],
             hue_deg(cols), cols[2] / max(cols[1], 1e-9)))

    # ---- Part 6: the shallow band in numbers ----
    print()
    print("--- Part 6: shallow band (0-3 blocks): is the water tint readable at all? ---")
    print("  %6s %10s %10s %10s   %s" % ("depth", "red kept", "green kept", "blue kept", "note"))
    for d in (0.0, 1.0, 2.0, 3.0):
        _, T = astra_transmission(d, CHARACTERS["BALANCED (1, default)"])
        note = ""
        if d == 0.0:
            note = "knee-deep water already loses %.0f%% of red" % (100.0 * (1.0 - T[0]))
        print("  %6.2f %9.1f%% %9.1f%% %9.1f%%   %s"
              % (d, 100 * T[0], 100 * T[1], 100 * T[2], note))

    # ---- Part 7: candidate depth-interpolated spectrum (A1 fix) ----
    print()
    print("--- Part 7: candidate depth-interpolated spectrum vs shipped ---")
    print("The shipped spectrum has sigma_g > sigma_b at EVERY depth, so T is blue-leaning")
    print("everywhere (Part 1: g/b <= 0.96) and the cyan of the shallows can only come from a")
    print("warm bed. On a neutral bed the shallows read blue-teal (Part 4: hue 184.6).")
    print("Candidate: interpolate two ends by appearanceDepth, u = clamp((ad-1)/15, 0, 1);")
    print("  shallow end sigma_b > sigma_g  -> green survives -> cyan-green T;")
    print("  deep end    sigma_g >> sigma_b -> deep blue, wider gap than the shipped 0.04.")
    candidates = {
        "BALANCED (1, default)": ((1.000, 0.0500, 0.0900), (1.000, 0.3000, 0.0500)),
        "TROPICAL (2)": ((2.000, 0.0400, 0.0700), (2.000, 0.2400, 0.0450)),
    }
    for name, (shallow, deep) in candidates.items():
        print()
        print("  %s   shallow sigma (%.4f, %.4f, %.4f)  deep sigma (%.4f, %.4f, %.4f)"
              % (name, shallow[0], shallow[1], shallow[2], deep[0], deep[1], deep[2]))
        for bg_name in ("sand (1.00,0.93,0.72)", "stone (0.45,0.45,0.45)"):
            bg = BACKGROUNDS[bg_name]
            print("    bed %s" % bg_name)
            print("    %6s %10s   %-22s %8s %8s  %s"
                  % ("depth", "u", "T (r,g,b)", "hue", "b/g", "label"))
            for d in (0.0, 1.0, 2.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0):
                ad = min(max(d + 1.0, 0.0), 24.0)
                u = min(max((ad - 1.0) / 15.0, 0.0), 1.0)
                coef = tuple(mix(shallow[i], deep[i], u) for i in range(3))
                sigma = tuple(c * WATER_ABSORPTION * 0.01 for c in coef)
                T = tuple(math.exp(-ad * s) for s in sigma)
                col = tuple(bg[i] * T[i] + WATER_BODY_COLOR[i] * min(max(noon[i], 0.0), 2.0)
                            * (1.0 - T[i]) for i in range(3))
                h = hue_deg(col)
                print("    %6.2f %10.3f   (%.4f, %.4f, %.4f) %8s %8.3f  %s"
                      % (d, u, T[0], T[1], T[2], "%.1f" % h if h is not None else "grey",
                         col[2] / max(col[1], 1e-9), label(h, col)))

    print()
    print("Reading guide for the in-game pass:")
    print("  * the transmission's own hue is BLUE-leaning at every depth (g/b < 1) because")
    print("    green is absorbed faster than blue; that is the 2026-09-20 C1 re-ordering.")
    print("  * 'cyan' in the composed image therefore comes from the BED, not from the")
    print("    water: a warm sand bed multiplied by T keeps its green over blue and reads")
    print("    cyan; a neutral bed reads blue-teal at every depth (Part 4).")
    print("  * the deep end's blueness is set by the green-blue sigma gap: Astra BALANCED")
    print("    %.3f/block vs Steadfast %.3f/block, i.e. %.2fx weaker (Part 2/5)."
          % (0.1000 - 0.0600, 3.0 / 16.0 - 1.0 / 16.0, (0.1000 - 0.0600) / (2.0 / 16.0)))


if __name__ == "__main__":
    main()
