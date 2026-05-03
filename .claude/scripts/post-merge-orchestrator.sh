#!/usr/bin/env bash
# post-merge-orchestrator.sh - Post-merge automation pipeline
# Version: 1.0.0
#
# Orchestrates post-merge phases: classify → semver → changelog →
# gt_regen → rtfm → tag → release → notify.
#
# Usage:
#   .claude/scripts/post-merge-orchestrator.sh \
#     --pr <number> --type <cycle|bugfix|other> --sha <commit> \
#     [--dry-run] [--skip-gt] [--skip-rtfm]
#
# Exit Codes:
#   0 - All phases completed (some may have failed non-fatally)
#   1 - Invalid arguments
#   2 - Fatal error (state file corruption, missing dependencies)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Configuration
# =============================================================================

STATE_FILE="${PROJECT_ROOT}/.run/post-merge-state.json"
STATE_LOCK="${PROJECT_ROOT}/.run/post-merge-state.lock"

PR_NUMBER=""
PR_TYPE=""
MERGE_SHA=""
DRY_RUN=false
SKIP_GT=false
SKIP_RTFM=false
DOWNSTREAM=false

# Phase matrix: which phases run for each PR type.
# lore_promote (cycle-061, #484) runs after release for every PR type when
# enabled in config — turns the operator-triggered HARVEST consumer into a
# spiral-driven step. Default-disabled in config; opt-in per repo.
declare -A CYCLE_PHASES=( [classify]=1 [semver]=1 [changelog]=1 [gt_regen]=1 [rtfm]=1 [tag]=1 [release]=1 [lore_promote]=1 [notify]=1 )
declare -A BUGFIX_PHASES=( [classify]=1 [semver]=1 [changelog]=1 [tag]=1 [release]=1 [lore_promote]=1 [notify]=1 )
declare -A OTHER_PHASES=( [classify]=1 [semver]=1 [tag]=1 [lore_promote]=1 [notify]=1 )

# Ordered phase list
PHASE_ORDER=(classify semver changelog gt_regen rtfm tag release lore_promote notify)

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<'USAGE'
Usage: post-merge-orchestrator.sh [OPTIONS]

Options:
  --pr NUMBER          Source PR number (required)
  --type TYPE          PR type: cycle|bugfix|other (required)
  --sha COMMIT         Merge commit SHA (required)
  --dry-run            Validate without executing side effects
  --skip-gt            Skip ground truth regeneration
  --skip-rtfm          Skip RTFM validation
  --downstream         Filter commits to app-zone only (for downstream repos)
  --help               Show this help
USAGE
}

# =============================================================================
# State Management
# =============================================================================

# Atomic state update using flock
atomic_state_update() {
  local jq_expr="$1"
  shift
  (
    flock -w 5 200 || { echo "ERROR: Lock timeout on state file" >&2; return 1; }
    local tmp="${STATE_FILE}.tmp.$$"
    if jq "$jq_expr" "$@" "$STATE_FILE" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$STATE_FILE"
    else
      rm -f "$tmp"
      echo "ERROR: jq update failed" >&2
      return 1
    fi
  ) 200>"$STATE_LOCK"
}

# Initialize state file
init_state() {
  local rand_hex
  rand_hex=$(openssl rand -hex 3 2>/dev/null || head -c 3 /dev/urandom 2>/dev/null | xxd -p 2>/dev/null || printf '%06x' $((RANDOM * RANDOM)))
  local pm_id="pm-$(date +%Y%m%d)-${rand_hex}"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$(dirname "$STATE_FILE")"

  # Use jq for safe JSON construction (no shell injection via variables)
  jq -n \
    --arg pm_id "$pm_id" \
    --argjson pr_number "$PR_NUMBER" \
    --arg pr_type "$PR_TYPE" \
    --arg merge_sha "$MERGE_SHA" \
    --arg now "$now" \
    '{
      schema_version: 1,
      post_merge_id: $pm_id,
      pr_number: $pr_number,
      pr_type: $pr_type,
      merge_sha: $merge_sha,
      state: "RUNNING",
      timestamps: {
        started: $now,
        last_activity: $now,
        completed: null
      },
      phases: {
        classify: {status: "pending", result: null},
        semver: {status: "pending", result: null},
        changelog: {status: "pending", result: null},
        gt_regen: {status: "pending", result: null},
        rtfm: {status: "pending", result: null},
        tag: {status: "pending", result: null},
        release: {status: "pending", result: null},
        notify: {status: "pending", result: null}
      },
      errors: [],
      metrics: {
        duration_seconds: null,
        phases_completed: 0,
        phases_failed: 0,
        phases_skipped: 0
      }
    }' > "$STATE_FILE"
}

# Update a phase status and optional result
update_phase() {
  local phase="$1" status="$2" result="${3:-null}"

  atomic_state_update \
    --arg phase "$phase" \
    --arg status "$status" \
    --argjson result "$result" \
    '.phases[$phase].status = $status | .phases[$phase].result = $result | .timestamps.last_activity = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))'
}

# Increment a metric counter
increment_metric() {
  local field="$1"
  atomic_state_update --arg f "$field" '.metrics[$f] = (.metrics[$f] + 1)'
}

# Add an error to the errors array
log_error() {
  local phase="$1" message="$2"
  atomic_state_update \
    --arg phase "$phase" \
    --arg msg "$message" \
    '.errors += [{"phase": $phase, "message": $msg, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]'
}

# =============================================================================
# Phase Helpers
# =============================================================================

# Check if a phase should run for the current PR type
should_run_phase() {
  local phase="$1"
  case "$PR_TYPE" in
    cycle)  [[ -n "${CYCLE_PHASES[$phase]:-}" ]] ;;
    bugfix) [[ -n "${BUGFIX_PHASES[$phase]:-}" ]] ;;
    *)      [[ -n "${OTHER_PHASES[$phase]:-}" ]] ;;
  esac
}

# Check if gh CLI is available
check_gh() {
  if ! command -v gh &>/dev/null; then
    echo "WARNING: gh CLI not available — skipping GitHub operations" >&2
    return 1
  fi
  return 0
}

# Read a field from the state file
read_state() {
  local field="$1"
  jq -r "$field" "$STATE_FILE" 2>/dev/null
}

# =============================================================================
# Phase Implementations
# =============================================================================

phase_classify() {
  update_phase "classify" "in_progress"

  if [[ -n "$PR_TYPE" && -n "$PR_NUMBER" ]]; then
    # Type was provided via CLI — just record it
    local title=""
    if check_gh 2>/dev/null; then
      title=$(gh pr view "$PR_NUMBER" --json title --jq '.title' 2>/dev/null || echo "")
    fi

    local result
    result=$(jq -n \
      --argjson pr "$PR_NUMBER" \
      --arg type "$PR_TYPE" \
      --arg title "$title" \
      '{pr_number: $pr, pr_type: $type, title: $title}')

    update_phase "classify" "completed" "$result"
    increment_metric "phases_completed"
    echo "[CLASSIFY] PR #${PR_NUMBER} classified as: ${PR_TYPE}"
    return 0
  fi

  # Auto-classify from merge commit
  local pr_number
  pr_number=$(git -C "$PROJECT_ROOT" log -1 --format='%s' "$MERGE_SHA" 2>/dev/null | grep -o '#[0-9][0-9]*' | head -1 | tr -d '#' || echo "")

  if [[ -z "$pr_number" ]]; then
    update_phase "classify" "skipped" '{"reason": "no PR found in commit message"}'
    increment_metric "phases_skipped"
    echo "[CLASSIFY] No PR found in commit message — skipped"
    return 0
  fi

  PR_NUMBER="$pr_number"

  if check_gh 2>/dev/null; then
    local pr_json title labels
    pr_json=$(gh pr view "$pr_number" --json title,labels 2>/dev/null || echo '{}')
    title=$(echo "$pr_json" | jq -r '.title // ""')
    labels=$(echo "$pr_json" | jq -r '[.labels[]?.name] | join(",")' 2>/dev/null || echo "")

    # Classify via shared helper — single source of truth (Issue #550).
    # The pre-existing `|feat:` catch-all false-positived on every feat PR
    # as a full cycle. New classifier uses `\bcycle-[0-9]+\b` instead.
    local classifier="${SCRIPT_DIR}/classify-pr-type.sh"
    if [[ -f "$classifier" ]]; then
      # shellcheck source=classify-pr-type.sh
      source "$classifier"
      PR_TYPE=$(classify_pr_type "$title" "$labels")
    else
      # Defensive fallback
      if echo "$labels" | grep -qi "cycle"; then
        PR_TYPE="cycle"
      elif echo "$title" | grep -qE '\bcycle-[0-9]+\b|^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)'; then
        PR_TYPE="cycle"
      elif echo "$title" | grep -qE "^fix"; then
        PR_TYPE="bugfix"
      else
        PR_TYPE="other"
      fi
    fi

    local result
    result=$(jq -n \
      --argjson pr "$PR_NUMBER" \
      --arg type "$PR_TYPE" \
      --arg title "$title" \
      '{pr_number: $pr, pr_type: $type, title: $title}')
    update_phase "classify" "completed" "$result"
  else
    PR_TYPE="other"
    local result
    result=$(jq -n --argjson pr "$PR_NUMBER" --arg type "$PR_TYPE" '{pr_number: $pr, pr_type: $type, title: ""}')
    update_phase "classify" "completed" "$result"
  fi

  increment_metric "phases_completed"
  echo "[CLASSIFY] PR #${PR_NUMBER} classified as: ${PR_TYPE}"
}

phase_semver() {
  update_phase "semver" "in_progress"

  local semver_script="${SCRIPT_DIR}/semver-bump.sh"
  if [[ ! -f "$semver_script" ]]; then
    update_phase "semver" "failed" '{"reason": "semver-bump.sh not found"}'
    log_error "semver" "semver-bump.sh not found"
    increment_metric "phases_failed"
    return 1
  fi

  local semver_args=()
  if [[ "$DOWNSTREAM" == "true" ]]; then
    semver_args+=(--downstream)
  fi

  local result
  if result=$("$semver_script" "${semver_args[@]}" 2>/dev/null); then
    update_phase "semver" "completed" "$result"
    increment_metric "phases_completed"
    local current next bump
    current=$(echo "$result" | jq -r '.current')
    next=$(echo "$result" | jq -r '.next')
    bump=$(echo "$result" | jq -r '.bump')
    echo "[SEMVER] ${current} → ${next} (${bump})"
  else
    update_phase "semver" "failed" '{"reason": "semver calculation failed"}'
    log_error "semver" "semver-bump.sh failed with exit code $?"
    increment_metric "phases_failed"
    echo "[SEMVER] Failed — semver calculation error"
    return 1
  fi
}

# =============================================================================
# CHANGELOG Auto-Generation (FR-1, cycle-016)
# =============================================================================

# Generate a CHANGELOG entry from PR metadata and conventional commits
# when no [Unreleased] section is maintained by developers.
#
# Issue #697 Defect 2: accepts an optional pathspec argument so multi-changelog
# repos route framework-zone vs project-zone commits to the correct file.
# When pathspec is empty (single-changelog default), behavior matches pre-fix.
#
# Args:
#   $1 — version (e.g. "1.1.0")
#   $2 — changelog file path
#   $3 — git pathspec for `git log -- <pathspec>` filter (optional; empty = no filter)
auto_generate_changelog_entry() {
  local version="$1"
  local changelog="$2"
  local pathspec="${3:-}"
  local date_str
  date_str=$(date +%Y-%m-%d)

  # 1. Get PR metadata (single API call for efficiency)
  local pr_title="" pr_body=""
  if [[ -n "${PR_NUMBER:-}" ]] && check_gh 2>/dev/null; then
    local pr_json
    pr_json=$(gh pr view "$PR_NUMBER" --json title,body 2>/dev/null || true)
    if [[ -n "$pr_json" ]]; then
      pr_title=$(echo "$pr_json" | jq -r '.title // ""')
      pr_body=$(echo "$pr_json" | jq -r '.body // ""')
    fi
  fi

  # 2. Get conventional commits since previous tag
  # Use grep -A1 to find the tag BEFORE the current version (not just head -1)
  local prev_tag
  prev_tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | \
    grep -v "^v${version}$" | head -1)
  local range="${prev_tag:+${prev_tag}..HEAD}"

  # Build pathspec args for `git log`. Empty pathspec → no filter (single-
  # changelog backward-compat). Non-empty → `-- <pathspec>` so commits outside
  # the target domain are excluded.
  local -a pathspec_args=()
  if [[ -n "$pathspec" ]]; then
    pathspec_args=(--)
    # Allow space-separated multi-pathspec input (callers may pass exclude patterns).
    # shellcheck disable=SC2206
    local extra=($pathspec)
    pathspec_args+=("${extra[@]}")
  fi

  local feat_commits fix_commits
  if [[ -n "$range" ]]; then
    feat_commits=$(git -C "$PROJECT_ROOT" log "$range" --format='%s' \
        ${pathspec_args[@]+"${pathspec_args[@]}"} 2>/dev/null | grep -E '^feat' || true)
    fix_commits=$(git -C "$PROJECT_ROOT" log "$range" --format='%s' \
        ${pathspec_args[@]+"${pathspec_args[@]}"} 2>/dev/null | grep -E '^fix' || true)
  else
    feat_commits=$(git -C "$PROJECT_ROOT" log --format='%s' \
        ${pathspec_args[@]+"${pathspec_args[@]}"} 2>/dev/null | grep -E '^feat' || true)
    fix_commits=$(git -C "$PROJECT_ROOT" log --format='%s' \
        ${pathspec_args[@]+"${pathspec_args[@]}"} 2>/dev/null | grep -E '^fix' || true)
  fi

  # If pathspec filtering left no commits in this domain, skip writing entirely
  # — the entry would be vacuous. Caller (phase_changelog) treats this as
  # "no domain content for this version".
  if [[ -z "$feat_commits" && -z "$fix_commits" ]]; then
    return 1
  fi

  # 3. Extract subtitle from PR title
  local subtitle=""
  if [[ -n "$pr_title" ]]; then
    # Store regex in variable — bash [[ =~ ]] requires this for patterns with parentheses
    local re_with_pr_ref='^(feat|fix)\([^)]+\): (.+) \(#[0-9]+\)$'
    local re_simple='^(feat|fix)\([^)]+\): (.+)$'
    if [[ "$pr_title" =~ $re_with_pr_ref ]]; then
      subtitle="${BASH_REMATCH[2]}"
    elif [[ "$pr_title" =~ $re_simple ]]; then
      subtitle="${BASH_REMATCH[2]}"
    else
      subtitle="$pr_title"
    fi
  fi

  # 4. Extract summary from PR body (## Summary section or first paragraph)
  local summary=""
  if [[ -n "$pr_body" ]]; then
    # Try ## Summary section first (awk handles last-section case correctly)
    summary=$(printf '%s\n' "$pr_body" | awk '/^## Summary/{f=1;next} /^## /{f=0} f' | head -5)
    if [[ -z "$summary" ]]; then
      # Fall back to first non-empty paragraph
      summary=$(printf '%s\n' "$pr_body" | awk 'NF{p=1} p && !NF{exit} p' | head -5)
    fi
  fi

  # 5. Build entry
  local entry=""
  entry="## [${version}] — ${date_str}"
  if [[ -n "$subtitle" ]]; then
    entry+=" — ${subtitle}"
  fi
  entry+=$'\n'

  if [[ -n "$summary" ]]; then
    entry+=$'\n'"${summary}"$'\n'
  fi

  # Regex stored in variable — bash [[ =~ ]] requires this for patterns with parentheses
  local re_feat_scope='^feat\(([^)]+)\)'
  local re_fix_scope='^fix\(([^)]+)\)'

  if [[ -n "$feat_commits" ]]; then
    entry+=$'\n'"### Added"$'\n\n'
    while IFS= read -r commit; do
      local msg="${commit#*: }"
      local scope=""
      if [[ "$commit" =~ $re_feat_scope ]]; then
        scope="${BASH_REMATCH[1]}"
      fi
      if [[ -n "$scope" && "$scope" != "release" ]]; then
        entry+="- **${scope}**: ${msg}"$'\n'
      else
        entry+="- ${msg}"$'\n'
      fi
    done <<< "$feat_commits"
  fi

  if [[ -n "$fix_commits" ]]; then
    entry+=$'\n'"### Fixed"$'\n\n'
    while IFS= read -r commit; do
      local msg="${commit#*: }"
      local scope=""
      if [[ "$commit" =~ $re_fix_scope ]]; then
        scope="${BASH_REMATCH[1]}"
      fi
      if [[ -n "$scope" && "$scope" != "release" ]]; then
        entry+="- **${scope}**: ${msg}"$'\n'
      else
        entry+="- ${msg}"$'\n'
      fi
    done <<< "$fix_commits"
  fi

  if [[ -n "${PR_NUMBER:-}" ]]; then
    entry+=$'\n'"_Source: PR #${PR_NUMBER}_"$'\n'
  fi

  # 6. Insert into CHANGELOG before the first existing "## [" entry
  local tmpfile
  tmpfile=$(mktemp)
  local inserted=false

  while IFS= read -r line; do
    if [[ "$inserted" == false && "$line" =~ ^##\ \[ ]]; then
      printf '%s\n\n' "$entry" >> "$tmpfile"
      inserted=true
    fi
    printf '%s\n' "$line" >> "$tmpfile"
  done < "$changelog"

  # If no existing ## [ found, append after header
  if [[ "$inserted" == false ]]; then
    printf '\n%s\n' "$entry" >> "$tmpfile"
  fi

  mv "$tmpfile" "$changelog"
}

# Issue #697 Defect 2: discover sibling changelog files in the repo root.
# Returns paths newline-separated on stdout. Filters out backups, .claude/,
# node_modules, archive directories.
#
# The convention this honors: a repo with a single `CHANGELOG.md` is the
# common case (Loa upstream itself). Downstream Loa-mounted projects layer
# a `<PROJECT>-CHANGELOG.md` next to it; the unprefixed `CHANGELOG.md` then
# tracks framework changes (`.claude/**`) while `*-CHANGELOG.md` tracks
# project changes.
_discover_changelogs() {
  find "$PROJECT_ROOT" -maxdepth 2 -type f -name '*CHANGELOG.md' \
      -not -path '*/.claude/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/grimoires/*' \
      -not -path '*/.cycle-archive/*' \
      -not -name '*.bak' \
      2>/dev/null | sort
}

# Issue #697 Defect 2: write a single domain entry to a target changelog,
# honoring pathspec partitioning. Returns 0 if entry written, 1 if skipped
# (no domain commits, idempotent, or `[Unreleased]` finalization).
#
# Args:
#   $1 — version
#   $2 — changelog file
#   $3 — pathspec (empty for single-changelog/default)
#   $4 — domain label for log output ("framework", "project", or "")
_write_changelog_entry() {
  local version="$1" changelog="$2" pathspec="$3" domain_label="${4:-changelog}"

  # Per-target idempotency: skip if this version already documented in this file.
  if grep -q "## \[${version}\]" "$changelog"; then
    echo "[CHANGELOG/$domain_label] v${version} already in $changelog — skipped"
    return 1
  fi

  # If `[Unreleased]` exists, finalize it (existing pre-#697 behavior — applies
  # equally per-file in multi-changelog repos so each curated section lands).
  if grep -q '## \[Unreleased\]' "$changelog"; then
    local date_str
    date_str=$(date +%Y-%m-%d)
    local tmpfile
    tmpfile=$(mktemp)
    sed "s/## \[Unreleased\]/## [Unreleased]\\
\\
## [${version}] — ${date_str}/" "$changelog" > "$tmpfile" && mv "$tmpfile" "$changelog"
    echo "[CHANGELOG/$domain_label] Finalized v${version} in $(basename "$changelog")"
    return 0
  fi

  # Auto-generate path: respect pathspec filter so commits outside this domain
  # do not leak into this file. `auto_generate_changelog_entry` returns 1 if
  # the pathspec filter left no commits in scope.
  if auto_generate_changelog_entry "$version" "$changelog" "$pathspec"; then
    echo "[CHANGELOG/$domain_label] Auto-generated v${version} in $(basename "$changelog")"
    return 0
  fi
  echo "[CHANGELOG/$domain_label] No commits in domain for v${version} — $(basename "$changelog") unchanged"
  return 1
}

phase_changelog() {
  update_phase "changelog" "in_progress"

  # Get version from semver phase result
  local version
  version=$(read_state '.phases.semver.result.next // empty')
  if [[ -z "$version" ]]; then
    update_phase "changelog" "skipped" '{"reason": "no version from semver phase"}'
    increment_metric "phases_skipped"
    echo "[CHANGELOG] No version available — skipped"
    return 0
  fi

  # Issue #697 Defect 2: discover sibling *-CHANGELOG.md files. If only one
  # changelog exists (the Loa-upstream default), preserve pre-fix behavior.
  # If multiple exist, partition by .claude/** vs project paths.
  local changelogs
  changelogs=$(_discover_changelogs)
  local changelog_count
  changelog_count=$(printf '%s\n' "$changelogs" | grep -c . || true)

  if [[ "$changelog_count" -eq 0 ]]; then
    update_phase "changelog" "skipped" '{"reason": "no CHANGELOG.md found"}'
    increment_metric "phases_skipped"
    echo "[CHANGELOG] No CHANGELOG files found — skipped"
    return 0
  fi

  # Pre-check idempotency across ALL discovered changelogs. If every target
  # already documents this version, short-circuit with "already" reason —
  # preserves backward-compat with the existing dry-run idempotency test
  # (post-merge-int: CHANGELOG idempotent).
  local all_have=true
  while IFS= read -r _cl; do
    [[ -z "$_cl" ]] && continue
    if ! grep -q "## \[${version}\]" "$_cl"; then
      all_have=false
      break
    fi
  done <<< "$changelogs"

  if [[ "$all_have" == "true" ]]; then
    update_phase "changelog" "skipped" '{"reason": "version already in CHANGELOG"}'
    increment_metric "phases_skipped"
    echo "[CHANGELOG] Version ${version} already exists in all changelogs — skipped"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[CHANGELOG] Would finalize v${version} across ${changelog_count} changelog(s) (dry-run)"
    update_phase "changelog" "completed" '{"dry_run": true}'
    increment_metric "phases_completed"
    return 0
  fi

  if [[ "$changelog_count" -eq 1 ]]; then
    # Single changelog (Loa upstream default). No pathspec filter — preserves
    # backward-compat with existing test suite + production behavior.
    local changelog="$changelogs"
    if _write_changelog_entry "$version" "$changelog" "" "default"; then
      git -C "$PROJECT_ROOT" add "$changelog"
      if ! git -C "$PROJECT_ROOT" diff --cached --quiet; then
        git -C "$PROJECT_ROOT" commit -m "chore(release): v${version} — finalize CHANGELOG"
      fi
      update_phase "changelog" "completed" '{"mode": "single-changelog"}'
      increment_metric "phases_completed"
    else
      update_phase "changelog" "skipped" '{"reason": "version already documented or no commits"}'
      increment_metric "phases_skipped"
    fi
    return 0
  fi

  # Multi-changelog repo (e.g. CHANGELOG.md + ECHELON-CHANGELOG.md).
  # The unprefixed `CHANGELOG.md` is the framework changelog (filters to
  # `.claude/**` only). Any prefixed `*-CHANGELOG.md` is the project changelog
  # (excludes `.claude/**`).
  local framework_changelog="" project_changelog=""
  while IFS= read -r cl; do
    [[ -z "$cl" ]] && continue
    local base
    base=$(basename "$cl")
    if [[ "$base" == "CHANGELOG.md" ]]; then
      framework_changelog="$cl"
    else
      # First non-CHANGELOG.md match wins. Multi-project routing (3+ files) is
      # deferred to a future cycle (per .loa.config.yaml `changelog.routes`
      # schema) — heuristic detection is sufficient for cycle-105.5 use case.
      [[ -z "$project_changelog" ]] && project_changelog="$cl"
    fi
  done <<< "$changelogs"

  echo "[CHANGELOG] Multi-changelog routing: framework=${framework_changelog:-none} project=${project_changelog:-none}"

  local any_written=false
  local any_committed=false

  if [[ -n "$framework_changelog" ]]; then
    if _write_changelog_entry "$version" "$framework_changelog" ".claude/" "framework"; then
      git -C "$PROJECT_ROOT" add "$framework_changelog"
      any_written=true
    fi
  fi
  if [[ -n "$project_changelog" ]]; then
    if _write_changelog_entry "$version" "$project_changelog" ":!.claude/" "project"; then
      git -C "$PROJECT_ROOT" add "$project_changelog"
      any_written=true
    fi
  fi

  if [[ "$any_written" == "true" ]]; then
    if ! git -C "$PROJECT_ROOT" diff --cached --quiet; then
      git -C "$PROJECT_ROOT" commit -m "chore(release): v${version} — finalize multi-changelog routing"
      any_committed=true
    fi
    update_phase "changelog" "completed" "{\"mode\": \"multi-changelog\", \"committed\": ${any_committed}}"
    increment_metric "phases_completed"
  else
    update_phase "changelog" "skipped" '{"reason": "no domain content for either target", "mode": "multi-changelog"}'
    increment_metric "phases_skipped"
  fi
}

phase_gt_regen() {
  update_phase "gt_regen" "in_progress"

  if [[ "$SKIP_GT" == true ]]; then
    update_phase "gt_regen" "skipped" '{"reason": "skipped via --skip-gt"}'
    increment_metric "phases_skipped"
    echo "[GT_REGEN] Skipped via --skip-gt"
    return 0
  fi

  local gt_script="${SCRIPT_DIR}/ground-truth-gen.sh"
  if [[ ! -f "$gt_script" ]]; then
    update_phase "gt_regen" "skipped" '{"reason": "ground-truth-gen.sh not found"}'
    increment_metric "phases_skipped"
    echo "[GT_REGEN] ground-truth-gen.sh not found — skipped"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[GT_REGEN] Would regenerate ground truth (dry-run)"
    update_phase "gt_regen" "completed" '{"dry_run": true}'
    increment_metric "phases_completed"
    return 0
  fi

  # Issue #697 Defect 1: ground-truth-gen.sh requires --reality-dir AND
  # --output-dir for `--mode checksums`. Pre-fix the orchestrator omitted both
  # and silenced stderr via 2>/dev/null, so gt_regen was silently failing on
  # every cycle ship since the script's flag requirement landed.
  local gt_reality_dir="${PROJECT_ROOT}/grimoires/loa/reality"
  local gt_output_dir="${PROJECT_ROOT}/grimoires/loa/ground-truth"

  # Reality dir is the source of truth for what gets checksummed. If the repo
  # has not been onboarded via /ride, gracefully skip rather than fail.
  if [[ ! -d "$gt_reality_dir" ]]; then
    update_phase "gt_regen" "skipped" '{"reason": "reality dir not present (project not onboarded via /ride)"}'
    increment_metric "phases_skipped"
    echo "[GT_REGEN] No reality dir at $gt_reality_dir — skipped"
    return 0
  fi

  local gt_stderr gt_exit=0
  gt_stderr=$(mktemp)
  # NOTE: stderr captured to tmpfile (no 2>/dev/null swallow) so failures
  # surface diagnostic detail in the errors[] array.
  "$gt_script" --mode checksums \
      --reality-dir "$gt_reality_dir" \
      --output-dir "$gt_output_dir" \
      2>"$gt_stderr" || gt_exit=$?

  if [[ "$gt_exit" -eq 0 ]]; then
    # Commit if there are changes
    git -C "$PROJECT_ROOT" add grimoires/loa/ground-truth/ 2>/dev/null || true
    if ! git -C "$PROJECT_ROOT" diff --cached --quiet 2>/dev/null; then
      git -C "$PROJECT_ROOT" commit -m "chore(gt): regenerate ground truth checksums"
    fi
    update_phase "gt_regen" "completed"
    increment_metric "phases_completed"
    echo "[GT_REGEN] Ground truth checksums updated"
  else
    local gt_stderr_content
    gt_stderr_content=$(cat "$gt_stderr" 2>/dev/null || echo "")
    update_phase "gt_regen" "failed" "{\"exit_code\": $gt_exit}"
    log_error "gt_regen" "ground-truth-gen.sh failed (exit $gt_exit): ${gt_stderr_content}"
    increment_metric "phases_failed"
    echo "[GT_REGEN] Failed — exit code $gt_exit"
    [[ -n "$gt_stderr_content" ]] && echo "[GT_REGEN] stderr: $gt_stderr_content"
  fi
  rm -f "$gt_stderr"
}

phase_rtfm() {
  update_phase "rtfm" "in_progress"

  if [[ "$SKIP_RTFM" == true ]]; then
    update_phase "rtfm" "skipped" '{"reason": "skipped via --skip-rtfm"}'
    increment_metric "phases_skipped"
    echo "[RTFM] Skipped via --skip-rtfm"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[RTFM] Would run RTFM validation (dry-run)"
    update_phase "rtfm" "completed" '{"dry_run": true}'
    increment_metric "phases_completed"
    return 0
  fi

  # RTFM headless validation: check README.md and GT index.md for gaps
  # Uses the RTFM tester concept — spawn zero-context agent to test docs
  # Per C-MERGE-003: gaps are logged but do NOT block the pipeline
  local rtfm_report="${PROJECT_ROOT}/.run/post-merge-rtfm-report.json"
  local gap_count=0
  local docs_checked=0
  local gaps=()

  # Check README.md exists and has key sections
  local readme="${PROJECT_ROOT}/README.md"
  if [[ -f "$readme" ]]; then
    docs_checked=$((docs_checked + 1))
    # Check for version reference consistency
    local version
    version=$(read_state '.phases.semver.result.next // empty')
    if [[ -n "$version" ]] && ! grep -q "$version" "$readme" 2>/dev/null; then
      gaps+=("{\"doc\": \"README.md\", \"type\": \"STALE_VERSION\", \"severity\": \"MINOR\", \"detail\": \"Version $version not found in README\"}")
      gap_count=$((gap_count + 1))
    fi
  else
    gaps+=("{\"doc\": \"README.md\", \"type\": \"MISSING_DOC\", \"severity\": \"DEGRADED\", \"detail\": \"README.md not found\"}")
    gap_count=$((gap_count + 1))
  fi

  # Check GT index.md if it exists
  local gt_index="${PROJECT_ROOT}/grimoires/loa/ground-truth/index.md"
  if [[ -f "$gt_index" ]]; then
    docs_checked=$((docs_checked + 1))
    # Basic staleness check: GT should reference recent files
    # Use portable file age detection (stat -c is Linux-only, stat -f is macOS)
    local gt_mtime gt_age
    gt_mtime=$(stat -c %Y "$gt_index" 2>/dev/null || stat -f %m "$gt_index" 2>/dev/null || echo "0")
    gt_age=$(( $(date +%s) - gt_mtime ))
    local gt_staleness_threshold=604800  # 7 days in seconds
    if [[ "$gt_age" -gt "$gt_staleness_threshold" ]]; then
      gaps+=("{\"doc\": \"ground-truth/index.md\", \"type\": \"STALE_DOC\", \"severity\": \"MINOR\", \"detail\": \"GT index older than 7 days\"}")
      gap_count=$((gap_count + 1))
    fi
  fi

  # Write RTFM report
  local gaps_json="[]"
  if [[ ${#gaps[@]} -gt 0 ]]; then
    gaps_json="["
    local first=true
    for gap in "${gaps[@]}"; do
      if [[ "$first" == true ]]; then
        first=false
      else
        gaps_json+=","
      fi
      gaps_json+="$gap"
    done
    gaps_json+="]"
  fi

  jq -n \
    --argjson gaps "$gaps_json" \
    --argjson docs_checked "$docs_checked" \
    --argjson gap_count "$gap_count" \
    '{
      timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      docs_checked: $docs_checked,
      gap_count: $gap_count,
      verdict: (if $gap_count == 0 then "SUCCESS" else "PARTIAL" end),
      gaps: $gaps
    }' > "$rtfm_report"

  local result
  result=$(jq -n \
    --argjson gap_count "$gap_count" \
    --argjson docs_checked "$docs_checked" \
    '{gap_count: $gap_count, docs_checked: $docs_checked, report: ".run/post-merge-rtfm-report.json"}')

  update_phase "rtfm" "completed" "$result"
  increment_metric "phases_completed"

  if [[ "$gap_count" -gt 0 ]]; then
    echo "[RTFM] Found ${gap_count} documentation gap(s) across ${docs_checked} docs (non-blocking per C-MERGE-003)"
  else
    echo "[RTFM] All ${docs_checked} docs passed validation"
  fi
}

phase_tag() {
  update_phase "tag" "in_progress"

  local version
  version=$(read_state '.phases.semver.result.next // empty')
  if [[ -z "$version" ]]; then
    update_phase "tag" "skipped" '{"reason": "no version from semver phase"}'
    increment_metric "phases_skipped"
    echo "[TAG] No version available — skipped"
    return 0
  fi

  local tag="v${version}"

  # Idempotency: check if tag already exists
  if git -C "$PROJECT_ROOT" tag -l "$tag" | grep -q "$tag"; then
    update_phase "tag" "skipped" "{\"reason\": \"tag ${tag} already exists\"}"
    increment_metric "phases_skipped"
    echo "[TAG] Tag ${tag} already exists — skipped"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[TAG] Would create tag ${tag} (dry-run)"
    update_phase "tag" "completed" "{\"tag\": \"${tag}\", \"dry_run\": true}"
    increment_metric "phases_completed"
    return 0
  fi

  # Create annotated tag
  git -C "$PROJECT_ROOT" tag -a "$tag" -m "Release ${tag}"

  # Push tag
  if git -C "$PROJECT_ROOT" push origin "$tag" 2>/dev/null; then
    update_phase "tag" "completed" "{\"tag\": \"${tag}\"}"
    increment_metric "phases_completed"
    echo "[TAG] Created and pushed ${tag}"
  else
    # Tag created locally but push failed — still report success
    update_phase "tag" "completed" "{\"tag\": \"${tag}\", \"pushed\": false}"
    increment_metric "phases_completed"
    echo "[TAG] Created ${tag} (push to remote failed)"
  fi
}

phase_release() {
  update_phase "release" "in_progress"

  local version
  version=$(read_state '.phases.semver.result.next // empty')
  if [[ -z "$version" ]]; then
    update_phase "release" "skipped" '{"reason": "no version from semver phase"}'
    increment_metric "phases_skipped"
    echo "[RELEASE] No version available — skipped"
    return 0
  fi

  local tag="v${version}"

  if ! check_gh 2>/dev/null; then
    update_phase "release" "skipped" '{"reason": "gh CLI not available"}'
    increment_metric "phases_skipped"
    echo "[RELEASE] gh CLI not available — skipped"
    return 0
  fi

  # Idempotency: check if release already exists
  if gh release view "$tag" &>/dev/null; then
    update_phase "release" "skipped" "{\"reason\": \"release ${tag} already exists\"}"
    increment_metric "phases_skipped"
    echo "[RELEASE] Release ${tag} already exists — skipped"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[RELEASE] Would create GitHub Release ${tag} (dry-run)"
    update_phase "release" "completed" "{\"tag\": \"${tag}\", \"dry_run\": true}"
    increment_metric "phases_completed"
    return 0
  fi

  # Generate release notes
  local notes_script="${SCRIPT_DIR}/release-notes-gen.sh"
  local notes=""
  if [[ -f "$notes_script" ]]; then
    notes=$("$notes_script" --version "$version" --pr "$PR_NUMBER" --type "$PR_TYPE" 2>/dev/null || echo "Release ${tag}")
  else
    notes="Release ${tag}"
  fi

  # Extract release title with subtitle (FR-4, cycle-016)
  local release_title="${tag}"
  local pr_title_raw
  if [[ -n "${PR_NUMBER:-}" ]] && check_gh 2>/dev/null; then
    pr_title_raw=$(gh pr view "$PR_NUMBER" --json title --jq '.title' 2>/dev/null || true)
    if [[ -n "$pr_title_raw" ]]; then
      local subtitle=""
      local re_title_with_pr='^(feat|fix)\([^)]+\): (.+) \(#[0-9]+\)$'
      local re_title_simple='^(feat|fix)\([^)]+\): (.+)$'
      if [[ "$pr_title_raw" =~ $re_title_with_pr ]]; then
        subtitle="${BASH_REMATCH[2]}"
      elif [[ "$pr_title_raw" =~ $re_title_simple ]]; then
        subtitle="${BASH_REMATCH[2]}"
      fi
      [[ -n "$subtitle" ]] && release_title="${tag} — ${subtitle}"
    fi
  fi

  # Create release
  if gh release create "$tag" --title "$release_title" --notes "$notes" --verify-tag 2>/dev/null; then
    update_phase "release" "completed" "{\"tag\": \"${tag}\"}"
    increment_metric "phases_completed"
    echo "[RELEASE] Created GitHub Release ${tag}"
  else
    update_phase "release" "failed" '{"reason": "gh release create failed"}'
    log_error "release" "gh release create failed"
    increment_metric "phases_failed"
    echo "[RELEASE] Failed to create GitHub Release"
  fi
}

phase_lore_promote() {
  # Cycle-061 (#484): consume PRAISE candidates from
  # .run/bridge-lore-candidates.jsonl and promote vetted entries into
  # grimoires/loa/lore/patterns.yaml. Default-disabled — opt-in via
  # post_merge.lore_promote.enabled in .loa.config.yaml.
  #
  # Without this phase, lore-promote.sh (v1.80.0) never fires unless an
  # operator manually invokes it — meaning the autopoietic spiral never
  # closes. With this phase enabled, every merge auto-promotes patterns
  # that recurred across ≥2 distinct PRs (the safe-default floor).
  update_phase "lore_promote" "in_progress"

  local enabled
  enabled=$(yq '.post_merge.lore_promote.enabled // false' "${PROJECT_ROOT}/.loa.config.yaml" 2>/dev/null || echo "false")

  if [[ "$enabled" != "true" ]]; then
    update_phase "lore_promote" "skipped" '{"reason": "disabled in config"}'
    increment_metric "phases_skipped"
    echo "[LORE_PROMOTE] Skipped — post_merge.lore_promote.enabled is false"
    return 0
  fi

  local script="${PROJECT_ROOT}/.claude/scripts/lore-promote.sh"
  if [[ ! -x "$script" ]]; then
    update_phase "lore_promote" "skipped" '{"reason": "lore-promote.sh not found or not executable"}'
    increment_metric "phases_skipped"
    echo "[LORE_PROMOTE] Skipped — script missing: $script"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    update_phase "lore_promote" "skipped" '{"reason": "dry-run"}'
    increment_metric "phases_skipped"
    echo "[LORE_PROMOTE] Skipped — dry-run mode"
    return 0
  fi

  local out_log="${PROJECT_ROOT}/.run/post-merge-lore-promote.log"
  if "$script" --auto > "$out_log" 2>&1; then
    # Extract counts from log (best-effort)
    local promoted_count
    promoted_count=$(grep -c "Promoted " "$out_log" 2>/dev/null || echo 0)
    update_phase "lore_promote" "completed" "$(jq -nc --argjson n "$promoted_count" '{promoted: $n}')"
    increment_metric "phases_completed"
    echo "[LORE_PROMOTE] Completed — promoted $promoted_count pattern(s) (log: $out_log)"
  else
    update_phase "lore_promote" "failed" '{"reason": "lore-promote.sh exited non-zero"}'
    log_error "lore_promote" "lore-promote.sh failed (see $out_log)"
    increment_metric "phases_failed"
    echo "[LORE_PROMOTE] Failed — see $out_log"
    # Per RTFM gap convention from Post-Merge automation: this phase MUST NOT
    # block the pipeline (lore promotion is informational, not a release blocker)
    return 0
  fi
}

phase_notify() {
  update_phase "notify" "in_progress"

  # Build summary table from state
  local summary=""
  summary+="## Post-Merge Pipeline Results\n\n"
  summary+="| Phase | Status | Details |\n"
  summary+="|-------|--------|--------|\n"

  for phase in "${PHASE_ORDER[@]}"; do
    local status result_str
    status=$(read_state ".phases.${phase}.status // \"pending\"")
    local icon="⏳"
    case "$status" in
      completed) icon="✅" ;;
      failed)    icon="❌" ;;
      skipped)   icon="⊘" ;;
      pending)   icon="⏳" ;;
    esac

    # Extract a detail string from the result
    result_str=""
    case "$phase" in
      classify) result_str=$(read_state '.phases.classify.result.pr_type // ""') ;;
      semver)
        local curr next bump
        curr=$(read_state '.phases.semver.result.current // ""')
        next=$(read_state '.phases.semver.result.next // ""')
        bump=$(read_state '.phases.semver.result.bump // ""')
        [[ -n "$curr" ]] && result_str="${curr} → ${next} (${bump})"
        ;;
      tag) result_str=$(read_state '.phases.tag.result.tag // ""') ;;
      rtfm)
        local gaps
        gaps=$(read_state '.phases.rtfm.result.gap_count // ""')
        if [[ -n "$gaps" && "$gaps" != "null" ]]; then
          result_str="${gaps} gap(s)"
        else
          result_str=$(read_state '.phases.rtfm.result.reason // ""')
        fi
        ;;
      *) result_str=$(read_state ".phases.${phase}.result.reason // \"\"") ;;
    esac

    summary+="| ${phase} | ${icon} ${status} | ${result_str} |\n"
  done

  # Add timing
  local started
  started=$(read_state '.timestamps.started // ""')
  if [[ -n "$started" ]]; then
    summary+="\n_Started: ${started}_\n"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    printf '%b' "$summary"
    echo "[NOTIFY] Would post summary (dry-run)"
    update_phase "notify" "completed" '{"dry_run": true}'
    increment_metric "phases_completed"
    return 0
  fi

  # Post as PR comment if gh is available
  if check_gh 2>/dev/null && [[ -n "$PR_NUMBER" ]]; then
    printf '%b' "$summary" | gh pr comment "$PR_NUMBER" --body-file - 2>/dev/null || true
    echo "[NOTIFY] Posted summary to PR #${PR_NUMBER}"
  else
    printf '%b' "$summary"
    echo "[NOTIFY] Summary displayed (gh not available for PR comment)"
  fi

  update_phase "notify" "completed"
  increment_metric "phases_completed"
}

# =============================================================================
# Ledger Integration
# =============================================================================

# Archive the active cycle in the Sprint Ledger when a cycle PR merges.
#
# Issue #674 (sprint-bug-140): pre-archive completeness gate. Pre-fix the
# orchestrator blindly marked the active cycle as archived even when its
# sprints were still in `planned` / `in_progress` state. The integrity guard
# (post-merge.yml) caught this and reverted on every merge — pipeline failed
# on every cycle PR. The gate transforms the integrity guard from "routine
# recovery" into a true safety net.
archive_cycle_in_ledger() {
  local ledger="${PROJECT_ROOT}/grimoires/loa/ledger.json"
  if [[ ! -f "$ledger" ]]; then
    echo "[LEDGER] No ledger.json found — skipping cycle archival"
    return 0
  fi

  # Archive the cycle (with flock for concurrent safety)
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local ledger_lock="${ledger}.lock"
  local active_cycle=""

  (
    flock -w 5 200 || { echo "[LEDGER] Lock timeout — skipping" >&2; return 1; }

    # Find active cycle inside lock to prevent race condition
    active_cycle=$(jq -r '.cycles[] | select(.status == "active") | .id' "$ledger" 2>/dev/null || echo "")
    if [[ -z "$active_cycle" ]]; then
      echo "[LEDGER] No active cycle found — skipping"
      return 0
    fi

    # Issue #674: pre-archive gate — count sprints whose status is not
    # "completed". Skip-and-continue (return 0) on incomplete state so the
    # post-merge pipeline doesn't fail on cycle PRs whose remaining sprints
    # are still in flight. The cycle remains `active` until every sprint
    # closes; subsequent merges retry the gate idempotently.
    local incomplete_count
    incomplete_count=$(jq -r --arg cycle "$active_cycle" \
      '[(.cycles[] | select(.id == $cycle)).sprints[]? | select(.status != "completed")] | length' \
      "$ledger" 2>/dev/null || echo "0")

    if [[ "${incomplete_count:-0}" -gt 0 ]]; then
      echo "[LEDGER] Cycle ${active_cycle} has ${incomplete_count} incomplete sprint(s); skipping archive"
      return 0
    fi

    jq --arg cycle "$active_cycle" --arg now "$now" '
      .cycles = [.cycles[] |
        if .id == $cycle then
          .status = "archived" | .archived_at = $now
        else . end
      ]
    ' "$ledger" > "${ledger}.tmp"

    if [[ -s "${ledger}.tmp" ]]; then
      mv "${ledger}.tmp" "$ledger"
    else
      rm -f "${ledger}.tmp"
      echo "[LEDGER] Failed to update ledger — skipping"
      return 1
    fi
  ) 200>"$ledger_lock"

  local flock_exit=$?
  if [[ "$flock_exit" -eq 0 ]]; then
    echo "[LEDGER] Archived cycle ${active_cycle}"

    # Commit the ledger change
    git -C "$PROJECT_ROOT" add "$ledger" 2>/dev/null
    if ! git -C "$PROJECT_ROOT" diff --cached --quiet 2>/dev/null; then
      git -C "$PROJECT_ROOT" commit -m "chore(ledger): archive ${active_cycle} after merge" --quiet 2>/dev/null || true
    fi
  else
    echo "[LEDGER] Failed to update ledger — skipping"
  fi
}

# =============================================================================
# Orchestration
# =============================================================================

run_pipeline() {
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  Post-Merge Pipeline"
  echo "  PR: #${PR_NUMBER}  Type: ${PR_TYPE}  SHA: ${MERGE_SHA:0:8}"
  [[ "$DRY_RUN" == true ]] && echo "  MODE: DRY RUN"
  echo "════════════════════════════════════════════════════════════"
  echo ""

  for phase in "${PHASE_ORDER[@]}"; do
    if should_run_phase "$phase"; then
      # Run the phase function
      "phase_${phase}" || true  # Don't let phase failure stop the pipeline
    else
      update_phase "$phase" "skipped" '{"reason": "not in phase matrix for this PR type"}'
      increment_metric "phases_skipped"
    fi
  done

  # Post-pipeline: archive cycle in ledger for cycle-type PRs
  if [[ "$PR_TYPE" == "cycle" && "$DRY_RUN" != true ]]; then
    archive_cycle_in_ledger || true
  fi

  # Finalize state
  local completed failed skipped
  completed=$(read_state '.metrics.phases_completed // 0')
  failed=$(read_state '.metrics.phases_failed // 0')
  skipped=$(read_state '.metrics.phases_skipped // 0')

  atomic_state_update '.state = "DONE" | .timestamps.completed = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))'

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  Pipeline Complete"
  echo "  Completed: ${completed}  Failed: ${failed}  Skipped: ${skipped}"
  echo "════════════════════════════════════════════════════════════"

  # Output state file as structured result
  cat "$STATE_FILE"
}

# =============================================================================
# Main
# =============================================================================

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) PR_NUMBER="$2"; shift 2 ;;
      --type) PR_TYPE="$2"; shift 2 ;;
      --sha) MERGE_SHA="$2"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --skip-gt) SKIP_GT=true; shift ;;
      --skip-rtfm) SKIP_RTFM=true; shift ;;
      --downstream) DOWNSTREAM=true; shift ;;
      --help|-h) usage; exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done

  # Auto-detect downstream mode (cycle-052)
  # If no explicit --downstream flag, check if this is a non-loa repo
  if [[ "$DOWNSTREAM" == "false" ]]; then
    local classify_script="${SCRIPT_DIR}/classify-commit-zone.sh"
    if [[ -f "$classify_script" ]]; then
      source "$classify_script"
      if ! is_loa_repo 2>/dev/null; then
        DOWNSTREAM=true
      fi
    fi
  fi

  # Validate required arguments
  if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: --pr is required" >&2
    exit 1
  fi
  if [[ -z "$PR_TYPE" ]]; then
    echo "ERROR: --type is required" >&2
    exit 1
  fi
  if [[ -z "$MERGE_SHA" ]]; then
    echo "ERROR: --sha is required" >&2
    exit 1
  fi

  # Validate PR type
  case "$PR_TYPE" in
    cycle|bugfix|other) ;;
    *) echo "ERROR: Invalid --type: ${PR_TYPE} (expected cycle|bugfix|other)" >&2; exit 1 ;;
  esac

  # Validate PR number is numeric (H-04)
  if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --pr must be a number" >&2
    exit 1
  fi

  # Validate SHA is hex hash (H-05)
  if ! [[ "$MERGE_SHA" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    echo "ERROR: --sha must be a valid git commit hash" >&2
    exit 1
  fi

  # Initialize state
  init_state

  # Run pipeline
  run_pipeline
}

main "$@"
