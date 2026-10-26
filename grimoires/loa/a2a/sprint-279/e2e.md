# sprint-279 (cycle-135 Sprint 1) — goal validation (Task 1.E2E)

Head at the gates: `b02459e5a` on `feature/cycle-135-review-coverage`. Rows marked *pending* are completed at ship time and updated below.

| Goal | Criterion (sprint.md § Success metrics) | Evidence | Status |
|---|---|---|---|
| G-1 | 5 of 5 beads closed with commit and test | bd-ow72o, bd-i4fyw, bd-w5pd9, bd-nr5i6, bd-oglcu closed at the sprint close, each close reason naming the fix commit and the test file (`beads-map.txt`; `reviewer.md` § Commits + § Round 1) | *pending the close step* |
| G-2 | the matcher fixtures pass in both directions and with the native glob disabled | `loa-detection.test.ts` + `truncation.test.ts` (A: 279 cases green at `8d22e449a`): segment-anchored names (`PROCESS.md` ⇢ `docs/PROCESS.md`, not `MYPROCESS.md` / `PROCESS.md.old`; `a/b` ⇢ `a/b/c`, not `x/a/b`), floating slashless wildcards, dot-agnostic classes; there is no native path any more — `path.matchesGlob` and the Node < 22 fallback are removed, so `{ native: false }` is the only matcher (DEC-1026); Node 20 and 22 agree by construction | met |
| G-3 | the protected-kept fixture and rendering pass; both prepare jobs skip `housekeeping` in the guard tests; the next live housekeeping merge runs no prepare job | pipeline bats re-run at the shipped head `f41f58adf`: `classify-merge-pr.bats` 34/34, `post-merge-workflow-guards.bats` 8/8, `post-merge-orchestrator-type.bats` 2/2; protected-kept fixture + coverage rendering (`paged-fetch-coverage.test.ts`, `truncation.test.ts` `partitionUserExclusions` cases, lead integration check through dist in `reviewer.md` § E2E); PMWG-T1…T8 (shell mirror over the type × PR matrix, yq parse, actionlint rc 0), HK-T1/T2, PMOT-T1/T2 all green; live confirmation on the first housekeeping merge after this PR (the archive PR of this cycle) | met in tests; live confirmation *pending the archive merge* |
| G-4 | the content-fetch fixtures pass; the Q-1 probe recorded | `paged-fetch-contents.test.ts` + `github-cli-contents.test.ts` (B: 46 cases green at `04b552529`: budget / bytes-ahead / aborted / too_large / binary / deadline / cap / envelope errors); Q-1 live read-only probe through the built adapter: `getFileContent('0xHoneyJar','loa','README.md', <main sha>, 512000)` → `{ kind: "text", bytes: 23632 }`, bounded to 1000 → `too_large` (one call, `reviewer.md` § E2E) | met |
| G-5 | every check run green on the merged head; three consecutive green `npm test` runs under load; one PR, one non-degraded Bridgebuilder verdict; cycle spend ≤ USD 40 | three consecutive `npm test` runs while the CI mirror loaded the host: 1243/1243 ×3 (16 s / 15 s / 16 s; 1251/1251 at the final head); local CI mirror — see below; **one PR (#1302)**; **Bridgebuilder: two non-degraded rounds** (2/2 voices, 28 files reviewed, `reviewignore_source: base`), round 1 REQUEST_CHANGES → 3 fixed, round 2 REQUEST_CHANGES → 2 fixed, every remaining item documented or refuted with evidence in the triage comments; spend: cost-ledger rows price at 0 (subscription routes; no Bedrock fallback logged) — meter nominal under the USD 40 cap; check runs on the merged head — *pending merge* | met except the merged-head checks; *pending merge* |

## Local CI mirror (`s-tests.sh all`, from `998c3bd58`)

- unit suite: FAIL rc 1 (4506 s) — 7185 ok, 4 not ok: `PB-9 live gate` (Bridgebuilder `SKILL.md` 24,710 B > 16,384 B — real, fixed in `b6d0a07b4`, `prompt-budget.bats` 10/10 after) and `semver-evidence.bats` cases 2/3/5 (`git tag v1.0.0 … fatal: no tag message?` — host-local KF-034, recurrence 6; green in CI).
- evals 918 ok, scripts 399 ok, vitest 176 ok, analysis + gates PASS; pytest rc 1 — 2 host-local reds (`test_claude_headless_adapter.py` `test_minimal_command`, `test_complete_round_trip`: `CLAUDE_HEADLESS_BIN`, accepted class). Pipeline bats re-run at `f41f58adf`: 44/44.

## Ship (appended)

- Heads: gates at `b02459e5a`; PB-9 fix `b6d0a07b4`; close `f41f58adf` (PR #1302 opened); Bridgebuilder round-1 fixes `9c4f742a6` → `23f7d9319` → `57e64e152`; round-2 fixes `486b356f5` → `70444f0d2` → `1471861aa` (final head).
- *merge, record branch, archive: pending*
