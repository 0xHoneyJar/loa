# Beads sweep report — cycle-133 Sprint 275 (FR-13 / C-13)

**Frozen inventory:** 329 open beads at 2026-10-24T13:21Z (`inventory.jsonl`, sha256 `667765512a5c34551c83822538066e7a9fa5abc313d5c7cc32ea78223331562f`), the cycle's 26 Tier 1 beads excluded (all already closed with commit and test; bd-kddde closed last with its remainder split to bd-mopz7). Nine batches of up to 40 beads in id order.
**First pass:** nine read-only Explore agents (Opus 5.5; brief `~/.cache/loa/cycle-133/briefs/sweep-explore.md`), one manifest each; `sweep-apply.sh --validate`: VALID, a complete partition (no duplicate, unknown, missing or conflicting id; every closure's evidence resolves to a commit, a PR number in the log, or a path at HEAD; every closure bead still open).
**Lead triage before the sample:** one low-confidence closure demoted to kept (bd-2255); four completed sprint items promoted from kept to closed-implemented with ledger evidence (bd-a3t83, bd-6cvom, bd-s9xg5, bd-x8xim); Sprint 275's own seven beads (the epic bd-3rrwz and tasks 4.1–4.E2E) marked pulled-in (`sprint:275`) so the sweep does not label the active sprint as backlog.
**Sample (10 %, seed 20261023):** 18 of 180 proposed closures (`sample.jsonl`); a second read-only Explore (`sample-verify.first.jsonl`) confirmed 17 and disagreed on one — bd-a4td (batch 03, proposed closed-obsolete): the evidence commit implements part of the ask (RANGE_CAP 25, multi-site anchors, same-scope rule) and the remainder (must_match crediting, a recorded miss reason per uncredited defect) is open. Per the rule the batch went back: a fresh Explore re-verified every closure row of batch 03 from scratch with the stricter standard (`manifest-03.first-pass.jsonl` kept beside the rewritten `manifests/manifest-03.jsonl`): bd-a4td → kept, and the two sprint epics the lead had promoted (bd-a3t83, bd-6cvom) → kept because each still has open children (deferred follow-ups labelled with the epic); the other 14 closures of the batch were confirmed. The lead accepted the re-sweep.
**Apply:** `sweep-apply.sh --apply --sprint 275 --review-by 2027-01-31` in three runs (the first stopped after 7 rows on a tracker refusal — `br close` refuses a bead blocked by an open dependency — which became the per-row robustness fix `f48de024e`; the second surfaced the re-run validity fix `3deb39cd5`; both covered by SW-7/SW-10). Two epics `br` refused for open children (bd-1rhd, bd-3o53) were demoted to kept by the lead and applied in the third run. `applied.jsonl` holds every mutation (append-only, reversible by hand with `br reopen` / `br label remove`).

## The five-category table

| category | beads | of which opened during cycle-133 | applied | action |
|---|---|---|---|---|
| closed-implemented | 166 | 8 | 165 | `br close --reason "implemented: <evidence>"` |
| closed-obsolete | 9 | 1 | 9 | `br close --reason "obsolete: <evidence>"` |
| kept | 147 | 22 | 147 | label `backlog-2026-10` + status comment, review-by 2027-01-31 |
| pulled-in | 7 | 7 | 7 | label `sprint:275` + comment (the sprint's own beads) |
| **total (the frozen inventory)** | **329** | **38** | 328 | |

skipped-blocked: bd-16wg (blocked by a bead this sweep keeps; left open, no label)

Open beads: 329 before the sweep → 155 after (the 155 = 147 kept + 7 pulled-in + bd-16wg skipped-blocked). "Opened during cycle-133" counts beads created on or after 2026-10-23 (38 in the frozen inventory; the ledger's cycle start).

## Sample result

17 of 18 confirmed; 1 disagreement (bd-a4td) → batch 03 fully re-verified (3 of its 17 closures demoted). No closure outside the sample was changed by the second pass except through that re-sweep.

## Files

`inventory.jsonl`, `inventory.sha256`, `INVENTORY.md`, `tier1-excluded.txt`, `batches/batch-00…08.jsonl`, `manifests/manifest-00…08.jsonl` (final), `manifest-03.first-pass.jsonl`, `sample.jsonl`, `sample-verify.first.jsonl`, `VALIDATE.txt`, `APPLY.txt`, `applied.jsonl`, `TABLE.md`, this report. The a2a directory is gitignored in the working repository; the record branch carries it (`record-branch.sh`).
