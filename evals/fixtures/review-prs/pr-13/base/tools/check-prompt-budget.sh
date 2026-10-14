#!/usr/bin/env bash
# =============================================================================
# tools/check-prompt-budget.sh — byte budgets for the always-loaded prompt surface
#
# cycle-124 FR-8 (AC-8.1). The prompt surface Claude loads on every turn or on
# every skill invocation has hard byte budgets; this is the CI gate behind them.
#
#   .claude/skills/*/SKILL.md      ≤ 16,384 B  each — charged with every
#                                  resources/*.md the skill reads UNCONDITIONALLY
#   .claude/loa/CLAUDE.loa.md      ≤ 10,240 B
#   .claude/protocols/*.md (total) ≤ 200,000 B fail; > 143,360 B warns
#
# Resource charging rule (the byte budget cannot be met by moving text into a
# file the skill still always loads): a resources/<name>.md is charged when a
# SKILL.md line names it AND reads as an unguarded read imperative —
#   imperative: (?i)\b(read|load|source|include)\b          e.g. "Read `resources/X.md`"
#   guard:      (?i)\b(if|when|only|optional|as needed|on demand|unless|may|see)\b
# A line with a guard word ("See resources/X.md §Security", "read X.md if …") is
# a pointer, not a load, and is not charged. Pinned by tests/unit/prompt-budget.bats.
#
# Every other SKILL.md figure the sprint report needs from the "mechanical pass"
# (history tokens per file) rides along in --json as `history_tokens` —
# informational; enforcement of that rule is tests/unit/no-history-in-rule-text.bats.
#
# Usage:
#   tools/check-prompt-budget.sh              # human table, exit 1 on any breach
#   tools/check-prompt-budget.sh --json       # machine-readable report
#   tools/check-prompt-budget.sh --root DIR   # check a fixture tree (tests / CI sentinels)
#   tools/check-prompt-budget.sh --quiet      # exit code only
#
# Exit codes: 0 within budget · 1 breach · 2 usage / missing root
# =============================================================================
set -euo pipefail
export LC_ALL=C

ROOT="."
JSON=0
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { echo "check-prompt-budget.sh: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --quiet|-q) QUIET=1; shift ;;
    --help|-h) sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check-prompt-budget.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -d "$ROOT/.claude" ]] || { echo "check-prompt-budget.sh: no .claude/ under $ROOT" >&2; exit 2; }

python3 - "$ROOT" "$JSON" "$QUIET" <<'PY'
import glob, json, os, re, sys
root, as_json, quiet = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 200000, 143360
IMPERATIVE = re.compile(r"\b(read|load|source|include)\b", re.I)
GUARD = re.compile(r"\b(if|when|only|optional|as needed|on demand|unless|may|see)\b", re.I)
HISTORY = re.compile(r"cycle-[0-9]{3}|#[0-9]{3,4}|KF-[0-9]{3}")
RES = re.compile(r"resources/([A-Za-z0-9_.-]+\.md)")

def size(p):
    return os.path.getsize(p)

violations, skills = [], []
for skill_md in sorted(glob.glob(os.path.join(root, ".claude/skills/*/SKILL.md"))):
    sdir = os.path.dirname(skill_md)
    name = os.path.basename(sdir)
    charged, seen = [], set()
    text = open(skill_md, encoding="utf-8", errors="replace").read()
    for ln, line in enumerate(text.splitlines(), 1):
        for m in RES.finditer(line):
            rel = m.group(1)
            if rel in seen or not IMPERATIVE.search(line) or GUARD.search(line):
                continue
            rp = os.path.join(sdir, "resources", rel)
            if os.path.isfile(rp):
                seen.add(rel)
                charged.append({"path": os.path.relpath(rp, root), "bytes": size(rp), "line": ln})
    total = size(skill_md) + sum(c["bytes"] for c in charged)
    ok = total <= SKILL_LIMIT
    skills.append({"skill": name, "path": os.path.relpath(skill_md, root), "skill_md_bytes": size(skill_md),
                   "charged_resources": charged, "total": total, "limit": SKILL_LIMIT, "ok": ok,
                   "history_tokens": len(HISTORY.findall(text))})
    if not ok:
        extra = f" (+{len(charged)} charged resource(s))" if charged else ""
        violations.append(f"skill {name}: {total} B > {SKILL_LIMIT} B{extra}")

loa_path = os.path.join(root, ".claude/loa/CLAUDE.loa.md")
loa = {"path": ".claude/loa/CLAUDE.loa.md", "bytes": size(loa_path) if os.path.isfile(loa_path) else 0,
       "limit": LOA_LIMIT, "present": os.path.isfile(loa_path)}
loa["ok"] = loa["bytes"] <= LOA_LIMIT
if not loa["ok"]:
    violations.append(f"CLAUDE.loa.md: {loa['bytes']} B > {LOA_LIMIT} B")

pfiles = sorted(glob.glob(os.path.join(root, ".claude/protocols/*.md")))
protos = [{"path": os.path.relpath(p, root), "bytes": size(p)} for p in pfiles]
ptotal = sum(p["bytes"] for p in protos)
protocols = {"total": ptotal, "count": len(protos), "fail_limit": PROTO_FAIL, "warn_limit": PROTO_WARN,
             "ok": ptotal <= PROTO_FAIL, "warn": PROTO_WARN < ptotal <= PROTO_FAIL, "files": protos}
if not protocols["ok"]:
    violations.append(f"protocols total: {ptotal} B > {PROTO_FAIL} B")

report = {"ok": not violations, "skills": skills, "claude_loa": loa, "protocols": protocols, "violations": violations}
if as_json:
    print(json.dumps(report, indent=2))
elif not quiet:
    print(f"{'skill':<32}{'SKILL.md':>10}{'charged':>10}{'total':>10}  limit {SKILL_LIMIT}")
    for s in skills:
        flag = "" if s["ok"] else "  BREACH"
        print(f"{s['skill']:<32}{s['skill_md_bytes']:>10}{sum(c['bytes'] for c in s['charged_resources']):>10}{s['total']:>10}{flag}")
    print(f"CLAUDE.loa.md {loa['bytes']} B (limit {LOA_LIMIT}){'' if loa['ok'] else '  BREACH'}")
    pw = "  WARN (> %d)" % PROTO_WARN if protocols["warn"] else ("" if protocols["ok"] else "  BREACH")
    print(f"protocols total {ptotal} B over {len(protos)} files (fail > {PROTO_FAIL}){pw}")
if violations and not quiet and not as_json:
    print("\nBUDGET BREACH:", file=sys.stderr)
    for v in violations:
        print("  " + v, file=sys.stderr)
elif protocols["warn"] and not quiet and not as_json:
    print(f"WARN: protocols total {ptotal} B exceeds the {PROTO_WARN} B warning threshold", file=sys.stderr)
sys.exit(1 if violations else 0)
PY
