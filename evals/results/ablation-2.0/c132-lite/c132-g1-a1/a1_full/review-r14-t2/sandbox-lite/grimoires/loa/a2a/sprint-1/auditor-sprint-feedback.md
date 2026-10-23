# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` — 88 files, cycle-126 sprint-250 tasks 4.1–4.8 (`opus` → `claude-opus-5-5`, `cheap` → `claude-sonnet-5`, permission-registry rows, implement-gate evidence recorder, permission-rule grammar, constraint-rationale revert, probes and docs). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint's data work is sound and was verified mechanically, not from the report: all 16 Anthropic entries the head catalog serves (direct and Bedrock) have a `model-permissions.yaml` row whose trust scopes, trust level, execution mode and capabilities equal the 4.7 reference row, with no orphan rows; `model-config.yaml.checksum` matches the head catalog; the two in-PR `SHA256SUMS` rows match; the bash model maps, flatline allowlists and red-team defaults agree with the catalog's `opus` alias; no secret patterns appear in the diff. The `rule_key` normaliser, the `grep -q <<<` pipefail fixes and the licence-fixture freshness guard are correct and minimal.

What blocks the merge is the compliance fence the PR touches. First, the opt-in `authoritative` branch of `implement-gate.sh` grants App Zone writes on `tool_input.active_skill`, a field the PR's own header calls model-authored, and the opt-in selector lives in `.loa.config.yaml`, a file the fenced agent can write; I reproduced the silent allow against the head script. Second, the gate's only enforcement output, `{"decision":"ask"}`, is not a PreToolUse decision at all: the Claude Code hooks reference puts `allow|deny|ask` under `hookSpecificOutput.permissionDecision` and defines no top-level `decision` field for PreToolUse, so the fence never asks in either mode. That shape predates the PR, but the PR's new fixture corpus, `decision()` test helper and restated constraint rationale ("implement-gate.sh fail-asks") pin it as the contract, and this is the sprint that rewrote the gate's mode logic and header. Five medium findings follow (permission grammar, catalog long-context contradiction, `mktemp` under `set -e`, a stale generated block at the raised prompt budget, 300/500-token budgets on adaptive-thinking models) and ten lows.

Adversarial dissent (Phase 1C) ran on `pr/head.diff` with two voices: primary `gpt-5.5-pro`, companion `claude-headless` (status `succeeded`, counted as an independent voice). Envelope status `clean`, `degraded: false`, four findings (one MEDIUM, three LOW), zero rejected payloads, no advisory voices. All four were triaged below: the MEDIUM (model-writable selector) is folded into HIGH-001; the three LOWs are confirmed as LOW-001, part of MED-001, and LOW-009.

**Process deviation:** the skill's Phase 0 prerequisite ("engineer-feedback.md says All good") is not met; the review's verdict is CHANGES_REQUIRED. The task directive for review-r14 instructs this audit to run and write its feedback regardless, so it ran; nothing here supersedes the review's required changes. `qmd-context-query.sh`, `br` and `grimoires/loa/known-failures.md` are unavailable in this workspace (the SessionStart hook reported the known-failures surface degraded); those steps were skipped.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 10 |

`excluded`: 0 (no high was demoted as speculative). `excluded_confirmed`: 0 (the review trailer's `excluded` is 0; nothing to confirm).

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The opt-in `authoritative` mode grants App Zone writes on a model-authored field, selected by a model-writable file

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/hooks/compliance/implement-gate.sh:128` (grant), `:10-13` (header), `:114-116` (selector), `head/tests/fixtures/pretooluse-payloads/expected.tsv:8-9,11` (`allow` pinned), `head/tests/unit/implement-gate.bats:104` (IG-7)
**Issue:** The header states "tool_input is model-authored, so nothing in .run/ selects this mode" (`:12-13`), then the branch at `:122-131` reads exactly that field and exits 0 on `implement|bug|run|simstim`:
```bash
case "$active_skill" in
    implement|/implement|bug|/bug|run|/run|simstim|/simstim)
        exit 0
        ;;
esac
```
Reproduced against the head script: with `implement_gate.mode: authoritative` in a scratch `.loa.config.yaml` and a Write payload for `src/index.ts` carrying `"active_skill":"implement"`, the hook exits 0 with no JSON (silent allow); the same payload without the opt-in emits the ADVISORY ask. The selector file `.loa.config.yaml` sits at the repo root, outside the `.claude/` System Zone fence, so the agent being fenced can write the opt-in and then self-attest on every App Zone write (the dissent's MEDIUM finding, anchor `:113`, makes the same point). The removed `compliance.mode.change` audit row means the switch into the weaker mode leaves no trace in `.run/audit.jsonl`. `expected.tsv` rows 8, 9 and 11 and IG-7 lock `allow` in as the expected outcome for the forged payloads; IG-5's "a forged active_skill Write payload does not flip the gate" holds only in the default mode.
**Impact:** The mechanical fence for C-PROC-001 ("NEVER write application code outside `/implement`") becomes fail-open under a two-step the fenced party can perform alone: unreviewed application code reaches the tree with no ask and no log. HIGH rather than CRITICAL because the key is opt-in and the heuristic path already trusts model-writable `.run/` state (the gate is advisory by design); the PR makes the weaker mode easier to reach and pins it in tests.
**Fix:** Make a claim tighten-only: an implementation claim falls through to the heuristic exactly like an absent field (never `exit 0`); a non-implementation claim may add an ask. Update `expected.tsv` rows 8, 9, 11 to `ask` and IG-7 accordingly, or remove the branch and the key outright. Re-add a one-row audit event when a claim influenced the decision.
**Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; OWASP A01:2021 Broken Access Control — https://owasp.org/Top10/A01_2021-Broken_Access_Control/

### [HIGH-002] The gate's "ask" reply is not a PreToolUse decision, so the fence never asks; the PR's corpus pins the shape

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/hooks/compliance/implement-gate.sh:230` (ADVISORY ask), `:135` (AUTHORITATIVE ask), `:19` ("Failure mode: FAIL-ASK"); `head/tests/unit/implement-gate.bats:35` (`decision()` helper), `head/tests/fixtures/pretooluse-payloads/expected.tsv:5`; `head/.claude/data/constraints.json:14` and `head/.claude/loa/CLAUDE.loa.md:74` ("implement-gate.sh fail-asks Write/Edit-tool App-Zone writes")
**Issue:** Both ask paths print
```bash
echo '{"decision":"ask","reason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}'
```
The Claude Code hooks reference (https://code.claude.com/docs/en/hooks, the page the PR itself cites in `implement-gate.bats:6` and `expected.tsv:1`) defines the PreToolUse decision as `hookSpecificOutput.permissionDecision` with values `allow|deny|ask|defer` and states there is no top-level `decision` field for PreToolUse. A hook that exits 0 and prints an unrecognised JSON object is treated as non-blocking, so the write proceeds. The two lines predate this PR (`pr/base/.claude/hooks/compliance/implement-gate.sh:172,267`), but the PR rewrote the gate's header and mode logic around them, added a seven-fixture corpus whose `heuristic`/`authoritative` columns are defined as "the gate emits {"decision":"ask"}" (`expected.tsv:5`), added a `decision()` helper that recognises only that string, and restated in the constraint registry and the rendered NEVER table that the fence "fail-asks". The later framework copy in this workspace fixed exactly this ("A top-level decision accepts approve|block only, so ask never goes there"), which confirms the defect is real and the fix known.
**Impact:** In both modes the fence is fail-open while documented as FAIL-ASK: every App Zone write outside `/implement` proceeds without a prompt. The stderr lines are the only signal, and nothing consumes them.
**Fix:** Emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}` at `:135` and `:230`; make `decision()` and the `expected.tsv` header assert that shape; verify once against the hooks reference.
**Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html; CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

---

## Medium/Low Priority Issues

### [MED-001] Permission grammar: the universal rule is outside the grammar, and `Bash(:*)` collapses to a bare `*` key
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/scripts/check-permissions.sh:164` (guard), `:167-172` (key), `:203` (deny insertion), `:233-250` (lookups); `head/tests/unit/check-permissions.bats:209-216` (no universal shape in the fuzz set); `head/docs/migration/v2.0-model-generation-floor.md:258-262` ("Deny still wins over allow")
- **Issue:** Probed with `rule_key` extracted from head: bare `Bash` returns 1 and is skipped, `Bash(*)` becomes the exact key `=*`, `Bash(:*)` and `Bash( :* )` become the bare key `*`. None of these can be hit by a requirement lookup, so `"deny": ["Bash"]` or `["Bash(:*)"]` is reported as 16 found (Claude Code then denies every Bash call mid-run) and `"allow": ["Bash"]` as 16 missing. The bare `*` key is worse than inert: in bash, `${deny_by[$RULE_KEY]+x}` with `RULE_KEY='*'` expands as the all-elements form and is true whenever the map already has any entry (verified: `declare -A a; a["*git"]=f; k='*'; ${a[$k]+x}` → `x`), so the rule is dropped at `:203` without a WARN. The dissent's LOW (anchor `:162`) covers the `Bash(*)` half.
- **Fix:** Map bare `Bash`, `Bash(*)` and an empty wildcard body to a reserved `ALL` key; check `deny_by[ALL]` before per-key lookups and `allow_by[ALL]` alongside them; never use a settings-derived string as a subscript without a prefix; add the three shapes to CP-13.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [MED-002] Catalog: the long-context pricing model contradicts itself within the 1M family
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/defaults/model-config.yaml:476-478` (rationale), `:470-509` (entry, `cache_read_per_mtok: 200000` at `:509`), `:562-566` (`claude-opus-5` long_context 2.0×/1.5×), `:344` and `:722` (fable-5-1, sonnet-5 keep tiers); `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:69` (0.05× exception), `:343` (pins "no long_context" for 5.5 only); `head/docs/migration/v2.0-model-generation-floor.md:246`
- **Issue:** The new entry omits `long_context` because "Claude 4.6 and later models … include the full 1M token context window at standard pricing", while `claude-opus-5`, `claude-fable-5-1` and `claude-sonnet-5`, all "4.6 and later", keep the 2.0×/1.5× tier above 200K in the same file. One reading is wrong; cost estimates above 200K differ by 2× between siblings, and the 0.05× cache-read price is a second exception to the 0.1× rule recorded only in a comment.
- **Fix:** Decide once for the family (drop the FR-1.9 tiers, or give 5.5 the same unverified `reference` tier); record both source lines in `catalog-evidence.md`.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-003] `model-adapter.sh`: a failing `mktemp` now aborts the model call
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/scripts/model-adapter.sh:656` under `set -euo pipefail` (`:33`); `:655-659`
- **Issue:** `err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX")"` has no fallback; with an unusable `TMPDIR` the shim exits before `model-invoke` runs, where the previous `2>/dev/null` path completed the hop. The file is also never removed if the shim is killed between `:656` and `:659`.
- **Fix:** `err_file="$(mktemp … 2>/dev/null)" || err_file=""`; discard stderr with a one-line WARN when empty; `trap 'rm -f -- "$err_file"' EXIT` (chaining any existing trap).
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [MED-004] Constraint registry: the Agent Teams block is stale with a placeholder hash, and the raised budget has 15 bytes of headroom
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/loa/CLAUDE.loa.md:124-130`; `head/.claude/data/constraints.json:1235,1256,1277,1298,1319`; `head/tools/check-prompt-budget.sh:53` (limit 9,216 → 10,240); `head/tests/unit/instruction-diet-revert.bats:37,61`
- **Issue:** The `agent_teams_constraints` block carries `hash:c020-teamcreate` and five "Why" cells (e.g. "Planning skills assume single-writer semantics") that match neither the diet text nor the pre-diet text the PR restored in the registry ("Planning skills produce single artifacts (PRD, SDD, sprint plan) that assume single-writer semantics; concurrent invocation would corrupt state"). A "DO NOT EDIT — generated" block therefore does not match its source, and the head file is 10,225 bytes against the 10,240-byte limit this PR set, so regenerating the block trips PB-9. IDR-3 checks only the registry and IDR-4 only the seven C-PROC rows.
- **Fix:** Regenerate the block and size the budget for the generated file (or shorten elsewhere), or scope the revert and say so; extend IDR-4 to every `@constraint-generated` block so a placeholder hash fails a test.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [MED-005] Model retargeting: 300/500-token output budgets now land on adaptive-thinking models
- **Severity:** MEDIUM | **Confidence:** medium
- **File:** `head/.claude/scripts/flatline-validate-learning.sh:80-81,264,315`; `head/.claude/scripts/flatline-proposal-review.sh:75-77,182,233`; `head/.claude/scripts/flatline-learning-extractor.sh:317`; `head/.claude/defaults/model-config.yaml:474` ("adaptive thinking always on")
- **Issue:** Defaults move from non-thinking wire ids to the `reviewer`/`opus`/`cheap` aliases while the calls keep `max_tokens` 300 and 500. `call_flatline_chat` forwards the value as `--max-tokens` to cheval; `opus` resolves to Opus 5.5 and `cheap` to Sonnet 5 (`thinking_adaptive: true`), and thinking tokens are charged against `max_tokens`, so a short budget can return empty or truncated text that these scripts treat as a model failure. The alias routing itself is fine (cheval resolves aliases).
- **Fix:** Raise the Anthropic budgets or omit `--max-tokens` to take cheval's per-model default; add one mocked check that a 300-token call on `opus` returns non-empty text.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-001] Evidence recorder fires on model-authored input before the zone check and can replace the file wholesale
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:40-50`
- **Issue:** Any payload with a non-empty `tool_input.active_skill` and no `agent_id` triggers a write to `.run/platform-features.json` before `file_path` is read; it forces `active_skill_available: false`, and when the existing file is not a single JSON object the base falls back to `{}` so other keys are lost. Evidence only, no decision effect (dissent LOW, anchor `:40`, confirmed).
- **Fix:** Run the recorder after the App Zone check; merge without forcing `active_skill_available`; skip when the file is unparsable.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-002] Grader: the comma continuation binds any following number to the cited path
- **Severity:** LOW | **Confidence:** high
- **File:** `head/evals/graders/recall-vs-defects.sh:71-73,88`
- **Issue:** `(?:\s*,\s*RNG)*` after the first span accepts `a.sh:40, 2 of the 3 callers` as citing `a.sh:2`, so a decoy defect at line 2 ± 3 is scored as detected.
- **Fix:** Require the continuation to end at a token boundary (`)`, `;`, newline, end) or be glued to the comma.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-003] `lib-content.sh`: C1 controls and bidi code points survive the stderr filter
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/scripts/lib-content.sh:295`
- **Issue:** `tr -d '\000-\037\177'` removes C0 and DEL only; UTF-8 C1 (`C2 80..9F`) and U+202E/U+200B in a `diff --git` path still reach the operator's terminal. CMP-278 covers C0/DEL only.
- **Fix:** Filter to printable, or strip the C1/bidi sequences as well.
- **Reference:** CWE-116 Improper Encoding or Escaping of Output — https://cwe.mitre.org/data/definitions/116.html

### [LOW-004] `/loa` evidence line echoes model-writable state after a control-character strip only
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/scripts/detect-platform-features.sh:35-36`, `:62` (refresh carries values forward); `head/.claude/scripts/loa-status.sh:881-887`
- **Issue:** `active_skill_seen_at` and `active_skill_source` come from `.run/platform-features.json`, which the agent can write; a non-timestamp or non-`tool_input` value is printed as "evidence" into agent-visible status output, and Unicode format characters pass `[:cntrl:]`.
- **Fix:** Accept only an ISO-8601 Z timestamp and the literal `tool_input`; print `none`/`unknown` otherwise; filter to printable ASCII.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-005] `validate-skill-capabilities.sh`: ambient override and all-false fallback
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/scripts/validate-skill-capabilities.sh:110`, `:117`
- **Issue:** `AGENT_TYPES_FILE` from the environment redirects the write-capable allowlist without a visible flag; a file that parses with no `write_capable: true` entry silently re-enables `general-purpose`.
- **Fix:** Take the override as an explicit `--agent-types-file` argument; treat an all-false file as "nothing is write-capable".
- **Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html

### [LOW-006] `check-permissions.sh`: bare `rule_key` under `set -e` in the requirement loop
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/scripts/check-permissions.sh:235`
- **Issue:** The first non-`Bash(…)` requirement added to `all_required` aborts the preflight with no report instead of being reported missing. Latent today (all requirements are `Bash(…:*)`).
- **Fix:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }`.
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [LOW-007] `flatline-orchestrator.sh`: the stub allowlist and the fallback provider map disagree
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/scripts/flatline-orchestrator.sh:556`, `:694-702`
- **Issue:** The no-generated-maps stub admits `cheap`, `gpt-5.5`, `gpt-5.5-pro`, `gemini-3.1-pro-preview`; `MODEL_TO_PROVIDER_ID` has no rows for them, so the bare name passes through and works only because cheval resolves aliases.
- **Fix:** Add the rows or drop the names so the two fallback tables agree.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-008] IG-11 enforces an undocumented operator-facing key
- **Severity:** LOW | **Confidence:** high
- **File:** `head/tests/unit/implement-gate.bats:151-154`
- **Issue:** The test asserts `implement_gate` appears nowhere in `.loa.config.yaml.example`, `docs/` or `README.md`; operators cannot discover the mode they are expected to avoid, and "undocumented" is not a control (see HIGH-001).
- **Fix:** Document the key with its caveat, or remove the key and the test.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-009] `anthropic:claude-headless` row: `command_execution: false` is not cross-checked against the adapter
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/data/model-permissions.yaml:446-473` (note at `:469`); `head/.claude/adapters/tests/test_trust_scopes.py:360-371` (row excluded from the mirror test)
- **Issue:** The row is justified by the adapter running `claude -p --tools "" --permission-mode plan`; the adapter does default to `--tools ""`, but `extra.allowed_tools` replaces that argument, and no test asserts the catalog's `claude-headless.extra.allowed_tools` is empty. The hop is the terminal fallback of `claude-opus-5-5` and siblings. Dissent LOW (anchor `:449`), confirmed.
- **Fix:** Add a test that the catalog's `claude-headless` entry carries no `extra.allowed_tools` whenever this row is relied upon.
- **Reference:** CWE-285 Improper Authorization — https://cwe.mitre.org/data/definitions/285.html

### [LOW-010] Advisor tier lags the `opus` alias without a stated reason
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.loa.config.yaml.example:2717` (`anthropic: claude-opus-5`), `:962` (`opus` → 5.5); `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:267-273` pins the former
- **Issue:** The migration note presents 5.5 as the current generation; the advisor tier still names `claude-opus-5` with no comment saying the lag is deliberate.
- **Fix:** One comment line beside the alias stating the intent.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

---

## Rejected dissent payloads

None. The envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json` records `rejected_count: 0`, `rejected_summary: []`, `rejected_sidecars: []`; primary `gpt-5.5-pro` status `clean` (`model_attempts: ["gpt-5.5-pro:clean"]`), companion `claude-headless` status `succeeded`, `counted_as: independent_voice`, `degraded: false`, `hallucination_filter.downgraded: 0`. The four findings were triaged: MEDIUM at `implement-gate.sh:113` (model-writable selector) → HIGH-001; LOW at `:40` (evidence recorder) → LOW-001; LOW at `check-permissions.sh:162` (`Bash(*)` blind spot) → MED-001; LOW at `model-permissions.yaml:449` (headless row) → LOW-009. No `advisory_voices` were present; `DEGRADED_SECURITY_REVIEW` does not apply.

---

## Review demotions confirmed

The review trailer records `excluded: 0`; there are no demoted highs to confirm. `excluded_confirmed: 0`.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 10 |

---

## Rubric Scores

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.0/5 | IV:3 AZ:2 CI:4 IN:3 AV:3 — a fence that grants on a model field and emits an unrecognised decision |
| Architecture | 3.6/5 | MO:4 SC:4 RE:4 CX:3 ST:3 — generated artifacts regenerated, but one generated block and one catalog rule drift |
| Code Quality | 3.6/5 | RD:4 TC:4 EH:3 TS:4 DC:3 — strong corpus-driven tests; two `set -e` regressions |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 AC:4 DS:4 — checksums, manifests and maps verified byte-for-byte |
| Blockchain | n/a | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (pattern scan of `pr/head.diff` clean; fixture paths are synthetic)
- [ ] Input validation on all new entry points — model-authored `active_skill` trusted under the opt-in (HIGH-001); universal permission rule unhandled (MED-001); C1/bidi bytes reach stderr (LOW-003); `.run/` values echoed into `/loa` (LOW-004)
- [ ] Authorization correct — compliance fence fail-open under the opt-in (HIGH-001) and never asks in either mode (HIGH-002)
- [x] No SQL/XSS injection vulnerabilities (none applicable; settings strings used as associative-array keys, not evaluated)
- [x] Error handling doesn't leak info — cheval stderr relayed as one fixed-string line cut to 600 bytes
- [ ] Tests cover security paths — the new corpus pins the wrong decision shape and `allow` for forged payloads

## Documentation Audit

No `documentation-coherence-*.md` reports exist in this workspace (no `/implement` ran here); manual check instead. The migration addendum and README match the catalog retargets. The constraint rationale and `CLAUDE.loa.md:74` state the gate "fail-asks" (HIGH-002); the header's "Failure mode: FAIL-ASK" (`implement-gate.sh:19`) is not true in head. No `CHANGELOG.md` is among the 88 touched files, so a security-change entry for the gate rewrite could not be verified. No secrets or internal URLs in docs or comments.

---

## Next Steps

1. Fix HIGH-001 and HIGH-002 together: tighten-only claim handling and the `hookSpecificOutput.permissionDecision` shape, then update `expected.tsv`, `decision()` and IG-5/IG-6/IG-7 so the corpus asserts a real ask.
2. Resolve MED-001 (universal rule, reserved key), MED-002 (one long-context reading), MED-003 (`mktemp` fallback), MED-004 (regenerate the Agent Teams block or re-scope the revert), MED-005 (Anthropic output budgets).
3. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:44:00Z"} -->
