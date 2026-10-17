"""Text -> Config."""
import re

from .escape import scan_quoted, unquote
from .model import Config, ParseError, norm

_INLINE_COMMENT = re.compile(r"\s[#;]")


def parse_value(rest, line):
    rest = rest.strip()
    if rest.startswith('"'):
        body, tail = scan_quoted(rest, line)
        tail = tail.strip()
        if tail and tail[0] not in "#;":
            raise ParseError(line, "text after closing quote")
        return unquote(body, line)
    match = _INLINE_COMMENT.search(rest)
    return (rest[:match.start()] if match else rest).rstrip()


def loads(text):
    config = Config()
    section = None
    seen_sections, seen_keys = set(), set()
    for n, raw in enumerate(text.split("\n"), 1):
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("["):
            if not line.endswith("]"):
                raise ParseError(n, "bad section header")
            section = line[1:-1].strip()
            if not section:
                raise ParseError(n, "empty section name")
            if norm(section) in seen_sections:
                raise ParseError(n, f"duplicate section: {section}")
            seen_sections.add(norm(section))
            seen_keys = set()
            config.add_section(section)
            continue
        if section is None:
            raise ParseError(n, "key outside a section")
        key, eq, rest = line.partition("=")
        key = key.strip()
        if not eq:
            raise ParseError(n, "expected key = value")
        if not key:
            raise ParseError(n, "empty key")
        if norm(key) in seen_keys:
            raise ParseError(n, f"duplicate key: {key}")
        seen_keys.add(norm(key))
        # keys are matched case-insensitively, so they are stored in one case
        config.set(section, key.lower(), parse_value(rest, n))
    return config
