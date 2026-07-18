# 09 — Runbook: Manual Mode

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md),
> with the immutable manual execution binding fixed by
> [`Decision 0004`](../decisions/0004-core-adapter-and-bundle-boundary.md).
> Manual mode is the currently sanctioned path (routing doctrine §13) and the
> mode the accepted fixtures were authored in. This runbook writes down how a human executes the
> full method at **reconstructable fidelity** — sparse bookkeeping a later
> tool or agent can rebuild the complete graph from, never exhaustive
> hand-maintained completeness.

## 1. The manual-mode promise, restated

You can reach the same result as an agent because the procedure is explicit
and the bookkeeping is deliberately sparse. What changes versus agent mode is
fidelity of representation and throughput — never the steps, the invariants,
or what must be true at the end. The doctrine already fixed what you are NOT
required to do (routing doctrine §10), repeated here so you never feel guilty
skipping it:

- no materialized per-edge graph; no per-pre-cluster documents;
- no disposition on every packet at index time;
- no bidirectional links maintained by hand;
- no rewriting cards on every propagation step;
- no separate cluster-evolution ledger.

What you must always keep: **every route-cluster card lists exact packet IDs,
and every packet ID reopens a real source span.** That single habit is the
whole trail.

## 2. Equipment

A verified immutable Core bundle and lock, a run directory (same layout as
agent mode — create the folders, fill what manual mode fills), an immutable
runtime snapshot, a text editor, and the worksheets below. New manual runs pin
the reserved `core-manual` execution binding; it is not a native agent adapter.
Manual mode never
requires producing machine-twin files, routing logs, or exhaustive verifier
records; the Markdown ledgers and cards are the complete manual artifact set.

## 3. The stages by hand

Work the same S0–S13 order as doc 04. Per-stage manual guidance, with the
sparse substitutions called out:

**S0–S1 (intake, inventory, criteria).** Record the Core, `core-manual`,
bundle, checker, protocol/run-format, host=`human-operator`, model=`human`, and
runtime-snapshot pins before corpus freeze. Otherwise these stages are
identical to agent mode and were designed at hand scale. Freeze the corpus (copy the files in;
note a checksum if you can, a file listing with sizes if you cannot). Write
the extraction criteria *before* reading deeply; if you have already read
deeply, write down the criteria your instincts are using — honesty beats
ritual purity.

**S2 (packets).** Walk each source top to bottom with the criteria beside
you. A packet row by hand uses every T3.1 field:
`PKT-0042 | SRC-003 | L118-L131 | sha256:<hex> | "tight quote..." | 2 |
active`. Canonical line ranges (or declared message locators for chat exports)
are your locators; compute the span hash over the frozen bytes. Do a whole
source in one sitting where possible — split
sittings are where spans get skipped; if you must split, mark the exact
resume point.

**S3–S4 (claims, merges).** Draft claims on one pass, merge on a second,
separate pass over the whole inventory (the barrier matters by hand too —
merging while drafting is how duplicate conviction sneaks through). The
contradiction rule is absolute: never merge two claims because reconciling
prose is easy to write.

**S5 (dispositions).** One claim, one disposition, one line of reason for
anything not obviously carried. Do dispositions in a different sitting from
claim drafting; the gap is your cheap substitute for a fresh-context judge.

**S6 (evidence roles).** By hand, do the sparse version: complete role edges
for every **carried and merged** claim (these are what projections will lean
on) and for anything contradiction-adjacent; skip decorative-vs-contextual
hair-splitting on backgrounded/non-load-bearing material. Declare removal
effects only for load-bearing edges. This sparse rule is a proposed
manual-mode boundary — the evidence-role fixture slice will confirm or adjust
it.

**S7–S8 (tags, cards, routing).** Tags are pencil marks: `PC-3` written
against packet IDs, nothing more. Promote to route-cluster cards only when a
doctrine-like spine emerges; fill the card template (doc 03 artifact 11)
completely — it is short on purpose. Posture changes overwrite the card's
posture line with a dated note; that is your entire routing log.

**S9a (adversarial arm).** Run the slice-2 risk families as a checklist
against each adversarial-weighted cluster and build the stress-test matrix.
Your refuter is *you, later, in a hostile mood*: schedule the stress-test
sitting apart from synthesis, and for each matrix row write the strongest
case **against** the current handling before writing the resolution. For
load-bearing evidence edges, do leave-one-source-out as a thought experiment
and check the declared removal effect holds.

**S9b (convergent arm).** Only over supplied referent material that was already
inside the corpus when S0 froze it. Material supplied after freeze leaves the
current run tainted and starts a successor run whose manifest names this run;
admit and reconcile it there. A recorded authority statement/sign-off may
resolve a referent in the current run but must not be treated as research
material unless that material was already frozen into the corpus. By hand this
is a comparison table per cluster: claim | referent |
agrees/conflicts/extends | note. Mark the arm unvalidated in the manifest
exactly as agent mode would.

**S10–S11 (synthesis, assembly).** Write the synthesis last, from the
ledgers, with the inventory open beside you — every claim ID you type, check
it exists and its disposition licenses the sentence. Assemble the Précis
section by section from the ledgers; the fixtures (`docs/fixtures/slice-1`,
`slice-2`) are your worked examples of exactly this.

**S12 (verification gate).** Run the kernel if a run-mode checker exists by
then; otherwise run the fixture checker's discipline by hand using the
self-check worksheet (§4). For the ⚖ items, manual mode substitutes **sampled
self-audit**: pick the samples doc 06 §3 marks exhaustive (all exclusions,
all contradictions, all big merges) plus a handful per disposition class, and
re-derive each cold before comparing. Record what you sampled — the sampling
record is part of the honesty, not paperwork.

**S13 (acceptance).** Same as agent mode: branch, PR, independent audit,
authority acceptance. Manual work gets no audit discount.

**P-stages.** Follow doc 07: commission first, defining one `PRJ-NNN` and exact
trace path; selection ledger before prose; cite that ID in the rendering and
trace; trace as you write (after each load-bearing paragraph, list the claim
IDs it rests on); gaps stay gaps.

## 4. Worksheets

**W1 — Stage-exit worksheet** (run at the end of every stage): the stage's
DoD list from doc 04 with ⚙ items checked by eye, ⚖ items checked by sampled
self-audit, 👤 items checked by an actual recorded sign-off. Any box you
cannot honestly tick is the next thing you do.

**W2 — Précis self-check worksheet** (S12): the ten wedge acceptance
criteria; the seven-disposition coverage table; the accounting equalities
(inventory count = ledger total = sum of per-disposition counts); the
phantom/orphan sweep (every `CC-`/`SRC-`/`STM-` token you can find resolves;
every inventory claim appears somewhere downstream); merge provenance
supersets; corpus blindness (open `corpus.md` and search for claim IDs,
disposition words, matrix vocabulary). This is the manual rendering of checks
1–10 and C1–C8.

**W3 — Card audit worksheet** (any time, and at S12): for each route-cluster
card — does every packet ID resolve? open two at random and *actually reopen
the source spans*. Does the posture match the shape vector? Is every pending
referent in the referent ledger?

**W4 — Sampling record** (S12): what you re-derived cold, what changed as a
result. Changes flow back as superseding ledger entries, exactly like agent
mode.

## 5. Scale guidance

Manual mode is honest about its ceiling. Rough bands (to be calibrated by the
first real manual runs, not guessed at harder than this):

- **A few sources / tens of claims** (fixture scale): fully comfortable.
- **~20 threads / low hundreds of claims** (instance #1 scale): feasible with
  discipline; expect the extraction and disposition sittings to dominate;
  tooling is *desirable* here but the promise holds.
- **Beyond that:** manual mode remains *possible* by the doctrine, but the
  honest recommendation is hybrid: a human drives gates, dispositions on the
  contested band, and all acceptance; an agent (once validated) does volume.
  Hybrid runs record per-stage actors in the manifest.

## 6. What manual mode must never skip

The sparse rules trim representation, never guarantees. Even at full sparsity:

- every candidate claim gets its disposition (no "obvious, skipped" rows);
- exclusions get reasons; contradictions stay separate and visible;
- merges keep all provenance;
- cards keep exact packet IDs; packets keep working locators;
- external facts come only from supplied referents;
- the known-incompleteness section tells the truth about what sampling and
  sparsity left unchecked.
