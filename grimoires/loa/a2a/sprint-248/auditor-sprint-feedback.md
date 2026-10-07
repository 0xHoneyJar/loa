# Sprint 2 Security Audit Feedback (cycle-126, global sprint 248)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, `/audit-sprint sprint-2`)
**Date:** 2026-10-05
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 2 "Two voices, nothing dropped" (FR-2, SDD §1.3 D-2.1 … D-2.4)
**Implementation Report:** grimoires/loa/a2a/sprint-248/reviewer.md (rounds 1a … 1ap)
**Tree audited:** `feature/cycle-126-full-size` at `51d7a1ff` (round 1ap); cycle base `2079e719`
**Prerequisites:** `engineer-feedback.md` opens with "All good" and its trailer reads `review APPROVED 0/0/1/3, excluded 0`; `adversarial-audit.json` parses and carries `metadata.type: audit`, `metadata.model: gpt-5.5-pro`, `metadata.head: 9fabac05`, 24 `merged_from_chunks`, 92 findings, `verdict_quality.voices_succeeded_ids: [codex-headless, claude-headless]`, `rejected_summary []`, `rejected_sidecars []`. The guardrail pre-check (`guardrails-orchestrator.sh --skill auditing-security --mode interactive --file …`) proceeded; `security-audit-scope.sh` ran (whole-repo categorisation, not sprint-specific).

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Sprint 2 adds a second, cross-family dissent voice, a tolerant finding normaliser with a rejected-payload summary, the `## Rejected dissent payloads` contract in `verdict-derive.sh`, and the repair-model rule; the review rounds hardened the run lock, the reaper, the fold, the headless adapters' private workspaces and the test helpers. I read the code on the four main surfaces (`adversarial-review.sh`, `lib-content.sh`, `verdict-derive.sh`, `kf-write-lib.sh`), the adapters (`headless_cli.py`, `agy_headless_adapter.py`, `claude_headless_adapter.py`, `codex_headless_adapter.py`, `providers/__init__.py`), the Bridgebuilder key gate (`resources/config.ts`), the config example, the CHANGELOG and the tests — not the report alone — and I ran the round-1ap cases here (CMP-274/275/276, NRM-66/67, the kf-write-lib U+2028 case, the verdict-derive isolation case: 7/7 green; `test_headless_workspace.py` + `test_agy_headless_adapter.py`: 59 passed, 1 skipped) plus my own variant probes under `~/.cache/loa/cycle-126-dissent/`. The tree is clean after the probes.

The cross-model audit dissent (run 1 on `9fabac05`, 92 findings: 3 HIGH, 33 MEDIUM, 56 LOW, all 24 chunks two-voice, no rejected payload) was **not re-run** (per-sprint cap, real cost). I checked its triage (`audit-dissent-triage-run-1.md`) finding by finding against the code: the two fixes the lead flagged are complete (§ "Dissent triage, checked" below), none of the 19 REFUTED / 24 REPEAT / 37 DECLINE verdicts is wrong on my reading, and the three dissent HIGHs resolve to one fixed defect (the stable-workspace denylist), one pre-existing MEDIUM carried on bead `bd-ugmi` (agy's argv prompt) and one repeat of it.

No critical or high finding is open. The one medium is the pre-existing agy argv exposure, which I judge **non-blocking for this sprint** (reasoning in § "The agy argv question"). The lows are a mitigation with no operator-facing sink, two defence-in-depth gaps in `lib-content.sh` with no reach from a `--diff-range` dissent, and one record-hygiene note on the merged envelope.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 4 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] `gemini-headless` dispatches `agy -p <whole prompt>` on argv — the redacted review diff is readable by every local account for the life of the hop (pre-existing on main; tracked `bd-ugmi`)
- **Severity:** MEDIUM · **Confidence:** high (mechanism certain; reach conditional)
- **File:** `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:285-321` (`_build_command`: `[agy, "-p", prompt, "--model", …, "--sandbox", "--dangerously-skip-permissions"]`); `.claude/adapters/loa_cheval/providers/__init__.py:55` (`"gemini-headless": AgyHeadlessAdapter`)
- **Issue:** Every stock Google chain ends in the `gemini-headless` CLI terminal, and that class is `AgyHeadlessAdapter`, whose only prompt transport is argv. On a host with `agy` installed and a Google chain configured (Flatline tertiary, `deep-thinker`, or an operator `companion_chain`), a co-tenant account reads the prompt — the redacted diff plus the system prompt — through `/proc/<pid>/cmdline` or `ps` for the hop's duration, unless `/proc` is mounted `hidepid`. The earlier review-round refutations rested on "agy is disabled", which the dissent's g5 group showed false; round 1ap corrected the comments, the config example (`.loa.config.yaml.example:829-840` now names the exposure and says "Avoid it on a shared host") and added a once-per-process WARN.
- **Why not higher, and why not blocking here:** the transport predates this cycle (`a67a1a98`, on main); Sprint 2 neither added nor widened it — the companion voice plans only the Anthropic or OpenAI chain (`_companion_chain`), so the sprint's own feature never reaches agy by default; this repository's config has no Google rung enabled and no `agy` on PATH; the data is the redacted diff (secret scanning runs before dispatch), not a credential; and the exposure is now documented where an operator configures it. It is an information-disclosure to a local co-tenant — CWE-214 — not a code-execution or credential path.
- **Fix:** land `bd-ugmi`: either prove `agy -p` reads the prompt from stdin (the adapter's `communicate()` path already keeps stdin closed only for the permission prompt) or gate the argv transport behind an explicit model-entry opt-in (`extra.allow_argv_prompt: true`) that raises a walkable `ProviderUnavailableError` otherwise. Do this before 2.0.0 GA — the rc soak is where shared-host operators show up.
- **Reference:** CWE-214 Invocation of Process Using Visible Sensitive Information — https://cwe.mitre.org/data/definitions/214.html

### [LOW-001] The agy argv WARN — the runtime half of the e1 DISS-001 mitigation — has no operator-facing sink on Loa's own dispatch path
- **Severity:** LOW · **Confidence:** high
- **File:** `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:146-153` (`logger.warning(…)`); `.claude/scripts/model-adapter.sh:645` (`result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>/dev/null)`)
- **Issue:** cheval configures no logging handler (no `basicConfig`/`StreamHandler` in `cheval.py`), so the WARN goes to Python's last-resort handler on stderr — and the shim every Loa dispatch runs through (`adversarial-review.sh` → `model-adapter.sh` → `model-invoke`) discards that stderr. `companion.log` holds the shim's own banner lines only (the fold's diagnostic path filters `[model-adapter:shim]`). The triage records "every dispatch WARNs once per process of the argv exposure" as part of the fix; in practice the config example and the adapter docstring are the whole operator-facing mitigation. `test_every_dispatch_warns_of_the_argv_prompt_once_per_process` asserts the log record, not its delivery.
- **Fix:** carry the exposure where the operator looks — a `note` on the MODELINV ledger row the adapter already writes, or the envelope's `status_note` via the shim — or let the shim forward cheval WARN lines to its own stderr; or make the opt-in gate of MED-001 the mechanism, which needs no logging at all.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-002] `_lc_chunk_tok`'s index guard admits a leading zero, which bash reads as octal and aborts on (no reach today)
- **Severity:** LOW · **Confidence:** high on the behaviour; no reach from any diff
- **File:** `.claude/scripts/lib-content.sh:165-166`
- **Issue:** `[[ "$2" =~ ^[0-9]+$ ]] || return 1` then `${_lc_tok[$2]:-}`. Probe: `_lc_chunk_tok "$T" 08 v` under `set -euo pipefail` → `line 166: 08: value too great for base` and the shell exits (an expansion error, not a command — nothing runs). The index is produced only by `printf '%d' "$file_index"` from a counter, and the round-1ap manifest order (`pri<TAB>idx<TAB>path`, the path taking the rest of the line) keeps a header path out of the field, so no diff can place `08` there. Defence in depth only.
- **Fix:** `^(0|[1-9][0-9]*)$`, as `_conf_uint` already does for config integers.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-003] A `--diff-file` header path carrying terminal control bytes reaches the operator's stderr raw when that file is the top-priority one over budget
- **Severity:** LOW · **Confidence:** medium (read from the code; my probe's top file was the docs chunk, so the line named it, not the hostile path)
- **File:** `.claude/scripts/lib-content.sh:337,352` (`$_log_fn "… ${top_path} …"`), `.claude/scripts/adversarial-review.sh:125` (`log() { echo "[adversarial-review] $*" >&2; }`)
- **Issue:** `current_file` is `BASH_REMATCH[1]` of the raw `diff --git a/(.+) b/` header; `--diff-range` is immune because git C-quotes control bytes in that header, but a hand-built or received patch through `--diff-file` (and `gpt-review-api.sh`'s content file) is not. The header path is otherwise data only (`file_priority` `case`, `is_excluded` `==`, the manifest's last field, text in the footer that goes to the model) — I confirmed with six variants (`PATH[$(…)]`, an unset name, a bare arithmetic expression, a second tab field, a third tab field, an ESC sequence) that nothing executes and the hostile file is ranked and shown. What remains is the same provider-text-to-a-terminal class round 1ap stripped from the companion diagnostic (`tr -d '\000-\010\013-\037\177'`).
- **Fix:** strip C0 controls from `top_path` before the two `$_log_fn` lines, or in `_lc_log`/`log`.
- **Reference:** CWE-150 Improper Neutralization of Escape, Meta, or Control Sequences — https://cwe.mitre.org/data/definitions/150.html

### [LOW-004] The merged `adversarial-audit.json` carries one chunk's `metadata.scope`
- **Severity:** LOW · **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-248/adversarial-audit.json` (`metadata.scope: {diff_range: null, diff_oids: null, diff_sha256: 0b8b7816…, run_tag: "e4-bb"}` beside `merged_from_chunks` of 24 and `head: 9fabac05`)
- **Issue:** the merge (a scratchpad tool, not in the repo) kept the last chunk's scope block, so the one field `resources/ADVERSARIAL-REVIEW.md` tells a reader to adopt a round's dissent by (`metadata.scope` with `run_tag` null and matching `diff_oids`) says "one chunk, e4-bb" on an envelope that is the union of 24. `verdict-derive.sh` does not read `scope`, the per-chunk envelopes sit beside it, and `merged_from_chunks` + `head` are the authoritative provenance, so nothing is held wrongly; it is a record-hygiene gap of the same shape as the review's Observation 2. Not a defect in the sprint's code.
- **Fix:** have the merge write `scope: {merged: true, chunks: N, head: <sha>}` (or null) instead of inheriting a chunk's block; if the merge tool is promoted into the repo, pin it with a test.
- **Reference:** CWE-1230 Exposure of Sensitive Information Through Metadata (record-integrity class, informational) — https://cwe.mitre.org/data/definitions/1230.html

---

## Dissent triage, checked (`audit-dissent-triage-run-1.md` on `9fabac05`, fixes in round 1ap `51d7a1ff`)

Counts reconcile: g1 16 + g2 15 + g3 18 + g4 16 + g5 13 + g6 14 = 92; REAL 11, REAL-DOC 1, REFUTED 19, REPEAT 24, DECLINE 37.

**b1 DISS-C-001 (command execution through an array subscript; sprint-introduced at round 1aa) — fix complete.** The defect: `lib-content.sh` wrote the manifest as `pri<TAB>path<TAB>idx`, a raw tab in the header path shifted attacker text into `chunk_idx`, and `_lc_chunk_tok` used it as `${_lc_tok[$2]}` — an arithmetic subscript, where `$(…)` runs. Round 1ap: (1) `_lc_chunk_tok` refuses a non-numeric index (`lib-content.sh:165`); (2) the manifest is `pri<TAB>idx<TAB>path` and every reader is `read -r pri idx path`, so the path takes the rest of the line (`:204, :219, :244, :250, :288, :300, :320, :355`); (3) the filter loop drops a non-numeric index (`:245`); (4) the include loop has the pre-scans' `-f "$temp_dir/chunk_${chunk_idx}"` guard (`:357`); (5) every `_lc_chunk_tok` call is `|| continue`. I traced the remaining uses of the header path: `file_priority` (`[[ … == .claude/* ]]`, `case`) and `is_excluded` (`[[ "$file" == "$zone_path"/* …]]`) use it as the subject, the priority fields are `%d` of `file_priority`'s 0–3 (so the `-le`/`-gt`/`(( priority > inc_low ))` arithmetic is closed), `sort -k1,1n` reads field 1 only, and the path otherwise appears as text. CMP-274 is green here; my six-variant probe (above) ran the truncation branch each time (`priority-based truncation` logged) with nothing executed. `--diff-range` was never reachable (git C-quotes the tab). Not a CHANGELOG matter: the defect lived only on this branch (rounds 1aa–1ao), never in a release.

**e1 DISS-C-001 (stable CLI workspace guarded by a denylist) — fix complete for its claim.** `private_workspace` (`headless_cli.py:220-242`) now `lstat`s the path (a symlink, another owner or group/other-writable → `OSError`), then `held = sorted(os.listdir(path))` and refuses any entry — dotfiles included — with a message naming them; the caller turns the `OSError` into a walkable `ProviderUnavailableError` (`agy_headless_adapter.py:140-144`, the claude twin at `:245`). The `notes.txt` pin flipped to `pytest.raises`; the new parametrised case (`.env`, `.agent`, `.antigravity`, `.geminiignore`, `rules.md`) passes here. The residual — whether agy's `--sandbox --dangerously-skip-permissions` writes outside its cwd (`~/.gemini`, `~/.claude`) — is outside what an empty-cwd check can close and is exactly `bd-ugmi`'s probe. Fail-closed is the right shape: a hop that leaves state makes every later hop refuse until an operator looks.

**The other REAL fixes, read:** a5 DISS-C-002 (`--sprint-id` shape in `main` before any sink, `adversarial-review.sh:3765-3767`; CMP-275 green: `../x`, `x/../../x`, `.hidden`, `a..b` all exit 2 with nothing written); a4a DISS-C-003 (the diagnostic is redacted by `log-redactor.sh` and the key-shape `sed`, then `tr -d` controls, then `cut -c1-300` — `:3350-3375`; `_companion_failure_class` only greps its 300-char head and never logs it; CMP-276 green); a2 DISS-C-002 (`got`/`clean` classes carry U+061C, U+180E, FE00–FE0F, FFF9–FFFB, the Tag block; NRM-66 green); c2a DISS-C-001 (no-digest run tag carries `cksum`, `|| _ck=""` errexit-safe; NRM-67 green); e2c DISS-C-001 (`san1` maps `\302[\200-\237]|\342\200[\250\251]` to a space under the script's `export LC_ALL=C`, `kf-write-lib.sh:35,56-57`; the canonical reader parses 3 entries after the write; green); c2b/c2c/c2d (test-side lints and `_vd_git`/`_cmp_git` isolation: `GIT_TEMPLATE_DIR`, `GIT_EXEC_PATH`, `XDG_CONFIG_HOME`, `core.hooksPath=/dev/null`; the isolation case green); a3 DISS-C-001 (comment reworded to what `_adv_lock_dir_ours` checks — acceptable, the mode is set by `mkdir -m 700` when we create it).

**REFUTED / REPEAT / DECLINE — none wrong on my reading.** I verified in code the ones a wrong call would have made load-bearing: `_conf_uint`, `_adv_num_or`, `_adv_pos_ceil` and `_adv_hop_charge` keep every `(( ))` operand an integer (a1 DISS-C-001, a2 DISS-C-005, a3 DISS-C-002); `--type` is validated before `_adv_record_fallback` (a2 DISS-C-001); the sidecar path is script-authored from `PROJECT_ROOT`, `type`, `_ADV_SIDECAR_TAG` and the shape-checked run tag (`:1503-1510`; a4a DISS-001/C-001); the walker writes `companion.result.json` only on a non-failed hop and `main` removes it unless the phase is `done` (`:3028, :3645`; a4a DISS-C-002); `_adv_pid_tokens` records `-` for a gone pid (c1b DISS-C-002); the `_rr="$diff_range"` fallback keeps a regex-validated ref string and a failed diff is `diff_range_failed` (a5 DISS-C-004); claude runs `--permission-mode plan --tools "" --no-session-persistence` and codex `--ephemeral --sandbox read-only --ignore-user-config` (b2 DISS-C-003); `isHeadlessModelId(id, provider)` requires a `GENERATED_MODEL_REGISTRY` entry under the named provider (e4 DISS-C-001/003); `adapter-factory.ts` never forwards `apiKey` (e4 DISS-C-002); `GeminiHeadlessAdapter` is absent from `_ADAPTER_REGISTRY` (e1b DISS-C-001/002). One record note: the g6 verbatim text for e2a DISS-001 and e2a DISS-C-001 still says "agy is not installed and is disabled" — the premise g5 refuted; the lead's header ("The premise of the earlier refutations … was false") supersedes it and the REPEAT-of-e1-DISS-001 verdict itself is right. Declines that rest on "pre-existing, tracked" (c2e DISS-C-001 `bd-rk9o`, c2e DISS-C-003 `bd-mfqp`, e2b DISS-C-001 `bd-swz7`, b2 DISS-C-002 `bd-xqjw`) are correctly out of this sprint's scope; the a3 DISS-C-003/004, a1 DISS-C-004/005, c2b DISS-C-002 and d DISS-C-004 declines correctly refuse to treat the operator's own environment and config as a trust boundary.

## The agy argv question (`bd-ugmi`) — not blocking for Sprint 2

The exposure is real and the triage's severity (MEDIUM, down from the dissent's HIGH) is right; MED-001 above is my own tally of it. It does not block this sprint because it is not this sprint's regression (the transport is `a67a1a98` on main; Sprint 2 changed the docstring, the comments, the config example and added a WARN), the sprint's companion voice never plans the Google family, this host has neither `agy` nor a Google rung, and the one-way rule turns on critical/high — a local co-tenant reading a redacted diff is a medium-impact confidentiality issue, not a credential or execution path. Two things should still happen before 2.0.0 leaves rc: the opt-in gate or stdin proof on `bd-ugmi` (P2 is right; it should be a GA exit criterion), and a WARN sink that exists (LOW-001). If the maintainer prefers to keep stock dispatch, the config example's "Avoid it on a shared host" line should move into the headless runbook too.

## Review observations, confirmed (not re-tallied)

The review's `excluded` is 0, so `excluded_confirmed` is 0. Its MEDIUM (function length in `main`/`process_findings`/`_fold_companion`/`_adv_take_run_lock`) and LOWs (one chunk's review envelope beside the file; the missing `multi-model-reference.md` row, carried to Sprint 4; the guardrail orchestrator's unnamed invalid `--mode`) stand as written; none is a security defect.

## Scope limits

- The audit dissent's evidence base is `9fabac05`; round 1ap (`51d7a1ff`: 15 files, +435/−148, including the three security fixes above) has no cross-model dissent and was reviewed here by code read, the round's own tests and my variant probes. Per the maintainer's cap I did not re-run it.
- No `documentation-coherence-*` report exists for sprint-248 under `grimoires/loa/a2a/subagent-reports/`; I verified the documentation manually: the CHANGELOG `[Unreleased]` FR-2 entry (companion, opt-out, spend, the argv note), `.loa.config.yaml.example` (companion keys; the corrected agy block with its SECURITY line), both skills' `resources/ADVERSARIAL-REVIEW.md` (two voices, the rejected-payload contract, the degraded-audit rule), the SKILL.md Phase 1C/2.5 paragraphs, `verdict-derive.sh --help`, the adapter docstrings. The dissent's e2a/e2b chunks covered the same files.
- Probes ran only under `~/.cache/loa/cycle-126-dissent/`; no real provider CLI was invoked; `git status` is clean.

## Rubric (sprint surface)

SEC-IV 4 (every new boundary shape-checked: `--sprint-id`, `--diff-range`, run tag, chunk index, companion-chain hop names; LOW-002/003 are the residue), SEC-IN 5 after 1ap (the one subscript sink closed; every other `(( ))` operand integer by construction), SEC-CI 4 (redaction before truncation; credential presence never a value; MED-001/LOW-001 are the gap), SEC-AV 4 (per-voice budgets, the wall cap, the reaper; the aggregate spend cap is an operator bead), CQ-TC 5 (every fix red-first; 7 bats + 59 pytest re-run here), CQ-DC 4 (LOW-001/004).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — the test fixtures' key-shaped strings are fakes built to miss the scanners (CMP-276 assembles the `AIza` shape in pieces; `sk-ant-api03-SECRET…` is 28 characters, below the real rule's length)
- [x] Input validation on all new entry points — `--sprint-id` shape (new in 1ap), `--type`, `--diff-range` ref grammar, the run tag, the chunk index, `companion_chain` hop names, the YAML boolean spellings of `companion_voice`
- [x] Authentication required where needed — credential *presence* only (`_adv_cred_present`), the value never held; `*-headless` hops authenticate themselves
- [x] No injection paths — the b1 subscript sink closed and probed; the header path is data in every remaining use; `jq --arg`/`--argjson` throughout (NRM-46 lint widened)
- [x] Error handling doesn't leak — the companion diagnostic is redacted, then control-stripped, then cut; the envelope gets the allowlisted summary; refusals name the operator's own paths only
- [x] Tests cover security paths — CMP-274/275/276, NRM-66/67, the kf-write-lib line-separator case, the `_vd_git`/`_cmp_git` isolation legs, the parametrised empty-workspace case, the once-per-process WARN case

---

## Rejected dissent payloads

None — the merged envelope's `metadata.rejected_summary` is `[]` and `metadata.rejected_sidecars` is `[]`; every chunk of run 1 reports `rejected_summary []`, and the five `adversarial-rejected-audit-{a4a-script-4a,a4b-script-4b,b1-contracts-code,e1-adapters,e2a-changelog}.jsonl` sidecars beside this file are 0 bytes (no row to triage). Not degraded: `companion_voice.status: succeeded`, `counted_as: independent_voice`, `voices_planned 2`, `voices_dropped []` on the merged envelope and on all 24 chunks.

---

## Next Steps

1. Sprint 2 is cleared: the lead writes the COMPLETED marker, closes ledger 248 and moves to Sprint 3.
2. Carry as beads (none blocks): `bd-ugmi` — the agy argv opt-in gate or stdin proof, made a 2.0.0 GA exit criterion (MED-001), with a WARN sink that reaches the operator (LOW-001); a `lib-content.sh` hardening pair — canonical-integer index guard and control-byte stripping on the logged `top_path` (LOW-002/003); the merge tool's `metadata.scope` on a union envelope (LOW-004).
3. The review's cycle-end bead (extract `_companion_launch` / `_companion_settle` / the verdict-quality aggregation from `main`) stands.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-248","ts":"2026-10-05T10:40:00Z"} -->
