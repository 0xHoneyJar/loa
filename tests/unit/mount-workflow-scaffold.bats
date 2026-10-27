#!/usr/bin/env bats
# =============================================================================
# mount-workflow-scaffold.bats — Tests for scaffold_post_merge_workflow (#669)
# =============================================================================
# sprint-bug-130. Validates that mount installs a runnable
# .github/workflows/post-merge.yml in the consumer repo and that the
# scaffolded file includes `submodules: recursive` on actions/checkout
# (required for the submodule-install mode where .claude/scripts/* are
# symlinks into the submodule).
#
# Pattern mirrors tests/unit/mount-clean.bats: function under test is
# defined inline in setup so the bats can run in isolation without
# sourcing mount-loa.sh / mount-submodule.sh (which have main "$@"
# guards that side-effect on source).

setup() {
    TEST_DIR="$(mktemp -d)"
    export TARGET_DIR="$TEST_DIR"

    # Bridgebuilder F2/F6 (PR #671): test exercises the REAL production
    # function via lib/scaffold-post-merge-workflow.sh. No more inline
    # fixture copy — drift between test and production is impossible
    # because they are now the same code.
    PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    # shellcheck source=../../.claude/scripts/lib/scaffold-post-merge-workflow.sh
    source "$PROJECT_ROOT/.claude/scripts/lib/scaffold-post-merge-workflow.sh"

    # Fixture upstream workflow file — represents what `git checkout
    # $REMOTE/$BRANCH -- .github/workflows/post-merge.yml` would produce
    # OR what a submodule mode mount would copy from $SUBMODULE_PATH.
    FIXTURE_DIR="$TEST_DIR/_upstream"
    mkdir -p "$FIXTURE_DIR/.github/workflows"
    cat > "$FIXTURE_DIR/.github/workflows/post-merge.yml" <<'YAML'
name: Post-Merge Pipeline
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  classify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          fetch-depth: 0
          submodules: recursive
      - name: Classify
        run: .claude/scripts/classify-merge-pr.sh --merge-sha "$MERGE_SHA"
YAML

    # Ensure the lib's git-checkout fallback is inert in the test environment
    unset LOA_REMOTE_NAME LOA_BRANCH

    # cycle-136 C-1 (bd-akkgq, FR-1): re-mount fixtures for the legacy
    # simple-release guard check (MWS-T13 …), all heredocs, and a yq-less PATH
    _build_guard_fixtures

    cd "$TEST_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# =========================================================================
# MWS-T1..T2: idempotency (preserve user customization)
# =========================================================================

@test "MWS-T1: writes target when absent + valid source" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    [ -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

@test "MWS-T2: preserves existing target (idempotency)" {
    mkdir -p .github/workflows
    echo "# user-customized workflow" > .github/workflows/post-merge.yml
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    run cat .github/workflows/post-merge.yml
    [ "$output" = "# user-customized workflow" ]
}

# =========================================================================
# MWS-T3..T5: structural validity of the scaffolded YAML
# =========================================================================

@test "MWS-T3: scaffolded workflow names a workflow and triggers on push to main" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    run grep -E "^name:" "$TEST_DIR/.github/workflows/post-merge.yml"
    [ "$status" -eq 0 ]
    run grep -E "branches:.*\[main\]|branches: \[ main \]" "$TEST_DIR/.github/workflows/post-merge.yml"
    [ "$status" -eq 0 ]
}

@test "MWS-T4: scaffolded workflow references classify-merge-pr.sh OR post-merge-orchestrator.sh" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    grep -qE "(classify-merge-pr|post-merge-orchestrator)\.sh" "$TEST_DIR/.github/workflows/post-merge.yml"
}

@test "MWS-T5: scaffolded workflow includes submodules: recursive on actions/checkout (#669 symlink fix)" {
    scaffold_post_merge_workflow "$FIXTURE_DIR/.github/workflows/post-merge.yml"
    grep -qE "submodules:\s*recursive" "$TEST_DIR/.github/workflows/post-merge.yml"
}

# =========================================================================
# MWS-T6: empty source path → graceful no-op (mount-loa.sh git fallback path)
# =========================================================================

@test "MWS-T6: empty source path → no file written, no error" {
    scaffold_post_merge_workflow ""
    [ ! -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

# =========================================================================
# MWS-T7: nonexistent source path → graceful no-op
# =========================================================================

@test "MWS-T7: nonexistent source path → no file written, no error" {
    scaffold_post_merge_workflow "$TEST_DIR/_does_not_exist/post-merge.yml"
    [ ! -f "$TEST_DIR/.github/workflows/post-merge.yml" ]
}

# =========================================================================
# MWS-T8: live source-of-truth — repo's actual upstream workflow
# (validates the submodules: recursive change to post-merge.yml landed)
# =========================================================================

@test "MWS-T8: repo's .github/workflows/post-merge.yml has submodules: recursive on every actions/checkout" {
    local upstream_workflow="$BATS_TEST_DIRNAME/../../.github/workflows/post-merge.yml"
    [ -f "$upstream_workflow" ]
    # Bridgebuilder F4 (PR #671): drop the redundant `|| echo 0` from grep -c.
    # `grep -cE` already prints 0 when no matches; the `|| true` keeps
    # bash strict-mode pipefail from aborting on empty results.
    local checkout_count submodules_count
    checkout_count=$(grep -cE "uses:\s*actions/checkout" "$upstream_workflow" || true)
    submodules_count=$(grep -cE "submodules:\s*recursive" "$upstream_workflow" || true)
    # Every checkout must have a matching submodules: recursive (3 of each
    # in the live workflow as of #669)
    [ "$checkout_count" -gt 0 ]
    [ "$submodules_count" -ge "$checkout_count" ]
}

# =========================================================================
# MWS-T9: mount-loa.sh sources the canonical scaffold lib
# =========================================================================

@test "MWS-T9: mount-loa.sh sources scaffold-post-merge-workflow lib" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-loa.sh"
    grep -qE "scaffold-post-merge-workflow\.sh" "$script"
}

# =========================================================================
# MWS-T10: mount-submodule.sh sources the canonical scaffold lib
# =========================================================================

@test "MWS-T10: mount-submodule.sh sources scaffold-post-merge-workflow lib" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-submodule.sh"
    grep -qE "scaffold-post-merge-workflow\.sh" "$script"
}

# =========================================================================
# MWS-T11: lib is the single source of truth (no inline defs in installers)
# Bridgebuilder F2/F6 (PR #671): drift between test and prod is impossible
# when both source the same lib. Verify no inline scaffold_post_merge_workflow()
# function definition remains in either installer (would shadow the lib).
# =========================================================================

@test "MWS-T11: no inline scaffold_post_merge_workflow body in mount-loa.sh" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-loa.sh"
    # Allow comment references to the function name; reject standalone definitions
    ! grep -qE "^scaffold_post_merge_workflow\(\)\s*\{" "$script"
}

@test "MWS-T12: no inline scaffold_post_merge_workflow body in mount-submodule.sh" {
    local script="$BATS_TEST_DIRNAME/../../.claude/scripts/mount-submodule.sh"
    ! grep -qE "^scaffold_post_merge_workflow\(\)\s*\{" "$script"
}

# =========================================================================
# MWS-T13 …: re-mount legacy simple-release guard check (cycle-136 C-1,
# bd-akkgq, FR-1; sdd.md § 5.1, § 4). Every case sources the library inside
# `bash -euo pipefail` (as mount-loa.sh / mount-submodule.sh do) with a PATH
# holding only the tools below — no yq — and a scrubbed environment.
# =========================================================================

LEGACY="needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''"
ALLOWLIST="(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''"
WF=".github/workflows/post-merge.yml"

# _wf <job-if-line> <step-if-line> [extra-job-block]
# Mirrors the shipped workflow's shape: jobs → classify → simple-release
# (needs, if, runs-on, steps with a step-level if: and a run: | body) →
# [extra] → full-pipeline → notify. A line argument is the text after the
# indentation; an empty first argument omits the job-level if: line.
_wf() {
    local job_if="${1:-}" step_if="$2" extra="${3:-}" tpl
    tpl=$(cat <<'YAML'
name: Post-Merge Pipeline
on:
  push:
    branches: [main]
permissions:
  contents: write
jobs:
  # classify every merge first
  classify:
    runs-on: ubuntu-latest
    outputs:
      pr_type: ${{ steps.c.outputs.pr_type }}
      pr_number: ${{ steps.c.outputs.pr_number }}
    steps:
      - id: c
        run: .claude/scripts/classify-merge-pr.sh --merge-sha "$MERGE_SHA"

  simple-release:
    name: Prepare Release (Bugfix or Other)
    needs: classify
    # bd-nr5i6 (cycle-135 C-4): an allowlist, not `!= 'cycle'`.
@@JOBIF@@
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
        with:
          fetch-depth: 0
          submodules: recursive
      - name: Prepare
        @@STEPIF@@
        run: |
          echo "preparing the release"
          .claude/scripts/post-merge-orchestrator.sh --type simple
@@EXTRA@@
  full-pipeline:
    needs: classify
    if: needs.classify.outputs.pr_type == 'cycle' && needs.classify.outputs.pr_number != ''
    runs-on: ubuntu-latest
    steps:
      - run: echo full
  notify:
    needs: [simple-release, full-pipeline]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - run: echo done
YAML
)
    # Quoted replacements: bash 5.2 patsub_replacement treats a bare & as the match
    if [[ -n "$job_if" ]]; then
        tpl="${tpl//@@JOBIF@@/"    $job_if"}"
    else
        tpl="${tpl//@@JOBIF@@$'\n'/}"
    fi
    tpl="${tpl//@@STEPIF@@/"$step_if"}"
    if [[ -n "$extra" ]]; then
        tpl="${tpl//@@EXTRA@@/"$extra"}"
    else
        tpl="${tpl//@@EXTRA@@$'\n'/}"
    fi
    printf '%s\n' "$tpl"
}

_build_guard_fixtures() {
    GUARDS="$TEST_DIR/_guards"
    mkdir -p "$GUARDS"
    local step_ok="if: steps.c.outputs.skip != 'true'"

    _wf "if: $LEGACY" "$step_ok" > "$GUARDS/legacy.yml"
    _wf "if: $ALLOWLIST" "$step_ok" > "$GUARDS/allowlist.yml"
    _wf "if: needs.classify.outputs.pr_type == 'bugfix' && github.ref == 'refs/heads/main'" "$step_ok" > "$GUARDS/custom.yml"
    # inline comment after the guard (ignored by detection, kept by a rewrite)
    _wf "if: $LEGACY # keep in sync with the classifier" "$step_ok" > "$GUARDS/legacy-comment.yml"
    _wf "if: $ALLOWLIST # keep in sync with the classifier" "$step_ok" > "$GUARDS/allowlist-comment.yml"
    # quoting styles (YAML single quotes escape ' as '')
    _wf "if: \"$LEGACY\"" "$step_ok" > "$GUARDS/legacy-dq.yml"
    _wf "if: \"$ALLOWLIST\"" "$step_ok" > "$GUARDS/allowlist-dq.yml"
    _wf "if: '${LEGACY//\'/\'\'}'" "$step_ok" > "$GUARDS/legacy-sq.yml"
    _wf "if: '${ALLOWLIST//\'/\'\'}'" "$step_ok" > "$GUARDS/allowlist-sq.yml"
    # ${{ … }}-wrapped legacy guard: detected, never rewritten
    _wf "if: \${{ $LEGACY }}" "$step_ok" > "$GUARDS/legacy-wrapped.yml"
    # CRLF line endings
    awk '{ printf "%s\r\n", $0 }' "$GUARDS/legacy.yml" > "$GUARDS/legacy-crlf.yml"
    awk '{ printf "%s\r\n", $0 }' "$GUARDS/allowlist.yml" > "$GUARDS/allowlist-crlf.yml"
    # no final newline
    printf '%s' "$(cat "$GUARDS/legacy.yml")" > "$GUARDS/legacy-nonl.yml"
    printf '%s' "$(cat "$GUARDS/allowlist.yml")" > "$GUARDS/allowlist-nonl.yml"

    # --- negative fixtures ------------------------------------------------
    # a step-level if: carrying the legacy text; the job's own if: is the allowlist
    _wf "if: $ALLOWLIST" "if: $LEGACY" > "$GUARDS/neg-step-level.yml"
    # a second job carrying the legacy if: while simple-release is the allowlist
    _wf "if: $ALLOWLIST" "$step_ok" "$(cat <<YAML
  legacy-copy:
    needs: classify
    if: $LEGACY
    runs-on: ubuntu-latest
    steps:
      - run: echo copy
YAML
)" > "$GUARDS/neg-legacy-copy.yml"
    # the legacy text in comment lines inside the block (one at the child indent)
    _wf "if: $ALLOWLIST" "# if: $LEGACY" > "$GUARDS/neg-comment.yml"
    awk -v l="    # if: $LEGACY" '{ print } /^    needs: classify$/ && !d { print l; d = 1 }' \
        "$GUARDS/neg-comment.yml" > "$GUARDS/neg-comment.tmp" && mv "$GUARDS/neg-comment.tmp" "$GUARDS/neg-comment.yml"
    # a multi-line if: | block holding the legacy text
    _wf "if: |"$'\n'"      $LEGACY" "$step_ok" > "$GUARDS/neg-multiline.yml"
    # the legacy if: inside a run: | body; the body line sits at the child
    # indentation because the scalar opener is shallower than the job's keys
    # (no YAML parser would place it there — the awk pass must still not read it)
    _wf "if: $ALLOWLIST" "$step_ok" "$(cat <<YAML
   script: | # the opener may carry a comment
    if: $LEGACY
YAML
)" > "$GUARDS/neg-runbody-at-child.yml"
    # the legacy if: inside an ordinary run: | body (deeper than the child indent)
    _wf "if: $ALLOWLIST" "$step_ok" | awk -v l="          if: $LEGACY" \
        '{ print } /echo "preparing the release"/ { print l }' > "$GUARDS/neg-runbody.yml"
    # two job-level if: lines
    _wf "if: $LEGACY"$'\n'"    if: $LEGACY" "$step_ok" > "$GUARDS/neg-two-ifs.yml"
    # no simple-release job at all
    _wf "if: $LEGACY" "$step_ok" | awk '{ sub(/^  simple-release:/, "  prepare-release:"); print }' > "$GUARDS/neg-no-job.yml"
    # a job id with digits right after the block, carrying the legacy if:
    _wf "if: $ALLOWLIST" "$step_ok" "$(cat <<YAML
  simple-release-2:
    needs: classify
    if: $LEGACY
    runs-on: ubuntu-latest
    steps:
      - run: echo two
YAML
)" > "$GUARDS/neg-digit-job.yml"

    # a 4-space-indented workflow (detection must not assume two spaces)
    cat > "$GUARDS/legacy-4sp.yml" <<YAML
name: Post-Merge Pipeline
on:
    push:
        branches: [main]
jobs:
    classify:
        runs-on: ubuntu-latest
        steps:
            -   run: .claude/scripts/classify-merge-pr.sh
    simple-release:
        needs: classify
        if: $LEGACY
        runs-on: ubuntu-latest
        steps:
            -   name: Prepare
                if: steps.c.outputs.skip != 'true'
                run: |
                    echo "preparing"
    full-pipeline:
        needs: classify
        if: needs.classify.outputs.pr_type == 'cycle'
        runs-on: ubuntu-latest
        steps:
            -   run: echo full
YAML
    awk -v a="        if: $ALLOWLIST" '/^        if: needs.classify.outputs.pr_type != / { print a; next } { print }' \
        "$GUARDS/legacy-4sp.yml" > "$GUARDS/allowlist-4sp.yml"

    # A scratch PATH with the tools the callers' environment provides — no yq
    STUB_BIN="$TEST_DIR/_bin"
    mkdir -p "$STUB_BIN"
    local b
    for b in bash awk sed grep cat cp mv rm mktemp dirname tail head mkdir chmod ln ls tr; do
        if command -v "$b" >/dev/null 2>&1; then
            ln -s "$(command -v "$b")" "$STUB_BIN/$b"
        fi
    done
    BASH_BIN="$(command -v bash)"
    LIB="$(cd "$PROJECT_ROOT" && pwd)/.claude/scripts/lib/scaffold-post-merge-workflow.sh"
}

# _install <fixture> — place a fixture as the consumer's existing workflow
_install() {
    mkdir -p .github/workflows
    cp "$GUARDS/$1" "$WF"
}

# _scaffold [VAR=value …] — run the re-mount scaffold the way the callers do;
# $output holds stderr only (the function's notices), $status its exit code
_scaffold() {
    run env -i HOME="$HOME" PATH="$STUB_BIN" "$@" "$BASH_BIN" -euo pipefail -c \
        'source "$1"; scaffold_post_merge_workflow "" 2>&1 >/dev/null' _ "$LIB"
}

_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

_warn_legacy() {
    printf '%s' "[scaffold] WARN: $1 keeps the legacy simple-release guard (pr_type != 'cycle' && pr_number != ''); since Loa cycle-135 housekeeping merges classify 'housekeeping' and this guard sends them to the orchestrator, which refuses. Replace it with: $ALLOWLIST  — or re-run the mount with LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 to rewrite that one line (bd-nr5i6)"
}
_warn_refuse() {
    printf '%s' "[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but $1 has no single job-level simple-release if: carrying the legacy guard — left unchanged"
}
_notice_fixed() {
    printf '%s' "[scaffold] fixed: $1 simple-release if: → allowlist guard (one line changed; bd-nr5i6)"
}

# _negative <fixture> <flag-output: silent|refuse> — byte-identical with and
# without the flag; silent without it
_negative() {
    _install "$1"
    _scaffold
    [ "$status" -eq 0 ] || { echo "status=$status output=$output"; return 1; }
    [ -z "$output" ] || { echo "unexpected output: $output"; return 1; }
    cmp "$GUARDS/$1" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ] || { echo "status=$status output=$output"; return 1; }
    if [[ "$2" == silent ]]; then
        [ -z "$output" ] || { echo "unexpected output: $output"; return 1; }
    else
        [ "$output" = "$(_warn_refuse "$WF")" ] || { echo "got: $output"; return 1; }
    fi
    cmp "$GUARDS/$1" "$WF"
}

@test "MWS-T13: the scratch PATH has no yq and every fixture is a regular file" {
    [ ! -e "$STUB_BIN/yq" ]
    [ -x "$STUB_BIN/awk" ] && [ -x "$STUB_BIN/bash" ] && [ -x "$STUB_BIN/mktemp" ] && [ -x "$STUB_BIN/mv" ]
    grep -qF "    if: $LEGACY" "$GUARDS/legacy.yml"
    grep -qF "    if: $ALLOWLIST" "$GUARDS/allowlist.yml"
    # the two base fixtures differ in exactly the one if: line
    run diff "$GUARDS/legacy.yml" "$GUARDS/allowlist.yml"
    [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 2 ]
}

@test "MWS-T14: legacy guard → one WARN on stderr naming the path, the guard, the allowlist, the flag and bd-nr5i6; file byte-identical; exit 0" {
    _install legacy.yml
    _scaffold
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "got: $output"; return 1; }
    [[ "$output" == *"$WF"* ]]
    [[ "$output" == *"pr_type != 'cycle'"* ]]
    [[ "$output" == *"$ALLOWLIST"* ]]
    [[ "$output" == *"LOA_SCAFFOLD_FIX_RELEASE_GUARD"* ]]
    [[ "$output" == *"bd-nr5i6"* ]]
    cmp "$GUARDS/legacy.yml" "$WF"
}

@test "MWS-T15: allowlist guard → silent, unchanged, exit 0 (with and without the flag)" {
    _negative allowlist.yml silent
}

@test "MWS-T16: customised single-line if: → silent; with the flag → the refuse WARN, unchanged, exit 0" {
    _negative custom.yml refuse
}

@test "MWS-T17: flag + legacy → exactly the if: line changes, notice printed, result equals the allowlist fixture, mode kept, second run silent" {
    _install legacy.yml
    chmod 640 "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")"$'\n'"$(_notice_fixed "$WF")" ] || { echo "got: $output"; return 1; }
    run diff "$GUARDS/legacy.yml" "$WF"
    [ "$(printf '%s\n' "$output" | grep -c '^<')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^>')" -eq 1 ]
    [[ "$output" == *"<     if: $LEGACY"* ]]
    cmp "$GUARDS/allowlist.yml" "$WF"
    [ "$(_mode "$WF")" = "640" ]
    [ ! -L "$WF" ]
    # no temp file left behind
    [ -z "$(ls -A .github/workflows | grep -v '^post-merge.yml$' || true)" ]
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    _scaffold
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    cmp "$GUARDS/allowlist.yml" "$WF"
}

@test "MWS-T18: negative — a step-level if: with the legacy text (job if: is the allowlist) is never matched" {
    _negative neg-step-level.yml silent
}

@test "MWS-T19: negative — a second job legacy-copy carrying the legacy if: is never matched" {
    _negative neg-legacy-copy.yml silent
}

@test "MWS-T20: negative — the legacy text inside # comment lines in the block is never matched" {
    _negative neg-comment.yml silent
}

@test "MWS-T21: negative — a multi-line if: | block holding the legacy text → silent; with the flag → refuse" {
    _negative neg-multiline.yml refuse
}

@test "MWS-T22: negative — the legacy if: inside run: | bodies (deeper, and at the child indentation) is never matched" {
    _negative neg-runbody.yml silent
    _negative neg-runbody-at-child.yml silent
}

@test "MWS-T23: negative — two job-level if: lines → silent; with the flag → refuse" {
    _negative neg-two-ifs.yml refuse
}

@test "MWS-T24: negative — no simple-release job → silent; with the flag → refuse" {
    _negative neg-no-job.yml refuse
}

@test "MWS-T25: negative — a job id with digits (simple-release-2:) right after the block does not extend it" {
    _negative neg-digit-job.yml silent
}

@test "MWS-T26: a 4-space-indented workflow → WARN, unchanged; with the flag → only the if: line changes" {
    _install legacy-4sp.yml
    _scaffold
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy-4sp.yml" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")"$'\n'"$(_notice_fixed "$WF")" ]
    cmp "$GUARDS/allowlist-4sp.yml" "$WF"
}

@test "MWS-T27: a \${{ … }}-wrapped legacy guard → WARN; with the flag → WARN + refuse, never rewritten" {
    _install legacy-wrapped.yml
    _scaffold
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy-wrapped.yml" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")"$'\n'"$(_warn_refuse "$WF")" ] || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy-wrapped.yml" "$WF"
}

@test "MWS-T28: a symlinked target (pointing at a legacy file) → silent; with the flag → refuse; link and its target untouched" {
    mkdir -p .github/workflows
    cp "$GUARDS/legacy.yml" "$TEST_DIR/real-post-merge.yml"
    ln -s "$TEST_DIR/real-post-merge.yml" "$WF"
    _scaffold
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "got: $output"; return 1; }
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_refuse "$WF")" ] || { echo "got: $output"; return 1; }
    [ -L "$WF" ]
    cmp "$GUARDS/legacy.yml" "$TEST_DIR/real-post-merge.yml"
}

@test "MWS-T29: a CRLF workflow is detected and the rewritten line keeps \\r\\n" {
    _install legacy-crlf.yml
    _scaffold
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy-crlf.yml" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")"$'\n'"$(_notice_fixed "$WF")" ]
    cmp "$GUARDS/allowlist-crlf.yml" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ -z "$output" ]
}

@test "MWS-T30: an inline # comment after the guard is ignored by detection and kept by the rewrite" {
    _install legacy-comment.yml
    _scaffold
    [ "$status" -eq 0 ]
    [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy-comment.yml" "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    cmp "$GUARDS/allowlist-comment.yml" "$WF"
    _negative allowlist-comment.yml silent
}

@test "MWS-T31: double- and single-quoted legacy guards are detected and rewritten in the same quoting style" {
    local q
    for q in dq sq; do
        _install "legacy-$q.yml"
        _scaffold
        [ "$status" -eq 0 ]
        [ "$output" = "$(_warn_legacy "$WF")" ] || { echo "$q got: $output"; return 1; }
        cmp "$GUARDS/legacy-$q.yml" "$WF"
        _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
        [ "$status" -eq 0 ]
        cmp "$GUARDS/allowlist-$q.yml" "$WF"
        _negative "allowlist-$q.yml" silent
    done
}

@test "MWS-T32: a file without a final newline is rewritten without gaining one" {
    _install legacy-nonl.yml
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    cmp "$GUARDS/allowlist-nonl.yml" "$WF"
}

@test "MWS-T33: flag + a non-writable legacy target → WARN naming the failure, unchanged, exit 0" {
    [ "$(id -u)" -ne 0 ] || skip "root can write a read-only file"
    _install legacy.yml
    chmod 444 "$WF"
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    [ "$status" -eq 0 ]
    [[ "$output" == "$(_warn_legacy "$WF")"$'\n'"[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but $WF could not be rewritten (not writable) — left unchanged" ]] \
        || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy.yml" "$WF"
    [ "$(_mode "$WF")" = "444" ]
}

@test "MWS-T34: flag + a legacy target in a non-writable directory → WARN naming the failure, unchanged, exit 0" {
    [ "$(id -u)" -ne 0 ] || skip "root can write a read-only directory"
    _install legacy.yml
    chmod 555 .github/workflows
    _scaffold LOA_SCAFFOLD_FIX_RELEASE_GUARD=1
    chmod 755 .github/workflows
    [ "$status" -eq 0 ]
    [[ "$output" == "$(_warn_legacy "$WF")"$'\n'"[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but $WF could not be rewritten (no temp file in .github/workflows) — left unchanged" ]] \
        || { echo "got: $output"; return 1; }
    cmp "$GUARDS/legacy.yml" "$WF"
}

@test "MWS-T35: the library header documents the flag and the re-mount check" {
    grep -qF "LOA_SCAFFOLD_FIX_RELEASE_GUARD" "$LIB"
    grep -qF "bd-akkgq" "$LIB"
    ! grep -nE "sed -i |readlink -f|grep -P |-printf|^[[:space:]]*g?timeout [0-9]" "$LIB"
}
