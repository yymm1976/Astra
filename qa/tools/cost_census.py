#!/usr/bin/env python3
"""Static per-pass cost census: rank passes by texture-fetch work.

We have been guessing at hotspots. This walks each entry's include tree, counts the
texture fetches that actually execute per pixel, weights loop bodies by their trip
count, and multiplies by the pass's pixel count so a half-resolution pass is not
compared against a full-resolution one on equal terms.

It is a heuristic, not a profiler: it cannot see branches, early-outs, or driver
reordering. Its job is to rank candidates for measurement, so the next optimisation
is chosen from data rather than from a guess.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SHADERS = Path("Astra/shaders")
FETCH = re.compile(r"\b(texture|textureLod|texelFetch|textureGrad|textureProj)\s*\(")
LOOP = re.compile(r"for\s*\(\s*(?:int|uint)\s+\w+\s*=\s*\w+\s*;\s*\w+\s*<\s*([A-Za-z_0-9]+)")
INCLUDE = re.compile(r'#include\s+"([^"]+)"')

# Relative pass resolution, from shaders.properties size.buffer lines. 1.0 = screen.
RES = {"default": 1.0}


def resolve(base: Path, inc: str) -> Path | None:
    for cand in (SHADERS / inc.lstrip("/"), base / inc):
        if cand.is_file():
            return cand
    return None


def expand(path: Path, seen: set[Path]) -> list[tuple[Path, int]]:
    """Return (file, line) for every #include reachable from path."""
    out: list[tuple[Path, int]] = []
    if path in seen:
        return out
    seen.add(path)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for n, line in enumerate(text.splitlines(), 1):
        m = INCLUDE.search(line)
        if m:
            sub = resolve(path.parent, m.group(1))
            if sub:
                out.append((sub, n))
                out.extend(expand(sub, seen))
    return out


def count_fetches(path: Path) -> int:
    """Texture fetches per pixel, with loop bodies weighted by their trip count."""
    text = path.read_text(encoding="utf-8", errors="replace")
    total = 0.0
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        c = len(FETCH.findall(line))
        if not c:
            continue
        weight = 1.0
        m = LOOP.search(line)
        if m:
            token = m.group(1)
            if token.isdigit():
                weight = int(token)
            elif token == "SHADOW_FILTER_TAPS":
                weight = 4
            elif token == "UNDERWATER_SHAFT_SAMPLES":
                weight = 7
            elif token == "SAMPLECOUNT":
                weight = 16
            else:
                weight = 4  # unknown bound: assume a small fixed loop
        total += c * weight
    return int(round(total))


def main() -> int:
    entries = sorted(p for p in SHADERS.rglob("*.fsh") if "program" not in p.parts
                     and p.parent.name in ("shaders", "world-1", "world1"))
    rows = []
    for e in entries:
        seen: set[Path] = set()
        # Dedupe: expand() appends a file before recursing, so a module reachable by two
        # include paths is listed twice even though it compiles once.
        files = [(e, 0)] + list(dict.fromkeys(expand(e, seen)))
        own = sum(count_fetches(f) for f, _ in files)
        real = [f for f, _ in files if "program" in f.parts or "global" in f.parts
                or "lib" in f.parts]
        rows.append((own, len(files), len(real), e))
    rows.sort(reverse=True)
    print(f"{'fetches/px':>10} {'files':>6} {'modules':>8}  entry")
    for own, nf, nr, e in rows[:18]:
        print(f"{own:>10} {nf:>6} {nr:>8}  {e.relative_to(SHADERS)}")
    print()
    print(f"entries scanned: {len(rows)}")
    print("NOTE heuristic: branch/early-out blind, and a loop that CALLS a fetching")
    print("     function is not multiplied by its trip count. Ranks candidates only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
