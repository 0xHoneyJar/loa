#!/usr/bin/env bats
# OKF/ICM cycle Sprint 5 — kf-write-lib.sh (KF/NOTES minimal-conformance append helper).
# Hermetic: every test runs against a fresh fixture so the real append-only log is never touched.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  KFW="$PROJECT_ROOT/.claude/scripts/lib/kf-write-lib.sh"
  F="$(mktemp)"
  cat > "$F" <<'EOF'
# Known Failures

## Index

| ID | Status | Feature | Recurrence |
|----|--------|---------|------------|
| [KF-001](#kf-001-foo-thing) | OPEN | foo | 2 |
| [KF-002](#kf-002-bar) | RESOLVED | bar | many reproductions |

---

## KF-001: foo thing

**Status**: OPEN
**Feature**: foo
**Symptom**: it breaks
**Recurrence count**: 2

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-06-01 | tried x | DID NOT WORK | #100 |

### Reading guide

Do the thing.

## KF-002: bar

**Status**: RESOLVED
**Feature**: bar
**Recurrence count**: many reproductions

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-01 | y | RESOLVED | PR #1 |

### Reading guide

Already resolved.
EOF
  NF="$(mktemp)"
  printf '# Loa Project Notes\n\n## Decision Log — 2026-06-01 (cycle-old)\n\nold stuff.\n' > "$NF"
}

teardown() { rm -f "$F" "$NF"; }

@test "kf-write new: appends a new entry with the next id + an Index row" {
  run bash "$KFW" new --file "$F" --title "brand new failure" --status OPEN --feature "feat" --symptom "boom" --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "KF-003" ]
  grep -qE '^## KF-003: brand new failure$' "$F"
  grep -qE '^\| \[KF-003\]\(#kf-003-brand-new-failure\) \| OPEN \| feat \| 1 \|$' "$F"
  grep -qE '^\*\*Status\*\*: OPEN$' "$F"
}

@test "kf-write new: empty --status is rejected (malformed-entry floor)" {
  run bash "$KFW" new --file "$F" --title "no status" --status "" --quiet
  [ "$status" -ne 0 ]
  ! grep -q 'no status' "$F"
}

@test "kf-write new: refuses a duplicate title (idempotent — file unchanged)" {
  local before; before="$(sha256sum "$F" | cut -d' ' -f1)"
  run bash "$KFW" new --file "$F" --title "foo thing" --status OPEN --quiet
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$before" ]
}

@test "kf-write new: an inline attempt without evidence is BLOCKED" {
  run bash "$KFW" new --file "$F" --title "needs evidence" --status OPEN \
      --attempt-date 2026-06-28 --attempt-what "tried z" --attempt-outcome "DID NOT WORK" --attempt-evidence "" --quiet
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence"* || "$output" == *"Evidence"* ]]
  ! grep -q 'needs evidence' "$F"
}

@test "kf-write new: never rewrites existing entries (KF-001 block byte-identical)" {
  local before; before="$(awk '/^## KF-001:/{p=1} p&&/^## KF-002:/{exit} p' "$F")"
  bash "$KFW" new --file "$F" --title "another one" --status OPEN --quiet
  local after; after="$(awk '/^## KF-001:/{p=1} p&&/^## KF-002:/{exit} p' "$F")"
  [ "$before" = "$after" ]
}

@test "kf-write attempt: appends a row to an existing entry" {
  run bash "$KFW" attempt --file "$F" --id KF-001 --date 2026-06-28 --what "tried again" --outcome "WORKAROUND-AT-LIMIT" --evidence "PR #500" --quiet
  [ "$status" -eq 0 ]
  awk '/^## KF-001:/{p=1} p&&/^## KF-002:/{exit} p' "$F" | grep -qF '| 2026-06-28 | tried again | WORKAROUND-AT-LIMIT | PR #500 |'
}

@test "kf-write attempt: missing --evidence is BLOCKED (the load-bearing cell)" {
  local before; before="$(sha256sum "$F" | cut -d' ' -f1)"
  run bash "$KFW" attempt --file "$F" --id KF-001 --date 2026-06-28 --what "x" --outcome "DID NOT WORK" --evidence "" --quiet
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$before" ]
}

@test "kf-write attempt: unknown id errors and changes nothing" {
  local before; before="$(sha256sum "$F" | cut -d' ' -f1)"
  run bash "$KFW" attempt --file "$F" --id KF-999 --date 2026-06-28 --what "x" --outcome o --evidence "#1" --quiet
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$before" ]
}

@test "kf-write recur: integer count is incremented in the entry AND the Index row" {
  run bash "$KFW" recur --file "$F" --id KF-001 --quiet
  [ "$status" -eq 0 ]
  awk '/^## KF-001:/{p=1} p&&/^## KF-002:/{exit} p' "$F" | grep -qE '^\*\*Recurrence count\*\*: 3$'
  grep -qE '^\| \[KF-001\].* \| 3 \|$' "$F"
}

@test "kf-write recur: free-text recurrence count is refused (file unchanged)" {
  local before; before="$(sha256sum "$F" | cut -d' ' -f1)"
  run bash "$KFW" recur --file "$F" --id KF-002 --quiet
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$F" | cut -d' ' -f1)" = "$before" ]
}

@test "kf-write notes-header: prepends a dated cycle section under the title" {
  run bash "$KFW" notes-header --file "$NF" --date 2026-06-28 --cycle "cycle-okf sprint-5" --quiet
  [ "$status" -eq 0 ]
  # new header appears before the old one, after the '# ' title
  run grep -nE '^## Decision Log' "$NF"
  [[ "${lines[0]}" == *"2026-06-28"* ]]
  [[ "${lines[1]}" == *"2026-06-01"* ]]
}

@test "kf-write attempt: row lands in the Attempts table, NOT a table in a later subsection (KF-006 shape)" {
  # KF-001's Reading guide contains its own markdown table — the attempt must not target it.
  local G; G="$(mktemp)"
  cat > "$G" <<'EOF'
# Known Failures

## Index

| ID | Status | Feature | Recurrence |
|----|--------|---------|------------|
| [KF-001](#kf-001-foo) | OPEN | foo | 1 |

---

## KF-001: foo

**Status**: OPEN
**Recurrence count**: 1

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-06-01 | x | DID NOT WORK | #100 |

### Reading guide

When you see this, consult:

| Symptom | Action |
|---------|--------|
| boom | run X |
EOF
  run bash "$KFW" attempt --file "$G" --id KF-001 --date 2026-06-28 --what "newtry" --outcome "DID NOT WORK" --evidence "#777" --quiet
  [ "$status" -eq 0 ]
  # the new row must be ABOVE the '### Reading guide' line (i.e. inside the Attempts table)
  local attline newrow
  attline="$(grep -n '^### Reading guide' "$G" | cut -d: -f1)"
  newrow="$(grep -n '| 2026-06-28 | newtry |' "$G" | cut -d: -f1)"
  [ "$newrow" -lt "$attline" ]
  # the reading-guide table row is untouched
  grep -qF '| boom | run X |' "$G"
  rm -f "$G"
}

@test "kf-write new: a non-single-space '##  KF-NNN:' heading is seen (no duplicate id, reader grammar)" {
  local G; G="$(mktemp)"
  printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n| [KF-008](#kf-008-a) | OPEN | a | 1 |\n| [KF-009](#kf-009-b) | OPEN | b | 1 |\n\n---\n\n## KF-008: a\n\n**Status**: OPEN\n\n### Attempts\n\n| Date | What we tried | Outcome | Evidence |\n|------|---------------|---------|----------|\n| d | w | o | #1 |\n\n### Reading guide\n\ng\n\n##  KF-009: b\n\n**Status**: OPEN\n\n### Attempts\n\n| Date | What we tried | Outcome | Evidence |\n|------|---------------|---------|----------|\n| d | w | o | #2 |\n\n### Reading guide\n\ng\n' > "$G"
  run bash "$KFW" new --file "$G" --title "third" --status OPEN --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "KF-010" ]   # must skip KF-009 (two-space heading), not collide
  # exactly one KF-009 heading remains (no duplicate created)
  [ "$(grep -cE '^##[[:space:]]+KF-009:' "$G")" -eq 1 ]
  rm -f "$G"
}

@test "kf-write new: Index anchor preserves underscores (GitHub anchor parity)" {
  run bash "$KFW" new --file "$F" --title "beads_rust migration thing" --status OPEN --quiet
  [ "$status" -eq 0 ]
  grep -qE '^\| \[KF-003\]\(#kf-003-beads_rust-migration-thing\)' "$F"
}

@test "kf-write new: Index anchor keeps one hyphen per space around stripped punctuation (GitHub never collapses them)" {
  # cycle-126 thirty-first run, e2b DISS-C-001: `A / b` slugs to `a--b` on GitHub; the collapsed `a-b` link never resolved
  run bash "$KFW" new --file "$F" --title "PROVIDER_UNAVAILABLE / exit 1 — cheval's note" --status OPEN --quiet
  [ "$status" -eq 0 ]
  grep -qE '^\| \[KF-003\]\(#kf-003-provider_unavailable--exit-1--chevals-note\)' "$F" || { grep 'KF-003' "$F"; return 1; }
}

# The ledger link lint: every Index row's anchor is its heading's GitHub slug — the heading read as the library's grammar reads
# it (one or more blanks after `##`, trailing blanks trimmed) and slugged as GitHub does (a Unicode letter is kept, punctuation
# dropped, one hyphen per space): cycle-126 thirty-second run, e2c DISS-C-002
_kf_link_lint() {
  python3 - "$1" <<'PY'
import re, sys, unicodedata
s = open(sys.argv[1], encoding="utf-8").read()
# (a fenced block renders no heading and no link — a fenced example never shadows a real one: thirty-third run, e2c DISS-C-003;
# read as CommonMark does — an opener indented up to three spaces, a closer of its character at least as long with nothing
# after it, an unclosed fence running to the end, a backtick opener with no backtick in its info string: thirty-fifth run)
keep, fence = [], None
for line in s.split("\n"):
    m = re.match(r" {0,3}(`{3,}|~{3,})(.*)$", line)
    if fence is None:
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            fence = m.group(1)
        else:
            keep.append(line)
    elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
        fence = None
s = "\n".join(keep)
# (GitHub's slugger keeps \p{Word} — letters, marks, numbers but no Other_Number, connector punctuation, Other_Alphabetic
# symbols, ZWNJ/ZWJ: thirty-fourth run e2c DISS-C-001, thirty-fifth run e2c DISS-C-001 — the library's rule)
oa = ((0x24B6, 0x24E9), (0x1F130, 0x1F149), (0x1F150, 0x1F169), (0x1F170, 0x1F189))
def word(c):
    k = unicodedata.category(c)
    return k[0] in "LM" or k in ("Nd", "Nl", "Pc") or c in "\u200c\u200d" or any(a <= ord(c) <= b for a, b in oa)
# (a heading GitHub renders as other text than it reads has no raw-text anchor: thirty-fifth run, e2c DISS-C-002)
# (a backtick run of two or more, or a code span padded by a space at both ends, renders as other text: thirty-seventh run,
# e2c DISS-C-001 / DISS-C-002 — the library's refusal; with single backticks only, left-to-right pairing is CommonMark's)
# (a span is punctuation to its neighbours, never deleted, and an escaped backtick opens none: thirty-eighth run, e2c DISS-C-001)
def rendered_differs(h):
    t = re.sub(r"`[^`]*`", "'", h)
    p = h.split("`")
    if "``" in h or "\\`" in h or any(c.startswith(" ") and c.endswith(" ") and c.strip(" ") for c in p[1:len(p) - 1:2]):
        return True
    return bool(re.search(r"\]\(|\]\[|<[A-Za-z/!?]|&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);", t)
                or re.search(r"(^|[^\w])_+[^_\s](.*[^_\s])?_+([^\w]|$)", t) or re.search(r"(^|[ \t])#+[ \t]*$", t))   # (ASCII space or tab only, as the writer and CommonMark: thirty-ninth run, e2c DISS-C-001)
found = re.findall(r"^##[ \t]+(KF-\d+:.*?)[ \t]*$", s, re.M)
heads = {h.split(":")[0]: "".join(c for c in h.lower() if c in "- " or word(c)).replace(" ", "-") for h in found}
bad = [k for k, a in re.findall(r"^\| \[(KF-\d+)\]\(#([^)]*)\)", s, re.M) if heads.get(k) != a]
bad += [h.split(":")[0] for h in found if rendered_differs(h)]
# (a heading whose anchor the slug references disagree on — Other_Number, a format character, an Other_Alphabetic symbol, a
# context-dependent lowercase — has no settled anchor: thirty-sixth run, e2c DISS-C-002, the library's refusal)
def unsettled(h):
    return (any(unicodedata.category(c) in ("No", "Cf", "Cn") or any(a <= ord(c) <= b for a, b in oa) for c in h)
            or h.lower() != "".join(c.lower() for c in h))
bad += [h.split(":")[0] for h in found if unsettled(h)]
print("Index links that resolve to no heading:", bad) if bad else None
sys.exit(1 if bad else 0)
PY
}

@test "kf-write: every Index link in the shipped ledger names its entry's GitHub heading anchor" {
  # (cycle-126 thirty-first run, e2b DISS-C-001: nine rows the collapsing slug wrote, and three hand-made ones, linked nowhere)
  _kf_link_lint "$PROJECT_ROOT/grimoires/loa/known-failures.md"
}

@test "kf-write: the ledger link lint reads headings as the library and GitHub do — two blanks after ##, a trailing blank, a Unicode letter (thirty-second run, e2c DISS-C-002)" {
  local G="$BATS_TEST_TMPDIR/lint.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-two-blanks) | OPEN | x | 1 |' '| [KF-041](#kf-041-trailing-blank) | OPEN | x | 1 |' \
    '| [KF-042](#kf-042-café-timeout--retry) | OPEN | x | 1 |' '' '##  KF-040: Two blanks' '' '## KF-041: Trailing blank  ' '' '## KF-042: Café timeout — retry' > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # the ASCII-stripped slug GitHub never emits is a broken link (the fixture rewritten, never `sed -i` — BSD reads its next word
  # as a backup suffix: thirty-third run, e2c DISS-C-002)
  local B="$BATS_TEST_TMPDIR/lint-broken.md" line
  while IFS= read -r line; do printf '%s\n' "${line//#kf-042-café-timeout--retry/#kf-042-caf-timeout--retry}"; done < "$G" > "$B"
  ! grep -q 'café-timeout' "$B" || { echo "the broken fixture still holds the good slug"; return 1; }
  run _kf_link_lint "$B"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-042* ]]
}

@test "kf-write: the ledger link lint skips fenced blocks — a fenced example heading never shadows the real one, a fenced row is no link (thirty-third run, e2c DISS-C-003)" {
  local G="$BATS_TEST_TMPDIR/lint-fenced.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-real-heading) | OPEN | x | 1 |' '' '## KF-040: Real heading' '' \
    '```' '## KF-040: An example heading' '| [KF-041](#nowhere) | OPEN | x | 1 |' '```' '' '~~~md' '## KF-040: Another example' '~~~' > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "kf-write new: a non-ASCII title's Index anchor is the GitHub slug — its letters kept and lowercased, the link lint green (thirty-third run, e2c DISS-C-001)" {
  local G="$BATS_TEST_TMPDIR/utf8.md"
  printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G"
  run bash "$KFW" new --file "$G" --title "Naïve retry — CAFÉ_X" --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF '| [KF-001](#kf-001-naïve-retry--café_x) | OPEN' "$G" || { grep 'KF-001' "$G"; return 1; }
  run _kf_link_lint "$G"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # an ASCII title still slugs as before, without python
  run bash "$KFW" new --file "$G" --title "Plain / ASCII" --status OPEN --quiet
  [ "$status" -eq 0 ]
  grep -qF '| [KF-002](#kf-002-plain--ascii) | OPEN' "$G"
}

@test "kf-write new: a title that is not valid UTF-8 is refused before any write — never an anchor GitHub cannot match (thirty-third run, e2c DISS-C-001)" {
  local G="$BATS_TEST_TMPDIR/badutf8.md"
  printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G"
  local before; before="$(cksum < "$G")"
  run bash "$KFW" new --file "$G" --title "$(printf 'bad \377 byte')" --status OPEN --quiet
  [ "$status" -ne 0 ] || { echo "a non-UTF-8 title was written"; return 1; }
  [[ "$output" == *UTF-8* ]] || { echo "$output"; return 1; }
  [ "$(cksum < "$G")" = "$before" ] || { echo "the ledger changed"; return 1; }
}

@test "kf-write new: a non-UTF-8 title is refused before the ledger is touched even when it lacks its final newline (thirty-fourth run, e2c DISS-001)" {
  local G="$BATS_TEST_TMPDIR/nonl.md"
  printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---' > "$G"
  local before; before="$(cksum < "$G")"
  run bash "$KFW" new --file "$G" --title "$(printf 'bad \377 byte')" --status OPEN --quiet
  [ "$status" -ne 0 ] || { echo "a non-UTF-8 title was written"; return 1; }
  [ "$(cksum < "$G")" = "$before" ] || { echo "the ledger changed on a refused title"; return 1; }
}

@test "kf-write new: a python3 that fails for another reason is named, never reported as a non-UTF-8 title (thirty-fourth run, e2c DISS-C-002)" {
  local bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  printf '#!/bin/sh\necho "ModuleNotFoundError: No module named encodings" >&2\nexit 1\n' > "$bin/python3"; chmod +x "$bin/python3"
  run env PATH="$bin:$PATH" bash "$KFW" new --file "$F" --title "Café timeout" --status OPEN --quiet
  [ "$status" -ne 0 ] || { echo "a broken python3 wrote an entry"; return 1; }
  [[ "$output" != *"not valid UTF-8"* && "$output" == *python3* ]] || { echo "$output"; return 1; }
}

@test "kf-write new: a combining mark is kept in the anchor, as GitHub's slugger keeps every letter, mark, number and connector (thirty-fourth run, e2c DISS-C-001)" {
  local t; t="$(printf 'Nai\314\210ve retry\342\200\277x')"   # (NFD i + U+0308, and U+203F a connector punctuation)
  run bash "$KFW" new --file "$F" --title "$t" --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF "| [KF-003](#kf-003-$(printf 'nai\314\210ve-retry\342\200\277x')) |" "$F" || { grep 'KF-003' "$F"; return 1; }
  _kf_link_lint "$F" || { echo "the lint disagrees with the writer"; return 1; }
  # the lint refuses the mark-stripped anchor the old rule wrote
  local G="$BATS_TEST_TMPDIR/nfd.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-naive-retry) | OPEN | x | 1 |' '' "## KF-040: $(printf 'Nai\314\210ve retry')" > "$G"
  ! _kf_link_lint "$G" >/dev/null || { echo "a mark-stripped anchor passed the lint"; return 1; }
}

@test "kf-write new: can create the FIRST entry in an empty-Index ledger" {
  local G; G="$(mktemp)"
  printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G"
  run bash "$KFW" new --file "$G" --title "first ever" --status OPEN --quiet
  [ "$status" -eq 0 ]
  [ "$output" = "KF-001" ]
  grep -qE '^\| \[KF-001\]\(#kf-001-first-ever\) \| OPEN' "$G"
  grep -qE '^## KF-001: first ever$' "$G"
  rm -f "$G"
}

@test "kf-write new: result still parses under the canonical kf-auto-link.py reader" {
  command -v python3 >/dev/null || skip "python3 not available"
  bash "$KFW" new --file "$F" --title "compat check entry" --status OPEN --feature "f" --quiet
  run python3 -c "
import sys, importlib.util
spec=importlib.util.spec_from_file_location('kfal','$PROJECT_ROOT/.claude/scripts/lib/kf-auto-link.py')
m=importlib.util.module_from_spec(spec); sys.modules['kfal']=m; spec.loader.exec_module(m)
entries=m.parse_known_failures(open('$F').read())
print(len(entries))
"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

@test "kf-write new: a Unicode line separator (U+2028, U+2029, U+0085 NEL) or another C1 control is a space, never a line break the canonical reader splits into a phantom ## KF- heading (cycle-126 audit run 1, e2c DISS-C-001)" {
  command -v python3 >/dev/null || skip "python3 not available"
  local t
  t="$(printf 'probe \342\200\250## KF-001: phantom \342\200\251## KF-002: two \302\205## KF-003: three \302\233x end')"
  bash "$KFW" new --file "$F" --title "$t" --status OPEN --feature "$t" --symptom "$t" --quiet
  ! LC_ALL=C grep -q "$(printf '\342\200[\250\251]')" "$F" || { echo "a U+2028/U+2029 byte reached the ledger"; return 1; }
  ! LC_ALL=C grep -q "$(printf '\302[\200-\237]')" "$F" || { echo "a C1 control reached the ledger"; return 1; }
  grep -qF '## KF-003: probe ## KF-001: phantom ## KF-002: two ## KF-003: three x end' "$F" || { grep -n 'KF-003' "$F"; return 1; }
  run python3 -c '
import sys, importlib.util
spec=importlib.util.spec_from_file_location("kfal", sys.argv[1])
m=importlib.util.module_from_spec(spec); sys.modules["kfal"]=m; spec.loader.exec_module(m)
print(len(m.parse_known_failures(open(sys.argv[2], encoding="utf-8").read())))
' "$PROJECT_ROOT/.claude/scripts/lib/kf-auto-link.py" "$F"
  [ "$status" -eq 0 ] || { echo "the canonical reader failed: $output"; return 1; }
  [ "$output" -eq 3 ]
}

@test "kf-write new: the anchor keeps what GitHub's word class keeps — a titlecase and a modifier letter, a letter number, a non-ASCII digit and a connector kept, a symbol dropped — and the link lint agrees (thirty-fifth run, e2c DISS-C-001; the ambiguous characters are refused since the thirty-sixth run, e2c DISS-C-002)" {
  local t want
  local G0="$BATS_TEST_TMPDIR/e2c35.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  t="$(printf 'O(n) \307\205 \312\260 \342\205\253 \331\243 x\342\200\277y \342\230\205')"
  want="$(printf 'kf-001-on-\307\206-\312\260-\342\205\273-\331\243-x\342\200\277y-')"
  # (GitHub's slug: lowercase, drop all but \p{Word} — Alphabetic, Mark, Decimal_Number, Connector_Punctuation, Join_Control —
  # hyphen and space; perl's \w is that class, so a perl present re-derives the expectation)
  if command -v perl >/dev/null 2>&1; then
    local p; p="$(printf '%s' "KF-001: $t" | perl -CSD -Mfeature=unicode_strings -ne '$_ = lc; s/[^\w\- ]//g; s/ /-/g; print')"
    [ "$p" = "$want" ] || { echo "the fixture's expectation is not perl's \\w slug: $p"; return 1; }
  fi
  run bash "$KFW" new --file "$G0" --title "$t" --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF "| [KF-001](#$want) | OPEN" "$G0" || { grep 'KF-001' "$G0"; return 1; }
  run _kf_link_lint "$G0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # the lint refuses the slug that kept the Other_Number
  local G="$BATS_TEST_TMPDIR/lint-no.md"
  printf '%s\n' '# KF' '' '## Index' '' "$(printf '| [KF-040](#kf-040-on\302\262) | OPEN | x | 1 |')" '' "$(printf '## KF-040: O(n\302\262)')" > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "an Other_Number kept in the anchor passed the lint: $output"; return 1; }
}

@test "kf-write new: a title GitHub renders differently from its raw text — a link, an HTML tag, a character reference, an underscore emphasis outside a code span, a closing # sequence — is refused before any write, and the link lint names such a heading (thirty-fifth run, e2c DISS-C-002)" {
  local G0="$BATS_TEST_TMPDIR/e2c35.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local F="$G0" before t; before="$(cksum < "$F")"
  for t in 'see [the docs](http://x) here' 'an <b>html</b> tag' 'a &amp; b' 'a &#38; b' 'the _emph_ word' '_a_ alone' 'closing hashes ##'; do
    run bash "$KFW" new --file "$F" --title "$t" --status OPEN --quiet
    [ "$status" -ne 0 ] || { echo "'$t' was written"; return 1; }
    [[ "$output" == *renders* ]] || { echo "'$t': $output"; return 1; }
    [ "$(cksum < "$F")" = "$before" ] || { echo "'$t' changed the ledger"; return 1; }
  done
  # an identifier's underscores, a code span, a lone ampersand, an inner # are text GitHub renders as written
  run bash "$KFW" new --file "$F" --title 'ledger-lib _write_ledger accepts `_x_` & C# input' --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF '| [KF-001](#kf-001-ledger-lib-_write_ledger-accepts-_x_--c-input) | OPEN' "$F" || { grep 'KF-001' "$F"; return 1; }
  run _kf_link_lint "$F"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  local G="$BATS_TEST_TMPDIR/lint-rendered.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-see-the-docshttpx) | OPEN | x | 1 |' '' '## KF-040: See [the docs](http://x)' > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "a heading with a link passed the lint: $output"; return 1; }
}

@test "kf-write: the ledger link lint reads fences as CommonMark does — an opener indented up to three spaces, a closer at least as long as its opener, an unclosed fence running to the end (thirty-fifth run, e2c DISS-C-003)" {
  local G="$BATS_TEST_TMPDIR/lint-cm.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-real) | OPEN | x | 1 |' '' '## KF-040: Real' '' \
    '````md' '```' '## KF-040: Inside a four-backtick fence' '```' '````' '' \
    '   ~~~' '## KF-040: Inside an indented fence' '   ~~~' '' \
    '```' '| [KF-041](#nowhere) | OPEN | x | 1 |' '## KF-040: Inside an unclosed fence' > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # a heading after a closed fence is read again
  printf '%s\n' '```' 'x' '```' '' '| [KF-042](#nowhere) | OPEN | x | 1 |' > "$BATS_TEST_TMPDIR/lint-after.md"
  run _kf_link_lint "$BATS_TEST_TMPDIR/lint-after.md"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-042* ]] || { echo "a row after a closed fence went unread: $output"; return 1; }
}

@test "kf-write new: a title whose GitHub anchor the references disagree on — an Other_Number (², ½, ①), a format character (ZWJ, ZWNJ), an Other_Alphabetic symbol (Ⓐ, 🄰), a word-final capital sigma — is refused before any write, and the link lint names such a heading (thirty-sixth run, e2c DISS-C-002)" {
  local G0="$BATS_TEST_TMPDIR/e2c36.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local before t; before="$(cksum < "$G0")"
  for t in "$(printf 'O(n\302\262) growth')" "$(printf 'half \302\275 done')" "$(printf 'step \342\221\240')" "$(printf 'a\342\200\215b')" \
           "$(printf 'c\342\200\214d')" "$(printf 'circled \342\222\266')" "$(printf 'squared \360\237\204\260')" "$(printf '\316\237\316\224\316\237\316\243 timeout')"; do
    run bash "$KFW" new --file "$G0" --title "$t" --status OPEN --quiet
    [ "$status" -ne 0 ] || { echo "'$t' was written"; return 1; }
    [[ "$output" == *"not settled"* ]] || { echo "'$t': $output"; return 1; }
    [ "$(cksum < "$G0")" = "$before" ] || { echo "'$t' changed the ledger"; return 1; }
  done
  # a capital sigma that is not word-final lowercases the same either way, and is kept
  run bash "$KFW" new --file "$G0" --title "$(printf '\316\243\316\237\316\246\316\231\316\221 retry')" --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run _kf_link_lint "$G0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  local G="$BATS_TEST_TMPDIR/lint-amb.md"
  printf '%s\n' '# KF' '' '## Index' '' "$(printf '| [KF-040](#kf-040-on) | OPEN | x | 1 |')" '' "$(printf '## KF-040: O(n\302\262)')" > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "a heading with an ambiguous character passed the lint: $output"; return 1; }
}

@test "kf-write new: a title with a backtick run of two or more, or a code span padded by a space at both ends, is refused before any write — CommonMark pairs backtick runs by length and strips that padding, so the raw slug is no anchor — and the link lint names such a heading (thirty-seventh run, e2c DISS-C-001 / DISS-C-002)" {
  local G0="$BATS_TEST_TMPDIR/e2c37.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local before t; before="$(cksum < "$G0")"
  for t in 'x ``` _a_ ` y' 'a ``b`` c' 'run ` x ` now' 'pad `  two  ` spans'; do
    run bash "$KFW" new --file "$G0" --title "$t" --status OPEN --quiet
    [ "$status" -ne 0 ] || { echo "'$t' was written"; return 1; }
    [[ "$output" == *renders* ]] || { echo "'$t': $output"; return 1; }
    [ "$(cksum < "$G0")" = "$before" ] || { echo "'$t' changed the ledger"; return 1; }
  done
  # one-sided padding, an all-space span, a lone backtick and the space between two spans are rendered as written
  run bash "$KFW" new --file "$G0" --title 'the `_x_` and `y ` and ` ` then `a` x `b` or a lone ` tick' --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF '| [KF-001](#kf-001-the-_x_-and-y--and---then-a-x-b-or-a-lone--tick) | OPEN' "$G0" || { grep 'KF-001' "$G0"; return 1; }
  run _kf_link_lint "$G0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  local G="$BATS_TEST_TMPDIR/lint-cs.md" h
  for h in 'run ` x ` now|kf-040-run--x--now' 'a ``b`` c|kf-040-a-b-c'; do
    printf '%s\n' '# KF' '' '## Index' '' "| [KF-040](#${h#*|}) | OPEN | x | 1 |" '' "## KF-040: ${h%%|*}" > "$G"
    run _kf_link_lint "$G"
    [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "'${h%%|*}' passed the lint: $output"; return 1; }
  done
}

@test "kf-write new: a code span is punctuation beside an underscore and a backslash-escaped backtick opens no span — x\`a\`_y_ and a \\\`_x_\` c render emphasis on GitHub, so both are refused before any write and the link lint names both; the anchor call site checks its own status (thirty-eighth run, e2c DISS-C-001 / DISS-C-002)" {
  local G0="$BATS_TEST_TMPDIR/e2c38.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local before t; before="$(cksum < "$G0")"
  for t in 'x`a`_y_' '_y_`a`x' 'a \`_x_` c' 'run `a`_b_ now'; do
    run bash "$KFW" new --file "$G0" --title "$t" --status OPEN --quiet
    [ "$status" -ne 0 ] || { echo "'$t' was written"; return 1; }
    [[ "$output" == *renders* ]] || { echo "'$t': $output"; return 1; }
    [ "$(cksum < "$G0")" = "$before" ] || { echo "'$t' changed the ledger"; return 1; }
  done
  # a span beside an intraword underscore pair, and spans joined by text, are rendered as written
  run bash "$KFW" new --file "$G0" --title 'the `a`_b_c and [x]`y`(z) case' --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run _kf_link_lint "$G0"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  local G="$BATS_TEST_TMPDIR/lint-cs38.md" h
  for h in 'x`a`_y_|kf-040-xa_y_' 'a \`_x_` c|kf-040-a-_x_-c'; do
    printf '%s\n' '# KF' '' '## Index' '' "| [KF-040](#${h#*|}) | OPEN | x | 1 |" '' "## KF-040: ${h%%|*}" > "$G"
    run _kf_link_lint "$G"
    [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "'${h%%|*}' passed the lint: $output"; return 1; }
  done
  # (DISS-C-002: a refusal raised inside the anchor substitution reaches the caller by the call site's own check, not by
  # errexit on a bare assignment alone)
  grep -qF 'tail="$(gh_anchor ": ${title}")" || exit 1' "$KFW" || { echo "the anchor call site leans on errexit"; return 1; }
}

@test "kf-write new: an underscore emphasis bounded by non-ASCII punctuation — “_x_”, —_x_— — is refused like an ASCII-bounded one: CommonMark reads Unicode punctuation as punctuation, so GitHub renders it as emphasis (thirty-sixth run, e2c DISS-C-001)" {
  local G0="$BATS_TEST_TMPDIR/e2c36b.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local before t; before="$(cksum < "$G0")"
  for t in "$(printf 'the \342\200\234_quoted_\342\200\235 word')" "$(printf 'a \342\200\224_dash_\342\200\224 aside')" "$(printf '\302\253_g_\302\273')"; do
    run bash "$KFW" new --file "$G0" --title "$t" --status OPEN --quiet
    [ "$status" -ne 0 ] || { echo "'$t' was written"; return 1; }
    [[ "$output" == *renders* ]] || { echo "'$t': $output"; return 1; }
    [ "$(cksum < "$G0")" = "$before" ] || { echo "'$t' changed the ledger"; return 1; }
  done
  # the lint names the heading the writer now refuses
  local G="$BATS_TEST_TMPDIR/lint-uq.md"
  # (the anchor is the heading's slug as written — the curly quotes dropped — so only the rendered-text leg can fail it; no GNU-only
  # sed \xHH: thirty-seventh run, e2c DISS-C-003)
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-the-_quoted_-word) | OPEN | x | 1 |' '' "$(printf '## KF-040: the \342\200\234_quoted_\342\200\235 word')" > "$G"
  local C="$BATS_TEST_TMPDIR/lint-uq-ok.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-the-quoted-word) | OPEN | x | 1 |' '' "$(printf '## KF-040: the \342\200\234quoted\342\200\235 word')" > "$C"
  run _kf_link_lint "$C"
  [ "$status" -eq 0 ] || { echo "the control (no emphasis) failed the lint, so the anchor rule is not what the fixture assumes: $output"; return 1; }
  run _kf_link_lint "$G"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "the lint passed a Unicode-bounded emphasis: $output"; return 1; }
}

@test "kf-write new: a code point unassigned in this host's Unicode database is refused as unsettled (a newer GitHub may call it a letter), and the link lint names it; a Unicode space before a closing # is text to the writer and to the lint alike (thirty-ninth run, e2c DISS-C-002 / DISS-C-001)" {
  local G0="$BATS_TEST_TMPDIR/e2c39.md"; printf '# KF\n\n## Index\n\n| ID | Status | Feature | Recurrence |\n|----|--------|---------|------------|\n\n---\n' > "$G0"
  local before; before="$(cksum < "$G0")"
  run bash "$KFW" new --file "$G0" --title "$(printf 'an unassigned code point \315\270 here')" --status OPEN --quiet
  [ "$status" -ne 0 ] && [[ "$output" == *"not settled"* ]] || { echo "an unassigned code point was written: $output"; return 1; }
  [ "$(cksum < "$G0")" = "$before" ] || { echo "the refusal changed the ledger"; return 1; }
  local G="$BATS_TEST_TMPDIR/lint-cn.md"
  printf '%s\n' '# KF' '' '## Index' '' '| [KF-040](#kf-040-ab) | OPEN | x | 1 |' '' "$(printf '## KF-040: a\315\270b')" > "$G"
  run _kf_link_lint "$G"
  [ "$status" -eq 1 ] && [[ "$output" == *KF-040* ]] || { echo "the lint passed an unassigned code point: $output"; return 1; }
  # (CommonMark's closing sequence follows an ASCII space or tab only: an NBSP before it leaves the hashes as text)
  run bash "$KFW" new --file "$G0" --title "$(printf 'issue C\302\240##')" --status OPEN --quiet
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run _kf_link_lint "$G0"
  [ "$status" -eq 0 ] || { echo "the lint is stricter than the writer on a Unicode space before #: $output"; return 1; }
}
