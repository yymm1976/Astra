#!/usr/bin/env python3
"""Retired entry point for the air-side water probe.

The former probe recomputed the air-side water column from source anchors that no
longer exist: water_body_color() now takes a vec2 depth blend, and the
astra_water_caustics_focus() field and its caustic constant were removed. It cannot
describe the current medium, so keep a clear failure for historical command
references.
"""
import sys


def main() -> int:
    print("airside_water_probe.py is retired: its old source anchors, "
          "water_body_color()'s scalar float depth argument became a vec2 depth blend, and "
          "the old caustic field was removed. Current rendering is implemented in "
          "global/water/absorption.glsl, "
          "global/water/caustics.glsl and program/water.glsl.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
