# PRD: cycle-059 — Bridge Triage Analyzer

**Cycle**: cycle-059
**Issue**: [#467](https://github.com/0xHoneyJar/loa/issues/467) Option B/D decision-gate tooling
**Date**: 2026-04-13

---

## 1. Problem Statement

The post-PR Bridgebuilder loop (enabled in v1.74.0) writes per-decision triage entries to `grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl` with a mandatory `reasoning` field. We now have real-world signal: 3 PRs, ~118 decisions. But we have no way to *read* that signal at aggregate level.

**Concrete pain**: [#467](https://github.com/0xHoneyJar/loa/issues/467) Option A acceptance criterion says *"≥5 real-world PR reviews with signal metrics (FP rate, cost, convergence)"*. We can't measure FP rate, convergence distribution, or cost per cycle from a `jsonl` stream without tooling. That blocks the data-driven decision on Option B (auto-consume `.run/bridge-pending-bugs.jsonl`) and Option D (pattern aggregation across PRs).

> Sources: [#467](https://github.com/0xHoneyJar/loa/issues/467) roadmap, existing trajectory files at `grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl`

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| G1: Convert raw triage logs into actionable signal | Script exists, accepts glob + --json flag | Binary (yes/no) |
| G2: Enable data-gated #467 decisions | Comment posted on #467 with analyzer output | Binary |
| G3: Future-proof — tool improves as more PRs accumulate | Aggregates multiple `bridge-triage-*.jsonl` files | Binary |
| G4: Zero new dependencies | Uses only `jq` + bash (existing Loa prereqs) | Binary |

**Non-goals**:
- Real-time streaming metrics (batch analysis is sufficient)
- Web dashboard / visualization (plain-text + JSON suffices)
- Re-triage / re-classification logic (analyzer is read-only)
- Predicting whether a PR *will* converge (analyzer is retrospective)

## 3. User & Stakeholder Context

**Primary user**: the Loa framework maintainer reviewing open roadmap options in [#467](https://github.com/0xHoneyJar/loa/issues/467) — needs signal data to decide whether Option B (auto-dispatch) and Option D (pattern aggregation) are ready to start.

**Secondary users**:
- Future cycles doing retrospectives on Bridgebuilder performance
- The Bridgebuilder itself (read-only — the analyzer output becomes context for future planning sessions)

## 4. Functional Requirements

### FR-1: Script surface (ubiquitous)
The system shall provide `.claude/scripts/bridge-triage-stats.sh` that accepts:
- Positional arg: glob pattern (default `grimoires/loa/a2a/trajectory/bridge-triage-*.jsonl`)
- `--json`: machine-readable output
- `--pr N`: restrict to a single PR number
- `--since YYYY-MM-DD`: restrict to entries on/after this date
- `--help`: show usage

### FR-2: Aggregation dimensions (ubiquitous)
The script shall compute, per input set:
- **Total decisions** across all PRs in scope
- **Per-PR breakdown** (decisions per PR number, severity mix)
- **Action distribution** (dispatch_bug / log_only / lore_candidate / defer / fix / dispute / flatline / etc.)
- **Severity distribution** (HIGH / MEDIUM / LOW / PRAISE / SPECULATION / VISION / REFRAME / BLOCKER)
- **Convergence trajectory per PR** (severity counts per pass when multiple passes logged)
- **False-positive proxy**: count of `action: "dispute"` + `action: "defer"` + `action: "noise"` as share of total

### FR-3: Output formats (ubiquitous)
- **Default (text)**: human-readable markdown tables suitable for pasting into an issue comment
- **`--json`**: single JSON object with keys `total_decisions`, `prs`, `actions`, `severities`, `convergence`, `fp_proxy`

### FR-4: Graceful degradation (event-driven)
When the glob matches zero files, the system shall print "no trajectory files found" to stderr and exit 0 with empty output — not fail.

When a file contains malformed JSON lines, the system shall skip those lines, warn to stderr, and continue with valid entries. This honors the "never lose data" invariant from the cycle-053 trajectory schema.

### FR-5: Optional #467 comment helper (ubiquitous)
The script shall accept `--comment-issue N` that runs `gh issue comment N --body-file -` with the formatted text output. One-line workflow for closing the data-gating loop on #467.

## 5. Technical & Non-Functional Requirements

### NFR-1: No new dependencies
Uses only `bash`, `jq`, `date`, and the optional `gh` CLI. All already Loa hard prereqs.

### NFR-2: Performance
For ~1000 decisions across ~20 PRs, the script completes in < 2 seconds. jq native aggregation keeps this trivial.

### NFR-3: Safety
- Read-only on trajectory files (no writes back to `.jsonl`)
- No eval, no unquoted shell expansion, no shell-out to untrusted input
- Config inputs (globs, dates, PR numbers) validated before use

### NFR-4: Zone compliance
- Writes to System Zone (`.claude/scripts/`) — authorized at cycle-059 scope
- Reads from State Zone (`grimoires/loa/a2a/trajectory/`)
- No App Zone interaction

## 6. Scope & Prioritization

### MVP (this cycle)
- FR-1 through FR-5: script with all flags + text + JSON + graceful degradation + comment helper
- Tests: BATS suite covering every severity, empty glob, malformed line, --pr filter, --since filter, JSON output shape, text output shape
- Docs: inline usage header + mention in run-bridge SKILL.md

### Out of scope (follow-up)
- Real-time streaming mode
- HTML/markdown visualization
- Per-finding-ID deduplication across passes
- Automated cost calculation (trajectory schema doesn't carry token counts yet)

## 7. Risks & Dependencies

| Risk | Mitigation |
|------|-----------|
| Trajectory schema evolves, breaking the analyzer | Defensive `.field // default` everywhere; malformed entries skipped with warning |
| PR #100 legacy test data contaminates stats | `--since` flag lets caller exclude pre-enablement data |
| `gh issue comment` failing offline/unauthenticated | `--comment-issue` optional; prints to stdout as fallback |

Dependencies: `gh`, `jq`, `date` (all already required).

### Sources
- [#467](https://github.com/0xHoneyJar/loa/issues/467) Option B/D gating criteria
- Cycle-053 trajectory schema: `.claude/data/trajectory-schemas/bridge-triage.schema.json`
- Existing trajectory logs: `grimoires/loa/a2a/trajectory/bridge-triage-2026-04-13.jsonl`
- v1.78.0 [release](https://github.com/0xHoneyJar/loa/releases/tag/v1.78.0) — pattern this cycle supports
