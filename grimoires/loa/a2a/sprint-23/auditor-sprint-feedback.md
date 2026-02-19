# Security Audit: Sprint 23 — Constraint Yielding + Pre-flight Integration

**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-20
**Sprint**: sprint-2 (global sprint-23)
**Cycle**: cycle-029 — Construct-Aware Constraint Yielding

## Pre-requisite Verification

Senior Technical Lead approval: **VERIFIED** ("All good" in engineer-feedback.md)

## Security Checklist Results

### 1. constraints.json — `construct_yield` Addition

| Check | Status | Evidence |
|-------|--------|----------|
| No code injection via yield_text | PASS | yield_text is rendered by jq template into markdown — no eval, no shell interpolation |
| yield_on_gates restricted to valid gates | PASS | Values are "implement", "review", "audit", "sprint" — all valid gate names |
| No privilege escalation | PASS | `construct_yield` is declarative metadata; enforcement is in reader/activator (Sprint 1 audited) |
| Schema compatibility | PASS | JSON validates; existing fields untouched; additive-only change |
| No secrets | PASS | No credentials, tokens, or keys |

**Key Safety Analysis:**

1. **`construct_yield` is prompt-level metadata, not executable code.** The yield_text is rendered into CLAUDE.loa.md as markdown table content. It passes through jq's `escape_pipes` function which escapes `|` characters. There is no path from `yield_text` to shell execution.

2. **No bypass of `implement: required` invariant.** C-PROC-001 and C-PROC-003 have `yield_on_gates: ["implement"]`. This means they yield ONLY when the construct declares `implement: required` (enforced by Sprint 1's reader script, already audited). A malicious construct cannot set `implement: skip` — the reader blocks it with exit 2.

### 2. claude-loa-md-table.jq — Yield Clause Rendering

| Check | Status | Evidence |
|-------|--------|----------|
| No injection via template | PASS | jq string concatenation; `escape_pipes` applied to full output |
| Backward compatible | PASS | `if .construct_yield and .construct_yield.enabled` — false for all existing constraints |
| No eval or exec | PASS | Pure jq data transformation |
| Markdown table integrity | PASS | Pipe characters in yield_text are escaped via `escape_pipes` |

**Detailed Analysis:**

The template uses safe jq string concatenation:
```jq
$base_rule + " (" + .construct_yield.yield_text + ")"
```
This is pure data manipulation within jq. The output is fed through `escape_pipes` (line 13: `gsub("\\|"; "\\|")`) which prevents yield_text containing `|` from breaking the markdown table structure. No shell metacharacters can escape jq's string handling.

### 3. audit-sprint.md — `skip_when` Addition

| Check | Status | Evidence |
|-------|--------|----------|
| Cannot skip reviewer.md check | PASS | Only engineer-feedback.md checks have skip_when; reviewer.md check (line 56-58) has no skip_when |
| Cannot skip COMPLETED check | PASS | file_not_exists check for COMPLETED (line 80-82) has no skip_when |
| skip_when is prompt-level only | PASS | No programmatic enforcement; Claude reads YAML and follows instructions |
| Scope limited to review gate | PASS | Both skip_when blocks check construct_gate: "review", gate_value: "skip" |

**Key Safety Invariant:**

The `skip_when` mechanism CANNOT bypass the COMPLETED marker check or the reviewer.md existence check. Only the engineer-feedback.md checks (file_exists + content_contains "All good") are skippable. This means:
- A construct MUST still have an implementation report (`reviewer.md`) — no skip
- A construct MUST still not be already COMPLETED — no skip
- A construct can skip the "was it reviewed by senior lead?" gate when declaring `review: skip`

This is the correct security boundary: the construct takes responsibility for its own quality gate instead of delegating to Loa's review system.

### 4. review-sprint.md — `skip_when` on Context Files

| Check | Status | Evidence |
|-------|--------|----------|
| Only sprint.md is conditionally optional | PASS | prd.md and sdd.md remain required: true with no skip_when |
| skip_when is advisory, not programmatic | PASS | Claude interprets the YAML; file is loaded if available |
| Scope limited to sprint gate | PASS | construct_gate: "sprint", gate_value: "skip" |

**Residual Risk Analysis:**

- **Risk**: LOW. A construct declaring `sprint: skip` means sprint.md isn't required for review. This is by design — the construct's own workflow defines what context is needed.
- **Trust boundary**: Same as all construct trust — the construct pack must be installed within `.claude/constructs/packs/`, which requires explicit user action (per PRD NF-2, audited in Sprint 1).

## Vulnerability Assessment

### Constraint Bypass Analysis

- **Risk**: NONE
- **Analysis**: The `construct_yield` field is additive metadata. It does not modify constraint enforcement logic — it adds parenthetical text to the rendered constraint. The actual yielding behavior depends on Sprint 1's activation scripts (already audited) and Sprint 3's integration tests.

### Prompt Injection via yield_text

- **Risk**: NEGLIGIBLE
- **Analysis**: `yield_text` values are hardcoded in constraints.json (checked into git). They are not user-supplied at runtime. The jq template renders them as escaped markdown. An attacker would need write access to constraints.json, at which point they already have full system access.

### skip_when Scope Creep

- **Risk**: LOW
- **Analysis**: `skip_when` is narrowly scoped: only 3 checks across 2 files. The most sensitive gates (COMPLETED check, reviewer.md existence) are NOT skippable. Comments clearly document the semantics, reducing risk of future misunderstanding.

## Verdict

**APPROVED - LETS FUCKING GO**

Sprint 2 demonstrates security-appropriate design:

1. **Additive-only data model**: `construct_yield` adds metadata without modifying enforcement logic
2. **Safe rendering**: jq template with `escape_pipes` prevents markdown table injection
3. **Narrow skip_when scope**: Only review-gate checks and sprint context are skippable
4. **Invariant preservation**: COMPLETED check, reviewer.md check, and implement:required are never skippable
5. **Idempotent regeneration**: Hash-based change detection prevents accidental drift

No blocking security issues found. Ready for merge.
