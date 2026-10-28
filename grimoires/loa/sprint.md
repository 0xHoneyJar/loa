# Sprint Plan: Performance follow-ups (cycle-137)

**Version:** 1.0
**Date:** 2026-10-28
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.0, FR-1 … FR-8, G-1 … G-6)
**SDD Reference:** `grimoires/loa/sdd.md` (1.0, C-1 … C-8, § 5.1 … § 5.8, D-2.1 … D-8.1)
**Ledger:** cycle `cycle-137-performance-followups`, sprint globals 281 (local sprint-1) and 282 (local sprint-2)
**Execution:** Sprint 1 is already implemented (the 20 loop commits): the lead writes `a2a/sprint-281/reviewer.md`, then runs `/review-sprint sprint-1` and `/audit-sprint sprint-1` directly (no `/run`, nothing to implement). Sprint 2 runs under `/run sprint-2 --local` (implement → review → audit with the circuit breaker; no push and no PR from run mode); the PR, Bridgebuilder rounds, merge, record, archive and the rc.9 publish are the lead's ship tasks afterwards. Implementers are Opus 5.5 (`global.anthropic.claude-opus-5-5`) in linked worktrees returning `git diff --cached` patches (test patch first, then fix); the lead lands, reviews, audits and ships. CHANGELOG lines are returned as text in the reports and inserted by the lead. Bounded-loop exits (unattended): a patch returned for allowlist or red-test violations more than twice → the lead implements or defers the task with a bead and a DEC row; a dissent voice unreachable → lead-only gate, recorded; Bridgebuilder rounds exhausted with fixes still needed → the fixes land red-first, lead-read, recorded; spend cap or the one-day window reached → HALT with the state recorded.
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); the lead's tasks are `judgment`; no `operator` task exists — the operator's instruction of 2026-10-28 authorises the whole cycle including the release; proposed decision rows are confirmed at the close.
**Spend:** USD 30 cap in the meter's unit: Flatline reviews, dissent runs and Bridgebuilder rounds on subscription routes; real charges ≈ 0.

## Executive Summary

Two sprints. Sprint 1 (global 281) takes the 22-pass optimisation loop — 20 commits already on this branch, each proven byte-identical and Opus-reviewed — through the framework's formal review and audit gates; only gate fixes land. Sprint 2 (global 282) closes the six follow-up beads the loop filed (bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli, bd-09z1i) with the same discipline (profile, golden, one lever, old-vs-new mirror parity, red-first tests), then ships one PR through a Bridgebuilder round, the record branch, the archive and the `v2.0.0-rc.9` release candidate.

## Sprint Overview

| Sprint | Global | Goal | Owners |
|---|---|---|---|
| Sprint 1 | 281 | FR-1: the loop reviewed and audited; G-1, G-3, G-4 evidenced | lead |
| Sprint 2 | 282 | FR-2 … FR-7 implemented and tested; FR-8 shipped; G-2, G-5, G-6 | lead, A, B, C, D |

Duration: one unattended day (2026-10-28). Team: the lead plus up to four Opus 5.5 implementers (A shell: C-2 + C-5; B shell: C-3 + C-4; C tests: C-6; D python+shell: C-7). Cadence: implementers return patches; the lead lands them in dependency order and runs the gates.

## Sprint 1: Formal gates on the optimisation loop (global 281)

### Sprint Goal

`/review-sprint` ends `All good` and `/audit-sprint` ends `APPROVED` on the 20 loop commits, with any fix landed red-first and the touched passes' parity harnesses re-run; `COMPLETED` written; ledger sprint 281 completed.

### Deliverables

- `grimoires/loa/a2a/sprint-281/reviewer.md`: the engineer's report — one row per productive pass (target, lever, parity evidence and inputs, covering bats and counts, before/after, review verdict, commit), the two no-change passes with their floors, the final re-baseline table, the full-suite result, and the `## AC Verification` walkthrough of FR-1's criteria (C-1).
- `engineer-feedback.md` (review) and `auditor-sprint-feedback.md` (audit) with `LOA-VERDICT` trailers; fix commits where the gates find anything (each with `checksums.json` + REPO-MAP regenerated).
- `a2a/sprint-281/e2e.md` with the G-1 / G-3 / G-4 evidence.

### Acceptance Criteria

- [ ] FR-1 AC rows all green: `reviewer.md` walkthrough complete for passes 1–11, 13, 14, 16–22 and the no-change passes 12 and 15; review `All good`; audit `APPROVED`; `verdict-derive.sh --gate review` and `--gate audit` CONSISTENT; `COMPLETED` written; ledger 281 `completed`.
- [ ] Every gate fix commit is red-first where behaviour changes and byte-identical old-vs-new where a loop file's implementation changes; the pass's `~/.cache/loa/eso-loop/pass-K/` harness re-run on the final head.
- [ ] `tests/unit/perf-spawn-budget.bats` 6/6, `check-loa.sh` passes, `repo-map-gen.sh --validate` passes on the final Sprint 1 head.
- [ ] G-3: the re-baseline of `~/.cache/loa/eso-loop/rebaseline.sh` on the final head within 10 % of `final-table.tsv` for every touched row.
- [ ] G-4: the full `tests/unit` TAP on the final head shows no failure beyond the KF-034 `semver-evidence` reds; CMP-37 passes in isolation.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 1.0: Engineer's report (lead) — write `a2a/sprint-281/reviewer.md` from `.skill-loop-progress.md` § LOOP 2, the per-pass `REPORT.md` / `review/VERDICT.md` files, `final-table.tsv` and `bats-final/unit.tap`: per pass the parity inputs and comparison, the bats files and counts, the before/after numbers, the verdict and the commit; the no-change passes; the `## AC Verification` section mapping each FR-1 criterion to evidence. → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 1.1: Review (lead) — `/review-sprint sprint-1` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs over `main..HEAD`); findings fixed red-first (behaviour) or with a mirror parity proof (implementation), manifests regenerated per commit; `engineer-feedback.md` C-11 grammar, verdict-derive consistent; a non-fixable finding reverts that single loop commit with a DEC row. → **[G-1]** ⇐ 1.0 · kind: judgment
- [ ] Task 1.2: Audit (lead) — `/audit-sprint sprint-1` → `auditor-sprint-feedback.md`; fixes as 1.1; `COMPLETED`; ledger sprint 281 `completed` (set `completed` with jq under bash — ledger-lib sets only the status). → **[G-1]** ⇐ 1.1 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation (lead) — `a2a/sprint-281/e2e.md`: G-1 (the two verdicts, the marker), G-3 (re-baseline table within 10 %, guard 6/6), G-4 (full-suite TAP summary; CMP-37 alone). → **[G-1, G-3, G-4]** ⇐ 1.2 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| lead only | any loop file a gate finding names, with `checksums.json` + REPO-MAP regenerated; `a2a/sprint-281/**`; `.skill-loop-progress.md` | the 20 loop commits' history (no squash, no rebase) |

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| Old-vs-new mirror of each loop file in a REAL directory over the pass's fixture matrix | an implementation change that alters bytes, exit code or stderr | hosts with other awk/yq versions (noted UNVERIFIED per pass) | `~/.cache/loa/eso-loop/pass-K/review/` harnesses |
| `tests/unit/perf-spawn-budget.bats` over fixed fixtures | a spawn added to a guarded hot path | spawns on paths without a fixture (karpathy until Sprint 2) | pass 22 |
| The covering bats suites per touched file (repo-map-gen, grimoire-index, kf-surface, run-checkpoint*, compat-*, implement-gate, notes-size-guard, run-state-surface, cache-manager, loa-status*, guard-yield, adapter pytest, karpathy*, push-gate) | a behaviour regression a parity fixture did not cover | — | the loop's per-pass test runs |

### Dependencies

- Internal: 1.0 → 1.1 → 1.2 → 1.E2E. External: none beyond the host toolchain (bash 5, jq 1.7, mikefarah yq 4.44, Python 3.13, bats 1.13 via npx, hyperfine 2.0).

### Security Considerations

- The loop touched four fences (implement-gate, notes-size-guard, karpathy, run-mode-stop-guard) and one trust surface (kf-surface): the review re-reads their fail-open / fail-closed paths and the sanitisers; any widening is a blocking finding.
- The audit confirms no new eval/source of untrusted data, atomic-write semantics on the new `.run/perf-cache`-style paths (none added in the loop), and that the lazy provider imports change no credential handling.

### Risks & Mitigation

- Risk: the formal review finds a parity gap the per-pass reviews missed → fix red-first and re-run the pass harness; a non-fixable one reverts that single commit (one pass = one commit).
- Risk: dissent voices unreachable (KF-037/KF-041 shapes) → ≤ 3 runs, then lead-only gate recorded in a DEC row.
- Risk: the review's own bats runs load the host and CMP-37 fails → run the file alone and record it.

### Success Metrics

- G-1: review `All good`, audit `APPROVED`, `COMPLETED` present.
- G-3: re-baseline within 10 %; guard 6/6.
- G-4: full suite green modulo KF-034.

> Sources: prd.md § FR-1, § Goals; sdd.md § 1.4 C-1, § 7; `.skill-loop-progress.md` § LOOP 2

---

## Sprint 2: The six follow-up beads and the ship (global 282)

### Sprint Goal

Close bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli and bd-09z1i with red-first tests and byte-identical outputs where output exists; ship both sprints as one PR with a non-degraded Bridgebuilder verdict; record and archive the cycle; publish `v2.0.0-rc.9`.

### Deliverables

- C-2: shape-C field regex and H2 `cur` reset in both KF parsers; `kf-surface.bats` and `grimoire-index.bats` cases (A).
- C-5: `grimoire-index.sh` content-keyed decisions cache under `.run/perf-cache/`, `LOA_GRIMOIRE_INDEX_NO_CACHE=1`, one write-mode jq for `bad` + `total`; bats cases (A).
- C-3: `_anthropic_ceiling_json` six-line yq protocol with fallback; `_agy_opt_in_node_memo` in `agy-gate-lib.sh`; bats cases (B).
- C-4: `profiles.yaml` `cached_keys` + cache-builder support + `loa_knob` absent-source fast path; `profile-lib.bats` cases; karpathy target added to `perf-spawn-budget.bats` (B).
- C-6: `block-destructive-bash.bats` corpus-once `setup_file`; `adversarial-review-companion.bats` bounded waits; TAP-set parity evidence (C).
- C-7: `audit-envelope.sh verify-chains` + the Python batch entry; `loa-status.sh` switched to one call; bats and the security suite green (D).
- CHANGELOG `[Unreleased]` lines per bead (lead inserts the implementers' texts); the rc.9 heading at ship; README pin; `.loa-version.json`.
- One PR, Bridgebuilder round(s), record branch, archive, release candidate published, beads closed, JACKED_OUT (FR-8).

### Acceptance Criteria

- [ ] FR-2 AC rows all green (shape C parsed in both parsers, shape B still parsed, `## KF-abc:` resets, live file byte-identical for the hook stdout and `--tsv/--json/write`).
- [ ] FR-3 AC rows all green (mirror parity on live/--json/--help/bogus/no-yq and the config matrix; `yq` count 1 in `_anthropic_ceiling_json`; ≥ 40 ms; agy bats).
- [ ] FR-4 AC rows all green (warm cache resolves `diff_lines_per_task` without `yq`; override / profile default / hard default identical to the live path; `loa_profile` output unchanged; karpathy state files identical across the pass-19 matrix; new spawn-budget target).
- [ ] FR-5 AC rows all green (cold/warm parity on all modes; invalidation on content change; corrupt / symlink / read-only cache ignored; `NO_CACHE=1`; warm ≤ 650 ms; budget updated with reason).
- [ ] FR-6 AC rows green or the measured floor recorded by a DEC row (pass/fail/skip set identical per test name; corpus run once; companion wall time ≤ 300 s or the floor).
- [ ] FR-7 AC rows all green ((a) implemented per sdd.md § 5.7: per-path results equal per-call results on live and fixture chains; `test_audit_trust_policy.py` green; the 44 audit-envelope bats files green; ≥ 100 ms on a 5-chain fixture root) or (b) deferred by DEC row with the bead relabelled.
- [ ] Each red commit fails only its own new cases (`red-test-check.sh`); each fix commit green; `checksums.json` and REPO-MAP regenerated in every System Zone commit; `check-no-raw-sha256sum.sh`, `check-no-swallowed-jq.sh --quiet`, `check-loa.sh`, `repo-map-gen.sh --validate`, `perf-spawn-budget.bats` green at every fix commit and the final head.
- [ ] Review `All good`, audit `APPROVED`, `COMPLETED`; PR merged only when every check run on the exact final head is completed and the six required checks — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — are `success`; CI mirror from the final head shows only the KF-034 reds; Bridgebuilder ≤ 2 rounds, non-degraded; record stage 1 pushed; archive merge classifies `housekeeping`; `v2.0.0-rc.9` published and reachable from `main`; six beads closed (or bd-09z1i deferred); ledger cycle archived; JACKED_OUT.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 2.0: Sprint prep (lead) — rotate NOTES.md (`notes-guard.sh rotate`) if it is within 10 KiB of the 200 KiB block line; write the implementer briefs under `~/.cache/loa/cycle-137/briefs/` (one per implementer: allowlist, SDD section, fixtures, parity recipe with REAL-directory mirrors, red-first rule, no live push config, no deletions under the System Zone, zsh word-split note); create the four worktrees. → **[G-2]** ⇐ none · kind: judgment
- [ ] Task 2.1: KF shape-C regex and H2 reset (A, System Zone) — `loa-kf-surface.sh` and `grimoire-index.sh` `fieldval`: add shape C (`^(- )?\*\*LABEL( [^*]*)?\*\*: ?`), reset `cur` on every `^## ` line (sdd § 5.1); `kf-surface.bats` and `grimoire-index.bats` red-first cases: shape C parsed, shape B still parsed, `**Symptomatic**:` not a field, `## KF-abc:` resets, `## Index` fields ignored; live-file parity (hook stdout; `--tsv/--json/write`) byte-identical; busybox awk still runs both programs. → **[G-2]** ⇐ 2.0 · kind: mechanical
- [ ] Task 2.2: grimoire-index decisions cache and one write-mode jq (A, System Zone) — sdd § 5.5: key `v1:<sha256_portable of decisions.yaml>:<yq major.minor>` first line of `.run/perf-cache/grimoire-index-decisions.v1.tsv`; hit → print cached rows; miss → today's pipeline then atomic write (umask 077, `$$` temp, `mv -f -T`/`mv -f`, never under CI, never fatal, symlink refused); `LOA_GRIMOIRE_INDEX_NO_CACHE=1`; the unparsable-ledger NOTE path caches nothing; write-mode `bad` and `total` from one jq; bats red-first (hit skips yq by trace, miss rebuilds, content change invalidates, corrupt/symlink/read-only ignored, NO_CACHE); cold/warm parity on all modes; `perf-spawn-budget.bats` grimoire-index budget updated with the reason in the same commit. → **[G-2]** ⇐ 2.1 · kind: mechanical
- [ ] Task 2.3: loa-status six-line yq and the agy node memo (B, System Zone) — sdd § 5.2 and § 5.3: one `yq eval -r` emitting alias + five fields, accepted only as exactly six lines, else today's reads verbatim; `_agy_opt_in_node_memo` keyed by `<cfg>|dev:ino:size:mtime`, used by `agy_opted_in` and `agy_gate_warn_once`; bats red-first (`loa-status-providers.bats`: protocol + multi-line fallback; `agy-gate-conformance.bats`: memo hit, miss after rewrite, subshell caller unaffected); mirror parity over live/--json/--help/bogus/no-yq and the config matrix (alias absent; model without ceiling fields; opt_in true/false/"true"/absent); hyperfine ≥ 40 ms; `yq` count 1 in the function's trace. → **[G-2]** ⇐ 2.0 · kind: mechanical
- [ ] Task 2.4: profile-lib `cached_keys` (B, System Zone) — sdd § 5.4: `profiles.yaml` top-level `cached_keys: [karpathy_principles.diff_lines_per_task]`; the cache builder records `{value, source: explicit|absent, profile_value: null}` for listed non-profile keys; `profile_keys` and `overrides` unchanged; `loa_knob` warm-cache `absent` → fallback without `yq`; bats red-first in `profile-lib.bats` (absent → fallback, explicit wins, stale id → live, `loa_profile` output byte-identical, cache JSON differs only by the new knob entry); karpathy hook state files identical across the pass-19 matrix (`~/.cache/loa/eso-loop/pass-19/` harness); `perf-spawn-budget.bats` gains a karpathy target (fixed fixture + warm cache) measured and budgeted in the same commit. → **[G-2]** ⇐ 2.3 · kind: mechanical
- [ ] Task 2.5: Test-suite runtime (C, tests only) — sdd § 5.6: `block-destructive-bash.bats` `setup_file` runs the corpus once into `$BATS_FILE_TMPDIR/corpus.json`, `corpus_json()` reads it (the runtime test reads `runtime_ms` of that run); `adversarial-review-companion.bats`: `bats -T` profile first, then shorten only fixed sleeps no test waits on and keep every hold ≥ 2× the longest wait on it (`CMP_STUB_HOLD_S`, default 300); no assertion, expected value or skip condition changes; TAP pass/fail/skip set per test name identical before and after (serial); report the measured floor; if the companion file stays above 300 s, the report names the floor and the lead records the DEC row adjusting FR-6. → **[G-2]** ⇐ 2.0 · kind: mechanical
- [ ] Task 2.6: `verify-chains` (D, System Zone) — sdd § 5.7: `audit-envelope.sh verify-chains <path>…` → one Python process, `audit_verify_chain` per path, `ok <path>` / `FAIL <path>: <msg>` lines, exit 0/1; `_check_trust_store` untouched; `loa-status.sh:415-435` makes one call and reproduces today's `valid` count (missing files still valid by absence); bats red-first: valid/tampered/broken-link/missing/empty chains per path, a tampered trust store fails every path with the same `[TRUST-STORE-INVALID]` text, single `verify-chain` unchanged; `pytest tests/security/test_audit_trust_policy.py` green; the 44 audit-envelope bats files green; hyperfine on a 5-chain fixture root ≥ 100 ms; loa-status mirror parity. If the security suite cannot stay green without touching `_check_trust_store`, STOP and return the measurement for a DEC-row deferral. → **[G-2]** ⇐ 2.3 · kind: mechanical
- [ ] Task 2.7: Sprint close (lead) — land A (2.1, 2.2), B (2.3, 2.4), C (2.5), D (2.6) as red commit then fix commit each, under the marker with `checksums.json` and REPO-MAP regenerated; `red-test-check.sh` per red commit; the implementers' CHANGELOG texts inserted; `perf-spawn-budget.bats` budgets updated where a task says so; `rebaseline.sh` re-run and the table recorded; DEC rows for every judgment call (D-2.1 … D-8.1 and the implementers'); beads bd-atk7q, bd-gv5jf, bd-h5tcn, bd-1mfm7, bd-wctli closed with evidence, bd-09z1i closed or relabelled `deferred-cycle-137`. → **[G-2]** ⇐ 2.2, 2.4, 2.5, 2.6 · kind: judgment
- [ ] Task 2.8: Review and audit (lead) — `/review-sprint sprint-2` (≤ 3 dissent runs, code-only diffs since the Sprint 1 head), `engineer-feedback.md` (C-11 grammar, verdict-derive consistent); `/audit-sprint sprint-2` → `auditor-sprint-feedback.md`, `COMPLETED`, ledger sprint 282 `completed`. → **[G-2]** ⇐ 2.7 · kind: judgment
- [ ] Task 2.9: Ship (lead) — secret scan; CHANGELOG `[Unreleased]` → `## [2.0.0-rc.9] — <date> — Performance follow-ups (release candidate)` with the rc.8 version markers; `.loa-version.json` and README pin bumped; CI mirror (full unit suite) from the head; PR from `feature/cycle-137-performance` (title names the behaviour changes and classifies `cycle`; body lists both sprints, beads, DEC rows, gates and Bridgebuilder outcomes per head sha); Bridgebuilder ≤ 2 rounds (`BRIDGEBUILDER_MODEL=codex-headless`, generated and planning files excluded), fixes red-first; merge via the cycle-135 `ship-1` recipe only when every check on the exact head is green; `ship-2` record (`--cycle 137 --prev origin/record/cycle-136-bridgebuilder-followups`, `--accept-scan` only for the `audit-key-password-assignment` NOTES hit); post-merge candidate: publish from a non-shallow clone with `--approve-sha256`, verify the tag is an ancestor of `origin/main` and the release page exists; `ship-3*` archive (`archive-cycle.sh --cycle 137 --retention 50`, housekeeping merge); `ship-4` close (JACKED_OUT, parked copies, `main`). → **[G-5, G-6]** ⇐ 2.8 · kind: judgment
- [ ] Task 2.E2E: Sprint 2 goal validation (lead) — `a2a/sprint-282/e2e.md`: G-2 (six beads with commit + test, or the deferral row), G-5 (check runs on the merged head; Bridgebuilder summary; record and archive shas), G-6 (tag + release URL; `git merge-base --is-ancestor`). → **[G-2, G-5, G-6]** ⇐ 2.9 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh`, `tests/unit/kf-surface.bats`, `tests/unit/grimoire-index.bats`, `tests/unit/perf-spawn-budget.bats` (the grimoire-index budget line and comment only) | `CHANGELOG.md` (text returned in the report), `checksums.json`, REPO-MAP (lead regenerates), any other hook or script |
| B | `.claude/scripts/loa-status.sh` (`_anthropic_ceiling_json` only), `.claude/scripts/lib/agy-gate-lib.sh`, `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml`, `tests/unit/loa-status-providers.bats`, `tests/unit/agy-gate-conformance.bats`, `tests/unit/profile-lib.bats`, `tests/unit/perf-spawn-budget.bats` (the new karpathy target only) | `CHANGELOG.md`, manifests, the karpathy hook itself, any other `loa-status.sh` function |
| C | `tests/unit/block-destructive-bash.bats`, `tests/unit/adversarial-review-companion.bats` | anything under `.claude/`, any other test file, `tests/fixtures/**` |
| D | `.claude/scripts/audit-envelope.sh`, `.claude/adapters/loa_cheval/audit_envelope.py` (a new batch entry point only — `_check_trust_store`, `_trust_store_snapshot`, `audit_verify_chain` bodies untouched), `.claude/scripts/loa-status.sh` (the `verify-chain` loop at 415-435 only), `tests/unit/audit-envelope*.bats` (new cases only) | `CHANGELOG.md`, manifests, `audit-signing-helper.py`, `tests/security/**`, any chain file under `.run/` or `grimoires/` |

A patch outside its allowlist is returned, not landed. Implementers make no live model or GitHub calls, never run anything with the live push configuration, never write under `.run/` of the main checkout, and never commit, push or stash in their worktrees. Parity mirrors live under paths without `.claude` in them or with the file under test in a REAL directory.

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `fieldval` over fixtures of the three field shapes, a `**Symptomatic**:` decoy, `## KF-abc:` and `## Index` sections, plus the live file | a shape parsed differently between the two parsers; a field attached to the wrong entry | field shapes nobody writes (e.g. `__Label__:`) | pass-6 reviewer fixtures fx_e/fx_all |
| `_anthropic_ceiling_json` six-line protocol vs the per-field reads on the config matrix (alias absent, ceiling fields absent, multi-line value) | a value shift or a dropped field; a multi-line value swallowed | yq versions other than mikefarah 4.44 (UNVERIFIED) | pass 18's three-line protocol |
| `_agy_opt_in_node_memo` with a rewritten config between calls and a `$(...)` caller | a stale node after a rewrite; a memo leak across configs | a config rewritten with identical dev/ino/size/mtime within one second | pass 14's memo |
| `loa_knob` on a warm cache for an absent cached key, an explicit value, a stale id | a wrong fallback; a profile-keys change; an `overrides` change | profile-lib callers outside the hook set (10 callers — the cache builder test covers `loa_profile`) | `profile-lib.bats` |
| decisions cache hit / miss / invalidation / corrupt / symlink / read-only / NO_CACHE, cold and warm, all four modes | stale rows; a cache write that is fatal; a cache followed through a symlink | concurrent writers (last writer wins; both outputs are correct) | zone-write-guard's perf-cache |
| TAP pass/fail/skip set per test name for the two test files, serial, before vs after | a changed verdict; a dropped test | wall-time on CI runners (recorded, not asserted) | pass 21 |
| `verify-chains` per-path results vs `verify-chain` per-call results on live and fixture chains, with a tampered trust store | a per-path divergence; a trust decision changed by batching | hosts without the signing helper (same refusal as today) | `test_audit_trust_policy.py` |

### Dependencies

- Internal: 2.0 → 2.1 → 2.2 (A, same file area); 2.0 → 2.3 → 2.4 (B) and 2.3 → 2.6 (D touches `loa-status.sh` after B); 2.0 → 2.5 (C, independent); 2.7 after 2.2, 2.4, 2.5, 2.6; 2.8 after 2.7; 2.9 after 2.8 and after Sprint 1 `COMPLETED`; 2.E2E after 2.9.
- External: host toolchain only (bash 5, jq 1.7, mikefarah yq 4.44, Python 3.13 with the repo `.venv` for pytest, bats 1.13 via npx, hyperfine 2.0, busybox for the awk portability check, `gh` 2.x authenticated for the ship).

### Security Considerations

- The KF parsers surface untrusted text: the change widens which lines are recognised as fields, never what is done with them — sanitisation (`san()`, the jq `s` filter) is unchanged; busybox and mawk run the regexes.
- Caches: content-keyed, atomic, symlink-refusing, never fatal, never written under CI; a forged cache is served only to whoever could already write the source file (the pass-6 trust argument of the 2026-07 loop).
- `verify-chains` keeps `_check_trust_store` and its subprocess-over-snapshot defence untouched; chains are read-only inputs; the security suite is a gate.
- The agy memo keys on file identity so a rewritten config is re-read; the subshell reader keeps its fd-9 open-once check.
- Implementers never touch the live push config, credentials, `.run/` of the main checkout or the `br` contract calls; secret scan before every push.

### Risks & Mitigation

- Risk: shape C over-matches → space-after-label requirement; decoy fixtures.
- Risk: the six-line protocol swallows a newline → line-count gate and fallback; multi-line fixture.
- Risk: `cached_keys` changes visible profile output → `profile_keys`/`overrides` computed from profile keys only; `loa_profile` output pinned byte-identical.
- Risk: the companion file's floor is the script runtime → measured first; the AC moves to the floor by DEC row rather than forcing structural test changes.
- Risk: `verify-chains` alters a trust decision → untouched gate function; security suite; per-path vs per-call parity; else deferral.
- Risk: a Bridgebuilder round degrades (KF-010/KF-062) → prefix excludes for generated and planning files; ≤ 2 rounds; recorded.
- Risk: rc.9 publish (KF-034, KF-063) → rc.8 recipe; non-shallow clone; digest approval; ancestry check before announcing.
- Rollback: revert the single merge commit and regenerate manifests; each bead is one fix commit and reverts alone.

### Success Metrics

- G-2: 6 of 6 beads closed (or 5 + one deferral row) with commit and test.
- G-5: every check run green on the merged head; one PR; a non-degraded Bridgebuilder verdict; record and archive; spend ≤ USD 30.
- G-6: `v2.0.0-rc.9` tag reachable from `main`; release page present; `[Unreleased]` empty.

> Sources: prd.md § FR-2 … FR-8, § Goals; sdd.md § 3, § 5.1 … § 5.8, § 6, § 7, § 9, § 11.D; `~/.cache/loa/cycle-135/ship/*.sh`

---

## Appendix

### Goals (from prd.md § Goals & Success Metrics)

| Goal | Criterion | Evidence |
|---|---|---|
| G-1 | Review `All good` and audit `APPROVED` on the loop | `a2a/sprint-281/{engineer-feedback,auditor-sprint-feedback}.md`, `COMPLETED` |
| G-2 | Six beads closed (or one deferred by DEC row) | `br show` close reasons naming commit + test; `a2a/sprint-282/e2e.md` |
| G-3 | Gains hold; guard green | `rebaseline.sh` table within 10 %; `perf-spawn-budget.bats` 6/6 (7/7 after Task 2.4) |
| G-4 | Full suite green modulo KF-034 | the TAP summary on the final heads |
| G-5 | PR, Bridgebuilder, merge, record, archive | check runs on the merged head; Bridgebuilder summary; shas |
| G-6 | `v2.0.0-rc.9` published | tag + release URL; ancestry check |

### Flatline sprint review dispositions

(filled at 1.1 once `flatline-orchestrator.sh --phase sprint` completes)
