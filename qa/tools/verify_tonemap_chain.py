"""Chain-of-title verifier for lib/tonemap.glsl (survey P2-13, ticket T16).

THIRD-PARTY.md claims that Astra's tone operators reached the pack through Mellow v3.4 but are not
TheCMK's code: uchimura_*() and agx_*() are upstream glsl-tone-map (Damien Seguin, MIT), and
aces_tonemap() with its two matrices and rrt_and_odt_fit() is upstream BakingLab ACES.hlsl
(MJP, MIT, the fit credited there to Stephen Hill). This script re-measures both claims from the
files the pack itself ships, so they stay checkable after this session.

    python qa/tools/verify_tonemap_chain.py

Exit code 0 = every measured item matches the ledger. Comparison normalizes whitespace and line
comments only; identifiers are mapped through the alias tables (design.md 3.2 snake_case renames),
and the HLSL original is translated to GLSL by hlsl_to_glsl() - the mechanical part of the port.
Anything the ledger does not document as a deviation shows up as an UNEXPECTED DIFF and fails.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TONEMAP = ROOT / "Astra" / "shaders" / "lib" / "tonemap.glsl"
VENDOR = ROOT / "Astra" / "shaders" / "lib" / "vendor" / "glsl-tone-map"
BAKINGLAB = ROOT / "Astra" / "shaders" / "lib" / "vendor" / "bakinglab" / "ACES.hlsl.orig"
MELLOW = ROOT / "_analysis" / "Mellow Shader v3.4" / "shaders" / "lib" / "tonemap_operators.glsl"

UPSTREAM_UCHIMURA = VENDOR / "uchimura.glsl.orig"
UPSTREAM_AGX = VENDOR / "agx.glsl.orig"
# Siblings in the same package, vendored as the audit evidence for the ledger's negative claims.
UPSTREAM_ACES_HILL = VENDOR / "acesHill.glsl.orig"
UPSTREAM_ACES_NARKOWICZ = VENDOR / "aces.glsl.orig"
UPSTREAM_REINHARD = VENDOR / "reinhardJodie.glsl.orig"
ENCODING = ROOT / "Astra" / "shaders" / "lib" / "encoding.glsl"

# glsl-tone-map ports the same BakingLab fit (acesHill.glsl), so "which file was copied" has to be
# answered from the comments the two siblings do NOT share. code_only() strips comments, hence the
# separate presence check on the raw sources.
BAKING_ONLY_COMMENTS = ["Apply RRT and ODT", "Clamp to [0, 1]"]
HILL_ONLY_COMMENTS = ["have been transposed", "luminance-only curve"]
# The operators the ledger says were never ported. Numeric constants alone prove nothing here -
# the Rec.709 triple is also in agx.glsl's EOTF and 0.14/0.59 appear in the AgX and ACES matrices,
# both of which ARE ported - so every marker below is a string unique to that one upstream file.
# main() asserts that uniqueness instead of assuming it.
UNPORTED_SETS = [
    ("Narkowicz ACES fit", UPSTREAM_ACES_NARKOWICZ, ["vec3 aces(vec3 x)", "const float a = 2.51;"]),
    ("Seguin Rec.709 reinhard", UPSTREAM_REINHARD, ["reinhardJodie", "dot(x, lw)"]),
]

SEGUIN = "glsl-tone-map"
BAKING = "bakinglab"

# Astra/Mellow name -> upstream name. Applied longest-first so uchimura_tonemap_full is not
# partially rewritten by the uchimura_tonemap rule.
ASTRA_ALIASES = [
    ("uchimura_tonemap_full", "uchimura"),
    ("uchimura_tonemap", "uchimura"),
    ("agx_cdl", "agxCdl"),
    ("agx_punchy", "agxPunchy"),
    ("agx_tonemap", "agx"),
    ("agx_inset_matrix", "AgXInsetMatrix"),
    ("agx_outset_matrix", "AgXOutsetMatrix"),
    ("agx_min_ev", "AgxMinEv"),
    ("agx_max_ev", "AgxMaxEv"),
    ("linear_srgb_to_linear_rec2020", "LINEAR_SRGB_TO_LINEAR_REC2020"),
    ("linear_rec2020_to_linear_srgb", "LINEAR_REC2020_TO_LINEAR_SRGB"),
]
MELLOW_ALIASES = [("Uchimura", "uchimura")]

# Astra name -> BakingLab name.
ACES_ALIASES = [
    ("aces_input_mat", "ACESInputMat"),
    ("aces_output_mat", "ACESOutputMat"),
    ("rrt_and_odt_fit", "RRTAndODTFit"),
    ("aces_tonemap", "ACESFitted"),
]

# (label, astra key, mellow key, upstream key) with normalized argument lists.
A7 = "vec3x,floatP,floata,floatm,floatl,floatc,floatb"
CDL = "vec3color,vec3slope,vec3offset,vec3power,floatsaturation"
FUNCTIONS = [
    ("uchimura(vec3,float x7)", ("uchimura_tonemap_full", A7), ("Uchimura", A7),
     ("uchimura", A7), SEGUIN),
    ("uchimura(vec3)", ("uchimura_tonemap", "vec3x"), ("Uchimura", "vec3x"),
     ("uchimura", "vec3x"), SEGUIN),
    ("agxCdl(...)", ("agx_cdl", CDL), ("agxCdl", CDL), ("agxCdl", CDL), SEGUIN),
    ("agxPunchy(vec3)", ("agx_punchy", "vec3color"), ("agxPunchy", "vec3color"),
     ("agxPunchy", "vec3color"), SEGUIN),
    ("agx(vec3)", ("agx_tonemap", "vec3color"), None, ("agx", "vec3color"), SEGUIN),
    ("RRTAndODTFit(vec3)", ("rrt_and_odt_fit", "vec3v"), ("RRTAndODTFit", "vec3v"),
     ("RRTAndODTFit", "vec3v"), BAKING),
    ("ACESFitted(vec3)", ("aces_tonemap", "vec3color"), ("ACES_slow", "vec3color"),
     ("ACESFitted", "vec3color"), BAKING),
]

# Exact registered edits only; every other body statement must match upstream.
ASTRA_DIFF = {
    "agxCdl(...)": [("insert", "", "max("), ("insert", "", ",vec3(0.0))")],
}
# Two zero-weight curve skips in Uchimura. Construct the expected body from
# upstream with these exact statement substitutions, rather than exempting it.
ASTRA_REPLACEMENTS = {
    "uchimura(vec3,float x7)": [
        ("vec3T=vec3(m*pow(x/m,vec3(c))+b);",
         "vec3T=vec3(0.0);if(any(greaterThan(w0,vec3(0.0))))T=vec3(m*pow(x/m,vec3(c))+b);"),
        ("vec3S=vec3(P-(P-S1)*exp(CP*(x-S0)));",
         "vec3S=vec3(0.0);if(any(greaterThan(w2,vec3(0.0))))S=vec3(P-(P-S1)*exp(CP*(x-S0)));"),
    ],
}
# The one Mellow-side deviation, recorded so the relay is not mistaken for Astra's own edit:
# Mellow's dispatcher wrapper gamma-corrects in and out of the upstream fit.
MELLOW_DIFF = {
    "ACESFitted(vec3)": [("insert", "", "color=pow(color,vec3(1/2.2));"),
                         ("insert", "", "to_linear("), ("insert", "", ")")],
}


def insert_diff(upstream, other):
    """Non-equal opcodes of upstream -> other as (tag, upstream fragment, other fragment)."""
    import difflib
    ops = difflib.SequenceMatcher(None, upstream, other, autojunk=False).get_opcodes()
    return [(t, upstream[i1:i2], other[j1:j2]) for t, i1, i2, j1, j2 in ops if t != "equal"]


def read(p):
    return io.open(str(p), encoding="utf-8").read()


def code_only(src):
    """Drop line comments and all whitespace - what "verbatim" has to mean across reindentation."""
    return re.sub(r"\s+", "", re.sub(r"//[^\n]*", "", src))


def hlsl_to_glsl(src):
    """The mechanical HLSL -> GLSL part of the port, nothing else."""
    src = src.replace("float3", "vec3").replace("static const", "const")
    src = re.sub(r"(?<=\d)f(?![\w.])", "", src)                      # 0.0245786f -> 0.0245786
    src = re.sub(r"mul\(\s*(\w+)\s*,\s*(\w+)\s*\)", r"\1 * \2", src)  # mul(M, v) -> M * v
    src = re.sub(r"saturate\(\s*(\w+)\s*\)", r"clamp(\1, 0, 1)", src)
    return src


def functions(src):
    out = {}
    for m in re.finditer(r"^(?:vec3|float)\s+(\w+)\s*\(([^)]*)\)\s*\{", src, flags=re.M):
        i = src.index("{", m.end() - 1)
        depth = 0
        for j in range(i, len(src)):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    break
        out[(m.group(1), re.sub(r"\s", "", m.group(2)))] = code_only(src[i:j + 1])
    return out


def apply_aliases(text, pairs):
    for a, b in pairs:
        text = text.replace(a, b)
    return text


def matrices(src):
    out = {}
    for m in re.finditer(r"const\s+mat3\s+(\w+)\s*=\s*mat3\((.*?)\);", src, flags=re.S):
        key = re.sub(r"[^A-Za-z0-9]", "", m.group(1)).lower()
        out[key] = tuple(re.findall(r"-?\d*\.?\d+(?:[eE][-+]?\d+)?", m.group(2)))
    for m in re.finditer(r"const\s+float\s+(\w+)\s*=\s*(-?[\d.]+);", src):
        out[re.sub(r"[^A-Za-z0-9]", "", m.group(1)).lower()] = m.group(2)
    return out


def hlsl_matrices(src):
    """float3x3 rows -> the arg order a GLSL mat3() needs to hold the same linear map."""
    out = {}
    for m in re.finditer(r"float3x3\s+(\w+)\s*=\s*\{(.*?)\};", src, flags=re.S):
        rows = [re.findall(r"-?\d*\.?\d+", r) for r in re.findall(r"\{([^{}]*)\}", m.group(2))]
        key = re.sub(r"[^A-Za-z0-9]", "", m.group(1)).lower()
        out[key] = tuple(v for col in zip(*rows) for v in col)
    return out


def check_diff(label, expected, ops, who, failures):
    if ops == expected:
        return f"{who} + {' + '.join(o[-1] for o in ops) if ops else 'no edits'}"
    failures.append(f"{label}: {who} diff is not what the ledger records: {ops}")
    return f"{who} UNEXPECTED DIFF {ops}"


def main():
    missing = [p for p in (TONEMAP, UPSTREAM_UCHIMURA, UPSTREAM_AGX, BAKINGLAB) if not p.exists()]
    if missing:
        print("FAIL  missing input files:")
        for p in missing:
            print("      ", p)
        print("      vendor originals must ship under Astra/shaders/lib/vendor/")
        return 1
    up = {SEGUIN: {}, BAKING: {}}
    up[SEGUIN].update(functions(read(UPSTREAM_UCHIMURA)))
    up[SEGUIN].update(functions(read(UPSTREAM_AGX)))
    up[BAKING].update(functions(hlsl_to_glsl(read(BAKINGLAB))))
    ast = functions(read(TONEMAP))
    mel = functions(read(MELLOW)) if MELLOW.exists() else {}

    failures = []
    for label, ka, km, ku, source in FUNCTIONS:
        u = up[source][ku]
        a = apply_aliases(ast[ka], ASTRA_ALIASES if source == SEGUIN else ACES_ALIASES)
        target = u
        replacements = ASTRA_REPLACEMENTS.get(label, [])
        for old, new in replacements:
            if target.count(old) != 1:
                failures.append(f"{label}: registered statement anchor no longer occurs exactly once: {old}")
                break
            target = target.replace(old, new, 1)
        expected = ASTRA_DIFF.get(label, [])
        if a == target:
            verdict = (f"registered exact substitutions: {len(replacements)}" if replacements
                       else "identical") if not expected else "IDENTICAL - ledger expected a diff"
            if expected:
                failures.append(label + ": documented Astra deviation is gone")
        else:
            verdict = check_diff(label, expected, insert_diff(target, a), "Astra", failures)
        mrow = ""
        if km and mel:
            m = apply_aliases(mel[km], MELLOW_ALIASES if source == SEGUIN else ACES_ALIASES)
            if m == u:
                mrow = " | mellow==upstream: True"
            else:
                ops = insert_diff(u, m)
                ok = ops == MELLOW_DIFF.get(label, [])
                mrow = f" | mellow: upstream + {' + '.join(o[-1] for o in ops)}"
                if not ok:
                    mrow = " | mellow UNEXPECTED DIFF " + str(ops)
                    failures.append(label + ": Mellow relay is not verbatim upstream")
        print(f"{label:24s} upstream={len(u):4d} astra={len(a):4d}  {verdict}{mrow}")

    um, am = matrices(read(UPSTREAM_AGX)), matrices(read(TONEMAP))
    mismatched = [k for k, v in um.items() if am.get(k) != v]
    print(f"agx constants: {len(um)} upstream values, "
          f"{'all reproduced' if not mismatched else 'MISMATCH ' + ', '.join(mismatched)}")
    if mismatched:
        failures.append("agx constants differ from upstream")

    raw_bl = read(BAKINGLAB)
    bl = hlsl_matrices(raw_bl)
    bad = [k for k, v in bl.items() if am.get(k) != v]
    print(f"ACES matrices: {len(bl)} upstream matrices x {len(bl[list(bl)[0]])} values, "
          f"{'all reproduced in column-major order' if not bad else 'MISMATCH ' + ', '.join(bad)}")
    if bad:
        failures.append("ACES matrices differ from BakingLab")
    if MELLOW.exists():
        bl_mel = matrices(read(MELLOW))
        bad = [k for k, v in bl.items() if bl_mel.get(k) != v]
        print(f"ACES matrices via Mellow: "
              f"{'relay unchanged' if not bad else 'MISMATCH ' + ', '.join(bad)}")
        if bad:
            failures.append("Mellow's ACES matrices differ from BakingLab")

    astra_src = read(TONEMAP)
    hill_src = read(UPSTREAM_ACES_HILL) if UPSTREAM_ACES_HILL.exists() else ""
    if hill_src:
        baking_ok = [c for c in BAKING_ONLY_COMMENTS if c in raw_bl and c not in hill_src]
        hill_ok = [c for c in HILL_ONLY_COMMENTS if c in hill_src and c not in raw_bl]
        print(f"discriminators valid: bakinglab {len(baking_ok)}/{len(BAKING_ONLY_COMMENTS)}, "
              f"acesHill {len(hill_ok)}/{len(HILL_ONLY_COMMENTS)}")
        if len(baking_ok) != len(BAKING_ONLY_COMMENTS) or len(hill_ok) != len(HILL_ONLY_COMMENTS):
            failures.append("the ACES sibling comment sets overlap - the check below is meaningless")
    present = [c for c in BAKING_ONLY_COMMENTS if c in astra_src]
    leaked = [c for c in HILL_ONLY_COMMENTS if c in astra_src]
    print(f"ACES source: BakingLab-only comments {len(present)}/{len(BAKING_ONLY_COMMENTS)} "
          f"present in lib/tonemap.glsl, acesHill-only {len(leaked)}/{len(HILL_ONLY_COMMENTS)} present")
    if len(present) != len(BAKING_ONLY_COMMENTS):
        failures.append("ACES block no longer carries the comments only ACES.hlsl has")
    if leaked:
        failures.append(f"ACES block now matches acesHill.glsl instead: {leaked}")

    if UPSTREAM_REINHARD.exists() and ENCODING.exists():
        up_vec = re.search(r"vec3\(\s*([\d.,\s]+)\)", read(UPSTREAM_REINHARD))
        up_lum = re.findall(r"\d+\.\d+", up_vec.group(1)) if up_vec else []
        ast_body = re.search(r"float get_luminance\(vec3 \w+\)\s*\{(.*?)\}",
                             read(ENCODING), flags=re.S)
        ast_lum = re.findall(r"\d+\.\d+", ast_body.group(1)) if ast_body else []
        same = bool(up_lum) and up_lum == ast_lum
        print(f"reinhard weights: upstream reinhardJodie={','.join(up_lum)} "
              f"astra get_luminance={','.join(ast_lum)} "
              f"{'SAME - not the registered TheCMK variant' if same else 'differ (TheCMK variant)'}")
        if same:
            failures.append("Astra's reinhard_jodie luminance now equals glsl-tone-map's")

    vendored = [(p, read(p)) for p in sorted(VENDOR.parent.rglob("*.orig"))]
    for label, path, consts in UNPORTED_SETS:
        if not path.exists():
            print(f"not ported: {label:24s} skipped - {path.name} absent")
            continue
        up_src = read(path)
        unidentified = [c for c in consts if c not in up_src]
        shared = [(c, p.name) for c in consts for p, s in vendored if p != path and c in s]
        hit = [c for c in consts if c in astra_src]
        print(f"not ported: {label:24s} markers {len(hit)}/{len(consts)} in lib/tonemap.glsl, "
              f"unique among {len(vendored)} vendored originals: {not shared}")
        if unidentified:
            failures.append(f"{label}: {unidentified} no longer identify {path.name}")
        if shared:
            failures.append(f"{label}: markers shared with another upstream, cannot discriminate: {shared}")
        if len(hit) == len(consts):
            failures.append(f"{label} appears to be ported after all")

    print()
    if failures:
        for f in failures:
            print("FAIL ", f)
        return 1
    print("PASS  lib/tonemap.glsl matches upstream glsl-tone-map and BakingLab as registered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
