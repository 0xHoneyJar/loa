#!/usr/bin/env bats
# =============================================================================
# evals/tests/annotation-packets.bats — cycle-132 Sprint 1 Task 1.3 (FR-2,
# SDD §1.4 "Annotation packets and merge", §5.2, D-7.6)
#
# annotation-packets.sh over a synthetic fixture: a repo with head and fix
# commits, a record branch carrying the sprint's feedback (a review citing
# a.sh:14, a quoted snippet from d.sh, a dissent envelope anchoring b.sh), a
# corpus fixture dir with labels and a manifest, and an incident scan. Proves:
# the packet is deterministic and holds exactly the three files; hunks carry
# ids, ranges and head context; review_driven is tagged from the citations and
# lives outside the packet; the leak check fails closed on a label, manifest,
# feedback or --deny-dir line and exempts the fixture's own code; a sample label
# file validates against annotation.schema.json.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  PK="$REPO_ROOT/evals/harness/annotation-packets.sh"
  SCHEMA="$REPO_ROOT/evals/harness/schemas/annotation.schema.json"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ap.XXXXXX")"
  G="$T/repo"; C="$T/corpus"; O="$T/packets"
  mkdir -p "$G/scripts" "$C/labels" "$C/manifests" "$C/incidents/pr-60/evidence"
  gc() { git -C "$G" -c user.email=t@t -c user.name=t "$@"; }
  git -C "$G" init -q -b main
  local i
  for i in $(seq 1 30); do echo "a_line_$i=\"value number $i of the a script\""; done > "$G/scripts/a.sh"
  for i in $(seq 1 30); do echo "b_line_$i=\"value number $i of the b script\""; done > "$G/scripts/b.sh"
  for i in $(seq 1 30); do echo "c_line_$i=\"value number $i of the c script\""; done > "$G/scripts/c.sh"
  for i in $(seq 1 30); do echo "d_line_$i=\"value number $i of the d script\""; done > "$G/scripts/d.sh"
  gc add -A; gc commit -q -m base; BASE="$(git -C "$G" rev-parse HEAD)"
  sed -i 's/^a_line_10=.*/a_line_10="changed at head"/' "$G/scripts/a.sh"
  for f in b c d; do sed -i "s/^${f}_line_10=.*/${f}_line_10=\"changed at head\"/" "$G/scripts/$f.sh"; done
  gc commit -qam "feat: sprint-6 head"; HEAD_C="$(git -C "$G" rev-parse HEAD)"
  # the fix: a.sh line 15 (near the cited line 14) and an insertion after line 25; b.sh line 22
  # (the dissent anchor); c.sh lines 5 and 7 (uncited; one hunk: 3 lines of inter-hunk context);
  # d.sh line 20 (the quoted snippet)
  sed -i 's/^a_line_15=.*/a_line_15="fixed"/; /^a_line_25=/a a_inserted_guard="new check"' "$G/scripts/a.sh"
  sed -i 's/^b_line_22=.*/b_line_22="fixed"/' "$G/scripts/b.sh"
  sed -i 's/^c_line_5=.*/c_line_5="fixed"/; s/^c_line_7=.*/c_line_7="fixed too"/' "$G/scripts/c.sh"
  sed -i 's/^d_line_20=.*/d_line_20="fixed"/' "$G/scripts/d.sh"
  gc commit -qam "fix: sprint-6 review round 1 — the a.sh empty value"; FIX="$(git -C "$G" rev-parse HEAD)"
  # the record branch: feedback under a2a/sprint-6/ (plus a non-feedback report that is never read)
  gc checkout -q --orphan record/cycle-6-a2a
  git -C "$G" rm -rq --cached .; find "$G" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  mkdir -p "$G/grimoires/loa/a2a/sprint-6"
  cat > "$G/grimoires/loa/a2a/sprint-6/engineer-feedback-r1.md" <<'MD'
# Sprint 6 review — round 1

## Findings

### HIGH-1 — the a script accepts an empty value at its entry point

`scripts/a.sh:14` takes the value without a check; the reviewer wants a guard here.

### LOW-1 — the d script keeps a stale default in its lower half

In `d.sh` the assignment `d_line_20="value number 20 of the d script"` is stale:

    d_line_20="value number 20 of the d script"
MD
  printf '{"findings":[{"id":"DISS-C-001","severity":"ADVISORY","anchor":"scripts/b.sh:b_line","anchor_line":21,"description":"the b script default drifts from the documented default"}]}\n' \
    > "$G/grimoires/loa/a2a/sprint-6/adversarial-review.json"
  printf '# implementation report\n\nscripts/c.sh:5 was touched.\n' > "$G/grimoires/loa/a2a/sprint-6/reviewer.md"
  gc add -A; gc commit -q -m record; gc checkout -q main
  # the corpus fixture (as the seeder writes it)
  mkdir -p "$C/pr-60"
  git -C "$G" archive "$HEAD_C" scripts | tar -x -C "$T" && mkdir -p "$C/pr-60/head" && mv "$T/scripts" "$C/pr-60/head/"
  git -C "$G" archive "$BASE" scripts | tar -x -C "$T" && mkdir -p "$C/pr-60/base" && mv "$T/scripts" "$C/pr-60/base/"
  git -C "$G" diff "$BASE" "$HEAD_C" > "$C/pr-60/head.diff"
  printf 'name: pr-60\nsprint: 6\nbase_commit: "%s"\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-6-a2a"\nfeedback_files:\n  - "grimoires/loa/a2a/sprint-6/engineer-feedback-r1.md"\n' \
    "$BASE" "$HEAD_C" "$FIX" > "$C/pr-60/fixture.yaml"
  {
    echo "# approved-by: pending"
    echo "# L01 high review: the a script accepts an empty value at its entry point [fix hunk near cited line 14]"
    printf 'defect_id\tseverity\tcategory\tfile\tmust_match\tlabel_source\tsource\n'
    printf 'L01-the-a-script-accepts-an-empty-value\thigh\tlogic\tscripts/a.sh\ta_line_15="value number 15 of the a script"\treview\trecord/cycle-6-a2a:engineer-feedback-r1.md#L5\n'
  } > "$C/labels/pr-60.tsv"
  printf '{\n  "fixture": "pr-60",\n  "defects": [{"id": "L01-the-a-script-accepts-an-empty-value", "description": "the hidden key says the empty value is accepted"}]\n}\n' > "$C/manifests/pr-60.json"
  printf 'id\tkind\tref\tdate\tfiles\texcerpt\nI01\tfix-commit\tabc123def456\t2026-10-12T00:00:00Z\tscripts/c.sh\tfix(c): post-merge guard\n' > "$C/incidents/pr-60.tsv"
  printf 'commit abc123def456\nDate: 2026-10-12T00:00:00Z\n\nfix(c): post-merge guard\n\ndiff --git a/scripts/c.sh b/scripts/c.sh\n-c_line_7="value number 7 of the c script"\n+c_line_7="guarded"\n' \
    > "$C/incidents/pr-60/evidence/I01.diff"
  ARGS=(--repo "$G" --corpus "$C" --out "$O")
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "AP-1 the packet holds exactly codebook.md, hunks.md, incidents.md; hunks.meta.json sits outside it; output is deterministic with no absolute path" {
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(ls "$O/pr-60" | tr '\n' ,)" = "codebook.md,hunks.md,incidents.md," ]
  [ -f "$O/pr-60.hunks.meta.json" ]
  cmp -s "$O/pr-60/codebook.md" "$REPO_ROOT/evals/harness/annotation/codebook.md"
  ! grep -rqF "$T" "$O"
  ! grep -rqF "$REPO_ROOT" "$O"
  cp -R "$O" "$T/first"
  run "$PK" pr-60 "${ARGS[@]}" --out "$T/second"
  [ "$status" -eq 0 ]
  diff -r "$T/first" "$T/second"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  diff -r "$T/first" "$O"
}

@test "AP-2 every fix hunk has an id, its path, the head-side range and the head context; an insertion is named; --context changes the window" {
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  H="$O/pr-60/hunks.md"
  [ "$(grep '^## H' "$H" | tr '\n' '|')" = "## H01 — scripts/a.sh — head line 15|## H02 — scripts/a.sh — insertion after head line 25|## H03 — scripts/b.sh — head line 22|## H04 — scripts/c.sh — head lines 5–7|## H05 — scripts/d.sh — head line 20|" ]
  grep -q '^>   15 | a_line_15="value number 15 of the a script"$' "$H"
  grep -q '^     3 | a_line_3=' "$H"
  grep -q '^    27 | a_line_27=' "$H"
  ! grep -q '^     2 | a_line_2=' "$H"
  grep -q '^+a_line_15="fixed"$' "$H"
  grep -q '^-a_line_15="value number 15 of the a script"$' "$H"
  run "$PK" pr-60 "${ARGS[@]}" --context 2
  [ "$status" -eq 0 ]
  grep -q '^    13 | a_line_13=' "$H"
  ! grep -q '^    12 | a_line_12=' "$H"
}

@test "AP-3 review_driven: true for a hunk within ±3 of a path:line citation, a dissent anchor_line or a quoted snippet; false for an uncited hunk; never inside the packet" {
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  M="$O/pr-60.hunks.meta.json"
  rd() { jq -r --arg f "$1" --argjson s "$2" '[.hunks[] | select(.file == $f and .head_start == $s) | .review_driven] | .[0]' "$M"; }
  [ "$(rd scripts/a.sh 15)" = "true" ]
  [ "$(rd scripts/a.sh 25)" = "false" ]
  [ "$(rd scripts/b.sh 22)" = "true" ]
  [ "$(rd scripts/c.sh 5)" = "false" ]
  [ "$(rd scripts/d.sh 20)" = "true" ]
  jq -e '[.hunks[] | select(.file == "scripts/a.sh" and .head_start == 15) | .cited_by[]] | any(test("engineer-feedback-r1.md#L7$"))' "$M"
  jq -e '[.hunks[] | select(.file == "scripts/b.sh") | .cited_by[]] | any(test("adversarial-review.json:DISS-C-001$"))' "$M"
  # every hunk is tagged; the report file (reviewer.md, not feedback) is never read
  [ "$(jq -r '[.hunks[] | has("review_driven")] | all' "$M")" = "true" ]
  [ "$(jq -r '.feedback_files | join(",")' "$M")" = "grimoires/loa/a2a/sprint-6/adversarial-review.json,grimoires/loa/a2a/sprint-6/engineer-feedback-r1.md" ]
  ! grep -rq 'review_driven\|cited_by' "$O/pr-60"
}

@test "AP-4 the leak check fails closed on a feedback line, a label row and a manifest line; nothing is written and the line is printed" {
  local line='`scripts/a.sh:14` takes the value without a check; the reviewer wants a guard here.'
  printf '%s\n' "$line" >> "$C/incidents/pr-60/evidence/I01.diff"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 1 ]
  grep -qF 'leak: incidents.md:' <<<"$output"
  grep -qF 'reviewer wants a guard here' <<<"$output"
  grep -qF 'engineer-feedback-r1.md' <<<"$output"
  [ ! -e "$O/pr-60" ] && [ ! -e "$O/pr-60.hunks.meta.json" ]
  # a label row (its comment line) in an incident summary
  sed -i '$d' "$C/incidents/pr-60/evidence/I01.diff"
  printf 'I02\tissue\t#5\t2026-10-13T00:00:00Z\tscripts/a.sh\t# L01 high review: the a script accepts an empty value at its entry point [fix hunk near cited line 14]\n' >> "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 1 ]; grep -qF 'labels/pr-60.tsv' <<<"$output"
  # a manifest line
  sed -i '$d' "$C/incidents/pr-60.tsv"
  printf 'I02\tissue\t#5\t2026-10-13T00:00:00Z\tscripts/a.sh\t"defects": [{"id": "L01-the-a-script-accepts-an-empty-value", "description": "the hidden key says the empty value is accepted"}]\n' >> "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 1 ]; grep -qF 'manifests/pr-60.json' <<<"$output"
  [ ! -e "$O/pr-60" ]
}

@test "AP-5 --deny-dir adds a run directory's lines to the check; the fixture's own code quoted by feedback is exempt" {
  mkdir -p "$T/results/run-1"
  printf 'A finding from an arm: the c script post-merge guard is missing entirely here.\n' > "$T/results/run-1/review.md"
  printf 'I02\tissue\t#5\t2026-10-13T00:00:00Z\tscripts/c.sh\tA finding from an arm: the c script post-merge guard is missing entirely here.\n' >> "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  rm -rf "$O"
  run "$PK" pr-60 "${ARGS[@]}" --deny-dir "$T/results/run-1"
  [ "$status" -eq 1 ]; grep -qF 'run-1/review.md' <<<"$output"
  # the feedback quotes a d.sh head line verbatim (code): shown in the context, not a leak
  sed -i '$d' "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}" --deny-dir "$T/results/run-1"
  [ "$status" -eq 0 ]
  grep -qF 'd_line_20="value number 20 of the d script"' "$O/pr-60/hunks.md"
}

@test "AP-6 incidents.md lists every TSV row with its fenced evidence; a missing scan is refused unless --no-incidents; usage errors exit 2" {
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  I="$O/pr-60/incidents.md"
  grep -q '^## I01 — fix-commit — 2026-10-12$' "$I"
  grep -q '^- files: scripts/c.sh$' "$I"
  grep -q '^~~~~diff$' "$I"
  grep -q '^+c_line_7="guarded"$' "$I"
  rm "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 1 ]; grep -q 'run incident-scan.sh first' <<<"$output"
  run "$PK" pr-60 "${ARGS[@]}" --no-incidents
  [ "$status" -eq 0 ]
  grep -q 'No incident scan was supplied' "$O/pr-60/incidents.md"
  run "$PK" pr-60 "${ARGS[@]}" --context 101
  [ "$status" -eq 2 ]
  run "$PK" pr-61 "${ARGS[@]}" --no-incidents
  [ "$status" -eq 1 ]
  run "$PK" "${ARGS[@]}"
  [ "$status" -eq 2 ]
}

@test "AP-7 annotation.schema.json accepts the codebook's example and a complete sample label file; rejects a defect without a group, a not-defect without a class, a bad id and a non-positive anchor" {
  # -P (not -I): the validator reads only this test's files, and jsonschema may live in the user site
  python3 -P -c 'import jsonschema' 2>/dev/null || skip "python jsonschema not installed"
  cat > "$T/good.json" <<'JSON'
{"hunks": {"H01": {"verdict": "defect", "not_defect_class": null, "group": "D1", "file": "scripts/a.sh", "anchor_lines": [14, 15], "description": "Accepts an empty value.", "severity": "high", "category": "input-validation"},
           "H02": {"verdict": "not-defect", "not_defect_class": "follow-on", "group": "D1", "file": "scripts/a.sh", "anchor_lines": [], "description": "Second copy of the guard.", "severity": null, "category": null},
           "H03": {"verdict": "not-defect", "not_defect_class": "test", "group": null, "file": "scripts/b.sh", "anchor_lines": [], "description": "", "severity": null, "category": null}},
 "incidents": {"I01": {"verdict": "defect-at-head", "group": "D2", "file": "scripts/c.sh", "anchor_lines": [7], "description": "Missing guard.", "severity": "medium"},
               "I02": {"verdict": "not-at-head", "group": null, "file": null, "anchor_lines": [], "description": "", "severity": null}}}
JSON
  # the codebook's own example block
  awk '/^```json$/{p=1;next} /^```$/{p=0} p' "$REPO_ROOT/evals/harness/annotation/codebook.md" > "$T/codebook-example.json"
  v() { python3 -P -c 'import json,sys,jsonschema; jsonschema.validate(json.load(open(sys.argv[2])), json.load(open(sys.argv[1])))' "$SCHEMA" "$1"; }
  v "$T/good.json"
  v "$T/codebook-example.json"
  jq '.hunks.H01.group = null' "$T/good.json" > "$T/b1.json"; ! v "$T/b1.json" 2>/dev/null
  jq '.hunks.H03.not_defect_class = null' "$T/good.json" > "$T/b2.json"; ! v "$T/b2.json" 2>/dev/null
  jq '.hunks.X1 = .hunks.H01' "$T/good.json" > "$T/b3.json"; ! v "$T/b3.json" 2>/dev/null
  jq '.hunks.H01.anchor_lines = [0]' "$T/good.json" > "$T/b4.json"; ! v "$T/b4.json" 2>/dev/null
  jq '.incidents.I01.anchor_lines = []' "$T/good.json" > "$T/b5.json"; ! v "$T/b5.json" 2>/dev/null
  jq '.hunks.H03.group = "D3"' "$T/good.json" > "$T/b6.json"; ! v "$T/b6.json" 2>/dev/null
}

@test "AP-8 annotation.schema.json uses only the keywords annotation_merge.py's stdlib validator supports (no if/then, propertyNames, …)" {
  python3 -I - "$SCHEMA" <<'PY'
import json, sys
OK = {"type", "properties", "required", "additionalProperties", "patternProperties", "enum", "const", "items",
      "minItems", "maxItems", "uniqueItems", "minimum", "maximum", "minLength", "maxLength", "pattern", "oneOf",
      "anyOf", "allOf", "not", "$ref", "$defs", "definitions", "$schema", "$id", "title", "description",
      "$comment", "examples", "default", "format"}
MAPS = {"properties", "patternProperties", "$defs", "definitions"}
bad = []
def walk(o, path):
    if isinstance(o, dict):
        for k, v in o.items():
            if k not in OK:
                bad.append(f"{path}/{k}")
            if k in MAPS:
                for n, sub in v.items():
                    walk(sub, f"{path}/{k}/{n}")
            elif k in ("enum", "const", "examples", "default", "required"):
                continue
            else:
                walk(v, f"{path}/{k}")
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, f"{path}/{i}")
walk(json.load(open(sys.argv[1])), "")
if bad:
    sys.exit("unsupported keywords: " + ", ".join(bad))
PY
}

@test "AP-9 citations of files with 7–12 character extensions (.loa.config.yaml.example:127, Dockerfile.ablation:19) tag their hunks review_driven" {
  local G2="$T/repo2" C2="$T/corpus2" i
  mkdir -p "$G2/evals/harness" "$C2/incidents"
  gc2() { git -C "$G2" -c user.email=t@t -c user.name=t "$@"; }
  git -C "$G2" init -q -b main
  for i in $(seq 1 140); do echo "key_$i: value $i of the example config"; done > "$G2/.loa.config.yaml.example"
  for i in $(seq 1 40); do echo "RUN step $i of the ablation image"; done > "$G2/evals/harness/Dockerfile.ablation"
  gc2 add -A; gc2 commit -q -m base; local B2; B2="$(git -C "$G2" rev-parse HEAD)"
  sed -i 's/^key_5: .*/key_5: changed at head/' "$G2/.loa.config.yaml.example"
  sed -i 's/^RUN step 5 .*/RUN step 5 changed at head/' "$G2/evals/harness/Dockerfile.ablation"
  gc2 commit -qam head; local H2; H2="$(git -C "$G2" rev-parse HEAD)"
  sed -i 's/^key_127: .*/key_127: fixed/' "$G2/.loa.config.yaml.example"
  sed -i 's/^RUN step 19 .*/RUN step 19 fixed/' "$G2/evals/harness/Dockerfile.ablation"
  gc2 commit -qam fix; local F2; F2="$(git -C "$G2" rev-parse HEAD)"
  # the record branch, built from a separate work tree so main's files stay untouched
  local R2="$T/rec2"
  git -C "$G2" worktree add -q --detach "$R2" "$H2"
  git -C "$R2" checkout -q --orphan record/cycle-7-a2a
  git -C "$R2" rm -rq --cached .
  mkdir -p "$R2/grimoires/loa/a2a/sprint-7"
  printf '# Sprint 7 review — round 1\n\n### LOW-1 — stale default\n\nThe default at .loa.config.yaml.example:127 is stale.\n\n### LOW-2 — dead stage\n\nevals/harness/Dockerfile.ablation:19 declares a dead stage.\n' \
    > "$R2/grimoires/loa/a2a/sprint-7/engineer-feedback-r1.md"
  git -C "$R2" add grimoires
  git -C "$R2" -c user.email=t@t -c user.name=t commit -q -m record
  mkdir -p "$C2/pr-70/head"
  git -C "$G2" archive "$H2" | tar -x -C "$C2/pr-70/head"
  git -C "$G2" diff "$B2" "$H2" > "$C2/pr-70/head.diff"
  printf 'name: pr-70\nhead_commit: "%s"\nfix_commit: "%s"\nrecord_ref: "record/cycle-7-a2a"\nfeedback_files:\n  - "grimoires/loa/a2a/sprint-7/engineer-feedback-r1.md"\n' "$H2" "$F2" > "$C2/pr-70/fixture.yaml"
  run "$PK" pr-70 --repo "$G2" --corpus "$C2" --out "$T/p2" --no-incidents
  [ "$status" -eq 0 ]
  M="$T/p2/pr-70.hunks.meta.json"
  [ "$(jq -r '[.hunks[] | select(.file == ".loa.config.yaml.example") | .review_driven] | .[0]' "$M")" = "true" ]
  [ "$(jq -r '[.hunks[] | select(.file == "evals/harness/Dockerfile.ablation") | .review_driven] | .[0]' "$M")" = "true" ]
}

@test "AP-10 bidi overrides/isolates and zero-width characters in head context, diff lines and incident text become a visible U+FFFD marker" {
  local RLO ZWJ LRI BOM ZWSP M
  RLO="$(printf '‮')"; ZWJ="$(printf '‍')"; LRI="$(printf '⁦')"; BOM="$(printf '﻿')"; ZWSP="$(printf '​')"
  M="$(printf '�')"
  # a head line inside H01's context window (the fixture's head/ copy is what the packet shows)
  sed -i "s/^a_line_14=.*/a_line_14=\"admin${RLO}\"/" "$C/pr-60/head/scripts/a.sh"
  # an incident excerpt and an evidence diff line
  sed -i "s/fix(c): post-merge guard\$/fix(c): post-merge${ZWJ} guard${LRI}/" "$C/incidents/pr-60.tsv"
  printf '+c_line_8="zero%swidth%sbom"\n' "$ZWSP" "$BOM" >> "$C/incidents/pr-60/evidence/I01.diff"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 0 ]
  grep -qF "   14 | a_line_14=\"admin${M}\"" "$O/pr-60/hunks.md"
  grep -qxF "fix(c): post-merge${M} guard${M}" "$O/pr-60/incidents.md"
  grep -qF "+c_line_8=\"zero${M}width${M}bom\"" "$O/pr-60/incidents.md"
  python3 -I - "$O/pr-60" <<'PY2'
import os, re, sys
rx = re.compile("[\u202a-\u202e\u2066-\u2069\u200b-\u200d\ufeff]")
bad = [n for n in sorted(os.listdir(sys.argv[1])) if rx.search(open(os.path.join(sys.argv[1], n), encoding="utf-8").read())]
sys.exit("still carried by: " + ", ".join(bad) if bad else 0)
PY2
}

@test "AP-11 a packet line that still carries a bidi or zero-width character (an unsanitised incident field) is refused: exit 1, the line printed, nothing written" {
  local ZWJ; ZWJ="$(printf '‍')"
  # the kind column reaches the incident heading without safe(): the backstop must catch it
  sed -i "2s/\tfix-commit\t/\tfix${ZWJ}-commit\t/" "$C/incidents/pr-60.tsv"
  run "$PK" pr-60 "${ARGS[@]}"
  [ "$status" -eq 1 ]
  grep -qF 'incidents.md:' <<<"$output"
  grep -qF 'U+200D' <<<"$output"
  [ ! -e "$O/pr-60" ] && [ ! -e "$O/pr-60.hunks.meta.json" ]
}
