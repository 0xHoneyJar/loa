# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` (72 files; cycle-130 sprint-258 — mount integrity #1267, spend caps, ablation suite and arms, container pipeline executor, rows and took-effect evidence, smoke)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change adds a container-based pipeline executor (`evals/harness/pipeline-run.sh`, 907 lines, new) that runs an untrusted agent session with `--dangerously-skip-permissions` inside `docker run --read-only --pids-limit --memory` with exactly two bind mounts, a sandbox materialiser (`lib/sandbox-mount.sh`, new), the row builder, took-effect prover, spend scripts, the integrity tooling for #1267 and two edits to the System Zone fences (`preflight.sh`, `check-loa.sh`). I read every head-side script, the Dockerfile, the workflow, the suite file and the bats suites; ran the security dissent on `pr/head.diff` (two voices, 2/2 succeeded, 0 rejected payloads); and reproduced the two mechanisms behind the HIGH findings on this host (git 2.39.5, jq 1.6).

The secret-handling design is strong: credentials travel in the environment only, through a `python3 -I` exec shim that closes descriptors and keeps an allowlist; every capture masks `AWS_BEARER_TOKEN_BEDROCK` as `<set>` (`pipeline-run.sh:620-632, 702-710`); the per-run HOME is removed on the EXIT trap and on signals (`:348, :356`); no `eval` anywhere; every jq program takes `--arg`. Leak guards refuse `hidden`, defect keys and arm ids before a phase runs (`:502-521`).

Four findings block the merge. One is new to this audit and is the most serious: the containment boundary the executor is built around has a hole on the host side. After IMPLEMENT and FIX the driver runs `git add -A` and `git commit` **on the host** against `sandbox/.git`, a directory the containerised agent writes freely. Git executes repo-local hooks and `core.fsmonitor` / `core.hooksPath` / filter commands from that `.git`; `env -i` with `GIT_CONFIG_GLOBAL=/dev/null` does not isolate repo-local config. I confirmed on this host that both a planted `pre-commit` hook and a `core.fsmonitor` command run under the exact `sgit` invocation. The same PR gets this right elsewhere: `tools/fresh-mount-proof.sh:96` pins `core.hooksPath` to an empty directory for its hermetic git. The other three confirm the review's blocking findings (jq 1.6 keyword `label`; preflight's count no longer looks at the disk; `check-loa.sh` cannot see a removed link in a submodule mount), each re-verified here.

Pre-flight note: Phase 0 of this skill expects `engineer-feedback.md` to read "All good"; it reads CHANGES_REQUIRED (0/3/6/11). The task instruction ordered the audit regardless, so I proceeded and record the deviation here. `adversarial-review.json` carries `metadata.model` (gate satisfied). Beads (`br`) is not installed; the beads steps are skipped.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 4 |
| Low | 11 |

Excluded (speculative, low-confidence highs): 0. Review trailer `excluded`: 0 → `excluded_confirmed`: 0.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Host-side git on an agent-writable `.git` executes sandbox-planted hooks and config commands on the host

**Severity:** HIGH (confidence: high — mechanism reproduced; exploitation needs the agent, or content that steers it, to write into `sandbox/.git`)
**File:** `head/evals/harness/pipeline-run.sh:783` (also `:784`, `:787`; the wrapper at `:446-449`)
**Issue:** `sgit` is
```bash
env -i PATH="$PATH" HOME="$META" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C \
  git -C "$WS" "$@"
```
and after every IMPLEMENT/FIX phase `run_phase` calls `sgit add -A`, `sgit commit -q --allow-empty -m "snapshot $label"` and `sgit bundle create …` (`:783-787`). `$WS/.git` sits inside `/workspace`, the read-write bind mount the agent session owns (`:689`), so the agent (running `--dangerously-skip-permissions` with `Bash`, `:651-653`) or any `.claude/` hook of the mounted tree can write `sandbox/.git/hooks/pre-commit`, `sandbox/.git/config` (`core.fsmonitor`, `core.hooksPath`, `filter.*.clean`, `gpg.program` with `commit.gpgsign=true`) before the host-side commit. `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_NOSYSTEM` suppress the global and system files only; repo-local config and `.git/hooks` are read as usual.
**Reproduced here** (git 2.39.5): a repo with `.git/hooks/pre-commit` touching a marker and `core.fsmonitor` set to a `touch` command, then exactly the `sgit` environment running `git add -A` and `git commit --allow-empty`: both markers were created on the host.
**Impact:** Code execution on the operator host as the operator (`--user "$(id -u):$(id -g)"` means the host uid; the operator's `~/.codex/auth.json`, `~/.aws`, SSH keys and the batch results are all reachable), bypassing `--read-only`, `--pids-limit`, `--memory` and the two-mount rule (DEC-0411) that exist to contain exactly this agent. Review-catch fixtures carry third-party PR text, so the steering content need not be the operator's own.
**Fix:** Never run git on the host against a `.git` the sandbox can write. Either keep the snapshot repository outside the mount — `git --git-dir="$META/snap.git" --work-tree="$WS"` for init/base/add/commit/bundle (and give the sandbox its own `.git` for the gates' `git diff $BASE_COMMIT`, created from the same base) — or, at minimum, pass explicit overrides on every `sgit` call: `-c core.hooksPath=/dev/null -c core.fsmonitor=false -c commit.gpgsign=false -c core.sshCommand=false` and clear filter/diff drivers, as `tools/fresh-mount-proof.sh:92-96` already does with `GIT_CONFIG_KEY_1=core.hooksPath`. Prefer the separate `--git-dir`: an allowlist of config keys is a moving target. Add a bats case that plants a `pre-commit` hook in the stub sandbox and asserts it did not run.
**Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html; CWE-250 — https://cwe.mitre.org/data/definitions/250.html; OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [HIGH-002] jq keyword `label` breaks the executor, the mount library and the row builder on jq 1.6 (review §1, confirmed)

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/pipeline-run.sh:702` (also `:816`, `:881`), `head/evals/harness/lib/sandbox-mount.sh:462-467`, `head/evals/harness/ablation-row.sh:285`
**Issue:** `jq -n --arg label "$label" … '{label: $label, …}'` and the shorthand `{name, label, …}`. `label` is a jq reserved word; jq 1.6 (Debian 12 bookworm — the lineage `Dockerfile.ablation:22` pins — and Ubuntu 22.04) rejects both. Reproduced on this host:
```
$ jq -nc --arg label x '{l: $label}'
jq: error: syntax error, unexpected label, expecting IDENT or __loc__
$ echo '{"label":1}' | jq -c '{label}'
jq: error: syntax error, unexpected '}', expecting ':'
```
Under `set -e` the argv capture at `:702` aborts `run_phase` and every run ends `infrastructure_error` before its first phase; `write_sandbox_grimoire` returns 2 for every mounted arm (`sandbox-mount.sh:468-469` → `pipeline-run.sh:488`); `ablation-row.sh` exits 3 (undocumented) for every `--run-dir`. CI runs on `ubuntu-latest` (jq 1.7.1) and cannot see it. The repository declares no jq minimum.
**Fix:** Rename the bindings (`--arg lbl "$label"` / `$lbl`) at `pipeline-run.sh:702, 816, 881` and `sandbox-mount.sh:462`; expand `ablation-row.sh:285` to `label: .label`. Add a CI leg on `ubuntu-22.04` or a bats case that runs one program from each script under a jq 1.6 binary when present.
**Reference:** jq 1.7 changelog, "Allow keywords to be used as binding name and in object construction".

### [HIGH-003] preflight's integrity count is an index count and no longer sees the disk (review §2 + dissent DISS-C-003, confirmed)

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/preflight.sh:189-191` (fallback `:195-197`, decision `:199-214`)
**Issue:**
```bash
ACTUAL_COUNT=$(git -C "${MANIFEST_TREE}" ls-files -- .claude \
    | awk '!/^\.claude\/overrides\// && $0 != ".claude/checksums.json"' | wc -l | tr -d ' ')
```
`git ls-files` counts index entries. Deleting a tracked hook from the working tree (`rm .claude/hooks/<gate>.sh`) does not change it, and neither does planting an untracked file under `.claude/` (a new skill or command is auto-discovered by the CLI). Both cases change the pre-PR `find … -type f` count, which now runs only when the tracked count is zero. The manifest is itself generated from `git ls-files` (`tools/gen-checksums.sh:102`), so index-vs-manifest is a tautology for the one thing a count can detect. In `integrity_enforcement: strict` this is the only fence that exits non-zero before an operation.
**Fix:** Count tracked paths that exist (`[[ -f "$MANIFEST_TREE/$p" ]]` filter, or subtract `git ls-files --deleted -- .claude`) and add the untracked set (`git ls-files --others --exclude-standard -- .claude`) to the comparison, or do the sha256 verification the comment at `:175` already concedes is the real check. Bats cases: delete one tracked file → warning and `exit 1` under strict; plant one untracked file → same.
**Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [HIGH-004] `not-mounted` in a submodule mount cannot distinguish a never-linked path from a removed link (review §3 + dissent DISS-C-001, confirmed)

**Severity:** HIGH (confidence: medium — requires a submodule mount; the design is as the comment at `:47-55` describes)
**File:** `head/.claude/scripts/check-loa.sh:75-76` (summary `:83-85`)
**Issue:**
```bash
elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]; then
  not_mounted=$((not_mounted + 1))
```
Every path the mount links exists under `.loa/` by construction, so in a submodule mount deleting any linked hook, rule or script is counted as informational `not-mounted` and the run prints `Integrity verified` with exit 0, where it was `Missing` (fail) before. `mount-submodule.sh` logs `Linked: …` lines (`:908-965`) but persists no link set, so the classifier has nothing to compare against; the summary prints a count, not the paths. The only tamper signal left in that mode is a hash mismatch on a file that is still present.
**Fix:** Persist the linked set at mount time (`.loa-version.json` `linked: [...]` or `.claude/.mount-links`) and classify an absent path as `Missing` when it is in that set, `not-mounted` otherwise. Until then print the not-mounted paths and add a `check-loa-mount-scope.bats` case that removes a linked file and asserts a failure.
**Reference:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html; OWASP ASVS V14.2 — https://owasp.org/www-project-application-security-verification-standard/

---

## Medium/Low Priority Issues

### [MED-001] Operator credential copies in the run directory outlive the run when the driver is killed
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:569-571` (cleanup `:348`, `:356`; header `:104-106`)
- **Issue:** `make_home` copies `$CREDS_HOME/.codex/auth.json` and `config.toml` (the operator's codex OAuth tokens) into `<run>/meta/home/.codex/`, which is then bind-mounted read-write at `/home/evaluser` (`:690`). Removal happens only in `finish` and the EXIT trap. The header itself plans for a SIGKILLed driver (`:105-106`, "rewritten with status running after each phase so a SIGKILLed driver leaves a record") and `ablation-row.sh` reads `running` as interrupted — in exactly that case the live token file stays in the run directory that the batch runner, the row builder and the freeze keep. The mount into the agent's HOME is the stated design (`:79-82`) and is not counted here, but it means the agent under test and every `.claude/` hook of the mounted tree can read the operator's codex token during the run.
- **Fix:** Create `meta/home` under a `mktemp -d` outside the run tree (or on `--tmpfs`) and bind-mount that, so an orphaned HOME is not archived with the run; have `run-arms.sh`/the batch runner sweep `meta/home` of any run with `status: running` at start; and surface `CREDS_HOME` copies in `pipeline.json` so an operator can see when they were made.
- **Reference:** CWE-312 Cleartext Storage of Sensitive Information — https://cwe.mitre.org/data/definitions/312.html; CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [MED-002] Exit-code taxonomy misclassifies OOM kills and docker-client failures (review Observation 4, confirmed)
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:857-862` (`--memory 4g` at `:688`)
- **Issue:** A phase exiting 137 before its timeout is `interrupted` (exit 4). Under `--memory 4g` a container OOM-kill is also 137, so an OOM'd run is excluded from the analysis (`ablation-2.0.yaml:83` excludes `interrupted`) instead of counted. A docker-client failure (exit 125: daemon down, bad flag) reaches `:862` as `agent_error "phase … exited 125"`, charging the arm for an infrastructure fault. The pre-registered rules depend on this taxonomy.
- **Fix:** Keep the container (`--cidfile`, drop `--rm`, remove after inspect) and read `docker inspect --format '{{.State.OOMKilled}}'`; map OOM → `agent_error`/`cap_failure`, 125 → `infrastructure_error`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-003] The per-turn spend watchdog switches itself off silently when pricing is unavailable (review Observation 5, confirmed)
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:586-588` (gate `:731`, record `:847`; header claim `:125-126`)
- **Issue:** `price_for` runs `$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py` with `2>/dev/null`; absent module, import error or an unknown alias yields `null`, the watchdog loop skips every poll (`:731`), and the only trace is `watchdog.priced: false` in the phase record. Nothing is printed. The header states "No .claude/ code is sourced" (`:125-126`) while this path executes `.claude/` Python from the harness's own tree. The post-phase cap check still applies, so the exposure is bounded by one phase's spend, not the run cap.
- **Fix:** Print one stderr warning per model when pricing resolves to null and add `priced` to `pipeline.json`'s summary; or ship the price table with the harness (`LOA_EVAL_PRICING_JSON` already exists) and drop the `.claude/` call. Correct the header.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [MED-004] Dead, unpinned build stage installs a crate that is not on crates.io (review Observation 3, confirmed; supply-chain angle added)
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/Dockerfile.ablation:19-20` (the file's own statement at `:82`)
- **Issue:** `FROM rust:1-bookworm AS brbuild` + `cargo install beads_rust --version 0.2.6` is never `COPY --from`'d. Under BuildKit the stage is pruned; under the legacy builder (`DOCKER_BUILDKIT=0`) it runs, is unpinned (no digest, unlike `:22`), and resolves a crate name that `:82` says is not published. `cargo install` compiles build scripts of whatever that name resolves to, so a future registration of `beads_rust` on crates.io would execute third-party code on the image build host under the legacy builder. SIMPLICITY[delete].
- **Fix:** Remove lines 19-20.
- **Reference:** CWE-829 — https://cwe.mitre.org/data/definitions/829.html; OWASP A08:2021 Software and Data Integrity Failures — https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/

### [LOW-001] Host-side reads of sandbox paths follow symlinks
- **File:** `head/evals/harness/pipeline-run.sh:773-777` (also `:713`, `:715`, `:793-794`)
- **Issue:** After each phase the host copies `$WS/.eval/model-invoke.jsonl`, `$WS/.eval/cost-ledger.jsonl` and `$WS/grimoires/loa/a2a/sprint-1/adversarial-*.json` into `eval/` with `cp`, and `gate_verdict` reads the feedback files with awk. All of these resolve symlinks the agent may have planted, so the content of any operator-readable host file can be copied into `eval/` (archived with the run and read by graders) or parsed as the verdict. Low impact on its own; it is the second sandbox→host read primitive after HIGH-001.
- **Fix:** `[[ -f "$p" && ! -L "$p" ]]` before each read, `cp --no-dereference` / `-P`, or copy through the container.
- **Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

### [LOW-002] The row builder and the took-effect prover trust an agent-writable dissent envelope first (dissent DISS-C-004)
- **File:** `head/evals/harness/ablation-row.sh:201-202`; `head/evals/harness/took-effect.sh:87-88`
- **Issue:** `envelope()` reads `sandbox/grimoires/loa/a2a/sprint-1/adversarial-<gate>.json` and only falls back to `eval/`. `degraded`, `degraded_reason`, `voices_run` (row) and `one_voice_planned` (took-effect) derive from it, while both headers say sandbox content is never trusted for `arm` (`ablation-row.sh:11-12`) and evidence is "never from what the agent said" (`took-effect.sh:8-10`). The `eval/` copy is a phase-end snapshot of the same file, so the fix is to read `eval/` and have the executor record its hash in the phase record.
- **Fix:** Prefer `eval/`; record `sha256` of each copied envelope in `phases[]`; refuse sandbox reads in both readers.

### [LOW-003] `zone_violations.dot_claude_writes` sees Write/Edit tool inputs only (dissent DISS-C-005)
- **File:** `head/evals/harness/ablation-row.sh:216-220`
- **Issue:** A `Bash` write (`echo >`, `sed -i`, `git checkout`) into `.claude/` is not recorded, so an arm that removes guardrails can report zero zone violations. `integrity_clean` (took-effect) covers the hash side only when the manifest is regenerated.
- **Fix:** Add a filesystem delta of `sandbox/.claude` against the post-mount manifest to the row.

### [LOW-004] Placeholder pricing feeds spend estimates with no marker (dissent DISS-C-007; review)
- **File:** `head/.claude/defaults/model-config.yaml:143-149`; `cli_model` switch at `:240`
- **Issue:** `gpt-6.1-sol` copies gpt-5.5 list prices as an acknowledged placeholder and the codex-headless hop now prices every estimate through it; rows and ledgers carry no flag that the cost is unconfirmed.
- **Fix:** `pricing_confirmed: false` on the entry, surfaced in MODELINV rows; close the bead named in the comment.

### [LOW-005] Fingerprint depends on one operator's dotfiles path and on the first line of merged stderr (review; dissent DISS-C-006)
- **File:** `head/evals/harness/fingerprint.sh:52-54`, `:62-63`
- **Issue:** The bats fallback is `~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`; other hosts read `bats=absent` and get a different digest for a non-toolchain reason. `tool_version` keeps line 1 of `2>&1`, so an update notice flips the digest.
- **Fix:** Drop the hard-coded fallback; prefer stdout, fall back to stderr only when stdout is empty.

### [LOW-006] Readers duplicate executor constants
- **File:** `head/evals/harness/ablation-row.sh:201`, `head/evals/harness/took-effect.sh:87`, `:96-105`
- **Issue:** `sprint-1` is hard-coded while `pipeline-run.sh:132` owns it as `SPRINT`; `expected_labels` re-implements `plan_phases` (`pipeline-run.sh:215-227`). Either drifts silently.
- **Fix:** Record `sprint` and the planned labels in `pipeline.json` and read them.

### [LOW-007] Change-set completeness (review Observation 2; confidence: low)
- **File:** `head/evals/tests/took-effect.bats:18` (also `ablation-row.bats:19`); `head/.github/workflows/bats-tests.yml:176-178`
- **Issue:** `cp -a "$FX/runs"` needs `evals/tests/fixtures/ablation-runs/runs/`, which is not in the diff; the new CI gate `gen-checksums.sh --check` needs `.claude/checksums.json` to match five changed tracked files and the manifest is not in the diff either. In this workspace the manifest hashes do match the head files (checked for `preflight.sh` and `check-loa.sh`), so the frozen diff most likely omits generated files.
- **Fix:** Confirm both are in the committed change.

### [LOW-008] Header drift and dead code
- **File:** `head/evals/harness/pipeline-run.sh:85` (codex 0.137.0 vs `Dockerfile.ablation:25` 0.162.1); `:618` (`in_container_path` unused)
- **Fix:** Correct the header; delete the function.

### [LOW-009] `ms()` accepts `…Z` timestamps only and aborts with an undocumented exit (review)
- **File:** `head/evals/harness/ablation-row.sh:230`
- **Issue:** An offset timestamp makes `fromdateiso8601` fail and the whole `jq -n` exits 5, outside the documented 0/1/2.
- **Fix:** Wrap the row build in `|| usage`, or normalise offsets.

### [LOW-010] Suite file ships a literal placeholder for `source_commit`
- **File:** `head/evals/suites/ablation-2.0.yaml:25`
- **Issue:** `source_commit: "<sprint-258-commit>"` is read by the batch runner and the freeze as the pinned identity; a run started before the lead edits it records a non-commit as its provenance.
- **Fix:** Make the readers refuse a value that is not 40 hex characters.

### [LOW-011] `run_phase` is 235 lines (review Observation 6)
- **File:** `head/evals/harness/pipeline-run.sh:634-868`
- **Issue:** Launch, watchdog, reaping, record, snapshot, verdict and accounting in one function; `apply_arm_toggles` (`sandbox-mount.sh:255-373`) is 118 lines. The HIGH-001 fix lands in this body; split it first.
- **Fix:** `launch_phase` / `watch_phase` / `record_phase` / `account_phase`.

---

## Cross-Model Security Observations

Security dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — primary gpt-5.5-pro (answered by codex-headless) returned `status: clean` with no findings; companion claude-headless returned seven (4 MEDIUM, 3 LOW); `verdict_quality.voices_succeeded` 2/2, `companion_voice.independent: true`, `rejected_count` 0, `hallucination_filter.downgraded` 0. Not degraded.

| ID | Voice | Disposition |
|----|-------|-------------|
| DISS-C-001 `not-mounted` hides removed links (MEDIUM) | claude-headless | Confirmed by cross-model review → HIGH-004 |
| DISS-C-002 `check_integrity` ends `return 0` (MEDIUM) | claude-headless | Not a defect: `fail` increments `FAILURES` (`check-loa.sh:36`), `main` exits 1 on it (`:603-605`); the `return 0` keeps `set -e` from aborting the `&&` chain at `:86` |
| DISS-C-003 preflight count ignores untracked files; symlinked manifest points git at another tree (MEDIUM) | claude-headless | Part 1 folded into HIGH-003 (addition case). Part 2 speculative: it needs write access to `.claude/checksums.json` in the checkout, which already implies control over everything preflight protects, and a nested `.git` cannot arrive through a clone; not recorded |
| DISS-C-004 row fields from a sandbox envelope (MEDIUM) | claude-headless | Verified → LOW-002 (the `eval/` copy is a snapshot of the same agent-side file; severity reduced accordingly) |
| DISS-C-005 `dot_claude_writes` misses Bash writes (LOW) | claude-headless | Verified → LOW-003 |
| DISS-C-006 fingerprint runs env-chosen binaries and a hard-coded `$HOME` path (LOW) | claude-headless | Path/stderr part → LOW-005; the "planted executable" part crosses no trust boundary (it needs write access to the operator's HOME) |
| DISS-C-007 placeholder pricing feeds caps (LOW) | claude-headless | Verified → LOW-004 |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | ids, labels, caps, timestamps regex-checked; leak guards; symlink follow (LOW-001) |
| SEC-AZ Authorization / isolation | 2 | HIGH-001 host-side execution from the sandbox; HIGH-003/004 fences weakened |
| SEC-CI Confidentiality / Integrity | 3 | env-only secrets, masked captures; MED-001 credential copies at rest; manifest tooling solid |
| SEC-IN Injection Prevention | 3 | no `eval`, jq `--arg` everywhere; git config/hook execution is the one unparameterised sink |
| SEC-AV Availability / spend | 3 | run cap, watchdog, `--max-usd`; MED-002/003 |
| Architecture | 3 | clean library boundary; readers duplicate executor constants; `run_phase` monolith |
| Code Quality | 3 | thorough headers and bats; jq 1.6 defect ships green from CI |
| DevOps | 3 | digest-pinned base, yq sha256; dead unpinned stage; single-runner CI |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (tokens by name only; captures record `<set>`)
- [x] Input validation at trust boundaries (arm ids, sprint labels, task ids, numeric caps, timestamps)
- [ ] Containment boundary intact — **no**: HIGH-001 (host git on sandbox `.git`); LOW-001 (symlink follow)
- [ ] Integrity checks — **weakened**: HIGH-003 (preflight count), HIGH-004 (`not-mounted`)
- [x] No injection paths in the scripts themselves (no `eval`; jq `--arg`; prompts via argv)
- [ ] Credential lifetime bounded — partial: MED-001 (copies survive a killed driver)
- [x] Dependencies pinned — base image by digest, yq by sha256; dead unpinned stage (MED-004)
- [x] Error messages do not leak secrets
- [ ] Tests cover security paths — no test plants a hook, deletes a tracked `.claude/` file, or runs on jq 1.6

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist in this workspace (frozen evaluation; the PR description is the only report). Verified manually against the script headers: each new script documents its contract and exit codes; drift found at `pipeline-run.sh:85` (version) and `:125-126` (the "no .claude/ code" claim vs `price_for`), both recorded above. The `.loa-version.json` bump to 2.0.0-rc.5 and the `CLAUDE.loa.md` managed-header version are consistent. Scope limit: `mount-submodule.sh` (unchanged by the PR) was read only for whether it persists a link set.

---

## Next Steps

**CHANGES_REQUIRED:**
1. HIGH-001: move the snapshot repository out of the sandbox (`--git-dir` under `meta/`) or harden every `sgit` call with `core.hooksPath` / `core.fsmonitor` / `commit.gpgsign` overrides; add the planted-hook bats case.
2. HIGH-002: rename the jq `label` bindings in three files; add a jq 1.6 CI leg.
3. HIGH-003 / HIGH-004: restore on-disk detection in `preflight.sh`; persist the mount's linked set and fail on a removed link in `check-loa.sh` (or record the accepted threat as a NOTES Decision Log entry and print the paths).
4. Address MED-001 … MED-004; address or explicitly defer the LOWs.
5. Run `/implement sprint-1` to fix, record the bats results in `reviewer.md` under `## AC Verification`, then re-run `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":4,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:58:00Z"} -->
