#!/usr/bin/env python3
"""Retired entry point for the bloom mip-level probe.

The former probe compiled its own embedded fragment against getBloomTile(). That
function was removed from the current bloom implementation, which captures through
bloom_capture()/computeBloom(), so the probe's old fragment no longer links. Keep a
clear failure for historical command references.
"""
import sys


def main() -> int:
    print("bloom_lod_probe.py is retired: getBloomTile() is gone from the current bloom "
          "implementation, so the probe's own embedded fragment that calls it no longer "
          "compiles. Current rendering is implemented in global/post/bloom.glsl and "
          "global/water/bloom_capture.glsl.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
