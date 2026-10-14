# Sprint Plan: Earned Guards and Open Voices (cycle-129)

**Version:** 1.0
**Date:** 2026-10-14
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md
**Ledger:** cycle `cycle-129-earned-guards`, sprints global 255 / 256 / 257 (local sprint-1 / sprint-2 / sprint-3)
**Execution:** `/run sprint-plan`, push AUTO; Opus 5.5 implementers in linked worktrees returning `git diff --cached --binary` patches; the lead applies, reviews and audits on Fable 5.1; at most three dissent runs per sprint
**Task kinds:** every task carries `kind: mechanical | judgment | operator` (FR-10, DEC-0144); no `operator` task exists in this plan because the maintainer's instruction authorised the cycle end to end and every operator decision is a `proposed` DEC row

---

## Executive Summary

Three sprints turn the Van Clief paradigm review into measured, tightened, and honestly described guards, and open the voice path to open-weight and local models without a vote. Sprint 1 builds the instruments: a guard register with origin and 30-day yield, pre-registered gate-off control arms with a corpus drawn from the cycle-126 to 128 record, task kinds, and the path-scoping of the two always-loaded rule files. Sprint 2 spends the measurements: the inert controls are repaired or demoted, run position is derived from files, the fence stops blocking prose in heredocs, a profile knob sets the optional surfaces, and the kernel is thinned only where an arm shows no recall loss. Sprint 3 admits advisory open-weight voices, adds the `local_voices` posture, fixes the Bridgebuilder banner and exit code, and validates every goal end to end. The floor is not touched by any task.

> Sources: prd.md §Executive Summary, §Timeline; sdd.md §1.2, §8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 255 | Measure | `guard-origins.yaml`, `guard-yield.sh`, `guards.md`, generated hooks table, origin lint, `/loa` Guards line; FR-2 arms, toggles, eight record fixtures, `run-arms.sh` started; `kind:` validator and template; rule-file `paths:`; doc fixes; KF-041 issue | None |
| 2 | 256 | Thin and repair | implement-gate modes; `disallowed-tools`; per-task surgical-diff; guardrails off; C-TEAM rows out; `run-checkpoint.sh record-round` and `derive`; heredoc classifier and corpus; profiles and floor test; kernel diet and cap | Sprint 1 (arm results for FR-3) |
| 3 | 257 | Open voices | loader examples and insecure-endpoint opt-in; chat schema and thinking strip; advisory voices and catalog-priced budget gate; Bridgebuilder keyless map, banner, exit 3; `local_voices`; docs; E2E | Sprints 1–2 |

---

## Sprint 1: Guard register and yield, control arms, task kinds, rule path-scoping

**Global ID:** 255 · **Epic:** bd-61r5 · **Beads:** bd-9ntm, bd-jcfq, bd-sxzs, bd-tebv, bd-ovnz, bd-n8if, bd-ol5w, bd-1hv6, bd-6wcv, bd-6gcpy, bd-fjzah

### Sprint Goal
Make every guard carry an origin and a yield figure, make the control run exist, tag tasks by kind, and stop loading two rule files on every turn, without changing any gate's behaviour.

### Deliverables
- `.claude/data/guard-origins.yaml` seeded for every registered hook command, fence pattern id, validator rule and gate (SDD D-1.1)
- `.claude/scripts/guard-yield.sh` with `--hooks-table`, `--check`, `--json`; `grimoires/loa/guards.md`; the generated registration table in `hooks-reference.md`; `tests/unit/guard-yield.bats`, `tests/unit/guard-origins.bats` (D-1.2 … D-1.6)
- `/loa` Guards line (D-1.5)
- `ab.arms` in `review-recall.yaml` and `audit-recall.yaml`; arm toggles in `execute-agent.sh`; `report.sh --arms`; `evals/tests/arm-toggles.bats` (D-2.1, D-2.3)
- `evals/harness/seed-corpus-from-record.sh`; fixtures `pr-11` … `pr-18` (`pr-09` and `pr-10` already exist as clean controls) (sprints 247–254) with `labels.tsv`; `corpus.tsv` and `SHA256SUMS` extended; `evals/tests/seed-corpus.bats` (D-2.2)
- `evals/harness/run-arms.sh`, started detached at sprint end (D-2.3)
- `validate-artifact.sh --type sprint` `kind:` rule; sprint template; `reviewing-code` spec-axis lines; `tools/cycle-ratio.sh`; bats (D-10.1 … D-10.3)
- `paths:` frontmatter on `stash-safety.md` and `skill-invariants.md`; FR-1.2b block message pointer (D-3.1)
- Doc fixes: `check-prompt-budget.yml` comment, `implementing-tasks/SKILL.md:28`
- KF-041 upstream issue filed and recorded in the KF entry
- CHANGELOG `[Unreleased]` entries; REPO-MAP and checksums regenerated

### Acceptance Criteria
- [x] AC-1.1 `guard-origins.bats` fails on a fixture hook without an origin and passes on the seeded map; every enumerated hook script and fence id has a row (PRD AC-1.1)
- [x] AC-1.2 `guard-yield.bats`: replay rows (cwd under the temp dir or `/bats-run-`) are excluded and counted in the header; a rotated segment is read; heredoc, scratch-path and prose-class blocks classify as likely false positives; `last_real_catch` is day-granular (PRD AC-1.2)
- [x] AC-1.3 The tracked `guards.md` is structural (ids, class, status, origin, knob, floor, registrations; no timestamp) and the untracked `.run/guard-yield.md` and `.run/guard-yield.json` carry this host's 30-day yield with `scope: host` and the window; none of the three contains command text, cwd, hostname or model name; `guard-yield.sh --check` exits 0 after generation, 1 after an origin edit, and 0 after a yield-only change (PRD AC-1.3, AC-1.4; wording follows DEC-0162)
- [x] AC-1.4 `hooks-reference.md`'s table is the generated one and lists all registered hooks, including the six omitted before, with their registrations and status (PRD AC-1.4)
- [x] AC-1.5 `/loa` prints the Guards line from `.run/guard-yield.json` or the regenerate hint; `.claude/settings.json` hook registrations and the fence pattern-id list are byte-identical before and after the sprint (the register disables nothing); `floor-snapshot.bats` passes; `dormant` rows are excluded from the inert-controls KPI (PRD AC-1.5)
- [x] AC-1.6 Both suites declare the canonical arm ids and the `ab.threshold` block; a sandbox prepared for `no_rule_files` has no rule files, for `no_karpathy` no Karpathy section, for `no_companion` `companion_voice: false`, for `no_audit_delta` no delta paragraph; `compare.sh --ab` refuses skewed model ids; `report.sh --arms` prints the per-arm verdict (PRD AC-2.1, AC-2.3, AC-2.4)
- [x] AC-1.7 At least six of the eight record fixtures exist with `fixture.yaml`, `head.diff`, instructions and an approved `labels.tsv` (a sprint with no accepted finding whose fix touches a cited file is dropped and the gap stated in `corpus.tsv` and the report); every label satisfies the fix-touches-file rule and carries `label_source`; every label passes `no-secrets.sh`; `SHA256SUMS` covers every file; `recall-vs-defects.sh` grades a label file (PRD AC-2.2)
- [x] AC-1.8 `run-arms.sh --dry-run` lists the planned trials and writes a `MANIFEST.json`; batch 1 and batch 2 are started and their commands, log paths and `STATUS.json` paths recorded in the sprint report (PRD AC-2.4 precondition)
- [x] AC-1.9 A dated plan with an untagged task fails `--type sprint`; this plan passes; the spec-axis lines exist in `reviewing-code/SKILL.md` within budget and an eval fixture for a `mechanical` task shipped as prose is added under `evals/tasks/review-recall/` (not run in CI); `cycle-ratio.sh` prints both lines on a fixture (PRD AC-10.1 … AC-10.3)
- [x] AC-1.10 The two rule files carry `paths:` frontmatter and each glob matches at least one tracked file of the intended kind (lint); the hazard crosswalk is in the sprint report with the unmechanised hazards named; the harness observation is recorded; `no-history-in-rule-text.bats` and `check-prompt-budget.sh` stay green (PRD AC-3.1)
- [ ] AC-1.13 Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; the toolchain readiness check is recorded
- [x] AC-1.11 The workflow comment states 160,000 / 114,688 B; `implementing-tasks/SKILL.md:28` agrees with `:76`
- [x] AC-1.12 The KF-041 entry's Upstream issue field names the filed issue

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 1.0, 1.6 (start the detached batches), 1.10, 1.11 | main checkout | the only writer of the ledger, `CHANGELOG.md`, REPO-MAP and `checksums.json` |
| A (Opus 5.5) | 1.1, 1.2, 1.3 | `../loa-wt-s1a` | owns `guard-origins.yaml`, `floor.yaml`, `guard-yield.sh`, `loa-status.sh` Guards line, `hooks-reference.md` markers |
| B (Opus 5.5) | 1.4, 1.5, 1.6 (scripts) | `../loa-wt-s1b` | owns `evals/**`; hands the lead the exact `run-arms.sh` command |
| C (Opus 5.5) | 1.7, 1.8, 1.9 | `../loa-wt-s1c` | owns `validate-artifact.sh`, the sprint template, `reviewing-code/SKILL.md`, the two rule files, the workflow comment, `implementing-tasks/SKILL.md:28` |

Sequencing: B's 1.4 and 1.6 scripts land first so batch 1 of the arm run starts mid-sprint (D37); A's 1.1 before 1.2 before 1.3; C's tasks are independent. Non-patch side effects (starting the detached run, filing the issue) are lead steps, not implementer deliverables.

### Technical Tasks
- [x] Task 1.0: Toolchain readiness check recorded in the sprint report (yq v4, jq, bats, Python test deps, Node and vitest, the Fable 5.1 executor route for `run-arms.sh`, the record branches fetched) → **[G-2]** ⇐ none · kind: mechanical
- [x] Task 1.1: Seed `.claude/data/guard-origins.yaml` for all registered hooks, fence ids, validator rules and gates (origins from the inventory cites, the KF ledger and `git log --follow`; floor rows marked) and create `.claude/data/floor.yaml` (floor guard ids and config keys, the one source the floor tests read) → **[G-1]** ⇐ none · kind: judgment
- [x] Task 1.2: Write `guard-yield.sh` (hook enumeration against the canonical command schema with registrations, `# @guard fence:<id>` markers added above every `emit_block` site and cross-checked, `# @guard validator:<id>` markers added to `validate-artifact.sh`, the fixed gate list; 30-day join over `audit.jsonl` and rotated segments with replay exclusion and the FP heuristic; structural tracked `guards.md`; untracked `.run/guard-yield.md` and `.json`; `--hooks-table` markers; whole-file `--check`; `--json`) with `tests/unit/guard-yield.bats` over a fixture audit log and segment → **[G-1]** ⇐ 1.1 · kind: mechanical
- [x] Task 1.3: Add `tests/unit/guard-origins.bats` (hooks, fence ids, validator markers, gate scripts, floor set from `floor.yaml`, dormant knobs, sha256 pin), `tests/unit/floor-snapshot.bats` (the floor files and corpus rows named in `floor.yaml` are byte-identical to `origin/main`), the `guard-register` markers and generated table in `hooks-reference.md`, the `/loa` Guards line reading `.run/guard-yield.json`, and the `--check` step in the Shell Tests job → **[G-1]** ⇐ 1.2 · kind: mechanical
- [x] Task 1.4: Declare `ab.arms` by canonical id (`baseline`, `no_companion` marked informational, `no_karpathy` with its scope stated, `no_rule_files`; audit `no_audit_delta`) and the `ab.threshold` block in both recall suites; implement arm toggles in `execute-agent.sh` on the sandbox copy (including `constraints.json` for the Karpathy toggle); add `report.sh --arms` with mean/min/max/spread, the bootstrap interval, missed labels, the `no recall loss` / `recall loss` / `inconclusive` verdict and `--partial`; extend `recall-baseline-freshness.bats`; add `evals/tests/arm-toggles.bats` asserting absence at executor start → **[G-2]** ⇐ none · kind: mechanical
- [x] Task 1.5: Write `evals/harness/seed-corpus-from-record.sh` (fix-touches-file label rule, `label_source` including `fix` rows from the fix hunks, `# approved-by` header); generate fixtures `pr-11` … `pr-18` (`pr-09` and `pr-10` already exist as clean controls) from the round-1 commits of sprints 247–254 and the record branches; curate `must_match` anchors and approve each `labels.tsv`; extend `corpus.tsv` and `SHA256SUMS`; add `evals/tests/seed-corpus.bats` → **[G-2]** ⇐ none · kind: judgment
- [x] Task 1.6: Write `evals/harness/run-arms.sh` (detached worktree pinned at `--source-commit 864069f2`, executor pinned to Fable 5.1, `--fixtures` batches, three trials interleaved across arms, one retry per transport failure, a `MANIFEST.json` with source and harness commits, model id, executor config, fixture `SHA256SUMS` verified before each run and environment metadata, `STATUS.json` with `running|complete|partial|failed`, `source_commit` and `model_id` in every result row, results under `evals/results/arms/`), extend `compare.sh --ab` to refuse mixed source commits; the lead starts batch 1 (`pr-01` … `pr-08`) as soon as 1.4 and this task land and batch 2 (`pr-11` … `pr-18` (`pr-09` and `pr-10` already exist as clean controls)) when 1.5 lands, detached with the logs outside the scratchpad, and records both commands, log paths, the estimated duration (288 runs at about three minutes each, concurrency 2, roughly seven hours) and the M1 exit criterion in the sprint report → **[G-2]** ⇐ 1.4 · kind: mechanical
- [x] Task 1.7: Add the `kind:` rule to `validate-artifact.sh --type sprint` (`KINDS_REQUIRED_FROM=2026-10-14`, Date-header rules, E2E block covered, single-token parser, trailing-prose violation, judgment-tag WARN), the template line, the `reviewing-code` spec-axis lines (bytes taken from the named duplicated include sentence, recorded in the report), `tools/cycle-ratio.sh` (kind counts and volume lines with provenance), the three glossary entries, and bats for both → **[G-9]** ⇐ none · kind: mechanical
- [x] Task 1.8: Add `paths:` frontmatter to `stash-safety.md` and `skill-invariants.md`; write the hazard-to-mechanism crosswalk into the sprint report naming hazards with no mechanical check; record the harness observation that the rule files load on a matching turn and not on a non-matching one; point the FR-1.2b block message at the rule file; keep `no-history-in-rule-text.bats` green → **[G-3]** ⇐ none · kind: mechanical
- [x] Task 1.9: Fix the prompt-budget workflow comment and `implementing-tasks/SKILL.md:28`; add a one-line test or grep lint pinning the workflow comment to the script's constants → **[G-4]** ⇐ none · kind: mechanical
- [x] Task 1.10: File the KF-041 upstream issue on 0xHoneyJar/loa with `gh issue create` under the session's existing `gh` authentication (the maintainer's end-to-end instruction and DEC-0134 are the authorisation; if `gh` is unauthenticated the issue body is written to `a2a/sprint-255/kf-041-issue.md` and the gap stated), with the shape, recurrences and candidate fix; record the URL in the KF entry via `kf-write-lib.sh attempt` and the Upstream field → **[G-4]** ⇐ none · kind: judgment
- [x] Task 1.11: CHANGELOG `[Unreleased]` entries for Sprint 1; the always-on prose baseline recorded in the sprint report with its measuring command (`wc -c` of the kernel, the project `CLAUDE.md` and the unscoped rule files); REPO-MAP regenerated with its checksum; `checksums.json` refreshed; `sync-fixtures.sh --check` green → **[G-1]** ⇐ 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10 · kind: mechanical

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `guard-yield.sh` over a fixture audit log and fixture origin map | replay exclusion, FP heuristic, header counts, drift `--check` | the heuristic's false negatives on novel command shapes | `tests/unit/kf-write-lib.bats` (fixture-copy pattern) |
| `.claude/settings.json` ↔ `guard-origins.yaml` | a registered hook or fence id with no origin row | validator rules not listed in the map | `tests/unit/user-invoked-commands.bats` (allowlist ⇄ files) |
| `execute-agent.sh` arm toggles on a sandbox tree | a toggle that leaves text or config behind | prompt-cache effects on the live executor | `evals/tests/execute-agent.bats` |
| `seed-corpus-from-record.sh` on a fixture record tree | malformed labels, secrets, missing commits | label quality (human curation) | `evals/tests/eval-recall-grader.bats` |
| `compare.sh --ab` with skewed model ids | cross-model comparison | — | `evals/tests/recall-baseline-freshness.bats` |
| `validate-artifact.sh --type sprint` on dated fixtures | untagged task on a dated plan; WARN before the date | kinds that are wrong but present | the Seams gate tests (cycle-128) |
| `cycle-ratio.sh` on a fixture repo | wrong counts, missing MODELINV window | — | new |

### Dependencies
- The record branches `record/cycle-126-a2a`, `record/cycle-127-a2a`, `record/cycle-128-a2a` reachable (`git fetch origin 'refs/heads/record/*'`)
- `.run/audit.jsonl` on this host (gitignored) for the live register; fixtures for the tests
- yq v4, jq, bats, Opus 5.5 executor for `run-arms.sh`

### Security Considerations
- Nothing from a command string enters `guards.md` or the hooks table: ids are validated against `^[A-Za-z0-9._/-]+$`, origins come from the tracked map, counts are integers.
- Labels carry control-stripped finding titles only and pass `no-secrets.sh`; `head.diff` is generated from tracked commits.
- Path-scoping removes no rule text; FR-1.2b stays as a fence.
- The register never disables anything.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Origins unknown for old hooks | Med | Low | `origin: {kind: design, ref: <first commit>}` from `git log --follow`; never empty |
| Record branches lack a round-1 feedback file for a sprint | Med | Med | the fixture names the files it found; a sprint with no accepted findings is dropped and the gap stated |
| Arm run too slow or provider-limited | High | Med | detached driver; D-2.4 fallback governs Sprint 2 |
| `reviewing-code/SKILL.md` over budget after the spec-axis lines | High | Low | shed equal bytes in the same change; budget check in the task |

### Success Metrics
- `guard-origins.bats`, `guard-yield.bats`, `floor-snapshot.bats`, `arm-toggles.bats`, `seed-corpus.bats`, `validate-artifact-sprint-kinds.bats`, `cycle-ratio.bats` green; every existing bats, pytest, vitest and fence-corpus suite green
- `guards.md` rows = enumerated guards; zero without origin
- At least six record fixtures with labels; both arm batches started with manifests
- Review and audit APPROVED; COMPLETED marker

---

## Sprint 2: Inert controls retired or repaired, file-authoritative run position, heredoc false positives, profile knob, prose diet

**Global ID:** 256 · **Epic:** bd-hjlv · **Beads:** bd-kw5x3, bd-j7xkt, bd-fr2i7, bd-k9z94, bd-f59yy, bd-5t8wm, bd-9p6o0, bd-288up, bd-ont7r

### Sprint Goal
Every documented control runs, is telemetry, or is gone; run position comes from files; the fence stops blocking prose; one knob sets the optional surfaces and cannot reach the floor; the kernel is thinned where the arms allow.

### Deliverables
- `implement_gate.mode` `telemetry | ask | deny`, documented, this repo on `deny`; `implement-gate.bats` (D-4.1)
- `disallowed-tools` on the four pure-review skills; lint row (D-4.2)
- Per-task surgical-diff state and summary; review SURGICAL axis line (D-4.3)
- Guardrails and danger level off in the example and this repo (D-4.4)
- C-TEAM rows out of `constraints.json`; generator and lint updated; agent-teams reference section (D-4.5)
- `run-checkpoint.sh record-round` and `derive --write`; run-mode SKILL breaker prose replaced by the call; jack-out writes `.state`; `/loa` and `run-resume` drift line; bats (D-4.6, D-5.1 … D-5.4)
- Heredoc consumer classifier; corpus B- and D-rows; latency within budget (D-6.1, D-6.2)
- `.claude/data/profiles.yaml`, `profile-lib.sh`, knob readers, `profile-floor.bats`, `/loa` Profile line (D-9.1 … D-9.3)
- Kernel rows to pointers, prose-only rows to `.claude/protocols/process-compliance.md`, `LOA_LIMIT` lowered; or the D-2.4 fallback stated (D-3.2, D-3.3)
- CHANGELOG; REPO-MAP; checksums

### Acceptance Criteria
- [x] AC-2.1 `implement-gate.bats` covers the matrix mode × claims × write class × sanction state: `deny` returns a deny decision only for an unsanctioned App-Zone write; derived RUNNING, a fresh marker and the override sanction with a logged row each; a stale marker does not; `telemetry` writes one row and prints nothing; `ask` unchanged; trust-input writes ask in every cell (PRD AC-4.1)
- [x] AC-2.2 A pure-review skill without the strip fails `skill-capabilities.bats`; the four skills carry it (`rtfm-testing` writes a State-Zone report, so it keeps `Write` and strips `Edit` and `NotebookEdit`; as-built per the sprint-256 report); `skill-invariants.md` names the Bash gap (PRD AC-4.2)
- [x] AC-2.3 The surgical-diff counter resets when the checkpoint task changes and keys on the session id when no task is active; the summary file exists after a write; the state directory is bounded (PRD AC-4.3)
- [x] AC-2.4 The example's effective value under `standard` is `false` for both guardrail keys (the raw keys appear commented in the example because `loa.profile` governs them; review round 2 HIGH-2); this repository reads `guardrails.input.enabled: true` and `danger_level.enforce: false`; the orchestrator tests pass with the knob on; the CHANGELOG carries the migration notes (PRD AC-4.4)
- [x] AC-2.5 `constraints.json` has no C-TEAM rows; the kernel regenerates without the Agent Teams table; the reference states the rules and the arming variable; the three team hooks are `dormant` in the register (PRD AC-4.5)
- [x] AC-2.6 `record-round` increments `cycle_count.current`, sets `same_issue.last_hash`, appends `history` on a trip and writes `OPEN` and `HALTED`; `derive` over a fixture a2a directory recomputes the counters from the feedback history (PRD AC-4.6)
- [x] AC-2.7 `run-checkpoint-derive.bats` has one case per decision-table row: the drift fixture derives to the file-derived state; a stale marker whose trailer names another sprint does not count; terminal states are never moved back to RUNNING; each known reader has a fixture case; `run_mode.file_authoritative: false` makes `derive` report-only; the jack-out step writes `.state` (PRD AC-5.1 … AC-5.4)
- [x] AC-2.8 `run-corpus.sh` green with the new rows; no D-row removed; the recorded prose cases allow; every interpreter, wrapper, substitution, same-line-execution and unlisted-consumer D-row blocks; the knob off reproduces today's results; p95 under 80 ms (PRD AC-6.1, AC-6.2)
- [x] AC-2.9 `profile-lib.bats`: explicit key beats profile beats fallback; `standard` equals the post-cycle example defaults listed in `profiles.yaml`; `profile-floor.bats` passes under `lean`; `/loa` prints the profile and overrides (PRD AC-9.1 … AC-9.3)
- [x] AC-2.10 Always-on prose ≤ 12 KB per turn or the D-2.4 fallback is stated in the sprint report with the inconclusive arm named and no row deleted; `check-prompt-budget.sh` green at `LOA_LIMIT = min(current, measured + 256 B)`; every changed row listed with its class (review-affecting, mechanism, behavioural) and its evidence (arm verdict and missed-label reading, pointer, or proposed DEC row) (PRD AC-3.2, AC-3.3)
- [x] AC-2.11 `implement_gate.mode` and the new keys are documented in the example with a config-key table in the report; the hooks reference describes the gate as a fence only under `deny`; this repository still reads `ask` at sprint end
- [ ] AC-2.12 After each patch apply the fence corpus and the hook bats were run before the next tool call relied on them, recorded in the report; every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 2.8 (last), 2.9, each apply's smoke run | main checkout | after every patch apply the lead runs the fence corpus and the hook bats before the next tool call relies on them (D34); recovery: `git show HEAD:<hook> > <hook>`, knob off |
| D (Opus 5.5) | 2.10, 2.5, 2.1 | `../loa-wt-s2a` | owns `run-checkpoint.sh`, `implement-gate.sh`, `loa-status.sh` Run and gate-mode lines, the run-mode skill prose, `implementing-tasks` and `bug-triaging` marker lines |
| E (Opus 5.5) | 2.6 | `../loa-wt-s2b` | owns `block-destructive-bash.sh`, the fence corpus, the hooks-reference heredoc semantics section |
| F (Opus 5.5) | 2.2, 2.3, 2.4, 2.7 | `../loa-wt-s2c` | owns the four SKILL.md files, `karpathy-surgical-diff-check.sh`, `constraints.json` and its generator, `profiles.yaml`, `profile-lib.sh`, the example config and this repo's config (D's and E's config snippets are handed to F), `loa-status.sh` Profile line (applied after D's patch) |

Sequencing: D's 2.10 lands before 2.1 (the gate reads the derived cache); F's 2.4 before 2.7 (`standard` lists the final defaults); 2.8 is the last task and reads `STATUS.json` at its start; the `deny` flip for this repository is **not** part of 2.1: it happens in the cycle's last commit after the E2E validates the derived cache against the live run (D34).

### Technical Tasks
- [x] Task 2.1: Implement `implement_gate.mode` `telemetry` and `deny` as opt-ins in `implement-gate.sh` (`ask` stays the default and now logs a row) with the sanction paths (derived RUNNING with a fresh `derived_at`, fresh `.run/implement-active.json` written and removed by `implementing-tasks` and `bug-triaging` which also run `derive --write` before their first App-Zone write, `LOA_IMPLEMENT_GATE_OVERRIDE`), the unknown-position fallback to `ask`, the tighten-only claim modifier, one compliance row per path; document the keys; leave this repo on `ask` until the cycle-end flip; extend `implement-gate.bats` to the full matrix including cache states → **[G-4]** ⇐ 2.10 · kind: mechanical
- [x] Task 2.2: Add `disallowed-tools: Write, Edit, NotebookEdit` to `eval-running`, `flatline-knowledge`, `rtfm-testing`, `validating-construct-manifest` after a grep proves none of their documented workflows has a Write or Edit step; add the lint row to `validate-skill-capabilities.sh` and `skill-capabilities.bats`; name the Bash gap in `skill-invariants.md`; record a live harness probe in the sprint report (fall back to a read-only `allowed-tools` set if the key is not enforced) → **[G-4]** ⇐ none · kind: mechanical
- [x] Task 2.3: Rework `karpathy-surgical-diff-check.sh` to key on the checkpoint task (sanitised, session id when none), rotate per-task state under `.run/karpathy-surgical/`, delete the legacy state file on first run, write `karpathy-surgical-summary.json`; add the SURGICAL axis line to `reviewing-code/SKILL.md` (byte-neutral); add `karpathy-surgical-diff.bats` → **[G-4]** ⇐ none · kind: mechanical
- [x] Task 2.4: Default guardrails and danger level off in the example; set this repo to `enabled: true`, `enforce: false`; remove C-TEAM-001 … 005 from `constraints.json`; make `generate-constraints.sh` omit the Agent Teams table when the class is empty; update `lint-invariants.sh` and its test; add the rules and arming note to `agent-teams-reference.md`; mark the three team hooks `dormant` in the origin map → **[G-4]** ⇐ none · kind: mechanical
- [x] Task 2.5: Add `record-round` to `run-checkpoint.sh` (same-issue hash from the derived verdict, no-progress, cycle count, timeout; trip writes `OPEN` and `HALTED` and prints the trip line); replace the run-mode SKILL breaker prose with the call; add `run-checkpoint-record-round.bats` → **[G-4]** ⇐ none · kind: mechanical
- [x] Task 2.10: Add `derive [--json] [--write]` to `run-checkpoint.sh` (decision table D-5.1a, commit selection constrained to the cycle, terminal and sticky states, schema tolerance, breaker recomputed from the feedback history, `run_mode.file_authoritative` knob); call `derive --write` from `write`; fix the jack-out step to write `.state`; add the drift line to `/loa` (report-only) and `derive --write` on drift to `run-resume`; print the effective gate mode in `/loa`; add `run-checkpoint-derive.bats` with one case per table row and per reader → **[G-5]** ⇐ none · kind: mechanical
- [x] Task 2.6: Implement the fail-closed heredoc consumer classifier in `block-destructive-bash.sh` behind `destructive_command_guard.heredoc_classifier` with a stated grammar (interpreter and wrapper lists, substitution and variable-command detection, same-line execution rule, executable-extension and shebang rule, redirect targets under hook, settings, rc, PATH or `.git/hooks` locations treated as interpreter-class, exact-form non-executing allowlist with safe-flag checks, per-segment body scan with wrapper-prefix stripping, full scan for unlisted consumers, nested heredocs, variable-expanded delimiters, control characters and parse failures; CRLF normalised); add the B-rows and the complete D-row list to `corpus.jsonl` (including `echo ok && rm`, `; rm`, `\rm`, `/bin/rm`, `command rm`, `exec rm`, `sudo rm`, `x=rm; $x`, `$(rm)`, backticks, `eval`, `awk system()`, `sed e`, `make -f -`, `env python`, `find -exec`, `.sh`-target and shebang bodies, nested and variable-delimiter heredocs, a `tee` into `.claude/hooks/`); record the semantics in the hooks reference; keep `run-corpus.sh` green within the latency budget and prove the knob off reproduces today's results → **[G-6]** ⇐ none · kind: mechanical
- [x] Task 2.7: Capture `tests/fixtures/profiles/standard-oracle.json` (today's effective knob values, before any reader changes); add `.claude/data/profiles.yaml` (every profile defines every key; `standard` written out as the post-cycle example defaults; no pacing key) and `.claude/scripts/lib/profile-lib.sh` with the mtime-keyed `.run/effective-config.json` cache; route every knob reader through `loa_knob` and add the grep lint for direct reads; add `profile-lib.bats` (oracle comparison) and `profile-floor.bats` (reads `floor.yaml`, sha256-pinned); add `kind: policy` rows to the register; add the `/loa` Profile line; document `loa.profile` → **[G-8]** ⇐ 2.4 · kind: mechanical
- [x] Task 2.8: Read `STATUS.json` and the per-arm verdicts in `evals/results/arms-report-*.md`; classify every candidate kernel row (review-affecting: needs its arm's `no recall loss` verdict and the lead's missed-label reading; mechanism-describing: shrink to a pointer; behavioural prose-only: move to `.claude/protocols/process-compliance.md` with a kernel pointer and a proposed DEC row each, the register as the instrument); lower `LOA_LIMIT` to `min(current, measured + 256 B)`; list every change with its class and evidence, or state the D-2.4 fallback naming each inconclusive arm and the deferral bead (no row deleted, cap unchanged) → **[G-3]** ⇐ 2.4, 2.10 · kind: judgment
- [x] Task 2.9: CHANGELOG `[Unreleased]` entries for Sprint 2 with the migration notes (guardrails defaults, C-TEAM rows removed, new gate modes) and the rollback keys; a config-key table in the sprint report (each new key: documented default, validation, one reader test); the apply-time smoke results and the recovery step; hooks-reference wording for the gate modes; REPO-MAP regenerated; `checksums.json` refreshed; `sync-fixtures.sh --check` green → **[G-4]** ⇐ 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.10 · kind: mechanical

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `implement-gate.sh` stdin payload → stdout decision and audit row | wrong decision per mode, missing telemetry row, trust-input regression | the live harness's handling of `deny` | `tests/unit/implement-gate.bats` |
| `validate-skill-capabilities.sh` over fixture SKILL.md files | pure-review skill without the strip | — | `tests/unit/skill-capabilities.bats` |
| `karpathy-surgical-diff-check.sh` with a fixture checkpoint | counter not reset on task change; unbounded state | reviewer ignoring the summary | new, fixture pattern from `implement-gate.bats` |
| `generate-constraints.sh` on a `constraints.json` without C-TEAM | table still emitted; lint breakage | — | `tests/unit/lint-invariants.bats` |
| `run-checkpoint.sh record-round` on fixture feedback files | counts, hash reset, trip, HALTED write | a forged trailer | new |
| `run-checkpoint.sh derive` on a fixture `.run` + `a2a` + ledger | drift resolution, stale marker, terminal states | a marker and trailer forged together with the right sprint id | new |
| fence corpus `run-corpus.sh` | a D-row that stops blocking; a B-row that blocks; latency | commands outside the corpus | `tests/fixtures/fence-corpus/` |
| `profile-lib.sh` with fixture configs | precedence errors; `standard` drift from today | — | new |
| `profile-floor.bats` | a floor key in `profiles.yaml`; a floor surface that changes under `lean` | — | new |
| `check-prompt-budget.sh` at the lowered cap | kernel growth past the diet | — | `.github/workflows/check-prompt-budget.yml` |

### Dependencies
- Sprint 1's `run-arms.sh` results for Task 2.8 (fallback D-2.4 if absent)
- Sprint 1's `guard-yield.sh` (the gate telemetry rows feed the register)

### Security Considerations
- FR-4(a) is tighten-only: `deny` adds a refusal; no mode grants an allow the heuristic did not.
- FR-6 loosens only for non-executing consumers; the interpreter list is explicit; parse failure scans the whole body; FR-1.2b, the SZ rules and the deny list are untouched and pinned by D-rows.
- Profiles cannot name a floor key; the test reads the data file.
- The derivation never moves a terminal state to RUNNING; the implement gate reads the cache, so a forged cache is no worse than today and a derived cache is better.
- Telemetry rows carry control-stripped paths cut to 256 bytes; no command text.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Arm results absent at Task 2.8 | High | Med | D-2.4 fallback; path-scoping and pointers ship; deletions deferred by bead |
| Fence classifier opens a hole | Med | High | explicit interpreter list, fail-closed parse, new D-rows, two-step form fenced at the second command |
| Knob readers missed by Task 2.7 | Med | Low | grep lint for direct `yq` reads of the profile keys |
| Kernel regeneration changes unrelated rows | Low | Med | diff reviewed; `check-glossary-terms.sh` and budget green |

### Success Metrics
- All Sprint 2 bats and the fence corpus green; p95 under 80 ms; every existing bats, pytest, vitest and fence-corpus suite green
- `.run/circuit-breaker.json` counts a changes-required round in the fixture run
- `.run/guard-yield.json` regenerated shows the gate ask and telemetry rows
- Apply-time smoke runs recorded; this repository still on `ask`
- Review and audit APPROVED; COMPLETED marker

---

## Sprint 3 (Final): Advisory open-weight voices, local_voices posture, Bridgebuilder banner, E2E

**Global ID:** 257 · **Epic:** bd-9m8z · **Beads:** bd-cvb31, bd-irz7s, bd-xkbtg, bd-0piaj, bd-0luav, bd-5h8t9, bd-wl4gd

### Sprint Goal
An operator can declare a local or hosted open-weight model and have it serve as an advisory voice whose findings reach the reviewer and never change a verdict; a local posture refuses hosted hops and says what it costs; the Bridgebuilder banner and exit code tell the truth; every goal is validated end to end.

### Deliverables
- Example config: Azure block loads; local provider block; `allow_insecure_endpoint`; `keyless`; `secret_env_allowlist` note; `tests/test_config_examples_load.py` (D-7.1)
- `endpoint-validator.py` and `model-health-probe.sh --provider <name>` per-provider opt-in; cheval Python path agreement; `tests/test_endpoint_validator_optin.py` (D-7.2)
- Chat-completions `response_format`, `schema_enforced` truth, `reasoning_content` and `<think>` stripping, `thinking_stripped`; pytest (D-7.3)
- `advisory_voices` in `adversarial-review.sh`; envelope block; promotion refusal; catalog-priced budget gate; `price_source`/`price_date` provenance test; bats (D-7.4, D-7.6)
- Bridgebuilder keyless providers; banner completed/planned; exit 3 on DEGRADED; callers updated; vitest (D-7.5, D-7.7)
- `hounfour.locality: local_voices` across dissent, Flatline and Bridgebuilder; MODELINV `locality`; docs sentence; bats and vitest (D-8.1, D-8.2)
- Docs: example blocks, multi-model reference, hooks and scripts references, README what's-new, release-notes ratio line, CHANGELOG with Migration; REPO-MAP; checksums
- `grimoires/loa/a2a/sprint-257/e2e.md` with G-1 … G-9 evidence

### Acceptance Criteria
- [x] AC-3.1 The example config loads with the fixed Azure block and the local block; an `http` endpoint on a public host and an `allow_insecure_endpoint` naming a public host or given as a boolean fail at load with a named reason; one provider's opt-in leaves another provider's refusals intact on both the bash and the Python path (PRD AC-7.1)
- [x] AC-3.2 pytest: the chat body carries `response_format` json_schema for a `structured_json` entry and `schema_enforced` is true only then; `<think>` and `reasoning_content` are stripped before qualification and `thinking_stripped` recorded; a prompt over the declared `context_window` refuses the hop with a named reason and a MODELINV row; MODELINV rows carry `destination` (PRD AC-7.2, AC-7.5)
- [x] AC-3.3 bats (mock mode): an advisory voice's findings are present only under `advisory_voices[].findings` with `duplicate_of` links; `jq -S 'del(.advisory_voices)'` of the envelope and the `verdict-derive.sh --json` output are byte-identical with and without the advisory voice; a promotion attempt is refused by name (PRD AC-7.3)
- [x] AC-3.4 Bridgebuilder accepts a keyless provider from the trusted config source, refuses a head-only declaration by name and still refuses an undeclared provider; the banner prints completed/planned; a DEGRADED verdict exits 3 (or 0 under the rollback key) and every enumerated caller surfaces it; the probe uses the configured endpoint and honours the host-string opt-in (PRD AC-7.4)
- [x] AC-3.5 The budget gate reads the catalog price and logs the fallback; a zero-priced entry estimates zero and is logged; a non-zero open-weight price without provenance fails the catalog test (PRD AC-7.5)
- [x] AC-3.6 Under `local_voices`: no hosted hop in the inventory is planned, each refusal named; the repair chain stays on the declared providers; MODELINV rows carry `locality`; the DEGRADED sentence is present in config and output; the session-exempt sentence is in the docs (PRD AC-8.1 … AC-8.3)
- [x] AC-3.7 The release-notes report carries the script / prose / model-call ratio line for this cycle (PRD AC-10.3)
- [x] AC-3.8 `e2e.md` records a PASS or a stated exception for G-1 … G-9

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 3.6, 3.E2E, the cycle-end `deny` flip | main checkout | owns the docs, CHANGELOG, REPO-MAP, `checksums.json`, this repo's config |
| G (Opus 5.5) | 3.1, 3.2 | `../loa-wt-s3a` | owns `loa_cheval/**`, `endpoint-validator.py`, `model-health-probe.sh`, the example config blocks (hands snippets to the lead) |
| H (Opus 5.5) | 3.3, 3.5 | `../loa-wt-s3b` | owns `adversarial-review.sh`, `flatline-orchestrator.sh`, the catalog, the review and audit skills' advisory sentence |
| I (Opus 5.5) | 3.4 | `../loa-wt-s3c` | owns `bridgebuilder-review/**` and the two callers; H's `config.ts` locality change is handed to I |

Sequencing: G's 3.2 before H's 3.3; I's 3.4 and H's 3.3 before 3.5; everything before 3.6 and the E2E. The locality and advisory keys are not profile keys and are read directly from the config, not through `loa_knob`.

### Technical Tasks
- [x] Task 3.1: Fix the Azure example and add the local provider example; implement `allow_insecure_endpoint` as an IP-literal-or-`localhost` loopback/RFC1918 host string in `endpoint-validator.py`, `model-health-probe.sh --provider <name>` and the cheval Python path, with public-host, link-local, metadata, DNS-name, mismatched-host and boolean refusals, redirect refusal, proxy-env bypass and path-prefix enforcement for opted-in providers, and the keyless-provider preconditions; add `test_config_examples_load.py` and `test_endpoint_validator_optin.py` covering the D-7.2 test list → **[G-7]** ⇐ none · kind: mechanical
- [x] Task 3.2: Add `response_format` json_schema to `_build_chat_body` for `structured_json` entries with `schema_enforced` derived from the body and one retry without the schema on a server 400 (`schema_rejected_by_server`); handle `reasoning_content` deltas in `openai_streaming.py`; strip `<think>` blocks before qualification with `thinking_stripped` in MODELINV; refuse an over-`context_window` hop with a named reason and a `context_window_refused` MODELINV row; record `destination` in every MODELINV row; add `test_openai_chat_schema.py`, `test_openai_thinking_strip.py`, the over-window pytest and a stub OpenAI-compatible server test for streaming end to end → **[G-7]** ⇐ none · kind: mechanical
- [x] Task 3.3: Implement `advisory_voices` in `adversarial-review.sh` (concurrent run under `advisory_timeout_seconds`, findings written only under `advisory_voices[].findings` with `duplicate_of` links, byte-identical top-level findings and verdict, one reading sentence in the review and audit skills, promotion refusal naming the missing voice arm), the catalog-priced budget gate summing every voice with logged fallback, `open_weight`/`price_source`/`price_date` in the catalog schema with a 90-day `price_date` freshness WARN and `test_catalog_pricing_provenance.py`; add `adversarial-review-advisory.bats` and `adversarial-review-budget.bats` → **[G-7]** ⇐ 3.2 · kind: mechanical
- [x] Task 3.4: Extend Bridgebuilder `config.ts` with keyless providers read only from trusted configuration (the base branch's config or repository settings on a pull request; a head-only keyless or insecure provider is refused by name) and still refusing undeclared providers; pass completed/planned to `reportComplete`; exit 3 on DEGRADED behind `bridgebuilder.exit_on_degraded` (default 3, `0` restores today); enumerate every Bridgebuilder invocation by grep (scripts, workflows, docs) and update each caller to accept 3 as completed-degraded; vitest for each including the head-only refusal → **[G-7]** ⇐ none · kind: mechanical
- [x] Task 3.5: Implement `hounfour.locality: local_voices` over the hop inventory in `adversarial-review.sh` (plan-time refusal, pinned repair chain, advisory voices), `flatline-orchestrator.sh`, Bridgebuilder `config.ts` and the health probe, with the canonical keys (`keyless`, `dispatch_group: local`) and the request-time rules of D-7.2 applied to every local hop (no DNS, redirects refused, proxy env ignored, endpoint address logged); add `locality_mode` and `hop_locality` to MODELINV rows; state the unchanged gate behaviour under `DEGRADED_SECURITY_REVIEW`; write the DEGRADED sentence in config and audit output and the session-exempt sentence in the docs; add `adversarial-review-locality.bats`, `flatline-locality.bats` and the vitest case → **[G-7]** ⇐ 3.3, 3.4 · kind: mechanical
- [x] Task 3.6: Docs: example config blocks (with the marker convention `test_config_examples_load.py` uses), `multi-model-reference.md`, hooks and scripts references, README what's-new, CHANGELOG `[Unreleased]` with Migration notes and the rollback keys, the release-notes kind-count and volume lines via `cycle-ratio.sh`, glossary entries; a config-key table in the sprint report (each new key: documented default, validation, one reader test); tests for the three new `/loa` lines; REPO-MAP regenerated; `checksums.json` refreshed; `sync-fixtures.sh --check` green → **[G-7, G-9]** ⇐ 3.1, 3.2, 3.3, 3.4, 3.5 · kind: mechanical

### Task 3.E2E: End-to-End Goal Validation
- [x] Task 3.E2E: Validate every PRD goal on the integrated tree and write `grimoires/loa/a2a/sprint-257/e2e.md` → **[G-1, G-2, G-3, G-4, G-5, G-6, G-7, G-8, G-9]** ⇐ 3.6 · kind: judgment

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Every guard carries origin and yield | `guard-yield.sh --check`; `bats tests/unit/guard-origins.bats`; count rows vs enumerated guards | exit 0; zero rows without origin; counts equal |
| G-2 | The control run exists and runs | `run-arms.sh --dry-run`; `report.sh --arms` on the results present | arms listed; report names recall per arm or the D-2.4 fallback |
| G-3 | Always-on prose ≤ 12 KB, no recall loss | measure bytes of the kernel, project CLAUDE.md and unscoped rules; read the arms report | ≤ 12 KB, or fallback stated with the missing arm |
| G-4 | No documented control fails to run | run the FR-4 bats; grep the hooks reference for the gate wording | all green; wording matches the modes |
| G-5 | Run position derives from files | `bats tests/unit/run-checkpoint-derive.bats`; `record-round` fixture | drift resolves; counters move |
| G-6 | Heredoc false positives removed, corpus intact | `run-corpus.sh`; diff D-rows against `main` | green; no D-row removed; p95 < 80 ms |
| G-7 | Advisory and local voices with an honest posture | `adversarial-review-advisory.bats`, `-locality.bats`, pytest, vitest; one non-gating smoke run of an advisory voice against a local OpenAI-compatible server if one is present on the host, else a stated exception | all green; envelope unchanged; refusals named; smoke outcome recorded |
| G-8 | One profile knob that cannot reach the floor | `bats tests/unit/profile-floor.bats`; `/loa` under `lean` via `LOA_STATUS_CONFIG_FILE` pointing at a fixture config (this repo's config untouched) | green; profile printed |
| G-5a | The derived cache matches the live run (gate flip precondition) | `run-checkpoint.sh derive --json` on this run's `.run` and a2a tree compared with the cache; then the repo flips `implement_gate.mode` to `deny` in the cycle's last commit (D34) | no drift; flip recorded |
| G-9 | Task kinds and the ratio line | `validate-artifact.sh --type sprint --file grimoires/loa/sprint.md`; `cycle-ratio.sh` on the cycle range | exit 0; ratio line present in the release notes |

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| cheval config loader over the example's commented blocks | the Azure defect class; a block that does not load | server-side behaviour | `.claude/adapters/tests/test_loader_*.py` |
| `endpoint-validator.py` and the Python path with fixture configs | opt-in leaking to another provider; loopback refused when opted in | DNS rebinding | `tests/unit/endpoint-validator.bats` |
| `_build_chat_body` and the streaming assembler with fixture responses | missing `response_format`; `schema_enforced` lie; `<think>` leakage | a server that ignores `response_format` | `test_openai_adapter_*.py` |
| `adversarial-review.sh` in `FLATLINE_MOCK_MODE` with an advisory voice | envelope changed; tags missing; promotion accepted without config | real-model output quality | `tests/unit/adversarial-review-schema-enforced.bats` |
| budget pre-check with fixture catalog prices | fixed-rate fallback unlogged; unknown price mishandled | — | `tests/unit/adversarial-review.bats` |
| catalog pytest invariant | open-weight price without provenance | — | `test_anthropic_catalog_floor.py` |
| Bridgebuilder `config.ts`, `progress.ts`, `main` exit under vitest | unknown-provider refusal of a keyless provider; configured-vs-completed count; exit 0 on DEGRADED | the live PR comment path | `__tests__/progress.test.ts`, `__tests__/config.test.ts` |
| locality planning in dissent, Flatline and Bridgebuilder | a hosted hop planned; repair chain leaving; missing MODELINV field | a provider mislabelled local by the operator | `tests/unit/adversarial-review*.bats` |

### Dependencies
- Sprint 2's `profile-lib.sh` for the `/loa` Profile line only; the locality and advisory keys are not profile keys and are read directly from the config
- Sprint 1's `cycle-ratio.sh` for the release-notes lines; Sprint 2's `derive` for the G-5a precondition

### Security Considerations
- The insecure-endpoint opt-in is per provider; every other provider keeps the cycle-099 refusals; both paths agree.
- Advisory voices never enter `voices_planned`; promotion is refused without the maintainer-set threshold and a report line; the family slice is deferred (DEC-0132).
- Under `local_voices` the repair chain cannot leave the declared providers; the degradation is stated, not hidden.
- Bridgebuilder's unknown-provider refusal stays for providers the merged config does not declare keyless.
- Catalog prices without provenance fail a test; no price is invented.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `exit 3` breaks a Bridgebuilder caller | Med | Med | both callers updated in Task 3.4 with tests |
| Advisory-voice merge changes the envelope by accident | Med | High | byte-identical envelope assertion in AC-3.3 |
| Local fixture server unavailable in CI | High | Low | injected fetch seam; no real server |
| Streaming changes regress hosted OpenAI parsing | Low | High | existing streaming tests stay green; `reasoning_content` handled additively |

### Success Metrics
- All Sprint 3 pytest, bats and vitest green; existing suites unchanged
- `e2e.md` with nine PASS rows or stated exceptions
- Review and audit APPROVED; COMPLETED marker; consolidated draft PR

---

## Risk Register

| # | Risk | Sprint | Owner | Status |
|---|------|--------|-------|--------|
| R1 | Arm run incomplete before Task 2.8 | 1→2 | lead | open; D-2.4 fallback |
| R2 | Fence classifier hole | 2 | implementer 2.6 | open; corpus-gated |
| R3 | Profile reaches the floor | 2 | implementer 2.7 | open; floor test |
| R4 | Bridgebuilder exit-code consumers | 3 | implementer 3.4 | open; tests |
| R5 | Guard code review load (inventory evidence E2: all three cycle-128 HIGHs were in newly written control surfaces) | all | lead | accepted; three dissent runs max |
| R8 | Self-hosting: Sprint 2 changes the hooks and readers the run depends on | 2 | lead | smoke run after each apply; `deny` flip deferred to cycle end; recovery step documented (D34) |
| R9 | Bridgebuilder reads provider config from an attacker-controlled PR head | 3 | implementer 3.4 | trusted config source only; head-only declarations refused (D36) |
| R6 | Flatline planning reviews degraded (KF-041) | plan | lead | accepted; upstream issue Task 1.10 |
| R7 | Provider limits during dissent (KF-037/038) | all | lead | accepted; retry per chunk, never approve on one voice |

---

## Success Metrics Summary

| Metric | Target | Sprint |
|--------|--------|--------|
| Guards with an origin | 100 % | 1 |
| Replay rows in yield counts | 0 | 1 |
| Fixtures with labels | 8 | 1 |
| Plans tagged with `kind:` | this plan passes | 1 |
| Controls documented but inert | 0 | 2 |
| Breaker counts a changes-required round | yes (fixture) | 2 |
| Fence D-rows removed | 0; p95 < 80 ms | 2 |
| Always-on prose per turn | ≤ 12 KB or fallback stated | 2 |
| Advisory voice changes a verdict | never (byte-identical envelope) | 3 |
| Hosted hop under `local_voices` | 0 planned | 3 |
| E2E goals | 9 PASS or stated exception | 3 |

---

## Dependencies Map

```
Sprint 1: 1.0   1.1 → 1.2 → 1.3        1.4 → 1.6 (batch 1 starts)   1.5 (batch 2 starts)
          1.7   1.8   1.9   1.10        (all) → 1.11
Sprint 2: 2.10 → 2.1   2.5   2.2  2.3  2.6   2.4 → 2.7   {2.4, 2.10, arms STATUS} → 2.8 (last)   (all) → 2.9
Sprint 3: 3.1 ─────────────┐
          3.2 → 3.3 ┐      │
          3.4 ──────┴→ 3.5 ┴→ 3.6 → 3.E2E → cycle-end deny flip
```

---

## Appendix

### A. PRD Feature Mapping

| PRD FR | Sprint | Tasks |
|--------|--------|-------|
| FR-1 Guard register and yield | 1 | 1.1, 1.2, 1.3 |
| FR-2 Control arms | 1 (run read in 2) | 1.4, 1.5, 1.6, 2.8 |
| FR-3 Prose diet | 1, 2 | 1.8, 2.8 |
| FR-4 Retire or repair inert controls | 2 | 2.1, 2.2, 2.3, 2.4, 2.5 |
| FR-5 File-authoritative run position | 2 | 2.5 |
| FR-6 Fence false positives | 2 | 2.6 |
| FR-7 Advisory open-weight voices | 3 | 3.1, 3.2, 3.3, 3.4 |
| FR-8 Local posture | 3 | 3.5 |
| FR-9 Profile knob | 2 | 2.7 |
| FR-10 Task kinds | 1, 3 | 1.7, 3.6 (ratio line) |
| Carry-over defects | 1, 2, 3 | 1.9, 1.10, 2.1 (docs), 3.4 (banner, exit) |

### B. SDD Component Mapping

| SDD | Tasks |
|-----|-------|
| D-1.1 … D-1.6 | 1.1, 1.2, 1.3 |
| D-2.1 … D-2.4 | 1.4, 1.5, 1.6, 2.8 |
| D-3.1 … D-3.3 | 1.8, 2.8 |
| D-4.1 … D-4.6 | 2.1, 2.2, 2.3, 2.4, 2.5 |
| D-5.1 … D-5.4 | 2.5 |
| D-6.1, D-6.2 | 2.6 |
| D-7.1 … D-7.7 | 3.1, 3.2, 3.3, 3.4 |
| D-8.1, D-8.2 | 3.5 |
| D-9.1 … D-9.3 | 2.7 |
| D-10.1 … D-10.3 | 1.7, 3.6 |

### C. PRD Goal Mapping

| Goal | Sprint | Validation |
|------|--------|------------|
| G-1 | 1 | AC-1.1 … AC-1.5; E2E |
| G-2 | 1 (2) | AC-1.6 … AC-1.8; AC-2.10; E2E |
| G-3 | 1, 2 | AC-1.10, AC-2.10; E2E |
| G-4 | 2 | AC-2.1 … AC-2.6, AC-2.11; E2E |
| G-5 | 2 | AC-2.6, AC-2.7; E2E |
| G-6 | 2 | AC-2.8; E2E |
| G-7 | 3 | AC-3.1 … AC-3.6; E2E |
| G-8 | 2 | AC-2.9; E2E |
| G-9 | 1, 3 | AC-1.9, AC-3.7; E2E |

### D. Flatline review integration (2026-10-14)
Run on the pre-integration plan: two voices (`gpt-5.5`, `claude-headless`), cross-scoring degraded (KF-041, exit 6), eleven skeptic blockers, integrated by judgment per DEC-0134. SKP-008 (Bridgebuilder reading keyless or insecure providers from the PR head) → trusted config source only, head-only refusal, vitest (Task 3.4, D36); SKP-005 and opus IMP-003 (Sprint 2 changes the hooks the run depends on) → smoke run after each apply, `deny` flip deferred to the cycle's last commit after the E2E validates the cache, recovery step in the report (Tasks 2.1, 2.9, G-5a, D34); SKP-012 (locality enforcement at request time) → D-7.2 rules applied to every local hop (Task 3.5); SKP-001 and opus IMP-020 (the arm run cannot finish between sprints) → two batches started as early as their inputs exist, `--fixtures`, Task 2.8 last, fallback stated with no deletion and an unchanged cap (Tasks 1.4, 1.6, 2.8, D37); SKP-002 (arms measure review recall, not implementer behaviour; arms coarser than rows) → per-row evidence classification: arm verdict for review-affecting prose, pointers for mechanism rows, proposed DEC rows plus the register for behavioural rows (Task 2.8, AC-2.10, D35); SKP-002 (isolation) → `MANIFEST.json` with source and harness commits, executor config, fixture checksums verified before each run, environment metadata, trials interleaved (Task 1.6); SKP-006 and SKP-004 (classifier grammar, wrappers, hook and rc targets, two-step) → grammar stated, nested and variable-delimiter heredocs, control characters and CRLF, `env python`, `find -exec`, redirects into hook, settings, rc, PATH and `.git/hooks` locations, semantics recorded in the hooks reference (Task 2.6); SKP-001 (run manifest and PASS/PARTIAL/FAILED) → `STATUS.json` states and consume-only-complete (Tasks 1.6, 2.8); SKP-004 (floor inventory and no-floor-diff proof) → `floor.yaml` in Task 1.1 and `floor-snapshot.bats` in Task 1.3, checked by the E2E. Improvements folded: gpt IMP-002 (concrete filing path for Task 1.10), IMP-006 (normalised byte-identical comparison, AC-3.3), IMP-007 and opus IMP-010 (owner and shared-file tables per sprint), IMP-008 (Task 1.0 readiness), IMP-010 (catalog freshness WARN, Task 3.3), IMP-011 and opus IMP-021 (Task 2.5 split into 2.5 and 2.10), IMP-012 (`bridgebuilder.exit_on_degraded` rollback key); opus IMP-002 (lead-owned side effects), IMP-005 (advisory smoke run in G-7), IMP-007 (minimum six fixtures, gap statement), IMP-008 (sandbox cwd in the replay fallback, Task 1.2 via the flag), IMP-013 (prose baseline with its command, Task 1.11), IMP-015 (AC-1.9 reduced to the lint plus an eval fixture), IMP-016 (oracle snapshot and grep lint, Task 2.7), IMP-017 (callers enumerated by grep, Task 3.4), IMP-018 (all suites green in every sprint), IMP-019 (workflow grep before the strip, Task 2.2), IMP-022 (Sprint 3 dependency sentence), IMP-023 (map edges and E2 defined), IMP-024 (G-8 via `LOA_STATUS_CONFIG_FILE`), IMP-025 (cap rule under fallback), IMP-026 (paths glob lint), IMP-027 (checkable "disables nothing"). Declined: gpt IMP-002's reclassification of Task 1.10 as `operator` (the maintainer's instruction and DEC-0134 are the record; the concrete path is given instead); opus IMP-011's per-row arms (the classification in D35 answers the mismatch without multiplying arms).

---

*Generated by Sprint Planner Agent*
