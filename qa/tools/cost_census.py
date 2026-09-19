#!/usr/bin/env python3
"""Loop source inventory, not an execution-cost or GPU-safety estimator.

No preprocessing, call-graph expansion or branch probabilities are available.
Never label lexical fetch sites as fetches/pixel, nor guess symbolic bounds.
"""
from pathlib import Path
import re

SHADERS = Path(__file__).resolve().parents[2] / "Astra" / "shaders"
COMMENTS = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
LOOP = re.compile(r"\b(for|while)\s*\(")
FETCH = re.compile(r"\b(?:texture\w*|texelFetch\w*)\s*\(")

def closing(text, start, left, right):
    depth = 0
    for pos in range(start, len(text)):
        if text[pos] == left:
            depth += 1
        elif text[pos] == right:
            depth -= 1
            if depth == 0:
                return pos
    return len(text) - 1

def main():
    print("Source inventory: configurations may include inactive code.")
    print("Fetch sites are lexical, NOT fetches/pixel; nested bodies overlap.")
    print("Calls are listed, not expanded. Symbolic bounds remain symbolic.\n")
    for path in sorted(SHADERS.rglob("*")):
        if path.suffix not in {".glsl", ".fsh", ".vsh", ".csh"}:
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        source = COMMENTS.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), source)
        for match in LOOP.finditer(source):
            begin = source.index("(", match.start())
            end = closing(source, begin, "(", ")")
            start = end + 1
            while start < len(source) and source[start].isspace():
                start += 1
            if start >= len(source):
                continue
            stop = (closing(source, start, "{", "}") + 1
                    if source[start] == "{" else source.find(";", start) + 1)
            body = source[start:stop]
            calls = sorted(set(CALL.findall(body)) - {"if", "for", "while", "switch"})
            line = source.count("\n", 0, match.start()) + 1
            header = " ".join(source[begin+1:end].split())
            print(f"{path.relative_to(SHADERS)}:{line}: ({header})")
            print(f"  fetch sites: {len(FETCH.findall(body))}; calls: {', '.join(calls)}")
    print("\nManual workload context, not a runtime bound:")
    print("End lens: 48 steps, at most 96 candidate-segment calls plus entry/escape.")
    print("Each segment also traverses candidates/body geometry; 96 is NOT total work.")
    print("Empty bounds and early exits reduce actual work; no branch probability assumed.")
    print("End illumination: only slot 0 runs 256 disc samples, not all 294 slots.")
    print("Puddle SSR: up to 96 steps on tagged puddle pixels.")
    print("End sky geometry: 0.75 x 0.75 buffer; stars at full size.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
