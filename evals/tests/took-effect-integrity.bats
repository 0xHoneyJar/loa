#!/usr/bin/env bats
# =============================================================================
# evals/tests/took-effect-integrity.bats — cycle-134 Sprint 276 Task 1.3 (bd-htzy2; PRD FR-4; SDD C-3, D-1.3).
# took-effect.sh integrity_clean on a home-scope run binds the driver's meta/home-integrity.json to the pin the
# operator named: the pin (arms[].source_commit, else the batch MANIFEST.json source_commit — run-ablation.sh
# --source-commit — else the suite's source_commit) is pipeline.json source_commit; the pin's
# .claude/checksums.json (read from --source-repo) has a files map whose entries the record covers
# (record.files >= its entry count, = arm_evidence manifest_files); record and arm_evidence digests agree; 0
# tampered, 0 missing. A retained HOME copy (meta/home/.claude, or home/.claude) is walked independently: regular
# files only, its manifest is the recorded digest, every entry hashes to its value, every pinned path is listed,
# extra files are reported. The two passing modes are named in the evidence.
# The run is built by fixtures/took-effect/te-lib.bash (a two-commit pinned repository in $BATS_TEST_TMPDIR).
# =============================================================================

setup() {
  # shellcheck source=fixtures/took-effect/te-lib.bash
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/took-effect/te-lib.bash"
  te_setup
}
teardown() { te_teardown; }

# home — the run as pipeline-run.sh leaves it: the HOME framework copy (the pin's .claude/ plus one file the mount
# adds) under meta/home with its regenerated manifest, the record of its check, the digests in the evidence
home() {
  te_build || return 1
  yq -i '(.arms[] | select(.id == "a1_te") | .took_effect) = ["integrity_clean"]' "$S"
  yq -i ".source_commit = \"$F\"" "$S"
  local hd="$RD/meta/home"
  mkdir -p "$hd"
  git -C "$SRC" archive "$F" .claude | tar -x -C "$hd"
  printf 'mount-added\n' > "$hd/.claude/settings.local.json"
  { te_manifest "$hd" | jq '. + {generated: "2026-10-25T00:00:00Z"}'; } > "$T/m.json" && mv "$T/m.json" "$hd/.claude/checksums.json"
  D="$(sha256sum "$hd/.claude/checksums.json" | cut -c1-64)"
  N="$(jq '.files | length' "$hd/.claude/checksums.json")"
  printf 'manifest_files=%s (inline)\nmanifest_sha256=%s\n' "$N" "$D" >> "$ARM_EVIDENCE_FILE"
  jq --arg d "$D" '.arm_evidence = {manifest_sha256: $d}' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  jq -n --arg d "$D" --argjson n "$N" '{files: $n, first: null, manifest_sha256: $d, missing: 0, tampered: 0}' > "$RD/meta/home-integrity.json"
}
deleted() { find "$RD/meta/home" -mindepth 1 -delete; rmdir "$RD/meta/home"; }   # the HOME removed at exit
rec() { jq "$1" "$RD/meta/home-integrity.json" > "$T/h.json" && mv "$T/h.json" "$RD/meta/home-integrity.json"; }
ic() { printf '%s\n' "$output" | grep -E '^arm a1_te: integrity_clean '; }
pass_with() { [ "$status" -eq 0 ] || { echo "$output"; false; }; ic | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }
fail_with() { [ "$status" -eq 1 ] || { echo "$output"; false; }; ic | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }

@test "TEI-1 a clean record (the HOME deleted at exit) passes, cross-checked against the pin, naming the mode" {
  home; deleted
  te_run
  pass_with "integrity_clean OK home-scope: 3 HOME framework entries verified at finish; manifest_sha256 ${D:0:12}"
  pass_with "pin ${F:0:12} (suite source_commit) = source_commit; the pin's manifest $(git -C "$SRC" show "$F:.claude/checksums.json" | sha256sum | cut -c1-12) (2 entries) covered; record cross-checked against the pin (HOME deleted at exit)"
}

@test "TEI-2 a clean retained HOME copy passes by an independent walk, naming the mode" {
  home
  te_run
  pass_with 'independent walk (3 files, 0 extra)'
}

@test "TEI-3 digest mismatch: the record against arm_evidence, and a retained manifest that is not the recorded one, fail" {
  home; deleted
  rec '.manifest_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
  te_run
  fail_with 'integrity_clean FAIL home-scope: the checked HOME manifest 000000000000 is not arm_evidence.manifest_sha256'
  home
  printf '\n' >> "$RD/meta/home/.claude/checksums.json"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: its manifest'
  fail_with "is not the recorded manifest_sha256 ${D:0:12}"
}

@test "TEI-4 count mismatch: a record listing fewer files than the pin's manifest, or not arm_evidence manifest_files, fails" {
  home; deleted
  rec '.files = 1'
  te_run
  fail_with "integrity_clean FAIL home-scope: the HOME record lists 1 file(s), fewer than the pin's manifest (2 entries)"
  rec '.files = 4'
  te_run
  fail_with 'integrity_clean FAIL home-scope: the HOME record lists 4 file(s), arm_evidence manifest_files says 3'
}

@test "TEI-5 the pin the operator named must be pipeline.json's source_commit; the batch MANIFEST.json (run-ablation --source-commit) names it before the suite" {
  home; deleted
  yq -i ".source_commit = \"$H\"" "$S"
  te_run
  fail_with "integrity_clean FAIL home-scope: the pin ${H:0:12} (suite source_commit) is not pipeline.json source_commit ${F:0:12}"
  # an arm's own source_commit wins
  yq -i "(.arms[] | select(.id == \"a1_te\") | .source_commit) = \"${F:0:10}\"" "$S"
  te_run
  pass_with "pin ${F:0:12} (arms[].source_commit) = source_commit"
  # a run inside a batch directory: the batch's MANIFEST.json source_commit (the suite holds a placeholder)
  yq -i 'del(.arms[] | select(.id == "a1_te") | .source_commit) | .source_commit = "<sprint-258-commit>"' "$S"
  mkdir -p "$T/batch/a1_te"; mv "$RD" "$T/batch/a1_te/rc-te-t1"; RD="$T/batch/a1_te/rc-te-t1"
  te_run
  fail_with 'integrity_clean FAIL home-scope: no pin named for the run (arms[].source_commit, the batch MANIFEST.json source_commit, the suite source_commit)'
  jq -n --arg c "$H" '{source_commit: $c}' > "$T/batch/MANIFEST.json"
  te_run
  fail_with "integrity_clean FAIL home-scope: the pin ${H:0:12} (batch MANIFEST.json) is not pipeline.json source_commit ${F:0:12}"
  jq -n --arg c "$F" '{source_commit: $c}' > "$T/batch/MANIFEST.json"
  te_run
  pass_with "pin ${F:0:12} (batch MANIFEST.json) = source_commit"
  # a pin the source repository does not hold
  jq -n '{source_commit: "abcdef0123456789abcdef0123456789abcdef01"}' > "$T/batch/MANIFEST.json"
  te_run
  fail_with 'integrity_clean FAIL home-scope: the pin abcdef012345 (batch MANIFEST.json) does not resolve'
}

@test "TEI-6 a retained copy with a tampered or missing file fails naming it" {
  home
  printf 'tampered\n' >> "$RD/meta/home/.claude/protocols/p.md"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: tampered .claude/protocols/p.md'
  home
  rm "$RD/meta/home/.claude/loa/CLAUDE.loa.md"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: missing .claude/loa/CLAUDE.loa.md'
}

@test "TEI-7 the walk takes regular files only: a symlinked directory, a symlinked file, a special file and an unreadable file fail by name; an extra file is reported" {
  home
  mkdir "$T/outside"; ln -s "$T/outside" "$RD/meta/home/.claude/linked-dir"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: a symlink (.claude/linked-dir)'
  rm "$RD/meta/home/.claude/linked-dir"; ln -s protocols/p.md "$RD/meta/home/.claude/linked-file"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: a symlink (.claude/linked-file)'
  rm "$RD/meta/home/.claude/linked-file"; mkfifo "$RD/meta/home/.claude/fifo"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: not a regular file (.claude/fifo)'
  rm "$RD/meta/home/.claude/fifo"
  if [[ "$(id -u)" != 0 ]]; then
    chmod 000 "$RD/meta/home/.claude/protocols/p.md"
    te_run
    fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: unreadable (.claude/protocols/p.md)'
    chmod 644 "$RD/meta/home/.claude/protocols/p.md"
    chmod 000 "$RD/meta/home/.claude/loa"
    te_run
    fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: unreadable (.claude/loa)'
    chmod 755 "$RD/meta/home/.claude/loa"
  fi
  printf 'extra\n' > "$RD/meta/home/.claude/extra.txt"
  te_run
  pass_with 'independent walk (3 files, 1 extra: .claude/extra.txt)'
  # the retained HOME itself a symlink
  mv "$RD/meta/home" "$T/home-elsewhere"; ln -s "$T/home-elsewhere" "$RD/meta/home"
  te_run
  fail_with 'integrity_clean FAIL home-scope: retained HOME meta/home/.claude: a symlink (meta/home)'
}

@test "TEI-8 a record the pin cannot bind fails: the pin's manifest absent, and a retained manifest missing a pinned path" {
  home; deleted
  git -C "$SRC" rm -q .claude/checksums.json; ( cd "$SRC" && te_g . commit -qm no-manifest ); local F2; F2="$(git -C "$SRC" rev-parse HEAD)"
  jq --arg c "$F2" '.source_commit = $c' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  yq -i ".source_commit = \"$F2\"" "$S"
  te_run
  fail_with "integrity_clean FAIL home-scope: the pin ${F2:0:12} has no .claude/checksums.json files map"
  home
  jq 'del(.files[".claude/loa/CLAUDE.loa.md"])' "$RD/meta/home/.claude/checksums.json" > "$T/m.json" && mv "$T/m.json" "$RD/meta/home/.claude/checksums.json"
  rm "$RD/meta/home/.claude/loa/CLAUDE.loa.md"
  D="$(sha256sum "$RD/meta/home/.claude/checksums.json" | cut -c1-64)"
  sed -i "s/^manifest_sha256=.*/manifest_sha256=$D/; s/^manifest_files=.*/manifest_files=2 (inline)/" "$ARM_EVIDENCE_FILE"
  jq --arg d "$D" '.arm_evidence.manifest_sha256 = $d' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  rec ".manifest_sha256 = \"$D\" | .files = 2"
  te_run
  fail_with "integrity_clean FAIL home-scope: retained HOME meta/home/.claude: the manifest lacks .claude/loa/CLAUDE.loa.md of the pin's manifest"
}
