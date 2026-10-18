# Sprint 258 implementer B report (Tasks 1.4, 1.5, 1.6, 1.11)

## What was built
- **1.4** `evals/harness/run-arms.sh`: `--max-usd`, `--run-cap`, `--screen`, `--screen-tasks`. STATUS gains `cut_reason`, `cut`, `spend` and `screen`. MANIFEST gains `screen` and `spend`. The suite aggregate gains `cuts[]` and skips `screen-*`. Tests: `evals/tests/run-arms.bats` RA-6 to RA-10, stub `evals/tests/fixtures/ablation/claude-ablation-stub.sh`.
- **1.5** `evals/harness/spend.sh`. Tests: `evals/tests/spend.bats`, fixtures `evals/tests/fixtures/ablation/spend/`.
- **1.6** New `evals/suites/ablation-2.0.yaml` and new `evals/harness/lib/sandbox-mount.sh`. `evals/harness/execute-agent.sh` now sources the library and has the toggles `loa_mount`, `effort`, `gates` and `flatline`. Tests: `evals/tests/arm-toggles.bats` AT-13 to AT-24. AT-1 to AT-12 and `execute-agent.bats` are unchanged.
- **1.11** New `evals/harness/validate-suite.sh` and `evals/harness/freeze.sh`. New suite files: `grimoires/loa/evals/ablation-2.0/{README.md,MANIFEST.sha256}`, `smoke/smoke-review-01/{task.yaml,TASK.md}` and `smoke/smoke-build-01/{task.yaml,TASK.md,fixture/**,hidden/{manifest.json,reference.patch,tests/test_slug.py}}`. Tests: `evals/tests/{validate-suite,freeze}.bats` and helper `evals/tests/fixtures/ablation/suite-lib.bash`.

## Mount-library contract as implemented
Every function returns 0 on success and 2 when refused or when a step cannot take effect. Evidence is `key=value` lines, appended to `$ARM_EVIDENCE_FILE` when set, else written to fd `${SANDBOX_MOUNT_EVIDENCE_FD:-1}`.
```
mount_prompt_surface <ws> <prompt_tree> <skill|->      # evidence mount=skill:<s>|tree; "-" = whole .claude/ + CLAUDE.md + .loa.config.yaml
resolve_arm_toggles <arm> <suite_file>                 # stdout toggles JSON; reads .arms[] and .ab.arms[]; 2 = undeclared or absent:true
apply_arm_toggles <ws> <toggles_json> <arm>            # applies and verifies; gates also exports LOA_ADVERSARIAL_REVIEW_ENFORCE=false and appends it to $ARM_ENV_FILE
regen_sandbox_manifest <ws>                            # <ws>/.claude/checksums.json; evidence manifest_files, manifest_sha256 (=none without .claude)
check_fixture_path_rule <fixture_dir>                  # 2 when the top level holds .claude CLAUDE.md .loa.config.yaml grimoires .run
write_sandbox_grimoire <ws> <task_yaml> <arm> <sprint_label>   # evidence grimoire=<files>
init_sandbox_beads <ws> <task_title>                   # evidence beads=br|opt-out|none ($LOA_EVAL_BR_BIN overrides br)
```
Evidence keys: `loa_mount`, `effort`, `effort_skills_stripped` (n/m), `effort_catalog`, `gates`, `arm_env`, `flatline`, `sprint_plan`, `context_resets`, `manifest_files`, `manifest_sha256`, plus the four cycle-129 keys. Values for `sprint_plan` and `context_resets` are evidence only.

## How it was tested
| Command | Result |
|---|---|
| bats `evals/tests/*.bats` (all 11 files, one run) | rc 0, 165 ok, 0 not ok |
| run-arms.bats | 10/10 |
| arm-toggles.bats | 24/24 |
| execute-agent.bats | 12/12 |
| spend.bats | 6/6 |
| freeze.bats | 6/6 |
| validate-suite.bats | 10/10 |
| Baseline before changes (execute-agent, arm-toggles, run-arms) | rc 0, 29/29 |
| `bash tools/check-no-raw-sha256sum.sh` | rc 0 |
| shell-compat-lint workflow body | rc 0, 0 errors |
| eval.yml "Validate grader trust boundary" step, run locally on evals/ | rc 0 |
| my files: sed -i, readlink -f, grep -P, -printf, mktemp --suffix, bare timeout, curl, sha256sum, urllib.parse | none found |

Red/green proof for smoke-build-01, run on a temp copy with the hidden test overlaid, `env -i PATH=/usr/bin:/bin HOME=$HOME LC_ALL=C python3 -m pytest -q -p no:cacheprovider tests`:
- base: rc 1, `2 failed, 3 passed`
- after `patch -p1 < hidden/reference.patch`: rc 0, `5 passed`

Suite-root runs:
```
$ evals/harness/validate-suite.sh --smoke --allow-partial
validate-suite: OK — 2 task(s) valid in …/grimoires/loa/evals/ablation-2.0 (partial: type counts not enforced)   rc 0
$ evals/harness/freeze.sh --smoke --allow-partial
freeze: wrote MANIFEST.sha256 (10 files, sha256 e0461665a06c1fda658d2da8ac5090001852aacc4c3e28178631610206ebf6eb)   rc 0
$ evals/harness/freeze.sh --smoke --allow-partial --check     rc 0
```

Acceptance:
- **AC-1.5** is RA-6 (two trials launch, the third is cut, `cut_reason`, exit 1), RA-8 (screen writes no suite STATUS) and SP-1 to SP-3.
- **AC-1.6** is AT-14 to AT-22. AT-20 runs check-loa.sh's own `check_integrity` inside every arm's regenerated sandbox, and a tampered file then reads Tampered.
- **AC-1.10** is AT-13.
- **AC-1.13** is VS-1 to VS-10 and FZ-1 to FZ-6. FZ-2 shows one changed byte gives exit 1.

## DECISION bullets
- DECISION: Harness scripts hash with Python hashlib and do not use compat-lib's `sha256_portable`. eval.yml runs the base harness against a PR's `.claude/`, so sourcing `.claude/scripts/compat-lib.sh` from the harness pulls PR code into the trusted side. That step flagged 4 such lines. `run-arms.sh` already hashes this way, and the raw-sha256sum check stays green. This departs from the brief.
- DECISION: execute-agent.sh and validate-suite.sh source the library as `pushd "$SCRIPT_DIR"; source ./lib/sandbox-mount.sh; popd`. That is a literal in-tree path with no variable on the source line, which is what the trust-boundary scan requires.
- DECISION: `--max-usd` waits for a running trial while only the in-flight reservation blocks a launch. It cuts as soon as `spent + est_next > max`, because spend only grows. `cut.in_flight_reserved` is the reservation at that moment.
- DECISION: `spent` counts this invocation's rows only, not rows from earlier invocations of a reused batch.
- DECISION: For the recall suites `est_next` per arm × task type is the per-arm mean, since each suite has one task type. `cost_hint` is read from `ab.cost_hint`, else `cost_hint`; a map is read at `review-catch`.
- DECISION: `--screen` ignores `--batch` and `--trials`. STATUS carries both `cut_reason` (PRD wording) and `cut` (brief wording).
- DECISION: `spend.sh --since` filters ledger rows only. Run rows count once per `run_id` across files. Missing default files count as zero, and a named file that is missing is exit 1.
- DECISION: Build-only arms (A2, A4, A5, A6) list `applicability_refused`. A8 has no `took_effect`, so no `integrity_clean`. `phases` overrides are lists, used only where an arm differs: A0 `[BARE]`, A2 without PLAN, A4 `[PLAN, IMPLEMENT]`.
- DECISION: An `effort` toggle wins over `EVAL_EFFORT` and over the skill's own effort. Under `loa_mount: false` the skill frontmatter effort is not read, and A0's `effort: high` is left to the pipeline.
- DECISION: The `effort` toggle sets every `default_effort` key in the catalog. A catalog with none is exit 2, and an absent catalog gives evidence `absent`. Only frontmatter `effort:` lines are stripped; body lines stay.
- DECISION: In arm mode execute-agent unsets an inherited `LOA_ADVERSARIAL_REVIEW_ENFORCE` before applying toggles. In arm mode it also regenerates the sandbox manifest, which adds the `manifest_*` evidence keys.
- DECISION: `sprint_plan` and `context_resets` give exit 2 on the single-skill path. In the library they are evidence only.
- DECISION: With `loa_mount: false`, a sandbox that already holds a mount-owned path is exit 2.
- DECISION: The fixture path rule checks the top level only, since the mount owns root paths. The validator also refuses a reference patch or a hidden dest that touches those paths.
- DECISION: `write_sandbox_grimoire` resolves `sprint_plan` from `$LOA_EVAL_SUITE_FILE`, default the ablation suite. The ledger is cycle-001 with sprint-1 at global 1 and next 2. `reviewer.md` falls back to the corpus `PR.md`.
- DECISION: `regen_sandbox_manifest` calls `tools/gen-checksums.sh` only when the sandbox git-tracks `.claude`. Otherwise it hashes inline.
- DECISION: Schema rules:
  - review-catch has `fixture: null` and `test_command: null`;
  - `reference_patch` is required for bug-fix and feature-build;
  - `structural_check` is required for refactor;
  - `source.origin` is allowed;
  - empty `bounds` maps mean the phase defaults;
  - the criterion may name no path, file or `test_*`.
- DECISION: Leak stems come from the hidden manifest `src` files and `structural_check`. Phase prompts are scanned too.
- DECISION: `freeze.sh` takes `--smoke`, uses root-relative paths and exits 1 on validation failure. The committed manifest covers `smoke/`, because `tasks/` does not exist yet.
- DECISION: The original `test_slug.py` passes at base, so the hidden test gains two collapse cases to make it red. TASK.md no longer names that test.

## Known limitations
- Running jobs can overshoot the cut. The overshoot is bounded by the reservation, which is the stated PRD limit.
- RA-9 relies on timing. It uses a 2 s stub sleep, and the reap poll is 1 s.
- AT-20 sources `check-loa.sh` and calls `check_integrity`. A's change must keep that function callable.

## Handoff notes for the lead
- Pass to C: `source "${LOA_EVAL_MOUNT_LIB:-$SCRIPT_DIR/lib/sandbox-mount.sh}"` will fail eval.yml's trust-boundary step, and an env-chosen source path is a real injection vector. Use the pushd form, and gate the test override on a bats marker.
- Pass to C: `skill_effort_stripped` should check frontmatter only. A body line starting with `effort:` would defeat a whole-file `grep -L`.
- Set `source_commit` (`"<sprint-258-commit>"`) in `evals/suites/ablation-2.0.yaml`.
- Any edit under `smoke/` needs `evals/harness/freeze.sh --smoke --allow-partial`, because FZ-6 pins the committed manifest.
- Task 1.10 is still yours: REPO-MAP, CHANGELOG and checksums. I touched none.
