# SDD: Bridgebuilder & RTFM Integration into Run Workflows

**PRD**: `grimoires/loa/prd-run-skill-integration-265.md`
**Issue**: [#265](https://github.com/0xHoneyJar/loa/issues/265)
**Date**: 2026-02-09

---

## 1. Executive Summary

Wire Bridgebuilder (automated PR review) and RTFM (documentation usability testing) into the post-PR validation loop. Two changes to existing infrastructure:

1. **Modify** `post-pr-audit.sh` to invoke Bridgebuilder instead of regex-based checks
2. **Add** `DOC_TEST` phase to `post-pr-orchestrator.sh` that invokes RTFM on changed docs

Both changes operate within the existing post-PR validation state machine. All workflows (`/run`, `/simstim`, `/autonomous`) inherit automatically.

---

## 2. System Architecture

### Current State

```
post-pr-orchestrator.sh
  ├── POST_PR_AUDIT → post-pr-audit.sh (regex-based grep checks)
  ├── CONTEXT_CLEAR → post-pr-context-clear.sh
  ├── E2E_TESTING   → post-pr-e2e.sh
  └── FLATLINE_PR   → flatline-orchestrator.sh
```

### Target State

```
post-pr-orchestrator.sh
  ├── POST_PR_AUDIT → post-pr-audit.sh (Bridgebuilder invocation)
  ├── DOC_TEST      → post-pr-doc-test.sh (RTFM invocation)  ← NEW
  ├── CONTEXT_CLEAR → post-pr-context-clear.sh
  ├── E2E_TESTING   → post-pr-e2e.sh
  └── FLATLINE_PR   → flatline-orchestrator.sh
```

### Inheritance Chain

```
/run sprint-N ──────────┐
/run sprint-plan ───────┤
/simstim Phase 7.5 ─────┤──→ post-pr-orchestrator.sh ──→ [all phases]
/autonomous Phase 5.5 ──┘
```

---

## 3. Component Design

### 3.1 post-pr-audit.sh (Modified — FR-1)

**Current**: 514 lines of regex-based grep checks (hardcoded secrets, console.log, TODO, empty catch).

**Change**: Replace `run_audit()` function body with Bridgebuilder invocation. Preserve existing scaffolding (argument parsing, retry logic, finding identity, report generation).

#### Design Decision: Replace vs Wrap (revised per SKP-003)

**Option A: Replace run_audit() entirely** — Bridgebuilder subsumes all regex checks and adds LLM-powered analysis.
**Option B: Run both** — regex checks as fast-pass, Bridgebuilder as deep analysis.
**Decision: Option B (revised).** Per SKP-003, the existing regex checks for secrets, `console.log`, empty catch blocks are deterministic and fast. Bridgebuilder is probabilistic (LLM-driven) and may miss obvious patterns. Keep a minimal deterministic fast-pass (`run_fast_checks()`) that runs before Bridgebuilder invocation — if fast-pass finds critical issues (hardcoded secrets), exit immediately without incurring API cost. Bridgebuilder then provides deep LLM-powered analysis on top.

```bash
run_audit() {
  # Phase 1: Deterministic fast-pass (kept from existing regex checks)
  # Checks: hardcoded secrets, API keys, console.log in production, empty catch
  run_fast_checks "$pr_url" || return $?

  # Phase 2: LLM-powered deep analysis via Bridgebuilder
  run_bridgebuilder_audit "$pr_url" || return $?
}
```

The existing `finding_identity()` and `retry_with_backoff()` utilities are reused for Bridgebuilder error handling.

#### Invocation Contract

```bash
# 1. Canonical PR extraction (SKP-004)
pr_json=$(gh pr view "$pr_url" --json number,headRefName,baseRefName,repository 2>/dev/null)
pr_number=$(echo "$pr_json" | jq -r '.number')
repo_name=$(echo "$pr_json" | jq -r '.repository.nameWithOwner')

# 2. Bridgebuilder invocation (SKP-002)
bb_output=$(.claude/skills/bridgebuilder-review/resources/entry.sh \
  --pr "$pr_number" \
  --repo "$repo_name" \
  2>&1) || bb_exit=$?

# 3. Results mapping
# entry.sh → node dist/main.js → JSON RunSummary to stdout
# Parse RunSummary.results[].error for severity classification
```

#### Exit Code Mapping (revised per SKP-004)

Bridgebuilder outputs a JSON `RunSummary` to stdout. The audit script MUST validate the JSON schema before processing — invalid or missing JSON is treated as an error and routed through `failure_policy`.

**Schema validation**:
```bash
validate_bb_output() {
  local output="$1"
  # Required fields: results (array), status (string)
  if ! echo "$output" | jq -e '.results and .status' >/dev/null 2>&1; then
    handle_bb_error "Invalid Bridgebuilder output: missing required fields"
    return 1
  fi
}
```

**Severity classification** uses `min_severity` from config (default: `medium`). Only findings at or above the threshold count toward CHANGES_REQUIRED:

```bash
classify_findings() {
  local output="$1"
  local min_severity
  min_severity=$(yq '.post_pr_validation.phases.audit.min_severity // "medium"' \
    .loa.config.yaml 2>/dev/null || echo "medium")

  # Severity hierarchy: critical > high > medium > low
  local severity_levels='{"critical":4,"high":3,"medium":2,"low":1}'
  local min_level
  min_level=$(echo "$severity_levels" | jq -r --arg s "$min_severity" '.[$s] // 2')

  # Count findings at or above threshold
  local actionable
  actionable=$(echo "$output" | jq --argjson min "$min_level" \
    '[.results[] | select(.severity_level >= $min)] | length')

  echo "$actionable"
}
```

**Deterministic mapping table**:

| Bridgebuilder Output State | Audit Exit | Rationale |
|---------------------------|------------|-----------|
| Valid JSON, 0 actionable findings (above min_severity) | 0 (APPROVED) | Clean review posted |
| Valid JSON, ≥1 actionable findings (above min_severity) | 1 (CHANGES_REQUIRED) | Findings need addressing |
| Invalid JSON / missing required fields | Consult `failure_policy` | Schema violation = error |
| Node process exit code ≠ 0 | Consult `failure_policy` | Tool crash |
| Timeout (120s exceeded) | Consult `failure_policy` | Timeout = error |
| `ANTHROPIC_API_KEY` missing | Consult `failure_policy` | Env not configured |
| Empty stdout | Consult `failure_policy` | No output = error |

#### Failure Policy Implementation (revised per SKP-001)

**Environment-aware defaults**: CI environments default to `fail_closed`; local/interactive defaults to `fail_open`. Config can override both.

```bash
resolve_failure_policy() {
  local phase="${1:-audit}"

  # 1. Explicit config takes precedence
  local explicit
  explicit=$(yq ".post_pr_validation.phases.${phase}.failure_policy // \"\"" \
    .loa.config.yaml 2>/dev/null || echo "")

  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return
  fi

  # 2. Environment-aware default (SKP-001)
  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${CLAWDBOT_GATEWAY_TOKEN:-}" ]]; then
    echo "fail_closed"  # CI/autonomous: strict by default
  else
    echo "fail_open"    # Local/interactive: permissive by default
  fi
}

handle_phase_error() {
  local phase="$1"
  local error_msg="$2"
  local policy
  policy=$(resolve_failure_policy "$phase")

  # Always create degraded marker (NFR-1: silent approval never acceptable)
  jq -n --arg phase "$phase" --arg reason "$error_msg" \
    --arg policy "$policy" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{phase: $phase, reason: $reason, policy: $policy, timestamp: $ts}' \
    > .run/post-pr-degraded.json

  if [[ "$policy" == "fail_closed" ]]; then
    exit 2  # ESCALATED — blocks pipeline
  else
    exit 0  # fail_open — continue with warning
  fi
}
```

**Orchestrator-level degraded surfacing**: When `post-pr-degraded.json` exists after any phase, the orchestrator MUST surface it in the PR comment. This ensures reviewers see which quality gates were not fully enforced, regardless of fail_open/fail_closed policy.

```bash
# In post-pr-orchestrator.sh — after all phases complete:
surface_degraded_state() {
  if [[ -f .run/post-pr-degraded.json ]]; then
    local phase reason
    phase=$(jq -r '.phase' .run/post-pr-degraded.json)
    reason=$(jq -r '.reason' .run/post-pr-degraded.json)
    log_warning "Quality gate degraded: $phase — $reason"
    # Append degraded notice to PR comment body
    append_pr_comment "⚠️ **Quality gate degraded**: $phase was skipped ($reason)"
  fi
}
```

#### Results Schema (IMP-003)

Written to `.run/post-pr-audit-results.json`:

```json
{
  "tool": "bridgebuilder",
  "version": "2.1.0",
  "pr_number": 267,
  "repo": "0xHoneyJar/loa",
  "status": "findings|clean|error|skipped",
  "findings": { "critical": 0, "high": 1, "medium": 2, "low": 3 },
  "review_posted": true,
  "error_message": null,
  "duration_ms": 45000,
  "timestamp": "2026-02-09T12:00:00Z"
}
```

#### Provider Config

```bash
resolve_audit_provider() {
  local provider
  provider=$(yq '.post_pr_validation.phases.audit.provider // "bridgebuilder"' \
    .loa.config.yaml 2>/dev/null || echo "bridgebuilder")
  echo "$provider"
}

# In main():
case "$(resolve_audit_provider)" in
  bridgebuilder) run_bridgebuilder_audit "$pr_url" ;;
  skip)          log_info "Audit provider: skip"; exit 0 ;;
  *)             log_error "Unknown provider"; exit 3 ;;
esac
```

### 3.2 post-pr-doc-test.sh (New — FR-2)

**New script**: `~150 lines`. Follows the same pattern as `post-pr-audit.sh` and `post-pr-e2e.sh`.

#### Algorithm

```
1. Parse --pr-url argument
2. Extract PR number via gh pr view (canonical, SKP-004)
3. Get changed files: gh pr diff $number --name-only
4. Filter to *.md files
5. Apply exclude patterns from config
6. If 0 docs remain → exit 0 (skip)
7. Cap at max_docs (default 5, IMP-004)
8. For each doc (sequential, IMP-004):
   a. Check file exists on disk
   b. Invoke RTFM via Task tool pattern (see invocation below)
   c. Parse report for gap severities
   d. Accumulate results
   e. Check per-doc timeout (180s, IMP-001)
   f. Check total timeout (600s, IMP-001)
9. Aggregate: any BLOCKING → exit 1, else exit 0
10. Write results to .run/post-pr-doc-test-results.json
```

#### RTFM Invocation

RTFM is a skill, not a standalone CLI. In the shell context, we invoke it by writing the doc content to a temp file and using the RTFM tester pattern from `rtfm-testing/SKILL.md`:

```bash
# RTFM produces reports at grimoires/loa/a2a/rtfm/report-*.md
# We check for the latest report and parse its verdict
invoke_rtfm() {
  local doc_path="$1"
  local report_dir="grimoires/loa/a2a/rtfm"

  # Record pre-invocation report count
  local before_count
  before_count=$(ls "$report_dir"/report-*.md 2>/dev/null | wc -l)

  # RTFM is a skill — invoked via the agent (not direct CLI)
  # The orchestrator runs inside a Claude Code session, so we
  # write a marker file that the calling agent reads
  echo "$doc_path" > .run/rtfm-pending-doc.txt

  # Return pending — the calling agent (run-mode/simstim) will
  # invoke /rtfm and write results
  return 0
}
```

**Design Decision: Agent-mediated vs direct invocation**

RTFM is a pure skill (not a compiled binary). It spawns a Task subagent, which requires the Claude Code runtime. From a shell script, we cannot directly invoke it.

**Solution**: The `post-pr-doc-test.sh` script identifies which docs need testing and writes a manifest. The calling agent (run-mode SKILL.md or simstim SKILL.md) reads the manifest and invokes `/rtfm` for each doc, then writes results back. The shell script then reads the aggregated results.

```
post-pr-doc-test.sh (shell)
  ├── Identifies changed .md files
  ├── Filters and caps
  ├── Writes manifest: .run/rtfm-manifest.json (with run_id for correlation)
  └── Exits with code 0 (manifest written) or 2 (error)

Agent (run-mode/simstim) — AGENT-SIDE CONTRACT (IMP-010, SKP-002)
  ├── Detects .run/rtfm-manifest.json after doc-test script exits
  ├── Validates manifest schema (run_id, docs array, timeouts)
  ├── For each doc: invokes /rtfm <doc> (sequential, with per-doc timeout)
  ├── On per-doc failure: marks doc as "error" in results, continues to next
  ├── Writes .run/post-pr-doc-test-results.json (with matching run_id)
  └── Deletes .run/rtfm-manifest.json (cleanup)
```

#### Synchronization Contract (IMP-001, SKP-002)

The manifest/results handshake uses a **two-phase write pattern** with correlation IDs — not polling:

1. **Shell writes manifest** with `run_id` (UUID) and `status: "pending"`
2. **Shell exits** — control returns to the orchestrator's calling agent
3. **Agent reads manifest** — validates `run_id` and `status: "pending"`
4. **Agent executes RTFM** for each doc, writing intermediate progress to `.run/rtfm-progress.json`
5. **Agent writes results** with matching `run_id` and `status: "completed"|"error"`
6. **Agent deletes manifest** (consumed)

There is no polling or race condition because the shell script and agent execute sequentially within the same orchestrator invocation — the shell exits, the orchestrator agent reads the manifest, processes it, and then continues to the next phase.

**CI/headless mode (IMP-003)**: When no agent is present (e.g., CI pipeline running shell scripts directly), the manifest is written but no agent reads it. The orchestrator detects this by checking if `post-pr-doc-test-results.json` exists after a configurable deadline (default: 10s). If missing, the phase is marked as `skipped` with a degraded marker per `failure_policy`.

```bash
# In orchestrator — after doc-test script exits:
wait_for_results() {
  local deadline="${1:-10}"
  local run_id="$2"

  if [[ -f .run/post-pr-doc-test-results.json ]]; then
    local result_run_id
    result_run_id=$(jq -r '.run_id' .run/post-pr-doc-test-results.json)
    if [[ "$result_run_id" == "$run_id" ]]; then
      return 0  # Results found with matching correlation ID
    fi
  fi

  # No agent present — degrade gracefully
  return 1
}
```

#### Agent-Side Contract (IMP-010)

The calling agent (run-mode or simstim SKILL.md) MUST implement:

| Responsibility | Specification |
|---------------|---------------|
| **Detection** | Check for `.run/rtfm-manifest.json` after DOC_TEST shell script exits |
| **Validation** | Verify manifest has `run_id`, `docs` array, `timeout_per_doc`, `timeout_total` |
| **Execution** | Invoke `/rtfm <doc>` sequentially for each doc in `docs` array |
| **Per-doc timeout** | Honor `timeout_per_doc` (default 180s); on timeout, mark doc as `error` and continue |
| **Total timeout** | Honor `timeout_total` (default 600s); on expiry, stop processing remaining docs |
| **Partial failure** | Continue to next doc on failure; record per-doc status in results (IMP-004) |
| **Results** | Write `.run/post-pr-doc-test-results.json` with matching `run_id` |
| **Cleanup** | Delete `.run/rtfm-manifest.json` after writing results |
| **No manifest** | If manifest does not exist, skip DOC_TEST silently (no error) |

#### Manifest Schema (revised per IMP-001, SKP-002)

`.run/rtfm-manifest.json`:
```json
{
  "run_id": "rtfm-20260209-abc123",
  "status": "pending",
  "pr_number": 267,
  "docs": ["README.md", "INSTALLATION.md"],
  "excluded": ["grimoires/loa/a2a/sprint-1/reviewer.md"],
  "max_docs": 5,
  "timeout_per_doc": 180,
  "timeout_total": 600,
  "failure_policy": "fail_open",
  "timestamp": "2026-02-09T12:00:00Z"
}
```

#### Results Schema (revised per IMP-003, IMP-004)

`.run/post-pr-doc-test-results.json`:
```json
{
  "run_id": "rtfm-20260209-abc123",
  "tool": "rtfm",
  "version": "1.0.0",
  "pr_number": 267,
  "status": "pass|fail|error|skipped",
  "per_doc_results": [
    {
      "doc": "README.md",
      "status": "pass",
      "gaps": { "blocking": 0, "degraded": 1, "minor": 2 },
      "report": "grimoires/loa/a2a/rtfm/report-2026-02-09-readme.md",
      "duration_ms": 45000,
      "error": null
    },
    {
      "doc": "INSTALLATION.md",
      "status": "error",
      "gaps": null,
      "report": null,
      "duration_ms": 180000,
      "error": "Timeout after 180s"
    }
  ],
  "aggregate_gaps": { "blocking": 0, "degraded": 1, "minor": 2 },
  "docs_tested": ["README.md"],
  "docs_errored": ["INSTALLATION.md"],
  "docs_skipped_by_filter": ["grimoires/loa/a2a/sprint-1/reviewer.md"],
  "error_message": null,
  "duration_ms": 225000,
  "timestamp": "2026-02-09T12:00:00Z"
}
```

**Aggregate status rules** (IMP-004):
- `pass`: All docs tested, 0 blocking gaps
- `fail`: ≥1 doc has blocking gaps
- `error`: ≥1 doc errored AND 0 docs successfully tested (total failure)
- `pass` (with warnings): Some docs errored but ≥1 doc tested successfully (partial success — surfaced in PR comment)
```

#### Exclude Pattern Matching

```bash
matches_exclude() {
  local file="$1"
  local patterns
  patterns=$(yq '.post_pr_validation.phases.doc_test.exclude_patterns[]' \
    .loa.config.yaml 2>/dev/null || echo "")

  # Default excludes if config missing
  if [[ -z "$patterns" ]]; then
    patterns="grimoires/loa/a2a/**
CHANGELOG.md
**/reviewer.md
**/engineer-feedback.md
**/auditor-sprint-feedback.md"
  fi

  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # Use bash glob matching
    if [[ "$file" == $pattern ]]; then
      return 0
    fi
  done <<< "$patterns"

  return 1
}
```

### 3.3 post-pr-orchestrator.sh (Modified — FR-2)

#### Changes Required

1. **Add state constant**: `STATE_DOC_TEST="DOC_TEST"`
2. **Add phase handler**: `phase_doc_test()` between `phase_post_pr_audit()` and `phase_context_clear()`
3. **Add skip flag**: `--skip-doc-test` CLI option
4. **Update state machine**: Insert DOC_TEST between POST_PR_AUDIT and CONTEXT_CLEAR
5. **Add DOC_TEST script reference**: `DOC_TEST_SCRIPT="${SCRIPT_DIR}/post-pr-doc-test.sh"`
6. **Add timeout**: `TIMEOUT_DOC_TEST="${TIMEOUT_DOC_TEST:-600}"`

#### State Machine Update

```
Current flow:
  PR_CREATED → POST_PR_AUDIT → FIX_AUDIT → CONTEXT_CLEAR → ...

New flow:
  PR_CREATED → POST_PR_AUDIT → FIX_AUDIT → DOC_TEST → CONTEXT_CLEAR → ...
```

#### phase_doc_test() Design

```bash
phase_doc_test() {
  log_phase "DOC_TEST"

  # Check if phase is enabled
  local enabled
  enabled=$(yq '.post_pr_validation.phases.doc_test.enabled // true' \
    .loa.config.yaml 2>/dev/null || echo "true")

  if [[ "$enabled" != "true" ]]; then
    log_info "Doc test phase disabled, skipping"
    "$STATE_SCRIPT" update-phase doc_test skipped
    return 0
  fi

  "$STATE_SCRIPT" update-phase doc_test in_progress
  update_state "$STATE_DOC_TEST"

  local result=0
  if [[ -x "$DOC_TEST_SCRIPT" ]]; then
    run_with_timeout "$TIMEOUT_DOC_TEST" "$DOC_TEST_SCRIPT" --pr-url "$PR_URL" || result=$?
  else
    log_info "Doc test script not found, skipping"
    "$STATE_SCRIPT" update-phase doc_test skipped
    return 0
  fi

  case $result in
    0)
      log_success "Doc tests PASSED"
      "$STATE_SCRIPT" update-phase doc_test completed
      return 0
      ;;
    1)
      # BLOCKING gaps found — log and continue (no fix loop for docs)
      log_info "Doc test found blocking gaps"
      "$STATE_SCRIPT" update-phase doc_test completed
      # Don't halt — doc gaps are informational in post-PR context
      return 0
      ;;
    124)
      log_info "Doc test timed out, skipping"
      "$STATE_SCRIPT" update-phase doc_test skipped
      return 0
      ;;
    *)
      log_info "Doc test failed (exit: $result), skipping"
      "$STATE_SCRIPT" update-phase doc_test skipped
      return 0
      ;;
  esac
}
```

**Design Decision: No fix loop for DOC_TEST**

Unlike POST_PR_AUDIT and E2E_TESTING which have fix loops (iterate until findings resolved), DOC_TEST has no fix loop. Rationale: documentation gaps from RTFM are advisory — they tell you what's unclear, but the fix is human judgment (rewrite prose). Auto-fixing docs via LLM risks hallucination. The report is surfaced for human review.

### 3.4 Config Defaults (FR-3)

#### New Config Sections

Added to `.loa.config.yaml.example` under `post_pr_validation.phases`:

```yaml
    # Bridgebuilder-powered PR audit (v1.32.0)
    audit:
      enabled: true
      provider: bridgebuilder  # "bridgebuilder" | "skip"
      max_iterations: 5
      min_severity: "medium"
      timeout_seconds: 120
      failure_policy: fail_open  # "fail_open" | "fail_closed"

    # RTFM documentation usability testing (v1.32.0)
    doc_test:
      enabled: true
      max_docs: 5
      timeout_per_doc: 180
      timeout_total: 600
      failure_policy: fail_open  # "fail_open" | "fail_closed"
      exclude_patterns:
        - "grimoires/loa/a2a/**"
        - "CHANGELOG.md"
        - "**/reviewer.md"
        - "**/engineer-feedback.md"
        - "**/auditor-sprint-feedback.md"
```

#### Default Resolution

All config reads use `yq` with `// default_value` fallback. Missing keys resolve to "on" behavior:
- `provider` → `bridgebuilder`
- `enabled` → `true`
- `failure_policy` → `fail_open`

---

## 4. Data Architecture

### Ephemeral State Files (`.run/`)

| File | Written By | Read By | Lifecycle |
|------|-----------|---------|-----------|
| `post-pr-audit-results.json` | `post-pr-audit.sh` | orchestrator, PR comment | Cleaned on next run |
| `post-pr-doc-test-results.json` | agent (via RTFM) | orchestrator, PR comment | Cleaned on next run |
| `post-pr-degraded.json` | audit/doc-test scripts | PR comment generation | Cleaned on next run |
| `rtfm-manifest.json` | `post-pr-doc-test.sh` | agent (run-mode/simstim) | Cleaned after read |

---

## 5. Security Architecture (NFR-5)

### Data Flow

```
PR diff content → Bridgebuilder sanitizer → Anthropic API
Doc file content → RTFM Task subagent → Claude API (via agent runtime)
```

### Secrets Protection

1. **Bridgebuilder**: Already has `IOutputSanitizer` port that redacts credentials before LLM submission
2. **RTFM**: Operates on documentation files (`.md`), which should never contain secrets. If they do, the standard gitignore/pre-commit hooks catch them before PR.
3. **Shell scripts**: Never log full API responses. Only structured JSON results written to `.run/`.
4. **Environment**: `ANTHROPIC_API_KEY` checked before invocation; missing key triggers `failure_policy` path.

---

## 6. Files to Create/Modify

| File | Action | Size Estimate | Sprint |
|------|--------|--------------|--------|
| `.claude/scripts/post-pr-audit.sh` | **Modify** — replace `run_audit()` with Bridgebuilder invocation | ~200 lines (down from 514) | 1 |
| `.claude/scripts/post-pr-doc-test.sh` | **Create** — RTFM manifest generator | ~150 lines | 1 |
| `.claude/scripts/post-pr-orchestrator.sh` | **Modify** — add DOC_TEST phase + state + skip flag | ~30 lines added | 1 |
| `.loa.config.yaml.example` | **Modify** — add new config sections | ~20 lines added | 1 |
| `.claude/skills/run-mode/SKILL.md` | **Modify** — document RTFM manifest handling | ~30 lines added | 1 |

**Total**: 3 modified files, 1 new file, ~430 lines of shell script.

---

## 7. Decision Log

| ID | Decision | Rationale | Alternatives Considered |
|----|----------|-----------|------------------------|
| D-1 | Keep minimal regex fast-pass + Bridgebuilder deep analysis (revised per SKP-003) | Regex checks are deterministic and fast; Bridgebuilder is probabilistic. Fast-pass catches obvious issues (secrets) without API cost; Bridgebuilder adds LLM-powered depth. | Replace entirely (original); Run in parallel |
| D-2 | RTFM invoked via agent-mediated manifest pattern with correlation ID (revised per SKP-002, IMP-001) | RTFM is a skill, not a CLI binary. Manifest pattern with `run_id` provides explicit synchronization. Two-phase write avoids race conditions. | Create RTFM CLI wrapper; Shell-exec claude with /rtfm; Polling-based wait |
| D-3 | No fix loop for DOC_TEST | Doc gaps require human judgment. Auto-fixing prose via LLM risks hallucination. | Add single-iteration fix attempt; Spawn rewrite agent |
| D-4 | DOC_TEST before CONTEXT_CLEAR | Doc testing should run with full context available. After CONTEXT_CLEAR, agent has no memory of what changed. | After E2E; After FLATLINE |
| D-5 | Environment-aware failure policy defaults (revised per SKP-001) | CI defaults to fail_closed (safety), local defaults to fail_open (convenience). Explicit config overrides both. Degraded marker always surfaced in PR comment. | Uniform fail_open; Uniform fail_closed; No policy |
| D-6 | Sequential RTFM execution with partial-failure semantics (revised per IMP-004) | Predictable cost, avoids rate limits. On per-doc failure, continue to next doc and record per-doc status. Aggregate status uses defined rules. | Parallel with concurrency limit; Abort on first failure; Batch all docs |
| D-7 | Strict Bridgebuilder output schema validation (SKP-004) | Invalid/missing JSON treated as error, not silent pass. `min_severity` threshold filters actionable findings. Prevents misclassification of outcomes. | Trust raw output; Parse best-effort |
| D-8 | CI/headless degraded fallback for agent-mediated RTFM (IMP-003) | When no agent is present, DOC_TEST produces degraded marker instead of hanging or false-passing. 10s deadline for results file creation. | Require agent always; Skip silently |

---

## 8. Flatline Review Log

**Review Date**: 2026-02-09
**Phase**: SDD
**Agreement**: 90%
**Findings**: 3 HIGH_CONSENSUS + 1 DISPUTED (accepted) + 4 BLOCKERS (accepted)

### HIGH_CONSENSUS Integrated

| ID | Finding | Score | Integration |
|----|---------|-------|-------------|
| IMP-001 | Manifest write-then-read needs synchronization/handshake | 920 | Added §3.2 Synchronization Contract with correlation ID and two-phase write |
| IMP-003 | Must define CI/headless behavior when no agent present | 890 | Added CI/headless fallback in §3.2 (10s deadline + degraded marker) |
| IMP-004 | Multi-doc execution needs partial-failure semantics | 810 | Added per-doc results schema and aggregate status rules in §3.2 |

### DISPUTED Accepted

| ID | Finding | GPT | Opus | Integration |
|----|---------|-----|------|-------------|
| IMP-010 | Agent-mediated pattern needs explicit agent-side contract | 820 | 450 | Added §3.2 Agent-Side Contract table |

### BLOCKERS Accepted

| ID | Concern | Score | Integration |
|----|---------|-------|-------------|
| SKP-001 | fail_open makes gates non-enforcing | 920 | Revised §3.1 failure policy: CI defaults to fail_closed; orchestrator surfaces degraded marker in PR comment |
| SKP-002 | Agent-mediated RTFM has no hard synchronization | 900 | Added §3.2 Synchronization Contract + correlation ID + two-phase write |
| SKP-003 | Replacing regex removes deterministic safeguards | 760 | Revised D-1: keep minimal fast-pass + Bridgebuilder deep analysis |
| SKP-004 | Exit code/severity mapping underspecified | 720 | Revised §3.1: strict schema validation + min_severity thresholds + deterministic mapping table |
