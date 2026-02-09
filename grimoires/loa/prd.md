# PRD: Bridgebuilder & RTFM Integration into Run Workflows

**Issue**: [#265](https://github.com/0xHoneyJar/loa/issues/265)
**Date**: 2026-02-09
**Status**: Draft v1.1 (Flatline-hardened)
**Author**: Claude (AI agent)

---

## 1. Problem Statement

Bridgebuilder (automated PR review) and RTFM (documentation usability testing) are powerful quality skills that exist as standalone, manually-invoked tools. Users running convenience workflows (`/run sprint-plan`, `/simstim`, `/autonomous`) never benefit from these skills automatically. The post-PR validation loop already has a placeholder audit phase (`post-pr-audit.sh`) that always returns APPROVED — this is a missed opportunity for automated quality enforcement.

**Impact**: Users who don't know about `/bridgebuilder` or `/rtfm` miss automated PR review and doc testing entirely. Users who do know must invoke them manually after every sprint cycle.

---

## 2. Goals & Success Metrics

### Goals

1. Wire Bridgebuilder into the post-PR validation audit phase so every `/run` and `/simstim` PR gets automated code review
2. Add a documentation testing phase to post-PR validation so changed `.md` files are tested via RTFM
3. Both integrations on by default, configurable via `.loa.config.yaml`

### Success Metrics

| Metric | Target |
|--------|--------|
| Bridgebuilder runs automatically on PRs created by `/run sprint-plan` | 100% (when enabled) |
| RTFM tests changed docs on PRs created by `/run sprint-plan` | 100% (when `.md` files changed and enabled) |
| No regressions in existing post-PR validation phases | 0 failures |
| Configurable opt-out via `.loa.config.yaml` | Both skills independently toggleable |

---

## 3. User Stories

### US-1: Automatic PR Review
**As** a developer running `/run sprint-plan`,
**I want** Bridgebuilder to automatically review my PR after it's created,
**So that** I get code quality feedback without manually invoking `/bridgebuilder`.

### US-2: Automatic Doc Testing
**As** a developer whose sprint changes documentation,
**I want** RTFM to automatically test changed `.md` files,
**So that** documentation regressions are caught before merge.

### US-3: Opt-Out
**As** a developer who doesn't need automated review on a specific run,
**I want** to disable Bridgebuilder or RTFM via config,
**So that** I can skip them when time or cost is a concern.

---

## 4. Functional Requirements

### FR-1: Bridgebuilder Post-PR Audit Integration

**What**: Create `post-pr-audit.sh` that invokes Bridgebuilder on the PR created by `/run`.

**Behavior**:
1. Receives `--pr-url <url>` from `post-pr-orchestrator.sh`
2. Extracts PR number and repo canonically via `gh pr view <url> --json number,repository` (SKP-004: avoids fragile URL parsing; handles Enterprise, forks, query params)
3. Invokes Bridgebuilder via its entry script: `.claude/skills/bridgebuilder-review/resources/entry.sh --pr <number> --repo <owner/repo> --non-interactive` (SKP-002: stable CLI contract, no agent runtime dependency)
4. Parses machine-readable JSON results from `.run/post-pr-audit-results.json` (IMP-003: defined schema)
5. Maps results to orchestrator exit codes based on failure policy (SKP-001):
   - No critical/high findings → exit 0 (APPROVED)
   - Critical/high findings → exit 1 (CHANGES_REQUIRED)
   - On CHANGES_REQUIRED, orchestrator logs findings and continues to next phase (IMP-002: orchestrator does NOT auto-fix; it marks the PR and proceeds)
6. On Bridgebuilder error: consult `failure_policy` config (SKP-001):
   - `fail_open` (default for local): exit 0 + visible warning in PR comment + `.run/post-pr-degraded.json` marker
   - `fail_closed` (recommended for CI): exit 1 + block PR
7. Timeout: 120 seconds default, configurable (IMP-001)

**CLI Contract** (SKP-002):
```
# Invocation (non-interactive, machine-readable)
.claude/skills/bridgebuilder-review/resources/entry.sh \
  --pr <number> --repo <owner/repo> --non-interactive

# Exit codes:
#   0 = success (review posted or dry-run)
#   1 = findings posted (critical/high severity)
#   2 = error (API failure, auth, timeout)

# Output: JSON to stdout (RunSummary schema)
# Side effect: review posted to GitHub PR
```

**Results Schema** (IMP-003):
```json
{
  "tool": "bridgebuilder",
  "version": "2.1.0",
  "pr_number": 267,
  "repo": "owner/repo",
  "status": "findings" | "clean" | "error" | "skipped",
  "findings": { "critical": 0, "high": 1, "medium": 2, "low": 3 },
  "error_message": null,
  "timestamp": "2026-02-09T12:00:00Z"
}
```

**Config**:
```yaml
post_pr_validation:
  phases:
    audit:
      enabled: true            # Existing — controls entire audit phase
      provider: bridgebuilder  # NEW — "bridgebuilder" | "skip"
      timeout_seconds: 120     # IMP-001
      failure_policy: fail_open # SKP-001 — "fail_open" | "fail_closed"
```

**Acceptance Criteria**:
- [ ] `post-pr-audit.sh` exists and is executable
- [ ] Uses `gh pr view <url> --json` for canonical PR/repo extraction (SKP-004)
- [ ] Validates `gh pr view` exit code; propagates errors explicitly (IMP-009)
- [ ] Invokes Bridgebuilder via `entry.sh --non-interactive` (SKP-002)
- [ ] Parses JSON results schema (IMP-003), not log output
- [ ] Maps findings to orchestrator exit codes (0=pass, 1=changes)
- [ ] On CHANGES_REQUIRED, orchestrator logs findings and marks PR (IMP-002)
- [ ] Respects `failure_policy`: fail_open logs warning + degraded marker; fail_closed blocks (SKP-001)
- [ ] Creates `.run/post-pr-degraded.json` when phase is skipped/failed-open (SKP-001)
- [ ] Timeout enforced via config (IMP-001)
- [ ] Respects `post_pr_validation.phases.audit.provider` config
- [ ] When provider is `skip`, returns exit 0 immediately

### FR-2: RTFM Post-PR Doc Test Phase

**What**: Add a `DOC_TEST` phase to `post-pr-orchestrator.sh` that runs RTFM on changed `.md` files.

**Behavior**:
1. Runs after `POST_PR_AUDIT` phase, before `CONTEXT_CLEAR`
2. Gets list of changed `.md` files via `gh pr diff <number> --name-only` with explicit exit code check (IMP-009: `gh pr diff` failure must not be swallowed — if it fails, log error and exit based on `failure_policy`)
3. Filters to relevant docs (excludes `grimoires/loa/a2a/`, `CHANGELOG.md`, generated files)
4. If no relevant `.md` files changed → skip phase (exit 0)
5. Executes RTFM sequentially, one doc at a time (IMP-004: sequential to avoid rate limits and keep cost predictable; max 5 docs per run to cap latency)
6. Parses RTFM report JSON for gap severities (IMP-003: defined schema, not log scraping)
7. Aggregates results:
   - Any BLOCKING gaps → exit 1 (DOC_TEST_FAILED)
   - Only DEGRADED/MINOR → exit 0 (pass with warnings logged)
   - RTFM error: consult `failure_policy` (SKP-001)
8. Writes results to `.run/post-pr-doc-test-results.json` (IMP-003)
9. Timeout: 180 seconds per doc, 600 seconds total (IMP-001)

**Phase Ordering** (updated):
```
POST_PR_AUDIT → DOC_TEST → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR
```

**Doc Test Results Schema** (IMP-003):
```json
{
  "tool": "rtfm",
  "version": "1.0.0",
  "docs_tested": ["README.md", "INSTALLATION.md"],
  "docs_skipped": ["grimoires/loa/a2a/sprint-1/reviewer.md"],
  "status": "pass" | "fail" | "error" | "skipped",
  "gaps": { "blocking": 0, "degraded": 1, "minor": 2 },
  "error_message": null,
  "timestamp": "2026-02-09T12:00:00Z"
}
```

**Config**:
```yaml
post_pr_validation:
  phases:
    doc_test:
      enabled: true            # NEW — controls doc test phase
      max_docs: 5              # IMP-004 — cap to limit latency/cost
      timeout_per_doc: 180     # IMP-001 — seconds per doc
      timeout_total: 600       # IMP-001 — total phase timeout
      failure_policy: fail_open # SKP-001 — "fail_open" | "fail_closed"
      exclude_patterns:        # Docs to skip
        - "grimoires/loa/a2a/**"
        - "CHANGELOG.md"
        - "**/reviewer.md"
        - "**/engineer-feedback.md"
        - "**/auditor-sprint-feedback.md"
```

**Acceptance Criteria**:
- [ ] `DOC_TEST` phase added to `post-pr-orchestrator.sh` state machine
- [ ] Uses `gh pr diff` with explicit exit code check (IMP-009)
- [ ] Filters out excluded patterns (a2a artifacts, CHANGELOG)
- [ ] Skips gracefully when no relevant `.md` files changed
- [ ] Executes RTFM sequentially, max 5 docs (IMP-004)
- [ ] Parses RTFM JSON results (IMP-003), not log output
- [ ] Aggregates gap severities correctly (BLOCKING=fail, others=pass)
- [ ] Respects `failure_policy`: fail_open vs fail_closed (SKP-001)
- [ ] Creates `.run/post-pr-degraded.json` when phase skipped/failed-open (SKP-001)
- [ ] Enforces per-doc and total timeouts (IMP-001)
- [ ] Writes structured results to `.run/post-pr-doc-test-results.json` (IMP-003)
- [ ] Respects `post_pr_validation.phases.doc_test.enabled` config

### FR-3: Config Defaults Update

**What**: Update `.loa.config.yaml.example` with new config sections and ensure defaults are "on".

**Acceptance Criteria**:
- [ ] `post_pr_validation.phases.audit.provider: bridgebuilder` documented in example
- [ ] `post_pr_validation.phases.doc_test` section added to example config
- [ ] Both enabled by default
- [ ] Existing config files without new keys get sensible defaults (on)

---

## 5. Non-Functional Requirements

### NFR-1: Configurable Failure Policy (SKP-001)
Each phase has a `failure_policy` setting:
- **`fail_open`** (default for local/interactive): On tool error, log visible warning, create `.run/post-pr-degraded.json` marker, continue workflow. The degraded marker includes which phase was skipped and why — this is surfaced in the PR comment so reviewers know quality gates were not fully enforced.
- **`fail_closed`** (recommended for CI/autonomous): On tool error, block with exit 1. Use for environments where silent pass-through is unacceptable.

Both modes MUST produce a visible artifact (degraded marker or PR comment) when a phase is skipped — silent approval is never acceptable.

### NFR-2: Cost Awareness
Bridgebuilder uses one Anthropic API call per PR. RTFM spawns one subagent per doc file (max 5). Both should log estimated cost when invoked.

### NFR-3: Idempotency
Re-running post-PR validation should not duplicate Bridgebuilder reviews on GitHub. Bridgebuilder already checks for existing review markers.

### NFR-4: No New Dependencies
Both skills already exist. Integration should wire existing skills, not create new ones.

### NFR-5: Data Handling & Secrets Safety (SKP-008)
- Bridgebuilder sends PR diffs to Anthropic API; RTFM sends doc content to Claude subagents. Both inherit the existing secret scanning from Bridgebuilder's sanitizer (redacts API keys, credentials, private keys before LLM submission).
- `post-pr-audit.sh` MUST NOT log full API responses to disk — only structured results JSON.
- The `--non-interactive` flag ensures no sensitive content is echoed to stdout beyond the results schema.
- Repos with `bridgebuilder.enabled: false` in config are never sent to external APIs.

### NFR-6: Timeout Enforcement (IMP-001)
Every external call has a concrete timeout:
- Bridgebuilder: 120s default (configurable)
- RTFM per-doc: 180s default (configurable)
- RTFM total phase: 600s default (configurable)
- `gh pr view`/`gh pr diff`: 30s (non-configurable, hard limit)

Timeouts trigger the `failure_policy` path (fail_open or fail_closed).

---

## 6. Scope

### In Scope
- `post-pr-audit.sh` script creation (Bridgebuilder integration)
- `DOC_TEST` phase in `post-pr-orchestrator.sh` (RTFM integration)
- Config additions to `.loa.config.yaml.example`
- SKILL.md documentation updates for run-mode and post-PR validation

### Out of Scope
- Golden path `/review` or `/ship` integration (future)
- Bridgebuilder or RTFM code changes (use as-is)
- Simstim-specific phase additions (inherits from post-PR validation)
- Autonomous-specific phase additions (inherits from post-PR validation)

---

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Bridgebuilder requires `ANTHROPIC_API_KEY` which may not be set | Medium | Medium | Check for key in `post-pr-audit.sh`, skip with warning if missing |
| RTFM subagent adds latency to post-PR validation | Low | Low | Doc test runs on small set of changed files only |
| Post-PR orchestrator script may need refactoring for new phase | Low | Medium | DOC_TEST follows existing phase pattern — minimal changes |
| Bridgebuilder review duplication on retry | Low | Low | Bridgebuilder already has idempotency via review markers |

### Dependencies
- Bridgebuilder skill (`bridgebuilder-review/`) must be functional
- RTFM skill (`rtfm-testing/`) must be functional
- `post-pr-orchestrator.sh` must support phase insertion
- `gh` CLI must be authenticated (for PR diff extraction)

---

## 8. Architecture Notes

### Integration Point: Post-PR Orchestrator

The `post-pr-orchestrator.sh` already has a phase-based state machine:

```
Current:  POST_PR_AUDIT → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR
Proposed: POST_PR_AUDIT → DOC_TEST → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR
```

`POST_PR_AUDIT` currently calls a placeholder script. FR-1 replaces it with a real Bridgebuilder invocation. FR-2 adds `DOC_TEST` as a new phase in the existing state machine.

### Inheritance Chain

All workflows that use post-PR validation benefit automatically:
- `/run sprint-N` → calls `post-pr-orchestrator.sh` → gets Bridgebuilder + RTFM
- `/run sprint-plan` → calls `post-pr-orchestrator.sh` → gets Bridgebuilder + RTFM
- `/simstim` Phase 7.5 → calls `post-pr-orchestrator.sh` → gets Bridgebuilder + RTFM
- `/autonomous` Phase 5.5 → calls `post-pr-orchestrator.sh` → gets Bridgebuilder + RTFM

No per-workflow wiring needed — one integration point serves all workflows.

---

## 9. Flatline Review Log

**Review Date**: 2026-02-09
**Agreement**: 100%
**Findings**: 5 HIGH_CONSENSUS (auto-integrated) + 5 BLOCKERS (accepted)

### HIGH_CONSENSUS Integrated

| ID | Finding | Score | Integration |
|----|---------|-------|-------------|
| IMP-001 | Add concrete timeout thresholds | 835 | Added to FR-1/FR-2 configs, NFR-6 |
| IMP-002 | Define orchestrator behavior on CHANGES_REQUIRED | 810 | Added to FR-1 behavior step 5 |
| IMP-003 | Define JSON schemas for results files | 890 | Added schemas to FR-1 and FR-2 |
| IMP-004 | Specify RTFM sequential execution with cap | 770 | FR-2 step 5: sequential, max 5 docs |
| IMP-009 | Add error handling for `gh pr diff` pipeline | 770 | FR-2 step 2: explicit exit code check |

### BLOCKERS Accepted

| ID | Concern | Severity | Integration |
|----|---------|----------|-------------|
| SKP-001 | Fail-open makes gates non-enforcing | 930 | NFR-1: configurable fail_open/fail_closed with degraded marker |
| SKP-002 | Unspecified CLI contract for skill invocation | 900 | FR-1: documented entry.sh CLI contract with exit codes |
| SKP-003 | Result mapping underspecified | 760 | FR-1/FR-2: JSON schemas with severity enums |
| SKP-004 | PR URL parsing fragile | 720 | FR-1: use `gh pr view <url> --json` for canonical extraction |
| SKP-008 | Security/privacy risks for external API | 880 | NFR-5: data handling, secrets safety, sanitizer inheritance |
