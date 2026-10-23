# Sprint 1 Security Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Scope:** the pull request in `pr/` (72 files; `pr/head.diff` base to head) — sprint-258: mount integrity (#1267), spend caps, the ablation suite and arms, the container pipeline executor, rows and took-effect evidence, smoke
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable) over the `pr/head/` tree, with the review feedback and the two-voice adversarial dissent as inputs. Citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Executive Summary

The change is well structured and its secret handling is sound: the Bedrock bearer token travels by environment only, the docker client forwards it by name (`-e AWS_BEARER_TOKEN_BEDROCK`), captures record it as `<set>`, the sandbox git runs under `env -i`, and every embedded Python runs with `-I`. The new mount-integrity tools (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`) are NUL-safe, refuse unrepresentable paths, and pass their suites here.

The change cannot merge as is. Five high findings: (1) the new `not-mounted` outcome in `check-loa.sh` makes `Missing` unreachable in a submodule mount, so a deleted hook, rule or the whole `.claude/scripts` link passes integrity with exit 0, and the `-d .loa/.claude` probe lets any checkout be flipped into that lenient mode; (2) and (3) `pipeline-run.sh` and `ablation-row.sh` use the jq reserved word `label` as a variable and shorthand key, a syntax error on jq 1.6 (the toolchain the PR's own `Dockerfile.ablation` pins) — reproduced here: 39 of 52 `pipeline-run.bats` cases fail and no row can be built; (4) the fixture run directories that `took-effect.bats` and `ablation-row.bats` copy in `setup()` are not part of the change, so the CI step the PR adds is red on checkout; (5) `took-effect.sh`'s `integrity_clean` rule records the mount-time manifest hash but never enforces it, so an agent that edits `.claude/` and regenerates `checksums.json` is reported clean.

Observed test results on a scratch copy of the head tree (exec bits restored from the diff's `100755` modes; `TMPDIR` off the noexec `/tmp`; this host: jq 1.6, bats 1.13.0):

| Suite | Result |
|-------|--------|
| `tests/unit/check-loa-mount-scope.bats` (CM-1…CM-6) | 6 / 6 pass |
| `tests/unit/gen-checksums.bats`, `check-manifest-paths.bats` | 11 / 14 pass; GC-7, MP-7 need a temp dir outside a git repo and MP-6 needs the repository's committed manifest — neither exists in this environment (environmental, not defects) |
| `evals/tests/spend.bats` | 6 / 6 pass |
| `evals/tests/pipeline-run.bats` | 13 / 52 pass; every failing case dies in `run_phase` with `jq: error: syntax error, unexpected label, expecting IDENT` |
| `evals/tests/took-effect.bats`, `ablation-row.bats` | 0 / 39: `setup()` fails, `fixtures/ablation-runs/runs/` absent |
| `arm-toggles.bats`, `run-arms.bats`, `validate-suite.bats`, `freeze.bats` | not run: they need `evals/fixtures/review-prs`, `evals/tests/fixtures/claude-stub.sh` and the smoke tasks, which are outside the change set and absent from this workspace |

**Overall Risk Level:** HIGH

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 7 |
| Low | 10 |

**Verdict:** CHANGES_REQUIRED

### Process notes

- Phase 0 prerequisite: `engineer-feedback.md` carries `CHANGES_REQUIRED`, not "All good". The audit ran anyway on the harness's explicit instruction (`/audit-sprint sprint-1`, autonomous). Findings below are independent of the review's; where they coincide it is said.
- Phase 1C dissent: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` completed (`grimoires/loa/a2a/sprint-1/adversarial-audit.json`): primary `gpt-5.5-pro`, companion `claude-headless` succeeded (`counted_as: independent_voice`), 5 findings, 0 rejected, `degraded: false`, `metadata.locality` null — not DEGRADED_SECURITY_REVIEW.
- Documentation audit: no `documentation-coherence-*` reports exist in this environment (`grimoires/loa/a2a/subagent-reports/` absent); the PR description stands as the implementation report. Scope limit recorded; the header-versus-code mismatches found by reading are listed as findings.
- `.claude/checksums.json` and the tracked `.claude/` tree are not present in this workspace's git history (`git ls-files .claude` is empty), so the new CI gate `check-manifest-paths.sh` + `gen-checksums.sh --check` could not be exercised against the real manifest. Unable to assess whether the committed manifest passes the gate the PR adds.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.6/5 | IV:4 AZ:4 CI:2 IN:4 AV:4 |
| Architecture | 3.6/5 | MO:4 SC:4 RE:3 CX:3 ST:4 |
| Code Quality | 3.2/5 | RD:4 TC:1 EH:4 TS:3 DC:4 |
| DevOps | 3.2/5 | AU:2 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | — |
| **Overall** | **3.4/5** | Security weighted highest |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-23/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Merge)

### [HIGH-001] `not-mounted` makes `Missing` unreachable in a submodule mount; lenient mode is opt-in by directory

**Severity:** HIGH | **Confidence:** high
**Component:** `head/.claude/scripts/check-loa.sh:64`, `head/.claude/scripts/check-loa.sh:75-76` (behaviour pinned by `head/tests/unit/check-loa-mount-scope.bats:56-64`)
**Criterion:** SEC-CI: Confidentiality/Integrity

**Reasoning Trace:**
> In a submodule mount `.claude/checksums.json` is a symlink into `.loa/.claude/checksums.json` (mount-submodule.sh's symlink list), i.e. the manifest is the upstream's and every path it lists exists under `.loa/`. The new branch is taken for every absent path:
> ```
> [[ -d ".loa/.claude" ]] && submodule_mount=true            # :64
> …
> elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]; then
>   not_mounted=$((not_mounted + 1))                           # :75-76
> ```
> so `fail "Missing: $file"` (:78) can never fire for a manifest path in a submodule mount. `.claude/hooks/` is the mount's COPY set (#842) and `.claude/scripts`, `.claude/protocols`, `.claude/data` are directory symlinks: `rm .claude/hooks/safety/block-destructive-bash.sh`, or `rm .claude/scripts` (the link), leaves every affected path "exists upstream, absent locally" and the check prints `Integrity verified`, exit 0. The dissent (DISS-C-001) adds that the probe is only `-d .loa/.claude`: in a standard-mode checkout, `mkdir -p .loa/.claude && cp -a .claude/. .loa/.claude/` flips the check into the lenient mode without a submodule.

**Description:** The three-outcome classification cannot distinguish "never linked by design" from "linked, then deleted"; both read as not-mounted and never change the exit code.
**Impact:** The System Zone integrity self-check — the only detector for Bash-path deletions of fence scripts, which CLAUDE.loa.md names as an accepted fence gap — reports clean after a hook, rule, gate or the entire scripts tree is removed. In the mount mode #1267 exists to make trustworthy.
**Proof of Concept:**
```
# in a fresh submodule mount (tools/fresh-mount-proof.sh --keep gives one)
rm .claude/scripts            # the directory symlink
bash .claude/scripts/check-loa.sh   # (run upstream's copy) → "not-mounted: N path(s)…", "Integrity verified", exit 0
```
**Remediation:** Record what the mount linked (mount-submodule.sh owns the manifest of symlinks and the copy set; write it beside the checksums or derive it from `.loa/.claude` paths that have a sibling link) and treat only paths outside that set as not-mounted; a linked path now absent stays `Missing`. At minimum fail on any absent path under `.claude/hooks/`, `.claude/rules/`, `.claude/scripts/`, `.claude/protocols/`. Require the submodule probe to be a real gitlink (`git ls-files --stage -- .loa` shows mode `160000`, as `aleph_check_submodule_head_is_authorized` already does at :134-136), not `-d .loa/.claude`. Update CM-1 to the new semantics and add a case for a deleted linked path.
**References:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html ; CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [HIGH-002] `pipeline-run.sh` uses the jq reserved word `label`: every phase dies on jq 1.6

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/pipeline-run.sh:702-710` (also `:816-826`, `:881-882`)
**Criterion:** CQ-TC: Test Coverage / ARCH-ST: Standards Compliance

**Reasoning Trace:**
> `jq -n --arg label "$label" … '{label: $label, …}'` (:702, :708). `label` is a jq keyword; jq 1.6 rejects `$label` ("unexpected label, expecting IDENT or __loc__") and jq 1.7 relaxed it, which is why the author's host passed. Reproduced here (`jq-1.6`): `jq -n --arg label x '{label: $label}'` fails; `jq -n --arg lbl x '{"label": $lbl}'` works. Under `set -e` the argv-capture assignment aborts `run_phase`, `on_exit` writes `status: infrastructure_error, reason: driver aborted (rc 3)` and no phase runs. `evals/tests/pipeline-run.bats`: 13 / 52 pass, the 39 failures all carry this error; the 13 that pass are the dry-run, refusal and leak-guard paths that never reach a phase.

**Description:** The executor cannot complete a single phase on the stock Debian bookworm / Ubuntu 22.04 toolchain. `Dockerfile.ablation` (`head/evals/harness/Dockerfile.ablation:22,32`) pins bookworm and installs its `jq` (1.6) as the reference image; the harness never runs on it.
**Impact:** The sprint's central deliverable is inoperable on its own pinned toolchain; `regen.sh` produces fixture runs with `"phases":[]`.
**Remediation:** Rename the variable (`--arg lbl "$label"` / `$lbl`) at `:702`, `:708`, `:816`, `:826`, `:881`, `:882` and write the key explicitly (`"label": …`). Add a jq-1.6 guard (`jq -n '{label: 1}'`-style self-test at startup, or run `bats evals/tests/` in CI inside the ablation image).
**References:** CWE-710 Improper Adherence to Coding Standards — https://cwe.mitre.org/data/definitions/710.html

### [HIGH-003] `ablation-row.sh` shorthand key `label` is a jq 1.6 syntax error: no row is ever written

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-row.sh:285`
**Criterion:** CQ-TC: Test Coverage

**Reasoning Trace:**
> `phases: [ $phases[] | {name, label, session_id, …} ]` — `{name, label}` fails on jq 1.6 ("unexpected '}', expecting ':'"; reproduced). The `ROW=$(jq …)` assignment at `:224` fails under `set -e`; nothing is appended to `--out`. Every row-building case of `ablation-row.bats` would fail here independently of the missing fixtures (HIGH-004).

**Description:** Same root cause as HIGH-002 in the §3.1 row builder.
**Impact:** A batch on jq 1.6 ends with an empty `runs.jsonl`; `spend.sh` then under-counts the cycle's spend (run rows are a term of the total), so the spend cap this sprint introduces is blind to the runs.
**Remediation:** `"label": .label` at `:285`.
**References:** CWE-710 — https://cwe.mitre.org/data/definitions/710.html

### [HIGH-004] Fixture run directories required by two suites and the new CI step are not in the change

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/tests/took-effect.bats:18`, `head/evals/tests/ablation-row.bats:19`, `head/.github/workflows/bats-tests.yml:212-223`
**Criterion:** DO-AU: Automation / CQ-TC

**Reasoning Trace:**
> Both `setup()` functions `cp -a "$FX/runs" "$T/runs"` with `FX=evals/tests/fixtures/ablation-runs`. `head.diff` adds `ablation-runs/{MANIFEST.json,regen.sh,suite.yaml,tasks/…,prs/…}` but no `ablation-runs/runs/` entry; `MANIFEST.json`'s `arm_map` names ten run ids whose directories do not exist. `regen.sh:86-89` says the runs are tracked ("the fixtures on disk equal the fixtures a checkout carries"). Observed: all 21 + 18 cases error in `setup`. The new workflow step runs `bats --print-output-on-failure evals/tests/` unconditionally.

**Description:** The took-effect rules and the §3.1 row schema — the sprint's evidence layer — have no runnable test, and the CI gate the PR adds is red on a fresh checkout (compounded by HIGH-002/003 on a jq-1.6 runner, where `regen.sh` cannot rebuild them either).
**Remediation:** After the jq fix, regenerate with `regen.sh` on jq 1.6 and commit `evals/tests/fixtures/ablation-runs/runs/`, or make `setup()` invoke `regen.sh` when `runs/` is absent. Verify `bats evals/tests/` from a clean clone before merge.
**References:** CWE-710 — https://cwe.mitre.org/data/definitions/710.html

### [HIGH-005] `took-effect.sh` `integrity_clean` records the manifest pin but does not enforce it

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/took-effect.sh:239-240`, `head/evals/harness/took-effect.sh:265-267`
**Criterion:** SEC-CI: Confidentiality/Integrity

**Reasoning Trace:**
> The rule reads `arm_evidence.manifest_sha256` from `meta/pipeline.json` (:239) — written by the driver at mount time (`pipeline-run.sh:492-493`), outside the agent-writable sandbox — and hashes `sandbox/.claude/checksums.json` (`sha(man)` in the Python walk, :260). Then:
> ```
> EVID="$n manifest entries verified; manifest_sha256 ${msha:0:12}"
> [[ "$filesha" == "$msha" ]] && EVID="$EVID (matches checksums.json)"   # :265-266
> return 0                                                                # :267
> ```
> A mismatch only drops the parenthetical; the rule still returns OK. Every entry is verified against the manifest *as it now stands in the sandbox*, which the agent can rewrite (Bash is in `TOOLS_DEFAULT`, `pipeline-run.sh:133`; the sandbox carries `.claude/scripts/update.sh` whose `generate_checksums` rewrites exactly this file). `ablation-row.sh`'s `zone_violations.dot_claude_writes` (:208-222) sees only Write/Edit tool_use events, not Bash writes, so this rule is the only detector for a Bash-path edit of the mount.

**Description:** An agent (or a Loa script it invokes) that edits a hook, rule or skill under `.claude/` and regenerates `checksums.json` — or writes a one-entry manifest — satisfies `integrity_clean` for every arm that lists it (all eight).
**Impact:** The pre-registered took-effect evidence (DEC-0418: a miss is `infrastructure_error` and pauses the arm) reports a tampered mount as clean; the ablation's per-arm conclusions rest on it.
**Remediation:**
```bash
# took-effect.sh, replace :265-266
[[ "$filesha" == "$msha" ]] || { EVID="sandbox checksums.json sha256 ${filesha:0:12} differs from the recorded manifest_sha256 ${msha:0:12}"; return 1; }
EVID="$n manifest entries verified; manifest matches recorded manifest_sha256 ${msha:0:12}"
```
Add a bats case that rewrites the sandbox manifest and expects FAIL.
**References:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html ; CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

---

## Medium Priority Issues

### [MEDIUM-001] Preflight count now ignores untracked additions and deleted files

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/scripts/preflight.sh:189-191`
**Criterion:** SEC-CI
**Issue:** `ACTUAL_COUNT` is `git ls-files -- .claude | …` — tracked paths only. The pre-change `find` count moved on any file added to `.claude/` (a planted helper, an extra hook) and on any deletion; the new count moves on neither (a tracked file deleted from the working tree is still listed). Both signals are lost together (dissent DISS-C-002; the review's DISS-001 is the deletion half). `check-loa.sh` hashes manifest-listed files only, so additions to the System Zone are now detected by nothing.
**Remediation:** Filter with `[[ -f ]]` as `tools/gen-checksums.sh:96` does for deletions, and keep a second `find`-based count (or compare the two) so an untracked addition still warns.
**References:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [MEDIUM-002] The mount library executes the sandbox's own `.claude/` script on the host

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/lib/sandbox-mount.sh:511-514` (claims at `:75`, `:97-99`; `head/evals/harness/pipeline-run.sh:125-126`)
**Criterion:** ARCH-ST / SEC-IN
**Issue:** `init_sandbox_beads` runs `PROJECT_ROOT="$ws" bash "$ws/.claude/scripts/beads/update-beads-state.sh" --opt-out …` — a script from the tree under evaluation — on the host, outside the container, while the header states "no harness script sources .claude/ code (eval.yml 'Validate grader trust boundary')". The trust-boundary test (`pipeline-run.bats`, case 12) greps for `source` lines only and cannot see `bash <path>`.
**Remediation:** Write the opt-out marker JSON from the library itself (a small fixed document), or run the step inside the container as part of the first phase. Extend the trust-boundary test to `bash|sh|python3 … .claude/`.
**References:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html

### [MEDIUM-003] Beads initialised by the HOST's `br`, while the container has none

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/lib/sandbox-mount.sh:504-509`, `head/evals/harness/Dockerfile.ablation:82-84`
**Criterion:** ARCH-ST
**Issue:** The Dockerfile comment assumes the materialiser writes the opt-out marker because `br` is absent from the image; but `init_sandbox_beads` runs on the host (`pipeline-run.sh:489`) and takes the host's `br` when on PATH, leaving a `.beads/` database and `beads=br` evidence in a sandbox whose container cannot run `br`. Arms then differ by the operator's host, against "every arm runs the skills' markdown fallback alike".
**Remediation:** In container mode set `LOA_EVAL_BR_BIN` to a non-existent path (or pass the executor mode into `init_sandbox_beads`).
**References:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MEDIUM-004] Operator codex credentials are copied into the run directory and survive a SIGKILL

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:569-571` (cleanup `:307-311`, `:348`, `:356`)
**Criterion:** SEC-CI / DO-AC
**Issue:** `make_home` copies `$CREDS_HOME/.codex/auth.json` and `config.toml` (the operator's ChatGPT/OpenAI OAuth tokens) into `<run>/meta/home/.codex/`. Deletion is by the EXIT trap and `finish`; a SIGKILLed driver (the header's own "SIGKILLed driver leaves a record" case, `:104-106`) or a host crash leaves the tokens in `meta/`, which batch tooling archives and `regen.sh`-style copies carry along. The directory mode is 0700 but the file lives in the results tree.
**Remediation:** Mount the credentials read-only from a private per-run tmpfs or `mktemp -d` under `$XDG_RUNTIME_DIR`, not under the run directory; or mount `$CREDS_HOME/.codex` read-only as a third mount into `/home/evaluser/.codex` and keep `meta/home` for the session store only. Have the batch runner sweep `*/meta/home` before archiving.
**References:** CWE-312 Cleartext Storage of Sensitive Information — https://cwe.mitre.org/data/definitions/312.html ; CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html

### [MEDIUM-005] Whole ledgers passed as single `--argjson` arguments

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-row.sh:224-228`
**Criterion:** ARCH-RE
**Issue:** `--argjson minv "$MINV"` (the whole MODELINV ledger wrapped with line numbers), both envelopes, `pipeline.json` and the transcript tool-use list each travel as one argv string; Linux caps a single argument at 128 KiB (`MAX_ARG_STRLEN`). A full build run with two voices and repairs exceeds that, `jq` fails with E2BIG and the largest, most expensive runs lose their row (dissent, review DISS-C-004 confirmed).
**Remediation:** Pass files with `--slurpfile` / `--rawfile`.
**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MEDIUM-006] Exit 137 without a timeout is classified `interrupted`: OOM-killed phases vanish from the analysis

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:857-858`
**Criterion:** ARCH-RE
**Issue:** Under `--memory 4g` an OOM-killed phase also exits 137; with `timed_out=false` it becomes `interrupted` (exit 4), which the suite's `exclusion.statuses` (`head/evals/suites/ablation-2.0.yaml:83`) drops pairwise. OOM is the agent's account and should count as `agent_error`. `--rm` removes the container before `docker inspect` could read `OOMKilled`.
**Remediation:** Drop `--rm`, read `.State.OOMKilled` after `wait`, then `docker rm`; classify OOM as `agent_error`.
**References:** CWE-393 Return of Wrong Status Code — https://cwe.mitre.org/data/definitions/393.html

### [MEDIUM-007] Container `/tmp` is `noexec`

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:687`
**Criterion:** ARCH-RE
**Issue:** `--tmpfs /tmp:rw,size=1g` takes docker's defaults `nosuid,nodev,noexec` (confirmed on this host: `findmnt /tmp` → `rw,nosuid,nodev,noexec`). A task test command or fixture that executes a file from a hard-coded `/tmp` (bats run without `TMPDIR`, a helper script written to `/tmp`) fails with `Permission denied` and registers as `agent_error`, biasing the arm. The driver's `TMPDIR=/workspace/.eval/tmp` covers the common path only.
**Remediation:** `--tmpfs /tmp:rw,exec,size=1g`, or document the constraint in the task schema and have `validate-suite.sh` reject `/tmp` in `test_command`.
**References:** CWE-435 Improper Interaction Between Multiple Correctly-Behaving Entities — https://cwe.mitre.org/data/definitions/435.html

---

## Low Priority Issues

- **[LOW-001]** (confidence: high) `head/evals/harness/pipeline-run.sh:50` — header says `snapshots/index.json` carries `{IMPLEMENT|FIX1|FIX2: commit}`; `:788` lowercases the keys and `ablation-row.sh:324` reads them lowercase. Fix the comment. CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html
- **[LOW-002]** (confidence: medium) `head/evals/harness/pipeline-run.sh:840` — after `gate_recovered` resets `rc=0` (`:805`) the record keeps `is_error: true` from `$result.is_error` beside `exit: 0`; set `is_error` from the recovered state. CWE-393 — https://cwe.mitre.org/data/definitions/393.html
- **[LOW-003]** (confidence: high) `head/evals/harness/pipeline-run.sh:586` — pricing executes `.claude/adapters/loa_cheval/metering/pricing.py` from the harness root while `:125-126` states no `.claude/` code runs; it is the harness's own trusted copy, so say so in the comment or move the CLI under `evals/`. CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html
- **[LOW-004]** (confidence: medium) `head/evals/harness/pipeline-run.sh:506` — the arm-id leak grep scans the whole mounted `.claude/` tree and `.loa.config.yaml`; any future framework file mentioning an arm id refuses every run of that arm as `infrastructure_error`. Scope the scan to the fixture and grimoire paths. CWE-754 — https://cwe.mitre.org/data/definitions/754.html
- **[LOW-005]** (confidence: high) `head/evals/harness/fingerprint.sh:54` — a per-operator path (`$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats`) is the bats fallback, and `:62` folds stderr into the version line so update nags change the fingerprint. Drop the personal path; capture stdout only. CWE-710 — https://cwe.mitre.org/data/definitions/710.html
- **[LOW-006]** (confidence: medium) `head/.claude/defaults/model-config.yaml:140-146` — `gpt-6.1-sol` pricing is a copied placeholder, yet it is now the `codex-headless` hop's `cli_model` (`:240`) so every codex estimate and MODELINV cost row prices through it with `pricing_source: config`; nothing marks those rows provisional (dissent DISS-C-005). Add a `placeholder: true`/`price_date` marker surfaced in the row. CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html
- **[LOW-007]** (confidence: low) `head/.claude/scripts/preflight.sh:183-186` — when `.claude/checksums.json` is a symlink, its target is not validated to lie inside `PROJECT_ROOT` or `.loa/` before `git -C "$MANIFEST_TREE"` runs there (repository-local `core.fsmonitor`/hooks execute; dissent DISS-C-003). Requires an attacker who can already write the symlink. Check the resolved path is under `PROJECT_ROOT`. CWE-426 Untrusted Search Path — https://cwe.mitre.org/data/definitions/426.html
- **[LOW-008]** (confidence: medium) `head/evals/harness/ablation-row.sh:201-202` — the dissent envelopes are read from the agent-writable `sandbox/…/adversarial-*.json` first and from the eval-owned `eval/` copy only when absent; `voices_run`, `degraded` and `degraded_reason` derive from them (dissent DISS-C-004). Prefer `eval/` (the driver copies it at `pipeline-run.sh:776-778`). CWE-345 — https://cwe.mitre.org/data/definitions/345.html
- **[LOW-009]** (confidence: medium) `head/evals/harness/Dockerfile.ablation:19-20` — the `brbuild` stage is referenced by no `COPY --from`; it is dead under BuildKit and, by the file's own note at `:82` that beads_rust 0.2.6 is not on crates.io, fails the build under the classic builder. Remove it. CWE-710 — https://cwe.mitre.org/data/definitions/710.html
- **[LOW-010]** (confidence: low) `head/evals/harness/validate-suite.sh:295` requires `review_catch.fixture` under `evals/fixtures/`, while `head/evals/harness/pipeline-run.sh:441` also resolves task-dir and suite-root relative paths (the bats fixture `rc-01` uses `prs/pr-x`); the validator is the stricter reader, which is the safe direction, but a suite author will be surprised. Align the two. CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

---

## Observations

Nothing demoted. Every high above is tallied; none is marked speculative.

**Review demotions confirmed:** the review trailer records `excluded: 0`; confirmed — `excluded_confirmed: 0`.

**Positive observations:**
- Secret handling is correct end to end: `pipeline-run.sh:620-632` (env shim, `SECRET_KEYS`), `:694` (`-e NAME` only), `:705-706` (`<set>` in captures); `pipeline-run.bats` cases 29-31 pin it.
- `tools/gen-checksums.sh:89-102` and `tools/check-manifest-paths.sh:78-83` are NUL-safe, refuse newline/tab/backslash paths, and `mv -f` over a symlinked manifest replaces the link rather than writing through it (`gen-checksums.sh:136-137`).
- `tools/fresh-mount-proof.sh:91-99` runs git hermetically (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, empty `core.hooksPath`).
- Input validation at the trust boundaries is consistent: arm id regex (`sandbox-mount.sh:163`), task id (`:446`), sprint label (`:442`), fixture path rule (`:423-435`), `--max-run-usd` numeric (`pipeline-run.sh:186`).

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `metadata.rejected_count` is 0 in `adversarial-audit.json`; no `adversarial-rejected-audit.jsonl` sidecar rows exist.

## Cross-Model Observations

Two voices (primary `gpt-5.5-pro`, companion `claude-headless`, independent), 5 findings, all read against the code:

- DISS-C-001 (MEDIUM): not-mounted hides unlinked paths; `-d .loa/.claude` satisfiable anywhere — confirmed and escalated to HIGH-001 (the Missing branch is unreachable for every manifest path in a submodule mount).
- DISS-C-002 (MEDIUM): preflight count blind to untracked additions — confirmed, MEDIUM-001.
- DISS-C-003 (LOW): unvalidated symlink target before `git -C` — confirmed, LOW-007.
- DISS-C-004 (LOW): envelopes read from the agent-writable sandbox first — confirmed, LOW-008.
- DISS-C-005 (LOW): placeholder pricing drives the codex hop — confirmed, LOW-006.

The review's seven dissent items (adversarial-review.json) were re-read: DISS-C-002 there (`return 0` in `check_integrity`) is not a defect — `fail` increments `FAILURES` (`head/.claude/scripts/check-loa.sh:36`) and `main` exits 1 on the counter (`:603-605`), verified by CM-2/CM-3 passing here.

---

## Security Checklist

- [x] No hardcoded secrets or credentials in the change (bearer token by env and name only; `<set>` in captures)
- [x] Input validation at trust boundaries (arm/task/sprint regexes, fixture path rule, leak guards, numeric caps)
- [ ] Integrity check soundness — HIGH-001, HIGH-005, MEDIUM-001
- [x] No injection paths (no `eval`; no variable `source` lines; `python3 -I` for every embedded script; `env -i` for sandbox git)
- [ ] Trust boundary as documented — MEDIUM-002, LOW-003
- [ ] Credentials never persisted in artefacts — MEDIUM-004
- [x] Error messages do not leak the bearer token (`pipeline-run.bats` cases 29-31)

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Report each defect with file and line | Done | 22 findings cited `head/<path>:<line>` |
| Merge verdict | CHANGES_REQUIRED | 5 high, 0 critical |

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 7 |
| Low | 10 |

## Verdict

**CHANGES_REQUIRED** — five high findings (one-way rule: critical + high > 0).

## Next Steps

1. Rename the jq `label` variable/key in `pipeline-run.sh` and `ablation-row.sh`; run `bats evals/tests/pipeline-run.bats` on jq 1.6 (inside `loa-ablation:258`).
2. Regenerate and commit `evals/tests/fixtures/ablation-runs/runs/`; run `bats evals/tests/` from a clean clone.
3. Make `check-loa.sh` distinguish linked-then-deleted from never-linked, gate the lenient mode on a real gitlink, and update CM-1.
4. Enforce the recorded `manifest_sha256` in `took-effect.sh` `integrity_clean`; add the tamper case.
5. Address the medium items (preflight count, host execution of sandbox `.claude/` code, host `br`, credential copy location, `--slurpfile`, OOM classification, tmpfs `exec`).
6. Update `grimoires/loa/a2a/sprint-1/reviewer.md`, re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":5,"medium":7,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:58:00Z"} -->
