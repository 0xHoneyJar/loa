# Templates 06 — Arms, Synthesis, Précis Assembly

## T6.1 Stress-test matrix → `runs/<run-id>/arms/stress-test-matrix.md`

```markdown
# Stress-Test Matrix — ⟨RUN-slug⟩

## Stress-test matrix
| stm_id | adversarial pressure | source refs | candidate claim IDs | risk if handled badly | correct handling | resolved at |
|--------|---------------------|-------------|---------------------|----------------------|------------------|-------------|

## Evidence-removal rows  <!-- one per load-bearing edge in adversarial-weighted clusters -->
| stm_id | claim_id | removed source | declared effect | attack outcome | consequence |
|--------|----------|----------------|-----------------|----------------|-------------|
```

Rules: the seven slice-2 risk families (silent disappearance, lazy merge,
false certainty, unsupported exclusion, projection leakage, duplicate
conviction, contradiction hidden by synthesis) each appear in ≥1 row;
`resolved at` points at the run artifact (ledger row / section), never at
prose reassurance; `attack outcome` = `effect-held` |
`effect-wrong:⟨observed⟩` — a wrong effect forces a superseding evidence-role
row and is listed in `consequence`.

<!-- example -->
| STM-8 | remove SRC-104 from CC-104 | CC-104 | SRC-104 | confidence-decreases | effect-wrong: claim rests entirely on SRC-104; SRC-101/102 are restatements | evidence-roles superseded: SRC-104 → downgrades-to-unresolved; CC-104 confidence note added |

## T6.2 Reconciliation table (convergent arm; shape UNVALIDATED) → `runs/<run-id>/arms/reconciliations/RC-⟨NN⟩.md`

```markdown
# Reconciliation — RC-⟨NN⟩ against ⟨REF-…⟩
<!-- This arm shape has no replay case yet. Expect this template to be
     renamed by the convergent golden-corpus slice. Manifest must carry the
     unvalidated-machinery notice when this file exists. -->
| claim_id | referent (REF/SRC) | relation | note | consequence |
|----------|--------------------|----------|------|-------------|
```

`relation`: `agrees` | `conflicts` | `extends` | `out-of-scope`. Rules: rows
only against `supplied` referents; a `conflicts` row never edits the claim —
it spawns an unresolved-queue entry or an authority question; `agrees` rows
get a refuter pass (agreement is the easy lie).

## T6.3 Cluster synthesis → `runs/<run-id>/synthesis/cluster-synthesis.md`

```markdown
# Cluster Synthesis — ⟨RUN-slug⟩
<!-- Presentation compression only. Every claim keeps its inventory row.
     Every claim ID typed here must exist; every sentence must be licensed
     by the cited claims' dispositions. -->

## ⟨Cluster theme 1 (RC-…)⟩
⟨Prose grouped by cluster: carried spine first, then merged support, then
what stays open (deferred/unresolved, by ID), then context (backgrounded).⟩

## Grouped-out material
⟨One paragraph naming the classes grouped out of the narrative (e.g.
non-load-bearing cosmetics) with the rule that they remain in §4.⟩
```

## T6.4 Précis assembly map → `runs/<run-id>/synthesis/precis-assembly-map.md`

```markdown
# Précis Assembly Map — ⟨RUN-slug⟩
<!-- The compilation contract for S11. One row per envelope field. -->
| § | envelope field | assembled from | transform |
|---|----------------|----------------|-----------|
| 1 | Corpus scope | corpus/manifest.md ## Scope | verbatim + instance note |
| 2 | Source inventory | corpus manifest inventory | project columns: source_id, kind, locus |
| 3 | Extraction method / inclusion criteria | ledgers/extraction-criteria.md | summarize criteria + exclusion classes; cite supersessions |
| 4 | Candidate-claim inventory | ledgers/claim-inventory.md | ACTIVE rows; project to 4 columns (id, claim, sources, disposition) |
| 5 | Disposition ledger summary | ledgers/disposition-ledger.md | verbatim table |
| 6 | Carried claims | inventory (carried) | id + one-line elaboration each |
| 7 | Merged claims | merge-map | prose per canonical |
| 8 | Deferred claims | unresolved-queue (deferred) | prose per claim |
| 9 | Excluded-with-reason | inventory + rationale | prose per claim, reason verbatim |
| 10 | Backgrounded | inventory (backgrounded) | prose per claim |
| 11 | Duplicate/merge map | merge-map | project: canonical, absorbs, basis, provenance retained |
| 12 | Do-not-use / negative boundaries | negative-boundaries | prose per boundary |
| (matrix) | Stress-test matrix (between §12 and §13) | arms/stress-test-matrix.md | STM table verbatim |
| 13 | Cluster synthesis | synthesis/cluster-synthesis.md | verbatim |
| 14 | Unresolved claims / questions | unresolved-queue (unresolved) | prose per claim |
| 15 | Consumer-deferred projection notes | route cards + commission-free speculation rules | name what consumers COULD do; generate nothing |
| 16 | Verification summary | kernel-report + harness reports + sampling record | counts, rates, what was and was not checked |
| 17 | Known incompleteness / limits | manifest notices + taints + sampling record | every taint, every unvalidated arm, every sparsity/sampling honesty item |
```

Rules: any information a section needs that no ledger holds is an upstream
defect — fix the ledger, re-assemble; the map itself is copied into each run
so per-run deviations are visible diffs.
