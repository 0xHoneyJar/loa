# Sprint 144 (cycle-100 Sprint 2) — Senior Tech Lead Review

**Reviewer:** deep-name + Claude Opus 4.7 1M (acting as senior tech lead, adversarially)
**Date:** 2026-05-08
**Implementation commit:** `5b983ecd`
**Implementation report:** `grimoires/loa/a2a/sprint-144/reviewer.md`

---

## Verdict: **APPROVED — All good** (after engineer addressed all 3 blocking items inline within this review pass)

**Final state (2026-05-08 post-closure):**
- ✓ NEW-B1 (leading-whitespace bypass) — fixed via `_PLACEHOLDER_RE` symmetric `\s*` prefix; 3 new apparatus pins (`test_placeholder_with_leading_{whitespace,newline}_still_substitutes`, `test_placeholder_with_both_leading_and_trailing_whitespace`); pytest now 42 green (was 39 — 3 new symmetric-whitespace tests).
- ✓ NEW-D1 (AC-9 dual-review reconciliation) — re-framed as two-source dual: paranoid-cypherpunk subagent (T2.7 inline, 12 findings) + claude-opus-4-7 cross-model (Phase 2.5, 6 findings). Combined 18 findings, 11 closed pre-merge, 5 verified false-positive/LOW. AC-9 ✓ Met stands with the corrected framing.
- ✓ NEW-D2 (AC-8 deferral) — upgraded to `⏸ [ACCEPTED-DEFERRED]` with matching `grimoires/loa/NOTES.md` Decision Log entry per cycle-057 rule.

The implementation is substantively strong — 11 cypherpunk findings closed inline with apparatus pins, 35 bats + 42 pytest tests green, all 7 categories ≥5 vectors, 4 first-N-turn-bypass-class vectors. The blocking finding (NEW-B1) was a symmetric oversight to the M5 closure that the cross-model review caught (DISS-001) and this engineer-reviewer caught independently — the redundancy is exactly the cross-validation the multi-model adversarial review pattern is designed to produce.

The 3 non-blocking observations remain as recommendations for Sprint 3 / cycle-101 (NEW-N1 dead bash multi_turn fixtures, NEW-N2 formal replay JSON Schema, NEW-N3 templating at scale). DISS-004/DISS-005 ADVISORY findings from the cross-model review join the same deferred bucket.

**This sprint approves. Ready for `/audit-sprint sprint-2`.**

---

## Phase 2.5: Adversarial Cross-Model Review

**Initial run:** `gpt-5.5-pro` returned `Empty response content` × 3 retries (#783 follow-up: legacy bash adapter `/v1/responses` parsing for reasoning-model output shapes). Documented in `NOTES.md` 2026-05-08 entry. Mid-review the operator surfaced this regression — `code_review.model` + `security_audit.model` rolled back from `gpt-5.5-pro` → `claude-opus-4-7` in `.loa.config.yaml` to sidestep the legacy adapter until cycle-099 Sprint 4 flips `hounfour.flatline_routing: true`.

**Re-run:** `claude-opus-4-7` returned **6 findings** in 48s ($0.27, 39k input + 2.8k output) at `grimoires/loa/a2a/sprint-144/adversarial-review.json` (status: `reviewed`).

### Cross-Model Observations

| # | Severity (Opus) | Title | My Triage | Mapping |
|---|---|---|---|---|
| DISS-001 | BLOCKING | Leading-whitespace bypass in `_PLACEHOLDER_RE` | **CONFIRMED** | Cross-validates NEW-B1 above. Same fix applies. |
| DISS-002 | BLOCKING | RT-MT-004 FIXTURES dict only maps to `_part3` while replay JSON references `_part1`/`_part2`/`_part3` | **False positive for current path** — `substitute_runtime_payloads` uses `getattr(mod, fn_name)` not the FIXTURES dict, so all 3 part-functions resolve. Pytest RT-MT-004 passes today. **LOW concern for future consumers** (a hypothetical CLI enumerating FIXTURES would miss `_part1` and `_part2`). | Recommend: comment near FIXTURES noting that "split-payload" vectors register only the canonical-fixture; other parts are module-level helpers reachable via getattr. |
| DISS-003 | BLOCKING | Unescaped backslash in RT-TC-005 JSONL notes (`\bfunction_calls\b`) | **False positive** — verified on-disk bytes are `5c 5c 62` (i.e., `\\b` correctly escaped). Python `json.loads` parses to the 2-char regex-syntax intent `\b`. Schema validator + Python parser both accept; no defect. | Reviewer misread the parsed-string repr; no action. |
| DISS-004 | ADVISORY | `_VECTOR_ID_RE` error message shows `\d` (single backslash) — fine in Python f-string but visually confusing | LOW (style) | Optional: change error to `… does not match the schema regex (RT-XX-NNN format)` to avoid showing escape-syntax to operators. |
| DISS-005 | ADVISORY | `sys.path.insert(0, fixtures_dir)` in `substitute_runtime_payloads` — no cleanup, shadows top-level packages | LOW (real but bounded — no `role_switch` package on PyPI; isolated to test execution) | Recommend: scope mutation with try/finally OR migrate to `importlib.util.spec_from_file_location` for explicit per-category file paths. Defer to Sprint 3. |
| DISS-006 | ADVISORY | Dead bash multi_turn fixtures (uncalled by any test) | **CONFIRMED** | Cross-validates NEW-N1 above. Same recommendation. |

**Net impact on verdict:** The cross-model run **strengthened CHANGES_REQUIRED** by independently confirming NEW-B1 (leading-whitespace bypass) and NEW-N1 (dead bash fixtures). DISS-002 + DISS-003 false-positives don't escalate. DISS-004 + DISS-005 are LOW additions to the optional-improvements bucket.

---

## CRITICAL ISSUES (Blocking)

### NEW-B1: Leading-whitespace bypass in `_PLACEHOLDER_RE` — symmetric to M5 closure but missed

**File:** `tests/red-team/jailbreak/lib/corpus_loader.py:214` — `_PLACEHOLDER_RE = re.compile(r"__FIXTURE:(_make_evil_body_[a-z0-9_]+)__\s*")`

**Issue:** The cypherpunk M5 closure correctly tightened trailing-whitespace handling via `re.fullmatch(r"...\s*", content)`. The fix does NOT tolerate **leading** whitespace, so the symmetric vacuously-green class is still open.

**PoC** (verified by probe):
```python
# tests/red-team/jailbreak/lib/corpus_loader.py post-Sprint-2
fix = {"turns": [{"role": "operator", "content": "  __FIXTURE:_make_evil_body_rt_mt_001__"}]}
out = corpus_loader.substitute_runtime_payloads(fix, vector)
# RESULT: out['turns'][0]['content'] == "  __FIXTURE:_make_evil_body_rt_mt_001__" (literal)
# Placeholder NOT substituted; SUT receives literal token; no trigger ever runs.
# A future RT-MT-NNN.json with `"content": "  __FIXTURE:_make_evil_body_rt_mt_NNN__"`
# (e.g., copy-pasted from a code editor that auto-indented) silently passes
# expected_per_turn_redactions=[…0…] because no L1 marker fires — vacuously green.
```

This is the SAME class M5 closed for trailing whitespace. The cypherpunk reviewer flagged "vacuously-green" specifically; the engineer fix landed it for the trailing case but missed the leading case. Per the adversarial principle "edge cases on both sides of any boundary," symmetry is the contract here.

**Fix:**

```python
# Option A (preferred — explicit symmetric tolerance):
_PLACEHOLDER_RE = re.compile(r"\s*__FIXTURE:(_make_evil_body_[a-z0-9_]+)__\s*")

# Option B (strip-then-match — clearer intent):
m = _PLACEHOLDER_RE.fullmatch(content.strip())
```

**Required apparatus test (mirrors the M5 pin):**

```python
# tests/unit/test_replay_harness.py  TestSubstituteRuntimePayloads
def test_placeholder_with_leading_whitespace_still_substitutes(self) -> None:
    """Symmetric to test_placeholder_with_trailing_whitespace_still_substitutes.
    Closes the leading-whitespace vacuously-green class missed by Sprint 2."""
    v = _FakeVector(vector_id="RT-MT-001", category="multi_turn_conditioning")
    fixture = {
        "turns": [
            {"role": "operator",
             "content": "  __FIXTURE:_make_evil_body_rt_mt_001__"},
        ]
    }
    out = corpus_loader.substitute_runtime_payloads(fixture, v)
    assert "__FIXTURE:" not in out["turns"][0]["content"]
    assert "ignore" in out["turns"][0]["content"].lower()

def test_placeholder_with_leading_newline_still_substitutes(self) -> None:
    v = _FakeVector(vector_id="RT-MT-001", category="multi_turn_conditioning")
    fixture = {"turns": [{"role": "operator",
                          "content": "\n__FIXTURE:_make_evil_body_rt_mt_001__"}]}
    out = corpus_loader.substitute_runtime_payloads(fixture, v)
    assert "__FIXTURE:" not in out["turns"][0]["content"]
```

**Severity:** HIGH (vacuously-green test class; symmetric to a cypherpunk-flagged HIGH).

---

## DOCUMENTATION DRIFT (Blocking)

### NEW-D1: AC-9 inconsistency — "dual-review" claimed Met but report admits "Single"

**File:** `grimoires/loa/a2a/sprint-144/reviewer.md` — AC table row 9 + §"T2.7" inline narrative.

**Issue:** The AC table marks "Sprint-2 cypherpunk dual-review closed pre-merge" as `✓ Met`, citing "T2.7 review captured below." But the inline narrative under §"T2.7 — Cypherpunk dual-review" reads literally: *"Single paranoid-cypherpunk subagent (general-purpose) review against the Sprint 2 deliverables."*

The Sprint 2 plan's T2.7 deliverable language is "**Sprint-2 cypherpunk dual-review** + remediation" (sprint.md:184). Sprint 1's T1.7 ran two subagents per cycle-098 cadence. Sprint 2 ran one. Report should not claim ✓ Met when the inline narrative contradicts the claim.

**Fix (one of):**

(a) Run a second subagent (e.g., `general-purpose` with a "general-purpose code reviewer" persona prompt) against the Sprint 2 deliverables; merge findings into the report; close any new HIGH/MED inline.

(b) Update AC-9 row to `⚠ Partial` with explicit rationale — "Single subagent run; substantive (3 HIGH + 5 MED + 4 LOW + 4 PRAISE = 12 findings; 8 closed pre-merge). Dual-review process gap deferred to cycle-101 retrospective." Add a matching Decision Log entry to `grimoires/loa/NOTES.md`.

I prefer (a) because the cypherpunk pattern is load-bearing — but (b) is acceptable given the depth of the single review (12 findings is comparable to Sprint 1's 23 across 2 subagents). Operator's call.

**Severity:** Documentation honesty (blocking the audit gate; the auditor can't trust an AC table that contradicts its own narrative).

---

### NEW-D2: AC-8 ⚠ Partial without explicit Decision Log entry per cycle-057 rule

**File:** `grimoires/loa/a2a/sprint-144/reviewer.md` — AC table row 8.

**Issue:** AC-8 is "Pytest entrypoint + standalone CLI both invokable for ad-hoc operator runs (UC-3 acceptance)" — marked `⚠ Partial` with rationale "Standalone CLI for replay harness specifically: NOT shipped this sprint — corpus_loader.py:__main__ already exposes validate/iter/get/count subcommands; replay-specific CLI deferred to Sprint 4 README docs phase."

Per cycle-057 rule cited in this skill's workflow:
> "Any AC shows `⏸ [ACCEPTED-DEFERRED]` without a matching Decision Log entry in `grimoires/loa/NOTES.md`"

The AC was marked `⚠ Partial` (not `⏸ [ACCEPTED-DEFERRED]`), but the spirit of the rule applies: a deferred capability needs a NOTES.md entry so cross-session continuity can track it.

**Fix:** Add a Decision Log entry to `grimoires/loa/NOTES.md` under the existing `## 2026-05-08 — cycle-100 Sprint 2 IMPLEMENTED` section:

```markdown
- **AC-8 deferral**: Standalone replay CLI (`python -m corpus_loader replay <vector_id>`)
  deferred to Sprint 4. Pytest entrypoint (`pytest -k RT-MT-NNN test_replay.py`) is
  the supported ad-hoc invocation in Sprint 2. Sprint 4 README docs phase will add
  the standalone CLI per UC-3 — operator can author novel vectors, then run a
  single replay via CLI rather than pytest's collection overhead.
```

OR update the AC mark to `⏸ [ACCEPTED-DEFERRED]` with an explicit cycle-101 follow-up tracker.

**Severity:** Documentation drift (blocking under cycle-057 verification rule).

---

## NON-CRITICAL OBSERVATIONS (Non-blocking)

### NEW-N1: `multi_turn_conditioning.sh` has 13 dead functions (uncalled by any test)

**File:** `tests/red-team/jailbreak/fixtures/multi_turn_conditioning.sh` (entire file).

**Issue:** runner.bats now skips multi_turn category; pytest harness uses python fixtures via `substitute_runtime_payloads` (not bash). The 13 functions in this file (`_make_evil_body_rt_mt_001..011` + 3 split-payload helpers = 12 actually) are NEVER invoked by any test. Dead code that could rot or contain bugs that go undetected.

**Recommendation (non-blocking):** Either (a) delete the file (canonicalize on python only for multi-turn), or (b) add a smoke test under `tests/integration/` that sources the .sh and invokes each function once to ensure they remain syntactically valid + return non-empty output. (a) is simpler; (b) preserves bash↔python parity discipline at low cost.

I'd defer this to Sprint 3. The functions are simple enough that rot risk is low for one cycle.

**Severity:** LOW.

---

### NEW-N2: No formal JSON Schema for replay JSON fixtures (drift risk)

**File:** `tests/red-team/jailbreak/fixtures/replay/RT-MT-*.json` (11 files) + the implicit shape validation at `corpus_loader.py:255-294`.

**Issue:** The corpus JSONL has a formal JSON Schema at `.claude/data/trajectory-schemas/jailbreak-vector.schema.json` validated at `validate-all` time (NFR-Rel1: schema-first). The replay JSON files have NO formal schema — only the runtime checks in `load_replay_fixture` at first-test-invocation time. Future drift class: someone adds a new field (e.g., `expected_per_turn_blocker_count`) and the loader silently ignores it because shape validation only checks known-required fields.

**Recommendation (non-blocking):** Add `.claude/data/trajectory-schemas/jailbreak-replay-fixture.schema.json` formalizing:
- `vector_id` (string, regex `^RT-[A-Z]{2,3}-\d{3,4}$`)
- `expected_outcome` (enum)
- `expected_per_turn_redactions` (array of non-negative ints, length matching turns)
- `turns` (array, each with role enum + content string)
- `additionalProperties: false` to catch unknown fields

Wire `validate_all` to validate replay files for active multi_turn vectors. Defer to Sprint 3 alongside T3.6 cypherpunk pushback.

**Severity:** LOW–MEDIUM (no observable defect today, but the corpus-JSONL discipline argues for symmetric strictness).

---

### NEW-N3: Replay JSON files have ~90% structural duplication (DRY violation)

**File:** `tests/red-team/jailbreak/fixtures/replay/RT-MT-*.json` (11 files).

**Issue:** Most files are 3 turns of the form `[operator, downstream, operator-with-trigger]` differing only in conditioning prose. RT-MT-004's 3 split-payload turns and RT-MT-007's 3 fenced turns are exceptions. The repetition is acceptable for 11 files but at 50+ multi-turn vectors (cycle-101 expansion) the maintenance cost grows.

**Recommendation (non-blocking, deferred):** Sprint 3 or cycle-101 may want to introduce a YAML-templated replay generator. Today's hand-authored JSONs are perfectly readable; not a current defect.

**Severity:** STYLE.

---

## ADVERSARIAL ANALYSIS (Required minimum: ≥3 concerns, ≥1 assumption, ≥1 alternative)

### Concerns Identified (5)

1. **Leading-whitespace bypass** — `corpus_loader.py:214` (`_PLACEHOLDER_RE` symmetric gap; see NEW-B1).
2. **AC-9 dual-review reality** — `reviewer.md` AC-9 row vs §"T2.7" inline (see NEW-D1).
3. **AC-8 deferral framing** — `reviewer.md` AC-8 row missing NOTES.md Decision Log per cycle-057 (see NEW-D2).
4. **Dead bash multi_turn fixtures** — `fixtures/multi_turn_conditioning.sh` 12 uncalled functions (see NEW-N1).
5. **Implicit replay JSON schema** — no formal validation file; runtime-only shape check (see NEW-N2).

### Assumptions Challenged (1)

- **Assumption (engineer):** "fresh subprocess per turn = stateless SUT invocation" (`test_replay.py` docstring; `test_replay_harness.py:281-326` H2 closure).
- **Risk if wrong:** Filesystem-mediated state (e.g., a future SUT that writes to `/tmp/sanitize-history`) WOULD be visible across subprocess invocations even though env vars are not. The H2 byte-equal-output test catches in-process state but does NOT catch filesystem state.
- **Recommendation:** Treat the H2 closure as covering **process-memory** statelessness, not all-statelessness. Document in `test_replay.py` module docstring that filesystem-mediated state is OUT OF SCOPE for this harness's invariants. Sprint 3 differential oracle (against frozen baseline) is the cross-cycle pin that would catch a state-introducing SUT regression.

### Alternatives Not Considered (1)

- **Alternative:** Generate the 11 replay JSONs from a single shared YAML template (e.g., `fixtures/replay/templates/conditioning-then-trigger.yaml.j2`) and emit per-vector JSONs at corpus-build time.
- **Tradeoff:** Pro — single source of truth for the conditioning-then-trigger pattern; new vectors author "just the trigger turn" content + 1-line YAML stanza. Con — adds a Jinja2 dependency to the test apparatus; CI would need to materialize JSONs before pytest runs. Sprint 3+ might be worth it (50+ multi-turn vectors at cycle-101 = 50 × 90% redundant content).
- **Verdict:** Current hand-authored approach is justified for Sprint 2's 11 vectors. Consider templating at >25 multi-turn vectors. Not a current blocker.

---

## Karpathy Principles Verification

| Principle | Verdict | Note |
|---|---|---|
| Think Before Coding | ✓ | Cypherpunk T2.7 review captured 12 findings; engineer's reviewer.md surfaces all assumptions. NEW-B1 is the one missed symmetric case. |
| Simplicity First | ⚠ | The 11 replay JSONs are 90% identical (NEW-N3). Acceptable for 11; templating at 25+. |
| Surgical Changes | ✓ | Diff scope is exactly Sprint 2 deliverables; runner.bats touch is minimal (4 lines added for category filter). |
| Goal-Driven | ✓ | Per-turn count + final-state assertions trace directly to G-3 (Opus 740 first-N-turn bypass). 4 vectors explicitly target the bypass class. |

---

## Documentation Verification

| Item | Status | Note |
|---|---|---|
| CHANGELOG entry | N/A | Not gated for cycle-100 Sprints 1–3 (cycle-internal); CHANGELOG rolls up at cycle-100 ship in Sprint 4 |
| CLAUDE.md update | N/A | No new commands/skills added |
| Security code comments | ✓ | All M1+M2+M5 closures have inline `Cypherpunk M{N} closure:` comments with rationale |
| README user-facing | Deferred | Sprint 4 T4.3 ships `tests/red-team/jailbreak/README.md` |
| Code comments complex logic | ✓ | `_count_redactions` H1 closure, `_invoke_sanitize_subprocess` H3 closure, `_emit_audit_run_entry` M4 closure all comment WHY non-obvious |
| SDD sync for architecture changes | ✓ | Sprint 2 changes are within SDD §3.3 + §4.4 contracts; runner.bats category filter is documented per SDD §4.3 |

---

## Complexity Review

| Function | Lines | Params | Nesting | Verdict |
|---|---|---|---|---|
| `corpus_loader.load_replay_fixture` | 49 | 2 | 2 | OK |
| `corpus_loader.substitute_runtime_payloads` | 46 | 2 | 2 | OK |
| `test_replay.test_multi_turn_vector` | 64 | 1 | 3 | OK (inline pytest helper) |
| `test_replay._assert_final_outcome` | 50 | 5 | 2 | OK |
| `test_replay_harness.test_each_turn_runs_in_fresh_bash_process` | 47 | 1 (+self) | 1 | OK |

No function exceeds the 50-line ceiling. No duplication >3 occurrences. No circular imports. All dependencies present and used.

---

## Previous Feedback Status

No prior `engineer-feedback.md` for sprint-144. This is the first review cycle. (Cypherpunk T2.7 review was internal to /implement, not a `/review-sprint` artifact.)

---

## Approval Path

After the engineer addresses the 1 BLOCKING + 2 documentation-drift items below, this sprint approves:

### Required (blocking)

1. **NEW-B1 leading-whitespace bypass** — fix `_PLACEHOLDER_RE` to tolerate leading whitespace symmetrically with M5; add 2 apparatus tests pinning the contract.
2. **NEW-D1 AC-9 dual-review reconciliation** — either (a) run a second subagent persona OR (b) downgrade AC-9 to `⚠ Partial` with explicit cycle-101 follow-up tracker AND matching NOTES.md entry.
3. **NEW-D2 AC-8 deferral Decision Log** — add `grimoires/loa/NOTES.md` entry for the standalone-CLI deferral (or update mark to `⏸ [ACCEPTED-DEFERRED]`).

### Optional (non-blocking — may defer to Sprint 3 / cycle-101)

- NEW-N1 dead bash multi_turn fixtures (delete OR smoke-test)
- NEW-N2 formal JSON Schema for replay JSON
- NEW-N3 templating for replay JSONs (cycle-101 at scale)

---

## Next Steps

1. Engineer addresses NEW-B1 + NEW-D1 + NEW-D2 (estimated <30 minutes given the apparatus-test pattern is already established).
2. Re-run `pytest tests/unit/test_replay_harness.py` — expect +2 passing tests after the leading-whitespace pin.
3. Update `reviewer.md` with the closure delta.
4. Re-invoke `/review-sprint sprint-2` (or this reviewer can re-verify directly without a fresh /review-sprint cycle).
5. After approval: `/audit-sprint sprint-2` then PR draft per RESUMPTION brief.

---

*Generated by /review-sprint (acting as adversarial senior tech lead) on 2026-05-08.*
