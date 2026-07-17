# Aleph Conformance Checkers

Primary entry points:

- `scripts/validate-core-boundary.ts`: repository inventory, adapter lifecycle,
  typed-reference, ownership, and immutable-bundle boundary validation.
- `scripts/validate-precis-fixtures.ts`: discovered-fixture dispatcher plus
  the accepted Slice 1/Slice 2 Précis checks.
- `scripts/validate-run.ts`: import-safe K2-K6 validator for run and run-lite
  directories.
- `scripts/test-conformance-mutations.ts`: temporary-copy fail-closed battery.
- `scripts/test-core-boundary-mutations.ts`: temporary-repository negative
  battery for classification, schema shape, ownership, foreign references and
  host requirements, and lifecycle, plus Core/host-only rebuild selectivity.

All five runtime surfaces use Node built-ins only, are local, and fail closed.
The development dependencies are the TypeScript compiler and Node type
definitions used by the static typecheck; there is no emitted build artifact.
All three validators are read-only over their target artifacts. The mutation
batteries write only disposable copies beneath the operating system's temporary
directory and never mutate repository state. The checkers prove
structural, accounting, hash, reference, state, taint, and projection-trace
invariants. They do not judge semantic truth or grant authority acceptance.

## How to run

```bash
npm install
npm run typecheck
node scripts/validate-core-boundary.ts
node scripts/validate-precis-fixtures.ts
node scripts/validate-run.ts --run docs/fixtures/run-slice-2
node scripts/test-conformance-mutations.ts
node scripts/test-core-boundary-mutations.ts
```

- Node 22.18 or newer executes the `.ts` files directly through native type
  stripping. Runtime validation uses Node built-ins only.
- `npm install` installs only the pinned development typechecking toolchain.
  `npm run typecheck` emits no files.
- The Core-boundary validator inventories tracked and nonignored untracked
  paths, and computes Core/checker/adapter payload, lock, and bundle digests.
- All three validation scripts read files only, write nothing, and mutate no repo
  state.
- The conformance mutation battery copies fixtures beneath the operating system's temporary
  directory, mutates only those copies, and removes its temporary root on exit.
- The Core-boundary mutation battery creates disposable local Git repositories
  beneath the operating system's temporary directory and never mutates this
  checkout.
- Exit code `0` = all checks pass; non-zero = at least one invariant failed
  (**fail-closed**). Prints a per-check PASS list and, on failure, a `FAIL …`
  line naming what failed and where.

All three validation scripts accept `--json` and `--root <dir>`;
`validate-run.ts` additionally requires `--run <path>` and optionally accepts
`--kind run|evidence-role|routed|projection`.

## What it proves

That the accepted Précis fixtures are not merely human-readable but carry
**mechanically checkable completeness/accounting invariants**:

1. **Fixture shape** — each fixture directory contains exactly `README.md`,
   `corpus.md`, `precis.md`, and is Markdown-only (no code/data/subdirs leak in).
2. **Absolute forbidden tokens** — zero occurrences of `Phase` or the deferred
   business-intelligence consumer's proper name anywhere under a fixture
   directory (hard, context-free zero-tolerance).
3. **Projection boundary** — the Précis does not *generate* a downstream
   projection. A line is flagged only when it pairs a projection noun
   (`PRD`, `GTM`, `market landscape`, `product spec`, `projection`, …) with a
   generation verb (`generate`, `produce`, `formalize`, `emit`, `ship`,
   `project into`, …) **and** carries no inline refusal/negation/hypothetical
   cue (`no`, `not`, `does not`, `could`, `none … generated`, `projection-neutral`,
   `out of scope`, …). Real-export markers (`ChatGPT said:`, citation tags) are
   also rejected.
4. **Schema wording** — `precis.md`/`README.md` must explicitly reject schema
   finality (`no schema freeze`, `not a final schema`, `accepted provisional v0
   envelope`, or `field structure is provisional`).
5. **Corpus input boundary** — `corpus.md` contains the expected source IDs
   (Slice 1: `SRC-001..003`; Slice 2: `SRC-101..104`) and **leaks no answer
   key**: no candidate-claim IDs (`CC-NNN`), no `STM-N`, no `candidate claim`,
   no `stress-test matrix`, no compound disposition labels
   (`excluded-with-reason`, `judged-non-load-bearing`), no `disposition:` label
   or disposition column, and no disposition-classification table row.
6. **v0 envelope** — all 17 numbered envelope sections are present in
   `precis.md`. Described as the *accepted provisional v0 envelope*, not a final
   schema.
7. **Candidate-claim inventory** — IDs are unique and match the expected set
   exactly (Slice 1: `CC-001..010`; Slice 2: `CC-101..114`); every claim has
   exactly one disposition drawn from the valid seven.
8. **Disposition coverage** — all seven dispositions
   (`carried`, `merged`, `deferred`, `excluded-with-reason`, `backgrounded`,
   `judged-non-load-bearing`, `unresolved`) appear at least once per fixture.
9. **Accounting** — inventory count equals the declared §5 ledger total
   (Slice 1: 10; Slice 2: 14); the ledger's per-disposition counts sum to the
   inventory count; and each declared per-disposition count equals the actual
   count parsed from the §4 inventory.
10. **Stress-test matrix** (Slice 2 only) — a clearly named `## Stress-test
    matrix` section exists, carrying rows `STM-1 … STM-7`.

## Cross-section consistency (Slice 4)

Slice 3 proved each section is **well-formed**. Slice 4 proves the sections are
**internally consistent** with one another — that every cross-reference resolves
and the accounting agrees across sections. These checks are **reference-level**,
not semantic: they verify that an ID exists and that two sections agree, never
that a human's disposition judgment is *correct*. Run per fixture as check group
`C1–C8`:

- **C1 — no phantom `CC-NNN`.** Every candidate-claim ID appearing *anywhere* in
  `precis.md` must exist in the §4 candidate-claim inventory. Catches a claim ID
  invented in prose, the ledger, or the matrix.
- **C2 — no orphan claim.** Every §4 inventory claim must appear at least once
  **outside** §4 and §5. Deliberately **loose**: presence of the `CC-NNN` token
  anywhere outside the inventory + ledger satisfies it — no specific section,
  heading, prose wording, or disposition-themed location is required. This avoids
  prose-policing; it only catches a claim that is defined but never carried into
  any downstream section.
- **C3 — §5 ledger ↔ §4 disposition consistency.** Every `CC-NNN` listed in a §5
  ledger disposition row must (a) exist in §4, and (b) carry *that* disposition in
  §4; and every §4 claim must appear in some §5 row. Catches **safe disposition
  drift** (e.g. the ledger filing `CC-107` under `carried` while §4 records it
  `excluded-with-reason`) structurally, without reading prose.
- **C4 — no phantom `SRC-NNN`.** Every source ID appearing anywhere in
  `precis.md` must exist in the §2 source inventory. Catches an invented source in
  §4 provenance, §11, or the matrix.
- **C5 — matrix CC references valid** (Slice 2 only). Every `CC-NNN` in the
  matrix's *candidate claim IDs* column (located by header name, not index) must
  exist in §4.
- **C6 — matrix SRC references valid** (Slice 2 only). Every `SRC-NNN` in the
  matrix's *source refs* column must exist in §2.
- **C7 — no phantom `STM-N`.** Every stress-test ID appearing anywhere in
  `precis.md` must be an actual matrix table row. For a slice with no matrix the
  valid set is empty, so any `STM-N` token is phantom.
- **C8 — merge provenance retention.** For each §11 merge-map row, the canonical
  claim's §4 source set must be a **superset** of every absorbed claim's §4 source
  set — a merge may not silently drop a source provenance. Driven off the parsed
  §4 `SRC-NNN` sets (structured), not the free-text "provenance retained" column.

All Slice 4 checks read `precis.md` only and emit `FAIL <slice> consistency
C<n> (<label>): …` on violation. Matrix-dependent checks (C5/C6) and the matrix
side of C7 only engage for a slice that has a matrix; C8 only engages when a §11
merge-map row exists.

## Discovered fixtures and run kernels

Every non-legacy directory directly under `docs/fixtures/` declares one
`aleph-fixture` block. K1 validates the declaration/ranges and dispatches by
kind. The current suite contains:

| fixture | kind | applicable checks |
|---------|------|-------------------|
| `slice-1`, `slice-2` | legacy Précis | P1-P10 and C1-C8 |
| `evidence-role-adversarial` | `evidence-role` | K3.1-K3.8 |
| `projection-adversarial` | `projection` | K6.1-K6.10 |
| `run-slice-2` | `run` | K2.1-K6.10 |

The run kernel checks:

Top-level `control/` is reserved for host-adapter mechanics such as immutable
runtime snapshots and durable dispatch checkpoints. The run loader deliberately
excludes that subtree from canonical Core artifact discovery and all K2-K6
content/identifier scans. The bytes remain in the durable run directory, but
cannot themselves define or satisfy a Core artifact or participate in those
scans; a `control/` directory nested anywhere else is not excluded.

- **K2:** reached-state layout, manifest transitions/gates, fixture-only
  forbidden tokens, source-span hashes, global `RUN` through `PRJ` ID integrity,
  claim shape,
  disposition accounting, merge provenance, criteria chronology, append-ledger
  status chains, exact Précis projection, and kernel-report honesty.
- **K3:** evidence-edge shape/resolution, removal effects, support coverage,
  decorative/unresolved-source exclusions, contradiction preservation, and
  inference-marker resolution.
- **K4/K5:** route-card fields/vectors, packet/source reconstruction,
  referent-ledger relations and reroute history, tag/dependency discipline,
  transitive taint, finalization markers, Précis §17 honesty, and authorized
  referent resolution.
- **K6:** commissioned `PRJ-*`/trace/hash binding, exact selection/open-item coverage, trace
  resolution and paragraph coverage, no-new-claim/boundary rules, taint
  prominence, backwards-leak prevention, and registered type metadata/required
  sections for product-doctrine and PRD.

`validateRun({root, run, kind?})` exports the same run validation without
printing, exiting, writing, spawning, or using the network. It returns:

```json
{
  "result": "PASS",
  "checks": [
    {
      "id": "K2.1",
      "scope": "RUN-slice-2",
      "status": "PASS",
      "message": "(layout): required base and reached-state artifacts are present"
    }
  ]
}
```

`result` is `PASS` only when every applicable record has `status: PASS`.
Human mode prints the same records as `PASS/FAIL <scope> <id> <message>`.

### Durable cross-group mutation record

On 2026-07-16, the repository-level battery was run with:

```bash
node scripts/test-conformance-mutations.ts --json
```

It returned `PASS` with 53/53 mutation cases and 3/3 clean baselines:

| group | targeted mutations | result |
|-------|--------------------|--------|
| K1 discovery and declarations | 5 | PASS |
| K2 run structure, global IDs, accounting, hashes, chronology, status, and adapter-control isolation | 20 | PASS |
| K3 evidence roles and removal effects | 8 | PASS |
| K4/K5 cards, referents, routing, and taint | 9 | PASS |
| K6 commissioned projection IDs, selections, claim/boundary traces, rendering, and type contracts | 11 | PASS |

Each case copies only its target fixture to a fresh operating-system temporary
root, injects one defect, invokes the real JSON checker through `--root`, and
requires both a nonzero result and the intended failing check ID. The clean
baselines are the complete golden run, evidence-role fixture, and isolated
two-type projection fixture.

The K1 legacy case compares complete human stdout byte-for-byte, including the
terminal newline. With only `slice-1` and `slice-2` present, the sole permitted
change from the pre-K1 checker is the added discovery PASS line. The expanded
K2/K6 cases include duplicate run identity fields, malformed and externally
declared predecessor runs,
predecessor citations outside the manifest field, dangling `RUN-*`, `NB-*`, and
`PRJ-*` references, duplicate `PRJ-*` definitions, and missing commissioned
projection identity. The K2 control-boundary case first proves that arbitrary
retained bytes under top-level `control/runtime/` do not enter canonical
discovery, then introduces the same dangling identifier into canonical
`verification/control/` and `run-log.md` paths and requires K2.5 to fail.

## What it does NOT prove

- It is **not** a schema validator and does **not** freeze the envelope. It
  encodes the *provisional v0* vocabulary as evidence-of-current-shape; a later
  slice may amend the envelope and update the checker in lockstep.
- It is **not** a Markdown parser, an extractor, or a Précis *generator*. It
  reads the hand-authored fixtures and checks invariants with small, readable
  helper functions and targeted regexes — not a parsing framework.
- It does **not** judge research quality, truth, or whether dispositions are
  *correct* — only that the accounting balances and nothing silently vanishes.
- It does **not** read raw corpus and produce a Précis. No live machinery.

## Why this is not a schema freeze

The checker's constants describe the **accepted provisional v0 envelope** — the
shape Slice 1 and Slice 2 were accepted with. Per Aleph doctrine, packets are
run first and the matrices name the structure second; the envelope remains
amendable. If a future slice changes the envelope, the fix is to update this
checker alongside the fixtures — the checker follows the doctrine, it does not
ossify it.

## Why this is not extraction / generation machinery

The checker never transforms a corpus into a Précis, never emits a downstream
artifact, and never projects claims into a PRD/GTM/spec. It only *verifies* that
the existing artifacts honor the no-projection and no-silent-discard invariants.
It is a read-only conformance gate, the opposite of a generator.

## Relationship to Slice 1 and Slice 2

- **Slice 1** (happy-path v0 fixture) and **Slice 2** (adversarial fixture +
  stress-test matrix) were accepted as hand-authored, human-inspected Markdown.
- Slice 3 adds the *mechanical* inspection those slices' completeness guarantee
  implicitly promised. Both accepted fixtures must pass; the checker is run
  against both and exits 0 only if both conform.
- Slice 3 makes the forbidden-token / projection-boundary / accounting guarantees
  **enforced** rather than verified by eye.

## Running against a copy (`--root`)

By default the checker validates the fixtures under the repository it lives in.
It also accepts `--root <dir>`, pointing it at any directory that contains a
`docs/fixtures/…` tree:

```
node scripts/validate-precis-fixtures.ts --root /tmp/some-copy
```

This is read-only and writes nothing; it exists so the negative-test battery can
run the **real** checker against temporary copies of the fixtures without ever
mutating the tracked fixtures.

## Failure posture

Fail-closed. Any real invariant violation prints a `FAIL <slice> <check>: <what>
<where>` line and exits non-zero. A passing run prints `RESULT: PASS`.

After the Slice 3 hardening patch, the checker was **re-run** against a negative
battery using temporary copies (`--root`); every case below exited non-zero, and
a clean copy still exited 0:

1. an extra direct file in a fixture directory (`slice-1/extra.md`);
2. a candidate-claim ID (`CC-001`) leaked into `corpus.md`;
3. a `Disposition: unresolved` label leaked into `corpus.md`;
4. a compound disposition `excluded-with-reason` leaked into `corpus.md`;
5. a removed candidate-inventory row with the ledger left unchanged;
6. a ledger total changed to mismatch the inventory count;
7. the actual `STM-7` matrix **row** removed while `STM-7` still appears in
   summary prose (the checker fails because it isolates the matrix section and
   requires `STM-7` as a real table row, not prose);
8. `This Précis deliberately generates a PRD.` (a generation assertion — the word
   "deliberately" is **not** treated as an exemption);
9. a malformed inventory row carrying two disposition cells
   (`| CC-101 | SRC-101 | bad claim | deferred | carried |`) — rejected for both
   its column count and its multiple disposition cells;
10. `| CC-101 | claim | SRC-101 | carried | extra-cell` — a row with a leading
    pipe but **no trailing pipe** and an extra cell;
11. `| CC-101 | claim | SRC-101 | carried | deferred` — same shape, the extra
    cell being a second disposition;
12. `CC-101 | claim | SRC-101 | carried | extra-cell` — a row with **no outer
    pipes at all** and an extra cell;
13. `CC-101 | claim | SRC-101 | carried | deferred` — same, the extra cell being
    a second disposition.

Cases 10–13 are the optional-trailing-pipe bypass: the table-row parser strips a
leading/trailing split fragment **only when it is genuinely empty**, so a
non-empty trailing fragment is preserved as a real cell. Each of these rows
therefore parses to 5 cells and is rejected by the exact-column-count check
(`expected exactly 4 columns, got 5`) rather than being silently truncated to a
well-formed 4-column row. This closes the bypass that earlier let an extra cell
or a smuggled second disposition slip past when the outer pipes were omitted.

The false-positive guards still pass (a clean fixture is not flagged): legitimate
refusal/boundary prose such as `no PRD`, `not a GTM plan`, `does not become a
product spec`, `no schema freeze`, `projection-neutral`, `no downstream
projection generated`, and `could project only in a future consumer`, plus the
ordinary-English `unresolved at the research stage` inside `corpus.md`.

### Slice 4 negative battery (cross-section consistency)

Slice 4 adds a second `--root` mutation battery. Each case copies the fixtures to
a temp root, injects exactly one cross-section inconsistency, runs the **real**
checker, and confirms the **intended** `C<n>` check fires (verified by grepping
the specific `consistency C<n>` failure line, not merely a non-zero exit). A clean
copy still exits 0, and the entire Slice 3 battery above continues to fail closed.

1. **Phantom CC in prose** — inject `CC-999` into a §6 prose line → **C1** fires.
2. **Phantom CC in matrix** — put `CC-999` in a matrix candidate-claim-IDs cell →
   **C1** (token anywhere) and **C5** (matrix-column ref) fire.
3. **Phantom SRC in §4 provenance** — add `SRC-999` to a §4 claim's source cell →
   **C4** fires.
4. **Phantom STM outside the matrix** — reference `STM-99` in §13 prose → **C7**
   fires.
5. **Matrix row references a non-existent CC** — change a matrix CC cell to
   `CC-888` → **C5** fires (and **C1**, since the token is now in `precis.md`).
6. **Merged claim loses one SRC provenance** — drop `SRC-104` from canonical
   `CC-104`'s §4 source cell (it absorbs `CC-114`, which keeps `SRC-104`) → **C8**
   fires.
7. **Inventory claim removed but still referenced downstream** — delete `CC-103`'s
   §4 row and its §5 ledger entry, leaving §6/§13 references → **C1** fires (the
   downstream `CC-103` token no longer resolves to §4).
8. **Downstream prose references a claim not in inventory** — add `CC-777` to a
   §13 synthesis line → **C1** fires.
9. **Safe disposition drift via §5 ledger** — move a claim ID into the wrong §5
   disposition row (ledger says `carried` for a claim §4 records `unresolved`) →
   **C3 (disposition drift)** fires.
10. **Isolated orphan (C2 only)** — keep a claim in the §4 inventory **and** its §5
    ledger entry, but scrub it from every other section (its matrix cell and §13
    prose) → **C2 (orphan claim)** fires *in isolation*. Verified that **C1 and C3
    do not fire** for this case: the claim still resolves to §4 and the ledger
    still agrees, so only the orphan check trips. This proves C2 is independently
    triggerable, not merely a side effect of C1.

## Deferred hardening (intentionally NOT implemented)

These are **deferred** — not missing implementation, but checks we judged would
become brittle prose-policing or step over the line into semantic-truth checking.
They are documented here so the boundary is explicit; each would need its own
approved slice and a stable, false-positive-free pattern before adoption:

- **Disposition-themed prose-section membership** — e.g. requiring that any
  `CC-NNN` discussed under §9 "Excluded-with-reason" is recorded
  `excluded-with-reason` in §4. Deferred because it is **provably brittle** on the
  real fixtures: §6 references `CC-105`/`CC-106` (both `unresolved`) by ID while
  explaining a *carried* claim, and §13 cluster-synthesis groups claims by
  disposition *word*. A "claim under heading X ⇒ disposition Y" rule would
  false-positive on legitimate cross-references. C3 already catches the same drift
  **structurally** via the §5 ledger, without policing prose.
- **Semantic / human-judgment correctness** — whether a claim was *correctly*
  judged unresolved/excluded/carried. Out of scope by design: the checker proves
  internal consistency of references and accounting, not the soundness of the
  human call. (Allowed: "`CC-107` is in §4 and referenced where expected." Not
  allowed: "`CC-107` was correctly judged excluded.")
- **Prose ↔ inventory wording match** — verifying the normalized claim text in §4
  matches its prose restatement. Deferred as overfitting to exact wording.
- CI wiring (intentionally omitted: no CI in this slice).
