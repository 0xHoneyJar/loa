#!/usr/bin/env python3
"""Check literal procedure commands/spawn instructions against declared tools.

This is a Markdown contract lint, not a shell interpreter or a host permission
test. It checks shell examples and inline framework/CLI invocations; arbitrary
prose and runtime-expanded argument values are outside this lint.
"""
import fnmatch
import json
from pathlib import Path
import re
import shlex
import sys


def has_shell_syntax(line):
    """Lex quote/escape states before classifying shell operators/substitutions.

    shlex.split below parses argv but discards whether punctuation was quoted;
    retain that distinction here instead of reclassifying quoted data as code.
    """
    quote = None
    escaped = False
    for i, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote != "'":
            escaped = True
            continue
        if quote == "'":
            if char == "'":
                quote = None
            continue
        # These substitutions execute even inside double quotes.
        if char == "`" or line[i:i + 2] == "$(":
            return True
        if quote == '"':
            if char == '"':
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
        elif char == "#" and (i == 0 or line[i - 1].isspace()):
            break
        elif char in ";|&<>()":
            return True
    return False


def validate(frontmatter, text):
    caps = frontmatter.get("capabilities", {})
    execution = caps.get("execute_commands", False)
    tools = frontmatter.get("allowed-tools", "")
    if isinstance(tools, list):
        tools = ", ".join(tools)
    denied = frontmatter.get("disallowed-tools", [])
    errors = []
    body = text.split("---", 2)[-1]
    spawn = re.search(r"MUST split into parallel|\bSpawn \d+ parallel|\bTask\(", body)
    if spawn and (caps.get("agent_spawn") is not True or
                  not re.search(r"\b(Task|Agent)\b", tools) or
                  any(t in denied for t in ("Task", "Agent"))):
        errors.append("procedure requires agent spawning but agent_spawn/Task authority is absent")
    # Unrestricted command capability has no command allowlist to reconcile.
    if execution is True:
        return errors

    allowed = execution.get("allowed", []) if isinstance(execution, dict) else []
    deny_raw_shell = not isinstance(execution, dict) or execution.get("deny_raw_shell", True)
    tool_patterns = [" ".join(shlex.split(p)) for p in re.findall(r"Bash\(([^)]+)\)", tools)]

    def matches(command, pattern):
        return fnmatch.fnmatchcase(command, pattern) or (
            pattern.endswith(" *") and command == pattern[:-2])

    # Consume all fenced blocks so non-shell examples aren't read as inline code.
    for snippet in re.finditer(r"```([^\n]*)\n(.*?)```|(?<!`)`([^`\n]+)`(?!`)", body, re.S):
        language, block, inline = snippet.groups()
        if inline is not None:
            if not re.match(r"(?:\.claude/scripts/[\w/.-]+\.sh(?:\s|$)|(?:git|br|yq|jq)\s)", inline):
                continue
            lines = [inline]
        elif language.strip() in ("bash", "sh", "shell"):
            lines = block.replace("\\\n", " ").splitlines()
        else:
            continue
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                words = shlex.split(line, comments=True)
            except ValueError:
                errors.append("procedure shell example cannot be parsed: " + line)
                continue
            if not words:
                continue
            command = words[0]
            # Dynamic argument values are not evaluated; literal command/subcommand
            # prefixes still have to match the declared command grammar.
            invocation = " ".join(words)
            if deny_raw_shell and has_shell_syntax(line):
                errors.append("procedure requires raw shell with deny_raw_shell: " + line)
                continue
            if not any(entry.get("command") == command and matches(
                    invocation, " ".join([command] + entry.get("args", []))) for entry in allowed):
                errors.append("procedure command not allowed by execute_commands: " + invocation)
            if "Bash" in denied or not any(matches(invocation, p) for p in tool_patterns):
                errors.append("procedure command not allowed by allowed-tools: " + invocation)
    return sorted(set(errors))


if __name__ == "__main__":
    print(json.dumps(validate(json.load(sys.stdin), Path(sys.argv[1]).read_text())))
