# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** `pr/head.diff` — cycle-126 sprint-250 tasks 4.1–4.8 (88 files, +1956/−366)

---

## Overall Assessment

The bulk of this change is sound and mechanically verified: the `claude-opus-5-5` catalog entry matches the vendor pricing page read today ($4 / $20 per MTok, $0.20 cache hit, 1M window at standard pricing), `model-config.yaml.checksum` and the eval `SHA256SUMS` match their files, `generated-model-maps.sh` regenerates byte-identically from the head catalog, the `@loa-managed` hash on `CLAUDE.loa.md` verifies, and every Anthropic/Bedrock catalog entry (16) now has a `model-permissions.yaml` row. The suites that can run against the frozen head tree pass: check-permissions 13/13, implement-gate 11/11, instruction-diet-revert 4/4, flatline-model-validation 20/20, flatline-model-allowlist 18/18, model-config-v3-schema 33/33, model-residue 6/7 (the one failure greps two skill directories that are not part of the PR snapshot). Other suites failed only for environmental reasons in the snapshot (shared libs such as `compat-lib.sh` absent, executable bits lost in the copy); I re-ran their subjects by hand where possible.

Two findings block the merge:

1. The implement gate's "authoritative" branch is still reachable and still trusts a model-authored field. The PR's own header says the PreToolUse payload carries no harness skill signal, yet the branch allows an App-Zone write on `tool_input.active_skill: implement`. The selector moved from `.run/` (now correctly ignored, IG-5) to `.loa.config.yaml`, which no PreToolUse hook fences, so the fenced agent can flip the mode and self-authorise in two Writes. The opt-in key is deliberately undocumented (IG-11), which hides rather than closes the hole.
2. The recall grader's new citation parser credits defects the review never cited: the mandated LOA-VERDICT trailer's own `"critical":0,"high":1,…` counts are parsed as bare `:N` citations of the last cited path. Reproduced on the head script: a review citing only `a.sh:400` scores recall 1.0 on a defect anchored at line 2, and 0.0 once the trailer is removed.

Everything else is observations. With two HIGH findings the one-way rule applies.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — implement gate trusts a model-authored field behind a model-writable switch

- **HIGH** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:115-131` — with `implement_gate.mode: authoritative` in `.loa.config.yaml`, any App-Zone Write whose `tool_input` carries `active_skill: implement|bug|run|simstim` exits 0 (allow) without the fail-ask; `.loa.config.yaml` is outside every zone the PreToolUse hooks fence, so the agent being fenced can set the key itself and bypass the gate on its next write.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:115-131` (selector at :113-116, allow at :126-130; non-App-Zone paths exit 0 at :106-108)
**Issue:** The header (:9-13) and the D-4.4 rationale state that `tool_input` is model-authored and that nothing in `.run/` may select the mode (IG-5 pins that). The same reasoning applies to `.loa.config.yaml`: the registered PreToolUse Write/Edit hooks (`zone-write-guard.sh`, `team-role-guard-write.sh`, `spiral-dispatch-guard.sh`, this gate, `notes-size-guard.sh`) fence `.claude/` and `.run/`, not the project config. Exploit path, two tool calls: (1) `Write .loa.config.yaml` with `implement_gate:\n  mode: authoritative` — the gate itself exits 0 at :106-108 because the path is not App Zone; (2) `Write src/x.ts` with `"active_skill":"implement"` in `tool_input` — IG-7 (`head/tests/unit/implement-gate.bats:137-146`) demonstrates this returns allow. The fixture `write-src-active-implement.json` is exactly that payload.
**Why This Matters:** This hook is the mechanical stack named in C-PROC-001 ("implement-gate.sh fail-asks Write/Edit-tool App-Zone writes outside /implement//bug"). A fence the fenced party can switch off is not a fence; keeping the branch while documenting that its input is untrusted (and hiding the key per IG-11) leaves a latent bypass that the heuristic hardening in this PR appears to have closed. CWE-807 (Reliance on Untrusted Inputs in a Security Decision); CWE-284.
**Required Fix:** Preferred — `SIMPLICITY[delete]`: remove the authoritative branch (:118-150), `implement_gate.mode` reading (:113-116), the `--line` "authoritative (opt-in; …)" label in `detect-platform-features.sh:30-33`, and tests CH-T8/CH-T9/IG-7/IG-8/IG-11; keep the evidence recorder. The header already says no harness signal exists, so the branch has no legitimate input. Alternative — keep it only if the selector comes from a source the model cannot write (an environment variable set by the harness launcher, checked alongside a System-Zone-owned marker), document it, and add a bats case proving a `.loa.config.yaml` written in-session does not select it.

### 2. Correctness — recall grader credits defects from the LOA-VERDICT trailer's JSON

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:72-75` — the bare-citation alternative `(?<![A-Za-z0-9_./:]):(\d{1,6})` accepts `"` as the preceding character, so the trailer `"critical":0,"high":1,"medium":0,"low":0,"excluded":0` yields four or five phantom citations of the last cited path at lines 0/1; a defect anchored at line ≤ 4 in that file is marked detected without being cited.
**File:** `head/evals/graders/recall-vs-defects.sh:72-75` (regex), `:84-85` (binding to `last`)
**Issue:** Reproduced against the head script. Manifest with one defect `{file: .claude/scripts/a.sh, anchor_line: 2}`; review body is one line, `` `head/.claude/scripts/a.sh:400` — unrelated nit ``, plus the standard trailer:
```
{"pass": true, "score": 100, "details": {"recall": 1.0, "detected": ["D-EARLY"], "citations": 6, ...}, "grader_version": "1.1.0"}
```
Same review with the trailer line deleted:
```
{"pass": false, "score": 0, "details": {"recall": 0.0, "missed": ["D-EARLY"], "citations": 1, ...}}
```
The RG-1 fixture itself reports `citations: 5` for a single real citation. Every graded review carries this trailer by contract (`verdict-derive.sh` requires it), so `details.citations` is wrong on 100% of inputs and recall is inflated for any defect anchored in a file's first four lines. The base regex required a path before the colon and did not have this path.
**Why This Matters:** This grader is the measurement instrument behind the pre-registered replay A/B rule that Task 4.8 in this very PR acted on (reverting the CLAUDE.loa.md trim). A grader that credits uncited defects undermines those decisions; RG-14 ("a bare :N glued to a word credits nothing") shows the intent but the test corpus never includes the trailer the real harness always appends.
**Required Fix:** Exclude JSON/HTML-comment context from the bare form — e.g. require the bare `:N` to be preceded by start-of-line, whitespace, a backtick or `(` (`(?<=^|[\s\`(])`) rather than "not alphanumeric", and strip `<!-- … -->` comments from `text` before matching. Add RG tests where the review body is `a.sh:400` + trailer with a defect at anchor 2 (expect `missed`), and assert `citations == 1` for RG-1.

---

## Observations

### 1. Output budgets vs. the reasoning models the aliases now resolve to

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-learning-extractor.sh:317` — `call_flatline_chat "cheap" … 30 500` now reaches Sonnet 5 (`params.thinking_adaptive: true`, so the adapter sends `thinking: {type: adaptive}`); thinking tokens count against `max_tokens`, a 500-token cap can be consumed before the JSON answer, and cheval only prints a stderr WARN (`cheval.py:2525-2533`) that `call_flatline_chat` discards (`2>/dev/null`), so the extractor fails with exit 4 and no diagnostic.
**File:** `head/.claude/scripts/flatline-learning-extractor.sh:317`; same shape at `head/.claude/scripts/flatline-proposal-review.sh:75-76` (`reviewer` → gpt-5.5 reasoning, `opus` → Opus 5.5, 500 tokens) and `head/.claude/scripts/flatline-validate-learning.sh:80-81` (300 tokens).
**Suggestion:** Raise `max_tokens` for these calls (≥ 4000) or pass a low effort; surface the cheval WARN instead of discarding stderr. Add a mocked test that a `stop_reason: max_tokens` response is reported.
**Benefit:** The previous targets (gpt-4o, gpt-4o-mini, claude-3-opus) had no reasoning budget; the retarget silently changes the failure envelope of three scripts.

### 2. Documentation

- **MEDIUM** (confidence: medium) `head/README.md:12` — the README links `CHANGELOG.md`, the last commit message in `pr/PR.md` says it edited the CHANGELOG protocol figure, yet none of the 88 files is `CHANGELOG.md`; no entry for tasks 4.1–4.8 (opus/cheap retarget, Opus 5.5 pricing, permission-rule grammar, implement-gate evidence, grader 1.1.0, prompt-budget change) is in the change set.
**File:** `head/README.md:12`
**Suggestion:** Add the cycle-126 sprint-250 entries to `CHANGELOG.md` in the same change (Documentation Verification: one entry per task). If the CHANGELOG was edited in a commit outside this range, say so in the PR description.
**Benefit:** `/loa` and the release pipeline read the CHANGELOG heading; the migration addendum alone is not the release record.

### 3. check-permissions.sh robustness and documentation claims

- **LOW** (confidence: high) `head/.claude/scripts/check-permissions.sh:238` — `rule_key "$perm"` is called bare inside `main()` under `set -euo pipefail`; the first non-`Bash(...)` entry ever added to a `REQUIRED_*` array makes the preflight exit non-zero with no report (the loaders at :216 and :222 guard the same call with `|| continue`). At :237 the `base` of an exact-key requirement (`=git push`) is computed as `*=git`, which can never match. Both are latent today because every requirement is a `:*` wildcard. (Companion voice DISS-C-002 raised the first point.)
**Suggestion:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` and derive `base` only when `key` starts with `*`.
- **LOW** (confidence: medium) `head/docs/migration/v2.0-model-generation-floor.md:258-263` — "reads permission rules the way Claude Code does" overstates the grammar at `head/.claude/scripts/check-permissions.sh:162-173`. Claude Code's documented rules also treat `Bash(*)` and bare `Bash` as "every command", `Bash(git*)` (no space) as a prefix glob, and `*` anywhere in the body as a wildcard; `rule_key` reads all three as exact or skips them. A deny `Bash(git*)` therefore passes the preflight and then blocks every git command in the run. These gaps pre-date the PR, but the doc now claims parity and CP-13 pins the narrower grammar.
**Suggestion:** Soften the doc to the two forms actually modelled (`:*` and trailing ` *`), or extend `rule_key` to treat `*`/bare `Bash` as covering everything and a trailing `*` without a space as a prefix.

### 4. Catalog consistency on long-context pricing

- **LOW** (confidence: medium) `head/.claude/defaults/model-config.yaml:562` — `claude-opus-5` keeps a `long_context` tier (2.0× / 1.5× above 200K, `verified: false`) while the new `claude-opus-5-5` entry (:470-509) cites the vendor's "Claude 4.6 and later models … include the full 1M token context window at standard pricing". The vendor page (read 2026-10-21) confirms the 5.5 reading for the whole 4.6+ family, so the opus-5 / five-family tier pinned by `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:326-335` now contradicts the source the 5.5 test (:343-350) relies on; the cost ledger overstates Opus 5 / Sonnet 5 / Fable spend past 200K input tokens.
**Suggestion:** Out of this PR's scope to re-price, but record the contradiction (a NOTES/decision entry) and open the follow-up; do not let two tests pin opposite vendor policies silently.

### 5. platform-features.json shape after the recorder runs first

- **LOW** (confidence: medium) `head/.claude/scripts/detect-platform-features.sh:53-54` — when the gate recorder (`head/.claude/hooks/compliance/implement-gate.sh:44-46`) creates `platform-features.json` first, the file has `active_skill_available`, `active_skill_seen_at`, `active_skill_source` only; the 1-hour cache check returns before adding `schema_version`, `detected_at`, `harness_signal`. No consumer reads those keys today, so this is cosmetic. (Companion voice DISS-C-003.)
**Suggestion:** Have the recorder write the full schema-2 shape, or skip the cache early-exit when `schema_version` is absent.

### 6. Prompt budget headroom

- **LOW** (confidence: high) `head/.claude/loa/CLAUDE.loa.md:1` — the file is 10,225 B against the budget raised to 10,240 B in `head/tools/check-prompt-budget.sh:53` (15 bytes of headroom). The budget was raised by exactly enough to fit the reverted tables; the next rationale edit to `constraints.json` re-renders into this file and breaks PB-4 / CI.
**Suggestion:** Either give the budget real headroom with a stated rationale, or trim a non-generated line.

---

## Cross-Model Observations (Phase 2.5)

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — `status: clean`, primary `gpt-5.5-pro` (0 findings), companion `claude-headless` (`counted_as: independent_voice`, 5 advisory findings). Advisory input only; triage:

- DISS-C-001 (implement-gate authoritative branch; `.loa.config.yaml` outside the fenced zones) — **confirmed**, folded into Changes Required §1 with the two-Write exploit path.
- DISS-C-002 (`rule_key "$perm"` bare under errexit) — **confirmed**, Observations §3.
- DISS-C-003 (recorder-created `platform-features.json` lacks schema keys for an hour) — **confirmed**, Observations §5; no consumer reads the keys.
- DISS-C-004 (`cheap` → Sonnet 5 with 500-token cap and adaptive thinking) — **confirmed** as plausible, Observations §1; cheval WARNs but the shim discards stderr.
- DISS-C-005 (head test module asserts `claude-opus-5-5` is calibrated) — **not a defect**: `test_lookup_returns_the_concrete_bound_through_the_gate_path`, `test_a_foreign_transport_calibration_carries_its_provenance` and `is_foreign_transport` appear in neither `pr/head` nor `pr/base` of `test_anthropic_catalog_floor.py`; the only `calibrated_at` assertions (:290, :307, :350) agree with the catalog.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and `metadata.rejected_sidecars` lists no sidecar.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Report each defect with file and line | Pass | 2 blocking + 7 observations above, all cited `head/<path>:<line>` |
| Give a merge verdict | Pass | CHANGES_REQUIRED (two HIGH findings) |
| Opus 5.5 entry vendor-sourced ($4/$20, 1M/128K, 0.05× cache) | Pass | Matches platform.claude.com pricing page (read 2026-10-21) |
| Registry covers every served Anthropic/Bedrock entry (D-4.2) | Pass | 16/16 rows; `test_every_anthropic_catalog_entry_has_a_row` logic re-run by hand |
| Generated twins regenerated | Pass | `gen-adapter-maps.sh --dry-run` on the head catalog is byte-identical to `generated-model-maps.sh`; checksum file matches |
| Implement gate never selected by `.run/` (D-4.4) | Partial | IG-5 holds, but the opt-in moved to a file the model can write (Changes Required §1) |
| Grader 1.1.0 parser (Task 4.8) | Fail | Trailer JSON credited as citations (Changes Required §2) |

`reviewer.md` is the PR description and carries no `## AC Verification` section; per the review instructions for this frozen PR the pre-flight that needs it is skipped and the ACs were verified from the code.

---

## Security Checklist

- [x] No hardcoded secrets or credentials (adversarial-review secret scan: 1 redaction applied to its own prompt copy; none in the diff)
- [ ] Input validation at trust boundaries — implement-gate trusts `tool_input.active_skill` behind a model-writable switch (Changes Required §1)
- [x] Authentication/authorization — model-permissions rows copy the 4.7 all-none scopes; `claude-headless` row documents the `--tools ""` posture
- [x] No injection vectors introduced (`jq --argjson`/`--arg` used for all JSON writes; mktemp+mv atomic writes)
- [x] Error messages do not leak sensitive data (model-adapter forwards only the agy WARN line, 600 chars)

---

## Code Quality Summary

**Strengths:**
- Red-first tests for every residue fix (RES-1..7, IDR-1..4, IG-1..11, CP-11..13, MA-1..6), with fixtures that mirror the documented PreToolUse payload shapes.
- Generated artifacts and checksums are consistent with their sources; the catalog entry carries a dated vendor citation and a `loa:shortcut:` marker with an upgrade trigger on the probed ceiling.
- The `.run/`-forgery hardening of the gate (IG-5) and the single-writer recorder are correct as far as they go.

**Areas for Improvement:**
- `SIMPLICITY[delete]`: the authoritative branch of implement-gate.sh (~30 lines plus 5 tests) has no legitimate input by the PR's own analysis. net: -30 lines possible.
- `GOAL-DRIVEN`: the grader tests never include the LOA-VERDICT trailer the harness always appends; the regression hides behind that gap.
- `FAST-GATE`: not verifiable here — the PR description reports no formatter/shellcheck/type-check run, and the snapshot lacks CI config; `shellcheck` is not installed in this environment.

---

## Next Steps

1. Remove (or operator-fence and document) the implement-gate authoritative branch; keep IG-5 and add a test that an in-session `.loa.config.yaml` write cannot select it.
2. Fix the bare-`:N` alternative in `recall-vs-defects.sh` and add trailer-bearing RG tests; re-run the grader on the replay A/B corpus to confirm Task 4.8's decision is unchanged.
3. Address the observations you accept (output budgets, CHANGELOG entry, `rule_key` guard) and update `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:12:00Z"} -->
