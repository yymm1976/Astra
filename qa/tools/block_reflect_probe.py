#!/usr/bin/env python3
"""Retired entry point for the per-face rock-emission probe.

The former probe compiled its own fragment against astra_rock_emission() and the
four rock emission classes (materials 12..15). That function and those classes
were later removed from the pack - astra_rock_emission has zero references and
block.properties no longer declares a material >= 12 emission branch - so the
embedded fragment cannot link and it no longer describes any current material
response. Keep a clear failure for historical command references.

The only emission helper the current pack ships is astra_end_stone_emission() in
lib/surface_emission.glsl, gated to End stone (material 11); rock response lives
in lib/rock_material.glsl. A probe for it would be a new measurement, not a
repair of this fragment.
"""
import sys


def main() -> int:
    print("block_reflect_probe.py is retired: astra_rock_emission() and the four rock "
          "emission classes are gone from the current pack, so its embedded fragment no "
          "longer links. Current material response is implemented in "
          "lib/rock_material.glsl and lib/surface_emission.glsl (End stone, material 11).",
          file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
