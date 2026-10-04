"""Shared parsing for annotated Iris macro and const options."""
from dataclasses import dataclass
import re


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
