# Security & Quality Audit Report — sprint-1

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Task:** review-r22 (`/audit-sprint sprint-1`)
**Scope:** The pull request in `pr/` — `pr/head.diff` (72 files): #1267 mount integrity (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh`, `check-loa.sh` not-mounted outcome, `preflight.sh` count, CI gate), the cycle-130 ablation harness (`pipeline-run.sh`, `lib/sandbox-mount.sh`, `ablation-row.sh`, `took-effect.sh`, `validate-suite.sh`, `freeze.sh`, `spend.sh`, `fingerprint.sh`, `run-arms.sh` spend cap and screen), `Dockerfile.ablation`, the `ablation-2.0` suite, the `gpt-6.1-sol` catalog entry and 11 bats files. Findings cite `head/<path>:<line>` with line numbers from `pr/head/`.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable). Every harness script and System Zone hunk read in full; claims reproduced where the snapshot allowed (jq 1.6 on this host; bats suites run from a scratch copy of `pr/head/`).

**Prerequisite deviation (recorded):** the review gate's verdict is CHANGES_REQUIRED (`grimoires/loa/a2a/sprint-1/engineer-feedback.md`), not "All good". The skill's Phase 0 would stop here; the task brief directs the audit to run regardless, so this audit proceeds as an independent gate and this deviation is noted rather than silently skipped. No COMPLETED marker is written on this verdict.

---

## Executive Summary

The change is well-defended at its trust boundaries: secrets travel only in the environment through a descriptor-closing exec shim and are masked in every capture (`head/evals/harness/pipeline-run.sh:624-632, 702-710`); arm ids, sprint labels, task ids, effort values and fixture paths are allowlisted or regex-gated before use; the sandbox is a separate git repository whose `.claude/` is excluded from the agent's diff; prompts and the task brief are leak-scanned; and the new manifest tooling is NUL-safe and refuses unrepresentable paths. No injection path, hardcoded secret or privilege-escalation route was found. The dissent ran with two independent voices and produced no critical or high finding.

Three defects block the merge, all reproduced or evidenced from the PR's own files: the two new eval suites copy a fixture directory the PR does not ship, so all 39 of their tests fail in `setup()` and the PR's new CI step exits 1; the executor and the row builder use jq 1.7-only syntax and semantics, so on jq 1.6 (the repository's stated floor) every pipeline run ends `infrastructure_error` before its first phase (reproduced: 39 of 52 `pipeline-run.bats` cases fail, every one that launches a phase) and, after the obvious rename, the argv/env capture silently loses its last element; and the PR adds a CI gate that compares the committed integrity manifest against the tracked `.claude/` tree while changing 17 tracked `.claude/` files without regenerating `.claude/checksums.json`, so the gate fails on the PR's own tree and fresh downstream mounts report `Tampered` — the #1267 symptom the PR exists to end.

The medium findings are integrity-surface weakenings (the preflight count no longer inspects the filesystem; the submodule not-mounted outcome means `Missing` can never fire; `integrity_clean` records but does not enforce the manifest digest), one credential-at-rest exposure (the codex OAuth file copied into the results tree survives a SIGKILLed driver), one trust-boundary crossing the harness's own rule forbids (`regen_sandbox_manifest` executes `tools/gen-checksums.sh` from the prompt tree), arm-parity dependence on the host's PATH, and CI path filters that never trigger the new gates.

**Overall Risk Level:** HIGH (driven by the tally; rubric score 3.6/5)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 7 |
| Low | 12 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:4 AZ:4 CI:3 IN:5 AV:3 |
| Architecture | 3.4/5 | MO:4 SC:4 RE:3 CX:3 ST:3 |
| Code Quality | 3.4/5 | RD:4 TC:2 EH:4 TS:3 DC:4 |
| DevOps | 3.4/5 | AU:3 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | *(not applicable)* |
| **Overall** | **3.6/5** | *Weighted average (Security ×2)* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`; working file `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`.

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] The shipped eval suites cannot run: the `runs/` fixture directory is not in the PR

**Severity:** HIGH | **Score:** 2/5 | **Confidence:** high
**Component:** `head/evals/tests/ablation-row.bats:19`, `head/evals/tests/took-effect.bats:18`
**Criterion:** CQ-TC: Test Coverage

**Reasoning Trace:**
> `pr/head/evals/tests/fixtures/ablation-runs/` holds `MANIFEST.json`, `prs/`, `regen.sh`, `suite.yaml`, `tasks/` — no `runs/`. Both suites' `setup()` run `cp -a "$FX/runs" "$T/runs"`. Reproduced from a scratch copy of `pr/head/`: `ablation-row.bats` test 1 and `took-effect.bats` tests 1-3 fail in `setup` with `cp: cannot stat '.../ablation-runs/runs': No such file or directory`. `head/.github/workflows/bats-tests.yml:213-222` now runs `bats --print-output-on-failure evals/tests/` and exits 1 on any failure.

**Description:** `regen.sh` writes `runs/` (`head/evals/tests/fixtures/ablation-runs/regen.sh:52-56`) and prunes gitignored files so "the fixtures on disk equal the fixtures a checkout carries" (`:86-89`), but the generated directories were never added to the change. 18 + 21 tests fail before any assertion.
**Impact:** The harness lands with its evidence suite red; `took-effect.bats` is the only mechanical check of the pre-registered per-trial `took_effect` rules (`head/evals/suites/ablation-2.0.yaml:19-20, 88`). The PR's own CI step fails.
**Proof of Concept:**
```
$ bats --filter 'full graded A1' evals/tests/ablation-row.bats
not ok 1 a full graded A1 build row validates and carries the joined fields
# (from function `setup' in test file evals/tests/ablation-row.bats, line 19)
# cp: cannot stat '.../evals/tests/fixtures/ablation-runs/runs': No such file or directory
```
**Remediation:** Run `evals/tests/fixtures/ablation-runs/regen.sh` after HIGH-002 is fixed and commit `evals/tests/fixtures/ablation-runs/runs/`; or make `setup()` regenerate when the directory is absent.
**References:** CWE-1120 (Excessive Code Complexity / untested shipped code) — https://cwe.mitre.org/data/definitions/1120.html

### [HIGH-002] The executor and the row builder require jq ≥ 1.7; on jq 1.6 every run dies before its first phase and, once past the compile error, the argv/env capture is silently wrong

**Severity:** HIGH | **Score:** 2/5 | **Confidence:** high
**Component:** `head/evals/harness/pipeline-run.sh:702-710` (also `:816-826`, `:881-882`), `head/evals/harness/pipeline-run.sh:704-707`, `head/evals/harness/ablation-row.sh:285`
**Criterion:** CQ-EH: Error Handling / ARCH-RE: Resilience

**Reasoning Trace:**
> On this host's jq 1.6: `jq -n --arg label x '$label'` → `syntax error, unexpected label, expecting IDENT or __loc__`; `jq -n '{label: 1} | {label}'` → `syntax error, unexpected '}', expecting ':'`; `printf '%s\0' a b c | jq -Rs 'split("\u0000") | .[:-1]'` → `["a","b"]` (the last real element is dropped because the slurped string has no trailing empty element on 1.6; jq 1.7 yields `["a","b","c",""]`). Ran `pipeline-run.bats` "A4: ends after IMPLEMENT" with its output surfaced: `rc=2`, the jq compile error at the capture, `pipeline.json` `{"status":"infrastructure_error","reason":"driver aborted (rc 3)","phases":0}`. Full suite on jq 1.6: 13 of 52 pass (the 13 never launch a phase), 39 fail.

**Description:** `pipeline-run.sh:702/708`, `:816/826`, `:881/882` bind and read a jq variable named `$label` (a reserved word jq 1.6 refuses as a variable); `ablation-row.sh:285` uses the `{name, label, …}` key shorthand with the same reserved word, so no row can be built on 1.6; `pipeline-run.sh:704-707` splits NUL-joined argv and env with `split("\u0000") | .[:-1]`, which on 1.6 drops the final element — the recorded `argv` loses `--effort medium` → `--effort` and `--resume <sid>` → `--resume`, and the recorded `env` loses its last entry, which for `gates: false` is exactly `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`. `took-effect.sh` reads these captures (`effort_flag_medium:211-219`, `implementer_single_session:182-198`, `enforce_env_false:161-170`), so A4, A6 and A7 trials are judged "did not take effect" and the arm is paused (`ablation-2.0.yaml:88`).
**Impact:** The repository names jq 1.6+ as its floor (`.claude/scripts/lib/dec-write-lib.sh:208`); Debian 12 and Ubuntu 22.04 hosts ship 1.6. On any such driver host the whole ablation pipeline is dead with an opaque compile error, or — worse, once the variable is renamed — records false arm evidence that fails the pre-registered rules. `ubuntu-latest` (jq 1.7.1) and the smoke run hide it.
**Proof of Concept:**
```
$ jq --version
jq-1.6
$ bats --filter 'A4: ends after IMPLEMENT' evals/tests/pipeline-run.bats   # output surfaced
# DBG rc=2
# jq: error: syntax error, unexpected label, expecting IDENT or __loc__ ... at <top-level>, line 1:
# {label: $label, name: $name, executor: $executor, cwd: $cwd, timeout_s: $tsec,
# DBG pipeline: {"status":"infrastructure_error","reason":"driver aborted (rc 3)","phases":0}
```
**Remediation:**
```bash
# Before (1.7-only)
jq -n --arg label "$label" ... --argjson argv "$(printf '%s\0' "${cargv[@]}" | jq -Rs 'split("\u0000") | .[:-1]')" '{label: $label, ...}'
# After (1.6-safe)
jq -n --arg lbl "$label" ... --argjson argv "$(jq -n --args '$ARGS.positional' "${cargv[@]}")" '{label: $lbl, ...}'
# ablation-row.sh:285: write `label: .label` instead of the shorthand
```
Add a bats case pinning `(.argv | length) == ${#cargv[@]}` and a `jq --version` floor check (or pin 1.7 explicitly in the harness's requirements and the Dockerfile).
**References:** CWE-1104 (Use of Unmaintained/Incompatible Third-Party Components) — https://cwe.mitre.org/data/definitions/1104.html

### [HIGH-003] The new integrity-manifest gate fails on this PR: 17 tracked `.claude/` files change and `.claude/checksums.json` is not regenerated

**Severity:** HIGH | **Score:** 3/5 | **Confidence:** medium
**Component:** `head/.github/workflows/bats-tests.yml:176-179`, `head/tools/gen-checksums.sh:152-168`
**Criterion:** SEC-CI: Confidentiality/Integrity / DEVOPS-AU

**Reasoning Trace:**
> The gate regenerates the manifest from `git ls-files -- .claude` and exits 1 on any `added / removed / changed` path. The diff edits `head/.claude/defaults/model-config.yaml:122-149, 240`, `head/.claude/scripts/check-loa.sh:47-88`, `head/.claude/scripts/preflight.sh:175-197`, `head/.claude/scripts/generated-model-maps.sh`, `head/.claude/loa/CLAUDE.loa.md:1`, `head/.claude/adapters/tests/test_pricing_resolution_ladder.py:30` and the bridgebuilder `dist/` and `resources/*.generated.ts` files, and carries no `.claude/checksums.json`; only `model-config.yaml.checksum` was refreshed. `head/tests/unit/check-manifest-paths.bats:88-92` (MP-6, "the committed manifest of this repository passes") and the narrative in `head/tools/gen-checksums.sh:5-10` establish that the manifest is a committed artefact consumed by downstream mounts. Confidence is medium because the upstream tree's manifest is outside the PR snapshot; if it is tracked, the failure is deterministic.

**Description:** The PR introduces the mechanism that detects exactly this condition and then trips it. On merge, `gen-checksums.sh --check` prints `DRIFT — 17 path(s) differ` and exits 1; every fresh downstream mount of the resulting commit runs `check-loa.sh` and prints `Tampered:` for each changed path, exiting 1.
**Impact:** The PR's own CI goes red, and the #1267 failure class recurs for every downstream user until a follow-up commit regenerates the manifest. `tools/fresh-mount-proof.sh --worktree` (`head/tools/fresh-mount-proof.sh:176-181`) would have shown it; the implementation report (`pr/PR.md`) carries no evidence it was run.
**Proof of Concept:**
```
$ bash tools/gen-checksums.sh --check      # on the merged tree
gen-checksums: --check: DRIFT — 17 path(s) differ between .claude/checksums.json and the tracked tree:
  changed: .claude/defaults/model-config.yaml
  changed: .claude/scripts/check-loa.sh
  ...
```
**Remediation:** Run `bash tools/gen-checksums.sh` on the final tree and commit the manifest in the same change; run `tools/fresh-mount-proof.sh --worktree` and paste its `fresh-mount-proof: Tampered=0 Missing=0 …` line into the implementation report.
**References:** CWE-354 (Improper Validation of Integrity Check Value) — https://cwe.mitre.org/data/definitions/354.html

---

## Medium Priority Issues (Fix Soon)

### [MEDIUM-001] Preflight's System Zone count no longer inspects the filesystem

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/scripts/preflight.sh:188-197`
**Criterion:** SEC-CI
**Description:** The manifest is generated from `git ls-files` (`head/tools/gen-checksums.sh:102`) and `ACTUAL_COUNT` is now taken from `git ls-files` too, so both sides are index entries. A tracked file deleted from disk (the review's DISS-001) and an untracked executable planted under `.claude/hooks/` or `.claude/scripts/` (dissent DISS-C-001) both leave the count unchanged; the replaced `find` count (now only when the tracked count is 0, `:195-197`) saw both. *Confirmed by cross-model review.*
**Impact:** The "simple check" (`:175`) detects only a stale manifest. `check-loa.sh` still fails a deleted manifest path as `Missing`, but nothing at preflight flags a planted untracked file, which the manifest never lists.
**Remediation:** Count tracked paths that exist on disk and compare the on-disk `find` count against the tracked count as a second signal, or drop the heuristic and call `check_integrity` outright.
**References:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html

### [MEDIUM-002] In submodule mounts `Missing` can never fire, and the mount heuristic is forgeable

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/scripts/check-loa.sh:64, 75-76`
**Criterion:** SEC-CI
**Description:** `submodule_mount` is `[[ -d .loa/.claude ]]`; upstream always holds every manifest path, so every absent path is informational `not-mounted` and a removed link to a hook or gate script is indistinguishable from a by-design unlinked path (dissent DISS-C-001 of the review, DISS-C-002 part 1 here — *confirmed by cross-model review*). Anyone who can delete a System Zone file can also create `.loa/.claude/` plus a shadow copy and downgrade the deletion to a log line in a non-submodule mount. Dissent DISS-C-002 part 2 (the trailing `return 0` hides drift) is **not a defect**: `fail()` increments `FAILURES` (`head/.claude/scripts/check-loa.sh:36`) and `main` exits 1 when it is non-zero (`:603-605`); the base's trailing `[[ … ]] && log` returned 1 on drift and aborted the script under `set -e`, so the `return 0` is a fix.
**Impact:** The submodule check becomes Tampered-only.
**Remediation:** Compare against the mount's own link list (what `mount-submodule.sh` linked) rather than "exists upstream"; treat an absent path in that set as `Missing`.
**References:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html

### [MEDIUM-003] `integrity_clean` records the manifest digest but does not enforce it

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/evals/harness/took-effect.sh:266`
**Criterion:** SEC-CI
**Description:** The rule verifies every entry of the sandbox's *current* `checksums.json` and only annotates "(matches checksums.json)" when that file's digest equals `arm_evidence.manifest_sha256` captured at materialisation (`head/evals/harness/pipeline-run.sh:492-493`). A phase that edits `.claude/` and regenerates the manifest (hooks, `update.sh`, `tools/gen-checksums.sh` can) verifies clean against its own new manifest.
**Impact:** The pin was captured for exactly this case and is not used; System Zone tampering by the agent under test can pass the arm's integrity rule.
**Remediation:**
```bash
[[ "$filesha" == "$msha" ]] || { EVID="manifest replaced since materialisation (${filesha:0:12} vs ${msha:0:12})"; return 1; }
```
**References:** CWE-354 — https://cwe.mitre.org/data/definitions/354.html

### [MEDIUM-004] The codex OAuth credential is copied into the results tree and survives an abnormal driver exit

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/pipeline-run.sh:569-571` (with `:301`, `:348`, `:356`)
**Criterion:** SEC-CI
**Description:** `make_home` copies `~/.codex/auth.json` and `config.toml` into `<run>/meta/home/.codex/` (`HOME_DIR="$META/home"`, `:301`). `finish` and `on_exit` remove the directory, but a SIGKILLed or OOM-killed driver runs no trap (the header `:104-106` anticipates a SIGKILLed driver), and nothing sweeps stale `meta/home/` on the next start.
**Impact:** An operator credential at rest under `evals/results/…`, a tree that batches archive and `spend.sh` scans.
**Remediation:** Stage the codex files in a `mktemp -d` outside the run directory and bind-mount that; at minimum `chmod 0600` the copies and sweep `*/meta/home/` at driver start.
**References:** CWE-538 — https://cwe.mitre.org/data/definitions/538.html; CWE-312 — https://cwe.mitre.org/data/definitions/312.html

### [MEDIUM-005] `regen_sandbox_manifest` executes `tools/gen-checksums.sh` from the prompt tree, crossing the harness's own trust boundary

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/lib/sandbox-mount.sh:383-387` (also `:511-514`)
**Criterion:** SEC-AZ / ARCH-ST
**Description:** When the tool is executable and the sandbox is a git work tree tracking `.claude` files, the library runs `${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}/tools/gen-checksums.sh --root "$ws"`; that script `source`s its own tree's `.claude/scripts/compat-lib.sh` (`head/tools/gen-checksums.sh:51`). In `execute-agent.sh` the prompt tree is the tree under evaluation (`head/evals/harness/execute-agent.sh:146`), which the library's own header says must never run in the harness (`:96-100`, eval.yml "Validate grader trust boundary"). `init_sandbox_beads` likewise runs the sandbox's `.claude/scripts/beads/update-beads-state.sh` (`:513`). The bats trust-boundary scan (`head/evals/tests/pipeline-run.bats:248-260`) checks four files and `source` lines only, so neither execution is covered. [ASSUMPTION] eval.yml wires `EVAL_PROMPT_TREE` to the PR checkout; the workflow file is outside the snapshot. The git condition rarely holds for current callers, hence medium confidence.
**Impact:** PR-controlled code can run in the trusted grader process under a reachable configuration; the invariant the trust-boundary gate protects is violated in intent.
**Remediation:** Drop the `$tool` branch (the inline hashlib generator already produces an equivalent manifest), or only ever invoke the harness repo's own copy; extend the trust-boundary scan to `lib/sandbox-mount.sh` and to direct executions of prompt-tree paths.
**References:** CWE-829 (Inclusion of Functionality from Untrusted Control Sphere) — https://cwe.mitre.org/data/definitions/829.html; OWASP A08:2021 — https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/

### [MEDIUM-006] Sandbox beads state depends on the driver host's PATH, not on the arm

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/lib/sandbox-mount.sh:504-509`
**Criterion:** ARCH-ST
**Description:** `init_sandbox_beads` probes `br` on the host. `head/evals/harness/Dockerfile.ablation:82-84` says the image has no `br` and expects the opt-out marker; `pipeline-run.sh` never sets `LOA_EVAL_BR_BIN`. On an operator host with `br` on PATH every containerised arm gets a `.beads/` database the in-container CLI cannot drive; on one without, the opt-out marker.
**Impact:** Arm parity — the ablation's core requirement — varies by operator machine and is not pinned anywhere.
**Remediation:** In container mode pass `LOA_EVAL_BR_BIN=/nonexistent` (or probe the image) and assert the `beads=` evidence value in a took-effect rule.
**References:** CWE-1188 (Insecure Default Initialization) — https://cwe.mitre.org/data/definitions/1188.html

### [MEDIUM-007] The workflow's path filters never trigger the new gates

**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.github/workflows/bats-tests.yml:23-46, 49-72`
**Criterion:** DEVOPS-AU
**Description:** Neither `paths:` list names `evals/**`, `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh` or `tools/fresh-mount-proof.sh`, yet the workflow now runs the eval harness suites (`:213-225`) and the manifest gate (`:176-179`).
**Impact:** A PR that only changes the harness, its tests or the manifest tools never runs the steps that gate them.
**Remediation:** Add those paths to both lists.
**References:** CWE-1120 — https://cwe.mitre.org/data/definitions/1120.html

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Dead `brbuild` stage contradicts the Dockerfile's own comment
**Component:** `head/evals/harness/Dockerfile.ablation:19-20` (vs `:82-84`)
**Description:** Never `COPY --from`'d; `:82-84` says beads_rust 0.2.6 is not on crates.io. Under the classic builder (`DOCKER_BUILDKIT=0`) every stage builds and `cargo install` fails the image. SIMPLICITY[delete].
**Remediation:** Remove the stage.

### [LOW-002] The ablation image departs from the repository's pinning policy
**Component:** `head/evals/harness/Dockerfile.ablation:60-63, 69, 72-74`
**Description:** Four Python packages are installed by lower-bound range (`:69`), bats-core is cloned by mutable tag without the commit-SHA check the workflow performs (`head/.github/workflows/bats-tests.yml:147-152`), and the two CLIs are installed by version without integrity. The image is the batch's fixed identity (`drift_guard`, `head/evals/suites/ablation-2.0.yaml:86`), so two builds can differ silently; the yq install in the same file (`:44-57`) shows the intended pattern.
**Remediation:** Pin exact versions (a hashed requirements file), verify the bats-core SHA, record `pip freeze` in the health check.
**References:** OWASP A08:2021 — https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/

### [LOW-003] Operator-specific executable fallback in `fingerprint.sh`
**Component:** `head/evals/harness/fingerprint.sh:54` (with `head/evals/harness/pipeline-run.sh:428`)
**Description:** When `bats` is not on PATH the script executes `$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats` (a user-writable, one developer's path; `$HOME` under `set -u`); `pipeline-run.sh:428` swallows any failure and records `fingerprint: null`. *Confirmed by cross-model review (DISS-C-005).*
**Remediation:** `bats=absent` when not on PATH; make the driver warn or fail when `fingerprint.sh` exits non-zero.
**References:** CWE-426 — https://cwe.mitre.org/data/definitions/426.html

### [LOW-004] The harness executes `.claude/` code despite its stated invariant, and the invariant's test cannot see executions
**Component:** `head/evals/harness/pipeline-run.sh:586` (vs `:125-126`; test `head/evals/tests/pipeline-run.bats:248-260`)
**Description:** `price_for` runs `.claude/adapters/loa_cheval/metering/pricing.py` from the harness repo. `REPO_ROOT` is the harness's own (trusted) tree, so this is a documentation/invariant mismatch rather than a boundary crossing, but the bats scan inspects `source` lines only and would not catch an exec of a PR path either.
**Remediation:** Document the exception or read prices from a harness-owned table; extend the scan to `python3`/`bash` invocations of `.claude/` paths.

### [LOW-005] Placeholder pricing reaches cost rows unmarked; the new HTTP entry's fallback crosses into the subscription credential path
**Component:** `head/.claude/defaults/model-config.yaml:135, 144-149, 240`
**Description:** `gpt-6.1-sol` pricing is an acknowledged placeholder (`:144-149`) that every `codex-headless` estimate and MODELINV row now resolves to (`cli_model: gpt-6.1-sol`, `:240`) with no provisional marker on the rows; its `fallback_chain` is `openai:codex-headless` (`:135`), whose `cli_model` is itself `gpt-6.1-sol`, so an API-key failure silently re-runs the request through the operator's ChatGPT subscription. *Confirmed by cross-model review (DISS-C-006; review DISS-C-003).* The within-company chain is the repository's convention; the visibility is the gap.
**Remediation:** Surface a provisional flag on rows priced through the entry, or price the hop as unknown until the rate card lands; track the bead the comment names.

### [LOW-006] Suite `source_commit` placeholder can reach rows
**Component:** `head/evals/suites/ablation-2.0.yaml:25` (consumer `head/evals/harness/ablation-row.sh:276`)
**Description:** `"<sprint-258-commit>"` is written into rows when `pipeline.json` lacks the field.
**Remediation:** Set the commit before the freeze; have `validate-suite.sh` reject a non-hex `source_commit`.

### [LOW-007] The suite freeze skips symlinks
**Component:** `head/evals/harness/freeze.sh:69`
**Description:** `find -type f` omits symlinks and empty directories under `tasks/`, so a symlinked fixture file is outside the frozen identity.
**Remediation:** Refuse symlinks under the suite root, or hash through them with `find -L`.

### [LOW-008] A container OOM kill is classed `interrupted`
**Component:** `head/evals/harness/pipeline-run.sh:857` (with `:688`)
**Description:** `--memory 4g` kills the CLI with exit 137 before the timeout; the driver records `interrupted` (exit 4) rather than `agent_error`, so a model that blows the memory cap is excluded as an operator interrupt.
**Remediation:** Read the container's `OOMKilled` state before removal, or treat 137 without a driver signal as `agent_error`.

### [LOW-009] Row quality fields are derived from artefacts the system under measurement can write
**Component:** `head/evals/harness/ablation-row.sh:200-206` (also `:192-198, 236-247`)
**Description:** `degraded`, `degraded_reason` and `voices_run` come from envelopes read first from `sandbox/grimoires/…`; `effort_effective` and `voice_cost_usd` from `eval/model-invoke.jsonl`, itself copied out of the agent-writable `sandbox/.eval` (`pipeline-run.sh:773`). The header's never-from-`sandbox/` rule (DEC-0413) is applied to the arm only. *Cross-model DISS-C-003 rated this MEDIUM; kept LOW here because the writer is the Loa agent under test rather than an adversary and the took-effect rules bound the effect.*
**Remediation:** Read envelopes from `eval/` only and flag rows whose sandbox and eval copies differ.
**References:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [LOW-010] `zone_violations` is blind to Bash-tool writes
**Component:** `head/evals/harness/ablation-row.sh:214-221`
**Description:** Only `Write`/`Edit`/`MultiEdit`/`NotebookEdit` tool inputs are inspected; `echo >`, `sed -i`, `cp` through the Bash tool, symlinks into `.claude/` and nested `foo/.claude/` paths are not recorded. *Confirmed by cross-model review (DISS-C-004).* `integrity_clean` still catches content changes to manifest-listed files, so the gap is attribution, not detection — the same fence gap `CLAUDE.loa.md` documents for Bash-path writes.
**Remediation:** Also scan Bash tool_use commands for `.claude/` redirections and in-place edits, or derive the metric from a per-phase snapshot diff of `.claude/`.
**References:** CWE-778 — https://cwe.mitre.org/data/definitions/778.html

### [LOW-011] The per-run spend cap trusts ledger rows the sandbox agent can write
**Component:** `head/evals/harness/pipeline-run.sh:769-771, 854`
**Description:** `sandbox/.eval/cost-ledger.jsonl` rows are summed into `SPENT_MICRO` with no non-negative or numeric clamp; a negative `cost_micro_usd` row lowers the recorded spend and defers `cap_failure` (`:864`). The CLI's `result.total_cost_usd` is authoritative and unaffected.
**Remediation:** `select(type == "number" and . >= 0)` per row; count only rows with cheval's `primitive_id` shape.
**References:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [LOW-012] Stale toolchain version in the executor header
**Component:** `head/evals/harness/pipeline-run.sh:85-86` (vs `head/evals/harness/Dockerfile.ablation:25`)
**Description:** The header names `codex 0.137.0`; the Dockerfile pins `CODEX_VERSION=0.162.1`.
**Remediation:** Reference the Dockerfile ARGs instead of restating versions.

---

## Observations

- `head/evals/harness/pipeline-run.sh:657, 723-725` — host executor mode runs the agent under test with `--dangerously-skip-permissions` under the operator's real `$HOME` and PATH. Documented dev mode ("every arm runs in the container", `:87`); recorded as a residual risk, not a finding.
- `head/evals/harness/pipeline-run.sh:634-868` — `run_phase` is ~235 lines (build-argv, launch, watchdog, record, decide in one body); the jq capture defect reported above lived in it. Splitting into `build_launcher`, `watch_phase`, `record_phase` would isolate the capture logic.
- Review citation correction: the review cites the `gpt-6.1-sol` pricing at `model-config.yaml:42-47`; the entry is at `:122-149` (pricing `:144-149`). Noted for the FIX round; not a PR defect.
- The implementation report (`grimoires/loa/a2a/sprint-1/reviewer.md` = `pr/PR.md`) carries no `## AC Verification` section and no evidence that `tools/fresh-mount-proof.sh` or the eval suites were run on the final tree.
- Scope limits: `.github/workflows/eval.yml` and the upstream `.claude/checksums.json` are outside the PR snapshot (the manifest-gate finding and the prompt-tree execution finding above carry medium confidence for that reason); the bridgebuilder `dist/*.generated.*` files were checked for the `gpt-6.1-sol` additions only; `arm-toggles.bats`, `run-arms.bats`, `validate-suite.bats` and `freeze.bats` depend on fixtures outside the snapshot and were not run. The frozen `pr/head/` tree lost executable bits that the diff records as `100755`; tests were run after restoring them, and this is a snapshot artefact, not a PR defect.

---

## Cross-Model Security Observations

Dissent: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `metadata.type: audit`, `model: gpt-5.5-pro` (primary answered via `codex-headless`), companion `claude-headless` (`counted_as: independent_voice`, `status: succeeded`), `verdict_quality` 2/2 voices, `degraded: false`, status `clean`. 6 findings (3 MEDIUM, 3 LOW; 0 critical/high), all from the companion voice. Not a degraded review.

| Finding | Triage |
|---------|--------|
| DISS-C-001 (MEDIUM) preflight count blind to planted untracked files | Confirmed by cross-model review; merged into MEDIUM-001 together with the review's deletion case |
| DISS-C-002 (MEDIUM) submodule `Missing` never fires / `.loa/.claude` forgeable; `return 0` hides drift | Part 1 confirmed → MEDIUM-002. Part 2 not a defect: `fail()` counts into `FAILURES` (`check-loa.sh:36`) and `main` exits 1 (`:603-605`) |
| DISS-C-003 (MEDIUM) degraded/voices_run from agent-writable envelopes | Real; recorded as LOW-009 (severity reasoning there) |
| DISS-C-004 (LOW) zone_violations blind to Bash writes | Confirmed → LOW-010 |
| DISS-C-005 (LOW) fingerprint executes a user-writable path | Confirmed → LOW-003 |
| DISS-C-006 (LOW) gpt-6.1-sol fallback crosses credential boundary; placeholder pricing | Confirmed → LOW-005 |

## Rejected dissent payloads

No payload was rejected: `metadata.rejected_summary` is empty and `metadata.rejected_sidecars` is empty (no `adversarial-rejected-audit*.jsonl` exists beside the envelope).

---

## Review demotions

The review trailer counts `excluded: 0`; there are no demoted highs to confirm. `excluded_confirmed: 0`.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (an operator-specific path only, LOW-003)
- [ ] Credential copies never persist under archived output (MEDIUM-004)
- [x] Secrets never on argv or in captures (`pipeline-run.sh:694, 705-706`; `<set>` masking; tested at `pipeline-run.bats:703`)
- [x] Per-run HOME holds no `~/.claude` credential or settings (`pipeline-run.sh:556-561`)

### Authentication & Authorization
- [x] Container runs non-root as the host uid, `--read-only`, pids/memory/cpu limits, exactly two mounts (`pipeline-run.sh:686-691`)
- [ ] Harness never executes code from the tree under evaluation (MEDIUM-005, LOW-004)
- [x] Arm env lines limited to `LOA_*` (`pipeline-run.sh:673`)

### Input Validation
- [x] Arm ids, sprint labels, task ids, effort values, trial, cap, suite schema validated (`lib/sandbox-mount.sh:163, 442, 446`; `pipeline-run.sh:165, 186, 262`; `validate-suite.sh`)
- [x] Path traversal guarded (`lib/sandbox-mount.sh:488`; `validate-suite.sh` `rel_ok`); fixture path rule; hidden-path and leak guards
- [x] No `eval`; rule dispatch gated by `declare -F` (`took-effect.sh:318`)
- [ ] Agent-writable ledgers and envelopes clamped before use (LOW-009, LOW-011)

### Data Privacy
- [x] Error messages do not leak sensitive data (`AWS_BEARER_TOKEN_BEDROCK` recorded as `<set>`)
- [x] No PII in logs

### Supply Chain
- [x] Workflow dependencies pinned with integrity (bats SHA, yq sha256, actions by SHA)
- [ ] Image dependencies pinned with integrity (LOW-002)

### Integrity
- [x] Manifest generator NUL-safe; refuses newline/tab/backslash paths (`tools/gen-checksums.sh:89-102`)
- [ ] Manifest regenerated for this change (HIGH-003)
- [ ] Integrity checks detect on-disk drift (MEDIUM-001, MEDIUM-002, MEDIUM-003)

---

## Threat Model Summary

**Trust Boundaries:**
- Harness (trusted copy) ↔ tree under evaluation (`EVAL_PROMPT_TREE` / `--source-tree`): the harness must run none of its code.
- Driver host ↔ sandbox container: only `sandbox/` and `meta/home/` are mounted; the agent's writes to `sandbox/` are untrusted for evidence (DEC-0413).
- Operator credentials (Bedrock bearer token, codex OAuth) ↔ the agent under test: the token is in the agent's environment and the codex file in its HOME by design.

**Attack Vectors:**
- Agent under test tampers with `.claude/` and regenerates the manifest: MEDIUM-003 (not caught by `integrity_clean`).
- Agent under test forges envelopes / ledger rows: LOW-009, LOW-011 (metric and cap integrity).
- PR-controlled script executed by the harness under a reachable configuration: MEDIUM-005.
- Local actor deletes a System Zone file and forges the submodule heuristic: MEDIUM-002.

**Mitigations:** descriptor-closing exec shim; env-only secrets with masked captures; container resource limits and read-only root; leak guards; separate sandbox git with `.claude/` excluded; arm id kept under `meta/` only; manifest regenerated after toggles with the digest recorded.

**Residual Risks:**
- The agent under test holds the Bedrock bearer token and can read the codex OAuth file with outbound network (`--network bridge`); accepted by design (DEC-0411), scoped to the eval credentials.
- Host executor mode exposes the operator's HOME to an unrestricted agent; documented dev mode.

---

## Positive Findings

- Secrets travel in the environment only, through a `python3 -I` exec shim that closes every descriptor above 2 and keeps exactly the allowlist (`pipeline-run.sh:624-628, 696-698`); captures record `<set>`; a bats case asserts no artefact carries the token (`pipeline-run.bats:703`).
- Arm effects are proven from artefacts, never from agent claims (`took-effect.sh`); arm ids are kept out of the sandbox and leak-scanned from prompts and the task brief (`pipeline-run.sh:502-521`).
- `gen-checksums.sh` / `check-manifest-paths.sh` are small, NUL-safe, refuse unrepresentable paths, and are fully covered by passing unit tests (GC-1…GC-6, MP-1…MP-5, CM-1…CM-6 pass here; GC-7/MP-7 fail only because this host's `TMPDIR` is inside the repository).
- `fresh-mount-proof.sh` runs git hermetically (`GIT_CONFIG_GLOBAL=/dev/null`, `core.hooksPath` to an empty dir, `protocol.file.allow` scoped to the process).
- Containers run as the host uid with `--read-only`, `--pids-limit`, `--memory`, `--cpus`, and exactly two mounts; the trust-dialog pre-acceptance is limited to `/workspace`.

---

## Recommendations

### Immediate Actions (24 Hours)
1. Fix the jq 1.6 incompatibility (HIGH-002), regenerate and commit `evals/tests/fixtures/ablation-runs/runs/` (HIGH-001), run `bats evals/tests/ tests/unit/` on a jq 1.6 host and paste the summary into the implementation report.
2. Run `bash tools/gen-checksums.sh` on the final tree, commit `.claude/checksums.json`, and paste the `tools/fresh-mount-proof.sh --worktree` summary line into the report (HIGH-003).

### Short-Term Actions (1 Week)
1. Enforce the manifest digest in `integrity_clean` (MEDIUM-003); make the preflight count inspect the filesystem (MEDIUM-001); compare submodule mounts against their link list (MEDIUM-002).
2. Move the codex credential copies out of the results tree and sweep stale `meta/home/` (MEDIUM-004); drop the prompt-tree `gen-checksums.sh` execution and widen the trust-boundary scan (MEDIUM-005); pin beads state per executor mode (MEDIUM-006); add `evals/**` and the tools to the workflow path filters (MEDIUM-007).

### Long-Term Actions (1 Month)
1. Pin the image's dependencies with integrity (LOW-002); split `run_phase`; derive `zone_violations` from a per-phase `.claude/` snapshot diff (LOW-010); read row quality fields from `eval/` copies only (LOW-009).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | Every harness script, System Zone hunk, tool, workflow, Dockerfile and suite file read; stubs and test setups read; 4 unit/eval suites and a `pipeline-run.bats` full run executed from the PR content |
| Report each defect with file and line | Pass | Above, `head/<path>:<line>` |
| Give a merge verdict | Pass | CHANGES_REQUIRED |

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 7 |
| Low | 12 |

---

## Verdict

**CHANGES_REQUIRED**

Three HIGH findings (HIGH-001 missing `runs/` fixtures; HIGH-002 jq 1.6 incompatibility; HIGH-003 manifest not regenerated against the new gate) force the verdict under the one-way rule. No COMPLETED marker is written.

**Next Steps:**
1. Address HIGH-001…003 and the seven MEDIUM findings; update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section carrying the bats and fresh-mount-proof summaries.
2. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

**Audit Completed:** 2026-10-22T20:05:00Z
**Next Audit Recommended:** on the FIX round
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-22/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T20:05:00Z"} -->
