#!/usr/bin/env python3
"""report-assemble.py — render grimoires/loa/reports/review-catch-c132/report.md from report.template.md (Sprint 271, FR-9 AC 2).

Every number in the report's tables comes from a generated artefact: the template carries prose and directives, and this
script copies the referenced lines byte for byte. Directives (FILE is relative to the report directory):
  {{table FILE "HEADING PREFIX"}}   the first markdown table (consecutive lines starting with |) after the first line that starts with the prefix
  {{tableat FILE /REGEX/}}          the table whose first line matches REGEX (re.search), through the consecutive | lines
  {{rows FILE /REGEX/}}             every line of FILE matching REGEX, in file order
  {{line FILE /REGEX/}}             the first line matching REGEX
A directive that matches nothing is an error (exit 1): the report is never rendered with a hole.
Usage: python3 -I report-assemble.py [--template T] [--out report.md]   (defaults beside this script's parent directory)
Exit: 0 rendered; 1 a directive matched nothing or a file is missing; 2 usage.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)   # the report directory
DIRECTIVE = re.compile(r'\{\{(table|tableat|rows|line) (\S+) (?:"([^"]*)"|/((?:[^/\\]|\\.)*)/)\}\}')


def lines_of(path):
    p = os.path.normpath(os.path.join(ROOT, path))
    if not os.path.isfile(p):
        sys.exit("report-assemble: missing artefact %s" % path)
    with open(p, encoding="utf-8") as fh:
        return [l.rstrip("\n") for l in fh]


def table_from(lines, start):
    out = []
    i = start
    while i < len(lines) and lines[i].lstrip().startswith("|"):
        out.append(lines[i]); i += 1
    return out


def resolve(kind, path, heading, regex):
    ls = lines_of(path)
    if kind == "table":
        for i, l in enumerate(ls):
            if l.startswith(heading):
                j = i + 1
                while j < len(ls) and not ls[j].lstrip().startswith("|"):
                    if ls[j].startswith("#"):
                        break
                    j += 1
                t = table_from(ls, j)
                if t:
                    return t
        sys.exit("report-assemble: no table after heading %r in %s" % (heading, path))
    rx = re.compile(regex)
    if kind == "tableat":
        for i, l in enumerate(ls):
            if rx.search(l) and l.lstrip().startswith("|"):
                return table_from(ls, i)
        sys.exit("report-assemble: no table starting at /%s/ in %s" % (regex, path))
    hits = [l for l in ls if rx.search(l)]
    if not hits:
        sys.exit("report-assemble: nothing matches /%s/ in %s" % (regex, path))
    return hits if kind == "rows" else hits[:1]


def main(argv):
    tpl = os.path.join(ROOT, "report.template.md"); out = os.path.join(ROOT, "report.md")
    it = iter(argv)
    for a in it:
        if a == "--template": tpl = next(it, None)
        elif a == "--out": out = next(it, None)
        else: sys.exit(2)
    if not tpl or not out or not os.path.isfile(tpl):
        sys.exit(2)
    with open(tpl, encoding="utf-8") as fh:
        text = fh.read()

    def sub(m):
        kind, path, heading, regex = m.group(1), m.group(2), m.group(3), m.group(4)
        return "\n".join(resolve(kind, path, heading, regex))

    rendered = DIRECTIVE.sub(sub, text)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(rendered)
    print("rendered %s (%d bytes, %d directives)" % (os.path.relpath(out), len(rendered.encode()), len(DIRECTIVE.findall(text))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
