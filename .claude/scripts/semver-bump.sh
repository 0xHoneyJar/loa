#!/usr/bin/env bash
# semver-bump.sh - Conventional commit semver parser
# Version: 1.0.0
#
# Reads git tag history and commit messages to compute the next
# semantic version based on conventional commit prefixes.
#
# Usage:
#   .claude/scripts/semver-bump.sh [--from-tag | --from-changelog]
#
# Output: JSON to stdout
#   {"current": "1.35.1", "next": "1.36.0", "bump": "minor", "commits": [...]}
#
# Exit Codes:
#   0 - Success
#   1 - No commits since last tag
#   2 - Invalid version source/input
#   3 - Commits cannot be classified

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# shellcheck source=lib/dx-utils.sh
if [[ -f "$SCRIPT_DIR/lib/dx-utils.sh" ]]; then
  source "$SCRIPT_DIR/lib/dx-utils.sh"
fi

# =============================================================================
# Bump Priority Map
# =============================================================================

# Conventional commit type → bump level
# major > minor > patch
declare -A BUMP_MAP=(
  ["feat"]=minor
  ["fix"]=patch
  ["perf"]=patch
  ["refactor"]=patch
  ["chore"]=patch
  ["docs"]=patch
  ["test"]=patch
  ["ci"]=patch
  ["style"]=patch
  ["build"]=patch
)

# Numeric priority for comparison
declare -A BUMP_PRIORITY=(
  ["patch"]=1
  ["minor"]=2
  ["major"]=3
)

# =============================================================================
# Version Utilities
# =============================================================================

# Get current version from the latest git tag matching either:
#   - vX.Y.Z          (release)
#   - vX.Y.Z-PRE.N    (prerelease, where PRE ∈ {alpha, beta, rc})
#
# Both shapes are returned to the caller; bump_version() handles the kind
# difference. Pre-1.0 projects that ship through a prerelease cadence (e.g.
# v2.0.0-alpha.7) need this to compute "next version" correctly — without
# the prerelease branch, the strict vX.Y.Z glob silently misses every
# alpha/beta/rc tag and the post-merge orchestrator skips tag/CHANGELOG/
# release entirely.
get_version_from_tag() {
  local tag
  # `tag -l` accepts multiple patterns; combine release + prerelease shapes,
  # then filter by precise regex (the glob is permissive — matches strings
  # like "v1.2.3-foo" too).
  # bug-745 residual (sprint-bug-203): full SemVer 2.0 §9/§10 — the official
  # grammar (pre-release: dot-separated alphanumeric/hyphen identifiers, no
  # leading-zero numerics, none empty; build metadata after '+'). PR #785
  # covered alpha|beta|rc.N only; pre.N/dev.N/dotted forms and +metadata
  # were silently filtered, skipping tag/CHANGELOG/release downstream.
  local semver_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'
  # bug-745 (review iter-1): git's -v:refname does NOT honor SemVer
  # prerelease precedence by default — `v1.0.0-alpha` sorts AFTER `v1.0.0`,
  # so a prerelease could be picked ahead of its own stable release.
  # `-c versionsort.suffix=-` tells git the '-' introduces a prerelease,
  # restoring §11 precedence (v1.0.0-alpha < v1.0.0) under descending sort.
  # (Build-metadata '+' tags are equal-precedence per §10; the grep keeps
  # them eligible and version sort breaks ties deterministically.)
  # KNOWN LIMIT (review iter-2): git version-sort is NOT a full SemVer §11
  # comparator — it can misorder two prereleases with arbitrary hyphenated /
  # dotted identifiers (e.g. alpha.1 vs alpha.beta). Accepted: this picker
  # selects among the project's own monotonic release tags, and the
  # CHANGELOG header is the authoritative current-version source
  # (get_version_from_tag is the fallback). A full bash SemVer comparator is
  # out of scope; release-vs-prerelease (the real-world failure) is correct.
  tag=$(git -C "$PROJECT_ROOT" -c versionsort.suffix=- \
    tag -l 'v[0-9]*.[0-9]*.[0-9]*' 'v[0-9]*.[0-9]*.[0-9]*-*' 'v[0-9]*.[0-9]*.[0-9]*+*' \
    --sort=-v:refname 2>/dev/null \
    | grep -E "$semver_re" \
    | head -1)
  if [[ -n "$tag" ]]; then
    echo "${tag#v}"
    return 0
  fi
  return 1
}

# Get current version from CHANGELOG.md header
get_version_from_changelog() {
  local changelog="${PROJECT_ROOT}/CHANGELOG.md"
  if [[ -f "$changelog" ]]; then
    local version
    version=$(grep -o '## \[[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\]' "$changelog" | head -1 | sed 's/## \[//;s/\]//')
    if [[ -n "$version" ]]; then
      echo "$version"
      return 0
    fi
  fi
  return 1
}

# Prerelease transitions signalled by the CHANGELOG (sprint-bug-240).
#
# bump_version() increments an existing prerelease (rc.1 → rc.2) but has no
# way to ENTER one from a release tag or to PROMOTE out of one; both were
# "operator-driven" with no formal path through the post-merge pipeline. The
# operator signal is the topmost versioned CHANGELOG heading, honoured for
# exactly two transitions and only while that heading is UNTAGGED:
#
#   enter    current X.Y.Z (release) and heading X'.Y'.Z'-PRE whose triple
#            equals the computed next release → next = heading
#            (1.202.1 + breaking commits → 2.0.0 → 2.0.0-rc.1)
#   promote  current X.Y.Z-PRE (prerelease) and heading exactly X.Y.Z
#            → next = heading                    (2.0.0-rc.3 → 2.0.0)
#
# Anything else keeps the computed version: a prerelease heading whose triple
# differs from the computed next warns on stderr (the commits do not warrant
# it); a tagged heading, an invalid prerelease identifier (SemVer §9 grammar)
# or a missing CHANGELOG are ignored. Prints "<kind>\t<heading>" and returns 0
# on a transition; returns 1 otherwise.
changelog_prerelease_transition() {
  local current="${1%%+*}" computed="$2"
  local changelog="${PROJECT_ROOT}/CHANGELOG.md"
  [[ -f "$changelog" ]] || return 1
  local heading
  heading=$(grep -m1 -oE '^## \[(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?\]' "$changelog") || return 1
  heading="${heading#\#\# [}"
  heading="${heading%]}"
  # A tagged heading is history, not intent.
  if git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/v${heading}" >/dev/null 2>&1; then
    return 1
  fi
  local pre_id='(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)'
  local prerelease_re="^([0-9]+\.[0-9]+\.[0-9]+)-(${pre_id}(\.${pre_id})*)\$"
  local release_re='^[0-9]+\.[0-9]+\.[0-9]+$'
  if [[ "$current" =~ $release_re && "$heading" =~ $prerelease_re ]]; then
    if [[ "${BASH_REMATCH[1]}" == "$computed" ]]; then
      printf 'enter\t%s\n' "$heading"
      return 0
    fi
    echo "WARN: CHANGELOG names ${heading} but the commits warrant ${computed}; heading ignored" >&2
    return 1
  fi
  if [[ "$current" =~ $prerelease_re && "$heading" =~ $release_re && "$heading" == "${current%%-*}" ]]; then
    printf 'promote\t%s\n' "$heading"
    return 0
  fi
  return 1
}

# Bump a version string by type. Handles two shapes:
#
#   1. Release  X.Y.Z          → bump per `bump` arg (major/minor/patch)
#   2. Prerelease X.Y.Z-PRE.N  → increment N (PRE ∈ {alpha, beta, rc})
#
# Prerelease bumping is type-agnostic by design: while a project is on a
# prerelease cadence (e.g. 2.0.0-alpha.N), conventional-commit signal
# (feat/fix/etc.) does not warrant a major/minor/patch flip — the project
# is still pre-1.0-of-this-major. Entering a prerelease and promoting out of
# one are operator-driven through the CHANGELOG heading
# (changelog_prerelease_transition above), not through this bump path.
#
# Validate version format (M-05) — accept either release or prerelease.
bump_version() {
  local current="$1" bump="$2"
  # bug-745: SemVer §10 — build metadata denotes a build of a version; the
  # NEXT version never inherits it. Strip before bumping (validated below
  # via the identifier grammar on what remains).
  local meta_re='^([^+]+)\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)$'
  if [[ "$current" =~ $meta_re ]]; then
    current="${BASH_REMATCH[1]}"
  fi
  # Full SemVer §9 pre-release grammar (PR #785 covered alpha|beta|rc.N only)
  local pre_id='(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)'
  local prerelease_re="^([0-9]+)\.([0-9]+)\.([0-9]+)-(${pre_id}(\.${pre_id})*)\$"
  local release_re='^([0-9]+)\.([0-9]+)\.([0-9]+)$'

  if [[ "$current" =~ $prerelease_re ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local pre="${BASH_REMATCH[4]}"
    # #785 policy preserved: any commit during a pre-release advances the
    # pre-release counter. Trailing numeric identifier increments; a
    # non-numeric tail gains a .1 (deterministic, precedence-increasing
    # per §11: alpha.beta < alpha.beta.1).
    local pre_head="${pre%.*}" pre_tail="${pre##*.}"
    if [[ "$pre" != *.* ]]; then pre_head=""; fi
    if [[ "$pre_tail" =~ ^(0|[1-9][0-9]*)$ ]]; then
      if [[ -n "$pre_head" ]]; then
        echo "${major}.${minor}.${patch}-${pre_head}.$((pre_tail + 1))"
      else
        echo "${major}.${minor}.${patch}-$((pre_tail + 1))"
      fi
    else
      echo "${major}.${minor}.${patch}-${pre}.1"
    fi
    return 0
  fi

  if [[ "$current" =~ $release_re ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    case "$bump" in
      major) echo "$((major + 1)).0.0" ;;
      minor) echo "${major}.$((minor + 1)).0" ;;
      patch) echo "${major}.${minor}.$((patch + 1))" ;;
      *) echo "ERROR: Unknown bump type: $bump" >&2; return 1 ;;
    esac
    return 0
  fi

  echo "ERROR: Invalid version format: $current" >&2
  return 1
}

# =============================================================================
# Commit Parsing
# =============================================================================

# Parse commits since a ref and determine bump type
# Outputs JSON array of commits to stderr, returns bump type on stdout
parse_commits() {
  local since_ref="$1"
  local range="${since_ref:+${since_ref}..}HEAD"
  local commits_json="[]"
  local highest_bump="patch"
  local highest_priority=0

  # Parse each commit
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local hash="${line%% *}"
    local subject="${line#* }"

    # Extract conventional commit parts
    local type="" scope="" msg="$subject"
    local cc_regex='^([a-z]+)(\([^)]*\))?(!)?\: (.*)$'
    if [[ "$subject" =~ $cc_regex ]]; then
      type="${BASH_REMATCH[1]}"
      scope="${BASH_REMATCH[2]}"
      scope="${scope#(}"
      scope="${scope%)}"
      msg="${BASH_REMATCH[4]}"
    fi

    # Determine bump for this commit type
    local commit_bump=""
    if [[ -n "$type" && -n "${BUMP_MAP[$type]:-}" ]]; then
      commit_bump="${BUMP_MAP[$type]}"
    fi
    local body breaking_re='^[a-z]+(\([^)]*\))?!:'
    body=$(git -C "$PROJECT_ROOT" log -1 --format='%B' "$hash") || return 2
    if [[ "$subject" =~ $breaking_re || "$body" == *"BREAKING CHANGE:"* ]]; then
      commit_bump="major"
    fi

    # Track highest bump (if not already major from breaking change)
    local priority=0
    [[ -n "$commit_bump" ]] && priority="${BUMP_PRIORITY[$commit_bump]}"
    if [[ "$priority" -gt "$highest_priority" ]]; then
      highest_priority=$priority
      highest_bump="$commit_bump"
    fi

    # Build commit JSON entry
    local commit_entry
    commit_entry=$(jq -n \
      --arg hash "$hash" \
      --arg type "${type:-unknown}" \
      --arg scope "${scope:-}" \
      --arg subject "$msg" \
      --arg bump "$commit_bump" \
      '{hash: $hash, type: $type, scope: $scope, subject: $subject, classified_bump: $bump}')

    commits_json=$(echo "$commits_json" | jq --argjson entry "$commit_entry" '. + [$entry]')

  done < <(git -C "$PROJECT_ROOT" log "$range" --format='%H %s')

  # Output commits JSON to fd 3
  echo "$commits_json" >&3
  if [[ "$highest_priority" -eq 0 ]]; then
    echo "ERROR: Cannot classify commits: no conventional-commit or breaking-change metadata" >&2
    return 3
  fi
  # Output bump type to stdout
  echo "$highest_bump"
}

# =============================================================================
# Main
# =============================================================================

main() {
  local source_mode="auto"
  local downstream=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from-tag) source_mode="tag"; shift ;;
      --from-changelog) source_mode="changelog"; shift ;;
      --downstream) downstream=true; shift ;;
      --help|-h|help)
        echo "Usage: semver-bump.sh [--from-tag | --from-changelog] [--downstream]"
        echo "  Computes next semver from conventional commits."
        echo "  Output: JSON with current, next, bump, commits"
        echo ""
        echo "Options:"
        echo "  --downstream  Filter out non-app commits (system-only, state-only, mixed-internal)"
        echo ""
        echo "Pre-releases: an untagged topmost CHANGELOG heading enters a prerelease of the"
        echo "  computed version (2.0.0 -> 2.0.0-rc.1) or promotes a prerelease to its release"
        echo "  (2.0.0-rc.3 -> 2.0.0); reported as prerelease_transition in the output."
        echo ""
        echo "Exit codes:"
        echo "  0  Success (JSON on stdout)"
        echo "  1  No commits since last tag"
        echo "  2  No version source found (no tags / no CHANGELOG match) or bad input"
        exit 0
        ;;
      *)
        if declare -f dx_unknown_flag >/dev/null 2>&1; then
          dx_unknown_flag "$1" "Usage: semver-bump.sh [--from-tag | --from-changelog] [--downstream]" \
            --from-tag --from-changelog --downstream --help
        else
          echo "ERROR: Unknown argument: $1" >&2
        fi
        exit 2
        ;;
    esac
  done

  # Determine current version
  local current=""
  local tag_ref=""
  local version_source="$source_mode"

  case "$source_mode" in
    tag)
      current=$(get_version_from_tag) || { echo "ERROR: No version tags found" >&2; exit 2; }
      tag_ref="v${current}"
      ;;
    changelog)
      current=$(get_version_from_changelog) || { echo "ERROR: No version in CHANGELOG.md" >&2; exit 2; }
      # Try to find matching tag
      if git -C "$PROJECT_ROOT" tag -l "v${current}" | grep -q "v${current}"; then
        tag_ref="v${current}"
      else
        echo "ERROR: No tag matching v${current} found" >&2
        exit 2
      fi
      ;;
    auto)
      if current=$(get_version_from_tag); then
        tag_ref="v${current}"
        version_source="tag"
      elif current=$(get_version_from_changelog); then
        if git -C "$PROJECT_ROOT" tag -l "v${current}" | grep -q "v${current}"; then
          tag_ref="v${current}"
          version_source="changelog"
        else
          echo "ERROR: CHANGELOG version v${current} has no matching tag" >&2
          exit 2
        fi
      else
        current="0.0.0"
        version_source="initial"
      fi
      ;;
  esac

  # Check for commits since tag
  local commit_count
  commit_count=$(git -C "$PROJECT_ROOT" rev-list "${tag_ref:+${tag_ref}..}HEAD" --count) || exit 2
  if [[ "$commit_count" -eq 0 ]]; then
    echo "ERROR: No commits since ${tag_ref}" >&2
    exit 1
  fi

  # Parse commits and determine bump
  local commits_json bump
  local tmpdir="${TMPDIR:-/tmp}"
  local tmpfile_commits tmpfile_bump
  # bug-978 (#978): trailing-X templates (BSD expands only trailing X-runs).
  # Both files are internal redirect targets; extensions were cosmetic.
  tmpfile_commits=$(mktemp "${tmpdir}/semver-commits.XXXXXXXXXX")
  tmpfile_bump=$(mktemp "${tmpdir}/semver-bump.XXXXXXXXXX")

  # Ensure cleanup on exit or error
  trap 'rm -f "$tmpfile_commits" "$tmpfile_bump"' EXIT

  # parse_commits writes commits JSON to fd 3, bump type to stdout
  # Redirect fd 3 to tmpfile_commits, stdout to tmpfile_bump
  if ! ( parse_commits "$tag_ref" 3>"$tmpfile_commits" ) > "$tmpfile_bump"; then
    rm -f "$tmpfile_commits" "$tmpfile_bump"
    trap - EXIT
    exit 3
  fi

  bump=$(cat "$tmpfile_bump")
  bump="${bump%$'\n'}"  # Trim trailing newline
  commits_json=$(cat "$tmpfile_commits")
  rm -f "$tmpfile_commits" "$tmpfile_bump"
  trap - EXIT

  # Downstream filtering: keep only app-zone commits (cycle-052)
  if [[ "$downstream" == "true" ]]; then
    # Source classify-commit-zone.sh for zone classification
    local classify_script="${SCRIPT_DIR}/classify-commit-zone.sh"
    if [[ -f "$classify_script" ]]; then
      source "$classify_script"

      local filtered_json="[]"
      local highest_app_bump="patch"
      local highest_app_priority=0
      local app_breaking=false
      local commit_count_after=0

      # Iterate each commit, keep only app-zone ones
      local total
      total=$(echo "$commits_json" | jq 'length')
      local i=0
      while [[ "$i" -lt "$total" ]]; do
        local hash
        hash=$(echo "$commits_json" | jq -r ".[$i].hash")
        local zone
        zone=$(classify_commit_zone "$hash" 2>/dev/null) || zone="app"

        if [[ "$zone" == "app" ]]; then
          local entry
          entry=$(echo "$commits_json" | jq ".[$i]")
          filtered_json=$(echo "$filtered_json" | jq --argjson e "$entry" '. + [$e]')

          # Recalculate bump from filtered commits
          local commit_bump
          commit_bump=$(echo "$entry" | jq -r '.classified_bump')
          local priority=0
          [[ -n "$commit_bump" ]] && priority="${BUMP_PRIORITY[$commit_bump]}"

          # Check for breaking change marker
          if [[ "$commit_bump" == major ]]; then
            app_breaking=true
          fi

          if [[ "$priority" -gt "$highest_app_priority" ]]; then
            highest_app_priority=$priority
            highest_app_bump="$commit_bump"
          fi
          commit_count_after=$((commit_count_after + 1))
        fi
        i=$((i + 1))
      done

      commits_json="$filtered_json"

      if [[ "$commit_count_after" -eq 0 ]]; then
        echo "ERROR: No app-zone commits since ${tag_ref} (all filtered as internal)" >&2
        exit 1
      fi

      # Update bump based on filtered commits
      if [[ "$app_breaking" == "true" ]]; then
        bump="major"
      elif [[ "$highest_app_priority" -eq 0 ]]; then
        echo "ERROR: Cannot classify app-zone commits" >&2
        exit 3
      else
        bump="$highest_app_bump"
      fi
    fi
  fi

  # Calculate next version
  local next transition_json="null"
  if [[ "$version_source" == "initial" ]]; then
    next="0.1.0"
    bump="initial"
  else
    next=$(bump_version "$current" "$bump")
    # sprint-bug-240: an untagged CHANGELOG heading may enter a prerelease of
    # the computed version or promote a prerelease to its release. `bump`
    # keeps the conventional-commit classification; the transition is
    # reported separately.
    local transition
    if transition=$(changelog_prerelease_transition "$current" "$next"); then
      next="${transition#*$'\t'}"
      transition_json=$(jq -nc --arg kind "${transition%%$'\t'*}" --arg heading "$next" \
        '{kind: $kind, source: "changelog", heading: $heading}')
    fi
  fi

  # Output result
  jq -n \
    --arg current "$current" \
    --arg next "$next" \
    --arg bump "$bump" \
    --arg source "$version_source" \
    --argjson commits "$commits_json" \
    --argjson transition "$transition_json" \
    '{current: $current, next: $next, bump: $bump, commits: $commits,
      version_source: $source,
      prerelease_transition: $transition,
      classification: {
        source: "conventional_commits",
        reasoning: (if $bump == "initial" then "First release from classified repository history"
          elif $bump == "major" then "Breaking-change metadata in commit history"
          else "Highest recognized conventional-commit bump in the selected history" end),
        commits: [$commits[] | select(.classified_bump != "") | .hash]
      }}'
}

main "$@"
