# Product Requirements Document: Hardening follow-ups (cycle-138)

**Version:** 1.0
**Date:** 2026-10-29
**Author:** Requirements Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous cycle on the operator's instruction of 2026-10-29 ("… and then proceed with the next cycle …", after the lead's next-steps message that named this cycle's content)
**Cycle:** `cycle-138-hardening-followups` (ledger), branch `feature/cycle-138-hardening-followups` from `main` fe52be893
**Grounding:** brownfield; the stale `grimoires/loa/reality/` set (2026-05-04) is not re-run — grounding is the live `grimoires/loa/REPO-MAP.md`, the file:line anchors each bead's finding recorded, and the cycle-137 / sprint-bug-283 gate artefacts (DEC-1144); the brief is `grimoires/loa/context/cycle-138-brief.md`, the bead table `grimoires/loa/context/cycle-138-followups.md`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: `.claude/skills/discovering-requirements/resources/templates/prd-template.md` (section order)

---

## Executive Summary

cycle-137 shipped the 22-pass optimisation loop through the formal gates and released `v2.0.0-rc.9`; sprint-bug-283 fixed the publisher's release read-back (KF-064). Those three review rounds, two audits, four cross-model dissent runs and three Bridgebuilder rounds left fifteen open beads, each with a severity and an exact code anchor: two trust boundaries that the new code has and its older siblings lack (the profile-lib effective-config cache, the publisher's argv-borne request bodies), a status summary that counts a missing integrity chain as valid, a cache directory created under the user's umask, two hook seams honoured from the ambient environment, an unbounded session-context injection, a sanitiser that lets UTF-8 C1 controls through, a portability contract never verified on BSD tooling, and six test-coverage or guard gaps the gates themselves found.

This cycle closes them in three sprints ordered by exposure — security and the release path first, hooks and the known-failures surface second, tests and guards third — with the same discipline as cycle-137: red-first tests, byte-identical old-versus-new output where output exists, System Zone edits under the bounded marker with manifests regenerated, spawn budgets kept, decisions as class-S rows. One pull request, two Bridgebuilder rounds at most, merge on green checks on the exact head, a record branch and an archive. No release: the candidate the pipeline prepares after the merge stays unpublished unless the operator asks (DEC-1145).

> Sources: `grimoires/loa/context/cycle-138-brief.md`; `grimoires/loa/context/cycle-138-followups.md`; `grimoires/loa/a2a/sprint-282/auditor-sprint-feedback.md` § Medium/Low; `grimoires/loa/a2a/bug-20261028-90f357/engineer-feedback.md` § Observations; beads bd-j34zb … bd-qyvju (`br show`)

---

## Problem Statement

### The Problem

1. **Two caches, one boundary.** cycle-137 gave the grimoire-index decisions cache a trust check (uid-owned, non-group-writable directory, symlink refusal, `mktemp` + `mv -T`); its older sibling, the profile-lib `effective-config.json` cache that every PostToolUse karpathy check and several hooks read through `loa_knob`, has none: `_loa_pl_load` reads the file when it merely exists (`profile-lib.sh:206-215`) and `_loa_pl_write_cache` writes `<cache>.tmp.$$` through a shell redirect and `mv -f` (`profile-lib.sh:188-190`). A co-tenant who can write `.run` but not the config files can plant knob values or clobber a file through a sprayed temp-name symlink (Sprint 282 audit MED-001).
2. **A release can fail to be created for its size.** The publisher builds the release POST and the notify comment with `jq -nc --arg body "$notes"` (`post-merge-orchestrator.sh:1286, 1488`); Linux caps one argv string at 131 072 bytes, which multi-byte notes under GitHub's 125 000-character limit can exceed — the read-back side was fixed in sprint-bug-283, the write side was not (review r2 observation 4).
3. **Absence counts as health.** `loa-status` counts a missing L1–L6 chain file as "validates by absence" (`loa-status.sh:430-434`), so deleting a tampered chain file turns a red count into `7/7` (Sprint 282 audit LOW-001).
4. **A cache directory inherits the umask.** `zone-write-guard.sh:261` creates `.run/perf-cache` with a bare `mkdir -p`; under umask 002 it is group-writable and the decisions cache was inert until cycle-137 added a tightening step (DEC-1126) — the creator should not need tightening.
5. **Hook seams and surfaces.** The karpathy hook honours `KARPATHY_CHECKPOINT_CMD` from the ambient environment without a bats gate or a warning (`karpathy-surgical-diff-check.sh:62`) and appends its trajectory through a directory and file it never checks for symlinks (`:214-217`); the known-failures SessionStart hook injects every entry (65 today) into the session context with no volume bound; its `san()` strips C0 and DEL but not UTF-8-encoded C1 controls (`loa-kf-surface.sh:97-104`); the BSD byte-cap contract of that sanitiser is still unverified on BWK awk / BSD `cut` (Sprint 281 MED-001, DEC-1123).
6. **Guards the gates found hollow or missing.** `forbidden()` has no descendant clause for a mapping-level floor key (`profile-lib.sh:131`); `loa_knob` returns sentinel strings that a real config value can collide with (`profile-lib.sh:248-280`); the spawn-budget guard measures the grimoire-index cache miss only; CMP-55 asserts nothing about the reap it exercises; `_path_without a b` excludes nothing (`loa-decisions-surface.bats:124-135`); the providers registry builds its dispatch twice over.

### User Pain Points

- The maintainer cannot claim the trust boundary cycle-137 introduced is complete while the cache that runs on every edit lacks it.
- A release whose notes quote enough multi-byte text could fail at creation with an `E2BIG` nobody expects.
- The one in-tool integrity view can be silenced by deleting a file.

### Current State

`main` at fe52be893 (`v2.0.0-rc.9` + sprint-bug-283); fifteen beads open under the `cycle-137` label; the full unit suite green modulo the three KF-034 `semver evidence` tests; `check-loa.sh` All checks passed.

### Desired State

Every bead closed with a red-first test and a landed fix (or, for bd-aceil and bd-0h7kq, the bounded exit a class-S row records — DEC-1146); every touched hot path byte-identical old-versus-new and inside its spawn budget; three sprints through `/review-sprint` and `/audit-sprint`; one PR merged on green; record and archive; no release.

> Sources: `.claude/scripts/lib/profile-lib.sh:50-76, 181-222, 236-288`; `.claude/scripts/post-merge-orchestrator.sh:1286, 1488, 1502`; `.claude/scripts/loa-status.sh:408-461, 481-522`; `.claude/hooks/safety/zone-write-guard.sh:230-264`; `.claude/hooks/quality/karpathy-surgical-diff-check.sh:38-62, 205-220`; `.claude/hooks/loa-kf-surface.sh:88-110`; `tests/unit/perf-spawn-budget.bats:137-169, 275`; `tests/unit/adversarial-review-companion.bats:1678-1691`; `tests/unit/loa-decisions-surface.bats:124-140`; `.claude/adapters/loa_cheval/providers/__init__.py:26-60`

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Every one of the fifteen beads is closed by a landed red-first fix, or by the bounded exit DEC-1146 names (bd-aceil contract form, bd-0h7kq deferral) with a class-S row | 15 beads closed or deferred-with-row; `red-test-check.sh` VERIFIED per red commit | `br show` per bead; `~/.cache/loa/cycle-138/logs/rtc-*.json` |
| G-2 | No hot path regresses: spawn budgets hold (FR-1 may add at most one spawn with a stated reason), every touched entry point byte-identical old-versus-new on the live inputs and the fixture matrix | `perf-spawn-budget.bats` green; mirror parity logs | the sprint reports and the review's own parity re-run |
| G-3 | Each sprint passes `/review-sprint` (`All good`) and `/audit-sprint` (`APPROVED`) with `reviewed_head` equal to the head the PR merges; ≤ 3 dissent runs per sprint | three COMPLETED markers; `verdict-derive.sh` CONSISTENT | `a2a/sprint-<N>/` |
| G-4 | One PR merged on green checks on the exact head after ≤ 2 Bridgebuilder rounds; record branch and archive; nothing published | merge sha on `origin/main`; `git ls-remote --tags` unchanged for new tags | `e2e.md` part 2 |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Open follow-up beads from cycle-137 / sprint-bug-283 | 15 | 0 open (≤ 2 deferred by row) | cycle end | G-1 |
| profile-lib cache: reads of a foreign-owned or symlinked cache | accepted | refused (red tests) | Sprint 1 | G-1 |
| Publisher POST/notify body size that fails at `execve` | > 131 072 bytes | none (file-borne) | Sprint 1 | G-1 |
| `loa-status` chain summary with one chain file deleted | `7/7` | names the absence; never `7/7` | Sprint 1 | G-1 |
| karpathy hook warm-path spawns (`perf-spawn-budget.bats`) | budget B | ≤ B + 1 with a reason | Sprint 1 | G-2 |
| Full `tests/unit` on the final head | 7315 planned, 3 allowed reds (KF-034) | new tests added, same 3 reds only, no new skips except named host-conditional ones | cycle end | G-3 |

### Constraints

- No new configuration keys unless a requirement states one (FR-7's cap is a documented constant first; a knob only if the SDD shows one is needed).
- No behaviour change on a hot path without a red test; where output changes by design (FR-3, FR-7) the change is enumerated and the parity criterion becomes "differs only by the enumerated lines, diff attached".
- No release, no tag, no publish in this cycle (DEC-1145).

> Sources: brief § Constraints; DEC-1144 … DEC-1147; `tests/unit/perf-spawn-budget.bats:275`

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)
Runs Loa on their own machine and on shared checkouts; expects every per-tool-call hook to trust only what it owns and to say what it refuses; publishes releases through the post-merge candidate recipe.

### Secondary Persona: A downstream mount operator
Installs Loa into another repository; may have a group-writable `.run`, a non-GNU awk, or large release notes; must see no new prompts and no silent changes.

### Tertiary Persona: The lead agent and its implementers
Need deterministic guards (spawn budgets, parity harnesses, red-test-check) that fail when a property breaks.

### Use Cases

#### UC-1: A shared checkout with a writable `.run`
**Actor:** maintainer on a shared workstation. **Preconditions:** `.run` group-writable; a co-tenant plants `.run/effective-config.json`. **Flow:** a Write triggers the karpathy hook → `loa_knob` → the profile-lib cache check refuses the foreign/writable location → the live read answers. **Postconditions:** the attacker's knobs are never served; the hook's output is identical to the no-cache path. **Acceptance Criteria:** FR-1.

#### UC-2: Large release notes
**Actor:** the publisher. **Preconditions:** a candidate whose `release_body` exceeds 131 072 bytes. **Flow:** `--publish` creates the release and comment with file-borne bodies. **Postconditions:** release verified; state `DONE`. **Acceptance Criteria:** FR-2.

#### UC-3: A tampered chain file is deleted
**Actor:** `/loa` status. **Flow:** `loa-status` lists the chain files; one is missing. **Postconditions:** the summary names one absent chain; it never reads `7/7`. **Acceptance Criteria:** FR-3.

> Sources: Sprint 282 audit MED-001, LOW-001; sprint-bug-283 review r2 observation 4

---

## Functional Requirements

### Sprint 1 — security and the release path

### FR-1: profile-lib effective-config cache gets the decisions-cache trust boundary (bd-j34zb)
**Priority:** Must Have
**Description:** `_loa_pl_load` and the warm path of `loa_knob` read `.run/effective-config.json` only when `.run` is a real directory owned by the running uid with no group/other write bit (a uid-owned directory carrying such a bit is tightened `chmod go-w`, as `_gi_trusted_dir` does — DEC-1126 — else the cache is off), and the cache file is a regular non-symlink file read through an opened descriptor; `_loa_pl_write_cache` writes through `mktemp` under umask 077 beside the cache, re-checks `[[ ! -L ]]`, and renames with `mv -f -T` (falling back to `mv -f` only when the target is neither a directory nor a symlink). `LOA_PROFILE_CACHE_FILE` (the bats seam) keeps its current semantics inside bats; outside bats a redirected cache follows the same trust check. Every refusal falls back to today's live read: behaviour identical, output identical.
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/profile-lib.bats` (fixtures modelled on `grimoire-index.bats` 420-500): a foreign-owned `.run` (stat shim) → neither read nor written; a group-writable uid-owned `.run` → tightened then used; a symlinked cache file → ignored, never followed, not replaced; a symlink pre-planted at a temp-like name beside the cache → never followed (the victim keeps its bytes); a cache that is a FIFO → not opened (no hang), replaced on the next write.
- [ ] `loa_knob`, `loa_profile` and `_loa_pl_live` outputs byte-identical old-versus-new on the live config and on the pass-19 config matrix; the karpathy hook's stdout/stderr/state files identical across that matrix (mirror in a REAL directory).
- [ ] `perf-spawn-budget.bats` karpathy target: ≤ one additional spawn with the reason stated in the budget line (the SDD prefers `[[ -O ]]` and one `stat` to anything more); grimoire-index targets unchanged.
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated under the marker.
**Dependencies:** none.

> Sources: `.claude/scripts/lib/profile-lib.sh:50-76, 181-222, 236-288`; `.claude/scripts/grimoire-index.sh:263-331` (the pattern to mirror); `grimoires/loa/a2a/sprint-282/auditor-sprint-feedback.md` MED-001; DEC-1126, DEC-1136

### FR-2: Publisher request bodies leave argv (bd-qyvju)
**Priority:** Must Have
**Description:** In `post-merge-orchestrator.sh` the release-creation request (`phase_release`, line 1286) and the notify comment request and its read-back comparison (`phase_notify`, lines 1488 and 1502) stop passing bodies as `jq --arg` command-line values: bodies are written to temp files by the `printf` builtin and read with `--rawfile` (or fed on jq's stdin); the read-back comparisons keep their exact semantics (the release body already goes through `release_body_identical`; the comment body stays an exact comparison). Temp files follow sprint-bug-283's pattern (a `mktemp -d` per call, a `RETURN` trap).
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/post-merge-publication.bats`: a candidate whose `release_body` and `notification_body` exceed 131 072 bytes publishes `DONE` with one release POST and one comment POST (today: `jq: Argument list too long` at the POST); the existing identity and retry cases unchanged (71 → 71 + new).
- [ ] No body text on any `execve` argv in the publish path (a `bash -x` trace of the publish shows no `--arg body`/`--arg sent` of body text).
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated.
**Dependencies:** none (sprint-bug-283 is merged).

> Sources: `.claude/scripts/post-merge-orchestrator.sh:1286, 1488, 1502` (at fe52be893); `grimoires/loa/a2a/bug-20261028-90f357/engineer-feedback-r2.md` § Observations 4; `getconf ARG_MAX` 2 097 152 / per-argument 131 072

### FR-3: `loa-status` reports an absent chain file as a third state (bd-hyah6)
**Priority:** Must Have
**Description:** `_an_audit_chain_summary` keeps counting valid chains through `verify-chains` but reports absence separately: the human line becomes `Audit chain: V valid, A absent, B broken of 7 primitives` (exact wording decided in the SDD) and the JSON gains `audit_chain: {valid, absent, broken, total}` beside the existing `audit_chain_summary` string, which is kept for compatibility and shows the same three numbers. Absence is never folded into `valid`; `7/7`-equivalent wording appears only when every chain file exists and verifies. L5 and L7 (not chain-critical) stay counted as they are today, named as such.
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/loa-status-providers.bats` (LS-1 fixtures `none`, `r3-partial` and the `_oracle`): with one chain file deleted the summary names one absent chain and the JSON `absent` is 1; with every file present and valid the counts equal today's `7/7` reading; a broken chain is reported as broken, not absent.
- [ ] The intended output change is enumerated in the sprint report (the one human line and the added JSON object); every other `loa-status` line byte-identical old-versus-new (mirror parity); `run-preflight.sh` unchanged.
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated.
**Dependencies:** none.

> Sources: `.claude/scripts/loa-status.sh:408-461, 481-522`; `tests/unit/loa-status-providers.bats` (LS-1); Sprint 282 audit LOW-001 (DISS-C-004), bead bd-hyah6

### FR-4: `.run/perf-cache` is created under umask 077 by every creator (bd-20bh1)
**Priority:** Should Have
**Description:** `zone-write-guard.sh` (line 261) and any other framework writer that creates `.run/perf-cache` (the karpathy hook's state writers, grimoire-index's `_gi_dec_write` already does) create the directory inside a `(umask 077; mkdir -p …)` subshell or an equivalent, so a fresh directory is 0700 regardless of the user's umask and the D-5.3 tightening (`chmod go-w`) becomes a no-op on fresh mounts.
**Acceptance Criteria:**
- [ ] Red test: under `umask 002` a fresh `.run/perf-cache` created by the zone-write-guard hook is mode 0700 (today 0775); the same for every other creator the SDD enumerates.
- [ ] `grimoire-index.bats` D-5.3 case still passes (the tightening path stays for directories created by older versions).
- [ ] Spawn budgets unchanged (a `umask` subshell is a builtin; no new process).
**Dependencies:** FR-1 lands first when both touch the same hook line ranges (sequencing only).

> Sources: `.claude/hooks/safety/zone-write-guard.sh:230-264`; `.claude/hooks/quality/karpathy-surgical-diff-check.sh:156-157`; DEC-1126; `grimoires/loa/a2a/sprint-282/reports/a.md` (decision 1)

### Sprint 2 — hooks and the known-failures surface

### FR-5: The karpathy checkpoint seam is gated or announced (bd-yos4s)
**Priority:** Should Have
**Description:** `KARPATHY_CHECKPOINT_CMD` (`karpathy-surgical-diff-check.sh:62`) is honoured only under a bats marker (`BATS_TEST_FILENAME`/`BATS_VERSION`, as `_loa_pl_paths` does for `LOA_STATUS_CONFIG_FILE`), or, if a non-bats consumer needs it, honoured with a once-per-process WARN on stderr in the profile-lib style; `perf-spawn-budget.bats` passes the marker explicitly instead of relying on `env -i`.
**Acceptance Criteria:**
- [ ] Red test: outside bats (marker absent) an exported `KARPATHY_CHECKPOINT_CMD` pointing at a counter script is not executed (or is executed with the WARN line present — the SDD chooses one and the test pins it).
- [ ] Hook stdout and state files byte-identical on the pass-19 matrix (the seam is not used by the live path).
- [ ] Spawn budget unchanged.
**Dependencies:** none.

> Sources: `.claude/hooks/quality/karpathy-surgical-diff-check.sh:38-62`; `.claude/scripts/lib/profile-lib.sh:57-67` (the seam pattern); Sprint 282 audit LOW-003 (DISS-C-007)

### FR-6: Trajectory append refuses symlinked directories and files (bd-kdzc3)
**Priority:** Should Have
**Description:** Before `mkdir -p "$TRAJ_DIR"` and the `>>` append (`karpathy-surgical-diff-check.sh:214-217`) the hook refuses when `TRAJ_DIR` or the per-day file is a symlink (`-L`), exactly as its state files are guarded; refusal is silent (fail-open: the warning line is still printed, only the append is skipped).
**Acceptance Criteria:**
- [ ] Red test: with the trajectory directory (or the day file) replaced by a symlink to a victim file, the hook's warning path leaves the victim byte-identical and writes nothing through the link; the normal append still works.
- [ ] Spawn budget unchanged (`[[ -L ]]` is a builtin).
**Dependencies:** none.

> Sources: `.claude/hooks/quality/karpathy-surgical-diff-check.sh:205-220`; Sprint 281 audit LOW-003; the state-file symlink guard in the same hook

### FR-7: The KF SessionStart surface has a volume bound (bd-4sikh)
**Priority:** Should Have
**Description:** `loa-kf-surface.sh` prints at most N rows (a documented constant in the hook, default decided in the SDD — the live file has 65 entries) chosen deterministically (recurrence count descending, then id descending), followed by one line `… and K more: see grimoires/loa/known-failures.md` when entries were elided; when the file has ≤ N entries the output is byte-identical to today's.
**Acceptance Criteria:**
- [ ] Red test: a 100-entry fixture yields N rows + the summary line; a fixture with ≤ N entries yields today's exact output (byte-identical against the pre-change hook on the fixture set and the live file if 65 ≤ N — otherwise the live diff is exactly the elided rows + one line, attached).
- [ ] Ordering is deterministic and pinned by a test (ties broken by id).
- [ ] Spawn budget (`kf-surface 36/2`) unchanged: the selection happens inside the existing awk program.
**Dependencies:** FR-8 (same awk program; land FR-8 first or together).

> Sources: `.claude/hooks/loa-kf-surface.sh:88-140`; `grep -c '^## KF-' grimoires/loa/known-failures.md` = 65; Sprint 281 audit LOW-002

### FR-8: The KF sanitiser strips UTF-8-encoded C1 controls (bd-z6gxn)
**Priority:** Should Have
**Description:** `san()` in `loa-kf-surface.sh` and its twin `SAN_AWK` in `grimoire-index.sh` turn the byte pairs `\302[\200-\237]` (U+0080–U+009F) into a space, aligning the awk sanitisers with the decisions jq `s` filter; the drift-guard test keeps the two programs identical; mawk, busybox awk and `gawk --posix` produce identical output on the fixture set.
**Acceptance Criteria:**
- [ ] Red test: a fixture symptom containing NEL (U+0085) and other C1 code points yields a single space in the hook's table and the index TSV; C0, DEL and the byte cap behave as today; the live file output byte-identical (no C1 bytes in it today — asserted by a grep in the report).
- [ ] Drift guard green; three-awk parity green; spawn budgets unchanged.
**Dependencies:** none.

> Sources: `.claude/hooks/loa-kf-surface.sh:97-104`; `.claude/scripts/grimoire-index.sh` `SAN_AWK`; Sprint 282 report A (observation); bead bd-z6gxn

### FR-9: The BSD byte-cap contract is verified or documented (bd-aceil)
**Priority:** Could Have (bounded exit by DEC-1146)
**Description:** The KF awk programs' NUL regex (`/\000/`), octal classes and `LC_ALL=C` byte cap are verified under a BWK one-true-awk build and BSD `cut` semantics; the byte-versus-character cap contract on BSD hosts is stated in the hook header and pinned by a fixture with a 3-byte UTF-8 symptom crossing the cap. If no BWK build can be obtained on the ship host within the sprint, form (b) applies: the contract is stated and tested under the available awks, the BWK verification stays UNVERIFIED with the reason in the report, and a bead stays open for a macOS host.
**Acceptance Criteria:**
- [ ] Form (a): BWK awk and `gawk --posix`, mawk, busybox produce identical output on the fixture set incl. NUL, `\001`, `\177` and a multi-byte symptom at the cap; or form (b): the attempt and its blocker are recorded, the contract text landed, a class-S row written.
- [ ] No change to Linux output in either form.
**Dependencies:** FR-7, FR-8 (the same programs).

> Sources: Sprint 281 audit MED-001 (DEC-1123); `grimoires/loa/a2a/sprint-282/reports/a.md` (BWK unobtainable: no yacc, upstream unreachable); Bridgebuilder #1309 R-001; DEC-1146

### Sprint 3 — tests, guards and one refactor

### FR-10: `forbidden()` protects the descendants of a mapping-level floor key (bd-7utms)
**Priority:** Should Have
**Description:** In `profile-lib.sh` the floor predicate gains a descendant clause (`$k` starts with `<floor key without glob>.`) so a profile or cached key one level below a floor entry that names a mapping is dropped with the existing WARN text.
**Acceptance Criteria:**
- [ ] Red test in `tests/unit/profile-floor.bats` (or `profile-lib.bats`): a fixture floor entry `safety.block_destructive` drops a profile key `safety.block_destructive.enabled` with the WARN; existing glob and ancestor cases unchanged; the live floor list (`fence:*`, `gate:*`, `policy:*` tokens) produces identical output.
**Dependencies:** none.

> Sources: `.claude/scripts/lib/profile-lib.sh:131`; `.claude/data/floor.yaml`; Sprint 282 audit LOW-002 (DISS-C-005)

### FR-11: `loa_knob` presence metadata cannot collide with a value (bd-y5fy4)
**Priority:** Should Have
**Description:** The internal result of the cache and memo reads in `loa_knob` carries presence separately from the rendered value (a JSON `{kind, value}` or an exit-code channel — the SDD decides) so the strings `__LOA_PL_ABSENT__`, `__LOA_PL_MISS__` and `__LOA_PL_STALE__` are no longer sentinels a configured value can equal; the public contract (`loa_knob <path> <fallback>` prints the value or the fallback) and the 19 call sites in 10 files are unchanged.
**Acceptance Criteria:**
- [ ] Red tests in `profile-lib.bats`: a config value literally equal to each former sentinel round-trips through the warm path, the memo path and the live path; the warm-versus-live classification matrix stays green.
- [ ] Outputs byte-identical on the live config and the matrix for every caller; karpathy spawn budget unchanged.
**Dependencies:** FR-1 (same file; sequencing).

> Sources: `.claude/scripts/lib/profile-lib.sh:236-288`; `grep -rn loa_knob .claude --include=*.sh` = 19 sites; Sprint 282 review observation 3; Bridgebuilder #1309 R-002

### FR-12: The spawn-budget guard measures the grimoire-index cache hit (bd-5v1oa)
**Priority:** Should Have
**Description:** `perf-spawn-budget.bats` adds a second trace of the same decisions fixture after a first run (warm cache) with its own measured budget and reason, so the production hot path (a hit) is guarded as the miss is.
**Acceptance Criteria:**
- [ ] The new target traces a hit (the trace shows no `yq -o=json` parse of decisions.yaml) with a budget measured over three identical runs plus the file's headroom rule; a deliberately added spawn on the hit branch fails it (a one-off red run recorded in the report).
**Dependencies:** none.

> Sources: `tests/unit/perf-spawn-budget.bats:137-169`; Sprint 282 review observation 1

### FR-13: CMP-55 observes the reap it exercises (bd-rq6gk)
**Priority:** Could Have
**Description:** `adversarial-review-companion.bats` CMP-55 asserts that the reaper was attempted (an observable marker from the wrapped `_adv_kill_tree`) so its stub hold can be shortened to the file's 240 s like the other reaped holds, and the sleeper margin is raised so a slow host cannot make the shortened hold flaky.
**Acceptance Criteria:**
- [ ] CMP-55 fails when the reaper is never invoked (one-off red run recorded); with the hold at 240 s the serial whole-file TAP set is identical to today's and the wall time drops by about 60 s on the measured floor (DEC-1130).
**Dependencies:** none.

> Sources: `tests/unit/adversarial-review-companion.bats:1678-1691`; DEC-1130, DEC-1131

### FR-14: `_path_without` builds its skip list before switching IFS (bd-3qed8)
**Priority:** Could Have
**Description:** In `tests/unit/loa-decisions-surface.bats` the helper reads its arguments into an array before `local IFS=:` so `_path_without a b` excludes both tools; a multi-tool case pins it.
**Acceptance Criteria:**
- [ ] Red test: `_path_without yq jq` yields a PATH with neither tool; the single-tool callers unchanged.
**Dependencies:** none.

> Sources: `tests/unit/loa-decisions-surface.bats:124-140`; Sprint 281 review observation 3; Bridgebuilder #1309 R002

### FR-15: One lazily built provider dispatch mapping (bd-0h7kq)
**Priority:** Could Have (deferrable by DEC-1146)
**Description:** `providers/__init__.py` builds one lazily populated registry used by both `__getattr__` and the normal `_ADAPTER_TYPES` resolution, derives `cli_adapter_types` from a static auth table, and tests presence with name-in-`globals()` instead of truthiness; behaviour and import cost unchanged (the cheval `--help` and spawn budgets as today).
**Acceptance Criteria:**
- [ ] Existing provider tests green; `cheval --help` timing within the loop's measured band; a red test for the one observable change the refactor pins (the SDD names it) — or a class-S deferral row.
**Dependencies:** none.

> Sources: `.claude/adapters/loa_cheval/providers/__init__.py:26-60`; Sprint 281 review observation; DEC-1146

### FR-16: Ship — one PR, Bridgebuilder, merge, record, archive; no release
**Priority:** Must Have
**Description:** After the third sprint's `COMPLETED`: secret scan on the final head; PR from `feature/cycle-138-hardening-followups` whose body lists the three sprints, beads, DEC rows and each gate's verdict with its `reviewed_head`; Bridgebuilder ≤ 2 rounds (`BRIDGEBUILDER_MODEL=codex-headless`, generated and planning files excluded; the degraded exit applies only with no blocking finding open); merge only when every check run on the exact head has completed with `success` (or `skipped`/`neutral` for path-filtered workflows) and the six required checks are `success`; `git diff --quiet <head> <merge>`; record branch via `record-branch.sh`; main CI green; `archive-cycle.sh` on a chore branch, housekeeping merge; `JACKED_OUT`. The rc.10 candidate the pipeline prepares is left unpublished and said so in the PR body.
**Acceptance Criteria:**
- [ ] The merge gate predicate above holds on the exact head; both verdicts of every sprint name a head whose code equals the merged tree (docs-only tails allowed, listed).
- [ ] Record branch pushed; archive PR merged as housekeeping (both Prepare jobs skipped); ledger cycle archived; beads closed with the merged sha.
- [ ] No tag created, no release published (`gh release list` unchanged); the publish-summary stage is not run.
**Dependencies:** FR-1 … FR-15 landed or deferred.

> Sources: cycle-137 § Ship S-1 … S-9 and its e2e.md part 2 (the scripts under `~/.cache/loa/cycle-137/ship/` are the recipe); DEC-1139, DEC-1145

---

## Non-Functional Requirements

### Performance
Every change keeps its hot path's spawn budget (`perf-spawn-budget.bats`; FR-1 may add one spawn with the reason in the budget line); where output changes by design (FR-3, FR-7) the change is enumerated; everything else is byte-identical old-versus-new on the live inputs and the fixture matrices. Benchmark protocol for any number quoted: `hyperfine -N -i --warmup 3 --runs 10`, old and new mirrors in the same session, host state named (the fukuoka runaway shells are gone; load is checked before a timing claim).

### Security
Trust boundaries are explicit and tested with foreign-owned, group-writable, symlinked, FIFO and hard-link fixtures; refusals fall back to today's behaviour (never a silent pass); bodies and config values stay data to static programs (no `eval`, no `source` of data, no interpolated `bash -c`, nothing user-controlled on `execve` argv in the publish path); untrusted bodies sanitised at surfacing; the audit chain untouched; seams honoured only under a bats marker or with a WARN.

### Reliability
Red-first tests for every behaviour change; `red-test-check.sh` per red commit; the covering suites and the full unit suite green on each sprint's head (only the KF-034 trio allowed red; new skips only when named and host-conditional); rollback is one revert per bead (red and fix together).

### Compliance
System Zone writes under the bounded marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); class-S decision rows for every judgment call (`dec-batch`, summary ≤ 150 code points); CHANGELOG `[Unreleased]` lines per behaviour-visible change (FR-3, FR-7 wording; FR-1 refusal semantics); no version stamp changes.

### Authorization basis and refusal list
Operator instruction of 2026-10-29 (verbatim in the brief). Unattended implementation, gates, merge, record and archive are authorised; publishing is NOT (DEC-1145). Refuse: writing `main` outside the merge, force-pushing, deleting tags or branches, merging with a red or pending required check, creating a tag or release, touching credentials or the live push configuration in tests, changing `br` contract calls, quarantining a test, editing `.claude/` outside the authorised list below.

> Sources: brief § Constraints and § Non-goals; DEC-0824; DEC-1145; cycle-137 PRD § Authorization basis (the refusal list carried forward)

---

## User Experience

### Key User Flows
Edit → identical gate decisions and karpathy warnings, with the profile cache refused only where it should never have been trusted. `/loa` → the chain summary names absent chains. Session start → at most N KF rows plus one "and K more" line. Release → notes of any size under GitHub's limit publish.

### Interaction Patterns
Two new operator-visible texts: the chain-summary wording (FR-3) and the KF elision line (FR-7); one optional WARN (FR-5). Everything else silent.

### Accessibility Requirements
Plain text; no colour-only signals (`agent-ergonomics-color-guard.bats` green).

> Sources: `.claude/settings.json` (hook wiring); `tests/unit/agent-ergonomics-color-guard.bats`

---

## Technical Considerations

### Architecture (for the SDD)
C-1 profile-lib trust boundary (mirror of `_gi_trusted_dir` / `_gi_dec_write`, shared or duplicated — the SDD decides whether a tiny `cache-trust-lib.sh` is worth a new sourced file on the hot path); C-2 publisher file-borne bodies (`--rawfile`, the sprint-bug-283 temp-dir pattern); C-3 chain summary third state (string + JSON object); C-4 umask-077 creators; C-5 karpathy seam gate + symlink guards; C-6 KF hook: C1 class, volume bound, BSD contract (one awk program, three changes, one drift guard); C-7 profile-lib floor clause + presence metadata; C-8 test guards (spawn hit target, CMP-55, `_path_without`); C-9 providers registry; C-10 ship.

### System Zone authorization (explicit, cycle-level)
This PRD authorises writes under `.claude/scripts/lib/profile-lib.sh`, `.claude/scripts/post-merge-orchestrator.sh`, `.claude/scripts/loa-status.sh`, `.claude/hooks/safety/zone-write-guard.sh`, `.claude/hooks/quality/karpathy-surgical-diff-check.sh`, `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh` (the `SAN_AWK` twin only), `.claude/adapters/loa_cheval/providers/__init__.py` (FR-15 only), `.claude/data/profiles.yaml` / `.claude/data/floor.yaml` (test fixtures only if needed — the SDD states), `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md{,.checksum}` — each under the bounded marker with manifests regenerated in the same commit. Any other System Zone path needs a PRD amendment.

### Integrations
GitHub (PR, checks, merge) through `gh`; Bridgebuilder `codex-headless`; the post-merge pipeline runs on the merge and prepares a candidate that is not published.

### Dependencies
None new (python3, jq, yq v4, bats 1.13 as today).

### Technical Constraints
Hooks must stay bash-3.2-safe where they already are (no associative arrays, no `${var,,}`); awk changes must run on mawk, busybox awk and `gawk --posix`; `SKILL.md` budgets untouched; NOTES.md under the size guard (rotate if needed).

> Sources: `.claude/scripts/grimoire-index.sh:263-331`; `grimoires/loa/a2a/bug-20261028-90f357/reviewer.md` (temp-dir pattern); DEC-0824

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1, FR-2, FR-3, FR-16 (Must); FR-4 … FR-8, FR-10 … FR-12 (Should); FR-9, FR-13, FR-14, FR-15 (Could — FR-9 and FR-15 with the bounded exits of DEC-1146).

### In Scope (Future Iterations)
Promotion `v2.0.0-rc.N → 2.0.0` (operator's call); a `/bug` for the ledger numbering defect (KF-065, bd-d6dr5); a macOS host run for FR-9 form (b).

### Explicitly Out of Scope
- Publishing any release — Reason: DEC-1145; rc.9 is soaking and promotion is the operator's decision.
- New optimisation targets, Flatline/Bridgebuilder/adapter wire-contract changes, test quarantines — Reason: brief § Non-goals.
- The ledger-lib `_next_cycle_id` fix — Reason: a separate defect with its own red test (bd-d6dr5), outside the fifteen beads.

### Priority Matrix
| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1 profile-lib cache boundary | P0 | M | High (per-tool-call trust surface) |
| FR-2 publisher bodies off argv | P0 | S | High (release path) |
| FR-3 absent chain third state | P0 | S | Med (integrity view) |
| FR-4 umask-077 creators | P1 | S | Med |
| FR-5 / FR-6 karpathy seam + symlink guards | P1 | S | Med |
| FR-7 / FR-8 KF volume bound + C1 | P1 | S | Med |
| FR-9 BSD contract | P2 | M (tooling) | Low–Med |
| FR-10 / FR-11 floor clause + presence metadata | P1 | S/M | Med |
| FR-12 / FR-13 / FR-14 guards | P2 | S | Low–Med |
| FR-15 providers registry | P3 | M | Low |
| FR-16 ship | P0 | M | — |

> Sources: brief § Scope and § Non-goals; DEC-1145, DEC-1146; KF-065 / bd-d6dr5

---

## Success Criteria

### Launch Criteria
- [ ] Three `COMPLETED` markers with `All good` + `APPROVED` bound to heads whose code equals the merged tree.
- [ ] 15 beads closed or deferred-with-row; `red-test-check.sh` VERIFIED per red commit; full `tests/unit` green modulo the KF-034 trio; spawn budgets green.
- [ ] PR merged on the exact green head; record branch; archive merged as housekeeping; `JACKED_OUT`; no tag, no release.

### Post-Launch Success (30 days)
- [ ] No regression report against the profile cache, the chain summary wording or the KF elision on downstream mounts.

### Long-term Success (90 days)
- [ ] The next release (rc.10 or 2.0.0) publishes end to end with large notes through the file-borne path.

> Sources: cycle-137 PRD § Success Criteria (carried pattern); G-1 … G-4 above; `tests/unit/perf-spawn-budget.bats`

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| FR-1's trust check refuses the cache on a common layout and silently slows every edit | Med | Med | parity + spawn-budget guards on the pass-19 matrix; the refusal is logged once per process in the sprint's diagnostics mode; DEC row if any default layout refuses |
| FR-3 / FR-7 wording changes break a consumer that parses `loa-status --json` or the KF table | Low | Med | keep `audit_chain_summary`; add fields, never remove; KF elision line is additive |
| BWK awk still unobtainable (FR-9) | High | Low | form (b) exit, DEC-1146 |
| Bridgebuilder degraded again (KF-037 class) | Low (host unloaded) | Low | the plan's degraded exit; retry once after ten minutes first |
| Dissent budget exhausted by review rounds | Med | Low | round 3 lead-only; the audit keeps run 3 (DEC-1134 pattern) |
| Three sprints' wall time (gates ≈ 2 h each) | — | Low | sprints are independent; a HALT at a sprint boundary loses nothing |

### Assumptions
- `[ASSUMPTION decision]` (DEC-1144) grounding on REPO-MAP and finding anchors suffices — if wrong, an FR cites a stale line and the SDD's own code reads correct it.
- `[ASSUMPTION decision]` (DEC-1145) no release this cycle — if wrong, the operator asks and the cycle-137 publish recipe applies to the prepared candidate.
- `[ASSUMPTION decision]` (DEC-1146) bd-aceil and bd-0h7kq may end as documented exits — if wrong, the operator reopens them with a host or a reason.

### Dependencies on External Factors
GitHub Actions availability for the required checks; the host staying unloaded for the companion voice.

> Sources: KF-037 (companion timeouts), DEC-1134 (third dissent run = audit), DEC-1123 (BWK unobtainable), DEC-1144 … DEC-1146

---

## Timeline & Milestones

| Milestone | Target |
|---|---|
| PRD 1.0 + Flatline review → 1.1 | T+1 h |
| SDD, sprint plan, beads created | T+3 h |
| Sprint 1 implemented, reviewed, audited | T+8 h |
| Sprint 2 | T+13 h |
| Sprint 3 | T+17 h |
| Ship (PR, BB, merge, record, archive) | T+20 h |

(T = this PRD's timestamp; unattended, one calendar day; slip order: FR-15, FR-13, FR-9 first.)

> Sources: cycle-137 sprint plan § Time budget (the gate durations observed on 2026-10-28: review + audit ≈ 2 h per sprint, Shell Tests ≈ 75 min)

---

## Appendix

### A. Bead map
| FR | Bead | Origin |
|---|---|---|
| FR-1 | bd-j34zb | Sprint 282 audit MED-001 |
| FR-2 | bd-qyvju | sprint-bug-283 review r2 obs 4 |
| FR-3 | bd-hyah6 | Sprint 282 audit LOW-001 |
| FR-4 | bd-20bh1 | Sprint 282 report A / DEC-1126 |
| FR-5 | bd-yos4s | Sprint 282 audit LOW-003 |
| FR-6 | bd-kdzc3 | Sprint 281 audit LOW-003 |
| FR-7 | bd-4sikh | Sprint 281 audit LOW-002 |
| FR-8 | bd-z6gxn | Sprint 282 report A |
| FR-9 | bd-aceil | Sprint 281 audit MED-001 / BB #1309 R-001 |
| FR-10 | bd-7utms | Sprint 282 audit LOW-002 |
| FR-11 | bd-y5fy4 | Sprint 282 review obs 3 / BB #1309 R-002 |
| FR-12 | bd-5v1oa | Sprint 282 review obs 1 |
| FR-13 | bd-rq6gk | Sprint 282 Task 2.5 |
| FR-14 | bd-3qed8 | Sprint 281 review obs 3 / BB #1309 R002 |
| FR-15 | bd-0h7kq | Sprint 281 review obs |

### B. Decision rows written for this PRD
DEC-1144 (grounding), DEC-1145 (scope and no release), DEC-1146 (bounded exits for bd-aceil and bd-0h7kq), DEC-1147 (ledger id correction, KF-065, bd-d6dr5) — all `proposed`, class S.

### C. Grounding note
No `/ride` run: the reality set is from 2026-05-04; the anchors above were read from the working tree at fe52be893 while writing this PRD, and `grimoires/loa/REPO-MAP.md` is regenerated at every System Zone commit. Conflicts between a bead's text and the current code were resolved in favour of the code and noted in the FR.

> Sources: beads bd-j34zb … bd-qyvju (`br show`); `grimoires/loa/decisions.yaml` DEC-1144 … DEC-1147; `grimoires/loa/known-failures.md` KF-065
