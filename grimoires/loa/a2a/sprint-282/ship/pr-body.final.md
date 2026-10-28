## cycle-137 — performance follow-ups (Sprints 281 and 282) · releases `v2.0.0-rc.9`

Branch `feature/cycle-137-performance` from `main` 9e23cbf84. Two sprints, one PR (DEC-0960 pattern). The release predicate R-1 … R-8 lives in `grimoires/loa/prd.md` § Scope; this body is its evidence index.

### Sprint 281 (sprint-1) — formal gates on the 22-pass extreme-software-optimization loop

The loop (2026-10-27/28) is 20 commits 395795939 … c0d41f5e3 over 18 System Zone files, one new test file and three bats helpers; every pass profiled first, byte-identical old-vs-new on golden and adversarial fixtures, Opus-reviewed, re-verified by the orchestrator (`grimoires/loa/reports/perf/eso-loop-2026-10-27.md`; `.skill-loop-progress.md` § LOOP 2). Headline numbers (hyperfine 2.0, `-N`, host fukuoka, serial idle): repo-map-gen 4658 → 1219 ms, grimoire-index 1819 → 826 ms, SessionStart kf-surface 488 → 15 ms, Write/Edit PreToolUse chain ≈ 78 → 62 ms, Stop guard 24 → 14 ms. Guard: `tests/unit/perf-spawn-budget.bats`.

| Gate | Verdict | `reviewed_head` | Dissent |
|---|---|---|---|
| `/review-sprint` | All good — 0 critical, 0 high, 2 medium, 5 low | d005a771a | gpt-5.5-pro (via codex-headless) + claude-headless, 2/2, consensus APPROVED, 6 advisories, 0 rejected |
| `/audit-sprint` | APPROVED — 0/0/1/3 | 747b5db0d | 2/2, consensus APPROVED, 3 low, 0 rejected, not degraded |

Gate fixes (test-only, red-first): 74790b2d1 → d005a771a (the spawn-budget tracer now counts spawns behind stderr redirects and in child shells: `BASH_XTRACEFD` + `SHELLOPTS=xtrace`; wider tool regex; +3 headroom floor); 227da3249 → 747b5db0d (traced hooks run under an explicit `env -i` allowlist; live `.loa.config.yaml` / `.run/` / `grimoires/` paths refused as command arguments). G-4: full `tests/unit` on c0d41f5e3 — 7224 tests, only the three KF-034 `semver evidence` reds (identical on `main`), no new skips; `adversarial-review-companion.bats` serial whole-file 284/284 in 872 s. Evidence: `grimoires/loa/a2a/sprint-281/` (record branch).

### Sprint 282 (sprint-2) — the six follow-up beads

| Bead | Change | Red → fix | Evidence |
|---|---|---|---|
| bd-atk7q (FR-2) | KF parser shape C (`**Label**: value`) for `Symptom` / `Recurrence count` in the SessionStart hook and grimoire-index; `## KF-` resets | 980013b87 → 2944f4b55 | 9 red cases; live file byte-identical; mawk + busybox identical; BWK UNVERIFIED (bd-aceil) |
| bd-1mfm7 (FR-5) | grimoire-index decisions cache under `.run/perf-cache` (content-keyed, awk-validated, uid-owned non-group-writable dir; D-5.3: a uid-owned group-writable dir is tightened `chmod go-w`) | 87f5ee362 → 937b87ee0; 3d8e520a2 → e5f751ac0 | 46 cases incl. symlink / foreign / FIFO / hard link; warm 826 → 196 ms live; cold +24 ms |
| bd-gv5jf (FR-3) | loa-status: one yq for the six ceiling reads; agy opt-in memo keyed on `dev:ino:size:mtime:ctime` + `PATH` with the current-second rule (mtime + ctime, one-second margin) | 462c8b0dd → 67276f62a; 92dfbbc34 → 268bc2f1b; review fixes 57e38f8c0 → c31b9e03c, c69059546 → c31089280 | parity loa-status / run-preflight identical; −104 ms; AGC-27 … AGC-36 |
| bd-h5tcn (FR-4) | profile-lib `cached_keys` (karpathy `diff_lines_per_task` served from the cache, no yq on the warm path) | cbdb5ef96 → cb46eabac | PL-20 … PL-25; spawn-budget karpathy target; hook parity over three payloads |
| bd-wctli (FR-6) | test-suite runtime: destructive-bash corpus once per file (`setup_file`), companion holds 240 s (CMP-55 pinned 300) | 55f82c534 (single, exempt) | TAP set identical ×7; negative control per hold; floor 667 s median (DEC-1130) |
| bd-09z1i (FR-7) | `audit-envelope.sh verify-chains` / `audit_verify_chains`: N chains in one process, fail-closed per index; loa-status one call | d1e49e920 → bf96f91cb | 18 bats + 15 pytest; six store-mutation schedules = two oracles; protected functions untouched |
| audit strengthening | AGC-29 / AGC-31 prove a populated memo before each mutation; FIFO + hard-link cache cases | 03f910129 (test-only) | 36/36, 48/48 |

| Gate | Verdict | `reviewed_head` | Dissent |
|---|---|---|---|
| `/review-sprint` | All good — 0 critical, 0 high, 1 medium, 5 low (r1 CHANGES_REQUIRED → r2 CHANGES_REQUIRED → r3 All good → r4 verify-only) | 03f910129 | r1: gpt-5.5-pro (codex-headless), companion timed out (KF-037 class) — 1 BLOCKING fixed; r2: 2/2 consensus — 2 BLOCKING + 4 advisories fixed; r3/r4: lead-only (DEC-1134); 0 rejected |
| `/audit-sprint` | APPROVED — 0/0/2/3 (MED-001 pre-existing profile-lib cache → bd-j34zb; MED-002 fixed 03f910129) | 03f910129 | 2/2 (codex-headless + claude-headless), status clean, 8 companion findings triaged (2 refuted by probe), 0 rejected, not degraded |

G-4 (R-4): full `tests/unit` on the final head 03f910129 — 7315 planned, 7312 ok, 3 not ok = exactly the KF-034 `semver evidence` allowed-failure list (identical on `main`), 135 skipped with skip names identical to the 8d63417b0 run (which was 7309 / 7306 / 3 / 135; the two skips new since Sprint 281 are this sprint's host-conditional awk tests, DEC-1135). TAP copies: `a2a/sprint-282/evidence/tap/` (record branch). Shell Tests on the PR head: green (46/46 check runs pass).

### Measurement protocol

`hyperfine -N -i --warmup 3 --runs 10`, mean ± σ, old and new mirrors in the same session on the idle host `fukuoka` (Linux 6.16, bash 5.2, mawk 1.3.4, jq 1.7, mikefarah yq 4.44.1, Python 3.13), cache state stated per number; mirrors in REAL directories. Spawn counts: `PS4='+' bash -x` through `BASH_XTRACEFD` with `SHELLOPTS=xtrace`.

### Decisions taken on the operator's behalf

DEC-1109 … DEC-1138 (30 rows) (this branch) plus the ship-time rows DEC-1139 (Bridgebuilder degraded exit) and DEC-1140 (loaded re-baseline caveat) and the KF-037 recurrence, which ride the archive PR — all `proposed`; confirm with `/decisions confirm --cycle cycle-137-performance-followups --all`. Classes per sprint.md § Decision-row classes: every row is class S (self-confirmable under the operator's instruction of 2026-10-28); no class-H row was written.

### Release

CHANGELOG `[Unreleased]` → `## [2.0.0-rc.9] — 2026-10-28 — Performance follow-ups (release candidate)`; `.loa-version.json` / `CLAUDE.loa.md` header / README pin at `2.0.0-rc.9`; release notes `grimoires/loa/reports/release-notes-2.0.0-rc.9.md`. After merge: the post-merge candidate is published from a non-shallow clone with the lead-recomputed digest (R-6), the publish summary (`a2a/sprint-282/publish-summary.md`, R-7), tag identity and an install smoke test (R-8); the written rollback is in the sprint plan § Ship S-9.

### Bridgebuilder

Round 1 on 3215c141f (`BRIDGEBUILDER_MODEL=codex-headless`, generated and planning files excluded): COMMENT, degraded 1/2 (anthropic/claude-headless timed out under host load, KF-037 class); 3 findings — R001 refuted (jq `as` binding; INDEX.md intro present), R002 confirmed pre-existing → bd-3qed8 (waived, no in-tree multi-tool call), R003 praise; triage comment on the PR. Round 2 outcome: COMMENT, degraded 1/2 again (anthropic voice PROVIDER_UNAVAILABLE under the same host load; KF-037 recurrence 13); 3 findings — R-001 BSD byte-vs-character cap confirmed pre-existing → bd-aceil (Sprint 281 MED-001), R-002 sentinel collision confirmed pre-existing → bd-y5fy4, R-003 praise; triage comment on the PR. No blocking finding after two rounds → the plan's degraded exit (class S, DEC-1139).

### Beads

Sprint 281: bd-520lp bd-4wpi0 bd-0qnop bd-0zfjg closed; follow-ups bd-0h7kq bd-3qed8 bd-4sikh bd-kdzc3. Sprint 282: bd-atk7q bd-gv5jf bd-h5tcn bd-1mfm7 bd-wctli bd-09z1i closed provisionally (updated at ship-4 with the merged sha); follow-ups bd-20bh1 (zone-write-guard umask), bd-z6gxn (san C1), bd-aceil (BWK awk), bd-rq6gk (CMP-55 reap assertion), bd-5v1oa (warm-path spawn budget), bd-j34zb (profile-lib cache trust boundary), bd-hyah6 (absent chain state), bd-7utms (floor descendant clause), bd-yos4s (karpathy seam gate). Known failures: KF-005 recurrence (beads `--parent`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
