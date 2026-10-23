# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Gate:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — CHANGES_REQUIRED (trailer `excluded: 0`)
**Scope:** `pr/head.diff`, 88 files — cycle-126 sprint-250 tasks 4.1–4.8: `opus` → `claude-opus-5-5`, `cheap` → `claude-sonnet-5`, a `model-permissions.yaml` row for every Anthropic catalog entry, the implement-gate evidence recorder, the `check-permissions.sh` rule grammar, eval grader 1.1.0, and the Sprint 3 instruction-diet revert.
**Dissent:** DEGRADED_SECURITY_REVIEW — see "Rejected dissent payloads".

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The security posture of this change is sound. Every new remote-model row copies the all-`none` trust scopes and `security: redacted` context access of the 4.7 entry, and a parity test now makes an unscoped Anthropic catalog entry impossible. The implement gate no longer lets anything in `.run/` or in a model-authored payload select authoritative mode; the evidence recorder is lead-only, write-once and atomic, and a forged `active_skill` payload is refused whatever `.run/` claims (IG-5). The permission checker's new grammar is pure parameter expansion with no glob or eval, deny still wins in every layer, and Claude Code's own documentation confirms the `:*` and trailing ` *` forms are equivalent. Control bytes are stripped before diff header paths reach stderr, and the shim forwards only the one fixed-string cheval WARN. No secrets, no new dependencies, no injection surface.

What blocks the merge is a correctness defect in a measuring instrument. The 1.1.0 citation parser in the eval recall grader adds a bare `:N` alternative whose lookbehind admits a double quote, so the counts in every graded review's own LOA-VERDICT trailer become line citations bound to the last cited file. Reproduced here on head and absent on base, it inflates recall for exactly the grader the Task 4.8 replay A/B rule relies on. Two medium items follow it: the new agent-type registry misses an agent present in the tree so its completeness test is red, and the rationale revert never reached the rendered Agent Teams block that the model actually reads. Six low items round it out, including a second, environmental reason the registry test fails (a `yq` function the installed version lacks).

Independently verified in a scratch copy of the head tree: CP-1..13, IG-1..11, CH-T1..T14, MA-1..6, RES-1..7, IDR-1..4, FMT-1..6, CMP-277/278, the V3 c126 schema additions, the bd-8ndx validate-artifact cases, LFF-1/2, RG-1..15 and the hook-guard WARN test all pass; `gen-adapter-maps.sh` regenerates `generated-model-maps.sh` byte-identical; the catalog checksum verifies. Not verifiable in this sandbox: the five Python adapter test files (the snapshot's `loa_cheval` package fails to import `TransportPolicy`), RG-16/17, PB-8, PR-1 and c124-1.3-11 (fixture corpus, allowlist and regen script absent), the `.loa.config.yaml.example` hunks (file absent), and the Bridgebuilder `dist/` rebuild (`tsx` absent).

**Prerequisite note.** The review gate's verdict is CHANGES_REQUIRED rather than "All good". The audit ran anyway on the orchestrator's explicit instruction so both gates' findings land together; the sprint still owes a re-review after the fixes below.

**Security Issues Found (Severity Tally):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 6 |

`excluded`: 0 (no high demoted to Observations). `excluded_confirmed`: 0 — the review trailer carries `excluded: 0`; there were no demoted highs to confirm or re-tally.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Eval grader — bare `:N` citations bind JSON values to the last cited file

**Severity:** HIGH | **Confidence:** high
**File:** `head/evals/graders/recall-vs-defects.sh:74`
**Issue:** The 1.1.0 parser's second alternative

```python
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
```

rejects only identifier and path characters before the colon. A `"`, `'`, `}`, `]`, `)` or `*` passes, so any `"key":N` after a cited path is a citation of line N in that file. Every graded review ends with a verdict trailer whose JSON carries `"counts":{"critical":0,"high":0,"medium":7,"low":0}`, which yields bare citations 0, 0, 7, 0 against the last cited path. Reproduced on head with a synthetic manifest (D3 anchored at `c.sh:7`, D4 at `d.sh:2`, D5 at `e.sh:0`):

```
review: c.sh:100 is odd.  + trailer with "medium":7      → detected ["D3"], citations 6
review: d.sh:300 … JSON body: {"line":1,"count":2}        → detected ["D4"], citations 3
review: e.sh:900 fine.  + all-zero trailer                → detected ["D5"], citations 5
control: c.sh:100 is odd. (no trailer)                    → detected [],     citations 1
base 1.0.0 parser on the first review                     → detected [],     citations 1
```

The third case matters most: an all-zero trailer, the shape of every approving review, auto-detects any defect anchored within lines 0–3 of whichever file the review cited last. The header contract at lines 17–21 ("a `:N` glued to a word or a number … or with no cited path before it, credits nothing") is not what the code does.
**Impact:** `recall-vs-defects.sh` is the pre-registered instrument behind the Task 4.8 replay A/B decision (the revert in this same PR) and the review-PR eval corpus. Recall is over-reported for defects anchored near the top of a file or at a count value, so the A/B comparison that justified reverting the instruction diet, and every future comparison, is measured with a biased ruler. RG-11..15 pass only because their trailer counts (1, 1, 0, 0) fall outside the ±3 window of the planted anchors.
**Fix:** Restrict the bare alternative to a preceding whitespace, start-of-text, backtick or opening paren. Python lookbehinds are fixed-width, so use `(?:^|(?<=[\s`(]))` for the empty branch and extend the lookbehind before `head|base` the same way. Add RG cases: a trailer whose count equals a planted anchor, and an inline JSON object after a citation, each asserting zero detections. Also scope the binding (see LOW-002). Bump `grader_version` to 1.1.1 and re-run the replay A/B that drove Task 4.8.
**Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

---

## Medium/Low Priority Issues

### [MED-001] agent-types.yaml does not list every agent under `.claude/agents/`
- **Severity:** MEDIUM | **Confidence:** medium
- **File:** `.claude/data/agent-types.yaml:25` (last row, `prompt-auditor-io`); test at `head/tests/unit/skill-capabilities.bats:854`; table at `.claude/rules/skill-invariants.md:18`
- **Issue:** The new registry names `loa-scout`, `prompt-auditor`, `prompt-auditor-io`. The tree also carries `.claude/agents/chart-researcher.md` (tools: Read, Grep, Glob, WebFetch), so the completeness loop in SC-T-AGENT-7 fails here: `unlisted: .claude/agents/chart-researcher.md`. Confidence is medium because the snapshot's `.claude/` tree is not provably the PR's base (its Python adapter package is from another revision), though `agent-types.yaml` and the CLAUDE.loa.md hash do match head. The validator treats an unlisted type as not write-capable, so the runtime default is safe either way.
- **Fix:** Add `chart-researcher: {write_capable: false}`, add it to the read-only row in `skill-invariants.md`, and extend the expected string in SC-T-AGENT-7.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-002] Rationale revert — the rendered Agent Teams block still carries the trimmed text
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `.claude/loa/CLAUDE.loa.md:124` (block marker `hash:c020-teamcreate`); data at `.claude/data/constraints.json:1235-1320`; test at `head/tests/unit/instruction-diet-revert.bats:61-62`
- **Issue:** Task 4.8 reverts C-TEAM-001..005 `why` to the pre-diet text ("Planning skills produce single artifacts (PRD, SDD, sprint plan) that assume single-writer semantics; …") and IDR-3 pins it, but the generated block the model reads still renders "Planning skills assume single-writer semantics", "SQLite single-writer prevents lock contention", and so on. `.claude/scripts/generate-constraints.sh --validate-only` fails: `STALE: Section 'agent_teams_constraints' … (stored: c020, expected: 19641576807c2086)`. IDR-4 pins only the seven C-PROC rows, so the sprint's own tests cannot see it. The block was already STALE at base, so this is pre-existing drift that the revert was meant to close and did not, rather than new breakage.
- **Fix:** Run `generate-constraints.sh` (or hand-sync and update the marker hash), widen IDR-4 to the five C-TEAM rows, and make the validate-only step part of the test. Expect LOW-004 to trip when you do.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] SC-T-AGENT-7 uses a `yq` function the installed version does not provide
- **Severity:** LOW | **Confidence:** high
- **File:** `head/tests/unit/skill-capabilities.bats:850`
- **Issue:** `yq -r '.agent_types | to_entries | map(.key + "=" + (.value.write_capable | tostring)) | join(" ")'` fails on mikefarah yq v4.40.5 with `Error: 1:70: invalid input text "tostring)) | joi..."` (`to_string` fails the same way), so the assertion at line 851 is red before the registry loop runs. The validator itself only relies on `select(.value.write_capable == true) | .key`, which works (SC-T-AGENT-8/9 pass).
- **Fix:** Render through JSON (`yq -o=json '.agent_types' | jq -r 'to_entries | map(.key + "=" + (.value.write_capable|tostring)) | join(" ")'`) or compare the sorted list of write-capable keys using the validator's own expression.
- **Reference:** CWE-1104 Use of Unmaintained Third Party Components (version-dependent behaviour) — https://cwe.mitre.org/data/definitions/1104.html

### [LOW-002] Grader — the most-recent-path binding never resets
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/graders/recall-vs-defects.sh:77`
- **Issue:** `last` is set on the first path citation and never cleared, so a bare `:N` in a later section or in the trailer still binds to it, contrary to the header's "with no cited path before it … credits nothing". Same root cause as HIGH-001; the fix is distinct.
- **Fix:** Iterate per paragraph (reset `last` at a blank line) or require the bare `:N` on the same line as the path it binds to.
- **Reference:** CWE-185 — https://cwe.mitre.org/data/definitions/185.html

### [LOW-003] Catalog comment misdescribes the Opus 5.5 ceiling as measured
- **Severity:** LOW | **Confidence:** high
- **File:** `.claude/defaults/model-config.yaml:491`
- **Issue:** The `loa:shortcut` marker reads "Opus 5's measured bound, not probed on 5.5"; the catalog shows `claude-opus-5.ceiling_calibration.source: kf_derived`, `calibrated_at: null`. Nothing was measured.
- **Fix:** "Opus 5's kf-derived bound (conservative default), not probed on 5.5". The upgrade trigger (`tools/ceiling-probe-live.py --write-catalog`) is right.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-004] CLAUDE.loa.md sits 15 bytes under the restored budget
- **Severity:** LOW | **Confidence:** high
- **File:** `head/tools/check-prompt-budget.sh:53`
- **Issue:** `LOA_LIMIT` is restored to 10,240 B; `tools/check-prompt-budget.sh --root .` reports `CLAUDE.loa.md 10225 B (limit 10240)`. Regenerating the Agent Teams block (MED-002) lengthens five rows and will turn PB-9 red.
- **Fix:** Set the limit with headroom for the regenerated block, or document that the limit tracks the file by design and move it in the same change as MED-002.
- **Reference:** CWE-710 Improper Adherence to Coding Standards — https://cwe.mitre.org/data/definitions/710.html

### [LOW-005] model-adapter.sh — `mktemp` failure exits without the shim's own error
- **Severity:** LOW | **Confidence:** medium
- **File:** `.claude/scripts/model-adapter.sh:656`
- **Issue:** `err_file="$(mktemp …)"` runs under `set -euo pipefail` (line 33); if mktemp fails the shim exits before `error "model-invoke failed …"` and the exit-code translation, with only mktemp's stderr. No `trap` removes the file if the hop is interrupted.
- **Fix:** `err_file=$(mktemp …) || { error "cannot create stderr capture file"; exit 1; }` and `trap 'rm -f -- "$err_file"' EXIT`, matching how `call_flatline_chat` guards its mktemp.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-006] Process — no documentation-coherence reports, no AC Verification walkthrough
- **Severity:** LOW | **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1`
- **Issue:** `grimoires/loa/a2a/subagent-reports/` does not exist (no `documentation-coherence-task-*.md` or `-sprint-*.md`), and the implementation report is the PR description with no `## AC Verification` section. Documentation was verified manually instead: the README and migration addendum match the code for the alias retargets, the permission grammar and the gate evidence line; the `model-permissions.yaml` headless row documents the `extra.allowed_tools` widening; no security-relevant change lacks documentation.
- **Fix:** Add the AC walkthrough with `file:line` evidence and run the documentation-coherence pass before the next review.

---

## Observations (not tallied)

- **Permission grammar edge shapes (pre-existing at base, conservative).** Claude Code treats `Bash(*)` and bare `Bash` as allow-all and `Bash(git*)` (no space) as a wildcard that also matches `gitk`; `rule_key` credits none of them (`.claude/scripts/check-permissions.sh:89-97`), so an operator who allows everything is told requirements are missing, and a deny-all `Bash` rule is not reported as a denial. The base checker had the same gaps. Worth a follow-up row in CP-13, not a defect this PR introduces.
- **The authoritative opt-in lives in a model-writable file (speculative, confidence low).** `implement_gate.mode` is read from `.loa.config.yaml` (`.claude/hooks/compliance/implement-gate.sh:115`), which no PreToolUse hook fences (zone-write-guard covers `.claude/` only). A session could write the key and then an `active_skill: implement` payload to pass the gate silently. This is the same class as the base behaviour, which keyed off `.run/platform-features.json` and was strictly easier to forge, so the PR narrows the surface; the config file is operator territory by design, and the fence is documented as fail-ask advisory. Recorded so the trust boundary is explicit; not counted.
- **`security-audit-scope.sh` prints `00` for zero counts** (`"controllers": 00`); not part of this change.
- **Dissent degraded.** See below.

---

## Rejected dissent payloads

- None. The adversarial audit ran (`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`); the envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json` stands with `metadata.status: api_failure`, `degraded: true`, `findings: []`, `rejected_sidecars: []`, and no `adversarial-rejected-audit*.jsonl` beside it. All four hops (`gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro`, `claude-headless`) and the Anthropic companion voice failed with exit 126: the snapshot's `.claude/scripts/model-adapter.sh` is not executable and no provider credentials exist in this sandbox. `verdict_quality.status: FAILED`, 0 of 1 voices succeeded. This is a **DEGRADED_SECURITY_REVIEW**: single-model assessment applies and the dissent should be re-run where the adapter is executable and credentials exist before the sprint is closed.

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|----------|-------|-------|
| Security | 4.2/5 | IV 4 (rule_key, chunk index, control-byte strip), AZ 5 (permission rows mirror 4.7; gate ignores `.run/`), CI 4, IN 4, AV 4 |
| Architecture | 3.8/5 | Registry-as-data (agent-types.yaml) and catalog-driven defaults are right; the registry ships incomplete and one generated surface is stale |
| Code Quality | 3.0/5 | Strong test tables (CP-13 fuzz set, IG corpus) but the grader regex shipped without adversarial inputs and one new test depends on a yq function the toolchain lacks |
| DevOps | 3.8/5 | Checksums and generated maps verify; budget gate pinned to the current size; no doc-coherence reports |
| Blockchain | n/a | |
| **Overall** | **3.7/5** | MODERATE risk; the verdict is driven by the HIGH count, not the score |

Machine-parseable findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`. Working file: `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the dissent's content scan applied one redaction to the bundled diff context; nothing in the diff itself)
- [x] Input validation on new trust boundaries — `rule_key` normalises without glob expansion or eval; `_lc_chunk_tok` admits only canonical decimals; `top_path_log` strips C0/DEL; the gate recorder validates payload shape with `jq -e`; `WRITE_CAPABLE_AGENTS` keys filtered by `^[A-Za-z0-9_-]+$`; v3 schema types the new catalog keys with `additionalProperties: false`
- [x] Authorization — every new `model-permissions.yaml` row mirrors the 4.7 remote-model scopes (all `none`, `security: redacted`), covered by `test_every_anthropic_catalog_entry_has_a_row` and `test_current_generation_rows_mirror_the_4_7_scopes`; the implement gate's mode is never selected by `.run/` or by a model-authored payload
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Error handling does not leak — the shim forwards only the fixed-string agy WARN, 600 chars; `/loa` strips control bytes from `.run/` evidence
- [x] Tests cover security paths — IG-5 forged payload, CP-13 dangerous-shape deny fuzz, CMP-277/278, MA-5/6
- [ ] Measurement instrument hardened against the documents it scores — **no** (HIGH-001)

---

## Next Steps

1. Fix the bare-citation lookbehind and the binding scope in `evals/graders/recall-vs-defects.sh` (HIGH-001, LOW-002); add the two RG cases; bump `grader_version` to 1.1.1; re-run the replay A/B behind Task 4.8.
2. Add `chart-researcher` to `agent-types.yaml` and `skill-invariants.md`; rewrite SC-T-AGENT-7's yq expression (MED-001, LOW-001).
3. Regenerate the `agent_teams_constraints` block and widen IDR-4; adjust the prompt budget in the same change (MED-002, LOW-004).
4. Fix the catalog comment and guard the shim's mktemp (LOW-003, LOW-005).
5. Re-run the adversarial dissent where `model-adapter.sh` is executable and credentials exist; then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:02:00Z"} -->
