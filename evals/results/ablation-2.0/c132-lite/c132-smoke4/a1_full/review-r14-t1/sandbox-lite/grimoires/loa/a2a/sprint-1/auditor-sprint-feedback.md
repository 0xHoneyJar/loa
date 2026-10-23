# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (PR description: `pr/PR.md`)
**Task:** review-r14

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change under audit is `pr/head.diff` (88 files): the `opus` alias moves to the new `claude-opus-5-5` catalog entry and `cheap` to `claude-sonnet-5`; every Anthropic catalog entry gains a `model-permissions.yaml` row; the implement gate becomes heuristic-by-default with an evidence recorder and a config-selected authoritative mode; `check-permissions.sh` gets the second rule grammar; the eval recall grader goes to 1.1.0; and the Sprint 3 instruction-diet edits are reverted per the pre-registered replay A/B rule.

The integrity surfaces verify: the `@loa-managed` hash on `CLAUDE.loa.md` recomputes to the header value (`99948d56…`, via `marker-utils.sh compute-hash`), the catalog checksum matches (`759dfd3f…`), and the PR's `implement-gate.bats` (11/11), `check-permissions.bats` (13/13) and `eval-recall-grader.bats` RG-1..15 pass against the head tree (RG-16/17 need the fixture corpus the snapshot lacks). No secrets, no new dependencies, no new network or exec sinks. Input handling added in this PR (`lib-content.sh` control-byte scrub, `rule_key` grammar, canonical-decimal index guard, `agent-types.yaml` key filter) is sound.

Two things block. First, the grader's new bare-`:N` citation rule treats the JSON pairs inside every review's LOA-VERDICT trailer (and markdown tokens such as `**Severity**:2`) as citations of the last cited file at lines 0–2, so a defect anchored near the top of that file is credited without being cited; reproduced head vs base. This grader produced the recall numbers behind the Task 4.8 revert in this same PR. Second, the gate rewrite keeps an undocumented `implement_gate.mode: authoritative` opt-in under which a model-authored `tool_input.active_skill` silently allows App Zone writes, while an Edit of `.loa.config.yaml` is itself a non-App-Zone write this hook allows silently in the head tree; reproduced end to end. The PR's own header states the field is model-authored and evidence-only.

**Phase 0 note.** `engineer-feedback.md` carries `CHANGES_REQUIRED`, not "All good"; the run-mode orchestrator requested this audit explicitly, so it ran as an independent gate and this deviation is recorded here. The known-failures surface was unreadable at session start (KF-SURFACE warning); triage proceeded without it. `br` is not installed, so the beads steps were skipped.

**Phase 1C dissent.** `adversarial-review.sh --type audit --diff-file pr/head.diff`: two voices (primary `gpt-5.5-pro` answered clean via `codex-headless`; companion `claude-headless` three findings), `consensus`, `voices_succeeded 2/2`, `rejected_summary` empty, `degraded: false`. Not a degraded security review. DISS-C-001 is confirmed below as MEDIUM-001; DISS-C-002 and DISS-C-003 are confirmed as LOW-002 and LOW-003.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Eval grader credits phantom citations from the LOA-VERDICT trailer and markdown tokens

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:74`
**Issue:** The 1.1.0 parser adds a bare-`:N` alternative:

```
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
```

The negative lookbehind excludes word characters, `.`, `/` and `:` but not `"`, `*`, `)`, `]`, `{` or `,`. Every `"critical":0`, `"high":1`, `"medium":0`, `"low":2`, `"excluded":0` pair in the trailer that every Loa review ends with, and tokens like `**Severity**:2`, `(see):1`, `"count":3`, therefore match and bind to the most recent cited path (`:84`) as citations at lines 0–2.

Reproduced against `pr/head/` and `pr/base/` with a two-defect manifest (anchors 3 and 400) and a review citing only `head/.claude/scripts/a.sh:400` followed by the standard trailer:

```
head 1.1.0: {"pass": true,  "score": 100, "detected": ["D-early","D-late"], "citations": 6}
base 1.0.0: {"pass": false, "score": 50,  "detected": ["D-late"], "missed": ["D-early"], "citations": 1}
```

Without a trailer, `**Severity**:2 and "count":3 and (see):1` after the same citation gives `citations: 4` and detects D-early; on a clean fixture without a trailer the false-positive count doubles (2 vs 1 on base).

**Impact:** Any defect whose anchor (or any `anchors[]` site) lies within lines 0–5 of the last file a review cites is credited unconditionally; `details.citations` is inflated on every trailer-bearing review; the no-trailer false-positive path over-counts. This grader is the measurement behind the pre-registered replay A/B rule that Task 4.8 used, in this PR, to revert the Sprint 3 trim and twelve rationales, and it is the fixture corpus's recall metric going forward. RG-1..15 pass on head only because no fixture anchor lies within lines 0–5 of the last cited file; no test places the mandated trailer after a citation with an early anchor.

**Fix:**

```python
# strip the verdict trailer comment before citation parsing (it is parsed separately at `tm = re.search`)
text_for_cites = re.sub(r'<!--\s*LOA-VERDICT\b.*?-->', '', text, flags=re.S)
# and/or widen the lookbehind
r'(?<![A-Za-z0-9_./:"\'*(){}\[\],])'
```

Add an RG test: review `a.sh:400` plus the standard trailer must yield `citations == 1` and must not detect an anchor at line ≤ 5 of `a.sh`; add a no-trailer case with `**Bold**:2`. Re-run the replay A/B with the corrected grader and record whether the Task 4.8 revert stands.

**Reference:** CWE-1286 Improper Validation of Syntactic Correctness of Input — https://cwe.mitre.org/data/definitions/1286.html

---

## Medium Priority Issues

### [MEDIUM-001] Undocumented `implement_gate.mode: authoritative` turns a model-authored field into authorization, and the opt-in file is unfenced by this hook

**Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (DISS-C-001, `claude-headless`)
**File:** `head/.claude/hooks/compliance/implement-gate.sh:115` (selector), `:128-129` (silent allow), `head/tests/unit/implement-gate.bats:151-153` (IG-11 pins the key undocumented)
**Issue:**

```bash
configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
[[ "${configured_mode//\"/}" == "authoritative" ]] && compliance_mode="authoritative"
…
            implement|/implement|bug|/bug|run|/run|simstim|/simstim)
                exit 0
```

The PR's header (`:9-13`) states the PreToolUse payload carries no harness-set skill field and `tool_input` is model-authored. In authoritative mode that field alone allows an App Zone write with no RUNNING state. `.loa.config.yaml` sits at the project root, outside the App Zone; in the head tree a Write/Edit to it reaches "Non-App-Zone writes always allowed" (`:108`) and exits silently. The live install this audit runs on has a later revision that lists `.loa.config.yaml` as a trust input (ask); the PR as frozen does not.

Reproduced on `pr/head/` in a scratch project with no `.run/` state:

```
step 1  Edit {file_path: <root>/.loa.config.yaml, …}                     → exit 0, no output (silent allow)
        (file now holds: implement_gate:\n  mode: authoritative)
step 2  Write {file_path: <root>/src/index.ts, active_skill: "implement"} → exit 0, no output (silent allow)
control same Write without the key                                         → {"decision":"ask","reason":"[ADVISORY] …"}
```

**Impact:** The fenced agent (or a prompt-injected session) can switch the fence off and then self-attest on every App Zone write; no `ask` is raised and nothing is logged on the allow path. The base tree was bypassable through `.run/` files in the same way, so this PR narrows the selector rather than widening it, but it chooses to keep the self-attestation branch, keep the key out of every operator-facing document, and pin that choice with a test. A fence that is weakened by a hidden key is a Think-Before-Coding gap as much as an authz one.

**Fix:** Remove the authoritative branch until a harness-set field exists (the PR's own rationale). If it must stay: require RUNNING state AND the attestation; treat `.loa.config.yaml` (and `.run/platform-features.json`) as trust inputs that `ask` in this hook; write a `compliance.mode.model_signal` row to `audit.jsonl` on every authoritative allow; document the key with its warning in `.loa.config.yaml.example` and drop IG-11.

**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; OWASP A01:2021 Broken Access Control — https://owasp.org/Top10/A01_2021-Broken_Access_Control/

### [MEDIUM-002] Catalog encodes two incompatible long-context pricing models for one vendor family

**Severity:** MEDIUM (confidence: high) — Confirmed by cross-model review (review-phase DISS-C-002)
**File:** `head/.claude/defaults/model-config.yaml:470-509` (new entry), `:562` (first fallback hop keeps the tier), `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:326` and `:348`
**Issue:** The `claude-opus-5-5` entry omits `pricing.long_context`, citing the vendor page: `"Claude 4.6 and later models … include the full 1M token context window at standard pricing", so no long_context tier` (`:473-475`). Its first fallback hop `claude-opus-5` (`:562`), and `claude-sonnet-5`, `claude-fable-5`, `claude-fable-5-1`, keep `long_context: {threshold_tokens: 200000, input_multiplier: 2.0, output_multiplier: 1.5, verified: false}` from the same vendor source. `test_five_family_declares_the_beta_header_list_and_the_long_context_tier` (`:326`) pins the tier on FIVE_FAMILY; the new `test_opus_5_5_has_the_1m_window_at_standard_pricing` (`:348`) pins its absence on 5.5. FIVE_FAMILY excludes 5.5, so both tests pass and the contradiction is locked in.
**Impact:** A request that falls from `opus` to its first hop above 200K input is metered at twice the primary's cost (or the primary is under-metered); budget guards and cost tables tuned on one hop misfire on the other; the migration addendum (`head/docs/migration/v2.0-model-generation-floor.md:245-247`) documents one side only.
**Fix:** Decide once for the 4.6+ family: drop `long_context` from the FIVE_FAMILY entries and update `:326`, or add it to 5.5 with `verified: false` and record in catalog-evidence.md why the vendor statement is not trusted.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

---

## Low Priority Issues

### [LOW-001] `rule_key "$perm"` is a bare call under `set -euo pipefail`
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/scripts/check-permissions.sh:235`
- **Issue:** `rule_key` returns 1 for anything not shaped `Bash(…)` (`:164`). All sixteen `REQUIRED_*` entries are `Bash(…:*)` today, so the path is dead; the first non-Bash requirement added aborts the preflight with exit 1 and no report (or, if `set -e` is relaxed, reuses the previous iteration's `RULE_KEY`).
- **Fix:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }`; reset `RULE_KEY=""` at the top of `rule_key`.
- **Reference:** CWE-252 Unchecked Return Value — https://cwe.mitre.org/data/definitions/252.html

### [LOW-002] Base-wildcard derivation is wrong for an exact-form requirement
- **Severity:** LOW (confidence: high) — Confirmed by cross-model review (DISS-C-002)
- **File:** `head/.claude/scripts/check-permissions.sh:237`
- **Issue:** `base="*${key#\*}"; base="${base%% *}"` — for an exact key `=git push` the strip is a no-op and `base` becomes `*=git`, a key no rule normalises to, so a wildcard deny such as `Bash(git:*)` would not deny an exact requirement (reported as missing rather than denied). No exact requirement exists today; fails toward "missing", never toward "allowed".
- **Fix:** `body="${key#[*=]}"; base="*${body%% *}"`; add a bats case with an exact requirement and a wildcard deny.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [LOW-003] `anthropic:claude-headless` registry row asserts no side effects that nothing enforces
- **Severity:** LOW (confidence: medium) — Confirmed by cross-model review (DISS-C-003)
- **File:** `head/.claude/data/model-permissions.yaml:446-471`
- **Issue:** The row declares `execution_mode: remote_model` and every capability `false` for a local `claude -p` subprocess, while its own notes (`:467-469`) say `extra.allowed_tools` widens what the CLI can do. No parity check ties the row to that catalog knob. Rows have no runtime effect unless `hounfour.feature_flags.context_filtering` is on, which bounds the impact.
- **Fix:** Add a test (or adapter refusal) that fails when the catalog's `claude-headless` `extra.allowed_tools` is non-empty while this row still declares all capabilities false.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-004] 15 bytes of prompt-budget headroom
- **Severity:** LOW (confidence: high)
- **File:** `head/tools/check-prompt-budget.sh:53`
- **Issue:** `LOA_LIMIT` is raised 9,216 → 10,240 B; the reverted `CLAUDE.loa.md` measures 10,225 B. The next rationale regeneration that lengthens a `why` string fails PB-4.
- **Fix:** Set the limit from the measured size plus a stated margin (say so in the comment), or trim non-rendered whitespace.

### [LOW-005] Agent-type registry omits a project agent present on this install
- **Severity:** LOW (confidence: low)
- **File:** `head/.claude/data/agent-types.yaml:26`
- **Issue:** The file lists eight types. `head/tests/unit/skill-capabilities.bats:854` fails on any `.claude/agents/*.md` not listed, and `:850` pins the exact eight-entry string. The install this audit runs on carries `.claude/agents/chart-researcher.md` (read-only) and a later revision of this YAML that lists it. The touched-file snapshot cannot show whether the PR's own tree had that agent; the pinned string suggests it did not, hence low confidence.
- **Fix:** Add `chart-researcher: {write_capable: false}` and any other `.claude/agents/*.md` present at merge; the validator already treats an unlisted type as not write-capable, so this is a test-truth gap, not a fence gap.

---

## Cross-Model Security Observations

All three companion-voice findings were confirmed and tallied above (MEDIUM-001, LOW-002, LOW-003); the primary voice returned no findings. `metadata.locality` is absent and `degraded` is false: no DEGRADED_SECURITY_REVIEW marker.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and `rejected_sidecars` is `[]` in `grimoires/loa/a2a/sprint-1/adversarial-audit.json`; no `adversarial-rejected-audit*.jsonl` sidecar exists beside it.

---

## Observations (not tallied)

- **Review demotions:** the review trailer carries `excluded: 0`; nothing to confirm (`excluded_confirmed: 0`).
- **CHANGELOG (scope limit):** the final commit message cites a CHANGELOG figure but no CHANGELOG file is in the diff; README "Unreleased" (`head/README.md:24`) and the migration addendum are the release notes visible here. The head snapshot holds touched files only, so this cannot be assessed and is not counted.
- **Evidence recorder cost:** `head/.claude/hooks/compliance/implement-gate.sh:39-49` runs up to three `jq` processes on every lead-session Write/Edit, before the `file_path` and App-Zone checks. Harmless; could sit after the App-Zone test.
- **`model-adapter.sh:654`:** `mktemp` under `set -e` aborts the shim with no message if `TMPDIR` is unwritable; previously the call ran. Trivial.
- Verified clean: `lib-content.sh` canonical-decimal guard and control-byte scrub; `detect-platform-features.sh --line` output sanitised (`tr -d '[:cntrl:]' | cut -c1-120`); `validate-skill-capabilities.sh` key filter and fallback; `ensure_license_fixtures.sh` two-window guard; all generated twins (bash maps, BB TS/JS, build manifest) consistent with the catalog; `fallback_chain` of 5.5 → 5 → Sonnet 5 → headless resolves to rows that exist.

---

## Documentation Audit

No `documentation-coherence-task-*.md` reports exist in this sandbox (the PR files are the entire input); documentation was verified manually: README "Unreleased" paragraph and the cycle-126 migration addendum describe the alias moves, the permissions rows, the gate evidence line and the permission grammar accurately. Two gaps: the addendum states one side of the long-context question (MEDIUM-002), and the operator-facing docs intentionally omit the `implement_gate.mode` key that weakens a fence (MEDIUM-001; IG-11 enforces the omission). No secrets or internal URLs in docs or comments; auth-relevant change (gate rewrite) is commented in the hook header.

---

## Acceptance Criteria Check

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Area | Status | Notes |
|------|--------|-------|
| `opus` → 5.5, `cheap` → Sonnet 5 across catalog, generated maps, bash maps, example config, docs | Pass | checksum and generated twins consistent; RES-1/2/3/4/5/7 shapes verified by reading |
| Every Anthropic catalog entry has a permissions row | Pass | 16/16 served entries; `claude-headless` row semantics noted (LOW-003) |
| Implement gate heuristic by default; `.run/` never selects authoritative; evidence recorded once | Pass with finding | 11/11 bats on head; opt-in branch is MEDIUM-001 |
| `check-permissions.sh` second rule grammar | Pass with findings | 13/13 bats on head; LOW-001, LOW-002 dead paths |
| Grader 1.1.0 parser fixes | Fail | HIGH-001 |
| Task 4.8 revert of trim and twelve rationales | Pass | managed hash verifies; golden tables match; headroom LOW-004 |
| License fixture freshness 12-hour window | Pass (unverified in sandbox) | generator not in snapshot |
| Schema v3 typing for the new keys | Pass | `head/.claude/data/schemas/model-config-v3.schema.json:148-243` |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on new inputs — `rule_key` grammar, canonical-decimal guard, control-byte scrub, agent-type key filter
- [ ] Authentication/authorization — the gate's authoritative opt-in honours a model-authored field (MEDIUM-001)
- [x] No SQL/XSS injection vulnerabilities — n/a
- [x] Error handling doesn't leak info — only the agy WARN line is forwarded from cheval stderr
- [ ] Tests cover security paths — no test places a trailer after a citation (HIGH-001); no test ties the headless row to `extra.allowed_tools` (LOW-003)

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | new parsers are allowlist-shaped; grader lookbehind gap |
| SEC-AZ Authorization | 3 | MEDIUM-001 |
| SEC-CI Confidentiality/Integrity | 5 | hashes and checksums regenerate; no secrets |
| SEC-IN Injection | 5 | no shell interpolation of untrusted strings added |
| SEC-AV Availability | 4 | fail-open hook posture preserved; two dead abort paths (LOW-001) |
| ARCH-ST Standards | 3 | MEDIUM-002 contradiction locked by tests |
| CQ Test quality | 3 | RG suite misses the real review shape |
| DevOps | 4 | budget headroom LOW-004 |

---

## Next Steps

1. Fix HIGH-001 (strip the trailer or widen the lookbehind), add the citation-plus-trailer regression, re-run the replay A/B and record whether the Task 4.8 revert stands.
2. Resolve MEDIUM-001: remove the authoritative branch, or fence `.loa.config.yaml` as a trust input, require RUNNING state with the attestation, log the allow, and document the key.
3. Resolve MEDIUM-002 in one direction for the 4.6+ family and update the pinned test.
4. Fold LOW-001..005 as convenient; LOW-005 at merge time against the real `.claude/agents/` directory.
5. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and re-run `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:10:00Z"} -->
