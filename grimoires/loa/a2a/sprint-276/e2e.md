# Sprint 276 — goal validation (Task 1.E2E)

Written at the pre-merge gate (Task 1.12); the post-merge rows are filled after the merge, record and archive.

## G-1 — every in-scope bead closed with evidence

| Check | Evidence | Result |
|---|---|---|
| 9 beads closed, each close reason naming the commit and the test | bd-bex39, bd-k3dia, bd-htzy2, bd-kgfh5, bd-1br0v, bd-ruo5b, bd-kdk3l, bd-4pv1j, bd-hyx0n closed 2026-10-25 with "Fixed in cycle-134 Sprint 276 (landing 5fc05dc9, head c87cc20c): … Tests …" (`br show`); the nine task beads closed with the landing commit; open beads 156 → 152 | **MET** |

## G-2 — the validator is right in both directions

| Check | Evidence | Result |
|---|---|---|
| fixtures both ways | `took-effect-hooks.bats` (14: pass with k = 2 ≤ 2 triggers; k = 0 passes; unpinned group fails; non-multiple fails; k above triggers fails), `took-effect-transcripts.bats` (15: missing/empty/no init/no result/malformed/result-not-last/init-after-result/foreign session_id/symlink fail; complete passes), `took-effect-integrity.bats` (8) — 36 of 37 red before the patch, 37/37 after | **MET** |
| the retained smoke runs re-validate as pre-registered (D-4.3) | `regression.md`: both runs rc 1, failing sets unchanged; run 1 +34 → +35 with exactly `(g) transcript REVIEW: no result event`; `integrity_clean` passes as "record cross-checked against the pin" | **MET** (binding amended by DEC-0990) |

## G-3 — the post-merge pipeline is green on a push without a PR

| Check | Evidence | Result |
|---|---|---|
| classifier and guard fixtures | `classify-merge-pr.bats` KF063-T1 … T13 (ledger subject → other; cycle subject without a number → other; `(#345)` trailer; `(#0)`/`(#12a)`/`(#012)` → empty; `--pr-number` honoured; gh failure + trailer kept), `post-merge-workflow-guards.bats` PMWG-T1 … T4 | **MET** (fixtures) |
| live confirmation | the next rc publish's ledger push (recorded on KF-063 afterwards) | deferred by design |

## G-4 — one PR, one non-degraded Bridgebuilder verdict

| Check | Evidence | Result |
|---|---|---|
| the sprint PR's Bridgebuilder summary carries no `degraded_reason`; verdict = consensus block | round 1 (glob excludes) degraded: `incomplete_coverage` — the `**` glob skipped the `pinned/.claude/…` fixture files (bd-a8l0c) and `prd.md`/`sdd.md` were `no_patch`; round 2 (prefix excludes, 27 reviewable files): 2/2 voices, `degraded_reasons: []`, 18 findings (1 consensus, 4 disputed, 0 blocker), verdict REQUEST_CHANGES = the consensus block's; triage comment on PR #1296; five findings fixed in `5e3f44f5` (review/audit round-3 addenda), one already satisfied, the rest noted; no third round (DEC-1000, DEC-0999) | **MET** (non-degraded, trustworthy verdict; its findings acted on) |

## G-5 — green suites at no model spend

| Check | Evidence | Result |
|---|---|---|
| CI green on the head | pending (PR checks) | pending |
| cycle spend | the cost ledger prices the headless CLI hops (`pricing_source: cli_reported`): Flatline PRD/SDD/sprint reviews ≈ USD 8.8 (claude-headless) + codex voices, three dissent runs ≈ USD 6.4 + codex; codex total USD 3.38; Q-1 probe USD 0.05 → **USD 18.6** before the Bridgebuilder round. DEC-0969's USD 20 assumed those hops were subscription-free; see the cap amendment row (the operator-confirmed precedent was USD 100) | see the amendment |

## Spend

| Share | Spent (cost ledger, 2026-10-25) | Note |
|---|---|---|
| Flatline (3 reviews) | ≈ USD 11.6 (claude-headless ≈ 8.8 + codex ≈ 2.8) | priced by the meter as `cli_reported`; Flatline's own report said 0 cents |
| dissent (3 review runs) | ≈ USD 6.9 (claude-headless ≈ 6.4 + codex ≈ 0.5) | |
| Q-1 probe | USD 0.05 | Sonnet one-turn |
| Bridgebuilder | two rounds (round 1 degraded, round 2 non-degraded): meter-priced ≈ USD 16 (codex ≈ 7 + claude-headless ≈ 9; subscription-routed, no Bedrock fallback logged) | within the amended cap DEC-0999 |
| not the cycle's | USD 10.45 `claude-opus-5-5` rows tagged `judge-v2` / `blind-session cost.json` at 04:33–04:45Z and the stray `grimoires/loa/evals/judge-v2/` — another session's grader-validation runs on this host, excluded | |
