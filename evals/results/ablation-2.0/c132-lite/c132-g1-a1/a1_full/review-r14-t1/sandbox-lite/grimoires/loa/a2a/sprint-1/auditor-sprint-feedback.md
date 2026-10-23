# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`; task review-r14)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 0/1/4/5, excluded 0)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change retargets the `opus` alias to `claude-opus-5-5` and `cheap` to `claude-sonnet-5`, adds a model-permissions row for every served Anthropic entry, drops the `.run/`-driven authoritative mode of the implement gate in favour of an operator opt-in, adds the `Bash(<cmd> *)` rule grammar to the run preflight, ships recall-grader parser 1.1.0, and reverts the Sprint 3 instruction-diet trims. The security posture of the diff is sound where it touches trust boundaries: the evidence recorder writes fixed strings atomically, `rule_key` keys an associative array with no arithmetic, the `/loa` evidence line and the content-lib log strip control characters, and the model-adapter forwards one fixed-prefix stderr line cut at 600 bytes. Every generated twin verifies: `model-config.yaml.checksum` equals the head catalog's SHA-256, the two changed fixture manifests match `SHA256SUMS`, and the Bridgebuilder `.build-manifest.json` hashes match the regenerated TypeScript.

One HIGH blocks the merge, confirmed by an independent reproduction: the grader's new bare `:N` rule credits the LOA-VERDICT trailer that every graded review carries, so recall is inflated for any defect anchored near the top of the last-cited file. Four MEDIUM findings follow: an opt-in gate branch that trusts a model-authored field (confirmed by the cross-model dissent), an unguarded `rule_key` call that aborts the preflight on the first non-Bash requirement, a yq expression written in jq syntax that leaves the only agent-types pin red, and two contradictory pricing models derived from one vendor statement. Five LOWs are recorded. Phase 0 prerequisite note: the review verdict is CHANGES_REQUIRED rather than "All good"; this audit ran on the operator's instruction to proceed autonomously and the deviation is recorded here. Scope limits: `grimoires/loa/known-failures.md` is absent (ICM surface degraded); the Python adapter tests and the tsx/cheval-dependent bats were not run here.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 4 |
| Low | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Recall grader 1.1.0 credits the LOA-VERDICT trailer and quoted JSON keys as citations

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:74`
**Issue:** The bare alternative of `CITE`:
```python
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'
```
admits `"` as the preceding character, so `:0`, `:1`, `:0`, `:3`, `:0` inside the mandatory trailer `"counts":{"critical":0,"high":1,"medium":0,"low":3},"excluded":0` are parsed as bare line citations and bound (line 85) to the most recently cited path. Quoted JSON keys in prose (`"status":1`, `"note":2`) are credited the same way. This contradicts the parser contract the PR writes at lines 19-21 ("A `:N` glued to a word … credits nothing") and RG-14 at `head/evals/tests/eval-recall-grader.bats:146` only exercises the unquoted `note:40`.
**Reproduction (head grader, manifest with defects anchored at lines 3 and 400 of `a.sh`):**
```
review citing only `head/.claude/scripts/a.sh:400` + standard trailer
  → detected ["EARLY","FAR"], citations 6, recall 1.0, pass
same review without the trailer
  → detected ["FAR"], citations 1, recall 0.5, fail
base grader (1.0.0) with the trailer
  → detected ["FAR"], citations 1, recall 0.5, fail
```
**Impact:** The grader is the instrument behind the pre-registered replay A/B rule this PR acts on (Task 4.8 reverts). Every graded review that ends with a trailer gains five phantom citations and a false detection for any defect anchored within ±3 of lines 0-3 in the last-cited file. Measurement integrity, not exploitability, but it silently biases the decision the sprint was built to make.
**Fix:**
```python
text = re.sub(r'<!--.*?-->', '', text, flags=re.S)   # drop the trailer before scanning
r'|(?:(?<![A-Za-z0-9_./:"\'}\]])(?:head|base)|(?<![A-Za-z0-9_./:"\'}\]])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'
```
Add an RG case with the trailer plus a defect anchored at line ≤ 6, and one with a quoted JSON key in prose.
**Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

---

## Medium/Low Priority Issues

### [MED-001] Opt-in authoritative branch trusts a model-authored `tool_input.active_skill`
- **Severity:** MEDIUM (confidence: high) — confirmed by cross-model review (DISS-C-001)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:123-129`
- **Issue:** With `implement_gate.mode: authoritative` in `.loa.config.yaml`, the hook allows an App-Zone write whenever `tool_input.active_skill` names implement/bug/run/simstim. The file's own header (lines 12-14) states "The PreToolUse payload carries no harness-set skill field … and tool_input is model-authored", so the branch has no legitimate input: it is a one-line config switch to a fence that the fenced party satisfies by emitting `"active_skill":"implement"` (the corpus row `write-src-active-implement.json → authoritative: allow` in `head/tests/fixtures/pretooluse-payloads/expected.tsv:8` pins exactly that). `head/tests/unit/implement-gate.bats:151-153` (IG-11) then pins the key as undocumented instead of removing the branch. The PR does narrow the surface relative to base, where `.run/` tampering could select the mode (IG-5 and CH-T10 now prove that is closed), and the hook is advisory (ask, not block), which keeps this at MEDIUM.
- **Fix:** Delete the authoritative branch and the `implement_gate.mode` read (about 40 lines), or document the key in `.loa.config.yaml.example` with the forgeability caveat and drop IG-11. If kept, emit a stderr WARN on every authoritative decision naming the field as self-asserted.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-002] `rule_key "$perm"` runs unguarded under `set -euo pipefail`
- **Severity:** MEDIUM (confidence: high; latent today)
- **File:** `head/.claude/scripts/check-permissions.sh:235`
- **Issue:** `rule_key` returns 1 for any requirement that is not `Bash(...)` (line 164). The ingestion loops at lines 198 and 202 guard with `|| continue`; the requirements loop does not. Sourcing the head `rule_key` and running a `set -e` loop over `Bash(git push:*)`, `Read(/etc/*)`, `Bash(bash:*)` processes the first item and dies on the second. All 16 current requirements (lines 49-78) are `Bash(...)`, so no input fails today; the first `Read(...)` or `WebFetch(domain:...)` requirement added aborts every preflight with no report and no JSON. The replaced `base_pattern_of` never failed.
- **Fix:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` plus a bats case with a non-Bash requirement.
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [MED-003] SC-T-AGENT-7 is written in jq syntax against yq
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/tests/unit/skill-capabilities.bats:850`
- **Issue:** `tostring` is jq; mikefarah yq v4.40.5 (the yq the repository documents and the one installed here) fails with `Error: 1:68: invalid input text "tostring)) | joi..."`, so the test fails at its first assertion. It is the only test pinning the content of `agent-types.yaml`, the file that now defines which agent types may hold Write/Edit (a security-relevant invariant per `.claude/rules/skill-invariants.md`).
- **Fix:** `yq -o=json '.agent_types' "$data" | jq -r 'to_entries | map(.key + "=" + (.value.write_capable|tostring)) | join(" ")'`.
- **Reference:** n/a (test correctness; no CWE applies)

### [MED-004] One vendor statement, two pricing models
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/defaults/model-config.yaml:478` (and `:562`)
- **Issue:** The Opus 5.5 entry omits a `long_context` tier on the vendor sentence "Claude 4.6 and later models … include the full 1M token context window at standard pricing", while Opus 5 (`:558-566`), Sonnet 5, Fable 5 and Fable 5.1 keep `long_context: {threshold_tokens: 200000, input_multiplier: 2.0, output_multiplier: 1.5}`, pinned by `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:326-336`, with 5.5 carved out of `FIVE_FAMILY` at `:277` and a new test asserting it has no tier. The same sentence cannot justify both; above 200K input the metered cost of `opus` and a pinned `claude-opus-5` diverge 2×, across the 5.5 → 5 → Sonnet 5 fallback chain.
- **Fix:** Drop the tiers from the four entries (and update the test), or document in the 5.5 comment why 5.5 alone is exempt.
- **Reference:** n/a (cost-control consistency)

### [LOW-001] Configured authoritative mode degrades silently without yq
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:114` (and `head/.claude/scripts/detect-platform-features.sh:31`)
- **Issue:** `if command -v yq … ; then` has no else branch: a configured `implement_gate.mode: authoritative` runs heuristic with no stderr line and no audit event. The removed code wrote `compliance.mode.change` to `audit.jsonl` on downgrade.
- **Fix:** WARN on stderr when `.loa.config.yaml` exists but yq does not.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-002] Base key for an exact-form requirement can never match
- **Severity:** LOW (confidence: high; latent)
- **File:** `head/.claude/scripts/check-permissions.sh:237`
- **Issue:** `base="*${key#\*}"; base="${base%% *}"` assumes a wildcard key. For `Bash(git status)` the derivation yields `key==git status base=*=git`. All 16 requirements are wildcards today.
- **Fix:** `b="${key#[*=]}"; base="*${b%% *}"`.

### [LOW-003] `agent_teams_constraints` block is STALE after the C-TEAM rationale revert
- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/loa/CLAUDE.loa.md:124-131`
- **Issue:** The PR rewrites the five C-TEAM `why` strings in `head/.claude/data/constraints.json` (Task 4.8, "twelve rationales reverted") but the generated block keeps the placeholder hash `c020-teamcreate` and the condensed rationales. `generate-constraints.sh --validate-only` in the head overlay: `FAIL: STALE: Section 'agent_teams_constraints' in .claude/loa/CLAUDE.loa.md (stored: c020, expected: 19641576807c2086)`. IDR-4 at `head/tests/unit/instruction-diet-revert.bats:61` checks only the seven C-PROC rows, so the C-TEAM half of the revert never reaches the prompt surface the replay measured.
- **Fix:** Regenerate the block (or exclude it deliberately with a comment) and extend IDR-4 to the twelve ids in the fixture.

### [LOW-004] 15 bytes of prompt-budget headroom
- **Severity:** LOW (confidence: high)
- **File:** `head/tools/check-prompt-budget.sh:53`
- **Issue:** `LOA_LIMIT` rises 9,216 → 10,240 B; head `CLAUDE.loa.md` is 10,225 B. The next rationale edit lands on PB-9.
- **Fix:** State the headroom in the test name or trim a row.

### [LOW-005] Stale advisor example pin survives the residue grep
- **Severity:** LOW (confidence: medium)
- **File:** `head/.loa.config.yaml.example:2717`
- **Issue:** The commented `tier_aliases.advisor` example still reads `anthropic: claude-opus-5` after `opus` moves to 5.5; `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:258` substring-checks `"anthropic: claude-opus-5"`, which `claude-opus-5-5` also satisfies, so neither the test nor RES-6 sees it.
- **Fix:** Update the example (or mark it a deliberate pin) and tighten the assertion.

---

## Cross-Model Security Observations

Dissent ran as `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` (envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, `metadata.type: audit`, `metadata.model: gpt-5.5-pro`). Primary gpt-5.5-pro answered via codex-headless with `status: clean`; companion claude-headless (anthropic family, `counted_as: independent_voice`) returned five findings; `voices_succeeded 2/2`, `chain_health ok`, `degraded: false`, no truncation waiver, `hallucination_filter.downgraded 0`. Not DEGRADED_SECURITY_REVIEW. Disposition:

- **DISS-C-001** (MEDIUM, `implement-gate.sh:111-115`, authoritative mode satisfiable by a model-emitted `active_skill`) — confirmed; tallied as MED-001 above ("Confirmed by cross-model review").
- **DISS-C-002** (LOW, `implement-gate.sh:40-50`, recorder clobbers non-object `platform-features.json` and forces `active_skill_available: false`) — not a defect: `head/.claude/scripts/detect-platform-features.sh:60` itself keeps only `active_skill_seen_at` and `active_skill_source` on every refresh and writes `active_skill_available: false` (IG-1, IG-9 pin both), so nothing the system retains is lost; the recorder is gated on the field being present, writes fixed strings plus a timestamp via mktemp + mv, and runs once. Not tallied.
- **DISS-C-003** (LOW, `check-permissions.sh:162-173`, trailing ` *` may not be a prefix wildcard at runtime) — dismissed against the vendor documentation (https://code.claude.com/docs/en/permissions, "Wildcard patterns"): "The `:*` suffix is an equivalent way to write a trailing wildcard, so `Bash(ls:*)` matches the same commands as `Bash(ls *)`", and "The permission dialog writes the space-separated form". The PR's grammar is the documented one. Not tallied.
- **DISS-C-004** (LOW, `cheval.py:2932-2937`, non-Anthropic default output budget 4096 → min(16000, catalog)) — out of scope for this diff: the hunks at `head/.claude/adapters/cheval.py:2929-2939` and `head/.claude/adapters/loa_cheval/providers/base.py:158-166` change help text and a comment only; the behaviour was shipped by an earlier sprint (FR-1.3). The cost-ceiling test gap is a fair observation for that sprint, not a defect this PR introduces. Not tallied.
- **DISS-C-005** (LOW, `model-config.yaml:485-488`, Opus 5.5 falls back to `anthropic:claude-headless` whose new registry row claims no capabilities while `extra.allowed_tools` could widen them) — pre-existing pattern: every Anthropic entry in base already terminates its chain in `anthropic:claude-headless` (10 occurrences in base, 10 in head), and the head catalog's `claude-headless` entry (`:892-923`) sets no `allowed_tools`. The new row at `head/.claude/data/model-permissions.yaml:446` (`anthropic:claude-headless`) states the caveat in its own notes and has no runtime effect unless `hounfour.feature_flags.context_filtering` is on. Not tallied; a test pinning `extra.allowed_tools` absent on the headless entry would make the row's claim mechanical.

## Rejected dissent payloads

`metadata.rejected_summary` is empty, `metadata.rejected_count` is 0, `rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope. Nothing to triage.

---

## Pre-existing or out of scope (not tallied)

- `head/.claude/scripts/check-permissions.sh:167` treats a body ending in `*` with no preceding space or colon (`Bash(git*)`) as an exact rule; the vendor docs say `Bash(ls*)` is a wildcard matching `lsof` too. A deny written that way would be missed by the preflight, which then fails at runtime (fail-safe direction). The header at lines 18-26 scopes this out explicitly ("Nothing else is rewritten") and base did not recognise it either.
- `head/.claude/hooks/compliance/implement-gate.sh:134` echoes the model-authored `$active_skill` to stderr; identical to `base:171`.
- `head/.claude/hooks/hook-guard.sh:46-49` fails OPEN on a hook that does not parse; the change is message-only, the design pre-dates this PR.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` reports exist in this workspace; manually verified instead. `README.md:24` and `docs/migration/v2.0-model-generation-floor.md:224-264` describe the alias moves, the implement-gate evidence line and the permission grammar accurately; `.loa.config.yaml.example` follows the alias changes (except LOW-005). Security-critical code is commented (the gate's header states the trust model; `rule_key` documents the grammar). No secrets, keys or internal URLs appear in the diff (dissent secret scan: one redaction in the prepared input, none in the diff itself). Two blockers to note rather than count: the `implement_gate.mode` switch is deliberately undocumented by test (IG-11) while remaining live — covered by MED-001; and the commit `docs(cycle-126): sprint-250 E2E — CHANGELOG protocol figure …` names a CHANGELOG edit that is not among the 88 files in `pr/head.diff`, so the changelog entry for the alias retarget and the gate change could not be verified here.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on all new trust boundaries (`rule_key` rejects non-`Bash(...)`; `--line` output control-stripped and cut; `top_path_log` strips C0/DEL; agent-type names regex-filtered)
- [x] Authentication/authorization — with MED-001: the opt-in branch trusts a model-authored field
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Error handling doesn't leak info (model-adapter forwards one fixed-prefix line, 600 B)
- [ ] Tests cover security paths — MED-003 leaves the agent-types pin red; MED-002/LOW-002 have no negative case

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 4 | Boundaries sanitised; grader regex gap (HIGH-001) |
| SEC-AZ Authorization | 3 | Opt-in branch on an untrusted field (MED-001) |
| SEC-CI Confidentiality/Integrity | 4 | Generated twins verified; stderr forwarding bounded |
| SEC-IN Injection prevention | 5 | No shell/jq interpolation of untrusted data added |
| SEC-AV Availability | 4 | Latent preflight abort (MED-002) |
| Architecture | 4 | Surface reduced (.run/ no longer selects the mode); one deletable branch |
| Code Quality | 3 | Two red/incorrect tests (HIGH-001 contract, MED-003) |
| DevOps | 3 | Stale generated block, 15 B headroom, pricing-model split |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001: strip HTML comments before scanning and reject quote/bracket context in the bare `:N` rule; add the trailer and quoted-key RG cases.
2. Fix MED-001 (remove or document the authoritative branch), MED-002 (guard `rule_key`), MED-003 (yq expression), MED-004 (one pricing model for the 1M family).
3. Address the LOWs; regenerate the `agent_teams_constraints` block.
4. Run `/implement sprint-1`, then `/review-sprint sprint-1` and re-run `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:58:00Z"} -->
