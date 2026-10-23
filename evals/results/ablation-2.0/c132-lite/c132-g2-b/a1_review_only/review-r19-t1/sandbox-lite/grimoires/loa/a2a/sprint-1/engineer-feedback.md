# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (task review-r19: the pull request in `pr/`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (81 files): the guard register (`guard-origins.yaml`, `floor.yaml`, `guard-yield.sh`, `@guard` markers in the fence and the validator, a generated hooks table, a `/loa` Guards line), pre-registered control arms on a record corpus (`run-arms.sh`, `arms-report.py`, `seed-corpus-from-record.sh`, grader 1.2.0, 16 record tasks), the `kind:` task-line rule in `validate-artifact.sh` plus `tools/cycle-ratio.sh`, and `paths:` frontmatter on two rule files.

What holds up: the origin map is complete and internally consistent (the 34 fence markers equal the 34 fence rows; the 21 `floor: true` rows equal `floor_guards`; the pinned `floor.yaml` sha256 matches), the `@guard` marker cross-check in the fence is clean both ways, the committed hooks table is byte-identical to what `guard-yield.sh --hooks-table` regenerates from `settings.json`, and every new unit suite the PR ships passes when run on an overlay (`guard-origins` 15/15 once the register file exists, `guard-yield` 11/11, `validate-artifact-sprint-kinds` 11/11, `cycle-ratio` 6/6, `rule-paths` 6/6, `loa-status-guards` 3/3; `floor-snapshot` skips without `origin/main`). The glossary passes `--type glossary`; the rule-lifecycle validator accepts both path-scoped rule files.

What blocks: the PR adds a CI drift gate and a bats test that both require a tracked `grimoires/loa/guards.md`, and that file is not in the change, so the merged tree fails its own new gate. The 16 new record tasks and both suites reference fixture directories, labels, manifests and a corpus freeze that are not in the change either. Both findings carry medium confidence because the frozen PR could in principle omit generated artefacts, but PR.md's "81 file(s) in scope" equals the 81 files in the diff, and the seed script introduced here is the only documented producer of the fixtures.

Beyond the two blockers, `guard-yield.sh` has four reproduced robustness gaps (the heredoc heuristic classifies the System-Zone tamper shape as a likely false positive, a symlinked directory under `.claude/hooks` escapes containment, a misordered end marker truncates `hooks-reference.md`, and a sourced lib's `exit` ends the run as a silent success), and the arms harness and seeder have several reproduced correctness defects in the verdict path (refuted-share dedup, a skipped rule reading as "no recall loss", batch re-runs overwriting the manifest, a toggle env var leaking into every arm, a seeder test that passes because the script deleted its own template directory).

**Think Before Coding**: the implementation report is the PR description only; it carries no `## AC Verification` section and no assumptions, so the acceptance-criteria walkthrough the skill requires is missing (automatic CHANGES_REQUIRED on its own). The scope creep in `implementing-tasks/SKILL.md` (app zone `read` to `read-write`) is undocumented anywhere in the change (SURGICAL).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Completeness: the generated register is not in the change but CI now gates on it

- **HIGH** (confidence: medium) `head/.github/workflows/bats-tests.yml:159` — the new step `bash .claude/scripts/guard-yield.sh --check` exits 1 ("drift") whenever `grimoires/loa/guards.md` is absent or stale, and no `grimoires/loa/guards.md` is in this change (no `grimoires/` path appears in `head.diff`; PR.md counts 81 files and the diff has 81). `head/tests/unit/guard-origins.bats:120` (GO-9) runs the same `--check` and expects exit 0 and "in sync". Verified on an overlay of the head tree: `--check` with no register exits 1 with `drift: .../guards.md differs from the generated register`; after `guard-yield.sh --hooks-table` writes the file, GO-1..GO-15 all pass and `hooks-reference.md` is unchanged, so the register file is the only missing piece.
**File:** `head/.github/workflows/bats-tests.yml:159`, `head/tests/unit/guard-origins.bats:120`, `head/.claude/scripts/guard-yield.sh:596-615`
**Issue:** The change ships the generator, the CI gate and the test, but not the generated artefact the gate compares against. The script's own header (`head/.claude/scripts/guard-yield.sh:19`) says the register is "tracked".
**Why This Matters:** The merged tree is red on its first CI run, and `/loa` prints "no register" until someone runs the generator. A drift gate whose reference file is missing cannot distinguish "never generated" from "stale".
**Required Fix:** Run `.claude/scripts/guard-yield.sh --hooks-table` at the PR's head and commit `grimoires/loa/guards.md` with the change. Add a one-line guard in `--check` that names the missing file explicitly (exit 1 with "no register at <path>; run --hooks-table") so the failure mode is self-describing.

### 2. Completeness: 16 record tasks and both suites point at fixtures that are not in the change

- **HIGH** (confidence: medium) `head/evals/tasks/review-recall/review-pr-11.yaml:5` — `fixture: review-prs/pr-11` (and the same shape in `review-pr-12..18.yaml` and `audit-pr-11..18.yaml`); `head/evals/suites/review-recall.yaml:7` and `head/evals/suites/audit-recall.yaml:7` include `tasks/<suite>/**/*.yaml`, so both suites now schedule 8 tasks each whose fixture directory, hidden labels (`labels/pr-NN.tsv`), manifest (`manifests/pr-NN.json`), `record-pairs.tsv`, the `corpus.tsv` record rows and the refreshed `SHA256SUMS` are absent from the diff (`head/evals/fixtures/` holds only `build-review-corpus.sh` and `review-kinds/`). The `.gitignore` change at `head/.gitignore:32-33` and the README at `head/evals/README.md:514` describe these as tracked artefacts produced by `seed-corpus-from-record.sh`, which this PR introduces, so nothing upstream could have produced them earlier.
**File:** `head/evals/tasks/review-recall/review-pr-11.yaml:5`, `head/evals/suites/review-recall.yaml:7`, `head/evals/suites/audit-recall.yaml:7`
**Issue:** The task descriptions carry seed-generated label counts (5, 8, 5, 2, 3, 4, 20, 8), so the fixtures were built locally and not committed.
**Why This Matters:** `run-eval.sh --suite review-recall` fails sandbox creation on 8 of its tasks, `run-arms.sh --fixtures pr-11,...` dies in `verify_corpus`, and the grader's manifest checksum cannot cover the record corpus. The arms feature this sprint delivers cannot run against the corpus it was built for.
**Required Fix:** Commit the seeded fixtures (`pr-11` .. `pr-18` with `fixture.yaml`, `labels/`, `manifests/`, `record-pairs.tsv`, the `corpus.tsv` rows and `SHA256SUMS`), or remove the 16 task files and the README/.gitignore references until they land. Add a cheap guard in `run-eval.sh` task validation that fails fast when `fixture:` names a directory that does not exist.

---

## Observations

### 1. guard-yield.sh: yield heuristics and containment

- **MEDIUM** (confidence: high) `head/.claude/scripts/guard-yield.sh:507` — `likely_fp` treats any block whose command holds a heredoc as a likely false positive, including the sixteen `FR-SZ*` floor fences. The System-Zone tamper shape is exactly `cat > .claude/hooks/x.sh <<'EOF'`; `head/tests/unit/guard-yield.bats:34` and `:85` pin that very row (`FR-SZ2-REDIR` with `<<`) as `likely_fp`. The yield therefore under-reports real catches of the floor fences, which is the figure the register exists to surface. Apply the heredoc rule to content guards only (not `FR-SZ*`), and flip the GY-3 expectation.
- **MEDIUM** (confidence: high) `head/.claude/scripts/guard-yield.sh:220-230` — containment resolves a symlink only when the leaf script itself is a link (`-L "$abs"`); an intermediate symlinked directory passes. Reproduced: with `.claude/hooks/safety` replaced by a symlink to a directory outside the tree, the register accepted all ten `hook:safety/*` rows and exited 0. Resolve the parent with `pwd -P` and compare the physical path to `$ROOT/.claude/` before accepting the row.
- **MEDIUM** (confidence: high) `head/.claude/scripts/guard-yield.sh:387-397` — `render_hooks_ref` checks that each marker appears exactly once but not their order. Reproduced: a reference file with `<!-- guard-register:end -->` above `<!-- guard-register:begin -->` was rewritten with every line after the begin marker dropped, and `--hooks-table` then installed the truncated file over the tracked `hooks-reference.md` (`:615`). Check `begin < end` and `die 3` otherwise.
- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:310-330` — the cross-check requires every `floor: true` gate row's `script` to exist but not, for a gate implemented as a hook, that `settings.json` still runs it. Unregistering `safety/adversarial-review-gate.sh` and deleting its `hook:` row leaves `--check` green while the COMPLETED gate never fires; `floor-snapshot.bats` FS-3 would catch it only when `origin/main` is reachable, and it skips otherwise. Require a registration for a floor gate whose `script` is under `.claude/hooks/`.
- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:470` — `source "$HEREDOC_LIB" 2>/dev/null` runs in the main shell, so an `exit` inside the sourced lib ends `guard-yield.sh` with that status. Reproduced on the overlay with a classifier lib that sources the fence: the run printed only the audit-log WARN, exited 0 and wrote none of `guards.md`, `guard-yield.md`, `guard-yield.json`. Source in a subshell (or call `heredoc_nonexec` via `bash -c`) and treat a classifier that cannot load as "no classifier".
- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:519` — the burst rule discards every block in a UTC minute that holds 10 or more, on the premise that "no interactive session blocks ten commands in one minute". An unattended `/run` session retrying a blocked System-Zone write does exactly that, and those are the real catches the floor fences exist for. Scope the burst rule to rows whose `cwd` is under a temp prefix, or raise the threshold and record the dropped count per pattern id so the loss is visible.
- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:528` — only rows written while the hook's own environment carries `LOA_AUDIT_REPLAY=1` are tagged `replay: true`. The new suites and `run-corpus.sh` export it, but any pre-existing suite or ad-hoc reproduction that pipes JSON into the fence from inside the repository appends untagged block rows that the yield counts as real (companion dissent DISS-C-004). The cwd and burst rules catch most of these; document the residue in the heuristic string.

### 2. Floor and rule-file design

- **LOW** (confidence: medium) `head/.claude/data/floor.yaml:41` — `floor_keys` protects `destructive_command_guard.*`, yet the fence's hook row (`head/.claude/data/guard-origins.yaml:162`) says `knob: none`, and all fifteen `floor: true` fence rows name `LOA_ALLOW_STATE_ZONE_EXEC_WRITE` as a knob that switches them off. The floor is defined as what "no profile, knob or cycle task may weaken"; nothing cross-checks `floor_keys` against the knobs of floor guards, and `flatline_protocol.security_audit.enabled` and `hounfour.locality` tie to no register row (companion dissent DISS-C-002, DISS-C-005). Sprint 2's `profile-floor.bats` should assert the two halves agree.
- **LOW** (confidence: medium) `head/.claude/rules/stash-safety.md:2-6` — scoping the rule to `**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**` means a session that edits only Markdown or app code and runs `git stash pop | tail -1` never loads it; the rule governs the model's Bash behaviour, not shell-file content (companion dissent DISS-C-003). This follows SDD D-3.1 as pinned by RP-2, so it is a design note, not a defect; consider adding `**/*.md` or leaving the rule unscoped.

### 3. SURGICAL: undocumented permission change

- **MEDIUM** (confidence: medium) `head/.claude/skills/implementing-tasks/SKILL.md:28` — the app zone moves from `permission: read` to `read-write` in a sprint whose stated scope is the register, the arms, task kinds and rule path-scoping. The value is plausibly correct for `/implement`, but nothing in PR.md, the sprint plan, CLAUDE.loa.md ("App: Confirm writes") or a CHANGELOG line names it, and `reviewing-code/SKILL.md:135` now defers to the frontmatter for zone semantics, so the widening is load-bearing (companion dissent DISS-C-001). Either revert it here or land it with a one-line rationale and a `validate-skill-capabilities` expectation.

### 4. Grader and arms report: the verdict path

- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:175` — `findings = sorted(set(cites))` dedups on the raw cited `(path, lo, hi)` while matching uses `path_matches` normalisation. Reproduced in a scratch copy: one review citing `a.sh:40`, `head/.claude/scripts/a.sh:40` and `a.sh:40-41` plus `b.sh:200` and `head/.claude/scripts/b.sh:200` graded `findings_cited: 5, findings_refuted: 2, refuted_share: 0.4` instead of 2 / 1 / 0.5. `refuted_share` feeds the pre-registered `refuted_share_max_rise` rule, so an arm's verdict moves with citation spelling. Normalise the path (and merge overlapping ranges) before `set()`.
- **MEDIUM** (confidence: high) `head/evals/harness/arms-report.py:296` — the refuted-share rule is applied only when both shares are non-null; an arm or baseline with `findings_cited == 0`, or rows from a grader without the field, drops the third pre-registered rule silently and the verdict still reads `no recall loss` (reproduced with `findings_cited: 0` on every row). The docstring (`:24`) says every rule must hold; an unevaluable rule should yield `inconclusive`.
- **MEDIUM** (confidence: high) `head/evals/harness/arms-report.py:393` — `sys.exit(main())` lets any uncaught exception (missing suite yaml under `--suites-dir`, malformed `STATUS.json`; both reproduced) exit 1, which the docstring (`:30`), `report.sh` and AR-5 define as "refused, pass --partial". A gate that treats 1 as "wait" treats a crash as "wait". Wrap `main()` and map exceptions to exit 2.
- **LOW** (confidence: high) `head/evals/harness/arms-report.py:144` (same at `head/evals/harness/compare-ab.py:71`) — every `models_used` key with non-zero output tokens joins the skew set, so one auxiliary call in one trial invalidates the whole comparison (exit 2) with no override; before this PR the max-output model was attributed. Reproduced with synthetic rows. Intentional per the inline comment, but undocumented in usage/README.
- **LOW** (confidence: high) `head/evals/harness/arms-report.py:219-221` — `sorted({m.get("source_commit") ...})` raises `TypeError` when one manifest lacks the key (hand-edited or legacy batches); filter `None` first as `:280-285` already do.

### 5. run-arms.sh

- **MEDIUM** (confidence: high) `head/evals/harness/run-arms.sh:251-257` — a second run into an existing batch with the same source and model is accepted; rows are appended to `<arm>/results.jsonl` (`:408`) but `MANIFEST.json` is overwritten with the latest run's `arms`/`fixtures`/`trials_planned` and `DONE`/`FAILED` restart at 0 (`:264-265`), so `STATUS.json` understates and `arms-report.py` (`:206-211`) reads only the arms the last manifest lists. The default batch name (`:126`) collides for any two fixture sets sharing first, last and count. Reproduced: three appended rows all labelled `trial: 1` satisfied `trials_required: 3`. Refuse a non-empty batch or merge instead of overwrite.
- **MEDIUM** (confidence: high) `head/evals/harness/run-arms.sh:336-337` — the per-trial env sets `LOA_EVAL_ARM` and `LOA_EVAL_SUITE_FILE` but does not clear `LOA_EVAL_ARM_TOGGLES`, which `execute-agent.sh:163` prefers over the suite's `ab.arms[]`. An operator with that variable exported runs every arm with the same toggles while rows are labelled by arm id, and the report never compares `executor.arm_toggles` with the declared toggles. `run-arms.bats:31` unsets it in setup, which shows the leak is known. Set `LOA_EVAL_ARM_TOGGLES=` in the trial env and have the report flag a mismatch.
- **MEDIUM** (confidence: medium) `head/evals/harness/run-arms.sh:97` and `head/evals/harness/arms-report.py:182-192` — "pre-registered" toggles and thresholds are read from the live `evals/suites/<suite>.yaml` at run time and report time, not from the pinned worktree, and `MANIFEST.json` records only the suite path (`:191`). A committed threshold edit after the data is in changes the verdict with nothing in the artefacts showing it (`harness_dirty` covers uncommitted edits only). Snapshot the `ab` block or its sha into the manifest and refuse on mismatch.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:380` — nothing checks that `executor.model_id` (from `modelUsage`) corresponds to `--model`; skew is flagged only between arms, so every arm running on a substituted model reports `complete`. `head/evals/tests/run-arms.bats:78` asserts `claude-sonnet-5-20260401` for a run that requested `claude-fable-5-1` because the stub ignores `--model`, encoding the gap as passing.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:124` — `.loa.config.yaml` is gitignored (`head/.gitignore:169`), so the detached worktree at `--source-commit` never holds one; in ARM_MODE `execute-agent.sh:157-158` copies nothing, the baseline runs with no config and `no_companion` creates a two-key config from scratch. The header's "every arm sees the same config" does not hold; `run-arms.bats:23-24` commits a config into the throwaway repo, a path the real repo cannot take.
- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:308-315` — `is_transport_failure` greps `agent-output.json` (which embeds the agent's result text) for `network` and `5[0-9][0-9] `, so a review that mentions "network" or "line 512 " is classified transport and retried after a 300 s sleep; `subtype == "missing"` also covers an invalid `--model` or logged-out CLI. Restrict the grep to `agent-stderr.log`.
- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:105` — duplicate ids (`--arms baseline,baseline`) pass validation; `arm_index` returns the first index so one counter takes all completions and `write_status` lets the second entry overwrite with `trials_done: 0` while the script exits 0 "complete". Reject duplicates.
- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:197` — the manifest hardcodes `effort: "task/skill default"` while `execute-agent.sh:296-310` honours an inherited `EVAL_EFFORT`; record `${EVAL_EFFORT:-task/skill default}` or unset it in the trial env.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:286-303` — `aggregate_status` gives up after about 5 s on a stale `.status.lock` and returns 0, so after a crash between `mkdir` and `rmdir` the suite-level `STATUS.json` is never updated again and `cleanup()` does not remove the lock; `$(find ...)` at `:301` is unquoted, so a `--results-dir` with a space breaks aggregation silently.
- **LOW** (confidence: high) `head/.github/workflows/bats-tests.yml:23-26` — no workflow runs `evals/tests`, so none of the four new bats files (`arm-toggles`, `run-arms`, `arms-report`, `seed-corpus`) run in CI; the corpus-drift exit 3 path (`run-arms.sh:402-405`) and the batch lock have no test at all.

### 6. seed-corpus-from-record.sh

- **MEDIUM** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:295` and `:730` — the overwrite refusal fires only when a `fixture.yaml` exists and lacks `sprint:`; an existing `pr-NN` directory without a `fixture.yaml` is wiped by `shutil.rmtree(fdir)` before any validation. `head/evals/tests/seed-corpus.bats:159-161` (SC-6 "non-record fixture is refused") passes for the wrong reason: its `pr-01` has no `fixture.yaml`, so the script deletes the template directory, writes `PR.md`/`head.diff`/`base/`/`head/` into it and then crashes at `:745` copying `REVIEW-INSTRUCTIONS.md` from the directory it just deleted (reproduced: exit 1, templates gone). Refuse any existing `pr-NN` that is not a record fixture, validate before `rmtree`, and have SC-6 assert the refusal text and template survival.
- **MEDIUM** (confidence: medium) `head/evals/harness/seed-corpus-from-record.sh:452-458` — for Bridgebuilder "Fixed" table rows the finding's `text` is `cells[2]` (the Status column) while the path sits in `cells[0]`; cites are extracted from `text` only, so such rows are always dropped as "cites no file" (reproduced). Include `cells[0]` in `text`.
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:404` — `SKIP_SECTION` matches the unanchored substring `closed`, so `## Disclosed Risks` (or "Enclosed", "Closed-loop") silently skips every finding under it, and skipped sections are not written to `dropped.txt`, breaking the header's "every finding that did not become a label, and why". Anchor with `\bclosed\b`.
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:261` — `--approve` rewrites `# approved-by:` and writes the file before `build_manifest()` validates the rows; a non-unique `must_match` exits 1 but leaves the labels file claiming approval, the manifest at `approved: false` and `SHA256SUMS` drifted. Validate first, write to a temp and rename.
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:314-320` — paths come from `git diff --name-status` without `-z` or `core.quotePath=false`; a non-ASCII filename arrives quoted, `show()` returns `None`, and the file is silently omitted from `base/`, `head/` and `head.diff`, dropping any label on it.
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:309-312` — the `--numstat` rename form `dir/{old => new}` is parsed to `new` without `dir/`, so a renamed binary in a subdirectory is not excluded and is then run through `redact()` (`errors="replace"`), corrupting it in both `base/` and `head/`.
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:111-129` — the secret regexes over-match ordinary code (`client_secret: "${{ secrets.CLIENT_SECRET }}"` becomes `client_REDACTED-TEST-SECRET"`, `password="${DB_PASSWORD:-}"` leaves a dangling quote, `xox[bpors]-` matches any `xoxb-` word), and `has_secret()` at `:524` then drops findings that quote such lines. Latent (no hit in this PR's own files) but it rewrites fixture code silently.
- **LOW** (confidence: medium) `head/evals/harness/seed-corpus-from-record.sh:400-404` — `## Observations` entries, where the review skill files demoted speculative highs, are parsed as full findings and can become labels when the fix touches the file; and `RX_H` (`^#{1,4}\s`) has no fence awareness, so a `# comment` inside a code block in a finding body starts a new section and truncates the body (reproduced).
- **LOW** (confidence: high) `head/evals/harness/seed-corpus-from-record.sh:774` — on a `no-secrets.sh` failure during a re-seed, "nothing kept" removes `pr-NN/` and the label files but leaves the previous `manifests/pr-NN.json`, both task YAMLs and the `corpus.tsv` row, and `SHA256SUMS` stays stale so `--check` fails (reproduced). Remove the stale artefacts as the gap path at `:713-718` does.

### 7. validate-artifact.sh, run-eval.sh and the kind-01 fixture

- **LOW** (confidence: high) `head/.claude/scripts/validate-artifact.sh:998` — an undated live plan now fails twice for one cause: the Seams rule (`:930`) and the kind rule emit near-identical violations. Factor the header-date gate into one helper and emit once.
- **LOW** (confidence: high) `head/evals/tasks/review-recall/review-kind-01.yml:6-9` — the comment says the `.yml` extension keeps the task out of "any suite, arm run or CI job"; the suite glob and `run-arms.sh` do exclude it, but `run-eval.sh:198` and `:283` (`--skill` and the all-tasks path) use `-name '*.yaml' -o -name '*.yml'` and will run it. Doc inaccuracy only.
- **LOW** (confidence: high) `head/evals/harness/run-eval.sh:341` — `_keep_trial_artifacts` copies `executor.json agent-output.json agent-stderr.log` but not `.eval/arm-removed.txt` (which `run-arms.sh:389` does keep), so an `audit_delta_instruction` arm run through `run-eval.sh` records `arm_evidence` pointing at a file destroyed with the sandbox.
- **LOW** (confidence: medium) `head/evals/harness/run-eval.sh:438` — error-path rows take `arm` from `env.LOA_EVAL_ARM` while completed rows use `$executor.arm // "baseline"`; an exported-but-empty `LOA_EVAL_ARM` (which `execute-agent.sh` treats as `baseline`) is recorded as `arm: ""` on error rows only.

**Complexity pass.** `validate_sprint_kinds` (~95 lines, `head/.claude/scripts/validate-artifact.sh:976-1067`) and the yield `jq` program (~90 lines, `head/.claude/scripts/guard-yield.sh:487-575`) exceed the 50-line threshold; both are single-purpose data pipelines with the awk/jq bodies doing the work, and I would not split them. `SIMPLICITY[shrink]`: the undated-plan branch is duplicated between the Seams and kind rules (observation 7.1). `net: -12 lines possible`.

---

## Rejected dissent payloads

None. The dissent envelope (`grimoires/loa/a2a/sprint-1/adversarial-review.json`) carries `rejected_summary: []`, `rejected_sidecars: []`, and no `adversarial-rejected-review*.jsonl` sidecar exists beside it.

## Cross-Model Observations

The dissent ran on `pr/head.diff` with two voices. The primary (`gpt-5.5-pro`) returned `status: clean` with no findings; the companion (`claude-headless`) returned five ADVISORY findings, none blocking, each read as advisory input and triaged above: DISS-C-001 (the `read-write` widening, observation 3), DISS-C-002 and DISS-C-005 (floor keys versus knobs, observation 2.1), DISS-C-003 (stash-safety path scoping, observation 2.2), DISS-C-004 (untagged replay rows, observation 1.7).

---

## Acceptance Criteria Check

The sprint's success criterion is "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict". The sprint plan carries no `kind:` tags and no `### Seams Under Test` table of its own (it is the review brief, not a plan the kind rule governs).

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Guard register: every guard has an origin row; floor set equals `floor_guards`; `--check` in sync (PRD AC-1.1, AC-1.5) | Fail | Map, floor and hooks table are consistent and all GO-/GY- tests pass on an overlay, but `grimoires/loa/guards.md` is not in the change, so the CI gate and GO-9 fail on the merged tree (Changes Required 1) |
| 30-day host yield with replay exclusion and the likely-FP heuristic (AC-1.2 .. 1.4) | Pass with observations | Works as tested; the heredoc rule misclassifies the System-Zone tamper shape and the burst rule drops unattended-run catches (observations 1.1, 1.6) |
| `/loa` Guards line (D-1.5) | Pass | LSG-1..3 pass; malformed yield file is treated as missing without echoing its content |
| Control arms on a record corpus (FR-2) | Fail | Harness and report are in place and their suites pass, but the corpus the 16 tasks reference is not in the change (Changes Required 2); verdict-path defects in observations 4 and 5 |
| Task kinds: `kind:` rule, template, glossary, `cycle-ratio.sh` (FR-10, D-10.1, D-10.3) | Pass | KINDS-1..11 and CR-1..6 pass; glossary validates; template lines end with the token |
| Path-scoped rule files (D-3.1) | Pass | RP-1..6 pass; rule-lifecycle validator accepts both files |
| `## AC Verification` walkthrough in the implementation report | Fail | `reviewer.md` is the PR description only; no AC walkthrough, no assumptions recorded |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the seeder's secret scan runs; its regexes over-match, observation 6.7)
- [x] Input validation at trust boundaries present (ids regex-checked in `guard-yield.sh`, `run-arms.sh`, `seed-corpus-from-record.sh`; `python3 -I`)
- [ ] Containment of hook script paths: a symlinked directory under `.claude/hooks` escapes the check (observation 1.2; CWE-59 link following)
- [x] No shell injection from data: audit rows reach `jq` as `--arg`; `loa-status.sh` sanitises `scope` and coerces numbers (LSG-3)
- [x] No command text, cwd or model name reaches the register or yield outputs (GY-5)
- [ ] The floor as enforced invariant: knobs and env vars can still weaken `floor: true` fences; unregistered floor gate is not detected by `--check` (observations 1.4, 2.1)

---

## Code Quality Summary

**Strengths:**
- The origin map, floor file and markers are mechanically cross-checked both ways, with fixture tests for every failure mode (GO-10..GO-15, GY-7, GY-10).
- Yield and register are cleanly separated (structural file is a pure function of the repository; host yield untracked), and the privacy test (GY-5) is a real negative check.
- The `kind:` rule reuses the Seams rule's fence tracker and date gate exactly; `cycle-ratio.sh` uses the same awk scope so the two cannot drift.
- Arm ids, fixture ids and batch names are validated before any path use; exit codes match the headers; the bootstrap is a paired per-fixture delta with a deterministic seed.

**Areas for Improvement:**
- Ship generated artefacts with their generators (register, fixtures, freeze) or gate on their presence explicitly.
- Validate before destroying (`rmtree` before the refusal; `--approve` before `build_manifest`; manifest overwrite before the batch check).
- Pin what is "pre-registered" (thresholds, toggles, model) into the artefacts the report reads, so a later edit cannot move a verdict silently.
- Run the new `evals/tests` suites in CI.

---

## Next Steps

1. Commit `grimoires/loa/guards.md` (regenerated at head) and the seeded record corpus, or remove the 16 task files until the corpus lands.
2. Fix the four `guard-yield.sh` MEDIUMs (heredoc rule scope, symlinked directory containment, marker order, subshell source) and the verdict-path MEDIUMs in the grader, `arms-report.py`, `run-arms.sh` and the seeder.
3. Add an `## AC Verification` section to `grimoires/loa/a2a/sprint-1/reviewer.md` with `file:line` evidence per criterion, and name the `implementing-tasks` zone change or revert it.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":15,"low":23},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T15:58:00Z"} -->
