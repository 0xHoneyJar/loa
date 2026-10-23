# Security & Quality Audit Report — sprint-1

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Scope:** `pr/head.diff` — cycle-126 sprint-250 tasks 4.1–4.8 (88 files, +1956/−366); frozen PR, cited as `head/<path>:<line>`
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable), Phase 1A/1B source→sink tracing (`grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`), Phase 1C two-voice dissent (`adversarial-audit.json`), hand reproduction of every HIGH.

---

## Pre-flight deviations (recorded, not hidden)

- **Phase 0 prerequisite not met.** `engineer-feedback.md` is `CHANGES_REQUIRED` (2 HIGH / 2 MEDIUM / 5 LOW), not "All good". The skill says STOP; the task brief for review-r14 directs this audit to run autonomously against the frozen PR, so I proceeded and treat the review's findings as input to confirm or dispute, not as settled. `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`, so the review's Phase 2.5 gate is COMPLETED.
- **Frozen snapshot limits.** No beads database, no documentation-coherence reports under `grimoires/loa/a2a/subagent-reports/`, no `.reviewignore`. Documentation was verified manually (below). bats suites that need shared libraries, executable bits or fixture trees outside the 88 files fail for environmental reasons in `pr/head`; where that happened I re-ran the subject by hand. Suites that do run: implement-gate 11/11, check-permissions 13/13, model-adapter MA-1..2 (MA-3..6 need `lib/model-resolver.sh`).
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` is absent in this workspace (SessionStart WARN); triaged without it.

---

## Executive Summary

The bulk of the change is sound and I confirmed the review's mechanical checks independently: the `claude-opus-5-5` catalog entry prices and shapes match the vendor pages cited in the entry's own comment; `model-config.yaml.checksum` equals `sha256sum` of the head catalog (`759dfd3f…`); the two re-anchored eval manifests match `SHA256SUMS`; every new `model-permissions.yaml` row copies the 4.7 all-`none` side-effect scopes; `generated-model-maps.sh` and the Bridgebuilder generated twins carry the new entry; the hardening that stops `.run/` from selecting the implement gate's mode (IG-5, CH-T10) holds; `lib-content.sh`'s octal-index and control-byte fixes are correct and tested.

Two findings block the merge, both confirmed by independent reproduction rather than taken from the review. First, the implement gate's authoritative branch still allows an App-Zone write on the model-authored `tool_input.active_skill` field, and the only selector is `implement_gate.mode` in `.loa.config.yaml`, a project-root file that this hook itself exits 0 for and that no other PreToolUse hook fences. The fenced agent can switch the fence off in two Writes; the key is kept undocumented by test (IG-11), which hides the hole. Second, the recall grader's new bare-`:N` citation form accepts a `"` before the colon, so the LOA-VERDICT trailer every graded review must carry is parsed as citations of the last cited path at lines 0/1: on the head script a review citing only `a.sh:400` scores recall 1.0 on a defect anchored at line 2 and 0.0 once the trailer is removed. That grader is the instrument behind the pre-registered replay rule Task 4.8 acted on.

Two MEDIUM and seven LOW findings follow; two of the LOWs are new to this audit (an untrapped temp file in `model-adapter.sh`, and the uncross-checked `claude-headless` trust row raised by the companion voice). The one-way rule applies.

**Overall Risk Level:** HIGH

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 7 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 3.4/5 | IV:3 AZ:2 CI:4 IN:4 AV:4 |
| Architecture | 3.6/5 | MO:4 SC:4 RE:3 CX:3 ST:4 |
| Code Quality | 3.8/5 | RD:4 TC:4 EH:3 TS:4 DC:4 |
| DevOps | 3.4/5 | AU:4 OB:3 RC:3 AC:4 DS:3 |
| Blockchain | n/a | *(not applicable)* |
| **Overall** | **3.5/5** | *Security-weighted average; two HIGH findings set the risk level* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Implement gate allows App-Zone writes on a model-authored field behind a model-writable switch

**Severity:** HIGH | **Confidence:** high
**Component:** `head/.claude/hooks/compliance/implement-gate.sh:128` (allow at :126-130; selector at :113-116; non-App-Zone exit at :106-108)
**Criterion:** SEC-AZ: Authorization

**Reasoning Trace:**
> Traced the allow decision backwards. The input is `tool_input.active_skill` (:120), which the hook's own header calls model-authored: "The PreToolUse payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input is model-authored" (`implement-gate.sh:11-13`). The branch runs only when `compliance_mode == authoritative` (:119), set from `yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml"` (:115). `.loa.config.yaml` is a project-root path: this hook exits 0 for it ("Non-App-Zone writes always allowed", :106-108) and the registered PreToolUse Write/Edit hooks fence `.claude/` and `.run/`, not the project config. IG-7 (`head/tests/unit/implement-gate.bats:104`) demonstrates the allow with `opt_in()` writing exactly `implement_gate:\n  mode: authoritative` to `$ROOT/.loa.config.yaml` (:37); I ran the suite against the head tree, 11/11 pass, so the allow path is live.

**Description:** The quoted code:
```bash
case "$active_skill" in
    implement|/implement|bug|/bug|run|/run|simstim|/simstim)
        exit 0
        ;;
esac
```
**Impact:** C-PROC-001 names this hook as the mechanical fence ("implement-gate.sh fail-asks Write/Edit-tool App-Zone writes outside /implement//bug"). The fenced party can switch the fence off: (1) `Write .loa.config.yaml` with the two-line opt-in, allowed at :106-108; (2) `Write src/x.ts` with `"active_skill":"implement"` in `tool_input`, allowed at :128. The fixture `head/tests/fixtures/pretooluse-payloads/write-src-active-implement.json` is exactly payload (2). IG-11 (`implement-gate.bats:151-153`) asserts the key stays out of `docs/`, `README.md` and the example config, so operators cannot even learn the switch exists.
**Proof of Concept:**
```bash
printf 'implement_gate:\n  mode: authoritative\n' > .loa.config.yaml   # Write #1: exit 0 at :107
echo '{"tool_input":{"file_path":"src/index.ts","active_skill":"implement"}}' \
  | PROJECT_ROOT=$PWD RUN_DIR=$PWD/.run .claude/hooks/compliance/implement-gate.sh  # Write #2: silent allow
```
**Remediation:**
```bash
# Preferred (SIMPLICITY[delete]): remove :113-150 (mode read + authoritative branch),
# the "authoritative (opt-in; " label in detect-platform-features.sh:30-33,
# and CH-T8/CH-T9/IG-7/IG-8/IG-11. Keep the evidence recorder (:40-51).
# Alternative: select the mode only from a source the model cannot write
# (harness-launcher env var checked together with a System-Zone-owned marker),
# document it, and add a bats case proving an in-session .loa.config.yaml
# write does NOT select it.
```
**References:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html; OWASP A01:2021 — https://owasp.org/Top10/A01_2021-Broken_Access_Control/

### [HIGH-002] Recall grader credits uncited defects from the LOA-VERDICT trailer's JSON

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/graders/recall-vs-defects.sh:74` (regex :72-75; binding to `last` :84-85)
**Criterion:** SEC-IV: Input Validation (measurement integrity)

**Reasoning Trace:**
> The bare-`:N` alternative is `(?<![A-Za-z0-9_./:]):(?P<bare>…)(?![A-Za-z0-9])`. The lookbehind excludes word, path and colon characters only, so a `"` qualifies. The trailer `verdict-derive.sh` requires on every graded review contains `"critical":0,"high":1,"medium":0,"low":0,"excluded":0`; each `:0`/`:1` matches the bare form and :84-85 bind it to the most recent real path. Reproduced on the head script with `python3 -I`-free invocation of the script itself (manifest `{file: .claude/scripts/a.sh, anchor_line: 2}`):
> - body `` `head/.claude/scripts/a.sh:400` `` + standard trailer → `{"recall": 1.0, "detected": ["D-EARLY"], "citations": 6}`
> - same body, trailer line removed → `{"recall": 0.0, "missed": ["D-EARLY"], "citations": 1}`
> - base 1.0.0 grader, with trailer → `{"recall": 0.0, "citations": 1}`

**Description:** The quoted code:
```python
r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
```
**Impact:** `details.citations` is inflated on every graded review (RG-1's single citation reports 5), and recall is marked for any defect anchored in a cited file's first four lines without the review having cited it. This grader is the measurement behind the pre-registered replay A/B rule that Task 4.8 in this PR acted on (reverting the CLAUDE.loa.md trim), so the decision rests on a biased instrument. The RG-11..17 corpus never includes the trailer the harness always appends, which is why RG-14 passes.
**Proof of Concept:** see reasoning trace; the three commands and outputs are recorded in `SECURITY_ANALYSIS_TODO.md`.
**Remediation:**
```python
# Before
r'(?<![A-Za-z0-9_./:])):(?P<bare>…)'
# After: bare :N only after start-of-line, whitespace, a backtick or an open paren,
# and strip HTML comments first so the trailer can never be parsed as citations
text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
r'(?<=^|[\s`(]):(?P<bare>…)'
# Tests: body `a.sh:400` + trailer with a defect at anchor 2 → missed; RG-1 asserts citations == 1.
```
**References:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html; CWE-1288 Improper Validation of Consistency within Input — https://cwe.mitre.org/data/definitions/1288.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] 500-token output caps now target reasoning models, with the diagnostic discarded

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/scripts/flatline-learning-extractor.sh:317`; same shape `head/.claude/scripts/flatline-proposal-review.sh:75-76`, `head/.claude/scripts/flatline-validate-learning.sh:80-81`
**Description:** `call_flatline_chat "cheap" "$prompt" 30 500` now resolves to `claude-sonnet-5` (`head/.claude/defaults/model-config.yaml:1102`), an adaptive-thinking entry whose thinking tokens count against `max_tokens`; `reviewer`/`opus` resolve to gpt-5.5 and Opus 5.5. cheval's `max_tokens` WARN goes to stderr, which the shim discards, so extraction fails with exit 4 and no diagnostic. The previous targets (gpt-4o-mini, gpt-4o, claude-3-opus) had no reasoning budget.
**Impact:** Three scripts' failure envelope changes silently with the retarget.
**Remediation:** Raise `max_tokens` for these calls (≥ 4000) or pass a low effort; forward the WARN; add a mocked test that a `stop_reason: max_tokens` response is reported.

### [MED-002] No CHANGELOG entry for sprint-250 tasks 4.1–4.8 in the change set

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/README.md:12` (CHANGELOG link)
**Description:** The README links `CHANGELOG.md`; `pr/PR.md`'s last commit says it measured the CHANGELOG protocol figure; none of the 88 touched files is `CHANGELOG.md`. The implement-gate rework (security-relevant), grader 1.1.0, the permission grammar, the prompt-budget change and the `opus`/`cheap` retarget have no release-record entry here. The migration addendum (`head/docs/migration/v2.0-model-generation-floor.md:224-263`) documents the behaviour, so this is a release-record gap rather than an undocumented change, which is why it is not a documentation blocker.
**Impact:** `/loa` and the release pipeline read the CHANGELOG heading; the addendum alone is not the release record.
**Remediation:** Add the cycle-126 sprint-250 entries (one per task, security changes called out) or state in the PR description where the CHANGELOG edit landed.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Bare `rule_key` under errexit; unreachable base for exact requirements

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/scripts/check-permissions.sh:238` (base at :240)
**Description:** `rule_key "$perm"` is called bare under `set -euo pipefail`; the loaders at :216/:222 guard the same call with `|| continue`. The first non-`Bash(...)` requirement ever added aborts the preflight with no report. At :240 an exact requirement's base becomes `*=<word>`, which can never match. Latent today (every requirement is a `:*` wildcard). Companion voice DISS-C-004 raised the same point.
**Remediation:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }`; derive `base` only when `key` starts with `*`.

### [LOW-002] Migration doc overclaims permission-grammar parity

**Severity:** LOW | **Confidence:** medium
**Component:** `head/docs/migration/v2.0-model-generation-floor.md:258`
**Description:** "reads permission rules the way Claude Code does" overstates `rule_key` (`check-permissions.sh:162-173`), which models only a trailing `:*` or ` *`. `Bash(*)`/bare `Bash` (every command), `Bash(git*)` (space-less prefix) and mid-body `*` are read as exact or skipped, so a deny `Bash(git*)` passes preflight and then blocks every git command. CP-13 pins the narrower grammar.
**Remediation:** Soften the claim to the two forms modelled, or extend `rule_key`.

### [LOW-003] Catalog carries contradictory long-context pricing policy for the 5 family

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/defaults/model-config.yaml:562`
**Description:** `claude-opus-5` keeps a `long_context` tier (2.0×/1.5×, `verified: false`) while the new `claude-opus-5-5` entry (:470-509) cites the vendor's "4.6 and later … at standard pricing" to carry none. `test_anthropic_catalog_floor.py:326-350` pins both, so two tests assert opposite vendor policy and the ledger overstates Opus 5 spend past 200K.
**Remediation:** Record the contradiction and open the follow-up; do not leave two tests pinning opposite policies silently.

### [LOW-004] Recorder-first `platform-features.json` lacks the schema-2 keys; recorder runs before the zone check

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/scripts/detect-platform-features.sh:53` (recorder at `head/.claude/hooks/compliance/implement-gate.sh:40-51`)
**Description:** When the gate recorder creates the file first it has only the `active_skill_*` keys; the 1-hour cache early-exit skips `schema_version`, `detected_at`, `harness_signal`. The recorder also runs before the `file_path` check, so any lead-session Write/Edit payload carrying `active_skill` triggers a model-timed write into `.run/` (fixed content, no injection; companion voice DISS-C-005). No consumer reads the missing keys today.
**Remediation:** Have the recorder write the full schema-2 shape (or skip the cache exit when `schema_version` is absent) and move it after the zone check.

### [LOW-005] Prompt budget raised to exactly fit

**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/loa/CLAUDE.loa.md:1`
**Description:** The file is 10,225 B (`wc -c`) against the budget raised to 10,240 B in `head/tools/check-prompt-budget.sh:53`; 15 bytes of headroom. The next `constraints.json` rationale edit re-renders into this file and breaks PB-4.
**Remediation:** Give the budget stated headroom or trim a non-generated line.

### [LOW-006] Untrapped temp file holding cheval's full stderr; silent abort when `mktemp` fails *(new)*

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/scripts/model-adapter.sh:656` (:656-659)
**Description:** New in this PR (base used `2>/dev/null`):
```bash
err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX")"
result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>"$err_file") || exit_code=$?
grep -F -- 'gemini-headless dispatches agy' "$err_file" | cut -c1-600 >&2 || :
rm -f -- "$err_file"
```
The script runs under `set -euo pipefail` with no EXIT/INT trap. A failed `mktemp` (unwritable `TMPDIR`) aborts before the `error` line at :662, so the caller gets a bare non-zero exit. A signal or errexit between :656 and :659 leaves the file, which holds cheval's complete stderr (provider error bodies, request ids, the full agy WARN), in a shared `TMPDIR`. The forwarded line itself is the fixed message at `agy_headless_adapter.py:161` and carries no prompt text.
**Remediation:** `trap 'rm -f -- "$err_file"' EXIT` after `mktemp`, or filter through a process substitution instead of a file; wrap `mktemp` with `|| { error "…"; exit 1; }`.
**References:** CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html; CWE-377 Insecure Temporary File — https://cwe.mitre.org/data/definitions/377.html

### [LOW-007] `claude-headless` trust row is not cross-checked against the catalog's tool grant *(new; from companion voice DISS-C-003)*

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/data/model-permissions.yaml:446` (row :446-471; note at :469)
**Description:** The row declares `execution_mode: remote_model`, `command_execution: false`, `file_write: false` for a `kind: cli` hop, and its own note says `extra.allowed_tools` widens what the CLI can do. Verified on the head catalog: `extra` is `{cli_model: fable}` with no `allowed_tools`, so the row is accurate today. The new `test_trust_scopes.py` tests (:349-372) check row presence and 4.7 parity only; nothing ties the row to the catalog's grant, so a later `allowed_tools` edit leaves the registry asserting a side-effect-free oracle.
**Remediation:** Assert in `test_trust_scopes.py` that `providers.anthropic.models.claude-headless.extra.allowed_tools` is empty or absent while the row claims `command_execution: false` and `file_write: false`.
**References:** CWE-1220 Insufficient Granularity of Access Control — https://cwe.mitre.org/data/definitions/1220.html

---

## Observations (not tallied)

- `hook-guard.sh:47-49` fails OPEN on a hook that fails `bash -n` (companion voice DISS-C-002). The posture pre-dates this PR, which changes only the WARN text to cover SessionStart hooks; not a defect introduced here. Worth a separate decision: fail-ask for PreToolUse fences, fail-open for SessionStart.
- `detect-platform-features.sh:35-36` prints `.run/platform-features.json` content (model-writable) into the `/loa` status line; the `tr -d '[:cntrl:]' | cut -c1-120` sanitisation is adequate. Positive.
- `validate-skill-capabilities.sh:110-117` filters agent-type names with `^[A-Za-z0-9_-]+$` and falls back to `general-purpose` on any parse failure. Positive.
- `lib-content.sh:166,246` canonical-decimal index guard and :295 control-byte strip are correct and pinned by CMP-277/278. Positive.

---

## Security Dissenter Analysis (Phase 1C)

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `type: audit`, primary `gpt-5.5-pro` `status: clean` (0 findings), companion `claude-headless` `status: succeeded`, `counted_as: independent_voice`, 5 findings; `degraded: false`; `metadata.locality` null (no DEGRADED_SECURITY_REVIEW). Companion findings are advisory input and were triaged, not tallied:

- DISS-C-001 (MEDIUM, implement-gate authoritative selector in `.loa.config.yaml`) — **confirmed**, same path as HIGH-001; the companion's severity is advisory, mine stands at HIGH per the two-Write exploit.
- DISS-C-002 (LOW, hook-guard fail-open) — **not introduced by this PR**; Observations.
- DISS-C-003 (LOW, claude-headless row vs catalog `allowed_tools`) — **confirmed as a missing cross-check**; tallied as LOW-007 after verifying the head catalog grants no tools today.
- DISS-C-004 (LOW, bare `rule_key` under errexit) — **confirmed**; LOW-001.
- DISS-C-005 (LOW, recorder runs before the zone check and rewrites `active_skill_available`) — **confirmed as shape**, no consumer impact (`active_skill_available` is always false in schema 2); folded into LOW-004.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty (`rejected_count: 0`) and `metadata.rejected_sidecars` lists no sidecar.

---

## Review-demotion check

The review trailer carries `excluded: 0`; there are no demoted HIGHs to confirm or re-tally. `excluded_confirmed: 0`.

---

## Documentation Audit

No `documentation-coherence-task-*.md` reports exist in this frozen snapshot; verified manually.

| Check | Result |
|-------|--------|
| Security-critical code commented | Pass — `implement-gate.sh:1-30` header, `detect-platform-features.sh:1-22`, `check-permissions.sh:15-27` grammar comment |
| CHANGELOG covers security changes | Gap — no CHANGELOG in the change set (MED-002); behaviour documented in the migration addendum |
| Secrets / internal URLs in docs or comments | Pass — only public vendor and docs URLs; dissent secret scan: none in the diff |
| Auth changes documented | Partial — `model-permissions.yaml` rows carry notes; the implement-gate opt-in is deliberately undocumented (IG-11), folded into HIGH-001 |
| API/CLI docs match behaviour | Pass — `cheval --help` text matches the FR-1.3 default (c124-1.4-3b); `model-adapter.sh --help` names the current generation (MA-3) |
| Doc claims match code | Gap — LOW-002 grammar overclaim |

---

## Security Checklist Status

- [x] No hardcoded secrets or credentials
- [ ] Input validation at trust boundaries — HIGH-001 (model-authored field in a security decision), HIGH-002 (trailer parsed as citations)
- [x] Authorization — new model-permissions rows all-`none` side-effect scopes; parity test re-run logic verified
- [x] No injection vectors introduced — `jq --arg/--argjson` for every JSON write; mktemp+mv atomic writes; `rule_key` pure parameter expansion
- [x] Error messages do not leak sensitive data — forwarded cheval line is a fixed message; LOW-006 covers the temp file
- [x] Dependencies pinned — no dependency changes

---

## Threat Model Summary

**Trust Boundaries:**
- Governed model ↔ PreToolUse hooks (stdin `tool_input`, project-root config, `.run/` state)
- Evaluated agent ↔ eval grader (review text)
- Operator ↔ `.claude/` System Zone and `settings*.json`

**Attack Vectors:**
- Self-authorised App-Zone write via config opt-in + forged `active_skill`: HIGH
- Recall inflation via the mandated trailer: HIGH (measurement integrity)
- Model-timed rewrite of `.run/platform-features.json`: LOW (fixed content)

**Mitigations present:** `.run/` no longer selects the gate mode (IG-5, CH-T10); evidence line sanitised; atomic writes; allowlist-filtered YAML reads.

**Residual Risks:** the authoritative branch exists with no legitimate input by the PR's own analysis; the grader corpus lacks the production trailer shape.

---

## Positive Findings

- Red-first tests for every residue fix (RES-1..7, IDR-1..4, IG-1..11, CP-11..13, MA-1..6, LFF-1..2, CMP-277/278) with fixtures mirroring the documented PreToolUse payload shapes.
- Generated artifacts and checksums consistent with their sources; the catalog entry carries a dated vendor citation and a `loa:shortcut:` marker with an upgrade trigger.
- `.run/`-forgery hardening of the gate and the single-writer, atomic evidence recorder are correct as far as they go.
- `validate-artifact.sh` here-string change removes a real SIGPIPE false negative under `pipefail` (bd-8ndx test reproduces it).

---

## Recommendations

### Immediate Actions (24 Hours)
1. Remove (or operator-fence and document) the implement-gate authoritative branch; add a bats case proving an in-session `.loa.config.yaml` write cannot select it (HIGH-001).
2. Fix the bare-`:N` alternative and strip HTML comments in `recall-vs-defects.sh`; add trailer-bearing RG tests; re-run the replay A/B corpus to confirm Task 4.8's decision stands (HIGH-002).

### Short-Term Actions (1 Week)
1. Raise the three 500/300-token caps or lower effort, and surface cheval's WARN (MED-001).
2. Land the CHANGELOG entries (MED-002); guard `rule_key` (LOW-001); add the `claude-headless` cross-check (LOW-007); trap the temp file (LOW-006).

### Long-Term Actions (1 Month)
1. Resolve the opus-5 vs opus-5-5 long-context policy (LOW-003); give the prompt budget stated headroom (LOW-005); align the permission-grammar doc with the code or vice versa (LOW-002).

---

## Verdict

**CHANGES_REQUIRED**

Two HIGH findings, each reproduced on the head tree; the one-way rule forces the verdict.

**Next Steps:**
1. Address HIGH-001 and HIGH-002 as above; re-request `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.
2. Address the MEDIUM/LOW items you accept and update `grimoires/loa/a2a/sprint-1/reviewer.md`.

---

**Audit Completed:** 2026-10-21T23:45:00Z
**Next Audit Recommended:** on the re-submitted sprint
**Remediation Tracking:** `grimoires/loa/a2a/audits/2026-10-21/`

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:45:00Z"} -->
