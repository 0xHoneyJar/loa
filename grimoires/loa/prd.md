# Product Requirements Document: Hardening follow-ups (cycle-138)

**Version:** 1.2
**Date:** 2026-10-29
**Revision:** 1.2 carries the Flatline SDD review back (SDD 1.2 § 11.F; Appendix E here): FR-2's bodies reach `jq --rawfile` through process substitutions (the 1.1 temp-file helper is withdrawn — its function-scoped RETURN trap would have deleted the file before use); FR-1 states its trust lifetime, lets the cache writer create an absent `.run` 0700 and names grimoire-index's existing tightening as the repair owner of a legacy writable `.run`; FR-3's JSON adds `not_applicable`; FR-4 enumerates every `mkdir` that can create `.run` or a directory under it; FR-6 refuses a group/other-writable day file, anchors the component check at the canonical checkout root and refuses without `realpath -m`; FR-11 puts the kind token on the last line with a newline guard. 1.1 integrates the Flatline PRD review of 1.0 (5 blockers, 48 medium items from two voices; cross-scoring degraded — dispositions in Appendix D): the profile-lib trust predicate now covers the cache file (ownership, mode, one link) and refuses rather than tightens a writable `.run`; the trajectory guard covers every path component, the file type and ownership; the karpathy seam is ignored in production; the KF cap separates selection from display order and states a byte ceiling; FR-3 gets a per-primitive classification; verdict binding, the six required checks, the three allowed failures, the Bridgebuilder degraded exit and the unattended halt protocol are explicit; FR-9 form (b) requires a prebuilt-BWK attempt first.
**Author:** Requirements Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous cycle on the operator's instruction of 2026-10-29 ("… and then proceed with the next cycle …", after the lead's next-steps message that named this cycle's content)
**Cycle:** `cycle-138-hardening-followups` (ledger), branch `feature/cycle-138-hardening-followups` from `main` fe52be893
**Grounding:** brownfield; the stale `grimoires/loa/reality/` set (2026-05-04) is not re-run — grounding is the live `grimoires/loa/REPO-MAP.md`, the file:line anchors each bead's finding recorded, and the cycle-137 / sprint-bug-283 gate artefacts (DEC-1144); the brief is `grimoires/loa/context/cycle-138-brief.md`, the bead table `grimoires/loa/context/cycle-138-followups.md`

---

## Table of Contents

1. Executive Summary
2. Problem Statement
3. Goals & Success Metrics
4. User Personas & Use Cases
5. Functional Requirements
6. Non-Functional Requirements
7. User Experience
8. Technical Considerations
9. Scope & Prioritization
10. Success Criteria
11. Risks & Mitigation
12. Timeline & Milestones
13. Appendix A — Bead map · B — Decision rows · C — Grounding note · D — Flatline PRD review dispositions

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
5. **Hook seams and surfaces.** The karpathy hook honours `KARPATHY_CHECKPOINT_CMD` from the ambient environment (`karpathy-surgical-diff-check.sh:62`) and appends its trajectory through a directory and file it never checks (`:214-217`); the known-failures SessionStart hook injects every entry (65 today) into the session context with no volume bound; its `san()` strips C0 and DEL but not UTF-8-encoded C1 controls (`loa-kf-surface.sh:97-104`); the BSD byte-cap contract of that sanitiser is still unverified on BWK awk / BSD `cut` (Sprint 281 MED-001, DEC-1123).
6. **Guards the gates found hollow or missing.** `forbidden()` has no descendant clause for a mapping-level floor key (`profile-lib.sh:131`); `loa_knob` returns sentinel strings that a real config value can collide with (`profile-lib.sh:248-280`); the spawn-budget guard measures the grimoire-index cache miss only; CMP-55 asserts nothing about the reap it exercises; `_path_without a b` excludes nothing (`loa-decisions-surface.bats:124-135`); the providers registry builds its dispatch twice over.

### User Pain Points

- The maintainer cannot claim the trust boundary cycle-137 introduced is complete while the cache that runs on every edit lacks it.
- A release whose notes quote enough multi-byte text could fail at creation with an `E2BIG` nobody expects.
- The one in-tool integrity view can be silenced by deleting a file.

### Current State

`main` at fe52be893 (`v2.0.0-rc.9` + sprint-bug-283); fifteen beads open under the `cycle-137` label; the full unit suite green modulo the three KF-034 `semver evidence` tests; `check-loa.sh` All checks passed.

### Desired State

Every bead closed with a red-first test and a landed fix (or, for bd-aceil and bd-0h7kq, the bounded exit a class-S row records — DEC-1146); every touched hot path byte-identical old-versus-new (or differing only by its enumerated change) and inside its spawn budget; three sprints through `/review-sprint` and `/audit-sprint`; one PR merged on green; record and archive; no release.

> Sources: `.claude/scripts/lib/profile-lib.sh:50-76, 181-222, 236-288`; `.claude/scripts/post-merge-orchestrator.sh:1286, 1488, 1502`; `.claude/scripts/loa-status.sh:408-461, 481-522`; `.claude/hooks/safety/zone-write-guard.sh:230-264`; `.claude/hooks/quality/karpathy-surgical-diff-check.sh:38-62, 205-220`; `.claude/hooks/loa-kf-surface.sh:88-110`; `tests/unit/perf-spawn-budget.bats:137-169, 275-299`; `tests/unit/adversarial-review-companion.bats:1678-1691`; `tests/unit/loa-decisions-surface.bats:124-140`; `.claude/adapters/loa_cheval/providers/__init__.py:26-60`

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Every one of the fifteen beads is closed by a landed red-first fix, or by the bounded exit DEC-1146 / DEC-1160 names (bd-aceil contract form with a linked macOS bead; a deferral row with a successor bead for FR-13, FR-15 or FR-9 under schedule slip) | 15 beads closed-or-deferred-with-row; `red-test-check.sh` VERIFIED per red commit | `br show` per bead; `~/.cache/loa/cycle-138/logs/rtc-*.json` |
| G-2 | No hot path regresses: spawn budgets hold at their current counts (karpathy warm path 196 trace lines / 9 external tools; kf-surface 36/2; grimoire-index 167/15); every touched entry point byte-identical old-versus-new on the live inputs and the fixture matrix except the enumerated changes of FR-3, FR-7, FR-8, FR-10, FR-11 | `perf-spawn-budget.bats` green; mirror parity logs with the enumerated diffs attached | the sprint reports and the review's own parity re-run |
| G-3 | Each sprint's `/review-sprint` (`All good`) and `/audit-sprint` (`APPROVED`) bind to that sprint's head (docs-only tails allowed and listed); the final sprint's gates bind to the PR head and include the whole-head parity gate over every entry point any sprint touched; ≤ 3 dissent runs per sprint (DEC-1161) | three COMPLETED markers; `verdict-derive.sh` CONSISTENT; parity log on the PR head | `a2a/sprint-<N>/`, the final sprint's `e2e.md` |
| G-4 | One PR merged under the merge gate of FR-16 after ≤ 2 Bridgebuilder rounds; record branch and archive; nothing published | merge sha on `origin/main`; `git ls-remote --tags origin` unchanged | `e2e.md` part 2 |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Open follow-up beads from cycle-137 / sprint-bug-283 | 15 | 0 open (deferred-with-row and successor bead counts as closed for this cycle — DEC-1160) | cycle end | G-1 |
| profile-lib cache: reads of a foreign-owned, writable, hard-linked or symlinked cache | accepted | refused (red tests) | Sprint 1 | G-1 |
| Publisher POST/notify body size that fails at `execve` | > 131 072 bytes | none (file-borne) | Sprint 1 | G-1 |
| `loa-status` chain summary with one chain file deleted | `7/7` | names the absent primitive; never `7/7` | Sprint 1 | G-1 |
| karpathy hook warm-path spawns (`perf-spawn-budget.bats`) | 196 / 9 | 196 / 9 (unchanged) | Sprint 1 | G-2 |
| Full `tests/unit` on each sprint's final head | 7315 planned, 3 allowed reds (KF-034) | new tests added, the same 3 reds only (exact names in R-4 below), no new skips except named host-conditional ones | each sprint | G-3 |

### Constraints

- No new configuration keys unless a requirement states one (FR-7's cap is a documented constant; a knob only if a downstream asks later).
- No behaviour change on a hot path without a red test; where output changes by design (FR-3 wording and JSON object, FR-7 elision, FR-8 C1 fixtures, FR-10/FR-11 adversarial configurations) the change is enumerated per fixture and the parity criterion becomes "differs only by the enumerated lines, diff attached".
- No release, no tag, no publish in this cycle (DEC-1145). Publishing is only ever an explicit operator-only `post-merge-orchestrator.sh --publish <candidate> --approve-sha256 <digest>` from a clone; nothing in CI publishes.
- **Unattended halt protocol (DEC-1160):** when a sprint's review or audit does not reach `All good` / `APPROVED` within the sprint's dissent budget (three runs, the third the audit's), or the one-day budget (T+20 h) is exceeded, the run HALTs at the sprint boundary with the HALT checkpoint written; the PR is opened with the completed sprints only; remaining beads stay open with a class-S row naming the stop. Schedule slip may defer FR-13, FR-15 and FR-9 (in that order) by a row with a successor bead.
- **R-4 allowed failures:** exactly `semver evidence: unknown squash subject refuses silent patch`, `semver evidence: classification records its source and matching commit`, `semver evidence: breaking body retains the classifying commit identity` (KF-034, host `tag.gpgsign`), failing with the same signature as on `main`; any other failure, or a changed signature, blocks the gate.

> Sources: brief § Constraints; DEC-1144 … DEC-1147, DEC-1157 … DEC-1161; `tests/unit/perf-spawn-budget.bats:119-299`; `grimoires/loa/a2a/sprint-282/e2e.md` § G-4

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
**Actor:** maintainer on a shared workstation. **Preconditions:** `.run` group-writable; a co-tenant plants `.run/effective-config.json`. **Flow:** a Write triggers the karpathy hook → `loa_knob` → the profile-lib trust predicate refuses the directory → the live read answers. **Postconditions:** the attacker's knobs are never served; the hook's output is identical to the no-cache path; `loa_profile` reports `cache: off (reason)`. **Acceptance Criteria:** FR-1.

#### UC-2: Large release notes
**Actor:** the publisher. **Preconditions:** a candidate whose `release_body` exceeds 131 072 bytes while under GitHub's 125 000-character limit. **Flow:** `--publish` creates the release and comment with file-borne bodies. **Postconditions:** release verified; state `DONE`. **Acceptance Criteria:** FR-2.

#### UC-3: A tampered chain file is deleted
**Actor:** `/loa` status. **Flow:** `loa-status` lists the chain files; one is missing. **Postconditions:** the summary says `6/7 validate (1 absent, 0 broken)` and a following line names the absent primitive; it never reads `7/7`. **Acceptance Criteria:** FR-3.

> Sources: Sprint 282 audit MED-001, LOW-001; sprint-bug-283 review r2 observation 4

---

## Functional Requirements

### Sprint 1 — security and the release path

### FR-1: profile-lib effective-config cache gets a trust predicate (bd-j34zb)
**Priority:** Must Have
**Description:** `_loa_pl_load` and the warm path of `loa_knob` read `.run/effective-config.json` only when the **trust predicate** holds; `_loa_pl_write_cache` writes only under the same predicate. The predicate, evaluated once per process from the stat rows the library already takes (SDD § 3): (a) the cache's directory is a real directory (`-d && ! -L`), owned by the running uid, with no group or other write bit — a writable or foreign directory is **refused** (cache off, live read); profile-lib never `chmod`s from the hook path (DEC-1157; the D-5.3 tightening stays in `grimoire-index.sh`); (b) the cache file, when present, is a regular non-symlink file owned by the running uid, with no group/other write bit and exactly one link — anything else is refused for reading and the next write **replaces** it through `mktemp` + `rename`, never truncating through the existing inode (hard-link safety); (c) when a redirected `LOA_PROFILE_CACHE_FILE` is honoured outside bats (it keeps its once-per-process WARN — a read redirection, not a command), its directory must satisfy (a) and no path component may be a symlink (`realpath` of the directory equals the configured path). The writer: `umask 077`, `mktemp "$cache.XXXXXX"` beside the cache, `[[ ! -L cache ]]` re-check, `mv -f -T` (fallback `mv -f` only when the target is neither a directory nor a symlink); any failure removes the temp and leaves the cache untouched. **Trusted ancestor boundary:** the checkout root is the trust root (operator-owned); a co-tenant who can write the checkout root can edit the config itself and is outside this threat model; check-then-use between the predicate and the open is closed by the predicate itself (an adversary needs write access to the directory the predicate just refused to trust), stated in the code comment and exercised by the directory-replacement fixtures below. Every refusal falls back to today's live read: behaviour identical, output identical; `loa_profile` (human and `--json`) reports the cache state and the refusal reason; hooks stay silent.
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/profile-lib.bats` (fixtures modelled on `grimoire-index.bats` 420-500, ownership answered by a `stat` shim since the predicate reads the stat row): foreign-owned `.run` → neither read nor written; group-writable uid-owned `.run` → refused (no chmod, live read, `loa_profile` names the reason); symlinked cache file → ignored, never followed, replaced on the next write by rename; cache file hard-linked to a victim → not read, the write leaves the victim byte-identical with one link; attacker-planted regular file (foreign uid or group-writable) already present → not read, replaced; a symlink pre-planted at a temp-like name beside the cache → never followed; a FIFO at the cache path → not opened (no hang), replaced; `LOA_PROFILE_CACHE_FILE` outside bats pointing into a directory with a symlinked component → refused; the non-GNU `mv` fallback exercised with a `mv` shim lacking `-T`; the directory replaced by a symlink between two calls → the second call refuses.
- [ ] `loa_knob`, `loa_profile` and `_loa_pl_live` outputs byte-identical old-versus-new on the live config and on the pass-19 config matrix except `loa_profile`'s new cache-state line (enumerated); the karpathy hook's stdout/stderr/state files identical across that matrix (mirror in a REAL directory).
- [ ] `perf-spawn-budget.bats` karpathy target stays at 196 / 9 (the predicate reads the directory's row from the existing stat call); grimoire-index targets unchanged.
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated under the marker.
**Dependencies:** none. **Rollback:** FR-1 and FR-11 touch `profile-lib.sh`; their red/fix pairs revert together in reverse landing order.

**1.2 clarifications (SDD 1.2 § 3, § 5.1; DEC-1166):** the predicate's trust lifetime is the process — every sampled property (owner, mode bits, file type, link count) can be changed afterwards only by the same uid or by root, both outside the threat model, and replacing `.run` needs write permission on the checkout root, the trust root — so no re-validation per access is required (the writer still re-checks `-O` / `! -L` with builtins before the rename); the extended `stat`'s exit status is ignored and presence comes from its `%n` rows, with malformed rows refused before any arithmetic; an absent `.run` is created by the writer with `mkdir` (no `-p`) inside the `umask 077` subshell and trusted by construction; a pre-existing group/other-writable `.run` is REFUSED here and repaired by `grimoire-index.sh`'s existing `_gi_trusted_dir` tightening on its next run (the repair owner), `loa_profile` naming `dir-writable` meanwhile — one fixture per reason and a 775 `.run` row (off before, on after one grimoire-index run) join the matrix.

> Sources: `.claude/scripts/lib/profile-lib.sh:50-83, 181-222, 236-288`; `.claude/scripts/grimoire-index.sh:263-331` (the pattern mirrored); `grimoires/loa/a2a/sprint-282/auditor-sprint-feedback.md` MED-001; DEC-1126, DEC-1136, DEC-1157; Appendix D B1, B2, B4

### FR-2: Publisher request bodies leave argv (bd-qyvju)
**Priority:** Must Have
**Description:** In `post-merge-orchestrator.sh` the release-creation request (`phase_release`, line 1286) and the notify comment request and its read-back comparison (`phase_notify`, lines 1488 and 1502) stop passing bodies as `jq --arg` values: each body reaches `jq --rawfile` through a bash process substitution fed by the `printf '%s'` builtin (`--rawfile body <(printf '%s' "$notes")`) — no argv, no temporary file, no cleanup, no trap; the assembled JSON still reaches `gh api … --input -` on stdin exactly as today. The SDD enumerates every argv-borne body site on the publish path (`grep -n -- '--arg body\|--arg summary\|--arg notes'`) and converts each. The 1.1 mechanism (a temp directory removed by a RETURN trap inside a helper) is withdrawn: a function-scoped RETURN trap fires when the helper returns, before the caller reads the file (SDD 1.2 § 11.F B1). A jq failure hands `gh api` an empty request and the phase fails with today's text — no new failure path. Comparison semantics unchanged (the release body through `release_body_identical`; the comment byte-exact).
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/post-merge-publication.bats`: a `release_body` that is ≤ 125 000 characters yet > 131 072 bytes (multi-byte) publishes `DONE` (today: `jq: Argument list too long`); a `notification_body` within GitHub's 65 536-character comment limit but > 131 072 bytes posts and verifies; both together; the stub records the arguments every external publish-path command received and asserts no body marker string appears on any argv (replacing a `bash -x` grep); the existing 71 cases unchanged.
- [ ] No temporary storage: the three body sites carry no `mktemp` and exactly three `--rawfile body <(printf` operands (structural assertion in the test file); a shimmed jq exiting 2 records today's `fail_phase` text and issues no second POST.
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated.
**Dependencies:** none (sprint-bug-283 is merged).

> Sources: `.claude/scripts/post-merge-orchestrator.sh:1286, 1488, 1502` (at fe52be893); `grimoires/loa/a2a/bug-20261028-90f357/engineer-feedback-r2.md` § Observations 4; `getconf ARG_MAX` 2 097 152 / per-argument 131 072; Appendix D M-publisher

### FR-3: `loa-status` classifies every primitive and reports absence (bd-hyah6)
**Priority:** Must Have
**Description:** `_an_audit_chain_summary` classifies each of the seven primitives into exactly one state — `valid` (chain file exists and verifies), `absent` (chain file missing), `broken` (exists but fails verification, is unreadable, malformed, or the verifier failed / exited abnormally) or `n/a` (L5 and L7 carry no chain file by design and are counted as valid, labelled `n/a` in the per-primitive list) — with `valid + absent + broken = 7` for every fixture (`n/a` counted inside `valid`). The human line is byte-identical to today's `Audit chain: 7/7 primitives validate.` only when nothing is absent or broken; otherwise `Audit chain: V/7 validate (A absent, B broken).` followed by one line per non-valid primitive (`  L4 trust-ledger: absent`). The JSON keeps `audit_chain_summary: "V/7"` (V excludes absent) and adds `audit_chain: {valid, absent, broken, not_applicable, total, primitives: [{id, path, state}]}`.
**Acceptance Criteria:**
- [ ] Red tests in `tests/unit/loa-status-providers.bats` (LS-1 fixtures `none`, `r3-partial` and the `_oracle`): one chain file deleted → `absent 1`, the primitive named, never 7/7; all present and valid → today's exact line; one tampered → `broken 1`; one unreadable (mode 000) → `broken`; verifier exits abnormally → every existing chain `broken`; the sum invariant holds in each fixture; L5/L7 listed as `n/a` and `not_applicable: 2` reported in the JSON object (`valid` still includes them; verified chains = `valid − not_applicable`); verifier exit 2, duplicate / missing / unexpected index records → `broken`; an empty existing list → `absent 5` without a verifier call.
- [ ] The intended output change is enumerated in the sprint report (the human line in the non-healthy case, the per-primitive lines, the added JSON object); every other `loa-status` line byte-identical old-versus-new (mirror parity); `run-preflight.sh` unchanged.
- [ ] `red-test-check.sh` VERIFIED; manifests regenerated.
**Dependencies:** none.

> Sources: `.claude/scripts/loa-status.sh:408-461, 481-522`; `tests/unit/loa-status-providers.bats` (LS-1); Sprint 282 audit LOW-001 (DISS-C-004), bead bd-hyah6; Appendix D M-FR3

### FR-4: `.run/perf-cache` is created under umask 077 by every creator (bd-20bh1)
**Priority:** Should Have
**Description:** Every framework writer that can create `.run/perf-cache` — `zone-write-guard.sh:261` is the known one; the sprint's first task runs `grep -rn 'perf-cache' .claude --include='*.sh' --include='*.py'` AND `grep -rn 'mkdir.*\.run' .claude tests --include='*.sh' --include='*.py'` and lists every `mkdir` that can create `.run/perf-cache`, `.run` itself or any directory under it (the karpathy hook's state and trajectory `mkdir -p` at lines 162 and 214 and profile-lib's cache writer at line 186 — the last two are rewritten by FR-6 and FR-1 and only listed here; `grimoire-index.sh` already uses umask 077) — creates the directory inside a `( umask 077; mkdir -p … )` subshell, so a fresh directory is 0700 regardless of the user's umask and the D-5.3 tightening becomes a no-op on fresh mounts. `.run` itself is created by several scripts and is out of this FR's scope (noted).
**Acceptance Criteria:**
- [ ] Red test: under `umask 002` a fresh `.run/perf-cache` created by the zone-write-guard hook is mode 0700 (today 0775); the same for every other creator the enumeration finds.
- [ ] `grimoire-index.bats` D-5.3 case still passes (the tightening path stays for directories created by older versions).
- [ ] A pre-existing group/other-writable `.run` (an older creator under umask 002) is refused by FR-1 and repaired by `grimoire-index.sh`'s existing `_gi_trusted_dir` tightening on its next run — the repair owner, named in the CHANGELOG line; the FR-1 matrix carries the 775 `.run` row.
- [ ] Spawn budgets unchanged (`umask` is a builtin; no new process).
**Dependencies:** none (FR-4 edits `zone-write-guard.sh` and possibly the karpathy hook; FR-1 edits `profile-lib.sh` — no shared line ranges).

> Sources: `.claude/hooks/safety/zone-write-guard.sh:230-264`; `.claude/hooks/quality/karpathy-surgical-diff-check.sh:156-157`; DEC-1126; `grimoires/loa/a2a/sprint-282/reports/a.md` (decision 1)

### Sprint 2 — hooks and the known-failures surface

### FR-5: The karpathy checkpoint seam is a test seam only (bd-yos4s)
**Priority:** Should Have
**Description:** `KARPATHY_CHECKPOINT_CMD` (`karpathy-surgical-diff-check.sh:62`) is honoured only when a bats marker (`BATS_TEST_FILENAME` or `BATS_VERSION`) is set; outside bats the variable is ignored silently — no WARN-and-honour option (DEC-1158). The PRD states the threat model plainly: the markers are themselves ambient, so the gate defends against accidental honouring (a leaked `.envrc`, a re-exporting subprocess) and not against a hostile same-uid environment, which already controls the hook; the profile-lib config redirection (`LOA_PROFILE_CACHE_FILE` / `LOA_PROFILE_CONFIG_FILE`) keeps its once-per-process WARN because it redirects a read, not a command. `perf-spawn-budget.bats` passes the marker explicitly in its `env -i` allowlist for the karpathy target.
**Acceptance Criteria:**
- [ ] Red test: outside bats (marker absent) an exported `KARPATHY_CHECKPOINT_CMD` pointing at a counter script is not executed and the hook reads its checkpoint from `run-checkpoint.sh`; with the marker it is honoured.
- [ ] Hook stdout, stderr and state files byte-identical on the pass-19 matrix (the seam is not used by the live path).
- [ ] Spawn budget unchanged (196 / 9).
**Dependencies:** none.

> Sources: `.claude/hooks/quality/karpathy-surgical-diff-check.sh:38-62`; `.claude/scripts/lib/profile-lib.sh:57-67` (the seam pattern); Sprint 282 audit LOW-003 (DISS-C-007); Appendix D B3

### FR-6: Trajectory append writes only through a trusted path (bd-kdzc3)
**Priority:** Should Have
**Description:** Before `mkdir -p "$TRAJ_DIR"` and the `>>` append (`karpathy-surgical-diff-check.sh:214-217`) the hook refuses the append — silently, the warning line is still printed — when: `TRAJ_DIR` or any of its path components is a symlink (`realpath -m` of `TRAJ_DIR` differs from its literal path, or `-L` on the final component), any directory component below the checkout root — the trust root; the check is anchored at `realpath -m` of the root so only components below it are constrained — is not owned by the running uid or is group/other-writable (every component and the day file read by ONE `stat`), the per-day file exists and is not a regular file (symlink, FIFO, device, directory), is not owned by the running uid, is group/other-writable, or has more than one link; when `realpath -m` is unavailable (BSD) the append is refused. The state directory and task file keep today's symlink guards (out of this requirement's scope). The checks run only on the warn path (the append happens only when the threshold is exceeded), so the hot path's spawn budget is unchanged. The trust root is the checkout (operator-owned), as in FR-1.
**Acceptance Criteria:**
- [ ] Red tests: `TRAJ_DIR` replaced by a symlink, a symlinked parent component, a foreign-owned or group-writable directory, the day file as a symlink / FIFO / hard link to a victim → the warning path leaves every victim byte-identical and appends nothing; the normal append still works; a replacement between two hook runs is refused on the second; a group-writable day file, a foreign-owned or writable intermediate component, and an unavailable `realpath -m` (shim) are refused with the warning still printed; the warn path's own spawn count is asserted once.
- [ ] Spawn budget unchanged on the non-warn path.
**Dependencies:** none.

> Sources: `.claude/hooks/quality/karpathy-surgical-diff-check.sh:150-165, 205-220`; Sprint 281 audit LOW-003; Appendix D B5

### FR-7: The KF SessionStart surface has a volume bound (bd-4sikh)
**Priority:** Should Have
**Description:** `loa-kf-surface.sh` prints at most `KF_SURFACE_MAX_ROWS` (a documented constant, 40) rows. **Selection** picks the 40 entries by recurrence count descending, then id descending (ties by id; recurrence parsed as the leading integer of the field, 0 when absent); **display** keeps today's file order for the selected rows, so output with ≤ 40 entries is byte-identical to today's and output with more differs only by the elided rows plus one final line `  … and K more — see grimoires/loa/known-failures.md` (DEC-1159). The row cap implies a byte ceiling: each row carries an id, a recurrence integer and a symptom capped at 100 bytes, so the table is ≤ 40 × ~140 bytes + headings + the elision line ≤ 8 KiB; a worst-case-row fixture pins it.
**Acceptance Criteria:**
- [ ] Red test: a 100-entry fixture yields 40 rows in file order + the elision line (byte-exact expected output); a fixture with ≤ 40 entries yields today's exact output; the live file (65 entries) differs from the pre-change output only by the 25 elided rows and the one line (diff attached to the report).
- [ ] Selection determinism pinned (ties by id); worst-case rows (100-byte symptoms, 3-digit recurrence) stay under 8 KiB.
- [ ] Spawn budget (`kf-surface 36/2`) unchanged: the selection happens inside the existing awk program.
**Dependencies:** FR-8 (same awk program; land FR-8 first or together). **Rollback:** FR-7, FR-8 and FR-9 touch the same awk program; they revert together in reverse landing order.

> Sources: `.claude/hooks/loa-kf-surface.sh:88-140`; `grep -c '^## KF-' grimoires/loa/known-failures.md` = 65; Sprint 281 audit LOW-002; Appendix D M-FR7

### FR-8: The KF sanitiser matches the decisions filter's control class (bd-z6gxn)
**Priority:** Should Have
**Description:** `san()` in `loa-kf-surface.sh` and its twin `SAN_AWK` in `grimoire-index.sh` strip exactly the class the decisions jq `s` filter strips — `[[:cntrl:]\u0080-\u009f  ]` → space (`grimoire-index.sh:251`): in bytes, the UTF-8 pairs `\302[\200-\237]` (U+0080–U+009F) and the triples `\342\200[\250\251]` (U+2028, U+2029) become a space; C0 and DEL as today; `<` and `>` are NOT replaced in the KF twins (the jq filter's `‹ ›` replacement serves Markdown table cells, which the KF surface already escapes elsewhere — stated, with the drift guard pinning the chosen class). Bidi controls and zero-width characters are out of scope (the jq filter does not strip them either); mawk, busybox awk and `gawk --posix` produce identical output on the fixture set; the drift-guard test keeps the two programs identical.
**Acceptance Criteria:**
- [ ] Red test: fixture symptoms containing NEL (U+0085), U+009F, U+2028 and U+2029 yield single spaces in the hook's table and the index TSV; C0, DEL and the byte cap behave as today; the live file output byte-identical (no such bytes in it today — asserted by a grep in the report).
- [ ] Drift guard green; three-awk parity green; spawn budgets unchanged.
**Dependencies:** none.

> Sources: `.claude/hooks/loa-kf-surface.sh:97-104`; `.claude/scripts/grimoire-index.sh:251` (`def s`); Sprint 282 report A (observation); bead bd-z6gxn; Appendix D M-FR8

### FR-9: The BSD byte-cap contract is verified or documented (bd-aceil)
**Priority:** Could Have (bounded exit by DEC-1146 / DEC-1159)
**Description:** The KF awk programs' NUL regex (`/\000/`), octal classes and `LC_ALL=C` byte cap are verified under a BWK one-true-awk and BSD `cut` semantics; the contract — **the symptom cap is 100 bytes on every host, and it may end inside a multi-byte sequence (the surface is advisory text, never parsed as a value)** — is stated in the hook header and pinned by a fixture with a 3-byte UTF-8 symptom crossing the cap (exact bytes at the boundary). Form (a): a BWK awk (a prebuilt one first — the Debian/Ubuntu `original-awk` package, a `nawk` binary, or a container image — then a source build) and BSD `cut` produce identical output on the fixture set. Form (b), only after the prebuilt attempt is recorded as failed: the contract text and fixture land under the available awks, the BWK verification stays UNVERIFIED with the reason, bd-aceil closes with the contract landed, and a new linked bead for a macOS host is opened (G-1 counts this as closed-for-this-cycle).
**Acceptance Criteria:**
- [ ] Form (a): BWK awk, `gawk --posix`, mawk, busybox identical on the fixture set incl. NUL, `\001`, `\177`, C1 pairs and a multi-byte symptom at the cap; or form (b): the prebuilt attempt and its blocker recorded, the contract text landed, the macOS bead opened, a class-S row written.
- [ ] No change to Linux output in either form.
**Dependencies:** FR-7, FR-8 (the same programs).

> Sources: Sprint 281 audit MED-001 (DEC-1123); `grimoires/loa/a2a/sprint-282/reports/a.md` (BWK unobtainable from source: no yacc, upstream unreachable); Bridgebuilder #1309 R-001; DEC-1146, DEC-1159

### Sprint 3 — tests, guards and one refactor

### FR-10: `forbidden()` protects the descendants of a mapping-level floor key (bd-7utms)
**Priority:** Should Have
**Description:** In `profile-lib.sh` the floor predicate gains a descendant clause — `$k` starts with `<floor key without glob suffix>.` — at any depth, for profile keys and cached keys alike, so a key one or more levels below a floor entry that names a mapping is dropped with the existing WARN text; a sibling that merely shares a prefix (`safety.block_destructive_x`) is not matched.
**Acceptance Criteria:**
- [ ] Red test in `tests/unit/profile-floor.bats` (or `profile-lib.bats`): a fixture floor entry `safety.block_destructive` drops `safety.block_destructive.enabled` (child), `safety.block_destructive.rules.rm` (grandchild) and a cached key under it, with the WARN; `safety.block_destructive_x` is kept; existing glob and ancestor cases unchanged; the live floor list (`fence:*`, `gate:*`, `policy:*` tokens) produces identical output; the adversarial fixtures' intended differences are enumerated in the parity report.
**Dependencies:** none.

> Sources: `.claude/scripts/lib/profile-lib.sh:131`; `.claude/data/floor.yaml`; Sprint 282 audit LOW-002 (DISS-C-005); Appendix D M-FR10

### FR-11: `loa_knob` presence metadata cannot collide with a value (bd-y5fy4)
**Priority:** Should Have
**Description:** The internal result of the cache and memo reads in `loa_knob` carries presence separately from the rendered value (the SDD's kind token on the LAST line of the jq output, split with a newline guard so an empty present value stays empty and trailing newlines are stripped as today) so the strings `__LOA_PL_ABSENT__`, `__LOA_PL_MISS__` and `__LOA_PL_STALE__` are no longer sentinels a configured value can equal; the public contract (`loa_knob <path> <fallback>` prints the value or the fallback) and the 19 call sites in 10 files are unchanged.
**Acceptance Criteria:**
- [ ] Red tests in `profile-lib.bats`: a config value literally equal to each former sentinel round-trips through the warm path, the memo path and the live path; an empty present value and a value with trailing newlines round-trip as today; the warm-versus-live classification matrix stays green.
- [ ] Outputs byte-identical on the live config and the matrix for every caller except the sentinel-collision fixtures (enumerated); karpathy spawn budget unchanged.
**Dependencies:** FR-1 (same file; sequencing; shared rollback).

> Sources: `.claude/scripts/lib/profile-lib.sh:236-288`; `grep -rn loa_knob .claude --include=*.sh` = 19 sites; Sprint 282 review observation 3; Bridgebuilder #1309 round 2 R-002

### FR-12: The spawn-budget guard measures the grimoire-index cache hit (bd-5v1oa)
**Priority:** Should Have
**Description:** `perf-spawn-budget.bats` adds a second trace of the same decisions fixture after a first untraced run that is asserted to have written a valid cache (the cache file exists with the expected key line), with its own measured budget and reason, so the production hot path (a hit) is guarded as the miss is.
**Acceptance Criteria:**
- [ ] The new target traces a hit (the trace shows no `yq -o=json` parse of decisions.yaml and the cache file is unchanged afterwards) with a budget measured over three identical runs plus the file's headroom rule; a mutation that adds headroom + 1 spawns on the hit branch fails it deterministically (a one-off red run recorded in the report).
**Dependencies:** none.

> Sources: `tests/unit/perf-spawn-budget.bats:137-169`; Sprint 282 review observation 1; Appendix D M-FR12

### FR-13: CMP-55 observes the reap it exercises (bd-rq6gk)
**Priority:** Could Have (deferrable under schedule slip, DEC-1160)
**Description:** `adversarial-review-companion.bats` CMP-55 asserts that the reaper was attempted (an observable marker written by the wrapped `_adv_kill_tree`) so its stub hold can be shortened to the file's 240 s like the other reaped holds, and the sleeper margin is raised so a slow host cannot make the shortened hold flaky.
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

> Sources: `tests/unit/loa-decisions-surface.bats:124-140`; Sprint 281 review observation 3; Bridgebuilder #1309 round 1 R002

### FR-15: One lazily built provider dispatch mapping (bd-0h7kq)
**Priority:** Could Have (deferrable by DEC-1146 / DEC-1160)
**Description:** `providers/__init__.py` builds one lazily populated registry used by both `__getattr__` and the normal `_ADAPTER_TYPES` resolution, derives `cli_adapter_types` from a static auth table, and tests presence with name-in-`globals()` instead of truthiness; behaviour and import cost unchanged (the cheval `--help` and spawn budgets as today). Implemented only within the SDD's 60-line bound with every provider test green; otherwise deferred by a class-S row with a successor bead.
**Acceptance Criteria:**
- [ ] Existing provider tests green; `cheval --help` timing within the loop's measured band; a red test for the one observable change the refactor pins (the SDD names it) — or the deferral row.
**Dependencies:** none.

> Sources: `.claude/adapters/loa_cheval/providers/__init__.py:26-60`; Sprint 281 review observation; DEC-1146

### FR-16: Ship — one PR, Bridgebuilder, merge, record, archive; no release
**Priority:** Must Have
**Description:** After the third sprint's `COMPLETED`: secret scan on the final head (the assignment-pattern scan over the changed tracked files and a token / private-key grep over the added lines); PR from `feature/cycle-138-hardening-followups` whose body lists the three sprints, beads, DEC rows and each gate's verdict with its `reviewed_head`, and states that the prepared rc.10 candidate is not published; Bridgebuilder ≤ 2 rounds (`BRIDGEBUILDER_MODEL=codex-headless`, generated and planning files excluded) with the **degraded-exit procedure**: a round counts as degraded only for provider unavailability or timeout of a voice (envelope `verdict_quality` DEGRADED with the failed voice and its error recorded); the first degraded round is retried once after ten minutes; a second degraded round proceeds only when no blocking finding is open, with a class-S row (the DEC-1139 shape); exhausted rounds with a blocking finding open HALT; **merge gate (R-3):** every check run on the exact PR head has completed; the six required checks — `Template Protection`, `Validate Framework Files`, `Lint Markdown`, `Lint YAML`, `Shell Tests`, `Cross-Platform Compatibility` — are `success` taking the latest run per name (a rerun supersedes an earlier run of the same name; any non-success completed run of a required name that is the latest blocks); every other completed run is `success`, `skipped` or `neutral` (path-filtered workflows); the final sprint's two verdicts name the PR head (DEC-1161); admin merge; then `git diff --quiet <PR head> <merge commit>` (the merge commit's tree equals the PR head's tree); record branch via `record-branch.sh` (the known NOTES prose hit class accepted); main CI (`CI`, `BATS Tests`) green on the merge commit; `archive-cycle.sh` on a chore branch, housekeeping merge (both Prepare jobs skipped, zero artifacts); `JACKED_OUT`. The rc.10 candidate the pipeline prepares is left unpublished: publishing requires an explicit operator-only `--publish … --approve-sha256` from a clone, which this cycle never runs.
**Acceptance Criteria:**
- [ ] The merge gate predicate above holds on the exact head; the final sprint's verdicts name the PR head; earlier sprints' verdicts name their own heads with their docs-only tails listed.
- [ ] Record branch pushed; archive PR merged as housekeeping (both Prepare jobs skipped, zero artifacts); ledger cycle archived; beads closed with the merged sha; HALT protocol honoured if invoked.
- [ ] No tag created, no release published (`gh release list` and `git ls-remote --tags origin` unchanged); the publish-summary stage is not run.
**Dependencies:** FR-1 … FR-15 landed or deferred.

> Sources: cycle-137 § Ship S-1 … S-9 and its e2e.md part 2 (the scripts under `~/.cache/loa/cycle-137/ship/` are the recipe; `merge-pr.sh` is the gate); DEC-1139, DEC-1145, DEC-1160, DEC-1161; Appendix D M-ship

---

## Non-Functional Requirements

### Performance
Every change keeps its hot path's spawn budget at the current count (karpathy warm path 196 / 9; kf-surface 36 / 2; grimoire-index 167 / 15; implement-gate 127 / 5; notes-size-guard 26 / 3; compat-lib 15 / 0; stop-guard 78 / 2); where output changes by design (FR-3, FR-7, FR-8 fixtures, FR-10/FR-11 adversarial fixtures) the change is enumerated per fixture; everything else is byte-identical old-versus-new on the live inputs and the fixture matrices. Benchmark protocol for any number quoted: `hyperfine -N -i --warmup 3 --runs 10`, old and new mirrors in the same session, host load named (checked before a timing claim).

### Security
Trust boundaries are explicit and tested with foreign-owned, group-writable, symlinked, hard-linked, FIFO and replaced-between-calls fixtures; refusals fall back to today's behaviour (never a silent pass); the trust root is the operator-owned checkout; bodies and config values stay data to static programs (no `eval`, no `source` of data, no interpolated `bash -c`, nothing user-controlled on `execve` argv in the publish path); untrusted bodies sanitised at surfacing with the decisions filter's control class; the audit chain untouched; test seams honoured only under a bats marker (command seams) or with a WARN (read redirections).

### Reliability
Red-first tests for every behaviour change; `red-test-check.sh` per red commit; the covering suites and the full unit suite green on each sprint's head (only the three R-4 failures allowed, with their signatures; new skips only when named and host-conditional); rollback is one revert per bead (red and fix together), with shared-file pairs (FR-1/FR-11; FR-7/FR-8/FR-9) reverting together in reverse landing order.

### Compliance
System Zone writes under the bounded marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); class-S decision rows for every judgment call (`dec-batch`, summary ≤ 150 code points); CHANGELOG `[Unreleased]` lines for every behaviour-visible change: FR-1 (cache refusals and the `loa_profile` cache-state line), FR-2 (large release notes publish), FR-3 (chain summary wording and JSON object), FR-4 (fresh `.run/perf-cache` is 0700), FR-5 (seam ignored outside tests), FR-6 (trajectory append refused through untrusted paths), FR-7 (row cap), FR-8 (C1/U+2028/2029 stripped), FR-10 (floor descendants), FR-11 (sentinel removal); no version stamp changes.

### Authorization basis and refusal list
Operator instruction of 2026-10-29 (verbatim in the brief). Unattended implementation, gates, merge, record and archive are authorised; publishing is NOT (DEC-1145). Refuse: writing `main` outside the merge, force-pushing, deleting tags or branches, merging with a red or pending required check, creating a tag or release, touching credentials or the live push configuration in tests, changing `br` contract calls, quarantining a test, editing `.claude/` outside the authorised list below.

> Sources: brief § Constraints and § Non-goals; DEC-0824; DEC-1145; cycle-137 PRD § Authorization basis (the refusal list carried forward); `tests/unit/perf-spawn-budget.bats` budget lines

---

## User Experience

### Key User Flows
Edit → identical gate decisions and karpathy warnings, with the profile cache refused only where it should never have been trusted. `/loa` → the chain summary names absent or broken primitives. Session start → at most 40 KF rows in today's order plus one "and K more" line. Release → notes of any size under GitHub's limit publish.

### Interaction Patterns
New operator-visible texts: the chain-summary wording and per-primitive lines in the non-healthy case (FR-3), the KF elision line (FR-7), `loa_profile`'s cache-state line (FR-1). Everything else silent.

### Accessibility Requirements
Plain text; no colour-only signals (`agent-ergonomics-color-guard.bats` green).

> Sources: `.claude/settings.json` (hook wiring); `tests/unit/agent-ergonomics-color-guard.bats`

---

## Technical Considerations

### Architecture (for the SDD)
C-1 profile-lib trust predicate (inline, mirroring `_gi_trusted_dir` / `_gi_dec_write` with a drift guard — no new sourced library, DEC-1148); C-2 publisher file-borne bodies (`--rawfile`, the sprint-bug-283 temp-dir pattern); C-3 chain summary classification (string + JSON object + primitives list); C-4 umask-077 creators; C-5 karpathy seam gate + trajectory guards; C-6 KF hook: control class, volume bound, BSD contract (one awk program, three changes, one drift guard); C-7 profile-lib floor clause + presence metadata; C-8 test guards (spawn hit target, CMP-55, `_path_without`); C-9 providers registry; C-10 ship.

### System Zone authorization (explicit, cycle-level)
This PRD authorises writes under `.claude/scripts/lib/profile-lib.sh`, `.claude/scripts/post-merge-orchestrator.sh`, `.claude/scripts/loa-status.sh`, `.claude/hooks/safety/zone-write-guard.sh`, `.claude/hooks/quality/karpathy-surgical-diff-check.sh`, `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh` (the `SAN_AWK` twin only), `.claude/adapters/loa_cheval/providers/__init__.py` (FR-15 only), `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md{,.checksum}` — each under the bounded marker with manifests regenerated in the same commit. No new `.claude/scripts/lib/` file is authorised (the trust predicate is inline — DEC-1148); test fixtures live under `tests/`. Any other System Zone path needs a PRD amendment.

### Integrations
GitHub (PR, checks, merge) through `gh`; Bridgebuilder `codex-headless`; the post-merge pipeline runs on the merge and prepares a candidate that is not published.

### Dependencies
None new: jq ≥ 1.6 (`--rawfile`, `$ARGS` — already required by cycle-137's code), yq v4, python3, bats-core 1.13 as today; downstream mounts that pin an older jq are already outside the supported floor.

### Technical Constraints
Hooks must stay bash-3.2-safe where they already are (no associative arrays, no `${var,,}`); awk changes must run on mawk, busybox awk and `gawk --posix`; `SKILL.md` budgets untouched; NOTES.md under the size guard (rotate if needed).

> Sources: `.claude/scripts/grimoire-index.sh:263-331`; `grimoires/loa/a2a/bug-20261028-90f357/reviewer.md` (temp-dir pattern); DEC-0824, DEC-1148

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1, FR-2, FR-3, FR-16 (Must); FR-4 … FR-8, FR-10 … FR-12 (Should); FR-9, FR-13, FR-14, FR-15 (Could — with the bounded exits of DEC-1146 and the slip order of DEC-1160: FR-15, then FR-13, then FR-9).

### In Scope (Future Iterations)
Promotion `v2.0.0-rc.N → 2.0.0` (operator's call); a `/bug` for the ledger numbering defect (KF-065, bd-d6dr5); a macOS host run for FR-9 form (b)'s linked bead.

### Explicitly Out of Scope
- Publishing any release — Reason: DEC-1145; rc.9 is soaking and promotion is the operator's decision.
- New optimisation targets, Flatline/Bridgebuilder/adapter wire-contract changes, test quarantines — Reason: brief § Non-goals.
- The ledger-lib `_next_cycle_id` fix — Reason: a separate defect with its own red test (bd-d6dr5), outside the fifteen beads.
- Creation mode of `.run` itself — Reason: many creators; FR-4 covers `.run/perf-cache` only.

### Priority Matrix
| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1 profile-lib trust predicate | P0 | M | High (per-tool-call trust surface) |
| FR-2 publisher bodies off argv | P0 | S | High (release path) |
| FR-3 chain classification | P0 | S | Med (integrity view) |
| FR-4 umask-077 creators | P1 | S | Med |
| FR-5 / FR-6 karpathy seam + trajectory guards | P1 | S | Med |
| FR-7 / FR-8 KF volume bound + control class | P1 | S | Med |
| FR-9 BSD contract | P2 | M (tooling) | Low–Med |
| FR-10 / FR-11 floor clause + presence metadata | P1 | S/M | Med |
| FR-12 / FR-13 / FR-14 guards | P2 | S | Low–Med |
| FR-15 providers registry | P3 | M | Low |
| FR-16 ship | P0 | M | — |

> Sources: brief § Scope and § Non-goals; DEC-1145, DEC-1146, DEC-1160; KF-065 / bd-d6dr5

---

## Success Criteria

### Launch Criteria
- [ ] Three `COMPLETED` markers with `All good` + `APPROVED`, bound per DEC-1161 (sprint heads; the final sprint on the PR head with the whole-head parity gate).
- [ ] 15 beads closed or deferred-with-row-and-successor; `red-test-check.sh` VERIFIED per red commit; full `tests/unit` green modulo the three R-4 failures; spawn budgets at their current counts.
- [ ] PR merged on the exact green head; record branch; archive merged as housekeeping; `JACKED_OUT`; no tag, no release.

### Post-Launch Success (30 days)
- [ ] The maintainer finds no issue labelled `kf` or `regression` that names the profile cache refusal, the chain summary wording or the KF elision (owner: the maintainer; channel: the repository's issues and the KF ledger).

### Long-term Success (90 days)
- [ ] The next release (rc.10 or 2.0.0) publishes end to end with large notes through the file-borne path, recorded in its publish summary.

> Sources: cycle-137 PRD § Success Criteria (carried pattern); G-1 … G-4 above; `tests/unit/perf-spawn-budget.bats`; DEC-1161

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| FR-1's predicate refuses the cache on a common downstream layout (a 775 `.run` from an older zone-write-guard) and silently slows every edit | Med | Med | the refusal falls back to the live read (identical output); `loa_profile` names the reason; FR-4 fixes the creator; the maintainer's fix is one `chmod go-w .run` (documented in the CHANGELOG line) |
| FR-3 / FR-7 wording changes break a consumer that parses `loa-status --json` or the KF table | Low | Med | `audit_chain_summary` kept; fields added never removed; KF rows keep file order; the elision line is additive |
| BWK awk still unobtainable (FR-9) | Med | Low | prebuilt attempt first; form (b) exit with a linked macOS bead (DEC-1159) |
| Bridgebuilder degraded again (KF-037 class) | Low (host unloaded) | Low | the FR-16 degraded-exit procedure; retry once after ten minutes first |
| Dissent budget exhausted by review rounds | Med | Low | round 3 lead-only; the audit keeps run 3 (DEC-1134 pattern); after that the halt protocol (DEC-1160) |
| Three sprints' wall time (gates ≈ 2 h each) | — | Low | sprint boundaries are HALT-safe; the halt protocol ships completed sprints |

### Assumptions
- `[ASSUMPTION decision]` (DEC-1144) grounding on REPO-MAP and finding anchors suffices — if wrong, an FR cites a stale line and the SDD's own code reads correct it.
- `[ASSUMPTION decision]` (DEC-1145) no release this cycle — if wrong, the operator asks and the cycle-137 publish recipe applies to the prepared candidate.
- `[ASSUMPTION decision]` (DEC-1146, DEC-1159) bd-aceil and bd-0h7kq may end as documented exits — if wrong, the operator reopens them with a host or a reason.
- `[ASSUMPTION decision]` (DEC-1157) refusing a writable `.run` from the hook path is preferable to tightening it — if wrong, a downstream with a shared `.run` loses the profile cache until it is fixed by hand.

### Dependencies on External Factors
GitHub Actions availability for the required checks; the host staying unloaded for the companion voice; a prebuilt BWK awk being installable for FR-9 form (a).

> Sources: KF-037 (companion timeouts), DEC-1134 (third dissent run = audit), DEC-1123 (BWK unobtainable), DEC-1144 … DEC-1146, DEC-1157 … DEC-1161

---

## Timeline & Milestones

| Milestone | Target |
|---|---|
| PRD 1.1 (this revision) | T+1 h |
| SDD 1.1, sprint plan, beads created | T+3 h |
| Sprint 1 implemented, reviewed, audited | T+8 h |
| Sprint 2 | T+13 h |
| Sprint 3 (incl. the whole-head parity gate) | T+17 h |
| Ship (PR, BB, merge, record, archive) | T+20 h |

(T = the 1.0 timestamp; unattended, one calendar day; slip order FR-15, FR-13, FR-9 by deferral row — DEC-1160; past T+20 h the halt protocol applies.)

> Sources: cycle-137 sprint plan § Time budget (the gate durations observed on 2026-10-28: review + audit ≈ 2 h per sprint, Shell Tests ≈ 75 min); DEC-1160

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
| FR-9 | bd-aceil | Sprint 281 audit MED-001 / BB #1309 round 2 R-001 |
| FR-10 | bd-7utms | Sprint 282 audit LOW-002 |
| FR-11 | bd-y5fy4 | Sprint 282 review obs 3 / BB #1309 round 2 R-002 |
| FR-12 | bd-5v1oa | Sprint 282 review obs 1 |
| FR-13 | bd-rq6gk | Sprint 282 Task 2.5 |
| FR-14 | bd-3qed8 | Sprint 281 review obs 3 / BB #1309 round 1 R002 |
| FR-15 | bd-0h7kq | Sprint 281 review obs |

### B. Decision rows written for this PRD
1.0: DEC-1144 (grounding), DEC-1145 (scope and no release), DEC-1146 (bounded exits for bd-aceil and bd-0h7kq), DEC-1147 (ledger id correction, KF-065, bd-d6dr5). 1.1: DEC-1157 (refuse, never chmod, cache-file predicate), DEC-1158 (karpathy seam ignored in production), DEC-1159 (KF selection vs display, byte ceiling, prebuilt BWK first), DEC-1160 (halt protocol and slip order), DEC-1161 (verdict binding) — all `proposed`, class S.

### C. Grounding note
No `/ride` run: the reality set is from 2026-05-04; the anchors above were read from the working tree at fe52be893 while writing this PRD, and `grimoires/loa/REPO-MAP.md` is regenerated at every System Zone commit. No conflict between a bead's text and the current code was found; each FR cites the code as read.

### D. Flatline PRD review dispositions
Review: `flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json` on PRD 1.0 (commit 34e442de9): two voices (claude-headless, gpt-5.5), 5 blockers, 48 medium items (22 Opus-scored 520–880, 26 GPT-scored); cross-scoring degraded (`verdict_quality.status DEGRADED`, "cross-scoring was incomplete or rejected", confidence floor low) — the lead read every item; envelope `grimoires/loa/a2a/flatline/cycle-138-prd-review.json`. Every blocker is adopted; medium items are adopted unless listed under "declined".

| # | Finding | Disposition in 1.1 |
|---|---|---|
| B1 (+ M 820, gpt cache-file, gpt hard-link) | FR-1 checked the directory but not the cache file's ownership, mode or links; existing contents trusted after tightening | FR-1 predicate (b): file uid-owned, no g/o write, one link, regular non-symlink; replacement by rename never truncates; hard-link and planted-file fixtures; after a re-trusted directory the cache is rebuilt, not read |
| B2 (+ M 780 redirected cache, gpt ancestors) | `.run`'s ancestors and replacement between check and use undefined | FR-1: trust root = the checkout (operator-owned), stated threat model; redirected `LOA_PROFILE_CACHE_FILE` directories must satisfy the predicate with no symlinked component (`realpath`); directory-replacement fixture between two calls |
| B3 (+ M 850, gpt seam threat model) | FR-5 allowed WARN-and-honour; markers are ambient | FR-5: ignored in production, marker-gated test seam only, threat model stated; profile seam's WARN rationale stated (DEC-1158) |
| B4 (+ M 740 TOCTOU) | descriptor opening is not atomic with the shell predicates; `mv` fallback gap | FR-1: the predicate establishes that the directory is not adversary-mutable (the race needs the write access just refused), stated in code; FIFO/special files refused by `-f`; the non-GNU `mv` fallback exercised with a shim |
| B5 (+ M 720, gpt FR-6 types/components) | trajectory guard too narrow | FR-6: every path component, directory ownership and mode, file type (regular only), ownership, link count; replacement fixture |
| M 880 | three sprint heads cannot all equal the merged code | G-3 / FR-16: per-sprint binding + final-sprint binding to the PR head with the whole-head parity gate (DEC-1161) |
| M 520, gpt byte bound | row limit without a byte ceiling | FR-7: derived ≤ 8 KiB with worst-case-row fixture |
| M 620, gpt prebuilt BWK | FR-9 form (a) scope; truncation inside a UTF-8 sequence | FR-9: BSD `cut` named; the cap may split a sequence (advisory text) — stated; exact bytes pinned; prebuilt attempt required before form (b) (DEC-1159) |
| M 700 FR-10 | depth, siblings, cached values | FR-10: any depth, grandchild, sibling-prefix negative, cached key |
| M 720 FR-12 | warm fixture validity; mutation determinism | FR-12: cache asserted valid before the trace; mutation adds headroom + 1 |
| M 740 FR-13 slip; M 640 FR-9 bead policy; gpt halt protocol | completion vs slip; form (b) bead; unattended end | § Constraints halt protocol and slip order (DEC-1160); FR-9 form (b) closes bd-aceil with a linked macOS bead; KPI counts deferred-with-row as closed |
| M 760 lib extraction; gpt System Zone reconciliation | optional `cache-trust-lib.sh` vs the authorization list | inline predicate only (DEC-1148); the list says no new lib |
| M 780 required checks; M 760 tree equivalence; M 700 KF-034 names; gpt FR-16 names + publish mechanism | merge predicate under-specified | FR-16: the six names, latest-run-per-name rule, `git diff --quiet <head> <merge>`, docs-only tails listed; R-4 names the three tests and their signature rule; publishing requires an explicit operator-only `--publish` from a clone |
| M 740 BB degraded exit | procedure undefined | FR-16 degraded-exit procedure (qualifying classes, evidence, retry, decision row) |
| M 780 parity exceptions | FR-8/FR-10/FR-11 intended differences | § Constraints and G-2 enumerate them per fixture |
| M 660 publisher temp storage; M 700 bash -x evidence; gpt FR-2 payload path + fixtures | failure paths, evidence, realism | FR-2: checked creation/write, private perms, cleanup on every return without clobbering a RETURN trap; stub-recorded argv assertions; multi-byte ≤ 125 000 chars > 131 072 bytes and a comment ≤ 65 536 chars; `gh api --input -` named; SDD enumerates every argv body site |
| M 800 FR-3 table; gpt primitives list + L5/L7 | classification and naming | FR-3: four states incl. `n/a` for L5/L7 (counted valid), unreadable/malformed/verifier-failure → broken, sum invariant, per-primitive lines and JSON list |
| M 680, gpt FR-7 order | selection vs display | FR-7: select by recurrence/id, display in file order (DEC-1159) |
| gpt FR-4 dependency note and `.run` creation | wrong note; `.run` creator | FR-4 note corrected; `.run` itself out of scope (§ Scope) |
| gpt FR-8 exact class | match the jq `s` filter fully | FR-8: `[[:cntrl:]\u0080-\u009f  ]` in bytes; `<>` not replaced (stated); bidi/zero-width out of scope like the jq filter |
| gpt .run mutation from a read path | may FR-1 chmod `.run`? | refused instead (DEC-1157) |
| gpt traceability refs; gpt budget placeholder | R-002 twice; 'budget B' | FR-11 "round 2 R-002", FR-14 "round 1 R002"; KPI uses 196 / 9 |
| gpt CHANGELOG list; gpt Appendix C statement; gpt jq version; gpt rollback order; gpt 30-day criterion; gpt observability; gpt seam consistency | documentation completeness | § Compliance lists every FR; Appendix C states no conflicts; Dependencies note jq ≥ 1.6; shared-file rollback order in FR-1/FR-7 and § Reliability; 30-day criterion names channel and owner; FR-1 `loa_profile` cache-state line; FR-5 states the seam rule for both |
| gpt FR-1 ownership fixture vs `[[ -O ]]` | shim-ability | FR-1 AC: ownership from the stat row (shimmable), as the SDD specifies |
| **Declined** — M 700 (M-FR12 variant asking for a knob-driven headroom) | — | headroom stays the file's rule (`max(mt/10, 3)`), unchanged this cycle: a knob is a new config key (§ Constraints) |

> Sources: beads bd-j34zb … bd-qyvju (`br show`); `grimoires/loa/decisions.yaml` DEC-1144 … DEC-1147, DEC-1157 … DEC-1161; `grimoires/loa/known-failures.md` KF-065; `grimoires/loa/a2a/flatline/cycle-138-prd-review.json`

### E. Flatline SDD review carried back (1.2)

The SDD's Flatline review (SDD 1.2 § 11.F: 6 blockers, 37 items; two voices, cross-scoring degraded — KF-041 recurrence 13) changed five requirements, all reflected above and in SDD 1.2 § 11.D (DEC-1165 … DEC-1170):

| SDD finding | Requirement changed | Change |
|---|---|---|
| B1/B4/B6 — the body-file helper's RETURN trap deletes the file before use | FR-2 | process substitution replaces the temp file; the failure-path AC becomes a structural assertion plus a jq-failure case |
| B2/B3 — tightening references left in the design; trust sampled once | FR-1, FR-4 | trust lifetime stated; absent `.run` created by the writer; repair owner named (grimoire-index); 775 row |
| B5 — intermediate components unchecked | FR-6 | anchored realpath, one stat over every component + the day file, writable file refused, no `realpath -m` → refuse |
| M5/M20/M25 — verify-chains contract; `not_applicable` | FR-3 | JSON object gains `not_applicable`; contract fixtures |
| M8/M30/M37 — empty value collapses to the token; glob entries widened | FR-11, FR-10 | kind token on the last line with a newline guard; descendant clause only for non-glob floor keys |

> Sources: grimoires/loa/sdd.md 1.2 § 11.F; `~/.cache/loa/cycle-138/logs/flatline-sdd.json`
