#!/usr/bin/env bats
# =============================================================================
# evals/tests/registration.bats — cycle-132 Sprint 269 Task 1.7c (SDD §3.2 "Entity: REGISTRATION.json",
# D-5.2, D-7.2; PRD FR-7)
#
# evals/analysis/c132/registration.py builds the JCS-canonical registration (through lib/jcs.sh, which
# needs the rfc8785 package: every case skips without it) and verifies it; run-ablation.sh --registration
# records what the builder printed. Its unit tests run here too (evals/analysis/c132/tests/test_registration.py).
# No model call, no docker (the runner's stubs).
# =============================================================================

setup() {
  # cycle-133 FR-9 (SDD C-9): runner invocations here use a stub docker and no egress block; the two-condition
  # test-mode escape (LOA_EGRESS_TEST_MODE=1 AND BATS_TEST_FILENAME) records enforced: false instead of refusing.
  export LOA_EGRESS_TEST_MODE=1
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  REG="$REPO_ROOT/evals/analysis/c132/registration.py"
  bash -c 'source "$1" && jcs_available' _ "$REPO_ROOT/lib/jcs.sh" 2>/dev/null || skip "lib/jcs.sh needs the rfc8785 package"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/reg.XXXXXX")"
  # a throwaway repository: the frozen suite root (review-01 with k 3), the suite file, corpus sums, a pre-registration
  R="$T/repo"; mkdir -p "$R/evals/analysis/c132"
  echo 'X = 1' > "$R/evals/analysis/c132/stats.py"
  cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0" "$R/root"
  yq -i '.review_catch.bare_sessions_matched = 3' "$R/root/tasks/review-01/task.yaml"
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$R/suite.yaml"
  cp "$REPO_ROOT/evals/fixtures/review-prs/SHA256SUMS" "$R/SHA256SUMS"
  printf '# Pre-registration\n' > "$R/PREREGISTRATION.md"
  ( cd "$R" && git init -q && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm init )
}

teardown() {
  [[ -n "${T:-}" ]] || return 0
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

build() {  # build [extra args…] → $T/REGISTRATION.json
  run python3 -I "$REG" build --repo "$R" --prereg "$R/PREREGISTRATION.md" --corpus-sums "$R/SHA256SUMS" --suite-root "$R/root" \
    --analysis-tree HEAD:evals/analysis/c132 --pin "${PIN:-abcdef1}" --suite-file "$R/suite.yaml" --arms a1_full,a0_bare_matched \
    --groups '[["review-01"]]' --looks '[1]' --boundary-constant 1.05 --cap-usd 2500 --seed 7 --kickoff 2026-10-21T00:23:00Z \
    --out "$T/REGISTRATION.json" "$@"
}
sha_of() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }

@test "REG-1 the registration module's unit tests pass (canonical, deterministic, every binding, drift, addenda, refusals)" {
  run python3 -I -m unittest discover -s "$REPO_ROOT/evals/analysis/c132/tests" -p 'test_registration.py'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "REG-2 build prints the sha256 of the canonical bytes it wrote; a second build is byte-identical; verify reads ok" {
  build
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(sha_of "$T/REGISTRATION.json")" ]
  cp "$T/REGISTRATION.json" "$T/first.json"
  build
  cmp "$T/first.json" "$T/REGISTRATION.json"
  [ "$(jq -r '.arms[] | select(.id == "a0_bare_matched") | .k_by_task["review-01"]' "$T/REGISTRATION.json")" = 3 ]
  [ "$(jq -r '"\(.suite_root) \(.corpus_sums_path) \(.analysis_tree)"' "$T/REGISTRATION.json")" = "root SHA256SUMS HEAD:evals/analysis/c132" ]
  run python3 -I "$REG" verify "$T/REGISTRATION.json" --repo "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $(sha_of "$T/REGISTRATION.json")" ]
}

@test "REG-3 verify catches a changed corpus sum (exit 1, the field named); a changed suite manifest too" {
  build
  [ "$status" -eq 0 ]
  printf '%064d  pr-99/fixture.yaml\n' 0 >> "$R/SHA256SUMS"
  run python3 -I "$REG" verify "$T/REGISTRATION.json" --repo "$R"
  [ "$status" -eq 1 ]
  grep -q '^drift: corpus_sha256sums_sha256: registered "' <<<"$output"
  echo '# edit' >> "$R/root/MANIFEST.sha256"
  run python3 -I "$REG" verify "$T/REGISTRATION.json" --repo "$R"
  [ "$status" -eq 1 ]
  grep -q '^drift: suite_manifest_sha256:' <<<"$output"
}

@test "REG-4 run-ablation.sh --registration with the builder's file: the dry run records the printed sha256 and derives the spend gate; an edit after the start refuses --resume" {
  # the batch's real inputs: the repository's frozen suite root and corpus sums, the throwaway source tree as the pin
  FX="$TESTS_DIR/fixtures"
  mkdir -p "$T/bin" "$T/src/.claude" "$T/creds/.codex"
  cp "$FX/ablation-docker-stub.sh" "$T/bin/docker"; cp "$FX/docker-stub.sh" "$T/bin/docker-stub.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "{\"total_usd\": 400, \"complete\": true}"' > "$T/bin/spend"
  chmod +x "$T/bin/"*
  echo "# loa" > "$T/src/.claude/CLAUDE.loa.md"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$T/src" rev-parse HEAD)"
  for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
  # $R/root/MANIFEST.sha256 is the frozen root's own copy: the hash the runner checks against its suite root
  PIN="${SHA:0:12}" build
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printed="$output"
  export PATH="$T/bin:$PATH" EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src" LOA_EVAL_CREDS_HOME="$T/creds"
  export LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2
  ra() {
    run "$REPO_ROOT/evals/harness/run-ablation.sh" --source-commit "$SHA" --results-root "$T/res" --self-check-log "$T/self-check.log" \
      --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" \
      --spend-bin "$T/bin/spend" "$@"
  }
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg --registration "$T/REGISTRATION.json" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  M="$T/res/rg/MANIFEST.json"
  [ "$(jq -r .registration_sha256 "$M")" = "$printed" ]
  [ "$(jq -r '.spend_gate | "\(.cycle_spent_usd) \(.derived_max_usd) \(.max_usd)"' "$M")" = "400 2100 2100" ]
  [ "$(jq -r '.registration.suite_manifest_sha256' "$M")" = "$(jq -r .suite_manifest_sha256 "$M")" ]
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg --registration "$T/REGISTRATION.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.registration_sha256' "$T/res/runs.jsonl")" = "$printed" ]
  build --seed 8
  ra --batch rg --resume
  [ "$status" -eq 2 ]
  grep -q "registration changed: $printed ≠ $(sha_of "$T/REGISTRATION.json")" <<<"$output"
}
