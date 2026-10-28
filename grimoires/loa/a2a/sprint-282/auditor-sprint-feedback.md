# Security & Quality Audit Report — Sprint 282 (cycle-137 sprint-2)

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-28
**Scope:** the six follow-up beads of the 22-pass optimisation loop as landed on `feature/cycle-137-performance` — `git diff 747b5db0d..c31089280 -- .claude/{adapters,data,hooks,scripts} .github tests CHANGELOG.md` (20 files, +2213/−37: 9 System Zone files incl. `checksums.json` and the version header, the CI workflow, 10 test files, CHANGELOG), i.e. seven red/fix pairs, one test-only commit and the two review fix pairs (57e38f8c0 → c31b9e03c, c69059546 → c31089280), plus the audit's own test-only strengthening 03f910129. `security-audit-scope.sh --paths <21 files>`: 0 controllers / routes / handlers / API endpoints; sinks: database/query 1 file, command exec 2 files, file operations 1 file; auth 2 files; LLM/AI 2 files. Working file: `grimoires/loa/a2a/audits/2026-10-28/SECURITY_ANALYSIS_TODO-sprint-282.md` (12 sources, 12 sinks, every entry traced; FIFO and hard-link probes).
**reviewed_head:** 03f910129 (the review verdict in `engineer-feedback.md` names the same head; the only commit after the last System Zone change c31089280 that is not docs-only is this test-only strengthening, read in full).
**PR head binding (S-3):** PR #1309 merges 3215c141f = 03f910129 + two `grimoires/`-only commits (e4dacaec9, 3215c141f: sprint-plan ticks, decision rows, ledger — 116 insertions, 5 deletions) — no System Zone, test, workflow or release file changes (`git diff --stat 03f910129..3215c141f`, verified by the auditor before the merge; D-1.1 exemption). This verdict binds to 3215c141f with 03f910129 as the last audited code change.
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain N/A) over the full code diff, two-pass source/sink tracing, two executable probes against a scratch mirror, and the two-voice security dissent (the sprint's third and last dissent run — DEC-1134).

---

## Executive Summary

This sprint adds two trust surfaces and widens one, and every one of them is a cache or a batch over data the framework already treated as untrusted. (1) The grimoire-index decisions cache stores the OUTPUT of the jq sanitiser, keyed by the sha256 of the exact decisions.yaml bytes it parsed, inside `.run/perf-cache`; it is read only when `.run` and `.run/perf-cache` are real directories owned by the running uid with no group/other write bit (a uid-owned directory carrying such a bit is tightened with `chmod go-w` — removing bits on our own directory, never adding — and a foreign or untightenable one is refused), and a row is served only after one awk validated the header key, the row count, nine fields and an alphabet that excludes control bytes, NUL and `<>`; the writer uses umask 077, an exclusive `mktemp` beside the cache, two symlink re-checks and `mv -T`, so a symlink, a FIFO or a hard link planted at the cache path is replaced, never followed or written through (probed, now pinned by tests). (2) The agy opt-in memo keys the consent read on the config's `dev:ino:size:mtime:ctime` and `PATH`; the two review rounds found and closed the whole-second window twice (mtime, then ctime with a one-second margin), the clock is a builtin rather than an inheritable variable, every stat-derived number is regex-gated before arithmetic, and after this audit's strengthening the memo's hit, per-component miss, reset-at-load and invalidation per mutation are each pinned deterministically. (3) `verify-chains` runs N chain verifications in one Python process by calling the UNCHANGED `audit_verify_chain` per path (the diff touches `audit_envelope.py` in a docstring line, a `Sequence` import, an `__all__` entry and the one new function; `_check_trust_store`, `audit_emit*` and `audit_verify_chain` have no hunk) and re-validates its own output in the shell wrapper by index and byte-exact path echo, so a crashed, truncated or malformed verifier yields FAILED records and `loa-status` counts none of the passed paths on an abnormal exit — strictly more conservative than the per-call loop it replaces. The KF shape-C parser, the one-program yq ceiling read and the profile `cached_keys` keep their inputs as data (`$m` bound as a value, `--arg k`, the same `san()`), and the integrity manifest is consistent on c31089280 (`check-loa.sh` All checks passed; 2080 manifest entries, 0 untracked, 0 missing).

The security dissent (gpt-5.5-pro via codex-headless + claude-headless, 2/2 voices, envelope status `clean`) returned eight findings, all from the companion voice. None is a defect introduced by this sprint's code: the one graded HIGH by the voice — the profile-lib `effective-config.json` cache lacks the ownership check and the `mktemp` discipline its new sibling has — is pre-existing (the cache code has no hunk in the diff; this sprint only widened its content by one karpathy knob), needs a co-tenant who can write `.run` but not the config files, and belongs to a red-first task of its own on that per-tool-call hot path: graded MEDIUM, bead bd-j34zb, DEC-1136. The one finding against this sprint's own work — its memo tests had lost their teeth to its own round-2 rule and passed by bypass — was fixed in the sprint (03f910129, DEC-1138). Two findings were refuted by execution (a FIFO at the cache path does not block; the companion hold knob does take effect — DEC-1137) and three pre-existing LOW observations have beads (bd-hyah6, bd-7utms, bd-yos4s).

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 3 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Notes |
|---|---|---|
| Security | 9/10 | two new trust boundaries explicit and tested (foreign-owned, untightenable, symlinked, FIFO, hard-link fixtures); the one real gap in this sprint's code (whole-second stat) was found by dissent and closed red-first twice; residual: remote-filesystem clock lag (DEC-1132) and the pre-existing sibling cache (bd-j34zb) |
| Architecture | 9/10 | every fast path has a verbatim fallback or a validated cache; protected functions untouched; `verify-chains` fail-closed at two layers |
| Code Quality | 8/10 | ~110 lines of cache helpers (each ≤ 30), a 40-line memo function; sentinel-string class in `loa_knob` pre-existing; the conformance file now waits ~14 s for fixtures to settle |
| DevOps | 9/10 | manifests regenerated under the bounded marker at every System Zone commit; CI pytest list explicit; red-test-check VERIFIED ×10 |
| Blockchain | N/A | — |

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

None.

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] profile-lib `effective-config.json` cache lacks the trust boundary its sibling has (pre-existing)

- **MEDIUM** (confidence: high) `.claude/scripts/lib/profile-lib.sh:181-216` — `_loa_pl_write_cache` writes `<cache>.tmp.$$` with a shell redirect and `mv -f`, and `_loa_pl_load` reads `.run/effective-config.json` with no ownership, mode or symlink check, while `loa_knob` serves any key present in the cache (floor keys are excluded only at write time). Failure: when a co-tenant can write the checkout's `.run` but not the tracked config files then they plant a forged cache carrying the current id and every hook in the victim's shell reads the attacker's knob values until a config, profiles or floor stamp changes, and a sprayed `effective-config.json.tmp.<pid>` symlink makes the victim's next write clobber a file of the attacker's choosing (DISS-C-001, DISS-C-002, companion voice).
**Status:** pre-existing — the cache code has no hunk in this sprint's diff; the sprint only added `cached_keys` (one non-floor karpathy knob) to its content. Precondition narrower than voiced: under umask 002 the tracked files are group-writable too, so the cache adds no capability there.
**Fix (bead bd-j34zb):** apply the decisions-cache boundary (`_gi_trusted_dir` semantics on `.run`; `[[ -f && ! -L ]]`; read through an opened fd) before every read and write, and write with `mktemp` under umask 077 + `[[ ! -L ]]` + `mv -f -T`; red-first with the planted-temp-symlink and foreign-owned-dir fixtures from `grimoire-index.bats`; mirror parity for the karpathy hook. Recorded as DEC-1136.

### [MED-002] AGC-29 and AGC-31 passed by bypass after the round-2 rule (FIXED in this sprint)

- **MEDIUM** (confidence: high) `tests/unit/agy-gate-conformance.bats:788-845` — before 03f910129 the mv-replacement, deletion and path-switch cases read fresh fixtures, which the current-second rule never memoises, and AGC-31 forged a key without the `PATH` component that could never match. Failure: when a regression dropped the reset-at-load or a key component from `_agy_opt_in_node_memo` then both tests still passed because no call was ever served from the memo (DISS-C-003, companion voice).
**Status:** FIXED — 03f910129 ages and settles each fixture, asserts one read for two calls before every mutation, forges the real in-shell key and adds the control that proves the forge would hit without the reset (36/36). DEC-1138.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] an absent chain file counts as valid in `loa-status` (pre-existing)

- **LOW** (confidence: high) `.claude/scripts/loa-status.sh:425-434` — a missing L1–L6 chain file is counted as "validates by absence", a rule that predates this sprint (present at 747b5db0d). Failure: when someone who tampered with a chain file and sees a red count deletes the file then `loa-status` reports 7/7 and the operator's only in-tool integrity view is silenced (DISS-C-004). Bead bd-hyah6: a third state (valid / absent / broken), never 7/7 with a missing slot.

### [LOW-002] `forbidden()` has no descendant clause for a mapping-level floor key (pre-existing)

- **LOW** (confidence: medium) `.claude/scripts/lib/profile-lib.sh:131` — the floor check catches a glob match and an ANCESTOR of a floor key but not a DESCENDANT of a floor entry naming a mapping. Failure: when a future floor entry names a mapping then a profile or cached key one level below it is served with no WARN; today's floor list (`fence:*`, `gate:*`, `policy:*` tokens) has no such entry, so there is no live exposure (DISS-C-005). Bead bd-7utms.

### [LOW-003] `KARPATHY_CHECKPOINT_CMD` is honoured from the ambient environment (pre-existing)

- **LOW** (confidence: high) `.claude/hooks/quality/karpathy-surgical-diff-check.sh:62` — the checkpoint reader command comes from an environment variable outside any bats gate, as it did at 747b5db0d. Failure: when a `.envrc`, a CI job or a re-exporting subprocess leaks the variable then the hook runs an arbitrary same-uid script for its checkpoint read — a hardening gap against the project's seam policy, not a boundary break (DISS-C-007). Bead bd-yos4s.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Cross-Model Observations

`adversarial-review.sh --type audit --sprint-id sprint-282 --diff-file <code-only diff 747b5db0d..c31089280, 155 KB> --context-file auditor-concerns.md --budget 900 --json` (run 3 of the sprint's ≤ 3). Envelope `adversarial-audit.json`: status `clean`, `verdict_quality` 2/2 voices (codex-headless gpt-5.5-pro, claude-headless), no voice dropped, confidence floor high, cost 0. Eight findings, all from the companion voice; triage:
- DISS-C-001 HIGH + DISS-C-002 MEDIUM → MED-001 (pre-existing, graded MEDIUM, bead, DEC-1136).
- DISS-C-003 MEDIUM → MED-002 (CONFIRMED, fixed in 03f910129, DEC-1138).
- DISS-C-004 MEDIUM → LOW-001 (pre-existing design, bead).
- DISS-C-005 LOW → LOW-002 (pre-existing; no live floor entry affected; bead).
- DISS-C-006 LOW (a FIFO at the cache path blocks every run) → NOT CONFIRMED: probed in a scratch mirror (`~/.cache/loa/cycle-137/scripts/cache-fifo-probe.py`) — the reader requires `-f`, never opens the FIFO, the writer's `mv -T` replaces it; rc 0, two runs identical, no hang; pinned by two new `grimoire-index.bats` cases (DEC-1137).
- DISS-C-007 LOW → LOW-003 (pre-existing, bead).
- DISS-C-008 LOW (`CMP_STUB_HOLD_S=240` never reaches the stub) → NOT CONFIRMED: the stub is the test process's own `invoke_dissenter` shim, which expands `${CMP_STUB_HOLD_S:-300}` after `setup()` set it; the serial wall time fell 872 → 667 s, matching three 60 s shorter holds; CMP-55 pins 300 deliberately (DEC-1137).
The primary voice returned no finding. Round 1's companion timeout (KF-037 class) did not recur in either later run.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets, tokens or keys in the diff (every patch read; the token-shaped strings are pre-existing fixture probes)
- [x] No credential file, push configuration or trust store touched

### Authentication & Authorization
- [x] The agy consent flag (`agy_opt_in`) is re-read on any content, permission or path change and within one second of any stamp; the permission rule (`_agy_config_untrusted`) unchanged and exercised by AGC-34
- [x] The decisions cache trusts only a uid-owned, non-group-writable directory; tightening removes bits on our own directory only

### Input Validation
- [x] Cache rows validated (header key, count, 9 fields, alphabet, NUL) before any byte is printed
- [x] Verifier records validated by index, type and byte-exact path echo; the default is FAILED
- [x] Every stat/clock value regex-gated before arithmetic (`^[0-9]+$`)
- [x] KF bodies, decisions rows and knob values stay data to static awk/jq/yq programs

### Data Privacy
- [x] No new data leaves the host; the cache holds sanitised index rows already published in INDEX.md
- [x] Traces, shims and probes in tests stay under BATS temp directories

### Supply Chain
- [x] Dependencies unchanged (jq ≥ 1.6, yq v4, python3; `cryptography` already pinned in the workflow for the trust-policy tests); CI gains one explicit pytest path
- [x] `.claude/checksums.json` consistent (`check-loa.sh` All checks passed on c31089280; `check-manifest-paths.sh` 2080 entries, 0 untracked, 0 missing; 03f910129 touches no System Zone file)

### API Security
- [x] N/A — no network surface added

---

## Threat Model Summary

| Actor | Vector | Control | Residual |
|---|---|---|---|
| Local non-owner user | plant or edit `.run/perf-cache/*.tsv` | directory ownership + mode gate; reader alphabet; `<>` excluded | none when `.run` is owned by the operator; a repo intentionally shared with group write is tightened on first run (documented) |
| Local non-owner user | swap `.run/perf-cache` for a symlink; plant a symlink, FIFO or hard link at the cache path | `[[ ! -L ]]` gates; `-f` before reading; `mv -T` replaces the planted entry | TOCTOU requires write on `.run`, i.e. the owner |
| Local non-owner user | plant `.run/effective-config.json` or spray its temp-name symlinks | none today (pre-existing) | MED-001 → bd-j34zb; needs `.run` writable while the config files are not |
| Operator (revoking consent mid-run) | same-size rewrite / chmod of `.loa.config.yaml` within one second | mtime+ctime current-second rule with a one-second margin (AGC-33 … AGC-36) | remote filesystem with a server clock behind the host (DEC-1132) |
| Environment | an inherited `EPOCHSECONDS` on bash < 5; an inherited memo variable | not consulted; memo reset at load (AGC-31 with control) | `KARPATHY_CHECKPOINT_CMD` seam (LOW-003, pre-existing) |
| Chain file author (L1–L6 bodies) | craft or delete a chain file | bodies verified by the unchanged `audit_verify_chain`; records re-validated by index | absence counted valid (LOW-001, pre-existing) |
| Agent-authored decisions.yaml | smuggle markup through the cache | sanitiser output alphabet excludes `<>`; `render_md` escapes `|` | a misleading row in a generated table, not code execution |

---

## Positive Findings

- Three review rounds and the audit dissent each found something real in the memo and each was closed red-first with deterministic shims; every memo property (hit, miss per key component, reset at load, invalidation per mutation, current-second bypass for mtime and ctime) is pinned.
- The cache trust check tightens instead of silently ignoring a group-writable directory the operator owns (the live `.run/perf-cache` was 775 from umask 002 — the cache had been inert), and the change is documented in the CHANGELOG and release notes with a bead for the creator.
- `verify-chains` is provably no weaker than N per-call verifications (six store-mutation schedules equal two oracles) and strictly fail-closed in the wrapper and in `loa-status`.
- Every stat-derived or clock-derived number is validated before it reaches shell arithmetic; no new `eval`, `source` of data or interpolated `bash -c`.
- Two dissent findings were settled by running the code rather than by argument, and the probes became tests.

---

## Recommendations

### Immediate Actions (24 Hours)
- None required for the release candidate.

### Short-Term Actions (1 Week — next cycle)
- bd-j34zb: the profile-lib cache trust boundary and `mktemp` writer (MED-001).
- bd-20bh1: create `.run/perf-cache` under umask 077 in zone-write-guard so the tightening is a no-op on fresh mounts.
- bd-hyah6: absent chain files as a third state in `loa-status` (LOW-001).
- bd-5v1oa: a warm-path spawn budget for the grimoire-index cache hit.

### Long-Term Actions (1 Month)
- bd-7utms, bd-yos4s: the floor descendant clause and the karpathy seam gate.
- bd-aceil: verify `_gi_dec_read` and `fieldval` on a BWK awk host (the reader fails closed there, never open).
- Tag `loa_knob` results as JSON to retire the sentinel-string class (`__LOA_PL_*`); bd-rq6gk: make CMP-55 assert the reap attempt.

---

## Verdict

**APPROVED - LET'S FUCKING GO**

Sprint 282 (cycle-137 sprint-2) is approved on reviewed head 03f910129: no critical or high finding; one medium finding fixed in the sprint, one medium and three low findings pre-existing and recorded with beads and decision rows; none blocks the release candidate. `COMPLETED` follows this file; the Sprint Ledger marks sprint 282 `completed`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-282","ts":"2026-10-28T07:45:00Z"} -->
