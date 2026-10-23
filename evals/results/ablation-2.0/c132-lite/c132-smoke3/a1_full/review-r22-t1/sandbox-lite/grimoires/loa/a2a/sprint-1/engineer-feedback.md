# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is the Sprint 258 pull request (72 files): the #1267 mount-integrity work (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh`, `check-loa.sh` not-mounted classification, `preflight.sh` count), the spend scripts (`spend.sh`, `run-arms.sh --max-usd/--screen`), the ablation-2.0 suite, the container pipeline executor (`pipeline-run.sh` + `lib/sandbox-mount.sh`), `ablation-row.sh`, `took-effect.sh`, `validate-suite.sh`, `freeze.sh`, `fingerprint.sh`, the `gpt-6.1-sol` catalog entry, and the CI wiring.

I reviewed every file in `pr/head.diff` and, rather than trusting the report, assembled a merged tree (this workspace's `.claude/` plus the PR head, committed to git) and ran the PR's own bats suites and tools there. Results on this host (bash 5, jq 1.6, yq 4.40.5, bats 1.13):

| Suite / tool | Result |
|---|---|
| `tests/unit/gen-checksums.bats`, `check-manifest-paths.bats`, `check-loa-mount-scope.bats` | 20/20 pass (with a temp dir outside the git tree) |
| `evals/tests/spend.bats` | 6/6 pass |
| `tools/fresh-mount-proof.sh` on the merged tree | exit 0: `Tampered=0 Missing=0 not-mounted=423` |
| `lib/sandbox-mount.sh` against the full real `.claude/` tree (whole-tree mount, all seven toggles, manifest regen, `check-loa.sh` integrity inside the sandbox) | all toggles take effect; `Integrity verified`, `FAILURES=0`; `write_sandbox_grimoire` fails (jq, below) |
| `evals/tests/fixtures/ablation-runs/regen.sh` (= `pipeline-run.sh` with the stub CLI), unpatched | every mounted arm exits 2 with a jq compile error (below) |
| `evals/tests/pipeline-run.bats` unpatched | 12/52 pass |
| `pipeline-run.bats` with only the `$label` jq variable renamed | 48/52 pass; the 4 left are the NUL-split truncation (below) |
| `ablation-row.bats` / `took-effect.bats` on regenerated fixtures, same rename | 18/18 pass / 15/21 pass (the 6 are the same truncation) |
| `validate-suite.bats`, `freeze.bats`, `arm-toggles.bats`, `run-arms.bats` | not runnable here: they need `grimoires/loa/evals/ablation-2.0/smoke/*`, `evals/fixtures/review-prs/*` and `evals/tests/fixtures/claude-stub.sh`, none of which are in this change |

The design is careful (secret handling, descriptor hygiene, the leak guards, the exact-two-mounts container launcher and the per-run HOME all passed their tests), and the mount-integrity tooling does what #1267 asks. What blocks the merge is portability and completeness: the executor, the mount library and the row builder use jq 1.7-only syntax while the repository's own libraries declare `jq 1.6+` as the floor; the row builder passes unbounded JSON through argv; the new CI integrity gate and the new unit test cannot pass against a manifest this PR does not regenerate; and two new test files depend on fixture run directories that are not in the change.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability — jq 1.6 rejects the executor, the mount library and the row builder

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:702` — `--arg label "$label"` binds the jq variable `$label`; `label` is a jq keyword, and jq 1.6 fails the program with `syntax error, unexpected label, expecting IDENT or __loc__`. Every mounted phase dies at the argv capture, so every arm except the refused ones ends `infrastructure_error`. Same construct at `head/evals/harness/pipeline-run.sh:816` (the phase record) and `head/evals/harness/pipeline-run.sh:881` (`record_skip`); in the real library at `head/evals/harness/lib/sandbox-mount.sh:462` and `:467` (`write_sandbox_grimoire` → "ledger write failed", so the real-library path fails even earlier than the stubbed tests show); and the `{name, label, …}` shorthand at `head/evals/harness/ablation-row.sh:285`, which jq 1.6 also rejects.
**File:** `head/evals/harness/pipeline-run.sh:702`
**Issue:** The repository's floor is `jq 1.6+` (`.claude/scripts/lib/dec-write-lib.sh:208` says so verbatim) and Debian bookworm, the base of `Dockerfile.ablation`, ships 1.6. Reproduced: `regen.sh` on this host exits 2 for a1, a2, a3, a5, a6, a7 and both a1 runs with the compile error above; `pipeline-run.bats` passes 12/52. Renaming the variable (`--arg lbl`) and writing `"label": .label` in `ablation-row.sh` takes `regen.sh` to exit 0, `ablation-row.bats` to 18/18 and `pipeline-run.bats` to 48/52.
**Why This Matters:** Nothing in the PR declares a jq ≥ 1.7 requirement, there is no version check, and the failure mode is a hard stop before the first phase. The author's machine and `ubuntu-latest` carry jq 1.7, which is why the suites are green there.
**Required Fix:** Rename the jq variable (`--arg lbl "$label"` and `$lbl`) at the three `pipeline-run.sh` sites and in `write_sandbox_grimoire`; use `"label": .label` in `ablation-row.sh`; either add a `jq --version` ≥ 1.7 check with a clear message or keep to 1.6 syntax throughout (recommended, given the documented floor). Add a jq 1.6 run to CI or state the floor change in the docs.

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:704-707` — the argv, env and launcher captures are built with `printf '%s\0' … | jq -Rs 'split("\u0000") | .[:-1]'`. On jq 1.6 the raw slurp yields no trailing empty element, so `.[:-1]` drops the LAST real element: `--effort medium` loses `medium`, `--resume <sid>` loses the session id, and the env capture loses its last variable, which for `gates: false` is `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`.
**File:** `head/evals/harness/pipeline-run.sh:704`
**Issue:** `took-effect.sh` reads exactly these captures. Reproduced on regenerated fixtures: `enforce_env_false FAIL LOA_ADVERSARIAL_REVIEW_ENFORCE not false in phase-IMPLEMENT phase-PLAN` (A4), `effort_flag_medium FAIL --effort medium on 0/4 phases` (A7), `implementer_single_session FAIL continuation argv does not resume …: FIX1 IMPLEMENT` (A6), and `pipeline-run.bats` 9, 16, 17, 18 fail for the same reason. The arm really did take effect; only the record is wrong, so the suite's rule "a took-effect miss is infrastructure_error and pauses the arm" (`head/evals/suites/ablation-2.0.yaml:19-20`) fires falsely on jq 1.6 hosts.
**Why This Matters:** The took-effect proof is the sprint's evidence that an arm ran as declared (FR-3/FR-7). A capture that silently truncates makes that proof fail on correct runs and, worse, could pass on an incorrect run whose last element was the offending one.
**Required Fix:** Build the arrays without relying on a trailing separator, e.g. `jq -Rn '[inputs]'` over newline-free elements, or `rtrimstr("\u0000") | split("\u0000")`, or pass the elements with `--args` and `$ARGS.positional`. Add a test that asserts the last argv element and the last env key are present in the capture.

### 2. Robustness — the row builder passes unbounded JSON through argv

- **HIGH** (confidence: medium) `head/evals/harness/ablation-row.sh:224-228` — the whole MODELINV ledger (`$MINV`, built at `:193-197` from `eval/model-invoke.jsonl`), the full `pipeline.json` (`$PIPE_JSON`, `:179`) and both envelopes are passed to jq as `--argjson` command-line strings. Linux caps one argv string at `MAX_ARG_STRLEN` (128 KiB); a long multi-phase run with Flatline and two-voice gates can exceed that, and jq is never launched.
**File:** `head/evals/harness/ablation-row.sh:226`
**Issue:** Reproduced: `jq -n --argjson x "<150001-byte array>" length` → `Argument list too long`. Under `set -e` the script dies before `ROW` is written, so `runs.jsonl` lacks exactly the long, expensive runs the ablation is measuring. (Raised by the cross-model dissent as DISS-001; confirmed here.)
**Why This Matters:** Silent loss of rows biases the arm comparison toward short runs, and the batch runner has no row to mark the failure with.
**Required Fix:** Write `$MINV`, `$PIPE_JSON`, the envelopes and `$DOT_WRITES` to files under a temp dir and load them with `--slurpfile`/`--rawfile`, or stream the MODELINV JSON on stdin. Add a test with a >128 KiB `model-invoke.jsonl`.

### 3. Completeness — the new CI integrity gate and MP-6 cannot pass against this PR's tree

- **HIGH** (confidence: high) `head/.github/workflows/bats-tests.yml:175-178` — the new step runs `tools/check-manifest-paths.sh` and `tools/gen-checksums.sh --check` against the committed `.claude/checksums.json`, but this PR modifies sixteen tracked files under `.claude/` (`check-loa.sh`, `preflight.sh`, `defaults/model-config.yaml`, `generated-model-maps.sh`, `loa/CLAUDE.loa.md`, the bridgebuilder `dist/` and `resources/` generated files, …) and does not touch the manifest. `gen-checksums.sh --check` therefore reports `changed: .claude/scripts/check-loa.sh` (and the rest) and exits 1 on the PR's own head, and `head/tests/unit/check-manifest-paths.bats:88-92` (MP-6, "the committed manifest of this repository passes") fails as long as the committed manifest still carries the #1267 artefact paths the PR was written to remove.
**File:** `head/.github/workflows/bats-tests.yml:178`
**Issue:** The PR's premise is that the manifest is committed and shipped ("the committed manifest that is compared", `head/tools/gen-checksums.sh:34`; the #1267 symptom only arises because downstream mounts receive it). A gate that compares the committed manifest against the tracked tree must ship with a regenerated manifest in the same change, or it is red at merge time. I could not inspect the upstream manifest itself (this workspace's copy is a mount artefact), hence the caveat: if the manifest was regenerated in a commit outside this diff, this item collapses to "confirm CI is green".
**Why This Matters:** A red gate on the merge commit either blocks the release or gets bypassed, and the first downstream fresh mount after the merge still reads the stale manifest.
**Required Fix:** Run `bash tools/gen-checksums.sh` on the head tree and commit `.claude/checksums.json` in this PR; consider making `semver-bump`/release regenerate it so every `.claude/` change keeps the gate green.

- **HIGH** (confidence: medium) `head/evals/tests/took-effect.bats:18` and `head/evals/tests/ablation-row.bats:19` — both `setup()` functions run `cp -a "$FX/runs" "$T/runs"`, but `evals/tests/fixtures/ablation-runs/runs/` is not in the change (the diff carries `MANIFEST.json`, `regen.sh`, `suite.yaml`, `tasks/`, `prs/` only). `regen.sh` (`head/evals/tests/fixtures/ablation-runs/regen.sh:86-89`) describes the run directories as tracked fixtures that "a checkout carries", and the new CI step at `head/.github/workflows/bats-tests.yml:212-221` runs `bats evals/tests/` unconditionally.
**File:** `head/evals/tests/took-effect.bats:18`
**Issue:** Without the directories every test in both files fails in `setup()` (18 + 21 tests). In this workspace I had to run `regen.sh` to obtain them. If the PR snapshot simply omitted them, this reduces to confirming they are committed; as presented, the change is incomplete.
**Why This Matters:** The eval-harness CI step added by this PR is red on this PR.
**Required Fix:** Commit `evals/tests/fixtures/ablation-runs/runs/` (post-`regen.sh`, with the gitignored copies removed as the script already does), or make the two suites regenerate the fixtures in `setup_file()` when the directory is absent.

---

## Observations

### 1. Integrity semantics

- **MEDIUM** (confidence: high) `head/.claude/scripts/check-loa.sh:75-76` — in a submodule mount the manifest is generated from the upstream tracked tree, so every manifest path exists under `.loa/<path>` by construction; the new `elif` therefore makes `Missing:` unreachable in that mode. Deleting a linked guard script or hook from `.claude/` now prints an informational not-mounted count and `Integrity verified`, where before this change it was a hard failure. (Dissent DISS-C-001, confirmed.)
**Suggestion:** Distinguish "never linked" from "was linked and removed" using the link scope `mount-submodule.sh` creates (its link list), and fail for an absent path inside that scope. Until then, document the accepted blind spot next to the SDD §5.3 comment.
**Benefit:** Keeps tamper-by-deletion detectable on the mount mode the sprint targets.

### 2. Trust boundary

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:383-386` — `regen_sandbox_manifest` executes `${EVAL_PROMPT_TREE}/tools/gen-checksums.sh`, i.e. a script from the PR tree under test, which in turn `source`s that tree's `.claude/scripts/compat-lib.sh`. The header at `:75` promises "Hashing is Python hashlib, never .claude/ code" and the eval.yml trust-boundary rationale is cited throughout. The branch only triggers when the sandbox is a git repo tracking `.claude/`, which `pipeline-run.sh` never produces (it excludes `.claude/` from the sandbox repo), so today this is dead code carrying a trust hole.
**Suggestion:** Drop the tool branch and keep the inline hashlib path (it already produced a manifest `check-loa.sh` accepts for 2033 files here), or run the trusted copy only (`$_SM_REPO_ROOT`), never `$EVAL_PROMPT_TREE`.
**Benefit:** The grader never executes code from the tree it grades.

### 3. Container image

- **MEDIUM** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19-20` — the `brbuild` stage builds `beads_rust` but nothing `COPY --from=brbuild`s it, and the comment at `:82` says the crate is not on crates.io. With BuildKit the unused stage is skipped; with the classic builder (or `DOCKER_BUILDKIT=0`) every stage is built and `cargo install` fails twice, failing the image build.
**Suggestion:** Delete the stage (the comment already records the decision not to ship `br`).
**Benefit:** No dead stage, no builder-dependent failure, shorter builds.

### 4. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:634-868` — `run_phase` is 235 lines with argv assembly, launcher construction, capture, watchdog loop, signal reaping, result parsing, snapshotting, verdict extraction, pricing and the exit decision in one body. SIMPLICITY[shrink]: the capture block (`:701-712`), the record block (`:813-851`) and the account-and-decide block (`:853-867`) are natural extractions, and the capture bug above would have been a one-line fix in a `capture_argv` helper. `net: -0 lines possible` (a split, not a deletion). The same phase-plan jq is duplicated verbatim between `head/evals/harness/pipeline-run.sh:215-229` and `head/evals/harness/took-effect.sh:92-105`; a change to one silently desynchronises the proof from the plan.
**Suggestion:** Extract the three blocks into functions; move the plan jq into a shared `lib/phase-plan.jq` (or a function in a sourced lib) read by both scripts.
**Benefit:** Testable units; one plan definition.

### 5. Low-severity items

- **LOW** (confidence: high) `head/evals/harness/fingerprint.sh:54` — the bats fallback is one operator's home path (`~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`); on any other host it reads `bats=absent`, so identical toolchains fingerprint differently by whose home runs them. (Dissent DISS-C-005.) Drop the path; `LOA_EVAL_BATS_BIN`/`--bats-bin` already exist.
- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:85` — header says the image pins "codex 0.137.0" while `head/evals/harness/Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`; `head/evals/harness/fingerprint.sh:13` carries the same stale note. Align the comments with the Dockerfile.
- **LOW** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:131` — the whole-tree mount uses `cp -a`, which preserves symlinks, while the contract at `:18-19` says "files, never a symlink to the tree". A source tree that is itself a submodule mount (`.claude/x → ../.loa/.claude/x`) yields dangling links in the sandbox. Use `cp -aL` or document the real-files precondition.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:200-206` — `voices_run` and the DEGRADED/voice-shortfall causes are read from `sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json` first, which the agent under test can rewrite; the `eval/` copy is only a fallback and is itself a copy of the same file. (Dissent DISS-C-004.) Prefer `eval/`, and cross-check `voices_run` against the MODELINV rows of the gate phases where you already have them.
- **LOW** (confidence: high) `head/tests/unit/gen-checksums.bats:9` — the header refers to a GC-8 case that reads the live manifest; no GC-8 exists (GC-1…GC-7). Either add the case (mirroring MP-6) or fix the comment.

### 6. Not counted — dependencies I could not verify

`validate-suite.bats`, `freeze.bats` (FZ-6 checks a committed `MANIFEST.sha256`), `arm-toggles.bats` AT-22/AT-24 and `run-arms.bats` rely on `grimoires/loa/evals/ablation-2.0/smoke/{smoke-build-01,smoke-review-01}`, `evals/fixtures/review-prs/pr-01` and `evals/tests/fixtures/claude-stub.sh`, none of which are in this change. If those exist on the base branch this is fine; if not, the same CI step is red for them too. The `.claude/loa/CLAUDE.loa.md` header bumps `version` to `2.0.0-rc.5` without changing `hash`; the body is unchanged, so that is consistent.

---

## Cross-Model Observations

Adversarial review ran with `--diff-file pr/head.diff` (envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`; primary `gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`, 2/2 voices, `verdict_quality.status: APPROVED`, 6 findings). Triage:

- DISS-001 (BLOCKING, `ablation-row.sh --argjson` E2BIG) — confirmed by reproduction; carried into Changes Required §2.
- DISS-C-001 (not-mounted makes Missing unreachable in submodule mode) — confirmed; Observations §1.
- DISS-C-002 (`return 0` in `check_integrity` hides drift from callers) — dismissed: the exit code is driven by the `FAILURES` counter (`head/.claude/scripts/check-loa.sh:36`, `:603-605`), no caller branches on the function's status, and the previous trailing `[[ … ]] && log` under `set -e` aborted the whole script before the summary when drift was found, so the explicit `return 0` is a fix, not a regression. The new unit tests CM-2/CM-3 cover the counter path.
- DISS-C-003 (same as DISS-001) — merged into §2.
- DISS-C-004 (envelopes read from the agent-writable sandbox) — accepted as LOW; Observations §5.
- DISS-C-005 (hard-coded personal bats path) — accepted as LOW; Observations §5.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` has no rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" | Done (this file; also `review.md` at the repository root in the brief's one-line-per-finding shape) | Verdict: CHANGES_REQUIRED |

`reviewer.md` carries no `## AC Verification` section (it is the PR description), which the skill treats as automatic CHANGES_REQUIRED on its own; the findings above are the substantive reason.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the Bedrock token travels by name only; the bats test for it passes)
- [x] Input validation at trust boundaries present (arm ids, sprint labels, task ids, numeric caps all validated); one trust-boundary gap noted in Observations §2
- [x] No shell `eval`; the exec shim closes descriptors above 2 and keeps an allowlist (verified by the passing descriptor/env tests)
- [x] Dependencies pinned in the Dockerfile (yq by SHA-256, CLIs by exact version)
- [x] Error messages do not leak the token (`<set>` in captures)

---

## Code Quality Summary

**Strengths:**
- The container launcher, secret handling and leak guards are precise and tested; every one of those tests passed once the jq issue was out of the way.
- `gen-checksums.sh`/`check-manifest-paths.sh` are small, NUL-safe and exact about what they compare; `fresh-mount-proof.sh` is a genuine end-to-end proof and passed here.
- The stub CLI, docker stub and stub mount library make the executor fully testable without a model or a daemon.

**Areas for Improvement:**
- Portability discipline: the sprint silently raised the jq floor to 1.7 in three scripts and one library.
- Large JSON through argv in `ablation-row.sh`.
- `run_phase` size and the duplicated phase-plan logic.

---

## Next Steps

1. Fix the jq 1.6 incompatibilities (variable name, object shorthand, NUL-split capture) or declare and check a jq ≥ 1.7 floor; add a jq 1.6 CI leg or a documented decision.
2. Move `ablation-row.sh`'s large inputs off argv.
3. Regenerate and commit `.claude/checksums.json`; commit `evals/tests/fixtures/ablation-runs/runs/`.
4. Address the observations at your discretion (the Dockerfile stage and the trust-boundary branch are one-line deletions).
5. Update `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T15:05:00Z"} -->
