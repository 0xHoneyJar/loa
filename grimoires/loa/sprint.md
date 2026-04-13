# Sprint Plan: cycle-059 — Bridge Triage Analyzer

**Cycle**: cycle-059
**Branch**: feat/cycle-059-bridge-triage-analyzer
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Issue**: [#467](https://github.com/0xHoneyJar/loa/issues/467) Option B/D decision-gate tooling
**Date**: 2026-04-13

---

## Cycle Summary

Build `.claude/scripts/bridge-triage-stats.sh` — a small shell analyzer that aggregates `grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl` into actionable signal (per-PR severity mix, action distribution, FP proxy, convergence trajectory). Output in markdown (default) or JSON. Optional `--comment-issue N` one-liner closes the data-gating loop on [#467](https://github.com/0xHoneyJar/loa/issues/467).

Enables data-gated decisions on [#467](https://github.com/0xHoneyJar/loa/issues/467) Options B and D which have been waiting on Option A signal data since v1.73.0.

## Sprint 1: Analyzer + Tests + Docs

**Scope**: MEDIUM (5 tasks)
**FRs**: FR-1 (surface), FR-2 (aggregation), FR-3 (formats), FR-4 (graceful degradation), FR-5 (comment helper)
**Goal**: Ship a standalone `bridge-triage-stats.sh` with full BATS coverage, no new deps.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T1 | Create `.claude/scripts/bridge-triage-stats.sh`. Flag parser (`--json`, `--pr`, `--since`, `--comment-issue`, `--help`), glob resolution, malformed-line warning. Bash strict mode (`set -euo pipefail`) with the documented patterns (array-safe expansion, arithmetic-with-set-e). | `.claude/scripts/bridge-triage-stats.sh` (new) | FR-1, FR-4 | G-1 |
| T2 | Single-jq aggregator: per-PR breakdown, global severities, global actions, FP proxy counts. Emit JSON object. | Same file (T1) | FR-2 | G-1 |
| T3 | Text formatter: render JSON summary as markdown tables (5 sections per SDD §2.6). | Same file (T1) | FR-3 | G-1 |
| T4 | `--comment-issue N` flow: pipe text output through `gh issue comment N --body-file -`. Validate `$N` is numeric. | Same file (T1) | FR-5 | G-2 |
| T5 | BATS tests at `tests/unit/bridge-triage-stats.bats`. 10 cases per SDD §4. Include: happy path, empty glob, malformed lines, `--pr`, `--since`, `--json`, `--help`, FP arithmetic, multi-file, unknown flag. | `tests/unit/bridge-triage-stats.bats` (new) | — | G-3 |

### Acceptance Criteria

- [ ] `bridge-triage-stats.sh` exists, executable, passes `bash -n` syntax check
- [ ] Default invocation against real trajectory data produces sensible markdown output
- [ ] `--json` produces valid JSON with top-level keys: `total_decisions`, `prs`, `severities`, `actions`, `fp_proxy`
- [ ] `--pr N` filters entries to the specified PR
- [ ] `--since YYYY-MM-DD` filters entries by timestamp
- [ ] `--comment-issue N` posts to `gh issue comment` when invoked (mockable in tests via `GH_BIN` env override)
- [ ] Empty glob → exit 0, stderr warning, no spurious output
- [ ] Malformed JSONL lines skipped with stderr count, valid lines still processed
- [ ] Unknown flag → exit 2 with error
- [ ] All 10 BATS cases pass
- [ ] Inline usage header lists every flag with one-line description + exit codes
- [ ] No new package dependencies (uses only `bash`, `jq`, `date`, optional `gh`)

### Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| jq regex `capture` syntax differs across jq versions | Use best-effort with `// {n: "0"}` fallback; don't rely on convergence detection for core aggregation |
| `date` portability (GNU vs BSD) for `--since` comparison | Use lexical `YYYY-MM-DD` comparison (ISO-8601 strings sort chronologically), avoiding `date -d` |
| `gh` CLI not available in test env for `--comment-issue` | Mock via `GH_BIN` env var → `echo` for BATS; real `gh` used only in production |
| Glob expansion finding zero files under `set -u` | Use `shopt -s nullglob` or array-safe fallback |

### Goals

- **G-1**: Analyzer is standalone and useful today against real data
- **G-2**: Closes the feedback loop on [#467](https://github.com/0xHoneyJar/loa/issues/467) via one-shot comment
- **G-3**: Test coverage prevents silent regression as trajectory schema evolves

### Dependencies

- Cycle-053 trajectory schema (already shipped, v1.73.0)
- Existing JSONL samples at `grimoires/loa/a2a/trajectory/bridge-triage-2026-04-13.jsonl`
- `gh`, `jq`, `date` (all already Loa hard prereqs)

### Zone & Authorization

**System Zone writes required**: `.claude/scripts/bridge-triage-stats.sh` (new file).
**Tests**: `tests/unit/bridge-triage-stats.bats` (outside System Zone, freely writable).
Cycle-level authorization: cycle-059 authorizes a single new System Zone file at the above path — no modifications to existing `.claude/` scripts or skills in this sprint. (The run-bridge SKILL.md cross-reference note from SDD §8 is a single-line addition that can land in this sprint or deferred.)

## AC Verification (Required — Issue #475)

Before writing COMPLETED marker, the implementation report MUST include an `## AC Verification` section walking each acceptance criterion verbatim with file:line evidence per the gate introduced in cycle-057 (v1.77.0). This sprint is the first real-world exercise of that gate.

---

*1 sprint, 5 tasks, closes [#467](https://github.com/0xHoneyJar/loa/issues/467) Option A tooling prerequisite*
