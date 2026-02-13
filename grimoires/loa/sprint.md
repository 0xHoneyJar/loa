# Sprint Plan: Post-Merge Automation Pipeline

**Cycle**: cycle-007
**Issue**: https://github.com/0xHoneyJar/loa/issues/298
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`

---

## Overview

| Metric | Value |
|--------|-------|
| **Total Sprints** | 3 |
| **Total Tasks** | 22 |
| **Estimated Effort** | Medium (shell scripts + GH workflow + config) |
| **Dependencies** | `ANTHROPIC_API_KEY` repo secret (for Sprint 3) |

---

## Sprint 1: Foundation — Semver Parser & Orchestrator Shell

**Goal**: Build the core shell infrastructure: semver parser, orchestrator skeleton, state management.

### Task 1.1: Semver Bump Script

**File**: `.claude/scripts/semver-bump.sh`

**Description**: Create the conventional commit semver parser that reads git tag history and commit messages to compute the next version.

**Acceptance Criteria**:
- [ ] Reads current version from latest `v*.*.*` git tag
- [ ] Falls back to CHANGELOG.md version header if no tags exist
- [ ] Parses conventional commit prefixes: feat→minor, fix→patch, chore→patch
- [ ] Detects BREAKING CHANGE in commit body → major bump
- [ ] Detects `!` suffix (e.g., `feat!:`) → major bump
- [ ] Highest-priority bump wins (major > minor > patch)
- [ ] Outputs JSON: `{"current", "next", "bump", "commits"}`
- [ ] Exits with error if no commits since last tag
- [ ] Script is executable and sources bootstrap.sh

### Task 1.2: Semver Bump Tests

**File**: `tests/unit/semver-bump.bats`

**Description**: Comprehensive BATS tests for the semver parser.

**Acceptance Criteria**:
- [ ] Tests feat → minor bump
- [ ] Tests fix → patch bump
- [ ] Tests BREAKING CHANGE → major bump
- [ ] Tests `!` suffix → major bump
- [ ] Tests mixed commits (feat + fix) → minor wins
- [ ] Tests no tags fallback to CHANGELOG
- [ ] Tests no commits since tag → error
- [ ] Tests JSON output structure
- [ ] Minimum 15 test cases

### Task 1.3: Release Notes Generator

**File**: `.claude/scripts/release-notes-gen.sh`

**Description**: Extract release notes from CHANGELOG.md for a given version, or generate minimal notes for bugfix releases.

**Acceptance Criteria**:
- [ ] Extracts CHANGELOG section between version headers
- [ ] Handles missing `[Unreleased]` section gracefully
- [ ] Includes PR link in output
- [ ] Cycle template: full CHANGELOG section + source info
- [ ] Bugfix template: minimal "Bug fix release" + PR link
- [ ] Outputs markdown to stdout
- [ ] Script is executable and sources bootstrap.sh

### Task 1.4: Release Notes Tests

**File**: `tests/unit/release-notes-gen.bats`

**Description**: BATS tests for release notes generation.

**Acceptance Criteria**:
- [ ] Tests cycle release extraction from CHANGELOG
- [ ] Tests bugfix template generation
- [ ] Tests missing CHANGELOG handling
- [ ] Tests version not found in CHANGELOG
- [ ] Minimum 8 test cases

### Task 1.5: Post-Merge Orchestrator Skeleton

**File**: `.claude/scripts/post-merge-orchestrator.sh`

**Description**: Create the orchestrator with argument parsing, state initialization, phase matrix, and phase dispatch loop.

**Acceptance Criteria**:
- [ ] Accepts `--pr`, `--type`, `--sha`, `--dry-run`, `--skip-gt`, `--skip-rtfm` flags
- [ ] Initializes state file at `.run/post-merge-state.json`
- [ ] Phase matrix: cycle runs all 8, bugfix runs 4, other runs 4
- [ ] Sequential phase dispatch with per-phase error capture
- [ ] Atomic state updates using flock pattern from bridge-state.sh
- [ ] Dry-run mode logs phases without executing side effects
- [ ] Graceful `gh` CLI detection (skip GitHub ops if unavailable)
- [ ] Script is executable and sources bootstrap.sh

### Task 1.6: Post-Merge Orchestrator Tests

**File**: `tests/unit/post-merge-orchestrator.bats`

**Description**: BATS tests for the orchestrator.

**Acceptance Criteria**:
- [ ] Tests argument parsing for all flags
- [ ] Tests phase matrix for cycle, bugfix, other types
- [ ] Tests state file initialization
- [ ] Tests dry-run mode
- [ ] Tests graceful degradation when gh is unavailable
- [ ] Minimum 12 test cases

### Task 1.7: Orchestrator Phase Implementations

**File**: `.claude/scripts/post-merge-orchestrator.sh` (continued)

**Description**: Implement all 8 phase functions within the orchestrator.

**Acceptance Criteria**:
- [ ] `phase_classify()`: Extracts PR number from commit, fetches PR metadata via gh, classifies type
- [ ] `phase_semver()`: Delegates to semver-bump.sh, stores result in state
- [ ] `phase_changelog()`: Replaces `[Unreleased]` with versioned header, idempotent
- [ ] `phase_gt_regen()`: Invokes ground-truth-gen.sh --mode checksums, commits if changes
- [ ] `phase_rtfm()`: Placeholder that logs "RTFM validation" (full implementation in Sprint 3)
- [ ] `phase_tag()`: Creates and pushes annotated tag, idempotent
- [ ] `phase_release()`: Creates GitHub Release via gh, idempotent
- [ ] `phase_notify()`: Posts summary table to PR comment

---

## Sprint 2: GitHub Actions Workflow & Integration

**Goal**: Create the GH Actions workflow, wire claude-code-action, update Loa config and docs.

### Task 2.1: Post-Merge Workflow

**File**: `.github/workflows/post-merge.yml`

**Description**: GitHub Actions workflow that triggers on push to main, classifies the PR, and dispatches to the appropriate pipeline tier.

**Acceptance Criteria**:
- [ ] Triggers on `push` to `main` branch only
- [ ] Concurrency group prevents parallel runs
- [ ] `classify` job: extracts PR number, classifies type, outputs pr_number + pr_type
- [ ] `simple-release` job: runs for bugfix/other, executes semver + tag in shell
- [ ] `full-pipeline` job: runs for cycle PRs, invokes claude-code-action
- [ ] `notify` job: posts results, sends Discord notification on failure
- [ ] 30-minute timeout on full-pipeline job
- [ ] Proper permissions block (contents:write, pull-requests:write, id-token:write, actions:read)

### Task 2.2: claude-code-action Configuration

**File**: `.github/workflows/post-merge.yml` (full-pipeline job)

**Description**: Configure the claude-code-action step with proper prompt, model, tool allowlist, and timeout.

**Acceptance Criteria**:
- [ ] Uses `anthropics/claude-code-action@v1`
- [ ] Prompt includes PR number, type, merge SHA
- [ ] Model: `claude-sonnet-4-5-20250929` (cost-efficient)
- [ ] `--max-turns 15` to limit conversation depth
- [ ] Tool allowlist: `Bash(bash),Read,Write,Glob,Grep`
- [ ] Reads `ANTHROPIC_API_KEY` from repository secrets
- [ ] Structured output captures pipeline result JSON

### Task 2.3: Config & Constraints Update

**Files**: `.loa.config.yaml.example`, `.claude/data/constraints.json`

**Description**: Add `post_merge:` configuration section and C-MERGE constraints.

**Acceptance Criteria**:
- [ ] `.loa.config.yaml.example` has `post_merge:` section with all options
- [ ] `constraints.json` has C-MERGE-001 through C-MERGE-005
- [ ] Constraint hash updated
- [ ] Config example has comments explaining each option

### Task 2.4: CLAUDE.loa.md Update

**File**: `.claude/loa/CLAUDE.loa.md`

**Description**: Add Post-Merge Automation section to framework instructions.

**Acceptance Criteria**:
- [ ] New section: "Post-Merge Automation (v1.36.0)"
- [ ] Documents the 3-layer architecture
- [ ] Documents phase matrix for each PR type
- [ ] References configuration options
- [ ] Constraint-generated block for C-MERGE rules

### Task 2.5: CHANGELOG & Version Bump

**Files**: `CHANGELOG.md`, `README.md`, `.loa-version.json`

**Description**: Add v1.36.0 changelog entry and bump version references.

**Acceptance Criteria**:
- [ ] CHANGELOG has `## [1.36.0]` entry with all changes
- [ ] README version badge updated
- [ ] `.loa-version.json` version updated
- [ ] Why This Release section explains issue #298

### Task 2.6: Integration Tests

**File**: `tests/unit/post-merge-orchestrator.bats` (extended)

**Description**: Add integration-level tests that exercise the full orchestrator flow with mocked external commands.

**Acceptance Criteria**:
- [ ] Tests full cycle pipeline (all 8 phases mock-executed)
- [ ] Tests bugfix pipeline (4 phases)
- [ ] Tests idempotency (run twice, no duplicate tags/releases)
- [ ] Tests CHANGELOG finalization
- [ ] Tests notify phase generates correct summary table
- [ ] Minimum 10 additional test cases

---

## Sprint 3: Ship Skill Enhancement & E2E Wiring

**Goal**: Wire the `/ship` skill for dual-mode operation, add RTFM integration, and validate E2E flow.

### Task 3.1: Ship Skill Enhancement

**File**: `.claude/skills/deploying-infrastructure/SKILL.md` (or new ship skill file)

**Description**: Extend `/ship` to support automated mode (invoked by claude-code-action) and manual mode (invoked by user).

**Acceptance Criteria**:
- [ ] Manual mode: interactive confirmations, shows progress
- [ ] Automated mode: `--automated --pr N --sha S` suppresses prompts
- [ ] Both modes delegate to `post-merge-orchestrator.sh`
- [ ] Automated mode posts results as PR comment
- [ ] Manual mode displays results in terminal

### Task 3.2: RTFM Phase Integration

**File**: `.claude/scripts/post-merge-orchestrator.sh` (phase_rtfm)

**Description**: Replace the RTFM placeholder with actual RTFM validation invocation.

**Acceptance Criteria**:
- [ ] Invokes RTFM testing on README.md and GT index.md
- [ ] Runs in headless mode (no user prompts)
- [ ] Gap report saved to `.run/post-merge-rtfm-report.json`
- [ ] Gaps are logged but don't block the pipeline (per C-MERGE-003)
- [ ] Gap count included in NOTIFY phase summary

### Task 3.3: Discord Notification

**File**: `.github/workflows/post-merge.yml` (notify job)

**Description**: Add Discord webhook notification on pipeline failure.

**Acceptance Criteria**:
- [ ] Posts to Discord only on failure (not success)
- [ ] Uses existing `DISCORD_WEBHOOK_URL` secret
- [ ] Message includes: PR number, failed phase, error summary
- [ ] Gracefully skips if `DISCORD_WEBHOOK_URL` is not set

### Task 3.4: Ledger & Cycle Integration

**File**: `.claude/scripts/post-merge-orchestrator.sh` (phase_classify enhancement)

**Description**: When a cycle-completion PR merges, automatically archive the cycle in the Sprint Ledger.

**Acceptance Criteria**:
- [ ] Detects cycle ID from PR body or commit messages
- [ ] Archives the cycle in `grimoires/loa/ledger.json`
- [ ] Moves planning artifacts to archive directory
- [ ] Only runs for cycle-type PRs

### Task 3.5: E2E Validation

**Description**: Manual validation of the complete pipeline with a test merge.

**Acceptance Criteria**:
- [ ] Create test PR with conventional commits
- [ ] Merge to main
- [ ] Verify: semver computed correctly
- [ ] Verify: CHANGELOG finalized
- [ ] Verify: tag created
- [ ] Verify: (if cycle) GT regenerated, release created
- [ ] Verify: PR comment posted with summary

### Task 3.6: Constraint Registry Update

**File**: `.claude/data/constraints.json`

**Description**: Generate constraint blocks in CLAUDE.loa.md from the new C-MERGE constraints.

**Acceptance Criteria**:
- [ ] `@constraint-generated` blocks rendered in CLAUDE.loa.md
- [ ] Constraint hash matches registry
- [ ] All 5 C-MERGE constraints present

---

## Sprint Dependencies

```
Sprint 1 (Foundation) → Sprint 2 (Integration) → Sprint 3 (Enhancement)
```

Sprint 2 depends on Sprint 1 (orchestrator must exist before workflow references it).
Sprint 3 depends on Sprint 2 (ship skill needs workflow, RTFM needs orchestrator phases).

## Risk Mitigation

| Risk | Sprint | Mitigation |
|------|--------|------------|
| claude-code-action not available | 2 | Shell-only fallback in simple-release job |
| `ANTHROPIC_API_KEY` not set | 2-3 | full-pipeline job checks secret existence, skips gracefully |
| CHANGELOG format varies | 1 | Parser handles multiple header formats |
| No git tags exist yet | 1 | Fallback to CHANGELOG version |
| Concurrent merges | 2 | Concurrency group in workflow |
