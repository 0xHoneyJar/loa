# s3-d report — Sprint 274 Task 3.4 (harness documentation); Task 3.6 not started

Status: Task 3.4 DONE. Task 3.6 NOT TOUCHED: no "smoke green" message from the lead has arrived, so the session-library drift test (`evals/tests/blind-session.bats` BS-8) and its fixture stay.
Patch: `~/.cache/loa/cycle-133/patches/s3-d.patch` (+ `.stat`). Two files, docs only. Base: `de366cc63`.

## What was built
- `evals/harness/README.md` is complete. The existing sections `## Refusal policy` and `## Pipeline version (cycle-133 Sprint 273 pin)` are byte-identical except for the pin section's last sentence ("Sprint 274 Task 3.4 completes this README …"), which is removed. DEC-0906 and the two script headers cite those headings, so they are kept verbatim. New sections:
  - intro + batch flow (README.md:1-5)
  - `## Mount modes` (:7): closed / open / none / skill, plus `home-scope` marked "lands with Task 3.1" (design per SDD C-10 + D-3.6, clauses (e)(f)(g), the spike gate, halt + the operator's fallback decision)
  - `## Egress block` (:27): threat model, layout, per-arm key resolution, refusal, operating commands, self-check, records, release gate
  - `## Supervisor` (:67): precondition, daemon, durable identity, dead/hung, retried vs not, pre-resume steps, cap, reboot restore, stop, bats coverage
  - `## Denominators` (:120): the three stacked rules (row status, matched cell, refusal_denominator)
  - `## Pipeline versions` (:130): version table (intermediate `50881e6f4` per DEC-0906; the measurement pin "not yet recorded", Task 3.5)
  - `## Exit codes` (:163): § 5.4 restated + per-script table for 11 scripts with file:line cites
  - `## Test health` (:183): QUARANTINE.tsv, the helper, the CI gate (0/1/2/3), the `-diff` frozen trees
- `evals/README.md`: a new final section "Index: the ablation harness, its analysis and test health", an 18-row path table.

## Tests
Docs only, so no bats or pytest change. Verification run instead:
- Every `:N` cite in the exit-code table was checked mechanically against the named script (a python pass printing each cited line). Every cite resolves to an `exit`, `finish <state> <code>`, `return`, `rc=`/`exit_code=` assignment or `sys.exit`. Three grader cites are `rc = …` lines, so the row also cites `sys.exit(rc)` at `ablation-grade.sh:3576`.
- The `-diff` reading commands were tested in a scratch repo: plain `git diff`, `git diff --no-ext-diff` and `git show <rev>` print "Binary files differ". `git diff --text`, `git show --text` and `git show <rev>:<path>` show the content.
- `git grep` for references to the README headings: `§ Refusal policy` (ablation-row.sh:159, run-ablation.sh:172) and DEC-0906's `§ Pipeline version (cycle-133 Sprint 273 pin)` both still resolve.
- No cycle-132 read numbers in either file (grep).

## Acceptance criteria (sprint.md Task 3.4)
- harness README complete: mount modes — Met (home-scope marked lands with Task 3.1). Egress threat model and supervisor — Met. Refusal policy and denominators — Met. Pipeline version table — Met (the measurement-pin row is pending Task 3.5). Exit codes per § 5.4 — Met, with the divergences named.
- `evals/README.md` index — Met.
- CHANGELOG entries — the lead's (common-s3 shared-file rule), not in this patch.
- Brief extras: the `.gitattributes -diff` rows — Met (Test health). QUARANTINE.tsv, the validator and the helper, one paragraph — Met.

## Judgment calls
- **Exit codes as implemented, divergences named.** I documented each script's codes as the code implements them and named where they differ from § 5.4. I did not restate § 5.4 as if every script followed it. `run-ablation.sh` 3 = failed (drift, invalid rows, nothing completed, every arm paused). `pipeline-run.sh` 3 = cap_failure or the broken-cheval refusal, and 4 = interrupted. `blind-session.sh` 3 = tainted. Rejected: writing § 5.4's meaning for 3 ("degraded") against those scripts, which would be false. Rejected: changing the scripts, which is outside my ownership and is behaviour change.
- **The quarantine date is the committer date.** The brief says "blame author date + 30 days". `tools/check-quarantine-expiry.sh` and SDD C-5 use the UTC committer date, with 30 or 31 days allowed and a shallow-clone rule. I documented the code. Rejected: the brief's wording.
- **`--text`, not `--no-ext-diff`.** The brief says reviewers read the frozen trees with `git diff --no-ext-diff`. Tested, that still prints "Binary files differ". I documented `git diff --text` and `git show <rev>:<path>` (the `.gitattributes` comment also says `--text`) and stated that `--no-ext-diff` does not work.
- **home-scope from the SDD, marked as not landed.** No Sprint 3 patch exists yet, so I described it from SDD C-10 + D-3.6 in one paragraph and said the landed contract replaces it when Task 3.1 lands. Rejected: omitting it (the brief requires it). Rejected: detailed flags such as `--setting-sources`, which the spike decides.
- **Existing headings kept verbatim.** I added `## Pipeline versions` (the table) above the unchanged `## Pipeline version (cycle-133 Sprint 273 pin)`, because DEC-0906's `source` cites that heading. Rejected: merging or renaming them.
- **The default image noted, not fixed.** `run-ablation.sh:412` still defaults `--image` to `loa-ablation:258`. The README tells the operator to pass `--image` explicitly. Changing the default is a code change outside my ownership (see below).
- **blind-session's bridge fallback stated as fact.** `blind-session.sh` runs on `--network bridge` without `LOA_EVAL_EGRESS_NETWORK` and has no refusal. Only `run-ablation.sh` refuses. I wrote it as a fact rather than implying blind sessions are always blocked.
- **The per-run egress record is `meta/egress.jsonl`.** pipeline-run's comment at :958 says `meta/egress.json`, but the code at :974-976 appends to `meta/egress.jsonl`. I documented the code.

## What the lead must do
- Add the CHANGELOG entry for Task 3.4 (docs only; revert = revert the two README hunks).
- The report copy at `<worktree>/grimoires/loa/a2a/sprint-274/reviewer-d.md` is gitignored (`.gitignore:193 grimoires/loa/a2a/*`), so it is not in the patch. Copy it if the record needs it.
- Consider a bead or a follow-up: `run-ablation.sh` default `--image loa-ablation:258` (:412) and the help text at :50 predate image 259. Also pipeline-run.sh:958's comment names `meta/egress.json` where the code writes `meta/egress.jsonl`.
- When Task 3.1 lands, replace the home-scope paragraph (README.md "The `home-scope` mode lands with Task 3.1") with the landed contract, or send me the patch and I will. When Task 3.5 records the measurement pin, fill its row in `## Pipeline versions`.
- Task 3.6 waits for your "smoke green" message.
