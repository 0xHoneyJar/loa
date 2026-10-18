All good

# Sprint 258 review — round 2 (cycle-130 Sprint 1) — APPROVED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-15
**Implementation:** `0c200dd6` (fix round r258-1 on `05442536`, base `252501b4`); reports `reviewer.md` (Feedback Addressed section), `reviewer-fix.md`, `reviewer-a.md`, `reviewer-b.md`, `reviewer-c.md`, `smoke.md`, `toolchain.md`
**Dissent:** `adversarial-review.json` (round 2, code-only diff of the fix range `05442536..0c200dd6`, 11 files / 669 lines) — two voices (`codex-headless` gpt-5.5-pro primary: no findings; `claude-headless` companion: 5 advisories DISS-C-001 … DISS-C-005), `verdict_quality.status` APPROVED, consensus, chain_health ok, 0 rejected payloads. Round 1 is `engineer-feedback-r1.md` / `adversarial-review-r1.json`.
**Local checks:** `evals/tests/` 269/269 (13 new cases), `tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope}.bats` 20/20, trust-boundary scan clean (no `source`/`.` with `$`, no `eval` with `$` under `evals/harness`), `tools/check-manifest-paths.sh` and `tools/gen-checksums.sh --check` unchanged (no `.claude/` edit), `evals/harness/spend.sh` on the live ledger exits 0 and reads complete (USD 97.89 of 1,500).

## Round 1 items

Every round-1 finding is closed in `0c200dd6`, each with a test that fails on `05442536` and passes now (the implementer restored each script from `git show HEAD:<path>` to confirm the "fails before"; `reviewer-fix.md` has the table):

- **MEDIUM-1 closed.** `evals/harness/Dockerfile.ablation` has one `FROM` and no `cargo install`; the line explaining why `br` is absent stays. No `COPY --from` consumer exists, so the legacy builder now builds the file as BuildKit did.
- **MEDIUM-2 closed.** `evals/harness/ablation-row.sh` writes the pipeline, task, grade, manifest, MODELINV, both envelopes and the transcript write list under a `mktemp -d` and binds them with `--slurpfile`; only scalars travel as `--arg`. The new case feeds a 204,800-byte MODELINV ledger whose rows the REVIEW phase owns, asserts the row validates and that `voice_cost_usd` sums the rows (1.1), and the old script on the same input fails with `Argument list too long` (exit 126).
- **LOW-1 closed.** `ms()` is `try … catch null`; `voices()` reads `verdict_quality` and `companion_voice` through object guards (`first(…, null)` keeps a boolean `false` as null rather than aborting); `models_used` passes an object guard before `keys[]`; the writer defaults `name`, `model_requested` and `models_used` and coerces the three `verdict_accuracy*` fields to boolean or null, so the writer always satisfies its own `--validate`; a row-program abort is `usage "row build failed for <run_id>"` (exit 2, documented).
- **LOW-2 closed.** `spend.sh` appends ` INCOMPLETE (N skipped)` and exits 1 when a line was skipped, `--json` carries `complete`, dedup keeps the larger `cost_usd` per `run_id` in either order, and rows without a `run_id` count once each with one warning per file.
- **LOW-3 closed.** `aggregate_status` filters `map(select(.screen != true))` before every derived field (`batches`, `cuts`, `per_arm`, `state`, `source_commit`, `model_id`) and the `-path` filter is gone; `--batch screen-*` without `--screen` is exit 2.
- **LOW-4 closed.** `freeze.sh` lists files and symlinks, refuses a symlink or a newline path with the documented line and exit 1 before hashing, for writes and `--check` alike; no manifest is written on refusal.
- **LOW-5 closed.** `pipeline-run.sh:85`, `CHANGELOG.md:17` and `grimoires/loa/sdd.md:112,139` read codex 0.162.1; a test ties the executor header to the Dockerfile's `CODEX_VERSION`.

## Round 2 dissent findings (all advisory; checked against the tree)

- **LOW-1 — `spend.sh` uses exit 1 for both an unreadable file and an INCOMPLETE total (DISS-C-002, confirmed as a design nit).** A caller doing `json=$(spend.sh --json) || die` would abort on one bad ledger line although the JSON it printed already says `complete: false`. No script in the tree calls `spend.sh` today (`run-ablation.sh`, Sprint 260, will). Follow-up `bd-li5vl`: a distinct exit code 3 for INCOMPLETE before that caller lands; DEC-0495 (L16) stands until then.
- **LOW-2 — a non-object `models_used` is coerced to `{}` and the model-mismatch signal is lost (DISS-C-003, confirmed as hardening).** `pipeline-run.sh` always emits an object (`with_entries` over `modelUsage // {}`), so no producer in this tree hits it; the round-1 brief asked for "never abort", and the coercion is what the writer's own validator requires. Follow-up `bd-z7ytx`: record `models_used not an object` as a `degraded_reason` when the row writer is next touched (Sprint 259).
- **LOW-3 — the MODELINV >200 KB case scans the shared `${TMPDIR:-/tmp}` for leftover work directories (DISS-C-005, confirmed).** A concurrent `ablation-row.sh` on the host could make it flaky; CI runs `bats evals/tests/` serially with nothing else on the runner, so it is not flaky there. Follow-up `bd-80l5u`: scope the check to a per-test `TMPDIR` (Sprint 259).
- **Refuted — the screen marker might be missing or a string, letting screen batches leak into the aggregate (DISS-C-001).** `run-arms.sh:271,366` pass `--argjson screen "$SCREEN"` and `:371` emits `{screen: true}` as a JSON boolean on every screen batch; RA-8 runs a real `--screen` batch, asserts `.screen == true` in its `STATUS.json` and then that a later regular batch's suite aggregate never reads it. RA-11 adds the name-independent cases on top.
- **Refuted — a `COPY --from=brbuild` consumer could remain (DISS-C-004).** `grep -- '--from' evals/harness/Dockerfile.ablation` finds nothing; the file has exactly one `FROM`.

## Acceptance criteria

AC-1.1 … AC-1.14 met (evidence in `reviewer.md`, re-checked in round 1 and unchanged by the fix: the fix touches no acceptance-bearing behaviour, only the hardening the findings named). The floor is untouched. The follow-ups routed in round 1 (`bd-obk5p`, `bd-eriso`, `bd-xj75c`) and here (`bd-li5vl`, `bd-z7ytx`, `bd-80l5u`) carry the remaining low items into Sprints 259 and 260.

## Verdict

APPROVED — Sprint 258 proceeds to the security audit.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-258","ts":"2026-10-15T02:15:00Z"} -->
