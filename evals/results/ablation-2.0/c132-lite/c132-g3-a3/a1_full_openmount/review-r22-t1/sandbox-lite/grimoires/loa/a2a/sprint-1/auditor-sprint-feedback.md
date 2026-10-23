# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED; 0 critical, 6 high, 7 medium, 7 low; `excluded` 0)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change under audit is `pr/head.diff` (72 files): the #1267 mount-integrity tools and the two System Zone gates they touch (`check-loa.sh`, `preflight.sh`), the shared sandbox mount library, the container pipeline executor, the took-effect and row tools, the spend scripts, the suite validator and freeze, the `gpt-6.1-sol` catalog entry, and about 1,600 lines of bats.

Prerequisite note: the skill requires the senior review to read "All good" before an audit runs. The review file reads CHANGES_REQUIRED. The orchestration asked for the audit regardless, so this audit ran against the same snapshot and records that deviation here; nothing below depends on the review's conclusions, which I re-derived from the code and reproduced where they are mechanical.

Security posture. The executor's secret handling is sound where it is deliberate: the Bedrock bearer token travels by environment only, is recorded as `<set>` (`head/evals/harness/pipeline-run.sh:694`, `:705-706`), descriptors above 2 are closed by the shim (`:624-628`), git runs with no global or system config, and every arm toggle verifies itself and refuses rather than running as its baseline. The mount-integrity tools are NUL-safe and byte-stable. Against that, the harness crosses the trust boundary it states about itself in two places by executing code out of a `.claude/` tree it treats as untrusted (`head/evals/harness/lib/sandbox-mount.sh:513`, `head/evals/harness/pipeline-run.sh:586`), with a third, gated crossing in the manifest regeneration path (`head/evals/harness/lib/sandbox-mount.sh:386`). The `preflight.sh` count check loses its ability to see deleted or planted System Zone files. Two undeclared jq ≥ 1.7 dependencies make the executor unusable on jq 1.6 (reproduced on this host) and, once the first is fixed, silently corrupt the argv and environment evidence the took-effect rules depend on. The fixture `runs/` tree the new bats suites copy in `setup()` is absent from the change while CI now runs `evals/tests/` unconditionally.

Cross-model dissent (`grimoires/loa/a2a/sprint-1/adversarial-audit.json`): 2/2 voices (gpt-5.5-pro answered by codex-headless, companion claude-headless), `verdict_quality.status` APPROVED, chain health ok, no rejected payloads. It raised six advisory findings (no critical or high); each is triaged under Cross-Model Security Observations and counted where confirmed. Not DEGRADED_SECURITY_REVIEW.

Test evidence: this host runs jq 1.6 and bash 5.2. Reproductions in this audit: `jq -n --arg label x '$label'` and `jq -n '{"label":1} | {label}'` fail to compile, `{label: 1}` compiles; `printf 'a\0b\0' | jq -Rsc 'split("\u0000") | .[:-1]'` prints `["a"]`; a repository with two tracked files and one deleted reports `git ls-files` 2 and `find` 1. The review's bats runs (20/20 `tests/unit`, 6/6 `spend.bats`, 98 of 117 executor/took-effect/row cases failing as shipped on jq 1.6) were not re-run here; the mechanisms behind them were.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 6 |
| Medium | 8 |
| Low | 12 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Harness executes the sandbox's `.claude/` code on the grader host

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/lib/sandbox-mount.sh:513`
**Issue:** `init_sandbox_beads` runs
```
PROJECT_ROOT="$ws" bash "$ubs" --opt-out "eval sandbox: br not on PATH"
```
with `ubs="$ws/.claude/scripts/beads/update-beads-state.sh"` (`:511`) whenever `br` is not on PATH. That is the ablation default: `head/evals/harness/Dockerfile.ablation:82-84` says "No beads (br) in the image … the sandbox materialiser writes the beads opt-out marker". The sandbox `.claude/` is a copy of the mounted source tree, which in the eval.yml layout is the PR's tree. The library's own header says "Hashing is Python hashlib (_sm_sha256), never .claude/ code" (`head/evals/harness/lib/sandbox-mount.sh:75`) and the executor repeats "No .claude/ code is sourced (eval.yml 'Validate grader trust boundary': the harness is the trusted copy and runs against a PR's .claude/)" (`head/evals/harness/pipeline-run.sh:125-126`). The call runs in the driver process before any container starts, in an environment that holds `AWS_BEARER_TOKEN_BEDROCK` (passed through at `:631`, `:665`). The in-tree trust-boundary test (`head/evals/tests/pipeline-run.bats:251-257`) scans four scripts for `source`/`eval` patterns only and never this library or a `bash <path>` invocation, so the guard passes while the boundary is crossed. AT-24 (`head/evals/tests/arm-toggles.bats:462`) asserts the behaviour, so it is intended; intended is not inside the boundary.
**Impact:** Arbitrary code execution from the artefact under evaluation into the evaluator, with operator credentials in scope.
**Fix:** Write the opt-out marker from the harness itself as data (the marker is a small JSON file under `<ws>/.run/`), or ship it with the fixture. Never execute anything under `<ws>/.claude/`. Extend the trust-boundary test to `lib/sandbox-mount.sh` and to `bash|sh|python3 … .claude/` invocations.
**Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html

### [HIGH-002] Watchdog pricing executes repository Python out of `.claude/adapters`

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/pipeline-run.sh:586`
**Issue:** `price_for` does
```
j="$(cd "$REPO_ROOT/.claude/adapters" && python3 -I "$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py" --alias "$alias" --json 2>/dev/null | sed -n '1p' || true)"
```
whenever `LOA_EVAL_PRICING_JSON` is unset (`:582`), which is the production default; every test and `regen.sh` set the variable, so the line is never exercised in CI. `python3 -I` isolates `sys.path` from the environment, but the script's own directory and the `loa_cheval` package still load from `.claude/adapters`. Confidence is medium because whether `REPO_ROOT/.claude` is the PR's tree depends on how the eval workflow lays out the checkout; the comment at `:125-126` says it is.
**Impact:** Same class as HIGH-001, one directory up, once per model per run in the driver process.
**Fix:** Resolve prices as data (`yq` over `.claude/defaults/model-config.yaml`), or require `LOA_EVAL_PRICING_JSON` and fail closed with `infrastructure_error` when absent.
**Reference:** CWE-829 — https://cwe.mitre.org/data/definitions/829.html

### [HIGH-003] Undeclared jq ≥ 1.7 requirement: `$label` makes every run an infrastructure error on jq 1.6

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/pipeline-run.sh:708` (also `:702/:708`, `:816/:826`, `:881-882`; `head/evals/harness/ablation-row.sh:285`)
**Issue:** The capture program binds `--arg label "$label"` (`:702`) and reads `{label: $label, …}` (`:708`); the phase record (`:816`, `:826`) and `record_skip` (`:881-882`) do the same, and `ablation-row.sh:285` uses the `{name, label, …}` shorthand. jq 1.6 treats `label` as a keyword in both positions. Reproduced on this host:
```
$ jq --version
jq-1.6
$ jq -n --arg label x '$label'
jq: error: syntax error, unexpected label, expecting IDENT or __loc__
$ jq -n '{"label":1} | {label}'
jq: error: syntax error, unexpected '}', expecting ':'
$ jq -n '{label: 1}'
{"label":1}
```
So `plan_phases` (`:224-225`, plain `label:` keys) is unaffected, but the first `run_phase` dies at `:702-710` and the driver records `infrastructure_error`; `ablation-row.sh` cannot compile its row program at all. The tool check at `:167` verifies presence only. jq 1.6 is what `apt-get install jq` yields on Debian bookworm, the base of `head/evals/harness/Dockerfile.ablation:22`.
**Impact:** The executor and the row builder are unusable on the most common stable jq, and the failure is classified as infrastructure, which pauses arms.
**Fix:** Rename the binding (`--arg lbl`) and write `label: .label` / `"label":`; add a jq feature probe beside the tool check, or declare the minimum version in the header and in `fingerprint.sh`.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-004] NUL-split capture drops the last argv and env element on jq 1.6; took-effect rules report false misses

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/pipeline-run.sh:704-707`
**Issue:**
```
--argjson argv "$(printf '%s\0' "${cargv[@]}" | jq -Rs 'split("\u0000") | .[:-1]')"
```
jq 1.6 does not preserve the trailing NUL in raw-slurp mode, so `.[:-1]` discards the last real element. Reproduced: `printf 'a\0b\0' | jq -Rsc 'split("\u0000") | .[:-1]'` prints `["a"]`. The lost element is always the last appended: the value after `--effort` (`:654`), the session id after `--resume` (`:655`), and the last environment entry, which for `gates: false` is `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` (`:676`). The phase runs correctly; only the evidence is wrong. `took-effect.sh` then fails `effort_flag_medium` (`head/evals/harness/took-effect.sh:211-219`), `enforce_env_false` (`:161-170`) and `implementer_single_session` (`:190-196`) on runs that were in fact correct, and DEC-0418 treats a miss as `infrastructure_error` and pauses the arm. The review reproduced exactly ten bats failures with only the HIGH-003 rename applied.
**Impact:** False infrastructure errors stop A4, A6 and A7 on wrong evidence; the recorded argv misdescribes what ran. Masked today only because HIGH-003 aborts first.
**Fix:** Build the arrays with `jq -n '$ARGS.positional' --args "${cargv[@]}"` (identical on 1.6 and 1.7, verified here) and derive the env map from that array; add a bats case asserting the last argv element and the last env key.
**Reference:** CWE-193 Off-by-one Error — https://cwe.mitre.org/data/definitions/193.html

### [HIGH-005] `preflight.sh` count check is blind to deleted and to planted System Zone files

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/preflight.sh:190`
**Issue:**
```
ACTUAL_COUNT=$(git -C "${MANIFEST_TREE}" ls-files -- .claude \
    | awk '!/^\.claude\/overrides\// && $0 != ".claude/checksums.json"' | wc -l | tr -d ' ')
```
`git ls-files` lists index entries whether or not the file exists, so a tracked file deleted from the working tree no longer changes the count (the previous `find` at `head/.claude/scripts/preflight.sh:179` of the base did). Reproduced: two tracked files, one deleted, `ls-files` 2 and `find` 1. The audit dissent (DISS-C-002) adds the converse: an untracked file planted under `.claude/` previously changed the `find` count and now never does, because the legacy count is used only when the git count is exactly zero (`:196-198`). The manifest and the index list the same tracked set, so the two numbers agree whatever the working tree holds.
**Impact:** The fast integrity gate that runs before `check-loa.sh` no longer guards anything the manifest length does not already say, in either direction of drift. Raised as BLOCKING by the review's dissent (DISS-001) and confirmed here.
**Fix:** Count tracked paths that exist (pipe `ls-files` through `[[ -f ]]`, as `head/tools/gen-checksums.sh:96-100` does) and keep a working-tree count for untracked additions, or replace the count with `tools/check-manifest-paths.sh` semantics.
**Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [HIGH-006] Fixture run directories missing while CI runs `evals/tests/` unconditionally

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/tests/took-effect.bats:18` (and `head/evals/tests/ablation-row.bats:19`, `head/.github/workflows/bats-tests.yml:221`)
**Issue:** Both `setup()` functions run `cp -a "$FX/runs" "$T/runs"`. `fixtures/ablation-runs/runs/` is not among the 72 files; the fixture directory in the change holds `MANIFEST.json`, `prs/`, `regen.sh`, `suite.yaml`, `tasks/`. `MANIFEST.json` is written by `regen.sh` (`head/evals/tests/fixtures/ablation-runs/regen.sh:96-104`), so regeneration ran on the author's machine and `runs/` exists there unshipped. The workflow now runs `bats --print-output-on-failure evals/tests/` (`:221`) and nothing in CI runs `regen.sh`. All 45 cases in the two files fail in `setup()`. Confidence medium because the snapshot is "every touched file"; if `runs/` exists outside this change, the finding downgrades to "the shipped fixtures were produced by an executor that fails on jq 1.6" per HIGH-003.
**Impact:** A red required check on the merge commit.
**Fix:** Commit the regenerated `runs/` tree after HIGH-003 and HIGH-004 are fixed, or make the two suites run `regen.sh` into a temp dir when `runs/` is absent.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

---

## Medium/Low Priority Issues

### [MED-001] Unused `brbuild` stage installs a crate the file says does not exist
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/Dockerfile.ablation:19-20`
- **Issue:** `FROM rust:1-bookworm AS brbuild` runs `cargo install beads_rust --version 0.2.6` and is never referenced by `COPY --from`; `:82-84` states "beads_rust 0.2.6 is not on crates.io". With the classic builder the stage is built and the image fails; with BuildKit it is dead weight documenting a path the file says cannot work.
- **Fix:** Delete the stage.
- **Reference:** CWE-1164 Irrelevant Code — https://cwe.mitre.org/data/definitions/1164.html

### [MED-002] npm lifecycle-script hardening is not in effect at run time
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/Dockerfile.ablation:77`
- **Issue:** `RUN npm config set ignore-scripts true` runs as root and writes `/root/.npmrc`; phases run as the host uid with `HOME=/home/evaluser` (`head/evals/harness/pipeline-run.sh:659`). The fallback `ENV NPM_CONFIG_IGNORE_SCRIPTS=true` (`:91`) is stripped by the in-container shim, which keeps exactly the allowlisted keys (`head/evals/harness/pipeline-run.sh:661-679`), and `NPM_CONFIG_IGNORE_SCRIPTS` is not among them.
- **Fix:** Write `ignore-scripts=true` to the global `/usr/local/etc/npmrc`, or add the key to the allowlist.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-003] codex credential copy survives a SIGKILLed driver
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/pipeline-run.sh:570`
- **Issue:** `make_home` copies `$CREDS_HOME/.codex/auth.json` into `<run>/meta/home/.codex/`. `finish` (`:348`) and `on_exit` (`:356`) remove the directory, but the header (`:104-106`) documents that a SIGKILLed driver leaves the run directory behind; the credential copy then sits in a run tree that is archived per batch. Nothing sweeps `meta/home` when a `running` record is found.
- **Fix:** Mount the codex files read-only from a per-run tmpfs or from `$CREDS_HOME` directly, or have the batch runner sweep `meta/home` on a `running` record.
- **Reference:** CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [MED-004] Long-lived operator credentials are readable by the evaluated agent
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:690` (and `:694`)
- **Issue:** The container mounts `meta/home` read-write at `/home/evaluser` (`-v "$HOME_DIR:/home/evaluser:rw"`) and forwards `AWS_BEARER_TOKEN_BEDROCK` by name (`full+=(-e "$k")`). The agent runs with `--permission-mode bypassPermissions --dangerously-skip-permissions` (`:652`), the Bash tool (`:133`) and `--network bridge` (`:687`), so it can read `~/.codex/auth.json` and the bearer token and send them anywhere. Both are needed for the sandbox gates' dissent to dispatch, so this is a design acceptance, but the agent works over untrusted fixture content and a prompt injection in a fixture reaches these secrets. [ASSUMPTION] The credentials used for ablation batches are the operator's personal, long-lived ones (`LOA_EVAL_CREDS_HOME` defaults to `$HOME`, `:562`).
- **Fix:** Use dedicated, short-lived credentials for batches (a batch-scoped Bedrock token with a TTL, a separate codex account), document the exposure in the Dockerfile header, and consider an egress allowlist for the bridge network.
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html

### [MED-005] `check-loa.sh` cannot distinguish a deleted mounted link from a never-linked path
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/check-loa.sh:75-76`
- **Issue:** In a submodule mount every manifest path absent locally but present under `.loa/<path>` is counted as informational `not-mounted`. The check keeps no record of which paths the mount linked, so a deliberately removed symlink to a hook or gate script drops from `Missing (fail)` to a count in a log line. Confirmed by the cross-model dissent (DISS-C-001). The same dissent's point about `return 0` is not a defect: `fail()` increments `FAILURES` (`head/.claude/scripts/check-loa.sh:36`) and `main` exits 1 on it (`:603-605`).
- **Fix:** Have `mount-submodule.sh` persist the linked set (it prints `Linked` lines; `head/tools/fresh-mount-proof.sh:157` already counts them) and treat an absent path in that set as Missing.
- **Reference:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html

### [MED-006] The new manifest gate is red on the commit that introduces it
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.github/workflows/bats-tests.yml:175-178`
- **Issue:** `bash tools/gen-checksums.sh --check` compares the committed `.claude/checksums.json` with a regeneration, but this change edits six tracked `.claude/` files (`check-loa.sh`, `preflight.sh`, `generated-model-maps.sh`, `defaults/model-config.yaml` and its `.checksum`, `loa/CLAUDE.loa.md`, the bridgebuilder generated sources) and does not carry a regenerated manifest.
- **Fix:** Regenerate `.claude/checksums.json` in this change, or run the gate only where the manifest is produced.
- **Reference:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html

### [MED-007] No CHANGELOG, no AC verification, no documentation-coherence report
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/pipeline-run.sh:1`
- **Issue:** Nothing under `CHANGELOG*` is touched by a change that adds a credential-handling container executor and alters two integrity gates; the implementation report is the PR title; no `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists (Glob: none), so the documentation audit is manually verified here rather than reported. Per the skill, a CHANGELOG omitting security changes is a blocker; it is moot behind the HIGH findings.
- **Fix:** Add the sprint-258 CHANGELOG entry naming the credential and integrity-gate changes, and an AC walkthrough citing `file:line`.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-008] Manifest regeneration can execute a tool from the prompt tree
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:386` (resolved at `:383`)
- **Issue:** `regen_sandbox_manifest` runs `"$tool" --root "$ws"` with `tool="${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}/tools/gen-checksums.sh"` when the tool is executable and the sandbox is a git work tree tracking `.claude` files. `EVAL_PROMPT_TREE` is the artefact under evaluation (`head/evals/harness/execute-agent.sh:50`: "repo whose .claude/ is materialized"), and that script in turn sources `${SELF_DIR}/../.claude/scripts/compat-lib.sh` from the same tree (`head/tools/gen-checksums.sh:49`). The header documents the path (`:50-53`). `pipeline-run.sh` excludes `/.claude/` from the sandbox index (`:476`), so the gate holds there; the `execute-agent.sh` sandbox is created by a script outside this change, so reachability on that path is unverified.
- **Fix:** Always use the inline hashlib path (or the harness's own copy of the tool); never resolve an executable under `EVAL_PROMPT_TREE`.
- **Reference:** CWE-829 — https://cwe.mitre.org/data/definitions/829.html

### [LOW-001] Header pins the wrong codex version
- **File:** `head/evals/harness/pipeline-run.sh:85` — says "codex 0.137.0"; `head/evals/harness/Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`.
- **Fix:** Fix the comment. CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-002] Fingerprint executes a binary at one operator's dotfiles path
- **File:** `head/evals/harness/fingerprint.sh:54` — when `bats` is not on PATH the script executes `$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`, whatever sits there, with no integrity check; other hosts read `bats=absent` for an identical toolchain. Confirmed by the dissent (DISS-C-005).
- **Fix:** Drop the fallback; `absent` is the documented outcome. CWE-547 — https://cwe.mitre.org/data/definitions/547.html

### [LOW-003] Fingerprint needs python3 despite the header's promise
- **File:** `head/evals/harness/fingerprint.sh:86` — the digest requires `python3`, so a host without it exits non-zero instead of printing `python3=absent` (`:7-9`).
- **Fix:** State python3 as a hard dependency. CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-004] `ms()` accepts one timestamp shape
- **File:** `head/evals/harness/ablation-row.sh:230` — any other `started`/`finished` shape aborts the jq program and no row is appended; latent today.
- **Fix:** `try … catch null` with fallback to summed `wall_ms`. CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-005] GC-7 and MP-7 assume `$BATS_TEST_TMPDIR` is outside any git work tree
- **File:** `head/tests/unit/gen-checksums.bats:86` (and `head/tests/unit/check-manifest-paths.bats:94`) — when `TMPDIR` lies inside a repository both fail; CI unaffected.
- **Fix:** Assert with `GIT_CEILING_DIRECTORIES` or a throwaway parent repo. CWE-1068

### [LOW-006] Recovered gate records `exit 0` with `is_error true`
- **File:** `head/evals/harness/pipeline-run.sh:805` — `gate_recovered=true; rc=0` while `is_error` at `:840` stays true from `result.is_error`.
- **Fix:** Derive `is_error` from the recovered `rc`, or document `gate_recovered` as the discriminator. CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [LOW-007] Arm-id leak guard scans the mounted `.claude/`
- **File:** `head/evals/harness/pipeline-run.sh:506` — greps the whole sandbox as a fixed substring; a future mention of an arm id anywhere in the Loa tree refuses every run of that arm.
- **Fix:** Scope the guard to the fixture and `grimoires/`. CWE-697 — https://cwe.mitre.org/data/definitions/697.html

### [LOW-008] docker stub rewrites paths by substring
- **File:** `head/evals/tests/fixtures/docker-stub.sh:63` — `${s//$dst/$src}` for every mount in every argument and env value; a host checkout containing `/home/evaluser` breaks all five container-mode cases. Test-only.
- **Fix:** Rewrite only arguments that start with a mount destination. CWE-697

### [LOW-009] Agent-writable ledger rows are summed into the spend unsigned
- **File:** `head/evals/harness/pipeline-run.sh:770` (summed at `:854`) — rows the sandbox writes to `.eval/cost-ledger.jsonl` contribute `cost_micro_usd` with no sign or type check; a negative row lowers `SPENT_MICRO` and defers the cap. The authoritative `result.total_cost_usd` is unaffected.
- **Fix:** Clamp ledger contributions to non-negative numbers and count rejected rows. CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-010] Row quality fields come from agent-writable envelopes
- **File:** `head/evals/harness/ablation-row.sh:201` (and `head/evals/harness/took-effect.sh:87`) — `voices_run`, `degraded`, `degraded_reason` and the `one_voice_planned` rule read `sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json`, and the `eval/` copies are taken from the same place after every phase (`head/evals/harness/pipeline-run.sh:776-778`). An implementer phase can pre-write an envelope that reads as a healthy two-voice gate. Raised by the dissent (DISS-C-003).
- **Fix:** Copy envelopes only after the gate phase that owns them and reject envelopes older than that phase's start. CWE-345 — https://cwe.mitre.org/data/definitions/345.html

### [LOW-011] `zone_violations.dot_claude_writes` sees tool inputs only
- **File:** `head/evals/harness/ablation-row.sh:220` — Bash-tool writes into `.claude/` are not counted; `took-effect.sh`'s `integrity_clean` hash walk (`:233-268`) catches content changes, so the gap is in the row's signal, not the arm gate. Raised by the dissent (DISS-C-004).
- **Fix:** Document the field as tool-input-only, or populate it from a post-run manifest diff. CWE-693

### [LOW-012] `gpt-6.1-sol` ships placeholder prices that feed the spend estimates
- **File:** `head/.claude/defaults/model-config.yaml:144` — the entry copies gpt-5.5 list prices "until the gpt-6.1 rate card is confirmed", and `codex-headless`'s `cli_model` (`:240`) now points at it, so MODELINV cost rows and the caps that read them estimate from an unconfirmed rate card. No dispatch cycle: `codex-headless` is a chain terminal with no `fallback_chain` (`:213-214`). Raised by the dissent (DISS-C-006).
- **Fix:** Confirm the rate card before the first batch and flag placeholder-priced rows in `spend.sh`. CWE-1059

---

## Observations

No HIGH finding of this audit is marked speculative; nothing is excluded from the tally. The review's trailer excluded 0 findings, so there are no demotions to confirm (`excluded_confirmed` 0).

Reviewed and not counted:
- `check_integrity` ending in `return 0` (`head/.claude/scripts/check-loa.sh:85`): `fail()` increments `FAILURES` at `:36`; `main` exits 1 on it at `:603-605`. Not a defect.
- `ENV_SHIM`'s `os.execvpe` (`head/evals/harness/pipeline-run.sh:628`) resolves the command through the new environment's `PATH`, which is in both key sets. Safe.
- `remove_tree` (`:307-311`) uses `find -depth -delete`, which does not follow symlinks; `HOME_DIR` sits under the run directory that `:283-285` requires empty. Safe.
- `write_sandbox_grimoire` rejects `..` and absolute `review_catch.fixture` values before assembling a path (`head/evals/harness/lib/sandbox-mount.sh:489`). Safe.
- `fresh-mount-proof.sh` copies the source work tree's untracked, non-ignored files into a temp clone (`head/tools/fresh-mount-proof.sh:122-136`); the clone is removed on exit unless `--keep`. No finding.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`metadata.type` audit, `metadata.model` gpt-5.5-pro answered by codex-headless, companion claude-headless `counted_as` independent_voice; `verdict_quality`: 2/2 voices, consensus, APPROVED; `metadata.degraded` false; `rejected_count` 0).

| Dissent | Severity (dissent) | Triage |
|---------|--------------------|--------|
| DISS-C-001 `check-loa.sh` not-mounted downgrade + `return 0` | MEDIUM | Downgrade counted as MED-005 (confirmed by cross-model review); `return 0` not a defect (see Observations) |
| DISS-C-002 `preflight.sh` counts tracked files only, planted untracked files invisible | MEDIUM | Folded into HIGH-005 as the second direction of blindness |
| DISS-C-003 row quality fields from sandbox envelopes | MEDIUM | Counted as LOW-010 (semi-trusted agent; the authoritative gate verdicts come from the same tree by design) |
| DISS-C-004 `dot_claude_writes` misses Bash writes | LOW | Counted as LOW-011; mitigated by `integrity_clean` |
| DISS-C-005 fingerprint hard-coded operator path executed | LOW | Counted as LOW-002 (confirmed by cross-model review) |
| DISS-C-006 `gpt-6.1-sol` placeholder prices, possible dispatch cycle | LOW | Counted as LOW-012; cycle ruled out (chain terminal) |

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no rejected-payload sidecar rows exist for this round.

---

## Rubric Scores

| Dimension | Score (1–5) | Justification |
|-----------|-------------|---------------|
| Security | 2 | Two confirmed trust-boundary crossings (HIGH-001, HIGH-002) plus a gated third (MED-008); secret handling otherwise careful (`<set>` capture, descriptor close, env-only token) |
| Architecture | 3 | Clear contract between executor and mount library; evidence files well separated from grader inputs; provenance of envelopes and ledger rows not enforced |
| Code Quality | 2 | Two undeclared jq ≥ 1.7 dependencies (HIGH-003, HIGH-004) with no version probe; otherwise strict-mode discipline, NUL-safe path handling |
| DevOps | 2 | New CI gates red on their own commit (HIGH-006, MED-006); dead Docker stage; ineffective npm hardening |
| Blockchain/Crypto | n/a | Not applicable |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the bearer token travels by environment and is recorded as `<set>`; `head/evals/harness/pipeline-run.sh:694`, `:705-706`)
- [ ] Input validation at trust boundaries — three executions of code from the evaluated tree (HIGH-001, HIGH-002, MED-008)
- [x] Authentication required where needed (N/A beyond the token and codex paths)
- [x] No SQL/XSS injection vulnerabilities (N/A)
- [ ] Error handling doesn't leak info — a SIGKILLed run leaves a credential copy (MED-003)
- [ ] Tests cover security paths — the trust-boundary test misses the library and non-`source` invocations; `price_for`'s production branch is untested

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix the six HIGH findings: remove both `.claude/` code executions from the harness and extend the trust-boundary test; rename the jq `label` bindings and replace the NUL-split captures with `--args`; count present files in `preflight.sh`; ship the regenerated `runs/` fixtures.
2. Regenerate `.claude/checksums.json` and the fixture runs with the fixed scripts; run `bats evals/tests/ tests/unit/` on a jq 1.6 host and in CI.
3. Address MED-001 through MED-008, in particular the credential lifecycle (MED-003, MED-004) and the manifest-regeneration tool path (MED-008).
4. Add the CHANGELOG entry and AC walkthrough; run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":6,"medium":8,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:06:00Z"} -->
