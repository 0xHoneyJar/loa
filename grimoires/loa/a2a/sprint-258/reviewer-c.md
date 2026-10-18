# Sprint 258 implementer C: Tasks 1.7, 1.8, 1.12 (revision 2)

Worktree `loa-wt-s1c` at 252501b4, nothing committed. Revision 2 applies the lead's three interface facts from B's landed patch.
- Full patch against 252501b4: `~/.cache/loa/cycle-130/patches/s1-c.patch` (stat beside it).
- Delta over revision 1: `s1-c-delta.patch` (stat beside it).

## What was built
- **Task 1.7 + 1.12**:
  - `evals/harness/pipeline-run.sh`: executor, container launcher, watchdog, `meta/` boundary.
  - `evals/harness/lib/phase-prompts/*.md` (six prompts), `fingerprint.sh`, `Dockerfile.ablation`.
  - `evals/tests/pipeline-run.bats` (52 cases).
  - Stubs in `evals/tests/fixtures/`: `claude-stub-pipeline.sh`, `docker-stub.sh`, `mount-lib-stub.sh`.
- **Task 1.8**:
  - `evals/harness/ablation-row.sh` and `took-effect.sh`.
  - `evals/tests/ablation-row.bats` (18) and `took-effect.bats` (21).
  - `evals/tests/fixtures/ablation-runs/`: a copy of B's suite file, two tasks, a PR, MANIFEST.json, and 10 run dirs. `regen.sh` rebuilds them.
- No existing file is changed. `lib/sandbox-mount.sh` is B's.

## Revision 2 changes
- **Library source:** the library is sourced by its literal path, as B's code does. There is no `LOA_EVAL_MOUNT_LIB` seam.
- **No .claude/ code:** nothing sources `.claude/` code. Hashing in fingerprint, took-effect and the stub is Python hashlib. Milliseconds use plain `date` with a fallback.
- **Library interface:** `ARM_ENV_FILE` (meta/arm-env) and `LOA_EVAL_SUITE_FILE` are exported to the library. The phase env takes its `LOA_*` lines.
- **took-effect:** `skill_effort_stripped` reads the frontmatter only. `applicability_refused` is evaluated on non-refused runs. An absent arm prints "component-absent" and passes.

## How it was tested (exit codes)
| Command | rc | Result |
|---|---|---|
| bats pipeline-run + ablation-row + took-effect (revision 2) | 0 | 91/91 |
| bats `evals/tests/*.bats` (revision 2) | 0 | 217/217 |
| eval.yml "Validate grader trust boundary" step, extracted, over my harness plus B's lib | 0 | "Trust boundary check passed" |
| shell-compat-lint body over my shell files | 0 | 0 errors |
| integration: my executor + B's real `lib/sandbox-mount.sh` + B's suite + B's two smoke tasks, `--source-tree` = this worktree (real 1,981-file `.claude/`), stub CLI, host mode | 0 | 11 arm × task runs all as expected (A4 on review-catch refused, exit 2); `took-effect.sh` OK on every run; 12 rows `--validate --allow-ungraded` rc 0; none degraded |
| `docker build -t loa-ablation:258 - < evals/harness/Dockerfile.ablation` | 0 | `sha256:64e11bf87c9c…`; claude 2.1.299, codex 0.137.0, pytest 9.0.2, Bats 1.13.0 |

**Acceptance:** every AC-1.7, AC-1.8, AC-1.12 and AC-1.14 case passes. The bats test names map to the criteria one to one.

## DECISION bullets
- DECISION: The default executor is `container` (DEC-0411); `--executor host` is the fallback. The image is `loa-ablation:258`.
- DECISION: The base commit holds the fixture only. The mount paths go to `.git/info/exclude`. The repo-local git identity is eval@loa.
- DECISION: FIX records are labelled FIX1 and FIX2. A FIX that does not run is `skipped: true`. Snapshots are `<label>.bundle` plus `index.json`.
- DECISION: The first non-zero exit means agent_error. Exit 124, or 137 after the timeout, is `timed_out`. Any other 143, 137, 129 or 130 means interrupted. pipeline.json carries `running` between phases, and the row reads that as interrupted.
- DECISION: The watchdog runs one jq per 1 s poll, deduplicated by message.id. pricing.py runs once per model. Missing cache prices are 0.1× input for reads and 1.25× for writes. An unpriced model disables the watchdog for that phase. The cap test is `≥`.
- DECISION: A0 skips the grimoire, beads, manifest and `.run/`. The fixture path rule applies to build fixtures only. Review-catch copies only the PR files, never fixture.yaml.
- DECISION: Leak guards exit 2 on a hidden path, the arm id anywhere in the sandbox, or "hidden", `D[0-9]{2}-` or an arm id in the brief or a prompt.
- DECISION: Toggles come from `resolve_arm_toggles`; `--dry-run` reads the suite. Effort is `arm.effort`, else `toggles.effort`. Caps are task bounds > `phase_defaults` > built-ins, with BARE = PLAN + IMPLEMENT + 2 × FIX by default. `effort_requested` is the flag, else the skill's frontmatter. `CLAUDE_CODE_USE_BEDROCK` defaults to 1.
- DECISION: The row compares MODELINV effort_effective with the row's own `payload.effort`, and model ids without the region prefix. A manifest arm that disagrees with meta/arm exits 2. `stalls` counts timed-out phases.
- DECISION: took-effect evaluates a refusal record on applicability_refused alone, and accepts a phase-set prefix when a run stopped early. integrity_clean requires `manifest_sha256` plus the hashlib walk. no_flatline_rows also needs `sprint.md`.
- DECISION (rev 2): There is no env seam for the mount library. A bats-gated `source "$LOA_EVAL_MOUNT_LIB"` line still matches the eval.yml regex, which scans every line wherever it sits. pipeline-run.bats and regen.sh instead run a temporary copy of the harness with the stub at `lib/sandbox-mount.sh`. A case proves that `LOA_EVAL_MOUNT_LIB` is ignored.
- DECISION (rev 2): The phase env takes only `^LOA_[A-Z0-9_]+=` lines from `ARM_ENV_FILE`, so an arm can never set PATH, HOME or a key. The driver still adds `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` for `gates: false` when the library wrote nothing.
- DECISION (rev 2): `applicability_refused` on a run that was not refused passes when the task type is inside `task_types` and fails otherwise; B lists it on the build-only arms. An absent arm (A8) prints "component-absent" and exits 0.
- DECISION (rev 2): `skill_effort_stripped` reads only the block between the first two `---` lines.
- DECISION (rev 2): The fixture suite is a copy of B's `evals/suites/ablation-2.0.yaml`, so the tests do not move with the live file.

## Known limitations
- No live CLI call was made; the lead runs the probe. This kernel discards `--memory 4g`.
- docker run adds `--name` (for kill) and `--user <host uid>` (writable sandbox and HOME).
- The host CLI is 2.1.300, while the image has 2.1.299. The image also has jq 1.6, yq 4.40.5, Python 3.11 and Node 20. Host and container fingerprints therefore differ.
- The watchdog can overshoot by one turn.
- A helper model in `modelUsage` marks a run degraded, per the SDD rule.
- Open: pricing.py (`.claude/adapters/`) still runs once per model. `LOA_EVAL_PRICING_JSON` avoids it.

## Handoff notes for the lead
1. If revision 1 is already applied in main, apply `s1-c-delta.patch`; otherwise apply `s1-c.patch` alone.
2. Suite keys read: `arms[].{id,absent,task_types,toggles,phases,effort,took_effect}`, `phase_sets`, `phase_defaults`, `caps.run_usd`, `suite_version`.
3. Smoke: the container mounts the sandbox and the per-run HOME only; the Bedrock token must be in the driver environment.
4. The three new bats files still need adding to the Shell Tests workflow.
5. Rerun `ablation-runs/regen.sh` whenever the pipeline.json shape changes.

## Fix round 1 (trust boundary) and fix round 2 (Bedrock env, per-run HOME): patch s1-c2.patch
- **Round 1:** the eight reported violations are revision-1 lines. Revision 2 had already removed them: no `.claude/` source, the literal library path with the test seam a harness copy, no `eval`, and `(.) as` in jq. The eval.yml step on this tree: "Trust boundary check passed", rc 0. The docs now state that in container mode the image's toolchain is the batch's (CLI 2.1.299; the host has 2.1.300).
- **Round 2 env:** the Bedrock keys `AWS_BEARER_TOKEN_BEDROCK`, `ANTHROPIC_BEDROCK_REGION_PREFIX` and `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` pass through when set, as do the optional `AWS_REGION`, `AWS_DEFAULT_REGION` and `AWS_PROFILE`. A `python3 -I` shim closes fds above 2 and keeps exactly the allowlist keys. Values reach it via the environment, never argv. Docker gets `-e AWS_BEARER_TOKEN_BEDROCK` by name only. The captures record `<set>`.
- **Round 2 HOME:** one per-run `meta/home/` (0700) is mounted rw at /home/evaluser. It holds `.codex/{auth.json,config.toml}` copies and empty `.claude/` and `.aws/`. No `~/.claude` file is copied. It is deleted at exit and on interrupt. There are exactly two mounts.
- **Tests:** bats 91/91 (pipeline-run 52: three container cases replaced by HOME, HOME-on-interrupt and Bedrock-token cases; ablation-row 18; took-effect 21). `evals/tests/*.bats` 217/217, rc 0. One new case checks that the token reaches every phase in host and container mode while its value appears nowhere under the run dir. A mutation with masking off fails that case.
- **Real-docker probe:** shell command instead of claude, fake token. The token arrived, the env was exactly the allowlist, and HOME writes persisted in `meta/home`.
- DECISION: The environment allowlist (amends DEC-0394) passes through, when set, AWS_BEARER_TOKEN_BEDROCK, ANTHROPIC_BEDROCK_REGION_PREFIX and ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL, plus the optional AWS_REGION, AWS_DEFAULT_REGION and AWS_PROFILE. The token is a secret key. It travels by environment only: exported into the launcher subshell, filtered by the shim, and forwarded to docker as `-e NAME`. It is recorded as `<set>`, and no argv, capture or log holds its value.
- DECISION: The container mounts are exactly two (amends DEC-0411): the sandbox rw, and `<run>/meta/home` rw at /home/evaluser. The home holds codex `auth.json`/`config.toml` copies and empty `.claude/` and `.aws/`. `~/.claude/.credentials.json` and `settings.json` are never copied. The directory persists for the run, so A6 `--resume` works, and is deleted at exit and on interrupt. `LOA_EVAL_HOME_TMPFS` and `LOA_EVAL_CREDS_MODE` are removed, not left inert.
- DECISION: The python shim replaces `env -i K=V` both on the host and inside the container. Keeping secrets off argv required this, and the image's python3 3.11 runs it.
