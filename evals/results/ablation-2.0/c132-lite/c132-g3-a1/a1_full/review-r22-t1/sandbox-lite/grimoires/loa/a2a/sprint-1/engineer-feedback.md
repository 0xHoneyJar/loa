# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries `pr/PR.md`; no `## AC Verification` section exists — in this evaluation layout the PR description stands in for the report, so that automatic rule is recorded as inapplicable rather than applied)

---

## Overall Assessment

The change under review is `pr/head.diff` (72 files): the #1267 mount-integrity fix (`check-loa.sh`, `preflight.sh`, `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh` + unit tests), the `gpt-6.1-sol` catalog entry, and the cycle-130 ablation harness (`pipeline-run.sh`, `lib/sandbox-mount.sh`, `ablation-row.sh`, `took-effect.sh`, `spend.sh`, `run-arms.sh`, `freeze.sh`, `fingerprint.sh`, `validate-suite.sh`, `Dockerfile.ablation`, suite yaml, fixtures and bats).

The design is sound and much of it is careful: the secret path (`AWS_BEARER_TOKEN_BEDROCK` by name only, `<set>` in captures, fd-closing exec shim, exactly two mounts) held up under hand-tracing and under the 52 pipeline tests when run with jq 1.7.1; `pipeline.json` field names and types match what `ablation-row.sh` reads; the `model-config.yaml.checksum`, bridgebuilder `.build-manifest.json` hashes and `CLAUDE.loa.md` header hash all verify; the adapter pricing tests pass against head.

It cannot merge as is. Two of the PR's own new CI steps go red on this tree (the fixture run directories the row/took-effect tests copy are not in the PR; the integrity-manifest gate is added while the PR changes manifest-covered files without shipping a regenerated `.claude/checksums.json`). The harness uses jq 1.7-only syntax with no version check, and on jq 1.6 (Debian bookworm, Ubuntu 22.04, the ablation image's own jq) every mounted run dies at materialisation — reproduced here. Eleven negated `grep` assertions in `pipeline-run.bats`, including the secret-leak and arm-id leak checks, are bare `! grep` statements mid-test and cannot fail. The cross-model dissent (2/2 voices, consensus) raised one BLOCKING finding on the `preflight.sh` count rule.

Karpathy: `GOAL-DRIVEN:` the leak-guard and secret-leak tests do not fail when they break (H4). `SIMPLICITY[delete]:` dead `brbuild` Docker stage; `SIMPLICITY[shrink]:` the phase-plan jq is duplicated verbatim between `pipeline-run.sh` and `took-effect.sh`; `PRICE_CACHE` is populated only inside a subshell and never read. net: -25 lines possible. Complexity: `run_phase` is ~235 lines (`pipeline-run.sh:634-868`), `apply_arm_toggles` ~120 (`sandbox-mount.sh:255-374`), the row builder is one ~105-line jq program (`ablation-row.sh:224-327`) — all over the 50-line threshold without a justifying comment.

Test runs performed (scratch copies of `pr/head`; `/tmp` is `noexec` here so exec-capable scratch dirs were used): `spend.bats` 6/6; `took-effect.bats` setup fails on the shipped tree (no `runs/`), 21/21 after `regen.sh` under jq 1.7.1; `ablation-row.bats` 0/18 as shipped, 18/18 after regen under jq 1.7.1, 11/18 after regen under jq 1.6 (regen silently produced broken fixtures); `pipeline-run.bats` 12/52 under jq 1.6, 52/52 under jq 1.7.1; `check-loa-mount-scope.bats` 6/6; `check-manifest-paths.bats` 5/7 (MP-6 stale manifest, MP-7 TMPDIR); `gen-checksums.bats` 6/7 (GC-7 TMPDIR); `arm-toggles.bats`, `run-arms.bats`, `freeze.bats`, `validate-suite.bats` need repo fixtures absent from the frozen tree and were reviewed by reading. `bash -n` clean on every shell file; `shellcheck` not installed.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Testing — the new eval-harness CI step fails on this PR

- **HIGH** (confidence: high) `head/evals/tests/ablation-row.bats:19` — `cp -a "$FX/runs" "$T/runs"` in `setup()` copies `evals/tests/fixtures/ablation-runs/runs/`, which is not in the PR (72 files, none under `runs/`); every test in this file and in `head/evals/tests/took-effect.bats:18` errors in setup, so `bats --print-output-on-failure evals/tests/` (`head/.github/workflows/bats-tests.yml:221`) fails.
**File:** `head/evals/tests/ablation-row.bats:19`, `head/evals/tests/took-effect.bats:18`
**Issue:** `regen.sh:2-8` says the run directories are tracked fixtures, but they were never committed; no workflow step runs `regen.sh` first.
**Why This Matters:** 39 tests (18 + 21) that are the only coverage of `ablation-row.sh` and `took-effect.sh` cannot execute, and the CI job the PR adds is red from its first run.
**Required Fix:** Commit `evals/tests/fixtures/ablation-runs/runs/` (after fixing `regen.sh`, see Observations), or build the fixtures in `setup_file` and correct the bats headers that call them checked-in.

### 2. Testing — the new integrity-manifest gate fails on this PR

- **HIGH** (confidence: high) `head/.github/workflows/bats-tests.yml:178` — `bash tools/gen-checksums.sh --check` compares the committed `.claude/checksums.json` with a regeneration over the tracked tree; this PR edits manifest-covered tracked files (`model-config.yaml`, `check-loa.sh`, `preflight.sh`, `generated-model-maps.sh`, `CLAUDE.loa.md`, six bridgebuilder `dist/` and `resources/` files) and `head.diff` carries no `.claude/checksums.json`, so the check exits 1 (`head/tools/gen-checksums.sh:144-168`: absent manifest or drift are both exit 1).
**File:** `head/.github/workflows/bats-tests.yml:177-178`
**Issue:** The gate is introduced without the artefact it checks being regenerated in the same change. Observed on a scratch tree: `DRIFT — 10 path(s)`; `tests/unit/check-manifest-paths.bats` MP-6 fails on the same stale manifest. After one `tools/gen-checksums.sh` run both gates and MP-6 pass, so the tools themselves are self-consistent.
**Why This Matters:** Every PR after this one is blocked until someone regenerates the manifest, and the first red run is this PR's.
**Required Fix:** Run `tools/gen-checksums.sh` and commit `.claude/checksums.json` in this PR; consider making the gate's path filter and the regeneration step explicit (see Observations on `paths:`).

### 3. Portability — jq 1.7-only syntax with no version floor; every mounted run dies on jq 1.6

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:708` — `'{label: $label, name: $name, …'` uses the jq reserved word `label` as a variable; on jq 1.6 this is `syntax error, unexpected label, expecting IDENT`, the argv capture fails under `set -e`, `on_exit` records `infrastructure_error` and the run exits 2 before the CLI starts. Same construct at `:702` (`--arg label`), `:816/:826`, `:881-882`, in `head/evals/harness/lib/sandbox-mount.sh:462,467` (`write_sandbox_grimoire` → `ledger write failed`, zero-byte `ledger.json`), and `head/evals/harness/ablation-row.sh:285` (`{name, label, …}` shorthand, jq ≥ 1.7 only).
**File:** `head/evals/harness/pipeline-run.sh:708`
**Issue:** Reproduced here with the system jq 1.6: 40/52 `pipeline-run.bats` and 7/18 `ablation-row.bats` fail; `regen.sh` writes `infrastructure_error` fixtures and exits 0. The tool check at `pipeline-run.sh:167` only tests `command -v jq`. CI (`ubuntu-latest`, jq 1.7.1) will not notice; Debian bookworm (the `Dockerfile.ablation` base) and Ubuntu 22.04 ship 1.6.
**Why This Matters:** An operator on a 1.6 host loses an entire batch to `infrastructure_error` with a jq compile error as the only clue; the fixtures regenerated on such a host are silently wrong.
**Required Fix:** Rename the binding (`$lbl`) and write `"label": .label` in the shorthand, or enforce `jq --version` ≥ 1.7 in the tool checks of `pipeline-run.sh`, `ablation-row.sh`, `took-effect.sh` and `regen.sh`.

### 4. Testing — negated assertions that cannot fail (GOAL-DRIVEN)

- **HIGH** (confidence: high) `head/evals/tests/pipeline-run.bats:726` — `! grep -rqF "$tok" "$T/log" "$T/dlog"` is a bare negated command inside a `for` loop; bash exempts `!`-prefixed commands from errexit, so bats reports `ok` whether or not the Bedrock token appears in the logs. Same at `:237` (`PATH=/evil`), `:332` (`^effort:` still in SKILL.md), `:339` (`--effort`), `:391-392` and `:394` (the `hidden` / defect-key / arm-id leak scan of prompts and task-brief), `:610` (arm id in sandbox/snapshots/transcripts/eval), `:652`, `:668-669` (`GH_TOKEN|AKIAX|SSH_AUTH_SOCK` in the allowlisted env).
**File:** `head/evals/tests/pipeline-run.bats:726` (and the ten lines above)
**Issue:** Verified with bats 1.13: `! true` mid-test passes; only a `!` on the last line of a `@test` fails. The leak-guard (`pipeline-run.sh:488-520`), secret-handling (`:661-690`) and effort-strip paths therefore have no failing check, although hand-tracing found them correct today.
**Why This Matters:** Security guarantees the harness header advertises (no secret in any capture or log, no arm id or hidden path in the sandbox) are not protected by CI; a regression ships green.
**Required Fix:** Use `run ! grep …` / `[ "$status" -ne 0 ]`, or `! grep … || fail "…"` as `:257` and `:725` already do.

### 5. Integrity check — `git ls-files` counts deleted tracked files (dissent BLOCKING)

- **HIGH** (confidence: high) `head/.claude/scripts/preflight.sh:190` — `ACTUAL_COUNT=$(git -C "${MANIFEST_TREE}" ls-files -- .claude | …)` reads the index, so a tracked `.claude/` file deleted from the working tree (a removed hook, guard script or rule) leaves `ACTUAL_COUNT` unchanged and the count mismatch the previous `find` count detected is suppressed; `check-loa.sh` still reports it as `Missing`, so this is a weakening of preflight's own check rather than a total loss.
**File:** `head/.claude/scripts/preflight.sh:190-191`
**Issue:** Raised as BLOCKING by the cross-model dissent (2/2 voices). The `find` fallback at `:196` only runs when the tracked count is 0.
**Why This Matters:** Preflight's integrity signal is the one that runs before every skill; it now passes a tree with fence files deleted.
**Required Fix:** Filter to paths that exist (`git ls-files -- .claude | while read -r p; do [[ -e "$p" ]] && …`), or subtract `git ls-files --deleted -- .claude`.

---

## Observations

### 1. took-effect evidence

- **MEDIUM** (confidence: high) `head/evals/harness/took-effect.sh:266` — `[[ "$filesha" == "$msha" ]] && EVID="$EVID (matches checksums.json)"` only decorates: a sandbox whose `.claude/` file was altered and whose `checksums.json` was regenerated afterwards passes `integrity_clean` (reproduced: appended to `CLAUDE.loa.md`, regenerated the manifest, `arm a1_full: OK`). The recorded `arm_evidence.manifest_sha256` is computed and never enforced. The walk at `:254` also iterates manifest entries only, so an injected `.claude/hooks/x.sh` passes (the header at `:34-35` says so, but the rule's name promises more).
**Suggestion:** Make a manifest-hash mismatch a FAIL (or a separate `manifest_rewritten` evidence line the row marks degraded) and flag unlisted files under `sandbox/.claude/`.
**Benefit:** `integrity_clean` becomes the arm-confound detector DEC-0418 intends.

- **MEDIUM** (confidence: high) `head/evals/harness/took-effect.sh:173` — `if [[ -f "$R/eval/model-invoke.jsonl" ]]` lets `no_flatline_rows` pass when the MODELINV capture is missing entirely (deleting the file from the a5 fixture → `OK`); sibling rules (`:118`, `:167`) fail on "no evidence captured".
**Suggestion:** Treat an absent ledger as FAIL with evidence `no eval/model-invoke.jsonl`.

- **LOW** (confidence: high) `head/evals/harness/took-effect.sh:133` — `cap_failure|agent_error|interrupted|running)` accepts a phase prefix for `running`, which the header (`:17-19`) does not list; a driver that died before writing a terminal status passes as an early stop.

### 2. Pipeline executor status and robustness

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:862` — `finish agent_error 1 "phase $label exited $rc"` books docker-client failures (125 daemon/name clash, 126/127 `python3`/`claude` absent from the image PATH) and host-shim `execvpe` failures as `agent_error`, which `ablation-row.sh` counts against the arm; container mode has no pre-check that `claude` exists in the image (host mode has one at `:426`). Reproduced with the stub: `STUB_EXIT_PLAN=127` → `status agent_error`. The docker allowlist at `:683` also omits `DOCKER_CERT_PATH`, `DOCKER_TLS_VERIFY`, `DOCKER_CONTEXT`, so a TLS/remote context fails the same way.
**Suggestion:** Map 125/126/127 (and a `result.subtype == "missing"` with zero events) to `infrastructure_error`; probe `docker run … claude --version` once before the first phase.

- **MEDIUM** (confidence: high) `head/evals/harness/pipeline-run.sh:634` — `run_phase()` runs to `:868` (~235 lines, launch + watchdog + parse + record + decide) with nesting past three levels; `apply_arm_toggles` (`head/evals/harness/lib/sandbox-mount.sh:255-374`) and the row builder's single jq program (`head/evals/harness/ablation-row.sh:224-327`) are in the same class. No justifying comment.
**Suggestion:** Split launch/watchdog, record and decide into functions; the recorded fields do not change.

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:595` — `PRICE_CACHE="$PRICE_CACHE$m"…` is appended inside `price_for`, which is only ever called as `prices="$(price_for "$model")"` (`:718`), so the cache lives in a subshell and "one lookup per model" (`:576`) is one `pricing.py` run per phase.

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:85` — header says the image pins "codex 0.137.0"; `head/evals/harness/Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`. `:50` documents `index.json` keys as `IMPLEMENT|FIX1|FIX2` while `:788` lowercases them (`ablation-row.sh` reads the lowercase keys, so only the doc is wrong).

- **LOW** (confidence: high) `head/evals/harness/pipeline-run.sh:138` — `--task-yaml) TASK_YAML="${2:-}"; shift 2 ;;` with a trailing valueless option makes `shift` fail under `set -e`, exit 1 with no message, against the documented usage exit 2. Same in `head/evals/harness/spend.sh:49-56`, `head/evals/harness/took-effect.sh:69-72`, and `head/evals/harness/fingerprint.sh:44-46` (`${2:?}` exits 1).

- **LOW** (confidence: medium) `head/evals/harness/pipeline-run.sh:570` — `cp "$CREDS_HOME/.codex/$f" "$HOME_DIR/.codex/$f"` places `auth.json` under `<run>/meta/home`; it is removed in `finish`/`on_exit`, but a SIGKILLed driver leaves the credential copy in the run directory. `:713` reads `.eval/cost-ledger.jsonl` with `wc -l <`, so an agent `git clean -fdx` (`.eval/` is only `info/exclude`d) aborts the driver as `infrastructure_error`.

### 3. Rows, spend and arms

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-row.sh:226` — `--argjson minv "$MINV" --argjson er … --argjson dot …` passes the whole MODELINV ledger, both envelopes and all tool inputs as single argv strings; Linux `MAX_ARG_STRLEN` is 128 KiB and a MODELINV row measured here is ~2 KB, so a run with ~65 rows (a PLAN with Flatline plus two two-voice gates is in range) fails with `Argument list too long` and no row is written. (Raised by the dissent as advisory.)
**Suggestion:** Feed the inputs via `--slurpfile`/`--rawfile` or stdin.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-row.sh:235` — `companion_planned: e.metadata.companion_voice.planned` (and `:232-234` `e.verdict_quality.…`, `:239/:242` `.payload.effort_effective`, `:262` `$g.contaminated`, `:266-267` `$rc.defects_seeded`, `:305/:307` `$g.verdict_accuracy_per_gate.review`) index into fields that are only checked as objects at the top level; a sandbox-produced envelope with `"metadata": "x"`, a MODELINV row with `"payload": "oops"`, or a `grade.json` with `"recall": 0.5` aborts the builder with jq exit 5, which is not one of the documented 0/1/2. The envelopes and MODELINV rows are written inside the agent sandbox (UNTRUSTED per CLAUDE.md).
**Suggestion:** Guard each with `(x | objects)` / `if type == "object"`, and fail closed with exit 2 and the offending file named.

- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:260` — `($p.status // "infrastructure_error" | if . == "running" then "interrupted" else . end)` passes an unknown pipeline status (`"weird"`) straight into the row, caught only by a later `--validate`, although `--status` is enum-checked at `:164`. Also: `--validate` accepts `schema_version: 2` (`:105`), `status: contaminated` with `contaminated: null` and `degraded: false` with a non-null reason (`:117-123`); `ms()` at `:230` accepts only `Z`-suffixed stamps (pipeline-run always writes them, so robustness only); `:332` leaves a permanent `runs.jsonl.lock`.

- **MEDIUM** (confidence: high) `head/evals/tests/fixtures/ablation-runs/regen.sh:63` — `… || { rc=$?; sed -n "1,20p" "$GEN/last.log" >&2; }` swallows a non-zero `pipeline-run.sh` (only `refused-a4-review` is expected non-zero), prints `wrote 10 run directories` and exits 0; observed under jq 1.6: nine `infrastructure_error` fixtures with empty `phases`, 11/18 row tests still passing on them.
**Suggestion:** `exit "$rc"` for any unexpected non-zero; assert each fixture's `status` before copying.

- **MEDIUM** (confidence: high) `head/evals/harness/run-arms.sh:454` — `ws=""; executor='null'` on a transport-classified failure discards attempt 1's `executor.json` before the retry, and `collect` (`:506`) sums cost only from the final row, so a trial that timed out (exit 124 is transport at `:401`) near `run_cap` drops that spend from `SPENT`; `--max-usd` can be exceeded by one `run_cap` per retried trial against the header's claim (`:18-19`).
**Suggestion:** Add attempt 1's `total_cost_usd` (kept in artifacts at `:452`) to `SPENT` before retrying.

- **MEDIUM** (confidence: high) `head/evals/harness/spend.sh:135` — `if key is not None and key in seen:` keeps the first row per `run_id` even when it carries no `cost_usd`, and dedups inside one file although the header (`:18`) promises cross-file dedup only: `{"run_id":"x1","status":"completed"}` followed by `{"run_id":"x1","cost_usd":9}` yields `runs_usd 0`. A cost-less row is also counted at zero with no stderr note (`:129`, `:152`), and a negative `cost_usd` is accepted.
**Suggestion:** Keep the max (or last) cost per `run_id`; count and report rows without a cost field.

- **LOW** (confidence: high) `head/evals/harness/run-arms.sh:121` — `usd_ok "$MAX_USD" && [[ "$MAX_USD" != "0" ]]` accepts `--max-usd 0.0`, which then creates a batch dir, MANIFEST and a `partial` STATUS with zero trials (exit 1) instead of the usage refusal RA-10 expects for `0`.

- **LOW** (confidence: medium) `head/evals/tests/run-arms.bats:178` — `[ "$(jq -r '.spend.run_cap_usd' "$B/MANIFEST.json")" = "12" ]` (and RA-9's schedule at `:221`) assumes the default `run_cap` is 12, but `run-arms.sh:123` reads `evals.ablation.run_cap_usd` from the live `.loa.config.yaml`; neither test passes `--run-cap 12`.

- **LOW** (confidence: high) `head/evals/harness/freeze.sh:69` — `( cd "$ROOT" && find "$d" -type f -print )` skips symlinks, while `validate-suite.sh` accepts them (`os.path.isfile` follows links); a symlinked task file is never frozen.

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:59` — `no_system_prompt` is listed as A0 evidence, but `pipeline-run.sh` never passes `--append-system-prompt-file` for any arm, so the rule is vacuous for pipeline runs (only `no_dot_claude` discriminates A0).

### 4. Mount integrity (#1267) and CI wiring

- **MEDIUM** (confidence: high) `head/.claude/scripts/check-loa.sh:75` — `elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]` makes the `Missing` branch unreachable on a submodule mount (every manifest path exists under `.loa/` by construction): a deleted or dangling link in `.claude/` is counted `not-mounted` and the exit code stays 0, where before this change it was `Missing` and exit 1. Raised independently by the dissent (advisory). `tests/unit/check-loa-mount-scope.bats` has no deleted-link case.
**Suggestion:** Distinguish "never linked" from "linked then removed" with the mount's own link manifest (`mount-submodule.sh --check-symlinks`), or keep `Missing` for paths whose parent directory is linked.

- **MEDIUM** (confidence: high) `head/.github/workflows/bats-tests.yml:50` — the `pull_request: paths:` filter (`:49-70`) lists `.claude/scripts/**`, `.claude/defaults/**` and two skills but not `.claude/skills/**`, `.claude/commands/**`, `.claude/protocols/**`, `.claude/loa/**`, `.claude/rules/**`, `.claude/checksums.json`, or `tools/gen-checksums.sh` / `tools/check-manifest-paths.sh`; a PR editing only a skill without regenerating the manifest never triggers the new gate, and the next unrelated PR goes red for drift it did not cause.

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:386` — `"$tool" --root "$ws"` runs `tools/gen-checksums.sh` from the prompt tree, which sources `<prompt tree>/.claude/scripts/compat-lib.sh` (`head/tools/gen-checksums.sh:51`); and `:513` `PROJECT_ROOT="$ws" bash "$ubs" --opt-out …` runs the sandbox's own `.claude/scripts/beads/update-beads-state.sh` on the host whenever `br` is absent (CI). Both contradict the header's trust-boundary claim at `:75-77` ("no harness script sources .claude/ code"); the `pipeline-run.bats` trust-boundary test scans `source` lines only.
**Suggestion:** Write the opt-out marker directly from the library, and use the inline hashing path unconditionally for the sandbox manifest.

- **LOW** (confidence: high) `head/tools/check-manifest-paths.sh:80` — `git -C "$ROOT" ls-files -- .claude | sort -u` C-quotes non-ASCII names under default `core.quotePath`, while `head/tools/gen-checksums.sh:102` uses `ls-files -z`; a tracked `.claude/résumé.md` passes `--check` but is reported `[other] untracked` here.

- **LOW** (confidence: high) `head/tests/unit/gen-checksums.bats:89` — the "outside a git repository" cases here and at `head/tests/unit/check-manifest-paths.bats:101` depend on `$T` not being inside any repo; with `TMPDIR` under the checkout both fail (exit 1 instead of 2). Set `GIT_CEILING_DIRECTORIES="$T"`. The header at `:8-9` also references a non-existent GC-8.

- **LOW** (confidence: medium) `head/tools/fresh-mount-proof.sh:129` — `cp -P "$SRC/$p" "$UP/$p"`: BSD `cp -P` only applies with `-R`, so a `--worktree` overlay on macOS turns tracked symlinks into regular files.

### 5. Container image and stubs

- **MEDIUM** (confidence: high) `head/evals/harness/Dockerfile.ablation:91` — `ENV NPM_CONFIG_IGNORE_SCRIPTS=true` never reaches the agent (the exec shim's allowlist at `pipeline-run.sh:661-670` drops it), and `:77` `npm config set ignore-scripts true` runs as root into `/root/.npmrc`, which the `--user <host uid>` process with `HOME=/home/evaluser` never reads; the comment "Disable npm lifecycle scripts for anything the agent installs later" is false.
**Suggestion:** Add `NPM_CONFIG_IGNORE_SCRIPTS` to the pass-through keys or write `ignore-scripts=true` into the per-run HOME's `.npmrc` in `make_home`.

- **LOW** (confidence: high) `head/evals/harness/Dockerfile.ablation:19` — `FROM rust:1-bookworm AS brbuild` / `:20` `cargo install beads_rust … || cargo install …` is never `COPY --from`'d, `:82-84` says br is deliberately absent, and by the file's own statement 0.2.6 is not on crates.io: dead under BuildKit, a build failure under the legacy builder. `SIMPLICITY[delete]`. Also `:2,17,44,79` cite a `Dockerfile.sandbox` that exists nowhere in the tree, and the pin recipe at `:18` (`.manifests[0].digest`) yields a per-platform digest, making the arm64 yq branch at `:51` unreachable.

- **MEDIUM** (confidence: high) `head/evals/tests/fixtures/mount-lib-stub.sh:24` — `echo "mount=whole_tree"` where the real library emits `mount=tree` (`head/evals/harness/lib/sandbox-mount.sh:134`), and `head/evals/tests/pipeline-run.bats:245` asserts the stub's value; the stub also emits `effort_stripped=` (`:59`) vs the lib's `effort_skills_stripped` (`:347`) and refuses an undeclared `baseline` the lib accepts (`:172`). No test runs `pipeline-run.sh` against the real `lib/sandbox-mount.sh`, so `lib_call`'s evidence plumbing, `write_sandbox_grimoire`'s suite-file resolution and `init_sandbox_beads` are untested end to end.
**Suggestion:** One `pipeline-run.bats` case with the real library (host executor, stub CLI), and align the stub's evidence keys with the contract.

- **LOW** (confidence: high) `head/evals/tests/fixtures/docker-stub.sh:63` — `s="${s//$dst/$src}"` substitutes every mount destination anywhere in the string, so when the test tmp dir lives under `/home/evaluser` the second pass rewrites the already-mapped host path (`cd: …/meta/home/…/run/sandbox: No such file`); five container-mode tests fail for runners whose user is `evaluser`.

- **LOW** (confidence: high) `head/evals/tests/fixtures/claude-stub-pipeline.sh:20` — `STUB_MODEL_USED_<PHASE>`, `STUB_REFUSAL_<PHASE>`, `STUB_DOT_CLAUDE_WRITE_<PHASE>` (`:20-22`) are implemented but used by no test, so `refusal_fallbacks`, `models_used` and the `.claude/` write capture in `pipeline-run.sh:765-768,830` and `ablation-row.sh:208-220` are unexercised. `SIMPLICITY[shrink]`: `head/evals/harness/took-effect.sh:92-106` duplicates `pipeline-run.sh:215-228` verbatim; a plan-logic change in one silently breaks the other.

### 6. Catalog and documentation

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:144` — `# PLACEHOLDER: gpt-5.5 list prices copied 2026-10-15 …` marks the `gpt-6.1-sol` rate card provisional in a comment only, while the entry is added to `VALID_FLATLINE_MODELS` (`head/.claude/scripts/generated-model-maps.sh:333`) and the generated registries, so direct `http_api` dispatch produces MODELINV/ledger rows with `pricing_source: config` that `spend.sh` and the caps treat as actual. (Dissent advisory.)
**Suggestion:** A machine-readable `pricing_provisional: true` on the entry, surfaced in the ledger row, or keep the model out of the Flatline allowlist until the rate card is confirmed.

- **MEDIUM** (confidence: low) `head/evals/harness/pipeline-run.sh:1` — 72 files, eight new operator-facing scripts (`pipeline-run.sh`, `ablation-row.sh`, `took-effect.sh`, `spend.sh`, `freeze.sh`, `fingerprint.sh`, `validate-suite.sh`, `tools/*.sh`) and a new CI gate, with no CHANGELOG or docs change in the diff. The repository's CHANGELOG convention is not visible in this frozen layout, so this is recorded at low confidence.

- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:291` — `verdict: (.verdict // null)` copies the string `"none"` that `pipeline-run.sh:874` returns for a gate without a trailer (only `"null"`/`""` are nulled at `:846`), and `--validate` does not check phase verdicts; `took-effect`'s `all_phases_present` treats a `FIX` skipped for `none` the same as for `APPROVED`, which is correct, but the row's `phases[].verdict` enum is now three-valued.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless`; `verdict_quality.voices_planned 2 / voices_succeeded 2`, `consensus`, `chain_health ok`. Six findings, none with `file:line`; each is re-cited above:

1. BLOCKING — `preflight.sh` `git ls-files` counts deleted tracked files → Changes Required #5 (`head/.claude/scripts/preflight.sh:190`).
2. ADVISORY — submodule-mount `not-mounted` hides a deleted link → Observations §4 (`head/.claude/scripts/check-loa.sh:75`).
3. ADVISORY — `check_integrity` unconditional `return 0` — verified: callers use the `FAILURES` counter (`check-loa.sh:36`, `:604-605`), so the exit code is unaffected; the `return 0` fixes a latent `set -e` exit. Not adopted.
4. ADVISORY — `--argjson` argv size → Observations §3 (`head/evals/harness/ablation-row.sh:226`).
5. ADVISORY — `ms()` offset handling → folded into Observations §3 (`:230`); pipeline-run always writes `Z` stamps.
6. ADVISORY — placeholder pricing → Observations §6 (`head/.claude/defaults/model-config.yaml:144`).

## Rejected dissent payloads

- None: `metadata.rejected_summary` is `[]` and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` listed in `rejected_sidecars` has 0 rows.

---

## Previous Feedback Status

No previous `engineer-feedback.md` existed for sprint-1; first review round.

---

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":16,"low":17},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T18:47:30Z"} -->
