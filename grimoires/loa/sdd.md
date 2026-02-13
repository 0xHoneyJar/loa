# SDD: Post-Merge Automation Pipeline

**Version**: 1.0.0
**Status**: Draft
**Author**: Architecture Phase (architect)
**Source Issue**: https://github.com/0xHoneyJar/loa/issues/298
**Cycle**: cycle-007
**PRD Reference**: `grimoires/loa/prd.md`

---

## 1. Architecture Overview

The post-merge automation pipeline is a **three-layer system**:

```
Layer 1: GitHub Actions Workflow (trigger + classification)
         ↓
Layer 2: claude-code-action (AI bridge)
         ↓
Layer 3: Shell orchestrator (phase execution)
```

**Layer 1** detects merges to `main`, classifies the PR type, and decides which pipeline tier to run. For simple tiers (patch bump + tag), it executes directly in shell. For complex tiers (cycle completion), it invokes **Layer 2**.

**Layer 2** runs claude-code-action with the `/ship` skill prompt, giving Claude Code access to the codebase for intelligent operations (GT regeneration, RTFM validation, release notes).

**Layer 3** is a shell orchestrator (`post-merge-orchestrator.sh`) that executes pipeline phases sequentially with state tracking, idempotency, and graceful degradation.

### 1.1 System Diagram

```
                    ┌─────────────────────┐
                    │  PR merged to main  │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │   post-merge.yml    │
                    │  (GH Actions)       │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │    PR Classifier    │
                    └──┬──────┬──────┬───┘
                       │      │      │
              ┌────────▼┐  ┌──▼───┐  ┌▼────────┐
              │  cycle  │  │ bug  │  │  other  │
              │ complete│  │ fix  │  │         │
              └────┬────┘  └──┬───┘  └──┬──────┘
                   │          │         │
         ┌─────────▼────┐   ┌▼─────────▼─────┐
         │ claude-code  │   │  Shell-only     │
         │ -action      │   │  (semver+tag)   │
         │ → /ship      │   └─────────────────┘
         └──────┬───────┘
                │
    ┌───────────▼───────────┐
    │ post-merge-orchestrator│
    │                       │
    │ CLASSIFY              │
    │ → SEMVER              │
    │ → CHANGELOG           │
    │ → GT_REGEN            │
    │ → RTFM                │
    │ → TAG                 │
    │ → RELEASE             │
    │ → NOTIFY              │
    └───────────────────────┘
```

## 2. Component Design

### 2.1 GitHub Actions Workflow (`post-merge.yml`)

**File**: `.github/workflows/post-merge.yml`

**Trigger**:
```yaml
on:
  push:
    branches: [main]
```

**Concurrency**: Only one post-merge job runs at a time:
```yaml
concurrency:
  group: post-merge-${{ github.ref }}
  cancel-in-progress: false  # Never cancel in-progress merges
```

**Jobs**:

| Job | Purpose | Runs When |
|-----|---------|-----------|
| `classify` | Detect merge commit, extract PR, classify type | Always on push to main |
| `simple-release` | Semver bump + tag (shell-only) | Bug fixes and other PRs |
| `full-pipeline` | claude-code-action → /ship | Cycle completions |
| `notify` | Post summary, Discord notification | Always (after other jobs) |

**Classification Logic** (in `classify` job):
```bash
# Extract PR number from merge commit
PR_NUMBER=$(git log -1 --format='%s' | grep -oP '#\K[0-9]+' | head -1)

# Fetch PR metadata
PR_JSON=$(gh pr view "$PR_NUMBER" --json title,labels,body)
TITLE=$(echo "$PR_JSON" | jq -r '.title')
LABELS=$(echo "$PR_JSON" | jq -r '.labels[].name')

# Classify
if echo "$LABELS" | grep -q "cycle"; then
  echo "type=cycle" >> "$GITHUB_OUTPUT"
elif echo "$TITLE" | grep -qE "^(Run Mode|Sprint Plan|feat\(sprint)"; then
  echo "type=cycle" >> "$GITHUB_OUTPUT"
elif echo "$TITLE" | grep -qE "^fix"; then
  echo "type=bugfix" >> "$GITHUB_OUTPUT"
else
  echo "type=other" >> "$GITHUB_OUTPUT"
fi
```

### 2.2 claude-code-action Integration

**Used only for `cycle` type PRs** (GT regeneration, RTFM, release notes require AI).

```yaml
- name: Run Post-Merge Pipeline
  uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    prompt: |
      Run the post-merge automation pipeline for PR #${{ steps.classify.outputs.pr_number }}.
      PR type: cycle-completion.
      Merge commit: ${{ github.sha }}.

      Execute: .claude/scripts/post-merge-orchestrator.sh \
        --pr ${{ steps.classify.outputs.pr_number }} \
        --type cycle \
        --sha ${{ github.sha }}

      Post results as a comment on the merged PR.
    claude_args: |
      --max-turns 15
      --model claude-sonnet-4-5-20250929
      --allowedTools "Bash(bash),Read,Write,Glob,Grep"
  timeout-minutes: 30
```

**Cost guard**: Single invocation, 30-minute timeout, Sonnet model (not Opus).

**Fallback**: If claude-code-action fails, the `notify` job posts a warning and the maintainer can run `/ship` manually.

### 2.3 Post-Merge Orchestrator (`post-merge-orchestrator.sh`)

**File**: `.claude/scripts/post-merge-orchestrator.sh`

**Interface**:
```bash
post-merge-orchestrator.sh \
  --pr <number>         # Source PR number
  --type <cycle|bugfix|other>  # Classification
  --sha <commit>        # Merge commit SHA
  [--dry-run]           # Validate without executing
  [--skip-gt]           # Skip ground truth regeneration
  [--skip-rtfm]         # Skip RTFM validation
```

**State Machine**:
```
CLASSIFY → SEMVER → CHANGELOG → GT_REGEN → RTFM → TAG → RELEASE → NOTIFY → DONE
    ↓         ↓         ↓          ↓         ↓      ↓       ↓         ↓
  FAILED    FAILED    FAILED     FAILED   FAILED  FAILED  FAILED   FAILED
```

Each phase transitions independently. A failed phase logs the error and continues to the next phase (no cascading failure). Only TAG depends on SEMVER (needs the computed version).

**Phase Matrix** (which phases run for each PR type):

| Phase | cycle | bugfix | other |
|-------|-------|--------|-------|
| CLASSIFY | Yes | Yes | Yes |
| SEMVER | Yes | Yes | Yes |
| CHANGELOG | Yes | Yes | Skip |
| GT_REGEN | Yes | Skip | Skip |
| RTFM | Yes | Skip | Skip |
| TAG | Yes | Yes | Yes |
| RELEASE | Yes | Skip | Skip |
| NOTIFY | Yes | Yes | Yes |

### 2.4 Semver Parser (`semver-bump.sh`)

**File**: `.claude/scripts/semver-bump.sh`

**Interface**:
```bash
semver-bump.sh [--from-tag | --from-changelog]
# Output: JSON to stdout
```

**Algorithm**:
1. Get current version from latest `v*.*.*` tag (fallback: CHANGELOG header)
2. Get all commits since that tag: `git log v{current}..HEAD --format='%s'`
3. Parse each commit message for conventional commit prefix
4. Determine highest-priority bump:

```bash
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

# Check for BREAKING CHANGE (in any commit body or ! suffix)
if git log v${current}..HEAD --format='%B' | grep -q 'BREAKING CHANGE:'; then
  BUMP=major
elif git log v${current}..HEAD --format='%s' | grep -qE '^[a-z]+(\(.+\))?!:'; then
  BUMP=major
fi
```

**Output**:
```json
{
  "current": "1.35.1",
  "next": "1.36.0",
  "bump": "minor",
  "commits": [
    {"hash": "abc1234", "type": "feat", "scope": "sprint-1", "subject": "implement login"},
    {"hash": "def5678", "type": "fix", "scope": "sprint-1", "subject": "handle null token"}
  ]
}
```

**Version Arithmetic**:
```bash
bump_version() {
  local current="$1" bump="$2"
  IFS='.' read -r major minor patch <<< "$current"
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
  esac
}
```

### 2.5 Release Notes Generator (`release-notes-gen.sh`)

**File**: `.claude/scripts/release-notes-gen.sh`

**Interface**:
```bash
release-notes-gen.sh --version <version> --pr <number> --type <cycle|bugfix>
# Output: Markdown to stdout
```

**For cycle completions**:
1. Extract the version's section from CHANGELOG.md
2. Append PR link and sprint summary table
3. Append test results if available

**For bugfixes**:
1. Minimal template with fix description from PR title
2. Link to source PR

**Template** (cycle):
```markdown
## What's New in v{version}

{CHANGELOG section content}

### Source

- PR: #{pr_number}
- Commits: {count} ({feat_count} features, {fix_count} fixes)

---
Generated by Loa Post-Merge Automation
```

### 2.6 Enhanced `/ship` Skill

**File**: `.claude/skills/deploying-infrastructure/SKILL.md` (updated)

Adds dual-mode support:

| Mode | Trigger | Behavior |
|------|---------|----------|
| Manual | User runs `/ship` | Interactive confirmations |
| Automated | `--automated --pr N --sha S` | No prompts, posts results to PR |

In automated mode, `/ship` delegates to `post-merge-orchestrator.sh` and captures its JSON output for PR comment posting.

## 3. State Management

### 3.1 State File

**Path**: `.run/post-merge-state.json`

**Schema**:
```json
{
  "schema_version": 1,
  "post_merge_id": "pm-20260213-abc123",
  "pr_number": 301,
  "pr_type": "cycle",
  "merge_sha": "7c96385...",
  "state": "RUNNING",
  "timestamps": {
    "started": "2026-02-13T12:00:00Z",
    "last_activity": "2026-02-13T12:05:00Z",
    "completed": null
  },
  "phases": {
    "classify": {"status": "completed", "result": "cycle"},
    "semver": {"status": "completed", "result": {"current": "1.35.1", "next": "1.36.0", "bump": "minor"}},
    "changelog": {"status": "completed"},
    "gt_regen": {"status": "in_progress"},
    "rtfm": {"status": "pending"},
    "tag": {"status": "pending"},
    "release": {"status": "pending"},
    "notify": {"status": "pending"}
  },
  "errors": [],
  "metrics": {
    "duration_seconds": null,
    "phases_completed": 3,
    "phases_failed": 0,
    "phases_skipped": 0
  }
}
```

### 3.2 Atomic Updates

Follow the `bridge-state.sh` pattern:
```bash
atomic_state_update() {
  local jq_expr="$1"
  shift
  (
    flock -w 5 200 || { echo "ERROR: Lock timeout" >&2; return 1; }
    local tmp="${STATE_FILE}.tmp.$$"
    jq "$jq_expr" "$@" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  ) 200>"${STATE_FILE}.lock"
}
```

## 4. Configuration

### 4.1 `.loa.config.yaml` Additions

```yaml
post_merge:
  enabled: true
  # Which phases to run
  phases:
    changelog: true
    ground_truth: true
    rtfm: true
    release: true
  # PR type overrides
  types:
    cycle:
      phases: [classify, semver, changelog, gt_regen, rtfm, tag, release, notify]
    bugfix:
      phases: [classify, semver, tag, notify]
    other:
      phases: [classify, semver, tag, notify]
  # Timeouts
  timeouts:
    total_minutes: 30
    per_phase_minutes: 10
  # Notification
  notify:
    pr_comment: true
    discord: true
```

### 4.2 Repository Secrets Required

| Secret | Purpose |
|--------|---------|
| `ANTHROPIC_API_KEY` | claude-code-action API access |
| `DISCORD_WEBHOOK_URL` | Failure notifications (existing) |

### 4.3 Repository Permissions

The workflow needs:
```yaml
permissions:
  contents: write       # Create tags, push commits
  pull-requests: write  # Post PR comments
  issues: write         # Close related issues
  id-token: write       # Claude GitHub App OIDC
  actions: read         # Access CI results
```

## 5. Phase Details

### 5.1 CLASSIFY Phase

**Input**: Merge commit SHA
**Output**: PR number, PR type, PR metadata
**Idempotency**: Read-only, always safe to re-run

```bash
phase_classify() {
  local sha="$1"
  local pr_number
  pr_number=$(git log -1 --format='%s' "$sha" | grep -oP '#\K[0-9]+' | head -1)

  if [[ -z "$pr_number" ]]; then
    # Direct push, not a PR merge
    update_phase "classify" "skipped" '{"reason": "no PR found in commit message"}'
    return 0
  fi

  local pr_json
  pr_json=$(gh pr view "$pr_number" --json title,labels,body,mergedAt 2>/dev/null)
  local title=$(echo "$pr_json" | jq -r '.title')
  local labels=$(echo "$pr_json" | jq -r '[.labels[].name] | join(",")')

  local pr_type="other"
  if echo "$labels" | grep -q "cycle"; then
    pr_type="cycle"
  elif echo "$title" | grep -qE "^(Run Mode|Sprint Plan|feat\(sprint)"; then
    pr_type="cycle"
  elif echo "$title" | grep -qE "^fix"; then
    pr_type="bugfix"
  fi

  update_phase "classify" "completed" \
    "{\"pr_number\": $pr_number, \"pr_type\": \"$pr_type\", \"title\": $(echo "$title" | jq -Rs .)}"
}
```

### 5.2 SEMVER Phase

**Input**: Git tag history, commit messages
**Output**: Current version, next version, bump type
**Idempotency**: Deterministic from git history, safe to re-run

Delegates to `semver-bump.sh` and stores result in state.

### 5.3 CHANGELOG Phase

**Input**: `CHANGELOG.md`, computed version from SEMVER phase
**Output**: Updated `CHANGELOG.md` with version header replacing `[Unreleased]`
**Idempotency**: Checks if version header already exists before modifying

```bash
phase_changelog() {
  local version="$1" date
  date=$(date +%Y-%m-%d)

  if ! grep -q '## \[Unreleased\]' CHANGELOG.md; then
    update_phase "changelog" "skipped" '{"reason": "no [Unreleased] section"}'
    return 0
  fi

  if grep -q "## \[${version}\]" CHANGELOG.md; then
    update_phase "changelog" "skipped" '{"reason": "version already in CHANGELOG"}'
    return 0
  fi

  # Replace [Unreleased] with versioned header, add new [Unreleased] above
  sed -i "s/## \[Unreleased\]/## [Unreleased]\n\n## [${version}] - ${date}/" CHANGELOG.md

  git add CHANGELOG.md
  git commit -m "chore(release): v${version} — finalize CHANGELOG"
  update_phase "changelog" "completed"
}
```

### 5.4 GT_REGEN Phase

**Input**: Current codebase state
**Output**: Updated ground truth files in `grimoires/loa/ground-truth/`
**Idempotency**: Regeneration overwrites previous state

```bash
phase_gt_regen() {
  if [[ ! -f ".claude/scripts/ground-truth-gen.sh" ]]; then
    update_phase "gt_regen" "skipped" '{"reason": "ground-truth-gen.sh not found"}'
    return 0
  fi

  .claude/scripts/ground-truth-gen.sh --mode checksums
  local exit_code=$?

  if [[ "$exit_code" -eq 0 ]]; then
    git add grimoires/loa/ground-truth/ 2>/dev/null || true
    if ! git diff --cached --quiet; then
      git commit -m "chore(gt): regenerate ground truth checksums"
    fi
    update_phase "gt_regen" "completed"
  else
    update_phase "gt_regen" "failed" '{"exit_code": '"$exit_code"'}'
  fi
}
```

### 5.5 RTFM Phase

**Input**: Documentation files (README.md, INSTALLATION.md, GT index.md)
**Output**: Gap report JSON
**Idempotency**: Read-only validation, safe to re-run

RTFM runs as a validation gate. Gaps are logged but don't block the pipeline.

### 5.6 TAG Phase

**Input**: Computed version from SEMVER phase
**Output**: Git tag `v{version}` pushed to origin
**Idempotency**: Checks tag existence before creating

```bash
phase_tag() {
  local version="$1"
  local tag="v${version}"

  if git tag -l "$tag" | grep -q "$tag"; then
    update_phase "tag" "skipped" '{"reason": "tag already exists"}'
    return 0
  fi

  git tag -a "$tag" -m "Release ${tag}"
  git push origin "$tag"
  update_phase "tag" "completed" "{\"tag\": \"$tag\"}"
}
```

### 5.7 RELEASE Phase

**Input**: Version, release notes from `release-notes-gen.sh`
**Output**: GitHub Release
**Idempotency**: Checks release existence before creating

```bash
phase_release() {
  local version="$1" pr_number="$2" pr_type="$3"
  local tag="v${version}"

  if gh release view "$tag" &>/dev/null; then
    update_phase "release" "skipped" '{"reason": "release already exists"}'
    return 0
  fi

  local notes
  notes=$(.claude/scripts/release-notes-gen.sh \
    --version "$version" --pr "$pr_number" --type "$pr_type")

  gh release create "$tag" \
    --title "v${version}" \
    --notes "$notes" \
    --verify-tag

  update_phase "release" "completed"
}
```

### 5.8 NOTIFY Phase

**Input**: Pipeline results from state file
**Output**: PR comment and optional Discord notification
**Idempotency**: Uses sticky comment (updates existing comment)

Posts a summary table to the merged PR:

```markdown
## Post-Merge Pipeline Results

| Phase | Status | Details |
|-------|--------|---------|
| Classify | ✅ | cycle-completion |
| Semver | ✅ | 1.35.1 → 1.36.0 (minor) |
| Changelog | ✅ | Finalized |
| Ground Truth | ✅ | Checksums updated |
| RTFM | ⚠️ | 2 gaps (non-blocking) |
| Tag | ✅ | v1.36.0 |
| Release | ✅ | [v1.36.0](link) |

Duration: 4m 32s
```

## 6. Error Handling

### 6.1 Phase Failure Strategy

Each phase is independent. A failed phase:
1. Logs the error to state file
2. Continues to next phase (unless TAG depends on SEMVER)
3. NOTIFY phase reports all failures

### 6.2 Graceful Degradation

| Failure | Impact | Fallback |
|---------|--------|----------|
| claude-code-action timeout | No GT/RTFM/release | Shell-only: semver + tag |
| `gh` CLI unavailable | No PR comment, no release | Tag still created locally |
| No `[Unreleased]` in CHANGELOG | CHANGELOG phase skips | Manual CHANGELOG update |
| GT script missing | GT phase skips | Manual GT regeneration |
| Tag already exists | TAG phase skips | No duplicate tags |
| Release already exists | RELEASE phase skips | No duplicate releases |

### 6.3 Circuit Breaker

If the same merge SHA triggers the workflow twice (e.g., rerun), all phases check for existing work before acting (idempotency).

## 7. Testing Strategy

### 7.1 Unit Tests

| Test File | Tests |
|-----------|-------|
| `tests/unit/semver-bump.bats` | Version parsing, bump logic, conventional commits |
| `tests/unit/post-merge-orchestrator.bats` | Phase execution, state transitions, idempotency |
| `tests/unit/release-notes-gen.bats` | CHANGELOG extraction, template rendering |

### 7.2 Key Test Cases

**Semver Parser**:
- `feat(auth): add login` → minor bump
- `fix(api): null check` → patch bump
- `feat(core)!: redesign API` → major bump (! suffix)
- `chore: update deps` with `BREAKING CHANGE:` in body → major bump
- No new commits since tag → no bump (error)
- No tags exist → read from CHANGELOG

**Orchestrator**:
- Cycle PR runs all 8 phases
- Bugfix PR runs only classify, semver, tag, notify
- Already-tagged version skips TAG phase
- Failed GT_REGEN doesn't block TAG
- Dry-run mode executes no side effects

**Release Notes**:
- Extracts correct CHANGELOG section
- Handles missing `[Unreleased]` section
- Includes PR link

## 8. File Manifest

### New Files

| File | Type | Description |
|------|------|-------------|
| `.github/workflows/post-merge.yml` | Workflow | GH Action trigger + classification |
| `.claude/scripts/post-merge-orchestrator.sh` | Script | Phase orchestrator |
| `.claude/scripts/semver-bump.sh` | Script | Conventional commit version calculator |
| `.claude/scripts/release-notes-gen.sh` | Script | Release notes from CHANGELOG |
| `tests/unit/semver-bump.bats` | Test | Semver parser tests |
| `tests/unit/post-merge-orchestrator.bats` | Test | Orchestrator tests |
| `tests/unit/release-notes-gen.bats` | Test | Release notes tests |

### Modified Files

| File | Change |
|------|--------|
| `.loa.config.yaml.example` | Add `post_merge:` section |
| `.claude/loa/CLAUDE.loa.md` | Add post-merge section |
| `.claude/data/constraints.json` | Add C-MERGE constraints |
| `CHANGELOG.md` | Add v1.36.0 entry |
| `README.md` | Update version badge |

## 9. Constraints

| ID | Rule | Why |
|----|------|-----|
| C-MERGE-001 | ALWAYS use `--verify-tag` when creating GitHub Releases | Ensures tag exists before release creation |
| C-MERGE-002 | ALWAYS check tag existence before creating | Prevents duplicate tags on reruns |
| C-MERGE-003 | NEVER block the pipeline on RTFM failures | Doc gaps are informational, not release-blocking |
| C-MERGE-004 | ALWAYS use concurrency groups in the GH Action | Prevents parallel post-merge runs |
| C-MERGE-005 | ALWAYS post pipeline results to the merged PR | Audit trail for what happened after merge |

## 10. Security Considerations

- `ANTHROPIC_API_KEY` is a repository secret, never logged
- claude-code-action runs with explicit tool allowlist (`Bash`, `Read`, `Write`, `Glob`, `Grep`)
- No `--dangerously-skip-permissions` flag
- Workflow permissions are minimal (`contents: write`, `pull-requests: write`)
- Redaction patterns from `bridge-github-trail.sh` applied to any PR comments
- 30-minute timeout prevents cost runaway

---

**Next Step**: `/sprint-plan` to break this into implementation tasks.
