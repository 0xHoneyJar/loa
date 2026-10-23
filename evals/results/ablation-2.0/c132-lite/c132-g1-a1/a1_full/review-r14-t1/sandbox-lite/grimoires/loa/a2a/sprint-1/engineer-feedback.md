# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff` (88 files): the `opus` alias moves to `claude-opus-5-5`, `cheap` to `claude-sonnet-5`, the model-permissions registry gains a row for every served Anthropic entry, the implement gate drops its `.run/`-driven authoritative mode, check-permissions gains the `Bash(x *)` grammar, the recall grader gets parser 1.1.0, and the Sprint 3 instruction-diet trims are reverted.

Verified directly against the head files: `model-config.yaml.checksum` matches the catalog; `gen-adapter-maps.sh --check` reports the generated bash maps match the head catalog; the Bridgebuilder `.build-manifest.json` per-file hashes match `config.generated.ts` and `truncation.generated.ts`; the two manifest lines in `evals/fixtures/review-prs/SHA256SUMS` match `pr-02.json`/`pr-05.json`; the `@loa-managed` hash of CLAUDE.loa.md verifies and both regenerated constraint blocks are fresh; every Anthropic and Bedrock-Anthropic catalog entry has a model-permissions row. In a head overlay these PR suites pass: implement-gate (11), check-permissions (13), model-residue (7), model-adapter (6), instruction-diet-revert (4), hook-guard (8), validate-artifact (36), gen-adapter-maps (14), compliance-hook (14), flatline-model-validation (20), flatline-model-allowlist (18), CMP-277/278, the four c126 schema cases, and RG-1 to RG-15 (RG-16/17 and PB-8 need fixture trees not in the PR). Not runnable here: the Python adapter tests (the overlay's loa_cheval package is a different revision) and the tsx/cheval-dependent bats.

One HIGH blocks the merge: the grader's new bare-`:N` rule credits the verdict trailer that every graded review carries, which the grader run below demonstrates. The remaining findings are medium/low and sit under Observations.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Eval grader — parser 1.1.0 credits the LOA-VERDICT trailer and quoted JSON keys as citations

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:74` — the bare `:N` alternative of `CITE` matches `:0`, `:1`, `:0`, `:3`, `:0` inside the mandatory trailer `"counts":{"critical":0,"high":1,"medium":0,"low":3},"excluded":0` and binds them to the most recently cited path, so any defect anchored within ±3 of lines 0–3 in the last-cited file is "detected" by every review that ends with a trailer; quoted JSON keys in prose (`"status":1`, `"note":2`) are credited the same way.
**File:** `head/evals/graders/recall-vs-defects.sh:71-90`
**Issue:** The lookbehind `(?<![A-Za-z0-9_./:])` admits `"` as the preceding character. Run against the head grader with a manifest holding defects at anchor 3 and anchor 400, a review that cites only `` `head/.claude/scripts/a.sh:400` `` and ends with the standard trailer returns `detected: ["EARLY","FAR"], citations: 6, recall: 1`; the same review without the trailer returns `detected: ["FAR"], citations: 1`. A review containing `` `{"status":1,"total_found":16}` and `"note":2` `` also detects the anchor-3 defect. This contradicts the contract the PR writes at lines 19-21 ("A `:N` glued to a word … credits nothing") and RG-14 at `head/evals/tests/eval-recall-grader.bats:146`, which only exercises the unquoted `note:40`.
**Why This Matters:** The grader is the instrument behind the pre-registered replay A/B rule this very PR acts on (Task 4.8 reverts); a systematic false credit for near-top anchors silently inflates recall, and `details.citations` is inflated by five for every graded review.
**Required Fix:** Exclude JSON-key context from the bare rule — reject when the preceding non-space character is `"`, `'`, `}` or `]`, and strip HTML comments (the trailer) before scanning; add an RG case with the trailer plus a defect anchored at line ≤ 6, and one with a quoted key.

**Example:**
```python
# Current: `"critical":0` → bare 0 bound to the last path
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'
# Should be: no quote/bracket before the colon, trailer removed first
text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
r'|(?:(?<![A-Za-z0-9_./:"\'}\]])(?:head|base)|(?<![A-Za-z0-9_./:"\'}\]])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'
```

---

## Observations

### 1. Testing

- **MEDIUM** (confidence: medium) `head/tests/unit/skill-capabilities.bats:850` — `tostring` is jq syntax; mikefarah yq v4.40.5 rejects the expression (`Error: 1:70: invalid input text "tostring"`), so SC-T-AGENT-7 fails at its first assertion and the only test pinning `agent-types.yaml` content is red (`to_string` also fails on this version). The repo documents mikefarah/yq. Compare via `yq -o=json … | jq -r` or per key with `yq -e`.
**File:** `head/tests/unit/skill-capabilities.bats:850`
**Suggestion:** `yq -o=json '.agent_types' "$data" | jq -r 'to_entries | map(.key + "=" + (.value.write_capable|tostring)) | join(" ")'`.
**Benefit:** The agent-types data file is actually pinned in CI.

### 2. Catalog pricing consistency

- **MEDIUM** (confidence: medium) `head/.claude/defaults/model-config.yaml:478` — the Opus 5.5 entry omits a `long_context` tier on the vendor statement "Claude 4.6 and later models … include the full 1M token context window at standard pricing", while Opus 5 (`:562`), Sonnet 5, Fable 5 and Fable 5.1 keep `long_context: {threshold_tokens: 200000, input_multiplier: 2.0, output_multiplier: 1.5}`, pinned by `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:326` and now excluded from `FIVE_FAMILY` at `:277`. The same vendor sentence cannot justify both; metering above 200K input diverges 2× between `opus` and a pinned `claude-opus-5`.
**Suggestion:** Drop the tiers from the four entries with the same 2026-10-05 citation (and update the test), or document in the 5.5 comment why 5.5 alone is exempt.
**Benefit:** One pricing model per vendor statement; cost ceilings stay consistent across the fallback chain 5.5 → 5 → Sonnet 5.

### 3. check-permissions.sh grammar

- **MEDIUM** (confidence: high) `head/.claude/scripts/check-permissions.sh:235` — `rule_key "$perm"` is a bare statement under `set -euo pipefail` and returns 1 for any requirement that is not `Bash(...)`; the allow/deny ingestion loops at `:198`/`:202` guard with `|| continue`, this loop does not. All 16 current requirements are `Bash(...)`, so there is no failing input today; the first `Read(...)`/`WebFetch(domain:...)` requirement added aborts every preflight with no report and no JSON.
**Suggestion:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` plus a bats case with a non-Bash requirement.
- **LOW** (confidence: high) `head/.claude/scripts/check-permissions.sh:237` — `base="*${key#\*}"` assumes a wildcard key; an exact requirement (`=git status`) would yield `*=git`, never matchable. Latent for the same reason.
**Suggestion:** `b="${key#[*=]}"; base="*${b%% *}"`.

### 4. Implement gate

- **MEDIUM** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:122-135` — the authoritative branch still allows an App-Zone write whenever a model-authored `tool_input.active_skill` names implement/bug/run/simstim. The PR's own header at `:12-14` states the payload carries no harness-set skill field and `tool_input` is model-authored, so the branch has no legitimate input and is an opt-in fence bypass; `head/tests/unit/implement-gate.bats:151-153` then pins the knob as undocumented rather than removing it. `SIMPLICITY[delete]`: remove the branch and the `implement_gate.mode` read (about 40 lines), or document the risk next to the key in `.loa.config.yaml.example` and drop IG-11.
- **LOW** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:114` and `head/.claude/scripts/detect-platform-features.sh:31` — a configured `implement_gate.mode: authoritative` silently runs heuristic when yq is missing; the removed code wrote a `compliance.mode.change` audit event on downgrade, the replacement emits nothing (the `.run/.compliance-mode` consumers the dissent worried about do not exist outside the two bats files).
**Suggestion:** WARN on stderr when the config file exists but yq does not.

### 5. Generated constraint blocks and prompt budget

- **LOW** (confidence: high) `head/.claude/loa/CLAUDE.loa.md:124-131` — the `agent_teams_constraints` block keeps the placeholder hash `c020-teamcreate` and five condensed rationales while the PR rewrites the five C-TEAM `why` strings in `head/.claude/data/constraints.json` (Task 4.8 "twelve rationales reverted"); `generate-constraints.sh --validate-only` reports the section STALE at head (it was already stale at base, so the drift is pre-existing but now wider), and IDR-4 at `head/tests/unit/instruction-diet-revert.bats:61` checks only the seven C-PROC rows. The C-TEAM revert therefore never reaches the prompt surface the replay measured.
**Suggestion:** Regenerate the block (or exclude it deliberately with a comment) and extend IDR-4 to the twelve ids in the fixture.
- **LOW** (confidence: high) `head/tools/check-prompt-budget.sh:53` — `LOA_LIMIT` rises 9,216 → 10,240 B and head `CLAUDE.loa.md` is 10,225 B: 15 bytes of headroom before PB-9 fails on the next rationale edit.
**Suggestion:** Say so in the test name or trim a row; otherwise the next constraint edit lands on PB-9.

### 6. Residue

- **LOW** (confidence: medium) `head/.loa.config.yaml.example:2717` — the commented `tier_aliases.advisor` example still pins `anthropic: claude-opus-5` after `opus` moves to 5.5; `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:258` only substring-checks `"anthropic: claude-opus-5"`, which `claude-opus-5-5` also satisfies, so the residue grep (RES-6) does not see it.

### 7. Complexity

`loa:shortcut:` at `head/.claude/defaults/model-config.yaml:496` carries its upgrade trigger (rerun the probe). No function over 50 lines added; `rule_key` and `_elf_future` are small. Over-engineering pass: the authoritative branch above is the only deletable block. net: -40 lines possible.

---

## Cross-Model Observations

Adversarial dissent ran with `--diff-file pr/head.diff` (envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`, primary gpt-5.5-pro via codex-headless "clean", companion claude-headless 6 findings, 2/2 voices, no truncation waiver). Disposition:

- DISS-C-001 (BLOCKING, `rule_key "$perm"` under set -e) — confirmed as latent: every current requirement is `Bash(...)`, so no failing input exists today; recorded as MEDIUM under Observations §3.
- DISS-C-002 (exact-key base) — confirmed latent; LOW under §3.
- DISS-C-003 (yq-missing silent downgrade; stale `.compliance-mode` readers) — downgrade confirmed, LOW under §4; no `.compliance-mode` readers exist outside tests.
- DISS-C-004 (long_context inconsistency) — confirmed against the head catalog; MEDIUM under §2.
- DISS-C-005 (calibrated-5.5 tests in a "later revision" of the test module) — dismissed: head's `test_anthropic_catalog_floor.py` contains no such tests; the dissenter was shown a different revision of the file.
- DISS-C-006 (recorder stamps model-authored evidence) — by design per the PR (evidence only, `active_skill_available: false` always); folded into the §4 MEDIUM, since the only consumer of that evidence is an operator deciding to turn the forgeable branch on.

## Rejected dissent payloads

The envelope's `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar exists; nothing to triage.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| review the pull request | Pass | Every hunk read; generated artifacts, checksums and 15 bats suites verified in a head overlay |
| report each defect it introduces with file and line | Pass | `review.md` at the repository root, one `head/<path>:<line>` per line |
| give a merge verdict | Pass | CHANGES_REQUIRED (one HIGH) |

The implementation report (`pr/PR.md`) carries no `## AC Verification` section; per the task brief the PR files are the entire input, so this is noted, not counted.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (secret scan: 1 redaction in the dissent input, none in the diff)
- [x] Input validation and sanitization present (`rule_key` rejects non-`Bash(...)`; `--line` evidence is control-stripped and cut to 120 chars; `top_path_log` strips C0/DEL)
- [x] Authentication/authorization correct — with the §4 caveat: the opt-in authoritative branch trusts a model-authored field
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no dependency changes)
- [x] Error messages don't leak sensitive data (model-adapter forwards only the agy WARN line, cut at 600 chars)

---

## Code Quality Summary

**Strengths:**
- Generated twins are regenerated and verifiable: catalog checksum, adapter maps, Bridgebuilder manifest hashes and the constraint-block hashes all check out.
- The evidence recorder writes atomically (mktemp + mv) and never promotes the flag; the fixture corpus in `tests/fixtures/pretooluse-payloads/` pins both modes.
- `validate-artifact.sh` here-string fix removes a real SIGPIPE race under pipefail, with a test that fails on the old pattern.

**Areas for Improvement:**
- The grader parser needs negative tests built from real review files (trailer, quoted JSON output), not only prose fragments.
- A test written in jq syntax against yq means the CI yq version is an unstated assumption; pin or avoid.

---

## Next Steps

1. Fix the grader's bare-`:N` rule and add the trailer/quoted-key RG cases.
2. Fix SC-T-AGENT-7's yq expression; decide the long_context tier question for the four 5-family entries.
3. Guard `rule_key "$perm"`; remove or document the authoritative branch.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:40:00Z"} -->
