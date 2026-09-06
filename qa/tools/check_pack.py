#!/usr/bin/env python3
"""Astra pack static validator (offline, no Iris / no glslang).

Checks the parts of an Iris shaderpack that are mechanically decidable:
option registries, GUI/sliders/profile/lang consistency, custom-uniform
contracts, include graph wiring, undeclared engine symbols, .properties
syntax, provenance ledger vs file headers, Bayer matrix correctness.

Usage:  python qa/tools/check_pack.py
Exit code = number of FAILed checks.
"""

import re
import sys
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Astra" / "shaders"
ANALYSIS = ROOT / "_analysis"

RESULTS = []
CHECKS = []


class Check:
    def __init__(self, cid, title):
        self.cid = cid
        self.title = title
        self.fails = []
        self.warns = []
        self.notes = []
        CHECKS.append(self)

    def fail(self, msg):
        self.fails.append(msg)

    def warn(self, msg):
        self.warns.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    def render(self):
        status = "FAIL" if self.fails else ("WARN" if self.warns else "PASS")
        print(f"[{status}] #{self.cid} {self.title}")
        for m in self.fails:
            print(f"       - {m}")
        for m in self.warns:
            print(f"       ~ {m}")
        for m in self.notes:
            print(f"       . {m}")
        RESULTS.append(self)


def read(p):
    return Path(p).read_text(encoding="utf-8", errors="replace")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def rel(p):
    try:
        return Path(p).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(p)


# ---------------------------------------------------------------- parsing

def parse_settings():
    """returns dict name -> {value, list, commented}"""
    path = PACK / "lib" / "settings.glsl"
    opts = {}
    for line in read(path).splitlines():
        m = re.match(r"^(//\s*)?#define\s+([A-Z][A-Z0-9_]*)\b(.*)$", line.strip())
        if not m:
            continue
        commented, name, rest = m.group(1) is not None, m.group(2), m.group(3)
        vl = re.search(r"\[([^\]]*)\]", rest)
        if vl is None:
            continue  # include guard / enum token constant, not a user option
        value = None
        vm = re.match(r"\s+([-\w.]+)", rest)
        if vm and not commented:
            value = vm.group(1)
        opts[name] = {
            "value": value,
            "list": vl.group(1).split() if vl else None,
            "bool": bool(vl) and set(vl.group(1).split()) == {"false", "true"},
            "commented": commented,
        }
    return opts


def logical_lines(text):
    """join backslash continuations"""
    out, buf = [], ""
    for line in text.splitlines():
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        out.append((buf + line).strip())
        buf = ""
    if buf:
        out.append(buf.strip())
    return out


def parse_properties():
    text = read(PACK / "shaders.properties")
    props = {}
    for line in logical_lines(text):
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        props.setdefault(k.strip(), []).append(v.strip())
    return props, text


# ---------------------------------------------------------------- checks

def check_option_registry():
    c = Check(1, "settings.glsl option registry (design 3.3: 60-80 options)")
    opts = parse_settings()
    n = len(opts)
    c.note(f"{n} options: {sum(1 for o in opts.values() if o['list'])} with value list, "
           f"{sum(1 for o in opts.values() if o['bool'])} bool, "
           f"{sum(1 for o in opts.values() if o['list'] and not o['bool'])} slider/enum")
    if not (60 <= n <= 80):
        c.fail(f"option count {n} outside design 3.3 range 60-80")
    for name, o in opts.items():
        if o["commented"] and not o["bool"]:
            # commented-out #define of a numeric option = default OFF enum/slider, suspicious
            c.warn(f"{name}: commented-out numeric define has no OFF representation rule")
        if o["list"] and not o["bool"] and o["value"] is not None:
            if o["value"] not in o["list"]:
                c.fail(f"{name}: default {o['value']} not in its own value list")
    return opts, c


def check_gui(opts):
    c = Check(2, "shaders.properties screen/sliders/profile <-> settings.glsl bijection")
    props, _ = parse_properties()
    screens = {k: v for k, v in props.items() if k == "screen" or k.startswith("screen.")}
    listed = set()
    for k, vals in screens.items():
        for v in vals:
            for tok in v.split():
                if tok.startswith("[") or tok.startswith("<"):
                    continue
                listed.add(tok)
    missing = set(opts) - listed
    extra = listed - set(opts)
    if missing:
        c.fail(f"{len(missing)} option(s) in settings.glsl not present in any screen: "
               + ", ".join(sorted(missing)))
    if extra:
        c.fail(f"{len(extra)} screen token(s) not defined in settings.glsl: "
               + ", ".join(sorted(extra)))
    subscreens = sorted(k for k in screens if k != "screen")
    c.note(f"1 main screen + {len(subscreens)} categories: {', '.join(s.split('.',1)[1] for s in subscreens)}")
    if len(subscreens) != 7:
        c.fail(f"{len(subscreens)} GUI categories, design 3.3 requires 7")

    sliders = set()
    for v in props.get("sliders", []):
        sliders |= set(v.split())
    def is_enum(o):
        vals = [int(v) for v in o["list"]]
        return vals == list(range(len(vals))) and len(vals) <= 5

    numeric = {k for k, o in opts.items() if o["list"] and not o["bool"]}
    enums = {k for k, o in opts.items() if o["list"] and not o["bool"] and is_enum(o)}
    c.note(f"{len(enums)} enum/dropdown option(s) (not sliders): {', '.join(sorted(enums))}")
    if sliders - numeric:
        c.fail("sliders= lists non-numeric option(s): " + ", ".join(sorted(sliders - numeric)))
    if (numeric - enums) - sliders:
        c.fail("slider option(s) missing from sliders=: "
               + ", ".join(sorted((numeric - enums) - sliders)))
    if sliders & enums:
        c.fail("sliders= lists an enum/dropdown option: " + ", ".join(sorted(sliders & enums)))
    c.note(f"sliders={len(sliders)} vs {len(numeric) - len(enums)} slider-typed options")

    profiles = {k.split(".", 1)[1]: v for k, v in props.items() if k.startswith("profile.")}
    for pname, vals in profiles.items():
        toks = []
        for v in vals:
            toks += v.split()
        names = [(t[1:] if t.startswith("!") else t).split("=", 1)[0] for t in toks]
        dup = {t for t in names if names.count(t) > 1}
        if dup:
            c.fail(f"profile.{pname}: duplicated token(s): {', '.join(sorted(dup))}")
        pset = set(names)
        if set(opts) - pset:
            c.fail(f"profile.{pname}: missing {len(set(opts)-pset)} option(s): "
                   + ", ".join(sorted(set(opts) - pset)))
        if pset - set(opts):
            c.fail(f"profile.{pname}: unknown token(s): " + ", ".join(sorted(pset - set(opts))))
        for t in toks:
            if t.startswith("!") and not opts.get(t[1:], {}).get("bool"):
                c.fail(f"profile.{pname}: '{t}' negates a non-bool option")
        for t in toks:
            if "=" not in t:
                continue
            name, raw = t.split("=", 1)
            if name.startswith("!"):
                name = name[1:]
            meta = opts.get(name) or {}
            allowed = meta.get("list") or []
            if meta.get("bool") or not allowed:
                continue
            try:
                val = float(raw)
            except ValueError:
                c.fail(f"profile.{pname}: '{t}' has a non-numeric value")
                continue
            if not any(re.fullmatch(r"[-\d.eE+]+", a) and abs(val - float(a)) < 1e-9
                       for a in allowed):
                c.fail(f"profile.{pname}: '{t}' is not one of {name}'s enumerated values")
        c.note(f"profile.{pname}: {len(pset)} tokens, complete={pset == set(opts)}")
    if len(profiles) != 3:
        c.fail(f"{len(profiles)} profiles, design 3.3 requires 3")
    return c


def check_lang(opts):
    c = Check(3, "lang files cover every option with title + comment")
    langs = {}
    for name in ("zh_CN.lang", "en_US.lang"):
        p = PACK / "lang" / name
        if not p.exists():
            c.fail(f"missing {name}")
            continue
        keys = set()
        for line in read(p).splitlines():
            m = re.match(r"^option\.([A-Za-z0-9_.]+)\s*=", line.strip())
            if m:
                keys.add(m.group(1))
        langs[name] = keys
        titles = {k for k in keys if not k.endswith(".comment")}
        comments = {k[:-len(".comment")] for k in keys if k.endswith(".comment")}
        missing_t = set(opts) - titles
        missing_c = set(opts) - comments
        extra = {k for k in titles if k not in opts}
        if missing_t:
            c.fail(f"{name}: {len(missing_t)} option(s) without title: "
                   + ", ".join(sorted(missing_t)))
        if missing_c:
            c.fail(f"{name}: {len(missing_c)} option(s) without .comment: "
                   + ", ".join(sorted(missing_c)))
        if extra:
            c.fail(f"{name}: {len(extra)} key(s) with no matching option: "
                   + ", ".join(sorted(extra)))
        n_com = sum(1 for line in read(p).splitlines() if line.strip().endswith("=默认"))
        c.note(f"{name}: {len(titles)} titles, {len(comments)} comments")
    if len(langs) == 2:
        if langs["zh_CN.lang"] != langs["en_US.lang"]:
            d1 = langs["zh_CN.lang"] - langs["en_US.lang"]
            d2 = langs["en_US.lang"] - langs["zh_CN.lang"]
            c.fail("zh_CN/en_US key sets differ: "
                   f"only-zh={sorted(d1)[:8]} only-en={sorted(d2)[:8]}")
    return c


def walk_shader_files():
    for p in sorted(PACK.rglob("*")):
        if p.is_file() and p.suffix in (".vsh", ".fsh", ".glsl", ".json"):
            yield p


def is_entry(p):
    """Iris compiles pass files and world shells (.vsh/.fsh); lib/, global/ and
    root .glsl includes are include-only layers; .json is engine config."""
    if p.suffix not in (".vsh", ".fsh"):
        return False
    parts = p.relative_to(PACK).parts
    return parts[0] not in ("lib", "global")


def resolve_include(spec, from_file):
    # "/lib/x.glsl" is pack-root-relative (the convention all four reference packs use)
    if spec.startswith("/"):
        return resolve_include(spec[1:], from_file.parent)
    cand = (from_file.parent / spec)
    if cand.exists():
        return cand
    cand = PACK / spec
    if cand.exists():
        return cand
    return None


def build_include_graph():
    graph, unresolved = {}, []
    for p in walk_shader_files():
        incs = []
        for m in re.finditer(r'^\s*#include\s+[<"]([^">]+)[">]', read(p), flags=re.M):
            spec = m.group(1)
            t = resolve_include(spec, p)
            if t is None:
                unresolved.append((p, spec))
            else:
                incs.append(t)
        graph[p] = incs
    return graph, unresolved


def closure(files, graph):
    seen, stack = set(), list(files)
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        stack.extend(graph.get(f, []))
    return seen


# Modules whose consumer task has not landed yet. An orphan listed here is a WARN with its
# owner named; an orphan NOT listed means somebody claimed the module but never wired it -> FAIL.
# Shrink this map as the owning task ships (design.md 3.2 include-layering resolution, SC-10).
PENDING_CONSUMERS = {
    "lib/uniforms.glsl": "E1",
    "lib/tonemap.glsl": "E1 (M1 minimal final chain) / C6",
    "lib/encoding.glsl": "E1 (flat uint face packing)",
    "lib/transforms.glsl": "E1 (varyings, view-space rebuild)",
    "lib/colors.glsl": "C1",
    "lib/distort.glsl": "B1",
    "lib/noise.glsl": "C2 / E2 (water surface)",
    "lib/dither.glsl": "C6",
    "lib/bayer.glsl": "B4",
    "global/lighting/shadowmap.glsl": "B1",
    "global/lighting/diffuse.glsl": "C1",
    "global/lighting/blocklight.glsl": "C1",
    "global/lighting/sss.glsl": "C1",
    "global/lighting/wind.glsl": "B3",
    "global/atmosphere/sky_minishita.glsl": "D2",
    "global/atmosphere/sky_gradient.glsl": "D2",
    "global/atmosphere/stars.glsl": "D2",
    "global/atmosphere/clouds_planar.glsl": "D2 (SC-12)",
    "global/atmosphere/fog.glsl": "B2",
    "global/water/surface.glsl": "unowned - see SC-15",
    "global/water/raytrace.glsl": "unowned - see SC-15",
    "global/water/refraction.glsl": "C2",
    "global/water/absorption.glsl": "C2",
    "global/water/caustics.glsl": "C2",
    "global/post/godrays.glsl": "B4",
    "global/post/bloom.glsl": "B5",
    "global/post/grading.glsl": "C6",
    "global/dimension/overworld.glsl": "E1 (dimension macro protocol)",
    "global/dimension/nether.glsl": "C3",
    "global/dimension/end.glsl": "C4",
    "voxy_opaque.glsl": "C5 (voxy.json patch data, not an #include entry)",
    "voxy_translucent.glsl": "C5 (voxy.json patch data, not an #include entry)",
}


def pk(p):
    return Path(p).resolve().relative_to(PACK.resolve()).as_posix()


def check_include_graph():
    c = Check(4, "include graph (design 3.2 layering): no dangling include, every entry reaches "
                 "lib/settings.glsl, no unwired module, no layer violation")
    graph, unresolved = build_include_graph()
    for p, spec in unresolved:
        c.fail(f"{rel(p)}: #include \"{spec}\" does not resolve")

    entries = [p for p in graph if is_entry(p)]
    used = closure(entries, graph)
    layers = [p for p in graph
              if not is_entry(p) and p.suffix in (".glsl", ".vsh", ".fsh")]
    orphans = [p for p in layers if p not in used]
    pending = [x for x in orphans if pk(x) in PENDING_CONSUMERS]
    untracked = [x for x in orphans if pk(x) not in PENDING_CONSUMERS]
    for x in untracked:
        c.fail(f"orphan and not registered in PENDING_CONSUMERS: {pk(x)} "
               f"(wire it or record its owner task)")
    for x in sorted(pending, key=pk):
        c.warn(f"pending wiring: {pk(x)} <- owner {PENDING_CONSUMERS[pk(x)]}")

    # layer 1: a shell carries only #version + macro + include of a program file
    for e in sorted(entries, key=pk):
        if pk(e).startswith("program/"):
            continue
        for t in graph.get(e, []):
            if pk(t).startswith(("lib/", "global/")):
                c.fail(f"{pk(e)}: shell includes {pk(t)} directly - layer 1 shells must only "
                       f"#version/#define/include a program file (design 3.2)")
    # layer 3: global/* must not depend on program/*
    for m in sorted(layers, key=pk):
        if not pk(m).startswith("global/"):
            continue
        for t in graph.get(m, []):
            if pk(t).startswith("program/"):
                c.fail(f"{pk(m)}: global module includes {pk(t)} - layer 3 may not depend on "
                       f"program (design 3.2)")
    no_settings = [p for p in sorted(entries)
                   if not any(x.name == "settings.glsl" for x in closure([p], graph))]
    if no_settings:
        c.fail(f"{len(no_settings)}/{len(entries)} compiled entry/entries whose closure "
               f"does not include lib/settings.glsl (no option reachability); e.g. "
               + ", ".join(rel(p) for p in no_settings[:4]))
    c.note(f"{len(entries)} compiled entries, {len(layers)} lib/global modules, "
           f"{len(layers)-len(orphans)} reachable, {len(pending)} waiting on their owner task, "
           f"{len(untracked)} unwired-and-unregistered")
    return c, graph, entries


# symbols that must be declared somewhere in the effective closure
ENGINE_SYMBOLS = {
    "frameCounter": "uniform int frameCounter;",
    "noisetex": "uniform sampler2D noisetex;",
    "noiseTextureResolution": "const int noiseTextureResolution;",
    "shadowDistance": "const float shadowDistance; (or uniform)",
    "colortex": "buffer format declaration",
}


def check_undeclared_symbols():
    c = Check(5, "engine/vanilla symbols referenced by lib|global must be declared in the "
                 "declaration layer (settings/uniforms)")
    decl_files = [PACK / "lib" / "uniforms.glsl", PACK / "lib" / "settings.glsl"]
    # engine settings are also legal in the program const blocks (design.md 2.3)
    decl_text = "\n".join(strip_comments(read(p)) for p in decl_files if p.exists())
    DECL_RE = r"\b(?:uniform|const|in|out)\s+\w+\s+(\w+)\s*(?:\[[^\]]*\])?\s*[;=]"
    declared = set(re.findall(DECL_RE, decl_text))
    const_names = set(re.findall(r"\bconst\s+\w+\s+(\w+)\s*(?:\[[^\]]*\])?\s*[;=]", decl_text))
    declared |= set(re.findall(r"#define\s+(\w+)", "\n".join(read(p) for p in decl_files)))
    watch = ["frameCounter", "frameTimeCounter", "noisetex", "noiseTextureResolution", "shadowDistance",
             "shadowMapResolution", "sunPathRotation", "gbufferModelView", "gcolor",
             "texture2D"]
    for p in sorted(walk_shader_files()):
        if is_entry(p):
            continue
        body = strip_comments(read(p))
        for sym in watch:
            if re.search(r"\b" + re.escape(sym) + r"\b", body):
                if sym not in declared:
                    c.fail(f"{rel(p)}: uses '{sym}' but it is not declared in "
                           f"lib/uniforms.glsl nor lib/settings.glsl")
        # const initialised from a *uniform* is illegal GLSL; a const initialised from an
        # engine const (shadowDistance et al. are const, not uniform) is a constant expr
        for m in re.finditer(r"\bconst\s+\w+\s+(\w+)\s*=\s*([^;]+);", body):
            name, expr = m.group(1), m.group(2)
            used_uniforms = [u for u in ("shadowDistance", "sunPathRotation", "frameTimeCounter")
                             if re.search(r"\b" + u + r"\b", expr) and u not in const_names]
            if used_uniforms:
                c.fail(f"{rel(p)}: const {name} = {expr.strip()[:60]} initialised from "
                       f"uniform {used_uniforms} (not a constant expression)")
    return c


def check_custom_uniforms():
    c = Check(6, "custom uniforms: shaders.properties <-> lib/uniforms.glsl contract")
    props, text = parse_properties()
    uni_decl, var_decl = {}, {}
    for line in logical_lines(text):
        m = re.match(r"^uniform\.(\w+)\.(\w+)=", line)
        if m:
            uni_decl[m.group(2)] = m.group(1)
        m = re.match(r"^variable\.(\w+)\.(\w+)=", line)
        if m:
            var_decl[m.group(2)] = m.group(1)

    glsl_path = PACK / "lib" / "uniforms.glsl"
    glsl_decl = {}
    if glsl_path.exists():
        for m in re.finditer(r"^\s*uniform\s+(\w+)\s+(\w+)\s*(?:\[\s*\d+\s*\])?\s*;",
                             read(glsl_path), flags=re.M):
            glsl_decl[m.group(2)] = m.group(1)
    for name, ty in uni_decl.items():
        if name not in glsl_decl:
            c.fail(f"uniform.{name} sent by properties but not declared in lib/uniforms.glsl")
        elif glsl_decl[name] != ty:
            c.fail(f"uniform.{name}: properties says {ty}, GLSL declares {glsl_decl[name]}")
    for name, ty in glsl_decl.items():
        if name in uni_decl:
            continue
        # built-ins are fine; flag only our own camelCase precomputed names
    c.note(f"{len(uni_decl)} uniform.* + {len(var_decl)} variable.* in properties; "
           f"{len(glsl_decl)} uniform decl(s) in lib/uniforms.glsl")

    # every intermediate referenced in expressions must be defined earlier in the file
    order, seen = [], set()
    for line in logical_lines(text):
        m = re.match(r"^(?:variable|uniform)\.\w+\.(\w+)=", line)
        if not m:
            continue
        name = m.group(1)
        expr = line.split("=", 1)[1]
        refs = set(re.findall(r"\b([a-z][A-Za-z0-9]*)\b", expr))
        local = {r for r in refs if r in var_decl or r in uni_decl}
        undeclared = {r for r in local if r not in seen}
        if undeclared:
            c.fail(f"{name}: references {sorted(undeclared)} before it is defined "
                   f"(Iris evaluates top-down)")
        seen.add(name)
        order.append(name)

    # GLSL-side: uniforms.glsl must NOT declare variables that properties never sends
    # (harmless) -> informational only
    return c


BUILTIN_OR_LIB = {
    "sunPosition", "shadowLightPosition", "frameTimeCounter", "rainStrength", "far",
    "near", "isEyeInWater", "gbufferProjection", "gbufferModelViewInverse", "dimension",
    "temperature", "rainfall", "zero", "one", "abs", "min", "max", "pow", "clamp", "mix",
    "sin", "cos", "degrees", "radians", "smoothstep", "if", "floor", "ceil", "fract",
    "vec2", "vec3", "vec4", "float", "int", "true", "false", "wetness", "snowStrength",
    "blindness", "ageGate", "sunAngle", "moonPhase", "inRain", "eyeAltitude",
}


def check_properties_syntax():
    c = Check(7, "block.properties / entity.properties syntax + ID sanity")
    for fname in ("block.properties", "entity.properties"):
        p = PACK / fname
        if not p.exists():
            c.fail(f"missing {fname}")
            continue
        lines = logical_lines(read(p))
        ids = {}
        for line in lines:
            if not line or line.startswith("#"):
                continue
            if "+=" in line.split("=")[0] or re.match(r"^\s*\w+\.\d+\+=", line):
                c.fail(f"{fname}: invalid append syntax (OptiFine/Iris have no '+=' operator): "
                       f"{line[:80]}")
                continue
            m = re.match(r"^(\w+)\.(\d+)\s*=\s*(.*)$", line)
            if not m:
                c.fail(f"{fname}: unparseable line: {line[:80]}")
                continue
            key, bid, val = m.groups()
            if key not in ("block", "entity"):
                c.fail(f"{fname}: unexpected key '{key}'")
            tokens = val.split()
            if bid in ids:
                same = set(ids[bid]) == set(tokens)
                if not same:
                    c.fail(f"{fname}: id {bid} defined twice with different content")
                else:
                    c.warn(f"{fname}: id {bid} defined twice (identical)")
            ids[bid] = tokens
        n = len(ids)
        c.note(f"{fname}: {n} id groups")

    # unknown vanilla ids vs the union of ids used by the four reference packs
    corpus = set()
    if ANALYSIS.exists():
        for p in ANALYSIS.glob("*/shaders/block*.properties"):
            for line in logical_lines(read(p)):
                for tok in (line.split("=", 1)[1:] or [""])[0].split():
                    m = re.match(r"^([a-z0-9_]+):([a-z0-9_./]+)", tok)
                    if m:
                        corpus.add(f"{m.group(1)}:{m.group(2)}")
    if not corpus:
        c.warn("no reference corpus available for block-id validation")
        return c
    p = PACK / "block.properties"
    if p.exists():
        unknown = set()
        for line in logical_lines(read(p)):
            if "=" not in line or line.startswith("#"):
                continue
            for tok in line.split("=", 1)[1].split():
                m = re.match(r"^minecraft:([a-z0-9_.]+)$", tok)
                if m and tok not in corpus:
                    unknown.add(tok)
        if unknown:
            c.note(f"{len(unknown)} minecraft: id(s) absent from all 4 reference packs "
                   f"(new/renamed, verify at smoke): {', '.join(sorted(unknown)[:12])}")
    return c


def check_provenance():
    c = Check(8, "THIRD-PARTY.md ledger <-> file provenance headers <-> license rules (design 9)")
    led = ROOT / "Astra" / "THIRD-PARTY.md"
    if not led.exists():
        c.fail("Astra/THIRD-PARTY.md missing (design 9.2 requires it from day one)")
        return c
    text = read(led)
    rows = []
    for line in text.splitlines():
        if line.startswith("|") and "lib/" in line or line.startswith("|") and "shaders/" in line \
           or line.startswith("|") and "program/" in line or line.startswith("|") and ".properties" in line:
            cells = [x.strip() for x in line.strip().strip("|").split("|")]
            rows.append(cells)
    c.note(f"{len(rows)} ledger rows")

    # every file with a provenance header must be in the ledger, and vice versa
    header_paths = {}
    for p in walk_shader_files():
        head = read(p)[:4000]
        m = re.search(r"(?://|/\*)\s*From\s+([^\n]+)", head)
        if m:
            header_paths[rel(p)] = m.group(1).strip()
    ledger_norm = text.replace("`", "")
    for path, src in header_paths.items():
        key = Path(path).name
        if key not in ledger_norm and path not in ledger_norm:
            c.fail(f"{path}: has provenance header ('From {src[:40]}') but no ledger row")
    for row in rows:
        joined = " ".join(row)
        m = re.search(r"([A-Za-z0-9_./-]+\.(?:glsl|fsh|vsh|properties|lang|png|json|md))", joined)
        if m:
            fname = m.group(1)
            matches = [p for p in header_paths if p.endswith(fname)]
            if not matches and (PACK / fname).exists():
                body = read(PACK / fname)
                named = re.search(r"(Mellow|Steadfast|Refrax|Solas)", body)
                if not named:
                    c.fail(f"ledger row for {fname} exists but the file names no source pack")

    # GPL / proprietary rules
    steadfast_files = [p for p in header_paths if "Steadfast" in header_paths[p]]
    for p in steadfast_files:
        if "GPL" not in read(p):
            c.fail(f"{p}: header credits Steadfast (GPLv3) but carries no GPL notice "
                   f"(design 9.1: 'GPL declaration kept in file header')")
    props = read(PACK / "shaders.properties")
    if "Steadfast" in props and "GPL" not in props:
        c.fail("shaders.properties: credits Steadfast for the custom-uniform style but carries "
               "no GPLv3 notice (design 9.1: 'GPL declaration kept in file header')")
    # ledger numbers must match the expression-diff classifier (qa/tools/provenance_steadfast.py)
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import provenance_steadfast
    except Exception as e:
        c.fail(f"cannot import provenance_steadfast to verify the Steadfast ledger: {e}")
        return c
    measured = provenance_steadfast.counts()

    # every count stated for a borrow class in the ledger must equal the measured value
    stated = {k: [] for k in measured}
    for cls in measured:
        for m in re.finditer(re.escape(cls) + r"\s*(?:=|＝|\(|（)\s*(\d+)", ledger_norm):
            stated[cls].append(int(m.group(1)))
    missing = [k for k, v in stated.items() if not v]
    if missing:
        c.fail("THIRD-PARTY.md states no count for " + ", ".join(missing)
               + " (ledger must be machine-checkable; run provenance_steadfast.py --quiet and record it)")
    for cls, values in stated.items():
        bad = sorted(set(v for v in values if v != measured[cls]))
        if bad:
            c.fail(f"THIRD-PARTY.md '{cls}' counts {bad} disagree with the expression diff "
                   f"({measured[cls]}); re-run: python qa/tools/provenance_steadfast.py --quiet")
    if not missing and not any(
            v != measured[k] for k, vals in stated.items() for v in vals):
        c.note("Steadfast expression-diff matches every ledger count: "
               + " ".join(f"{k}={v}" for k, v in measured.items())
               + f" (stated {sum(len(v) for v in stated.values())}x)")
    return c


def check_bayer():
    c = Check(9, "bayer.glsl ordered-dither matrix correctness")
    p = PACK / "lib" / "bayer.glsl"
    if not p.exists():
        c.fail("lib/bayer.glsl missing")
        return c
    body = strip_comments(read(p))
    m = re.search(r"bayer8x8\s*\[\s*64\s*\]\s*=\s*float\s*(?:\[\s*\])?\s*\((.*?)\)\s*;",
                  body, flags=re.S)
    if not m:
        c.fail("no 'const float bayer8x8[64] = float(...)' array found")
        return c
    vals = [float(v) for v in re.findall(r"-?\d+\.?\d*", m.group(1))]
    if len(vals) != 64:
        c.fail(f"array holds {len(vals)} values, must be 64")
        return c
    if len(set(vals)) != 64:
        c.fail(f"only {len(set(vals))} distinct levels; an ordered matrix needs all 64")
        return c
    lo, hi = min(vals), max(vals)
    got = [[int(round((vals[x * 8 + y] - lo) / (hi - lo) * 63)) for y in range(8)]
           for x in range(8)]
    canonical = [[0, 32, 8, 40, 2, 34, 10, 42],
                 [48, 16, 56, 24, 50, 18, 58, 26],
                 [12, 44, 4, 36, 14, 46, 6, 38],
                 [60, 28, 52, 20, 62, 30, 54, 22],
                 [3, 35, 11, 43, 1, 33, 9, 41],
                 [51, 19, 59, 27, 49, 17, 57, 25],
                 [15, 47, 7, 39, 13, 45, 5, 37],
                 [63, 31, 55, 23, 61, 29, 53, 21]]
    bad = [(x, y) for x in range(8) for y in range(8) if got[x][y] != canonical[x][y]]
    if bad:
        c.warn(f"valid 64-level ordered matrix but differs from canonical Bayer8 in "
               f"{len(bad)} cells (row-major [y*8+x]): {bad[:6]}")
    else:
        c.note("matches canonical recursive Bayer8 (row-major, [y*8+x] indexing)")
    if "bayer8(" not in body:
        c.fail("no bayer8() accessor function")
    return c


def check_final_chain():
    c = Check(10, "M1 'minimal final chain' (design 7: tonemap + sRGB) actually present")
    p = PACK / "program" / "final.fsh"
    body = strip_comments(read(p))
    has_main = "void main" in body
    writes = re.search(r"gl_Frag(Depth|Data\[)", body)
    real = re.search(r"tonemap|linearToSrgb|pow\(.*1\.0\s*/\s*2\.2", body, flags=re.I)
    if has_main and not real:
        stub = bool(re.search(r"gl_FragData\[\d+\]\s*=\s*vec4\(\s*0", body))
        if stub:
            c.fail("program/final.fsh is a black-screen stub: design 7 M1 requires a minimal "
                   "final chain (tonemap + sRGB) so the vanilla picture is visible")
    c.note(f"final.fsh: {len(body.splitlines())} lines of code, tonemap/sRGB present={bool(real)}")
    return c


FORMAT_NAMES = ["colortex0Format", "colortex1Format", "colortex2Format",
                 "colortex3Format", "colortex4Format", "shadowcolor0Format"]


def check_buffer_formats():
    c = Check(11, "design 2.3: all buffer formats declared as LIVE const int inside a compiled closure")
    graph, _ = build_include_graph()
    entries = [p for p in graph if is_entry(p)]
    reach = closure(entries, graph)
    live = set()
    for p in reach:
        body = strip_comments(read(p))
        for n in FORMAT_NAMES:
            if re.search(r"\bconst\s+int\s+" + n + r"\s*=", body):
                live.add(n)
    for p in sorted(walk_shader_files()):
        raw = read(p)
        for n in FORMAT_NAMES:
            if n in raw and n not in live and p not in reach:
                c.warn(f"{pk(p)}: {n} mentioned in a file nobody compiles")
    inert = [n for n in FORMAT_NAMES
             if n not in live and any(n in read(p) for p in walk_shader_files())]
    if inert:
        c.fail("declared only inside a comment (Iris never sees it, design 2.3 not in force): "
               + ", ".join(inert))
    missing = [n for n in FORMAT_NAMES if n not in live]
    if missing:
        c.fail("no live const int in any compiled closure: " + ", ".join(missing))
    c.note(f"{len(live)}/{len(FORMAT_NAMES)} buffer formats live in the compiled closure")
    return c


def main():
    print(f"Astra pack validator | pack={rel(PACK)} | python={sys.version.split()[0]}")
    print("=" * 72)
    opts, _ = check_option_registry()
    check_gui(opts)
    check_lang(opts)
    check_include_graph()
    check_undeclared_symbols()
    check_custom_uniforms()
    check_properties_syntax()
    check_provenance()
    check_bayer()
    check_final_chain()
    check_buffer_formats()
    for c in CHECKS:
        c.render()
    print("=" * 72)
    fails = [r for r in RESULTS if r.fails]
    warns = [r for r in RESULTS if r.warns and not r.fails]
    print(f"{len(RESULTS)} checks: {len(fails)} FAIL, {len(warns)} WARN, "
          f"{len(RESULTS) - len(fails) - len(warns)} PASS")
    return len(fails)


if __name__ == "__main__":
    sys.exit(main())
