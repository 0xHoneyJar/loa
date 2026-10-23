# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is the cycle-126 sprint-250 PR (88 files): `opus` → `claude-opus-5-5` and `cheap` → `claude-sonnet-5` across the catalog, the generated bash/TS twins, the three hand-maintained bash maps and the script defaults; a model-permissions row for every Anthropic catalog entry; the implement-gate rework (heuristic by default, `.loa.config.yaml` opt-in, evidence recorder); the check-permissions rule grammar; `agent-types.yaml`; the v3 schema additions; the license-fixture freshness guard; the CLAUDE.loa.md / rationale revert; and the eval grader 1.1.0 citation parser.

The bulk of it is sound and well tested. I verified by hand (not from the report) that: the catalog checksum matches the head catalog (`sha256 759dfd3f…`); every Anthropic and Bedrock-Anthropic catalog entry has a permissions row and the `opus-5-5` entry carries the same key set as `opus-5`; the `@loa-managed` header hash on CLAUDE.loa.md is VALID and both `@constraint-generated` block hashes recompute to the stamped values (`74e01d57cbb517af`, `bcb45bf913806ff2`); the golden NEVER/ALWAYS tables match the rendered rows; the manifest SHA256SUMS lines match; `call_flatline_chat` routes through model-invoke, so the alias defaults (`reviewer`, `opus`, `cheap`) resolve; the orchestrator falls back to `${MODEL_TO_PROVIDER_ID[$model]:-$model}`, so `cheap` dispatches as an alias. Against a head-only tree I ran the touched bats suites: check-permissions (13/13), implement-gate (11/11), instruction-diet-revert (4/4), compliance-hook (14/14), validate-artifact (36/36), flatline-model-validation new tests (5/5), flatline-model-allowlist (18/18), v3 schema c126 (4/5; the fifth needs the adapter package), prompt-budget (8/9; PB-8 needs fixtures outside the diff), hook-guard new test (pass; two others need the safety hook outside the diff), eval-recall-grader RG-1…RG-15 (pass; RG-16/17 need fixture trees outside the diff), model-adapter MA-1/MA-2 (pass; MA-3…6 need `lib/model-resolver.sh`, outside the diff), and the two new `test_trust_scopes.py` tests (pass). `test_anthropic_catalog_floor.py` could not be collected here (no `loa_cheval` package); its assertions were re-checked with a standalone script.

One defect blocks: the grader 1.1.0 "bare `:N`" citation form treats every JSON `"key":N` pair, including the mandatory LOA-VERDICT trailer, as a line citation bound to the last cited file. On a controlled input the head grader credits two planted defects the review never cited while the base grader credits none. Because the trailer is present in every graded review, the bias is systematic.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Eval grader — JSON values parsed as line citations

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:74` — the bare-citation alternative `(?<![A-Za-z0-9_./:]):(?P<bare>…)` excludes letters, digits, `_./:` before the colon but not a double quote, so every JSON `"key":N` pair in the review text is a line citation bound to the most recently cited path (`last`, `:85-88`). The LOA-VERDICT trailer that every graded review must carry (`"critical":0,"high":1,"medium":2,"low":3`, `"excluded":0`) therefore injects five bogus citations at lines 0–3 of the last cited file, and any JSON literal quoted in prose (`{"status":200}`) injects one at that number.
**File:** `head/evals/graders/recall-vs-defects.sh:74` (parser), `:85-88` (binding to `last`)
**Issue:** Reproduced with the head and base graders on identical input. Manifest: two defects in `.claude/scripts/a.sh` at anchor lines 3 and 200. Review body: one citation `head/.claude/scripts/a.sh:90` plus the phrase "returns `{"status":200}`" and the standard trailer.

| grader | detected | citations | recall |
|---|---|---|---|
| head (1.1.0) | Z1 (line 3), Z2 (line 200) | 7 | 1.0 |
| base (1.0.0) | none | 1 | 0.0 |

On a clean fixture without a trailer the same body yields `false_positives` 3 (head) vs 1 (base), so the false-positive metric is inflated as well. The RG-11…RG-15 tests pass because the fixture anchors (40, 120, 7) are not within ±3 of 0–3 and no JSON literal appears in the bodies.
**Why This Matters:** The grader is the instrument behind the recall figures this PR itself relies on (Task 4.8 reverts the Sprint 3 diet "per the pre-registered replay A/B rule"). A defect anchored in the first six lines of any file the reviewer cites (shebang, `set -euo pipefail`, header guards — a common planted-defect class) is credited for free, and `details.citations` is wrong on every review. A grader that over-credits silently is worse than one that under-credits.
**Required Fix:** Exclude quotes from the bare form's lookbehind and require the colon to stand on its own, e.g. `(?<![A-Za-z0-9_./:"'])` (or require a preceding whitespace/backtick/start-of-line), and skip the LOA-VERDICT comment before matching. Add RG cases: (a) a review whose only citation is `a.sh:90` with the standard trailer must detect nothing anchored at lines 0–6 and report `citations == 1`; (b) a body containing `{"status":200}` must not detect a defect anchored at 200; (c) a clean fixture without a trailer must report `false_positives == 1` for that body.
**Reference:** CWE-20 (improper input validation) for the parser; the grader header's own contract: "A `:N` glued to a word or a number … or with no cited path before it, credits nothing" (`head/evals/graders/recall-vs-defects.sh:17-21`).

**Example:**
```python
# Current (head:74) — a quote before the colon is not excluded
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'

# Should be — quotes excluded, and the trailer stripped before matching
TRAILER = re.compile(r'<!--\s*LOA-VERDICT\b.*?-->', re.S)
text = TRAILER.sub('', text)
r'|(?:(?<![A-Za-z0-9_./:"\'])(?:head|base)|(?<![A-Za-z0-9_./:"\'])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'
```

---

## Observations

### 1. Documentation and report

- **MEDIUM** (confidence: medium) `head/README.md:24` — the user-facing "Unreleased — full size" note and the migration addendum (`head/docs/migration/v2.0-model-generation-floor.md:224-263`) are present, but the diff carries no `CHANGELOG.md` hunk although the final commit message says "CHANGELOG protocol figure is 131,189 B". If the CHANGELOG entry lives outside this change, the merge leaves the release notes and the CHANGELOG out of step for the `opus`/`cheap` retarget, the gate rework and the grader bump.
**File:** `head/README.md:24`
**Suggestion:** Add the sprint-250 entries to CHANGELOG.md in this PR (one per task: residue/registry, implement-gate, check-permissions grammar, agent-types, schema, license freshness, diet revert, grader 1.1.0) or state in the PR where they land.
**Benefit:** Documentation verification can pass on the diff alone.

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR description: no `## AC Verification` walkthrough, no `file:line` evidence per acceptance criterion, and no fast-gate evidence (which test suites, shellcheck, or `gen-adapter-maps.sh --check` ran). I ran the suites myself (see Overall Assessment); the report should carry that evidence so the next reviewer does not have to.
**Suggestion:** Add an `## AC Verification` table (one row per sprint-250 task, `file:line` + symbol) and a `## Fast gate` line naming the commands and their exit codes, including `gen-adapter-maps.sh --check` for the regenerated twins and the bridgebuilder `dist/` rebuild.
**Benefit:** Satisfies the review gate's AC-verification requirement and makes the "generated, not hand-edited" claim for `generated-model-maps.sh` and `dist/*.js` checkable.

### 2. Latent robustness

- **LOW** (confidence: high) `head/.claude/scripts/check-permissions.sh:235` — `rule_key "$perm"` is a bare statement under `set -euo pipefail` (`:2`). `rule_key` returns 1 for anything not shaped `Bash(...)`; the two read loops guard it with `|| continue`, this one does not. Today all 16 requirements (`:49-78`) are `Bash(...)`, so nothing fires, but the first non-Bash requirement added to `REQUIRED_*` aborts the preflight with no report, and without `set -e` the stale `RULE_KEY` from the previous iteration would mis-classify it.
**Suggestion:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` and reset `RULE_KEY=""` at the top of `rule_key`. (Dissent DISS-C-001, confirmed.)
**Benefit:** The preflight degrades to a reported "missing" instead of a crash.

- **LOW** (confidence: high) `head/tools/check-prompt-budget.sh:53` — `LOA_LIMIT` is raised from 9,216 to 10,240 B and head `CLAUDE.loa.md` is 10,225 B: 15 bytes of headroom. The next `generate-constraints.sh` run that lengthens any rationale fails PB-9 and the CI budget gate.
**Suggestion:** Either trim a line elsewhere in CLAUDE.loa.md or set the limit with a few hundred bytes of headroom and record the rationale in the header comment (`:10`).
**Benefit:** Avoids a budget break on the next routine constraint edit.

- **LOW** (confidence: medium) `head/.claude/scripts/model-adapter.sh:656` — `err_file="$(mktemp …)"` runs under `set -euo pipefail` (`:33`); a failed `mktemp` (full or unwritable `TMPDIR`) now aborts the shim before model-invoke runs, where the previous `2>/dev/null` path had no such dependency. The stderr forwarding itself is correctly limited to the single agy WARN line (`:659`).
**Suggestion:** `err_file="$(mktemp …)" || err_file=/dev/null` and skip the grep when it is `/dev/null`.
**Benefit:** A temp-dir failure degrades to the old behaviour instead of a failed hop.

### 3. Residue and ownership

- **LOW** (confidence: medium) `head/.loa.config.yaml.example:2717` — the advisor-tier example still pins `anthropic: claude-opus-5`, and `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:256-267` asserts the live config keeps `advisor.anthropic == "claude-opus-5"` and `red_team.models.evaluator_primary == "claude-opus-5"` while `red-team-pipeline.sh` now defaults to `opus`. These are pinnable by design, but the sprint's residue acceptance (RES-6) stops short of the advisor and red-team pins, so the framework's own advisor voice stays one generation behind the `opus` alias it documents.
**Suggestion:** Either retarget the advisor/evaluator pins to the alias (`opus`) and relax the two asserts, or document in the migration addendum that the advisor tier is deliberately held at Opus 5.
**Benefit:** One rule for "what is current" across the catalog, the example and the live config.

- **LOW** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:46` — the evidence recorder hard-codes `active_skill_available: false` on every write, and `head/.claude/scripts/detect-platform-features.sh:65` writes the same key. They agree today (neither can ever write `true`, by D-4.4), so there is no contradiction; the IG-1 test even relies on the hook overriding a forged `true`. Two writers for one key is still a maintenance hazard.
**Suggestion:** Let the hook add only `active_skill_seen_at`/`active_skill_source` and leave `active_skill_available` to the detector (`$b + {…} | .active_skill_available //= false`). (Dissent DISS-C-002; the "clobbered probe-derived true" failure mode does not exist on this branch, so recorded as LOW.)
**Benefit:** One owner per key in `.run/platform-features.json`.

### Adversarial dissent triage

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — primary `gpt-5.5-pro` (answered by `codex-headless`), companion `claude-headless` succeeded (independent voice), status `clean`, 4 ADVISORY findings, `rejected_count` 0.

| id | claim | disposition |
|---|---|---|
| DISS-C-001 | unguarded `rule_key` under `set -e` | Confirmed, latent — recorded as LOW above (`check-permissions.sh:235`) |
| DISS-C-002 | recorder clobbers a probe-derived `active_skill_available: true` | Not reproducible — no writer can produce `true` on this branch; recorded as a LOW ownership note (`implement-gate.sh:46`) |
| DISS-C-003 | `reviewer`/`opus` defaults hit vendor APIs directly | Rejected — both scripts source `lib-curl-fallback.sh` and `call_flatline_chat` passes `--model` to model-invoke, which resolves aliases (`flatline-proposal-review.sh:56-61,182,233`) |
| DISS-C-004 | `cheap`/`claude-opus-5.5` pass validation then have no provider id | Rejected — the dispatch path falls back to `${MODEL_TO_PROVIDER_ID[$model]:-$model}` (`flatline-orchestrator.sh:992`), so the alias reaches cheval, which resolves it |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `rejected_count` is 0 and no `adversarial-rejected-review*.jsonl` sidecar exists.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The grader 1.1.0 parser defect above (Task 4.8 of sprint-250); CHANGELOG entry not in the diff |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request (sprint-250 tasks as stated in `pr/PR.md`)

| Criterion | Status | Notes |
|-----------|--------|-------|
| `opus` → `claude-opus-5-5` in catalog, generated twins and bash maps | Pass | `model-config.yaml:1105`, `generated-model-maps.sh:133`, `model-adapter.sh:111`, `flatline-orchestrator.sh:697`, `red-team-model-adapter.sh:66`; RES-1/RES-2 pass |
| `cheap` → `claude-sonnet-5` | Pass | `model-config.yaml:1102`; cycle099 integration expectations updated |
| Catalog entry vendor-sourced 1M/128K, $4/$20, 0.05× cache, conservative 180K ceiling with `loa:shortcut` | Pass | `model-config.yaml:470-509`; marker carries ceiling and upgrade trigger |
| Every Anthropic catalog entry has a permissions row | Pass | Verified by script and by `test_trust_scopes.py` (2 passed) |
| Script defaults are catalog aliases; previous generation not described as current | Pass (with LOW residue) | RES-3/RES-4/RES-5/RES-7 pass; advisor/red-team pins in the example and live config stay at Opus 5 (Observation 3) |
| Implement gate: heuristic default, opt-in authoritative, evidence recorder, `/loa` line | Pass | implement-gate.bats 11/11, compliance-hook.bats 14/14 |
| check-permissions rule grammar (`:*` and ` *`, trim, exact rules, deny wins) | Pass | check-permissions.bats 13/13 incl. CP-11…CP-13 fuzz table |
| `agent-types.yaml` drives the write-capable allowlist | Pass | `validate-skill-capabilities.sh:110-118`; SC-T-AGENT-7…9 not runnable here (needs `.claude/agents/`), logic reviewed |
| v3 schema types `probed_ceiling`, `account_limits`, `headless_timeout_seconds`, `params.beta_headers` | Pass | 4/4 shape tests pass; adapter cross-check test needs the package |
| License-fixture freshness covers the 12-hour grace window | Pass (reviewed) | `ensure_license_fixtures.sh:47-61`; LFF tests need the generator, outside the diff |
| Sprint 3 trim and twelve rationales reverted; budget raised | Pass (with LOW) | IDR-1…4 pass; hashes re-stamped correctly; 15 B headroom |
| Grader 1.1.0 citation parser (bd-ewrc) | **Fail** | JSON values parsed as bare citations — Changes Required #1 |
| `--help` states the FR-1.3 non-Anthropic default | Pass | `cheval.py:2932-2937`; c124-1.4-3b asserts it |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (fixtures carry synthetic ids only)
- [x] Input validation and sanitization present (lib-content control-byte stripping `:295`; canonical-decimal index guard `:166`; model-adapter forwards one filtered WARN line only)
- [x] Authentication/authorization correct (recorder treats model-authored `tool_input.active_skill` as evidence only; nothing in `.run/` selects the authoritative mode — IG-5 passes)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data (cheval stderr discarded except the agy WARN)

---

## Code Quality Summary

**Strengths:**
- Red-first tests for every behavioural change (RES-7, IDR, CP-11…13, IG-1…11, CMP-277/278, bd-8ndx) and the fuzz table for the deny grammar.
- Generated twins (`generated-model-maps.sh`, bridgebuilder `dist/`, `config.generated.ts`) regenerated consistently; checksums and header hashes re-stamped correctly.
- The implement-gate rework states plainly what the payload cannot carry and keeps the opt-in undocumented on purpose.

**Areas for Improvement:**
- The grader's bare-citation form needs a stricter boundary (above).
- The implementation report should carry the fast-gate and AC evidence rather than the commit list.

**Complexity:** no new function over 50 lines; `rule_key` and the recorder block are compact; nesting ≤ 3. Lean already. Ship.

---

## Next Steps

1. Fix the grader lookbehind (and strip the trailer before matching), add the three RG cases, bump `grader_version` if the contract text changes.
2. Add the CHANGELOG entries or point to where they land; add `## AC Verification` and fast-gate evidence to the report.
3. Optionally fold the LOW items (guarded `rule_key`, budget headroom, `mktemp` fallback, single owner for `active_skill_available`).
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T04:10:00Z"} -->
