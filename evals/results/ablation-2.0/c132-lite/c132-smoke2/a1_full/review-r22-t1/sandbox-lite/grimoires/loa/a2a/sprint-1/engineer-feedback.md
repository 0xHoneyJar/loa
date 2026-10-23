# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is the frozen pull request in `pr/` (72 files): cycle-130 sprint-258 — mount integrity (#1267), spend caps as scripts, the ablation suite and arms, the container pipeline executor, rows and took-effect evidence, smoke. I read every head-side shell script, the suite file, the Dockerfile, the workflow change and the bats suites, ran the adversarial dissent on `pr/head.diff` (two voices, 2/2 succeeded), and executed the bats suites that could run here against the head tree.

The design is careful in the places that matter for the eval's integrity: credentials travel in the environment only and are masked in every capture (`pipeline-run.sh:620-632, 702-710`), the per-run HOME is deleted on every exit path (`pipeline-run.sh:348, 356`), the sandbox base commit excludes the mount so snapshots carry only the agent's work (`pipeline-run.sh:471-481`), leak guards refuse `hidden`, defect keys and arm ids before any phase runs (`pipeline-run.sh:502-521`), and the integrity tooling (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`) is correct and fully tested (7/7 and 6/7 here, the one miss being my scaffold not being a git repo).

Three findings block the merge:

1. **jq 1.6 portability.** `label` is a jq keyword. jq 1.6 (Debian 12's and Ubuntu 22.04's jq) rejects `$label` as a variable and `{name, label}` as shorthand; jq 1.7 accepts both. The PR uses both forms in the executor, the mount library and the row builder. Reproduced on this host (jq-1.6): every pipeline run ends `infrastructure_error` and `ablation-row.sh` exits 3 with a compile error. CI on `ubuntu-latest` ships jq 1.7.1 and does not see it. Nothing in the repo declares a jq ≥ 1.7 requirement, and the pre-existing scripts never bind `$label` in jq.
2. **preflight.sh's integrity count no longer looks at the disk** (dissent DISS-001, verified): it counts `git ls-files` index entries, which do not change when a tracked System Zone file is deleted from the working tree. The pre-PR `find` count did.
3. **check-loa.sh's `not-mounted` outcome cannot tell a path the mount never linked from a link that was removed** (dissent DISS-C-002, verified): `mount-submodule.sh` writes no link list, so in a submodule mount deleting a linked hook or rule file is now one informational summary line and exit 0 where it was `Missing` (fail) before.

`reviewer.md` is the PR description and carries no `## AC Verification` section, which is itself an automatic CHANGES_REQUIRED under this skill's Phase 4 rule; it is noted here and not counted as a finding.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability — jq keyword `label` breaks the harness on jq 1.6

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:702` — `jq -n --arg label "$label" … '{label: $label, …}'` fails to compile on jq 1.6 (`syntax error, unexpected label, expecting IDENT or __loc__`), so the argv capture of the first phase aborts `run_phase` under `set -e`; `on_exit` writes `status: infrastructure_error` and every run of every arm fails before a single phase starts.
**File:** `head/evals/harness/pipeline-run.sh:702-708`, also `:816-826` (phase record) and `:881-882` (`record_skip`)
**Issue:** `label` is a reserved word in jq. jq 1.6 accepts it as an object key (`{label: …}`) but rejects it as a variable binding (`$label`) and in object shorthand (`{label}`); jq 1.7 relaxed both. Reproduced here (jq-1.6): `jq -nc --arg label x '{l: $label}'` → compile error; `jq -nc --arg lbl x '{label: $lbl}'` → `{"label":"x"}`. Running `evals/tests/fixtures/ablation-runs/regen.sh` on this host produced ten run directories all at `infrastructure_error` with "phases none", and `pipeline-run.bats` failed 36 of 49 cases with exactly this compile error (the 13 passing cases are the dry-run, refusal and usage paths that never reach `run_phase`). The same root cause sits in two more files:
  - `head/evals/harness/lib/sandbox-mount.sh:462-468` — `write_sandbox_grimoire` binds `--arg label "$label"` and reads `$label` inside the ledger program, so on jq 1.6 it returns 2 ("ledger write failed") and `pipeline-run.sh:488` turns that into `infrastructure_error` for every mounted arm. `arm-toggles.bats` AT-24 exercises this function directly and will fail on a jq 1.6 host.
  - `head/evals/harness/ablation-row.sh:285` — `{name, label, session_id, …}` shorthand; jq 1.6: `syntax error, unexpected ',', expecting ':'`; `ablation-row.sh` exits 3 (not one of its documented 0/1/2) for every `--run-dir` call. `ablation-row.bats` failed 17 of 18 cases here; only `usage: missing inputs exit 2` passed.
**Why This Matters:** The ablation harness is run on operator hosts and in the Debian-bookworm-based image lineage this PR pins (`Dockerfile.ablation:22` installs bookworm's jq, which is 1.6). The repository declares no jq minimum, its existing scripts avoid the construct (e.g. `.claude/scripts/golden-path.sh:801` quotes `"label"` and never binds `$label`), and CI on `ubuntu-latest` (jq 1.7.1) cannot catch it, so the suite ships green and fails on first use.
**Required Fix:** Rename the binding (`--arg lbl "$label"` / `$lbl`) at `pipeline-run.sh:702, 816, 881` and `sandbox-mount.sh:462`, and expand the shorthand at `ablation-row.sh:285` to `label: .label` (or quote: `"label": .label`). Either pin jq ≥ 1.7 explicitly (preflight tool check plus a line in the harness headers) or keep the scripts 1.6-clean; given the Debian base, 1.6-clean is the smaller change. Add a bats case that runs one jq program from each script under `jq-1.6` when available, or at least a CI matrix leg on `ubuntu-22.04`.
**Reference:** jq 1.7 changelog, "Allow keywords to be used as binding name and in object construction".

### 2. Integrity — preflight's file-count check no longer detects a deleted System Zone file

- **HIGH** (confidence: high) `head/.claude/scripts/preflight.sh:190` — `ACTUAL_COUNT` is now `git ls-files -- .claude | …| wc -l`, an index count; `rm .claude/hooks/<any-tracked-hook>.sh` leaves it unchanged, so `EXPECTED_COUNT == ACTUAL_COUNT` and neither the warning nor the `strict`-mode `exit 1` at `:199-214` fires. The pre-PR `find … -type f` count (kept only as the fallback at `:195-197`) caught exactly this case.
**File:** `head/.claude/scripts/preflight.sh:188-197`
**Issue:** The manifest is generated from `git ls-files` (`tools/gen-checksums.sh`), so comparing it against `git ls-files` again is a tautology for the one thing a count can detect: a tracked file removed from disk. This is dissent finding DISS-001 (gpt-5.5-pro, BLOCKING); I verified it by reading the code path and by the trivial model (`git ls-files` counts index entries; a working-tree `rm` without `git rm` does not change the index).
**Why This Matters:** preflight runs before skills as the fast System Zone fence; in `integrity_enforcement: strict` it is the only check that exits non-zero before an operation. Removing a hook from `.claude/hooks/` is precisely the tamper class the fence exists for, and this PR makes it invisible to preflight. `check-loa.sh` still reports it as `Missing`, but only when someone runs it.
**Required Fix:** Count tracked paths that exist: pipe the `git ls-files` output through a `[[ -f "${MANIFEST_TREE}/${p}" ]]` filter (or subtract `git -C "${MANIFEST_TREE}" ls-files --deleted -- .claude`). Add a bats case: generate the manifest, delete one tracked file, assert the mismatch warning (and `exit 1` under `strict`).
**Reference:** CWE-354 (Improper Validation of Integrity Check Value); SDD §5.2/§5.3 as cited in the PR's own comments.

### 3. Integrity — `not-mounted` swallows deletions of linked files in a submodule mount

- **HIGH** (confidence: medium) `head/.claude/scripts/check-loa.sh:75` — in a submodule mount (`.loa/.claude` is a directory), any manifest path absent from `.claude/` whose upstream copy exists under `.loa/<path>` is counted as `not-mounted` and never fails. `rm .claude/hooks/implement-gate.sh` in a downstream mount now yields `not-mounted: 1 path(s) exist in the upstream tree but are not linked by this mount` and exit 0; before this PR it was `Missing: …` and exit 1.
**File:** `head/.claude/scripts/check-loa.sh:75-76`, summary at `:83-85`
**Issue:** The classifier has no record of what the mount linked. `mount-submodule.sh` logs `Linked: …` lines (`:908-965`) but persists only `zones` in `.loa-version.json` (`:1108-1115`), so "not linked by design" and "link removed" are indistinguishable; the only tamper signal left in a submodule mount is a hash mismatch on a file that is still present. The summary prints a count, not the paths, so a reviewer cannot even eyeball an unexpected one. Dissent DISS-C-002 (claude-headless) raised the same point; the bats suite (`tests/unit/check-loa-mount-scope.bats`, 6/6 green here) tests only the intended "never linked" case (CM-1), not a removed link.
**Why This Matters:** `check-loa.sh` is the CI/CD integrity gate (`:2`). The #1267 fix was needed, but as written it trades "every submodule mount fails" for "no deletion in a submodule mount is ever detected". That is the SDD §5.3 design as the comment at `:47-55` describes it, and I am challenging the design (grant 1): an integrity check that cannot fail on deletion is not an integrity check for that mount mode.
**Required Fix:** Have `mount-submodule.sh` persist the linked set (e.g. `.loa-version.json` → `"linked": [...]`, or `.claude/.mount-links`), and classify absent paths as `Missing` when they are in that set and `not-mounted` otherwise. Until the mount records it, print the `not-mounted` paths (not just the count) and add a CM-7 case that removes a linked file and asserts a failure. If the design is deliberately accepted as-is, record that as a Decision Log entry in `grimoires/loa/NOTES.md` with the threat it accepts.
**Reference:** CWE-354; OWASP ASVS V14.2 (component integrity).

---

## Observations

### 1. Fast gate / test evidence

- **MEDIUM** (confidence: high) `head/.github/workflows/bats-tests.yml:221` — the report (`reviewer.md`) carries no test run, no `AC Verification`, and the new `bats evals/tests/` step cannot have been exercised on a jq 1.6 host. FAST-GATE: what I could run here (jq-1.6, bats 1.x, yq, python3): `tests/unit/check-loa-mount-scope.bats` 6/6, `evals/tests/spend.bats` 6/6, `tests/unit/gen-checksums.bats` 7/7, `tests/unit/check-manifest-paths.bats` 6/7 (MP-6 needs the real git repo), `evals/tests/pipeline-run.bats` 13/49, `evals/tests/took-effect.bats` 9/21 and `evals/tests/ablation-row.bats` 1/18 — the last three all from Changes Required §1; `freeze.bats` and `validate-suite.bats` need `grimoires/loa/evals/ablation-2.0/smoke/`, which the frozen PR does not carry. Re-run the full set after the jq fix and record the results in `reviewer.md`.
**Suggestion:** Add `ubuntu-22.04` as a second runner, or install jq 1.6 in one CI leg.
**Benefit:** The suite's own CI would have caught §1.

### 2. Change set completeness

- **MEDIUM** (confidence: low) `head/evals/tests/took-effect.bats:18` — `cp -a "$FX/runs" "$T/runs"` (also `ablation-row.bats:19`) needs a committed `evals/tests/fixtures/ablation-runs/runs/` tree, and the regenerator's header (`regen.sh:7-8`, "no nested repositories in the tracked tree") says it is meant to be tracked, yet no `runs/` file is in `pr/head.diff`. Likewise the workflow's new gate `bash tools/gen-checksums.sh --check` (`bats-tests.yml:178`) requires `.claude/checksums.json` to match the tracked tree, this PR changes five tracked `.claude/` files, and the manifest is not in the diff either. In this workspace the manifest does match the head hashes, so the frozen diff may simply omit generated files; if they are genuinely missing, the two bats suites and the manifest gate fail in CI.
**Suggestion:** Confirm both are committed in the real PR.
**Benefit:** Avoids a red CI on merge.

### 3. Container image

- **MEDIUM** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19` — `FROM rust:1-bookworm AS brbuild` + `cargo install beads_rust --version 0.2.6` is a dead stage (nothing `COPY --from=brbuild`), unpinned (no digest, unlike the base at `:22`), and installs a crate the file itself says is not on crates.io (`:82`). Under BuildKit the stage is pruned; under the legacy builder (`DOCKER_BUILDKIT=0`) the failing `cargo install` aborts the whole build. SIMPLICITY[delete].
**Suggestion:** Remove lines 19-20.
**Benefit:** Reproducible build; no dependency on an unavailable crate.

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:85` — header says the image pins "codex 0.137.0"; `Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`.

### 4. Exit-code classification in the executor

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:857` — a phase exiting 137 before its timeout is recorded `interrupted` (exit 4). With `--memory 4g` (`:688`), a container OOM-kill also surfaces as 137, so an OOM'd run is excluded from the analysis as "interrupted" (`ablation-2.0.yaml:83` excludes that status) instead of being counted. Likewise a docker-client failure (exit 125: daemon down, bad flag) reaches `:862` as `agent_error "phase … exited 125"`, charging the model for an infrastructure fault.
**Suggestion:** Inspect `docker inspect --format '{{.State.OOMKilled}}'` (keep the container with `--cidfile`, or read the `stderr-<label>.log` for the docker-client error) and map OOM → `agent_error`/`cap_failure`, 125 → `infrastructure_error`.
**Benefit:** The status taxonomy the pre-registered rules depend on stays honest.

### 5. Watchdog pricing dependency

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:586` — `price_for` executes `$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py`; when it is absent or fails (a trusted-copy deployment of the harness, a PR whose `.claude/` moved the module, a Python import error), `j=null`, `watchdog.priced=false`, and the per-turn cap (D-4.10) is silently off for the whole run with no stderr line. The header (`:125-126`) states no `.claude/` code is run.
**Suggestion:** Log one warning per model when pricing resolves to null and surface `priced:false` in the final `pipeline.json` summary; or ship the price table with the harness (`LOA_EVAL_PRICING_JSON` already exists).
**Benefit:** A cap that is not enforcing says so.

### 6. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:634` — `run_phase` is 235 lines (`:634-868`) with launch, watchdog, reaping, record, snapshot, verdict and accounting in one body; `apply_arm_toggles` is 118 lines (`sandbox-mount.sh:255-373`). SIMPLICITY[shrink]: split `run_phase` into `launch_phase`, `watch_phase`, `record_phase`, `account_phase`. Duplicates: `took-effect.sh:96-105` re-implements `plan_phases` (`pipeline-run.sh:215-227`); `in_container_path` (`pipeline-run.sh:618`) is unused. net: -15 lines possible.

### 7. Smaller items

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:618` — `in_container_path` is defined and never called. SIMPLICITY[delete].
- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:53` — default bats path is one operator's dotfiles location (`~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`); on any other host it reads `bats=absent`, which changes the fingerprint between operators for a reason unrelated to the toolchain.
- **LOW** (confidence: medium) `head/evals/harness/fingerprint.sh:61` — `tool_version` keeps the first line of `2>&1`; an update notice or deprecation warning on stderr becomes the recorded version and flips the digest between runs (dissent DISS-C-006). Prefer stdout, fall back to stderr only when stdout is empty.
- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:201` and `head/evals/harness/took-effect.sh:87` — `sprint-1` is hard-coded in the envelope paths while the executor owns it as `SPRINT` (`pipeline-run.sh:132`); a change there silently breaks both readers. Read it from `pipeline.json` (add `sprint` to the record).
- **LOW** (confidence: high) `head/evals/harness/took-effect.sh:96` — `expected_labels` duplicates `plan_phases`; a change to one and not the other makes `all_phases_present` fail every run or pass a wrong set.
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:477` — for a review-catch task the `reviewer.md` write is inside the `sprint_plan == true` branch, so an arm with `sprint_plan: false` would leave the REVIEW phase without an implementation report. Moot today because `a2_no_sprint_plan` is `task_types: [build]` (`ablation-2.0.yaml:61`), but the coupling is accidental.
- **LOW** (confidence: medium) `head/evals/tests/fixtures/mount-lib-stub.sh:2` — `pipeline-run.bats` and `regen.sh` run the driver only against this stub; no test runs `pipeline-run.sh` with the real `lib/sandbox-mount.sh`, which is how a lib-side failure (§1, `write_sandbox_grimoire`) stays invisible to the driver's suite. One end-to-end case with the real library and the stub CLI would close it.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:285` — `name`, `model_requested`, `models_used` are emitted without defaults while `--validate` (`:130-131`) requires them non-null (dissent DISS-C-003). Today `pipeline-run.sh:826-830` always sets them, so this is defensive only.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:230` — `ms()` accepts `…Z` only; an offset timestamp aborts the whole `jq -n` with exit 5 (dissent DISS-C-004). `pipeline-run.sh` writes `Z` today; wrap the ROW build in `|| usage` so a jq failure maps to the documented exit 2.
- **LOW** (confidence: high) `head/.claude/defaults/model-config.yaml:143` — gpt-6.1-sol pricing is an acknowledged placeholder (`:143-148`); the bead to confirm the rate card is referenced but rows carry no marker that their cost is placeholder-priced (dissent DISS-C-008).

---

## Cross-Model Observations

Adversarial review envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — primary gpt-5.5-pro (answered by codex-headless), companion claude-headless; `verdict_quality.voices_succeeded` 2/2, `rejected_count` 0.

| ID | Voice | Disposition |
|----|-------|-------------|
| DISS-001 (BLOCKING) preflight count from `git ls-files` | gpt-5.5-pro | Verified → Changes Required §2 |
| DISS-C-001 `check_integrity` ends `return 0` | claude-headless | Not a defect: `fail` increments `FAILURES` (`check-loa.sh:36`) and main exits 1 on it (`:603-605`); the `return 0` is needed so `set -e` does not abort on the `&&` chain at `:86` |
| DISS-C-002 `not-mounted` hides removed links | claude-headless | Verified (no link list is persisted) → Changes Required §3 |
| DISS-C-003 row fields without defaults | claude-headless | Observation 7 (defensive; pipeline-run always sets them) |
| DISS-C-004 `ms()` accepts `Z` only | claude-headless | Observation 7 |
| DISS-C-005 `norm_model` and dated ids | claude-headless | Speculative: the suite requests `global.anthropic.*` ids and the prefix case is tested (`ablation-row.bats:152`); not recorded |
| DISS-C-006 fingerprint first stderr line | claude-headless | Observation 7 |
| DISS-C-007 dirty source tree not in fingerprint | claude-headless | Not recorded: `--source-tree` is the pinned tree and `source_commit` is recorded alongside |
| DISS-C-008 placeholder pricing | claude-headless | Observation 7 (acknowledged in the file) |
| DISS-C-009 `.claude` itself a symlink | claude-headless | Speculative: the mount creates `.claude/` as a directory of links (`check-loa-mount-scope.bats:24-29`); not recorded |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` has 0 rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| review the pull request | Pass | every head-side script, suite, workflow and test read; dissent run on `pr/head.diff` |
| report each defect it introduces with the file and line it sits on | Pass | Changes Required §1-3, Observations 1-7, all cited `head/<path>:<line>` |
| give a merge verdict | Pass | CHANGES_REQUIRED |

`reviewer.md` `## AC Verification`: missing (the report is the PR description) — automatic CHANGES_REQUIRED per Phase 4; not counted above.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (`AWS_BEARER_TOKEN_BEDROCK` travels by name only; captures record `<set>`; per-run HOME deleted on every exit path)
- [x] Input validation at trust boundaries (arm ids, sprint labels, task ids, numeric caps, timestamps all regex-checked; leak guards before any phase)
- [ ] Integrity checks — weakened: Changes Required §2 and §3
- [x] No injection paths (no `eval`; prompts via argv; jq programs take `--arg`)
- [x] Dependencies — Dockerfile pins the base by digest and verifies yq's sha256; dead `rust:1-bookworm` stage is unpinned (Observation 3)
- [x] Error messages do not leak secrets

---

## Code Quality Summary

**Strengths:**
- Secret handling in the executor is exemplary: environment-only transport, a Python exec shim that closes descriptors and keeps exactly the allowlist, masked captures, and per-run HOME cleanup on normal exit, error and signal.
- Every refusal is a one-line reason and a non-zero exit; nothing silently runs as its baseline (`sandbox-mount.sh` verifies each toggle after applying it).
- `tools/gen-checksums.sh` and `tools/check-manifest-paths.sh` are small, NUL-safe, and their tests are precise.

**Areas for Improvement:**
- Portability: the harness targets Debian/Ubuntu hosts but was only run on jq 1.7 (§1).
- The two integrity fences lost detection power in exchange for fewer false positives (§2, §3); detection on deletion must come back.
- `run_phase` needs splitting; three readers duplicate the executor's phase plan and sprint label.

---

## Next Steps

1. Fix the jq keyword bindings in `pipeline-run.sh`, `sandbox-mount.sh`, `ablation-row.sh`; re-run `bats evals/tests/ tests/unit/` on a jq 1.6 host and record the output in `reviewer.md` under `## AC Verification`.
2. Restore on-disk detection in `preflight.sh` (filter the tracked list through `-f`) with a bats case for a deleted tracked file.
3. Either persist the mount's linked set and make `check-loa.sh` fail on a removed link, or record the accepted threat as a NOTES Decision Log entry and print the not-mounted paths.
4. Address or explicitly defer the Observations; confirm `evals/tests/fixtures/ablation-runs/runs/` and `.claude/checksums.json` are in the committed change.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:43:00Z"} -->
