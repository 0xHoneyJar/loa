# evals/harness

The scripts here run, grade and row the Loa 2.0 ablation (`run-ablation.sh` and its collaborators) and the older single-skill recall suites (`run-eval.sh`, `run-arms.sh`, `execute-agent.sh`; see `evals/README.md`). This file documents what the landed code does. Each script's header comment is the full contract; where this file and a header disagree, the header wins and this file has a bug.

A batch runs as one driver, `run-ablation.sh`. Its pre-flight refuses with exit 2 before any trial runs. It then dispatches every planned trial to `pipeline-run.sh`, which materialises a sandbox, mounts the pinned framework and runs the phases in a container. After each trial the driver runs `took-effect.sh` (did the arm take effect, is the mount closed), the drift guard, `ablation-grade.sh` and `ablation-row.sh`, and appends the row under a lock. `MANIFEST.json` and `STATUS.json` in the batch directory hold the plan and the progress. The header of `run-ablation.sh` documents every file, field and option.

## Mount modes

The mount decides which framework bytes the session under test can see. `lib/sandbox-mount.sh` implements the modes, and `pipeline-run.sh` chooses one from the arm's toggles in `evals/suites/ablation-2.0.yaml`.

| Mode | Selected by | What the sandbox holds | Evidence in `meta/arm-evidence.txt` |
|---|---|---|---|
| closed | any mounted arm without `oracle_open` (the default) | the pinned source tree's whole `.claude/`, `CLAUDE.md` importing `.claude/loa/CLAUDE.loa.md`, and `.loa.config.yaml`; the PR's own versions only under `pr/head/`, `pr/base/` and `pr/head.diff` | `mount=tree`, `mount_overlay=head:0` or `base:0`, `overlay_excluded=…`, then `mount_closed=pre-launch` |
| open | `oracle_open: true` (evaluation-only) | the same mount with no overlay and no closed-mount check | `mount_overlay=none`, `oracle_open=true` |
| none | `loa_mount: false` | no `.claude/`, no `CLAUDE.md`, no `.loa.config.yaml`; the arm runs one BARE session | `loa_mount=none` |
| skill | `execute-agent.sh` (recall suites) | one skill directory, `CLAUDE.loa.md`, `.claude/rules/` and the import line | `mount=skill:<name>` |
| home-scope | lands with Task 3.1 | see below | see below |

**The closed mount.** `pipeline-run.sh` runs four steps in order. `mount_prompt_surface` copies the tree. `overlay_answer_paths` gives every answer-bearing path of the PR fixture the mode's version, head by default or base when `task.yaml` says so. `regen_sandbox_manifest` rewrites the sandbox's `checksums.json`. `check_mount_closed` then checks clauses (a) to (d) before any phase runs. Since cycle-132 pre-registration addendum 9, every answer path under `.claude/` stays at its pinned version, so the overlay writes nothing and the evidence counts the excluded paths. The copy source must be a clean git tree at the batch's `--source-commit`, else the trial is refused. After the run, `took-effect.sh oracle_closed` repeats the clauses against the finished sandbox, and the grader's oracle scan fires on a read of pinned bytes.

**The open mount.** It is the eval-only control that lets the session see the answer. `pipeline-run.sh` refuses an arm that is `eval_only: true`, or whose toggles set `oracle_open: true`, unless the batch passes `--batch-context`.

**The bare mount.** `loa_mount: false` runs a single BARE session with no framework. A `bare_sessions: matched` arm must also set `loa_mount: false`, and `run-ablation.sh` plans k such sessions per cell (the header's "Matched cells" paragraph).

**The `home-scope` mode (Task 3.1, cycle-133 SDD C-10 as amended by D-3.6).** `mount_mode` (suite `mount_mode.default`, overridden by `arms[].mount_mode`) is **pinned-root** (the default and the cycle-132 behaviour: the framework at the workspace root, `--setting-sources project`; output byte-identical to before) or **home-scope** (mounted review-catch arms only, container executor only, Claude Code 2.1.299 only — the image's `org.loa.claude_code_version` must match or the trial is `infrastructure_error` before any phase). Under home-scope the pinned framework is materialised under the session `HOME` as the user scope, redirected through `LOA_FRAMEWORK_ROOT` by five reversible rules (`lib/sandbox-mount.sh` `mount_home_scope`: hook toplevel prefix, shell root variables, markdown relative paths made absolute, Python root joins and path literals; a residual refuses the mount; `verify` proves reverse(copy) == pinned). The user `CLAUDE.md` imports `CLAUDE.loa.md` and the rules by absolute path; `.loa.config.yaml` stays at the workspace root. The session runs with `--setting-sources user` and `LOA_FRAMEWORK_ROOT` on every phase. The workspace root receives the PR's own version (head) of every changed `.claude/` path except the executable and prompt surface — skills, commands, agents, hooks, settings, rules, `CLAUDE.md` files, `.mcp.json`, output styles, plugins, nested memory files and anything those `@`-import (five hops) — which is removed from the root and stays readable under `pr/head/` only. `took-effect.sh` `oracle_closed` adds clauses (e) (the surface is absent at the root and the root `.claude/` holds only the PR's data), (f) (every changed `.claude/` file the findings cite was read by content from the root or `pr/head/` — Read tool or a single-file Bash read — covering at least 60 % of its lines, fail-closed on any non-PR line; a read of the pinned bytes from `HOME` fails) and (g) (no project hook, MCP server, planted canary or PR `.claude/` script executed: `docker top` samples per phase, hook counts within the pinned settings' declared counts). `meta/mount.json` records the flags and version, `meta/ps-<label>.txt` the process samples and `meta/home-integrity.json` the HOME hash taken before the HOME is deleted. Negative control: `evals/tests/fixtures/home-scope-nc/`; tests `evals/tests/sandbox-mount-home-scope.bats`. The mode was gated on the Task 3.0 spike (`grimoires/loa/a2a/sprint-274/spike-3.0.md`: `--setting-sources user` loads nothing from the project scope in 2.1.299).

## Egress block

**Threat model.** The block denies repository and arbitrary-destination egress from the sandbox. A session under test must not fetch the PR's upstream history, a fix commit, or anything else on the internet. Exfiltration through an allowlisted model API is out of scope. The grader's class-9 tripwire is left to catch that.

**Layout.** `lib/egress-proxy.sh` builds three objects per batch, plus one guard per sandbox container:

- **`loa-egress-<batch>`** is a docker `--internal` network with no route out. Its gateway is the host's own address, and the host still answers there (KF-058). So no sandbox joins this network directly.
- **A guard** is a small container of the proxy image on the internal network, started by `egress-proxy.sh guard <batch> <name>` with `--dns 0.0.0.1`, so nothing but container names resolves. The sandbox runs in the guard's network namespace with `--network container:<guard>`. The guard's netfilter lets that namespace reach loopback and the sidecar's port 8888 only. Either gateway on any port, other containers, the metadata address and IPv6 are rejected inside the namespace, so the sandbox sees "no route to host" and the host is never reached. The sandbox holds no `NET_ADMIN` there and cannot change the rules. After installing them, the guard drops to `nobody` with no capability and sleeps.
- **`loa-egress-<batch>-ext`** is an ordinary bridge network, unless `--external-network` names one.
- **`loa-proxy-<batch>`** is the sidecar built from `Dockerfile.proxy` (tinyproxy 1.11) and attached to both networks. It allows the listed hostnames only and allows CONNECT to port 443 only. Netfilter in its own namespace rejects every private, loopback, link-local, metadata and reserved address after resolution, which covers DNS rebinding and the host gateway.

The allowlist comes from `providers.<p>.egress_hosts[]` in `.claude/defaults/model-config.yaml`, which lists model endpoints and their auth and token-refresh hosts. A `{region}` entry expands to the provider's default region and every `--region` given.

**Per arm.** The suite key `egress: blocked | bridge` sits on the arm, else under `egress.arms.<id>`, else at `egress.default`, else it is `blocked`. A blocked arm's container runs in its own guard with `HTTPS_PROXY` and `HTTP_PROXY` set to `http://loa-proxy-<batch>:8888` and `NO_PROXY` empty. A `bridge` arm runs on `--network bridge` and is recorded as a factor of the batch.

**Refusal.** `run-ablation.sh` refuses a container batch with a blocked arm, exit 2 before any write, unless `LOA_EVAL_EGRESS_NETWORK` names a `loa-egress-<batch>` network that is internal and whose sidecar is running from a proxy image that carries the guard. `up` also refuses a proxy image built before the guard, and both refusals name the rebuild line. The refusal line names the repair. A `--dry-run` and a bats run with `LOA_EGRESS_TEST_MODE=1` record `enforced: false` instead of refusing. `blind-session.sh` has no such refusal: without the variable it runs on `--network bridge`.

**Operating a batch.**

```bash
evals/harness/lib/egress-proxy.sh allowlist > hosts.txt
evals/harness/lib/egress-proxy.sh up <batch> hosts.txt
evals/harness/lib/egress-proxy.sh self-check <batch> --image loa-ablation:259 --log <dir>/self-check.txt
LOA_EVAL_EGRESS_NETWORK=loa-egress-<batch> evals/harness/run-ablation.sh … --batch <batch> --image loa-ablation:259
evals/harness/lib/egress-proxy.sh down <batch> --log-dir <dir>
```

Pass `--image` to the runner explicitly. Its default is still `loa-ablation:258`, which is not the image the pipeline versions below name.

`self-check` runs from a sandbox-shaped container of the image in a guard of its own, as a launcher runs a phase. It opens one CONNECT tunnel per allowlisted host with no credential and no completion token. It then exercises the denials: github.com, raw.githubusercontent.com and gitlab.com by curl and `git ls-remote`, direct IPv4 and IPv6, a non-443 CONNECT, plain HTTP, the metadata address, both gateways, the sidecar's other ports, alternate hostname encodings, external DNS, and a misconfigured or absent proxy. For the gateways it binds a listener on the host at each gateway address on one free high port. Ports 22, 80 and 443 and that port must each be rejected inside the namespace. A connection, a refusal by the host or a timeout is a FAIL, so the result never depends on the host's firewall. It also checks that the listener saw no connection, denial attribution, and the guard's and the sidecar's netfilter rules. Any FAIL line makes it exit 1. `up` refuses a batch whose network or sidecar already exists. The repair is `down <batch>`, which is idempotent.

**Records.** `MANIFEST.json` `egress` holds `{arms, network, proxy, enforced}`. Each run of `pipeline-run.sh` writes:

- **`meta/egress.jsonl`** has one line per phase container: label, mode, network, guard, proxy URL, `enforced` and DNS.
- **`meta/egress-addr.jsonl`** has the address of the container's guard on the batch network at start and end. Each guard has a unique name and its own address, which keeps the attribution per container.
- **`meta/egress-denied.jsonl`** has every sidecar denial whose source is that address during that container's lifetime. The background watcher removes the guard after the end record, and `down` removes any guard left behind.

`blind-session.sh` writes the same records as `egress.json`, `egress-addr.jsonl` and `egress-denied.jsonl` in its output directory. `down --log-dir` saves the sidecar log and every parsed denial of the batch.

`evals/tests/egress-proxy.bats` is the release gate for the block. Its container cases run on a Docker host, and `tests/QUARANTINE.tsv` may never list them.

## Supervisor

`run-ablation.sh --supervised [--max-retries N]` hands the batch to `lib/batch-supervisor.sh launch`. Its job is to bring a batch back after the driver dies, hangs or the host reboots, without a duplicate row or a second owner.

- **Precondition.** The user must linger (`loginctl show-user <user> --property=Linger` reads `yes`), or the process must run in a system-level scope. Otherwise it refuses with exit 2, nothing written, and names `loginctl enable-linger <user>`. `--supervised` is exclusive with `--detach` and `--dry-run`.
- **Daemon.** With `systemd-run` available, the loop runs as `systemd-run --user --unit loa-batch-<name> --collect`. Without it, the loop runs under `setsid`. Either way the loop holds `flock <batch>/supervisor.lock` across daemonisation, so a second owner is refused.
- **Durable identity.** `supervisor/state.json`, mirrored into `STATUS.json` `supervisor`, records the owner pid with its boot id and process start time. A pid reused after a reboot is therefore never mistaken for the owner.
- **Dead or hung.** The runner is dead when it exits. It is hung when no batch file changes for `LOA_SUPERVISOR_HANG_S`, default 1800 seconds, while `STATUS.json` is absent or `running`.
- **Retried classes.** `driver_lost`, `hang`, `infrastructure_error` and `incomplete` are retried. Complete, refusal, failed, budget, outage, `metering_incomplete`, a paused arm and an intentional stop are never retried. Refusal fallbacks belong to the refusal policy, not the supervisor.
- **Before every resume.** The supervisor terminates the runner's process group and every group under `<batch>/.jobs/`, on the same boot only. It removes the `loa-abl-<batch>-*` containers. It then records the uncertain provider requests of interrupted runs from their cost ledgers in the retry entry, and the resumed runner charges such a trial its cap.
- **Cap.** After `--max-retries` retries, default 3, the state is `gave_up`.
- **Reboot.** The launch arguments are copied into `MANIFEST.json` `supervisor`. `lib/batch-supervisor.sh restore <batch-dir>` resumes the batch after a reboot, and the retry cap counts across it.
- **Stop.** `lib/batch-supervisor.sh stop <batch-dir>` is the intentional stop. It terminates the groups, removes the containers and never retries. `status <batch-dir>` prints the record.

`evals/tests/batch-supervisor.bats` covers a killed driver resumed with a retry id, a second owner, the linger precondition, the retry cap, the non-retryable classes, hang detection, cancellation during a request, reboot and same-boot PID reuse, the systemd mode, and a driver killed mid-batch end to end. It is a mandatory gate that the quarantine helper refuses.

## Refusal policy

A Fable 5.1 review or audit session can refuse a PR whose code is security tooling, and Claude Code then continues the session on a fallback model (KF-051). Such a row is not the arm it claims to be. The suite key `refusal_policy` decides, per arm, what that row counts as (cycle-133 SDD C-8, PRD FR-8, bead bd-r9abp).

The key sits on an arm in `evals/suites/ablation-2.0.yaml` and takes one of three values. An arm without it runs `exclude`, which was cycle-132's behaviour.

| Policy | What happens to a refused trial | The row | The denominator |
|---|---|---|---|
| `exclude` | nothing more | invalid: `degraded`, reason `<phase>: refusal fallback` | excluded |
| `keep` | nothing more | valid and flagged: the fallback is not a degraded cause, `refusal_flagged: true` | included |
| `rerun-once` | relaunched once at the same plan index | the second attempt's row is the cell when it has no fallback | included when the second attempt is clean, else excluded |

Under `rerun-once`, the cell is invalid and both attempts stay recorded in three cases:

- **A second refusal.** The relaunch is never relaunched again.
- **An infrastructure failure on the retry.** This covers `transport_error`, `infrastructure_error` and `interrupted`.
- **No room for the relaunch.** The attempt limit of 3 (D-7.3) leaves none, so the row reads `rerun_not_run`.

**Recorded before execution.** `run-ablation.sh` checks every planned arm's value at pre-flight. An unknown value is refused with exit 2, and so is any policy but `exclude` on a `bare_sessions: matched` arm. Such an arm's refused session stays invalid inside its cell. The runner then writes `MANIFEST.json` `refusal_policy {<arm>: policy}` before any trial runs. At run time it reads the policy from the MANIFEST only, so a resumed batch keeps the policy it started with. A MANIFEST written before the key existed reads `exclude`.

**The relaunch.** The refused attempt's run directory is left untouched and never graded. Its record goes to `<batch>/<arm>/<task>-t<n>.refusal-1.json`, which is written once by a hard link and never rewritten. The relaunch runs into a fresh `-r<k>` directory under the same per-run cap. Both attempts are charged. The first attempt's spend goes to the batch's spent and ledger totals and into the row's `all_spend_usd`, and its attempts count in the row's `attempts`. A driver resumed after the first attempt finds the record and launches only the second.

One limit is accepted. The relaunch runs in its trial's slot without a second budget-gate check, so in the worst case a batch passes `--max-usd` by one run cap per refused trial in flight.

**The row fields.** `ablation-row.sh` row writer 1.6 writes these fields on every row:

- `refusal_policy_applied`: the arm's policy.
- `attempt`: 1, or 2 for the relaunch. This differs from `attempts`, which counts transport retries and re-runs.
- `refusal_attempts`: the refused first attempt `{attempt, run_dir, status, cost_usd, refusal_fallbacks}`, with the original and fallback model ids per phase.
- `refusal_outcome`: one of `none`, `excluded`, `kept`, `rerun_not_run`, `rerun_clean`, `rerun_refused`, `rerun_failed` or `sessions_excluded`. The last one marks a matched cell with a refused session.
- `refusal_denominator`: `included` or `excluded`.
- `refusal_flagged`: true on a kept row.

`refusal_denominator` is the refusal policy's verdict alone. Every other exclusion rule of the pre-registration still applies to the row.

**The rate.** `ablation-row.sh --refusal-rate runs.jsonl` prints, per arm, the rows, the refused rows and `refusal_rate = refused / rows`. A refused row is one whose `refusal_outcome` is not `none`, so a clean relaunch still counts as a refusal. Rows from before 1.6 count by their phase records. An arm above 0.2 is flagged with one stderr line.

## Denominators

Three rules decide whether a row counts, and they stack. A row must pass all three.

- **The row status.** `run-ablation.sh` counts a `transport_error`, `infrastructure_error`, `interrupted` or `contaminated` row as excluded in `STATUS.json` `per_arm`, and the batch then ends partial. A run with an unmetered attempt is `infrastructure_error`, so it is already excluded. Its row carries `metering_unmetered: true`, and `spend.sh` counts it.
- **The matched cell.** A `bare_sessions: matched` cell is `completed` when at least one of its k sessions is valid, and the union of the valid sessions is graded. It is degraded when fewer than ⌈k/2⌉ sessions are valid. A matched arm may run only `exclude`, so a session with a refusal fallback is invalid inside its cell.
- **The refusal policy.** `refusal_denominator` is the refusal policy's verdict alone, per the table above.

The pre-registration's exclusion rules apply on top of all three when the reads are computed.

## Pipeline versions

A pipeline version is a commit of this repository together with the images it runs. A later commit that changes nothing under `evals/harness`, `evals/suites`, `evals/graders`, `evals/fixtures` or `evals/analysis` leaves the version as it was. A run names the version it ran at.

| Version | Commit | Images and CLI | Recorded in |
|---|---|---|---|
| intermediate, after Sprint 273 | `50881e6f4` | `loa-ablation:259`, `loa-egress-proxy:259`, Claude Code 2.1.299 | DEC-0906 and the next section |
| measurement pin, after Sprint 274 | the commit that lands § Pipeline version (cycle-133 Sprint 274 pin) below | `loa-ablation:259`, `loa-egress-proxy:259` (rebuilt with the guard label), Claude Code 2.1.299 | the DEC row written right after that commit and the section below |

`evals/analysis/c132/reproduce.sh` reproduces the cycle-132 record at that cycle's own pin by default, and `--pin` names a later version.

## Pipeline version (cycle-133 Sprint 274 pin — the measurement pin)

The measurement pin (sdd.md § 7.3; sprint.md Task 3.5) is **the commit that lands this paragraph** — recorded with its tree
hash in `grimoires/loa/decisions.yaml` (the DEC row written right after it). The first pin of this sprint, `32a8d79cf` (DEC-0942),
ran smoke run 1 and was moved by the s3-a3 fix to the home-scope dissent path (an `evals/harness` change, DEC-0947/0948); the
smoke's verification rerun runs at the new pin and named by the Task 3.5 smoke, by every later
cycle-133 measurement and by `evals/analysis/c132/reproduce.sh --pin` for runs made at it. Later docs-only commits do not
invalidate it; a change under `evals/harness`, `evals/suites`, `evals/graders`, `evals/fixtures` or `evals/analysis` does.

| Component | Value |
|---|---|
| sandbox image | `loa-ablation:259` — `sha256:61e88d02d78519f3ecf20fc3bc162cc1b7a56cd927673ce9d94a7fdb78246dbb` (unchanged since the Sprint 273 pin) |
| proxy image | `loa-egress-proxy:259` — `sha256:95c4c379107c2ae0ce7aea6ca653b9277b4a97c8eb91e2d91af35c1664b86eb0`, rebuilt from `evals/harness/Dockerfile.proxy` with the `loa-egress-guard` entrypoint and label `org.loa.egress.guard=1` (KF-058); `up` and the runner refuse the unlabelled image |
| Claude Code in the image | `2.1.299` (label `org.loa.claude_code_version`; the home-scope surface is derived for this version, `SM_SURFACE_DERIVED_FOR`) |
| grader | 1.5.0 (`ablation-grade.sh`, `--judge-verdicts`) · row writer 1.6 (`ablation-row.sh`) · session library `lib/session-exec.sh` · registration v2 (`registration.py`, `looks_seen`) · the four finding validators (`.claude/schemas/finding.schema.json` v1) · seeding library `lib/corpus-seed.sh` |
| mount modes | `pinned-root` (default) and `home-scope` (`lib/sandbox-mount.sh`, `took-effect.sh` clauses (e)–(g), clause (f) credits Read-tool and single-file Bash reads by content; the HOME copy's project-root climbs resolve to the workspace through `LOA_PROJECT_ROOT`, rules R6–R8, s3-a3) |
| egress block | `lib/egress-proxy.sh` with a guard namespace per blocked sandbox (`guard`, `--network container:<guard>`); allowlist from `.claude/defaults/model-config.yaml` `egress_hosts[]` (10 hosts) |
| self-check | `grimoires/loa/reports/ablation-2.0/self-check-c133-s274.txt` — 62 checks PASS, 0 FAIL at this pin: a CONNECT probe per allowlisted host (no credential, no completion token), every denial case, both gateways on 22/80/443 and a host listener unreachable from the guard, the sidecar's 22/443, metadata |
| egress suite | `evals/tests/egress-proxy.bats` EP-1 … 9, EGR-1 … 13 — 22/22 with real containers on this host (`~/.cache/loa/cycle-133/tests/s3e-lead-gate-094721.log`) and the CI eval job green on the GitHub runner (run 40085119807); never quarantined |
| supervisor | `lib/batch-supervisor.sh` (`run-ablation.sh --supervised`) |

A live batch at this pin: `egress-proxy.sh allowlist > hosts; egress-proxy.sh up <batch> hosts --image loa-egress-proxy:259;
egress-proxy.sh self-check <batch> --image loa-ablation:259; LOA_EVAL_EGRESS_NETWORK=loa-egress-<batch> run-ablation.sh …
--image loa-ablation:259 [--supervised]`; `egress-proxy.sh down <batch> --log-dir <dir>` afterwards. The Task 3.5 smoke
used the lead's driver (`grimoires/loa/reports/ablation-2.0/c133-smoke/README.md`).

## Pipeline version (cycle-133 Sprint 273 pin)

The intermediate pipeline version after Sprint 273 (sdd.md § 7.3; sprint.md Task 2.5) is **the commit that lands this
section** — recorded with its tree hash in `grimoires/loa/decisions.yaml` (DEC-0906) and named by the Sprint 274 smoke
and by `evals/analysis/c132/reproduce.sh --pin` for runs made at it. Later docs-only commits do not invalidate it; a
change under `evals/harness`, `evals/suites`, `evals/graders`, `evals/fixtures` or `evals/analysis` does.

| Component | Value |
|---|---|
| sandbox image | `loa-ablation:259` — `sha256:61e88d02d78519f3ecf20fc3bc162cc1b7a56cd927673ce9d94a7fdb78246dbb` (built from `evals/harness/Dockerfile.ablation` on 2026-10-24) |
| proxy image | `loa-egress-proxy:259` — `sha256:10fc90b6e85ace444896ed01985a1c6c04b57c1cd8f162f99558a60151bba274` (`evals/harness/Dockerfile.proxy`) |
| Claude Code in the image | `2.1.299` (label `org.loa.claude_code_version`, `/etc/loa-claude-code-version`) |
| grader | 1.4.0 (`ablation-grade.sh`) · row writer 1.6 (`ablation-row.sh`) · session library `lib/session-exec.sh` (one copy) |
| egress block | `lib/egress-proxy.sh` + the suite's `egress` key (every arm `blocked`); allowlist from `.claude/defaults/model-config.yaml` `egress_hosts[]` (10 hosts for the default providers and region) |
| self-check | `grimoires/loa/reports/ablation-2.0/self-check-c133.txt` — 49 checks PASS, 0 FAIL: a CONNECT probe per allowlisted host (no credential, no completion token) and every denial case, attribution and the sidecar's netfilter, run on 2026-10-24 against the two images above |
| egress suite | `evals/tests/egress-proxy.bats` EP-1 … 8, EGR-1 … 12 — 20/20 on this host (`~/.cache/loa/cycle-133/tests/s2d2-egress-bats.log`); the release gate for the Sprint 274 smoke |
| supervisor | `lib/batch-supervisor.sh` (`run-ablation.sh --supervised`) |

A live batch at this pin: `egress-proxy.sh allowlist > hosts; egress-proxy.sh up <batch> hosts; egress-proxy.sh
self-check <batch> --image loa-ablation:259; LOA_EVAL_EGRESS_NETWORK=loa-egress-<batch> run-ablation.sh … --image
loa-ablation:259 [--supervised]`; `egress-proxy.sh down <batch> --log-dir <dir>` afterwards.

## Shipping a measurement cycle

A measurement cycle changes code, adds fixtures, records a batch and cuts a release. It ships as four stacked PRs, each based on the one before it and merged in this order (cycle-133 SDD C-12, PRD FR-12).

| Order | PR kind | What it holds | How it is reviewed |
|---|---|---|---|
| 1 | code | harness, graders, analysis, suites, schemas, their tests and docs | the full gates: `/review-sprint`, `/audit-sprint`, Bridgebuilder, CI |
| 2 | fixtures | new corpus fixtures from `seed-corpus-from-record.sh` or `seed-corpus-from-external.sh`, their labels, manifests, `SHA256SUMS`, `THIRD-PARTY.tsv` rows | `seed-corpus-from-record.sh --check`, `seed-corpus-from-external.sh --check`, the labels' approval line, the licence and attribution rows |
| 3 | artefacts | the registration chain (`REGISTRATION-N.json`, with `looks_seen` for every committed look already seen), rows, grades, looks and reads under `grimoires/loa/reports/` | the verifiers: `registration.py verify`, `reproduce.sh`, the reads' input hashes |
| 4 | release | CHANGELOG, version files, release notes | the release path: post-merge orchestrator, rc publish |

The split exists because Bridgebuilder bounds what it reads. It pages a PR's files under `max_files_per_pr` and `max_diff_bytes`, and an omitted reviewable file marks the review degraded with `incomplete_coverage`. A code change mixed with thousands of fixture or grade files is then reviewed in part, or not at all. Fixtures and artefacts are data whose correctness a script proves. Code is what a reviewer must read.

Each later PR names what it rests on. The fixtures PR states the code commit whose seeder built it. The artefacts PR states the measurement pin, which is the merged code commit with its tree hash, and the registration it ran under. A registration is committed before its batch runs. A new registration's `looks_seen` lists every committed look its authors had seen, and `registration.py verify` refuses one that omits a committed look or names one whose rows changed.

**One PR is acceptable** in two cases. The first is a cycle whose diff is code, tests and documentation only, with no fixture corpus and no measurement artefact. Cycle-133 itself is such a cycle. The second is a payload that fits the Bridgebuilder limits with nothing omitted, so the review is not degraded. Any other mix ships stacked. When the payload outgrows the limits mid-cycle, the code goes first and the generated files follow.

## Exit codes

Cycle-133 SDD § 5.4 is the authoritative table for every script the cycle touches: 0 completed as asked, 1 a step failed or a named difference, 2 a refusal before any write, 3 completed but degraded with the reason named. Several harness scripts predate it, and their 3 means something else. The table gives each script's codes as the code implements them. Every citation is the `exit` statement, or the call that reaches it through the script's `finish` or `exit "$rc"`.

| Script | 0 | 1 | 2 | 3 and above |
|---|---|---|---|---|
| `run-ablation.sh` | complete (`:2313`); `--detach` (`:628`); `--dry-run` (`:1357`) | partial: a cut, the outage breaker, a paused arm, an excluded row (`:2298`–`:2311`); signalled (`:2065`) | usage or a pre-flight refusal, `REFUSED.txt` only (`die` `:434`, `refuse` `:636`) | **3 failed**, not degraded: an invalid rows file, drift, no trial completed, every arm paused (`:2294`, `:2296`, `:2302`, `:2305`; `finish` exits at `:2079`) |
| `pipeline-run.sh` | completed, any verdict (`:1244`); `--dry-run` (`:421`) | `agent_error`: a phase failed or timed out (`:1191`, `:1192`) | `infrastructure_error`, including `metering_incomplete` and `unmetered_attempt` (`die_usage` `:224`, `infra` `:521`, `:326`, `:383`) | **3** `cap_failure` (`:1186`, `:1195`) and the broken-cheval launch refusal (`:738`); **4** interrupted (`:1181`, `:1188`); `finish` exits at `:519` |
| `blind-session.sh` | labels written (`:505`) | the session failed, metering incomplete or unmetered (`:507`–`:513`) | usage, a missing CLI or image, no valid price (`die_usage` `:112`, `:202`) | **3 tainted**, taking precedence over 1 (`:506`); exits at `:555` |
| `ablation-grade.sh` | graded, or self-check PASS (`main` `:3564`) | self-check FAIL (`:3508`) | usage, missing inputs, an internal error (`:3567`, `:3570`) | —; `rc` exits through `sys.exit(rc)` at `:3576` |
| `ablation-row.sh` | row written, file valid (`:275`, `:428`) | `--validate` found a bad row (`:424`) | usage, unreadable input, row build failed (`usage` `:220`) | — |
| `took-effect.sh` | every rule OK (`:626`; batch mode's last test `:641`) | any rule FAIL (`:626`, `:641`) | usage, missing files, unknown arm (`usage` `:137`, `:634`) | — |
| `spend.sh` | printed and complete (`:252`) | a file unreadable or the total INCOMPLETE (`:125`, `:128`, `:252`) | usage (`:68`, `:69`) | — |
| `lib/egress-proxy.sh` | done; `down` and `record-address` never fail the caller (`:512` and the normal end) | a start failure after cleanup, a self-check FAIL (`fail` `:76`; self-check `:500`) | usage, an existing network, a missing image, a bad allowlist (`die` `:75`, `:129`) | — |
| `lib/batch-supervisor.sh` | `launch` and `restore` after daemonising; the loop on a complete batch (`:427`) | the loop halted, gave up or was stopped (`:422`, `:428`, `:430`; `finish` exits at `:379`) | no linger, the lock held, no record (`die` `:78`, `refuse` `:79`) | — |
| `evals/analysis/c132/reproduce.sh` | every artefact reproduced (`:128`, `:195`) | a reproduction difference or an engine failure (`rc=1` `:127`, then `:128` or `:195`) | usage, or the environment refused (`:63`, `:115`) | **3** the live sample requested but not run or incomplete (`:138`, `:194`) |
| `tools/check-quarantine-expiry.sh` | every row valid (`:270`) | an invalid or expired row (`:264`) | usage, a bad file or header (`die2` `:69`) | **3** a bead's status could not be verified (`:268`) |

The supervisor classifies its runner by these codes. A runner exit of 0 is complete, 2 is a refusal and 3 is failed, and none of the three is retried.

## Test health

`tests/QUARANTINE.tsv` lists the bats tests skipped on purpose, one tab-separated row per test: `test_id`, `owner`, `expiry`, `bead` and `reason`. The id is `<repo-relative bats path>::<test description>`. A quarantined test's file loads `tests/unit/helpers/quarantine.bash` and calls `loa_quarantine_check` in `setup`, which skips a listed test with the row's reason. The helper fails the test instead of skipping it when an id argument does not match the running test, or when the id names a mandatory gate: egress, the home-scope mount, the sandbox mount, mount provenance, the batch supervisor or the finding-clause rule. `tools/check-quarantine-expiry.sh` is the CI gate. It checks that every test id exists, the owner is set, the bead is open and the id is not listed twice. It also checks that the expiry is 30 or 31 days after the row's quarantine date and never more than 60 days out. The quarantine date is the UTC committer date of the commit that last wrote the row, per git blame. It exits 0 when every row is valid, 1 on an invalid or expired row, 2 on a usage or file error, and 3 when it cannot verify a bead. Exit 3 is what a runner without `.beads/` or `br` gets, so it reads as a warning there.

**Frozen trees are hidden from diffs.** `.gitattributes` marks `evals/fixtures/review-prs/pr-*/**` and `grimoires/loa/reports/ablation-2.0/*-grades/**` as `linguist-generated -diff`. GitHub collapses them in PR views, and local `git diff`, `git log -p` and `git show` print only "Binary files differ" for them. A reviewer reads their content with `--text` or by naming the blob:

```bash
git diff --text <base>..<head> -- evals/fixtures/review-prs/pr-20/
git show <rev>:evals/fixtures/review-prs/pr-20/<path>
```

`--no-ext-diff` does not reveal them. `corpus.tsv`, `labels/`, `manifests/` and `incidents/` at the fixture root are not covered and stay reviewable.
