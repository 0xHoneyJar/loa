# Sprint 1 Security Audit Feedback (cycle-127 operator decisions, global sprint 251)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1, `/audit-sprint sprint-1`, audit round 1, no model calls)
**Date:** 2026-10-08
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1 (Final) "agy opt-in, Opus 5.5 effort default, ceiling probe" (FR-1 … FR-3; SDD §1.2–§1.6, D-1.1 … D-3.12), global 251 via `ledger.json`
**Implementation Report:** grimoires/loa/a2a/sprint-251/reviewer.md (every round section through "Audit round r251-4")
**Tree audited:** `feature/cycle-127-operator-decisions` at `cbfccab2`; sprint diff `6f6cc8a6..cbfccab2` (6 commits, 92 files, +8,960 / −473); the audit-round delta `58f87195..cbfccab2` (43 files, +1,767 / −355) has no dissent run behind it and was read in full by this audit (code, schema, tests, dist manifest, record).
**Prerequisites:** `engineer-feedback.md` opens with "All good" and carries `LOA-VERDICT review APPROVED 0/0/1/3, excluded 0` (Fable round 2, 2026-10-07T15:56Z); `a2a/index.md` row `sprint-251 … REVIEW_APPROVED`; no `COMPLETED` marker existed. `adversarial-audit.json` (= run 2 merged, head `58f87195`) carries `metadata.type audit`, `metadata.model gpt-5.5-pro`, `companion_voice.status succeeded` (claude-headless, independent), 4 clean chunks each 2/2 voices, `rejected_count 0`, `rejected_sidecars []`, `degraded false`; run 1 (22 chunks, 60 findings, 2/2 voices) is beside it as `adversarial-audit-run1-merged.json`. `validate-ac-verification.sh --report reviewer.md --sprint sprint.md --sprint-id sprint-1` exits 0 (the review's Observation 1 is fixed). `.run/zone-guard-authorization.json` (scope `framework`, expires 2026-10-10) covers every `.claude/` path in the diff; no hook, settings, rules, commands or `CLAUDE.loa.md` file was touched.

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The sprint makes the argv-exposing agy route opt-in and default-off through one rule read by three readers, gives Opus 5.5 a typed catalog effort default, and lands a headless-CLI ceiling probe whose live run moved the Opus 5.5 bound from 180,000 to 936,000 with structured provenance (`probe_outcome: partial`, the operator's vouch recorded). Four review/audit rounds hardened it; the r251-4 round, which no dissent saw, closes the audit dissent's real items the way the triage says: the opt-in read is anchored to cheval's install root (a planted `/tmp/.loa.config.yaml` no longer opts a host in — reproduced off here), one exact-tag rule holds across PyYAML, python-yq, go-yq and Bridgebuilder's yq program (my own 24-spelling matrix agrees on every value; the two shapes go-yq cannot parse fail closed as `readError`), the bash lib indexes its associative maps only with catalog-shaped ids (six hostile strings left no side effect), an exported include-guard no longer skips the lib, the probe's catalog writer refuses control characters and re-parses its own output before `os.replace` (every injection shape I fed it was refused; a `#` or `"` in a model id passes and loads back intact), and Bridgebuilder's merge gate no longer subtracts not-planned voices under a config read error.

**No critical or high issue is open.** One MEDIUM is the r251-4 round's own regression on the sprint's load-bearing invariant: the new owner/mode refusal of the opt-in config exists only in the Python reader. A world- or group-writable `.loa.config.yaml` carrying `agy_opt_in: true` reads **off** in cheval and **on** in the bash lib (so in the dissent, Flatline, preflight and `/loa`) and in Bridgebuilder's `readAgyGate` — reproduced below — so those planners plan an agy voice that cheval then refuses with `opt_in_required`: exactly the "planned voice that fails" shape FR-1 set out to remove, on a misconfigured host. It fails safe (nothing spawns, cheval WARNs why) and is a two-line fix in either direction, which is why it does not block. Four LOWs: the user-private-group heuristic behind that check fails open on hosts whose users share a primary group; the r251-4 security-relevant behaviour changes are absent from CHANGELOG, the migration addendum and SDD D-1.1; the review's throttle-before-auth observation is confirmed still present (no real shape known); and the AGC-6 batch intermittent reproduced once here with the new diagnostics, which now rule out the timeout and point at a `loa-status` internal jq failure.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 1 |
| Low | 4 |

Confidence is independent of severity and stated per finding. The review trailer excludes nothing (`excluded: 0`), so `excluded_confirmed: 0`.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] The owner/mode refusal of the opt-in config is Python-only: a world- or group-writable config opts the planners in while cheval refuses

- **Severity:** MEDIUM · **Confidence:** high (reproduced)
- **Files:** `.claude/adapters/loa_cheval/config/loader.py:167-176` (`_config_untrusted_reason`), `:216` (`raise _UntrustedConfig`), `:281-285` (reads off, one WARN); the other readers have no counterpart — `.claude/scripts/lib/agy-gate-lib.sh:106-110` (`agy_opted_in` → `_agy_opt_in_node`, `:61`), `.claude/skills/bridgebuilder-review/resources/config.ts:176-195` (`readAgyGate`); consumers `.claude/scripts/adversarial-review.sh:2367`, `.claude/scripts/flatline-orchestrator.sh:524`, `.claude/scripts/run-preflight.sh` P3, `.claude/scripts/loa-status.sh:792`, `core/multi-model-pipeline.ts:172-173`.
- **Issue:** r251-4 S2 (audit n6) added two things to `agy_opt_in_enabled`: the install-root anchor (correct, and the real fix for the planted-ancestor finding) and a permission predicate — a config "not owned by the euid, world-writable, or group-writable by a shared group" reads off. Only the Python reader got the predicate. SDD D-1.5 ("one predicate … the only readers of the rule") and the AGC conformance suite exist precisely so the planners and cheval cannot disagree on this value; the round added a reader-specific rule with no conformance row. Reproduction on this host (the lib and the TS yq program given the same file):

  ```
  mode 644: python=True  bash=ON   (TS: opt true)
  mode 664: python=True  bash=ON   (user-private group here)
  mode 666: python=False bash=ON   reason=world-writable
  mode 646: python=False bash=ON   reason=world-writable
  symlink → 0666 target: python=False bash=ON
  ```

- **Impact:** on a host whose `.loa.config.yaml` is group/world-writable (umask 002 with a non-private group, a file created by a container as root then `chmod 666`, a shared dev box) and opted in, the dissent's companion chain, Flatline's tertiary, `run-preflight.sh` P3 and `/loa` plan the agy voice and Bridgebuilder registers it; cheval's adapter raises `AgyOptInRequiredError` (`agy_headless_adapter.py:124`) → `models_failed` INVALID_CONFIG (`cheval.py:2659`) → the companion voice fails, verdict quality DEGRADED, Bridgebuilder's merge blocked by a voice that "ran" and failed. Fails safe (no spawn; cheval's WARN names the file and the reason) — but it is the G-1 failure shape, and preflight reports PASS for a voice that cannot run.
- **Fix (either direction, one rule everywhere):** (a) apply the same predicate in the bash lib's `agy_opted_in` (`stat -c '%u %a %g'` / `stat -f` on macOS; owner ≠ `$EUID` or `o+w` or `g+w` → off with the one-shot WARN) and in `readAgyGate` (`fs.statSync(configPath)`: `uid !== process.getuid()` or `mode & 0o022` → `optIn=false`, `typeWarning` naming the mode), with AGC rows for 0666 / foreign-owner; or (b) keep the install-root anchor and make the Python permission check WARN-only (the lead already ruled in n3 that the project tree is the trust root; whoever can write `.loa.config.yaml` can write `.claude/scripts/lib/agy-gate-lib.sh`). Option (b) is the smaller change and restores the one rule; option (a) keeps the defence. Either way add the conformance row.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html ; OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [LOW-001] `_group_is_private` reads an empty `gr_mem` as "the owner's own group": on hosts whose users share a primary group a group-writable config is honoured

- **Severity:** LOW · **Confidence:** medium (read; not reproducible on this host, whose primary group is user-private)
- **File:** `.claude/adapters/loa_cheval/config/loader.py:153-164` (`_group_is_private`: `gid == os.getegid()` and `all(m == me for m in grp.getgrgid(gid).gr_mem)`), consulted at `:174`.
- **Issue:** `gr_mem` lists only *supplementary* members; users whose *primary* gid is that group are not in it. On a host where every user's primary group is a shared one (`users`, gid 100, the historical SUSE/Slackware default; any site that sets `USERGROUPS_ENAB no`), `gr_mem` is typically empty, `all([])` is True, and a `0664` config writable by every user of the group reads as private — the predicate the round added to refuse "a config others can write" passes exactly the case it describes. On this host `egid 1000 merlin gr_mem=[] → True`, correctly.
- **Fix:** require the user-private-group convention explicitly — `grp.getgrgid(gid).gr_name == me` and empty `gr_mem` — or simply treat any `g+w` as untrusted (the WARN tells an operator with umask 002 to `chmod 644`); moot under MED-001 option (b).
- **Reference:** CWE-732 Incorrect Permission Assignment for Critical Resource — https://cwe.mitre.org/data/definitions/732.html

### [LOW-002] The r251-4 security-relevant behaviour changes are not in CHANGELOG, the migration addendum or the SDD; SDD D-1.1 now misdescribes the read

- **Severity:** LOW · **Confidence:** high
- **Files:** `CHANGELOG.md:12` (the FR-1 bullet says "read from the project config only"; nothing on the install-root anchor, the owner/mode refusal, the alias/merge-key/exact-tag rule), `docs/migration/v2.0-model-generation-floor.md:276` (cycle-127 addendum; same gap, and nothing on the probe writer's refusal/re-parse or Bridgebuilder's merge gate under `readError`), `grimoires/loa/sdd.md:29` (D-1.1: "Read through the existing project-config layer (`load_project_config` → `hounfour`)" — the read is now a node-level `yaml.compose` from `_opt_in_root()` with a trust check, `loader.py:139-150`, `:203-235`).
- **Issue:** the r251-4 commit touched no doc besides `sprint.md`'s round section and `reviewer.md`. The skill's documentation audit flags "a CHANGELOG omitting security changes" and "auth changes without security documentation": an operator reading the addendum cannot learn that a config they do not own, or that is writable by others, is ignored (and why their opt-in "does not take"), nor that a cwd under another tree never opts in. The commit message and `audit-dissent-triage.md` carry all of it, which is why this is LOW.
- **Fix:** one sentence each in the CHANGELOG FR-1 bullet and the addendum (anchor + trust check + the three-reader exact-tag rule), one in the FR-3 bullet (the writer refuses control characters and re-parses before replacing), one in the Bridgebuilder sentence (merge blocked under a read error); amend D-1.1 to name `_opt_in_root` and the trust check. Fold into the cycle PR's docs pass.
- **Reference:** OWASP ASVS V1.1.2 (documented security controls) — https://owasp.org/www-project-application-security-verification-standard/

### [LOW-003] A throttle marker still precedes the static-auth markers in the headless classifier (the review's Observation 3, confirmed present)

- **Severity:** LOW · **Confidence:** low (speculative; no real CLI shape known)
- **File:** `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:563-578` (`_throttle` wins), `:582-611` (the auth arms after it); markers `.claude/adapters/loa_cheval/routing/ceiling.py:273-283`.
- **Issue:** reproduced: `Not logged in · please wait, then run /login` → `RateLimitError` (retried, walked); `Not logged in. Run /login` → `ConfigError`. A login message containing `please wait`, `quota` or a bare `429` would waste the retry budget and walk instead of hard-aborting. The precedence is what the review's HIGH required for Bedrock's "Too many tokens, please wait" and the r251-4 word boundaries did not change it. Tallied so it is not lost; the review counted it too.
- **Fix:** none required now; if a real shape appears, let `not logged in` / `/login` take precedence over `please wait` alone (not over a status 429/529).
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-004] AGC-6 still fails intermittently in the batch; the r251-4 diagnostics now show a `loa-status` internal jq failure (exit 5 in 1 s), not the timeout

- **Severity:** LOW · **Confidence:** medium (observed once in three full-file runs here; passes alone)
- **File:** `tests/unit/agy-gate-conformance.bats:120-134` (AGC-6); the subject `.claude/scripts/loa-status.sh` (`--json` assembly; the Providers helpers from `:792`).
- **Issue:** first full-file run: `not ok 6 … status=5 elapsed=1s (gate mismatch or loa-status failure) --- stderr: jq: parse error: Invalid numeric literal at line 1, column 2 --- google block: (not JSON)`. `loa-status.sh` has no `exit 5` of its own, so a jq inside it (exit 5 = runtime error) received non-JSON from a sub-generator and `set -e` ended the run with partial stdout. Alone twice and in the second full run: 18/18. The S9 diagnostics did their job — this is neither `timeout 180` nor a gate mismatch — but the failing jq is still unnamed. Candidates are the helpers that read shared state the test's `LOA_STATUS_RUN_DIR` does not isolate (the beads/`loa-doctor --quick` path the review named; `_anthropic_ceiling_json` reads the real `.run/ceiling-observed.json` via `LOA_CHEVAL_CEILING_OBSERVED_PATH`'s default, though that writer is atomic).
- **Fix:** capture the full stderr (not `tail -20`) and run `loa-status.sh` under `bash -x` on failure, or have each `_providers_*` helper guard its jq input (`jq -e . >/dev/null || echo null`); bead it with LSP-1.
- **Reference:** CWE-703 Improper Check or Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/703.html

---

## The audit-round delta (`58f87195..cbfccab2`), audited by reading, probes and suites

No dissent run covers this delta (≤ 2 per gate), so every item the lead listed in `audit-dissent-triage.md` § "Round r251-4 outcome" was checked against the code, not the report.

| Item | Verified | How |
|---|---|---|
| S1 Bridgebuilder merge gate under `readError` | ✓ | `multi-model-pipeline.ts:464-470`: `mergeBlocked = true` + `mergeBlockedReason` when `readError` and any not-planned voice; the quorum arithmetic subtracts not-planned voices only when `readError === undefined`; strict mode throws at `:194` before any dispatch. Tests `multi-model-agy-opt-in.test.ts` "a host fault never shrinks the quorum" (graceful: APPROVE voices, merge still blocked, summary names the reason; no google voice → cohort clears). dist rebuilt (`check-bb-dist-fresh` OK, source_hash `0b13c028…`). |
| S2 install-root anchor | ✓ | `loader.py:133-150`: `_opt_in_root()` honours the cwd walk only when its `.claude/adapters` resolves to this cheval's; probed: cwd `/tmp/…/plant/child/deep` with a planted `plant/.loa.config.yaml: agy_opt_in: true` → root = the repo, `agy_opt_in_enabled() == False`; a planted tree with a bare `.claude/adapters` directory → still the repo; cwd inside the repo → the repo. Explicit `project_root` bypasses the anchor by design — every production caller passes none (`agy_headless_adapter.py:124/261/296`, `cheval.py:406/408`). |
| S2 owner/mode refusal | ✓ but Python-only | reads off with one WARN on 0666 / 0646 / foreign owner / symlink to a 0666 target (probed) — **MED-001**, **LOW-001**. |
| S3 exact tag, alias, merge key | ✓ | 24 spellings through PyYAML, the Python yq fallback, the bash lib (go-yq v4.44.1) and Bridgebuilder's yq program: identical on all 22 go-yq can parse (`true`, `!!bool true`, `!!bool "true"`, `!<tag:yaml.org,2002:bool> true`, flow style, duplicate-key last-wins, anchored key, BOM, CRLF → on; `True/yes/on/"true"/1`, `!!bool True`, `!<x:bool>`, alias, merge key, merge + explicit false, a Cyrillic look-alike key → off); multi-document and `hounfour` as a sequence → off in Python/bash, `readError` (fail closed, merge blocked) in TS. AGC-13 pins the three bash/Python readers row by row; the TS cases in `readAgyGate shapes`. |
| S4 include guard, preflight fail-closed | ✓ | `agy-gate-lib.sh:44-46` (`declare -F agy_opted_in`; flags reset, never seeded from env); probed with `_LOA_AGY_GATE_LIB_LOADED=1 _LOA_AGY_GATE_WARNED=1` exported → functions defined, flag empty. `run-preflight.sh:48-52` exits 2 when the lib cannot be sourced; `loa-status.sh:804-812` installs fail-closed stubs instead (display path). AGC-14, PF suite 22/22. |
| S5 provider maps | ✓ | `loader.py:324-373` caches only a complete read, WARNs once naming the failure; `agy-gate-lib.sh:126-147` indexes `MODEL_IDS`/`MODEL_PROVIDERS` only for `^[A-Za-z0-9][A-Za-z0-9._@+/-]*$` ids and only after `declare -p` proves both associative; probed six hostile strings (`a[$(…)]`, `` `…` ``, `x$(…)`, `gemini-$(…)`, `google:$(…)`) → no file created; `deep-research-pro`/`researcher` → google under cli-only, `opus`/`gpt-5.5`/unknown → planned. AGC-15/16, `test_s5_*`. |
| S6 throttle boundaries, CLI sentence, quoted hint | ✓ | `ceiling.py:283` `(?<![\w,.])(429|529)(?!\w|…)`; `:235-236` `_RE_CLI_REQUEST_SENTENCE`; `processed 12 tokens (limit 100)` → not a context limit, `the request is ~1065182 tokens (limit 1000000)` → is; `cheval.py:363-376` `shlex.quote`; `test_ceiling_r251_4.py` (hostile id round-trips through `shlex.split`). |
| S7 plausibility floor | ✓ | `ceiling.py:49-68`, `:190-192`, `:378-409`: an observation outside `[0.1 × window, window]` ignored once with a WARN, in `input_bound` and `observed_for`; cheval passes `context_window` at all three `_observed_for` sites (`cheval.py:850`, `:2062`, `:2366`; pinned by `test_s7_cheval_passes_the_window…`); `loa-status.sh:856-863` jq mirrors the floor. |
| S8 `_effort_on_wire` at the emit site, `strenv`, argv `--` | ✓ | `cheval.py:2941-2954` own try, records None and WARNs; `loa-status.sh:846-852` `strenv(M)`; `build_headless_argv` takes no prompt, the adapter appends `["--", prompt]` only when one is given (`claude_headless_adapter.py:349-352`; callers pass none). |
| S9 AGC-6 diagnostics | ✓ | `agy-gate-conformance.bats:126-134` prints status, elapsed, stderr, the google block — and produced the evidence for **LOW-004**. |
| T1 injection guard, dry run with real kwargs, re-parse | ✓ | `ceiling-probe-live.py:265-283` (`_UNSAFE_CHARS` C0/DEL/C1/U+2028/2029, 200 chars), `:996-1004` (refused before the dry run and any spend, exit 2), `:607-612` (the writer refuses on its own), `:694-741` (`_verify_operator_set`: ceilings, provenance fields, nothing outside the three keys changed). Probed on the live catalog text: newline / NEL / U+2028 / tab / DEL / 201 chars / empty / non-string → refused; `m" # x: 1`, `a: b`, a `#` in the route → written and loaded back intact (`json.dumps` quoting); a planted provenance defect → "re-parse … failed"; partial without `force_partial` → refused. `_write_text_atomic` lands only after the writer returns (`:1252-1264`); the record claims `written_*` only then. |
| T2 finite, bounded CLI numbers | ✓ | `_bounded` drops `inf`/`nan`/bool/≥ cap into `dropped_values`; `_charge` with `inf` falls back to the estimate (probed). |
| T3 1.8 prior | ✓ | `_PRIOR_RATIO` in the pre-flight estimate and the first step's `est_measured`; the filler sent is unchanged. |
| T4 `~`-relative record, resolved binary | ✓ | `_home_rel` prefix-exact (`/home/op` ≠ `/home/operator`), `_recorded_bin` via `shutil.which`; the committed record carries `~/.local/bin/claude-bedrock` and no `/home/`, `/Users/` or user name (grep over the record and the whole non-dist sprint diff: only the test's fixture strings). |
| T5 schema if/then + maxLength | ✓ | `model-config-v3.schema.json:312-324`; `model-config-v3-schema.bats` 35/35 incl. the negative if/then cases; the live entry carries `probe_outcome: partial`, `transport: claude-headless`. |
| T6/T7 test sentinels, `/proc/<pid>/cmdline` | ✓ | `_dry` sets a `CLAUDE_HEADLESS_BIN` sentinel and a minimal PATH; `_cmdline_has` before the kill. Probe suite 145/145 with the sentinel; the two production ledgers byte-identical before and after every suite run (KF-033 hygiene). |

---

## The checklist focus items, verified

- **Opt-in gate — env / cwd / spelling / permission tricks.** No environment variable is read by any reader (`loader.py` reads the file only; the bash lib reads `LOA_HEADLESS_MODE` for the *mode*, as cheval does, never for the opt-in; `readAgyGate` likewise). cwd: closed by S2 (above). Spelling: the matrix above — nothing but the exact bool scalar `true` (or its explicit/full tag) opts in anywhere. Permissions: the only divergence is MED-001, in the *safe* direction (planners on, cheval off). The planner-plans-a-voice-cheval-refuses shape therefore exists only under MED-001's misconfiguration; on a sane config the four bash planners, Bridgebuilder and cheval agree (AGC 18/18 on the second full run, PF 22/22, FTA 5/5, LSP 12/12).
- **`AgyHeadlessAdapter` refuses before any spawn.** `complete()` checks the gate first (`:124`), before `_get_model_config`, the workspace, the WARN and `run_subprocess_pgkill`; `validate_config` (`:261`) and `health_check` (`:296`) likewise; `_build_command` never spawns. Opted in with no binary: `FileNotFoundError` → `ConfigError` "agy CLI not found" (`:201-205`), as AC 1 now says.
- **cheval `_plan_around_agy` / the `opt_in_required` arm.** `cheval.py:395-423`: a gated hop inside a longer chain is dropped before the walk into `models_not_planned` (never a breaker count, never in `models_requested`); an agy-alone chain is left whole and the adapter's refusal lands in `models_failed` with `error_class INVALID_CONFIG`, `failure_class opt_in_required` (`:2659-2669`), `voices_dropped.reason OptInRequired` (`:1322`). MODELINV truthfulness holds: requested ∪ not_planned = the resolved chain (`:1785-1793`).
- **Bridgebuilder merge gate under `readError` / strict.** See S1. Under `readError` every google voice is not planned (K7b, `config.ts:243`), the review runs in graceful mode with the merge blocked and the posted Verdict Quality line naming the voices and the cause (`:388-393`).
- **`_raise_for_error` precedence.** Crafted-text probe (16 shapes): the throttle rule wins over a context marker only when a throttle marker or a status-position 429/529 is present; a request id containing `429` does not flip a size verdict (`Prompt is too long. request id req_011CX429abc` → `ProviderContextLimitError`); `Prompt is too long` + `api_error_status 429` → `RateLimitError`, + `400` → context limit. A crafted provider text *can* turn a size verdict into a throttle (retried, then walked, never a breaker count beyond the rate-limit path) — the documented trade-off the review's HIGH required (run-2 n10 declined); it cannot turn a throttle into a terminal size verdict unless the text carries no throttle word and no status, which is the pre-r251-3 Bedrock gap the review closed. LOW-003 is the residual on the auth side.
- **`routing/ceiling.py`.** Foreign-transport tightening (`:142-149`, `:193-194`: `observed - 1` applies when `not calibrated or foreign`; a same-route calibration ignores observations), the plausibility floor (S7), `CALIBRATED_COUNT_NEAR_BOUND = 0.5` (`:566`, used at `:621`; a calibrated entry with no count in the band dispatches with `warn`, `:634-638`), `parse_context_limit` reads the bare CLI shape for numbers only while `is_context_limit_message` requires the sentence (`:231-236`, `:336-338`). The observed store writer keeps its symlink/owner/inode lock checks (`:412-432`) and atomic replace.
- **`tools/ceiling-probe-live.py`.** Input validation (T1), the re-parse (T1), env forwarding: `_run_capped` passes the full environment plus `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` to the env-selected binary (`:332-349`; the wrapper reads its own secret — the trust model the lead recorded in n51); the record stores the `~`-relative resolved binary, `cli_version` (first line, 120 chars), the resolved `cli_model` (alias through `ANTHROPIC_DEFAULT_*_MODEL`, validated), the 3-key `route_env` with the Bedrock switch as presence only, the argv (no credential, prompt on stdin), per-sample `detail` capped at 300 chars; `--write-partial-as-operator-set` needs `--write-catalog`, is refused on the api transport, writes only when a verified accept exists, and the entry says `probe_outcome: partial` (`:1246-1264`).
- **Catalog entry and schema.** `.claude/defaults/model-config.yaml:470-528`: `effective_input_ceiling 936000`, `probed_ceiling 936000`, `ceiling_calibration {operator_set, calibrated_at 2026-10-07T09:29:07Z, sample_size 5, stale 90, reprobe_trigger, probed_headless, claude-headless, cli_version, cli_model, measured_input_tokens 972887, probe_outcome partial}`, `params.default_effort: high`; `tools/regen-model-artifacts.sh --check`: adapter maps match, BB registry current, dist fresh, checksum OK.
- **Secrets / PII in tracked state.** None in the committed probe record or the sprint diff (patterns: cloud keys, `sk-`, `AIza`, `ghp_`, private keys, `Bearer`, home paths, the operator's user name). `a2a/` and NOTES are gitignored.
- **Effort default cannot be hijacked.** `resolve_effort` (`cheval.py:952-1001`) reads only the resolved entry's `params.default_effort` through the merged catalog (System defaults under the project's `hounfour:` section — the operator's own file; no env rung), validated against `EFFORT_LEVELS` with one WARN on an invalid value; `--effort` is argparse-`choices`-bound; the schema types the key (`model-config-v3.schema.json:163`). `effort_effective` is the dispatching adapter's own `wire_effort` (`anthropic_adapter.py:203`, `claude_headless_adapter.py:188`), derived in its own try at the emit site (S8).
- **Zone marker.** Every `.claude/` path in the sprint diff is a framework file named by the marker's reason (adapters, scripts, lib, schemas, defaults, the Bridgebuilder skill, checksums); nothing under hooks, settings, rules, commands, agents or `CLAUDE.loa.md`.

---

## Review observations, confirmed

| Review item | Status at `cbfccab2` |
|---|---|
| Obs 1 (MEDIUM) reviewer.md AC 1 heading lagging | Fixed — `validate-ac-verification.sh` exits 0 |
| Obs 2 (LOW) AGC-6 batch flake undiagnosable | Diagnostics landed (S9); the flake reproduced once with them → LOW-004 |
| Obs 3 (LOW, speculative) throttle before auth | Still present, confirmed by probe → LOW-003 |
| Obs 4 (LOW) provider lookup fails soft silently | Fixed — WARN once in Python and bash (S5, AGC-16, `test_s5_*`) |

The review's trailer excludes no HIGH (`excluded: 0`); `excluded_confirmed: 0`.

---

## Dissent record

- Run 1 (`adversarial-audit-run1-merged.json`): 60 findings, 0 critical / 0 high / 18 medium / 42 low, 2/2 voices, 22 chunks, 0 schema-rejected. Run 2 (`adversarial-audit.json`, the gate's envelope): 11 findings, 4 medium / 7 low, 2/2 voices, 4 chunks, `rejected_count 0`, `hallucination_filter.downgraded 0`. The lead's rulings in `audit-dissent-triage.md` with two Opus verifier reports (E, F).
- Spot-checked rulings against the code: n6 REAL (the planted-ancestor probe now reads off); n22 REAL (gate fixed); n52 REAL (every injection shape refused); n7 REFUTED-plus-hardened (associative maps, hostile strings inert); run-2 n2/n3 REFUTED (the bash lib resolves provider through the generated maps; `routes_to_agy` checks the literal hop forms before the provider rule — `agy-gate-lib.sh:187`); n19 REFUTED (prefer-cli: `_plan_around_agy` keeps the HTTP hop); n55 REFUTED (`_route_env` is a 3-key allowlist, presence-only for the switch). No ruling I checked was wrong; the one thing the dissent could not see — the r251-4 delta — produced MED-001.

---

## Notes, not tallied

- The TS reader reports a multi-document or sequence-shaped config as `readError` where Python and bash read "off"; the *value* agrees (nothing planned) and r251-4 makes the TS path block the merge — stricter, by design (K7b).
- `gemini-$(…)`-shaped ids are agy-routed by the `gemini*` name rule in bash (no evaluation occurs; the regex guard keeps them out of array subscripts) — harmless.
- `loa-status.sh`'s fail-closed stubs (lib missing) recognise only the literal `gemini-headless` forms, so under cli-only a Google voice would display as planned — display only, said on stderr, documented in the comment.
- `_cli_version` runs the env-selected binary before the dry run; whoever sets `CLAUDE_HEADLESS_BIN` already runs code (the n51 trust model).
- One pytest skip in the selection: `test_agy_headless_adapter.py:319` "needs an OAuth-authed agy on host" — pre-existing.

---

## Scope limits

- No model was called (lead's constraint); the cross-model audit is the two dissent runs above. The guardrails pre-execution step, the trajectory JSONL and the `findings.jsonl` sidecar were not written: they fall outside this audit's write allowance (three files).
- Not run by me: the full adapters pytest (the lead records 3,015 / 6 skipped), Bridgebuilder vitest (807/808, KF-036), `adversarial-review-companion.bats`, `gen-bb-registry-codegen.bats`, `cycle-124-anthropic-catalog.bats`, the live probe. `regen-model-artifacts.sh --check` and `check-bb-dist-fresh` were run and pass.
- Beads were not touched (lead's constraint); the task notes are MED-001 / LOW-001 (one bead: "one permission rule across the three opt-in readers"), LOW-002 (docs pass before the cycle PR), LOW-004 (fold into LSP-1).

---

## Rubric (sprint surface)

Security 4/5 (one reader-conformance regression, safe direction; every attack shape probed was closed) · Architecture 4/5 (one predicate in three languages with a conformance suite; the permission rule broke the pattern) · Code Quality 4/5 (small functions, every fix with a test; `_main_cli` still ~300 lines, bead bd-rbkz) · DevOps 4/5 (artefacts drift-free, ledgers clean, one intermittent) · Blockchain/Crypto n/a.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — grep over the sprint diff and the committed probe record: none; the record's home paths were rewritten `~`-relative
- [x] Input validation on all new surfaces — opt-in: exact-tag scalar only, three readers agree on every parseable spelling; bash maps: catalog-shaped ids only; probe: control characters / length refused before spend, output re-parsed before replace; effort: enum-bound at the schema, the argparse `choices` and the resolver
- [x] Authentication/authorization — the opt-in is file-only (no env), anchored to cheval's install root, fail-closed on an unreadable config; the refusal happens before any discovery or spawn; **one reader applies an extra permission rule the others do not (MED-001)**
- [x] No SQL/XSS injection — n/a; shell: `shlex.quote` on the printed hint, `strenv` into yq, no `eval`, no arithmetic subscripts on untrusted strings
- [x] Error handling doesn't leak info — the error envelope carries the constant refusal message; MODELINV redacts; the probe caps `detail` at 300 chars and records no credential
- [x] Tests cover security paths — `test_agy_opt_in_r251_4.py`, `test_ceiling_r251_4.py`, the T1 injection tests, AGC-13…18, the merge-gate vitest cases; **no conformance row for the permission rule (MED-001)**

---

## Rejected dissent payloads

None — `adversarial-audit.json` `rejected_count 0`, `rejected_summary []`, `rejected_sidecars []`; no `adversarial-rejected-audit*.jsonl` exists beside it (the seven `adversarial-rejected-review-*.jsonl` sidecars beside it belong to the review gate and are all empty).

---

## What this audit ran (serial, no model calls, at `cbfccab2`)

- `validate-ac-verification.sh` on `reviewer.md` → exit 0. `tools/regen-model-artifacts.sh --check` → maps match, registry current, dist fresh, checksum OK.
- adapters pytest (`env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK`): 15 gate/effort/ceiling/headless modules → **418 passed, 1 skipped** (pre-existing); `test_ceiling_probe_cli_transport.py` → **145 passed**. `.run/model-invoke.jsonl` and `.run/cost-ledger.jsonl` sha256 unchanged across both runs.
- bats (node v24.11.1 on PATH): `agy-gate-conformance` 17/1 (AGC-6, LOW-004) then AGC-6 alone 1/1 ×2 and the full file 18/0; `run-preflight` 22/0; `model-config-v3-schema` 35/0; `flatline-tertiary-agy-opt-in` 5/0; `cycle-124-effort-flag` 13/0; `loa-status-providers` 12/0. 0 skips.
- Read-only probes in `/tmp`: the 24-spelling × 4-reader opt-in matrix; the permission-bit split (MED-001); the planted-ancestor / fake-adapters / in-repo / symlink roots; the bash lib with six hostile ids, an exported include guard and a project-alias config; the probe writer with eleven hostile or edge values, a forced provenance defect, partial-without-force, `_bounded`/`_charge` on `inf`/`nan`; `_raise_for_error` on 16 crafted texts plus two `api_error_status` cases.

---

## Next Steps

1. MED-001 + LOW-001 (one bead): pick a direction — the same permission predicate in `agy_opted_in` and `readAgyGate` with AGC rows, or WARN-only in Python — before the cycle PR; it is a few lines either way.
2. LOW-002: the docs sentences in the cycle PR's docs pass (CHANGELOG FR-1/FR-3 bullets, the addendum, SDD D-1.1).
3. LOW-004: full stderr capture or `bash -x` on AGC-6 failure, folded into the LSP-1 bead.
4. Sprint cleared: `COMPLETED` written, index row set; the lead updates the ledger and opens the cycle PR.

---

## Post-approval verification (c2ef7581)

Round r251-5 (`cbfccab2..c2ef7581`, 29 files, +625 / −189), verified under the same constraints — reading, probes and light suites, no model calls — at the lead's request after the approval above.

**MED-001 — CLOSED.** One permission rule now lives in all three readers and was read in each: `loader.py:167-180` (`_config_untrusted_reason`: owned by the euid, neither group- nor world-writable, no private-group exception, `stat()` through symlinks), `agy-gate-lib.sh:63-79` (`_agy_config_untrusted`: `stat -L -c '%u %a'` with the BSD `-f '%u %Lp'` fallback, an un-stat-able file untrusted — fail closed) applied in `_agy_opt_in_node` (`:81-90`) only to a value that would opt in, and `config.ts:177-191` (`agyConfigUntrustedReason`: `statSync` uid/mode) applied the same way in `readAgyGate` (`:222-226`) as a `typeWarning`, not a `readError`, so the gate reads off exactly as the other two readers rather than blocking the merge. The dist carries it (`dist/config.js` imports `statSync`; `check-bb-dist-fresh` OK). The probe that found MED-001, rerun through the Python loader, the bash lib and the **real** TS `readAgyGate` (node on `dist/config.js`):

| config (`agy_opt_in: true` unless stated) | python | bash | TS |
|---|---|---|---|
| mode 0644 | on | on | on |
| mode 0600 | on | on | on |
| mode 0664 | off (WARN: group-writable) | off (WARN) | off (typeWarning) |
| mode 0666 | off (WARN: world-writable) | off (WARN) | off (typeWarning) |
| mode 0646 | off (WARN: world-writable) | off (WARN) | off (typeWarning) |
| symlink → 0666 target | off (the target decides) | off | off |
| `agy_opt_in: false`, mode 0666 | off, no trust WARN (only a value that would opt in is judged) | off | off |
| foreign owner (Python, euid monkeypatched) | off (WARN: not owned by the current user) | — | — |

No split remains. Conformance rows for world-/group-writable configs on the three readers landed (`agy-gate-conformance.bats` 21/21 here).

**LOW-001 — CLOSED.** `_group_is_private` is gone; group-writable is refused unconditionally (the 0664 row above).

**LOW-003 — CLOSED as specified.** `_STATIC_AUTH_MARKERS` (`claude_headless_adapter.py:164`) outrank a throttle that rests on `please wait` alone (`:572`, `ceiling.py:295` `is_throttle_beyond_wait`): "Not logged in · please wait, then run /login" → `ConfigError`; a status 429/529 or a named rate / token / overload / quota marker still wins ("API Error: 429 not logged in", "not logged in (quota exceeded)" → `RateLimitError`, by design); the Bedrock shapes are unchanged (`test_claude_headless_context_limit.py` extended, 209 passed across the four gate/headless/ceiling modules).

**LOW-004 — CLOSED.** Root cause found: `workflow-state.sh:354-359` `store_cache` let the cache manager's `set` status line ("v Cached result for key: …") onto stdout on every cache miss, which led `--json` output and broke `loa-status --json`'s jq merge with exit 5 — the exact diagnostics AGC-6 printed; now `>/dev/null 2>&1`, with a regression case (`agent-ergonomics-workflow-state.bats` 5/5). `agy-gate-conformance` 21/21 with AGC-6 in the batch, `loa-status-providers` 13/13.

**LOW-002 — CLOSED.** SDD D-1.1 now describes the node-level read from cheval's install root and D-1.11 records the three-reader trust rule; the migration addendum and the CHANGELOG FR-1 bullet carry the anchor and the rule.

**Open at `c2ef7581`: 0 critical / 0 high / 0 medium / 0 low.** The tally table and the trailer keep the round-1 record (1 medium / 4 low found at `cbfccab2`, all closed in r251-5) per the lead's instruction; `COMPLETED` and the index row are unchanged. `regen-model-artifacts.sh --check` drift-free at `c2ef7581`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-251","ts":"2026-10-07T17:44:23Z"} -->
