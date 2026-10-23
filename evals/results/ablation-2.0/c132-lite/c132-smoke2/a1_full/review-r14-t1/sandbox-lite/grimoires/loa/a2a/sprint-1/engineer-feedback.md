# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: cycle-126 sprint-250 tasks 4.1–4.8 — the `opus` alias moves to a new `claude-opus-5-5` catalog entry, `cheap` moves to `claude-sonnet-5`, every Anthropic catalog entry gets a `model-permissions.yaml` row, the implement gate stops reading a harness skill signal from `.run/`, `check-permissions.sh` learns the `Bash(cmd *)` rule form, the eval recall grader gets a 1.1.0 citation parser with multi-site anchors, and the Sprint 3 instruction diet is reverted per the pre-registered replay A/B rule.

Most of the sprint is solid and was verified by running the PR's own tests against the PR's `.claude/` tree (`pr/head/` holds only the non-dotfile files; the `.claude/` and `.loa.config.yaml.example` changes were reviewed from the diff and the workspace tree). Passing: CP-1..13 (permission grammar incl. the dangerous-shape deny fuzz set), IG-1..11 and CH-T1..T14 (implement gate), MA-1..6, RES-1..7, IDR-1..4, FMT-1..6, CMP-277/278, the V3 schema additions, the validate-artifact pipefail fix, RG-1..15. `gen-adapter-maps.sh` regenerates `generated-model-maps.sh` byte-identical, the catalog checksum and the CLAUDE.loa.md `@loa-managed` hash verify, the Bridgebuilder `.build-manifest.json` hashes match the generated sources, and every Anthropic direct/Bedrock catalog entry has a permissions row.

One defect blocks the merge: the grader's new bare-`:N` citation alternative credits JSON values — including the counts in every review's own LOA-VERDICT trailer — as line citations bound to the last cited file, so recall is over-reported for exactly the instrument this sprint's A/B rule relies on. Two medium items (a stale generated block the rationale revert left behind, and an agent-types registry that misses an agent present in the review tree) and three lows follow.

Not verifiable in this sandbox: the five Python adapter test files (the snapshot's `loa_cheval` package is from a different revision and fails to import), the `.loa.config.yaml.example` edits (file absent from the snapshot), RG-16/RG-17 and PB-8 (fixture corpus absent), the license-fixture freshness tests (generator script absent), and the Bridgebuilder `dist/` rebuild (`tsx` absent).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Eval grader — bare `:N` citations bind JSON values to the last cited path

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:74` — the bare-citation alternative's lookbehind `(?<![A-Za-z0-9_./:])` does not exclude `"`, `'`, `}`, `]` or `)`, so any `"key":N` after a cited path becomes a citation of line N in that file; every graded review carries one in its LOA-VERDICT trailer.
**File:** `head/evals/graders/recall-vs-defects.sh:71-90`
**Issue:** The 1.1.0 parser (bd-ewrc) adds `(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>…)` so that a later `:7` or `head:7` binds to the most recent cited path. The lookbehind only rejects word/path characters and a colon. A double quote passes, so the trailer `"counts":{"critical":0,"high":0,"medium":7,"low":0}` yields bare citations 0, 0, 7, 0 against the last cited file. Reproduced with a synthetic manifest (D3 anchored at `c.sh:7`, D4 at `d.sh:2`):

```
review.md: c.sh:100 is odd.  + trailer with "medium":7
→ {"detected":["D3"],"citations":6}

review.md: The guard in d.sh:300 is wrong. JSON body: {"line":1,"count":2} and a ratio 1:2.
→ {"detected":["D4"],"citations":3}
```

Neither review cited line 7 of `c.sh` or line 2 of `d.sh`. The 1.0.0 parser required a path before the colon and did not credit either.
**Why This Matters:** `recall-vs-defects.sh` is the pre-registered instrument behind Task 4.8's replay A/B decision and the review-PR eval corpus. Every review the grader scores ends with a LOA-VERDICT trailer, so every scored review silently gains up to four free citations (lines 0–N where N is a count) against its last cited file, and any inline JSON (`{"decision":"ask"}`-style snippets with numeric values, quoted manifest fields such as `"anchor_line":807`) does the same. Recall is inflated for defects anchored near the top of a file or at a count value; the RG-11..15 tests pass only because their trailer counts (1, 1, 0, 0) land outside the ±3 window of the planted anchors.
**Required Fix:** Restrict the bare alternative to a preceding whitespace, start-of-text or backtick — e.g. replace the empty-lookbehind branch with `(?<=^|[\s`(])` semantics (Python needs fixed-width lookbehinds, so use `(?:^|(?<=[\s`(]))`) — and extend the negative lookbehind before `head|base` the same way. Add a RG case where the trailer's counts equal a planted anchor and assert zero detections, and one with an inline JSON object after a citation.
**Reference:** CWE-185 (Incorrect Regular Expression); evals/graders header contract "credits nothing" for a `:N` glued to a word or number (`head/evals/graders/recall-vs-defects.sh:17-21`).

---

## Observations

### 1. Rationale revert — the rendered Agent Teams block still carries the trimmed text

- **MEDIUM** (confidence: high) `.claude/loa/CLAUDE.loa.md:124-131` — the `agent_teams_constraints` generated block still renders the diet-era C-TEAM rationales ("Planning skills assume single-writer semantics", …) while `constraints.json` C-TEAM-001..005 were reverted to the pre-diet text; `generate-constraints.sh --validate-only` fails with `STALE: Section 'agent_teams_constraints' … (stored: c020, expected: 19641576807c2086)`.
**File:** `.claude/loa/CLAUDE.loa.md:124` (block marker `hash:c020-teamcreate`), `.claude/data/constraints.json:1235-1320`, `head/tests/unit/instruction-diet-revert.bats:61`
**Suggestion:** The drift pre-exists at base (base also reports STALE, expected `12c50d60ff9c0dbf`), so it is not introduced here — but Task 4.8 edits exactly these five rationales because the replay A/B showed the trimmed text costs recall, and the file the model actually reads keeps the trimmed version. Run `generate-constraints.sh` to regenerate the block (or hand-sync and update the marker), and widen IDR-4 beyond the seven C-PROC rows to the five C-TEAM rows so the generated surface is pinned too.
**Benefit:** The revert's stated purpose (restore before-level recall) is only delivered where the rendered text matches the data file.

### 2. agent-types.yaml does not list every agent under `.claude/agents/`

- **MEDIUM** (confidence: low) `.claude/data/agent-types.yaml:10-26` — the registry names `loa-scout`, `prompt-auditor`, `prompt-auditor-io`; the review tree also has `.claude/agents/chart-researcher.md` (read-only, no Write/Edit), so the completeness loop in `head/tests/unit/skill-capabilities.bats:854` fails here (`unlisted: .claude/agents/chart-researcher.md`).
**File:** `.claude/data/agent-types.yaml:25`, `.claude/rules/skill-invariants.md:18`, `head/tests/unit/skill-capabilities.bats:854`
**Suggestion:** Confidence is low because the snapshot's `.claude/` tree is not provably the PR's base (its Python adapter package is from another revision). If `chart-researcher.md` is in the PR's tree, add `chart-researcher: {write_capable: false}` and the row to the skill-invariants table; the validator already treats an unlisted type as not write-capable, so the runtime default is safe either way.
**Benefit:** SC-T-AGENT-7 is red at head otherwise, and the data file's "one row per agent" contract holds.

### 3. Catalog comment misdescribes the Opus 5 ceiling as measured

- **LOW** (confidence: high) `.claude/defaults/model-config.yaml:491` — the `loa:shortcut` marker on the Opus 5.5 entry reads "Opus 5's measured bound, not probed on 5.5"; Opus 5's own `ceiling_calibration.source` is `kf_derived` with `calibrated_at: null`, so nothing was measured.
**Suggestion:** Say "Opus 5's kf-derived bound" (or the conservative default). The upgrade trigger (`tools/ceiling-probe-live.py --write-catalog`) is right.
**Benefit:** An operator deciding whether to probe should not read the 180,000 as a measurement.

### 4. CLAUDE.loa.md sits 15 bytes under the restored budget

- **LOW** (confidence: high) `head/tools/check-prompt-budget.sh:53` — `LOA_LIMIT` is restored to 10,240 B and the live file is 10,225 B (`tools/check-prompt-budget.sh --root .` reports `CLAUDE.loa.md 10225 B (limit 10240)`).
**Suggestion:** Either leave headroom (a one-word rationale edit will fail PB-9) or document that the limit is the file's current size by design.
**Benefit:** The next constraints.json rationale edit does not turn the budget gate red by surprise.

### 5. model-adapter.sh — `mktemp` failure exits without the shim's own error

- **LOW** (confidence: medium) `.claude/scripts/model-adapter.sh:656` — `err_file="$(mktemp …)"` runs under `set -euo pipefail` (line 33); if `mktemp` fails the shim exits before `error "model-invoke failed …"` and before the exit-code translation, with only mktemp's stderr.
**Suggestion:** `err_file=$(mktemp …) || { error "cannot create stderr capture file"; exit 1; }`, matching how `call_flatline_chat` guards its mktemp.
**Benefit:** Callers that parse the shim's error line keep getting one.

### 6. Process — no AC Verification walkthrough

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1-15` — the implementation report is the PR description and carries no `## AC Verification` section; the acceptance criteria were checked directly against the code above (sprint.md: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict").
**Suggestion:** In a normal cycle, the engineer's report must walk every AC verbatim with `file:line` evidence.

## Rejected dissent payloads

- None. The adversarial review ran (`adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --context-file grimoires/loa/a2a/sprint-1/reviewer-concerns.md --json`); the envelope at `grimoires/loa/a2a/sprint-1/adversarial-review.json` stands with `metadata.status: api_failure` — all four hops (`gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro`, `claude-headless`) and the Anthropic companion voice failed with exit 126 because the snapshot's `.claude/scripts/model-adapter.sh` is not executable and no provider credentials exist in this sandbox. `findings: []`, `rejected_sidecars: []`, no `adversarial-rejected-review*.jsonl` beside it. Single-model assessment applies; the dissent should be re-run before the audit completes the sprint.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The grader defect above; the stale `agent_teams_constraints` block left by the Task 4.8 revert |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request

| Criterion | Status | Notes |
|-----------|--------|-------|
| report each defect it introduces with the file and line it sits on | Pass | One HIGH, two MEDIUM, three LOW above, each with `head/<path>:<line>` (or the `.claude/` path when the file is outside `pr/head/`) |
| give a merge verdict | Pass | CHANGES_REQUIRED — one HIGH |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the adversarial content scan applied one redaction to the diff bundle; nothing in the diff itself)
- [x] Input validation and sanitization present (`rule_key` normalises without glob expansion; `_lc_chunk_tok` canonical-decimal guard; `top_path_log` strips C0/DEL before stderr; implement-gate recorder validates payload shape with `jq -e`)
- [x] Authentication/authorization correct (every new `model-permissions.yaml` row mirrors the 4.7 remote-model scopes; `claude-headless` row documents the `extra.allowed_tools` widening)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data (model-adapter forwards only the agy argv WARN line, 600-char capped)

---

## Code Quality Summary

**Strengths:**
- `check-permissions.sh` rule grammar is small, fork-free and exhaustively tabled (CP-13's 21-shape deny fuzz set); deny precedence preserved.
- Implement gate: the evidence recorder is lead-only, write-once, atomic (mktemp + mv), and nothing in `.run/` or a model-authored payload selects authoritative mode (IG-5 forged payload test).
- Generated surfaces regenerate byte-identical (`gen-adapter-maps.sh`), checksums/hashes verify, and `test_every_anthropic_catalog_entry_has_a_row` closes the unscoped-model gap mechanically.
- `validate-artifact.sh` here-string fix removes a real pipefail/SIGPIPE flake, with a regression test that greps the anti-pattern out of the script.

**Areas for Improvement:**
- Regex changes to a measuring instrument need adversarial inputs drawn from the documents it will actually score (the trailer, JSON snippets), not only the shapes it was meant to admit.
- When a sprint edits generated data (`constraints.json`), run the generator's validate step; the STALE block was one command away.

---

## Next Steps

1. Fix the bare-citation lookbehind in `evals/graders/recall-vs-defects.sh` and add the two RG cases; bump `grader_version` to 1.1.1.
2. Regenerate the `agent_teams_constraints` block in `CLAUDE.loa.md` (or sync by hand and update the marker) and widen IDR-4 to the C-TEAM rows.
3. Confirm whether `chart-researcher` is in the PR's tree; if so, add it to `agent-types.yaml` and the skill-invariants table.
4. Re-run the adversarial dissent where `model-adapter.sh` is executable and credentials exist.
5. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T13:20:00Z"} -->
