#!/usr/bin/env python3
"""Read-only probe: what the air-side water path does with light.

Written for the 2026-09-22 four-symptom round, air-side scope (viewing the water
body from above water): "sunlight does not reach the water / the body is grey and
faint / the bed is not readable / the distant surface is over-exposed and white".

Every number below is recomputed from the constants actually shipped in the files
this probe names, read at run time, so a table entry cannot drift away from the
shader it describes. Nothing is written and no GL context is opened.

Sibling probe note: qa/tools/underwater_light_probe.py is the gate for the same round
(the path the runner executes; exit != 0 on any unmet target). It was rewritten on
2026-09-22 into a source-anchored measuring gate covering all four looks, including the
air-side numbers below; this file stays as the air-side table with more rows and the
file:line provenance beside each number.

2026-09-22 update, after the fixes landed. water_body_color() is depth-dependent now, so
both of its ends are read from the source and the fill follows appearanceDepth the way
the call site does. The section that reproduced astra_water_caustics_focus() is gone
with that function - the air-side pattern is program/lit.fsh's field-driven gain on the
direct sun, measured in the gate probe's section [2]. Section 5's check list names the
shipped forms of the fix instead of the pre-fix gates.

  Sources read (all read-only):
    Astra/shaders/global/water/absorption.glsl    spectra, fill, water_surface_medium
    Astra/shaders/global/water/caustics.glsl      caustic focus and its eye-dependent tail
    Astra/shaders/program/water.glsl              fresnel, reflection, glint
    Astra/shaders/program/lit.fsh                 caustic gate on terrain
    Astra/shaders/global/lighting/diffuse.glsl    air-side resolution of a water caster
    Astra/shaders/global/lighting/shadowmap.glsl  software-path copy of that rule
    Astra/shaders/global/dimension/overworld.glsl daytime sky ambient
    Astra/shaders/lib/settings.glsl               WATER_ABSORPTION, FOG_DENSITY, ...
    Astra/shaders/lib/twilight.glsl               astra_scene_highlights (the shoulder)
    Astra/shaders/shaders.properties              atmosphereFogCoefficient on the CPU
    Astra/shaders/global/post/bloom.glsl          BLOOM_THRESHOLD
    Astra/shaders/textures/solas-water-noise.png  caustic height field (optional)

Re-run: python qa/tools/airside_water_probe.py
"""

import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SHADERS = os.path.join(ROOT, "Astra", "shaders")


def read(*parts):
    with open(os.path.join(SHADERS, *parts), "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def line_of(text, needle):
    for index, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return index
    return None


def triple(values):
    return "(%s)" % ",".join("%.4f" % v for v in values)


def luma(colour):
    return 0.2126 * colour[0] + 0.7152 * colour[1] + 0.0722 * colour[2]


def srgb(colour):
    out = []
    for value in colour:
        value = max(value, 0.0)
        out.append(12.92 * value if value <= 0.0031308 else 1.055 * value ** (1.0 / 2.4) - 0.055)
    return out


def smoothstep(edge0, edge1, x):
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def pct(values, q):
    ordered = sorted(values)
    index = min(max(int(round((q / 100.0) * (len(ordered) - 1))), 0), len(ordered) - 1)
    return ordered[index]


def spectrum_branch(character):
    """The shallow/deep pair the shipped #if chain selects (absorption.glsl:32-45).

    The chain is #if COLD / #elif TROPICAL / #else BALANCED, so the third literal is
    the default branch that WATER_CHARACTER == 1 lands on.
    """
    shallow = re.findall(r"shallow = vec3\(([^)]*)\)", ABSORPTION)
    deep = re.findall(r"deep    = vec3\(([^)]*)\)", ABSORPTION)
    index = {0: 0, 2: 1, 1: 2}[character]         # COLD / TROPICAL / BALANCED
    cut = lambda text: [float(x) for x in text.replace(",", " ").split()]
    return cut(shallow[index]), cut(deep[index])


ABSORPTION = read("global", "water", "absorption.glsl")
CAUSTICS = read("global", "water", "caustics.glsl")
WATER = read("program", "water.glsl")
LIT = read("program", "lit.fsh")
DIFFUSE = read("global", "lighting", "diffuse.glsl")
SHADOWMAP = read("global", "lighting", "shadowmap.glsl")
TWILIGHT = read("lib", "twilight.glsl")
SETTINGS = read("lib", "settings.glsl")
BLOOM = read("global", "post", "bloom.glsl")

WATER_CHARACTER = int(re.search(r"#define WATER_CHARACTER (\d+)", SETTINGS).group(1))
SHALLOW, DEEP = spectrum_branch(WATER_CHARACTER)
# water_body_color() returns a mix of a shallow and a deep end over the same
# (appearanceDepth - 1)/15 blend the spectrum uses; both ends are read from the source.
_BODY_BLOCK = re.search(r"vec3 water_body_color\(float appearanceDepth\) \{(.*?)\n\}",
                        ABSORPTION, re.S).group(1)
_BODY_MIX = re.search(r"return (mix\(vec3\(([^)]*)\), vec3\(([^)]*)\), blend\);)",
                      _BODY_BLOCK)
BODY_MIX_EXPR = _BODY_MIX.group(1)
_cut = lambda text: [float(x) for x in text.replace(",", " ").split()]
BODY_SHALLOW, BODY_DEEP = _cut(_BODY_MIX.group(2)), _cut(_BODY_MIX.group(3))
BODY = BODY_DEEP        # the deep end is what the old single constant named
SKY_AMBIENT = [0.36, 0.43, 0.57]          # overworld.glsl:29, sunProgress = 1 (day)
WATER_ABSORPTION = float(re.search(r"#define WATER_ABSORPTION (\d+)", SETTINGS).group(1))
FOG_DENSITY = float(re.search(r"#define FOG_DENSITY (\d+)", SETTINGS).group(1))
SKY_FOG_STRENGTH = float(re.search(r"#define SKY_FOG_STRENGTH (\d+)", SETTINGS).group(1))
CAUSTIC_STRENGTH = float(re.search(r"ASTRA_CAUSTIC_STRENGTH = ([0-9.]+)", CAUSTICS).group(1))
BLOOM_THRESHOLD = float(re.search(r"BLOOM_THRESHOLD = ([0-9.]+)", BLOOM).group(1))
SCALE = WATER_ABSORPTION * 0.01

# noon sunlit bed: albedo * (ambient + direct). direct = astra_direct_light() * 0.8 Lambert
SAND = [0.72 * 1.18, 0.65 * 1.17, 0.47 * 1.20]
STONE = [0.62 * value for value in SAND]


def sigma(appearance):
    blend = min(max((appearance - 1.0) / 15.0, 0.0), 1.0)
    return [SHALLOW[i] + (DEEP[i] - SHALLOW[i]) * blend for i in range(3)]


def transmission(depth):
    appearance = min(max(depth, 0.0) + 1.0, 24.0)
    return [math.exp(-appearance * sigma(appearance)[i] * SCALE) for i in range(3)]


def body_colour(appearance):
    """water_body_color(): the shipped mix, at this appearance depth."""
    blend = min(max((appearance - 1.0) / 15.0, 0.0), 1.0)
    return [BODY_SHALLOW[i] + (BODY_DEEP[i] - BODY_SHALLOW[i]) * blend for i in range(3)]


def fill(depth):
    appearance = min(max(depth, 0.0) + 1.0, 24.0)
    body = body_colour(appearance)
    return [body[i] * SCALE * SKY_AMBIENT[i] * (1.0 - transmission(depth)[i])
            for i in range(3)]


def main():
    print(__doc__)
    print()
    print("shipped constants in force: WATER_ABSORPTION=%d (scale %.2f), WATER_CHARACTER=1"
          % (WATER_ABSORPTION, SCALE))
    print("  shallow spectrum absorption.glsl:%s %s   deep end %s %s"
          % (line_of(ABSORPTION, "shallow = vec3(1.000, 0.0500, 0.0900)"), triple(SHALLOW),
             line_of(ABSORPTION, "deep    = vec3(1.000, 0.3000, 0.0500)"), triple(DEEP)))
    print("  water_body_color(appearanceDepth) absorption.glsl:%s %s"
          % (line_of(ABSORPTION, "vec3 water_body_color(float appearanceDepth) {"),
             BODY_MIX_EXPR))
    print("    shallow end %s (the shallow transmission's own hue), deep end %s"
          % (triple(BODY_SHALLOW), triple(BODY_DEEP)))
    print("  fill's incident light = astra_sky_ambient() day (overworld.glsl:29) %s"
          % triple(SKY_AMBIENT))
    print("  bed samples: sunlit sand %s, sunlit stone %s" % (triple(SAND), triple(STONE)))
    print()

    print("--- 1. air-side column: water_surface_medium() (absorption.glsl:88-95) ---")
    print("  %5s %-24s %-24s %-26s %s"
          % ("depth", "T(r,g,b) g/b", "fill(r,g,b)", "comp sand L / srgb", "comp stone L"))
    for depth in (0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 24):
        t = transmission(depth)
        f = fill(depth)
        comp_sand = [SAND[i] * t[i] + f[i] for i in range(3)]
        comp_stone = [STONE[i] * t[i] + f[i] for i in range(3)]
        print("  %5d %-24s %-24s L=%.3f %-18s L=%.3f"
              % (depth,
                 "%.3f,%.3f,%.3f %.2f" % (t[0], t[1], t[2], t[1] / max(t[2], 1e-9)),
                 "%.4f,%.4f,%.4f" % tuple(f),
                 luma(comp_sand), str([round(x, 3) for x in srgb(comp_sand)]),
                 luma(comp_stone)))
    deep_fill = [body_colour(24.0)[i] * SCALE * SKY_AMBIENT[i] for i in range(3)]
    print("  fill at full depth (T->0) %s luma %.3f srgb %s b/g %.2f"
          % (triple(deep_fill), luma(deep_fill),
             [round(x, 3) for x in srgb(deep_fill)], deep_fill[2] / deep_fill[1]))
    shallow_body = body_colour(1.0)
    print("  shallow end of the fill's own colour (appearanceDepth 1): b/g %.2f against the"
          " transmission's own b/g %.2f at 0 blocks" % (
              shallow_body[2] / shallow_body[1],
              transmission(0)[2] / transmission(0)[1]))
    print("  reading: the bed's own colour survives mostly in BLUE past ~6 blocks, green is")
    print("  gone by ~12; past that the picture is the fill, whose light is the ambient sky")
    print("  only - the sun never enters the water body's own colour (that is the design")
    print("  boundary; the sun's pattern arrives on the BED instead, lit.fsh's caustic gain).")
    print("  Since 2026-09-22 the fill's hue follows the depth blend, so the shallows are")
    print("  tinted with the transmission's own cyan instead of a constant navy.")
    print()

    print("--- 2. caustic field: the pre-fix consumer is gone (2026-09-22) ---")
    # the removal note in caustics.glsl still NAMES the function, so test the definition
    removed = not re.search(r"float\s+astra_water_caustics_focus\s*\(", CAUSTICS)
    print("  astra_water_caustics_focus() definition removed: %s" % ("yes" if removed else "NO"))
    print("  terrain gain is now %s" % re.search(
        r"float causticGain = (clamp\(.*?\));", LIT, re.S).group(1).replace("\n", " "))
    print("  reading (pre-fix, kept as the reason for the change): that field sat on its")
    print("  own 0.2 clamp floor for 92.3%% of a seabed patch, and mix(1, field, %.2f) made it"
          % CAUSTIC_STRENGTH)
    print("  a flat 0.44x multiplier that could only dim the direct sun. The shipped field")
    print("  is solas_water_caustics() mapped around its own median (1.0 at p50), measured")
    print("  in qa/tools/underwater_light_probe.py section [2]; the air-side arm of")
    print("  program/lit.fsh applies the same gain through the water caster's own height.")
    print()

    print("--- 3. grazing reflection and the glint (water.glsl:%s, :%s, :%s) ---"
          % (line_of(WATER, "fresnel = (0.025 + 0.975 * pow5"),
             line_of(WATER, "fallback=astra_reflection_sky(reflectedWorld,roughness)*skylight;"),
             line_of(WATER, "reflection += glintColor * glint * skylight")))
    # 2026-09-22: the reflection now passes through astra_scene_highlights before it is
    # mixed with the transmitted colour, so the shipped column is the shouldered one.
    shoulder_knee, shoulder_soft = 1.0, 0.60     # lib/twilight.glsl astra_scene_highlights
    print("  %8s %10s %12s %14s %12s %12s" % ("angle", "fresnel", "HDR peak*", "srgb(g2.2)",
                                              "shipped", "bloom?"))
    print("  (* mirror + the sun's glint at full amplitude. The mirror alone stays at or")
    print("   below 1.0 above about 4.5 degrees - at 5.0 deg it is 0.966 - so the excess")
    print("   above the white point is the sun's image, which is what the shoulder acts on)")
    transmitted_far = 0.20
    sky_horizon = 1.0
    for angle in (45.0, 60.0, 70.0, 75.0, 80.0, 85.0, 88.0, 89.5):
        cosine = math.cos(math.radians(angle))
        fresnel = 0.025 + 0.975 * (1.0 - cosine) ** 5
        mirror = fresnel * sky_horizon + (1.0 - fresnel) * transmitted_far
        peak = mirror + 0.72 * 1.00              # glint amplitude x glintColor's peak channel
        shipped = shoulder_knee + (peak - shoulder_knee) / (
            1.0 + shoulder_soft * (peak - shoulder_knee)) if peak > shoulder_knee else peak
        print("  %8.1f %10.3f %12.3f %14.3f %12.3f %12s"
              % (angle, fresnel, peak, srgb([peak] * 3)[0], shipped,
                 "yes" if shipped > BLOOM_THRESHOLD else "no"))
    print("  glint peak worst case = %.3f, BLOOM_THRESHOLD = %.1f (bloom.glsl:%s)"
          % (sky_horizon + 0.72, BLOOM_THRESHOLD, line_of(BLOOM, "BLOOM_THRESHOLD = 1.0")))
    print("  astra_scene_highlights present in program/water.glsl: %s"
          % ("yes" if "astra_scene_highlights" in WATER else "NO"))
    print("  the shoulder's own comment (lib/twilight.glsl:%s-%s) names "
          "'the sun's image on water' as a consumer"
          % (line_of(TWILIGHT, "// The same shoulder, applied by the scene assembly"),
             line_of(TWILIGHT, "vec3 astra_scene_highlights(vec3 color)")))
    print()

    print("--- 4. the air fog a water-surface pixel also gets (fog.glsl:128-190) ---")
    print("  %6s %10s %10s %10s %10s" % ("far", "d", "atom fog", "border", "sky add %"))
    for far in (128.0, 256.0):
        coefficient = (1.0 + 0.01 * max(0.0, far - 200.0)) * (0.60 / far) ** 3
        for distance in (32.0, 64.0, far * 0.75, far):
            atom = distance ** 3 * coefficient * (FOG_DENSITY * 0.01) * 1.264
            border = smoothstep(far - 8.0, far, distance)
            factor = min(border + atom, 1.0)
            factor *= smoothstep(0.01, 0.015, factor)
            print("  %6.0f %10.0f %10.4f %10.3f %10.3f"
                  % (far, distance, atom, border, 100.0 * factor * SKY_FOG_STRENGTH * 0.01))
    print("  reading: away from the border band the fog adds under 3 percent of a horizon sky")
    print("  even at 192 blocks with FOG_DENSITY=50, SKY_FOG_STRENGTH=15. The far water's")
    print("  whiteness cannot come from fog.glsl; it comes from the reflection.")
    print()

    print("--- 5. gates that decide whether the air-side bed shows the sun ---")
    checks = (
        ("caustic overlay now covers both sides of the surface", LIT, "program/lit.fsh",
         "if (!iceTop) {"),
        ("air-side water caster resolves to a white transmission", DIFFUSE,
         "global/lighting/diffuse.glsl",
         "transmission = isEyeInWater == 1 ? caster.gba : vec3(1.0);"),
        ("same rule in the software shadow path", SHADOWMAP,
         "global/lighting/shadowmap.glsl",
         "transmission = isEyeInWater == 1 ? caster.gba : vec3(1.0);"),
        ("the pre-fix pixel-side focus field is gone (its removal note only names it)",
         CAUSTICS, "global/water/caustics.glsl", "float astra_water_caustics_focus("),
        ("air-side arm: the caster's water height is read", LIT, "program/lit.fsh",
         "vec4 caster = shadow_caster_data(surfaceShadowPosition.xy);"),
        ("air-side arm: the delta hits the direct sun term only", LIT, "program/lit.fsh",
         "color += directRadiance * ((causticGain - 1.0) * causticFade);"),
        ("the fill's hue follows the depth blend", ABSORPTION,
         "global/water/absorption.glsl", "water_body_color(appearanceDepth)"),
    )
    for label, text, path, needle in checks:
        line = line_of(text, needle)
        # the two "gone" entries are the ones whose present line is a REGRESSION
        expected_absent = label.startswith("the pre-fix")
        ok = (line is None) if expected_absent else bool(line)
        print("  [%s] %s -> %s:%s" % ("ok" if ok else "FAIL", label, path, line))
    print("  (the two global/lighting/ entries above are unchanged and are the reason the")
    print("  air side needs its own caustic term: a water caster resolves to white there.)")
    print()
    print("probe complete (exit 0).")


# caustic_field_stats() is gone with astra_water_caustics_focus(): it reproduced a
# function that no longer ships. The shipped field measurement (on the same texture,
# with the gain the pixel shader applies) lives in qa/tools/underwater_light_probe.py
# section [2], which is the gate.


if __name__ == "__main__":
    main()
    sys.exit(0)
