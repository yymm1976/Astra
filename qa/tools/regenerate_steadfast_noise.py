#!/usr/bin/env python3
"""Regenerate steadfast-water-noise.png with documented provenance.

The legacy texture (14561 B, sha256 b9502f10ec238b90...) has an unreproducible
pixel origin: the Steadfast 0.8.0 distribution contains no image files at all
and the pixels match no testable generator (see THIRD-PARTY.md and
qa/review-2026-09-21-* logs). User ruling 2026-09-21: regenerate.

New texture spec (same as old): 64x64 RGBA8, alpha = 255 on every pixel,
linear repeat. Pixels come from an in-file splitmix64 stream (no stdlib RNG,
no version drift), three draws per pixel, low byte per channel, SEED = 20260921.
PNG is written with Pillow defaults (compress_level=6), like the old encoder.
"""
from pathlib import Path
import hashlib

W = H = 64
SEED = 20260921
MASK64 = (1 << 64) - 1
TARGET = Path(__file__).resolve().parents[2] / "Astra" / "shaders" / "textures" / "steadfast-water-noise.png"


def splitmix64(state):
    state = (state + 0x9E3779B97F4A7C15) & MASK64
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
    return state, (z ^ (z >> 31)) & MASK64


def main():
    if TARGET.exists():
        old = TARGET.read_bytes()
        print("old_size=%d" % len(old))
        print("old_sha256=%s" % hashlib.sha256(old).hexdigest())
    state = SEED
    px = bytearray()
    for _ in range(W * H):
        state, r = splitmix64(state)
        state, g = splitmix64(state)
        state, b = splitmix64(state)
        px += bytes((r & 0xFF, g & 0xFF, b & 0xFF, 255))
    from PIL import Image
    img = Image.frombytes("RGBA", (W, H), bytes(px))
    img.save(TARGET, format="PNG")
    data = TARGET.read_bytes()
    check = Image.open(TARGET)
    alphas = set(check.getchannel("A").getdata())
    print("new_size=%d" % len(data))
    print("new_sha256=%s" % hashlib.sha256(data).hexdigest())
    print("verify_mode=%s verify_size=%s alpha_min=%d alpha_max=%d"
          % (check.mode, check.size, min(alphas), max(alphas)))


if __name__ == "__main__":
    main()
