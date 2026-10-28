# Sprint 281 (cycle-137 sprint-1) — goal validation (Task 1.E2E)

**Written:** 2026-10-28 by the lead. **Final Sprint 1 head:** 747b5db0d (code of the loop = c0d41f5e3; the review fix 74790b2d1 → d005a771a and the audit fix 227da3249 → 747b5db0d touch `tests/unit/perf-spawn-budget.bats` only). Measurement protocol for every number: `hyperfine -N -i --warmup 3 --runs 10`, mean ± σ, host `fukuoka` (Linux 6.16, bash 5.2, mawk 1.3.4, jq 1.7, mikefarah yq 4.44.1, Python 3.13), serial on the idle host unless stated.

## G-1 — review `All good` and audit `APPROVED` on the loop

| Gate | File | Verdict | `reviewed_head` | verdict-derive |
|---|---|---|---|---|
| Review (Task 1.1) | `a2a/sprint-281/engineer-feedback.md` | `All good` — 0 critical, 0 high, 2 medium, 5 low, 0 excluded | d005a771a | `CONSISTENT: gate=review verdict=APPROVED` |
| Audit (Task 1.2) | `a2a/sprint-281/auditor-sprint-feedback.md` | `APPROVED - LET'S FUCKING GO` — 0 critical, 0 high, 1 medium (awk sanitiser portability → Sprint 2 Task 2.1), 3 low (tracer ambient environment, fixed in-sprint; KF row cap → bd-4sikh; karpathy trajectory symlink → bd-kdzc3), excluded 0, excluded_confirmed 0 | 747b5db0d | `CONSISTENT: gate=audit verdict=APPROVED` (with `--review-file engineer-feedback.md`) |
| Marker | `a2a/sprint-281/COMPLETED` | written 2026-10-28T03:35Z (final head 747b5db0d) | — | — |
| Ledger | `grimoires/loa/ledger.json` sprint 281 | `completed` 2026-10-28T03:24:38Z (`update_sprint_status 281 completed`; ledger valid) | — | — |

Dissent envelopes: `adversarial-review.json` (review: gpt-5.5-pro answered via codex-headless + claude-headless, 2/2 voices, consensus APPROVED, 6 advisories, 0 rejected) and `adversarial-audit.json` (audit: gpt-5.5-pro answered via codex-headless + claude-headless, 2/2 voices, consensus APPROVED, 3 LOW, 0 rejected, locality not degraded).

Gate fixes landed red-first inside the sprint (both on `tests/unit/perf-spawn-budget.bats` only; no System Zone file changed after c0d41f5e3). Review: 74790b2d1 (case (g): the spawn-budget tracer must count spawns inside stderr-redirected functions, sourced libs and child shells — fails on the old tracer, EXT=1 of 4) → d005a771a (BASH_XTRACEFD + SHELLOPTS=xtrace tracer, wider tool regex, +3 headroom floor, live-config assertion, budgets re-measured three times: implement-gate 113 → 127 trace lines, external-tool lines unchanged; 7/7). Audit: 227da3249 (case (h): an exported canary reaches the traced target and its trace — fails on the old tracer) → 747b5db0d (`env -i` allowlisted environment: PATH, fixture HOME and TMPDIR, LANG=C, the explicit seams; the live `.loa.config.yaml`, `.run/` and `grimoires/` paths refused as command arguments; budgets re-measured three times: kf-surface 34 → 36 trace lines, the rest unchanged; 8/8).

## G-3 — the loop's gains hold; guard green

`final-table.tsv` (`evidence/final-table.tsv`) is the serial idle-host re-baseline on c0d41f5e3; no code path changed afterwards (the fix is test-only), so it stands as the final-head measurement. Rule: no touched row above 110 % of its final-table mean — trivially met (the table is the measurement). Untouched rows recorded for completeness.

| Command | Baseline ms | Final ms | Final / baseline | Touched by pass |
|---|---:|---:|---:|---|
| repo-map-gen (write) | 4658.4 | 1218.5 | 0.26 | 1, 2, 3, 20 |
| grimoire-index (write) | 1818.9 | 826.2 | 0.45 | 4, 5, 8 |
| loa-status | 899.0 | 817.5 | 0.91 | 13, 14 |
| beads-health --json | 207.6 | 225.9 | 1.09 | untouched (host noise) |
| upgrade-health-check (Setup) | 214.8 | 211.3 | 0.98 | 16 |
| cheval --help | 128.6 | 122.1 | 0.95 | 17 |
| SessionStart kf-surface | 487.6 | 15.4 | 0.03 | 6, 8 |
| SessionStart run-state-surface | 29.7 | 17.6 | 0.59 | 11 |
| SessionStart context-class | 24.2 | 24.7 | 1.02 | untouched |
| SessionStart decisions-surface | 17.1 | 17.0 | 0.99 | untouched |
| PreToolUse implement-gate | 35.4 | 23.1 | 0.65 | 8, 9 |
| PreToolUse notes-size-guard | 21.5 | 20.1 | 0.93 | 10 |
| PreToolUse zone-write-guard | 12.3 | 13.9 | 1.13 | untouched |
| PreToolUse block-destructive-bash | 15.5 | 18.5 | 1.19 | untouched |
| PostToolUse karpathy | 96.0 | 80.5 | 0.84 | 7, 19 |
| Stop run-mode-stop-guard | 23.6 | 13.6 | 0.58 | 18 |

Guard: `npx --no-install bats tests/unit/perf-spawn-budget.bats` on 747b5db0d → 1..8 all ok (budgets, 3 identical measurement runs: kf-surface 36/2, grimoire-index --tsv 96/11, implement-gate 127/5, notes-size-guard 26/3, compat-lib source 15/0, stop-guard 78/2). `check-loa.sh` → All checks passed; `repo-map-gen.sh --validate` → consistent; `tools/check-no-raw-sha256sum.sh` OK; `tools/check-no-swallowed-jq.sh --quiet` rc 0.

## G-4 — full suite green modulo the three KF-034 tests; companion file serial

| Run | Head | Result | File |
|---|---|---|---|
| Full `tests/unit` TAP (pre-loop baseline) | main 9e23cbf84 | 7224 tests, 7221 ok, 133 skipped, 3 not ok | `evidence/tap/unit-baseline-main-9e23cbf84.tap` |
| Full `tests/unit` TAP (loop head) | c0d41f5e3 | 7224 tests, 7220 ok, 133 skipped (same names), 4 not ok | `evidence/tap/unit-final-c0d41f5e3.tap` |
| Covering suites for every touched file (18 files) | d005a771a | 341/341 ok | `evidence/tap/covering-d005a771a.tap` |
| `adversarial-review-companion.bats` serial whole-file, `bats -T` | c0d41f5e3 code (branch e5df3b589) | 284/284 ok, wall 872 s, started 2026-10-28T02:40:26Z | `evidence/tap/companion-serial-c0d41f5e3.tap` |

The four `not ok` on c0d41f5e3: `semver evidence: unknown squash subject refuses silent patch`, `semver evidence: classification records its source and matching commit`, `semver evidence: breaking body retains the classifying commit identity` (the R-4 allowed-failure list; KF-034 host `tag.gpgsign`; identical three on main) and CMP-37 — load-induced: a reviewer's bats job overlapped that run, and the whole-file serial run passes. No new skips (133 = 133, identical names).

## External, unversioned artefacts (sha256; also in `a2a/sprint-282/prep.md`)

| sha256 | Path |
|---|---|
| 0b464ff8f263f78612e0069356a0b13252d61f6960bcdbd224941e63563ad0c0 | `~/.cache/loa/cycle-135/ship/ship-1-merge.sh` |
| 56ba02434b757f6e07f2e021b3c56223faf292b9b9bf11cb0d3fd04bef0ffe4a | `~/.cache/loa/cycle-135/ship/ship-2-record.sh` |
| ca118babc5a7674a53baa5d4adeb4936c4e9aba68a93cf72517f1fe180569a4e | `~/.cache/loa/cycle-135/ship/ship-3-archive.sh` |
| 45645a45ac2d2044196eae585c2f5a84c535d050b4a760988b6ed3f348f044f9 | `~/.cache/loa/cycle-135/ship/ship-3b-archive-pr.sh` |
| 56ddd39f6c27624f48dd296e391fff13cda14d2a1b339c7cb33026a5cad8d84d | `~/.cache/loa/cycle-135/ship/ship-3c-archive-merge.sh` |
| cb4c5a923708820ded9658a205ce859d33034d34521ad53d0494e21e869414d1 | `~/.cache/loa/cycle-135/ship/ship-4-close.sh` |
| d764c62ccbc28c1f3f37e444f68c3b6f4bdfcbbf0c4393cb8ebcdbdb84ffcdf1 | `~/.cache/loa/eso-loop/rebaseline.sh` (= `evidence/rebaseline.sh`) |

## Portability note carried to Sprint 2 (review observation 1 / DISS-C-006)

BWK one-true-awk: UNVERIFIED on this host — not installed (`/usr/bin/nawk` is mawk), no yacc/bison to build it, and `https://github.com/onetrue-awk/awk` was unreachable from here ("Repository not found") at 2026-10-28T03:00Z. mawk 1.3.4 and busybox awk run both KF awk programs identically (pass-4 / pass-6 reviewer fixtures). Sprint 2 Task 2.1 keeps the matrix at "every awk present, absent ones named" and adds BWK awk if it can be obtained; the byte-cap contract decision is recorded there.

## Meter checkpoint

`.run/cost-ledger.jsonl` real charges ≈ 0 (subscription routes); dissent envelopes report `cost_usd: 0`. Spend cap USD 30: untouched.
