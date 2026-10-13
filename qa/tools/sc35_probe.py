#!/usr/bin/env python3
"""Retired entry point for the SC-35 coordinate/artifact probe.

The former probe fed textures/noise.png into an embedded fragment program. That
texture, its sampler and the noisetex path were removed from the current shaders, so
the probe cannot complete its input reads or describe the current held-light,
wave-field and shoreline paths. Keep a clear failure for historical command
references.
"""
import sys


def main() -> int:
    print("sc35_probe.py is retired: its embedded fragment required textures/noise.png, "
          "which the current shaders no longer ship. Current rendering is implemented in "
          "global/lighting/blocklight.glsl, program/water.glsl and "
          "global/water/caustics.glsl.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
