# Fairness review — feature-v2-03

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty, and neither names an arm id, a test or the overlay path. TASK.md is a precise behavioural spec: the API, the file format and digest, the reuse rule, the seven ordered errors and the CLI. Every hidden assertion traces to a sentence:

- `test_checkpoint_format_after_a_full_run` traces to the format paragraph and the digest definition, and to "`how` is `"ran"` when the step's function was called". Its last line requires that no temporary file is left beside the checkpoint. That follows from "write a temporary file in the same directory, then `os.replace` it over the checkpoint".
- `test_resume_reuses_every_completed_step` traces to the four-condition reuse rule, "A reused step's function is not called", and "After every completed step, reused or ran, the whole file is rewritten". The test checks that the rewritten file is JSON-equal to the old one.
- `test_a_failed_step_restarts_from_its_recorded_input` traces to "the exception propagates unchanged and the file keeps the entries of the steps completed before it. A later resume reruns that step from its input".
- `test_once_a_step_runs_every_later_step_runs` traces to "The first step that is not reused runs, and so does every step after it … a changed pipeline input reruns everything".
- `test_an_edited_middle_output_invalidates_the_steps_after_it` follows from "its recorded output becomes the next step's input" and the input-digest condition. Step 2 is reused with the edited output. Step 3's recorded input digest then no longer matches, so step 3 runs.
- `test_a_run_without_resume_deletes_the_old_checkpoint_first` traces to "It deletes an existing checkpoint file before the first step runs". The test's `not ck.exists()` after step 1 fails also follows, because the file is written only "after every completed step".
- `test_resume_needs_a_checkpoint_and_tolerates_a_missing_file` traces to the `ValueError("resume needs a checkpoint")` sentence, "A run without a checkpoint reports every completed step as `"ran"`", and "A run with `resume` and no checkpoint file is a fresh run".
- `test_a_checkpoint_from_another_pipeline_is_refused_before_any_step` traces to "`CheckpointError` is a subclass of `PipelineError`" and to errors 6 and 7 with their exact texts. The renamed pipeline has three steps, so error 6 passes and error 7 fires at entry 2. The shorter pipeline fires error 6. Both happen "before any step runs".
- `test_corrupt_checkpoints` (13 inputs) traces to errors 1 to 5 in order. `b"\xff\xfe{}"` is "not valid UTF-8 JSON". The missing key gives `None`, and `"1"` and `true` give their reprs, as stated. The bad-entry cases (a missing key, an extra key, uppercase hex, a non-string name and a non-object entry) each map to the rule-5 wording "exactly the keys `name` (a string), `input` (64 lowercase hex digits) and `output`".
- `test_an_output_that_is_not_json_keeps_the_earlier_entries` traces to the `CheckpointError(f"step {name!r} output is not JSON-serialisable")` sentence, "right after that step returns" and "The file then keeps the entries written before". The closing `p.run(["a"]) == 1` follows from "With `checkpoint=None` a run behaves exactly as today".
- `test_cli_checkpoint_and_resume` traces to "With `--checkpoint`, it prints one line per completed step to standard output: `<how> <name>`". The silent run without the flag is today's behaviour, since the fixture CLI prints nothing on success.
- `test_cli_errors` traces to the `--resume` usage-error sentence and the `CheckpointError` sentence: exit status 1, nothing on standard output, `stagerun: <message>`, and the output file not written.

No assertion depends on an ordering, format or message the brief leaves open.

## 2. Red then green

Runner: host Python 3.13.5 and pytest 9, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`, a fresh `fixture/` copy per side, the manifest file at its `dest`, and the reference applied with `patch -p1` after a clean dry run, leaving no `.orig` or `.rej`.

```
[base] pytest -q tests                         => 12 failed, 16 passed in 0.07s
[base] pytest -q tests/acceptance              => 12 failed in 0.06s
[base] pytest -q tests --ignore=tests/acceptance => 16 passed in 0.02s
  patching file src/stagerun/checkpoint.py
  patching file src/stagerun/cli.py
  patching file src/stagerun/errors.py
  patching file src/stagerun/pipeline.py
[ref]  pytest -q tests                         => 28 passed in 0.04s
[ref]  pytest -q tests/acceptance              => 12 passed in 0.04s
[ref]  pytest -q tests --ignore=tests/acceptance => 16 passed in 0.02s
```

The counts match `success_criterion`. The hidden file fails 12 of 12 at base and passes at the reference. The regression command passes 16 cases at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line naming the file, the overlay path, the counts at both ends and the regression condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py` and `tests/test_stagerun.py`, and the fixture has no ini or pyproject. `bounds`, `suite_version: 2`, and `source.kind: synthetic` with the date 2026-10-17 all match the rules. The fixture is 52K and clean. `no-secrets.sh` exits 0.

## Notes

- **Hardness:** moderate. The reference adds about 140 lines in four files, and the brief is precise enough to implement line by line. The cases a bare agent can miss are `true` as a version, since `True == 1`, invalid UTF-8 as "not JSON", deleting the file before step 1, and the edited-middle-output interaction. Missing any one of them fails the task, so a bare pass is plausible but not certain.
