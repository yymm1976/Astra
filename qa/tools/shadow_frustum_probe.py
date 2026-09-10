#!/usr/bin/env python3
"""Shadow frustum numeric probe (SC-35 shadow P2 diagnosis).

Reproduces the receiver-side math of Astra/lib/distort.glsl and
global/lighting/shadowmap.glsl for a *ground-plane* receiver walking out
along a shadow-NDC axis, and prints the world-space texel footprint, the
PCF blur width, the adaptive bias and the map fade at each distance.

Why: the "tree shadows keep changing while the player moves, fine inside
~a dozen blocks, murky/unloaded outside" report is suspected to be the
distort grid (25.6-block high-res core) plus interval snap plus a PCF that
is 4 texels wide where texels grow to 0.6+ blocks. This script quantifies
those terms before/after the planned change so the fix can be verified
numerically (visual verification remains the user's in-game pass).

Usage:  python qa/tools/shadow_frustum_probe.py [--distance 256] [--resolution 2048]
        [--softness 2] [--bias-clamp 0.35] [--interval 0.5]
"""

import argparse
import math


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--distance", type=float, default=128.0, help="shadowDistance (blocks)")
    ap.add_argument("--resolution", type=int, default=2048, help="shadowMapResolution")
    ap.add_argument("--softness", type=float, default=4.0, help="SHADOW_SOFTNESS (texels)")
    ap.add_argument("--bias-clamp", type=float, default=0.12, help="bias clamp upper bound (blocks)")
    ap.add_argument("--interval", type=float, default=2.0, help="shadowIntervalSize (blocks)")
    ap.add_argument("--distort-core", type=float, default=25.6, help="distort high-res core radius (blocks)")
    args = ap.parse_args()

    d = args.distance
    res = args.resolution
    soft = args.softness
    clamp_hi = args.bias_clamp
    interval = args.interval
    core = args.distort_core

    # distort.glsl: shadow_map_bias = 1 - core / shadowDistance
    bias = 1.0 - core / d
    fade_in = d - 16.0
    fade_out = d - 4.0

    print(f"shadowDistance={d:g}  resolution={res}  softness={soft:g}  biasClamp={clamp_hi:g}")
    print(f"distort: core={core:g} blocks, shadow_map_bias={bias:.4f}")
    print(f"interval snap = {interval:g} blocks  fade band = [{fade_in:g}..{fade_out:g}]\n")
    print(f"{'dist':>6} {'factor':>7} {'texelWorld':>11} {'PCF width':>10} "
          f"{'bias@ndotl=1':>11} {'fade':>6}")
    for r in [2, 5, 12, 19, 25.6, 32, 48, 64, 96, 112, 120, 128, 160, 192, 224, 256]:
        if r > d:
            continue
        ndc = r / d  # box-NDC along a principal axis; the shadow box spans +-distance
        factor = ndc * bias + (1.0 - bias)
        stretch = (factor * factor) / max(1.0 - bias, 0.05)
        texel = (2.0 * d / res) * stretch
        pcf = texel * soft
        # shadowmap.glsl: bias = clamp(texel * (0.30 + 0.45*(1-ndotl)), 0.008, clamp_hi)
        bias_val = max(0.008, min(texel * 0.30, clamp_hi))
        fade = 1.0
        if r > fade_in:
            fade = 1.0 - min(1.0, max(0.0, (r - fade_in) / (fade_out - fade_in)))
        if r <= fade_out:
            fade = 1.0 - max(0.0, min(1.0, (r - fade_in) / (fade_out - fade_in)))
        snap = texel  # one texel jump per interval cell
        print(f"{r:6g} {factor:7.3f} {texel:11.5f} {pcf:10.3f} {bias_val:11.4f} {fade:6.3f}")
        if r in (2, 5, 12, 19, 25.6, 32, 48, 64, 96, 112, 120, 128):
            snap_mult = interval / texel if texel > 0 else 0
            print(f"       -> interval snap: {texel:.4f} blocks/texel, {snap_mult:.1f} texels per {interval:g} block cell"
                  + ("  (visible: edge crawls)" if texel > 0.15 else ""))


if __name__ == "__main__":
    main()
