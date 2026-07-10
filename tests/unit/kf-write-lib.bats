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
