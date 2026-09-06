#!/usr/bin/env python
"""
Astra QA - Steadfast provenance classifier.

Mechanically re-derives what THIRD-PARTY.md claims about the CUSTOM UNIFORMS
section of shaders/shaders.properties: every Astra entry is classified against
every definition of the same name in the Steadfast 0.8.0 properties file
(Steadfast keeps several historical duplicates per name; last one wins).

    verbatim       expression identical after whitespace removal
    literal-suffix identical except an int/float literal suffix (2 vs 2.0)
    rewritten      same name, materially different expression
    astra-only     name does not exist in Steadfast

Usage:
    python qa/tools/provenance_steadfast.py            # print the report
    python qa/tools/provenance_steadfast.py --quiet    # counts only

check_pack.py #8 compares these counts with the ledger's declared counts.
"""
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASTRA = os.path.join(ROOT, "Astra", "shaders", "shaders.properties")
# reference library is read-only and excluded from git (see .gitignore)
STEADFAST = os.path.join(ROOT, "_analysis", "Steadfast-0.8.0", "shaders", "shaders.properties")

KEY = re.compile(r"^(uniform|variable)\.(\w+)\.(\w+)\s*=\s*(.*)$")
CLASSES = ("verbatim", "literal-suffix", "rewritten", "astra-only")


def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()


def parse(path):
    """name -> list of (kind, type, expression); continuation lines joined."""
    text = re.sub(r"\\\s*\n\s*", " ", read(path))
    defs = {}
    for raw in text.split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = KEY.match(line)
        if not m:
            continue
        kind, _ty, name, expr = m.groups()
        defs.setdefault(name, []).append((kind, _ty, expr.split("#")[0].strip()))
    return defs


def squash(s):
    return re.sub(r"\s+", "", s)


def strip_literal_suffix(s):
    """1.0 -> 1 in the trailing exponent argument of pow(...) only, which is the
    single difference between several Steadfast lines and their Astra copies."""
    return re.sub(r",\s*(\d+)\.0\s*\)", r",\1)", squash(s))


def classify():
    astra, stead = parse(ASTRA), parse(STEADFAST)
    out = {k: [] for k in CLASSES}
    for name, adefs in astra.items():
        aexprs = [e for _, _, e in adefs]
        if name not in stead:
            out["astra-only"].append(name)
            continue
        sexprs = [e for _, _, e in stead[name]]
        if any(squash(a) == squash(s) for a in aexprs for s in sexprs):
            out["verbatim"].append(name)
        elif any(strip_literal_suffix(a) == strip_literal_suffix(s)
                 for a in aexprs for s in sexprs):
            out["literal-suffix"].append(name)
        else:
            out["rewritten"].append(name)
    return out, astra, stead


def counts():
    out, _, _ = classify()
    return {k: len(out[k]) for k in CLASSES}


def main():
    quiet = "--quiet" in sys.argv
    out, astra, _ = classify()
    total = sum(len(v) for v in out.values())
    if quiet:
        print(" ".join(f"{k}={len(v)}" for k, v in out.items()), f"total={total}")
        return 0
    print(f"Astra CUSTOM UNIFORMS entries: {len(astra)} (classified: {total})")
    for k in CLASSES:
        print(f"\n== {k}: {len(out[k])}")
        for name in sorted(out[k]):
            expr = [e for _, _, e in astra[name]][0]
            print(f"   {name:<28} {expr[:100]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
