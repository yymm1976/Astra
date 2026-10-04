#!/usr/bin/env python3
"""Retired entry point for helpers removed from the current water implementation.

The former synthetic scene called water_light_field helpers and an obsolete
absorption signature. It cannot describe the current volumetric shafts, wave
lens or water medium. Keep a clear failure for historical command references.
"""
import sys


def main() -> int:
    print("underwater_light_probe.py is retired: its water helpers were removed. "
          "Current rendering is implemented in global/water/light_shafts.glsl, "
          "lib/water_wave_lens.glsl and global/water/absorption.glsl.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
