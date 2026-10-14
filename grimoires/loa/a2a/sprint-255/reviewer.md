# Implementation Report: Sprint 255 (cycle-129 Sprint 1) — guard register and yield, control arms, task kinds, rule path-scoping

**Date:** 2026-10-14
**Engineer:** lead (Claude Fable 5.1, model id `global.anthropic.claude-fable-5-1`) integrating implementers A, B and C (Claude Opus 5.5 subagents, model id `global.anthropic.claude-opus-5-5`; their reports: `reviewer-a.md`, `reviewer-b.md`, `reviewer-c.md` in this directory)
**Sprint Reference:** grimoires/loa/sprint.md (## Sprint 1, Tasks 1.0 … 1.11)
**Version:** 1.0
**Base:** plan commit `ffd25258`; patches `~/.cache/loa/cycle-129/patches/s1-{a,b,c}.patch` applied with `git apply --3way --index` in the main checkout

---

## Executive Summary

Sprint 1 built the instruments. Every guard Loa ships now has a row with an origin: `.claude/data/guard-origins.yaml` holds 95 rows (30 hook scripts, 34 fence pattern ids, 19 validator rules, 9 gates, 3 floor policies), `.claude/data/floor.yaml` is the one source of the 21 floor guard ids and the floor config keys, and `.claude/scripts/guard-yield.sh` enumerates the guards from the repository, fails on any gap (exit 5), writes the tracked structural register `grimoires/loa/guards.md`, the untracked host yield `.run/guard-yield.{md,json}` and the generated hooks-reference registration table, and runs as a CI drift gate (`--check`). The lint earned its keep on its first day: implementer C added the `validator:sprint.kinds` marker and implementer A's map had no row for it, so integration stopped at exit 5 until the lead added the row (origin `cycle-129 D-10.1 (DEC-0144)`). This host's 30-day yield reads 159 blocks, 87 real, 72 likely false positives, 342 replay rows excluded (`scope: host`; the replays carry the repository root as cwd, so A added a burst heuristic alongside the flag and the cwd fallback).

The recall evals now pre-register their control arms and a verdict threshold. `execute-agent.sh` applies an arm to the sandbox copy immediately before the executor starts and fails a trial whose toggle cannot take effect. Eight record fixtures (`pr-11` … `pr-18`, sprints 247–254) carry 55 lead-approved feedback labels and 810 fix regions; `run-arms.sh` runs the arms against a detached worktree pinned at `864069f2` with a manifest, a status file, interleaved trials and one retry; `compare.sh --ab` refuses mixed source commits; `report.sh --arms` writes the per-arm verdict with a bootstrap interval and the missed labels. Two real single trials on `pr-01` proved the pipeline end to end and found that Fable 5.1's safeguards refuse security-heavy review content and fall back to Opus 5.5 mid-session, so the arm executor is Opus 5.5 (DEC-0172 amends D33) and the batches are cost-gated (DEC-0173).

Sprint tasks carry `kind: mechanical|judgment|operator`: the validator requires it for plans dated from 2026-10-14, this plan passes, the archived cycle-128 plan WARNs, the review's spec axis names the two failure shapes, and `tools/cycle-ratio.sh` prints the kind counts and the volume line. The two always-loaded rule files are path-scoped and a lint checks their globs; the FR-1.2b block message points at the rule file; the hazard crosswalk names four hazards with no mechanical check. The prompt-budget workflow comment matches the script and a bats case pins it; `implementing-tasks` declares its app zone `read-write`. KF-041 went upstream as issue #1281.

**Key Accomplishments:**
- 95 guards registered with origins; CI drift gate; generated hooks table (30 registrations, six previously omitted hooks present); `/loa` Guards line
- Arms, toggles, threshold, record corpus, arm runner and report; the executor finding recorded as DEC-0172
- `kind:` rule, template, review axis, glossary entries, `cycle-ratio.sh`; path-scoped rule files with a glob lint; doc fixes pinned by tests
- 24 suites run on the integrated tree: 665 bats cases green (see Testing Summary); fence corpus 78/78 benign, 100/100 dangerous, 0/5 residual, unchanged

---

## AC Verification

Acceptance criteria quoted verbatim from `grimoires/loa/sprint.md` "## Sprint 1". Evidence cites the integrated main checkout.

**AC-1.1**: "AC-1.1 `guard-origins.bats` fails on a fixture hook without an origin and passes on the seeded map; every enumerated hook script and fence id has a row (PRD AC-1.1)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/guard-yield.sh:316` — `"guard \(.) has no origin row in \($map)"`, exit 5; `.claude/data/guard-origins.yaml` 95 rows, `guards_without_origin: 0` (`grimoires/loa/guards.md:8-11`).
- Test: `tests/unit/guard-origins.bats` GO-1 … GO-15 (15/15), GO-11 the fixture registration without a row fails by name; GO-3/GO-4 set-equality of hook scripts and fence ids.

**AC-1.2**: "AC-1.2 `guard-yield.bats`: replay rows (cwd under the temp dir or `/bats-run-`) are excluded and counted in the header; a rotated segment is read; heredoc, scratch-path and prose-class blocks classify as likely false positives; `last_real_catch` is day-granular (PRD AC-1.2)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/guard-yield.sh:499-507` (`replay`, `outside_repo`, `destructive_start`, `heredoc`, `likely_fp`), `:443` (segments), `:543` (`strftime("%Y-%m-%d")`).
- Test: `tests/unit/guard-yield.bats` GY-1 (13 replays excluded by flag, cwd and burst), GY-2 (segment catch), GY-3 (likely-FP classes), GY-4 (day granularity) — 11/11.

**AC-1.3**: "AC-1.3 The tracked `guards.md` is structural (ids, class, status, origin, knob, floor, registrations; no timestamp) and the untracked `.run/guard-yield.md` and `.run/guard-yield.json` carry this host's 30-day yield with `scope: host` and the window; none of the three contains command text, cwd, hostname or model name; `guard-yield.sh --check` exits 0 after generation, 1 after an origin edit, and 0 after a yield-only change (PRD AC-1.3, AC-1.4; wording follows DEC-0162)"
- Status: `✓ Met`
- Evidence: `grimoires/loa/guards.md:1-11` (structural header, no timestamp); `.run/guard-yield.json` header `{"window_days":30,"scope":"host",…}` and totals `blocks_30d 159, real_blocks_30d 87, likely_fp_30d 72`; `guard-yield.sh:419-439` (`--check` never reads the audit log).
- Test: `tests/unit/guard-yield.bats` GY-5 (privacy), GY-6 (structural, identical across audit logs), GY-7 (`--check` 0 / 1 / 0 / 1).

**AC-1.4**: "AC-1.4 `hooks-reference.md`'s table is the generated one and lists all registered hooks, including the six omitted before, with their registrations and status (PRD AC-1.4)"
- Status: `✓ Met`
- Evidence: `.claude/loa/reference/hooks-reference.md:170-204` (the `guard-register` markers and 30 generated rows: zone-write-guard, spiral-dispatch-guard, spiral-skill-sentinel, adversarial-review-gate, the Karpathy check, Setup and PermissionRequest now present); `guard-yield.sh:387` `render_hooks_ref`.
- Test: `tests/unit/guard-yield.bats` GY-8; `bash .claude/scripts/guard-yield.sh --check` → `in sync (95 guards)`.

**AC-1.5**: "AC-1.5 `/loa` prints the Guards line from `.run/guard-yield.json` or the regenerate hint; `.claude/settings.json` hook registrations and the fence pattern-id list are byte-identical before and after the sprint (the register disables nothing); `floor-snapshot.bats` passes; `dormant` rows are excluded from the inert-controls KPI (PRD AC-1.5)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/loa-status.sh:938` `display_guards_line`, called at `:694`; `git diff ffd25258 -- .claude/settings.json` empty; the fence's `emit_block` id list unchanged (A added marker comments and the `replay` field only; corpus identical); `floor.yaml` + `floor-snapshot.bats` FS-1 … FS-4; the yield JSON carries `status` per row and `totals.dormant: 3` so the KPI excludes them by status (the KPI line itself is Sprint 2's FR-4 report).
- Test: `tests/unit/loa-status-guards.bats` LSG-1 … LSG-3; `tests/unit/floor-snapshot.bats` 4/4 (FS-3 settings `.hooks` identical to `origin/main`, FS-4 fence pattern ids identical).

**AC-1.6**: "AC-1.6 Both suites declare the canonical arm ids and the `ab.threshold` block; a sandbox prepared for `no_rule_files` has no rule files, for `no_karpathy` no Karpathy section, for `no_companion` `companion_voice: false`, for `no_audit_delta` no delta paragraph; `compare.sh --ab` refuses skewed model ids; `report.sh --arms` prints the per-arm verdict (PRD AC-2.1, AC-2.3, AC-2.4)"
- Status: `✓ Met`
- Evidence: `evals/suites/review-recall.yaml:35-63` (`arms:` with `no_companion` `informational: true` at `:44`, `no_karpathy` scope note `:51`; `threshold:` at `:63`); `evals/suites/audit-recall.yaml:27-42`; `evals/harness/execute-agent.sh:230-280` (`apply_toggles` before the skill prompt is derived from the toggled copy); `evals/harness/compare-ab.py:141` (model skew); `evals/harness/arms-report.py:300-309` via `report.sh:38`.
- Test: `evals/tests/arm-toggles.bats` AT-1 … AT-11 (11/11; each asserts on the CLI stub's snapshot at executor start; AT-9 exit 2 when a toggle cannot apply); `evals/tests/recall-baseline-freshness.bats` BF-8, BF-13 (13/13); `evals/tests/arms-report.bats` AR-1 … AR-7 (7/7).

**AC-1.7**: "AC-1.7 At least six of the eight record fixtures exist with `fixture.yaml`, `head.diff`, instructions and an approved `labels.tsv` (a sprint with no accepted finding whose fix touches a cited file is dropped and the gap stated in `corpus.tsv` and the report); every label satisfies the fix-touches-file rule and carries `label_source`; every label passes `no-secrets.sh`; `SHA256SUMS` covers every file; `recall-vs-defects.sh` grades a label file (PRD AC-2.2)"
- Status: `✓ Met`
- Evidence: all eight fixtures `evals/fixtures/review-prs/pr-11` … `pr-18` (sprints 247–254; none dropped; 5/8/5/2/3/4/20/8 labels); labels live in `evals/fixtures/review-prs/labels/pr-NN.tsv` (hidden from the sandbox copy; B's decision) with `# approved-by: lead 2026-10-14` after the lead read every label and ran `seed-corpus-from-record.sh --approve pr-NN --by "lead 2026-10-14"`; the rule at `evals/harness/seed-corpus-from-record.sh:550` (`if p not in fix_touched`), `label_source` from `source_kind()` at `:411`, `fix` rows per hunk; no-secrets at `:774`; `seed-corpus-from-record.sh --check` → `corpus OK: 842 files match SHA256SUMS`. Integration fix by the lead: the fixtures' `.claude/skills/bridgebuilder-review/dist/` copies (60 files under `pr-11`, `pr-14`, `pr-15`) were shadowed by the repository's `dist/` ignore rule and absent from B's patch; `.gitignore` re-includes `evals/fixtures/review-prs/*/*/.claude/skills/bridgebuilder-review/dist/` and the files were copied from B's worktree.
- Test: `evals/tests/seed-corpus.bats` SC-1 … SC-6 (6/6: kept, dropped by the rule, fix rows, hidden labels, freeze, secret rejected, grader grades the seeded label, approved-by header required).

**AC-1.8**: "AC-1.8 `run-arms.sh --dry-run` lists the planned trials and writes a `MANIFEST.json`; batch 1 and batch 2 are started and their commands, log paths and `STATUS.json` paths recorded in the sprint report (PRD AC-2.4 precondition)"
- Status: `✓ Met` for batch 1; batch 2 is cost-gated (DEC-0173) and starts from batch 1's measured cost. Batch 1 started 2026-10-14T01:14Z after the audit-round commit `b6802e4f` on `global.anthropic.claude-opus-5-5` (DEC-0172): review-recall 96 trials then audit-recall 48 trials at concurrency 2; log `~/.cache/loa/cycle-129/logs/arms-batch-1.log`; `evals/results/arms/{review-recall,audit-recall}/batch-1/{MANIFEST.json,STATUS.json,run.log}`; Sprint 2 gate `evals/results/arms/<suite>/STATUS.json`.
- Evidence: `evals/harness/run-arms.sh:208-211` (`--dry-run` plan and manifest); `~/.cache/loa/cycle-129/logs/arms-batch-{1,2}.log`; `evals/results/arms/<suite>/batch-{1,2}/{STATUS.json,MANIFEST.json,run.log}`; Sprint 2 gate `evals/results/arms/{review-recall,audit-recall}/STATUS.json`.

**AC-1.9**: "AC-1.9 A dated plan with an untagged task fails `--type sprint`; this plan passes; the spec-axis lines exist in `reviewing-code/SKILL.md` within budget and an eval fixture for a `mechanical` task shipped as prose is added under `evals/tasks/review-recall/` (not run in CI); `cycle-ratio.sh` prints both lines on a fixture (PRD AC-10.1 … AC-10.3)"
- Status: `✓ Met`
- Evidence: `.claude/scripts/validate-artifact.sh:961-964` (`# @guard validator:sprint.kinds`, `KINDS_REQUIRED_FROM="2026-10-14"`, `validate_sprint_kinds`, called at `:319`); `bash .claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md` exit 0 (one WARN: Task 1.5 is a judgment task that names a script — accepted, the anchor curation is the judgment); the archived cycle-128 plan WARNs only; `.claude/skills/reviewing-code/SKILL.md:218` (the `**Task kinds**:` sentence; 16,367 B of 16,384); `evals/tasks/review-recall/review-kind-01.yml` + `evals/fixtures/review-kinds/kind-01/` (`.yml` so the suite's `*.yaml` include does not pick it up); `tools/cycle-ratio.sh` (kinds and volume lines with `scope: host · modelinv: <path>`).
- Test: `tests/unit/validate-artifact-sprint-kinds.bats` KINDS-1 … KINDS-11 (11/11); `tests/unit/cycle-ratio.bats` CR-1 … CR-6 (6/6); `tests/unit/prompt-budget.bats` PB-9.

**AC-1.10**: "AC-1.10 The two rule files carry `paths:` frontmatter and each glob matches at least one tracked file of the intended kind (lint); the hazard crosswalk is in the sprint report with the unmechanised hazards named; the harness observation is recorded; `no-history-in-rule-text.bats` and `check-prompt-budget.sh` stay green (PRD AC-3.1)"
- Status: `✓ Met`
- Evidence: `.claude/rules/stash-safety.md:1-10`, `.claude/rules/skill-invariants.md:1-10` (`paths:` lists in the form the other three rule files use, with `origin: enacted`, `version: 1`, `enacted_by: cycle-083`); crosswalk in §Hazard crosswalk below (from `reviewer-c.md`); harness observation in §Harness observation below; `bash tools/check-prompt-budget.sh` exit 0.
- Test: `tests/unit/rule-paths.bats` RP-1 … RP-6 (6/6); `tests/unit/no-history-in-rule-text.bats` 3/3; `tests/unit/rule-lifecycle.bats` 4/4.

**AC-1.11**: "AC-1.11 The workflow comment states 160,000 / 114,688 B; `implementing-tasks/SKILL.md:28` agrees with `:76`"
- Status: `✓ Met`
- Evidence: `.github/workflows/check-prompt-budget.yml:5` (`protocols total ≤ 160,000 B (warn > 114,688 B)`); `.claude/skills/implementing-tasks/SKILL.md:28` `permission: read-write` (the vocabulary `run-bridge` already uses), matching `:76`.
- Test: `tests/unit/prompt-budget.bats` PB-10 (red on the old comment, green now); `bash .claude/scripts/validate-skill-capabilities.sh` 37/37, 0 errors.

**AC-1.12**: "AC-1.12 The KF-041 entry's Upstream issue field names the filed issue"
- Status: `✓ Met`
- Evidence: `grimoires/loa/known-failures.md:1662` — `**Upstream issue**: https://github.com/0xHoneyJar/loa/issues/1281 (filed 2026-10-14, cycle-129 Task 1.10)`; recurrence 4 and the 2026-10-14 attempt row landed in the plan commit `ffd25258`.

**AC-1.13**: "AC-1.13 Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; the toolchain readiness check is recorded"
- Status: `⚠ Partial` → the full `tests/unit/*.bats` sweep runs in the background on this tree (`~/.cache/loa/cycle-129/logs/s1-full-bats.log`); the lead records its result in §Testing Summary before the sprint commit. Every suite touching a changed file is green (665 cases over 24 suites plus the 125 eval cases); the fence corpus is unchanged. pytest and vitest were not exercised by Sprint 1 (no Python or TypeScript source changed; the eval fixtures copy TypeScript test files as data). Toolchain readiness (Task 1.0) is recorded below.

---

## Tasks Completed

| Task | Owner | Deliverable | Report |
|------|-------|-------------|--------|
| 1.0 | lead | yq v4.44.1, jq 1.7, bats 1.13.0 at `~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats` (not on `PATH`), Python 3.13.5 + pytest 9.0.2 + PyYAML, Node 22.22.2 + npm 10.9.7 (vitest not installed under `bridgebuilder-review/`; Sprint 3 runs `npm ci`), claude CLI 2.1.296 (`CLAUDE_HEADLESS_BIN=claude-fallback`), codex-cli 0.137.0, `gh` authenticated as deep-name, record branches `origin/record/cycle-12{6,7,8}-a2a` fetched | this file |
| 1.1 | A | `.claude/data/guard-origins.yaml` (95 rows), `.claude/data/floor.yaml` (21 floor ids, 6 key patterns, floor files) | `reviewer-a.md` |
| 1.2 | A | `.claude/scripts/guard-yield.sh` (625 lines), `# @guard fence:` markers (34) and the `replay` field in the fence, `# @guard validator:` markers (19; the `sprint.kinds` row added by the lead), `grimoires/loa/guards.md`, `.run/guard-yield.{md,json}`, `tests/unit/guard-yield.bats` | `reviewer-a.md` |
| 1.3 | A | `tests/unit/guard-origins.bats`, `tests/unit/floor-snapshot.bats`, the generated hooks-reference table, `/loa` Guards line + `tests/unit/loa-status-guards.bats`, `--check` step in `.github/workflows/bats-tests.yml` | `reviewer-a.md` |
| 1.4 | B | `ab.arms` + `ab.threshold` in both suites, `execute-agent.sh` toggles, `report.sh --arms` (`arms-report.py`), `compare-ab.py` source-commit refusal, `evals/tests/arm-toggles.bats`, `arms-report.bats`, `recall-baseline-freshness.bats` BF-13 | `reviewer-b.md` |
| 1.5 | B + lead | `evals/harness/seed-corpus-from-record.sh`, fixtures `pr-11` … `pr-18`, `labels/pr-NN.tsv` (approved by the lead), `labels/curation.tsv`, `labels/pr-NN.dropped.txt`, `corpus.tsv`, `SHA256SUMS`, `evals/tests/seed-corpus.bats`; lead: `.gitignore` re-include for the fixture `dist/` copies | `reviewer-b.md` |
| 1.6 | B + lead | `evals/harness/run-arms.sh`, `evals/tests/run-arms.bats`, two proof trials on `pr-01`; lead: executor decision (DEC-0172), cost gate (DEC-0173), batch start after the commit | `reviewer-b.md`, §Arm batches |
| 1.7 | C | `validate_sprint_kinds` + marker, template line, `reviewing-code` spec-axis sentence (bytes from the zone sentence and the Red Flags parenthetical, both duplicates), five glossary entries, `tools/cycle-ratio.sh`, `tests/unit/{validate-artifact-sprint-kinds,cycle-ratio}.bats`, eval fixture `review-kinds/kind-01` + task `review-kind-01.yml`, Seams fixture updated | `reviewer-c.md` |
| 1.8 | C + lead | `paths:` frontmatter on both rule files (also clearing two pre-existing `validate-rule-lifecycle.sh` errors), `tests/unit/rule-paths.bats`, FR-1.2b message pointer, crosswalk; lead: harness observation | `reviewer-c.md`, §Hazard crosswalk, §Harness observation |
| 1.9 | C | workflow comment + PB-10 pin, `implementing-tasks` app zone `read-write` | `reviewer-c.md` |
| 1.10 | lead | KF-041 upstream issue #1281; KF entry updated | this file |
| 1.11 | lead | CHANGELOG `[Unreleased]` cycle-129 block (and the `## [2.0.0-rc.4] — 2026-10-13` heading restored above the cycle-128 block, as the rc tag finalised it), REPO-MAP + checksum regenerated, `checksums.json` refreshed, `sync-fixtures.sh --check` green, prose baseline below | this file |

### Always-on prose baseline (Task 1.11)

Measured on the plan commit with `wc -c .claude/loa/CLAUDE.loa.md CLAUDE.md .claude/rules/stash-safety.md .claude/rules/skill-invariants.md`: kernel 10,225 B, project `CLAUDE.md` 2,460 B, the two unscoped rule files 7,301 B — 19,986 B per turn. After this sprint the two rule files are path-scoped, so a turn that touches no shell source or SKILL.md loads 12,685 B; the kernel is unchanged until Sprint 2's diet.

### Hazard crosswalk (Task 1.8, D-3.1; from `reviewer-c.md`)

| Rule file | Hazard named in the rule | Mechanism | Proof |
|-----------|--------------------------|-----------|-------|
| stash-safety.md | output-swallowing around `git stash push/pop/apply` | fence FR-1.2b (`block-destructive-bash.sh:736-749`) | `test-safety-hooks.sh:100-103, 150-152`; `tests/unit/stash-safety.bats` |
| stash-safety.md | outer stash shifted by the hook's internal `--keep-index` | `stash_with_guard` count-delta (`stash-safety.sh`), only when the helper is used | `tests/unit/stash-safety.bats:98` |
| stash-safety.md | output hidden or exit masked inside a guarded stash | `stash_with_guard` | `tests/unit/stash-safety.bats:53, 158` |
| stash-safety.md | `git stash -k` with pre-commit-wrapped operations | **none** (invisible to a command-string fence) | the `no_rule_files` arm measures it |
| stash-safety.md | `git gc` before `git fsck --unreachable` | **none** (recovery advice); FR-1.2 blocks `drop`/`clear` only | `block-destructive-bash.bats:104, 110` |
| skill-invariants.md | write-capable skill through a read-only agent type | `validate-skill-capabilities.sh` exit 1 | `skill-capabilities.bats:288, 317, 426, 461` |
| skill-invariants.md | agent-type allowlist drift or unparsable `agent-types.yaml` | data-file loader with `general-purpose` fallback | `skill-capabilities.bats:848-896` |
| skill-invariants.md | `role: review` + `write_files: true` keeping `Write` | validator WARN (Sprint 2 FR-4(b) adds the four pure-review lines) | `skill-capabilities.bats:574, 598, 635` |
| skill-invariants.md | review/audit skills keep Write/Edit, drop NotebookEdit | frontmatter pinned | `skill-capabilities.bats:626`; `validation-skill-contracts.bats:50-77` |
| skill-invariants.md | report-authoring skills drop `git add/commit/push` | harness-enforced by `disallowed-tools`; **no lint pins the list** | `skill-capabilities.bats:635` |
| skill-invariants.md | tool-granular `disallowed-tools` cannot refuse `src/` while allowing `grimoires/` | zones (`implement-gate.sh`, `zone-write-guard.sh`); **Bash-path writes unmechanised** (accepted gap) | `tests/unit/zone-write-guard.bats` |

Hazards with no mechanical check: the `stash -k` under pre-commit rule; the `fsck` before `gc` recovery advice; the git-mutation list of the report-authoring review skills (enforced at run time, not linted); Bash-path App-Zone writes under `disallowed-tools`.

### Harness observation (Task 1.8)

In this session the two unscoped rule files were injected at session start, while the three `paths:`-scoped rules already in the repository (`shell-conventions.md`, `zone-state.md`, `zone-system.md`) were injected only on turns that touched matching files (`zone-state.md` on the first `grimoires/` edit, `shell-conventions.md` on the first shell-script write, `zone-system.md` on the first `.claude/` edit). The harness honours `paths:`; the two newly scoped files stop loading on non-matching turns from the next session start.

### Arm batches (Task 1.6, lead steps)

Executor: `global.anthropic.claude-opus-5-5` (DEC-0172; B's Fable proof trial was refused by a safeguard, category `cyber`, and the CLI fell back to Opus for the rest of the session). Source commit `864069f2` (pre-cycle tree, true baseline). Both batches run from the main checkout after the sprint commit, at concurrency 2, suites back to back, never overlapping (KF-037 contention shape).

- Batch 1 (`pr-01` … `pr-08`; 96 review + 48 audit = 144 trials; B's measurement: $3.2–3.5 and 5–9 min per `pr-01` trial on Fable, so about 8–9 h): started after the sprint-255 commit; log `~/.cache/loa/cycle-129/logs/arms-batch-1.log`; `evals/results/arms/{review-recall,audit-recall}/batch-1/{STATUS.json,MANIFEST.json,run.log}`.
- Batch 2 (`pr-11` … `pr-18`; 144 trials; record diffs 10–60× larger): cost-gated (DEC-0173). The lead projects its cost from batch 1's manifest; under $1,500 list it runs at the pre-registered 3 trials, otherwise 1 trial per fixture as a sizing pass and the record arms read `inconclusive`.
- Sprint 2 gate: `evals/results/arms/review-recall/STATUS.json` and `audit-recall/STATUS.json` (`complete` required for a verdict); `evals/harness/report.sh --arms`.

---

## Technical Highlights

- The register's identity rule (one row per hook script, registrations listed) and the two-way marker cross-check make the lint strict in both directions: a marker without a call site, a call site without a marker, a registration not in the map, a map row whose script does not exist — each is exit 5 by name. The first cross-implementer integration tripped it (the `sprint.kinds` marker), which is the intended failure.
- The replay rule has three fallbacks: `replay: true` (producers under `LOA_AUDIT_REPLAY=1`), the cwd prefix (temp dir, bats run dir, eval sandbox), and a burst heuristic (≥ 10 block rows in one UTC minute). On this host the cwd fallback catches nothing (all 501 rows carry the repository root), the burst rule 342 rows. The rule is labelled a heuristic in the yield files.
- Arm toggles are applied after sandbox materialisation and asserted at executor start by a CLI stub that snapshots the sandbox; a toggle that cannot apply is exit 2, so no arm silently runs as its baseline.
- The record corpus hides its labels in `review-prs/labels/`, outside the directory the sandbox copies, so the reviewer under test never sees them; `run-arms.sh` refuses unapproved fixtures.
- `validate_sprint_kinds` reuses the Seams gate's date parsing and the shared fence tracker; inline code spans are not tokens; the judgment WARN is advisory.

## Testing Summary

Run on the integrated main checkout with `LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1` and bats 1.13.0.

| Suite | Pass / total |
|-------|--------------|
| tests/unit/guard-origins.bats | 15 / 15 |
| tests/unit/guard-yield.bats | 11 / 11 |
| tests/unit/floor-snapshot.bats | 4 / 4 |
| tests/unit/loa-status-guards.bats | 3 / 3 |
| tests/unit/validate-artifact-sprint-kinds.bats | 11 / 11 |
| tests/unit/cycle-ratio.bats | 6 / 6 |
| tests/unit/rule-paths.bats | 6 / 6 |
| tests/unit/prompt-budget.bats | 10 / 10 |
| tests/unit/no-history-in-rule-text.bats | 3 / 3 |
| tests/unit/sprint-seams.bats | 12 / 12 |
| tests/unit/validate-artifact.bats | 66 / 66 |
| tests/unit/skill-capabilities.bats | 36 / 36 |
| tests/unit/block-destructive-bash.bats | 291 / 291 |
| tests/unit/block-destructive-bash-limitations.bats | 6 / 6 |
| tests/unit/stash-safety.bats | 12 / 12 |
| tests/unit/hook-guard.bats | 8 / 8 |
| tests/unit/agent-teams-hooks.bats | 8 / 8 |
| tests/unit/settings-permissions.bats | 65 / 65 |
| tests/unit/gitattributes-hook-merge-safety.bats | 5 / 5 |
| tests/unit/git-branch-prune.bats | 15 / 15 |
| tests/unit/cycle-114-rm-home-precision.bats | 6 / 6 |
| tests/unit/spike-validator.bats | 16 / 16 |
| tests/unit/glossary-terms.bats | 34 / 34 |
| tests/unit/glossary-validator.bats | 27 / 27 |
| tests/unit/rule-lifecycle.bats | 4 / 4 |
| tests/unit/zones-schema.bats | 6 / 6 |
| tests/unit/charting-lint.bats | 28 / 28 |
| tests/unit/loa-status-providers.bats | 13 / 13 |
| evals/tests/*.bats (9 suites) | 125 / 125 |
| fence corpus `run-corpus.sh` | benign 78/78, dangerous 100/100, residual 0/5 (unchanged) |
| full `tests/unit/*.bats` sweep | see the line the lead appends below before the commit |

Lints: `tools/check-prompt-budget.sh` (kernel 10,225 B; `reviewing-code` 16,367 B), `tools/check-glossary-terms.sh` PASS, `validate-skill-capabilities.sh` 37/37, `tools/check-no-raw-sha256sum.sh` OK, `guard-yield.sh --check` in sync, `evals/fixtures/sync-fixtures.sh --check` current, `seed-corpus-from-record.sh --check` 842 files OK, `validate-artifact.sh --type sprint` exit 0 (one judgment WARN), `repo-map-gen.sh --validate` 0.

## Known Limitations

- The arm executor is Opus 5.5, not the production gate model: a model-transfer assumption, recorded in DEC-0172 and to be printed next to every kernel-row change the arms clear (Task 2.8).
- Batch 2's cost is unmeasured until batch 1 reports; the pre-registered record arms may read `inconclusive` under the cost gate (DEC-0173), in which case Sprint 2 takes the D-2.4 fallback for them.
- The eval sandbox executor has Read, Grep, Glob and Write only, so `no_companion` is a prompt-surface arm (informational, as declared) and `no_audit_delta` removes an instruction the audit fixtures give it nothing to act on.
- `pr-14` (2 labels) and `pr-15` (3 labels) are thin: the 249–251 record branches keep only the approving review round.
- The likely-false-positive and burst-replay rules are heuristics; the yield files say so.
- The inert-controls KPI line is Sprint 2's; the register already carries the `status` it needs.

## Verification Steps

```
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 "$(cat ~/.cache/loa/cycle-128/bats-path)" tests/unit/guard-origins.bats tests/unit/guard-yield.bats tests/unit/floor-snapshot.bats tests/unit/validate-artifact-sprint-kinds.bats tests/unit/cycle-ratio.bats tests/unit/rule-paths.bats evals/tests/*.bats
bash .claude/scripts/guard-yield.sh --check
bash tests/fixtures/fence-corpus/run-corpus.sh
bash .claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md
evals/harness/seed-corpus-from-record.sh --check
evals/harness/run-arms.sh --suite review-recall --arms baseline,no_rule_files --fixtures pr-01,pr-02 --trials 1 --source-commit 864069f2 --dry-run
```

## Decisions taken during integration (lead)

- [ASSUMPTION decision] The `validator:sprint.kinds` origin row was added by the lead at integration (origin `cycle-129 D-10.1 (DEC-0144)`) rather than sent back to A: a one-row data fix the lint demanded.
- [ASSUMPTION decision] The fixture `dist/` copies are re-included in `.gitignore` (two negation lines mirroring the existing bridgebuilder-review lines) and copied from B's worktree, keeping B's verbatim-copy design and the frozen `SHA256SUMS` intact.
- [ASSUMPTION decision] All eight label files were approved after the lead read every label (`--approve pr-NN --by "lead 2026-10-14"`); nine machine-chosen anchors had already been hand-corrected by B in `labels/curation.tsv`.
- [ASSUMPTION decision] The arm executor is Opus 5.5 (DEC-0172) and batch 2 is cost-gated (DEC-0173); batch 1 starts after the sprint commit, not before, because the manifest records a dirty harness otherwise.
- [ASSUMPTION decision] The sprint plan's fixture numbering and AC-1.3 wording were amended to the as-built state (`pr-11` … `pr-18`; structural register per DEC-0162) rather than the fixtures renamed.
- [ASSUMPTION fact] A stray `evals/fixtures/review-prs/pr-05/.run/audit.jsonl` appeared during a dry run and was frozen into `SHA256SUMS` by the first `--approve`; the lead removed the file and refroze (842 files).
- The 56 `[ASSUMPTION decision]` lines of A, B and C are seeded as `proposed` ledger rows DEC-0174 … DEC-0229 (`lead-seed`, source `reviewer-{a,b,c}.md#assumptions`).
