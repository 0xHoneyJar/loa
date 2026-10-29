# Sprint Plan: Hardening follow-ups (cycle-138)

**Version:** 1.1
**Date:** 2026-10-29
**Revision:** 1.1 carries SDD 1.2 / PRD 1.2 (the Flatline SDD review, SDD § 11.F): FR-2 by process substitution, FR-4's `.run` creators and repair owner, FR-1's trust lifetime and absent-`.run` creation, FR-6's one-stat component check, FR-11's last-line kind token, FR-7's portable top-K, FR-3's `not_applicable` (DEC-1165 … DEC-1170).
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md (1.2, FR-1 … FR-16, G-1 … G-4, Appendices D–E)
**SDD Reference:** grimoires/loa/sdd.md (1.2, C-1 … C-10, § 11.D decisions DEC-1148 … DEC-1156 and DEC-1165 … DEC-1170, § 11.F dispositions)
**Cycle:** `cycle-138-hardening-followups`, branch `feature/cycle-138-hardening-followups` from `main` fe52be893; ledger sprints 284, 285, 286

---

## Executive Summary

Fifteen follow-up beads from cycle-137 and sprint-bug-283, closed in three sprints ordered by exposure: the two trust boundaries and the release path first (profile-lib cache predicate, publisher bodies off argv, chain summary classification, umask-077 creators), the per-tool-call hooks and the known-failures surface second (karpathy seam and trajectory guards; KF control class, row cap and BSD contract), the test guards and one bounded refactor third, followed by the ship (one PR, Bridgebuilder ≤ 2 rounds, merge on green, record, archive — no release). Every task lands red-first from an implementer's patch, under the bounded System Zone marker with manifests regenerated, with byte-identical old-versus-new parity except the enumerated changes, and each sprint passes `/review-sprint` and `/audit-sprint` with ≤ 3 dissent runs (the third is the audit's). The unattended halt protocol (DEC-1160) bounds the cycle: a sprint that misses its gates after the dissent budget, or the T+20 h budget, HALTs at the sprint boundary and the PR ships the completed sprints.

**Total Sprints:** 3 (global 284, 285, 286)
**Sprint Duration:** ≈ 5 h each unattended (implement ≈ 2 h, gates ≈ 2 h, slack 1 h); the whole cycle inside one calendar day
**Estimated Completion:** 2026-10-30

**Execution:** `/run sprint-plan --local` (implement → review → audit per sprint with the circuit breaker; no push and no PR from run mode); implementers are Opus 5.5 agents in linked worktrees returning `git diff --cached` patches (test patch first, then fix) with a report file; the lead lands each patch under the marker (red run must fail only the new cases; fix run green; lint; manifests), reviews, audits and ships. Decision classes: S (self-confirmable under the operator's instruction, recorded as a `proposed` row) and H (needs the operator: anything that would publish, force-push, delete, or widen the System Zone list). Bounded exits: a patch returned twice for allowlist or red-test violations → the lead implements or defers with a bead and a class-S row; a dissent voice unreachable after ≤ 3 runs → the lead's review and the audit still run, the gap recorded (class S); a circuit-breaker trip → HALTED, fix forward once, then a real HALT; Bridgebuilder per PRD FR-16's degraded-exit procedure; the halt protocol of PRD § Constraints.

> Sources: prd.md § Executive Summary, § Constraints (halt protocol), FR-16; sdd.md § 8; cycle-137 sprint plan § Execution (the pattern carried)

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 284 | Security and the release path | C-4 umask-077 creators; C-3 chain classification; C-2 publisher bodies off argv; C-1 profile-lib trust predicate; FR-1 … FR-4 ACs green | None |
| 2 | 285 | Hooks and the known-failures surface | C-5 karpathy seam gate + trajectory guards; C-6 KF control class, 40-row cap, BSD contract (form a or b); FR-5 … FR-9 | Sprint 1 (C-1 lands before C-7 touches the same file; sequencing only) |
| 3 | 286 | Tests, guards, the bounded refactor, the ship | C-7 floor clause + presence metadata; C-8 three guards; C-9 providers (or deferral row); whole-head parity gate; `reviewer.md`; gates; E2E; then § Ship | Sprints 1–2 |

> Sources: sdd.md § 8 Development Phases; prd.md § Scope & Prioritization

---

## Sprint 1: Security and the release path (global 284)

**Duration:** ≈ 5 h unattended
**Dates:** 2026-10-29 (T+3 h) – 2026-10-29 (T+8 h)

### Sprint Goal

Close bd-20bh1, bd-hyah6, bd-qyvju and bd-j34zb with red-first tests and byte-identical outputs except the enumerated FR-3 change; the profile-lib cache reads and writes only under the trust predicate with zero added spawns; the publisher carries no body on argv; `loa-status` never counts an absent chain as valid.

### Deliverables

- [ ] C-4: `( umask 077; mkdir -p … )` around every `mkdir` that can create `.run/perf-cache` (zone-write-guard line 261 and any creator the enumeration finds); hook test under umask 002 → 0700 (A).
- [ ] C-3: `_an_audit_chain_classify` / `_an_audit_chain_summary` with the four states, the sum invariant, the per-primitive lines and the `audit_chain` JSON object (with `not_applicable`); the verify-chains contract cases (exit 2, duplicate / missing / unexpected index, empty list); LS-1 fixtures extended (B).
- [ ] C-2: `--rawfile body <(printf '%s' …)` process substitutions at the three body sites (no temp file, no trap — SDD 1.2 § 5.2); stub-recorded argv assertions; structural greps; the jq-failure case; oversized multi-byte fixtures (C).
- [ ] C-1: `_loa_pl_id` extended stat (dir + file rows, excluded from the id; rc ignored, fail-closed row parsing), `_loa_pl_cache_trusted` / `_loa_pl_cache_readable` (refuse, never chmod; anchored realpath on the seam), writer with `mkdir` (no `-p`) for an absent `.run`, builtin re-check, `mktemp` + `mv -T`; trust-lifetime comment; `loa_profile` cache-state line with one case per reason; the 775 `.run` repair row; drift guard against `grimoire-index.sh` (listed lines); the FR-1 fixtures; matrix parity for the karpathy hook (D).
- [ ] CHANGELOG `[Unreleased]` lines for FR-1 … FR-4 (implementers' texts, lead inserts).
- [ ] `a2a/sprint-284/reviewer.md` (FR-1 … FR-4 AC walkthrough, parity evidence, spawn-budget counts, red/fix shas) before Task 1.8.

### Acceptance Criteria

- [ ] FR-1 AC rows all green (the refusal/replacement fixtures incl. hard link, planted file, FIFO, redirected path with a symlinked component, mv-fallback shim, directory replaced between calls, a 775 `.run` refused — recording chmod shim sees no call — then admitted after one grimoire-index run, an absent `.run` created 0700, a malformed stat row, one `loa_profile` case per reason; `loa_knob`/`loa_profile`/`_loa_pl_live` parity on the live config + the pass-19 matrix except the enumerated `loa_profile` cache-state line; karpathy hook parity across the matrix; karpathy spawn budget 196 / 9 unchanged; drift guard green).
- [ ] FR-2 AC rows all green (multi-byte `release_body` ≤ 125 000 chars > 131 072 bytes and a `notification_body` ≤ 65 536 chars > 131 072 bytes publish DONE singly and together; stub argv carries no body marker; `grep -n -- '--arg body\|--arg summary\|--arg notes'` shows none; no `mktemp` on the body sites and exactly three `--rawfile body <(printf` operands (structural); a shimmed jq exiting 2 records today's `fail_phase` text and issues no second POST; existing 71 cases green).
- [ ] FR-3 AC rows all green (deleted / tampered / unreadable chain, abnormal verifier exit, healthy; sum invariant per fixture; L5/L7 `n/a` with `not_applicable` 2 in the JSON; duplicate / missing / unexpected index records → broken; empty list → absent 5; the human and JSON changes enumerated; every other `loa-status` line and `run-preflight` identical).
- [ ] FR-4 AC rows all green (fresh dir 0700 under umask 002 for every creator; D-5.3 case still green; budgets unchanged).
- [ ] Each red commit fails only its own new cases (`red-test-check.sh --env-pass PYTHONUSERBASE`); each fix commit green; `checksums.json` and REPO-MAP regenerated in every System Zone commit; `check-no-raw-sha256sum.sh`, `check-no-swallowed-jq.sh --quiet`, `check-loa.sh`, `repo-map-gen.sh --validate`, `perf-spawn-budget.bats` green at every fix commit and the sprint head.
- [ ] `a2a/sprint-284/reviewer.md` written before the review; review `All good` and audit `APPROVED` with `reviewed_head` = the sprint head (docs-only tails listed); `verdict-derive.sh` CONSISTENT; `COMPLETED`; ledger 284 `completed`.
- [ ] Full `tests/unit` TAP on the sprint head: only the three R-4 failures with their signatures; no new skips except named host-conditional ones.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 1.0: Sprint prep (lead) — worktrees `../loa-wt-c138-{a,b,c,d}` at the kickoff head; briefs under `~/.cache/loa/cycle-138/briefs/` (copies in `a2a/sprint-284/briefs/`) with the COMMON rules (red patch first, report file written with a heredoc, no writes under the main checkout's `.run/`, no `br` calls); `a2a/sprint-284/prep.md` fingerprinting the external recipes (`~/.cache/loa/cycle-137/scripts/{land.sh,regen-manifests.sh,mirror-ls.py}`, `~/.cache/loa/cycle-137/ship/merge-pr.sh`) with sha256 → **[G-3]** ⇐ none · kind: judgment
- [ ] Task 1.1: umask-077 creators (A, System Zone) — enumerate every `mkdir` that can create `.run/perf-cache`, `.run` or a directory under it (`grep -rn 'perf-cache' .claude --include='*.sh' --include='*.py'` AND `grep -rn 'mkdir.*\.run' .claude tests --include='*.sh' --include='*.py'`; SDD 1.2 § 5.4): wrap zone-write-guard.sh:261 and the karpathy state-dir `mkdir -p` (line 162) in `( umask 077; mkdir -p -- … )`; list — do not edit — the trajectory `mkdir` (line 214, Task 2.1) and profile-lib's writer `mkdir` (line 186, Task 1.4); red: a hook test under `umask 002` asserts the fresh directory is 0775 today → 0700 after, per creator; `grimoire-index.bats` D-5.3 case unchanged; CHANGELOG line names grimoire-index's tightening as the repair owner of a legacy writable `.run`; budgets unchanged → **[G-1, G-2]** ⇐ Task 1.0 · kind: mechanical
- [ ] Task 1.2: Chain summary classification (B, System Zone) — sdd § 5.3: `_an_audit_chain_classify` (valid / absent / broken / n/a per primitive; abnormal verifier → every existing chain broken), `_an_audit_chain_summary` prints `V A B` with `V + A + B == 7`; the human line byte-identical when healthy, else `V/7 validate (A absent, B broken).` + one line per non-valid primitive; JSON keeps `audit_chain_summary` and adds `audit_chain {valid, absent, broken, not_applicable, total, primitives[]}`; the verify-chains contract (one `{i, path, ok}` record per argument; exactly one match per index) written into a comment; red cases in `loa-status-providers.bats` (deleted, tampered, unreadable, verifier exit 0/1/2, duplicate / missing / unexpected index, empty existing list, healthy, L5/L7 n/a, sum invariant); mirror parity of every other line; `run-preflight` identical → **[G-1, G-2]** ⇐ Task 1.0 · kind: judgment
- [ ] Task 1.3: Publisher bodies off argv (C, System Zone) — sdd 1.2 § 5.2: `--rawfile body <(printf '%s' "$text")` at lines 1286, 1488, 1502 — a process substitution (no temp file, no trap, no new failure path; the 1.1 helper is withdrawn, SDD § 11.F B1); the stub records every command's argv to a log and the tests assert no body marker on argv; structural assertions (no `--arg body|--arg summary|--arg notes`; three `--rawfile body <(printf` sites; no `mktemp` on them); red: multi-byte `release_body` (≤ 125 000 chars, > 131 072 bytes) and a `notification_body` (≤ 65 536 chars, > 131 072 bytes), singly and together → `jq: Argument list too long` today, DONE after; a jq shim exiting 2 → today's `fail_phase` text, no second POST; 71 existing cases green → **[G-1]** ⇐ Task 1.0 · kind: judgment
- [ ] Task 1.4: profile-lib trust predicate (D, System Zone) — sdd § 3 and § 5.1: extended `_loa_pl_id` stat (five paths, `|%a|%u|%h`, GNU and BSD formats; the two extra rows never enter the id), `_loa_pl_cache_trusted` (dir real, uid, no g/o write — REFUSE, never chmod; `realpath -m` check anchored at the canonical root, only on the redirected seam outside bats; stat rc ignored, rows keyed by `%n`, malformed rows refused before arithmetic), `_loa_pl_cache_readable` (file regular, non-symlink, uid, mode, one link), guards in `_loa_pl_load` and the `loa_knob` warm path, writer: `dir-absent` → `( umask 077; mkdir -- dir )` (no `-p`), then `[[ -O dir && ! -L dir && ! -L cache ]]` re-check, `mktemp` + `mv -f -T` with the fallback (SDD 1.2 § 5.1 outcomes table; trust-lifetime comment), `_LOA_PL_CACHE_OFF` reason surfaced by `loa_profile` (human + `--json`, one case per reason); drift guard vs `grimoire-index.sh` (the listed invariant lines); red: the FR-1 fixtures (stat shim answers ownership; recording chmod shim; 775 `.run` off → one grimoire-index run → on; absent `.run` created 0700); parity: `loa_knob` / `loa_profile` / `_loa_pl_live` live + pass-19 matrix (enumerated `loa_profile` line), the karpathy hook across the matrix in REAL mirror directories; spawn budget 196 / 9 → **[G-1, G-2]** ⇐ Task 1.1 · kind: judgment
- [ ] Task 1.5: Landing and the Sprint 1 report (lead) — land in this order: A (1.1 red, 1.1 fix), B (1.2), C (1.3), D (1.4); every commit under the marker with `checksums.json` and REPO-MAP regenerated; `red-test-check.sh` per red commit; CHANGELOG lines inserted; `reviewer.md` written (FR-1 … FR-4 walkthrough, parity evidence, spawn counts, shas); beads closed provisionally ("landed on feature branch <sha>, pending merge"); class-S rows for every judgment call → **[G-1, G-2]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4 · kind: judgment
- [ ] Task 1.6: Review and audit (lead) — `/review-sprint sprint-1` (≤ 3 dissent runs on code-only `--diff-file` diffs; rounds beyond the budget lead-only, the third run reserved for the audit), `engineer-feedback.md` (C-11 grammar, `reviewed_head`, verdict-derive CONSISTENT); fixes red-first with the touched task's parity re-run; `/audit-sprint sprint-1` → `auditor-sprint-feedback.md`; `COMPLETED`; ledger 284 `completed`; full `tests/unit` TAP on the head; `e2e.md` (sprint part) → **[G-3]** ⇐ Task 1.5 · kind: judgment

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `_loa_pl_cache_trusted` / `_loa_pl_cache_readable` exit codes and `loa_profile`'s cache-state line, under a `stat` shim | a foreign, writable, symlinked, hard-linked or planted cache being read or written; a chmod issued from the hook path (the trace shows none) | a race inside one process (argued, not tested — the predicate excludes the writer) | `grimoire-index.bats:420-500`, `agy-gate-conformance.bats` `_agc33_shim` |
| `_loa_pl_write_cache`'s resulting file: mode, inode, link count, victim bytes | truncation through a hard link or symlink; a `.tmp.$$` predictable name | — | `grimoire-index.bats` planted-temp-symlink case |
| the publication stub's argv log and the state receipt | a body on `execve` argv; a jq failure not failing the phase | GitHub's real request size limits | `post-merge-publication.bats` gh stub, bug-283 cases |
| `_an_audit_chain_summary` output `V A B` and the JSON object, under fixture chain files | absence counted valid; a broken chain hidden; a sum that does not reach 7 | the verifier's own correctness (tested in `audit-envelope*.bats`) | `loa-status-providers.bats` LS-1 |
| the hook's created directory mode under `umask 002` | a 0775 `.run/perf-cache` | `.run` itself (out of scope) | `grimoire-index.bats` D-5.3 |
| `perf-spawn-budget.bats` karpathy target (196 / 9) | an added spawn on the warm path | spawns on paths without a fixture | the file's own budget lines |
| the whole-head mirror parity run (old pre-sprint head vs sprint head, REAL dirs) | any non-enumerated output change on a touched entry point | timing | `~/.cache/loa/cycle-137/scripts/mirror-ls.py` |

### Dependencies

- Prior art and recipes: cycle-137 landing/regen scripts and the sprint-bug-283 publisher pattern (`a2a/bug-20261028-90f357/reviewer.md`).
- Hosts: GNU stat on the ship host; the BSD stat branch covered by a shim.

### Security Considerations

- **Trust boundaries**: the checkout root is the trust root (operator-owned); `.run` and `.run/effective-config.json` are trusted only under the predicate; the publisher's bodies are data in files, never argv; chain files are untrusted bodies verified by the unchanged `audit_verify_chain`.
- **External dependencies**: none new (jq ≥ 1.6 for `--rawfile`).
- **Sensitive data**: none; release bodies are public text.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| The predicate refuses the cache on the live checkout (`.run` 700 today — fine) or on a downstream 775 `.run` | Low / Med | Med | refusal = live read, identical output; `loa_profile` names the reason; one `chmod go-w .run` fixes it (CHANGELOG line) |
| The extended `stat` format differs on BSD | Low | Med | both branches extended symmetrically; a shim per format |
| The FR-3 wording change breaks a consumer | Low | Low | string kept; additive JSON |
| Implementer patches collide on `profile-lib.sh` (only D touches it this sprint) | Low | Low | one implementer per file |

### Success Metrics

- 4 beads closed provisionally; ≥ 4 red/fix pairs VERIFIED; karpathy budget 196 / 9 unchanged; publication file 71 + new cases green; loa-status parity identical except the enumerated change; both gates on the sprint head.

> Sources: prd.md FR-1 … FR-4, G-1 … G-3; sdd.md § 3, § 5.1 … 5.4, § 7

---

## Sprint 2: Hooks and the known-failures surface (global 285)

**Duration:** ≈ 5 h unattended
**Dates:** 2026-10-29 (T+8 h) – 2026-10-29 (T+13 h)

### Sprint Goal

Close bd-yos4s, bd-kdzc3, bd-4sikh, bd-z6gxn and bd-aceil: the karpathy checkpoint seam is a test seam only and the trajectory append writes only through a trusted path; the KF SessionStart surface strips the decisions filter's control class, caps at 40 rows in file order with one elision line, and states the BSD byte-cap contract — verified under a BWK awk (form a) or documented with a linked macOS bead (form b).

### Deliverables

- [ ] C-5: marker-gated `KARPATHY_CHECKPOINT_CMD`; `_traj_trusted` guard on the warn path; `perf-spawn-budget.bats` allowlist adds the marker; red tests for both (A).
- [ ] C-6: `san()` + `SAN_AWK` control class (C1 pairs, U+2028/2029); selection-vs-display row cap with `KF_SURFACE_MAX_ROWS=40` and the elision line; the byte-cap contract text and boundary fixture; the drift guard and three-awk parity; the BWK attempt (prebuilt first) recorded; form (a) or (b) (B).
- [ ] CHANGELOG lines for FR-5 … FR-9; `a2a/sprint-285/reviewer.md` before Task 2.5.

### Acceptance Criteria

- [ ] FR-5 AC rows all green (seam ignored without the marker, honoured with it; hook parity on the matrix; budget 196 / 9).
- [ ] FR-6 AC rows all green (symlinked dir / component / day file, foreign or writable dir, FIFO, hard link → victims byte-identical, nothing appended, the warning still printed; replacement between two runs refused; hot-path budget unchanged).
- [ ] FR-7 AC rows all green (100-entry fixture → 40 rows in file order + the elision line, byte-exact; ≤ 40 entries → byte-identical; the live file differs only by its 25 elided rows + one line, diff attached; tie order pinned; worst-case rows < 8 KiB; kf-surface budget 36 / 2).
- [ ] FR-8 AC rows all green (NEL, U+009F, U+2028, U+2029 → single spaces in both twins; C0/DEL/byte cap as today; live output byte-identical with the no-such-bytes grep; drift guard; three-awk parity).
- [ ] FR-9 form (a) or (b) complete per PRD 1.1 (prebuilt-BWK attempt recorded first; contract text and boundary fixture landed; form (b) closes bd-aceil with the contract and opens a linked macOS bead with a class-S row).
- [ ] Red/fix discipline, manifests, lint and the full-suite TAP as in Sprint 1; `reviewer.md` before the review; review `All good` + audit `APPROVED` on the sprint head; `COMPLETED`; ledger 285 `completed`.

### Technical Tasks

- [ ] Task 2.0: Sprint prep (lead) — worktrees reset onto the Sprint 1 head; briefs for A and B; the prebuilt-BWK attempt is part of B's brief (`apt-cache policy original-awk`, `command -v nawk`, a container image; record the outcome in the report) → **[G-3]** ⇐ none · kind: judgment
- [ ] Task 2.1: karpathy seam gate and trajectory guards (A, System Zone) — sdd § 5.5: line 62 honours `KARPATHY_CHECKPOINT_CMD` only under `BATS_TEST_FILENAME`/`BATS_VERSION`; `_traj_trusted` (SDD 1.2 § 5.5: anchored at `realpath -m` of the checkout root — `TRAJ_DIR` inside the checkout and its canonical path equal to the root's canonical path plus the relative path; ONE `stat -Lc '%n|%u|%a|%h'` over every component below the root plus the day file, rc ignored, rows keyed by `%n`; each component a uid-owned non-symlink directory with no g/o write; the day file regular, non-symlink, uid-owned, one link, no g/o write; no `realpath -m` → refuse; the directory created under umask 077 when absent) guards the append on the warn path only — the state dir and task file keep today's `-L` guards (stated in the report); `perf-spawn-budget.bats` karpathy target passes `BATS_TEST_FILENAME`; red: seam ignored outside bats (counter script not run), each trajectory refusal (symlinked dir, symlinked ancestor, foreign or writable component, symlink / FIFO / hard-link / group-writable day file, BSD shim) with its victim preserved and the warning printed, normal append still works, replacement between runs refused, the warn path's spawn count asserted once; hook parity on the matrix; budget 196 / 9 → **[G-1, G-2]** ⇐ Task 2.0 · kind: judgment
- [ ] Task 2.2: KF control class (B, System Zone) — sdd § 5.6: `gsub(/\302[\200-\237]/, " ", s)` and `gsub(/\342\200[\250\251]/, " ", s)` in `san()` and `SAN_AWK`, before the C0 strip; `LC_ALL=C` pinned on each awk command of both twins (grimoire-index's `SAN_AWK` call sites at lines 101, 177, 191) with a parity case run from a `LANG=en_US.UTF-8` parent; red: fixtures with NEL, U+009F, U+2028, U+2029 → single spaces in the hook table and the index TSV; the drift guard extended to the new lines; mawk / busybox / `gawk --posix` parity; live output byte-identical (grep proves no such bytes) → **[G-1, G-2]** ⇐ Task 2.0 · kind: mechanical
- [ ] Task 2.3: KF row cap (B, System Zone) — sdd § 5.6: rows collected in file order with (recurrence leading integer, id); `n <= max` → today's output; else top-K by `max` linear passes (no `asort`: mawk / busybox / BWK) over (recurrence desc, numeric id `substr(id, 4) + 0` desc; malformed recurrence reads 0; an exact tie resolves to the earlier file position) and print the SELECTED rows in file order + `  … and K more — see grimoires/loa/known-failures.md`; `-v max=40`; every field bounded (id regex, integer recurrence, 100-byte symptom); red: 100-entry fixture (byte-exact expected), ≤ 40 fixture byte-identical, tie order, malformed recurrence, worst-case 40 rows < 8 KiB; the live diff (25 rows + 1 line) attached; budget 36 / 2 → **[G-1, G-2]** ⇐ Task 2.2 · kind: judgment
- [ ] Task 2.4: BSD byte-cap contract (B, System Zone + tests) — the contract sentence in the hook header (100 bytes on every host, may end inside a multi-byte sequence; advisory text); the boundary fixture (3-byte UTF-8 symptom crossing byte 100, exact expected bytes); form (a): BWK awk + BSD cut semantics in the parity test when a BWK binary exists; form (b): attempt recorded, UNVERIFIED stated, bd-aceil closed with the contract, a linked macOS bead opened, class-S row → **[G-1]** ⇐ Task 2.3 · kind: judgment
- [ ] Task 2.5: Landing and the Sprint 2 report (lead) — A then B (2.2 → 2.3 → 2.4, each red/fix under the marker); CHANGELOG lines; `reviewer.md`; provisional closes; class-S rows (incl. the FR-9 form) → **[G-1, G-2]** ⇐ Task 2.1, Task 2.4 · kind: judgment
- [ ] Task 2.6: Review and audit (lead) — as Task 1.6, for sprint-2 (global 285) → **[G-3]** ⇐ Task 2.5 · kind: judgment

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| the karpathy hook's checkpoint command actually executed (a counter script) with and without the marker | the seam honoured from the ambient environment | a hostile same-uid environment (out of the threat model) | `perf-spawn-budget.bats:275-299` |
| the trajectory victim file's bytes and link count after the warn path | an append through a symlink, FIFO or hard link; a foreign/writable directory used | — | the hook's state-file guards (lines 162, 165) |
| the hook's stdout table on fixtures and the live file, byte-compared | a wrong row selected, a wrong display order, a missing elision line, a C1 byte passing | rendering in the session UI | `kf-surface.bats`, `grimoire-index.bats` drift guard |
| the three (four with BWK) awk interpreters' outputs `cmp`'d | a gawk-only construct, an octal class BWK rejects | BSD `cut` without a BSD host (form b) | Sprint 282 Task 2.1 parity test |
| `perf-spawn-budget.bats` kf-surface (36 / 2) and karpathy (196 / 9) | an added spawn | — | the file |

### Dependencies

- Sprint 1 landed (the karpathy hook is shared with Task 1.1's umask change only if the enumeration touched it; sequencing).
- A BWK awk source: Debian/Ubuntu `original-awk`, `nawk`, or a container image (form a).

### Security Considerations

- **Trust boundaries**: the trajectory directory and day file are trusted only when owned, non-writable, regular and single-linked; the checkpoint seam is a test seam; KF bodies stay untrusted and sanitised with the decisions filter's class.
- **External dependencies**: none new.
- **Sensitive data**: none.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| BWK awk unobtainable (no package, no network) | Med | Low | form (b) with the prebuilt attempt recorded (DEC-1159) |
| The row cap elides an entry a session needed | Low | Med | recurrence-first selection; the elision line names the file |
| `realpath -m` absent on a host | Low | Low | fall back to refusing when `-L` on any component found by a loop (bash only) |

### Success Metrics

- 5 beads closed (or bd-aceil closed in form b with a linked bead); kf-surface 36 / 2 and karpathy 196 / 9 unchanged; the live KF table changes by exactly 25 rows + 1 line; both gates on the sprint head.

> Sources: prd.md FR-5 … FR-9; sdd.md § 5.5, § 5.6, § 7; DEC-1158, DEC-1159

---

## Sprint 3 (Final): Tests, guards, the bounded refactor, and the gates on the PR head (global 286)

**Duration:** ≈ 4 h unattended (+ the ship)
**Dates:** 2026-10-29 (T+13 h) – 2026-10-30 (T+17 h)

### Sprint Goal

Close bd-7utms, bd-y5fy4, bd-5v1oa, bd-rq6gk, bd-3qed8 and bd-0h7kq (or defer the last by a class-S row), run the whole-head parity gate over every entry point any sprint touched, and pass the final review and audit bound to the head the PR will merge (DEC-1161); then the § Ship section.

### Deliverables

- [ ] C-7: `forbidden()` descendant clause; `loa_knob` kind-token presence metadata; `profile-floor.bats` / `profile-lib.bats` cases (A).
- [ ] C-8: `perf-spawn-budget.bats` warm grimoire-index target; CMP-55 reap marker + 240 s hold; `_path_without` array skip list; one-off red runs recorded (B).
- [ ] C-9: providers registry refactor within the 60-line bound with its pinned observable, or the deferral row (C).
- [ ] Whole-head parity gate: old mirror = fe52be893 (pre-cycle), new mirror = the sprint head, every touched entry point, enumerated diffs attached.
- [ ] CHANGELOG lines for FR-10 … FR-15; `a2a/sprint-286/reviewer.md`; `e2e.md` part 1.

### Acceptance Criteria

- [ ] FR-10 AC rows all green (child, grandchild, cached key dropped with the WARN; sibling prefix kept; live floor list identical).
- [ ] FR-11 AC rows all green (each former sentinel string, an empty present value and a trailing-newline value round-trip on warm, memo and live paths; classification matrix green; call sites unchanged; budget 196 / 9).
- [ ] FR-12 AC rows all green (hit traced after an asserted-valid cache; mutation of headroom + 1 spawns fails deterministically — one-off red run recorded).
- [ ] FR-13 AC rows all green (reap marker asserted; 240 s hold; TAP set identical; one-off red run recorded) — or deferred by a class-S row under the slip order.
- [ ] FR-14 AC rows all green (`_path_without yq jq` excludes both; single-tool callers unchanged).
- [ ] FR-15 implemented within the 60-line bound with its pinned observable, or deferred by a class-S row (DEC-1146).
- [ ] Whole-head parity gate: stdout, stderr, rc and written files identical for every touched entry point except the enumerated changes (FR-3 line/JSON, FR-7 elision, FR-8/FR-10/FR-11 fixtures, `loa_profile` cache line), diffs attached.
- [ ] Red/fix discipline, manifests, lint, full-suite TAP as before; `reviewer.md` before the review; review `All good` + audit `APPROVED` with `reviewed_head` = the head the PR merges (docs-only tails listed); `COMPLETED`; ledger 286 `completed`; `e2e.md` part 1 (G-1 … G-3 evidence, measurements with host/command/run count, the parity gate, the TAP, the meter).

### Technical Tasks

- [ ] Task 3.0: Sprint prep (lead) — worktrees reset onto the Sprint 2 head; briefs for A, B, C → **[G-3]** ⇐ none · kind: judgment
- [ ] Task 3.1: Floor descendant clause and presence metadata (A, System Zone) — sdd § 5.7: `forbidden()` gains `or ($k | startswith(($f | split("*")[0] | rtrimstr(".")) + "."))`; the descendant clause applies only to floor entries without `*` (glob entries keep `test(globre)` alone); `loa_knob`'s cache and memo reads print the value then the kind token on the LAST line, split with a newline guard (an empty present value stays empty; trailing newlines stripped as today — SDD 1.2 § 5.7); red: child/grandchild/cached-key dropped with the WARN, sibling-prefix kept, glob entry not widened, live floor identical (pre-flight: no live key newly forbidden); each former sentinel, an empty present value and a trailing-newline value round-trip on the three paths; classification matrix green; parity on the live config + matrix for the 19 call sites (fixtures' intended differences enumerated); budget 196 / 9 → **[G-1, G-2]** ⇐ Task 3.0 · kind: judgment
- [ ] Task 3.2: Test guards (B, tests only; one commit exempt from the red/fix pair, with the one-off red runs recorded in the report) — sdd § 5.8: warm grimoire-index spawn target (cache asserted valid first; budget measured over three runs; a mutation of headroom + 1 spawns fails), CMP-55 reap marker, the test's own `CMP_STUB_HOLD_S=300` override removed (setup's 240 applies), `LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS` 3 → 6 (serial TAP set identical); the warm fixture's `.run/perf-cache` 0700 uid-owned with the cache file asserted present before the second trace, `_path_without` array skip list + `yq jq` case → **[G-1, G-2]** ⇐ Task 3.0 · kind: mechanical
- [ ] Task 3.3: Providers registry (C, System Zone, bounded) — sdd § 5.9: one lazily built `_registry()` used by `__getattr__`, `get_adapter` and `cli_adapter_types` (static auth table), name-in-`globals()` presence; ≤ 60 lines diff, every provider test green, `cheval --help` within the loop's band, one pinned observable with a red test; else STOP and return a deferral note (lead writes the class-S row, bead stays open with the successor label) → **[G-1]** ⇐ Task 3.0 · kind: judgment
- [ ] Task 3.4: Landing and the Sprint 3 report (lead) — A, B, C in that order (C last so a deferral costs nothing); CHANGELOG lines; provisional closes; class-S rows; the whole-head parity gate (`mirror-ls.py`-style REAL mirrors, old fe52be893 vs new head, every touched entry point: kf-surface, grimoire-index, loa-status, run-preflight, karpathy, zone-write-guard, the publisher's `--generate` on a fixture); `reviewer.md` → **[G-1, G-2]** ⇐ Task 3.1, Task 3.2, Task 3.3 · kind: judgment
- [ ] Task 3.5: Review and audit on the PR head (lead) — `/review-sprint sprint-3` and `/audit-sprint sprint-3` with `reviewed_head` = the head the PR merges (the final sprint's verdicts bind to the PR head — DEC-1161); the review's AC walk covers FR-10 … FR-15 and re-checks the parity gate; `COMPLETED`; ledger 286 `completed` → **[G-3]** ⇐ Task 3.4 · kind: judgment
- [ ] Task 3.E2E: End-to-End Goal Validation (lead) — `a2a/sprint-286/e2e.md` part 1 at `COMPLETED`: G-1 (fifteen beads: commit + test, or the deferral row + successor bead), G-2 (spawn budgets table, parity gate result with enumerated diffs), G-3 (the three sprints' verdicts with heads and dissent runs; the full-suite TAP per sprint head with the R-4 names), the meter checkpoint; part 2 appended by § Ship → **[G-1, G-2, G-3, G-4]** ⇐ Task 3.5 · kind: judgment

### Task 3.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4)

**Description:** Validate that every PRD goal is achieved through the complete implementation and record the evidence in `a2a/sprint-286/e2e.md`.

**Validation Steps:**
| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | fifteen beads closed or deferred-with-row | `br show` per bead; the red/fix sha pairs and `red-test-check.sh` verdicts | 15 closed-or-deferred; every red VERIFIED |
| G-2 | no hot-path regression | `perf-spawn-budget.bats` on the PR head; the whole-head parity gate logs | budgets at their counts; parity identical except the enumerated diffs |
| G-3 | gates per sprint; final sprint bound to the PR head | the three `COMPLETED` markers, `verdict-derive.sh` on six verdict files, the parity gate on the PR head | CONSISTENT ×6; the Sprint 3 verdicts name the PR head |
| G-4 | merged on green, recorded, archived, nothing published | § Ship rows S-1 … S-5; `git ls-remote --tags origin` before/after | merge sha on main; identical trees; no new tag |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence (shas, file paths, counts)
- [ ] Integration points verified (hooks → profile-lib; loa-status → verify-chains; publisher → gh stub)
- [ ] No goal marked "not achieved" without the halt-protocol record (DEC-1160)

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `loa_knob` output for values equal to the former sentinels, on the three read paths | a sentinel collision | — | `profile-lib.bats` classification matrix |
| `forbidden()`'s WARN lines and the dropped-key list | a descendant served; a sibling wrongly dropped | — | `profile-floor.bats` |
| the spawn-budget guard's own failure on a mutated hit branch | a hollow warm target | — | `perf-spawn-budget.bats` tracer tests |
| CMP-55's reap marker file | a reaper never invoked | — | `adversarial-review-companion.bats` CMP-14/30/48 |
| the whole-head mirror parity run on the PR head | any unenumerated change from any sprint | timing | `mirror-ls.py` |

### Dependencies

- Sprints 1 and 2 landed (shared files: `profile-lib.sh` with Task 1.4; the karpathy hook budget line).

### Security Considerations

- **Trust boundaries**: unchanged from Sprints 1–2; the providers refactor touches no trust surface (static tables only).
- **External dependencies**: none new.
- **Sensitive data**: none.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| The whole-head parity gate finds an unenumerated diff | Low | Med | fix red-first within the sprint; re-run the gate; the review re-binds |
| FR-15 exceeds its bound | Med | Low | deferral row + successor bead (DEC-1146) |
| Time budget exceeded before Sprint 3's gates | Low | Low | halt protocol: PR ships Sprints 1–2 (DEC-1160) |

### Success Metrics

- 6 beads closed or ≤ 2 deferred-with-row; parity gate identical except the enumerated diffs; both gates on the PR head; `e2e.md` part 1 complete.

> Sources: prd.md FR-10 … FR-16, G-1 … G-4, § Constraints; sdd.md § 5.7 … 5.9, § 7; DEC-1146, DEC-1160, DEC-1161

---

## Ship (post-Sprint 3; outside the gated sprints, as in cycles 135–137)

Runs only after Sprint 286 `COMPLETED` and only while no class-H row and no blocking finding is open. Rows are checked separately:

- [ ] S-1 Pre-PR: secret scans on the final head (`audit-secret-redaction-scan.sh` over the changed tracked files; a token / private-key grep over the added lines); PR from `feature/cycle-138-hardening-followups` whose body lists the three sprints, beads, DEC rows, each gate's verdict with its `reviewed_head`, the parity gate and the statement that the prepared rc.10 candidate is NOT published; title classifies `cycle`.
- [ ] S-2 Bridgebuilder: ≤ 2 rounds (`BRIDGEBUILDER_MODEL=codex-headless`; excludes `checksums.json`, REPO-MAP, prd/sdd/sprint, decisions.yaml, ledger.json, reports); PRD FR-16's degraded-exit procedure (retry once after ten minutes; a second degraded round proceeds only with no blocking finding, class-S row); a blocking finding is fixed red-first and both final verdicts re-bind verify-only to the new head.
- [ ] S-3 Merge gate (R-3): every check run on the exact head completed; the six required checks `success` (latest run per name); every other completed run `success`/`skipped`/`neutral`; the Sprint 3 verdicts name the head; `merge-pr.sh`-style admin merge; `git diff --quiet <head> <merge>`.
- [ ] S-4 Record: `record-branch.sh --cycle 138 --head <merge> --prev origin/record/cycle-137-performance-followups --stage "stage 1"` (the known NOTES prose hit class accepted); pushed via run-mode-ice; a2a for sprints 284–286 on it.
- [ ] S-5 Main CI: `CI` and `BATS Tests` green on the merge commit.
- [ ] S-6 Archive and close: `archive-cycle.sh --cycle 138 --retention 50` on a chore branch; housekeeping merge (both Prepare jobs skipped, zero artifacts); `JACKED_OUT`; beads' provisional closes updated with the merged sha; ledger cycle archived; `e2e.md` part 2 (G-4 evidence; `git ls-remote --tags` unchanged; the unpublished rc.10 candidate named).
- [ ] S-7 No publish: nothing in this section runs `--publish`; a publish is an operator decision.

> Sources: prd.md FR-16; cycle-137 § Ship and `~/.cache/loa/cycle-137/ship/`; DEC-1145

---

## Risk Register

| Risk | Sprint | Probability | Impact | Mitigation |
|---|---|---|---|---|
| profile-lib predicate refuses a common downstream layout | 1 | Med | Med | live-read fallback; `loa_profile` reason; CHANGELOG fix line |
| Publisher fixtures (multi-byte > 131 072 bytes) slow the suite | 1 | Low | Low | two cases; bodies generated in-test |
| BWK awk unobtainable | 2 | Med | Low | form (b), DEC-1159 |
| Dissent budget exhausted by rounds | any | Med | Low | lead-only round 3; audit keeps run 3; halt protocol |
| Bridgebuilder degraded | ship | Low | Low | FR-16 procedure |
| Time budget | 3 | Low | Low | halt protocol ships 1–2 |

## Success Metrics Summary

15 beads closed-or-deferred-with-row; budgets unchanged (196/9, 36/2, 167/15, 127/5, 26/3, 15/0, 78/2); whole-head parity identical except enumerated diffs; three `COMPLETED`; one PR merged on green; record + archive; zero new tags.

## Dependencies Map

Task 1.1 → Task 1.4 (umask before the predicate's fixtures); Task 2.2 → 2.3 → 2.4 (one awk program); Task 1.4 → Task 3.1 (same file); every landing task → its gate task; Sprint 3 gates → Ship.

## PRD Feature Mapping

| FR | Task |
|---|---|
| FR-1 | 1.4 | 
| FR-2 | 1.3 |
| FR-3 | 1.2 |
| FR-4 | 1.1 |
| FR-5, FR-6 | 2.1 |
| FR-7 | 2.3 |
| FR-8 | 2.2 |
| FR-9 | 2.4 |
| FR-10, FR-11 | 3.1 |
| FR-12, FR-13, FR-14 | 3.2 |
| FR-15 | 3.3 |
| FR-16 | § Ship |

## SDD Component Mapping

C-1 → 1.4; C-2 → 1.3; C-3 → 1.2; C-4 → 1.1; C-5 → 2.1; C-6 → 2.2, 2.3, 2.4; C-7 → 3.1; C-8 → 3.2; C-9 → 3.3; C-10 → § Ship.

---

## Appendix

### Appendix C — Goal Traceability

| Goal | Goal (PRD) | Contributing tasks |
|---|---|---|
| G-1 | every bead closed by a red-first fix or a bounded exit with a row | 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.E2E |
| G-2 | no hot-path regression; parity except enumerated changes | 1.1, 1.2, 1.4, 1.5, 2.1, 2.2, 2.3, 2.5, 3.1, 3.2, 3.4, 3.E2E |
| G-3 | gates per sprint; final sprint bound to the PR head; ≤ 3 dissent runs | 1.0, 1.6, 2.0, 2.6, 3.0, 3.5, 3.E2E |
| G-4 | merged on green after ≤ 2 BB rounds; record; archive; nothing published | § Ship S-1 … S-7, 3.E2E |

No goal lacks a contributing task; the final sprint carries Task 3.E2E.

> Sources: prd.md § Goals & Success Metrics; this plan's task annotations

### Appendix D — Decision rows and beads

Sprint-planning rows (class S, proposed): DEC-1162 (three sprints by exposure), DEC-1163 (Task 3.2 guard commit exempt from the red/fix pair; one-off red runs recorded), DEC-1164 (beads graph: three epics, 23 tasks, blocking edges, no parent edges). SDD 1.2 design rows carried into this revision: DEC-1165 (process substitution), DEC-1166 (trust lifetime, absent `.run`, repair owner), DEC-1167 (`not_applicable`, verify-chains contract), DEC-1168 (anchored trajectory guard), DEC-1169 (portable top-K), DEC-1170 (last-line kind token).

Beads (`~/.cache/loa/cycle-138/beads-map.txt`, copy in `a2a/sprint-284/prep.md`): epics bd-fm8qc (284), bd-ei4dy (285), bd-685o9 (286); tasks 1.0 bd-ux7fq, 1.1 bd-ujmdr, 1.2 bd-84thp, 1.3 bd-uuwo5, 1.4 bd-1utps, 1.5 bd-g52ma, 1.6 bd-1dil1; 2.0 bd-jokyg, 2.1 bd-kk1ln, 2.2 bd-3df16, 2.3 bd-5u8n6, 2.4 bd-52c9d, 2.5 bd-v2x1e, 2.6 bd-zix6z; 3.0 bd-fb960, 3.1 bd-2kogs, 3.2 bd-gxt44, 3.3 bd-522gq, 3.4 bd-v4mlg, 3.5 bd-0uxoj, 3.E2E bd-v1vun, ship bd-9vp63. The fifteen follow-up beads (bd-j34zb bd-qyvju bd-hyah6 bd-20bh1 · bd-yos4s bd-kdzc3 bd-4sikh bd-z6gxn bd-aceil · bd-7utms bd-y5fy4 bd-5v1oa bd-rq6gk bd-3qed8 bd-0h7kq) are closed by their task's landing.

> Sources: grimoires/loa/decisions.yaml DEC-1162 … DEC-1164; beads-map.txt
