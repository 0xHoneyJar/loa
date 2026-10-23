# Sprint 1 Security & Quality Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`; brief `grimoires/loa/context/task-brief.md`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Senior Review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — verdict CHANGES_REQUIRED (high 2, medium 1, low 2, excluded 0)
**Scope:** `pr/head.diff` — 12 files: `evals/harness/{ablation-grade.sh, lib/arms-common.sh, pipeline-run.sh, run-ablation.sh}`, `evals/suites/ablation-2.0.yaml`, seven bats/fixture files. Every citation is `head/<path>:<line>` with lines from `pr/head/`.
**Methodology:** Sources/sinks recon on the four harness scripts, forward and backward trace of the credential and cap data flows, 5-category pass (Security, Architecture, Code Quality, DevOps; Blockchain n/a), two-voice adversarial dissent on the diff (`adversarial-audit.json`).

**Pre-flight note.** Phase 0 expects `engineer-feedback.md` to read "All good"; it reads CHANGES_REQUIRED. The audit was run anyway per the task instruction ("Run `/audit-sprint sprint-1` … work autonomously") so the sprint carries both gate verdicts; the review's findings were re-derived from the code, not inherited.

---

## Executive Summary

The change does four things: per-task-kind run caps in `run-ablation.sh` and `lib/arms-common.sh` (DEC-0567), the KF-048 codex credential handling (a placeholder refresh token in the per-run HOME written by `pipeline-run.sh`, an access-token expiry pre-flight in `run-ablation.sh`), the `--types` jq fix, and grader 1.2.11's basename-collision cleanup in `ablation-grade.sh`.

The security surface is handled with care. The credential copy writes with `O_CREAT|O_TRUNC` at 0600 inside a 0700 directory, passes paths only in argv, never writes the host file, and degrades to "no credential plus one WARN" on an unreadable file (`head/evals/harness/pipeline-run.sh:622-645`). The pre-flight decodes only the JWT payload, prints no token material, and records a `codex_preflight` block in MANIFEST so a refusal is auditable later (`head/evals/harness/run-ablation.sh:780-842`). Every cap reaching arithmetic was validated by `usd_ok` first. No injection path, no new dependency, no secret in code or docs.

The defect is in the grader. `remove_colliding` (`head/evals/harness/ablation-grade.sh:1074-1104`) reserves every `.py` basename found under a fixture `tests/`/`test/` directory and every `.py` basename in the hidden overlay, then unlinks any agent-added file anywhere in the grading tree with a reserved basename. Pytest's import-file-mismatch abort applies only to collected test modules in package-less directories, so this deletes implementation modules a correct solution depends on and grades the solution as failing, with only a counter as evidence. Both dissent voices of the review and the companion voice of this audit (DISS-C-003) reached the same conclusion independently. Two HIGH findings follow, so the verdict is forced to CHANGES_REQUIRED; the medium and low findings are improvements.

**Overall Risk Level:** HIGH (grading integrity, not exploitability)

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.2/5 | IV:4 AZ:4 CI:4 IN:5 AV:4 |
| Architecture | 3.8/5 | MO:4 SC:4 RE:3 CX:4 ST:4 |
| Code Quality | 3.2/5 | RD:4 TC:3 EH:3 TS:3 DC:3 |
| DevOps | 4.2/5 | AU:4 OB:5 RC:4 AC:4 DS:4 |
| Blockchain | n/a | — |
| **Overall** | **3.8/5** | Security weighted highest |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Grader 1.2.11 deletes agent-added non-test modules by basename, tree-wide

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1087` (reserved set), `head/evals/harness/ablation-grade.sh:1090-1100` (whole-tree walk and unlink)
**Criterion:** CQ-EH / ARCH-RE (correctness of a grading rule every calibration row depends on)

**Reasoning Trace:**
> Traced `reserved` backwards. Line 1081 adds the basename of every overlay `.py` dest. Lines 1084-1087 walk the whole fixture and, for any directory with a `tests` or `test` path component, add every `.py` name except `__init__.py` and `conftest.py` — so `tests/helpers.py`, `tests/utils.py`, `tests/fixtures/sample.py` all reserve their names. Traced the candidate walk forward: lines 1090-1100 visit every directory of the grading tree and unlink any file whose name is in `reserved` unless it is an overlay dest, under an overlay directory, or present at the same path in the fixture. There is no restriction to pytest-collected names (`test_*.py`, `*_test.py`), no check for an `__init__.py` sibling (a packaged module imports under its qualified name and cannot collide), and no restriction to the directories the task's `test_command` collects. The grader's own header (line 220) says fixture suites rely on `from helpers import …`, so fixtures with `tests/helpers.py` exist in the suite.

**Description:** The docstring at lines 1075-1078 scopes the rule to "package-less test modules" pytest imports by basename; the code applies it to any `.py` anywhere.

```python
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))   # :1087
...
            if rel in owned or rel.startswith(owned_dirs) or (fx and os.path.lexists(os.path.join(fx, *rel.split("/")))):
                continue
            found.append((rel, os.path.join(r, name)))   # :1098-1099
```

**Impact:** Concrete failing input: fixture `tests/helpers.py`; the agent adds `src/pkg/helpers.py` and imports it from the solution. `helpers.py` is reserved; `src/pkg/helpers.py` is not owned, not under an overlay dir, not in the fixture → unlinked at line 1100 before any command runs. The hidden suite fails with `ModuleNotFoundError`; `grade.json` shows `hidden_tests` failed and `colliding_tests_removed: 1`; the row is not flagged degraded. A correct solution is graded wrong, silently — the exact failure class 1.2.11 set out to remove. Arms that add modules (A1 with a sprint plan) are hit; A0 BARE, which edits in place, is not, so the DEC-0597 H1 estimate (+0.263) computed under 1.2.11 is exposed to a directional bias.

**Remediation:**
1. Reserve only names pytest collects: `n.startswith("test_") or n.endswith("_test.py")` for both sources (overlay and fixture).
2. Unlink a candidate only when pytest would import it by basename: no `__init__.py` beside it, and under a root the task's `test_command` collects.
3. Bats case: fixture `tests/helpers.py`, agent-added `src/pkg/helpers.py` imported by the solution; assert the file survives, the suite passes, `colliding_tests_removed` is 0.
4. Consider renaming out of pytest's glob instead of deleting, and surface `colliding_tests_removed > 0` as a degraded flag on the row (companion suggestion, DISS-C-003).

**References:** CWE-682 Incorrect Calculation, https://cwe.mitre.org/data/definitions/682.html ; pytest "Import modes" (prepend/append), https://docs.pytest.org/en/stable/explanation/pythonpath.html . Confirmed by cross-model review (DISS-C-003) and by the review's dissent (DISS-001, DISS-C-001).

### [HIGH-002] An overlay `__init__.py` reserves `__init__.py` tree-wide

**Severity:** HIGH | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:1081`
**Criterion:** CQ-EH (asymmetric exclusions between the two sources of `reserved`)

**Reasoning Trace:**
> `reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}` has no exclusion list; the `__init__.py`/`conftest.py` exclusions at line 1087 apply only to the fixture walk, and line 1088 discards only `conftest.py` afterwards. A hidden overlay that ships `tests/__init__.py` puts `__init__.py` into `reserved`; every package initializer the agent created that is not in the fixture (`src/newpkg/__init__.py`) is then unlinked at line 1100.

**Description:** Same unlink path as HIGH-001 with a single-file trigger that takes out a whole package. Confidence is medium because it needs a task whose overlay carries a package marker; the suite's task files are outside this diff, so it cannot be ruled out here.

**Impact:** The agent's new package stops being importable; the hidden suite fails; the row is graded wrong with `colliding_tests_removed` as the only trace.

**Remediation:** Apply one filter to both sources (never reserve `__init__.py` or `conftest.py`; only reserve collected test-module names). Bats case: overlay with `tests/__init__.py`, agent tree with `src/newpkg/__init__.py`, assert survival.

**References:** CWE-682, https://cwe.mitre.org/data/definitions/682.html . Noted by the review's dissent (DISS-C-001 of `adversarial-review.json`).

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Directory overlays contribute nothing to the collision guard

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/ablation-grade.sh:1079-1081`

**Description:** `owned` keeps only file overlays (`if not os.path.isdir(f)`), and `reserved` derives only from `owned`; `owned_dirs` protects overlay contents from deletion but never enumerates their test files. `load_task` accepts a directory source (lines 570-582 check `os.path.exists`, and `remove_harness` already carries `owned_dirs` for this shape). For a task whose hidden tests arrive as a directory, an agent-added `tests/extra/test_slug.py` survives, pytest aborts collection on the mismatch, and the row is graded failing with `colliding_tests_removed: 0` — the header's 1.2.11 guarantee (line 222) does not hold for those tasks.

**Impact:** The guard behaves differently by overlay shape; a false failure that the counter does not even record.

**Remediation:** When `os.path.isdir(f)`, `os.walk(f)` and add its collected test-module basenames to `reserved`; add a directory-overlay bats case. Confirmed by cross-model review (the review's DISS-002 / DISS-C-002).

### [MED-002] The per-run HOME still carries a live bearer, an identity token and any API key into the agent-writable mount

**Severity:** MEDIUM | **Confidence:** high (exposure) — pre-existing surface, narrowed but not closed by this change
**Component:** `head/evals/harness/pipeline-run.sh:633-640`, test `head/evals/tests/pipeline-run.bats:953`

**Description:** The rewrite replaces only `tokens.refresh_token`; `tokens.access_token` (a bearer valid until `exp`), `tokens.id_token` (OIDC identity: account id, e-mail) and a non-null `OPENAI_API_KEY` are copied verbatim into `$HOME_DIR/.codex/auth.json`, which is bind-mounted read-write at `/home/evaluser` where the evaluated agent runs with network access. The bats case asserts `has("OPENAI_API_KEY")` with a `null` value, so the long-lived-key shape is never exercised. Before this change the whole file, refresh token included, was copied, so the change reduces exposure; it does not bound the access token (the KF-048 pre-flight requires it to outlive the batch, i.e. to stay valid for hours) nor an API key (not time-bounded at all).

**Impact:** An evaluated agent, or prompt-injected content in a task tree, can read and exfiltrate the operator's OpenAI bearer, identity token, or API key. The comment at lines 617-621 frames the change as a credential-safety fix; it closes refresh-token reuse only.

**Remediation:** Build a minimal object (`auth_mode`, `tokens.access_token`, `tokens.account_id`, the placeholder `refresh_token`), drop `id_token`, blank or refuse a non-null `OPENAI_API_KEY` with a WARN, and add a bats case with a non-null key asserting it never reaches the snapshot. Longer term, proxy the codex call from the host so no bearer lives in the mount.

**References:** CWE-522 Insufficiently Protected Credentials, https://cwe.mitre.org/data/definitions/522.html ; CWE-200, https://cwe.mitre.org/data/definitions/200.html ; OWASP A07:2021, https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/ . Cross-model finding DISS-C-001 (companion voice), merged per ADVERSARIAL-REVIEW.md rule 2 and independently confirmed.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] `suite_kind_cap` lets `false` and `null` entries fall through to the fallback cap

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/run-ablation.sh:502-503`

**Description:** jq's `//` treats `false` and `null` as absent: `caps.run_usd_by_type: false` yields `""` (fallback to `RUN_CAP`), and `run_usd_by_type: {build: false}` (YAML `build: no`) yields `""` too. The comment at line 499 says "A present but malformed per-kind entry is refused, never skipped"; these two shapes are skipped and the batch runs on 12. RAB-22 covers the string and list shapes only.

**Remediation:** Test presence with `has($k)` and type with `type`: `if has($k) then (.[$k] | if type == "number" or type == "string" then tostring else "!" end) else "" end`, and the same for the map itself.

### [LOW-002] `colliding_tests_removed` counts the same file once per graded tree

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/ablation-grade.sh:1019` (accumulator), `:1708`, `:1723`, `:1748` (`prepare` per tree), `:1773` (the grade.json field)

**Description:** `prepare` calls `remove_colliding` on the final tree, the base tree and each extracted snapshot (`implement`, `fix1`), and `COLLIDING[0] +=` on every call. One agent file that collides is reported as 2 or 3 in a gated arm, while the header (line 223) and AG-35 (asserting 1 on an ungated run) read the field as a count of files. `harness_files_removed` follows the same convention, so this is a labelling defect, but the field is new and feeds the per-row analysis.

**Remediation:** Count distinct relative paths across trees (a set), or document the field as "per tree graded" and name it so.

### [LOW-003] The KF-048 pre-flight refuses in `--executor host`, where the CLI can still refresh

**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-ablation.sh:784-841`

**Description:** The pre-flight runs for every non-smoke batch regardless of `EXECUTOR`. `make_home` (and the placeholder refresh token) applies only in container mode (`pipeline-run.sh:650`); in host mode the codex CLI runs against the operator's real `~/.codex/auth.json` and can renew an expired access token. A host-mode batch is therefore refused for a token the CLI would have refreshed. Operational nuisance, not a safety gap; a conservative refusal is defensible (concurrent host trials refreshing a single-use token is the KF-048 hazard in another guise), but the header at lines 110-121 does not say so.

**Remediation:** Either skip the check when `EXECUTOR == host` or state in the header that the horizon rule applies to both executors and why.

### [LOW-004] `spend_charge` and `budget_gate` take an unvalidated numeric fourth argument

**Severity:** LOW | **Confidence:** low
**Component:** `head/evals/harness/lib/arms-common.sh:129`, `head/evals/harness/lib/arms-common.sh:143-147`

**Description:** The new `<cap>` and `<reserve-per-trial>` parameters go straight into `fadd`/awk arithmetic without the regex check applied to `<cost>` at line 130. Today every caller passes a `usd_ok`-validated value (`cap_for`, `RESERVE_CAP`), so this is a library-contract gap rather than a live bug: a runner passing an empty string or `null` would under-count `SPENT` and silently disable the `--max-usd` cut.

**Remediation:** Validate `cap`/`per` with the same regex and fall back to `RUN_CAP` with a log line, or die. Cross-model finding DISS-C-002 (companion voice), accepted at its stated severity.

---

## Observations

Nothing demoted: no high finding was marked speculative, so `excluded` is 0.

- **Unverifiable from `pr/`:** `head/evals/tests/seed-bugfix.bats:80` and `head/evals/tests/seed-refactor.bats:78` pass `--suite-version` to seed scripts that are not among the touched files; the twelve `*-v2-*` task directories the bats cases name are likewise outside the diff. Not counted; scope limit recorded.
- **Correct as read:** the cap plumbing end to end (`cap_for`, `RESERVE_CAP`, `account_row`, `collect`, `run_trial`, manifest `run_usd_by_type`, `--resume` from MANIFEST with `--run-cap` ignored and noted) at `head/evals/harness/run-ablation.sh:500-515, 850-854, 1043-1053, 1187, 1284, 1322, 1534`; RAB-22 through RAB-26 pin each path including the 27.99/28 and 21.99/22 budget-gate boundaries. The `--types` jq fix at line 565 (`.type as $t | … | index($t)`) is correct and RAB-27 pins it. `remove_colliding` cannot escape the tree: `os.walk(followlinks=False)` and `os.unlink` on a link removes the link, not the target.
- **Treating every arm with `loa_mount` unset as codex-using** (`run-ablation.sh:792-793`) is the right default: only A0 BARE is exempt.

## Cross-Model Security Observations

Primary voice (gpt-5.5-pro, answered by codex-headless): clean, no findings. Companion voice (claude-headless, independent family): DISS-C-001 MEDIUM → MED-002 (counted); DISS-C-002 LOW → LOW-004 (counted); DISS-C-003 LOW → confirms HIGH-001 (severity raised: the damage is a wrong grade on every affected calibration row). Two voices succeeded, `degraded: false`, no `locality.degraded_security_review` — not a DEGRADED_SECURITY_REVIEW.

## Rejected dissent payloads

The audit envelope (`adversarial-audit.json`, two voices, both succeeded) has `rejected_count` 0, an empty `rejected_summary` and no sidecar rows; nothing to triage.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace; verified manually. Header docs in `run-ablation.sh` (pre-flight 6, Run caps, MANIFEST `caps.run_usd_by_type`, `codex_token_exp`, `codex_preflight`), `pipeline-run.sh` (mount contents, KF-048 rationale) and `ablation-grade.sh` (1.2.10 superseded, 1.2.11) match the code except where HIGH-001 notes the docstring is narrower than the implementation; the suite file comment matches `caps`. The security-critical credential copy is commented in place. No secret, token or internal URL in docs, comments or tests (RAB-28 asserts no token material in REFUSED.txt or stdout).

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (the placeholder string is not a credential)
- [x] Host credential file never written; per-run copy 0600 in a 0700 directory
- [ ] Credential minimised in the agent-writable mount (MED-002: access token, id_token, API key still copied)

### Authentication & Authorization
- [x] Per-run HOME cannot refresh the host's token (placeholder refresh token)
- [x] Access token freshness gated before the batch (pre-flight 6)
- [ ] Bearer scoped to the run (MED-002; no per-run key)

### Input Validation
- [x] Every cap through `usd_ok` before arithmetic (LOW-001 for the `false`/`null` shapes; LOW-004 for the library contract)
- [x] JWT payload decode guarded; no signature trust implied
- [x] Paths only in argv, `python3 -I`, no shell interpolation of file content

### Data Privacy
- [x] No token material in logs, REFUSED.txt or MANIFEST (`codex_token_exp` is an instant)
- [x] Error messages carry paths and instants only

### Supply Chain
- [x] No new dependency

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 4 |

## Verdict

**CHANGES_REQUIRED** — two HIGH findings (HIGH-001, HIGH-002) in `ablation-grade.sh`'s `remove_colliding` force the verdict under the one-way rule. The cap plumbing, the `--types` fix and the KF-048 credential handling are sound and may stay as written; fix the grader's reserved-set and candidate scoping (bump to 1.2.12 with the three bats cases above), then re-grade the Sprint 261 priority-v2-p1/p1b rows before the DEC-0597 H1 figure is relied on. MED-002 should be scheduled as its own change.

## Next Steps

1. `ablation-grade.sh`: scope `reserved` to collected test-module names from both sources, skip packaged candidates and non-collected roots, exclude `__init__.py`/`conftest.py` symmetrically, enumerate directory overlays (HIGH-001, HIGH-002, MED-001); de-duplicate the counter (LOW-002).
2. `run-ablation.sh`: `has($k)`/`type` checks in `suite_kind_cap` (LOW-001); decide the host-executor rule for the pre-flight (LOW-003).
3. `pipeline-run.sh`: minimise the copied `auth.json` (MED-002); `arms-common.sh`: validate the new numeric parameters (LOW-004).
4. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:30:00Z"} -->
