# Sprint 1 Security & Quality Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** `grimoires/loa/sprint.md` (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** `grimoires/loa/a2a/sprint-1/reviewer.md` (the PR description, `pr/PR.md`)
**Review:** `grimoires/loa/a2a/sprint-1/engineer-feedback.md` — CHANGES_REQUIRED (0 critical, 3 high, 2 medium, 4 low, excluded 0)
**Scope:** `pr/head.diff` — 12 files, +720/−164: sprint-261 suite v2 freeze and per-kind run caps (DEC-0559, DEC-0567), the `--types` jq fix, KF-048 codex credential handling (`pipeline-run.sh make_home`, the `run-ablation.sh` token pre-flight), grader 1.2.11 (`remove_colliding`), and the bats updates
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a) over `pr/head/` with the two-voice security dissent on `pr/head.diff`

---

## Process notes

- **Phase 0 prerequisite not met, audit run anyway.** The review verdict is CHANGES_REQUIRED, so the skill's "All good" gate would stop here. The task brief for review-r25 orders the audit regardless, so this audit runs as an independent second gate and records the deviation. No `COMPLETED` marker is written.
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` does not exist in this workspace (SessionStart hook warning); triaged without it.
- **Input guardrails:** `guardrails-orchestrator.sh` → PROCEED (PII 0 redactions; the injection detector returned ERROR and was treated fail-open).
- **Scope script:** `security-audit-scope.sh` found no `src/`-style sources or sinks under `pr/head/` (the harness lives under `evals/`); the surface was catalogued by hand in `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.
- **Not verifiable here:** the twelve v2 task directories, `seed-bugfix.sh` and `seed-refactor.sh` are outside the PR files. `pr/head/.run/audit.jsonl` is a hook artifact of the review session in this workspace, not part of `pr/head.diff`, and is not a finding.
- **Security dissenter (Phase 1C):** `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff` → `adversarial-audit.json`: status `clean`, `metadata.model` gpt-5.5-pro (answered by codex-headless, 0 findings), companion claude-headless `succeeded`, `independent_voice`, 2 findings (DISS-C-001 MEDIUM, DISS-C-002 LOW); 2/2 voices, `degraded: false`, `rejected_count` 0, no `locality.degraded_security_review` marker. Not a DEGRADED_SECURITY_REVIEW. The diff was truncated to the primary's budget (run-ablation.bats shown 6 of 28 hunks).

---

## Executive Summary

The credential handling in this change is careful where it touches secrets: the per-run `auth.json` is rewritten through a `python3 -I` snippet with paths only in argv, written `0600` into a fresh per-run HOME, the host file is never opened for writing, and no token value reaches a log, a refusal message or the docker argv (`head/evals/tests/pipeline-run.bats:949-957`, `RAB-28`). The per-kind cap plumbing (`cap_for`, `spend_charge`/`budget_gate` cap parameters, the manifest `run_usd_by_type`, the `--resume` precedence) validates every cap with `usd_ok` before it reaches awk or `--max-run-usd`, including caps read back from `MANIFEST.json`. The `--types` fix is correct.

Three defects block the merge, all confirmed independently in code and two of them by the cross-model dissent. Grader 1.2.11's `remove_colliding` deletes files of a correct solution that pytest would never confuse with a hidden test (the reserved set is every fixture `.py` under `tests/`/`test/` plus every overlay `.py` basename, and the walk covers the whole grading tree), and it never reserves the test modules of a directory-shaped hidden overlay, so the collision it was written for persists silently for those tasks. The KF-048 pre-flight refuses any present `auth.json` that lacks a JWT `tokens.access_token`, which locks out codex API-key authentication with a misleading "run codex login" message. All three corrupt or block the measurement the harness exists to make: a false deletion is graded as an agent failure, and a refused batch cannot run.

Three medium items narrow the pre-flight's usefulness further (a 4× over-estimated horizon that also counts finished trials on `--resume`; host-executor batches refused although the host CLI keeps a real refresh token; an unverifiable `--suite-version` dependency in two seed tests), and four low items are hygiene. The dissenter's MEDIUM on the access token remaining readable by the agent inside the container is recorded as a pre-existing, now narrower exposure, not a defect this change introduces.

**Overall Risk Level:** HIGH (quality/availability of the grading and batch paths; no secret-exposure regression)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 3 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.6/5 | IV:4 AZ:4 CI:3 IN:5 AV:2 |
| Architecture | 3.8/5 | MO:4 SC:4 RE:3 CX:4 ST:4 |
| Code Quality | 3.8/5 | RD:4 TC:4 EH:4 TS:3 DC:4 |
| DevOps | 3.8/5 | AU:4 OB:4 RC:4 AC:4 DS:3 |
| Blockchain | n/a | — |
| **Overall** | **3.7/5** | *Security weighted highest* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Grader 1.2.11 `remove_colliding` deletes solution files that cannot collide under pytest

**Severity:** HIGH | **Confidence:** medium | **Score:** 2/5
**Component:** `head/evals/harness/ablation-grade.sh:1081` (overlay basenames, no `__init__.py` exclusion), `:1086-1087` (every fixture `.py` under a `tests/` or `test/` path component, helpers included), `:1090-1100` (walk over the whole grading tree, then `os.unlink`)
**Criterion:** SEC-IV Input Validation (what is treated as a collision) / CQ-TC Test Coverage
**Confirmed by cross-model review:** DISS-C-002 (claude-headless, LOW) names the same path.

**Reasoning Trace:**
> Traced the agent's sandbox → `copy_tree` → grading tree → `prepare` (`:1019`) → `remove_colliding`. `reserved` is built at `:1081` from `{d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}` with no exclusion, and at `:1086-1087` from `reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))` for every fixture directory whose path holds a `tests`/`test` component. The walk at `:1090` is `os.walk(tree, followlinks=False)` with no directory pruning (`copy_tree`'s `EXCLUDE_TOP` at `:319` drops only `.git`, `.claude`, `grimoires`, …; `src/`, `.venv/`, `node_modules/` stay). The keep conditions at `:1096` are overlay dest, overlay dir, or a path present in the fixture — not "is a module pytest collects".

**Description:** pytest's "import file mismatch" arises only between modules it imports for collection (`python_files`: `test_*.py`, `*_test.py`; plus `conftest.py`) that sit in package-less directories, because the default prepend mode names them by basename. The 1.2.11 header itself says the suites import sibling modules (`import _oracle_x`, `from helpers import …`): those are exactly the basenames the fixture walk reserves, and an agent module with that basename under `src/` or inside a package is imported package-qualified and never collides. Concrete failing inputs: fixture `tests/helpers.py` + agent `src/app/helpers.py` → deleted → `ImportError` in the hidden run; overlay `tests/hidden/__init__.py` + agent `src/newpkg/__init__.py` (a feature-build that adds a package) → deleted → `ModuleNotFoundError`; a refactor that moves `tests/test_x.py` to `tests/unit/test_x.py` loses the moved module. `grade.json` records the loss only as `colliding_tests_removed` (`:1773`), so the row reads as an agent failure.
**Impact:** A correct solution is graded as failing on the grading path of the harness that produces the H1/A4 measurement; the bias is silent (the sandbox is untouched, the only trace is `grading/<label>.colliding-removed.txt`). AG-35 (`head/evals/tests/ablation-grade.bats:1105`) passes only because its colliding file is itself a test module.
**Remediation:** Build `reserved` only from basenames pytest collects (`test_*.py`, `*_test.py`, honouring `python_files` from `pytest.ini`/`pyproject.toml` when present); exclude `__init__.py` and `conftest.py` from the overlay-derived set at `:1081` as well; restrict the walk to the directories the task's `test_command` targets, or at least prune `.git`, `.venv`/`venv`, `node_modules`, `__pycache__`; skip a candidate whose directory chain up to the tree root holds an `__init__.py`. Add bats cases: fixture `tests/helpers.py` + agent `src/helpers.py` kept; overlay `__init__.py` + agent package `__init__.py` kept.
**References:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html ; pytest import modes — https://docs.pytest.org/en/stable/explanation/pythonpath.html

### [HIGH-002] Directory-shaped hidden overlays are never reserved, so the targeted collision still aborts collection — silently

**Severity:** HIGH | **Confidence:** medium | **Score:** 2/5
**Component:** `head/evals/harness/ablation-grade.sh:1079-1081`
**Criterion:** CQ-TC Test Coverage / ARCH-RE Resilience

**Reasoning Trace:**
> `owned = {d for _s, d, f in t.overlay if not os.path.isdir(f)}` (`:1079`) keeps only file-shaped overlay entries and `reserved` (`:1081`) is derived from `owned`. Directory overlays are a supported shape: `put_file` at `:530-531` copies a directory source whole, `owned_dirs` at `:1080` exempts their paths, and `GRADER_SOURCES` at `:1703` likewise filters `os.path.isfile`. Nothing walks a directory overlay's contents for basenames.

**Description:** For a hidden suite delivered as `tests/hidden/` containing `test_slug.py`, an agent-added `tests/extra/test_slug.py` is kept, pytest aborts collection on the basename clash, the correct solution is graded as failing, and `grade.json` reports `colliding_tests_removed: 0` — the operator believes the guard ran. The 1.2.11 header promises removal for "a Python file … whose basename equals a hidden overlay's"; for directory overlays that promise is false.
**Impact:** Same false-failure class as HIGH-001 with a false negative on top: the telemetry says no collision happened.
**Remediation:** When building `reserved`, also `os.walk` each directory overlay source and add the basenames of its collected test modules (with the HIGH-001 exclusions), or derive `reserved` from the grading tree after `put_file` (every collected `.py` under overlay dests, files and directories). Add a bats case with a directory overlay.
**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-003] KF-048 pre-flight refuses API-key codex authentication with a misleading remedy

**Severity:** HIGH | **Confidence:** medium | **Score:** 2/5
**Component:** `head/evals/harness/run-ablation.sh:816-817` (`bad("has no tokens.access_token")`), `:819-820` (three-part JWT check), `:841` (`refuse`)
**Criterion:** SEC-AZ Authorization (a valid credential mode is rejected) / SEC-AV Availability

**Reasoning Trace:**
> The pre-flight runs for every non-smoke batch, `--dry-run` and `--resume` (`:784-841`). After `present` (`:795`) and the JSON parse (`:810-813`) it requires `tok.get("access_token")` to be a non-empty string (`:815-817`) and a three-part JWT (`:818-820`), else `bad()` → `refuse` → `REFUSED.txt`, exit 2, no `MANIFEST.json`. The codex CLI's API-key mode stores `OPENAI_API_KEY` with no `tokens` object; the PR's own fixture (`head/evals/tests/pipeline-run.bats:928`) carries that key beside `auth_mode`. No branch recognises it, and no flag skips the check.

**Description:** An API-key `auth.json` has no expiring JWT and no refresh-token hazard — KF-048 is about the ChatGPT refresh flow — yet the file is refused as broken and the message tells the operator to `codex login`, which would not change the file shape. Before this change such a host ran batches normally (`pipeline-run.sh make_home` still copies the key, `:634-640`).
**Impact:** Every batch, dry run and resume with a codex-using arm is unstartable for a working configuration, with no override.
**Remediation:** Before the JWT checks, recognise API-key auth (`data.get("OPENAI_API_KEY")` a non-empty string, or `auth_mode == "apikey"`), record `checked: false` with a reason and continue. Add a RAB case with an API-key `auth.json`.
**References:** CWE-287 Improper Authentication — https://cwe.mitre.org/data/definitions/287.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Pre-flight horizon double-counts the watchdog factor and counts finished trials on `--resume`

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:806`
**Description:** `required = now + 2 * sum(watchdog_s) / concurrency`, but `watchdog_s` is already `2 * s * 60` (`:772`), so the horizon is 4× the summed phase time over concurrency; on `--resume` the recorded plan (`:718`) includes trials that already have rows. For a full-suite batch (8 arms × 16 tasks × 3 trials) the horizon is weeks, longer than any ChatGPT codex access token lives (the operator's re-login on 2026-10-17 was valid to 2026-10-28), so such a batch is refused however fresh the login — while `make_home` re-copies the host's `auth.json` per trial, so a host re-login mid-batch already reaches later trials.
**Impact:** The guard makes long batches unrunnable instead of protecting them.
**Remediation:** Drop the extra 2×, exclude plan entries that already have rows on `--resume`, and consider bounding by what one trial needs (`max(watchdog_s)` plus margin) with the batch-level comparison as a WARN. Document that re-login mid-batch propagates.

### [MED-002] Pre-flight applies to `--executor host`, where the premise (placeholder refresh token) does not hold

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:784-841` (no executor input to the check); `head/evals/harness/pipeline-run.sh:648` (`make_home` runs only in container mode), `:465` (host branch)
**Description:** The pre-flight's rationale (`:780-782`, header item 6 at `:110-121`) is that the per-run HOME "cannot renew an expired access token". That is true only in container mode: `make_home` is gated `[[ "$EXECUTOR" == container ]]` (`pipeline-run.sh:648`), and in host mode the codex CLI reads the operator's real `auth.json` with its real refresh token and renews normally. The pre-flight never reads `EXECUTOR`, so a host batch whose token expires within the (over-estimated, MED-001) horizon is refused although nothing would degrade. The checked path (`${LOA_EVAL_CREDS_HOME:-$HOME}`) can also differ from the HOME the host CLI uses.
**Impact:** Unneeded refusals of host-mode batches; the manifest's `codex_preflight` record describes a hazard that does not apply to the recorded `executor_mode`.
**Remediation:** Pass `$EXECUTOR` into the pre-flight and record `checked: false` (reason `host executor renews`) when it is `host`, or downgrade to WARN there. Add a RAB case.

### [MED-003] Seed tests depend on a `--suite-version` flag not evidenced in this change

**Severity:** MEDIUM | **Confidence:** low
**Component:** `head/evals/tests/seed-bugfix.bats:80`, `head/evals/tests/seed-refactor.bats:78`
**Description:** Both tests now pass `--suite-version "$(yq -r .suite_version …)"` to `seed-bugfix.sh` / `seed-refactor.sh`, which are not in `pr/head.diff`; no touched or base file shows the flag exists. If the scripts reject unknown flags, SB-1 and the refactor seed test fail before their `candidate` assertion; if they ignore it, the seeded task keeps `suite_version: 1` and `validate-suite` rejects it against the suite's 2 — the failure the edit tries to avoid. Not verifiable from the PR files.
**Remediation:** Confirm the seed scripts accept `--suite-version` (or add it in this PR, defaulting to the suite file's value) and reference the commit that added it in the PR description.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Stale RAB-1 comment contradicts its assertion

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/tests/run-ablation.bats:95-97`
**Description:** The comment says "A0 BARE stays 70 min … the PLAN + IMPLEMENT + 2 x FIX derivation (80) does not apply"; the assertion on `:97` expects `9600` s (80 min) with the opposite explanation, and RAB-27 asserts `phase_sum_min` 80.
**Remediation:** Delete the stale sentence.

### [LOW-002] `colliding_tests_removed` accumulates across every prepared tree

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1019`, `:1773`; `prepare` is called at `:1708`, `:1723`, `:1748`
**Description:** `COLLIDING[0] += remove_colliding(t, tree)` runs for the final, base, implement and fix1 trees, so one colliding agent file is reported as 2 or 3 when snapshots are graded; AG-35 covers the final tree only.
**Remediation:** Count distinct paths, or document the field as "per prepared tree".

### [LOW-003] `suite_kind_cap` silently skips a `null`/`false` per-kind entry the header calls a usage error

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/run-ablation.sh:502-505`
**Description:** `(.[$k] // "" | tostring)` maps an explicit `build: null` or `build: false` to the empty string, which `:505` treats as "no entry" and falls back to `RUN_CAP`, while the header (`:189-190`) and the comment at `:496` say "a present entry that is not an amount in USD … is a usage error". Operator input at a trust boundary is accepted differently from how it is documented.
**Remediation:** Use `has($k)` to distinguish absent from present-but-invalid and `die` on the latter; add a RAB-22 sub-case.

### [LOW-004] Pre-flight horizon ignores `LOA_ABLATION_WATCHDOG_S`

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/run-ablation.sh:806` vs `:1338`
**Description:** The horizon sums the plan's `watchdog_s`, but the runtime watchdog substitutes `WATCHDOG_OVERRIDE` per trial (`:1338`), so with the override set the compared horizon is not the batch's actual deadline (too long or too short).
**Remediation:** Use `WATCHDOG_OVERRIDE` per entry in the pre-flight sum when it is set.

---

## Observations

Not tallied. Items confirmed or demoted from the review and the dissent, with the reason.

- **Credential readable by the agent inside the container (DISS-C-001, MEDIUM, claude-headless)** — `head/evals/harness/pipeline-run.sh:633-640`: the rewrite replaces only `tokens.refresh_token`; `tokens.access_token`, `tokens.id_token` and a top-level `OPENAI_API_KEY` are written verbatim into the per-run HOME bind-mounted at `/home/evaluser`, where the untrusted agent runs with shell and egress. Assessment: pre-existing — the base copied the whole file verbatim, refresh token included (`pr/base/evals/harness/pipeline-run.sh`, `for f in auth.json config.toml; do cp …`), so this change narrows the exposure (a stolen credential can no longer be renewed and is bounded by `exp`). The residual risk is inherent to running the codex dissent inside the agent container and is recorded in the Threat Model below, not as a defect this change introduces. Follow-up: consider dropping `id_token` and refusing to copy a long-lived `OPENAI_API_KEY` into the container, or proxying the OpenAI call from the host.
- **Review LOW on `uses_codex` and `a3_one_voice` — not confirmed.** `head/evals/suites/ablation-2.0.yaml:71` gives `a3_one_voice` `toggles: {companion_voice: false}`, which removes the Anthropic companion and keeps the configured OpenAI primary; a3 therefore does dispatch codex and the pre-flight is right to include it. `uses_codex` (`run-ablation.sh:792-793`) remains an over-approximation in principle (an arm absent from the suite is treated as codex-using), which is the conservative direction. Not tallied.
- **Review LOW on AG-35 `hidden_tests.total` inflation** — `head/evals/tests/ablation-grade.bats:1113` documents that an agent-authored test under `tests/` counts toward `hidden_tests.total` ("8/8"). Pre-existing grader behaviour that this change only makes visible; worth a grader follow-up (count hidden cases from overlay paths only). Not tallied as a defect of this change.
- **Review's `excluded` count is 0** — nothing to confirm; `excluded_confirmed` is 0.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope (both voices normalised cleanly).

## Cross-Model Security Observations

Two-voice dissent (`adversarial-audit.json`; primary gpt-5.5-pro answered by codex-headless with `status: clean` and no findings; companion claude-headless, independent, 2 findings):
- DISS-C-001 (MEDIUM, secrets) → Observations (pre-existing exposure, narrowed by this change).
- DISS-C-002 (LOW, input-validation, `remove_colliding` over-deletion) → confirms HIGH-001; tallied once as HIGH-001.
- `verdict_quality`: 2/2 voices succeeded, consensus, chain_health ok. The primary saw a truncated diff (run-ablation.bats 6 of 28 hunks), which weakens its clean result for the test files; my own pass covered them.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets — the only literal is the placeholder `loa-ablation-no-refresh-token` (`pipeline-run.sh:636`)
- [x] Token values never printed — refusal text carries the path and ISO instants only (`run-ablation.sh:809`, `:832-833`); RAB-28 and the KF-048 pipeline case assert no token in argv/logs
- [x] Per-run copy `0600`, host file never written (`pipeline-run.sh:637-640`; asserted by sha256 in the bats case)
- [ ] Residual: access token / `id_token` / `OPENAI_API_KEY` readable by the agent in the container (Observations, pre-existing)

### Authentication & Authorization
- [ ] API-key codex auth mode refused (HIGH-003)
- [ ] Host executor refused on a premise that does not apply (MED-002)
- [x] JWT `exp` read without trusting the token for anything else (no signature check needed for a freshness hint)

### Input Validation
- [x] Caps validated with `usd_ok` from argv, suite file and `MANIFEST.json` (`run-ablation.sh:367`, `:452`, `:504`)
- [x] `auth.json` validated as a dict; JWT payload decoded defensively (`:810-826`)
- [ ] `remove_colliding` treats non-colliding files as collisions (HIGH-001, HIGH-002)
- [ ] `null`/`false` per-kind cap silently skipped (LOW-003)
- [x] No injection vectors: `python3 -I` heredocs with paths in argv; jq `--arg` for `--types` (`:565`)

### Data Privacy
- [x] No PII in logs; no new persistence of credentials beyond the existing per-run HOME (deleted at exit)

### Supply Chain
- [x] Dependencies unchanged

### API Security
- [x] Spend gates and per-kind caps in place and tested (RAB-22…26)
- [ ] Availability: pre-flight refuses runnable batches (MED-001, MED-002, HIGH-003)

---

## Threat Model Summary

**Trust Boundaries:**
- Agent under test (untrusted) ↔ grading tree: the agent controls file names/contents copied into `grading/`; `remove_colliding` must not let that influence grader-owned files. It does not (overlay dests and fixture paths are kept, writes stay in `grading/`), but it over-deletes the agent's own files (HIGH-001/002).
- Operator credential (`~/.codex/auth.json`) ↔ pre-flight and container: read-only on the host; a reduced copy enters the container.
- Suite file / `MANIFEST.json` (operator-authored) ↔ cap arithmetic: validated before awk.

**Attack Vectors:**
- Agent reads `~/.codex/auth.json` in the container and exfiltrates the bearer token: MEDIUM, pre-existing, narrowed (no refresh).
- Agent names files to game `colliding_tests_removed` or `hidden_tests.total`: LOW, telemetry only.
- Tampered `MANIFEST.json` caps on `--resume`: mitigated by `usd_ok` (`:452`).

**Mitigations:** placeholder refresh token; `0600` copies; `python3 -I`; `usd_ok` everywhere a cap is read; `refuse` writes `REFUSED.txt` with no secret material.

**Residual Risks:** in-container access token lifetime (bounded by `exp`); `OPENAI_API_KEY` copied verbatim when present; false-failure bias in grading until HIGH-001/002 are fixed.

---

## Documentation Audit

No `documentation-coherence-*` reports exist in this workspace (eval layout). Manually verified: the `run-ablation.sh` header documents pre-flight 6, the per-kind cap chain, the manifest fields and the `--resume` precedence (`:33-39`, `:110-121`, `:188-199`, `:222-230`); the `pipeline-run.sh` header and `make_home` comment describe the placeholder copy (`:83-86`, `:601-622`); the grader header records 1.2.10 → 1.2.11 (`:220-226`); the suite file comments the cap change (`evals/suites/ablation-2.0.yaml:34-40`). Mismatch found: the header's "a present entry that is not an amount … is a usage error" vs. the `null`/`false` behaviour (LOW-003). No CHANGELOG is in the PR; the commit list in `pr/PR.md` names the KF-048 security-relevant changes. No secrets or internal URLs in docs or comments.

---

## Positive Findings

- `make_home` rewrites the credential with a hardened snippet: paths only in argv, `O_CREAT|O_TRUNC` with `0600`, host file never opened for write, a clean WARN fallback that removes a partial copy (`pipeline-run.sh:624-645`), three bats cases including a byte-identity check on the host file.
- Every cap that reaches awk or `--max-run-usd` passes `usd_ok`, including the three caps read back from `MANIFEST.json` on `--resume` (`run-ablation.sh:452`).
- The pre-flight never logs or prints a token value; the manifest records `exp` and `required_until` only (RAB-30).
- Tests are hermetic for credentials: `LOA_EVAL_CREDS_HOME` is pointed at a temp dir in setup (`run-ablation.bats:12-13`), so a developer's real `~/.codex/auth.json` never drives a test.
- The `--types` jq fix binds `.type` before indexing the split list and filters empty tokens (`:565`), covered by RAB-27.

---

## Recommendations

### Immediate Actions (24 Hours)
1. Fix `remove_colliding`: reserved set from collected test modules only, exclusions for `__init__.py`/`conftest.py` on both sources, walk pruned to the test command's targets and package-aware, directory overlays walked — with the two added bats cases (HIGH-001, HIGH-002).
2. Add the API-key branch to the pre-flight and a RAB case (HIGH-003).

### Short-Term Actions (1 Week)
1. Correct the horizon formula, exclude rowed trials on `--resume`, and skip or WARN for `--executor host` (MED-001, MED-002).
2. Resolve the seed `--suite-version` dependency in-PR or by reference (MED-003); fix LOW-001…004.

### Long-Term Actions (1 Month)
1. Reduce what the container can read: drop `id_token`, refuse to copy `OPENAI_API_KEY` into the per-run HOME, or move the OpenAI dissent call host-side (Observations / DISS-C-001).
2. Count hidden cases from overlay paths only so agent-authored tests cannot inflate `hidden_tests.total`.

---

## Verdict

**CHANGES_REQUIRED**

Severity tally (Phase 2.5): Critical 0, High 3, Medium 3, Low 4; excluded 0; excluded_confirmed 0. The one-way rule (critical + high > 0) forces CHANGES_REQUIRED.

**Next Steps:**
1. `/implement sprint-1` to fix HIGH-001…003 (and the medium/low items as scoped), update `reviewer.md` with an `## AC Verification` section.
2. `/review-sprint sprint-1`, then `/audit-sprint sprint-1` again; the `COMPLETED` marker is written only on an approved audit.

---

**Audit Completed:** 2026-10-21T23:49:05Z
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-21/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":3,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:49:05Z"} -->
