# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` — cycle-126 sprint-250 tasks 4.1–4.8, 88 files (base → head), cited as `head/<path>:<line>` with lines from `pr/head/`

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The change retargets the `opus` and `cheap` aliases to the new generation (`claude-opus-5-5`, `claude-sonnet-5`), adds a `model-permissions.yaml` row for every served Anthropic id, rewrites the implement-gate mode detection (heuristic default, lead-session evidence recorder, config opt-in for the authoritative branch), introduces a second permission-rule grammar in `check-permissions.sh`, hardens `lib-content.sh` (canonical-decimal index guard, control-byte stripping on stderr), extends the eval recall grader to 1.1.0, reverts the Sprint 3 instruction diet, and ships ~30 red-first bats/pytest changes.

Security posture: no critical or high finding. The two security-relevant surfaces this PR touches both move in the safe direction relative to base. The implement gate no longer lets model-writable `.run/` state select the authoritative mode (pinned by IG-5), and the permission checker reads rules as JSON arrays and emits its report through `jq --arg`/`jq -R`, so operator rule text cannot break the JSON. What remains is one residual authorization weakness that the PR inherits rather than introduces (the authoritative opt-in trusts a model-authored field, CWE-807), one data-integrity defect in the eval grader (the review's verdict-trailer JSON is parsed as line citations, inflating detection credit), and nine low-severity items. The cross-model security dissent ran with two independent voices and completed clean (not degraded); its two MEDIUMs are triaged below, one confirmed as MED-001 and one downgraded to LOW-002 with rationale.

**What I verified (code, not the report):**
- `marker-utils.sh verify-hash` on head `.claude/loa/CLAUDE.loa.md` → VALID (`99948d56…`), and on base → VALID (`ad303e10…`): the managed-file header was regenerated correctly. Head file is 10,225 B.
- FR-1.3 non-Anthropic output default already lives in head `base.py:170` (`_NON_ANTHROPIC_DEFAULT_OUTPUT_CAP = 16_000`); the `cheval --help` and `c124-1.4-3` changes describe existing behaviour rather than add it.
- The `claude-headless` registry note matches the adapter: `claude -p` runs with `--permission-mode plan` and `--tools ""`, and `extra.allowed_tools` rebuilds the tools flag (adapter read from the workspace install; the PR snapshot does not carry it).
- Grader defect reproduced with the head regex: one real citation plus a verdict trailer plus `port :8080` → 7 citations, with phantom lines 0–3 and 8080 bound to the cited file.
- bats on an executable copy of `pr/head`: `implement-gate.bats` 11/11, `check-permissions.bats` 13/13, `compliance-hook.bats` 14/14, `hook-guard.bats` 6/8 (the two failures need `block-destructive-bash.sh`, outside the snapshot), `model-adapter.bats` 2/6 (the four failures need `.claude/scripts/lib/model-resolver.sh`, outside the snapshot). Not reproducible here: the pytest suites (adapter package outside the snapshot).
- Working file with the source/sink trace: `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`; machine-readable findings: `grimoires/loa/a2a/audits/2026-10-22/findings.jsonl`.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 9 |

Excluded (speculative, low-confidence high findings): 0. The review trailer excluded 0 findings; confirmed independently (`excluded_confirmed`: 0).

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.2/5 | IV:4 AZ:4 CI:5 IN:5 AV:3 |
| Architecture | 4.2/5 | MO:4 SC:4 RE:4 CX:4 ST:5 |
| Code Quality | 4.0/5 | RD:4 TC:4 EH:4 TS:5 DC:3 |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 AC:4 DS:4 |
| Blockchain | n/a | not applicable |
| **Overall** | **4.1/5** | weighted (Security ×2) |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] Authoritative opt-in trusts the model-authored `tool_input.active_skill`, and the opt-in file is not fenced

- **Severity:** MEDIUM | **Confidence:** high | **Criterion:** SEC-AZ (authorization)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:115` (mode read), `:128-129` (silent allow), `:124` (field read)
- **Issue:** With `implement_gate.mode: authoritative` in `.loa.config.yaml`, the gate reads `tool_input.active_skill` — which the file's own header (`:11-12`) states is model-authored — and `exit 0`s on `implement|bug|run|simstim`:
  ```bash
  configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""   # :115
  active_skill=$(echo "$input" | jq -r '.tool_input.active_skill // empty' 2>/dev/null) || active_skill=""         # :124
  implement|/implement|bug|/bug|run|/run|simstim|/simstim)
      exit 0                                                                                                    # :128-129
  ```
  No Write/Edit hook in the head revision fences `.loa.config.yaml` (`zone-write-guard.sh` and `implement-gate.sh` treat it as a non-App-Zone path), so a model needs two silent Write calls — one adding the opt-in key, one carrying `"active_skill":"implement"` — to remove the fail-ask on any App Zone file. `tests/fixtures/pretooluse-payloads/expected.tsv:8` documents the resulting `allow`.
- **Impact:** The C-PROC-001 fence (fail-ask on ungated App Zone writes) can be bypassed without a prompt once the key is set. Blast radius is bounded: the fence is advisory (`ask`, not block); the Bash-path gap is already an accepted fence gap; the key is undocumented and IG-11 pins it undocumented; and this is **not a regression** — in base the same branch was selected by `.run/platform-features.json` and `.run/.compliance-mode`, both model-writable State Zone files, so head is strictly harder to flip (IG-5 pins that `.run/` can no longer select the mode).
- **Fix:** Either delete the authoritative branch until a harness-set signal exists, or make the opt-in inert unless `.run/platform-features.json` carries `harness_signal: true` (which `detect-platform-features.sh:63-66` never writes today), and add `.loa.config.yaml` to the zone-write guard's ask list so the enabling edit is itself visible. A one-line stderr WARN when the opt-in is active would also keep the operator honest.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; OWASP A01:2021 Broken Access Control — https://owasp.org/Top10/A01_2021-Broken_Access_Control/
- Confirmed by cross-model review (DISS-C-001, MEDIUM) and by the review gate (Observation 3).

### [MED-002] Eval grader: verdict-trailer JSON and prose `:N` tokens are credited as line citations

- **Severity:** MEDIUM | **Confidence:** high | **Criterion:** CQ-EH / data integrity (eval measurement)
- **File:** `head/evals/graders/recall-vs-defects.sh:74` (bare alternative), `:92-93` (binding to `last`), `:100-103` (detection credit)
- **Issue:** The second `CITE` alternative matches any `:N` whose preceding character is outside `[A-Za-z0-9_./:]` and whose following character is not alphanumeric:
  ```python
  r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])'   # :74
  ```
  In the review's own verdict-trailer comment, `"critical":1`, `"high":2`, `"medium":0`, `"low":3`, `"excluded":0` each satisfy it (preceding `"`, following `,` or `}`), and so does prose like `port :8080`. All bind to the most recent cited path (`:92-93`). Reproduced with the head regex: a review with exactly one citation reports `citations: 7`, with phantom lines 0, 1, 2, 3 and 8080 attached to the cited file.
- **Impact:** A manifest defect whose anchor is ≤ 3 in the last-cited file is marked detected regardless of review content; the `citations` detail is inflated for every graded review that ends with a trailer (all of them, by the review template). Task 4.8's pre-registered replay A/B rule reads these figures, so the eval that decides instruction-diet reverts is measuring a biased parser. No current `pr-x` fixture anchor is ≤ 3, which is why RG-11..17 stay green.
- **Fix:** Strip HTML comments (the trailer) from `text` before scanning, and tighten the bare form to code-fenced or whitespace-preceded tokens not followed by `,`/`}` inside a JSON object — or restrict it to `head:N` / `base:N`. Add an RG case with a trailer and an `anchor_line: 1` fixture so the phantom hit is pinned red.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html
- Confirmed by the review gate (Observation 1); the cross-model security dissent did not raise it.

### [LOW-001] Permission checker: universal `Bash` / `Bash(*)` rules are not recognised; the migration doc overclaims parity

- **Severity:** LOW | **Confidence:** high | **Criterion:** SEC-IV
- **File:** `head/.claude/scripts/check-permissions.sh:164` (`[[ "$b" == "Bash("*")" ]] || return 1`), `:171` (exact key for `Bash(*)` → `=*`); `head/docs/migration/v2.0-model-generation-floor.md:258`
- **Issue:** A bare `Bash` rule returns 1 from `rule_key` and `Bash(*)` becomes the exact key `=*`; neither covers a required `Bash(git push:*)`. An allow-all config is reported as all 16 requirements missing (preflight refuses to start); a deny-all `Bash` is ignored and the checker reports every permission effective while the harness denies each command. Pre-existing in base (`base_pattern_of` never matched bare `Bash` either). Rated LOW rather than MEDIUM because neither direction weakens a control: the ignored deny fails safe at the first Bash call, the ignored allow is an availability false-negative. The new sentence "reads permission rules the way Claude Code does" at `:258` is the part this PR introduces.
- **Fix:** Treat `Bash` and `Bash(*)` as a universal wildcard key for allow and deny, add CP cases for both, or soften the doc sentence to the two trailing-wildcard forms the grammar covers.
- **Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html
- Confirmed by cross-model review (DISS-C-003 names the dropped-rule class) and the review gate (Observation 2, rated MEDIUM there).

### [LOW-002] `claude-headless` registry row is static while the hop's capability is config-dependent

- **Severity:** LOW | **Confidence:** medium | **Criterion:** SEC-AZ
- **File:** `head/.claude/data/model-permissions.yaml:446-471` (row), `:469-470` (the `extra.allowed_tools` caveat); `head/.claude/defaults/model-config.yaml:364,432,488,528,587,625,689,736,791,831,866` (every Anthropic fallback chain ends in `anthropic:claude-headless`)
- **Issue:** The row declares `execution_mode: remote_model` with `file_read/file_write/command_execution/network_access: false`, which is true for the adapter default (`--tools ""`, `--permission-mode plan`) but not after an operator sets `extra.allowed_tools`; the row admits this only in prose. Because every Anthropic HTTP chain terminates in this local `claude -p` hop, an HTTP outage routes review/red-team/flatline traffic onto a subprocess whose effective tool surface the registry does not verify. The row is new in this PR and is an improvement over base (no row at all); the registry has no runtime effect unless `hounfour.feature_flags.context_filtering` is on.
- **Fix:** Add a validator check that fails when the catalog's `claude-headless.extra.allowed_tools` is non-empty while the registry row says `command_execution: false` / `file_write: false`, so the two cannot drift silently.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html
- From cross-model review (DISS-C-002, rated MEDIUM there; downgraded here for the reasons above).

### [LOW-003] `model-adapter.sh` stderr capture: `mktemp` under `set -e`, temp file not trap-cleaned

- **Severity:** LOW | **Confidence:** medium | **Criterion:** SEC-AV / CQ-EH
- **File:** `head/.claude/scripts/model-adapter.sh:656-659` (`set -euo pipefail` at `:33`)
- **Issue:** `err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX")"` aborts the shim before the model call when `$TMPDIR` is unwritable or full, where base ran with stderr discarded. The file (which can hold provider error bodies) is removed only on the straight-line path (`:659`); a signal between `:656` and `:659` leaves it in `/tmp` (0600, so exposure is limited to the same account).
- **Fix:** `|| err_file=/dev/null` with a one-line WARN, and `trap 'rm -f -- "$err_file"' RETURN` (or EXIT) so a temp-dir hiccup degrades to the old behaviour and nothing lingers.
- **Reference:** CWE-459 Incomplete Cleanup — https://cwe.mitre.org/data/definitions/459.html
- Confirmed by the review gate (Observation 7).

### [LOW-004] Gate echoes raw model-authored fields to stderr

- **Severity:** LOW | **Confidence:** medium | **Criterion:** SEC-IV (output neutralization)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:134` (`'$file_path' … /$active_skill`)
- **Issue:** The `[AUTHORITATIVE]` line prints `$active_skill` and `$file_path` unfiltered, so a payload carrying ESC sequences or carriage returns reaches the hook's stderr (surfaced in the harness transcript / debug output) raw. The sibling `detect-platform-features.sh:33` strips controls (`tr -d '[:cntrl:]' | cut -c1-120`) before printing evidence; the gate does not. Pre-existing pattern (the heuristic branch's `[ADVISORY]` line did the same in base); the JSON `reason` strings are constant, so the decision channel is unaffected.
- **Fix:** Pass both through the same `tr -d '[:cntrl:]' | cut -c1-200` before echoing.
- **Reference:** CWE-117 Improper Output Neutralization for Logs — https://cwe.mitre.org/data/definitions/117.html

### [LOW-005] Catalog encodes two readings of one vendor pricing fact

- **Severity:** LOW | **Confidence:** medium | **Criterion:** ARCH-ST / DevOps-AC
- **File:** `head/.claude/defaults/model-config.yaml:470-478` (5.5: no `long_context`, citing "4.6 and later … at standard pricing") vs `:408`, `:465`, `:562`, `:772` (fable-5-1, fable-5, opus-5, sonnet-5 keep a 2.0×/1.5× `long_context` tier, `verified: false`)
- **Issue:** `test_opus_5_5_has_the_1m_window_at_standard_pricing` and `test_five_family_declares_the_beta_header_list_and_the_long_context_tier` (`head/.claude/adapters/tests/test_anthropic_catalog_floor.py:277`, `:343`) lock both readings in. No runtime effect today: every probed ceiling is 180,000, under the 200,000 tier threshold.
- **Fix:** Pick one reading for the 4.6+ generation (or record which vendor page each entry follows) before any ceiling is calibrated above 200K.
- Confirmed by the review gate (Observation 4) and cross-model review (DISS-C-003 of the review round).

### [LOW-006] `rule_key` failure modes for requirement shapes not in today's list

- **Severity:** LOW (speculative) | **Confidence:** low | **Criterion:** CQ-EH
- **File:** `head/.claude/scripts/check-permissions.sh:235` (`rule_key "$perm"` with no `|| …` under `set -euo pipefail`), `:237` (`base="*${key#\*}"` keeps the `=` sentinel for an exact requirement)
- **Issue:** A future non-`Bash(...)` required rule aborts the preflight with exit 1 and no "missing" report; an exact-form requirement derives a base `*=cmd` that never matches. Every current requirement is `Bash(<cmd>:*)`, so nothing fails today.
- **Fix:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` and derive `base` from `${key#[*=]}`.
- Confirmed by cross-model review (DISS-C-003) and the review gate (Observation 6).

### [LOW-007] Evidence recorder runs before the `file_path` short-circuit

- **Severity:** LOW | **Confidence:** high | **Criterion:** SEC-AV (hot-path cost)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:40-48`
- **Issue:** Up to three `jq` processes (plus `yq` later for App Zone paths) run on every Write/Edit, including non-App-Zone writes, before the empty-`file_path` check at `:55`. Harmless at current latencies; noted because PreToolUse hooks sit on the hot path and the recorder fires on every tool call for the life of the session once `.run/` exists.
- **Fix:** Short-circuit on `[[ "$input" == *active_skill* ]]` before invoking `jq`, or move the recorder after the `is_app_zone` decision.
- Confirmed by the review gate (Observation 9).

### [LOW-008] Prompt budget raised to exactly fit

- **Severity:** LOW | **Confidence:** high | **Criterion:** DevOps-RC
- **File:** `head/tools/check-prompt-budget.sh:53` (`LOA_LIMIT` 9,216 → 10,240); head `CLAUDE.loa.md` is 10,225 B
- **Issue:** 15 bytes of headroom; the next one-word rationale edit in `constraints.json` trips PB-9 / the CI gate and invites another bump.
- **Fix:** Leave ≥ 5 % headroom or state in the script header why 10,240 is the principled ceiling.
- Confirmed by the review gate (Observation 5) and cross-model review (DISS-C-006 of the review round).

### [LOW-009] SIMPLICITY[shrink]: eleven verbatim 25-line scope blocks

- **Severity:** LOW | **Confidence:** high | **Criterion:** CQ-RD
- **File:** `head/.claude/data/model-permissions.yaml:207-471`
- **Issue:** The eleven new rows repeat the 4.7 `trust_scopes`/`capabilities` block byte for byte ("Scopes copied from the 4.7 entry"). `test_current_generation_rows_mirror_the_4_7_scopes` already asserts equality, so a YAML anchor on the 4.7 block expresses the invariant the test checks and removes ~200 lines; `yaml.safe_load` and `yq` both resolve anchors.
- **Fix:** `&remote_review_scopes` on the 4.7 row, `<<: *remote_review_scopes` on the rest. `net: -200 lines possible`.
- Confirmed by the review gate (Observation 8).

---

## Observations (not tallied)

- **Borrowed `probed_ceiling` provenance** (`head/.claude/defaults/model-config.yaml:491-493`): the 180,000 bound is Opus 5's measurement reused for 5.5 and is marked `loa:shortcut:` with the upgrade trigger (`tools/ceiling-probe-live.py --write-catalog`), `source: conservative_default`, `calibrated_at: null`. An acknowledged shortcut with a trigger, not a defect; a lower real bound fails at the provider and names the probe command.
- **Non-Anthropic default output budget 4,096 → 16,000** (`head/.claude/adapters/cheval.py:2931-2937`): a cost-exposure change, but it was implemented in an earlier cycle-126 sprint (head `base.py:166-170`); this PR only updates the help text and the stale test. Not introduced here.
- **Grammar parity with Claude Code**: [ASSUMPTION] the equivalence of `Bash(git push *)` and `Bash(git push:*)` is asserted by the PR (`check-permissions.sh:159-167`, migration doc `:258-263`) and not verifiable offline here. Unable to assess against the harness; recorded as a scope limit.
- **Permission report with a tab inside a deny rule** (`check-permissions.sh:240`, `:267`): `denied_lines` is tab-joined and split with `jq -R 'split("\t")'`, so a rule containing a literal tab shifts the `by`/`file` fields in the JSON report. Operator-authored, cosmetic.

---

## Cross-Model Security Observations

Two voices ran on `pr/head.diff` (`grimoires/loa/a2a/sprint-1/adversarial-audit.json`: `metadata.status: clean`, primary `gpt-5.5-pro` answered by `codex-headless` with no findings, companion `claude-headless` `counted_as: independent_voice`, `voices_succeeded: 2/2`, `degraded: false`, no `locality.degraded_security_review`). The security review is **not** degraded. Triage of each companion finding:

- **DISS-C-001 (MEDIUM)** — authoritative mode trusts model-authored `active_skill` once the config key is set. Real; counted as MED-001 (Confirmed by cross-model review).
- **DISS-C-002 (MEDIUM)** — `claude-headless` row declares no capabilities while `extra.allowed_tools` can widen the local `claude -p` hop, and every HTTP chain ends there. Real as a registry-coherence gap; downgraded to LOW-002 because the adapter default is tool-less and plan-mode, the row is new (base had none), and the registry is inert without `context_filtering`.
- **DISS-C-003 (LOW)** — `rule_key` drops non-Bash rules, aborts under `set -e` on a non-Bash requirement, and assumes space/colon wildcard equivalence. Real but hypothetical today; counted as LOW-006, with the parity assumption recorded under Observations.
- **DISS-C-004 (LOW)** — 4× default output budget for non-Anthropic providers. Not a defect of this change: the code predates the PR (`base.py:170`); recorded under Observations.
- **DISS-C-005 (LOW)** — borrowed `probed_ceiling` provenance, and "the escalated full-file test module expects 5.5 to be calibrated with probed_headless provenance". First clause: acknowledged `loa:shortcut`, Observations. Second clause: not a defect — the companion read this workspace's later-revision `test_anthropic_catalog_floor.py`, not `pr/head`'s, which asserts `source == "conservative_default"` and `calibrated_at is None` (`head/.claude/adapters/tests/test_anthropic_catalog_floor.py:343-350`), consistent with the catalog.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and the canonical sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-audit-companion.jsonl` has 0 rows.

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist for this sprint; coherence was verified manually. The security-relevant change (implement-gate mode detection) is documented in `head/docs/migration/v2.0-model-generation-floor.md:251-257` and the gate's header (`implement-gate.sh:8-15`); the opt-in key is deliberately undocumented and pinned so by IG-11. No CHANGELOG file is in the diff — this repository generates it post-merge (`generate-changelog.sh` via `post-merge-orchestrator.sh`), so that is not a gap. No secrets or internal URLs in the diff (payload fixtures carry synthetic ids and a synthetic `/home/op/...` transcript path; the dissent's secret scan applied one redaction to its own prompt copy, not to the repo). Red flag noted: the migration doc's parity claim at `:258` (LOW-001).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (fixtures synthetic; catalog carries pricing, no keys)
- [x] Input validation on new entry points (`lib-content.sh` canonical-decimal guard and control-byte stripping; `check-permissions.sh` rules read as JSON arrays and reported via `jq --arg`; `validate-skill-capabilities.sh` agent-type key allowlist; v3 schema `beta_headers` pattern never looser than the adapter regex)
- [x] Authentication/authorization — with the MED-001 caveat on the undocumented authoritative opt-in (CWE-807); default heuristic posture unchanged and strictly harder to flip than base
- [x] No SQL/XSS injection vulnerabilities (not applicable)
- [x] Error handling doesn't leak info (`model-adapter.sh` forwards only the agy argv WARN, cut to 600 bytes; LOW-003 on cleanup)
- [x] Tests cover security paths (IG-1..11 incl. IG-5 forged-payload case, CP-11..13 fuzz table, CMP-277/278, V3-add refusals)

---

## Next Steps

**APPROVED:**
1. Sprint is cleared; merge may proceed.
2. Carry MED-001 and MED-002 into the next sprint as beads: gate the authoritative opt-in on a harness signal (or delete the branch) and fence `.loa.config.yaml`; strip the verdict-trailer comment before the grader scans citations and add the `anchor_line: 1` red case.
3. Fold LOW-001/006 (universal `Bash` rule, `rule_key` under `set -e`) into the same permission-checker follow-up.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":9},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T01:28:05Z"} -->
