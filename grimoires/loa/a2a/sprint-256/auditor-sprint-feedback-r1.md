# Security & Quality Audit Report — sprint-256 (cycle-129 Sprint 2), round 1

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Scope:** `b6802e4f..5ecf13f5` (implementation `40df53ed`, review fix rounds `3263bbc4`, `b6030e5b`, `77455afb`, `5ecf13f5`; code only — generated register, REPO-MAP, checksums, ledgers and NOTES excluded from the diff), read against the approved review (`engineer-feedback.md`, round 3) and the three implementer reports.
**Dissent:** `adversarial-audit.json` — two voices (`codex-headless` gpt-5.5-pro, `claude-headless`), consensus, confidence floor high, chain ok; 9 findings (2 HIGH, 3 MEDIUM, 4 LOW), 0 rejected payloads (`adversarial-rejected-audit.jsonl` is empty).

## Executive Summary

The sprint's mechanics hold: the implement gate is tighten-only in every mode, the run-position derivation never moves a terminal state back to RUNNING, the heredoc classifier fails closed on every parse failure and the backtick normalisation closed a hole that predates the cycle, the profile library cannot reach a floor key, and every new audit row is control-stripped and byte-capped. Two things must change before approval. First, the corpus documents a real bypass of the branch-protection intent — `gh api` with a destructive method against refs, branches, tags, releases or the repository has no fence rule while the git porcelain forms are blocked — and the sprint's new `miss` class would let that and future misses stay green; the fence needs the rule and the class needs a pinned count. Second, the register's likely-false-positive heuristic treats a System-Zone block as a false positive when the heredoc body is prose, which is backwards for a rule whose hazard is the target, and one new test suite carries the same dead-negation pattern the review round just fixed elsewhere. Everything else is accepted risk by recorded decision or a documented gap, listed below with the bead or note that carries it.

## Findings

### HIGH-A1 — `gh api` with a destructive method on refs, branches, tags, releases or the repository bypasses the branch-protection intent (dissent DISS-C-001, confirmed)

`gh api -X DELETE repos/<o>/<r>/git/refs/heads/<branch>` deletes a remote branch; `-X PUT … /branches/<b>/protection` rewrites protection; `-X DELETE repos/<o>/<r>` deletes the repository. The fence blocks the porcelain twins (P2 force push, P5 branch force-delete, SP-1 spike pushes) and has no rule for the REST escape hatch; D113 blocks the same header only because its body carries a destructive command, and M01 records the benign-body call as a documented miss. The hole predates the cycle (identical on `main`), but the sprint's `miss` class institutionalises it: a `miss` row can never fail the run, so further misses could land with CI green. Required: a fence rule (`FR-GH-1`) for `gh api` with `-X`/`--method` (joined or separate, quoted or not) `DELETE|PUT|PATCH` against `/git/refs/`, `/branches/*/protection`, `/releases`, `/tags`, `/git/tags/` or a bare `repos/<o>/<r>`; M01 becomes a D-row; the miss class keeps a pinned expected count (zero today) so a new miss row is a mismatch until the pin is raised deliberately; register row, hooks-reference line and corpus B-rows for the GET/POST/issue-PATCH forms that stay allowed.

### MEDIUM-A1 — dead negated assertions in the new surgical-diff suite (dissent DISS-C-003, confirmed)

`tests/unit/karpathy-surgical-diff.bats` KS-9 asserts the no-content-leak property with a bare mid-test `! grep -rqF "$secret" …`, which bash exempts from errexit, so the test cannot fail on a leak; KS-8 chains `[ … ] && [ … ]` so only the first check can fail. Same class as review LOW-8 (fixed in `lint-invariants.bats`, `profile-lib.bats` and the corpus lint). Required: `run` plus a status assertion for the negation; one assertion per line in KS-8.

### MEDIUM-A2 — the register's false-positive heuristic treats a System-Zone block as prose (dissent DISS-C-007, confirmed)

`guard-yield.sh` marks a block as a likely false positive when the command's heredoc is non-executing; GY-3 pins that an `FR-SZ2-REDIR` block (a redirect into `.claude/x.md`) counts as a false positive because the body is prose. For a System-Zone rule the hazard is the target, not the body: files under `.claude/` are read as instructions, so prose written there is exactly what SZ2 exists to refuse (D124 relies on it). If the yield statistics ever inform a relaxation, this heuristic steers toward loosening SZ2. Required: apply the heredoc heuristic only to content rules, never to `FR-SZ*` pattern ids; the GY-3 expectation for that row becomes a real block.

### LOW-A1 — executable-content targets the classifier should also treat as code (dissent DISS-C-008, partly confirmed)

The classifier already treats `.git/hooks/`, rc files including `.envrc`, `.claude/settings*.json` and the interpreter extensions (`.py`, `.js`, `.rb`, `.pl`, …) as executable content, but nothing in the corpus pins most of them, and `Makefile`/`justfile`, `.github/workflows/*.yml` and `package.json`/`pyproject.toml`/`Cargo.toml` (script sections) are not covered. Required: extend the target rule and pin each class with a D-row.

### LOW-A2 — guardrails and danger-level enforcement default off for a fresh install (dissent DISS-001, DISS-C-004: accepted by decision, documentation required)

This is DEC-0161 / PRD D15 (82 events, zero catches, seven blocks on sanctioned skills), an operator-behalf decision awaiting `/decisions confirm`; the floor (review, audit, verdict-derive, the dissent gate, the deny list, FR-1.2b, the System-Zone rules) is untouched and this repository keeps the input guardrail on as telemetry. The auditor accepts the decision as the operator's and requires the exposure to be stated where an installer reads it: a security note in the CHANGELOG naming what is off by default, what it detected historically, and the two keys (or `loa.profile: full`) that turn it back on. The include's fail-open error path and the `LOA_GUARDRAILS_ENABLED=false` escape without an audit row predate the sprint (cycle-114) and go to a bead.

### LOW-A3 — Bash-forgeable sanctions (dissent DISS-C-002: accepted gap, already documented)

The gate's sanctions are `.run` files a Bash command can write (the new marker included) plus the operator override; the hooks reference lists this under accepted gaps, D-4.1 makes every new path tighten-only (a forged sanction returns to today's `ask` behaviour, never looser), and a cache without `derived_at` cannot sanction `deny`. A fence rule on shell writes into `.run` state files would today block the documented `/run-halt` flow, which edits `state.json` with jq; it goes to a bead with that dependency named. No change this round.

### LOW-A4 — `LOA_PROFILE_CONFIG_FILE` honoured outside bats (dissent DISS-C-005; review LOW-5)

Documented in the example this round; floor keys are read by the floor readers directly and never through the seam. No change this round.

### LOW-A5 — knob-lint bypass forms and scope (dissent DISS-C-006)

PL-17 already plants a direct read and asserts exit 1 (the sentinel the dissent asks for); the bracket/quoted path forms and a wider scan scope go to a bead. No change this round.

## Security Checklist Status

| Area | Status | Notes |
|------|--------|-------|
| Secrets / credentials | PASS | none added; the corpus hygiene lint (now `run`-based) covers hostnames, IPs, key shapes |
| Input validation at trust boundaries | PASS | gate payloads canonicalised and control-stripped; profile key paths regex-checked before yq; `run-checkpoint` labels and ids validated; classifier parse failure → full scan |
| Privilege / sanction paths | PASS with LOW-A3 | tighten-only; every sanction logs its own row; override logged only when nothing else sanctioned |
| Fail-closed defaults | CHANGES (HIGH-A1) | the fence's REST escape hatch; otherwise every new path fails closed (unknown position → ask, unreadable heredoc header → full scan, unbalanced quotes → normalise) |
| Audit trail | PASS | `replay: true` under `LOA_AUDIT_REPLAY=1`; rows written with `jq -a`, 256-byte cap |
| Test integrity | CHANGES (MEDIUM-A1) | dead negations in one new suite |
| System Zone | CHANGES (MEDIUM-A2) | the register must not learn to call SZ blocks false positives |

## Positive Findings

- The backtick normalisation is heredoc-aware and fails closed on unbalanced quotes; D143–D155 pin every shape the probes found, and the knob-off replay is row-identical to the pre-change hook except on those rows.
- `derive` never moves JACKED_OUT or HALTED back to RUNNING; `record-round` is idempotent on an already-open breaker and refuses a missing feedback file.
- The profile library drops floor keys with a WARN and refuses malformed key paths before they reach yq; the example now follows the profile a copier chooses.
- The gate skills' `deny_raw_shell` grants are byte-for-byte consistent with every prescribed shell step (CMP-188).

## Severity Tally

| Severity | Count | Items |
|----------|-------|-------|
| CRITICAL | 0 | — |
| HIGH | 1 | HIGH-A1 |
| MEDIUM | 2 | MEDIUM-A1, MEDIUM-A2 |
| LOW | 5 | LOW-A1 (change), LOW-A2 (CHANGELOG note + bead), LOW-A3, LOW-A4, LOW-A5 (beads/notes) |

## Verdict

CHANGES_REQUIRED — HIGH-A1, MEDIUM-A1, MEDIUM-A2 and LOW-A1 land in fix round r256-4 together with the LOW-A2 security note; LOW-A3 … LOW-A5 are recorded with their beads. Re-run the audit dissent on the fixed tree.

## Rejected dissent payloads

None: the envelope reports 0 rejected payloads and `adversarial-rejected-audit.jsonl` is empty.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-256","ts":"2026-10-14T05:10:00Z"} -->
