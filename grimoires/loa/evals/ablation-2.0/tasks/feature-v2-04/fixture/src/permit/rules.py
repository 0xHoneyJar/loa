"""Rules: ``allow PRINCIPAL ACTION PATH``, one per line."""
from dataclasses import dataclass

from .errors import RuleError

EFFECTS = ("allow",)


@dataclass(frozen=True)
class Rule:
    effect: str
    principal: str
    action: str
    pattern: str
    source: str
    line: int


def parse_rule(text, source, line):
    fields = text.split()
    if len(fields) != 4:
        raise RuleError(f"{source}:{line}: expected 4 fields, got {len(fields)}")
    effect, principal, action, pattern = fields
    if effect not in EFFECTS:
        raise RuleError(f"{source}:{line}: unknown effect {effect!r}")
    if not pattern.startswith("/"):
        raise RuleError(f"{source}:{line}: pattern must start with /: {pattern!r}")
    return Rule(effect, principal, action, pattern, source, line)


def parse_rules(text, source):
    """Every rule of ``text``; blank lines and ``#`` comments are skipped."""
    rules = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if line:
            rules.append(parse_rule(line, source, number))
    return rules
