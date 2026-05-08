# Security Audit — Sprint 143 (cycle-100 sprint-1)

**Sprint:** cycle-100 Sprint 1 (global sprint-143) — Foundation
**Branch:** `feat/cycle-100-sprint-1-foundation`
**Auditor:** Paranoid Cypherpunk Auditor (`/audit-sprint`)
**Date:** 2026-05-08
**Scope:** `tests/red-team/jailbreak/` + `tools/check-trigger-leak.sh` + `.claude/data/{trajectory-schemas,lore/agent-network}/jailbreak-*` (~2,000 LOC)

---

## Verdict

**APPROVED - LETS FUCKING GO**

Sprint 143 is **security-approved**. **0 CRITICAL, 0 HIGH, 2 MEDIUM, 3 LOW** — all non-blocking; deferred to Sprint 2 / cycle-101 cleanup.

The implementation demonstrates exceptionally strong security discipline:
- All user input parameterized via `jq --arg` (cycle-099 PR #215 lesson)
- Audit log: append-only + flock + mode 0600/0700 (cycle-098 envelope idiom)
- Test-mode dual-condition gate prevents env-var subversion (cycle-098 L4/L6/L7 + cycle-099 #761)
- Trigger strings runtime-constructed in fixtures (NFR-Sec1)
- Schema-first validation aborts before payload construction (NFR-Rel1)
- 5-second `timeout` wrapper around every SUT call (IMP-002 ReDoS containment)
- Audit-emit failures surfaced, not swallowed (F10 closure)

The 5 HIGH cypherpunk findings from T1.7 (F1 broken summary, F2 scanner glob blindness, F3 unconditional env-var override, F4 codepoint vs byte truncation, F5 silent corpus-corruption) were addressed inline pre-sprint with apparatus tests — all closures verified during this audit.

---

## Findings Summary

| Severity | Count | Status |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 0 | (5 pre-sprint HIGH closures verified) |
| MEDIUM | 2 | Non-blocking; deferred |
| LOW | 3 | Hygiene / future-proofing |

---

## MEDIUM Findings (non-blocking; deferred)

### MED-001: Run ID collision risk under concurrent matrix workflows

- **File:line:** `tests/red-team/jailbreak/lib/audit_writer.sh:51-58` (`_audit_compute_run_id`)
- **Class:** observability / matrix-job disambiguation
- **Description:** `GITHUB_RUN_ID` is identical across all matrix runners (Ubuntu + macOS). Today this is fine because each matrix runner uploads isolated artifacts. If a future workflow mounts a shared cache or merges per-platform run logs into a single file, both jobs will produce the same `run_id`, losing disambiguating information.
- **Current impact:** Zero (Sprint 4 wires the matrix workflow; Sprint 1 has no shared-cache surface).
- **Remediation:** Sprint 4 author seeds `run_id` with `${{ matrix.os }}` or `${{ matrix.node-version }}` when wiring the GitHub Actions workflow. One-line fix.
- **Defer:** Sprint 4 (T4.1 jailbreak-corpus.yml).

### MED-002: Per-entry python spawn for codepoint truncation scales linearly with vector count

- **File:line:** `tests/red-team/jailbreak/lib/audit_writer.sh:91-100` (`_audit_truncate_codepoints`)
- **Class:** performance / scaling cliff
- **Description:** F4 closure delegated truncation to python for locale-independent codepoint semantics. At Sprint 1 scale (20 vectors × 1 run = 20 spawns × ~5ms = ~100ms total), this is invisible. At cycle-101+ scale (e.g., 500 vectors × matrix CI), the spawn overhead consumes ~7.5 seconds of NFR-Perf1's 60s budget — 12.5% of the time-budget cliff.
- **Current impact:** Zero (well under NFR-Perf1).
- **Remediation:** Cycle-101+: batch truncation in a single python invocation at flush time, OR use `LC_ALL=en_US.UTF-8 ${s:0:N}` with a locale-availability check. Don't optimize prematurely.
- **Defer:** cycle-101+ (or Sprint 3 if T3.7 perf check shows it on the budget).

---

## LOW Findings

### LOW-001: SDD §4.3.1 vs implementation divergence on bats test registration timing

- **File:line:** SDD `grimoires/loa/cycles/cycle-100-jailbreak-corpus/sdd.md:551` ("Bats supports this via `bats_test_function` registration in `setup_file`") vs implementation `tests/red-team/jailbreak/runner.bats:39-58` (top-level loop).
- **Class:** documentation debt
- **Description:** SDD claims setup_file-time registration; bats 1.13's preprocess phase gathers tests from the file BODY before setup_file runs, so setup_file registration produces zero tests. Implementation correctly uses top-level `bats_test_function` calls during gather.
- **Risk:** Sprint 2 author reads SDD, writes test in setup_file, ships green-with-zero-tests run.
- **Remediation:** Add SDD amendment note in cycle-100 RESUMPTION brief; lift into the SDD itself when amended.
- **Defer:** RESUMPTION update (this session's next step).

### LOW-002: Schema gate for `superseded → superseded_by` is invisible until Sprint 3

- **File:line:** `.claude/data/trajectory-schemas/jailbreak-vector.schema.json:81-92`
- **Class:** design debt / discoverability
- **Description:** F11 closure added `superseded → superseded_by` allOf gate. Seed corpus has zero superseded vectors so the gate is invisible until Sprint 3's pushback round (T3.6) marks vectors as superseded. A Sprint 3 author who marks a vector superseded without the pointer will get a generic JSON-schema "required field missing" error.
- **Risk:** Confusing diagnostic; minor lost time.
- **Remediation:** Document the gate in a forthcoming `tests/red-team/jailbreak/README.md` "Suppression discipline" section (Sprint 4 T4.3 deliverable). Optionally enhance `corpus_loader.sh::_corpus_validate_one` to emit a clearer error: "vector_id XYZ marked superseded but missing superseded_by pointer (required by schema allOf gate)".
- **Defer:** Sprint 4 README (T4.3) or Sprint 2 cleanup.

### LOW-003: NFR-Sec1 lint excludes the entire fixtures tree by directory

- **File:line:** `tools/check-trigger-leak.sh:59` (`EXCLUDE_PREFIX="${REPO_ROOT}/tests/red-team/jailbreak/"`)
- **Class:** hygiene gap
- **Description:** Trigger-leak lint blanket-excludes the entire `tests/red-team/jailbreak/` subtree because fixtures legitimately reference attack patterns. The runtime-construction discipline (`_make_evil_body_*` concat) is enforced by code review, not automated detection. Cypherpunk T1.7 caught the F6 Python unicode literal regression in fixtures themselves — proof the gap is real.
- **Risk:** Future fixture author copy-pastes a verbatim DAN prompt instead of constructing it from concat parts; lint silently passes.
- **Remediation:** Cycle-101+: add a fixtures-internal lint that AST-parses fixture functions and rejects literals containing watchlist regex matches (post-decode). Document the gap in cycle-100 SDD §4.7 (currently only documents IMP-008 encoded-payload limitation).
- **Defer:** Sprint 3 / cycle-101.

---

## Security Checklist (full pass)

| Category | Result | Evidence |
|---|---|---|
| Input validation (schema + regex) | ✓ PASS | JSON Schema 2020-12 + `^RT-[A-Z]{2,3}-\\d{3,4}$` + `^_make_evil_body_[a-z0-9_]+$` patterns |
| Command injection mitigation | ✓ PASS | `jq --arg` for every value (cycle-099 PR #215 lesson) |
| File security (modes + flock) | ✓ PASS | `audit_writer.sh:115-145` mode 0700/0600 + flock with mkdir-fallback |
| Secret redaction in audit log | ✓ PASS | 7-pattern set: Anthropic / OpenAI / Google / GitHub / AWS / JWT / private keys |
| Error handling (no silent failures) | ✓ PASS | F5 BAIL on corpus invalid; F10 emit-failure surfaced |
| ReDoS containment (timeout 5s) | ✓ PASS | `runner.bats:113-128` |
| Test-mode env-var dual-condition gate | ✓ PASS | All 5 LOA_* env vars require both `LOA_JAILBREAK_TEST_MODE=1` AND bats/pytest marker |
| Path traversal mitigation | ✓ PASS | Schema regex on `payload_construction` blocks `../`; loader looks up via `declare -f` not eval |
| Append-only audit log | ✓ PASS | `>>` redirect; flock prevents interleave |
| No hardcoded secrets in source | ✓ PASS | Trigger-leak lint clean (production-path) |
| OWASP A03:2021 (Injection) | ✓ PASS | Parameterized inputs throughout |
| OWASP A02:2021 (Sensitive Data Exposure) | ✓ PASS | Redaction + file modes |
| OWASP A04:2021 (Insecure Design) | ✓ PASS | Schema-first validation; runtime payload construction |
| OWASP A01:2021 (Broken Access Control) | ✓ PASS | mode 0600/0700 + test-mode gate |
| OWASP A05:2021 (Security Misconfiguration) | ✓ PASS | Locale pinning + env-i sanitization in IMP-003 |

---

## Threat Model — Verdicts

| Threat | Defense | Verdict |
|---|---|---|
| Adversary embeds verbatim trigger in committed code | `tools/check-trigger-leak.sh` watchlist scan | ✓ DEFENDED (encoded forms are IMP-008 documented limitation) |
| Corpus corruption → silent zero-tests run | F5 closure: `runner.bats` BAIL on validate-all failure | ✓ DEFENDED |
| Audit log race / interleave under parallel writers | flock (Linux) + mkdir-fallback (macOS) | ✓ DEFENDED |
| Secret leakage in audit `reason` field | `_audit_redact_secrets` 7-pattern set | ✓ DEFENDED (custom secret formats not in patterns: residual risk) |
| LOA_* env-var subversion of audit dest / lint config | Test-mode dual-condition gate | ✓ DEFENDED |
| ReDoS DoS via pathological payload | `timeout 5s` + exit 124 detection | ✓ DEFENDED |
| Vector definition injection (path traversal in `payload_construction`) | Schema regex `^_make_evil_body_[a-z0-9_]+$` + `declare -f` lookup | ✓ DEFENDED |

---

## Verification of Pre-Sprint HIGH Closures

The /implement skill closed 5 HIGH findings inline before reaching this audit. Re-verified each:

| Finding | Closure | Verified |
|---|---|---|
| F1 — `audit_writer_summary` broken (counted run-log `pass` as "Active") | Rewrote to emit `Run: pass=N \| fail=M \| suppressed=K` + `Corpus: ...` lines. Apparatus test `audit-writer.bats:130-144`. | ✓ |
| F2 — Scanner glob blindness (extension-less + `.legacy`) | Added shebang detection second pass. Apparatus test `trigger-leak-lint.bats:73-103`. | ✓ |
| F3 — Unconditional `LOA_*` env-var override | Dual-condition gate (cycle-098 L4/L6/L7 pattern). Apparatus tests across audit-writer + trigger-leak suites. | ✓ |
| F4 — `_audit_truncate` codepoint vs byte ambiguity under LC_ALL=C | Renamed + delegated to python for locale independence. Apparatus test `audit-writer.bats:155-178`. | ✓ |
| F5 — runner had no `set -uo pipefail` + missing corpus-validate guard | Added `set -uo pipefail` + explicit BAIL at file-source time. Apparatus test `runner-generator.bats:79-91`. | ✓ |

---

## Recommendation

Proceed to PR.

The 2 MEDIUM and 3 LOW findings are documented in the cycle-100 RESUMPTION brief for Sprint 2 / Sprint 3 / cycle-101 follow-up. None block this sprint.

---

*Audited by `/audit-sprint sprint-143` (paranoid-cypherpunk role) per Loa workflow. Method: full codebase review (no sampling); threat modeling; schema validation; logic trace. Confidence: HIGH (all code paths analyzed).*
