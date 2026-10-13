# Software Design Document: Earned Guards and Open Voices (cycle-129)

**Version:** 1.0
**Date:** 2026-10-14
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-129, FR-1 … FR-10, Appendix E D1–D24 = DEC-0125 … DEC-0148)
**Status:** Draft — autonomous run; design-level decisions taken on the operator's behalf are listed in §11.3 and recorded as `proposed` DEC rows
**Branch:** `feature/cycle-129-earned-guards` from `main` `864069f2`

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 Principle
Measure before deleting, tighten before loosening, derive before trusting. Every change in this cycle is one of: a report (FR-1, FR-10), a measurement (FR-2), a removal justified by a measurement (FR-3), a control made true or made telemetry (FR-4), a write path moved from the model to a script (FR-5), a fence narrowed under corpus control (FR-6), a voice admitted without a vote (FR-7, FR-8), or a knob that cannot reach the floor (FR-9). Nothing in this cycle adds a model-executed instruction where a script can do the work.

### 1.2 Sprint shape
Three sprints (global 255, 256, 257). Sprint 1 produces the register, the arms and the corpus, and starts the arm run in two detached batches as soon as each batch's inputs exist (DEC-0171). Sprint 2 repairs or retires the inert controls and, as its last task, consumes whatever arm results are `complete` for the prose diet. Sprint 3 opens the voice path and runs the end-to-end validation; the cycle's last commit flips this repository's implement gate to `deny` once the E2E has validated the derived cache against the live run. Each sprint ends with review and audit on Fable 5.1 and at most three dissent runs.

**Self-hosting rule (DEC-0168).** Sprint 2 changes `implement-gate.sh`, `block-destructive-bash.sh`, `run-checkpoint.sh` and the knob readers that the executing `/run sprint-plan` session itself depends on. After every patch apply the lead runs `tests/fixtures/fence-corpus/run-corpus.sh` and the hook bats before any further tool call relies on the changed hook, and records the result; a failure is reverted with `git show HEAD:<path> > <path>` (never `git checkout --`, which the fence blocks) or the knob is switched off; this repository stays on `implement_gate.mode: ask` until the cycle-end flip.

### 1.3 Component map

| Component | Kind | New or changed | FR |
|---|---|---|---|
| `.claude/data/guard-origins.yaml` | data | new | FR-1 |
| `.claude/scripts/guard-yield.sh` | bash | new | FR-1 |
| `grimoires/loa/guards.md` | generated, tracked | new | FR-1 |
| `.claude/loa/reference/hooks-reference.md` registration table | generated section | changed | FR-1 |
| `.claude/scripts/loa-status.sh` | bash | Guards line, Profile line | FR-1, FR-9 |
| `tests/unit/guard-origins.bats` | bats | new | FR-1 |
| `evals/suites/{review,audit}-recall.yaml` `ab.arms` | yaml | changed | FR-2 |
| `evals/harness/execute-agent.sh` arm toggles | bash | changed | FR-2 |
| `evals/harness/seed-corpus-from-record.sh`, `run-arms.sh` | bash | new | FR-2 |
| `evals/fixtures/review-prs/pr-09 … pr-16` | fixtures | new | FR-2 |
| `evals/harness/compare.sh` | bash | model-skew refusal already exists; arm-aware report | FR-2 |
| `.claude/rules/stash-safety.md`, `skill-invariants.md` | rule files | `paths:` frontmatter | FR-3 |
| `.claude/loa/CLAUDE.loa.md`, `.claude/data/constraints.json`, `generate-constraints.sh` | kernel | rows shrink or leave | FR-3, FR-4(e) |
| `tools/check-prompt-budget.sh` `LOA_LIMIT` | python/bash | lowered | FR-3 |
| `.claude/hooks/compliance/implement-gate.sh` | hook | `telemetry`, `deny` modes | FR-4(a) |
| four pure-review `SKILL.md` + `validate-skill-capabilities.sh` | frontmatter, lint | `disallowed-tools` | FR-4(b) |
| `.claude/hooks/quality/karpathy-surgical-diff-check.sh` | hook | per-task reset, summary file | FR-4(c) |
| `.loa.config.yaml.example`, `.loa.config.yaml` | config | guardrails off, `implement_gate.mode`, `loa.profile`, `hounfour.locality`, local provider example | FR-4(d), FR-7, FR-8, FR-9 |
| `.claude/loa/reference/agent-teams-reference.md` | doc | receives the C-TEAM rules | FR-4(e) |
| `.claude/scripts/run-checkpoint.sh` | bash | `record-round`, `derive` verbs | FR-4(f), FR-5 |
| `.claude/skills/run-mode/SKILL.md`, `resources/completion-modes.md`, `halt-resume.md` | skill prose | breaker prose → one call; jack-out writes `.state` | FR-4(f), FR-5 |
| `.claude/hooks/safety/block-destructive-bash.sh` + `tests/fixtures/fence-corpus/corpus.jsonl` | hook, corpus | heredoc consumer classification | FR-6 |
| `.claude/adapters/loa_cheval/providers/openai_adapter.py`, `openai_streaming.py` | python | chat `response_format`, `reasoning_content`, `<think>` strip | FR-7 |
| `.claude/adapters/loa_cheval/config/loader.py` | python | per-provider `allow_insecure_endpoint`; Azure/local examples load | FR-7 |
| `.claude/scripts/lib/endpoint-validator.py`, `model-health-probe.sh` | python, bash | per-provider opt-in; configured-provider probe | FR-7 |
| `.claude/scripts/adversarial-review.sh` | bash | `advisory_voices`, catalog-priced budget gate, locality | FR-7, FR-8 |
| `.claude/scripts/flatline-orchestrator.sh` | bash | locality refusal of hosted voices | FR-8 |
| `.claude/adapters/loa_cheval/audit/modelinv.py` | python | `locality` field | FR-8 |
| `.claude/defaults/model-config.yaml` + `tests/test_catalog_pricing_provenance.py` | catalog, pytest | `price_source`, `price_date` | FR-7 |
| `.claude/skills/bridgebuilder-review/resources/{config.ts,main.ts,core/progress.ts}` | typescript | keyless providers, completed count, exit 3 on DEGRADED | FR-7, carry-over |
| `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml` | bash, data | new | FR-9 |
| knob readers (`loa-kf-surface.sh`, `loa-decisions-surface.sh`, `karpathy-surgical-diff-check.sh`, `guardrails-orchestrator.sh`, `danger-level-enforcer.sh`, `loa-l6-surface-handoffs.sh`, `loa-l7-surface-soul.sh`, the retrospective and success-criteria prose) | bash, prose | read through `profile-lib.sh` | FR-9 |
| `tests/unit/profile-floor.bats` | bats | new | FR-9 |
| `.claude/scripts/validate-artifact.sh` (`--type sprint`), `planning-sprints/resources/templates/sprint-template.md`, `reviewing-code/SKILL.md` spec axis | bash, template, prose | `kind:` | FR-10 |
| `tools/cycle-ratio.sh` | bash | new | FR-10 |
| `.github/workflows/check-prompt-budget.yml` comment, `implementing-tasks/SKILL.md:28` | docs | fixed | carry-over |

### 1.4 Prompt budget plan
`CLAUDE.loa.md` is at 10,225 B of 10,240 B. Sprint 1 adds no kernel text (path-scoping is frontmatter in the rule files). Sprint 2 removes the five C-TEAM rows (≈ 900 B) and shrinks the mechanism-describing rows to pointers; the FR-4(f) breaker prose leaves `run-mode/SKILL.md` (≈ 1.9 KB) for one `run-checkpoint.sh record-round` call. The two rule files stop loading on ordinary turns (−7,301 B). Target after Sprint 2: kernel ≤ 9,000 B, always-on prose ≤ 12 KB; `LOA_LIMIT` lowered to the measured kernel size + 256 B. `reviewing-code/SKILL.md` (16,306 B of 16,384 B) gains two lines for FR-10 and must shed the same bytes elsewhere in the same change; `implementing-tasks/SKILL.md` gains nothing.

### 1.5 Design decisions

#### FR-1: guard register and yield
- **D-1.1 Origin map.** `.claude/data/guard-origins.yaml` is the one hand-written artifact: a list of rows `{id, kind, class, status, origin: {kind, ref}, knob, floor, registrations, note}`. **Identity**: one row per unique hook script (`hook:safety/block-destructive-bash.sh`, with `registrations: [PreToolUse:Bash]` listing every event and matcher), one per fence pattern id (`fence:FR-1.2b`), one per validator rule marker (`validator:sprint.seams`, see D-1.2), one per gate from the fixed list `gate:verdict-derive`, `gate:adversarial-review-gate`, `gate:implement-gate`, `gate:success-criteria`, `gate:dissent-budget`, `gate:seams`, `gate:kinds`, `gate:prompt-budget`, `gate:guard-origins`. `kind ∈ hook|fence|validator|gate`; `class ∈ harness|script|prose`; `status ∈ active|dormant|telemetry` (`dormant` = armed only by an environment variable, with the variable named in `knob`); `origin.kind ∈ kf|issue|finding|cycle|design` with `ref` a KF id, `#NNN`, `sprint-NNN <gate> <item>`, `cycle-NNN`, or an ADR; `knob` is a config key, an env var, or `none`; `floor: true` marks the untouchable set. The map is seeded in Sprint 1 for every registered hook script (29), every fence pattern id (32), every validator rule marker and the gate list. Origins come from the inventory's cites and the KF ledger; a row whose origin is not known is written `origin: {kind: design, ref: "<cycle or commit that added it>"}` from `git log --follow`, never left empty.
- **D-1.2 Enumeration.** `guard-yield.sh` enumerates hooks from `.claude/settings.json` with `jq` (`.hooks | to_entries[] | .value[] | .hooks[].command`) and parses each command against the **canonical hook command schema**: `"$(git rev-parse --show-toplevel)"/.claude/<path> [args]` or the same wrapped in `hook-guard.sh <path> [args]`; `<path>` is the script's path under `.claude/` with no spaces or quotes, resolved through symlinks once and compared canonically. A command that does not match the schema is reported and fails `guard-origins.bats` (no silent drop). Event and matcher become the `registrations` list. Fence ids are enumerated from `# @guard fence:<id>` marker comments that Sprint 1 adds above each `emit_block` site in `block-destructive-bash.sh`; the lint cross-checks that every quoted first argument of an `emit_block` call and every `pattern_id=` constant has a marker and that every marker has a call site. Validator rules are enumerated from `# @guard validator:<id>` marker comments that Sprint 1 adds above each rule block in `validate-artifact.sh` (one per `--type` rule family: `prd.sources`, `prd.assumption-tags`, `sdd.sections`, `sprint.sections`, `sprint.seams`, `sprint.kinds`, `decisions.*`, `map.*`, `spike.*`, `glossary.*`). Gates come from the fixed list in D-1.1; the lint checks that each gate's script exists.
- **D-1.3 Yield join.** Rows of `.run/audit.jsonl` and of its rotated segments `.run/audit.jsonl.*` (retention: at least the 30-day window; `notes-guard`-style rotation is out of scope, the reader simply concatenates) with `action == "block"` carry `hook`, `pattern_id`, `ts`, `cwd`, and (for the fence) `command`; implement-gate `telemetry` rows (D-4.1) count as `telemetry_30d`. The 30-day window is `ts ≥ now − 30 d`. A row is a **replay** when it carries `replay: true` (the hooks write it when `LOA_AUDIT_REPLAY=1` is set, which `tests/run-bats.sh`, `run-corpus.sh` and `execute-agent.sh` export; DEC-0167) or, for rows that predate the flag, when its `cwd` starts with `${TMPDIR:-/tmp}/` or contains `/bats-run-` or `/bats.`; replays are excluded and counted in the header. A block is **likely false positive** by the predicate `heredoc_nonexec(command) OR outside_repo(cwd) OR (pattern_id ∈ {SP-1, FR-MERGE-2, FR-2-AMBIGUOUS} AND NOT destructive_verb_at_statement_start(command))`, where `heredoc_nonexec` sources the FR-6 classifier's consumer function when the fence provides it (a heredoc whose consumer the classifier calls non-executing) and falls back to `<<` presence otherwise; the column is labelled a heuristic and the fixture test mirrors the predicate. A **real catch** is a block that is not likely-FP; `last_real_catch` is the newest such block in the window at day granularity, else `none in window`. Hooks that never write `block` rows show `n/a` with their class.
- **D-1.4 Outputs.** `guard-yield.sh` writes three things. (1) `grimoires/loa/guards.md` (tracked, **structural only**, DEC-0162): a header (`guards`, `guards_without_origin`, `dormant`, no timestamp) and one table per kind with columns `id | class | status | origin | knob | floor | registrations`; it is a pure function of the repository, so `--check` compares the whole file and CI can regenerate it. (2) `.run/guard-yield.md` and (3) `.run/guard-yield.json` (gitignored): the same rows plus `blocks_30d | likely_fp_30d | telemetry_30d | last_real_catch` and a header (`generated_at` at day granularity, `window_days: 30`, `scope: host`, `audit_rows_considered`, `replay_rows_excluded`), regenerated on demand by the operator and read by `/loa` and by the sprint reports. `guard-yield.sh --hooks-table` rewrites the registration table of `hooks-reference.md` between `<!-- guard-register:begin -->` and `<!-- guard-register:end -->` from the structural register (ids, class, status, registrations, knob, purpose from `note`). `--check` exits 1 when `guards.md` or the hooks table differ from what it would write (CI drift gate, run in the Shell Tests job). **Privacy**: nothing from a command string, `cwd`, hostname, user or model name is written to any of the three files; ids match `^[A-Za-z0-9._/-]+$`; origin text comes from the tracked map.
- **D-1.5 `/loa` line.** `loa-status.sh` gains a `Guards` block that reads the structural register for the counts and `.run/guard-yield.json` for the yield (no recomputation at status time): `Guards: 78 (0 without origin, 3 dormant) · 30 d: 105 real blocks, 96 likely FP · scope host · regenerate: .claude/scripts/guard-yield.sh`. When the yield file is missing it prints the structural counts and the regenerate hint.
- **D-1.6 Lint.** `tests/unit/guard-origins.bats`: every enumerated hook script, fence id and validator marker has a row with a non-empty `origin.ref`; every row's `id` resolves (hook script exists, fence id present in the hook, marker present in the validator, gate script exists); `floor: true` rows are exactly the PRD's floor set; `status: dormant` rows name an env var in `knob`; the map parses with yq v4. A fixture audit log with replay rows, a rotated segment and real rows proves D-1.3's exclusion, segment reading and columns; a fixture with a heredoc block, a scratch-path block and a prose-class block proves the FP heuristic.

#### FR-2: control arms
- **D-2.1 Arm declaration.** `ab.arms:` in each suite lists `{id, description, toggles}` with canonical ids. Review: `baseline` (no toggles), `no_companion` (`companion_voice: false`), `no_karpathy` (`karpathy_block: false`), `no_rule_files` (`rule_files: false`). Audit: `baseline`, `no_audit_delta` (`audit_delta_instruction: false`). `ab.threshold:` pre-registers the verdict rule: `trials_required: 3`, `coverage_required: full`, `mean_recall_max_drop: 0.10` (= `ci.regression_threshold`), `min_trial_recall_max_drop: 0.15`, `refuted_share_max_rise: 0.10`; `report.sh --arms` prints `no recall loss`, `recall loss` or `inconclusive` (any missing trial or fixture) per arm. `execute-agent.sh` reads `LOA_EVAL_ARM` and applies the arm's toggles to the sandbox copy only: `companion_voice: false` sets `flatline_protocol.code_review.companion_voice: false` in the sandbox `.loa.config.yaml`; `karpathy_block: false` removes the `## Karpathy Principles` section from the sandbox `CLAUDE.loa.md`; `rule_files: false` removes the two rule files from the sandbox `.claude/rules/`; `audit_delta_instruction: false` removes the "look for what the review did not" paragraph from the sandbox `auditing-security/SKILL.md`. Each trial's `results.jsonl` row records `arm` and the executor `model_id` (already recorded; `compare.sh --ab` already refuses model skew, `compare.sh:43`).
- **D-2.2 Corpus from the record.** `evals/harness/seed-corpus-from-record.sh <global-sprint> <record-branch>` writes `evals/fixtures/review-prs/pr-NN/`: `fixture.yaml` (`sprint`, `base_commit` = parent of the round-1 implementation commit, `head_commit` = that commit, `fix_commit`, `record_branch`, `feedback_files`), `head.diff` from `git diff base..head`, `PR.md`, `REVIEW-INSTRUCTIONS.md` and `AUDIT-INSTRUCTIONS.md` (from the existing fixture templates), and `labels.tsv` (`defect_id, severity, category, file, must_match, label_source, source`) seeded from the round-1 `engineer-feedback*.md` and `auditor-sprint-feedback*.md` finding headings on the record branch. **Label rule**: a finding becomes a label only when `fix_commit` touches the file the finding cites (checked by the script against `git diff --name-only head..fix`); `label_source ∈ review|audit|bridgebuilder|fix`, where `fix` rows are generated from the hunks `fix_commit` touched (`source: fix/<sha>`, file and hunk range as the anchor) so that refuted share is computed only against findings matching neither a feedback label nor a fix-touched region. The lead curates `must_match` anchors so `recall-vs-defects.sh` can grade them and approves each `labels.tsv` before commit (a `# approved-by: lead <date>` header line the seed test requires). Labels carry control-stripped finding titles, severity, category, file and anchor only, and pass `graders/no-secrets.sh`. `corpus.tsv` and `SHA256SUMS` are extended; `ab.corpus_manifest` keeps pointing at `SHA256SUMS`.
- **D-2.3 Running the arms.** `evals/harness/run-arms.sh --suite review-recall --arms baseline,no_companion,no_karpathy,no_rule_files --trials 3 --source-commit 864069f2` creates a detached git worktree at the recorded source commit (`main` `864069f2`, the pre-cycle tree, is the true baseline: its rule files are unscoped and its kernel is undieted) and points every trial's sandbox copy at that worktree, never at the live working tree Sprint 2 edits; `results.jsonl` rows record `source_commit`, `arm`, `model_id`, `trial`, `seed` (when the executor route accepts one; CLI hops record `seed: null` and the run date); `compare.sh --ab` refuses mixed `source_commit` values as it refuses model skew. The executor is pinned to `global.anthropic.claude-opus-5-5`. `arm-toggles.bats` asserts the toggled text is absent from the sandbox at the moment the executor starts (after any sandbox regeneration), not only after the toggle script runs; a sandbox that regenerates `CLAUDE.loa.md` from `constraints.json` at session start has the Karpathy toggle applied to `constraints.json` as well. **Executor**: `global.anthropic.claude-fable-5-1`, the production gate model (DEC-0164); the eval executor plays the gate role, so the 2026-10-05 implementer policy is unaffected. **Coverage**: all sixteen fixtures (`pr-01` … `pr-16`), 4 review + 2 audit arms with a shared baseline, 3 trials: 288 executor runs. **Retry policy**: a trial that fails for transport reasons is retried once; a second failure leaves the arm `inconclusive`. `run-arms.sh --fixtures <list>` runs in batches (batch 1: `pr-01` … `pr-08` as soon as the harness lands; batch 2: `pr-09` … `pr-16` when the record fixtures land; DEC-0171), interleaving trials across arms to spread provider drift, and writes `evals/results/arms/<suite>/MANIFEST.json` (`source_commit`, `harness_commit`, `model_id`, executor configuration, fixture `SHA256SUMS` verified before each run, OS and tool versions) and `STATUS.json` `{state: running|complete|partial|failed, per_arm: {trials_done, trials_planned}, source_commit, model_id, started, finished}`; `report.sh --arms` refuses to write a report while `state` is not `complete` unless `--partial` is passed, in which case the report header says so and every verdict reads `inconclusive`. **Sprint 2 gate** (Task 2.8): read `STATUS.json` at task start; `complete` → use the verdicts; anything else → the D-2.4 fallback, no waiting. The run is started detached (`setsid nohup`, log outside the scratchpad) at the end of Sprint 1. `report.sh --arms` writes `evals/results/arms-report-<date>.md`: per arm recall (mean, min, max and trial-to-trial spread), refuted share (findings matching neither a feedback label nor a fix-touched region ÷ findings), tokens per call, a percentile-bootstrap 90 % interval of the recall delta over fixtures, the pre-registered verdict (`no recall loss` requires the interval's upper bound on the recall drop ≤ `mean_recall_max_drop` and the delta to exceed the baseline's own spread before any change is named), and the missed labels per arm; the `no_companion` arm is marked informational (the companion voice is a floor key that no profile can remove; the arm measures its yield only) and the `no_karpathy` arm's description states that it removes the kernel block only, not the SURGICAL review axis or the surgical-diff hook. A deletion in Task 2.8 requires the lead to read the missed labels for the arm it relies on and record that reading. The gate type stays `advisory`; no flip happens in this cycle.
- **D-2.4 Fallback.** If the arm run cannot complete in the cycle (provider limits, KF-037 class), Sprint 2 ships path-scoping and the mechanism pointers only, defers every text deletion to a follow-up bead naming the missing arm, and the Sprint 2 report says so. The cap is still lowered to the measured size.

#### FR-3: prose diet
- **D-3.1 Path scoping.** `stash-safety.md` frontmatter: `paths: ["**/*.sh", "**/*.bats", ".claude/scripts/**", ".claude/hooks/**"]`; `skill-invariants.md`: `paths: [".claude/skills/**/SKILL.md", ".claude/agents/**", ".claude/data/agent-types.yaml", ".claude/scripts/validate-skill-capabilities.sh"]`. The fence FR-1.2b block message already names the repair; it gains a pointer to the rule file's path. **Crosswalk** (Task 1.8 writes it into the Sprint 1 report, `a2a/sprint-255/reviewer.md`): one row per hazard named in each rule file → the fence pattern id or lint that mechanises it and the corpus or bats row proving it; hazards without a mechanical check are listed as such (expected: the `stash -k` under pre-commit rule and the `fsck` before `gc` recovery advice, both judgment rules the `no_rule_files` arm measures).
- **D-3.2 Kernel rows (evidence classes, DEC-0169).** In Sprint 2's last task, every candidate row is classified. *Review-affecting* prose (the Karpathy block; the audit's "look for what the review did not" instruction) changes only with its arm's `no recall loss` verdict and the lead's recorded reading of that arm's missed labels. *Mechanism-describing* rows become one line naming the mechanism without further evidence, because the mechanism holds (the implement gate row names `implement_gate.mode` and the hook; the breaker row names `run-checkpoint.sh record-round`; the Merge rows name `post-merge-orchestrator.sh` and `semver-bump.sh`). *Behavioural prose-only* rows (`TaskCreate`, `/bug` eligibility, beads creation) shape implementer and operator behaviour that no review-recall arm measures: they move to `.claude/protocols/process-compliance.md` with a one-line pointer in the kernel, each move is a `proposed` DEC row for the operator to confirm, and the register's block, ask and telemetry counts are the instrument going forward. The Agent Teams table leaves with FR-4(e). The two rule files are path-scoped on the crosswalk (D-3.1), not on an arm; the `no_rule_files` arm reports their review effect only. Each change is listed in the Sprint 2 report with its class and evidence (D-2.4 otherwise: no row deleted).
- **D-3.3 Cap.** `tools/check-prompt-budget.sh` `LOA_LIMIT` becomes `min(current LOA_LIMIT, measured post-diet kernel size + 256 B)` so the cap never rises; the workflow comment is corrected to the script's values (160,000 / 114,688 B). The −7,301 B rule-file saving applies to turns that touch no shell source or SKILL.md; Task 1.8 records a harness observation (which rule files the session loaded on a matching and a non-matching turn) in the Sprint 1 report.

#### FR-4: retire or repair inert controls
- **D-4.1 Implement gate modes.** `implement_gate.mode ∈ ask | telemetry | deny`; `implement_gate.claims: authoritative` is the tighten-only modifier (today's `mode: authoritative` keeps working as an alias for `mode: ask` + `claims: authoritative`). **Default when unset: `ask`** (today's behaviour; no silent change for any mount, DEC-0163); `telemetry` and `deny` are opt-ins. Every `ask` now writes one compliance row (`decision: ask`), so the register counts asks (today they are unlogged). **Sanction**: a write is sanctioned when the derived cache (FR-5) says `RUNNING` and its `derived_at` is within `run_mode.stale_hours`, or when `.run/implement-active.json` exists with `{skill: implement|bug, sprint, started_at}` and `started_at` is within two hours (the `implementing-tasks` and `bug-triaging` skills write it at start, call `run-checkpoint.sh derive --write` before their first App-Zone write, and remove it at the end), or when `LOA_IMPLEMENT_GATE_OVERRIDE=1` is set. Every sanction path logs one compliance row (`decision: sanctioned_run | sanctioned_marker | override`); a stale marker does not sanction and logs `stale_marker`. **Unknown position**: under `deny`, a missing cache, a cache older than `run_mode.stale_hours`, or an unparseable cache is *unknown* and falls back to `ask`, never allow (`decision: unknown_position`). `telemetry`: an unsanctioned App-Zone write appends one row `{"ts","hook":"implement-gate","action":"telemetry","decision":"outside_run","mode":"telemetry","path":<strip_controls, 256 B>}` to `.run/audit.jsonl` and exits 0 with empty stdout. `deny`: prints `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"App Zone write with no active implementation run (derived position: <state>); run /implement or /bug, or set implement_gate.mode: ask"}}` and logs `decision: deny`. `ask`: today's output plus the row. Trust-input writes keep asking in every mode and under every sanction. The run position is read from the derived cache; the gate never computes it. `implement-gate.bats` covers the full matrix mode × claims × write class × sanction state × cache state (present-fresh, stale, missing, unparseable). This repository's `.loa.config.yaml` sets `deny`; the example documents all three and says the hook is a fence only under `deny`.
- **D-4.2 `disallowed-tools`.** The four pure-review skills gain `disallowed-tools: Write, Edit, NotebookEdit`; `validate-skill-capabilities.sh` fails any `role: review` skill with `write_files: false` that lacks all three; `skill-invariants.md` keeps its sentence, now true, and names the Bash gap (shell-redirection writes remain fence territory). **Harness probe**: Task 2.2 records in the Sprint 2 report a live probe showing the harness refuses a Write from a skill carrying the key (the cycle-128 Task 1.0 pattern); if the key is not enforced, the task switches the four skills to an explicit read-only `allowed-tools` set and the invariant doc says so.
- **D-4.2a Surgical-diff hygiene.** The `<task>` component of `.run/karpathy-surgical/<task>.jsonl` is sanitised to `^[A-Za-z0-9._-]+$` (task labels carry spaces and dots); the hook deletes the legacy `.run/karpathy-task-state.jsonl` on its first run under the new layout.
- **D-4.3 Surgical-diff hook.** The hook reads the current task from `run-checkpoint.sh read --json` (`.task`, else `.sprint`, else the session id from the hook payload) and keys its running total on it: `.run/karpathy-task-state.jsonl` is replaced by `.run/karpathy-surgical/<task>.jsonl` (one small file per task, rotated when the task changes, the directory capped at the last 20 tasks) and `.run/karpathy-surgical-summary.json` `{task, lines, threshold, over, updated_at}`. `reviewing-code/SKILL.md`'s SURGICAL axis reads the summary when present (one line). The stderr warning is unchanged.
- **D-4.4 Guardrails default.** `guardrails.input.enabled: false` and `guardrails.danger_level.enforce: false` in the example; this repository keeps `guardrails.input.enabled: true` (the orchestrator keeps logging PASS/BLOCK events to the trajectory) and sets `guardrails.danger_level.enforce: false` (DEC-0161 amends DEC-0139); the `@skill-include input_guardrails` block already skips when disabled.
- **D-4.5 Team rows.** `generate-constraints.sh` stops emitting the Agent Teams table when `constraints.json` has no `C-TEAM-*` rows; the five rows are deleted; `agent-teams-reference.md` gains a "Rules and arming" section stating them and that the hooks are no-ops until the lead exports `LOA_TEAM_MEMBER`; `lint-invariants.sh` and its test are updated for the absent class.
- **D-4.6 Breaker in a script.** `run-checkpoint.sh record-round --gate review|audit --file <feedback.md> [--sprint sprint-N]` runs `verdict-derive.sh --json`, computes the same-issue hash exactly as the SKILL prose did (`{verdict,counts}` sorted, md5), updates `.run/circuit-breaker.json` atomically (same-issue count/reset, no-progress from unchanged `counts`, `cycle_count.current += 1` on any non-APPROVED verdict, timeout from `started`), appends a `history` entry on a trip, writes `state: OPEN` and sets `.run/state.json` `.state = HALTED`, and prints the trip line the SKILL used to print. **Mechanical caller**: `derive` (D-5.1) recomputes the same counters from the ordered feedback history of the active sprint (`engineer-feedback-r*.md`, `auditor-sprint-feedback-r*.md` sorted by round, their trailers derived) at every checkpoint and raises the breaker counters to the recomputed values when they are lower, so a forgotten `record-round` call cannot leave the breaker at zero. `run-mode/SKILL.md` §Circuit Breaker becomes the call plus a two-line description; the thresholds stay in the JSON and in `run_mode.defaults`.

#### FR-5: file-authoritative run position
- **D-5.1 Derivation.** `run-checkpoint.sh derive [--json] [--write]` computes, for the active ledger cycle: per sprint `global_id`, `local_label`, ledger `status`, `completed_marker` (`a2a/sprint-<gid>/COMPLETED` exists), `review` and `audit` verdicts (`verdict-derive.sh --json` on `engineer-feedback.md` / `auditor-sprint-feedback.md`, both APPROVED and the trailer's sprint id equal to `<gid>` or the local label; a feedback file with no trailer is legacy and yields no verdict, so the sprint stays incomplete), and `impl_commit` (the newest non-merge commit on the current branch since the sprint's ledger `started` timestamp that touches a path outside `grimoires/`, `.run/`, `REPO-MAP.md`, `checksums.json` and `CHANGELOG.md`; commits outside the active cycle's range are ignored). A sprint is **complete** when the marker exists, both verdicts are APPROVED for that sprint, and the ledger row is `completed`; a marker whose trailer names another sprint is reported as `stale_marker` and does not count. The run `state` is `JACKED_OUT` if the cache already says so or `.completion.merged_sha` is set; else `HALTED` if the breaker is `OPEN` or the cache says `HALTED`; else `COMPLETE` when every sprint is complete; else `RUNNING` when any sprint is incomplete and `timestamps.last_activity` is within `run_mode.stale_hours` (default 12); else `INTERRUPTED`. **Terminal and sticky states**: `JACKED_OUT` is terminal (files that contradict it are reported as drift and the cache is kept); `HALTED` is sticky until `run-resume` clears it; `COMPLETE` may advance only to `JACKED_OUT`; nothing moves back to `RUNNING` unless the ledger registers a new incomplete sprint. **Schema tolerance**: files written before this cycle lack `derived_at`, `derivation` and sometimes `.status`; `derive` reads them, adds the fields on `--write`, and keeps `schema_version: 2`.
- **D-5.1a Decision table.** Inputs per sprint: `M` = COMPLETED marker present and its trailer names this sprint; `R`/`A` = review/audit trailer APPROVED for this sprint; `L` = ledger row `completed`; `C` = an implementation commit exists after the last verdict. Sprint state: `M ∧ R ∧ A ∧ L` → `complete`; marker present but trailer names another sprint → `stale_marker`, treated as absent; `¬M` with `R ∧ A` → `awaiting_marker` (reported, counted incomplete); otherwise `in_progress`. Run state: cache `JACKED_OUT` or `.completion.merged_sha` set → `JACKED_OUT`; breaker `OPEN` or cache `HALTED` → `HALTED`; every sprint `complete` → `COMPLETE`; any sprint incomplete and `last_activity` within `run_mode.stale_hours` (12) → `RUNNING`; otherwise `INTERRUPTED`. Breaker: `cycle_count.current` = max(cache, number of non-APPROVED rounds in the feedback history); `same_issue` from the last two derived hashes; `no_progress` from unchanged `counts` across consecutive rounds; `state` = `OPEN` when any threshold is met, else unchanged. `tests/unit/run-checkpoint-derive.bats` has one case per row.
- **D-5.2 Writes.** `--write` rewrites `.run/sprint-plan-state.json` with the same keys the schema has today, `.state` canonical and `.status` mirrored, plus `.derived_at` and `.derivation: {source: "files", stale_markers: [...]}`; `.run/circuit-breaker.json` is recomputed per D-5.1a and D-4.6. `run-checkpoint.sh write` calls `derive --write` after its own update, so every checkpoint refreshes the cache. `run_mode.file_authoritative: false` makes `derive` report-only (the caches are written as today) — the rollback knob. The jack-out step in `completion-modes.md` writes `.state` (the cycle-128 defect wrote `.status` only).
- **D-5.3 Readers.** `golden-path.sh:874`, `loa-run-state-surface.sh`, `run-preflight.sh` P6 and the implement gate keep reading the cache; `/loa` calls `derive --json` and prints `drift: cache says X, files say Y` when they differ (report-only; `/loa` writes no state); `run-resume` calls `derive --write` on drift before it continues. `loa-status.sh` also prints the effective `implement_gate.mode`. The recovery doc in `halt-resume.md` reads `.state`. Each reader has a bats case over a derived file (`.derived_at` present, `.status` mirrored) proving it still reads the state it read before.
- **D-5.4 Drift fixture.** `tests/unit/run-checkpoint-derive.bats`: cache RUNNING + three COMPLETED markers with APPROVED trailers + ledger completed → `COMPLETE`; a stale marker whose trailer names `sprint-1` of another cycle → `stale_marker`, not counted; breaker `cycle_count` 0 with two `-r1` feedback files → 2; a terminal `JACKED_OUT` cache stays.

#### FR-6: heredoc consumer classification
- **D-6.1 Classifier (fail closed).** Behind `destructive_command_guard.heredoc_classifier` (default `true`; `false` = today's scan). Before pattern matching, the fence walks the command text statement by statement (reusing the existing segment splitter) and, for every `<<` / `<<-` heredoc, records its consumer (the statement's command word and every pipe target) and its destination (a `>`/`>>` redirect path, if any). **Interpreter-consumed** (body scanned exactly as today): the command word or any pipe target is a shell or interpreter (`bash`, `sh`, `zsh`, `dash`, `ksh`, `python*`, `node`, `ruby`, `perl`, `eval`, `source`, `.`, `exec`), a wrapper that runs its argument (`sudo`, `env`, `xargs`, `timeout`, `nohup`, `nice`, `setsid`, `ssh`, `docker exec`, `sh -c`, `bash -c`), a command or process substitution (`$(`, `` ` ``, `<(`) anywhere in the statement, an SQL runner from the SQL rule's list, or **any consumer when the destination path appears elsewhere on the same command line as an executed, sourced or `chmod +x`ed path** (`bash x.sh`, `./x`, `source x`, `. x`, `chmod +x x`, `exec x`). **Grammar**: the hook sees literal command text (no alias or function expansion); CRLF is normalised to LF; a body or delimiter containing control characters, a variable-expanded or unquoted-with-expansion delimiter, or a nested heredoc is interpreter-class (full scan); quoted and unquoted delimiters are both recognised; the classifier operates per statement after the existing splitter and never spans a `<<` that the splitter could not pair with its terminator. **Executable content rule**: a heredoc redirected to a path whose extension is `.sh`, `.bash`, `.zsh`, `.py`, `.rb`, `.pl`, `.js`, `.ts`, `.ps1`, whose first body line is a shebang, or whose target lies under `.claude/hooks/`, `.claude/settings*.json`, a shell rc or profile file, a directory on `PATH`, or `.git/hooks/`, is interpreter-class regardless of consumer (the write-then-run-later form; the System-Zone targets are also FR-SZ territory). **Non-executing exact forms** (allowlist of exact command plus safe-flag patterns, with an explicit file or stdout sink): `cat`, `tee`, `printf`, `echo` whose only redirect is a plain file; `gh pr comment -F -`, `gh issue comment -F -`, `gh pr create --body-file -`; `git commit -F -`; `br create`/`br update` reading stdin; `jq`/`yq` without `-i`/`--inplace`; `grep`, `sed -n` (no `e` command), `sort`, `wc`. For these, the body is **scanned per segment**: each body line is split by the existing statement splitter on `;`, `&&`, `||`, `|`, and any `$(`, backtick or `<(` makes the whole body interpreter-class; each segment's command word is taken after wrapper prefixes (`sudo`, `command`, `exec`, `env`, `nice`, `time`, `nohup`, a leading backslash, an absolute path such as `/bin/rm`) are stripped, and a variable-derived command word (`$x -rf`) makes the body interpreter-class; a segment whose command word is a destructive verb the fence already matches (`rm`, `git`, `find`, `dd`, `mkfs*`, `shred`, `truncate`, `kubectl`, `terraform`, `aws`, `gcloud`, `psql`, `mysql`, `DROP`, `DELETE`, `TRUNCATE`) is scanned by the normal rules; other segments are dropped. Argument-level checks: `gh api … --input -`, `jq -i`, `yq -i`, any `-x`/`--exec`/`-c`/`-e` form, `awk` (system()), `sed` with `e`, `make -f -`, `php`, `lua`, `tclsh`, `pwsh`, `osascript`, `kubectl exec -i`, unknown flags, or a second command word in the segment make the consumer interpreter-class. **Default**: a consumer on neither list is scanned in full. A parse failure scans in full. Alias and function expansion are assumed absent (the hook sees the literal command text). The existing quoted-`cat` scrub (`:333-415`) becomes a special case of this rule.
- **D-6.2 Corpus.** New B-rows: the five SP-1 prose cases from NOTES (a spike merge named in a heredoc body written to a `.md`), the P2 force-push string in a heredoc redirected to a file, a `br create --description` heredoc quoting a recursive delete, a `gh pr comment -F -` body naming a force push, a `jq` filter heredoc. New D-rows (every one must block): `bash <<'EOF'` with a root delete, `python3 - <<PY` with `os.system(...)`, `psql <<SQL` with `DROP TABLE`, `bash -c "$(cat <<EOF …)"`, `eval "$(cat <<EOF …)"`, `ssh host bash <<EOF`, `docker exec -i c sh <<EOF`, `sudo bash <<EOF`, `xargs sh -c` fed by a heredoc, `gh api -X DELETE --input -`, `jq -i` and `yq -i` with a destructive body, a heredoc written to `x.sh` followed by `bash x.sh` on the same line, the same with `chmod +x x.sh && ./x.sh`, a `tee x.sh` then `source x.sh`, and an unlisted consumer (`mycmd <<EOF`) with a destructive body. No existing D-row is removed; `run-corpus.sh` p95 stays under 80 ms; a corpus pass with the knob off reproduces today's results.

#### FR-7: advisory open-weight voices
- **D-7.1 Recipe and loader.** The example's Azure block gains `endpoint_family: chat`, `auth_type: http_api`, `dispatch_group: azure`, `context_window`, and loads; a new "Example 4: local OpenAI-compatible server" block declares `type: openai_compat`, `endpoint: "http://127.0.0.1:8000/v1"`, `auth: "local"`, `allow_insecure_endpoint: true`, one model with `endpoint_family: chat`, `auth_type: http_api`, `dispatch_group: local`, `capabilities: [chat]`, `context_window`, `max_output_tokens`, `streaming_recovery: {first_token_deadline_s: 120}`, `pricing: {input_per_mtok: 0, output_per_mtok: 0}`, and an alias. `secret_env_allowlist` is documented beside it. `tests/test_config_examples_load.py` loads every commented example block.
- **D-7.2 Insecure endpoint opt-in (threat model).** `hounfour.providers.<name>.allow_insecure_endpoint: "<host>"` is a host string, not a boolean, and must be an IP literal or `localhost` (no other DNS name: an insecure endpoint is never resolved, so there is no rebinding) whose address is loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`); link-local (`169.254/16`, `fe80::/10`), the cloud metadata address, unique-local IPv6 and every public range are refused. `endpoint-validator.py` (and so `model-health-probe.sh`) and the cheval Python path (`_build_provider_config`) apply the same rule: an `http://` endpoint is accepted only when its host equals the opt-in host; a public `http` host, a mismatched host, a DNS name, or a boolean value fails at load with a named reason; every other provider keeps the scheme, loopback and private-range refusals. For a provider with an insecure opt-in the adapter ignores proxy environment variables, refuses HTTP redirects, and requires every request path to start with the declared endpoint path. Request size is bounded by the declared `context_window`: a dissent or Flatline prompt over it refuses the hop with `context_window exceeded (<n> > <limit>) for <alias>` and writes a MODELINV row with `failure_class: context_window_refused`, never truncating silently; response size is bounded by `max_output_tokens`. Every MODELINV row records `destination: {host, scheme, provider}`. A keyless provider (`keyless: true` or a literal `auth`) is admitted only with a declared `context_window` and `dispatch_group`. Tests cover: IPv4 and IPv6 loopback accepted, RFC1918 accepted, link-local and metadata refused, DNS name refused, redirect refused, proxy env ignored, path prefix enforced, boolean refused.
- **D-7.3 Schema on chat.** `_build_chat_body` adds `response_format: {"type": "json_schema", "json_schema": {"name": ..., "schema": ..., "strict": true}}` when the request carries an output schema and the model entry declares `structured_json`; `schema_enforced` in the MODELINV row is `True` only when the body carried it. `openai_streaming.py` treats `delta.reasoning_content` as progress for the recovery tracker but not as content; after assembly, `<think>…</think>` blocks (and an unterminated leading `<think>`) are removed before qualification, with `thinking_stripped: true` recorded.
- **D-7.4 Advisory voices.** `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` list aliases. `adversarial-review.sh` runs them after the primary and companion, on the same chunks, with the same schema and repair rules, concurrently and under one overall wall-clock timeout (`advisory_timeout_seconds`, default 600) so they cannot delay the verdict; the budget pre-check sums primary + companion + every advisory alias at catalog prices. Their findings are written **only** under `advisory_voices: [{alias, status, counted_as: advisory_voice, findings: [...]}]`, each finding carrying `voice: advisory` and a `duplicate_of` link when a primary or companion finding has the same file, overlapping lines and the same category; the top-level `findings[]`, `voices_planned`, `voices_succeeded` and the `verdict-derive.sh` output are byte-identical with and without advisory voices (`adversarial-review-advisory.bats` asserts all four; DEC-0165). `reviewing-code` and `auditing-security` read the advisory block explicitly (one sentence each). A failed advisory voice is logged under `advisory_voices[].status` and ignored by verdict quality. **Promotion is unreachable this cycle**: no voice arm exists in `run-arms.sh`, so `hounfour.advisory_promotion.*` is read and the check always refuses with `advisory voice <alias> cannot be counted: no arms report line for the alias (voice arms are a future iteration)`; the knob and the refusal text exist so that a later cycle adds only the arm. The family-and-lineage slice itself is deferred (DEC-0132).
- **D-7.5 Bridgebuilder and probe (trusted config, DEC-0170).** `config.ts` extends `PROVIDER_API_KEY_ENV` from the cheval provider config, but reads `hounfour.providers` **only from trusted configuration**: on a pull request, the base branch's `.loa.config.yaml` (the merge target, fetched by ref) or repository settings, never the head checkout; locally, the working tree is trusted. A `keyless` or `allow_insecure_endpoint` provider present only in the head is refused with `head-only provider declaration refused: <name>` and logged; any undeclared provider still fails with `Unknown provider`. The precedence is documented in the Bridgebuilder reference and a vitest covers the head-only case. `model-health-probe.sh --provider <name>` accepts a configured provider name from the same trusted source and probes `<endpoint>/models` with the provider's auth, honouring D-7.2. `bridgebuilder.exit_on_degraded` (default `3`; `0` restores today's exit) is the rollback key for D-7.7.
- **D-7.6 Pricing.** `.claude/defaults/model-config.yaml` entries with `open_weight: true` and a non-zero price require `price_source` (an `https://` URL or a path under `docs/`) and `price_date` (`YYYY-MM-DD`); `tests/test_catalog_pricing_provenance.py` enforces it and the pricing module WARNs (ledger `pricing_source: stale_catalog`) when `price_date` is older than 90 days; no such row is added this cycle. `adversarial-review.sh`'s budget pre-check asks `python3 -m loa_cheval.metering.pricing --alias <primary>` for input/output per Mtok and falls back to 10/30 with a logged line when the price is unknown.
- **D-7.7 Banner and exit (carry-over).** `main.ts:674` passes the count of models whose result status is completed (`mmResult.modelResults.filter(ok).length`); `reportComplete(totalMs, completed, planned)` prints `n/m`. When the consensus verdict is DEGRADED the process exits 3 after writing its JSON; `post-pr-validation` and `run-bridge` treat 3 as completed-degraded (they already read the verdict from the JSON) and surface it.

#### FR-8: local posture
- **D-8.0 Canonical keys.** One key per concept across cheval, `endpoint-validator.py` and Bridgebuilder: `keyless: true` marks a provider that needs no credential (a literal `auth` value is still accepted by cheval and normalised to `keyless` in the merged view); `dispatch_group: local` marks a local provider (no separate `locality: local` provider key). MODELINV rows record both `locality_mode` (the switch) and `hop_locality: hosted|local` (the provider's dispatch group).
- **D-8.1 Switch.** `hounfour.locality: hosted | local_voices` (default `hosted`, the rollback). **Hop inventory** governed by the switch: the dissent primary and companion, the advisory voices, the Flatline primary/secondary/tertiary voices and scorers, the KF-004 repair chain (`tiny`, `claude-headless`, the answering voice), the Bridgebuilder voices and the consensus writer, and the health probe. The Claude Code session model is exempt and the docs say so. Under `local_voices`: `adversarial-review.sh` plans only hops whose provider has `dispatch_group: local` in the merged config, refusing each hosted hop at plan time with `locality: local_voices refuses hosted hop <alias> (<provider>)`; every local hop is dispatched under the D-7.2 request-time rules (IP-literal or `localhost` endpoint, no DNS resolution, redirects refused, proxy environment ignored, the endpoint address logged in MODELINV `destination`), so a declared locality is enforced, not trusted; the KF-004 repair chain is pinned to the answering voice (no `tiny`, no `claude-headless`); `flatline-orchestrator.sh` refuses hosted voices the same way; Bridgebuilder's `config.ts` drops hosted models with the same reason; the probe refuses hosted providers. cheval records `locality` in every MODELINV row. With one local family, the companion is `duplicate_voice` by the existing rule and the audit envelope is `DEGRADED_SECURITY_REVIEW`; `adversarial-review-gate.sh` and `verdict-derive.sh` treat that envelope exactly as they do today (the artefact gate checks presence, the verdict is the auditor's, the degradation is stated in the envelope and the audit report and shown by `/loa`); the config comment and the audit output say so in one sentence.
- **D-8.2 Tests.** Planning bats: under the switch, a config with one hosted and one local provider plans only the local hop and names the refusal; the repair chain is the answering voice; MODELINV rows carry `locality: local_voices`; the docs sentence is present.

#### FR-9: profile knob
- **D-9.1 Data and lib.** `.claude/data/profiles.yaml` lists, per profile, the optional keys it sets: `known_failures.surface_at_session_start`, `decisions.surface_at_session_start`, `karpathy_principles.surgical_diff_warning`, `karpathy_principles.require_success_criteria`, `guardrails.input.enabled`, `guardrails.danger_level.enforce`, `invisible_retrospective.enabled`, `structured_handoff.enabled`, `soul_identity_doc.enabled` (`interview.pacing` is not a profile key: `rounds` is already the `thorough` default and the key would not discriminate between profiles). Every profile defines every key explicitly (a `profile-lib.bats` case asserts it), so `loa_knob`'s fallback argument is never the effective source of a default. `profile-lib.sh` resolves the effective values once per session into `.run/effective-config.json` keyed on the mtimes of `.loa.config.yaml` and `profiles.yaml` and serves `loa_knob` from it. `lean` sets them off (pacing `rounds`); `standard` is the post-cycle-129 example default for each key, written out explicitly (so `guardrails.*` read `false` there, the FR-4(d) change being a migration item, not a profile effect); `full` sets them on. `.claude/scripts/lib/profile-lib.sh` exposes `loa_profile` (explicit `loa.profile`, else `standard`) and `loa_knob <yq-path> <fallback>`: the explicit key when present, else the profile's value when the key is in `profiles.yaml`, else the fallback. Every reader in §1.3 calls `loa_knob` instead of its own `yq` default.
- **D-9.2 Floor.** One tracked floor source, `.claude/data/floor.yaml` (DEC-0166), lists the floor guard ids (`fence:FR-1.2b`, the `FR-SZ*` ids, `gate:verdict-derive`, `gate:adversarial-review-gate`, `policy:permission-deny-list`, `policy:verdict-one-way-rule`, `policy:operator-only-commands`) and the floor config keys (`flatline_protocol.code_review.enabled`, `flatline_protocol.security_audit.enabled`, `flatline_protocol.*.companion_voice`, `destructive_command_guard.*`, `implement_gate.*`, `hounfour.locality`). `guard-origins.bats` checks `floor: true` rows against it, `profile-floor.bats` checks that `profiles.yaml` names none of its keys, and both pin the file's sha256 so an edit fails until the hash is deliberately updated. `profile-floor.bats` further asserts that, under `lean`, the floor surfaces (the two gate skills' effective config, `verdict-derive.sh` behaviour on a fixture, the adversarial gate env, the deny-list file hash, the FR-1.2b corpus rows, the SZ rules, `user-invoked-commands.txt`) are byte-identical to `standard`. The register gains `kind: policy` for the floor items that are not hooks, fences, validator rules or gates.
- **D-9.3 Visibility.** `loa-status.sh` prints `Profile: lean (overrides: guardrails.input.enabled=true)` listing explicit keys that differ from the profile.

#### FR-10: task kinds
- **D-10.1 Syntax.** A task line ends `… → **[G-N]** ⇐ <deps> · kind: mechanical|judgment|operator`. `validate-artifact.sh --type sprint` requires it on every `- [ ]` line under `### Technical Tasks` (and the `### Task N.E2E` block) for plans whose `**Date:**` header is on or after `KINDS_REQUIRED_FROM="2026-10-14"` (WARN before), reusing the Seams gate's date parsing (`:879-938`): `YYYY-MM-DD`, lexical comparison, and a live plan with no parseable date is a violation. **Parser**: exactly one `kind:` token per task line, whitespace-tolerant around the colon, the value one of the three words, and nothing but whitespace after the value (trailing prose is a violation); the dependency marker may be absent. A WARN (not a violation) fires when a task tagged `judgment` names only `*.sh`, `*.py`, `*.ts` deliverables or the verbs script, lint, generate. The template and this cycle's `sprint.md` carry it. The framework glossary defines the three kinds: *mechanical* (a script could do it reliably; ships as code with tests), *judgment* (needs reading and a decision; ships as prose or a reviewed artifact), *operator* (belongs to the human; unattended completion is flagged).
- **D-10.2 Review axis.** `reviewing-code/SKILL.md` spec axis gains: "A `kind: mechanical` task delivered as skill prose or instructions the model re-executes is a MEDIUM (Karpathy ladder); a `kind: operator` task completed unattended without a `decision:unblock` ticket or a DEC row is a MEDIUM." The bytes come from the `@skill-include trajectory_logging` block's duplicated sentence about log paths (the include already states it once in `trajectory_logging.md`); the implementer records the removed text in the sprint report and the lead confirms it is not load-bearing.
- **D-10.3 Ratio.** `tools/cycle-ratio.sh --from <sha> --to <sha> [--sprint-plan grimoires/loa/sprint.md]` prints two lines with a stated mapping: `kinds: mechanical N · judgment N · operator N` (counted from the plan's task lines) and `volume: script lines changed N (*.sh *.py *.ts *.js) · prose bytes changed N (*.md) · model calls N (MODELINV rows between the two commits' timestamps) · scope: host · modelinv: <path>`; the model-call count is host-local and says so; the release-notes report template gains both lines and the glossary defines them.

### 1.6 Floor statement
`/review-sprint`, `/audit-sprint`, `verdict-derive.sh`, the LOA-VERDICT one-way rule, `adversarial-review-gate.sh`, the permission deny list, fence FR-1.2b, the FR-SZ and FR-SZ2 rules, and the FR-8 operator-only commands are not touched by any task in this cycle; `tests/unit/profile-floor.bats` and the unchanged corpus D-rows are the proof.

> Sources: PRD FR-1 … FR-10, Appendix E; S:inv §A–§G; S:yield §5, §7; S:ow §2, §4, §7; `implement-gate.sh:5-12,61-71`; `run-mode/SKILL.md:131-160`; `block-destructive-bash.sh:333-415`; `openai_adapter.py:323-341`; `adversarial-review.sh:2397-2419,3427-3445,3927-3929`; `config.ts:135-139,384-392`; `main.ts:674`; `progress.ts:149`; `compare.sh:37-43`; `evals/fixtures/review-prs/manifests/pr-01.json`

---

## 2. Software Stack

| Layer | Technology | Version pin | Why |
|---|---|---|---|
| Hooks, scripts, lints | Bash 3.2-compatible (no `${var,,}`, no `${var^^}`) | bash ≥ 3.2 | the `${rel,,}` fail-open on macOS is in the record |
| Data | YAML (yq v4), JSON (jq 1.6+), TSV | yq 4.x, jq 1.6 | existing dependencies; `IN` builtin avoided |
| cheval | Python 3 | 3.11 | existing adapter package with pytest |
| Bridgebuilder | TypeScript, Node | Node 20, vitest | existing skill |
| Tests | bats-core, pytest, vitest | existing | one suite per seam |
| CI | GitHub Actions Shell Tests (~60 min), Prompt Budget | existing | the lints run there |

> Sources: feedback_cross_runtime_parity_traps; S:yield §2; CHANGELOG F-002/F-012 (jq 1.6 `IN`)

---

## 3. Database Design

### 3.1 `.claude/data/guard-origins.yaml` (tracked, hand-written)
```yaml
schema_version: 1
guards:
  - id: fence:FR-1.2b
    kind: fence
    class: harness
    status: active
    origin: { kind: issue, ref: "#555" }
    knob: none
    floor: true
    note: "stash push/pop with swallowed output; recurred cycle-122"
  - id: hook:compliance/implement-gate.sh
    kind: hook
    class: harness
    status: telemetry
    registrations: ["PreToolUse:Write|Edit|MultiEdit|NotebookEdit"]
    origin: { kind: cycle, ref: "cycle-050 FR-7" }
    knob: implement_gate.mode
    floor: false
  - id: hook:safety/team-role-guard.sh
    kind: hook
    class: harness
    status: dormant
    registrations: ["PreToolUse:Bash"]
    origin: { kind: cycle, ref: "cycle-agent-teams" }
    knob: LOA_TEAM_MEMBER
    floor: false
```
Invariants: `id` unique; `origin.ref` non-empty; `floor: true` set equals the PRD floor; `kind`, `class` and `status` enumerated; `dormant` rows name an env var in `knob`; hook rows list `registrations`.

### 3.2 `grimoires/loa/guards.md` (tracked, generated, structural) and `.run/guard-yield.{md,json}` (untracked, host yield)
Fields as D-1.4. The tracked file is a pure function of the repository and `--check` is its drift gate; the `.run` files carry the 30-day host yield and are regenerated on demand.

### 3.3 `evals/fixtures/review-prs/pr-NN/fixture.yaml` and `labels.tsv`
`fixture.yaml`: `sprint, base_commit, head_commit, fix_commit, record_branch, feedback_files[]`. `labels.tsv` columns: `defect_id, severity, category, file, must_match, source`; `source` is a `record/<branch>:<path>#<heading>` pointer. `corpus.tsv` gains the rows; `SHA256SUMS` covers every new file.

### 3.4 Derived run state (`.run/sprint-plan-state.json`, `.run/circuit-breaker.json`)
Same keys as `run-mode/resources/state-schemas.md` plus `derived_at`, `derivation.source`, `derivation.stale_markers[]`; `.state` canonical, `.status` mirror.

### 3.5 `.claude/data/profiles.yaml`
```yaml
schema_version: 1
profiles:
  lean:     { known_failures.surface_at_session_start: false, decisions.surface_at_session_start: false, karpathy_principles.surgical_diff_warning: false, karpathy_principles.require_success_criteria: false, guardrails.input.enabled: false, guardrails.danger_level.enforce: false, invisible_retrospective.enabled: false, structured_handoff.enabled: false, soul_identity_doc.enabled: false, interview.pacing: rounds }
  standard: { }   # today's defaults, expressed explicitly by the implementer
  full:     { ...all true, interview.pacing: rounds }
floor_keys_forbidden: [flatline_protocol.code_review.enabled, flatline_protocol.security_audit.enabled, "flatline_protocol.*.companion_voice", "destructive_command_guard.*", "implement_gate.*", hounfour.locality]
```

### 3.6 Catalog fields and MODELINV
`model-config.yaml` entries: optional `open_weight: true`, `price_source`, `price_date`. MODELINV rows: `locality: hosted|local_voices`, `thinking_stripped: bool`. Dissent envelope: `advisory_voices[]` and per-finding `voice: advisory`, `counted_as: advisory_voice`.

### 3.7 Audit rows written by this cycle
Implement-gate telemetry rows (D-4.1) use the existing plain-hook log shape; nothing enters the signed `audit_emit` chain.

> Sources: `.run/audit.jsonl` key shapes; `state-schemas.md` §circuit-breaker-schema; `evals/fixtures/review-prs/corpus.tsv`; `modelinv.py:514,600-601`

---

## 4. UI Design

### 4.1 `/loa` lines
```
Guards:  78 (0 without origin) · 30 d: 105 real blocks, 96 likely FP · scope host · regenerate: .claude/scripts/guard-yield.sh
Profile: standard (explicit overrides: none)
Run:     files say COMPLETE, cache said RUNNING (drift) → run-checkpoint.sh derive --write
```

### 4.2 `guards.md` row
`| fence:FR-1.2b | harness | issue #555 | none | yes | 0 | 0 | none in window |`

### 4.3 Refusal and telemetry texts
- Implement gate deny: `App Zone write with no active implementation run (derived position: COMPLETE); run /implement or /bug, or set implement_gate.mode: telemetry`.
- Locality: `locality: local_voices refuses hosted hop gpt-5.5 (openai); declare a local provider or set hounfour.locality: hosted`.
- Promotion: `advisory voice <alias> cannot be counted: hounfour.advisory_promotion is unset (or no arms report line for the alias)`.
- Compare: `arms captured under different executor model ids (A: …, B: …); comparison refused`.

### 4.4 Sprint task line
`- [ ] Task 1.1: Seed guard-origins.yaml for every registered hook and fence id → **[G-1]** ⇐ none · kind: mechanical`

> Sources: PRD §User Experience; `loa-status.sh:901-926` (Providers block as the pattern)

---

## 5. API Specifications

### 5.1 `guard-yield.sh`
`guard-yield.sh [--window-days 30] [--audit-log PATH] [--origins PATH] [--out grimoires/loa/guards.md] [--hooks-table] [--check] [--json]`. Exit 0 written or in sync; 1 drift (`--check`, with the regenerate hint); 5 a guard without origin or a hook command outside the canonical schema; 2 usage; 3 unreadable inputs (a missing audit log is a WARN and an empty yield, not an error).

### 5.2 `run-checkpoint.sh` new verbs
- `record-round --gate review|audit --file PATH [--sprint sprint-N] [--file-state F] [--breaker F]` → exit 0; prints `TRIPPED: <trigger>: <reason>` and exits 10 on a trip.
- `derive [--json] [--write] [--root DIR]` → exit 0; `--json` prints the derivation; `--write` rewrites the caches; exit 4 when the ledger has no active cycle.

### 5.3 `profile-lib.sh`
`loa_profile` → `lean|standard|full`; `loa_knob <yq-path> <fallback>` → the effective value; `loa_profile_overrides` → `key=value` lines that differ from the profile.

### 5.4 `evals/harness/run-arms.sh`, `seed-corpus-from-record.sh`, `report.sh --arms`
As D-2.2 and D-2.3; `run-arms.sh` exits 0 when every arm completed its trials, 1 when any trial failed (results kept), 2 usage.

### 5.5 `tools/cycle-ratio.sh`
`cycle-ratio.sh --from SHA --to SHA [--json]` → the three counts and the ratio line.

### 5.6 Config keys added
`implement_gate.mode`, `implement_gate.claims`, `loa.profile`, `hounfour.locality`, `hounfour.advisory_promotion.{min_recall_ratio,max_refuted_delta}`, `hounfour.providers.<p>.allow_insecure_endpoint` (host string), `hounfour.providers.<p>.keyless`, `flatline_protocol.{code_review,security_audit}.advisory_voices`, `run_mode.stale_hours`, `run_mode.file_authoritative`, `destructive_command_guard.heredoc_classifier`; env `LOA_IMPLEMENT_GATE_OVERRIDE`; catalog `open_weight`, `price_source`, `price_date`. Rollback keys (DEC-0158): `implement_gate.mode: ask`, `destructive_command_guard.heredoc_classifier: false`, `run_mode.file_authoritative: false`, `hounfour.locality: hosted`, `loa.profile: standard`.

### 5.7 Validator contracts
`--type sprint`: `kind:` required from 2026-10-14. `--type prd`, `--type sdd`: unchanged.

> Sources: `run-checkpoint.sh` usage; `compare.sh:29-43`; PRD FR-1, FR-4(f), FR-5, FR-9, FR-10

---

## 6. Error Handling Strategy

| Situation | Behaviour |
|---|---|
| Audit log missing or unparseable rows | WARN, skip bad rows, count them in the header; never crash |
| Origin map missing | `guard-yield.sh` exits 3 naming the path; the lint fails |
| Derivation inputs missing (no ledger, no a2a dir) | `derive` exits 4 with a named reason; callers keep the cache |
| `verdict-derive.sh` non-zero on a feedback file | the round counts as findings (today's rule); the derivation marks the sprint incomplete |
| Fence classifier cannot parse a heredoc | fall back to scanning the whole body (today's behaviour): fail-closed |
| Local server unreachable | typed cheval error; an advisory voice failure never changes the verdict; a local *primary* unreachable under `local_voices` fails the hop like any primary and the existing verdict-quality rules decide FAILED or DEGRADED |
| Local server rejects `response_format` (HTTP 400 naming it) | one retry without the schema, `schema_enforced: false` and `schema_rejected_by_server: true` recorded; the tolerant parser and repair loop apply as for any unenforced voice |
| Feedback file without a LOA-VERDICT trailer in `derive` | legacy: no verdict, the sprint stays incomplete, the file is named in `derivation.legacy_feedback` |
| Hook command outside the canonical schema | `guard-yield.sh` exit 5 naming the command; the lint fails |
| Hosted hop under `local_voices` | refused at plan time with the named reason; never silently rerouted |
| Profile key for a floor surface | schema test fails; `profile-lib.sh` ignores it with a WARN |
| Arm run incomplete | D-2.4 fallback; the report names the missing arm |
| Bridgebuilder DEGRADED | exit 3; callers surface it |

> Sources: PRD NFR Reliability; S:ow §4 (typed aborts); `implement-gate.sh` fail-ask contract

---

## 7. Testing Strategy

| Seam | Test | Catches | Misses |
|---|---|---|---|
| `guard-yield.sh` over a fixture audit log + fixture origins | `tests/unit/guard-yield.bats` | replay exclusion, FP heuristic, header counts, drift `--check` | the heuristic's false negatives |
| settings.json ↔ origin map | `tests/unit/guard-origins.bats` | a hook or fence id without origin | validator rules not listed |
| `execute-agent.sh` arm toggles on a sandbox tree | `evals/tests/arm-toggles.bats` | a toggle that leaves text or config behind | prompt caching effects |
| `seed-corpus-from-record.sh` on a fixture record tree | `evals/tests/seed-corpus.bats` | malformed labels, secrets, missing commits | label quality |
| `compare.sh --ab` with skewed model ids | existing `recall-baseline-freshness.bats` + new case | cross-model comparison | — |
| implement gate modes | `tests/unit/implement-gate.bats` | deny/telemetry/ask outputs, trust-input ask, cache read | the live harness contract |
| skill lint | `tests/unit/skill-capabilities.bats` | pure-review skill without the strip | — |
| surgical-diff per task | `tests/unit/karpathy-surgical-diff.bats` | reset on task change, summary file, bounded dir | — |
| kernel generation without C-TEAM | `tests/unit/lint-invariants.bats` | table still emitted | — |
| breaker in script | `tests/unit/run-checkpoint-record-round.bats` | counts, hash reset, trip, HALTED | — |
| derivation | `tests/unit/run-checkpoint-derive.bats` | drift resolution, stale marker, terminal states | a forged trailer with a matching sprint id |
| fence corpus | `tests/fixtures/fence-corpus/run-corpus.sh` | every D-row still blocks; new B-rows allow; latency | commands outside the corpus |
| chat schema, think strip | `tests/test_openai_chat_schema.py`, `test_openai_thinking_strip.py` | body without `response_format`, `schema_enforced` lie, `<think>` leakage | server-side schema behaviour |
| example configs load | `tests/test_config_examples_load.py` | the Azure defect class | — |
| insecure endpoint opt-in | `tests/test_endpoint_validator_optin.py` | opt-in leaking to other providers | — |
| advisory accounting | `tests/unit/adversarial-review-advisory.bats` (mock mode) | envelope changed by an advisory voice; missing tags | real-model behaviour |
| budget gate pricing | `tests/unit/adversarial-review-budget.bats` | fixed-rate fallback not logged; unknown price | — |
| locality | `tests/unit/adversarial-review-locality.bats`, `flatline-locality.bats`, vitest for `config.ts` | hosted hop planned; repair chain leaving | — |
| catalog provenance | `tests/test_catalog_pricing_provenance.py` | open-weight price without source/date | — |
| Bridgebuilder banner/exit | `__tests__/progress.test.ts`, `main` exit test | configured-vs-completed count; exit 0 on DEGRADED | — |
| profiles | `tests/unit/profile-lib.bats`, `profile-floor.bats` | floor key, override precedence, standard ≠ today | — |
| sprint kinds | `tests/unit/validate-artifact-sprint-kinds.bats` | untagged task on a dated plan | — |
| cycle ratio | `tests/unit/cycle-ratio.bats` | counts on a fixture repo | — |

Pre-PR checks: `check-no-raw-sha256sum.sh`, the shell-compat greps, `sync-fixtures.sh --check`, `check-prompt-budget.sh`, `guard-yield.sh --check`, `repo-map-gen.sh`.

> Sources: PRD AC-1 … AC-10; feedback: pipe-masked bats runs (capture then validate)

---

## 8. Development Phases

### Sprint 1 (global 255): measure
FR-1 (origin map seeded, `guard-yield.sh`, `guards.md`, hooks-reference table, lint, `/loa` line); FR-2 (arms declared, toggles, corpus seeding script and eight fixtures, report, `run-arms.sh` started detached at sprint end); FR-10 (validator, template, review axis, `cycle-ratio.sh`; this plan tagged); FR-3 path-scoping; doc fixes (workflow comment, `implementing-tasks/SKILL.md:28`); KF-041 upstream issue filed and recorded; CHANGELOG.

### Sprint 2 (global 256): thin and repair
FR-5 derivation first (Task 2.10), then FR-4 (a)–(f) with this repository kept on `ask`; FR-6 classifier and corpus rows; FR-9 profiles, lib, readers, floor test, `/loa` line; FR-3 kernel rows and cap as the last task (reading `STATUS.json`, with the D-2.4 fallback); `implement_gate.mode` documented; apply-time smoke runs; CHANGELOG.

### Sprint 3 (global 257): open voices
FR-7 (loader examples, insecure-endpoint opt-in, chat schema and thinking strip, advisory voices, Bridgebuilder key map and probe, catalog provenance and budget gate); FR-8 locality; Bridgebuilder banner and exit; the release-notes ratio line; E2E goal validation (G-1 … G-9); docs; CHANGELOG.

> Sources: PRD §Timeline; DEC-0135

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| The arm run does not finish inside the cycle | D-2.4: ship path-scoping and pointers; defer deletions with a named bead |
| The derivation disagrees with a live run | it runs at checkpoints only; never moves a terminal state to RUNNING; readers keep the cache shape |
| The fence classifier opens a hole | corpus D-rows pin interpreter forms; the two-step form is fenced at the second command; p95 budget |
| Profiles reach the floor by a key the test does not list | the forbidden-key list is in the data file and the test checks the file, not the code |
| Advisory voices cost tokens for no verdict | opt-in list, empty by default; findings still reach the reviewer |
| `exit 3` from Bridgebuilder breaks a caller | both callers updated in the same task; a vitest case per caller path |
| Guard code generates review load (E2) | tighten-only; one bats per item; three dissent runs at most |
| Kernel diet breaks the prompt-budget CI on the way down | cap lowered in the same commit as the diet |

> Sources: PRD §Risks; S:yield E2, §4

---

## 10. Open Questions
Every question raised by the PRD is resolved; the design-level resolutions below are DEC rows.

| # | Question | Status | Resolved by | DEC |
|---|---|---|---|---|
| 1 | Implement gate deny or telemetry | Resolved | D2, D-4.1 | DEC-0126 |
| 2 | Promotion threshold | Resolved | D3, D-7.4 | DEC-0127 |
| 3 | `lean` default | Resolved | D4, D-9.1 | DEC-0128 |
| 4 | Path-scoping key | Resolved | D5, D-3.1 | DEC-0129 |
| 5 | Fleet logs | Resolved (later) | D6, D-1.3 | DEC-0130 |
| 6 | First hosted open-weight price | Resolved (none) | D7, D-7.6 | DEC-0131 |
| 7 | How the arms run inside the cycle | Resolved | D-2.3, D-2.4 (A1) | DEC-0149 |
| 8 | Bridgebuilder exit code on DEGRADED | Resolved | D-7.7 (A2) | DEC-0150 |
| 9 | How the gate reads run position | Resolved | D-4.1, D-5.3 (A3) | DEC-0151 |
| 10 | Where profile defaults live | Resolved | D-9.1 (A4) | DEC-0152 |
| 11 | How advisory voices are declared | Resolved | D-7.4 (A5) | DEC-0155 |
| 12 | Corpus provenance | Resolved | D-2.2 (A6) | DEC-0153 |
| 13 | `kind:` syntax and date | Resolved | D-10.1 (A7) | DEC-0144 (the date, PRD D20), DEC-0154 (the line syntax, A7) |
| 14 | Where advisory findings live | Resolved | D-7.4 (A8) | DEC-0165 |
| 15 | One floor source | Resolved | D-9.2 (A9) | DEC-0166 |
| 16 | How replay rows are marked | Resolved | D-1.3 (A10) | DEC-0167 |
| 17 | Arm executor model | Resolved | D-2.3 (D33) | DEC-0164 |

> Sources: PRD Appendix E; decisions.yaml DEC-0125 … DEC-0155

---

## 11. Appendix

### 11.1 File inventory
See §1.3. New files: `guard-origins.yaml`, `guard-yield.sh`, `guards.md`, `guard-origins.bats`, `guard-yield.bats`, `profiles.yaml`, `profile-lib.sh`, `profile-lib.bats`, `profile-floor.bats`, `seed-corpus-from-record.sh`, `run-arms.sh`, eight fixtures, `arm-toggles.bats`, `seed-corpus.bats`, `run-checkpoint-record-round.bats`, `run-checkpoint-derive.bats`, `karpathy-surgical-diff.bats`, `adversarial-review-advisory.bats`, `adversarial-review-budget.bats`, `adversarial-review-locality.bats`, `flatline-locality.bats`, `test_openai_chat_schema.py`, `test_openai_thinking_strip.py`, `test_config_examples_load.py`, `test_endpoint_validator_optin.py`, `test_catalog_pricing_provenance.py`, `validate-artifact-sprint-kinds.bats`, `cycle-ratio.sh`, `cycle-ratio.bats`, `.claude/protocols/process-compliance.md`.

### 11.2 PRD → SDD map

| PRD | SDD |
|---|---|
| FR-1 | D-1.1 … D-1.6, §3.1, §3.2, §5.1 |
| FR-2 | D-2.1 … D-2.4, §3.3, §5.4 |
| FR-3 | D-3.1 … D-3.3, §1.4 |
| FR-4 | D-4.1 … D-4.6, §5.2 |
| FR-5 | D-5.1 … D-5.4, §3.4 |
| FR-6 | D-6.1, D-6.2 |
| FR-7 | D-7.1 … D-7.7, §3.6 |
| FR-8 | D-8.1, D-8.2 |
| FR-9 | D-9.1 … D-9.3, §3.5, §5.3 |
| FR-10 | D-10.1 … D-10.3, §5.5 |

### 11.3 Decisions taken on the operator's behalf (this SDD, `proposed` rows)

| # | Decision | Alternatives | Why | DEC |
|---|---|---|---|---|
| A1 | The FR-2 arms run as a detached driver started at the end of Sprint 1 on an Opus 5.5 executor; Sprint 2 waits for the result and falls back to path-scoping plus pointers if it does not arrive | run the arms inline in Sprint 1 | 8 fixtures × 5 arms × 3 trials is hours of executor time; the driver runs while Sprint 2 builds | DEC-0149 |
| A2 | Bridgebuilder exits 3 on a DEGRADED verdict and reports completed/planned voices; the two callers accept 3 as completed-degraded | keep exit 0 and fix the banner only | an exit code is the only signal a caller that does not parse JSON can see | DEC-0150 |
| A3 | The implement gate reads the derived cache written by `run-checkpoint.sh`; it never computes the derivation itself | derive inside the hook | a hook on every write must stay under the latency budget | DEC-0151 |
| A4 | Profile defaults live in `.claude/data/profiles.yaml` with a forbidden-floor-key list; `profile-lib.sh` resolves explicit key → profile → fallback | hard-code the table in the lib | a data file is reviewable and the floor test reads it | DEC-0152 |
| A5 | Advisory voices are declared as `flatline_protocol.<gate>.advisory_voices: [alias]`, run after primary and companion, merged with `counted_as: advisory_voice`, never in `voices_planned` | reuse `companion_chain` with a flag | the companion chain decides quorum; advisory voices must not touch it | DEC-0155 |
| A6 | The corpus fixtures are generated from git and the record branches by a script with the lead curating `must_match` anchors; labels are finding titles only | hand-write eight fixtures | reproducible from git; the anchors need a human eye once | DEC-0153 |
| A7 | `kind:` sits at the end of the task line after the dependency marker; the validator uses the Seams gate's date parsing | a separate `### Task kinds` table | one field per task line is what the reviewer reads | DEC-0154 |
| A8 | Advisory-voice findings live only in `advisory_voices[].findings` with `duplicate_of` links; the top-level findings, voice counts and `verdict-derive.sh` output are byte-identical with and without them; amends A5 | merge with a tag | a tag is a convention a consumer can ignore (SDD review opus IMP-004) | DEC-0165 |
| A9 | One tracked floor source `.claude/data/floor.yaml` read by the floor tests and the register, sha256-pinned; register kind `policy` for floor items that are not hooks, fences, rules or gates | the floor list in each test | copies drift (opus IMP-009, IMP-017) | DEC-0166 |
| A10 | Replay rows are marked at the source with `LOA_AUDIT_REPLAY=1` → `replay: true`; the cwd heuristic is the fallback for older rows | cwd heuristic only | a test run inside the repo would count as real (opus IMP-008) | DEC-0167 |

Sprint-planning decisions recorded after the sprint-plan review (PRD Appendix E D34–D37): the self-hosting rule (DEC-0168), the evidence classes for kernel rows (DEC-0169), Bridgebuilder's trusted config source (DEC-0170), and the two-batch arm schedule amending A1 (DEC-0171).

### 11.5 Sprint-plan Flatline review (2026-10-14)
The sprint-plan run (same two voices, same degraded shape, eleven skeptic blockers) changed this design in four places: §1.2 self-hosting rule and the deferred `deny` flip (SKP-005); D-3.2 evidence classes (SKP-002); D-7.5 trusted configuration source and the exit-code rollback key (SKP-008, gpt IMP-012); D-7.2 rules applied at request time to every local hop in D-8.1 (SKP-012); D-6.1 grammar, nested and variable-delimiter heredocs, control characters and the hook, settings, rc, PATH and `.git/hooks` targets (SKP-006, SKP-004); D-2.3 two batches, `MANIFEST.json`, interleaved trials, `failed` state (SKP-001, SKP-002 isolation); D-7.6 freshness WARN (gpt IMP-010). The sprint plan's Appendix D carries the full record.

### 11.4 Flatline review integration (2026-10-14)
Run on the pre-integration SDD: two voices (`gpt-5.5`, `claude-headless`), cross-scoring degraded (KF-041, exit 6), ten skeptic blockers, integrated by judgment. SKP-005 (silent default change) → `ask` stays the default, asks logged (D-4.1, DEC-0163); SKP-006 (deny with a missing or stale cache, first-write race) → unknown position falls back to `ask`, the implementing skills checkpoint before their first write (D-4.1); SKP-001 and SKP-011 (fence inversion, side-effecting tools, wrapper prefixes, substitutions) → exact-form allowlist with safe flags, per-segment body scan, wrapper stripping, substitution and variable-command detection, the named executors added to the interpreter class (D-6.1); SKP-012 (write-then-run-later) → executable-extension and shebang rule (D-6.1), separate-line execution stated as the per-command limit the Write tool already shares; SKP-004 (statistical power) → bootstrap interval, retry policy, missed-label review before deletion (D-2.3); SKP-002 (unpinned sandbox source, path-scoping confounds the baseline, kernel regeneration undoes a toggle) → pinned worktree at `864069f2`, `source_commit` recorded and refused when mixed, toggle asserted at executor start, `constraints.json` toggled too (D-2.3); SKP-001 (endpoint SSRF) → IP-literal or `localhost` only, no DNS, link-local and metadata refused, redirects refused, proxy env ignored, path prefix enforced, test list (D-7.2); SKP-002 (grep-based enumeration) → canonical hook command schema parsed with jq, `# @guard fence:<id>` markers cross-checked against call sites, unparseable commands fail the lint (D-1.2); SKP-007 (tracked yield can never match in CI) → structural register tracked, yield untracked under `.run` (D-1.4, DEC-0162). Per-voice improvements folded: gpt IMP-001 (identity per script with registrations), IMP-002 (FP heuristic uses the FR-6 classifier), IMP-003 and opus IMP-023 (`STATUS.json`, Sprint 2 gate, no waiting), IMP-004 and opus IMP-024 (fix-hunk labels, refuted share), IMP-005 and opus IMP-016 (spread, bootstrap interval), IMP-006 (commit selection constrained to the cycle), IMP-007 and opus IMP-028 (schema tolerance, terminal set), IMP-008 and opus IMP-006 (opt-in lifts only loopback and RFC1918), IMP-009 and opus IMP-004/IMP-012 (advisory block only, `duplicate_of`, budget sum, timeout; A8), IMP-010 (kind parser), IMP-011 (config-key AC in Tasks 2.9 and 3.6), IMP-012 (generated files regenerated in the same commit and `--check` in CI); opus IMP-001 (structural register), IMP-002 (cap never rises), IMP-003 (pinned worktree, source recorded), IMP-005 (unknown cache → ask; `run-resume` writes on drift), IMP-007 (substitution D-rows), IMP-008 (`LOA_AUDIT_REPLAY`; A10), IMP-009 and IMP-017 (`floor.yaml`, kind `policy`; A9), IMP-010 (promotion unreachable, stated), IMP-011 (every profile defines every key), IMP-014 (harness probe for `disallowed-tools`), IMP-015 (Fable executor; D33), IMP-018 (effective-config cache), IMP-019 (explicit predicate), IMP-020 (error rows), IMP-021 (canonical keys), IMP-025 (`locality_mode` and `hop_locality`), IMP-026 (gate behaviour under DEGRADED_SECURITY_REVIEW), IMP-027 (coverage and arm arithmetic), IMP-029 (task-name sanitisation, legacy file removed), IMP-030 (`/loa` prints the gate mode), IMP-031 (DEC references fixed), IMP-032 (the bytes to remove named), IMP-034 (paths frontmatter observation), IMP-035 (ratio provenance), IMP-036 (informational arms), IMP-037 and IMP-038 (tests and component rows), IMP-039 (exit codes), IMP-040 (pacing dropped from profiles), IMP-041 (judgment-tag WARN). **Declined**: opus IMP-013 (a new PostToolUse hook to call `record-round`: `derive` at every checkpoint already recomputes the counters from the feedback history, and this cycle adds no guard without an origin); opus IMP-022 (moving FR-6 to Sprint 1: Sprint 1 is already the larger sprint; the intra-sprint ordering FR-5 before FR-4(a) is kept as a bead dependency); opus IMP-033 (tagging the KF-041 issue task `operator`: the maintainer's end-to-end instruction and DEC-0134 are the record, and the review flags an unattended operator task by design).

> Sources: PRD Appendix E; proposals.md A1–A3, B1–B7; S:inv, S:yield, S:ow as cited above

---

*Generated by Architecture Agent*
