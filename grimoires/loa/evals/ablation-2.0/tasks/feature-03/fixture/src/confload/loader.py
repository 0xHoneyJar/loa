"""Parse `key = value` configuration text into {section: {key: value}}.

Format, one statement per line:

    # a comment (also `;`), only at the start of a line
    [section]             section names: letters, digits, `_`, `-`, `.`
    key = value           keys: letters, digits, `_`, `-`, `.`

Keys before the first section header belong to the section "" (the default
section). Whitespace around keys and values is stripped; a value may be empty
and may contain `=`. Later assignments of the same key in the same section
replace earlier ones; a section header may repeat and adds to the section.

Errors raise ConfigError carrying the 1-based line number.
"""
import re

NAME = r"[A-Za-z0-9_.-]+"
SECTION_RX = re.compile(r"\[\s*(" + NAME + r")\s*\]")
ASSIGN_RX = re.compile(r"(" + NAME + r")\s*=(.*)")


class ConfigError(ValueError):
    def __init__(self, message, line):
        super().__init__(f"line {line}: {message}")
        self.line = line


def loads(text):
    """Parse configuration text; returns {section: {key: value}}."""
    data = {"": {}}
    section = ""
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        m = SECTION_RX.fullmatch(line)
        if m:
            section = m.group(1)
            data.setdefault(section, {})
            continue
        m = ASSIGN_RX.fullmatch(line)
        if not m:
            raise ConfigError(f"cannot parse: {line!r}", number)
        data[section][m.group(1)] = m.group(2).strip()
    return data


def load(path):
    """Read and parse a configuration file (UTF-8)."""
    with open(path, encoding="utf-8") as fh:
        return loads(fh.read())
