# Sprint 258 — Task 1.9 smoke (recorded 2026-10-15T07:30Z by the lead)

Executor: `pipeline-run.sh --executor container --image loa-ablation:258` (sha256 9164d16c…; claude 2.1.299, codex 0.162.1, Python 3.11 + pytest 9.0.2 + cheval deps, bats 1.13, no br), source tree = the lead's working tree at the Sprint 258 integration state (dirty: 3,459 `.claude/` files copied per sandbox incl. node_modules; batches pin a pristine worktree, DEC-0488), `LOA_EVAL_BR_BIN=/nonexistent` (beads opt-out in every arm, DEC-0486). Tasks: `smoke-build-01` (slugify bug-fix, Python; hidden test outside the tree) and `smoke-review-01` (corpus `pr-01`, three planted defects). One trial per applicable arm; the four build-only arms on the review-catch task produced applicability refusal records (`meta/refused.json`), which `took-effect.sh` reads as `applicability_refused OK`.

## Executor-mode decision
**Container for the whole cycle.** Every arm authenticated and completed inside the container once the Bedrock bearer-token route was passed through (DEC-0480) and a per-run writable HOME replaced the read-only credential mounts (DEC-0481). The first probe had failed in 2.6 s with the geo-blocked Anthropic API (the dropped route variables), recorded as DEC-0484.

## Gate-model contingency read
Fable 5.1 gate phases run: 26 (REVIEW/AUDIT across every gate arm incl. the repeats). Refusal fallbacks: 0; `models_used` ≠ requested: 0. The contingency (SDD A8, DEC-0386) does not fire; the gates stay on Fable 5.1.

## Cap-fit read (DEC-0378)
A1 build runs: USD 4.88 (two-voice, no FIX) and 6.28 (the pre-repoint single-voice run with a FIX round) incl. sandbox voice costs; median well under USD 9 → the build tasks are not shrunk. Review-catch A1/A3/A7 gate runs: USD 6.6–7.9 at 60-turn budgets; the record fixtures (37–143 labels, 2–5K-line diffs) will cost more; the Sprint 260 smoke on the frozen suite re-reads this.

## Took-effect
Every arm's evidence rules passed (`took-effect.sh`): A0 no `.claude/`, no system prompt, no audit rows; A1 all phases + integrity clean; A2 no PLAN; A3 `companion_voice.planned=false` on both gates; A4 no gate phases + `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` in 2/2 phase envs; A5 no Flatline MODELINV rows with `sprint.md` present; A6 one implementer session (PLAN/IMPLEMENT `6c686d36`, resumed) with distinct REVIEW/AUDIT sessions; A7 `--effort medium` on 4/4 phases and 37/37 skill effort lines stripped; `integrity_clean` (3,390 sandbox manifest entries verified) on every arm with a mount.

## Outcomes (hand-graded inside the image; the Sprint 259 grader automates this)
- Hidden test `smoke-build-01`: **5/5 for every build run** (A0, A1 ×2, A2, A3, A4, A5, A6, A7 ×2) — the smoke task is easy by design; the frozen suite must separate arms (A4 sensitivity check).
- Review-catch recall on `pr-01` (combined gate outputs, `recall-vs-defects.sh`): A0 1.0 (8 citations, refuted 0.25, USD 0.23, 69 s); A1 1.0 (41 citations, refuted 0.76; AUDIT wrote CHANGES_REQUIRED 1 critical/4 high); A3 1.0 (54 citations, refuted 0.76); A7 1.0 (16 citations, refuted 0.44). Verdicts: every gate arm CHANGES_REQUIRED on the planted PR (correct: the key holds critical/high defects).

## Degraded and failed rows
- `a1_full smoke-build-01 ClZuvN`: `degraded` — review and audit envelopes 1 of 4 voices (run before the codex repoint; KF-044). Kept as evidence of the degradation detector.
- `a1_full smoke-review-01 9ZW83k`: `agent_error` — AUDIT hit the 40-turn cap at turn 41 after writing its verdict (recall 1.0, 4 HIGH) → DEC-0490 (60-turn gate budgets; a gate with its trailer on disk counts as completed with `turn_cap_hit`).
- `a3_one_voice smoke-review-01 bup4LP`, `a7_effort_medium smoke-build-01 muAmcL`, `a7_effort_medium smoke-review-01 oujFBb`: `infrastructure_error` with every phase exit 0 — the lead edited `pipeline-run.sh` while they ran (bash reads a script incrementally: `line 921: unexpected EOF`); artefacts intact; each re-run successfully (WyV7VD, cY16zt, PKQrzj). Lesson recorded: the batch runner must snapshot the harness per batch (Task 3.2).
- Four `infrastructure_error` rows with no phases are the applicability refusals (A2/A4/A5/A6 on review-catch), by design.

## Spend
Smoke runs USD 79.08 (20 rows incl. sandbox voice costs) + planning Flatline USD 14.29 = **USD 93.36 cycle spend** (`spend.sh --since 2026-10-14T13:50:00Z`: headroom 1,406.64, reserve 250).

## Per-run table
| run dir | arm | task | status | phases (name:exit:USD:turns) | USD | wall s | took-effect | degraded |
|---|---|---|---|---|---|---|---|---|
| s1-a0_bare-smoke-build-01.5PDFi5 | a0_bare | smoke-build-01 | completed | BARE:0:0.07:3 | 0.07 | 15 | arm a0_bare: OK | ? |
| s1-a0_bare-smoke-review-01.Y0HNBN | a0_bare | smoke-review-01 | completed | BARE:0:0.23:9 | 0.23 | 73 | arm a0_bare: OK | ? |
| s1-a1_full-smoke-build-01.caZDgh | a1_full | smoke-build-01 | completed | PLAN:0:0.24:8 IMPLEMENT:0:0.14:6 REVIEW:0:1.45:20 AUDIT:0:1.6:10 | 3.43 | 861 | arm a1_full: OK | ? |
| s1-a1_full-smoke-build-01.ClZuvN | a1_full | smoke-build-01 | completed | PLAN:0:0.26:7 IMPLEMENT:0:0.13:8 REVIEW:0:1.82:15 FIX:0:0.24:6 AUDIT:0:2.4:16 | 4.85 | 1224 | arm a1_full: OK | ? |
| s1-a1_full-smoke-review-01.9ZW83k | a1_full | smoke-review-01 | agent_error | REVIEW:0:2.41:16 AUDIT:1:4.19:41 | 6.6 | 1474 | arm a1_full: OK | ? |
| s1-a2_no_sprint_plan-smoke-build-01.MtK5dK | a2_no_sprint_plan | smoke-build-01 | completed | IMPLEMENT:0:0.13:6 REVIEW:0:2.27:33 FIX:0:0.31:11 AUDIT:0:1.8:14 | 4.52 | 1133 | arm a2_no_sprint_plan: OK | ? |
| s1-a2_no_sprint_plan-smoke-review-01.tOBzlL | a2_no_sprint_plan | smoke-review-01 | infrastructure_error |  | 0 | 0 | arm a2_no_sprint_plan: OK | ? |
| s1-a3_one_voice-smoke-build-01.inO66T | a3_one_voice | smoke-build-01 | completed | PLAN:0:0.23:6 IMPLEMENT:0:0.12:7 REVIEW:0:1.28:9 AUDIT:0:1.67:18 | 3.31 | 927 | arm a3_one_voice: OK | ? |
| s1-a3_one_voice-smoke-review-01.bup4LP | a3_one_voice | smoke-review-01 | infrastructure_error | REVIEW:0:1.79:15 AUDIT:0:3.26:45 | 5.05 | 961 | arm a3_one_voice: OK | ? |
| s1-a3_one_voice-smoke-review-01.WyV7VD | a3_one_voice | smoke-review-01 | completed | REVIEW:0:2.79:18 AUDIT:0:2.81:31 | 5.61 | 1098 | arm a3_one_voice: OK | ? |
| s1-a4_no_gates-smoke-build-01.jnvrG2 | a4_no_gates | smoke-build-01 | completed | PLAN:0:0.22:6 IMPLEMENT:0:0.11:7 | 0.33 | 239 | arm a4_no_gates: OK | ? |
| s1-a4_no_gates-smoke-review-01.PQlCZq | a4_no_gates | smoke-review-01 | infrastructure_error |  | 0 | 0 | arm a4_no_gates: OK | ? |
| s1-a5_no_flatline-smoke-build-01.feR3KP | a5_no_flatline | smoke-build-01 | completed | PLAN:0:0.18:7 IMPLEMENT:0:0.12:6 REVIEW:0:1.61:11 FIX:0:0.37:13 AUDIT:0:2.33:29 | 4.61 | 865 | arm a5_no_flatline: OK | ? |
| s1-a5_no_flatline-smoke-review-01.JMfmBn | a5_no_flatline | smoke-review-01 | infrastructure_error |  | 0 | 0 | arm a5_no_flatline: OK | ? |
| s1-a6_one_window-smoke-build-01.Xagogp | a6_one_window | smoke-build-01 | completed | PLAN:0:0.22:6 IMPLEMENT:0:0.49:11 REVIEW:0:1.58:14 AUDIT:0:2.09:13 | 4.37 | 1067 | arm a6_one_window: OK | ? |
| s1-a6_one_window-smoke-review-01.EAhUe9 | a6_one_window | smoke-review-01 | infrastructure_error |  | 0 | 0 | arm a6_one_window: OK | ? |
| s1-a7_effort_medium-smoke-build-01.cY16zt | a7_effort_medium | smoke-build-01 | completed | PLAN:0:0.21:6 IMPLEMENT:0:0.14:7 REVIEW:0:1.03:12 AUDIT:0:1.53:18 | 2.92 | 801 | arm a7_effort_medium: OK | ? |
| s1-a7_effort_medium-smoke-build-01.muAmcL | a7_effort_medium | smoke-build-01 | infrastructure_error | PLAN:0:0.25:8 IMPLEMENT:0:0.13:6 REVIEW:0:0.83:12 AUDIT:0:1.36:17 | 2.57 | 742 | arm a7_effort_medium: OK | ? |
| s1-a7_effort_medium-smoke-review-01.oujFBb | a7_effort_medium | smoke-review-01 | infrastructure_error | REVIEW:0:2.53:18 AUDIT:0:1.98:28 | 4.51 | 1148 | arm a7_effort_medium: OK | ? |
| s1-a7_effort_medium-smoke-review-01.PKQrzj | a7_effort_medium | smoke-review-01 | completed | REVIEW:0:1.99:19 AUDIT:0:2.02:18 | 4.02 | 1203 | arm a7_effort_medium: OK | ? |

Rows: `evals/results/ablation-2.0/smoke-258/rows.jsonl` (20 rows, `ablation-row.sh --validate … --allow-ungraded` OK). Run directories: `~/.cache/loa/cycle-130/smoke/s1-*/` (record branch carries this file, not the directories).
