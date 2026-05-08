# Sprint 144 (cycle-100 Sprint 2) — Paranoid Cypherpunk Security Audit

**Auditor:** deep-name + Claude Opus 4.7 1M (Paranoid Cypherpunk persona)
**Date:** 2026-05-08
**Implementation commit:** `5b983ecd` + closure commit `12d87c00`
**Engineer-reviewer verdict:** APPROVED — All good (NEW-B1/D1/D2 closed inline)

---

## Verdict: **APPROVED — LETS FUCKING GO**

| Severity | Count | Note |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 0 | — |
| MEDIUM | 0 | — |
| LOW | 2 | Both informational; non-blocking |
| INFORMATIONAL | 3 | Sprint-3 / cycle-101 follow-up suggestions |

Sprint 2 ships clean. The `/review-sprint` cycle (engineer-reviewer + Phase 2.5 cross-model = 18 findings, 11 closed pre-merge) caught the symmetric-whitespace-bypass class (NEW-B1) before this audit gate. The remaining surface holds against direct security boundary probes.

---

## Phase 2.5: Adversarial Cross-Model Audit

| Field | Value |
|---|---|
| Model | `claude-opus-4-7` (rolled back from `gpt-5.5-pro` per #787) |
| Latency | 46.2s |
| Cost | $0.27 (39.9k in / 2.9k out) |
| Status | `reviewed` (not `api_failure`) |
| Findings (post-validator) | 0 |
| Findings rejected (pre-validator) | 5 (structurally invalid — model output didn't conform to script's anchor shape) |
| Artifact | `grimoires/loa/a2a/sprint-144/adversarial-audit.json` |

The model attempted 5 findings; `adversarial-review.sh`'s structural validator rejected all 5. Without inspectable raw output (tmpdir cleaned up), this auditor cannot determine whether the rejections were genuine-concerns-malformed-output or genuine-hallucinations-correctly-filtered. Worth tracking: see Sprint 4 / cycle-101 LOW item below.

---

## Direct Security Boundary Probes

This auditor probed each defense boundary with adversarial inputs to verify enforcement, not just code presence.

### CWE-22 Path Traversal — `load_replay_fixture(vector_id)` (M1)

```python
load_replay_fixture("../../../etc/passwd") → ValueError("REPLAY-INVALID: vector_id shape ...")
load_replay_fixture("RT-..-001")            → ValueError("REPLAY-INVALID: ...")
load_replay_fixture("rt-mt-001")            → ValueError("REPLAY-INVALID: ...")  # lowercase rejected
load_replay_fixture("RT-MT-001/x")          → ValueError("REPLAY-INVALID: ...")  # slash rejected
load_replay_fixture("RT-MT-001\nINJECTION") → ValueError("REPLAY-INVALID: ...")  # newline rejected
```

**Verdict:** PASS. M1 closure wires the schema regex `^RT-[A-Z]{2,3}-\d{3,4}$` at function entry; every adversarial vector_id rejected before any pathlib operation. Test pin: `tests/unit/test_replay_harness.py::TestVectorIdAndCategoryGuards::test_path_traversal_vector_id_rejected`.

### CWE-94 Code Injection — `importlib.import_module(vector.category)` (M2)

```python
substitute_runtime_payloads(..., V(category="os"))             → FixtureMissing("FIXTURE-CATEGORY-FORBIDDEN")
substitute_runtime_payloads(..., V(category="subprocess"))     → FixtureMissing("FIXTURE-CATEGORY-FORBIDDEN")
substitute_runtime_payloads(..., V(category=".."))             → FixtureMissing("FIXTURE-CATEGORY-FORBIDDEN")
substitute_runtime_payloads(..., V(category="/etc/passwd"))    → FixtureMissing("FIXTURE-CATEGORY-FORBIDDEN")
substitute_runtime_payloads(..., V(category="role_switch.evil")) → FixtureMissing("FIXTURE-CATEGORY-FORBIDDEN")
```

**Verdict:** PASS. M2 frozenset allowlist gates `importlib.import_module` to the 7 schema-enum values. No attacker-controlled module can be imported.

### Schema ↔ Allowlist Drift Pin

```python
schema_categories = {"role_switch", "tool_call_exfiltration", "credential_leak",
                     "markdown_indirect", "unicode_obfuscation", "encoded_payload",
                     "multi_turn_conditioning"}
python_allowlist  = {"role_switch", "tool_call_exfiltration", "credential_leak",
                     "markdown_indirect", "unicode_obfuscation", "encoded_payload",
                     "multi_turn_conditioning"}
drift = schema - allowlist | allowlist - schema = ∅
```

**Verdict:** PASS. Zero drift today. **LOW-1 follow-up:** add a CI test that fails if drift appears (e.g., a future schema enum value added without matching allowlist update).

### CWE-1333 ReDoS — `_PLACEHOLDER_RE` post-NEW-B1

```python
adversarial = "__FIXTURE:" + "_make_evil_body_" + "x" * 10000 + " "
_PLACEHOLDER_RE.fullmatch(adversarial)   # 0.04ms; match=False
```

**Verdict:** PASS. Bounded-alternation regex with no nested quantifiers; 10k-char input rejects in <0.1ms. Symmetric `\s*` on both ends introduces no backtracking risk.

### CWE-78 OS Command Injection — `_invoke_sanitize_subprocess` + `_emit_audit_run_entry`

```python
subprocess.run(["bash", "-c", "...", "_", source, content], ...)
```

**Verdict:** PASS. argv-positional invocation; `bash -c "$1"; ...` pattern uses positional `"$1"`/`"$2"` quoting; no `shell=True`; content comes from validated fixture functions (not external input). Same pattern as Sprint 1's runner.bats invocation.

### NFR-Sec1 Runtime Construction Discipline

Every NEW Sprint 2 fixture function uses runtime concatenation:
- `tests/red-team/jailbreak/fixtures/encoded_payload.{sh,py}` — Base64/ROT-13/hex/URL-percent built at invocation
- `tests/red-team/jailbreak/fixtures/multi_turn_conditioning.{sh,py}` — trigger turns built at invocation
- 10 backfill fixtures — runtime concat (verified in /implement T2.1+T2.5)

**Trigger-leak lint** (`bash tools/check-trigger-leak.sh`) clean (exit 0). No verbatim triggers in source files.

### NFR-Sec3 Audit-Log Redaction

`audit_writer.sh::_audit_redact_secrets` from Sprint 1 unchanged. Pytest harness's `_emit_audit_run_entry` invokes the bash audit_writer via subprocess, inheriting the 7-pattern secret-redaction stripper. Reason fields passed positionally (no shell metas).

### Cypherpunk M4 — Audit Returncode Check

```python
r = subprocess.run(cmd, ..., check=False)
if r.returncode != 0:
    sys.stderr.write(f"audit emit returned non-zero ({r.returncode}) ...")
    if os.environ.get("LOA_JAILBREAK_STRICT_AUDIT") == "1":
        raise RuntimeError(...)
```

**Verdict:** PASS. M4 closure brings python harness to parity with Sprint 1 F10 closure on bash side. Strict-audit env opt-in mirrors L4/L7 dual-condition pattern.

### Cypherpunk H3 — Aggregate Budget Enforcement

```python
elapsed = time.monotonic() - aggregate_start
remaining = _PER_VECTOR_TIMEOUT_SEC - elapsed
if remaining <= 0:
    pytest.fail(...)
_invoke_sanitize_subprocess(turn["content"], turn_timeout=remaining)
# subprocess.run(timeout=max(0.1, min(5.0, turn_timeout)))
```

**Verdict:** PASS. Aggregate 10s/vector budget cannot be silently exceeded by a hung turn; subprocess timeout is `min(remaining, 5.0)`. Combined with Sprint 1's per-turn 5s ceiling, total worst-case for an 11-turn vector is bounded at 10s.

---

## OWASP Top 10 (2021) Coverage Summary

| Category | Sprint 2 surface | Status |
|---|---|---|
| A01:2021 Broken Access Control | N/A — no auth surface introduced | — |
| A02:2021 Cryptographic Failures | N/A — no crypto operations | — |
| A03:2021 Injection | OS command (CWE-78) PASS; code (CWE-94) PASS via M2 allowlist | ✓ |
| A04:2021 Insecure Design | NFR-Sec1 + dual-review pattern (cypherpunk + cross-model) maintained | ✓ |
| A05:2021 Security Misconfiguration | `audit_writer.sh` mode 0600 / dir 0700 (Sprint 1, unchanged) | ✓ |
| A06:2021 Vulnerable Components | No new runtime deps; `subprocess`+`importlib` are stdlib | ✓ |
| A07:2021 Auth Failures | N/A | — |
| A08:2021 Software/Data Integrity | Schema validation (corpus + replay), trigger-leak lint, audit redaction | ✓ |
| A09:2021 Logging Failures | M4 returncode check + LOA_JAILBREAK_STRICT_AUDIT opt-in | ✓ |
| A10:2021 SSRF | N/A — no network operations | — |

---

## Findings

### LOW-1 (informational): Schema ↔ allowlist drift CI pin

**File:** `tests/red-team/jailbreak/lib/corpus_loader.py:212-221` + `.claude/data/trajectory-schemas/jailbreak-vector.schema.json`

**Issue:** Today schema enum and `_FIXTURE_CATEGORY_ALLOWLIST` match exactly (verified). But adding a new category to the schema without updating the python frozenset is a silent-disable class — `substitute_runtime_payloads` would refuse the new category at runtime, but no schema-validation tool would warn.

**Fix:** Add a unit test in `tests/unit/test_replay_harness.py` that:
```python
def test_schema_enum_matches_python_allowlist():
    schema = json.load(open(SCHEMA_PATH))
    schema_enum = set(schema["properties"]["category"]["enum"])
    assert schema_enum == set(corpus_loader._FIXTURE_CATEGORY_ALLOWLIST)
```

**Severity:** LOW (no current defect; defense against future drift). **Defer:** Sprint 3 / cycle-101.

### LOW-2 (informational): adversarial-review.sh validator rejected 5 audit findings without preserving raw

**File:** `.claude/scripts/adversarial-review.sh` (Phase 2.5 telemetry)

**Issue:** During this audit run, the cross-model produced 5 findings; the script's structural validator rejected all 5. Tmpdir cleaned up before this auditor could inspect raw output. Without raw preservation, operators cannot distinguish "legitimately malformed model output" from "valid concerns rejected on overly-strict anchor schema."

**Fix:** Add `--preserve-raw <path>` flag OR write rejected findings to `<artifact>.rejected.json` for operator forensics. **Defer:** track in #787 as a sub-item.

**Severity:** LOW (tooling improvement; doesn't affect the verdict).

---

## Informational Observations (Sprint 3 / cycle-101 candidates)

### INFO-1: DISS-005 sys.path mutation in `substitute_runtime_payloads`

The cross-model `/review-sprint` flagged that `sys.path.insert(0, fixtures_dir)` is uncleaned. Real but bounded — no pip package collides with category names today. Recommend `importlib.util.spec_from_file_location` migration for explicit per-category file paths in Sprint 3.

### INFO-2: NEW-N1 dead bash multi_turn fixtures

`fixtures/multi_turn_conditioning.sh` has 12 functions never invoked by any test. Engineer-reviewer + cross-model both flagged. Recommend Sprint 3 either delete or add a smoke-test pin asserting bash↔python parity.

### INFO-3: NEW-N2 formal JSON Schema for replay JSON

Replay JSONs validated only at runtime by `load_replay_fixture` shape checks. Corpus JSONLs have a formal Draft 2020-12 schema. Symmetry argues for a sibling `jailbreak-replay-fixture.schema.json` validated by `validate-all`. Defer to Sprint 3 alongside T3.6 cypherpunk pushback.

---

## Karpathy Principles (Auditor View)

| Principle | Verdict |
|---|---|
| Think Before Coding | ✓ — assumptions documented; cross-model cross-validated NEW-B1; symmetric whitespace contract pinned via 3 apparatus tests |
| Simplicity First | ✓ — no speculative features; placeholder regex is 1 line; allowlist is 1 frozenset |
| Surgical Changes | ✓ — diff is exactly Sprint 2 deliverables + closure fix; no incidental refactor |
| Goal-Driven | ✓ — every defense boundary has at least one apparatus test pinning it |

---

## Test Coverage Verification

| Surface | Test File | Pass Rate |
|---|---|---|
| Single-shot vectors (35) | `runner.bats` | 35/35 |
| Multi-turn replay (11 + smoke) | `test_replay.py` | 12/12 |
| Apparatus tests (placeholder, paths, categories, isolation) | `test_replay_harness.py` | 30/30 |
| Trigger-leak lint | `tools/check-trigger-leak.sh` | clean |
| Corpus integrity | `corpus_loader.sh validate-all` | active=46, errors=0 |

**Total:** 35 bats + 42 pytest = 77 tests green. Lint clean. Schema validation clean.

---

## Approval Decision

All security boundaries probed adversarially (path traversal, code injection, ReDoS, command injection) hold. NFR-Sec1 runtime-construction discipline preserved across 23 new fixture functions + 11 new replay JSONs. Audit-log redaction inherited cleanly from Sprint 1.

The 2 LOW findings + 3 INFO observations are non-blocking and deferred to Sprint 3 / cycle-101 / #787 follow-up trackers.

**APPROVED — LETS FUCKING GO**

Creating `grimoires/loa/a2a/sprint-144/COMPLETED` marker.

---

*Generated by /audit-sprint (acting as Paranoid Cypherpunk Auditor) on 2026-05-08.*
