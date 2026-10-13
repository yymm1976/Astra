#!/usr/bin/env python3
"""Retired entry point for the shafts-only variant of the underwater light probe.

This entry was the ``shafts_only=True`` flag of underwater_light_probe.py. That
shared implementation is itself retired: its synthetic scene called
water_light_field helpers and an obsolete absorption signature, so it cannot
describe the current volumetric shafts, wave lens or water medium. Keep a clear
failure for historical command references instead of the TypeError an obsolete
keyword argument would now raise.
"""
import sys


def main() -> int:
    print("underwater_shaft_gate_probe.py is retired: it was the shafts-only flag of "
          "underwater_light_probe.py, whose water helpers were removed. Current rendering "
          "is implemented in global/water/light_shafts.glsl, lib/water_wave_lens.glsl and "
          "global/water/absorption.glsl.", file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
