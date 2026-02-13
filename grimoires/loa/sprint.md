# Sprint Plan: Harness Engineering Adaptations

> Source: SDD cycle-011, Issue [#297](https://github.com/0xHoneyJar/loa/issues/297)
> Cycle: cycle-011
> Sprints: 6 (3 original + 1 bridge-iter1 + 2 deep review)
> Deep Review Source: [Bridgebuilder Deep Read, Parts 1 & 2](https://github.com/0xHoneyJar/loa/pull/315#issuecomment-3896039870)

## Sprint 1: Safety Hooks + Deny Rules (P1, P2)

**Goal**: Ship the core safety infrastructure — destructive command blocking and credential deny rules.
**Status**: COMPLETED (sprint-74)

---

## Sprint 2: Stop Hook + Audit Logger + CLAUDE.md Optimization (P3, P4, P5)

**Goal**: Ship the stop guard, audit logging, and reduce CLAUDE.md token footprint by ~50%.
**Status**: COMPLETED (sprint-75)

---

## Sprint 3: Invariant Linter + Integration (P6)

**Goal**: Ship mechanical invariant enforcement and wire everything together.
**Status**: COMPLETED (sprint-76)

---

## Sprint 4: Bridge Iteration 1 — Findings Remediation

**Goal**: Address 6 actionable findings from Bridgebuilder iteration 1.
**Status**: COMPLETED (bridge-20260213-c011he, 20/20 tests pass)

---

## Sprint 5: Test Harnesses + Verification — "Who Tests the Testers?"

**Goal**: Build persistent, re-runnable test infrastructure for safety hooks and invariant linter. Add deny rule verification path. The safety layer must be the best-tested code in the stack (Google SRE principle: "The monitoring system must be the best-tested system").

**Source**: [Deep Review Critical 1, 2, 3](https://github.com/0xHoneyJar/loa/pull/315#issuecomment-3896040920)

### Task 5.1: Create Safety Hook Test Harness

**File**: `.claude/scripts/test-safety-hooks.sh`

Persistent, re-runnable regression test suite for `block-destructive-bash.sh`:
- All 20 existing test cases (12 original + 8 path/prefix/chain)
- Edge cases: empty command, malformed JSON, very long commands, unicode, pipe chains
- Test for fail-open behavior: what happens when jq is missing? When input is binary?
- Pass/fail summary with exit code 0 on all-pass, 1 on any failure
- Designed to be called from invariant linter or CI

**Acceptance Criteria**:
- `bash .claude/scripts/test-safety-hooks.sh` runs all test cases
- Includes at least 25 test cases covering: block patterns, allow patterns, edge cases, failure modes
- Exit code 0 when all pass, 1 when any fail
- Output format shows PASS/FAIL per test with summary line
- Script is executable and documented

### Task 5.2: Create Deny Rule Verification Script

**File**: `.claude/scripts/verify-deny-rules.sh`

Verify that deny rules from the template are actually active in `~/.claude/settings.json`:
- Read current settings and compare against template
- Report missing, present, and extra rules
- `--json` flag for machine-readable output
- Usable as standalone check or from invariant linter

Inspired by AWS IAM `simulate-principal-policy` — verify the *actual* permission state matches the *intended* permission state.

**Acceptance Criteria**:
- Reports count of: present rules, missing rules, extra rules (not in template)
- `--json` flag outputs structured result
- Exit code 0 if all template rules present, 1 if any missing
- Handles missing settings.json gracefully
- Works with `install-deny-rules.sh --dry-run` for cross-validation

### Task 5.3: Create Invariant Linter Self-Test

**File**: `.claude/scripts/test-lint-invariants.sh`

Test harness for `lint-invariants.sh` itself — the LLVM principle of testing the testing infrastructure:
- Create temporary directory with known-good project state → verify all pass
- Create temporary directory with known-bad state (missing files, invalid JSON, broken blocks) → verify correct errors/warnings
- Test `--json` output is valid JSON via `jq`
- Test `--fix` mode actually fixes fixable issues
- Test exit codes: 0 for all-pass, 1 for warnings, 2 for errors

**Acceptance Criteria**:
- Creates temp fixtures, runs linter, validates output, tears down
- Tests at least: all-pass state, missing-file error, invalid-json error, missing-block error
- Verifies `--json` output round-trips through `jq`
- Verifies exit codes match documentation
- Script is re-entrant (no side effects on real project)

### Task 5.4: Wire Test Harnesses into Invariant Linter

**File**: `.claude/scripts/lint-invariants.sh`

Add two new invariant checks:
- **Invariant 8**: Safety hook tests pass (`test-safety-hooks.sh` exits 0)
- **Invariant 9**: Deny rules active (`verify-deny-rules.sh` exits 0) — WARN-level, not ERROR

The safety test is mandatory (ERROR if fail). The deny rule check is advisory (WARN if missing) since not all environments have `~/.claude/settings.json`.

**Acceptance Criteria**:
- `lint-invariants.sh` now reports 9 invariant checks
- Invariant 8 runs safety hook tests, reports PASS/ERROR
- Invariant 9 checks deny rule installation, reports PASS/WARN
- Both new checks skip gracefully if their script is missing
- `--json` output includes new invariants

---

## Sprint 6: Decision Trails + Observability Foundations

**Goal**: Add inline decision documentation to safety-critical code, measure actual token reduction, and prepare the audit log schema for Hounfour multi-model observability.

**Source**: [Deep Review Critical 4, 5, Horizon 1-2](https://github.com/0xHoneyJar/loa/pull/315#issuecomment-3896040920)

### Task 6.1: Add Decision Trail Comments to Hooks

**Files**: All hook scripts in `.claude/hooks/`

Add inline `# WHY:` comments documenting architectural decisions in safety-critical code. The Linux kernel principle: "Describe *why* this change is needed, not just *what* it does."

Decisions to document:
- `block-destructive-bash.sh`: Why fail-open (not fail-closed)? Why ERE not PCRE? Why single script for all patterns?
- `run-mode-stop-guard.sh`: Why soft block (JSON decision) not hard block (exit 2)? Why no `set -euo pipefail`?
- `mutation-logger.sh`: Why JSONL not structured JSON? Why 10MB rotation threshold? Why these specific commands?
- `settings.deny.json`: Why `~/.bashrc` is read-allowed but edit-blocked. Why these specific paths.

**Acceptance Criteria**:
- Each hook script has `# WHY:` comments for non-obvious design decisions
- At least 3 decision comments per script
- Comments reference the finding or source that motivated the decision where applicable
- No code changes — documentation only

### Task 6.2: Measure Actual Token Reduction

**File**: `.claude/scripts/measure-token-budget.sh`

Create a script that measures actual token count of CLAUDE.loa.md and reference files, not just word count. The metric that matters is token count — word count is a proxy with variable accuracy depending on markdown formatting, code blocks, and HTML comments.

- Count tokens in CLAUDE.loa.md (the always-loaded file)
- Count tokens in each reference file
- Report: always-loaded tokens, demand-loaded tokens, total tokens, savings vs pre-optimization
- Use a tokenizer (tiktoken via Python, or heuristic: tokens ≈ words × 1.3 for English prose, × 1.5 for code/markdown)

**Acceptance Criteria**:
- Reports always-loaded token count (CLAUDE.loa.md only)
- Reports demand-loaded token count (sum of reference files)
- Reports total and percentage savings
- `--json` flag for machine-readable output
- Documents the tokenization method used

### Task 6.3: Enrich Audit Log Schema for Hounfour Readiness

**File**: `.claude/hooks/audit/mutation-logger.sh`

Extend the JSONL audit log schema with optional fields for multi-model provenance. These fields are empty now but establish the schema contract for when the Hounfour is live.

Current schema:
```jsonl
{"ts":"...","tool":"Bash","command":"...","exit_code":0,"cwd":"..."}
```

Extended schema:
```jsonl
{"ts":"...","tool":"Bash","command":"...","exit_code":0,"cwd":"...","model":"","provider":"","trace_id":""}
```

The `model`, `provider`, and `trace_id` fields are empty strings when not provided by the runtime. This follows the OpenTelemetry principle: define the trace schema before the instrumentation exists.

**Acceptance Criteria**:
- Audit log entries include `model`, `provider`, `trace_id` fields (empty string default)
- Fields populated from environment variables if present: `LOA_CURRENT_MODEL`, `LOA_CURRENT_PROVIDER`, `LOA_TRACE_ID`
- Existing log consumers (rotation, grep) unaffected by new fields
- Schema documented in hooks README

### Task 6.4: Add Per-Model Permission Constraint Template

**File**: `.claude/data/model-permissions.yaml`

Create a YAML template for per-model capability constraints. This doesn't enforce anything yet — it's a schema declaration for the Hounfour's permission landscape. The constraint-generated block pattern can later render this into CLAUDE.loa.md.

```yaml
# Per-model capability constraints (Hounfour readiness)
# These are not enforced yet — they define the target permission landscape
# See: https://github.com/0xHoneyJar/loa-finn/issues/31
model_permissions:
  claude-code:session:
    trust_level: high
    execution_mode: native_runtime
    capabilities:
      file_write: true
      command_execution: true
      network_access: true
  openai:gpt-4o:
    trust_level: medium
    execution_mode: remote_model
    capabilities:
      file_write: false
      command_execution: false
      network_access: false
  moonshot:kimi-k2-thinking:
    trust_level: medium
    execution_mode: remote_model
    capabilities:
      file_write: false
      command_execution: false
      network_access: false
  qwen-local:qwen3-coder-next:
    trust_level: medium
    execution_mode: remote_model
    capabilities:
      file_write: true
      command_execution: false
      network_access: false
```

**Acceptance Criteria**:
- Valid YAML parseable by `yq`
- Includes all 5 models from the Hounfour RFC Model Catalog
- Each model has: `trust_level`, `execution_mode`, `capabilities` with boolean flags
- Comment header explains this is a schema template, not enforced
- References the Hounfour RFC issue for context
