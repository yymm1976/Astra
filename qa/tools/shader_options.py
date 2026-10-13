"""Shared parsing for annotated Iris macro and const options."""
from dataclasses import dataclass
import re


QUALITY_TIERS = ("PERFORMANCE", "BALANCED", "QUALITY", "ULTRA")
ALL_PROFILES = ("PERFORMANCE", "NO_SHADOWS", "BALANCED", "QUALITY", "ULTRA")


def parse_profiles(text: str) -> dict[str, dict[str, str | None]]:
    """Expand profile references in token order; later assignments win."""
    logical = re.sub(r"\\\r?\n[ \t]*", " ", text)
    definitions = {}
    for line in logical.splitlines():
        match = re.match(r"^profile\.([A-Za-z0-9_]+)\s*=(.*)$", line.strip())
        if not match:
            continue
        name = match.group(1).upper()
        if name in definitions:
            raise ValueError(f"duplicate profile definition: {name}")
        definitions[name] = match.group(2).split()
    expanded = {}

    def resolve(name, stack):
        if name in stack:
            raise ValueError("profile inheritance cycle: " + " -> ".join((*stack, name)))
        if name not in definitions:
            raise ValueError("missing parent profile: " + " -> ".join((*stack, name)))
        if name in expanded:
            return expanded[name]
        values = {}
        for token in definitions[name]:
            if token.startswith("profile."):
                values.update(resolve(token[len("profile."):].upper(), (*stack, name)))
            elif token.startswith("!"):
                values[token[1:]] = None
            elif "=" in token:
                key, value = token.split("=", 1)
                values[key] = value
            else:
                values[token] = ""
        expanded[name] = values
        return values

    return {name: dict(resolve(name, ())) for name in definitions}


DEFINE_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?P<off>//[ \t]*)?#define[ \t]+"
    r"(?P<name>[A-Za-z_]\w*)(?:[ \t]+(?P<body>.*))?$")
CONST_RE = re.compile(
    r"^(?P<indent>[ \t]*)const[ \t]+(?P<type>float|int|bool)[ \t]+"
    r"(?P<name>[A-Za-z_]\w*)[ \t]*=[ \t]*(?P<value>[^;]+);"
    r"[ \t]*(?P<comment>//.*)?$")
LEVELS_RE = re.compile(r"\[([^\]]+)\]")


@dataclass(frozen=True)
class Declaration:
    name: str
    indent: str
    value: str
    comment: str
    levels: tuple[str, ...]
    off: bool = False
    const_type: str | None = None

    @property
    def boolean(self) -> bool:
        return set(self.levels) == {"false", "true"}


def declaration(line: str) -> Declaration | None:
    macro = DEFINE_RE.match(line)
    constant = None if macro else CONST_RE.match(line)
    if macro:
        value, marker, tail = (macro.group("body") or "").partition("//")
        comment = marker + tail
        match = macro
        off, const_type = bool(macro.group("off")), None
    elif constant:
        match = constant
        value, comment = constant.group("value"), constant.group("comment") or ""
        off, const_type = False, constant.group("type")
    else:
        return None
    levels = LEVELS_RE.search(comment)
    return Declaration(match.group("name"), match.group("indent"), value.strip(),
                       comment, tuple(levels.group(1).split()) if levels else (),
                       off, const_type)


def parse_options(text: str) -> dict[str, Declaration]:
    # An engine const with no annotated value list is not a user option.
    return {item.name: item for line in text.splitlines()
            if (item := declaration(line)) is not None and item.levels}
