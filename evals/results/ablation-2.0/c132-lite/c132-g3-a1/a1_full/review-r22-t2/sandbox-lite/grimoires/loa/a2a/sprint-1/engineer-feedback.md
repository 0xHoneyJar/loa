# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (72 files): the #1267 mount-integrity work (tracked-tree manifest generator, CI gate, fresh-mount proof, `check-loa.sh` not-mounted outcome, `preflight.sh` count), the cycle-130 ablation harness (`pipeline-run.sh` executor, `lib/sandbox-mount.sh`, `ablation-row.sh`, `took-effect.sh`, `validate-suite.sh`, `freeze.sh`, `spend.sh`, `fingerprint.sh`, run-arms spend cap and screen mode), `Dockerfile.ablation`, the `ablation-2.0` suite, the `gpt-6.1-sol` catalog entry, and 11 bats files.

The design is careful (trust-boundary sourcing by literal path, secrets never on argv, per-run HOME, leak guards, arm evidence recorded from artefacts rather than agent claims) and the parts I could exercise work: `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, the `check-loa.sh` mount-scope cases and `spend.sh` pass their suites (31 of 32 runnable tests; the one miss needs the repository's committed manifest, absent from the PR snapshot).

Three things block the merge:

1. The two new test files `ablation-row.bats` and `took-effect.bats` copy a fixture directory (`evals/tests/fixtures/ablation-runs/runs/`) that the PR does not ship. Every test in both files fails in `setup()`, and the PR's own new CI step runs `bats evals/tests/`.
2. The executor and the row builder assume jq 1.7 semantics (a `$label` variable, `{name, label, …}` shorthand, and `split("\u0000") | .[:-1]` on NUL-joined input). On jq 1.6, which the repository itself names as its floor and which Debian 12 / Ubuntu 22.04 ship, every phase aborts at the argv capture and no row can be built. Reproduced: 48 of 52 `pipeline-run.bats` and 17 of 18 `ablation-row.bats` tests fail on jq 1.6; after a local two-symbol rename, 73 of the 91 tests pass and the remaining 10 are the NUL off-by-one.
3. The PR adds a CI gate that regenerates the integrity manifest from the tracked `.claude/` tree and compares it with the committed `.claude/checksums.json`, yet it changes 17 tracked `.claude/` files (catalog, `check-loa.sh`, `preflight.sh`, model maps, `CLAUDE.loa.md`, bridgebuilder dist) without an updated manifest in the diff. The gate fails on this PR, and downstream `check-loa.sh` reports 17 `Tampered` paths — the #1267 symptom class the PR exists to end.

The implementation report is the PR description and carries no `## AC Verification` walkthrough; with the synthetic sprint definition used here that is noted rather than counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Testing — shipped tests cannot run

- **HIGH** (confidence: high) `head/evals/tests/ablation-row.bats:19` — `cp -a "$FX/runs" "$T/runs"` in `setup()` needs `evals/tests/fixtures/ablation-runs/runs/`; the diff ships `MANIFEST.json`, `regen.sh`, `suite.yaml`, `prs/` and `tasks/` but no `runs/`, so all 18 tests fail with `cp: cannot stat … /ablation-runs/runs`.
**File:** `head/evals/tests/ablation-row.bats:19`, `head/evals/tests/took-effect.bats:18`
**Issue:** Both suites consume the fixture run directories that `regen.sh` writes ("rebuilt by regen.sh"; `head/evals/tests/fixtures/ablation-runs/regen.sh:53`), and `regen.sh:86-89` even prunes gitignored files "so the fixtures on disk equal the fixtures a checkout carries" — but the directories were never added. Reproduced from the PR snapshot: both suites fail in `setup()` on the first test.
**Why This Matters:** `head/.github/workflows/bats-tests.yml:212-221` now runs `bats --print-output-on-failure evals/tests/` and exits 1 on any failure; 39 tests fail before any assertion runs, so the harness arrives with its evidence suite red. `took-effect.bats` is also the only mechanical check of the per-trial `took_effect` rules the suite pre-registers (`head/evals/suites/ablation-2.0.yaml:19-20`).
**Required Fix:** Run `evals/tests/fixtures/ablation-runs/regen.sh` (after fixing finding 2) and commit `evals/tests/fixtures/ablation-runs/runs/`; or make `setup()` regenerate when the directory is absent.

### 2. Functionality — the executor and row builder require jq ≥ 1.7

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:702-710` — the per-phase argv capture binds `--arg label` and reads `$label`; jq 1.6 rejects a keyword-named variable (`syntax error, unexpected label, expecting IDENT or __loc__`), the `jq -n … > "$argv_file"` fails under `set -euo pipefail`, `on_exit` records `infrastructure_error: driver aborted (rc 3)` and no phase ever starts.
**File:** `head/evals/harness/pipeline-run.sh:702-710`, `:816-826`, `:881-882`; `head/evals/harness/ablation-row.sh:285`
**Issue:** Four jq programs use jq-1.7-only syntax or semantics:
  - `pipeline-run.sh:702`/`:708`, `:816`/`:826`, `:881`/`:882` — `$label` as a jq variable (`label` is a reserved word; 1.6 refuses it as a variable name).
  - `ablation-row.sh:285` — `{name, label, session_id, …}` key shorthand with the reserved word `label` (1.6: `syntax error, unexpected '}', expecting ':'`), so no row can be built at all.
  - `pipeline-run.sh:704-707` — `printf '%s\0' … | jq -Rs 'split("\u0000") | .[:-1]'`: on jq 1.6 the slurped string has no trailing empty element, so `.[:-1]` drops the LAST real element. The recorded `argv` loses its final token (`--effort medium` → `--effort`; `--resume <sid>` → `--resume`) and the recorded `env` loses its last entry, which is exactly `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` for `gates: false`. `took-effect.sh` reads these captures (`effort_flag_medium`, `implementer_single_session`, `enforce_env_false`), so A4, A6 and A7 trials are judged "did not take effect" and the arm is paused (`ablation-2.0.yaml:88`).
  Reproduced on jq 1.6: `pipeline-run.bats` 4/52 pass, `ablation-row.bats` 1/18, `took-effect.bats` 15/39 (as fixtures cascade). With `$label` renamed and `label: .label` spelled out in a scratch copy: 48/52, 18/18, and the six remaining `took-effect` failures are all the NUL off-by-one above.
**Why This Matters:** The repository's own floor is "jq 1.6+" (`.claude/scripts/lib/dec-write-lib.sh:208`), the pinned sandbox base (`Dockerfile.ablation` on bookworm) installs 1.6, and Ubuntu 22.04 runners ship 1.6. On any such host the whole ablation pipeline is dead with an opaque compile error, or — worse, on the capture bug — silently records false evidence that fails the pre-registered took-effect rules. The smoke run and the current `ubuntu-latest` (jq 1.7.1) hide it.
**Required Fix:** Rename the variable (`--arg lbl "$label"` / `$lbl`) and write `label: .label` in the shorthand object; replace the NUL split with `jq -Rn '[inputs]'` over newline-free elements or `--args`/`$ARGS.positional` (`jq -n --args '$ARGS.positional' "${cargv[@]}"`), which is NUL-safe on both versions. Add a `jq --version` guard or a bats case that pins the capture length (`argv | length == ${#cargv[@]}`) so the next regression is caught.

### 3. Integrity — the committed manifest is not regenerated for the 17 `.claude/` files this PR changes

- **HIGH** (confidence: medium) `head/.github/workflows/bats-tests.yml:170-173` — the new "Integrity manifest gate" runs `tools/gen-checksums.sh --check`, which exits 1 with `DRIFT` when the tracked tree hashes differ from `.claude/checksums.json`; this PR edits `head/.claude/defaults/model-config.yaml:122-147`, `head/.claude/scripts/check-loa.sh:56-91`, `head/.claude/scripts/preflight.sh:197-217`, `head/.claude/scripts/generated-model-maps.sh`, `head/.claude/loa/CLAUDE.loa.md:1` and the bridgebuilder `dist/` files, and the diff carries no `.claude/checksums.json`.
**File:** `head/.github/workflows/bats-tests.yml:170-173`; `head/tools/gen-checksums.sh:152-168`
**Issue:** `tests/unit/check-manifest-paths.bats` MP-6 ("the committed manifest of this repository passes") and the #1267 narrative in `head/tools/gen-checksums.sh:5-10` both establish that `.claude/checksums.json` is a committed artefact consumed by downstream mounts. Only `model-config.yaml.checksum` was refreshed. Confidence is medium because the PR snapshot cannot show the upstream tree's manifest state; the failure mode is deterministic if the manifest is tracked, which the PR's own test asserts.
**Why This Matters:** The PR's own gate goes red on merge, and every fresh downstream mount of the resulting commit prints `Tampered:` for each changed path and exits 1 from `check-loa.sh` — the exact failure class #1267 reports. `tools/fresh-mount-proof.sh` would have shown it (`head/tools/fresh-mount-proof.sh:176-181`); there is no evidence it was run on this tree.
**Required Fix:** Run `bash tools/gen-checksums.sh` on the final tree and commit the manifest in the same change; run `tools/fresh-mount-proof.sh --worktree` and paste its summary line into the report.

---

## Observations

### 1. Integrity checks (mount scope)

- **MEDIUM** (confidence: high) `head/.claude/scripts/preflight.sh:209-211` — `git ls-files -- .claude | … | wc -l` counts index entries, so a tracked System Zone file deleted from the working tree leaves `ACTUAL_COUNT` unchanged and the count comparison passes; the replaced `find` count caught that case. (Dissent DISS-001, triaged medium: `check-loa.sh` still reports the path as `Missing`, and the comment at `:194` calls this a "simple check".)
**Suggestion:** Count with `git ls-files -- .claude` filtered by `[[ -e ]]`, or drop the count and call `check_integrity` outright.
**Benefit:** Preflight keeps detecting deletions, not only additions.

- **MEDIUM** (confidence: medium) `head/.claude/scripts/check-loa.sh:121-122` — in a submodule mount every absent manifest path that exists under `.loa/` is `not-mounted` and informational; since upstream always holds every manifest path, `Missing` can never fire in submodule mode, so a deleted link to a hook or gate script is indistinguishable from a by-design unlinked path. (Dissent DISS-C-001.) The outcome is the #1267 design decision, but it turns the submodule check into a Tampered-only check.
**Suggestion:** Compare against the mount's own link list (what `mount-submodule.sh` linked) rather than against "exists upstream".
**Benefit:** A removed System Zone link fails the check again.

- **MEDIUM** (confidence: high) `head/evals/harness/took-effect.sh:266` — `integrity_clean` only appends "(matches checksums.json)" when the sandbox manifest's digest equals `arm_evidence.manifest_sha256`; a mismatch is not a FAIL. A phase that rewrites a `.claude/` file and regenerates `checksums.json` (hooks and `update.sh` can) verifies clean against its own new manifest.
**Suggestion:** `[[ "$filesha" == "$msha" ]] || { EVID="manifest replaced since materialisation"; return 1; }`.
**Benefit:** The recorded digest becomes the pin it was captured to be.

### 2. Harness behaviour and parity

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:504-509` — `init_sandbox_beads` probes `br` on the HOST and initialises `.beads/` with it when found; in container mode the image has no `br` (`head/evals/harness/Dockerfile.ablation:82-84` says the materialiser "writes the beads opt-out marker"), and `pipeline-run.sh` never sets `LOA_EVAL_BR_BIN`. On an operator host with `br` on PATH every containerised arm sees a beads database it cannot drive; on one without, the opt-out marker — so arm parity depends on the driver's PATH.
**Suggestion:** In container mode pass `LOA_EVAL_BR_BIN=/nonexistent` (or probe the image), and record which path was taken in `arm_evidence`.
**Benefit:** Identical beads state for every arm regardless of host.

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:565-573` — `make_home` copies `~/.codex/auth.json` into `<run>/meta/home/.codex/` (`HOME_DIR="$META/home"`, `:301`). `finish`/`on_exit` delete it, but a SIGKILLed or OOM-killed driver leaves an OAuth credential inside the results tree that batches archive. (CWE-538: insertion of sensitive information into externally accessible file.)
**Suggestion:** Mount the codex files read-only from a tmpfs/`mktemp -d` outside the run directory, or at least `chmod 0600` and sweep stale `meta/home/` on the next driver start.
**Benefit:** No credential material under `evals/results/` after an abnormal exit.

- **MEDIUM** (confidence: high) `head/.github/workflows/bats-tests.yml:20-60` — the workflow's `push`/`pull_request` `paths:` filters list neither `evals/**` nor `tools/gen-checksums.sh` / `tools/check-manifest-paths.sh`, so a PR that only changes the harness, its tests, or those two tools never runs the new "Run eval harness tests" (`:212`) or "Integrity manifest gate" (`:170`) steps.
**Suggestion:** Add `evals/**`, `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh` to both path lists.
**Benefit:** The gates run when the gated code changes.

### 3. Lower-impact items

- **LOW** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19-20` — the `brbuild` stage is never `COPY --from`'d (dead), and `:82-84` says beads_rust 0.2.6 is not on crates.io; under the classic builder (`DOCKER_BUILDKIT=0`) all stages build and `cargo install` fails the image. SIMPLICITY[delete]: remove the stage.
- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:54` — an operator-specific fallback (`$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`) in shared code, and `$HOME` under `set -u`; `pipeline-run.sh:428` swallows any failure (`|| echo ""`), so the run records `fingerprint: null` silently.
- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:586` — `price_for` executes `.claude/adapters/loa_cheval/metering/pricing.py` from the harness repo although `:125-126` states no `.claude/` code is run; the bats trust-boundary scan checks `source` lines only.
- **LOW** (confidence: medium) `head/.claude/defaults/model-config.yaml:42-47` — `gpt-6.1-sol` pricing is an acknowledged placeholder that every `codex-headless` estimate and MODELINV row now resolves to, with no provisional marker on the rows (dissent DISS-C-003). Add a `pricing_note`/bead reference where the rate is consumed, or price the hop as unknown.
- **LOW** (confidence: medium) `head/evals/suites/ablation-2.0.yaml:25` — `source_commit: "<sprint-258-commit>"` placeholder; `head/evals/harness/ablation-row.sh:276` falls back to `$m.source_commit` and would write the literal placeholder into rows when `pipeline.json` lacks the field.
- **LOW** (confidence: medium) `head/evals/harness/freeze.sh:69` — `find "$d" -type f` skips symlinks and empty directories under `tasks/`, so a symlinked fixture file is outside the frozen identity and can change without drift.
- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:857` — exit 137 from the container's `--memory 4g` OOM kill is classed `interrupted` (exit 4) rather than `agent_error`, so a model that blows the memory cap reads as an operator interrupt.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:201-203` — `degraded`, `degraded_reason` and `voices_run` come from `sandbox/grimoires/…/adversarial-*.json`, which the agent under test can write (dissent DISS-C-005); the header's "never from sandbox/" rule is applied to the arm only. Prefer the `eval/` copies taken right after each gate phase.
- **LOW** (speculative, confidence: low) `head/evals/harness/ablation-row.sh:247` — any extra key in `result.modelUsage` marks the run degraded; if the CLI bills any side model (title/summary calls) despite `CLAUDE_CODE_SUBAGENT_MODEL`, every A1 run is excluded from the pairwise analysis.

### Complexity

`run_phase` (`head/evals/harness/pipeline-run.sh:634-868`) is ~235 lines with build-argv, launch, watchdog, record and decide in one body; `apply_arm_toggles` (`head/evals/harness/lib/sandbox-mount.sh:255-373`) ~118 lines. Both exceed the 50-line threshold without a justification comment; splitting `run_phase` into `build_launcher`, `watch_phase`, `record_phase` would also isolate the capture logic that finding 2 touches. Over-engineering pass: the dead `brbuild` stage and the dotfiles fallback are the only removable code. `net: -4 lines possible`.

---

## Cross-Model Observations

Adversarial review ran with two voices (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`), 7 findings, 0 rejected payloads.

| Finding | Triage |
|---------|--------|
| DISS-001 (BLOCKING) preflight count blind to deletions | Confirmed; recorded as MEDIUM above (check-loa.sh still fails the path as Missing; preflight's count is documented as a heuristic) |
| DISS-C-001 submodule `Missing` can never fire | Confirmed; MEDIUM above |
| DISS-C-002 `return 0` hides drift from the exit code | Not a defect: the script's exit code is the `FAILURES` counter (`head/.claude/scripts/check-loa.sh:605-609`); the base's trailing `[[ … ]] && log` returned 1 on drift and, under `set -e`, aborted the script before the remaining checks, so the `return 0` is a fix |
| DISS-C-003 placeholder pricing unmarked | LOW above |
| DISS-C-004 `--validate` rejects the builder's own rows | Not a defect: every executed record carries `name`, `label`, `model_requested`, `models_used` (`pipeline-run.sh:826-830`); skipped records are filtered (`ablation-row.sh:236`); an infrastructure_error before any phase yields `phases: []`. Verified: "every fixture run yields a valid row" passes once finding 2 is patched |
| DISS-C-005 degraded/voices from agent-writable envelopes | LOW above |
| DISS-C-006 Tampered after merge until the manifest is regenerated | Confirmed; HIGH finding 3 |

## Rejected dissent payloads

No payload was rejected: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` is empty (0 bytes).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | Every touched non-generated file read; 6 of 11 bats suites executed from the PR content (unit ×3, spend, pipeline-run, ablation-row, took-effect); `arm-toggles`, `run-arms`, `validate-suite`, `freeze` depend on fixtures outside the snapshot (`claude-stub.sh`, `review-recall.yaml`, the smoke tasks) and were not run |
| Report each defect with file and line | Pass | Above, `head/<path>:<line>` |
| Give a merge verdict | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (an operator-specific path only, `fingerprint.sh:54`)
- [x] Input validation at trust boundaries present (arm ids, sprint labels, task ids, suite schema, leak guards)
- [ ] Credential handling — codex `auth.json` copy can persist under `meta/home/` after SIGKILL (observation 2)
- [x] No injection vectors found (`declare -F "rule_$rule"` gates rule dispatch; no `eval`; env values never on argv)
- [x] Dependencies pinned (image digest, CLI versions, yq sha256)
- [x] Error messages do not leak sensitive data (`AWS_BEARER_TOKEN_BEDROCK` recorded as `<set>`)

---

## Code Quality Summary

**Strengths:**
- Evidence discipline: arm effects are proven from artefacts (`took-effect.sh`), arm ids are kept out of the sandbox, prompts are leak-scanned, and the trust boundary (no `.claude/` code sourced by the harness) is itself under test.
- Secrets travel in the environment only, through a descriptor-closing exec shim, with masked captures.
- `gen-checksums.sh` / `check-manifest-paths.sh` / the `check-loa.sh` not-mounted outcome are small, NUL-safe, and fully covered by passing unit tests.

**Areas for Improvement:**
- Pin the jq version the harness needs, or write for 1.6 (finding 2).
- Ship the fixtures the tests consume, and regenerate the committed manifest with every `.claude/` change (findings 1 and 3).
- `run_phase` should be split; the capture bug lived in a 235-line function.

---

## Next Steps

1. Address the three findings under Changes Required (regenerate `runs/` after the jq fix; regenerate `.claude/checksums.json`).
2. Run `bats evals/tests/ tests/unit/` on a jq 1.6 host and `tools/fresh-mount-proof.sh --worktree`; paste both summaries into the report.
3. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:42:00Z"} -->
