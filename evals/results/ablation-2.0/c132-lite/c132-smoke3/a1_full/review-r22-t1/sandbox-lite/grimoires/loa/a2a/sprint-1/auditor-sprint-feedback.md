# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 0 excluded)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change is the Sprint 258 pull request (72 files): the #1267 mount-integrity tooling (`tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh`, the `check-loa.sh` not-mounted classification, the `preflight.sh` count), the spend scripts, the ablation-2.0 suite, the container pipeline executor (`pipeline-run.sh` + `lib/sandbox-mount.sh`), `ablation-row.sh`, `took-effect.sh`, the fixtures, and the CI wiring. I read every file in `pr/head.diff`, catalogued sources and sinks (`grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`), traced each flagged flow, reproduced the mechanical claims on this host (bash 5, jq 1.6, Python 3.11, no `br` on PATH) and ran the two-voice security dissent on the diff.

The secret-handling design of the executor is sound where it matters most: the Bedrock token travels by name only, the exec shim keeps an allowlist and closes descriptors, the capture redacts the secret as `<set>` (`head/evals/harness/pipeline-run.sh:705-706`), the container gets exactly two mounts with a read-only root and resource limits, and the sandbox git is isolated from the operator's config. What blocks the merge: one live trust-boundary violation (the materialiser executes a script copied from the mounted tree on the host), the jq 1.6 incompatibilities and the NUL-split truncation that make the executor and its took-effect proof fail on the repository's own declared jq floor, the row builder's unbounded argv, and two CI gates this PR adds that are red on its own head (the manifest it does not regenerate; the fixture run directories it does not ship).

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 6 |
| Medium | 5 |
| Low | 8 |

Verdict quality: dissent 2/2 voices (primary `gpt-5.5-pro` answered by `codex-headless`: clean; companion `claude-headless`: 6 findings), no rejected payloads, not degraded. Review trailer `excluded: 0` → nothing to confirm; `excluded_confirmed: 0`.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The materialiser executes code from the mounted tree on the host

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/lib/sandbox-mount.sh:513`
**Issue:** `init_sandbox_beads` runs

```bash
PROJECT_ROOT="$ws" bash "$ubs" --opt-out "eval sandbox: br not on PATH" >/dev/null 2>&1
```

where `$ubs` is `$ws/.claude/scripts/beads/update-beads-state.sh` (`:511`), a file `mount_prompt_surface` copied out of `--source-tree` (`:131`). The branch is taken whenever `br` is not on PATH (`:505`), which is the documented default for the ablation (`head/evals/harness/Dockerfile.ablation:82-84`: "No beads (br) in the image … the sandbox materialiser writes the beads opt-out marker") and is the state of this host. It is reached from `head/evals/harness/pipeline-run.sh:489` for every mounted arm, on the HOST, before any container starts, with the driver's full environment (including `AWS_BEARER_TOKEN_BEDROCK` when set, and the operator's `$HOME`). The header promises the opposite: "Hashing is Python hashlib (_sm_sha256), never .claude/ code" (`head/evals/harness/lib/sandbox-mount.sh:75`), and `pipeline-run.sh:125-126` says "No .claude/ code is sourced (eval.yml 'Validate grader trust boundary': the harness is the trusted copy and runs against a PR's .claude/)". The eval.yml scan the comment cites looks for `source` lines; `bash "$ubs"` evades it while executing the same untrusted code. The base `execute-agent.sh` has no beads step, so the path is new in this change.
**Impact:** Any tree passed as `--source-tree` (or any PR whose `.claude/` is mounted by a future eval.yml integration of this executor) gains arbitrary code execution in the trusted harness context with the driver's credentials. Confidence is medium only because today's ablation flow mounts the operator's own pinned tree; the invariant violation itself is certain.
**Fix:** The script only writes `$PROJECT_ROOT/.run/beads-state.json`. Write that marker from the harness (jq, no exec), or run the trusted copy `$_SM_REPO_ROOT/.claude/scripts/beads/update-beads-state.sh` with `PROJECT_ROOT=$ws`, or move the step inside the container. Add a bats case asserting no process is spawned from `$ws/.claude/`.
**Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html

### [HIGH-002] jq 1.6 rejects the executor, the mount library and the row builder

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/pipeline-run.sh:702`
**Issue:** `jq -n --arg label "$label" …` binds the jq variable `$label`; `label` is a jq keyword and jq 1.6 — the floor the repository declares (`.claude/scripts/lib/dec-write-lib.sh:208`, "jq 1.6+") and what Debian bookworm, the image base, ships — fails to compile with `syntax error, unexpected label, expecting IDENT or __loc__`. Same construct at `head/evals/harness/pipeline-run.sh:816` and `:881`, and in `head/evals/harness/lib/sandbox-mount.sh:462` and `:467` (`write_sandbox_grimoire` → "ledger write failed", so the real-library path fails before the first phase). `head/evals/harness/ablation-row.sh:285` uses the `{name, label, …}` object shorthand, which jq 1.6 rejects with `unexpected '}', expecting ':'`. Reproduced on this host with jq-1.6 for both constructs.
**Impact:** Every mounted arm ends `infrastructure_error` before its first phase on a jq 1.6 host; the row builder cannot run at all. Nothing in the PR declares or checks a jq ≥ 1.7 requirement.
**Fix:** Rename the jq variable (`--arg lbl "$label"` / `$lbl`) at the five sites and write `"label": .label` in `ablation-row.sh`; or add a `jq --version` ≥ 1.7 check with a clear message and state the floor change. Add a jq 1.6 CI leg either way.
**Reference:** CWE-474 Use of Function with Inconsistent Implementations — https://cwe.mitre.org/data/definitions/474.html

### [HIGH-003] The NUL-split capture drops the last argv/env element on jq 1.6

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/pipeline-run.sh:704`
**Issue:** The argv, env and launcher captures are built with

```bash
printf '%s\0' "${cargv[@]}" | jq -Rs 'split("\u0000") | .[:-1]'
```

(also `:705`, `:707`). On jq 1.6 the raw slurp yields no trailing empty element, so `.[:-1]` removes the LAST real element. Reproduced: `printf '%s\0' a b c | jq -Rs 'split("\u0000") | .[:-1]'` → `["a","b"]`. `--effort medium` loses `medium`, `--resume <sid>` loses the session id, and the env capture loses its last variable, which for `gates: false` is `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`.
**Impact:** `took-effect.sh` reads exactly these captures (`head/evals/harness/took-effect.sh:165`, `:193`, `:215`): correct runs fail `enforce_env_false`, `effort_flag_medium` and `implementer_single_session`, and the suite's rule "a took-effect miss is infrastructure_error and pauses the arm" fires falsely; conversely a run whose offending element was last would pass. The took-effect proof is the sprint's evidence that an arm ran as declared (FR-3/FR-7).
**Fix:** `rtrimstr("\u0000") | split("\u0000")`, or pass the elements with `--args` and read `$ARGS.positional`. Add a test asserting the last argv element and the last env key are present in the capture.
**Reference:** CWE-474 — https://cwe.mitre.org/data/definitions/474.html

### [HIGH-004] The row builder passes unbounded JSON through argv

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/harness/ablation-row.sh:226`
**Issue:** The whole MODELINV ledger (`$MINV`, built at `:193-197` from `eval/model-invoke.jsonl`), the full `pipeline.json` (`$PIPE_JSON`), both envelopes and `$DOT_WRITES` are passed to jq as `--argjson` command-line strings (`:224-228`). Linux caps a single argv string at 128 KiB. Reproduced: a 140001-byte `--argjson` → `/usr/bin/jq: Argument list too long`. Under `set -e` the script dies before `ROW` exists.
**Impact:** `runs.jsonl` silently lacks exactly the long, multi-phase, two-voice runs the ablation measures; the comparison is biased toward short runs and the batch runner has no row to mark the failure. Confirmed by the review's dissent (DISS-001) and the review.
**Fix:** Write the inputs to files under a temp dir and load them with `--slurpfile`/`--rawfile`, or stream the ledger on stdin. Add a test with a >128 KiB `model-invoke.jsonl`.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-005] The new CI integrity gate is red on this PR's own head

**Severity:** HIGH (confidence: high)
**File:** `head/.github/workflows/bats-tests.yml:178`
**Issue:** The new step runs `tools/check-manifest-paths.sh` (`:177`) and `tools/gen-checksums.sh --check` against the committed `.claude/checksums.json`, but this PR changes sixteen tracked `.claude/` files (`check-loa.sh`, `preflight.sh`, `defaults/model-config.yaml`, `loa/CLAUDE.loa.md`, `generated-model-maps.sh`, the bridgebuilder `dist/` and `resources/` files, the pricing test) and `.claude/checksums.json` is not in the diff. A stale manifest → `changed:` drift, exit 1; an absent manifest → exit 1 (`head/tools/gen-checksums.sh:143-146`) and exit 2 (`head/tools/check-manifest-paths.sh:70`). `head/tests/unit/check-manifest-paths.bats:88-92` (MP-6, "the committed manifest of this repository passes") fails in the same way. The manifest in this workspace matches head hashes only because the harness regenerated the sandbox manifest (`regen_sandbox_manifest`), which says nothing about upstream.
**Impact:** A red gate on the merge commit is either a blocked release or a bypassed gate; the first downstream fresh mount after the merge still reads the stale manifest, which is the #1267 symptom the sprint set out to fix.
**Fix:** Run `bash tools/gen-checksums.sh` on the head tree and commit `.claude/checksums.json` in this PR; make the release path regenerate it so every `.claude/` change keeps the gate green.
**Reference:** OWASP Top 10 CI/CD Security Risks, CICD-SEC-1 Insufficient Flow Control Mechanisms — https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-01-Insufficient-Flow-Control-Mechanisms

### [HIGH-006] Two new test files depend on fixture run directories that are not in the change

**Severity:** HIGH (confidence: high)
**File:** `head/evals/tests/took-effect.bats:18`
**Issue:** `setup()` runs `cp -a "$FX/runs" "$T/runs"` (same at `head/evals/tests/ablation-row.bats:19`), but `evals/tests/fixtures/ablation-runs/runs/` is not in the diff: the fixture directory carries `MANIFEST.json`, `regen.sh`, `suite.yaml`, `tasks/` and `prs/` only. `head/evals/tests/fixtures/ablation-runs/regen.sh:86-89` describes the run directories as tracked fixtures a checkout carries, and the new CI step at `head/.github/workflows/bats-tests.yml:212-221` runs `bats evals/tests/` unconditionally.
**Impact:** Every test in both files (18 + 21) fails in `setup()`; the eval-harness CI step this PR adds is red on this PR. (The review also could not run `validate-suite.bats`, `freeze.bats`, `arm-toggles.bats` and `run-arms.bats` for fixtures outside the diff; if those exist on the base branch that part is fine.)
**Fix:** Commit the regenerated `runs/` directories (post-`regen.sh`, gitignored copies removed as the script already does), or regenerate them in `setup_file()` when absent.
**Reference:** CICD-SEC-1 — https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-01-Insufficient-Flow-Control-Mechanisms

---

## Medium/Low Priority Issues

### [MED-001] Submodule mode can no longer detect tamper-by-deletion
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/check-loa.sh:75`
- **Issue:** `elif [[ "$submodule_mount" == "true" && -f ".loa/${file}" ]]; then not_mounted=$((not_mounted + 1))` — in a submodule mount the manifest is generated from the upstream tracked tree, so every manifest path exists under `.loa/<path>` by construction and `Missing:` (`:78`) is unreachable. Deleting the link for a hook, gate or guard script now prints an informational not-mounted count and `Integrity verified` where it was a hard failure before. Confirmed by cross-model review (DISS-C-001) and by the review.
- **Fix:** Classify not-mounted only for paths outside the link scope `mount-submodule.sh` creates (its link list); fail for an absent path inside it, at minimum under `.claude/scripts` and `.claude/hooks`. Until then document the accepted blind spot beside the SDD §5.3 comment.
- **Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [MED-002] Dead branch that would execute the tree under test
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:386`
- **Issue:** `regen_sandbox_manifest` runs `${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}/tools/gen-checksums.sh --root "$ws"` (`:383-386`), and that script `source`s its own tree's `.claude/scripts/compat-lib.sh` (`head/tools/gen-checksums.sh:51`). The branch needs `$ws` to be a git repo tracking `.claude` (`:384-385`); `pipeline-run.sh:476` excludes `/.claude/` from the sandbox repo and `execute-agent.sh` never initialises one, so the branch is dead today and carries the trust hole for whoever first makes it live.
- **Fix:** Delete the tool branch and keep the inline hashlib path (it produced a manifest `check-loa.sh` accepts in the review's run), or run only `$_SM_REPO_ROOT`'s copy.
- **Reference:** CWE-829 — https://cwe.mitre.org/data/definitions/829.html

### [MED-003] Unused `brbuild` stage fails the image under the classic builder
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/Dockerfile.ablation:19`
- **Issue:** `FROM rust:1-bookworm AS brbuild` + `cargo install beads_rust --version 0.2.6 …` (`:20`) is never `COPY --from`'d and `:82` says the crate is not on crates.io. BuildKit skips the unused stage; the classic builder (`DOCKER_BUILDKIT=0`) builds every stage and the `cargo install` fails twice, failing the image build.
- **Fix:** Delete the stage (the comment already records the decision not to ship `br`).
- **Reference:** CWE-1164 Irrelevant Code — https://cwe.mitre.org/data/definitions/1164.html

### [MED-004] Codex credentials are exposed to every container arm, and survive a SIGKILL
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:570`
- **Issue:** `make_home` copies `$CREDS_HOME/.codex/auth.json` and `config.toml` into `meta/home`, bind-mounted rw at `/home/evaluser`, for every container run (`:574`), including arms that never run a codex hop (`a0_bare`, `a4_no_gates`). The agent under test runs with `--dangerously-skip-permissions`, Bash and WebFetch, and `--network bridge`, so it can read and exfiltrate the operator's codex token. The copy is removed by `remove_tree` only on trapped exits (`:348`, `:356`); a SIGKILLed driver leaves it under `meta/home` while the header says it "is deleted at exit and on interrupt" (`:82`). The Bedrock token in the agent's environment is a necessary exposure; the codex copy is not, for most arms.
- **Fix:** Copy the codex files only when the phase plan includes a gate and gates are on; refuse to start when `meta/home` already exists; document the residual-on-SIGKILL case or sweep it at the next run.
- **Reference:** CWE-522 Insufficiently Protected Credentials — https://cwe.mitre.org/data/definitions/522.html

### [MED-005] `run_phase` size and the duplicated phase plan
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/pipeline-run.sh:634`
- **Issue:** `run_phase` is 235 lines (argv assembly, launcher, capture, watchdog, reaping, result parsing, snapshot, verdict, pricing, exit decision). The phase-plan jq at `:215-229` is duplicated verbatim in `head/evals/harness/took-effect.sh:92-105`, so a change to one silently desynchronises the proof from the plan. The capture bug in HIGH-003 would have been a one-line fix in a `capture_argv` helper.
- **Fix:** Extract the capture (`:701-712`), record (`:813-851`) and account-and-decide (`:853-867`) blocks; move the plan jq into one shared file both scripts read.
- **Reference:** CWE-1120 Excessive Code Complexity — https://cwe.mitre.org/data/definitions/1120.html

### [LOW-001] Preflight's file count follows the manifest symlink to pick the tree
- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/preflight.sh:181`
- **Issue:** `MANIFEST_LINK=$(readlink …/.claude/checksums.json)` … `MANIFEST_TREE=$(cd "$(dirname "${MANIFEST_LINK}")/.." && pwd -P)` (`:181-185`): whoever controls the symlink chooses the tree whose `git ls-files -- .claude` count is compared; a zero count falls back to the legacy `find` count (`:193-195`). The check is count-only and was weak before; the PR adds the symlink-chosen tree. (Cross-model DISS-C-002.)
- **Fix:** Restrict the resolved target to `PROJECT_ROOT` or `.loa/`, or call `check-loa.sh`'s sha256 verification instead of counting.
- **Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

### [LOW-002] Dissent envelopes are agent-authored evidence
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-row.sh:201`
- **Issue:** `voices_run` and the DEGRADED / voice-shortfall causes come from `sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json` first (`:200-203`; same in `head/evals/harness/took-effect.sh:86-89`), which the agent under test can write; the `eval/` fallback is a copy of the same file taken after the phase (`head/evals/harness/pipeline-run.sh:776-778`), so neither copy is harness evidence. (Cross-model DISS-C-003; the review's LOW.)
- **Fix:** Cross-check `voices_run` against the MODELINV rows of the gate phases (the row already joins them); record the envelope's source path and sha256 in the row.
- **Reference:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

### [LOW-003] `dot_claude_writes` sees Write/Edit tools only
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-row.sh:218`
- **Issue:** The zone-violation metric counts `Write`/`Edit`/`MultiEdit`/`NotebookEdit` tool_use inputs whose path matches `(^|/)\.claude/` (`:216-220`); `.claude/` edits through Bash (`sed -i`, redirection, `cp`, `git checkout`) are invisible, so the metric under-reports. (Cross-model DISS-C-004.)
- **Fix:** Add an effect-based check: hash `sandbox/.claude` against the regenerated manifest after the run (`took-effect.sh:233-268` already does this walk) and record drift as a violation.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-004] A hardcoded home-directory binary is executed
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/fingerprint.sh:54`
- **Issue:** `BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"` is run with `--version` when bats is not on PATH; identical toolchains fingerprint differently by host, and a planted binary at that path is executed. (Cross-model DISS-C-005; the review's LOW.)
- **Fix:** Drop the fallback; `LOA_EVAL_BATS_BIN` / `--bats-bin` already exist.
- **Reference:** CWE-426 Untrusted Search Path — https://cwe.mitre.org/data/definitions/426.html

### [LOW-005] Placeholder pricing drives the codex hop's estimates
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/defaults/model-config.yaml:143`
- **Issue:** `gpt-6.1-sol` ships gpt-5.5 prices marked `PLACEHOLDER` (`:143-149`) and becomes `cli_model` for every `codex-headless` hop (`:240`), so MODELINV/ledger estimates for codex calls use an unverified rate card with no machine-readable marker. (Cross-model DISS-C-006.)
- **Fix:** Add `pricing.placeholder: true` surfaced as `pricing_source=placeholder`; close the confirmation bead before release.
- **Reference:** CWE-1053 Missing Documentation for Design — https://cwe.mitre.org/data/definitions/1053.html

### [LOW-006] Stale codex version in two headers
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/pipeline-run.sh:85`
- **Issue:** The header says the image pins "codex 0.137.0"; `head/evals/harness/Dockerfile.ablation:25` pins `CODEX_VERSION=0.162.1`; `head/evals/harness/fingerprint.sh:13` repeats the stale note.
- **Fix:** Align the comments with the Dockerfile.
- **Reference:** CWE-1053 — https://cwe.mitre.org/data/definitions/1053.html

### [LOW-007] Whole-tree mount preserves symlinks against its contract
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:131`
- **Issue:** `cp -a "$tree/.claude/." "$ws/.claude/"` preserves symlinks while the contract at `:18-19` says "files, never a symlink to the tree"; a source tree that is itself a submodule mount yields dangling links in the sandbox.
- **Fix:** `cp -aL`, or check and document the real-files precondition.
- **Reference:** CWE-59 — https://cwe.mitre.org/data/definitions/59.html

### [LOW-008] Test header refers to a case that does not exist
- **Severity:** LOW (confidence: high)
- **File:** `head/tests/unit/gen-checksums.bats:9`
- **Issue:** "manifest is only read by GC-8" — the file defines GC-1…GC-7.
- **Fix:** Add the case (mirroring MP-6) or fix the comment.
- **Reference:** CWE-1053 — https://cwe.mitre.org/data/definitions/1053.html

---

## Observations

None excluded. Every high in this report is tallied; no finding was marked speculative. The review's trailer carries `excluded: 0`, so there are no demotions to confirm (`excluded_confirmed: 0`).

Dismissed after tracing:
- The arm-id leak guard at `head/evals/harness/pipeline-run.sh:506` greps the whole sandbox, including the mounted `.claude/`, for the arm id; with the suite's ids (`a0_bare` … `a7_effort_medium`) nothing in this `.claude/` tree collides, so no false infra error today.
- `head/evals/harness/pipeline-run.sh:586` executes `pricing.py` from `$REPO_ROOT/.claude/adapters` — the harness's own trusted copy, not the mounted tree; acceptable, though the header's "No .claude/ code" wording at `:125` is imprecise.
- Review DISS-C-002 (`return 0` in `check_integrity`): the exit code is driven by `FAILURES` (`head/.claude/scripts/check-loa.sh:36`, `:603-605`); not a regression.

---

## Cross-Model Security Observations

Adversarial security dissent ran on `pr/head.diff` (`grimoires/loa/a2a/sprint-1/adversarial-audit.json`; primary `gpt-5.5-pro` answered by `codex-headless` with status `clean`, companion `claude-headless` with 6 findings; `verdict_quality`: 2/2 voices, consensus, `status: APPROVED`; `metadata.degraded: false`; no `locality.degraded_security_review`). Triage:

- DISS-C-001 (MEDIUM, `check-loa.sh:75-76` not-mounted hides deletion) — confirmed by cross-model review; MED-001.
- DISS-C-002 (LOW, `preflight.sh:183-191` symlink-chosen tree) — confirmed; LOW-001.
- DISS-C-003 (LOW, envelopes read from the sandbox) — confirmed; LOW-002.
- DISS-C-004 (LOW, `dot_claude_writes` misses Bash writes) — confirmed; LOW-003.
- DISS-C-005 (LOW, hardcoded bats path) — confirmed; LOW-004.
- DISS-C-006 (LOW, placeholder pricing) — confirmed; LOW-005.

The primary voice returned no findings; its `status_note` ("not an approval of unreviewed surface") is noted. No `advisory_voices` present.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace (the directory is absent), so documentation coherence was verified manually against the implementation for Task 1.1:

| Check | Result |
|-------|--------|
| Script headers describe behaviour | Three mismatches: the trust-boundary promise at `sandbox-mount.sh:75` / `pipeline-run.sh:125` vs HIGH-001; codex version at `pipeline-run.sh:85` / `fingerprint.sh:13` vs `Dockerfile.ablation:25` (LOW-006); `gen-checksums.bats:9` GC-8 (LOW-008) |
| Security-critical code commented | Yes: secret handling, the exec shim, the two-mount launcher and the leak guards are explained inline |
| Secrets / internal URLs in docs or comments | None found; one operator-specific home path in `fingerprint.sh:54` (LOW-004) |
| Auth/crypto changes documented | The not-mounted classification is documented at `check-loa.sh:47-56`; its blind spot (MED-001) is not |
| CHANGELOG security entries | No CHANGELOG in the diff; `.loa-version.json` bumps to 2.0.0-rc.5 and `CLAUDE.loa.md` bumps its version with an unchanged body hash, consistent |

---

## Rubric Scores

| Dimension | Score (1–5) | Justification |
|-----------|-------------|---------------|
| Security | 3 | Strong secret hygiene and container confinement; one live trust-boundary violation (HIGH-001), one dead one (MED-002), weakened deletion detection (MED-001), avoidable credential exposure (MED-004) |
| Architecture | 3 | Clear single-executor design and mount-library contract; `run_phase` monolith and duplicated plan logic (MED-005) |
| Code Quality | 3 | Careful validation and tests; portability regressions on the declared jq floor (HIGH-002/003), unbounded argv (HIGH-004), header drift |
| DevOps | 2 | Two new gates red on the PR's own head (HIGH-005/006); dead Dockerfile stage (MED-003) |
| Blockchain/Crypto | n/a | Not applicable |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the Bedrock token travels by name; captures record `<set>`)
- [x] Input validation at trust boundaries (arm ids, sprint labels, task ids, numeric caps, toggle enums; `..`/absolute refused for review-catch fixtures)
- [ ] No code from the tree under test executed by the harness — **HIGH-001**, MED-002
- [x] No shell `eval`; the exec shim closes descriptors above 2 and keeps an allowlist
- [x] Dependencies pinned (yq by SHA-256, CLIs by exact version, base image by digest)
- [x] Error messages do not leak the token
- [ ] Integrity controls preserved — MED-001 (deletion undetected in submodule mode), LOW-001
- [ ] Tests cover security paths and run green — HIGH-005, HIGH-006 (gates red on head)

---

## Scope limits and process notes

- Phase 0 prerequisite: the review's `engineer-feedback.md` says CHANGES REQUIRED, not "All good". The audit ran anyway on the operator's explicit instruction for this evaluation (`pr/AUDIT-INSTRUCTIONS.md`: skip pre-flight steps that need artefacts absent here; do not ask questions). Recorded here rather than halting.
- `grimoires/loa/known-failures.md` is absent (the session hook reported the surface degraded); triage proceeded without it.
- `security-audit-scope.sh` is web-application oriented and found one file-operations sink; the recon catalogue above was built by hand.
- Not runnable here: `validate-suite.bats`, `freeze.bats`, `arm-toggles.bats`, `run-arms.bats` (fixtures outside the diff), the Docker build, and any upstream manifest inspection.
- `br` is not installed; no beads comment or label was written.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Close HIGH-001: write the opt-out marker from the harness or run the trusted copy; add the no-exec-from-sandbox test.
2. Fix the jq 1.6 incompatibilities (HIGH-002) and the NUL-split truncation (HIGH-003), or declare and check a jq ≥ 1.7 floor; add a jq 1.6 CI leg.
3. Move `ablation-row.sh`'s large inputs off argv (HIGH-004).
4. Regenerate and commit `.claude/checksums.json`; commit `evals/tests/fixtures/ablation-runs/runs/` (HIGH-005, HIGH-006).
5. Address the mediums at your discretion; MED-002 and MED-003 are deletions, MED-004 is a condition on `make_home`.
6. Run `/implement sprint-1` to fix, update `reviewer.md`, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":6,"medium":5,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:48:00Z"} -->
