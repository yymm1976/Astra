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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compile_glsl  # shared Iris render-stage table (SC-31)
import option_matrix  # shared option/consumer analysis (check 13)
from shader_options import parse_options

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
    return option_matrix.strip_comments(text)


def rel(p):
    try:
        return Path(p).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(p)


# ---------------------------------------------------------------- parsing

def parse_settings():
    """returns dict name -> {value, list, commented}"""
    path = PACK / "lib" / "settings.glsl"
    return {name: {"value": item.value if item.value and not item.off else None,
                   "list": list(item.levels), "bool": item.boolean,
                   "commented": item.off, "const_type": item.const_type}
            for name, item in parse_options(read(path)).items()}


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

def quality_option_names(opts):
    # Colour settings intentionally survive a performance-profile change.
    independent = {"COLOR_STYLE", "TONEMAP_OPERATOR", "EXPOSURE", "AUTO_EXPOSURE",
                   "SATURATION", "VIBRANCE", "CONTRAST", "COLOR_TEMPERATURE"}
    return {name for name in opts if name not in independent
            and not name.startswith(("TINT_", "LOOK_"))}


def check_option_registry():
    c = Check(1, "settings.glsl option registry (nested colour controls supported)")
    opts = parse_settings()
    n = len(opts)
    c.note(f"{n} options: {sum(1 for o in opts.values() if o['list'])} with value list, "
           f"{sum(1 for o in opts.values() if o['bool'])} bool, "
           f"{sum(1 for o in opts.values() if o['list'] and not o['bool'])} slider/enum")
    if n < 60:
        c.fail(f"option count {n} below the core option set")
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
    screens = {k: v for k, v in props.items()
               if (k == "screen" or k.startswith("screen."))
               and not k.endswith((".columns", ".comment"))}
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
    required_screens = {"screen." + name for name in
                        ("LIGHTING", "SHADOWS", "SKY", "WATER", "FOG", "POST", "PERFORMANCE", "COLORS")}
    if required_screens - set(screens):
        c.fail("missing GUI categories: " + ", ".join(sorted(required_screens - set(screens))))

    sliders = set()
    for v in props.get("sliders", []):
        sliders |= set(v.split())
    def is_enum(o):
        try:
            vals = [int(v) for v in o["list"]]
        except ValueError:
            return False  # Float const options are sliders, not integer enum arms.
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

    quality_opts = quality_option_names(opts)
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
        if quality_opts - pset:
            c.fail(f"profile.{pname}: missing {len(quality_opts-pset)} quality option(s): "
                   + ", ".join(sorted(quality_opts - pset)))
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
        c.note(f"profile.{pname}: {len(pset)} tokens, quality complete={quality_opts <= pset}")
    expected_profiles = set(TIER_ORDER) | {"NO_SHADOWS"}
    if set(profiles) != expected_profiles:
        c.fail("expected the three quality tiers plus NO_SHADOWS; missing="
               + str(sorted(expected_profiles - set(profiles)))
               + ", unexpected=" + str(sorted(set(profiles) - expected_profiles)))
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
    # .csh covers Iris compute stages (and their include-only modules) so the
    # symbol/render-stage contracts apply to them too.
    for p in sorted(PACK.rglob("*")):
        if p.is_file() and p.suffix in (".vsh", ".fsh", ".glsl", ".csh", ".json"):
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
    "lib/sky_sh9.glsl": "S1 (H1 directional skylight wiring)",
    "lib/volume_integral.glsl": "S2 (H3 overworld volumetric fog wiring)",
    "global/water/temporal.glsl": "R5 residual: the SSR hit-radiance history was retired "
                                  "2026-09-28 (a geometry pass has no composite ping-pong "
                                  "contract); kept as the research record for a future "
                                  "composite-stage producer, see "
                                  "docs/2026-09-28-water-material-lighting.md",
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
    "global/water/particles.glsl": "C2",
    "global/post/godrays.glsl": "B4",
    "global/post/bloom.glsl": "B5",
    "global/post/grading.glsl": "C6",
    "global/dimension/overworld.glsl": "E1 (dimension macro protocol)",
    "global/dimension/nether.glsl": "C3",
    "global/dimension/end.glsl": "C4",
    "voxy_opaque.glsl": "C5 (voxy.json patch data, not an #include entry)",
    "voxy_translucent.glsl": "C5 (voxy.json patch data, not an #include entry)",
}

RETIRED_MODULES = {
    "global/dimension/nether_volume.glsl": "C3 research implementation; active Nether "
                                          "uses homogeneous fog, no volume producer "
                                          "or sampler binding",
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
    retired = [x for x in orphans if pk(x) in RETIRED_MODULES]
    untracked = [x for x in orphans
                 if pk(x) not in PENDING_CONSUMERS and pk(x) not in RETIRED_MODULES]
    for x in untracked:
        c.fail(f"orphan and not registered in PENDING_CONSUMERS: {pk(x)} "
               f"(wire it or record its owner task)")
    for x in sorted(pending, key=pk):
        c.warn(f"pending wiring: {pk(x)} <- owner {PENDING_CONSUMERS[pk(x)]}")
    for x in sorted(retired, key=pk):
        c.note(f"retired, intentionally not loaded: {pk(x)} <- {RETIRED_MODULES[pk(x)]}")

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
    c = Check(6, "custom uniforms: shaders.properties <-> GLSL uniform declarations")
    props, text = parse_properties()
    uni_decl, var_decl = {}, {}
    for line in logical_lines(text):
        m = re.match(r"^uniform\.(\w+)\.(\w+)=", line)
        if m:
            uni_decl[m.group(2)] = m.group(1)
        m = re.match(r"^variable\.(\w+)\.(\w+)=", line)
        if m:
            var_decl[m.group(2)] = m.group(1)

    # Custom uniforms may be declared in any include layer reachable from an entry:
    # lib/uniforms.glsl is the shared layer, but feature modules such as
    # lib/solas_water.glsl own their own names. Scanning only uniforms.glsl produced
    # false "not declared" failures for those.
    decl_files = {}
    glsl_decl = {}
    for path in walk_shader_files():
        if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh"):
            continue
        for m in re.finditer(r"^\s*uniform\s+(\w+)\s+(\w+)\s*(?:\[\s*\d+\s*\])?\s*;",
                             read(path), flags=re.M):
            name, ty = m.group(2), m.group(1)
            glsl_decl.setdefault(name, ty)
            decl_files.setdefault(name, pk(path))
    for name, ty in uni_decl.items():
        if name not in glsl_decl:
            c.fail(f"uniform.{name} sent by properties but declared in no GLSL file")
        elif glsl_decl[name] != ty:
            c.fail(f"uniform.{name}: properties says {ty}, GLSL declares "
                   f"{glsl_decl[name]} in {decl_files[name]}")
    for name, ty in glsl_decl.items():
        if name in uni_decl:
            continue
        # built-ins are fine; flag only our own camelCase precomputed names
    c.note(f"{len(uni_decl)} uniform.* + {len(var_decl)} variable.* in properties; "
           f"{len(glsl_decl)} uniform decl(s) across the include tree")

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
        # Self-written ledger rows (Astra组合/Astra自写/D2自写/...) record provenance of
        # NON-borrowed files; the body-naming check below only applies to borrow rows.
        if "自写" in joined or "self-written" in joined:
            continue
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
    if not Path(provenance_steadfast.STEADFAST).is_file():
        c.warn("Steadfast reference source is unavailable; expression comparison skipped. "
               "File-header and ledger checks above still apply.")
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


ENGINE_CONST_NAMES = {
    "shadowMapResolution", "shadowDistance", "shadowDistanceRenderMul",
    "entityShadowDistanceMul", "noiseTextureResolution", "sunPathRotation",
    "shadowHardwareFiltering",
}

# Format tokens Iris injects for const int colortex<N>Format (the engine reads the
# identifier, not a value), so neither check 11 nor check 13 may report them as
# unknown macros. Verified against the installed iris.jar by
# qa/tools/inspect_iris_properties.py.
ENGINE_FORMAT_TOKENS = {
    "RGBA", "R8", "RG8", "RGB8", "RGBA8", "R8_SNORM", "RG8_SNORM", "RGB8_SNORM",
    "RGBA8_SNORM", "R16", "RG16", "RGB16", "RGBA16", "R16_SNORM", "RG16_SNORM",
    "RGB16_SNORM", "RGBA16_SNORM", "R16F", "RG16F", "RGB16F", "RGBA16F", "R32F",
    "RG32F", "RGB32F", "RGBA32F", "R8I", "RG8I", "RGB8I", "RGBA8I", "R8UI",
    "RG8UI", "RGB8UI", "RGBA8UI", "R16I", "RG16I", "RGB16I", "RGBA16I", "R16UI",
    "RG16UI", "RGB16UI", "RGBA16UI", "R32I", "RG32I", "RGB32I", "RGBA32I",
    "R32UI", "RG32UI", "RGB32UI", "RGBA32UI", "RGBA2", "RGBA4", "R3_G3_B2",
    "RGB5_A1", "RGB565", "RGB10_A2", "RGB10_A2UI", "R11F_G11F_B10F", "RGB9_E5",
}


def _numeric_literal(value):
    return bool(re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?[fF]?", value.strip()))


def check_iris_parser_contracts():
    """Parser constraints learned from SC-21..SC-27 on Iris 1.11.2."""
    c = Check(11, "Iris 1.11.2 parser contracts (SC-21..SC-27)")

    shader_files = list(walk_shader_files())

    # SC-21: Iris treats anything after the closing quote as part of the path.
    for p in shader_files:
        for lineno, line in enumerate(read(p).splitlines(), 1):
            if re.match(r"^\s*#include\b", line) and not re.fullmatch(
                    r'\s*#include\s+"[^"]+"\s*', line):
                c.fail(f"{pk(p)}:{lineno}: include must end at the closing quote")

    # SC-22: texture directives require texture.<stage>.<sampler>. SC-27 currently
    # uses the conventional textures/noise.png auto-binding route, so zero entries is valid.
    _, properties_text = parse_properties()
    texture_count = 0
    for lineno, line in enumerate(logical_lines(properties_text), 1):
        if not line or line.startswith("#") or "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        if not key.startswith("texture."):
            continue
        texture_count += 1
        if "." not in key[len("texture."):]:
            c.fail(f"shaders.properties logical line {lineno}: single-segment texture key '{key}'")

    # SC-23: Iris engine const directives must reduce to literals. Simple option
    # macros are accepted only when their current default is itself one numeric literal.
    settings_macros = {}
    settings_text = read(PACK / "lib" / "settings.glsl")
    for m in re.finditer(r"^\s*#define\s+([A-Z][A-Z0-9_]*)\s+([^\s/]+)",
                         settings_text, flags=re.M):
        settings_macros[m.group(1)] = m.group(2)
    engine_consts = 0
    for p in shader_files:
        body = strip_comments(read(p))
        for m in re.finditer(r"\bconst\s+(bool|int|float|vec4)\s+(\w+)\s*=\s*([^;]+);", body):
            ctype, name, value = m.groups()
            if name not in ENGINE_CONST_NAMES and not name.endswith("ClearColor"):
                continue
            engine_consts += 1
            value = settings_macros.get(value.strip(), value.strip())
            if ctype == "bool":
                valid = value in ("true", "false")
            elif ctype in ("int", "float"):
                valid = _numeric_literal(value)
            else:
                vm = re.fullmatch(r"vec4\s*\((.*)\)", value)
                args = [x.strip() for x in vm.group(1).split(",")] if vm else []
                valid = len(args) == 4 and all(_numeric_literal(x) for x in args)
            if not valid:
                c.fail(f"{pk(p)}: engine const {name} must use literal initializer, got '{value}'")

    # SC-27 (revised 2026-09-10): the blanket "no active *Format const" rule was a
    # misdiagnosis. Bliss, Complementary Reimagined and Complementary Unbound all
    # declare "const int colortex<N>Format = <token>;" and load on Iris 1.11.2, so the
    # contract is: recognised buffer name, integer literal or upper-case token value,
    # and exactly one declaration per buffer.
    format_decls = {}
    for p in shader_files:
        body = strip_comments(read(p))
        for m in re.finditer(
                r"\bconst\s+int\s+((?:colortex|shadowcolor|depthtex)\d+Format)\s*=\s*([^;]+);", body):
            name, value = m.group(1), m.group(2).strip()
            format_decls.setdefault(name, []).append((pk(p), value))
    for name, decls in sorted(format_decls.items()):
        if len(decls) > 1:
            c.fail(f"{name} declared {len(decls)} times: "
                   + ", ".join(f"{where}={value}" for where, value in decls))
        for where, value in decls:
            if not re.fullmatch(r"\d+|[A-Z][A-Z0-9_]*", value):
                c.fail(f"{where}: {name} must be an integer literal or an upper-case "
                       f"token macro, got '{value}'")
            elif (value[0].isalpha() and value not in settings_macros
                  and value not in ENGINE_FORMAT_TOKENS):
                c.warn(f"{where}: {name} uses token '{value}', which no lib/settings.glsl "
                       f"macro defines (Iris resolves it to a buffer format)")

    # SC-26: when Voxy activates #ifdef VOXY, every vx* symbol used by shader code
    # must have a declaration in the shared uniform layer.
    uniform_path = PACK / "lib" / "uniforms.glsl"
    uniform_body = strip_comments(read(uniform_path))
    declared_vx = set(re.findall(r"\buniform\s+\w+\s+(vx[A-Z]\w*)\s*;", uniform_body))
    used_vx = set()
    for p in shader_files:
        body = strip_comments(read(p))
        body = re.sub(r"\buniform\s+\w+\s+vx[A-Z]\w*\s*;", " ", body)
        used_vx |= set(re.findall(r"\b(vx[A-Z]\w*)\b", body))
    missing_vx = sorted(used_vx - declared_vx)
    if missing_vx:
        c.fail("Voxy symbol(s) used without lib/uniforms.glsl declaration: "
               + ", ".join(missing_vx))

    # SC-28 (revised 2026-09-20 with bytecode from iris-fabric-1.11.2): a boolean option
    # enters the option set only if some graph file references it with #ifdef or #ifndef.
    # OptionAnnotatedSource.parseLine routes only those two prefixes into parseIfdef, which
    # fills booleanDefineReferences; ShaderPackOptions unions those names across files and
    # passes them to getOptionSet(path, names), which filters the declarations down to it.
    # defined() is never parsed, so "#if defined OPT" does NOT make an option discoverable -
    # the loader has no row for it, the profile token cannot change it, and the #define line
    # is left as authored. String options skip the filter entirely (getOptionSet passes no
    # name set for them). "#if defined OPT" is still correct GLSL once the option is
    # discovered, because the option value lands in the #define line, not in the guard.
    boolean_options = {}
    for m in re.finditer(r"^\s*(//?)?\s*#define\s+([A-Z][A-Z0-9_]*)\s*(//[^\n]*)?",
                         settings_text, flags=re.M):
        name, tail = m.group(2), m.group(3) or ""
        if re.search(r"\[\s*(?:false true|true false)\s*\]", tail):
            boolean_options[name] = m.group(1) != "//"
    references = {}
    defined_only = {}
    for p in shader_files:
        if Path(p).name == "settings.glsl":
            continue
        body = strip_comments(read(p))
        for m in re.finditer(r"^\s*#if(?:def|ndef)\s+([A-Z][A-Z0-9_]*)", body, flags=re.M):
            references.setdefault(m.group(1), set()).add(pk(p))
        for m in re.finditer(r"\bdefined\s+([A-Z][A-Z0-9_]*)", body):
            defined_only.setdefault(m.group(1), set()).add(pk(p))
    for name in sorted(boolean_options):
        if name in references:
            continue
        sites = sorted(m for m in defined_only.get(name, ()))
        c.fail(f"boolean option {name} is only referenced through defined() "
               f"{'/'.join(sites) + ' - ' if sites else ''}with no #ifdef/#ifndef site, so "
               f"Iris never discovers it: no GUI row and its profile token is inert (SC-28)")

    # SC-29: Iris rejects a pack that uses iris custom images without declaring the
    # CUSTOM_IMAGES feature flag (ShaderPack throws IllegalStateException at load time),
    # silently ignores custom images past its cap, and ignores malformed image fields.
    # Verified directive order against iris.jar ShaderProperties:
    #   image.<name>=<samplerName> <format> <internalFormat> <type> <clear> <relative> <w> <h> [d]
    # The texture target is derived from the dimension count, not written out.
    IMAGE_PIXEL_FORMATS = {
        "red", "rg", "rgb", "bgr", "rgba", "bgra",
        "red_integer", "rg_integer", "rgb_integer", "bgr_integer",
        "rgba_integer", "bgra_integer",
    }
    IMAGE_INTERNAL_FORMATS = {
        "rgba", "r8", "rg8", "rgb8", "rgba8", "r8_snorm", "rg8_snorm", "rgb8_snorm",
        "rgba8_snorm", "r16", "rg16", "rgb16", "rgba16", "r16_snorm", "rg16_snorm",
        "rgb16_snorm", "rgba16_snorm", "r16f", "rg16f", "rgb16f", "rgba16f", "r32f",
        "rg32f", "rgb32f", "rgba32f", "r8i", "rg8i", "rgb8i", "rgba8i", "r8ui",
        "rg8ui", "rgb8ui", "rgba8ui", "r16i", "rg16i", "rgb16i", "rgba16i", "r16ui",
        "rg16ui", "rgb16ui", "rgba16ui", "r32i", "rg32i", "rgb32i", "rgba32i",
        "r32ui", "rg32ui", "rgb32ui", "rgba32ui", "rgba2", "rgba4", "r3_g3_b2",
        "rgb5_a1", "rgb565", "rgb10_a2", "rgb10_a2ui", "r11f_g11f_b10f", "rgb9_e5",
    }
    IMAGE_PIXEL_TYPES = {
        "byte", "short", "int", "half_float", "float", "unsigned_byte",
        "unsigned_byte_3_3_2", "unsigned_byte_2_3_3_rev", "unsigned_short",
        "unsigned_short_5_6_5", "unsigned_short_5_6_5_rev", "unsigned_short_4_4_4_4",
        "unsigned_short_4_4_4_4_rev", "unsigned_short_5_5_5_1",
        "unsigned_short_1_5_5_5_rev", "unsigned_int", "unsigned_int_8_8_8_8",
        "unsigned_int_8_8_8_8_rev", "unsigned_int_10_10_10_2",
        "unsigned_int_2_10_10_10_rev", "unsigned_int_10f_11f_11f_rev",
        "unsigned_int_5_9_9_9_rev",
    }
    INTEGER_INTERNALS = tuple(
        name for name in IMAGE_INTERNAL_FORMATS if name.endswith(("i", "ui"))
    )
    image_directives = []
    feature_required, feature_optional = [], []
    for lineno, line in enumerate(logical_lines(properties_text), 1):
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key.startswith("image."):
            image_directives.append((lineno, key, value))
        elif key == "iris.features.required":
            feature_required += value.split()
        elif key == "iris.features.optional":
            feature_optional += value.split()
    if image_directives:
        declared = set(feature_required) | set(feature_optional)
        if "CUSTOM_IMAGES" not in declared:
            c.fail("image.* directives need iris.features.required/optional=CUSTOM_IMAGES "
                   "(Iris throws IllegalStateException otherwise)")
        if len(image_directives) > 15:
            c.fail(f"{len(image_directives)} custom images declared; Iris 1.11.2 caps them at 15")
        for lineno, key, value in image_directives:
            name = key[len("image."):]
            fields = value.split()
            if not name:
                c.fail(f"shaders.properties logical line {lineno}: image. has no name")
                continue
            if len(fields) < 8:
                c.fail(f"image.{name}: needs '<sampler> <format> <internalFormat> <type> "
                       f"<clear> <relative> <w> <h> [d]', got {len(fields)} field(s)")
                continue
            sampler = fields[0]
            pixel_format = fields[1].lower()
            internal = fields[2].lower()
            pixel_type = fields[3].lower()
            if pixel_format not in IMAGE_PIXEL_FORMATS:
                c.fail(f"image.{name}: pixel format '{pixel_format}' is unknown to Iris")
            if internal not in IMAGE_INTERNAL_FORMATS:
                c.fail(f"image.{name}: internal format '{internal}' is unknown to Iris")
            if pixel_type not in IMAGE_PIXEL_TYPES:
                c.fail(f"image.{name}: pixel type '{pixel_type}' is unknown to Iris")
            for flag in fields[4:6]:
                if flag not in ("true", "false"):
                    c.fail(f"image.{name}: clear/relative flags must be true or false, got '{flag}'")
            dims = fields[6:]
            for dim in dims:
                if not dim.isdigit() or int(dim) < 1:
                    c.fail(f"image.{name}: dimension '{dim}' is not a positive integer")
            target = {1: "texture1D", 2: "texture2D", 3: "texture3D"}.get(len(dims))
            if target is None:
                c.fail(f"image.{name}: {len(dims)} dimension(s); Iris supports 1, 2 or 3")
                continue
            # 3D images that back a usampler3D need a uint internal format and an
            # integer pixel type, otherwise every texelFetch in the compute/compute
            # consumers is a type mismatch on real drivers.
            integer_format = pixel_format.endswith("_integer")
            integer_internal = internal.endswith(("i", "ui"))
            if integer_format != integer_internal:
                c.fail(f"image.{name}: pixel format '{pixel_format}' and internal format "
                       f"'{internal}' disagree on integer-ness")
            if integer_format and pixel_type not in ("unsigned_int", "int", "unsigned_short",
                                                     "short", "unsigned_byte", "byte"):
                c.fail(f"image.{name}: integer image needs an integer pixel type, got '{pixel_type}'")
            if not integer_format and pixel_type in ("unsigned_int", "int"):
                c.fail(f"image.{name}: float image with integer pixel type '{pixel_type}'")
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", sampler):
                c.fail(f"image.{name}: sampler name '{fields[0]}' is not a GLSL identifier")
            # The sampler must appear in a shader, otherwise the image is dead weight.
            users = [q for q in walk_shader_files()
                     if q.suffix in (".vsh", ".fsh", ".csh")
                     and re.search(r"\b" + re.escape(sampler) + r"\b", strip_comments(read(q)))]
            if not users:
                c.warn(f"image.{name}: sampler '{sampler}' is declared but never referenced by a shader")

    # SC-30: compute shaders live at <stage>/<name>.csh; Iris reads the ShadowComposite,
    # Setup and Final stages, so a stray .csh is dead weight no compile step would catch.
    # Include-only helpers (program/*.csh) are fine when a stage file includes them.
    # A stage with no program.<name>.enabled condition cannot be switched off from
    # shaders.properties, so it always burns GPU time. The name Iris compares carries the
    # world folder for a dimension stage; "compute.<stage>.<name>.enabled" is not parsed by
    # any Iris handler at all (P2-18), so gating through it does nothing.
    compute_dir = {"shadowcomp", "setup", "final"}
    compute_files = sorted(PACK.rglob("*.csh"))
    gated_programs = set()
    for line in logical_lines(properties_text):
        if not line.startswith("program.") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key.endswith(".enabled") and value:
            gated_programs.add(key[len("program."):-len(".enabled")])
    for path in compute_files:
        parts = path.relative_to(PACK).parts
        stem = path.stem
        base = re.match(r"([a-z]+)", stem)
        if base and base.group(1) in compute_dir and not re.fullmatch(
                re.escape(base.group(1)) + r"[A-Z]?", stem):
            c.fail(f"{pk(path)}: compute stages are '<name>' plus '<name>A'..'<name>Z'; "
                   f"'{stem}' is never loaded by Iris (upper-case single letter suffix)")
        if len(parts) >= 2 and parts[-2] in ("program", "lib", "global"):
            # Include-only module (e.g. program/nether_light.csh pulled in by the
            # world-1/shadowcompN.csh wrappers); only require that something includes it.
            included = any(
                path.name in strip_comments(read(other))
                for other in compute_files if other is not path
            )
            if not included:
                c.warn(f"{pk(path)}: include-only compute module that no other compute "
                       f"shader includes")
            continue
        is_stage_file = (len(parts) in (1, 2)) and base and base.group(1) in compute_dir
        if not is_stage_file:
            c.fail(f"{pk(path)}: '{stem}' is not a compute stage Iris loads "
                   f"(expected {', '.join(sorted(compute_dir))})")
            continue
        stage_key = stem if len(parts) == 1 else f"{parts[0]}/{stem}"
        if stage_key not in gated_programs:
            c.warn(f"{pk(path)}: no program.{stage_key}.enabled condition; the whole stage "
                   f"is built and dispatched unconditionally")
    if compute_files and "COMPUTE_SHADERS" not in set(feature_required) | set(feature_optional):
        c.warn("compute shaders present but no iris.features.*=COMPUTE_SHADERS declaration")

    # SC-31: MC_RENDER_STAGE_* spellings must match the Iris WorldRenderingPhase names
    # exactly; a typo only compiles away if the macro is undefined, and an undefined
    # macro in a renderStage comparison is a hard compile error on Iris.
    known_stages = {
        "MC_RENDER_STAGE_" + name for name in getattr(compile_glsl, "RENDER_STAGES", ())
    }
    if known_stages:
        for p in shader_files:
            body = strip_comments(read(p))
            for m in re.finditer(r"\bMC_RENDER_STAGE_[A-Z0-9_]*", body):
                if m.group(0) not in known_stages:
                    c.fail(f"{pk(p)}: {m.group(0)} is not an Iris 1.11.2 render stage "
                           f"(see qa/tools/compile_glsl.py RENDER_STAGES)")

    c.note(f"{texture_count} staged texture directive(s); {len(image_directives)} custom image(s); "
           f"{len(compute_files)} compute shader(s); {engine_consts} engine const(s); "
           f"{len(declared_vx)} Voxy uniform declaration(s); Iris default buffer formats; "
           f"{len(references)}/{len(boolean_options)} boolean option(s) wired")
    return c


# ------------------------------------------------------- tier differential

TIER_ORDER = ("PERFORMANCE", "BALANCED", "ULTRA")

# Numeric knobs whose value must not step down along PERFORMANCE -> ULTRA, because the
# larger number is more work or a richer implementation (SHADOW_SOFTNESS widens the PCF
# footprint; SUN_MOON_MODE 1 draws procedural discs instead of the vanilla texture).
# ANTIALIASING: 0 off, 1 FXAA (extra final pass + full-resolution colortex13), 2 TAA
# (FXAA machinery plus jitter, HDR history buffers and reprojection) - profiles read
# 0/1/1 along PERFORMANCE -> BALANCED -> ULTRA, monotone up (TAA is opt-in per docs).
TIER_MONOTONE_UP = {
    "SHADOW_RESOLUTION", "SHADOW_DISTANCE", "ENTITY_SHADOW_DISTANCE", "SHADOW_SOFTNESS",
    "UNDERWATER_SHAFT_SAMPLES", "CLOUD_MODE", "SUN_MOON_MODE", "ANTIALIASING",
    "SHADOW_FILTER_QUALITY", "CLOUD_QUALITY", "VOLUME_FOG_QUALITY",
}
# Knobs where the smaller number is the richer implementation, so the value must not
# step up: SKY_MODE 0 = Minishita physical atmosphere, 1 = gradient
# (global/dimension/overworld.glsl:11).
TIER_MONOTONE_DOWN = {"SKY_MODE"}
# Tiered on purpose but decoupled from cost - reported, never asserted.
TIER_NONCOST = {"END_PRECESSION_MINUTES"}


def _profile_values():
    """profile name -> {option: 'on' | 'off' | numeric value as written}"""
    props, _ = parse_properties()
    out = {}
    for key, vals in props.items():
        if not key.startswith("profile."):
            continue
        toks = []
        for v in vals:
            toks += v.split()
        d = {}
        for t in toks:
            if t.startswith("!"):
                d[t[1:]] = "off"
            elif "=" in t:
                name, raw = t.split("=", 1)
                d[name] = {"true": "on", "false": "off"}.get(raw, raw)
            else:
                d[t] = "on"
        out[key.split(".", 1)[1]] = d
    return out


def check_tier_differential(opts):
    c = Check(12, "profile tier differential (survey 6 P0-1: cost-monotone ladder)")
    prof = _profile_values()
    absent = [t for t in TIER_ORDER if t not in prof]
    if absent:
        c.fail("missing profile(s): " + ", ".join(absent))
        return c
    keys = sorted(quality_option_names(opts))

    # BALANCED is the shipping default and the benchmark anchor: every one of its values
    # must equal the settings.glsl raw default, or the pack stops being reproducible
    # from source and "raw defaults = BALANCED" becomes a comment nobody checks.
    drift = []
    for name in keys:
        meta = opts.get(name) or {}
        if meta.get("bool"):
            disabled = meta.get("commented") or (
                meta.get("const_type") == "bool" and meta.get("value") == "false")
            want = "off" if disabled else "on"
        else:
            want = meta.get("value")
        got = prof["BALANCED"].get(name)
        if want is None:
            drift.append(f"{name}: no raw default in settings.glsl")
        elif str(want) != got:
            drift.append(f"{name}: profile {got} != default {want}")
    if drift:
        c.fail("profile.BALANCED diverges from the settings.glsl defaults: "
               + "; ".join(drift))

    missing = [f"{tier}.{name}" for tier in TIER_ORDER for name in keys
               if name not in prof[tier]]
    if missing:
        c.fail("quality tiers omit registered options: " + ", ".join(missing))
        return c

    # Compare values: matching option names alone says nothing about tier cost.
    for a, b in [("PERFORMANCE", "BALANCED"), ("BALANCED", "ULTRA"),
                 ("PERFORMANCE", "ULTRA")]:
        diff = [k for k in keys if prof[a][k] != prof[b][k]]
        c.note(f"{a} vs {b}: {len(diff)} value diff(s), density "
               f"{len(diff)}/{len(keys)} = {len(diff) / max(len(keys), 1):.0%}")
    varying = {k for k in keys if len({prof[t][k] for t in TIER_ORDER}) > 1}
    unclassified = sorted(
        varying - TIER_MONOTONE_UP - TIER_MONOTONE_DOWN - TIER_NONCOST
        - {k for k in varying if (opts.get(k) or {}).get("bool")}
    )
    if unclassified:
        c.fail("tier-varying numeric knob(s) with no cost classification: "
               + ", ".join(unclassified)
               + " - add to TIER_MONOTONE_UP/DOWN, or to TIER_NONCOST with a reason")

    def num(tier, name):
        try:
            return float(prof[tier][name])
        except (TypeError, ValueError):
            return None

    for name in sorted(varying & TIER_MONOTONE_UP):
        vals = [num(t, name) for t in TIER_ORDER]
        if any(v is None for v in vals):
            c.fail(f"{name}: tiered but non-numeric somewhere: {vals}")
        elif any(b < a for a, b in zip(vals, vals[1:])):
            c.fail(f"{name}: cost ladder steps down towards ULTRA: "
                   f"{dict(zip(TIER_ORDER, vals))}")
    for name in sorted(varying & TIER_MONOTONE_DOWN):
        vals = [num(t, name) for t in TIER_ORDER]
        if any(v is None for v in vals):
            c.fail(f"{name}: tiered but non-numeric somewhere: {vals}")
        elif any(b > a for a, b in zip(vals, vals[1:])):
            c.fail(f"{name}: richness ladder steps up towards ULTRA: "
                   f"{dict(zip(TIER_ORDER, vals))}")

    # A boolean on is more work, so the on-sets must grow along the ladder.
    bools = [k for k in keys if (opts.get(k) or {}).get("bool")]
    for a, b in zip(TIER_ORDER, TIER_ORDER[1:]):
        back = [k for k in bools if prof[a][k] == "on" and prof[b][k] != "on"]
        if back:
            c.fail(f"{b} drops boolean(s) that {a} enables: " + ", ".join(back)
                   + " - the richer tier must be a superset, or the knob belongs in "
                     "TIER_NONCOST with a reason")
    c.note(f"{len(varying)} of {len(keys)} listed tokens vary across tiers; non-cost by "
           f"design: {', '.join(sorted(varying & TIER_NONCOST)) or 'none'}")
    c.note("resolved per-tier pass and buffer sets: qa/tools/inspect_iris_properties.py")
    return c


# Names the pack deliberately tests without defining. check 13 fails on any name that
# appears in an #ifdef/#ifndef but in no #define, so these need a reason on file - and
# the reason is checked too: it becomes a failure the moment the pack defines the name.
GUARD_SYMBOL_SOURCES = {
    "ASTRA_VOXY_PASS": "the Voxy integration branch in lib/transforms.glsl and "
                       "lib/uniforms.glsl; program/lit_voxy.fsh is still the C5 stub, so "
                       "the branch is false by design until that task wires it",
    "EXTERNALLY_DEFINED_UNIFORMS": "lib/uniforms.glsl's own include guard. Absent from the "
                                   "installed iris.jar (qa/tools/inspect_iris_properties.py), "
                                   "so it is always true and hides no code",
    "ASTRA_WATER_TEMPORAL": "guards the retired water hit-radiance history module "
                            "global/water/temporal.glsl (2026-09-28). The branch is false "
                            "by design until a composite-stage producer task lands; the "
                            "module is registered in PENDING_CONSUMERS, see "
                            "docs/2026-09-28-water-material-lighting.md",
}

# settings.glsl enum tokens that name the arm no branch ever tests: the code checks one
# value and lets the rest fall through, so these constants document a value instead of
# selecting one. check 13 still requires each to be a real value of its option.
ENUM_ARM_TOKENS = {
    "SHADOW_FILTER_SOFTWARE": ("SHADOW_FILTER_MODE", "lib/settings.glsl tests SHADOW_FILTER_HARDWARE"),
    "SKY_MINISHITA": ("SKY_MODE", "global/dimension/overworld.glsl tests SKY_GRADIENT"),
    "SUN_MOON_DISCS": ("SUN_MOON_MODE", "program/sky.fsh tests SUN_MOON_VANILLA"),
    "WATER_BALANCED": ("WATER_CHARACTER", "global/water/absorption.glsl tests COLD and TROPICAL"),
}


def check_option_consumers():
    """Survey 6 P2-12: an option nobody reads and a branch on a name nobody defines are
    both invisible defects, and no reference pack studied there had a habit of catching
    either. This is the static half of the matrix; compile_glsl.py --matrix is the half
    that proves every surviving combination still compiles."""
    c = Check(13, "option consumers and branch symbols (survey 6 P2-12 option matrix)")
    space = option_matrix.option_space(PACK)
    opts = space["options"]
    rows, uncovered = option_matrix.covering_array(space)
    c.note(f"{len(opts)} option(s), {len(space['factors'])} of which can flip a "
           f"preprocessor branch; pairwise matrix = {len(rows)} row(s), "
           f"python qa/tools/compile_glsl.py --matrix")
    if uncovered:
        c.fail(f"covering array did not close: {len(uncovered)} factor-value pair(s) "
               f"received no row even with no row limit")
    if space["unused_options"]:
        c.fail("option(s) offered in the GUI but read by nothing (the JCL KILL_SWITCH "
               "failure): " + ", ".join(space["unused_options"]))

    settings_text = read(PACK / "lib" / "settings.glsl")
    for name, files in sorted(space["undeclared_guards"].items()):
        if name in ENGINE_FORMAT_TOKENS or name in GUARD_SYMBOL_SOURCES:
            continue
        c.fail(f"#ifdef/#ifndef {name} in {', '.join(files)}: nothing in the pack or the "
               f"engine ever defines it, so the branch is permanently false. Define it, "
               f"delete the branch, or add it to GUARD_SYMBOL_SOURCES with a reason")
    for name in GUARD_SYMBOL_SOURCES:
        if name not in space["undeclared_guards"] and name not in ENGINE_FORMAT_TOKENS:
            c.fail(f"GUARD_SYMBOL_SOURCES lists {name}, but the pack now defines it - "
                   f"the exemption is stale, remove it")

    for name, files in sorted(space["unread_macros"].items()):
        if name in ENUM_ARM_TOKENS:
            option, reason = ENUM_ARM_TOKENS[name]
            declared = re.search(r"^[ \t]*#define[ \t]+" + name + r"[ \t]+(\S+)",
                                 settings_text, re.M)
            if not declared:
                c.fail(f"{name}: exempted as the untested arm of {option}, but it is no "
                       f"longer defined in lib/settings.glsl")
                continue
            levels = (opts.get(option) or {}).get("levels") or []
            if not levels:
                c.fail(f"{name}: exempted as the untested arm of {option}, but {option} is "
                       f"no longer an option with a value list - the exemption is stale")
                continue
            try:
                in_range = float(declared.group(1)) in [float(v) for v in levels]
            except ValueError:
                in_range = False
            if not in_range:
                c.fail(f"{name}: value {declared.group(1)} is no longer one of "
                       f"{option}'s {levels} - the exemption reason is stale ({reason})")
            continue
        c.fail(f"#define {name} in {', '.join(files)} has no reader anywhere (comments "
               f"included): the code path it documents no longer exists. Delete it or "
               f"restore the branch")

    # Both tools parse settings.glsl; if they stop agreeing, every count in this report
    # is describing a different option set than the GUI check is validating.
    theirs = set(parse_settings())
    if theirs != set(opts):
        only_mine = sorted(set(opts) - theirs)
        only_theirs = sorted(theirs - set(opts))
        c.fail("check_pack.parse_settings and option_matrix.parse_options disagree about "
               f"the option set: only in option_matrix: {', '.join(only_mine) or '-'}; "
               f"only in check_pack: {', '.join(only_theirs) or '-'}")
    return c


# --------------------------------------------------- buffer declarations (survey P2-11)

ENGINE_DECL = re.compile(r"\bconst\s+(bool|int|float|vec4)\s+(\w+)\s*=\s*([^;]*);")
BUFFER_KNOB = re.compile(r"^\w+(?:Format|Clear(?:Color|Alpha|Depth)?)$")
BUFFER_BASE = re.compile(r"^(colortex\d+|shadowcolor\d+|depthtex\d+)"
                         r"(?:Format|Clear(?:Color|Alpha|Depth)?)?$")


def _is_engine_decl(name):
    """Names Iris parses out of the shader source rather than from the preprocessor: the
    buffer format/clear knobs plus the shadow and noise scalars (SC-23, SC-27)."""
    return bool(BUFFER_KNOB.match(name)) or name in ENGINE_CONST_NAMES


def _comment_spans(text):
    """Offsets of every comment. strip_comments() replaces comments with spaces, so a
    declaration wrapped in /* */ matches exactly as well as a live one - which is why the
    VanillaPlus / Sildur's / Bloop buffer-declaration rot survives every other check here."""
    spans, i, n = [], 0, len(text)
    while i < n:
        pair = text[i:i + 2]
        if pair == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
        elif pair == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
        else:
            i += 1
            continue
        spans.append((i, j))
        i = j
    return spans


def check_buffer_declarations():
    """Survey 6 P2-11. Astra already keeps each buffer's format next to its consumer; this
    is the anti-degradation gate for the failure three reference packs shipped with -
    declarations that exist only as text. Two rules: a declaration inside a comment never
    happened, and a buffer whose format or clear colour is declared but never referenced
    is a buffer Iris allocates and clears every frame for no reader."""
    c = Check(14, "buffer declarations live, unique and consumed (survey 6 P2-11)")
    shader_files = list(walk_shader_files())

    live, commented = {}, []
    for p in shader_files:
        text = read(p)
        spans = _comment_spans(text)
        for m in ENGINE_DECL.finditer(text):
            name, value = m.group(2), m.group(3).strip()
            if not _is_engine_decl(name):
                continue
            where = f"{pk(p)}:{text.count(chr(10), 0, m.start()) + 1}"
            if any(start <= m.start() < end for start, end in spans):
                commented.append((where, name, value))
            else:
                live.setdefault(name, []).append((where, value))

    for where, name, value in commented:
        c.fail(f"{where}: const {name} = {value} sits inside a comment, so Iris never parses "
               f"it and the buffer keeps its engine default - delete the line or uncomment it "
               f"(the VanillaPlus lib/pipeline.glsl failure mode, survey 6 P2-11)")

    # One declaration per name. The *Format knobs are already uniqueness-checked by check
    # 11 (SC-27); the clear knobs are not, and a duplicate there is the same silent loss.
    for name, decls in sorted(live.items()):
        if re.search(r"Clear(?:Color|Alpha|Depth)?$", name) and len(decls) > 1:
            c.fail(f"{name} declared {len(decls)} times: "
                   + ", ".join(f"{where}={value}" for where, value in decls))

    # The declaration statement mentions its own buffer name, so it cannot be its consumer.
    code = {p: ENGINE_DECL.sub(
        lambda m: " " * len(m.group(0)) if _is_engine_decl(m.group(2)) else m.group(0),
        strip_comments(read(p))) for p in shader_files}
    buffers = {}
    for name, decls in live.items():
        base = BUFFER_BASE.match(name)
        if base:
            buffers.setdefault(base.group(1), set()).update(where for where, _ in decls)
    consumed = {}
    for buf in sorted(buffers):
        readers = [pk(p) for p in shader_files if re.search(r"\b" + buf + r"\b", code[p])]
        if not readers:
            c.fail(f"{buf}: declared at {', '.join(sorted(buffers[buf]))} but referenced by "
                   f"nothing in the pack - drop the declaration or wire the consumer")
        else:
            consumed[buf] = readers
    c.note(f"{sum(len(v) for v in live.values())} live engine declaration(s) covering "
           f"{len(consumed)} buffer(s): "
           + ", ".join(f"{b}={len(r)}" for b, r in sorted(consumed.items()))
           + f"; {len(commented)} declaration(s) hidden in comments")
    return c


# ------------------------------------------------------- vendor isolation (survey P2-10)

VENDOR = PACK / "lib" / "vendor"

# The paragraphs that belong once in a licence file and never in a per-file header: survey 2
# counted the alternative - VanillaPlus repeats its header 224x (4,384 lines = 38.5% of the
# pack), Sildur's 109x (8.2%), LIGHT 72x (11.3%).
LICENCE_BODIES = (
    "Permission is hereby granted, free of charge",       # MIT / X11
    "Redistribution and use in source and binary forms",  # BSD / GPLv2 clause 1
    "GNU GENERAL PUBLIC LICENSE",                         # GPL full text
)


def check_vendor_isolation():
    """Survey 6 P2-10. Upstream code, its raw licence text and its registration row in one
    physically isolated directory - the landing spot for the MIT reuse list (P2-13, T16)."""
    c = Check(15, "lib/vendor/ isolation and no multiplied licence text (survey 6 P2-10)")
    led = ROOT / "Astra" / "THIRD-PARTY.md"
    if not led.exists():
        c.fail("Astra/THIRD-PARTY.md missing (check 8 owns its content, this one its paths)")
        return c
    ledger = read(led).replace("`", "")

    def registered(path):
        return path in ledger or ("shaders/" + path) in ledger

    if not VENDOR.is_dir():
        c.fail("shaders/lib/vendor/ missing - design 9.2 and survey P2-10 keep every "
               "third-party file and its licence in one isolated directory per upstream")
        return c
    if not (VENDOR / "README.md").exists():
        c.fail("shaders/lib/vendor/README.md missing: a convention nobody can read next to "
               "the directory it governs is not a convention")

    files = sorted(p for p in VENDOR.rglob("*") if p.is_file())
    for p in files:
        path = pk(p)
        # A directory's own README is Astra text registered by its directory row; every
        # upstream file - licence or source - has to be registered under its own path.
        if p.name == "README.md" and registered(pk(p.parent)):
            continue
        if not registered(path):
            c.fail(f"{path}: inside lib/vendor/ but absent from Astra/THIRD-PARTY.md - "
                   f"register the path, the upstream source file and the licence (design 9.2)")

    for d in sorted(p for p in VENDOR.iterdir() if p.is_dir()):
        names = [x.name.lower() for x in d.iterdir() if x.is_file()]
        if not any(n.startswith(("license", "licence", "copying")) for n in names):
            c.fail(f"{pk(d)}/: upstream code with no licence text beside it. Copy the upstream "
                   f"licence, or write out the standard text when its archive ships none "
                   f"(survey P2-13) - either way it lives here, not in a per-file comment")

    strays = []
    for p in walk_shader_files():
        if VENDOR in p.parents:
            continue
        hits = [b for b in LICENCE_BODIES if b in read(p)]
        if hits:
            strays.append((pk(p), hits))
    for path, hits in strays:
        c.fail(f"{path}: carries licence text ({'; '.join(hits)}) outside lib/vendor/. Keep "
               f"one copy in the upstream's vendor directory; a per-file licence header is "
               f"the VanillaPlus failure mode (4,384 of 11,373 lines)")

    dirs = sorted(pk(p) for p in VENDOR.iterdir() if p.is_dir())
    c.note(f"lib/vendor/ exists: {len(dirs)} upstream directory(ies) "
           f"({', '.join(dirs) or 'none yet - T16 fills it'}), {len(files)} file(s), "
           f"{len(strays)} file(s) carrying licence text outside it")
    return c


# ------------------------------------------------------- dimension gating

# Iris 1.11.2 takes a "<world>/" namespace on exactly one directive family: program.
# Everything else is stored under the key text as written and looked up by a bare name -
# ShaderProperties resolves blend overrides with blendModeOverrides.get(ProgramSource
# .getName()) and PackDirectives with scaleOverrides.containsKey(<buffer>) - so a
# namespaced blend./size./texture./image./uniform. key can never match a program, and
# several of them make Iris's own properties parser throw. program.* is the exception
# because ShaderPack derives the disabled-program name from the path text, world folder
# included. Measured on iris-fabric-1.11.2+mc26.2 (survey P2-18, 2026-09-20).
WORLD_FOLDER = re.compile(r"world-?\d+")
NAMESPACED_KEY = re.compile(r"^(?P<family>[A-Za-z.]+?)\.(?P<folder>world-?\d+)/")
PROPERTIES_IF = re.compile(r"^#if(def|ndef)?\s+\S")
OPTION_IDENTS = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")


def check_dimension_gating():
    c = Check(16, "per-dimension pipeline trimming uses keys Iris parses (survey P2-18)")
    folders = sorted(p.name for p in PACK.iterdir()
                     if p.is_dir() and WORLD_FOLDER.fullmatch(p.name))
    if not folders:
        c.note("no dimension folders in the pack - nothing to gate per dimension")
        return c

    def pass_stems(folder=None):
        base = PACK if folder is None else PACK / folder
        return {p.stem for p in base.iterdir()
                if p.is_file() and p.suffix in (".vsh", ".fsh", ".csh")}

    root_passes = pass_stems()
    folder_passes = {f: pass_stems(f) for f in folders}

    gates = {}                 # program name -> [(lineno, value, enclosing option names)]
    dead_namespaced = []
    branch_stack = []          # identifiers the enclosing #if/#ifdef tests positively
    _, properties_text = parse_properties()
    for lineno, line in enumerate(logical_lines(properties_text), 1):
        if PROPERTIES_IF.match(line):
            head = line.split()[0]
            idents = set() if head == "#ifndef" else {
                x for x in OPTION_IDENTS.findall(line) if x != "DEFINED"}
            branch_stack.append(idents)
            continue
        if line.startswith("#else"):
            branch_stack[-1:] = [set()]
            continue
        if line.startswith("#endif"):
            if branch_stack:
                branch_stack.pop()
            continue
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        match = NAMESPACED_KEY.match(key)
        if match and match.group("family") != "program":
            dead_namespaced.append((lineno, key))
        if key.startswith("program.") and key.endswith(".enabled"):
            enclosing = set().union(*branch_stack) if branch_stack else set()
            gates.setdefault(key[len("program."):-len(".enabled")], []).append(
                (lineno, value, enclosing))

    for lineno, key in dead_namespaced:
        c.fail(f"shaders.properties:{lineno}: {key} - only program.* accepts a <world>/ "
               f"namespace, so Iris never looks this key up; per-dimension behaviour has to "
               f"come from the shader sources")

    root_gates = {n: v for n, v in gates.items() if "/" not in n}
    folder_gates = {n: v for n, v in gates.items() if "/" in n}
    inherited = []
    for name, entries in sorted(folder_gates.items()):
        folder, _, stem = name.partition("/")
        if folder not in folder_passes:
            c.fail(f"shaders.properties:{entries[0][0]}: program.{name}.enabled names the "
                   f"unknown dimension folder {folder}/")
            continue
        if stem not in folder_passes[folder] | root_passes:
            c.fail(f"shaders.properties:{entries[0][0]}: program.{name}.enabled gates a pass "
                   f"that exists in neither {folder}/ nor the pack root")
        elif stem not in folder_passes[folder]:
            inherited.append(name)

    for name, entries in sorted(root_gates.items()):
        conditional = [v for _, v, _ in entries if v not in ("true",)]
        if not conditional:
            continue
        for folder in folders:
            if name not in folder_passes[folder]:
                continue
            if f"{folder}/{name}" not in folder_gates:
                c.fail(f"{folder}/{name}: the root gate program.{name}.enabled="
                       f"{'/'.join(conditional)} does not reach this folder - Iris matches "
                       f"the folder-qualified name, so the pass runs unconditionally here")

    for name, entries in sorted(gates.items()):
        for lineno, value, enclosing in entries:
            hidden = enclosing & set(OPTION_IDENTS.findall(value))
            if hidden:
                c.fail(f"shaders.properties:{lineno}: program.{name}.enabled={value} sits "
                       f"inside a {'/'.join(sorted(hidden))} branch, so the gate disappears "
                       f"exactly when the pass needs switching off")

    c.note(f"dimension folders {', '.join(folders)}; {len(gates)} program gate(s) "
           f"({len(folder_gates)} folder-qualified), {len(dead_namespaced)} inert "
           f"namespaced directive(s)")
    if inherited:
        off = [n for n in inherited if all(v == "false" for _, v, _ in folder_gates[n])]
        c.note(f"{len(inherited)} folder gate(s) whose pass file exists only at the pack root "
               f"({', '.join(sorted(inherited))}): redundant if a dimension folder drops a pass "
               f"it does not ship, load-bearing if Iris inherits the root source instead - "
               f"{len(off)} of them read a literal false, which switches the pass off either way")
    c.note("per-dimension buffer sizing is not expressible on Iris 1.11.2 - size.buffer.* is "
           "keyed by the bare buffer name - so P2-18's allocation clause is closed by "
           "check_dimension_gating's namespaced-key rule instead")
    return c




# ---------------------------------------------------------------------------
# #17 built-in uniform type faces
#
# Iris registers each built-in uniform with a specific GL type (through
# LocationalUniformHolder.uniformNNx). A GLSL declaration that re-declares the same
# name with a different face is silently disabled at runtime ("Wrong uniform type ...
# Disabling that uniform") - that is how `moonPhase` reached the shader pinned at 0
# before T17, and no offline check could see it: a wrong face still compiles.
# This check turns that class of defect into a hard FAIL.
#
# The table was harvested from the instance Iris jar (iris-fabric-1.11.2+mc26.2.jar,
# net/irisshaders/iris/uniforms/*.class plus the *UniformHolder classes) with
# javap -p -c: every `ldc // String <name>` followed by the next uniformNNx call,
# mapped through the UniformType constant that method pushes. 151 names, 0 with more
# than one face. Names registered through externallyManagedUniform carry no type face
# and are absent here; a declaration for such a name is not checked.
# Raw harvest: qa/iris-uniform-names-2026-09-21-b5.json;
# log: qa/b5-uniform-type-gate-2026-09-21.log.
BUILTIN_UNIFORM_TYPES = {
    "BiomeTemp": "FLOAT", "Projection": "MAT4", "alphaTestRef": "FLOAT",
    "anisotropicFiltering": "INT", "aspectRatio": "FLOAT", "atlasSize": "VEC2I", "biome": "INT",
    "biome_category": "INT", "biome_precipitation": "INT", "blendFunc": "VEC4I",
    "blindFactor": "FLOAT", "blindness": "FLOAT", "blockEntityId": "INT",
    "burningSmooth": "FLOAT", "cameraPosition": "VEC3", "cameraPositionFract": "VEC3",
    "cameraPositionInt": "VEC3I", "chunkFadeTimeInv": "FLOAT", "cloudTime": "FLOAT",
    "constantMood": "FLOAT", "currentColorSpace": "INT", "currentDate": "VEC3I",
    "currentPlayerAir": "FLOAT", "currentPlayerArmor": "FLOAT", "currentPlayerHealth": "FLOAT",
    "currentPlayerHunger": "FLOAT", "currentRenderedItemId": "INT",
    "currentSelectedBlockId": "INT", "currentSelectedBlockPos": "VEC3", "currentTime": "VEC3I",
    "currentYearTime": "VEC2I", "darknessFactor": "FLOAT", "darknessLightFactor": "FLOAT",
    "dawnDusk": "FLOAT", "day": "FLOAT", "dhFarPlane": "FLOAT", "dhNearPlane": "FLOAT",
    "dhRenderDistance": "INT", "effectStrength": "FLOAT", "endFlashIntensity": "FLOAT",
    "endFlashPosition": "VEC3", "entityColor": "VEC4", "entityId": "INT", "eyeAltitude": "FLOAT",
    "eyeBrightness": "VEC2I", "eyeBrightnessM": "FLOAT", "eyeBrightnessSmooth": "VEC2I",
    "eyePosition": "VEC3", "far": "FLOAT", "feetInWater": "INT", "firstPersonCamera": "INT",
    "fogColor": "VEC3", "fogDensity": "FLOAT", "fogEnd": "FLOAT", "fogMode": "INT",
    "fogShape": "INT", "fogStart": "FLOAT", "frameCounter": "INT", "frameTime": "FLOAT",
    "frameTimeCounter": "FLOAT", "frameTimeSmooth": "FLOAT", "gtextureId": "INT",
    "gtextureSize": "VEC2I", "heavyFog": "INT", "heldBlockLightColor": "VEC3",
    "heldBlockLightColor2": "VEC3", "heldBlockLightValue": "INT", "heldBlockLightValue2": "INT",
    "heldItemId": "INT", "heldItemId2": "INT", "hideGUI": "INT", "inSwimmingAnimation": "INT",
    "iris_FogColor": "VEC4", "iris_FogDensity": "FLOAT", "iris_FogEnd": "FLOAT",
    "iris_FogStart": "FLOAT", "iris_LightmapTextureMatrix": "MAT4", "iris_ScreenSize": "VEC2",
    "iris_currentAlphaTest": "FLOAT", "isDry": "FLOAT", "isElytraFlying": "INT",
    "isEyeInCave": "FLOAT", "isEyeInWater": "INT", "isPrecipitationRain": "FLOAT",
    "isRainy": "FLOAT", "isRiding": "INT", "isRightHanded": "INT", "isSnowy": "FLOAT",
    "isSpectator": "INT", "is_burning": "INT", "is_hurt": "INT", "is_invisible": "INT",
    "is_on_ground": "INT", "is_sneaking": "INT", "is_sprinting": "INT",
    "lightningBoltPosition": "VEC4", "maxPlayerAir": "FLOAT", "maxPlayerArmor": "FLOAT",
    "maxPlayerHealth": "FLOAT", "maxPlayerHunger": "FLOAT", "moonBrightness": "FLOAT",
    "moonPhase": "INT", "moonPosition": "VEC3", "near": "FLOAT", "night": "FLOAT",
    "nightVision": "FLOAT", "pi": "FLOAT", "playerBodyVector": "VEC3",
    "playerLookVector": "VEC3", "playerMood": "FLOAT", "previousCameraPosition": "VEC3",
    "previousCameraPositionFract": "VEC3", "previousCameraPositionInt": "VEC3I",
    "previousEndFlashIntensity": "FLOAT", "rainFactor": "FLOAT", "rainStrength": "FLOAT",
    "rainStrengthS": "FLOAT", "rainStrengthS2": "FLOAT", "rainStrengthShiningStars": "FLOAT",
    "rainfall": "FLOAT", "relativeEyePosition": "VEC3", "relativeVehiclePosition": "VEC3",
    "renderStage": "INT", "screenBrightness": "FLOAT", "seaLevel": "INT", "shadowAngle": "FLOAT",
    "shadowFade": "FLOAT", "shadowLightPosition": "VEC3", "shdFade": "FLOAT", "skyColor": "VEC3",
    "sneakSmooth": "FLOAT", "starter": "FLOAT", "sunAngle": "FLOAT", "sunPosition": "VEC3",
    "temperature": "FLOAT", "textureFilteringMode": "INT", "textureReloadCount": "INT",
    "thunderStrength": "FLOAT", "timeAngle": "FLOAT", "timeBrightness": "FLOAT",
    "touchmybody": "FLOAT", "upPosition": "VEC3", "vehicleId": "INT", "vehicleInWater": "INT",
    "vehicleLookVector": "VEC3", "velocity": "FLOAT", "viewHeight": "FLOAT",
    "viewWidth": "FLOAT", "wetness": "FLOAT", "worldDay": "INT", "worldTime": "INT",
}

# GLSL keyword -> the Iris UniformType it can satisfy. UniformType has exactly ten
# constants (INT FLOAT MAT3 MAT4 VEC2 VEC2I VEC3 VEC3I VEC4 VEC4I); there is no DOUBLE
# family, so a `double` declaration can never satisfy a built-in.
GLSL_FACE_TO_UNIFORM_TYPE = {
    "float": "FLOAT", "int": "INT",
    "vec2": "VEC2", "ivec2": "VEC2I",
    "vec3": "VEC3", "ivec3": "VEC3I",
    "vec4": "VEC4", "ivec4": "VEC4I",
    "mat3": "MAT3", "mat4": "MAT4",
}


def check_builtin_uniform_types():
    c = Check(17, "built-in uniform type faces (Iris registration <-> GLSL declaration)")
    seen = 0
    astra_names = set()
    for path in walk_shader_files():
        if path.suffix not in (".glsl", ".vsh", ".fsh", ".csh"):
            continue
        text = read(path)
        for m in re.finditer(
                r"^\s*uniform\s+(\w+)\s+(\w+)\s*(?:\[\s*\d+\s*\])?\s*;", text, flags=re.M):
            ty, name = m.group(1), m.group(2)
            if name.startswith("astra"):
                astra_names.add(name)
            if name not in BUILTIN_UNIFORM_TYPES:
                continue
            seen += 1
            want = BUILTIN_UNIFORM_TYPES[name]
            got = GLSL_FACE_TO_UNIFORM_TYPE.get(ty)
            if got != want:
                c.fail("%s: `uniform %s %s;` - Iris registers this built-in as %s, "
                       "the declared face is %s; Iris drops a mismatched binding at "
                       "runtime without failing the build"
                       % (rel(path), ty, name, want, got or ty))
    if not c.fails:
        c.note("%d built-in declaration(s) checked against %d registered names; "
               "0 mismatches" % (seen, len(BUILTIN_UNIFORM_TYPES)))
    # A custom uniform colliding with a built-in name IS a hard failure in Iris, so
    # surface any astra-prefixed declaration that also names a built-in.
    for name in sorted(astra_names & set(BUILTIN_UNIFORM_TYPES)):
        c.fail("`%s` carries an astra prefix but is also an Iris built-in name" % name)
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
    check_iris_parser_contracts()
    check_tier_differential(opts)
    check_option_consumers()
    check_buffer_declarations()
    check_vendor_isolation()
    check_dimension_gating()
    check_builtin_uniform_types()
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
