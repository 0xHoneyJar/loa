# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)
**Scope:** `pr/head.diff` — 12 files, +719/-164, in the evals harness (grader 1.2.11, per-kind run caps DEC-0567, KF-048 codex credential handling, suite v2 ids). Lines cite `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope notes

- **Prerequisite deviation.** The skill's Phase 0 requires `engineer-feedback.md` to say "All good". The review of 2026-10-22 ended CHANGES_REQUIRED (2 HIGH, 2 MEDIUM, 4 LOW). The task instruction orders the audit regardless, so it ran; this report is an audit of the same unchanged head, not a post-fix re-audit.
- **Input guardrail:** `guardrails-orchestrator.sh --skill auditing-security` → PROCEED.
- **Scope script:** `security-audit-scope.sh --json` over `pr/head/` reports 0 sources, 0 sinks, 0 auth files (its heuristics target web apps). Manual recon in `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`.
- **Integrity pre-check:** `integrity_enforcement` is unset in `.loa.config.yaml`; no drift check applied.
- **Known failures:** `grimoires/loa/known-failures.md` is absent (SessionStart WARN); triaged without it.
- **Unable to assess:** the bats suites could not be run. `evals/` is not in `/workspace`, and the v2 task directories, `seed-bugfix.sh` / `seed-refactor.sh` (now called with `--suite-version`, `head/evals/tests/seed-bugfix.bats:80`, `seed-refactor.bats:78`) and the `a0_bare` toggles are outside `pr/`. Every test claim below rests on reading the assertions.
- **Beads:** `br` is not installed; no beads comment or label written.

## Executive Summary

The change is careful where it handles credentials: the per-run codex `auth.json` copy replaces the single-use refresh token with a placeholder, is written through an `O_CREAT|O_TRUNC` 0600 descriptor under a 0700 HOME, is removed on any failure, never writes the host file, and keeps every token value out of argv, logs and `REFUSED.txt` (`head/evals/harness/pipeline-run.sh:627-644`; tests at `pipeline-run.bats:741-787`, `run-ablation.bats:664-674`). The pre-flight reads only the JWT `exp` claim with `python3 -I`. The per-kind caps thread through every spend site (`account_row`, both `collect` fallbacks, `spend_charge`, `budget_gate`, dispatch argv) and `--resume` is manifest-authoritative; the `--types` jq fix is correct.

Two defects in the grading and pre-flight logic block the merge, both confirmed independently of the review by reading the head files and recomputing: the grader's new `remove_colliding` reserves every `.py` basename under a fixture `tests/` directory and every overlay basename, then deletes matches anywhere in the graded tree, so a correct solution's own `src/<pkg>/helpers.py` is removed before `test_command` runs; and the codex horizon sums `2 × watchdog_s` over the whole plan including `a0_bare` and already-finished trials, which refuses full-suite batches and late resumes with a remedy that cannot satisfy it (RAB-30's own comment pins `a0_bare`'s 9600 s inside the horizon while `codex_arms` is `["a1_full"]`).

The security dissent (two voices, both succeeded, zero rejected payloads, not degraded) raised no CRITICAL or HIGH. Its MEDIUM — the access token, id token and any `OPENAI_API_KEY` are still mounted into the container where the agent under test runs — is a pre-existing exposure that this change narrows (the base copied the refresh token too), recorded under Observations and not tallied as introduced here.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 6 |

**Overall Risk Level:** MODERATE (rubric 3.7/5; the verdict is driven by the counts above, not the score)

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Grading integrity — `remove_colliding` deletes agent source modules

**Severity:** HIGH | **Confidence:** medium
**File:** `head/evals/harness/ablation-grade.sh:1081` (overlay basenames, no filter), `:1087` (every fixture `.py` under `tests/`/`test/`), `:1090-1099` (whole-tree walk and unlink)
**Criterion:** CQ correctness / CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html
**Issue:**
```python
reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}                       # 1081
...
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))  # 1087
...
for r, ds, fs in os.walk(tree, followlinks=False):                                          # 1090
    ...
    if rel in owned or rel.startswith(owned_dirs) or (fx and os.path.lexists(...)): continue
    found.append((rel, os.path.join(r, name)))
for _rel, p in found:
    os.unlink(p)                                                                            # 1099
```
Three over-reaches combine. (a) Line 1087 reserves support modules pytest never collects (`helpers.py`, `utils.py`, `fixtures.py`). (b) Line 1081 reserves every overlay basename, so an overlay carrying `tests/__init__.py` reserves `__init__.py` and every package initialiser the agent created is deleted. (c) The walk at 1090-1097 is not restricted to package-less test directories: a match under `src/` is removed although pytest names it `pkg.helpers` and no collision can occur.
**Impact:** Fixture has `tests/helpers.py` (the grader header at `:221-222` names `from helpers import …` as a fixture-suite pattern); the agent implements the feature in `src/<pkg>/helpers.py`; `prepare()` deletes it; every test raises `ModuleNotFoundError`; `hidden_tests` is 0/N and `grade.json` shows only `colliding_tests_removed: 1`. Arms that add more modules (the full pipeline) are penalised more than BARE, biasing the H1 contrast the suite measures. The sandbox itself is never written (AG-35 asserts), so no data is lost; the row is wrong.
**Fix:** Reserve only collected test-module basenames (`test_*.py` / `*_test.py`, honouring `pytest.ini` `python_files` when present) from the fixture and from the overlay, never `__init__.py`; restrict the walk to the directories `test_command` collects from, or at minimum skip any directory containing `__init__.py` and `src/`-style package trees; keep `.colliding-removed.txt` and the count. Add AG cases: fixture `tests/helpers.py` + agent `src/pkg/helpers.py` kept; overlay `tests/__init__.py` + agent `src/pkg/__init__.py` kept; agent `tests/pkg/__init__.py` + `tests/pkg/test_slug.py` kept.
**Cross-model:** Confirmed by both voices of the review's dissent (DISS-001, DISS-C-001); this audit's dissent touched the function only for the gap in LOW-… below.

### [HIGH-002] Availability — the codex horizon refuses the batches the suite defines

**Severity:** HIGH | **Confidence:** medium
**File:** `head/evals/harness/run-ablation.sh:806` (formula); `:793-794` (`uses_codex` filters `codex_arms` but not the sum); header `:116` ("on --resume the whole recorded plan counts")
**Criterion:** SEC-AV / ARCH-RE; CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html
**Issue:**
```python
required = int(math.ceil(now + 2 * sum(float(e.get("watchdog_s") or 0) for e in plan) / max(conc, 1)))
```
`watchdog_s` is already `2 × phase_sum` (RAB-1: a1 build phase_sum 140 min → watchdog 16800 s), so the horizon is about four times the summed phase time per concurrency slot. The sum includes `a0_bare` trials (which the same block says never run the dissent) and, on `--resume`, every already-rowed trial. RAB-30's comment (`run-ablation.bats:694`) documents it: `required_until = now + 2 x (9600 + 16800) / 3` with `codex_arms == ["a1_full"]` — the 9600 is `a0_bare`'s.
**Impact:** With the RAB-1 figures (a1 build 16800 s, a0 build 9600 s, concurrency 3):

| Batch | Σ watchdog_s | required horizon |
|-------|--------------|------------------|
| priority-v2-p1 (a0+a1 × 4 review × 3) | ≈ 172 800 | ≈ 32 h |
| a0+a1 × 12 build × 3 | 950 400 | ≈ 7.3 days |
| full suite (8 arms × 16 tasks × 3) | ≈ 5.8 M | ≈ 6 weeks |

The commit trail records a fresh token "valid to 2026-10-28" from a 2026-10-18 login, about ten days. The two-arm build batch is refused from day three of a token's life, the full suite always (even at concurrency 9), a `--resume` with three trials left on a large batch is refused the same way, and `--dry-run` pre-registrations with it. The refusal tells the operator to re-login, which cannot satisfy the horizon. Fail-closed: no data harmed, but the runner cannot run the suite's own batch shapes.
**Fix:** Sum only trials that will launch (not in the done set on `--resume`) and only for arms where `uses_codex` is true; use the phase sum or one watchdog rather than `2 × watchdog` (a run cannot exceed its watchdog); optionally cap the horizon at the token lifetime and WARN rather than refuse above it. Add RAB cases: an a0-heavy plan with a short token passes when only the a1 share fits; a `--resume` with one trial left needs one trial's horizon. Update header `:110-119` with the chosen formula.
**Cross-model:** Confirmed by both voices of the review's dissent (DISS-C-002 BLOCKING); not raised by this audit's dissent.

---

## Medium/Low Priority Issues

### [MED-001] Grading — directory overlays escape the collision rule
- **Severity:** MEDIUM | **Confidence:** low
- **File:** `head/evals/harness/ablation-grade.sh:1079-1081`
- **Issue:** `owned` excludes directory overlays and `owned_dirs` is only an exemption, so a hidden suite overlaid as a directory (`put_file` copies it as a tree, `:528-531`) contributes no basenames to `reserved`. An agent test file elsewhere with the same basename as a module inside that directory survives and the pytest "import file mismatch" abort 1.2.11 fixes still occurs, with `colliding_tests_removed: 0`. No suite in evidence overlays a directory, hence low confidence.
- **Fix:** `os.walk` each directory overlay and add its collected-module basenames to `reserved` with the same filter as HIGH-001.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-002] Credentials — the pre-flight guards `exp` but not the CLI's own refresh trigger
- **Severity:** MEDIUM | **Confidence:** low
- **File:** `head/evals/harness/pipeline-run.sh:635-636` (only `refresh_token` rewritten; `last_refresh` copied verbatim, asserted by `pipeline-run.bats:756`)
- **Issue:** [ASSUMPTION] If the codex CLI refreshes proactively when `last_refresh` is older than a threshold (rather than only on a 401), a per-run copy past that age attempts a refresh with the placeholder, fails, and the run loses the OpenAI voice although the pre-flight (which compares `exp` only) passed. The CLI's policy was not verifiable offline; the window is narrow because `exp` and `last_refresh` move together.
- **Fix:** Check the codex CLI refresh policy. If age-based, rewrite `last_refresh` in the copy to the copy time, or have the pre-flight refuse when `last_refresh + threshold` falls inside the horizon.
- **Reference:** CWE-672 — https://cwe.mitre.org/data/definitions/672.html

### [LOW-001] Configuration — false/null per-kind caps fall back silently
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/run-ablation.sh:502-503`
- **Issue:** jq's `//` treats `false` and `null` as absent. Verified: `run_usd_by_type: {build: false}` and `run_usd_by_type: false` both yield the empty string, so the single-cap fallback applies although the comment at `:499` and header `:188-189` promise a usage error for a present malformed entry.
- **Fix:** Test with `has($k)` and `type == "number" or type == "string"`; add a RAB-22 case for `build: false`.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-002] Configuration — a zero run cap is accepted
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/run-ablation.sh:505` (per-kind), `:452` (manifest caps on `--resume`), `:366` (`--run-cap`); `head/evals/harness/lib/arms-common.sh:56` (`usd_ok`)
- **Issue:** `usd_ok` matches `^[0-9]{1,6}(\.[0-9]{1,4})?$` and accepts `0`, `0.0`, `00` (verified). `--max-usd` refuses zero explicitly (`:365`) but the new per-kind entries do not. `pipeline-run.sh` accepts `--max-run-usd 0` (`:199`), so every trial of that kind ends `cap_failure` at its first phase, is charged a cap of 0, and `RESERVE_CAP` is 0 for a plan of that kind alone. Fail-closed on spend, but a typo'd `build: 0` burns a batch of trials.
- **Fix:** Refuse a zero cap after `usd_ok` at `:452`, `:505` and `:366` (or add a positive variant of `usd_ok`).
- **Reference:** CWE-1284 — https://cwe.mitre.org/data/definitions/1284.html

### [LOW-003] Error handling — an out-of-range `exp` crashes the pre-flight with a generic message
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/run-ablation.sh:829-830`
- **Issue:** The check at `:827` accepts any finite number; `time.gmtime` raises `OverflowError` for `1e300` or `2**63` and `OSError` for `1e17` (verified), so the heredoc exits non-zero and the batch dies with `the codex token pre-flight failed` instead of a KF-048 refusal naming the file; no `REFUSED.txt` or MANIFEST is written. A negative `exp` is accepted and refused as expired (harmless). Confirmed from this audit's dissent (DISS-C-002).
- **Fix:** Guard the range (e.g. `0 <= exp < 2**40`) and route the rest through `bad("the access token's exp is out of range")`.
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [LOW-004] Telemetry — `colliding_tests_removed` sums across up to four trees
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/evals/harness/ablation-grade.sh:1019` (accumulation), `:1708`, `:1723`, `:1748` (prepare on final, base, implement, fix1), `:1773` (field)
- **Issue:** The same agent file present in `final` and both snapshot trees counts three times. `harness_files_removed` follows the same convention, so this is consistent, but the field name reads as a file count and the per-tree `.colliding-removed.txt` files are the only disaggregation.
- **Fix:** Record the final tree's count, or name the field per tree.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [LOW-005] Tests — stale comment contradicts its assertion
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/tests/run-ablation.bats:95-97`
- **Issue:** The comment says "A0 BARE stays 70 min … (80) does not apply"; the assertion two lines later expects 9600 s = 80 min and its own trailing comment derives 80.
- **Fix:** Delete the "stays 70 min" sentence.
- **Reference:** CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-006] SIMPLICITY[shrink] — duplicated MANIFEST field
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/harness/run-ablation.sh:903`
- **Issue:** `codex_token_exp` repeats `codex_preflight.token_exp` byte for byte (RAB-30 asserts both equal `$exp`).
- **Fix:** Keep `codex_preflight` only; drop the three `codex_token_exp` assertions in RAB-30/31/32. Net −1 line.
- **Reference:** CWE-1041 — https://cwe.mitre.org/data/definitions/1041.html

---

## Observations

Not tallied. Pre-existing conditions, scope limits, and informational notes.

### 1. Residual credential exposure to the agent under test (pre-existing; narrowed by this change)
- **File:** `head/evals/harness/pipeline-run.sh:627-642`
- `make_home` still copies `tokens.access_token`, `tokens.id_token`, `tokens.account_id` and any top-level `OPENAI_API_KEY` verbatim into the per-run HOME that is bind-mounted read-write at `/home/evaluser` in the container where the LLM-driven agent runs arbitrary shell with provider network access. The pre-flight deliberately requires that access token to stay valid for the batch horizon. An agent (or prompt-injected task content) that runs `cat ~/.codex/auth.json` puts a live OpenAI bearer and an id token with account PII into a transcript that is stored under the results root. The base already copied the whole file including the single-use refresh token, so this change strictly reduces exposure. Raised by this audit's dissent (DISS-C-001, MEDIUM); recorded here because it is not introduced by the change. CWE-522 — https://cwe.mitre.org/data/definitions/522.html
- **Recommendation:** strip `OPENAI_API_KEY` from the copy when `auth_mode` is `chatgpt`; consider whether the dissent voice needs the id token at all; add `~/.codex/auth.json` to the grader's contamination/secret scan so a transcript that reads it is flagged.

### 2. Unverifiable test dependencies (scope limit)
- `head/evals/tests/seed-bugfix.bats:80` and `seed-refactor.bats:78` pass `--suite-version` to `seed-bugfix.sh` / `seed-refactor.sh`, neither of which is in the change; every RAB case now depends on `grimoires/loa/evals/ablation-2.0/tasks/*-v2-*` and on `a0_bare` carrying `toggles.loa_mount: false`. If the seed scripts lack the flag, SB-1 and SR-1 fail. Confirm on the base commit and attach a bats run log to the implementation report.

### 3. Host path disclosure in `REFUSED.txt` (informational)
- `head/evals/harness/run-ablation.sh:809`, `:803`: the refusal and WARN lines embed the absolute path of `auth.json` (the operator's `$HOME`). Not a secret; matches existing message patterns.

---

## Cross-Model Security Observations

Security dissent: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — primary `gpt-5.5-pro` (status `clean`, answered by `codex-headless`), companion `claude-headless` (`succeeded`, `counted_as: independent_voice`), `voices_succeeded 2/2`, `degraded: false`, `hallucination_filter.downgraded 0`. Not DEGRADED_SECURITY_REVIEW. Advisory input, never tallied on its own; every item was re-read against the head files.

- **DISS-C-001** (MEDIUM, `pipeline-run.sh:make_home:622`) — access token / id token / `OPENAI_API_KEY` reachable from the container. Triaged as pre-existing, narrowed by the change → Observation 1, not tallied.
- **DISS-C-002** (LOW, `run-ablation.sh:codex-preflight:829`) — out-of-range `exp` aborts generically. Confirmed by execution → LOW-003 (counted).
- **DISS-C-003** (LOW, `ablation-grade.sh:remove_colliding:1096`) — two parts. (a) "agent files under an `owned_dirs` prefix survive and still collide": **not a defect** — `put_file` (`:528-531`) removes the destination before copying a directory overlay, so no agent file survives under an overlaid directory. (b) a filename containing a newline makes `.colliding-removed.txt` ambiguous: real but trivial telemetry hygiene; folded into the LOW-004 remediation (write one JSON object per line if the file is ever parsed). Not tallied separately.
- The dissent did not raise HIGH-001 or HIGH-002; the review's dissent (two voices, `adversarial-review.json`) raised both as BLOCKING.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_sidecars` is `[]`, and `companion_voice.rejected_sidecar` is null.

---

## Review demotions

The review trailer carries `excluded: 0`; nothing to confirm. `excluded_confirmed: 0`.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.8/5 | IV:4 AZ:4 CI:3 IN:5 AV:3 |
| Architecture | 3.8/5 | MO:4 SC:4 RE:3 CX:4 ST:4 |
| Code Quality | 3.4/5 | RD:4 TC:4 EH:3 TS:3 DC:3 |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 AC:4 DS:4 |
| Blockchain | n/a | — |
| **Overall** | **3.7/5** | MODERATE |

Machine-parseable findings: `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — the placeholder `loa-ablation-no-refresh-token` is deliberately non-functional; test fixtures use `R`, `x.y.z`, `h.<payload>.s`
- [x] Input validation on all new inputs — caps `usd_ok`-checked (gaps: LOW-001, LOW-002); JWT payload type-checked (gap: LOW-003); `--types` list cleaned of empties
- [x] Authentication/authorization — host `auth.json` never written (hash asserted); per-run copy 0600 under 0700; refresh token never leaves the host
- [x] No injection — paths only in argv; `python3 -I` for every embedded script; jq `--arg`/`--argjson` throughout; no eval
- [x] Error handling doesn't leak info — refusal text carries ISO times and a file path only; `rm -f` on copy failure; `! grep` assertions for token material in `REFUSED.txt`, argv and output
- [x] Tests cover security paths — RAB-28…34, pipeline-run KF-048 ×3, AG-35; not executable here (Observation 2)
- [x] Documentation — no `documentation-coherence-*` reports exist; manually verified that every behavioural change has a header entry (`run-ablation.sh:110-119, 186-198, 222-237`; `pipeline-run.sh:83-88, 601-609`; `ablation-grade.sh:220-226`). No CHANGELOG in the diff; version headers serve that role in this repository.

---

## Threat Model Summary

**Trust boundaries:** operator host (`$HOME/.codex`) → harness (`run-ablation.sh`, `pipeline-run.sh`) → per-run HOME bind-mounted into the agent container (untrusted agent, provider network) → results root (transcripts, grade.json, MANIFEST) → grader reading the agent's sandbox tree.
**Attack vectors:** credential exfiltration by the agent under test (pre-existing, Observation 1): MEDIUM; grading manipulation through filenames (newline telemetry only; unlink confined to the grading copy, `followlinks=False`): LOW; malformed configuration (suite caps, auth.json): LOW, fail-closed.
**Mitigations in this change:** refresh token replaced; 0600 copy; `rm -f` on failure; `python3 -I`; exp-only JWT read; `--resume` manifest-authoritative caps.
**Residual risks:** access/id token in the container; grading over-deletion (HIGH-001) biasing arm comparisons; horizon refusals (HIGH-002) stalling the cycle.

---

## Positive Findings

- `make_home` is the right shape for a credential copy: `O_WRONLY|O_CREAT|O_TRUNC` with mode 0600, `fchmod`, paths only in argv, host file never opened for write, `rm -f` plus one WARN on any failure (`pipeline-run.sh:627-644`).
- The hermetic `LOA_EVAL_CREDS_HOME="$T/creds"` in `run-ablation.bats:34` means the test suite no longer reads a developer's real `~/.codex/auth.json`.
- Every spend site takes the kind's cap; `--resume` ignores `--run-cap` with a note and reads caps from MANIFEST (RAB-26).
- The `--types` fix is minimal and RAB-27 pins both the filter and the usage error.

---

## Next Steps

1. Fix HIGH-001 (reserved set and walk scope in `remove_colliding`) and HIGH-002 (horizon formula) with the listed regression cases.
2. Address LOW-001/002/003 in the same pass (they share the two touched blocks); MED-001/002 as judgment allows.
3. Run `bats evals/tests/ablation-grade.bats evals/tests/run-ablation.bats evals/tests/pipeline-run.bats evals/tests/seed-bugfix.bats evals/tests/seed-refactor.bats` and attach the log to the implementation report.
4. `/implement sprint-1` → `/review-sprint sprint-1` → `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:16:00Z"} -->
