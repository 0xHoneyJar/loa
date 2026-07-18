# Artifact Templates — Usage Rules

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../../decisions/0003-architecture-build-kit-implementation.md).
> These are the copy-into-a-run templates for every artifact in
> [`../03-artifact-contracts.md`](../03-artifact-contracts.md). They remain
> **provisional shapes** (no schema freeze); the golden run exercises the
> current forms, and future fixture evidence may amend them in lockstep.

## How to use

1. Copy the relevant template block into the run directory at the path given
   in its header. Fill every `⟨angle-bracket⟩` slot. Delete instructional
   comments (lines starting `<!--`).
2. **Never reorder or rename table columns.** The checker specs
   ([`../checker-spec/`](../checker-spec/)) parse by header name and column
   count; renderings into the Précis depend on the exact shapes below.
3. **Ledger files are append-over-mutate.** Corrections are new rows marked in
   the `status` column (`active` → `superseded-by:<row-ref>`), never edits to
   old rows. Where a table has no `status` column, it is not a correctable
   ledger (e.g. the run manifest's fixed fields) — get it right or supersede
   the whole file with a dated note.
4. **Example rows** in each template (marked `<!-- example -->`) show the
   expected texture using the same synthetic Freeside frame as the accepted
   fixtures. Delete them when copying.
5. **Forbidden-token discipline:** any copy of these templates that lands
   under `docs/fixtures/**` (the golden run fixture) inherits the checker's
   absolute forbidden-token rule. Inside run artifacts, always write "stage"
   (S0–S13), never the P-word used for roadmap groupings; never name the
   deferred business-intelligence consumer. The templates below are already
   clean; keep them that way when filling.
6. IDs follow [`../02-system-architecture.md`](../02-system-architecture.md)
   §2: zero-padded (`PKT-0042`), assigned once, never reused, hash-anchored.

## Index

| File | Templates inside | Run-directory target |
|------|------------------|----------------------|
| [`01-run-control.md`](01-run-control.md) | run manifest · run log · kernel report | `run-manifest.md`, `run-log.md`, `verification/kernel-report.md` |
| [`02-corpus-intake.md`](02-corpus-intake.md) | corpus manifest · extraction criteria | `corpus/manifest.md`, `ledgers/extraction-criteria.md` |
| [`03-extraction-claims.md`](03-extraction-claims.md) | packet index · claim inventory · disposition ledger · merge map | `ledgers/…` |
| [`04-evidence-boundaries.md`](04-evidence-boundaries.md) | evidence roles · negative boundaries · unresolved queue · external referents | `ledgers/…` |
| [`05-clustering-routing.md`](05-clustering-routing.md) | pre-cluster tags · route-cluster card · routing log | `clusters/…` |
| [`06-arms-synthesis.md`](06-arms-synthesis.md) | stress-test matrix · reconciliation table · cluster synthesis · Précis assembly map | `arms/…`, `synthesis/…` |
| [`07-verification.md`](07-verification.md) | verifier verdict · sampling record | `verification/harness/…` |
| [`08-projection.md`](08-projection.md) | projection commission · selection ledger · projection trace | `projections/…` |

## Rendering into the Précis (critical)

The Précis keeps the **accepted envelope shapes** — the ledgers are richer.
The assembly map template (in `06-arms-synthesis.md`) fixes the projections:

- Précis §4 renders **exactly 4 columns** from the claim inventory:
  `claim_id | normalized claim | source(s) | disposition` — extra ledger
  columns (packets, claim type, rationale, status) never appear in §4.
- Précis §5 renders `disposition | count | claim_ids` from the disposition
  ledger; §11 renders `canonical | absorbs | basis | provenance retained`
  from the merge map.
- Counts in rendered sections are recomputed at assembly from `active` rows
  only, never copied from stale totals.
