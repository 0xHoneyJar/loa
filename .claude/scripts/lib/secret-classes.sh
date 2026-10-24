#!/usr/bin/env bash
# =============================================================================
# secret-classes.sh — the credential-shaped secret classes and their placeholder
# filter, one source for every caller (cycle-133 Sprint 3 Task 3.3; SDD C-4, C-12).
#
# Extracted from record-branch.sh (Sprint 1 Task 1.4) so that the external corpus
# seeder runs "the same scanner as C-4" without a copy of the regexes. Sourced;
# defines functions only and changes no shell option of the caller.
#
# Classes (never bypassable): private-key, anthropic-key, openai-key, github-token,
# aws-access-key, google-api-key, slack-token, bearer-token. Placeholder filter: the
# matched body needs at least six distinct characters (xxxx…, 0000… are not hits);
# a generic shape (openai-key, slack-token, bearer-token) also needs a digit and a
# letter (prose after "Bearer" is not a token). The bypassable class
# audit-key-password-assignment comes from audit-secret-redaction-scan.sh.
#
# Functions:
#   secret_classes_names                  the eight class names, one line
#   secret_classes_py credscan DIR LIST   path:line:class per credential hit of the
#                                         LIST (newline-separated paths under DIR)
#   secret_classes_py parsepw LIST PWOUT  audit-secret-redaction-scan.sh output →
#                                         path:line:audit-key-password-assignment
#   secret_classes_scan DIR LIST CRED_OUT OTHER_OUT
#                                         both passes over DIR; writes the two hit
#                                         lists; 0 scanned (hits or not), 1 the
#                                         scanner failed (one stderr line)
# Hits name path:line:class only; the matched text is never printed.
# SECRET_CLASSES_TAG (default secret-classes) prefixes failure messages.
# Tests: tests/unit/secret-classes.bats, tests/unit/record-branch.bats
# =============================================================================

_SECRET_CLASSES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -r -d '' _SECRET_CLASSES_PY <<'PYEOF' || true
import os, re, sys

TAG = os.environ.get("SECRET_CLASSES_TAG") or "secret-classes"

def die(code, msg):
    print(TAG + ": REFUSED: " + msg if code == 2 else TAG + ": FAILED: " + msg, file=sys.stderr)
    sys.exit(code)

CRED = [
    ("private-key", re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"), False),
    ("anthropic-key", re.compile(rb"sk-ant-([A-Za-z0-9_-]{20,})"), False),
    ("openai-key", re.compile(rb"(?<![A-Za-z0-9_-])sk-(?!ant-)([A-Za-z0-9_-]{20,})"), True),
    ("github-token", re.compile(rb"(?<![A-Za-z0-9_])(?:gh[pousr]_([A-Za-z0-9]{36,})|github_pat_([A-Za-z0-9_]{22,}))"), False),
    ("aws-access-key", re.compile(rb"(?<![A-Z0-9])(?:AKIA|ASIA)([A-Z0-9]{16})(?![A-Z0-9])"), False),
    ("google-api-key", re.compile(rb"AIza([0-9A-Za-z_-]{35})"), False),
    ("slack-token", re.compile(rb"xox[abporsu]-([A-Za-z0-9-]{10,})"), True),
    ("bearer-token", re.compile(rb"[Bb]earer\s+([A-Za-z0-9._~+/-]{20,})"), True),
]

def secretish(m, generic):
    groups = [g for g in m.groups() if g]
    if not groups:
        return True
    body = groups[0]
    if len(set(body)) < 6:
        return False          # placeholder shapes: xxxx…, 0000…, REDACTED
    if generic and not (re.search(rb"[0-9]", body) and re.search(rb"[A-Za-z]", body)):
        return False          # prose ("Bearer authentication-is-required") is not a token
    return True

def cmd_names():
    print(" ".join(c for c, _r, _g in CRED))

def cmd_credscan(outdir, list_file):
    hits = []
    for path in [l for l in open(list_file, encoding="utf-8", errors="surrogateescape").read().split("\n") if l]:
        with open(os.path.join(outdir, path), "rb") as fh:
            for n, line in enumerate(fh, 1):
                for cls, rx, generic in CRED:
                    if any(secretish(m, generic) for m in rx.finditer(line)):
                        hits.append("%s:%d:%s" % (path, n, cls))
    sys.stdout.write("".join(h + "\n" for h in hits))

def cmd_parsepw(list_file, pw_out):
    known = sorted([l for l in open(list_file, encoding="utf-8", errors="surrogateescape").read().split("\n") if l], key=len, reverse=True)
    hits = []
    for line in open(pw_out, encoding="utf-8", errors="surrogateescape").read().split("\n"):
        for p in known:
            m = re.match(re.escape(p) + r":(\d+):", line)
            if m:
                hits.append("%s:%s:audit-key-password-assignment" % (p, m.group(1)))
                break
        else:
            if line.strip():
                die(1, "unparsed scanner output line (path not in the export): %d bytes" % len(line))
    sys.stdout.write("".join(h + "\n" for h in hits))

{"names": cmd_names, "credscan": cmd_credscan, "parsepw": cmd_parsepw}[sys.argv[1]](*sys.argv[2:])
PYEOF

secret_classes_py() { python3 -I -c "$_SECRET_CLASSES_PY" "$@"; }

secret_classes_names() { secret_classes_py names; }

secret_classes_scan() {
  local dir="$1" list="$2" cred_out="$3" other_out="$4" pw_rc=0 tag="${SECRET_CLASSES_TAG:-secret-classes}"
  local scanner="$_SECRET_CLASSES_DIR/../audit-secret-redaction-scan.sh"
  if [[ ! -f "$scanner" ]]; then
    echo "$tag: FAILED: the scanner $scanner is missing" >&2
    return 1
  fi
  case "$list" in /*) ;; *) list="$PWD/$list" ;; esac
  (cd "$dir" && cat -- "$list" | bash "$scanner") > "$other_out.pw" 2> "$other_out.err" || pw_rc=$?
  case "$pw_rc" in
    0) : > "$other_out.pw" ;;
    1) : ;;
    *) echo "$tag: FAILED: audit-secret-redaction-scan.sh exited $pw_rc: $(head -c 300 "$other_out.err")" >&2
       rm -f -- "$other_out.pw" "$other_out.err"; return 1 ;;
  esac
  secret_classes_py parsepw "$list" "$other_out.pw" > "$other_out" || { rm -f -- "$other_out.pw" "$other_out.err"; return 1; }
  rm -f -- "$other_out.pw" "$other_out.err"
  secret_classes_py credscan "$dir" "$list" > "$cred_out" || return 1
}

# Executed rather than sourced (a Python caller such as seed-corpus-from-external.sh):
#   bash secret-classes.sh scan DIR LIST CRED_OUT OTHER_OUT    → secret_classes_scan
#   bash secret-classes.sh names                               → secret_classes_names
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  export LC_ALL=C
  case "${1:-}" in
    scan)  [[ $# -eq 5 ]] || { echo "usage: secret-classes.sh scan DIR LIST CRED_OUT OTHER_OUT" >&2; exit 2; }
           shift; secret_classes_scan "$@" ;;
    names) secret_classes_names ;;
    *)     echo "usage: secret-classes.sh scan DIR LIST CRED_OUT OTHER_OUT | names" >&2; exit 2 ;;
  esac
fi
