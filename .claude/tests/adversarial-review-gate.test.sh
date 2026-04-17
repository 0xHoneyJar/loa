#!/usr/bin/env bash
# =============================================================================
# Tests for .claude/hooks/safety/adversarial-review-gate.sh
# =============================================================================
# Covers the cases the gate must get right:
#   1. Block when config enables code_review and no review artefact exists
#   2. Allow when a valid review artefact (metadata.type + metadata.model) exists
#   3. Block when artefact is empty/malformed (structural validation)
#   4. Allow when config disables code_review (no enforcement requested)
#   5. Allow on non-Write tool calls (gate scope)
#   6. Allow on non-COMPLETED writes (gate scope)
#   7. Allow when LOA_ADVERSARIAL_REVIEW_ENFORCE=false (opt-out)
#   8. Fail-open when yq is missing (with stderr warning)
#   9. Walk upward from sprint_dir to locate .loa.config.yaml (CWD-independent)
#  10. Fail-CLOSED when no .loa.config.yaml can be resolved at all
#
# Run: bash .claude/tests/adversarial-review-gate.test.sh
# =============================================================================

set -u  # deliberately not -e; we want to sum up passes/fails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/hooks/safety/adversarial-review-gate.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

_run() {
  local name="$1"
  local want_exit="$2"
  local actual_exit="$3"
  if [[ "$actual_exit" == "$want_exit" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name (want exit $want_exit, got $actual_exit)")
    echo "  FAIL: $name (want exit $want_exit, got $actual_exit)"
  fi
}

_make_workdir() {
  mktemp -d -t adv-gate-test.XXXXXX
}

_write_config() {
  # $1 workdir, $2 code_review_enabled, $3 audit_enabled
  local dir="$1" cr="$2" au="$3"
  cat > "$dir/.loa.config.yaml" <<EOF
flatline_protocol:
  code_review:
    enabled: $cr
  security_audit:
    enabled: $au
EOF
}

_valid_artefact() {
  # Emits the minimum structural fields the gate checks for.
  printf '{"metadata":{"type":"code_review","model":"gpt-5.3-codex","status":"clean"}}'
}

_hook_payload() {
  # $1 tool_name, $2 file_path
  jq -cn --arg t "$1" --arg p "$2" '{tool_name: $t, tool_input: {file_path: $p}}'
}

# ─────────────────────────────────────────────────────────────────────────────
# Case 1: config enables code_review, artefact missing → block (exit 1)
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case1_block_on_missing_artefact" 1 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 2: valid artefact present → allow (exit 0)
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
_valid_artefact > "$wd/sprint-1/adversarial-review.json"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case2_allow_on_valid_artefact" 0 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 3: empty file present (the `touch` bypass) → block (structural check)
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
: > "$wd/sprint-1/adversarial-review.json"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case3_block_on_empty_artefact_touch_bypass" 1 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 3b: JSON present but missing metadata.model → block
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
echo '{"metadata":{"type":"code_review"}}' > "$wd/sprint-1/adversarial-review.json"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case3b_block_on_incomplete_metadata" 1 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 4: config disables code_review → allow even with no artefact
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "false" "false"
mkdir -p "$wd/sprint-1"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case4_allow_when_config_disabled" 0 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 5: non-Write tool call → allow (gate scope)
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
payload=$(_hook_payload "Edit" "$wd/sprint-1/COMPLETED")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case5_allow_on_non_write_tool" 0 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 6: Write to non-COMPLETED path → allow (gate scope)
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
payload=$(_hook_payload "Write" "$wd/sprint-1/notes.md")
LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case6_allow_on_non_completed_path" 0 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 7: opt-out env var → allow even with enforcement otherwise required
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
LOA_ADVERSARIAL_REVIEW_ENFORCE=false \
  LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
_run "case7_allow_on_opt_out_env" 0 $?
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 8: yq missing → fail open, emit stderr warning
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/sprint-1"
# Hermetic sandbox: symlink only the tools the gate needs externally (jq,
# head, dirname, bash itself). Omit yq so `command -v yq` returns false.
sandbox_bin=$(mktemp -d)
_link_if_found() {
  local t
  t=$(command -v "$1" 2>/dev/null) && ln -s "$t" "$sandbox_bin/$1"
}
_link_if_found jq
_link_if_found head
_link_if_found dirname
_link_if_found cat
_link_if_found mktemp

if [[ ! -e "$sandbox_bin/jq" ]]; then
  echo "  SKIP: case8_yq_missing_fail_open — jq unavailable in test env"
else
  payload=$(_hook_payload "Write" "$wd/sprint-1/COMPLETED")
  BASH_BIN="$(command -v bash)"
  stderr=$(PATH="$sandbox_bin" \
    LOA_CONFIG_PATH_OVERRIDE="$wd/.loa.config.yaml" \
    "$BASH_BIN" "$GATE" <<<"$payload" 2>&1 >/dev/null)
  exit_code=$?
  if [[ "$exit_code" == "0" && "$stderr" == *"yq not found"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: case8_yq_missing_fail_open"
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("case8_yq_missing_fail_open (exit=$exit_code, stderr=${stderr:0:160})")
    echo "  FAIL: case8_yq_missing_fail_open (exit=$exit_code, stderr=${stderr:0:160})"
  fi
fi
rm -rf "$wd" "$sandbox_bin"

# ─────────────────────────────────────────────────────────────────────────────
# Case 9: hook fires with neutral CWD → walk-up locates .loa.config.yaml
# ─────────────────────────────────────────────────────────────────────────────
wd=$(_make_workdir)
_write_config "$wd" "true" "false"
mkdir -p "$wd/grimoires/loa/a2a/sprint-9"
payload=$(_hook_payload "Write" "$wd/grimoires/loa/a2a/sprint-9/COMPLETED")
# No LOA_CONFIG_PATH_OVERRIDE; CWD is /tmp (not repo root) — walk-up must find
# the config starting from the sprint dir upward.
(
  cd /tmp
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
)
# Expected: block (exit 1) because config enables review and no artefact exists.
# If the walk-up fails, the gate would fail-closed on unresolved config and
# ALSO exit 1 — but the stderr would differ. Check block message explicitly.
exit_code=$?
stderr=$(
  cd /tmp
  bash "$GATE" <<<"$payload" 2>&1 >/dev/null
)
if [[ "$exit_code" == "1" && "$stderr" == *"adversarial review required"* ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: case9_walkup_locates_config_from_sprint_dir"
else
  FAIL=$((FAIL + 1))
  FAILED_NAMES+=("case9_walkup_locates_config_from_sprint_dir (exit=$exit_code, stderr=${stderr:0:160})")
  echo "  FAIL: case9_walkup_locates_config_from_sprint_dir (exit=$exit_code)"
fi
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
# Case 10: no .loa.config.yaml anywhere on walk-up → fail CLOSED
# ─────────────────────────────────────────────────────────────────────────────
# Isolate sprint dir under a fresh tmp tree that has no config on the walk.
# (Ancestors like /tmp, /, etc. never contain .loa.config.yaml.)
wd=$(_make_workdir)
mkdir -p "$wd/sprint-10"
payload=$(_hook_payload "Write" "$wd/sprint-10/COMPLETED")
(
  cd /tmp
  bash "$GATE" <<<"$payload" >/dev/null 2>&1
)
exit_code=$?
stderr=$(
  cd /tmp
  bash "$GATE" <<<"$payload" 2>&1 >/dev/null
)
if [[ "$exit_code" == "1" && "$stderr" == *"cannot locate .loa.config.yaml"* ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: case10_fail_closed_on_unresolvable_config"
else
  FAIL=$((FAIL + 1))
  FAILED_NAMES+=("case10_fail_closed_on_unresolvable_config (exit=$exit_code, stderr=${stderr:0:160})")
  echo "  FAIL: case10_fail_closed_on_unresolvable_config (exit=$exit_code)"
fi
rm -rf "$wd"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo "adversarial-review-gate.test.sh: $PASS passed, $FAIL failed"
echo "──────────────────────────────────────────"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
