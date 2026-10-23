# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries `pr/PR.md`)
**Task:** review-r22 — `/audit-sprint sprint-1`
**Change under audit:** `pr/head.diff` (72 files, cycle-130 sprint-258: mount integrity #1267, spend caps, ablation suite and arms, container pipeline executor, rows and took-effect evidence, smoke)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint adds a sandboxed, containerised executor that runs an LLM agent with `--dangerously-skip-permissions` over a PR's `.claude/` tree, a mount-integrity manifest pipeline (generator, CI gate, preflight/check-loa consumers), spend-cap tooling and the ablation evidence chain. The secret path is well designed: the Bedrock bearer token travels by name only, the exec shim closes descriptors and keeps an exact key allowlist, captures record `<set>`, and exactly two bind mounts are passed. The arm-toggle library verifies every edit after making it, the fixture path rule and leak guards exist, and the manifest generator is NUL-safe and refuses unsafe names.

The audit still finds four HIGH defects. Two are new: the host-side driver dereferences symlinks that the untrusted sandbox controls when it copies ledgers and envelopes out of the sandbox (a sandbox-to-host file read that lands in persisted eval artefacts), and the mount library executes a script from the sandbox's own `.claude/` on the host, outside the container, whenever `br` is absent — the exact boundary the container exists to hold. Two confirm the review and the review's cross-model dissent: on a submodule mount the new `not-mounted` branch in `check-loa.sh` and the `git ls-files` count in `preflight.sh` together let a deleted fence file pass both integrity checks green. Seven MEDIUM and seven LOW findings follow, most of them hardening of the cost-cap trust boundary, container flags and credential lifecycle.

Prerequisite note: the skill's Phase 0 expects `engineer-feedback.md` to say "All good"; it says CHANGES REQUIRED (0 critical, 5 high). The orchestration invoked the audit on this evaluation layout regardless, so the audit ran and records the deviation here rather than stopping.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 7 |
| Low | 7 |

Dissent: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — two voices (`gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`), `voices_planned 2 / voices_succeeded 2`, `chain_health ok`, `degraded: false`, `companion_voice.counted_as independent_voice`. Not a degraded security review.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Host-side driver dereferences sandbox-controlled symlinks when copying out ledgers and envelopes

**Severity:** HIGH — **Confidence:** medium
**File:** `head/evals/harness/pipeline-run.sh:773` (also `:774`, `:777`, `:713`, `:715`, `:769`)
**Issue:** After every phase the driver, running on the host as the operator, copies files the agent wrote inside the sandbox:

```bash
cp "$WS/.eval/model-invoke.jsonl" "$EVALD/model-invoke.jsonl" 2>/dev/null || true
cp "$WS/.eval/cost-ledger.jsonl" "$EVALD/cost-ledger.jsonl" 2>/dev/null || true
...
for env_f in "$WS"/grimoires/loa/a2a/"$SPRINT"/adversarial-*.json; do
  [[ -f "$env_f" ]] && cp "$env_f" "$EVALD/"
```

Plain `cp` dereferences a symlink given as its source operand (verified here with coreutils 9.1: `cp link dst` copies the target's bytes). `sandbox/.eval/` is writable by the agent (`.eval/` is only `info/exclude`d, `:476`), and in container mode the agent runs as the host uid (`--user "$(id -u):$(id -g)"`, `:686`) on a bind mount, so a symlink it creates at `/workspace/.eval/model-invoke.jsonl` is a host symlink under `$WS` whose target string the host resolves. `wc -l <` (`:713`, `:715`) and `sed -n` (`:769`) read through the same links. The sandbox is UNTRUSTED by the harness's own trust model (`lib/sandbox-mount.sh:97-99`, DEC-0413 "never from sandbox/").
**Impact:** An agent that is adversarial or prompt-injected by fixture content (the review-catch PRs it reads are arbitrary code and prose) runs `ln -sf /home/<op>/.aws/credentials /workspace/.eval/model-invoke.jsonl` and the driver copies the operator's host file into `<run>/eval/model-invoke.jsonl`, a persisted batch artefact that `ablation-row.sh` ingests and the grader reads. Any host file the operator can read is reachable (`~/.ssh/*`, `~/.claude/.credentials.json`, the real `~/.codex/auth.json`). The container boundary does not help because the read happens on the host.
**PoC:**
```
# inside the sandbox (any phase with Bash)
ln -sf /home/evaluser/.ssh/id_ed25519 /workspace/.eval/cost-ledger.jsonl
# host driver after the phase: cp follows the link → <run>/eval/cost-ledger.jsonl == the key
```
**Fix:** Before every host-side read of a sandbox path, refuse symlinks and non-regular files: `[[ -L "$p" || ! -f "$p" ]] && infra "sandbox path is not a regular file: $p"`; copy with `cp -P`/`--no-dereference` after the check (or `python3 -I` with `os.open(..., O_NOFOLLOW)`). Apply the same guard in `ablation-row.sh:194,201` and `took-effect.sh:87-88` which also read `sandbox/` paths on the host. Add a bats case that plants a symlink and asserts `infrastructure_error`.
**Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

### [HIGH-002] Mount library executes a script from the sandbox's `.claude/` on the host, outside the container

**Severity:** HIGH — **Confidence:** medium
**File:** `head/evals/harness/lib/sandbox-mount.sh:513` (and `:386`)
**Issue:**

```bash
local ubs="$ws/.claude/scripts/beads/update-beads-state.sh"
if [[ -f "$ubs" ]]; then
  PROJECT_ROOT="$ws" bash "$ubs" --opt-out "eval sandbox: br not on PATH" >/dev/null 2>&1 \
```

`init_sandbox_beads` is called by the driver on the host (`pipeline-run.sh:489`) before any container starts. When `br` is not on the host PATH (CI, and any operator host without the glibc-2.38 binary — `Dockerfile.ablation:82-84`), it runs `bash` on a script that was copied from the `--source-tree` under test into the sandbox (`mount_prompt_surface`, `:131`). The file header states the boundary this crosses: "the eval workflow runs the harness as the trusted copy against a PR's .claude/, so no harness script sources .claude/ code" (`:97-99`). Executing is worse than sourcing. `:386` has the same shape (`"$tool" --root "$ws"` where `$tool` may be `$EVAL_PROMPT_TREE/tools/gen-checksums.sh`, which itself sources `<prompt tree>/.claude/scripts/compat-lib.sh`, `head/tools/gen-checksums.sh:51`); in the pipeline flow that branch is dead because the sandbox excludes `.claude/` from git, but `execute-agent.sh` runs with `EVAL_PROMPT_TREE` set to a PR worktree (`run-arms.sh:433`). The `pipeline-run.bats` trust-boundary test (`:248-259`) only scans `source` lines and cannot see either call.
**Impact:** The container, the two-mount rule, the read-only root and the env allowlist confine the PR's `.claude/` code to the sandbox. This call runs it as the operator on the host with the operator's full environment (credentials, SSH agent, docker socket), defeating all of them. Trigger: a PR whose `.claude/scripts/beads/update-beads-state.sh` is hostile, on a host or CI runner without `br`.
**Fix:** Write the opt-out marker from the library itself (it is a small JSON/marker file; mirror its format) and never invoke sandbox code on the host; use the inline hashing path unconditionally for the sandbox manifest (`:383-387` → always `how="inline"`). Extend the trust-boundary test to flag `bash "$ws/…"`, `"$tool"` and any exec of a path under `$ws/.claude` or `$EVAL_PROMPT_TREE`.
**Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html ; CWE-668 Exposure of Resource to Wrong Sphere — https://cwe.mitre.org/data/definitions/668.html

### [HIGH-003] Preflight file-count check reads the index, so a deleted tracked fence file is still counted

**Severity:** HIGH — **Confidence:** high
**File:** `head/.claude/scripts/preflight.sh:190`
**Issue:**

```bash
ACTUAL_COUNT=$(git -C "${MANIFEST_TREE}" ls-files -- .claude \
    | awk '!/^\.claude\/overrides\// && $0 != ".claude/checksums.json"' | wc -l | tr -d ' ')
```

`git ls-files` lists the index, not the working tree. A tracked `.claude/hooks/safety/*.sh`, rule or guard deleted from the working tree leaves `ACTUAL_COUNT` unchanged, so the count mismatch the previous `find`-based count (`pr/base`, now the `:196` fallback used only when the tracked count is 0) detected is suppressed. Confirms review Changes Required #5 and the review dissent's BLOCKING finding.
**Impact:** Preflight is the integrity signal that runs before every skill (`integrity_enforcement` strict mode exits 1 on mismatch, `:204-214`). A tree with fence files deleted now passes it.
**Fix:** Count only tracked paths that exist: `git -C "$MANIFEST_TREE" ls-files -- .claude | while IFS= read -r p; do [[ -f "$MANIFEST_TREE/$p" ]] && …; done`, or subtract `git ls-files --deleted -- .claude`. Add a unit case that deletes one tracked file and expects the mismatch.
**Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [HIGH-004] On a submodule mount every absent manifest path is `not-mounted`, so a deleted fence file never fails `check-loa.sh`

**Severity:** HIGH — **Confidence:** medium
**File:** `head/.claude/scripts/check-loa.sh:75`
**Issue:**

```bash
elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]; then
  not_mounted=$((not_mounted + 1))
else
  fail "Missing: $file"
```

`submodule_mount` is true whenever `.loa/.claude` is a directory (`:64`), and on a submodule mount every manifest path exists under `.loa/` by construction, so the `Missing` branch is unreachable: a removed or dangling link in `.claude/` (a hook, gate script, rule file) is counted as informational `not-mounted` and the exit code stays 0, where `pr/base` reported `Missing` and exit 1. The upstream copy's hash is not compared either. Together with HIGH-003 the two integrity checks a downstream has are both green after a fence is deleted. `tests/unit/check-loa-mount-scope.bats` has no deleted-link case. Raised independently by both the review dissent (advisory) and this audit's dissent (DISS-C-001, MEDIUM); the review rated it MEDIUM — the audit rates the failure scenario (a silent loss of a safety fence with a passing integrity check) HIGH.
**Impact:** The #1267 fix trades a false-positive storm for a blind spot on exactly the paths the check exists to protect.
**Fix:** Distinguish "never linked" from "linked then removed" with the mount's own link inventory (`mount-submodule.sh --check-symlinks` or the manifest it writes), or treat a path as Missing when its parent directory in `.claude/` is linked/present; compare the `.loa/<path>` hash in the `not-mounted` branch so an upstream tamper is still Tampered. Add the deleted-link bats case.
**Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

---

## Medium/Low Priority Issues

### [MED-001] Sandbox-written cost-ledger rows are summed without a sign or type clamp; a negative row defers the per-run cap
- **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:770` (also `:854`, `:719`; `head/evals/harness/ablation-row.sh:242`, `:312`; `head/evals/harness/spend.sh:129`)
- **Issue:** `ledger_micro="$(… jq -R -n '[inputs | fromjson? | select(type == "object") | (.cost_micro_usd // ((.cost_usd // 0) * 1000000))] | add // 0 | round')"` sums rows from `sandbox/.eval/cost-ledger.jsonl`, which the agent can write. A row `{"cost_micro_usd": -900000000}` makes `SPENT_MICRO` negative (`:854`), inflates the watchdog `budget` (`:719`) and defeats the `SPENT_MICRO -ge CAP_MICRO` check (`:864`). `spend.sh:129` accepts negative `cost_usd` the same way and `ablation-row.sh` propagates it into `cost_usd`.
- **Impact:** The D-4.6 per-run cap and the cycle cap can be pushed past by the thing they meter. Bounded by phase timeouts and `--max-turns`, hence MEDIUM.
- **Fix:** `select((.cost_micro_usd // .cost_usd) | type == "number" and . >= 0)`; clamp each row to `[0, cap]`; same in `spend.sh` and `ablation-row.sh`.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [MED-002] Container runs an autonomous agent with setuid binaries available and no privilege hardening flags
- **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:686`
- **Issue:** `docker run --rm --name … --user uid:gid --network bridge --read-only --tmpfs /tmp … --pids-limit 512 --memory 4g --cpus 2` has no `--cap-drop=ALL`, no `--security-opt=no-new-privileges`, and no egress restriction. The image is Debian bookworm-slim, which ships setuid `su`, `mount`, `umount`, `passwd`, `chsh`, `chfn`, `gpasswd`, `newgrp`; the process inside runs with `--dangerously-skip-permissions`, Bash, and the Bedrock bearer token plus the codex credentials in reach. `--read-only` and the non-root uid limit, but do not remove, the local escalation surface; outbound network to anything is open.
- **Fix:** Add `--cap-drop=ALL --security-opt=no-new-privileges:true` (and `--security-opt=seccomp=default` explicitly); consider a user-defined network with egress allowed only to the Bedrock/OpenAI endpoints. Extend the `pipeline-run.bats` "resource flags" test (`:632-657`) to assert them.
- **Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html ; CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-003] Operator Codex credentials are copied under the run directory and survive a SIGKILLed driver
- **Confidence:** high
- **File:** `head/evals/harness/pipeline-run.sh:570` (cleanup `:348`, `:356`)
- **Issue:** `cp "$CREDS_HOME/.codex/$f" "$HOME_DIR/.codex/$f"` places `auth.json` at `<run>/meta/home/.codex/auth.json`, mounted read-write into the container and readable by the agent (same uid). Deletion relies on `finish`/`on_exit`; a SIGKILLed driver (`:104-106` documents this case for `pipeline.json`) leaves the credential copy inside a results tree that batch tooling archives. The copy is deliberate (the sandbox gates dispatch codex) but it hands a long-lived operator OAuth token to the agent under test, and the run tree is not a credential store.
- **Fix:** Mount the two codex files read-only from a dedicated 0700 directory outside the run tree (a third mount is a documented contract change; alternatively a tmpfs populated by the shim), or at minimum create `$HOME_DIR` under `mktemp -d` outside `$RUN_DIR` and have `run-arms`/batch tooling sweep stale `meta/home` dirs. Prefer a scoped, short-lived credential for the eval user.
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html ; CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [MED-004] Transcripts and stderr are persisted raw; no redaction of the secret values the driver knows, and the test guarding this cannot fail
- **Confidence:** medium
- **File:** `head/evals/harness/pipeline-run.sh:725` (test: `head/evals/tests/pipeline-run.bats:726`)
- **Issue:** `exec "${full[@]}" ) < /dev/null > "$events" 2> "$errf"` writes the CLI's stream-json and stderr to `transcripts/`, which outlive the run, are read by `ablation-row.sh` and are kept in batch artefacts. The agent holds `AWS_BEARER_TOKEN_BEDROCK` in its environment; one `env` or `printenv` in a Bash tool call (its own, or induced by fixture prose) puts the token into `events-<label>.jsonl`. The driver knows every `SECRET_KEYS` value and never scrubs. The only check, `! grep -rqF "$tok" "$T/log" "$T/dlog"` at `pipeline-run.bats:726`, is a bare negated command inside a `for` loop and passes regardless (review Changes Required #4; verified mechanism: bash exempts `!` from errexit).
- **Fix:** After each phase, scan `$events`/`$errf` for every set `SECRET_KEYS` value and either rewrite it to `<redacted>` or fail the run `infrastructure_error: secret in transcript`. Make the bats assertions failing (`run ! grep …; [ "$status" -ne 0 ]`).
- **Reference:** CWE-532 Insertion of Sensitive Information into Log File — https://cwe.mitre.org/data/definitions/532.html

### [MED-005] `integrity_clean` never enforces the recorded manifest hash, so tamper-then-regenerate passes
- **Confidence:** high
- **File:** `head/evals/harness/took-effect.sh:266` (walk `:254`)
- **Issue:** `[[ "$filesha" == "$msha" ]] && EVID="$EVID (matches checksums.json)"` only decorates the evidence; `arm_evidence.manifest_sha256` (written by the driver before any phase) is computed and never compared as a pass/fail condition. An agent that edits `sandbox/.claude/…` and regenerates `checksums.json` passes `integrity_clean`, and the walk iterates manifest entries only, so an injected `.claude/hooks/x.sh` is invisible. Confirms the review's Observation.
- **Fix:** FAIL when `$filesha != $msha` (the driver's pre-phase digest is the trusted anchor) and FAIL on unlisted regular files under `sandbox/.claude/`.
- **Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [MED-006] The new integrity-manifest CI gate is red on this PR because `.claude/checksums.json` is not regenerated in the change
- **Confidence:** high
- **File:** `head/.github/workflows/bats-tests.yml:178` (tool: `head/tools/gen-checksums.sh:143-168`)
- **Issue:** `bash tools/gen-checksums.sh --check` compares the committed manifest with a regeneration over the tracked tree; the PR edits ten manifest-covered files (`model-config.yaml`, `check-loa.sh`, `preflight.sh`, `generated-model-maps.sh`, `CLAUDE.loa.md`, six bridgebuilder files) and carries no `.claude/checksums.json`, so the gate exits 1 from its first run (the review observed `DRIFT — 10 path(s)`). Confirms review Changes Required #2. The `paths:` filter (`:49-70`) also omits `.claude/skills/**`, `.claude/protocols/**`, `.claude/rules/**`, `.claude/loa/**` and `.claude/checksums.json`, so a skill-only PR never triggers the gate and the next unrelated PR inherits its drift.
- **Fix:** Run `tools/gen-checksums.sh` and commit the manifest in this PR; add the missing paths to the filter.
- **Reference:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html (an integrity gate that cannot pass is an integrity gate nobody keeps)

### [MED-007] `ignore-scripts` is set where the agent never reads it, so npm lifecycle scripts of anything the agent installs run
- **Confidence:** high
- **File:** `head/evals/harness/Dockerfile.ablation:91` (and `:77`)
- **Issue:** `ENV NPM_CONFIG_IGNORE_SCRIPTS=true` is dropped by the exec shim's exact allowlist (`pipeline-run.sh:661-670` never lists it) and `npm config set ignore-scripts true` at `:77` writes `/root/.npmrc`, which the `--user <host uid>` process with `HOME=/home/evaluser` never reads. The comment "Disable npm lifecycle scripts for anything the agent installs later" is false. Confirms the review's Observation.
- **Fix:** Add `NPM_CONFIG_IGNORE_SCRIPTS=true` to the pass-through keys, or write `ignore-scripts=true` into `$HOME_DIR/.npmrc` in `make_home` (`pipeline-run.sh:563`).
- **Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html

### [LOW-001] Preflight follows the `checksums.json` symlink to an unconstrained tree and runs `git` there
- **Confidence:** medium
- **File:** `head/.claude/scripts/preflight.sh:184`
- **Issue:** `MANIFEST_LINK=$(readlink …)` → `MANIFEST_TREE=$(cd "$(dirname "${MANIFEST_LINK}")/.." && pwd -P)` → `git -C "${MANIFEST_TREE}" ls-files`. The link target is not constrained to the project or `.loa/`, so whoever controls the link chooses the tree the count comes from, and `git` honours that repository's own config (`core.fsmonitor`, `core.hooksPath` — a known exec vector on untrusted repos). Dissent DISS-C-002.
- **Fix:** Require `MANIFEST_TREE` to be `${PROJECT_ROOT}` or `${PROJECT_ROOT}/.loa` (`pwd -P` prefix check) before invoking git; pass `-c core.fsmonitor=false -c core.hooksPath=/dev/null`.
- **Reference:** CWE-59 — https://cwe.mitre.org/data/definitions/59.html

### [LOW-002] Degraded/voices metrics and took-effect rules read the dissent envelopes from the agent-writable sandbox
- **Confidence:** medium
- **File:** `head/evals/harness/ablation-row.sh:201` (and `head/evals/harness/took-effect.sh:87`)
- **Issue:** `envelope()` prefers `sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json`; the `eval/` fallback is only a copy of the same sandbox file (`pipeline-run.sh:776-777`). The gate necessarily writes inside the sandbox, so the agent under evaluation can rewrite `verdict_quality` to hide a degraded or skipped gate from `runs.jsonl` and from `one_voice_planned`. The header's DEC-0413 rule ("never from sandbox/") is applied to the arm only. Dissent DISS-C-003.
- **Fix:** Cross-check envelope claims against driver-owned evidence (MODELINV rows copied per phase, `modelinv_lines` ranges) and mark the row `degraded_reason: envelope unverifiable` when they disagree; or sign envelopes with the harness-held key.
- **Reference:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

### [LOW-003] Fingerprint executes a hard-coded operator home-directory path when `bats` is absent
- **Confidence:** high
- **File:** `head/evals/harness/fingerprint.sh:54`
- **Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` then `tool_version "$BATS_BIN" --version` (`:76`) runs whatever sits at that path on any host. A personal dotfiles path in committed harness code; `tool_version` also runs `$EVAL_CLAUDE_BIN`/`$LOA_EVAL_BATS_BIN` from the environment unchecked. Dissent DISS-C-005.
- **Fix:** Default to `bats=absent` when not on PATH; drop the personal path.
- **Reference:** CWE-426 Untrusted Search Path — https://cwe.mitre.org/data/definitions/426.html

### [LOW-004] Placeholder rate card now prices the default Codex CLI hop; caps and MODELINV rows treat it as actual
- **Confidence:** high
- **File:** `head/.claude/defaults/model-config.yaml:144` (repoint `:239`)
- **Issue:** `gpt-6.1-sol` carries `# PLACEHOLDER: gpt-5.5 list prices copied 2026-10-15` and `codex-headless` `cli_model` is moved to it, so every codex estimate, MODELINV row and `spend.sh` figure for the OpenAI CLI path uses unconfirmed numbers with `pricing_source: config`; the entry also enters `VALID_FLATLINE_MODELS` (`head/.claude/scripts/generated-model-maps.sh:333`). Dissent DISS-C-006; the review rated it MEDIUM.
- **Fix:** Machine-readable `pricing_provisional: true` surfaced in ledger rows, or keep the entry out of the Flatline allowlist until confirmed.
- **Reference:** CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

### [LOW-005] Unpinned `rust:1-bookworm` build stage with an unlocked `cargo install` fallback
- **Confidence:** high
- **File:** `head/evals/harness/Dockerfile.ablation:19` (`:20`)
- **Issue:** `FROM rust:1-bookworm AS brbuild` has no digest (every other base is digest-pinned) and `cargo install … --locked || cargo install …` retries without `--locked`, pulling an unverified dependency graph. The stage is never `COPY --from`'d (`:82-84` say `br` is deliberately absent), so under BuildKit it is dead; under the legacy builder it is a network build that can fail or be poisoned. Delete it.
- **Reference:** CWE-1357 Reliance on Insufficiently Trustworthy Component — https://cwe.mitre.org/data/definitions/1357.html

### [LOW-006] `--worktree` overlay commits every untracked, non-ignored file of the operator's tree into the proof clone
- **Confidence:** medium
- **File:** `head/tools/fresh-mount-proof.sh:133`
- **Issue:** `git ls-files -z --cached --others --exclude-standard` copies and commits untracked files (anything not yet gitignored — a stray `.env`, a token file) into the temp upstream; `--keep` leaves that clone on disk, and the clone is cloned again into `downstream/`. Temp-only, so LOW.
- **Fix:** Restrict the overlay to `.claude/`, `tools/`, `.loa-version.json` and the files `check-loa.sh` reads, or warn and list the untracked paths before committing them.
- **Reference:** CWE-312 Cleartext Storage of Sensitive Information — https://cwe.mitre.org/data/definitions/312.html

### [LOW-007] `zone_violations.dot_claude_writes` counts Write/Edit tool calls only; Bash-path writes to `.claude/` are invisible
- **Confidence:** high
- **File:** `head/evals/harness/ablation-row.sh:216`
- **Issue:** The row's System-Zone write metric inspects `Write|Edit|MultiEdit|NotebookEdit` `tool_use` inputs matching `(^|/)\.claude/`; `sed -i`, redirects, `cp`/`mv` through Bash and paths via `..` or symlinks are not counted, so the metric under-reports. Same class as the accepted fence gap in CLAUDE.loa.md, but the schema presents it as authoritative. Dissent DISS-C-004.
- **Fix:** Add the `regen_sandbox_manifest` digest vs the post-run walk (MED-005's enforced form) as a second signal: any `.claude/` content change is a zone violation whatever the tool.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

---

## Additional Notes (not tallied; no demoted findings)

- `pipeline-run.sh:568` pre-trusts `/workspace` (`hasTrustDialogAccepted`) so the mounted tree's project settings and hooks run without a dialog, and `--setting-sources project` with `bypassPermissions` lets the PR's `.claude/settings.json` hooks execute inside the container. This is the eval's purpose; it is why the two new sandbox-boundary findings above matter — the container is the only boundary.
- `pipeline-run.sh:586` runs `pricing.py` from the harness repository's own `.claude/adapters` (`$REPO_ROOT`), not the sandbox; correct side of the boundary.
- `check-loa.sh:87` unconditional `return 0`: verified that callers use the `FAILURES` counter (`:36`, `:604-605`), so the exit code is unaffected; the review's dissent also dismissed it. Not adopted.
- `gen-checksums.sh:94` refuses newline/tab/backslash names and `:137` replaces a symlinked manifest with `mv` rather than writing through it; `check-manifest-paths.sh:80` is not `-z` (review LOW). Good defensive shape overall.
- Scope limits: `security-audit-scope.sh` scans the workspace root (its counts cover the live checkout, not `pr/head/`, and were not used); `shellcheck` is not installed; the audit did not re-run the bats suites (the review's runs and counts are relied on and quoted where used); `arm-toggles.bats`, `run-arms.bats`, `freeze.bats`, `validate-suite.bats` need repo fixtures absent from the frozen tree and were read only. No `.reviewignore` exists.

---

## Cross-Model Security Observations

Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`: primary `gpt-5.5-pro` returned `clean` (no findings); companion `claude-headless` returned seven, none CRITICAL/HIGH. Triage:

1. DISS-C-001 (MEDIUM) `check-loa.sh` not-mounted masks a deleted guard → adopted and raised: HIGH-004 (confirmed by cross-model review).
2. DISS-C-002 (LOW) preflight readlink target unconstrained; git in an attacker-chosen dir → LOW-001.
3. DISS-C-003 (LOW) envelopes read from the agent-writable sandbox → LOW-002.
4. DISS-C-004 (LOW) Bash-path `.claude/` writes not counted → LOW-007.
5. DISS-C-005 (LOW) hard-coded operator bats path executed → LOW-003 (`fingerprint.sh:54` verified).
6. DISS-C-006 (LOW) placeholder pricing on the repointed codex hop → LOW-004 (`model-config.yaml:239` repoint verified).
7. DISS-C-007 (LOW) `CLAUDE.loa.md` managed-header hash unchanged across the version bump → **not adopted**: the file body below the header is byte-identical between `pr/base` and `pr/head` (sha256 `fbba66c3…` both), so an unchanged content hash is the correct outcome; only the version field moved.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope (the `adversarial-rejected-review.jsonl` present is the review round's, 0 rows).

---

## Review Findings Confirmed (security-relevant subset)

Review trailer: `CHANGES_REQUIRED`, 0 critical / 5 high / 16 medium / 17 low, `excluded: 0` → nothing to confirm as a demotion; `excluded_confirmed: 0`.

| Review item | Audit disposition |
|---|---|
| #5 `preflight.sh:190` deleted tracked files counted | HIGH-003 (confirmed, same severity) |
| #2 `bats-tests.yml:178` manifest gate red | MED-006 (confirmed; audit rates the gate defect MEDIUM) |
| #4 `pipeline-run.bats:726` vacuous negated assertions | folded into MED-004 (the untested guarantee is the security issue) |
| Obs §4 `check-loa.sh:75` not-mounted masks deletion | HIGH-004 (raised) |
| Obs §1 `took-effect.sh:266` manifest hash decorative | MED-005 |
| Obs §5 `Dockerfile.ablation:91` ignore-scripts unreachable | MED-007 |
| Obs §4 `sandbox-mount.sh:386/:513` trust-boundary contradiction | HIGH-002 (raised: it is execution of sandbox code on the host) |
| Obs §2 `pipeline-run.sh:570` credential copy residue (LOW) | MED-003 (raised) |
| Obs §6 `model-config.yaml:144` placeholder pricing (MEDIUM) | LOW-004 (lowered: estimates only) |
| #1 fixture `runs/` absent, #3 jq 1.7 syntax, Obs §2-3 robustness, §5 stubs, §6 docs | Not security findings; stand as the review's; not re-tallied here |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (none found; `AWS_BEARER_TOKEN_BEDROCK` by name only, `<set>` in captures)
- [ ] Input validation at trust boundaries — sandbox-written ledgers, symlinks and envelopes are consumed unvalidated (HIGH-001, MED-001, LOW-002)
- [ ] Sandbox boundary held — sandbox `.claude/` code executed on the host (HIGH-002); container lacks cap-drop/no-new-privileges (MED-002)
- [ ] Integrity checks fail closed — deleted fence files pass preflight and check-loa on submodule mounts (HIGH-003, HIGH-004); took-effect manifest hash decorative (MED-005)
- [ ] Error handling and logs don't leak info — transcripts unredacted, guard test vacuous (MED-004)
- [ ] Credentials protected — codex auth copy under the run tree (MED-003)
- [ ] Tests cover security paths — the secret/leak/effort assertions cannot fail; no symlink, deleted-link or negative-ledger case

## Rubric Scores

| Dimension | Score | Basis |
|---|---|---|
| SEC-IV Input Validation | 3 | Strong on argv/task/suite inputs; sandbox outputs trusted (HIGH-001, MED-001) |
| SEC-AZ Authorization / boundary | 2 | Host exec of sandbox code (HIGH-002); container hardening gaps (MED-002) |
| SEC-CI Confidentiality/Integrity | 3 | Good secret plumbing; integrity checks regress on submodule mounts (HIGH-003/004); credential residue (MED-003) |
| Architecture | 4 | Clear trust model stated in headers; two violations of it |
| Code Quality | 3 | Careful shell; see review for size/duplication |
| DevOps | 3 | Pinned images except the dead rust stage; CI gate ships red (MED-006) |

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` reports exist in this evaluation layout (no `/implement` ran here), so the per-task coherence check is recorded as not applicable rather than failed. Security-critical code is commented (every script carries a contract header). No CHANGELOG change is in the diff for a sprint that adds eight operator-facing scripts and a CI gate (review Obs §6, low confidence on the convention). `Dockerfile.ablation:77` and `pipeline-run.sh:85` carry claims the code contradicts (MED-007; codex version pin — review).

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 first (sandbox → host reads and execution): symlink/regular-file guard on every host-side read of `sandbox/`, and remove every host invocation of sandbox or prompt-tree code from `lib/sandbox-mount.sh`.
2. Fix HIGH-003 and HIGH-004 together with a deleted-fence unit case for both `preflight.sh` and `check-loa.sh`.
3. Address MED-001 … MED-007 before the first live batch (cap clamp, container flags, credential placement, transcript redaction, manifest enforcement, regenerate `.claude/checksums.json`, npm ignore-scripts).
4. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":7,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:05:00Z"} -->
