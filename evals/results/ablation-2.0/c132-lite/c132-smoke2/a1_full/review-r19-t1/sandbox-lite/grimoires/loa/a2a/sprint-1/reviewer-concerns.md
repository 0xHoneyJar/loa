# Reviewer concerns — sprint-1 (PR: sprint-255, cycle-129)

Scope: `pr/head.diff`, 81 files. The fixture excludes `grimoires/`, so the generated register
`grimoires/loa/guards.md` and the record corpus under `evals/fixtures/review-prs/` could not be
inspected; findings below are about the files present.

## Concerns to probe

1. `evals/harness/run-arms.sh` — re-running the same deterministic default batch name after a
   partial run appends duplicate trial rows to `<arm>/results.jsonl` and resets the per-arm
   STATUS counters (DONE/FAILED start at 0; MANIFEST.json is rewritten). `arms-report.py`
   counts every row per fixture, so coverage can be satisfied by duplicates.
2. `evals/harness/run-arms.sh` — `date +%s%N | cut -c1-13` is GNU-only; the script claims bash 3.2
   (macOS) compatibility. On BSD date the arithmetic `$(( end_ms - start_ms ))` is a syntax
   error inside the background job → no row → trial FAILED.
3. `evals/harness/run-arms.sh` — `is_transport_failure` greps `agent-output.json` for
   `network`, `5[0-9][0-9] `: model prose in the result text can classify a genuine agent
   error as transport and trigger a retry.
4. `evals/harness/run-arms.sh` — `aggregate_status` passes `$(find …)` unquoted to jq; a
   results dir with spaces breaks it; `--results-dir` is not validated.
5. `evals/harness/execute-agent.sh` — arm mode copies the prompt tree's `.loa.config.yaml` over
   any config the fixture itself carried; `karpathy_block` toggle rewrites `constraints.json`
   with `(.constraints // []) |=` creating the key when absent.
6. `evals/harness/seed-corpus-from-record.sh` — `REDACTED` counter is incremented for the diff
   text and again for each base/head file (`redact(b)` with count=True), so the dropped.txt
   note over-reports; binary rename detection `p.split(" => ")[-1].strip("{}")` mishandles
   `dir/{old => new}/file`.
7. `evals/harness/arms-report.py` — `sorted({m.get('source_commit') …})` raises TypeError when
   a manifest lacks the key (None vs str).
8. `.claude/scripts/guard-yield.sh` — the replay heuristic's `$tmp` prefix is the generator's
   own TMPDIR; `TMPDIR=/` would classify every row as replay. `"$AUDIT_LOG".*` glob also reads
   `.lock`/`.bak` siblings as segments.
9. `.claude/skills/implementing-tasks/SKILL.md` — `app.permission` changed read → read-write; not
   named in the PR title; check whether it is intended (SURGICAL).
10. `.github/workflows/check-prompt-budget.yml` + `tests/unit/prompt-budget.bats` PB-10 — the
    header comment now states 160,000 / 114,688; `tools/check-prompt-budget.sh` is not in the
    change, so the pin depends on constants outside the diff.
11. `.claude/scripts/validate-artifact.sh validate_sprint_kinds` — the J heuristic and the
    `T`/`U` classification; `[[ "$plan_date" < … ]]` string compare.
12. `evals/graders/recall-vs-defects.sh` — refuted-share regions and ±3 widening consistent with
    the detection rule?
