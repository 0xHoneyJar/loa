# Sprint Plan: Cycle-123 — Bug Burndown

> **Cycle**: `cycle-123-bug-burndown` (NEW — branch from `main` at v1.202.1 (post PRs #1200/#1167/#1153/#1109/#1228; the transient v2.0.0 tag from #1109's `fix(agy)!:` breaking marker was deleted and re-cut as v1.202.0 by maintainer decision 2026-07-30). NOTE: the ledger's `active_cycle` is `cycle-122-mechanical-floor-extensions` and cycles 121 AND 122 (plus `cycle-bug-20260718-i1227-cf7ca4`) are all still `status=active` with no `archived_at` because issue #1234 (Task 1.1) has never successfully archived a cycle. `/run sprint-plan` MUST reconcile the ledger before registering this cycle — do not trust `next_sprint_number` blindly.)
> **Sprints**: 4 (local sprint-1..4; global **235-238**, continuing from cycle-122's 232-234)
> **Ground truth**: 2026-07-30 issue triage. The triage workflow verified **61 open issues**; the 15 tasks below are the `/bug`-eligible subset — every one carries an OBSERVED failure, regression, or reproduced defect, and every one was re-verified as `still_reproduces: true` against `main` at v1.202.x (12 by live/sandbox execution, 3 by code reading with an explicitly stated non-execution caveat and a hand-substituted BSD-semantics repro). Non-bug clusters from the same triage are enumerated in **Out of scope** and are NOT in this cycle.
> **Theme**: Burn down the verified live defects, nothing else. Four lanes: release-pipeline correctness (A), cross-platform portability (B), silent-success / fail-open surfaces (C), authorization and tripwire honesty (D).
> **Beads policy**: Beads do NOT yet exist for this cycle. Create them at `/run sprint-plan` preflight — one bead per Task N.M below, label `bug-burndown`, tags `sprint:<global>` + `cycle-123-bug-burndown`, plus the four spin-off beads named in the Blocked & Split Items table. Run `br sync --flush-only` FIRST; per KF-005 discipline, if beads repair exceeds 5 minutes, STOP and use the markdown fallback. NEVER `--rebuild`/`--import-only` while ids are DB-only (KF-022).
> **Routing**: `/bug` per task (each cites an observed failure — see Ground rules), executed through `/run sprint-N` → `/review-sprint` → `/audit-sprint` per sprint. Every task below touches `.claude/` (System Zone) except Task 4.2's `tools/` half: writes land **inside `/implement`//`bug` under one cycle-level zone authorization** (`.run/zone-guard-authorization.json`, bounded marker, deleted at run end) per `.claude/rules/zone-system.md`.
> **AC gate**: the validator-gated acceptance criteria are the per-task `**Acceptance Criteria:**` bullets. Each must be reproduced VERBATIM in the sprint report under `## AC Verification` with its own `- Evidence: <file>:<line>` line (`.claude/scripts/validate-ac-verification.sh`). The `### Sprint Exit Gate` bullets are sprint-level suite runs, not per-AC rows.
> **PR review**: maintainer @deep-name (CODEOWNERS).

---

## Executive Summary

Fifteen defects with observed failures, grouped so that each sprint shares one substrate and one test idiom. The highest-value work is Sprint 1: the post-merge ledger archival is broken four independent ways and the broken path was exercised twice in production on 2026-07-30 (runs 30503075975 and 30506809255 both logged `[LEDGER] Archived cycle ` with a blank id), which is why this repo's own ledger cannot mark a shipped cycle archived — and why Task 1.4's staleness signal would be inert until Task 1.1 lands.

- **Sprint 1** (P0, global 235) — release pipeline: ledger archival rewritten (4 defects, all four reproduced); Bridgebuilder `--pr` selection ordered before batch truncation; semver bootstrap for greenfield repos; worktree fossil-status detection.
- **Sprint 2** (P1, global 236) — portability: two GNU-only regex/flag classes (`\s` in a sed expression, `realpath -m`) that break validation on macOS; BSD `date -jf` parsing UTC as local; the submodule-mount abort that ships partial installs.
- **Sprint 3** (P1, global 237) — silent success: bridge orchestrator jacking out with zero work; bare-relative hook commands that fail open in nested worktrees; cwd-anchored L3 contract scripts; DEGRADED triage state invisible at READY_FOR_HITL; a test helper that discards its injected sanitizer.
- **Sprint 4** (P2, global 238) — authorization and tripwire honesty: audit-envelope keydir downgrade on a VERIFIED trust store plus never-enforced revocations; 8 yq swallow sites whose proposed tripwire is provably vacuous.

**Expected outcome**: 15 issues closed with a failing-repro regression test each; 4 spin-off beads filed for the deliberately-excluded scope; 0 feature work.

## Ground rules

These are cycle-level constraints, not suggestions. An audit finding against any of them is a sprint failure.

1. **Failing-repro test FIRST** (Karpathy #4). Every task writes or extends its named regression test BEFORE the fix, and records the pre-fix failure (exit code + message) in the sprint report. A task whose test passes on unmodified `main` has not reproduced the defect and is not done — this is exactly how all four #1234 defects and the #1206 ordering bug shipped past green suites (degenerate fixtures).
2. **Smallest correct diff** (Karpathy #2). Implement the `fix_shape` as scoped: no new scripts, no new helpers, no new config surfaces, no new state fields, no abstraction layers. Where a task's fix shape explicitly rejects an alternative (e.g. #1197 rejects `get_canonical_path` because it never returns non-zero), that rejection is binding.
3. **No adjacent refactors** (Karpathy #3). Sibling instances of the same class WITHOUT an observed failure stay out: #1216 does not touch the `\s` sites in `validate-change-plan.sh` / `butterfreezone-validate.sh` / `feature-gates.sh` / `loa-learnings-index.sh` / `post-pr-e2e.sh`; #1197 does not add `tools/check-no-raw-realpath-m.sh`. Both become lint beads (see Blocked & Split Items).
4. **`/bug` eligibility is per-task, not per-cycle.** Each task states its observed failure. Where a task's remedy is net-new detection logic rather than a corrected line (#1233), the lane check is called out explicitly and needs maintainer confirmation before autonomous implementation.
5. **Dual-artifact discipline.** Compiled twins and copy-set files regenerate in the SAME commit as their source: #1206 → `dist/core/template.js` + `dist/.build-manifest.json` (BB Dist Drift Gate); #1172 → `.claude/settings.json` AND `.claude/hooks/settings.hooks.json` (KF-021 drift class); #1211 → bash and Python halves (R15 behavior identity).
6. **Portability is shim-tested, not host-tested.** `tests/bats-tests.yml` is ubuntu-only. Sprint 2 proves BSD semantics with PATH shims plus a mandatory shim-faithfulness positive control (the shim must reproduce the defect pre-fix, or the test proves nothing). Adding a macOS CI lane is out of scope.
7. **Sequencing is load-bearing.** Task 1.1 (#1234) lands before Task 1.4 (#1233): #1233's staleness signal is "cycle archived in origin/main's ledger", which #1234 currently prevents from ever being written.

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 (global 235) | Release pipeline | Ledger archival correct (4 defects); `--pr` selection before truncation; greenfield semver bootstrap; worktree fossil-status | None (internal: T1.1 before T1.4) |
| 2 (global 236) | Portability | GNU-only `\s` and `realpath -m` removed; BSD `date -u` sweep; submodule mount no longer ships partial installs | None (parallel-safe with 1) |
| 3 (global 237) | Silent success | Bridge zero-work HALT; hook commands anchored to repo root; L3 contract scripts anchored; DEGRADED surfaced; sanitizer injection honored | None (parallel-safe with 1-2) |
| 4 (global 238) | Authorization + tripwire honesty | Keydir downgrade killed on VERIFIED store; revocations enforced; 8 yq swallow sites routed + non-vacuous tripwire | Sprints 1-3 (E2E battery covers all) |

---

## Sprint 1: Release Pipeline — the merge path that silently does nothing

**Duration:** ~1.5 days. **Zone:** System. **Basis:** issues #1234, #1206, #1235, #1233 — all four reproduced; #1234's broken path exercised twice in production on 2026-07-30.

**Issues closed by this sprint:** #1234, #1206, #1235, #1233

### Sprint Goal
The post-merge release path does what its logs claim: a shipped cycle is actually archived with a non-blank commit subject, an explicit `--pr N` is never eaten by a batch cap, a greenfield repo can reach its first tag, and a worktree parked on a shipped cycle stops recommending `/deploy-production` forever.

### Deliverables
- [x] **D1.1** — `archive_cycle_in_ledger()` body rewritten (`.claude/scripts/post-merge-orchestrator.sh:1224-1291`): pointer-first cycle resolution, resolved id passed out of the flock subshell via a result temp file, commit gated on the non-empty id instead of `flock_exit`, `jq -a` on the rewrite, `objects` guard in the #674 completeness gate with the `|| echo "0"` swallow dropped, and the top-level `active_cycle` pointer nulled in the same rewrite
- [x] **D1.2** — `resolveItems()` selects before truncating (`.claude/skills/bridgebuilder-review/resources/core/template.ts:117-146`) and throws a named not-found error after the repos loop; compiled twin + build manifest regenerated in the same commit
- [x] **D1.3** — `semver-bump.sh` auto-mode terminal `else` emits a bootstrap JSON (`{current: "0.0.0", next: LOA_INITIAL_VERSION|0.1.0, bump: "initial", commits: []}`, exit 0) instead of `exit 2`; explicit `tag)`/`changelog)` arms unchanged; `--help` exit-code text updated
- [x] **D1.4** — `_is_stale_worktree()` added to `workflow-state.sh` (linked-worktree check + local `active_cycle` + `git show origin/main:<ledger-rel-path>` status probe, matched by cycle id not SHA), called BEFORE the cache lookup and bypassing it when stale; `stale`/`stale_cycle` in the JSON emit; `--no-stale-check` escape hatch
- [x] **D1.5** — four regression suites written test-first, with pre-fix failure recorded per Ground rule 1

### Sprint Exit Gate
- [ ] `bats tests/unit/post-merge-archive-gate.bats tests/unit/semver-bump.bats tests/unit/bug-1233-worktree-staleness.bats` green
- [ ] `cd .claude/skills/bridgebuilder-review && npm test` green; `tools/check-bb-dist-fresh.sh --check` exits 0
- [ ] Four issues closed with the reproducing test cited in each closing comment

### Technical Tasks

#### Task 1.1 — Rewrite `archive_cycle_in_ledger()` (#1234, four defects) → **[G-1]** ⇐ none

**Issue:** #1234 · **Risk:** medium · **Effort:** M · **Files:** `.claude/scripts/post-merge-orchestrator.sh`, `tests/unit/post-merge-archive-gate.bats`
**Observed failure:** post-merge runs 30503075975 (PR #1238, v1.199.0) and 30506809255 (PR #1239, v1.200.0) both logged `[LEDGER] Archived cycle ` with a blank id; cycle-121 and cycle-122 are still `status=active` with no `archived_at` on main despite both having shipped.

- [ ] Extend `_write_ledger_with_sprints` coverage FIRST with `_write_ledger_multi_active`, `_write_ledger_legacy_sprints`, `_write_ledger_ascii_escaped`; assert the COMMIT (subject text + `git log` count), not just cycle status — the existing 5 tests all pass on the broken code because they never inspect the commit
- [ ] D1 — resolve from `.active_cycle`; fall back to `first(.cycles[] | select(.status=="active") | (.cycle_id // .id)) // empty` ONLY when the key is absent; empty → log + `return 0`
- [ ] D2 — keep resolution inside the flock (documented race intent preserved), write the resolved id to a result temp file, read it in the parent, gate the parent's echo AND commit on that non-empty id
- [ ] D3 — add `-a` to the whole-ledger `jq` rewrite at :1262
- [ ] D4 — `objects` guard in the gate filter; drop the `|| echo "0"` swallow so a real jq failure is visible
- [ ] Null the top-level `active_cycle` pointer in the same jq rewrite that flips status, only when the field exists

**Acceptance Criteria:**
- [ ] Archival resolves the cycle from the ledger's top-level `active_cycle` pointer, not from a `status == "active"` scan.
- [ ] The archive commit subject is exactly `chore(ledger): archive <cycle-id> after merge` with a non-empty cycle id.
- [ ] Stdout never contains `Archived cycle ` immediately followed by end-of-line.
- [ ] With `active_cycle: null` and unrelated staged churn in the index, the function creates ZERO commits.
- [ ] With two or more `status == "active"` entries plus a pointer, only the pointed-to cycle changes and every other `active` entry is byte-unchanged.
- [ ] The archived cycle gets `status: archived`, an `archived_at` value, and a nulled top-level `active_cycle`.
- [ ] Every `\uXXXX` escape present in a `jq -a` serialized ledger before archival is still present after.
- [ ] With `sprints` as an array of plain strings, stderr contains no `Cannot index string with string`.
- [ ] A genuine jq failure in the completeness gate is reported, not swallowed as 0 incomplete sprints.

**Regression test:** `tests/unit/post-merge-archive-gate.bats` (extend, do not replace)

#### Task 1.2 — Select `--pr` before applying `max_prs` (#1206) → **[G-1]** ⇐ none

**Issue:** #1206 · **Risk:** low · **Effort:** S · **Files:** `.claude/skills/bridgebuilder-review/resources/core/template.ts`, `dist/core/template.js`, `dist/.build-manifest.json`, `resources/__tests__/template.test.ts`
**Observed failure:** an explicit `--pr N` outside the first `maxPrs` entries is truncated before the filter sees it; the run exits 0 with `reviewed=0 skipped=0 errors=0` — a success-shaped zero-item run.

- [ ] Add the three failing cases to the existing `describe("resolveItems")` block first, reusing the 3-PR provider shape from the `respects maxPrs config` test
- [ ] Replace the loop bound: filter on `targetPr` when set, else `slice(0, maxPrs)`; delete the in-loop `continue` guard
- [ ] After the repos loop (not per-repo), throw a named error when `targetPr` is set and `items.length === 0`
- [ ] `npm run build` in `.claude/skills/bridgebuilder-review`; commit `dist/` + `.build-manifest.json` in the same commit

**Acceptance Criteria:**
- [ ] With `maxPrs: 2` and PRs [1,2,3], `resolveItems()` and `targetPr: 3` returns exactly one item whose `pr.number === 3`.
- [ ] With `targetPr` unset, `maxPrs: 2` and PRs [1,2,3], `resolveItems()` still returns exactly 2 items.
- [ ] With `targetPr: 99` and PRs [1,2,3], `resolveItems()` rejects with an Error whose message contains `99`.
- [ ] A `targetPr` miss never resolves to a zero-length array.
- [ ] `tools/check-bb-dist-fresh.sh --check` exits 0 on the resulting tree.

**Regression test:** `.claude/skills/bridgebuilder-review/resources/__tests__/template.test.ts`

#### Task 1.3 — Bootstrap the first version in `semver-bump.sh` (#1235) → **[G-1]** ⇐ none

**Issue:** #1235 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/semver-bump.sh`, `tests/unit/semver-bump.bats`
**Observed failure:** on a repo with no tags and no CHANGELOG, auto mode exits 2; `post-merge.yml`'s Compute semver step swallows it (`|| echo '{}'`) → empty `NEXT` → `skip=true` → tag, CHANGELOG, release and GT refresh skipped on every merge, forever, while the workflow reports green. The operator workaround is closed too: seeding `## [0.1.0]` hits `ERROR: CHANGELOG version v0.1.0 has no matching tag`.
**Recorded decision:** initial version is `0.1.0` (SemVer §4 initial-development default) with a `LOA_INITIAL_VERSION` env override. A `.loa.config.yaml` `initial_version` key is REJECTED for this cycle — `semver-bump.sh` reads no config today and adding a yq path plus a schema entry is scope increase, not the observed failure.

- [ ] FLIP the existing asserted contract at `tests/unit/semver-bump.bats:138-145` (`semver-bump: errors when no version source found`) — it encodes this bug as intended behavior; it must assert exit 0 plus the bootstrap fields, not be worked around
- [ ] Replace the auto-arm terminal `else` (`:333-335`) with the bootstrap `jq -n` emit + `exit 0`; leave the `tag)` and `changelog)` arms at exit 2
- [ ] Update the exit-code text in `--help` (`:289`)
- [ ] Add the AC-2 and AC-3 cases using the file's existing `make_commit`/`make_tag` helpers

**Acceptance Criteria:**
- [ ] In a repo with zero tags and no CHANGELOG.md, auto mode exits 0 and emits `.next == "0.1.0"` with `.bump == "initial"`.
- [ ] In that same repo, `semver-bump.sh --from-tag` still exits 2.
- [ ] In that same repo, `semver-bump.sh --from-changelog` still exits 2.
- [ ] `LOA_INITIAL_VERSION=1.0.0` makes the bootstrap emit `.next == "1.0.0"`.
- [ ] Once a `v0.1.0` tag exists, auto mode reports `.current == "0.1.0"` and `.bump` is never `initial` again.
- [ ] The post-merge Compute-semver emulation yields a non-empty `NEXT` on a greenfield repo, so the Create-tag step is not skipped.

**Regression test:** `tests/unit/semver-bump.bats` (one existing assertion FLIPPED, not deleted)

#### Task 1.4 — Detect a fossil worktree in `workflow-state.sh` (#1233) → **[G-1]** ⇐ Task 1.1

**Issue:** #1233 · **Risk:** medium · **Effort:** M · **Files:** `.claude/scripts/workflow-state.sh`, `tests/unit/bug-1233-worktree-staleness.bats`
**Observed failure:** reproduced 3x — a worktree parked on a branch whose cycle merged, archived and tagged keeps reporting `state: complete` and suggesting `/deploy-production` on every new session; the local-file-only cache key means origin/main advancing never invalidates the fossil verdict.
**Lane check (needs maintainer confirmation before autonomous implementation):** the failure is observed and reproduced, but the remedy is net-new detection logic rather than a corrected line. If the maintainer routes this through `/plan` instead, drop the task from the sprint and keep the other three.

- [ ] New file `tests/unit/bug-1233-worktree-staleness.bats` FIRST, following the `post-merge-archive-gate.bats` setup pattern (throwaway repo under `BATS_TMPDIR` with `PROJECT_ROOT` pointed at it — the in-repo `.loa-test-*` pattern will NOT work, a linked worktree is required); clone the fixture so `origin/main` resolves, then `git worktree add`
- [ ] Add `_is_stale_worktree()` (~12 lines, pure git + jq): non-stale unless `--git-dir` differs from `--git-common-dir`; read local `.active_cycle`; probe `git show origin/main:<ledger-rel-path>` for that cycle's status; `archived` → stale
- [ ] Derive the ledger's repo-relative path from `get_ledger_path()` — never hard-code `grimoires/loa/ledger.json` (breaks `LOA_GRIMOIRE_DIR`)
- [ ] Call it BEFORE the cache lookup and bypass the cache when stale; override `suggested_command` and prefix `description`; add `stale` + `stale_cycle` to the JSON emit; add `--no-stale-check` to the arg loop

**Acceptance Criteria:**
- [ ] In a linked worktree whose cycle is `archived` in origin/main's ledger, `workflow-state.sh --json` emits `.stale == true`.
- [ ] That same run's `.suggested_command` matches `git worktree remove` and is never `/deploy-production`.
- [ ] In the primary checkout with the same fixture, the JSON is unchanged apart from an added `"stale": false` field.
- [ ] With `--no-stale-check` in a stale worktree, output is byte-identical to pre-fix behavior.
- [ ] With no `origin/main` ref present, the probe exits 0 with `.stale == false` and empty stderr.
- [ ] Two consecutive `--json` runs in a stale worktree both report `.stale == true`.

**Regression test:** `tests/unit/bug-1233-worktree-staleness.bats` (new)

### Dependencies
- T1.4 strictly after T1.1 (the staleness signal is unwritable until archival works). T1.1-T1.3 are mutually independent.

### Risks & Mitigation
- **T1.1's fallback path stays hazardous after the fix** → this repo carries 54 stale `active` entries and 46 legacy string-sprint entries; a data-hygiene bead reconciles them separately and is NOT bundled into this diff
- **T1.2 lands without regenerating dist** → `.github/workflows/check-bb-dist-fresh.yml` fails the PR; the dist regeneration is an acceptance criterion, not a step
- **T1.3 changes an asserted test contract** → the flip is declared in the task body and in the PR description; the other exit-2 assertions (`:670`, `:687`) use `--from-tag` and are unaffected
- **T1.4 passes unit tests while inert in production** → mitigated by the T1.1 ordering; verify on this repo's real ledger after T1.1 archives cycle-122

### Success Metrics
- Post-merge orchestrator archives a real cycle with a non-blank commit subject; `--pr N` honored at any batch size; greenfield repo reaches `v0.1.0`; fossil worktree self-identifies

### Security Considerations
- T1.1 removes a silent no-op commit path (staged churn committed as an "archive") — an audit-trail integrity fix, not just cosmetics. T1.4's probe uses the existing remote-tracking ref only: zero network calls, no new credentials or fetch path.

---

## Sprint 2: Portability — GNU-only assumptions that brick macOS hosts

**Duration:** ~1 day. **Zone:** System. **Basis:** issues #1216, #1197, #1037, #1232. Verification caveat: #1216, #1197 and #1037 were VERIFIED BY READING CODE plus a hand-substituted BSD-semantics repro (this host is Linux/GNU); #1232 is layout-structural and reproduces in any submodule-mode mount.

**Issues closed by this sprint:** #1216, #1197, #1037, #1232

### Sprint Goal
Every code path that a macOS operator hits during triage, cleanup, staleness checks or a first mount behaves the same as on Linux — proven by PATH shims that demonstrably reproduce the BSD defect before the fix.

### Deliverables
- [x] **D2.1** — `validate-artifact.sh:273`: every `\s` replaced with `[[:space:]]` in BOTH the `grep -E` pattern and the `sed -E` expression; `| xargs` trim and `|| true` kept
- [x] **D2.2** — `workspace-cleanup.sh`: `lib/portable-realpath.sh` sourced beside the existing compat-lib source; the three raw `realpath -m` calls (`:464`, `:465`, `:1031`) replaced with `resolve_path_portable`, `|| return 1` kept at the security sites, explicit failure + empty-string guard added at `:1031`
- [x] **D2.3** — `-u` added to every BSD `date` parse whose input is UTC: `compat-lib.sh:458`, `constructs-lib.sh:240`/`:242`/`:547`, plus the 8-file mechanical sweep; `compat-lib.sh:459` deliberately left WITHOUT `-u`
- [x] **D2.4** — `mount-submodule.sh`: the initial-mount `refresh_copy_set "true"` call at `:912` degraded to a warning; `_release_inherited_mount_lock()` added and trapped inside `main()` AFTER the `SOURCE_ONLY` early return
- [x] **D2.5** — four suites written test-first with mandatory shim-faithfulness positive controls

### Sprint Exit Gate
- [ ] `bats tests/unit/validate-artifact-bsd-sed-portability.bats tests/unit/compat-lib-date-to-epoch.bats tests/unit/aleph-framework-integration.bats .claude/scripts/tests/test-workspace-cleanup.bats` green
- [ ] Existing consumer suites green: `tests/unit/validate-artifact.bats`, `tests/unit/red-team-retention.bats`, `tests/unit/butterfreezone-validate.bats`, `tests/unit/compliance-hook.bats`, `tests/unit/portable-realpath.bats`
- [ ] Four issues closed; #1197's and #1232's corrected severity noted on the PR (see Blocked & Split Items)

### Technical Tasks

#### Task 2.1 — Replace GNU `\s` in the bug-triage validator (#1216) → **[G-2]** ⇐ none

**Issue:** #1216 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/validate-artifact.sh`, `tests/unit/validate-artifact-bsd-sed-portability.bats`
**Observed failure:** on macOS the validator rejects its own shipped template — `grep` (REG_ENHANCED) selects the line, BSD `sed` fails to strip the Markdown prefix, so `$bug_id` becomes the whole line `- **bug_id**: <id>`, cascading into an ID-grammar violation plus a bogus `.run/bugs/- **bug_id**: .../state.json` lookup.

- [ ] New suite FIRST, modeled on `tests/unit/mktemp-bsd-portability.bats` (BSD-semantics shim in `$BATS_TEST_TMPDIR/shim`, masked PATH, hermetic per case)
- [ ] Replace every `\s` with `[[:space:]]` in the `grep -E` pattern AND the `sed -E` expression at `:273` (fixing grep too: a macOS grep without REG_ENHANCED produces the "no bug_id line found" violation instead)
- [ ] Leave the `| xargs` trim and `|| true` untouched; no helper, no new script

**Acceptance Criteria:**
- [ ] `grep -c -F '\s' .claude/scripts/validate-artifact.sh` returns 0.
- [ ] Under a BSD-semantics `sed` shim, `validate-artifact.sh --type bug-triage --json` on the shipped template form exits 0 with zero violations.
- [ ] Under a BSD-semantics `grep` shim, the same invocation emits no `no '**bug_id**:' line found` violation.
- [ ] Shim-faithfulness control: under the same shims, a raw `sed -E` on the template line still emits the un-stripped line.
- [ ] The existing GNU-side bug-triage cases in `tests/unit/validate-artifact.bats` stay green unmodified.

**Regression test:** `tests/unit/validate-artifact-bsd-sed-portability.bats` (new)

#### Task 2.2 — Portable path resolution in `workspace-cleanup.sh` (#1197) → **[G-2]** ⇐ none

**Issue:** #1197 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/workspace-cleanup.sh`, `.claude/scripts/tests/test-workspace-cleanup.bats`
**Observed failure:** `realpath -m` is a GNU extension; BSD realpath exits 1 with `illegal option -- m`, so every path-validation branch fails on Darwin. Corrected severity: the script does NOT exit 0 as filed — `main():1061` is `validate_grimoire_path … || exit 3`, and `autonomous-agent/SKILL.md:208-212` takes the `3)` branch, so Phase 0.0 HARD-FAILS with `HALT: Workspace cleanup security validation failed`. Worse than filed, not silent.

- [ ] Four cases FIRST in the suite that already owns path validation, reusing the BSD-stub realpath shim from `tests/unit/portable-realpath.bats:49+`
- [ ] Source `lib/portable-realpath.sh` beside the existing compat-lib source (mirroring `mount-submodule.sh:478-479`)
- [ ] Replace the three `realpath -m` calls with `resolve_path_portable`, keeping `|| return 1` at `:464`/`:465` so the security sites stay fail-closed by contract
- [ ] At `:1031` make failure explicit (`|| { error …; return 1; }`) plus an empty-string guard — never fall through to comparing against `""`
- [ ] Do NOT substitute compat-lib's `get_canonical_path`: it never returns non-zero, which would silently drop the fail-closed property

**Acceptance Criteria:**
- [ ] `grep -c 'realpath -m' .claude/scripts/workspace-cleanup.sh` returns 0.
- [ ] Under a BSD-stub `realpath` that rejects `-m`, `workspace-cleanup.sh --dry-run --json` exits 0.
- [ ] That same run's output contains no `Grimoire path outside expected location`.
- [ ] Nothing matching `realpath: illegal option` appears on stderr.
- [ ] Fail-closed preserved: with a `realpath` stub that fails every argument form, `validate_grimoire_path` returns non-zero and the script exits 3.

**Regression test:** `.claude/scripts/tests/test-workspace-cleanup.bats` (extend)

#### Task 2.3 — `date -u` on every BSD parse of a UTC timestamp (#1037) → **[G-2]** ⇐ none

**Issue:** #1037 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/compat-lib.sh`, `.claude/scripts/constructs-lib.sh`, `.claude/hooks/compliance/implement-gate.sh`, `.claude/hooks/post-merge/cycle-108-rollout-watch.sh`, `.claude/scripts/simstim-orchestrator.sh`, `.claude/scripts/trajectory-gen.sh`, `.claude/scripts/check-reality-freshness.sh`, `.claude/scripts/flatline-snapshot.sh`, `.claude/scripts/beads/update-beads-state.sh`, `tests/unit/compat-lib-date-to-epoch.bats`
**Observed failure:** BSD `date -jf` consumes the trailing `Z` as a literal and interprets the wall-clock in `$TZ`, so `_date_to_epoch` returns an epoch shifted by up to 14h on Darwin. GNU tier 1 and the perl tier are correct; the 2026-06-15 triage note cited the same line. Five consumers now depend on it.
**Recorded decision:** the 8-file one-flag sweep rides in THIS diff. It is one flag per line, inert on Linux (those branches run only after GNU `date -d` fails), `+%s` output is TZ-invariant, and AC-5 needs it to pass. If a reviewer splits the sweep, AC-5 must be re-scoped to `compat-lib.sh` + `constructs-lib.sh` only.

- [ ] New suite FIRST, modeled on `tests/unit/compat-lib-sha256.bats`: per-case shim PATH in `$BATS_TEST_TMPDIR`, `_COMPAT_OS` overridden AFTER sourcing (it is cached from `uname -s`), hermetic teardown
- [ ] Add `-u` to `compat-lib.sh:458` and `constructs-lib.sh:240`/`:242`/`:547`
- [ ] Mechanical sweep of the remaining inline BSD fallbacks that parse a `Z` format across the 7 other files
- [ ] Leave `compat-lib.sh:459` WITHOUT `-u` — it runs only when the input had no `Z`, where local-time interpretation matches GNU `date -d`

**Acceptance Criteria:**
- [ ] Under a BSD `date` shim with `_COMPAT_OS=darwin` and `TZ=America/New_York`, `_date_to_epoch "2026-01-01T00:00:00Z"` returns 1767225600.
- [ ] The same call under `TZ=Asia/Tokyo` returns the identical epoch.
- [ ] Shim-faithfulness control: the same shim invoked without `-u` returns 1767243600, proving the shim models the defect.
- [ ] `parse_iso_date "2026-01-01T00:00:00Z"` returns the same epoch as AC-1 under a non-UTC TZ, matching its own python3 tier.
- [ ] Every `date -j` / `date -jf` whose format string ends in `Z` also carries `-u` across `.claude/scripts/` and `.claude/hooks/`.
- [ ] `compat-lib.sh:459` (the no-`Z` branch) is byte-unchanged and keeps local-time semantics.

**Regression test:** `tests/unit/compat-lib-date-to-epoch.bats` (new)

#### Task 2.4 — Stop a failed Aleph install from killing the mount (#1232) → **[G-2]** ⇐ none

**Issue:** #1232 · **Risk:** medium · **Effort:** M · **Files:** `.claude/scripts/mount-submodule.sh`, `tests/unit/aleph-framework-integration.bats`
**Observed failure:** `curl | bash` submodule install aborts with `bundle and target directories may not overlap` (the bundle always lives under the repo root passed as `--target`), the failure propagates through an UNGUARDED `refresh_copy_set "true"` under `set -euo pipefail`, `create_symlinks` aborts, and `main()` never reaches `create_claude_md`/`create_config`/`create_manifest`/`create_commit` — the reported partial-install table. Secondary: the mount lock's EXIT trap is discarded by `exec` into this script, so the lock is only reaped by the next mount's stale sweep.
**PARTIAL BLOCK — root cause is NOT fixable here:** the Aleph bundle is an ingested immutable upstream artifact (`UPSTREAM_REPOSITORY = 0xHoneyJar/loa-aleph`, sha256-pinned in `bundle.lock.json`, verified at `mount-submodule.sh:697-721`). Do NOT touch `installer.ts`/`installer.js`. This task ships the crash-safety wrapper only; "Aleph runtime can never install in submodule mode" is split out (see Blocked & Split Items) so the fix does not silently normalize every submodule mount shipping without an Aleph runtime.

- [ ] Amend the harness mock node so `install` CAN fail — it currently does `--bundle) shift 2 ;;`, discarding the bundle and always succeeding, which is exactly what hid this bug
- [ ] Guard `:912`: `if ! refresh_copy_set "true"; then warn "… mount continuing — run mount-submodule.sh --reconcile"; fi`. Leave the fatal contract at `:1531`, `:1561`, `update-loa.sh:225` and `:349` untouched
- [ ] Add `_release_inherited_mount_lock()` that removes `.claude/.mount-lock` ONLY if its contents equal `$$` (`exec` preserves the PID), and register the EXIT trap inside `main()` AFTER the `SOURCE_ONLY` early return — a top-level trap would leak into `update-loa.sh`'s sourcing shell

**Acceptance Criteria:**
- [ ] With the mock node failing `install`, `create_symlinks` returns 0 and emits a warning naming the copy-set/Aleph failure.
- [ ] In that fixture, a full submodule mount leaves `CLAUDE.md`, `.loa.config.yaml` and `.loa-version.json` present and creates a mount commit.
- [ ] `.claude/.mount-lock` is absent after `mount-submodule.sh` exits on the success path.
- [ ] `.claude/.mount-lock` is absent after it exits on the Aleph-failure path.
- [ ] A pre-existing `.claude/.mount-lock` whose contents are a DIFFERENT pid is left untouched.
- [ ] `refresh_copy_set "true"` still returns non-zero when the Aleph refresh fails, so `--reconcile` and `update-loa.sh` keep failing loudly.

**Regression test:** `tests/unit/aleph-framework-integration.bats` (extend; mock node gains a failure mode)

### Dependencies
- None between tasks. All four are independently landable and parallel-safe with Sprints 1 and 3.

### Risks & Mitigation
- **A shim that does not actually model BSD** → every portability task carries a mandatory shim-faithfulness positive control as an AC; without it the suite proves nothing
- **The 8-file `date -u` sweep touches unrelated scripts** → one flag per line, no logic change, inert on Linux; the sweep boundary is stated as a recorded decision, not discovered mid-diff
- **T2.4 normalizes Aleph-less mounts** → the upstream issue is split out in the same PR description, and AC-6 keeps `--reconcile` failing loudly so the degradation is scoped to the initial mount only
- **No real-BSD verification lane** → accepted; `tests/bats-tests.yml` is ubuntu-only and adding a macOS matrix is out of scope (Ground rule 6)

### Success Metrics
- Zero GNU-only regex shorthand or `realpath -m` in the two fixed scripts; zero `Z`-format BSD date parse without `-u`; a submodule mount completes with a commit even when the pinned Aleph installer refuses

### Security Considerations
- T2.2's two validator sites stay fail-closed BY CONTRACT (`|| return 1` preserved, and AC-5 proves an unresolvable path is still rejected) — the fix must not trade a Darwin HALT for a silent accept. T2.4's lock release is pid-matched, so a standalone or sourced invocation can never delete another process's lock.

---

## Sprint 3: Silent Success — runs that report green while doing nothing

**Duration:** ~1.5 days. **Zone:** System. **Basis:** issues #1174, #1172, #1213, #1036, #1215.

**Issues closed by this sprint:** #1174, #1172, #1213, #1036, #1215

### Sprint Goal
Every surface in this sprint currently answers "fine" when it means "nothing happened": an undriven bridge jacks out, fail-open hooks stop firing in a nested worktree, an L3 phase reports "nothing in flight" from the wrong cwd, a DEGRADED triage substrate reaches READY_FOR_HITL wearing the wording of a clean run, and a test helper silently substitutes the safe default for its injected sanitizer. After this sprint each one is loud or provably wired.

### Deliverables
- [x] **D3.1** — `bridge-orchestrator.sh`: `detect_zero_work()` extracted from `:1083-1108`, file check scoped to `${bridge_id}-iter*-findings.json`, metrics conjunct added via one jq read, `HALTED` + exit 3 on zero work, `--allow-empty` added to the arg parser, `usage()` and the Exit Codes block
- [x] **D3.2** — all 26 hook commands in `.claude/settings.json` and all 22 in `.claude/hooks/settings.hooks.json` anchored via `$(git rev-parse --show-toplevel 2>/dev/null || echo .)`, both files rewritten identically in the same commit; `lint-invariants.sh::check_hooks_wiring` gains a bare-relative fence
- [x] **D3.3** — `session-cap-bb/reader.sh` and `dispatcher.sh` anchored to a script-location-derived `REPO_ROOT` (depth-5, correct in both vendored and submodule layouts); both env overrides kept as first-wins
- [x] **D3.4** — `post-pr-orchestrator.sh`: `elif DEGRADED` branch in the post-loop block (error naming the convergence file + its `.reason`), `bridgebuilder_convergence_state` field, `PR-BB-DEGRADED` marker, and a guarded warning at the READY_FOR_HITL transition
- [x] **D3.5** — `cache.test.ts` helper honors its injected sanitizer (`opts?.sanitizer ?? mockSanitizer()`, opts field narrowed to `IOutputSanitizer`) plus the redaction test that fails on current main

### Sprint Exit Gate
- [ ] `bats tests/unit/bridge-orchestrator-single-iteration.bats tests/unit/hook-wiring.bats tests/unit/post-pr-bridgebuilder-1036.bats tests/integration/session-cap-bb-dispatch.bats` green
- [ ] `.claude/scripts/test-lint-invariants.sh` green; `cd .claude/skills/bridgebuilder-review && npm test` green
- [ ] Five issues closed with the reproducing test cited in each closing comment

### Technical Tasks

#### Task 3.1 — Gate bridge finalization on evidence of work (#1174) → **[G-3]** ⇐ none

**Issue:** #1174 · **Risk:** medium · **Effort:** M · **Files:** `.claude/scripts/bridge-orchestrator.sh`, `tests/unit/bridge-orchestrator-single-iteration.bats`
**Observed failure:** the #473 silent-no-op detector counts ANY `*.json` under `.run/bridge-reviews`, including files from prior bridges, then unconditionally sets `JACKED_OUT`. A run nobody drove (no `SIGNAL:*` lines) reports success with `total_sprints_executed=0` and `total_findings_addressed=0` — the orchestrator cannot distinguish "nothing to do" from "nobody drove me" and defaults to green.
**Recorded decision (the post-PR question):** ACCEPT the exit-3 HALT in `post-pr-orchestrator.sh`. Its `case $bridge_result` default already HALTs on any non-zero bridge exit and that path already exits 3 today via the existing detector, so accepting is both the smallest diff and consistent with the deliberate #1076 fail-loud posture. `post-pr-orchestrator.sh` is NOT edited by this task.

- [ ] Functional tests FIRST: awk-extract `detect_zero_work()` (technique from `tests/unit/flatline-jq-construction.bats:85-115`), source it against fixture `BRIDGE_STATE_FILE` + review dirs in the bats temp `PROJECT_ROOT`
- [ ] Extract `:1083-1108` into `detect_zero_work()`, mirroring `detect_silent_noop_flatline()` in `flatline-orchestrator.sh`
- [ ] Scope the file check to `find "$findings_dir" -maxdepth 1 -name "${bridge_id}-iter*-findings.json"`
- [ ] Add the metrics conjunct (one jq read summing `total_sprints_executed`, `total_findings_addressed`, `[.iterations[].bridgebuilder.total_findings]|add // 0`); zero AND no current-bridge findings → keep the actionable stderr message (with a 4th option line naming `--allow-empty`), `HALTED`, exit 3
- [ ] Add `--allow-empty` to the arg parser, `usage()` flag list and the Exit Codes block; leave `--no-silent-noop-detect` untouched; the gate stays finalization-only (`--single-iteration` exits by contract)

**Acceptance Criteria:**
- [ ] With all work metrics at 0 and no `${bridge_id}-iter*-findings.json`, `detect_zero_work` exits 3.
- [ ] That same run leaves the state file's `.state` at `HALTED` and never `JACKED_OUT`.
- [ ] A findings file belonging to a DIFFERENT `bridge_id` does not satisfy the check: the exit is still 3.
- [ ] With `metrics.total_sprints_executed >= 1`, `detect_zero_work` returns 0 and finalization reaches `.state == JACKED_OUT`.
- [ ] `bridge-orchestrator.sh --allow-empty --help` exits 0 and `usage()` lists `--allow-empty`.
- [ ] With `ALLOW_EMPTY=true`, a zero-work state finalizes to `JACKED_OUT` with exit 0.
- [ ] `.claude/scripts/post-pr-orchestrator.sh` is byte-unchanged by this task.

**Regression test:** `tests/unit/bridge-orchestrator-single-iteration.bats` (extend, #473 family)

#### Task 3.2 — Anchor hook command paths to the repo root (#1172) → **[G-3]** ⇐ none

**Issue:** #1172 · **Risk:** medium · **Effort:** M · **Files:** `.claude/settings.json`, `.claude/hooks/settings.hooks.json`, `.claude/scripts/lint-invariants.sh`, `tests/unit/hook-wiring.bats`
**Observed failure:** all 26 hook commands are bare-relative (`jq` over `.hooks[][].hooks[].command`: total 26, `startswith(".claude/")` 26; template file 22/22). In a worktree nested under `.claude/worktrees/`, Claude Code anchors hook cwd to an intermediate `.claude` directory, so `/bin/sh` resolves `.claude/hooks/...` to a non-existent double-nested path. Hook errors are non-blocking, so the destructive-bash fence, team-role guard and mutation audit trail silently stop running for the whole session.
**Scope note:** the deeper cause is Claude Code's project-root resolution for worktrees under `.claude/worktrees/` (upstream Anthropic). This is mitigation, not a root-cause fix; the upstream report is split out.

- [ ] W11/W12 FIRST in `hook-wiring.bats` (jq-driven bare-relative assertion; four-cwd resolution against a temp git repo with a worktree created under `.claude/worktrees/`), plus the lint-fence fixture case in `.claude/scripts/test-lint-invariants.sh`
- [ ] One jq pass over each file's `.command` values rewriting every leading AND embedded bare `.claude/` to `$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/`; commands with two paths (hook-guard + guarded hook) get the prefix on both
- [ ] Do NOT use `$CLAUDE_PROJECT_DIR` as the primary anchor — it is unset/mis-resolved in the failing environment
- [ ] Rewrite BOTH files identically in the same commit (template-live parity compares exact strings)
- [ ] Extend `check_hooks_wiring` with an ERROR for any command matching `(^|[[:space:]])\.claude/`

**Acceptance Criteria:**
- [ ] Zero hook commands in `.claude/settings.json` start with `.claude/` or contain an unanchored ` .claude/` argument.
- [ ] The same assertion holds for `.claude/hooks/settings.hooks.json`.
- [ ] Every `.claude/settings.json` hook command resolves to an existing executable from repo root, worktree root, `<repo>/.claude`, and `<repo>/.claude/worktrees`.
- [ ] In a non-git tree the anchor falls back to `.`, preserving today's cwd-relative behavior.
- [ ] Template-live parity holds: `hook-wiring.bats` W1 and W10 pass and no command appears twice under one matcher (W3).
- [ ] `lint-invariants.sh` exits with an ERROR for a fixture settings file that reintroduces a bare-relative hook command.

**Regression test:** `tests/unit/hook-wiring.bats` (W11, W12) + `.claude/scripts/test-lint-invariants.sh`

#### Task 3.3 — Anchor the session-cap contract scripts (#1213) → **[G-3]** ⇐ none

**Issue:** #1213 · **Risk:** low · **Effort:** S · **Files:** `.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/reader.sh`, `.../dispatcher.sh`, `tests/integration/session-cap-bb-dispatch.bats`
**Observed failure:** `reader.sh:25` defaults the state file to a cwd-relative `.run/session-limit-state.json` and `dispatcher.sh:42` calls `git remote get-url origin` with no `git -C`. The L3 executor runs phase scripts under `env -i` with NO cd and no repo-root in the allowlist, so from any other directory the reader reports `state_present:false` (a false noop that looks like "nothing was in flight") and the dispatcher cannot derive owner/repo and exits 1.

- [ ] Two cases FIRST, both invoked with `cd "$TEST_DIR"`: dispatcher default-origin resolution with a mock entry and no `LOA_SESSION_CAP_BB_REPO`; reader default-state resolution against a 5-deep fixture tree, plus the absent-file variant
- [ ] `reader.sh`: derive `_here` + `REPO_ROOT` (depth-5) and default `STATE_FILE` under `${REPO_ROOT}/.run/`
- [ ] `dispatcher.sh`: reuse the existing `_here`, add the same `REPO_ROOT`, change `:42` to `git -C "$REPO_ROOT" remote get-url origin`
- [ ] Keep `LOA_SESSION_CAP_STATE_FILE` and `LOA_SESSION_CAP_BB_REPO` as the first-wins branch; introduce no new env var; leave `decider.sh`/`awaiter.sh`/`logger.sh` untouched

**Acceptance Criteria:**
- [ ] `dispatcher.sh` run from a cwd outside the repository with `LOA_SESSION_CAP_BB_REPO` unset writes `dispatcher.json` with `.dispatched == true`.
- [ ] That same run records `.repo == "0xHoneyJar/loa"`.
- [ ] `reader.sh` run from an unrelated cwd against a 5-deep fixture tree containing a state file emits `state_present:true`.
- [ ] With no state file in that fixture tree, `reader.sh` still exits 0 with `state_present:false`.
- [ ] Explicit `LOA_SESSION_CAP_STATE_FILE` and `LOA_SESSION_CAP_BB_REPO` overrides still win — every existing case in `tests/integration/session-cap-bb-dispatch.bats` stays green.

**Regression test:** `tests/integration/session-cap-bb-dispatch.bats` (extend)

#### Task 3.4 — Surface DEGRADED triage at READY_FOR_HITL (#1036) → **[G-3]** ⇐ none

**Issue:** #1036 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/post-pr-orchestrator.sh`, `tests/unit/post-pr-bridgebuilder-1036.bats`
**Observed failure:** `grep -c DEGRADED .claude/scripts/post-pr-orchestrator.sh` → 0. `post-pr-triage.sh` honestly sets `convergence_state=DEGRADED` on PARSE_FAILURES and returns 3; the orchestrator swallows that exit as "non-fatal", falls into the else branch and reports `Max iterations reached without flatline` — the same benign wording as an ordinary non-converged run — then hands off at READY_FOR_HITL with no distinct marker.
**Scope note:** visibility only. Whether DEGRADED should HALT stays on the #969 line; the loop condition and the `completed` phase status are deliberately unchanged.

- [ ] Tests FIRST: static contract assertions that the DEGRADED branch exists and references the convergence file + marker (technique from `post-pr-bridgebuilder-1076.bats:31-49` — `phase_bridgebuilder_review` cannot run standalone), plus a functional `post-pr-state.sh init/add-marker/set/get` round-trip in a temp STATE_DIR
- [ ] Insert an `elif [[ "$convergence_state" == "DEGRADED" ]]` branch in the post-loop block: `log_error` naming the convergence file plus its `.reason`, then `set bridgebuilder_convergence_state DEGRADED` and `add-marker PR-BB-DEGRADED` via the native marker mechanism
- [ ] Add one guarded warning at the READY_FOR_HITL transition; add no new lib; leave the loop condition alone

**Acceptance Criteria:**
- [ ] With convergence state DEGRADED, the post-loop block emits an error line naming the convergence file.
- [ ] That same run does NOT emit `Max iterations reached without flatline`.
- [ ] After a DEGRADED run, `post-pr-state.json` has `.bridgebuilder_convergence_state == "DEGRADED"` and `.markers` contains `PR-BB-DEGRADED`.
- [ ] The `PR-BB-DEGRADED` marker file exists in the state dir.
- [ ] The READY_FOR_HITL transition emits a degraded warning when that field is DEGRADED and nothing extra when it is unset.
- [ ] With convergence state FLATLINE the success line still fires and no `PR-BB-DEGRADED` marker is created.
- [ ] The `bridgebuilder_review` phase status remains `completed` in the DEGRADED case.

**Regression test:** `tests/unit/post-pr-bridgebuilder-1036.bats` (new)

#### Task 3.5 — Honor the injected sanitizer in the cache test helper (#1215) → **[G-3]** ⇐ none

**Issue:** #1215 · **Risk:** low · **Effort:** S · **Files:** `.claude/skills/bridgebuilder-review/resources/__tests__/cache.test.ts`
**Observed failure:** `cache.test.ts:169` is a ternary with identical branches — `opts?.sanitizer ? mockSanitizer() : mockSanitizer()` — so the injected value declared at `:151` is discarded. The helper advertises sanitizer injection the constructor never wires, meaning any cache test that varies sanitizer behavior passes vacuously against the safe default. The correct pattern already exists at `integration.test.ts:254`.

- [ ] Add the injecting test FIRST (`describe/it "injected sanitizer reaches the pipeline"`), reusing the existing `mockPoster` override hook to capture the posted body; it must fail on current main
- [ ] Narrow the opts field at `:151` from `Partial<IOutputSanitizer>` to `IOutputSanitizer`; change `:169` to `opts?.sanitizer ?? mockSanitizer()`
- [ ] No production-code change; no dist rebuild (the BB dist drift gate excludes `__tests__/`)

**Acceptance Criteria:**
- [ ] `buildPipeline({ sanitizer })` passes the instance through: a spy sanitizer records exactly 1 `sanitize()` call after a completed run.
- [ ] With an injected sanitizer returning `sanitizedContent: "[REDACTED]"`, the mock poster's captured body equals `[REDACTED]`.
- [ ] With `sanitizerMode: "strict"` and the same unsafe sanitizer, the run produces an `E_SANITIZER_BLOCKED` result rather than a posted review.
- [ ] No ternary with identical branches remains in `cache.test.ts`.
- [ ] `npm test` in `.claude/skills/bridgebuilder-review` is green with all pre-existing cache tests passing.

**Regression test:** `.claude/skills/bridgebuilder-review/resources/__tests__/cache.test.ts` (fix and guard in the same file)

### Dependencies
- None between tasks; all five are independently landable. T3.1's recorded decision keeps `post-pr-orchestrator.sh` out of that task, so T3.1 and T3.4 do not collide on the same file.

### Risks & Mitigation
- **T3.1 makes a legitimately empty bridge HALT the post-PR run** → accepted by recorded decision (that path already exits 3 today); `--allow-empty` exists as the documented escape and is named in the block message
- **T3.2 changes 48 command strings across two files** → single mechanical jq pass, both files in one commit, template-live parity asserted by W1/W10/W3, and the `|| echo .` fallback keeps non-git installs working
- **T3.2 adds a `git rev-parse` per hook invocation (~3ms)** → verify no hook is on a hot loop before landing
- **T3.4's phase semantics drift** → AC-7 pins the phase status at `completed`; the convergence question stays on #969

### Success Metrics
- An undriven bridge HALTs instead of jacking out; hook commands resolve from all four cwds including the two that fail today; L3 phases work from any cwd; DEGRADED is impossible to mistake for clean; sanitizer injection is provably wired

### Security Considerations
- T3.2 is the sprint's security-relevant fix: the fence that stops firing in a nested worktree is the destructive-bash guard, and the audit loggers that go quiet are the mutation audit trail. The rewrite widens nothing (same scripts, same matchers) — it only makes the existing fences reachable. T3.5's redaction test proves the sanitizer boundary is actually exercised rather than defaulted past.

---

## Sprint 4: Authorization and Tripwire Honesty

**Duration:** ~1 day. **Zone:** System + `tools/`. **Basis:** issues #1211, #1065.

**Issues closed by this sprint:** #1211, #1065

### Sprint Goal
Two defects where the system's own assurance signal is wrong: a VERIFIED root-signed trust store is silently overridden by a producer-writable keydir (chain forgery accepted with `OK 1 entries`) while `revocations[]` is cryptographically protected yet semantically inert, and a tripwire that would pass over the very lines it was asked to guard.

### Deliverables
- [x] **D4.1** — `audit-envelope.sh:344` keydir fallback additionally hard-rejects when `_audit_trust_store_status` is `VERIFIED`; `_audit_revoked_at` added and revocation enforced at the verify block (`:855-864`) reusing the existing `_audit_ts_ge_cutoff` comparator; both changes mirrored in `loa_cheval/audit_envelope.py` for R15 behavior identity
- [x] **D4.2** — the 8 remaining `yq ... 2>/dev/null || echo` sites in `construct-index-gen.sh` routed through the existing `_strict_or_default` wrapper with defaults preserved verbatim; `:206`'s numeric-compare guard untouched; the file added to `ENFORCED_FILES`; the matcher extended from `jq` to `[jy]q` and the 34 pre-existing yq sites annotated with the script's own documented suppression marker
- [x] **D4.3** — cycle E2E battery + issue closure with per-issue re-scoping notes

### Sprint Exit Gate
- [ ] `bats tests/security/audit-envelope-strip-attack.bats tests/integration/audit-trust-store-auto-verify.bats tests/unit/construct-index-gen.bats tests/unit/check-no-swallowed-jq.bats` green
- [ ] `pytest .claude/adapters/tests/test_audit_envelope_strict_verify.py` green; `tools/check-no-swallowed-jq.sh` exits 0 over the full enforced set
- [ ] **E2E (end-to-end)**: full `tests/unit/` + `tests/integration/` + `tests/security/` + `.claude/scripts/tests/` suites; `validate-constraints.sh`; `validate-skill-capabilities.sh`; `check-loa.sh` on this repo AND a fresh `mount-loa.sh` mount (covers Sprint 2's mount fix); `grimoire-index.sh --validate`; `tools/check-bb-dist-fresh.sh --check`
- [ ] Cycle report at `grimoires/loa/reports/bug-burndown-cycle-123.md`: per-issue verdict, reproducing test, and the spin-off bead ids
- [ ] Two issues closed; #1211 re-scoped BEFORE implementation (see Blocked & Split Items)

### Technical Tasks

#### Task 4.1 — Kill the silent keydir downgrade and enforce revocations (#1211) → **[G-4]** ⇐ none

**Issue:** #1211 · **Risk:** medium · **Effort:** M · **Files:** `.claude/scripts/audit-envelope.sh`, `.claude/adapters/loa_cheval/audit_envelope.py`, `tests/security/audit-envelope-strip-attack.bats`, `.claude/adapters/tests/test_audit_envelope_strict_verify.py`
**Observed failure (live repro against main's script):** with a root-signed trust store whose `keys[]` contains only `alice` (`verify-trust-store` rc=0 → VERIFIED) and an `evil` keypair absent from the store but present in `LOA_AUDIT_KEY_DIR`, a post-cutoff entry signed by `evil` yields `verify-chain` → `OK 1 entries`, rc=0 — FORGERY ACCEPTED. Non-strict is the production default (`audit/audit-snapshot.sh:152` calls it bare). Second live repro: a root-signed `revocations[]` entry with `revoked_at=2020-01-02` and an entry at `ts_utc=2026-07-30` verifies `OK` in BOTH default and `--verify-for-merge` mode, contradicting `runbooks/audit-keys-bootstrap.md:249`.
**BLOCKED ON RE-SCOPING (maintainer, before implementation):** the issue's PRIMARY diagnosis — the `yq --arg` sub-claim — is ALREADY FIXED on main at `:332-333` (PR #1160, 89ee924a, 16 days before the issue was filed; the reporter tested a stale `.loa` pin). Sub-finding (e) (unquoted ISO-8601) is also already fixed. An implementer who takes the issue at face value will "fix" working code and miss both live mechanisms. Retitle/re-scope first.
**Recorded decision:** sub-finding (d) — absent/BOOTSTRAP-PENDING store failing open in default mode — is EXCLUDED. Making it fail closed would break install-time bootstrap, which is precisely what BOOTSTRAP-PENDING exists to permit; it needs a policy such as "fail closed once the log contains any signed entry" and is re-filed separately.

- [ ] Two paired bash/python cases FIRST in the security suite; note its current fixture store is BOOTSTRAP-PENDING, so the new cases must root-sign their own store via `lib/audit-signing-helper.py trust-store-sign` with a test-pinned root pubkey
- [ ] A. Widen the strict-only guard at `:344`: also `return 1` when `_audit_trust_store_status` is `VERIFIED` (already per-process cached on mtime/size/sha256 — zero added cost); BOOTSTRAP-PENDING and missing stores keep the keydir fallback
- [ ] B. Add `_audit_revoked_at <writer_id>` modeled verbatim on the adjacent `_audit_trust_cutoff` (yq with `env()` + python-yaml fallback); reject with `[KEY-REVOKED]` at `:855-864` REUSING `_audit_ts_ge_cutoff` — no new comparator, no new abstraction
- [ ] Mirror both in `audit_envelope.py` (`:141-162`, `:610-612`)

**Acceptance Criteria:**
- [ ] Default non-strict `verify-chain` exits non-zero when the signing writer is absent from a VERIFIED root-signed trust store.
- [ ] That failure prints a key-resolution message naming the writer id.
- [ ] An entry whose `ts_utc >= revoked_at` fails with `[KEY-REVOKED]` in BOTH default and `--verify-for-merge` modes.
- [ ] An entry whose `ts_utc < revoked_at` still verifies OK, preserving the runbook grandfathering rule.
- [ ] Python `audit_verify_chain` returns the same pass/fail verdict as bash for the out-of-store-writer fixture.
- [ ] Python `audit_verify_chain` returns the same pass/fail verdict as bash for the revoked-writer fixture.
- [ ] With a BOOTSTRAP-PENDING or absent trust store, non-strict verify still resolves keydir pubkeys.
- [ ] All 7 existing cases in `tests/security/audit-envelope-strip-attack.bats` and all 13 in `tests/integration/audit-trust-store-auto-verify.bats` pass unchanged.

**Regression test:** `tests/security/audit-envelope-strip-attack.bats` + `.claude/adapters/tests/test_audit_envelope_strict_verify.py`

#### Task 4.2 — Route the 8 yq swallow sites and make the tripwire non-vacuous (#1065) → **[G-4]** ⇐ none

**Issue:** #1065 · **Risk:** low · **Effort:** S · **Files:** `.claude/scripts/construct-index-gen.sh`, `tools/check-no-swallowed-jq.sh`, `tests/unit/construct-index-gen.bats`, `tests/unit/check-no-swallowed-jq.bats`
**Observed failure:** 8 `yq eval ... 2>/dev/null || echo` sites remain (`:205`, `:213`, `:221`, `:224`, `:233` in `aggregate_capabilities`; `:366`, `:367`, `:368` in the construct.yaml overlay). On malformed frontmatter `yq eval` exits 1 (`Error: bad file: yaml: line 1: did not find expected ',' or ']'`) and the current shape converts that to `sv=0` / `read_files=false` with rc=0 — a pack's declared capabilities silently collapse. Textbook KF-004/KF-015 silent-clean class.
**Recorded decision (the scope question the issue forces):** take the **M scope**. The issue's own stated acceptance criterion — "added to ENFORCED_FILES (the tripwire passes after the remaining sites are routed)" — is satisfied VACUOUSLY today: the matcher at `tools/check-no-swallowed-jq.sh:121` is `jq`-only, all 8 sites are `yq`, and running the real scanner over main's file returns `OK — no output-swallowing jq shapes`, exit 0. Shipping the S scope would close the issue with ZERO regression protection for the sites it is about, which fails Ground rule 1. So: extend the matcher to `[jy]q` AND append the script's OWN documented suppression marker (`# check-no-swallowed-jq: ok (pending #1025 sweep)`) to the 34 pre-existing yq sites across `adversarial-review.sh` (12), `flatline-orchestrator.sh` (7), `red-team-pipeline.sh` (12), `red-team-retention.sh` (2), `red-team-model-adapter.sh` (1). This is the mechanism the scanner header prescribes for exactly this situation; it makes those sites greppable and tracked instead of invisible, and it changes no runtime behavior. A follow-up bead converts them under the #1025 sweep.

- [ ] Malformed-input cases FIRST in `construct-index-gen.bats`, copying the shape of T18 (exit 0 + `extraction failed` + resilient default, with the existing `create_mock_pack`/`create_mock_construct_yaml` helpers): one `aggregate_capabilities` site, one boolean field, the `execute_commands` map/allowed path, one construct.yaml overlay field
- [ ] A positive-detection case in `check-no-swallowed-jq.bats` asserting a yq swallow line in `construct-index-gen.sh` is FLAGGED — this is the guard against the current vacuous pass
- [ ] Convert the 8 sites to `_strict_or_default "<default>" "<ctx>" yq eval …` with defaults preserved verbatim (`"0"`, `"false"`, `"!!null"`, `"false"`, `"[]"`, `""`, `""`, `""`), following the proven shape already at `:375-396` in the same function; leave `:206` alone
- [ ] Add `construct-index-gen.sh` to `ENFORCED_FILES`; extend the matcher to `[jy]q`; append the suppression marker to the 34 legacy sites

**Acceptance Criteria:**
- [ ] `grep -nE '2>/dev/null \|\| echo' .claude/scripts/construct-index-gen.sh | grep -vE ':[[:space:]]*#' | wc -l` returns 0.
- [ ] Line `:206`'s `[[ "$sv" -gt "$agg_schema_version" ]] 2>/dev/null` numeric guard is byte-unchanged.
- [ ] A pack with malformed SKILL.md frontmatter makes `construct-index-gen.sh` exit 0 and emit a `WARNING: <ctx>: extraction failed` naming the capability context.
- [ ] That run applies the documented resilient default for at least one `aggregate_capabilities` site and one construct.yaml overlay site.
- [ ] For well-formed packs the generated index JSON is byte-identical to pre-change output.
- [ ] With the matcher extended to `[jy]q`, `tools/check-no-swallowed-jq.sh` exits 0 over the full enforced set including `construct-index-gen.sh`.
- [ ] Introducing a fresh `yq ... 2>/dev/null || echo` line into `construct-index-gen.sh` makes the tripwire exit 1.

**Regression test:** `tests/unit/construct-index-gen.bats` + `tests/unit/check-no-swallowed-jq.bats`

### Dependencies
- Sprints 1-3 merged before the E2E battery in the Sprint Exit Gate (it covers the whole cycle, including the fresh-mount check that exercises Sprint 2's mount fix). T4.1 and T4.2 are mutually independent.

### Risks & Mitigation
- **T4.1's guard breaks install-time bootstrap** → the widened guard fires ONLY on `VERIFIED`; BOOTSTRAP-PENDING and absent stores are explicitly preserved, and AC-7/AC-8 pin every existing fixture
- **An implementer "fixes" the already-fixed `yq --arg` line** → the issue must be re-scoped before implementation; the task body states the fixed line and its PR
- **T4.2's 34-site marker sweep looks like adjacent churn** → it is comment-only, changes no runtime behavior, and is the documented mechanism; the alternative (S scope) ships a knowingly vacuous guard, which Ground rule 1 forbids
- **`bats` is not installed in the triage checkout** → T4.1's and T4.2's suites can only be executed in CI; the local baseline is a code-level diff review plus the sandbox repros already recorded on the issues

### Success Metrics
- Forged chain entry rejected in the DEFAULT verify mode; revocation actually revokes in both modes with grandfathering intact; bash and Python verdicts identical; 0 swallow sites in `construct-index-gen.sh` with a tripwire that can actually see them

### Security Considerations
- T4.1 is the cycle's only true authorization fix: it closes an accepted-forgery path on a root-signed VERIFIED trust store and makes a cryptographically-protected-but-inert `revocations[]` array actually load-bearing. The fix narrows trust (never widens): the keydir remains usable ONLY where the trust store is absent or explicitly BOOTSTRAP-PENDING. T4.2 converts silent capability collapse into a visible WARNING, which is a fail-loud change in a gate-adjacent generator.

---

## Blocked & Split Items

Everything here is deliberately NOT implemented in this cycle. Each row is either a decision a maintainer must record before the task runs, or scope split out so a task's diff stays minimal.

| Item | Type | Disposition |
|---|---|---|
| #1233 lane check | DECISION (recorded 2026-07-30) | Proceed as `/bug`. The failure is observed and reproduced 3x (wrong next-step on a shipped cycle), which clears the evidence bar; the remedy adds a detection branch to an existing status function rather than a new capability, so it stays inside the bug lane. Delegated authority: maintainer deferral 2026-07-30. |
| #1233 second symptom (repro 2: a HALTED run state whose blocker was superseded by rulings on main) | SPLIT | Needs a different signal than ledger-archived. Separate bead; do NOT bundle — it would stop T1.4's diff being minimal. |
| #1234 ledger data hygiene | SPLIT | This repo's ledger carries 54 stale `active` entries and 46 legacy string-sprint entries. The `first(...)` fallback stays hazardous until they are reconciled. Distinct data-hygiene bead; NOT in T1.1's diff. |
| #1234 fallback-order decision | DECISION (recorded) | Pointer → `first(...)` in document order → skip-with-warning. Recorded here per the issue author's sandbox-tested design. |
| #1232 Aleph overlap guard | PARTIAL BLOCK (upstream) | `installer.ts`/`installer.js` are an sha256-pinned immutable ingest from `0xHoneyJar/loa-aleph`; relaxing the guard needs an upstream change plus re-ingest and re-pin. New upstream-dependent issue: "Aleph runtime can never install in submodule mode". Staging the bundle to a tmpdir is rejected — it would execute a COPY of a pinned installer, a trust-boundary change needing an owner decision. |
| #1206 SETTLE `max_prs: 1000` mitigation | SPLIT (external repo) | Removable once T1.2 lands, but it lives outside this repo. Follow-up, not part of the diff. |
| #1216 sibling `\s` sites | SPLIT (feature work) | `validate-change-plan.sh`, `butterfreezone-validate.sh`, `feature-gates.sh`, `loa-learnings-index.sh`, `post-pr-e2e.sh` carry the same class with NO observed failure — not `/bug`-eligible. Lint bead: `tools/check-no-gnu-regex-shorthand.sh`, mirroring `tools/check-no-raw-sha256sum.sh`. |
| #1197 `tools/check-no-raw-realpath-m.sh` | SPLIT (feature work) | Regression-coverage feature work needing an exemption set (`lib/portable-realpath.sh:31`, `compat-lib.sh:189`, `path-lib.sh:340`, `mount-submodule.sh` comments), a `--root` flag and a suppression marker. Separate bead. |
| #1197 issue body correction | MAINTAINER ACTION | The body's "exits 0 / silent skip" claim is wrong: it exits 3 and the autonomous-agent HALTs. Severity is understated. Correct the body or note it on the PR (triage was read-only). |
| #1037 macOS CI lane | SPLIT (CI config) | Real-BSD verification has no lane (`bats-tests.yml` is ubuntu-only; macos-latest exists only in `model-health-probe-concurrency.yml` and `model-registry-drift.yml`). Shim-only now; adding a runner lane is separate CI work with cost implications. |
| #1174 post-PR interaction | DECISION (recorded) | ACCEPT the exit-3 HALT in `post-pr-orchestrator.sh` (that path already exits 3 today; consistent with #1076 fail-loud). No `--allow-empty` plumbing from post-PR. |
| #1172 upstream root cause | SPLIT (upstream Anthropic) | Claude Code's project-root/hook-cwd resolution for worktrees under `.claude/worktrees/`. T3.2 is mitigation; file the upstream report separately. |
| #1211 issue is wrong-on-main | RE-SCOPED (comment posted 2026-07-30) | The `yq --arg` diagnosis is stale — `_trust_store_status()` (`.claude/adapters/loa_cheval/audit_envelope.py:407-469`) parses with Python `yaml.safe_load`. The live fail-open survives via a different route: a bare `except Exception` downgrades an UNREADABLE store to `BOOTSTRAP-PENDING` (`:453-456`), which `_check_trust_store()` permits writes under. T4.1 targets THAT mechanism (present-but-unparseable ⇒ INVALID; absent ⇒ bootstrap) plus revocation-consultation coverage. Absent-store policy stays split. Correction posted on the issue. |
| #1211 sub-finding (d) absent-store fail-open | SPLIT (policy decision) | Failing closed in default mode would break install-time bootstrap. Re-file with an explicit policy, e.g. "fail closed once the log contains any signed entry". |
| #1065 legacy yq site conversion | SPLIT | The 34 marker-suppressed sites in `adversarial-review.sh` / `flatline-orchestrator.sh` / `red-team-*` are annotated, not converted. Follow-up bead under the #1025 sweep. |

### Already-fixed issues (close, do not implement)

The 2026-07-30 triage found **no** whole issue already fixed on main — all 15 tasks above re-reproduced. But three sub-claims inside otherwise-live issues ARE already fixed, and each must be closed-out in the issue text rather than implemented:

- **#1211 (a)** — the `yq --arg` resolver sub-claim: fixed at `.claude/scripts/audit-envelope.sh:332-333` (PR #1160, 89ee924a, 2026-06-28) and now using `env()`. The issue was filed against a stale sensenet `.loa` pin.
- **#1211 (e)** — unquoted ISO-8601 bricking verify: fixed; `rfc8785.dumps` is wrapped with a "QUOTE all timestamps" diagnostic on BOTH the verify path (`lib/audit-signing-helper.py:359-364`) and the sign path (`:453-457`), and the runbook example is quoted (`audit-keys-bootstrap.md:244`).
- **#1197** — the "exits 0, so `/autonomous` reports success" claim: REFUTED. The script exits 3 and Phase 0.0 hard-HALTs.

Do not write code for these. Annotate them on the issue/PR so the next reader is not sent to fix working code.

---

## Out of scope

The 2026-07-30 triage covered 61 open issues. Everything below is a non-bug cluster — feature work, design decisions, or reports — and is explicitly OUT of this cycle. Routing anything here through `/bug` would violate the bug-eligibility rule (`/bug` requires an OBSERVED failure, regression, or stack trace; the same rule already excludes the split-out lint tools listed above).

| Cluster | Issues | Why out |
|---|---|---|
| Refactors | #1026, #1032, #1027 | Structural improvement with no observed failure — route through `/plan`, not `/bug`. |
| RFCs | #1006, #1001 | Design proposals awaiting a decision; no defect to reproduce. |
| Guard features | #1207, #1208, #1209, #1025, #1230 | New enforcement surfaces (including the #1025 swallow sweep that T4.2's marker follow-up feeds). Feature work by definition — a guard that does not exist yet cannot have regressed. |
| Config decisions | #1199, #1095 | Configuration policy choices needing an owner ruling, not a fix. |
| Maintainer-decision items | #1181, #1195 | Blocked on a maintainer ruling; nothing to implement until it lands. |
| Research-report series | (report-only issues from the triage set) | Findings/analysis deliverables with no code change requested. |

---

## Appendix

### Goal Mapping

| Goal | Statement | Sprints | Verification |
|------|-----------|---------|--------------|
| G-1 | The release path performs what it logs: real archival, honored `--pr`, reachable first version, self-identifying fossil worktrees | 1 | archive-gate + semver + worktree-staleness bats; BB dist-fresh gate; post-T1.1 check on this repo's real ledger |
| G-2 | No GNU-only assumption breaks a macOS operator; a failed optional runtime install never ships a partial mount | 2 | BSD shim suites with mandatory faithfulness controls; fresh-mount smoke |
| G-3 | No surface reports success for work that did not happen; fences and state readers resolve from any cwd | 3 | zero-work HALT tests; four-cwd hook resolution; DEGRADED marker round-trip; sanitizer spy |
| G-4 | Trust decisions honor the authoritative store and its revocations; every tripwire can actually see what it guards | 4 | paired bash/python security fixtures; positive-detection tripwire case; full E2E battery |

### Provenance

Ground truth: the 2026-07-30 issue triage over 61 open issues. Each task cites its verifying evidence in the task body — production run/job ids for #1234, live sandbox repros for #1211, #1235, #1234 and #1065 (real scanner and real ledger copies), jq/grep censuses for #1172 and #1065, and an explicit VERIFIED-BY-READING-CODE caveat plus a hand-substituted BSD repro for #1216, #1197, #1037 and #1232 (Linux host, no macOS lane). Partial refutations are recorded rather than hidden: #1211's primary diagnosis and #1197's exit-code claim were both wrong on main, and #1206's apparent CHANGELOG fix (`#257`, `#258`) is an EARLIER, different fix that leaves the ordering defect untouched.

### Out-of-cycle follow-ups (bead at Task 4.2, do NOT implement here)

1. Ledger data hygiene: reconcile 54 stale `active` entries and 46 legacy string-sprint entries (#1234 split).
2. `#1233` repro 2: superseded-blocker HALT staleness (needs a non-ledger signal).
3. Upstream `0xHoneyJar/loa-aleph`: relax the installer overlap guard for nested-bundle layouts, then re-ingest and re-pin (#1232 split).
4. Upstream Anthropic: hook-cwd/project-root resolution for worktrees under `.claude/worktrees/` (#1172 split).
5. Lint beads: `tools/check-no-gnu-regex-shorthand.sh` (#1216 split) and `tools/check-no-raw-realpath-m.sh` (#1197 split).
6. Convert the 34 marker-suppressed yq swallow sites under the #1025 sweep (#1065 split).
7. Re-file `#1211` sub-finding (d) with an explicit absent-store policy.
8. CI: a macOS bats lane so BSD behavior is verified on a real host rather than by shim (#1037 split).
