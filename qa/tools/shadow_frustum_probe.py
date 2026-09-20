#!/usr/bin/env python3
"""Shadow frustum numeric probe - reproduces lib/distort.glsl receiver math.

Model (the factor is read from the shader source, never hardcoded here):

    distort:      q = p / (|p| + a)            a = SHADOW_DISTORT_FACTOR
    p (NDC)       r (blocks) / D               D = SHADOW_DISTANCE
    => in block units the warp is  rho = r / (r + k)  with  k = a * D
    texels/block  (R / 2) * d(rho)/dr = (R / 2) * k / (r + k) ** 2
    blocks/texel  2 * (r + k) ** 2 / (R * k)
    center        2 * k / R

History: this file modelled the pre-2026-09-09 Mellow square distortion as a
lerp (`factor = ndc * bias + (1 - bias)`). The Steadfast radial projection
replaced that formula, so every number the old model printed came from a
mapping the pack no longer uses. The formulas above are the current ones.

Limit kept on purpose: D is taken as SHADOW_DISTANCE. Iris fits its shadow
ortho to the truncated view frustum, so the real half-extent varies a little
with FOV and sun angle; this probe measures the pack's own control law, not
Iris's matrix.

Usage:
    python qa/tools/shadow_frustum_probe.py                    # source defaults
    python qa/tools/shadow_frustum_probe.py --ladder           # the three profiles
    python qa/tools/shadow_frustum_probe.py --distance 256 --resolution 4096
    python qa/tools/shadow_frustum_probe.py --factor 0.20      # force a constant
    python qa/tools/shadow_frustum_probe.py --all-distances    # one row per option value
"""

import argparse
import os
import re

from functools import partial

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DISTORT = os.path.join(ROOT, "Astra", "shaders", "lib", "distort.glsl")
SETTINGS = os.path.join(ROOT, "Astra", "shaders", "lib", "settings.glsl")
PROPERTIES = os.path.join(ROOT, "Astra", "shaders", "shaders.properties")

# The old probe flagged an edge that visibly crawls above this world footprint
# per texel; kept so the before/after tables stay comparable.
CRAWL_BLOCKS = 0.15

FACTOR_CONST = re.compile(
    r"^\s*const\s+float\s+SHADOW_DISTORT_FACTOR\s*=\s*([0-9.]+)\s*;", re.M)
FACTOR_SCALED = re.compile(
    r"^\s*const\s+float\s+SHADOW_DISTORT_FACTOR\s*=\s*(\w+)\s*/\s*"
    r"float\(\s*SHADOW_DISTANCE\s*\)\s*;", re.M)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def define(name, text):
    m = re.search(r"^#define\s+%s\s+(\S+)" % re.escape(name), text, re.M)
    return float(m.group(1)) if m else None


def macro_options(name, text):
    """The bracketed value list Iris shows for an option, e.g. '// [64 80 ...]'."""
    m = re.search(r"^#define\s+%s\s+\S+\s*//\s*\[([^\]]+)\]" % re.escape(name), text, re.M)
    return [float(v) for v in m.group(1).split()] if m else []


def distort_factor(source, distance):
    """(SHADOW_DISTORT_FACTOR, where it came from) for this SHADOW_DISTANCE.

    Only the two shapes the file actually uses are accepted. Anything else raises,
    so the probe cannot quietly keep measuring a formula the pack has replaced.
    """
    scaled = FACTOR_SCALED.search(source)
    if scaled:
        name = scaled.group(1)
        core = re.search(r"const\s+float\s+%s\s*=\s*([0-9.]+)\s*;" % re.escape(name), source)
        if not core:
            raise ValueError("distort.glsl scales the factor by %s, which is not a literal" % name)
        return float(core.group(1)) / distance, "%s=%s / SHADOW_DISTANCE=%g" % (
            name, core.group(1), distance)
    const = FACTOR_CONST.search(source)
    if const:
        return float(const.group(1)), "constant %s" % const.group(1)
    raise ValueError("SHADOW_DISTORT_FACTOR is neither a literal nor CORE / "
                     "float(SHADOW_DISTANCE); update this probe to read it")


def bias_blocks(distance, factor, radius, ndotl):
    """shadowmap.glsl shadow_map_position(), non-End branch, in blocks."""
    raw = radius / distance                      # player_shadow() NDC radius
    return 1.5 * raw + factor * (1.0 - max(ndotl, 0.0))


def table_rows(distance, resolution, softness, factor, radii):
    core = factor * distance                     # warp scale, in blocks
    rows = []
    for r in radii:
        if r > distance:
            continue
        world = 2.0 * (r + core) ** 2 / (resolution * core)
        rows.append((r, world, world * softness, bias_blocks(distance, factor, r, 1.0)))
    return core, rows


def report(title, distance, resolution, softness, factor, radii):
    core, rows = table_rows(distance, resolution, softness, factor, radii)
    edge = 1.0 / (1.0 + factor)                  # distorted radius of the receiver edge
    waste = 100.0 * (1.0 - edge * edge)
    # Solve 2 * (r + core) ** 2 / (resolution * core) == CRAWL_BLOCKS for r: the
    # sampled grid below only brackets this, it does not find it.
    crawl = (CRAWL_BLOCKS * resolution * core / 2.0) ** 0.5 - core
    print(f"\n== {title}: SHADOW_DISTANCE={distance:g} SHADOW_RESOLUTION={resolution:g} "
          f"SHADOW_SOFTNESS={softness:g}")
    print(f"   factor={factor:.4f}  core={core:.1f} blocks  center={2.0 * core / resolution:.4f} "
          f"blocks/texel")
    print(f"   receiver edge lands at rho={edge:.3f}, so {waste:.1f}% of the map area sits "
          f"outside it")
    print(f"   crawl threshold ({CRAWL_BLOCKS} blocks/texel) crossed at "
          + (f"{crawl:.1f} blocks" if crawl <= distance else f"never within range ({crawl:.1f})"))
    print(f"   {'r(blocks)':>10} {'blocks/texel':>13} {'PCF(blocks)':>12} {'bias@ndotl=1':>13}")
    for r, world, pcf, bias in rows:
        flag = "  <- edge crawls" if world > CRAWL_BLOCKS else ""
        print(f"   {r:10g} {world:13.4f} {pcf:12.3f} {bias:13.4f}{flag}")
    return core


def profiles():
    """(name, SHADOW_DISTANCE, SHADOW_RESOLUTION) for the three shipped tiers."""
    text = read(PROPERTIES)
    out = []
    for name in ("PERFORMANCE", "BALANCED", "ULTRA"):
        tokens = re.search(r"^profile\.%s=(.*)$" % name, text, re.M).group(1).split()
        dist = float(next(t for t in tokens if t.startswith("SHADOW_DISTANCE=")).split("=")[1])
        res = float(next(t for t in tokens if t.startswith("SHADOW_RESOLUTION=")).split("=")[1])
        out.append((name, dist, res))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--distance", type=float, help="override SHADOW_DISTANCE (blocks)")
    ap.add_argument("--resolution", type=int, help="override SHADOW_RESOLUTION")
    ap.add_argument("--softness", type=float, help="override SHADOW_SOFTNESS (texels)")
    ap.add_argument("--factor", type=float,
                    help="force a constant SHADOW_DISTORT_FACTOR instead of reading the source")
    ap.add_argument("--ladder", action="store_true", help="report the three shipped profiles")
    ap.add_argument("--all-distances", action="store_true",
                    help="one report per advertised SHADOW_DISTANCE value")
    args = ap.parse_args()

    settings = read(SETTINGS)
    source = read(DISTORT)
    distance = args.distance or define("SHADOW_DISTANCE", settings)
    resolution = args.resolution or int(define("SHADOW_RESOLUTION", settings))
    softness = args.softness or define("SHADOW_SOFTNESS", settings)
    radii = [2, 5, 8, 12, 16, 24, 32, 48, 64, 96, 128, 160, 192, 224, 256]

    if args.factor is not None:
        print(f"forcing SHADOW_DISTORT_FACTOR={args.factor:g} "
              f"(constant - ignores SHADOW_DISTANCE, the pre-P1-9 shape)")

        def resolve(dist):
            return args.factor, "forced constant"
    else:
        print(f"SHADOW_DISTORT_FACTOR as read from lib/distort.glsl: "
              f"{distort_factor(source, distance)[1]}")
        resolve = partial(distort_factor, source)

    def show(title, dist, res):
        factor, how = resolve(dist)
        print(f"   factor = {how}")
        return report(title, dist, res, softness, factor, radii)

    if args.ladder:
        for name, dist, res in profiles():
            show(name, dist, res)
    elif args.all_distances:
        for dist in macro_options("SHADOW_DISTANCE", settings):
            show(f"SHADOW_DISTANCE={dist:g}", dist, resolution)
    else:
        show("source defaults", distance, resolution)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
