# Sprint Plan: Bridgebuilder & RTFM Integration into Run Workflows

**PRD**: `grimoires/loa/prd-run-skill-integration-265.md`
**SDD**: `grimoires/loa/sdd-run-skill-integration-265.md`
**Issue**: [#265](https://github.com/0xHoneyJar/loa/issues/265)
**Date**: 2026-02-09
**Sprints**: 2
**Team**: 1 AI agent (Claude)

---

## Overview

Wire Bridgebuilder (automated PR review) and RTFM (doc testing) into the post-PR validation loop. The work divides naturally into two sprints: Sprint 1 implements the core shell scripts and orchestrator changes, Sprint 2 adds config, documentation, and integration testing.

**Dependencies**: PRD v1.1 (Flatline-hardened), SDD v1.1 (Flatline-hardened). Both Bridgebuilder and RTFM skills are functional as-is — no changes to either skill.

---

## Sprint 1: Core Implementation

**Goal**: Validate Bridgebuilder CLI contract, replace the placeholder audit with Bridgebuilder, create the RTFM doc-test script, and wire both into the post-PR orchestrator.

### Task 1.0: Preflight Spike — Validate Bridgebuilder CLI Contract (IMP-001, IMP-002, SKP-002)

**Description**: Time-boxed verification (30 min max) that Bridgebuilder's `entry.sh` supports the flags and output format assumed by Task 1.1. This is a **gate** — if the contract doesn't match, Task 1.1 must be redesigned before proceeding.

**Steps**:
1. Run `entry.sh --help` (or inspect source) to document actual CLI flags
2. Run Bridgebuilder locally against a known PR: `entry.sh --pr <number> --repo <owner/repo>`
3. Capture and document: exact CLI flags, exit codes, JSON output schema, auth requirements
4. Verify `gh` CLI is installed, authenticated, and has required scopes (`gh auth status`) (SKP-004)
5. Verify `gh pr view` works with `--json number,repository` fields
6. Create a contract test fixture: expected input → expected output mapping

**Acceptance Criteria**:
- [ ] Bridgebuilder `entry.sh` CLI flags documented: actual flags, not assumed
- [ ] Exit codes documented: map actual exit codes to SDD §3.1 mapping table
- [ ] JSON output schema captured: required fields for `RunSummary` identified
- [ ] Auth requirements documented: `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, any others
- [ ] `gh auth status` passes with required scopes for `gh pr view` and `gh pr diff`
- [ ] If contract differs from SDD assumptions, update Task 1.1 description before proceeding
- [ ] Pass/fail: If entry.sh cannot be invoked with `--pr`/`--repo`, HALT and redesign

**Estimated Effort**: Low (30 min time-boxed spike)
**Dependencies**: None (must complete BEFORE Task 1.1)
**Testing**: This IS the test.

---

### Task 1.1: Modify `post-pr-audit.sh` — Bridgebuilder Integration

**File**: `.claude/scripts/post-pr-audit.sh` (modify, ~200 lines target)
**SDD Reference**: §3.1

**Description**: Refactor `post-pr-audit.sh` to:
1. Keep a minimal deterministic fast-pass (`run_fast_checks()`) for secrets, console.log, empty catch (per SKP-003)
2. Add `run_bridgebuilder_audit()` that invokes Bridgebuilder via `entry.sh --pr <number> --repo <owner/repo>`
3. Add canonical PR extraction via `gh pr view <url> --json` (per SKP-004)
4. Add strict Bridgebuilder output schema validation (per SKP-004) — invalid JSON = error
5. Add `min_severity` threshold filtering from config
6. Add environment-aware `resolve_failure_policy()` — CI defaults to `fail_closed`, local to `fail_open` (per SKP-001)
7. Add `handle_phase_error()` that always creates `.run/post-pr-degraded.json` marker
8. Add `resolve_audit_provider()` — supports `bridgebuilder` and `skip` providers
9. Write structured results to `.run/post-pr-audit-results.json` (per IMP-003)

**Acceptance Criteria**:
- [ ] `run_fast_checks()` runs deterministic regex checks (secrets, console.log, empty catch) before Bridgebuilder
- [ ] `run_bridgebuilder_audit()` invokes `entry.sh --pr <number> --repo <owner/repo>`
- [ ] PR number/repo extracted via `gh pr view <url> --json number,repository` (not URL parsing)
- [ ] `gh pr view` exit code validated; failure triggers `failure_policy` path
- [ ] Bridgebuilder JSON output validated for required fields (`results`, `status`)
- [ ] `min_severity` config applied: only findings at or above threshold count toward CHANGES_REQUIRED
- [ ] Exit codes: 0 (APPROVED), 1 (CHANGES_REQUIRED), 2 (ESCALATED via fail_closed)
- [ ] `failure_policy` resolves: CI/GITHUB_ACTIONS/CLAWDBOT → `fail_closed`; local → `fail_open`; config overrides both
- [ ] `.run/post-pr-degraded.json` created on ANY error (never silent approval)
- [ ] `.run/post-pr-audit-results.json` written with schema from SDD §3.1
- [ ] Provider config: `bridgebuilder` invokes Bridgebuilder, `skip` exits 0 immediately
- [ ] Timeout enforced (120s default, configurable)
- [ ] Existing `finding_identity()` and `retry_with_backoff()` utilities preserved and reused

**Required Fields** (from SDD §3.1 Results Schema):
- `post-pr-audit-results.json`: `tool`, `version`, `pr_number`, `repo`, `status`, `findings`, `review_posted`, `error_message`, `duration_ms`, `timestamp`
- `post-pr-degraded.json`: `phase`, `reason`, `policy`, `timestamp`

**`gh` Prerequisites** (SKP-004): Script MUST verify `gh` is installed and authenticated before any `gh` calls. On failure, trigger `failure_policy` path (not silent skip).

**Failure Policy Precedence** (SKP-003): Hard default → environment default (CI=fail_closed, local=fail_open) → `.loa.config.yaml` override → CLI flag override. Config example must document this precedence order.

**Estimated Effort**: Medium-high (largest task — refactoring 514-line script)
**Dependencies**: Task 1.0 (CLI contract must be validated first)
**Testing**: Manual invocation with `--pr-url` pointing to an existing PR. Verify JSON output schema.

---

### Task 1.2: Create `post-pr-doc-test.sh` — RTFM Manifest Generator

**File**: `.claude/scripts/post-pr-doc-test.sh` (new, ~150 lines)
**SDD Reference**: §3.2

**Description**: Create a new shell script that:
1. Parses `--pr-url` argument
2. Extracts PR number via `gh pr view` (canonical, SKP-004)
3. Gets changed files via `gh pr diff $number --name-only` with exit code check (IMP-009)
4. Filters to `*.md` files
5. Applies exclude patterns from config (or defaults: `grimoires/loa/a2a/**`, `CHANGELOG.md`, etc.)
6. If 0 docs remain, exits 0 (skip)
7. Caps at `max_docs` (default 5, IMP-004)
8. Generates `run_id` (UUID) for correlation (IMP-001, SKP-002)
9. Writes `.run/rtfm-manifest.json` with `run_id`, `status: "pending"`, docs list, timeouts, failure_policy
10. Exits 0 — the calling agent handles RTFM invocation

**Acceptance Criteria**:
- [ ] Script is executable (`chmod +x`)
- [ ] Parses `--pr-url <url>` argument
- [ ] Uses `gh pr view <url> --json` for canonical PR extraction (not URL parsing)
- [ ] `gh pr diff` exit code explicitly checked; failure triggers `failure_policy` path
- [ ] Filters to `*.md` files only
- [ ] Applies exclude patterns from `post_pr_validation.phases.doc_test.exclude_patterns[]` config
- [ ] Default excludes applied when config missing: `grimoires/loa/a2a/**`, `CHANGELOG.md`, `**/reviewer.md`, `**/engineer-feedback.md`, `**/auditor-sprint-feedback.md`
- [ ] Caps doc list at `max_docs` (default 5)
- [ ] Exits 0 with no manifest when 0 docs remain after filtering
- [ ] Generates unique `run_id` for manifest/results correlation
- [ ] Writes `.run/rtfm-manifest.json` matching SDD §3.2 schema
- [ ] Handles `doc_test.enabled: false` config (exit 0 immediately)
- [ ] `gh` presence and auth verified before `gh pr diff` call (SKP-004)
- [ ] On `gh` failure: trigger `failure_policy` path with descriptive error

**Required Fields** (from SDD §3.2 Manifest Schema):
- `rtfm-manifest.json`: `run_id`, `status`, `pr_number`, `docs`, `excluded`, `max_docs`, `timeout_per_doc`, `timeout_total`, `failure_policy`, `timestamp`

**CI Limitation** (IMP-004, SKP-001): This script only produces a manifest — it does NOT invoke RTFM. In CI environments where no Claude Code agent is running, the manifest will go unconsumed. This is an **accepted limitation**: the orchestrator's 10s deadline (Task 1.3) will detect the missing results and apply `failure_policy`. DOC_TEST in CI is informational only (degraded marker) until a CI-native RTFM consumer is built (out of scope for #265).

**Estimated Effort**: Medium (new script, well-defined contract)
**Dependencies**: Task 1.0 (for `gh` auth verification pattern)
**Testing**: Run against a PR with mixed `.md` and non-`.md` changes. Verify manifest JSON.

---

### Task 1.3: Modify `post-pr-orchestrator.sh` — Add DOC_TEST Phase

**File**: `.claude/scripts/post-pr-orchestrator.sh` (modify, ~40 lines added)
**SDD Reference**: §3.3

**Description**: Wire the DOC_TEST phase into the orchestrator state machine:
1. Add `STATE_DOC_TEST="DOC_TEST"` constant
2. Add `DOC_TEST_SCRIPT="${SCRIPT_DIR}/post-pr-doc-test.sh"` reference
3. Add `TIMEOUT_DOC_TEST="${TIMEOUT_DOC_TEST:-600}"` timeout
4. Add `--skip-doc-test` CLI option
5. Add `phase_doc_test()` handler between `phase_post_pr_audit()`/`phase_fix_audit()` and `phase_context_clear()`
6. Update state machine transition: `FIX_AUDIT → DOC_TEST → CONTEXT_CLEAR`
7. Add `surface_degraded_state()` — after all phases, check `.run/post-pr-degraded.json` and post PR comment if present (per SKP-001)
8. Handle CI/headless mode: if `post-pr-doc-test-results.json` doesn't appear within 10s after manifest written, mark DOC_TEST as skipped with degraded marker (per IMP-003)

**Acceptance Criteria**:
- [ ] `STATE_DOC_TEST` constant defined
- [ ] `phase_doc_test()` function implemented per SDD §3.3
- [ ] DOC_TEST phase executes between FIX_AUDIT and CONTEXT_CLEAR
- [ ] `--skip-doc-test` flag skips the phase
- [ ] `doc_test.enabled: false` config skips the phase
- [ ] Phase handles exit codes: 0 (pass), 1 (blocking gaps — log and continue), 124 (timeout — skip), other (skip)
- [ ] No fix loop for DOC_TEST (design decision D-3)
- [ ] `surface_degraded_state()` checks for `.run/post-pr-degraded.json` after all phases
- [ ] Degraded state surfaced as PR comment: "Quality gate degraded: {phase} was skipped ({reason})"
- [ ] CI/headless fallback: 10s deadline for results file (per IMP-003)

**Estimated Effort**: Medium (modifying existing state machine — need to be precise)
**Dependencies**: Task 1.2 (DOC_TEST_SCRIPT must exist)
**Testing**: Run orchestrator in dry-run mode. Verify state transitions.

---

## Sprint 2: Config, Documentation, and Integration Testing

**Goal**: Add configuration, update SKILL.md docs, write integration tests, and verify end-to-end.

### Task 2.1: Update `.loa.config.yaml.example` — New Config Sections

**File**: `.loa.config.yaml.example` (modify, ~25 lines added)
**SDD Reference**: §3.4

**Description**: Add new config sections under `post_pr_validation.phases`:
1. Expand `audit` section: add `provider`, `timeout_seconds`, `failure_policy`, `min_severity`
2. Add `doc_test` section: `enabled`, `max_docs`, `timeout_per_doc`, `timeout_total`, `failure_policy`, `exclude_patterns`
3. Add inline comments explaining each option

**Acceptance Criteria**:
- [ ] `post_pr_validation.phases.audit.provider` added with `bridgebuilder` default
- [ ] `post_pr_validation.phases.audit.failure_policy` added with `fail_open` default
- [ ] `post_pr_validation.phases.audit.timeout_seconds` added (120)
- [ ] `post_pr_validation.phases.audit.min_severity` added (`medium`)
- [ ] `post_pr_validation.phases.doc_test` section added with all fields from SDD §3.4
- [ ] `exclude_patterns` includes all 5 default patterns
- [ ] Comments explain `fail_open` vs `fail_closed` and CI recommendation
- [ ] Existing config structure preserved (no breaking changes)

**Estimated Effort**: Low
**Dependencies**: None
**Testing**: `yq` can parse the example config without errors.

---

### Task 2.2: Update `run-mode/SKILL.md` — Document RTFM Manifest Handling

**File**: `.claude/skills/run-mode/SKILL.md` (modify, ~30 lines added)
**SDD Reference**: §3.2 Agent-Side Contract (IMP-010)

**Description**: Add documentation for the agent-side RTFM manifest contract:
1. After DOC_TEST phase, check for `.run/rtfm-manifest.json`
2. If present: validate schema, invoke `/rtfm` for each doc, write results with matching `run_id`
3. Cleanup manifest after processing
4. Document the full agent-side contract table from SDD §3.2

**Acceptance Criteria**:
- [ ] RTFM manifest detection documented in run-mode SKILL.md
- [ ] Agent-side contract table included (detection, validation, execution, timeouts, partial failure, results, cleanup)
- [ ] Example manifest JSON shown
- [ ] Per-doc timeout and total timeout honored
- [ ] Partial failure behavior documented (continue to next doc on error)
- [ ] Results schema documented with `run_id` correlation

**Estimated Effort**: Low
**Dependencies**: Task 1.2 (manifest schema must be finalized)
**Testing**: Manual review that SKILL.md accurately reflects SDD §3.2.

---

### Task 2.3: Integration Test — End-to-End Post-PR Validation

**Description**: Verify the full post-PR validation loop works end-to-end:
1. Create a test PR (or use an existing one) with both code and `.md` changes
2. Run `post-pr-orchestrator.sh --pr-url <test-pr>` and verify:
   - POST_PR_AUDIT: fast-pass runs, then Bridgebuilder invokes (or skips if API key missing)
   - DOC_TEST: manifest generated for changed `.md` files
   - Degraded marker created if Bridgebuilder/RTFM unavailable (fail_open)
   - State transitions follow: POST_PR_AUDIT → FIX_AUDIT → DOC_TEST → CONTEXT_CLEAR → ...
3. Test config toggles:
   - `audit.provider: skip` → POST_PR_AUDIT exits 0 immediately
   - `doc_test.enabled: false` → DOC_TEST exits 0 immediately
   - `audit.failure_policy: fail_closed` → blocks on Bridgebuilder error

**Acceptance Criteria**:
- [ ] Orchestrator completes all phases without error
- [ ] POST_PR_AUDIT writes `.run/post-pr-audit-results.json` with valid schema
- [ ] DOC_TEST writes `.run/rtfm-manifest.json` when `.md` files changed
- [ ] DOC_TEST skips when no `.md` files changed
- [ ] Exclude patterns correctly filter out a2a artifacts and CHANGELOG.md
- [ ] `--skip-doc-test` flag works
- [ ] `provider: skip` config works for audit phase
- [ ] `failure_policy` correctly differentiates CI vs local defaults
- [ ] `.run/post-pr-degraded.json` created on tool errors
- [ ] Degraded state surfaced in log output

**Estimated Effort**: Medium (E2E testing requires careful setup)
**Dependencies**: Tasks 1.1, 1.2, 1.3 (all Sprint 1 tasks)
**Testing**: This IS the test task.

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Bridgebuilder `entry.sh` doesn't support `--pr`/`--repo` flags | HIGH | **Task 1.0**: preflight spike validates contract before implementation (SKP-002) |
| `post-pr-orchestrator.sh` state machine is complex (684 lines) | MEDIUM | Minimal changes — only add DOC_TEST phase, don't refactor existing logic |
| Regex fast-pass removal could miss patterns Bridgebuilder handles | LOW | D-1 revised: keep fast-pass, don't remove it |
| RTFM manifest has no agent consumer in CI | MEDIUM | IMP-003/SKP-001: 10s deadline fallback + degraded marker; CI limitation accepted and documented |
| `gh` CLI not authenticated or missing in CI | MEDIUM | SKP-004: verify `gh auth status` in preflight + per-script auth checks |
| Config failure_policy defaults mismatch example vs code | MEDIUM | SKP-003: single precedence order documented; example config shows CI-recommended settings |

---

## Success Criteria

| Criterion | Measurement |
|-----------|-------------|
| Bridgebuilder runs on PRs from `/run sprint-plan` | Manual test: run orchestrator, verify audit results JSON |
| RTFM manifest generated for changed `.md` files | Manual test: run doc-test script, verify manifest JSON |
| Config toggles work (provider, enabled, failure_policy) | Integration test: verify each toggle |
| No regressions in existing post-PR phases | All existing phases still complete normally |
| Degraded state always surfaced (never silent approval) | Verify `.run/post-pr-degraded.json` on error paths |
| CI/headless DOC_TEST degrades gracefully | Test with no agent: verify degraded marker created within 10s |
| `gh` auth failures handled cleanly | Remove `GITHUB_TOKEN`, verify `failure_policy` path triggered |

---

## Flatline Sprint Review Log

**Review Date**: 2026-02-09
**Agreement**: 90%
**Findings**: 3 HIGH_CONSENSUS + 1 DISPUTED (accepted) + 4 BLOCKERS (accepted)

### HIGH_CONSENSUS Integrated

| ID | Finding | Score | Integration |
|----|---------|-------|-------------|
| IMP-002 | Add gated preflight spike to verify BB CLI contract | 855 | Added Task 1.0 as gate before Task 1.1 |
| IMP-003 | Include required-fields tables + SDD schema links | 765 | Added Required Fields sections to Tasks 1.1, 1.2 |
| IMP-004 | Declare CI limitation for DOC_TEST explicitly | 815 | Added CI Limitation note to Task 1.2; accepted limitation documented |

### DISPUTED Accepted

| ID | Finding | GPT | Opus | Integration |
|----|---------|-----|------|-------------|
| IMP-001 | Document entry.sh flags/output/exit codes as preflight | 910 | 520 | Merged into Task 1.0 (combined with IMP-002/SKP-002) |

### BLOCKERS Accepted

| ID | Concern | Score | Integration |
|----|---------|-------|-------------|
| SKP-001 | CI RTFM execution model undefined/fragile | 930 | CI limitation accepted + documented; 10s deadline + degraded marker |
| SKP-002 | BB CLI contract not validated; may block sprint | 900 | Task 1.0 preflight spike is a gate — HALT if contract doesn't match |
| SKP-003 | Failure policy defaults inconsistent | 760 | Precedence order documented in Task 1.1; config example to show CI settings |
| SKP-004 | Over-reliance on `gh` without auth/availability checks | 740 | `gh` prereqs added to Tasks 1.0, 1.1, 1.2; `gh auth status` verification |
