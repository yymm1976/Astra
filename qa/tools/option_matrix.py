"""The option space of the pack, and a compile matrix that walks it.

Survey docs/2026-09-20-shader-pack-design-survey.md 6 P2-12 asked for this after
finding the same missing habit in three reference packs: VanillaPlus ships a menu
option whose second value refers to a symbol that does not exist, so flipping one
row in the GUI produces a compile error (its grading.fsh:178/:182); JCL ships
KILL_SWITCH with a UI and zero consumers; VanillaPlus' profile.Fast names
cloudVolumeFastMultiscatter, which no shader source reads. None of those packs has
a "compile every option combination" step or a "who reads this token" step.

Two questions get answered here, and they cost very differently:

  * statically (option_space): is every declared option actually read, and which
    options can change a preprocessor branch at all? Only that second set can make a
    compile fail or silently drop a code path, so only those become matrix factors;
    the rest are arithmetic inputs to code that is already selected.
  * by compiling (covering_array, driven by compile_glsl.py --matrix): every pair of
    option values, taken together, at least once.

Boolean levels use the two forms apply_profile_settings understands: "" means
"#define NAME" and None means "leave it undefined".

One rule the matrix leans on is an Iris rule, not a GLSL one: a boolean option only
enters the option set if some file references it with #ifdef or #ifndef, because
OptionAnnotatedSource never parses defined(). check_pack.py 11 fails on that, and
undeclared_guards / factors here report the same names from this side so the two
tools cannot drift apart quietly.
"""
from __future__ import annotations

from collections import defaultdict
from itertools import combinations
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Astra" / "shaders"

DEFINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<off>//\s*)?#define\s+(?P<name>[A-Za-z_]\w*)"
    r"(?:\s+(?P<value>[^\n]*?))?\s*(?://\s*\[(?P<levels>[^\]]*)\])?\s*$")
# Only these four prefixes can carry an option name into a branch decision.
CONDITION_RE = re.compile(r"^\s*#\s*(?:if|elif|ifdef|ifndef)\b")
IFDEF_NAME_RE = re.compile(r"^\s*#\s*(?:ifdef|ifndef)\s+([A-Za-z_]\w*)")
COMPARISON_RE = re.compile(r"(?:==|!=|<=|>=|<|>)")


def strip_comments(text: str) -> str:
    """Blank out // and /* */ comments so commented-out code never counts as a consumer."""
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return "\n".join(re.sub(r"//.*", "", line) for line in text.splitlines())


def shader_sources(root: Path = PACK) -> dict[str, str]:
    """Every GLSL file in the pack, keyed by pack-relative path, comments already stripped."""
    out: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if path.suffix in (".glsl", ".fsh", ".vsh", ".csh") and path.is_file():
            out[path.relative_to(root).as_posix()] = strip_comments(
                path.read_text(encoding="utf-8-sig"))
    return out


def parse_options(settings_text: str) -> dict[str, dict]:
    """name -> {levels, bool, default, declared} for every `#define` with a value list.

    `declared` records the shipped state: "on" for a live #define, "off" for a
    commented-out one. A #define with no value list is a constant, not an option, so
    Iris never shows a row for it and it is excluded here.
    """
    out: dict[str, dict] = {}
    for line in settings_text.splitlines():
        match = DEFINE_RE.match(line)
        if not match or not match.group("levels"):
            continue
        name = match.group("name")
        levels = match.group("levels").split()
        is_bool = set(levels) == {"false", "true"}
        raw = (match.group("value") or "").split("//")[0].strip()
        out[name] = {
            "levels": levels,
            "bool": is_bool,
            "default": raw or ("true" if is_bool else "false"),
            "declared": "off" if match.group("off") else "on",
        }
    return out


def _compared_values(line: str, name: str) -> set[str]:
    """Numbers a conditional compares this option against: the slider values that can
    actually flip a branch, as opposed to the 100 that only change a multiplier."""
    out: set[str] = set()
    for side in (rf"\b{re.escape(name)}\s*(?:==|!=|<=|>=|<|>)\s*(-?\d+)",
                 rf"(-?\d+)\s*(?:==|!=|<=|>=|<|>)\s*\b{re.escape(name)}\b"):
        out |= {g for g in re.findall(side, line) if g}
    return out


def option_space(root: Path = PACK) -> dict:
    """Who reads what, and which options can change what gets compiled."""
    sources = shader_sources(root)
    options = parse_options((root / "lib/settings.glsl").read_text(encoding="utf-8-sig"))
    consumers = {name: set() for name in options}
    conditionals = {name: set() for name in options}
    compared = {name: set() for name in options}
    guards: dict[str, set[str]] = defaultdict(set)
    macros: dict[str, set[str]] = defaultdict(set)

    for rel, body in sources.items():
        # A backslash continuation hides everything after the first line from a
        # line-by-line scan, so join them before looking for conditionals.
        lines = re.sub(r"\\\s*\n\s*", " ", body).splitlines()
        for line in lines:
            # A line that defines a name does not *read* it. Without this, every option's
            # own settings.glsl #define counts as a consumer and an option nobody reads -
            # the exact defect this module exists to find - could never be reported.
            defining = DEFINE_RE.match(line)
            mentioned = [name for name in options
                         if name != (defining and defining.group("name"))
                         and re.search(r"\b" + re.escape(name) + r"\b", line)]
            for name in mentioned:
                consumers[name].add(rel)
            if CONDITION_RE.match(line):
                for name in mentioned:
                    conditionals[name].add(rel)
                    compared[name] |= _compared_values(line, name)
                guard = IFDEF_NAME_RE.match(line)
                if guard:
                    guards[guard.group(1)].add(rel)
            define = DEFINE_RE.match(line)
            if define:
                macros[define.group("name")].add(rel)

    factors: dict[str, list[str]] = {}
    for name, files in conditionals.items():
        if not files:
            continue
        info = options[name]
        if info["bool"]:
            factors[name] = ["false", "true"]
            continue
        keep = {info["default"]} | compared[name] | {info["levels"][0], info["levels"][-1]}
        chosen = [v for v in info["levels"] if v in keep]
        factors[name] = chosen or list(info["levels"])

    # A #ifdef for a name nothing defines is a permanently false branch: the code
    # inside it has not compiled since whoever renamed it.
    undeclared_guards = {name: sorted(files) for name, files in guards.items()
                         if name not in options and name not in macros}
    # The mirror case: a constant #define that nothing reads any more.
    unread_macros = {}
    for name, files in macros.items():
        if name in options:
            continue

        def reads(line: str, name: str = name) -> bool:
            define = DEFINE_RE.match(line)
            if define and define.group("name") == name:
                return False
            return bool(re.search(r"\b" + re.escape(name) + r"\b", line))

        readers = {rel for rel, body in sources.items() if any(reads(l) for l in body.splitlines())}
        if not readers:
            unread_macros[name] = sorted(files)

    return {
        "options": options,
        "consumers": consumers,
        "conditionals": conditionals,
        "compared": compared,
        "guards": guards,
        "macros": macros,
        "factors": factors,
        "unused_options": sorted(n for n in options if not consumers[n]),
        "undeclared_guards": undeclared_guards,
        "unread_macros": unread_macros,
    }


def to_override(name: str, level: str, info: dict) -> str | None:
    """A matrix level -> the value form apply_profile_settings expects."""
    if not info["bool"]:
        return level
    return "" if level == "true" else None


def levels_from_profile(profile: dict[str, str | None], name: str, info: dict) -> str:
    """A shaders.properties token -> this option's level name, so profile rows and
    matrix rows speak one vocabulary."""
    value = profile.get(name)
    if info["bool"]:
        return "false" if value is None else "true"
    if value in (None, ""):
        return info["default"]
    return value


def covering_array(space: dict, seeds: list[dict[str, str]] | None = None,
                   max_rows: int = 0) -> tuple[list[dict[str, str]], set]:
    """A greedy pairwise covering array over the factor set.

    Every pair of (option, value) taken from two different options appears together
    in at least one row. Same-family full cartesian products were deliberately not
    used: the shadow family alone (SHADOWS x COLORED_SHADOWS x
    STATIC_SHADOW_FALLBACK x SHADOW_FILTER_MODE x SHADOW_DISTANCE x
    ENTITY_SHADOW_DISTANCE) is 640 rows, and pairwise already covers every pair
    inside it. Seed rows come first, so the factory default and the three shipping
    profiles are always in the compiled set.

    Returns (rows, uncovered_pairs). A non-empty second element means max_rows cut
    coverage short - callers must treat that as a failed gate, not a smaller matrix.
    """
    factors = space["factors"]
    options = space["options"]
    names = sorted(factors, key=lambda n: (-len(factors[n]), n))

    def key(a: str, va: str, b: str, vb: str):
        (x, vx), (y, vy) = sorted(((a, va), (b, vb)))
        return x, vx, y, vy

    outstanding = {key(a, va, b, vb) for a, b in combinations(names, 2)
                   for va in factors[a] for vb in factors[b]}
    rows: list[dict[str, str]] = []

    def consume(row: dict[str, str]) -> None:
        for (a, x), (b, y) in combinations(sorted(row.items()), 2):
            outstanding.discard(key(a, x, b, y))

    for seed in seeds or []:
        row = {name: seed.get(name, options[name]["default"]) for name in names}
        rows.append(row)
        consume(row)
    while outstanding:
        if max_rows and len(rows) >= max_rows:
            break
        a, va, b, vb = min(outstanding)
        row = {a: va, b: vb}
        for c in names:
            if c in row:
                continue
            best, best_gain = None, -1
            for vc in factors[c]:
                gain = sum(1 for entry in outstanding
                           if (entry[0], entry[1]) == (c, vc) or (entry[2], entry[3]) == (c, vc))
                if gain > best_gain:
                    best, best_gain = vc, gain
            row[c] = options[c]["default"] if best is None else best
        rows.append(row)
        consume(row)
    return rows, outstanding


def summarise(space: dict) -> str:
    options, factors = space["options"], space["factors"]
    pairs = sum(1 for _ in combinations(sorted(factors), 2))
    lines = [
        f"{len(options)} option(s) with a value list; {len(factors)} appear in a "
        f"preprocessor conditional and became matrix factors, "
        f"{len(options) - len(factors)} are value-only inputs to code already selected",
        f"factor levels total {sum(len(v) for v in factors.values())} "
        f"(boundary values only for sliders), over {pairs} factor pairs",
        f"declared but read nowhere: {space['unused_options'] or 'none'}",
        f"#ifdef/#ifndef names nothing declares: "
        f"{sorted(space['undeclared_guards']) or 'none'}",
        f"constant #defines nothing reads: {sorted(space['unread_macros']) or 'none'}",
    ]
    return "\n".join("       . " + line for line in lines)


if __name__ == "__main__":
    # Report only, always exit 0. Whether a finding here is a *defect* depends on engine
    # knowledge (which symbols the loader itself defines, which enum arms are named but
    # deliberately untested) that lives in check_pack.py check 13. Duplicating that
    # judgement would let two gates disagree about the same pack.
    space = option_space()
    rows, uncovered = covering_array(space)
    print(summarise(space))
    print(f"       . unseeded greedy pairwise covering array = {len(rows)} row(s), "
          f"{len(uncovered)} uncovered pair(s)")
    print("       . verdict: python qa/tools/check_pack.py | compile: "
          "python qa/tools/compile_glsl.py --matrix")
