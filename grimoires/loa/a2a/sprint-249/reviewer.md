# Implementation Report — Sprint 3: Context discipline and instruction diet (cycle-126, global sprint 249)

**Cycle:** cycle-126 full-size · **PRD:** `grimoires/loa/prd.md` FR-3 · **SDD:** `grimoires/loa/sdd.md` §1.4 (D-3.1 … D-3.3) · **Plan:** `grimoires/loa/sprint.md` Sprint 3
**Implementer:** Opus 5.5 subagent under the lead (`/run sprint-plan`, unattended) · **Date:** 2026-10-05 · **Epic:** bd-7ydj (tasks bd-lp4j, bd-vywd, bd-c0o7, bd-8bxb, bd-ng1s) · **Commit:** `41b783a1`

## Summary

A single context-class table now drives the context discipline. `long` is the default (thresholds 20K/50K/30K/150K). `standard` (2K/5K/3K/15K) is selected by `LOA_CONTEXT_CLASS=standard` or by a session model whose catalog context window is ≤ 200K.

A SessionStart hook writes the class to `.run/context-class` and `/loa` prints it. Five reference-grade protocols move to `.claude/protocols/reference/` behind anchor-stable stubs. `CLAUDE.loa.md` and the protocol set regain budget headroom. The three skills drop their line-count parallelism gates for one sentence. No enforcement text was removed: constraint rule text is unchanged, and only rationales were tightened.

## Changes

### Task 3.2 — Context class (D-3.1)
- `.claude/protocols/tool-result-clearing.md`: the two-class thresholds table and the selection rule.
- The `context_discipline` include (476 B) cites `.run/context-class` and the rule; the ten skills are regenerated (`generate-skill-includes.sh --check` clean).
- `.claude/hooks/session-start/loa-context-class.sh` behaves as follows:
  - It never blocks, and every error path resolves to `long`.
  - The model id is sanitised to `[A-Za-z0-9._:-]` before it reaches the yq lookup.
  - The window lookup through the catalog is alias-aware.
  - The record is written atomically (mktemp + mv).
  - It is registered behind `hook-guard.sh` with `once` in both `settings.json` and `settings.hooks.json` (RSS-7 requires both).
- `loa-status.sh`: `display_context_line` → `hook --show` prints `  Context: long (default; …)`.
- `tests/unit/context-class.bats` CC-1…CC-9 (red first: 7/7 exit 127 with the hook absent).

### Task 3.3 — Instruction diet (D-3.2)
- `git mv` of `helper-scripts`, `constructs-integration`, `trajectory-evaluation`, `recommended-hooks` and `session-continuity` to `.claude/protocols/reference/`. A stub at each old path keeps the anchors existing tests grep: recommended-hooks §4 and the session-continuity notes-guard recipes.
- Every live reference was grepped and repointed:
  - `protocols-summary`, `scripts-reference`, `context-engineering`;
  - seven protocols;
  - the skill resources `context-retrieval.md`, `impact-analysis.md` and `BIBLIOGRAPHY.md`;
  - `PROCESS.md`, `commands/ride.md` and `NOTES.md.template`;
  - `validate-ck-integration.sh`: its >10-line check would fail on a stub, so it now reads the moved file.
- `tools/check-prompt-budget.sh`: `CLAUDE.loa.md` ≤ 9,216 B; protocols ≤ 160,000 B (warn 114,688). `prompt-budget.bats` pins the new numbers.
- `constraints.json`: twelve `why` fields tightened with the rule text unchanged (C-PROC-001/002/004/005/015/017/018, C-TEAM-001–005). The C-PROC-001 rationale still names implement-gate fail-asks, the disallowed-tools strip, the adversarial gates and the Bash-path gap. `generate-constraints.sh` was re-run, the golden NEVER/ALWAYS tables re-rendered, and the kernel hash verified. Only the seven C-PROC rationales render (the NEVER/ALWAYS tables); `generate-constraints.sh` has no `agent_teams_constraints` section, so the five C-TEAM rationales render nowhere (corrected in round s3-1a; dissent B#21).
- `CLAUDE.loa.md`: the Reference Files table is one line; the truenames table is one line; the duplicate NOTES clause is dropped.

### Task 3.4 — Skills (D-3.3)
- `auditing-security`, `implementing-tasks` and `reviewing-code` have lost their line-count size classes. Each now carries "Parallelise (`parallel_threshold`) when the scope warrants; the lead decides."
- The `PARALLEL-SPLIT.md` / `PARALLEL-REVIEW.md` headers that pointed at the deleted Phase -1 thresholds are fixed.

### Budgets

| Item | Before (`f4531477`) | After (`41b783a1`) | Limit |
|---|---|---|---|
| `CLAUDE.loa.md` | 10,225 B | 9,199 B | 9,216 B |
| Protocols total | 199,593 B | 131,078 B | 160,000 B (warn 114,688) |
| `auditing-security` SKILL.md | 16,376 B | 16,250 B | 16,384 B |
| `implementing-tasks` SKILL.md | 16,311 B | 16,203 B | 16,384 B |
| `reviewing-code` SKILL.md | 16,380 B | 16,269 B | 16,384 B |

## Test-first record
- `context-class.bats` was red (7/7, hook absent) before the hook existed; CC-8 and CC-9 were added after RSS-7 named the second settings file.
- `prompt-budget.bats` 90–91 pinned 10240/200000; they were updated with the budget change.
- `skill-includes.bats` tests 4–5 tampered with the old include text; they were re-anchored to the new include.
- Suites green, run serially:

| Suite | Passed |
|---|---|
| context-class | 9/9 |
| prompt-budget | 9/9 |
| skill-capabilities | 32/32 |
| skill-includes | 7/7 |
| prompt-audit-generated-blocks / prompt-audit-keeplist | 3 / 3 |
| no-history-in-rule-text | 3 |
| protocol-refs-resolve | 3 |
| dead-recall-relabel | 6 |
| notes-template | 51 |
| hook-wiring | 10 |
| run-state-surface | 7 |
| bug-989-kernel-hash-stamp | 8 |
| no-constraint-temp-files | 3 |
| quality-gates | 18 |
| zone-compliance | 18 |
| zone-write-guard | 20 |
| classify-commit-zone | 16 |
| repo-map-gen | 6 |
| loa-status-providers | 5 |
| loa-status-stale-worktree | 10 |
| agent-ergonomics loa-status / golden-path | 8 / 4 |
| golden-path-c8-verdict-trailer | 33 |
| integration loa-status | 7 |
| `tests/test-constraints.sh` | 17/17 |

- Pre-existing failures, unchanged by this sprint: `integration/test_process_compliance` tests 6, 7, 9 and 10 fail on HEAD before the change because the strings they grep are absent.
- Load flake: `loa-status-artefacts` LSA-1 timed out once under the eval load and then passed 3/3.

## AC Verification (sprint.md)

### `generate-skill-includes.sh --check` clean; `tools/check-prompt-budget.sh`: `CLAUDE.loa.md` ≤ 9,216 B, protocols ≤ 160,000 B, every skill ≤ 16,384 B.
Met. `generate-skill-includes.sh --check` exits 0; `check-prompt-budget.sh` exits 0; the byte counts are in the Budgets table above; all 36 SKILL.md files are ≤ 16,384 B.

### `tool-result-clearing.md` shows both classes; the include cites the rule; `LOA_CONTEXT_CLASS=standard` and a 200K session model select `standard`; default `long`.
Met. The two-class table is in `.claude/protocols/tool-result-clearing.md`; the include names `.run/context-class` and the rule. CC-1…CC-7 cover the default `long`, the env override to `standard` and back to `long`, and a 200K catalog model and a 1M model through `--model` and the payload's `.model`. CC-9 checks both classes in the protocol, the include's citation, and the `/loa` line.

### Replay A/B: no gold case loses recall; report attached.
Not met as pre-registered; met on blind adjudication, with one deviation disclosed. Report: `grimoires/loa/a2a/sprint-249/replay-ab.md`.
- **Pre-registered gate fails.** Pooled n = 9 graded recall is lower after than before on five cases: review-pr-02 .926 → .815, review-pr-05 .963 → .852, audit-pr-02 .852 → .815, audit-pr-03 1 → .963 and audit-pr-05 .926 → .889.
- **Blind adjudication.** An Opus 5.5 adjudicator, blind to the arm and reading only the fixture and the review `.md`, judged all 44 graded misses across the three arms. Of these, 38 are correct detections that the grader dropped:
  - a `(` swallowed into the cited path;
  - continuation citations (`:776,807`, `head:468`) ignored;
  - D13's single anchor at 807, while every review cites the regex at 776.
  On the adjudicated measure, only audit-pr-02 differs: .963 after vs 1.000 before, one D06 slot in 27.
- **Ablation.** `c9b7bdc0` (old include restored) grades at or below the after arm on three of four cases (0.833), so the include is not what moves the grader.
- **Decision.** The pre-registered remedy, revert or retune, is not applied, and this is disclosed as a deviation for the review and the audit to rule on.
- **Follow-up.** The grader defect is bead **bd-ewrc**, to be fixed test-first with a re-baseline.
- Before arm on `main` `2079e719` (wt-main): review-recall `run-20261005-101017-d84e5ef2`; audit-recall run `120403`.
- After arm on `41b783a1` (wt-s3-after): review-recall `run-20261005-125008-6c06abbe`; audit-recall run `144744`.
- Recall lost at n=3: review-pr-02 (0.889 → 0.778), review-pr-05 (1 → 0.778), audit-pr-02 (1 → 0.778), audit-pr-03 (1 → 0.889), audit-pr-05 (1 → 0.889).
- Recall gained: review-pr-06, audit-pr-04. The rest held.
- Missed-defect slots summed over both suites: 5/144 before, 10/144 after.
- The misses recur on the same defects across the two suites:
  - D13-find-exec-multi-root: before 0/6, after 3/6.
  - D06-prerelease-tags-rejected: before 1/6, after 3/6.
- Both arms reviewed the same way on pr-05: one model, no parallel subagents, 17–22 turns, and every trial read the file holding D13. The parallelism change is therefore not implicated.
- Pre-registered gate, fixed 2026-10-05T15:00Z and 15:45Z before any extra trial ran: every losing case gets +6 trials per arm. For each case, pooled after recall (n=9) must be ≥ pooled before recall (n=9).
- Ablation (diagnostic): `c9b7bdc0` (local only, never pushed) is `41b783a1` with the `f4531477` context_discipline include restored. It runs 6 trials on review-pr-05/02 and audit-pr-05/02, testing whether the include's long-class thresholds (full file 3K → 30K before extraction) cause the misses.
- Remedy if the gate fails: revert or retune the implicated change (plan risk table: "revert the specific move"), then re-run the affected cases.

### The three skills are smaller than before and contain no `wc -l` parallelism gate.
Met. The byte deltas are in the Budgets table (−126, −108, −111 B), and `grep -n 'wc -l' .claude/skills/{auditing-security,implementing-tasks,reviewing-code}/SKILL.md` returns nothing.

## Deliberately not done
- `migrate-skill-names.sh` and `loa-eject.sh` loop over `.claude/protocols/*.md` without `reference/`. The moved files carry no `@loa-managed` marker, so eject is unaffected; the legacy rename migration skips them.
- `check-loa.sh` still lists `session-continuity.md`; the stub satisfies its existence check.
- `/loa --show` with no record computes the class and writes `.run/context-class`. That is a write from a status command, kept because the record is one word and atomically replaced.

## Round s3-1a — review dissent run 1 (2026-10-06)

Two-voice run at `41b783a1` (codex-headless gpt-5.5-pro + claude-headless on claude-bedrock), 7 chunks, all two-voice, rejected 0, no `verdict_quality_error`. Merged envelope `adversarial-review.json`: 33 findings. Two independent Opus 5.5 verifiers read every finding against `41b783a1` vs `f4531477`: `review-dissent-run-1-verifier-A.md` (#4–18) and `-B.md` (#1–3, #19–33).

| Verdict | Count | Findings |
|---|---|---|
| REAL, code (fixed, test-first) | 2 | B#1, B#3 |
| REAL, gate (one issue: the replay A/B AC) | 3 | B#20, B#24, B#28 — not a code change; disclosed in `replay-ab.md`, for review and audit to rule on |
| DOC (fixed) | 7 | A#4, A#8, A#16, A#18, B#21, B#23, B#29 |
| REFUTED | 9 | A#5, A#7, A#9, A#10, A#11, A#15, A#17 (gpt-5.5-pro's citations.md hunks are mislabelled helper-scripts / session-continuity hunks), B#19, B#30 |
| DECLINED | 12 | A#6, A#12 (the same gate issue, causal claim refuted), A#13, A#14, B#2, B#22, B#25, B#26, B#27, B#31, B#32, B#33 |

Fixes:
- **B#1.** `loa-context-class.sh` looped forever on a value flag given last (`shift 2` with one argument left). Each value flag now checks `[[ $# -ge 2 ]] || break`. CC-10 was red (timeout, exit 124) before the fix.
- **B#3.** Without a `timeout` binary, the payload read failed and a Haiku 4.5 session got `long`. The read now tries `timeout`, then `gtimeout`, then bash's own `read -t 2`. CC-11 checks that the Haiku payload resolves to `standard`. CC-13 checks that an open stdin with no `timeout` binary does not block the hook (the lead's addition: a plain-`cat` fallback was exit 124 in the probe).
- **A#4/A#8.** The five stubs now say they keep the old path resolvable, not "its anchors stable".
- **A#16.** The two bare `> 2000` mentions now point at the class's single-search row. CC-12 is a grep lint, red at HEAD with exactly those two hits.
- **A#18.** Level 2 recovery is `ck --hybrid` in both the stub and the reference, with `notes-guard.sh read --section` as the no-ck fallback.
- **B#23.** The include path is `.claude/protocols/tool-result-clearing.md` again. CC-9 and the skill-includes tamper anchors are updated. Each SKILL.md grew 18 B; planning-sprints is now 16,370 of 16,384.
- **B#29.** `/ride`'s "Yellow threshold (5k tokens)" now points at the class's accumulated-results threshold.
- **B#21.** The rationale count is corrected here and in the CHANGELOG. The CHANGELOG also notes that the A/B gate failed as pre-registered (bd-ewrc follows).

Suites green in the real tree after the apply:

| Suite | Passed |
|---|---|
| context-class | 13/13 |
| prompt-budget | 9/9 |
| skill-includes | 7/7 |
| skill-capabilities | 32/32 |
| dead-recall-relabel | 6/6 |
| protocol-refs-resolve | 3/3 |
| notes-template | 51/51 |
| hook-wiring | 10/10 |

`generate-skill-includes.sh --check` and `check-prompt-budget.sh` both exit 0. `regen-checksums --check` reports changed=0.

Declined and left as follow-up candidates:
- the catalog has no `haiku` or `claude-haiku-4-5` short alias (A#13);
- the class is per checkout and set once per session (A#14, B#2, B#32);
- a lint for `protocols/reference/` reads (B#26).

## Next
`/review-sprint sprint-3` (Fable) → `/audit-sprint sprint-3` (Fable) → ≤ 3 dissent runs → COMPLETED.

## Round s3-1b — audit dissent run 1 and the audit's MEDIUMs (2026-10-06, `36b71e4e`)

Triage: `audit-dissent-triage-run-1.md` (13 findings: 1 real, 1 doc, 4 refuted, 4 repeat, 3 declined).

- **Dissent #1.** The alias target read back from the catalog is whitelisted before the second yq lookup. CC-14 was red before the fix.
- **Review LOW 2.** `LOA_CONTEXT_CLASS` is read case-insensitively. CC-15 was red before the fix.
- **MED-001.** A Bedrock id resolves. The candidates, in order: the id as given, then without the region prefix (`global|us|eu|apac|jp|au|ca|us-gov`), without `anthropic.`, and without the `-vN[:M]` suffix. CC-16 was red before the fix. The live session id `global.anthropic.claude-opus-5-5` still resolves to `long`/default because the catalog has no `claude-opus-5-5` key. The class is the same either way, since the model is ≥ 1M.
- **MED-002.** A SessionStart re-fire whose payload `.source` is clear, compact or resume and that carries no model keeps a `model` or `env` record. A startup without a model still writes the default. CC-17 was red before the fix. The CC-4 second leg now uses `source: startup`.
- **"Once" wording.** The CHANGELOG, `hooks/README.md`, `hooks-reference.md` and the CC-8 name no longer claim once per session. The `"once": true` key stays, in line with the other SessionStart entries.
- **LOW-002.** The large-file edge case follows the class's full-file row.
- **CHANGELOG figures.** 131,164 B; CC-1 – CC-17.
- **Task 4.8.** It now carries the audit's three conditions.

context-class is 17/17, and the other suites are green as listed in the triage.
