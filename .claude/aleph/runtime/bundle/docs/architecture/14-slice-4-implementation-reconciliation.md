# Slice 4 Typed Relations — Implementation Reconciliation

> Date: 2026-08-29
>
> Implementation base: `c8b8022a664315ee7fc4d3c7d3c094dd7ecf8b5f`
>
> First independently audited candidate:
> `0759ec394a0848eede0fa058f87564d5429910dc`
>
> Adopted proposal blob: `51af0df8e3f44201a086169c5ce1fe02050ff8a9`
>
> Adopted proposal SHA-256:
> `c7604873a724627806b911a39153796e551b1c1e627f4000866f07ade1a2e1b9`

This is a structural implementation reconciliation, not an authority
acceptance record. `PASS` below means only the cited deterministic or retained
contract evidence. It does not mean replay validation, semantic validation,
agent sanction, acceptance, production readiness, golden status, or Aleph v1.

## First independent audit and successor repair

The first fresh independent implementation audit reviewed exact head
`0759ec394a0848eede0fa058f87564d5429910dc` and returned:

`BLOCK_SLICE_4_IMPLEMENTATION_MERGE`

The adopted design remains authoritative and unchanged. The audit found:

- I-01: typed-null `semantic-prerequisite` rows could bypass the required
  `source_kind = CC`;
- I-02: `reviewed_by` identity was resolved through arbitrary prose mentions
  instead of exact verdict-record identity;
- N-01/N-03: consumed T7.1 verdicts were not required to retain the complete
  mandatory field set and could be shadowed by a preceding canonical table;
- N-02/N-04: scratch/index prose or a differently identified VER document
  could participate in false authorization or duplicate resolution;
- N-07: the predecessor's published candidate bundle/lock identities did not
  reproduce from the audited commit; and
- N-05/N-06/N-10: status-honesty, mutation-count, and adapter-boundary wording
  required reconciliation.

The successor repair separates relation source-kind legality from concrete
target legality, applies claim-dependency source-kind rules for every record
state, and leaves typed-null target validation separate. A consumed
`reviewed_by = VER-NNNN` now resolves only under `verification/harness/` by the
exact basename `VER-NNNN.md`, the exact first document heading
`# Verdict VER-NNNN`, and exactly one canonical `field | value` verdict table.
That table must contain exactly one nonblank row for `target`, `lens`, `stage`,
`shown`, `withheld`, `verdict`, and `consequence`. Exact target equality and
`verdict = upheld` remain mandatory.

The focused battery now includes:

- forbidden PKT-source `semantic-prerequisite` rows for `unresolved-target`,
  `explicitly-absent`, and subtype `indeterminate`;
- forbidden PKT-source claim-dependency family-level indeterminate;
- legal CC-source near-neighbors for typed-null semantic prerequisite and
  family-level indeterminate;
- moved VER bytes, a differently headed VER that mentions the cited identity,
  wrong heading identity, and duplicate actual VER records;
- an unrelated `INDEX.md` prose mention that remains non-authorizing and
  non-duplicating;
- missing `shown`, `withheld`, `lens`, and `consequence`, plus blank `stage`;
- scratch notes carrying a correct table but no canonical verdict identity;
  and
- two competing canonical verdict tables with an upheld decoy before a
  refuted table.

## DoD-01 through DoD-21

| DoD | File(s) | Test/proof | Status |
|-----|---------|------------|--------|
| DoD-01 | adopted proposal and `ADOPTED-slice-4-typed-relations-design-20260828.md` | exact blob/SHA-256 and adoption blob remain unchanged | SATISFIED |
| DoD-02 | `run-model.ts`, artifact/checker docs, manifests | exact capability-set assertions for 1.0–1.4 plus 1.4 fixture K2.13–K2.16 | SATISFIED |
| DoD-03 | `checks-k2-relations.ts`, manual/orchestrator contracts | missing/empty/present and retained pre-closure mutations; separate process-helper tests | SATISFIED (static/process-contract split) |
| DoD-04 | `relations.ts`, `checks-k2-relations.ts`, T3.3b | schema/state/taxonomy/stage checks plus source-kind legality for asserted and typed-null states | SATISFIED (focused) |
| DoD-05 | relation checker and typed-relations fixture | positive `md-lines`; malformed/wrong-scheme/hash and asserted `chat-msg` failures | SATISFIED (focused) |
| DoD-06 | relation checker + Slice 3 lineage helpers | non-current source/target and historical predecessor mutations | SATISFIED (focused) |
| DoD-07 | fixture REL-1407/VER-1407 | explicit `CC-0421` successor; `CC-0420` mutation rejected | SATISFIED (focused) |
| DoD-08 | relation state/conflict checks; semantic review cases | subtype/family/taxonomy null positives and conflict mutations; review-only not-applicable row | SATISFIED (focused) |
| DoD-09 | digest helper, verifier records, K2.16 | exact digest vector; basename/heading identity; one complete T7.1 table; exact target and upheld verdict | SATISFIED (focused) |
| DoD-10 | producer prompts and L3R lens | S2/S3/S4 context contracts plus retained ten-case semantic challenge set | SATISFIED as implementation contract; NOT semantically validated |
| DoD-11 | orchestrator prompt, manual runbook, `requireRelationWriteWindow()` | Core process-contract/test helper demonstrates intended pre/at/post refusal semantics only; it has no production call site and is not a live writer guard | SATISFIED as test-surface process contract; F-03 preserved |
| DoD-12 | K2.16 checker/spec | targeted mutation diagnostics and non-claiming PASS text | SATISFIED (focused) |
| DoD-13 | focused fixture | all eight types, legal mixed cycle, distinct indeterminate scopes, and relation multiplicity/evidence-role separation pass | SATISFIED (focused) |
| DoD-14 | `test-relation-mutations.ts` | 64 deterministic negative mutations, three targeted positive controls, exact digest vector, three temporal cases; 74/74 focused checks pass | SATISFIED (focused) |
| DoD-15 | `verification/semantic-review-cases.md` | ten required structurally legal semantic failures retained outside K2 | SATISFIED as contract evidence; NOT semantically validated |
| DoD-16 | unchanged historical fixtures; capability registry | 117/117 conformance mutations with 11/11 clean baselines; 34/34 lineage mutations; explicit 1.3 incompatible-activation failure | SATISFIED |
| DoD-17 | canonical TS + generated `runtime-js` | TypeScript gate and generated runtime drift gate pass for 34 files | SATISFIED |
| DoD-18 | Core manifest/bundle machinery | CB1–CB9, Core-boundary mutations, 30-case bundle tests, and 23/23 release-package tests pass | SATISFIED |
| DoD-19 | adapter protocol, manifests, and pin tests from the predecessor | no `adapters/*/src` repair and no live writer/orchestrator integration; F-03/F-04/F-05 retained | SATISFIED within authorized host-mechanical pin scope |
| DoD-20 | required docs/checker/test/runtime surfaces | narrow successor repair and generated runtime projection reconciled | SATISFIED |
| DoD-21 | fresh independent implementation audit | first audit blocked `0759ec39`; the repaired successor has not received a fresh independent audit | OPEN — RE-AUDIT REQUIRED |

## Recorded verification

The complete repository-defined `npm test` battery passed on the repaired
successor:

- TypeScript typecheck: PASS;
- generated runtime parity: 34 files; runtime tests: 6/6 PASS;
- CB1–CB9: PASS over 479 classified paths;
- worker-return contracts: 12/12 PASS;
- Loa host: 24/24 PASS;
- Loa adapter and offline installer batteries: PASS, with no real model calls;
- all nine discovered fixtures: PASS;
- K1–K6 conformance: 117/117 with 11/11 clean baselines;
- lineage mutations: 34/34 PASS;
- relation checks: 74/74 with 64 deterministic negative mutations;
- Core-boundary mutation battery: PASS;
- bundle assembly/mutation battery: 30 cases PASS; and
- release-package battery: 23/23 PASS.

`git diff --check`, final post-commit bundle assembly, independent verification,
and two-clean-worktree identity reproduction are rerun after the final commit
is fixed. Their exact evidence belongs in the PR record because adding
commit-dependent identities here would change the bytes being identified.

The focused relation result is 74/74:

- 64 deterministic negative mutations;
- three targeted positive controls added by the repair;
- the baseline 14-row fixture;
- the cumulative capability assertion;
- the exact review-subject digest vector;
- three process-helper temporal cases; and
- the retained semantic-review challenge-set check.

These results are structural only. Final candidate identities are derived only
after repository bytes are committed and are published in the PR record, not
predeclared in this file.

## Finding dispositions and preserved boundaries

| Classification | Finding | Disposition |
|----------------|---------|-------------|
| PREDECESSOR BLOCKING | I-01 source-kind gap | repaired with record-state-independent source-kind legality and four negative/two positive controls |
| PREDECESSOR BLOCKING | I-02/N-02/N-04 verdict identity gap | repaired with exact harness basename + heading identity and moved/prose/wrong-heading/duplicate/scratch controls |
| PREDECESSOR BLOCKING | N-01/N-03 T7.1 structural gap | repaired with one-table and complete nonblank required-field checks |
| PREDECESSOR BLOCKING | N-07 stale candidate identities | predecessor values are not retained; exact successor identities require two-clean-worktree reproduction |
| DOCUMENTARY | N-05 writer-guard wording | helper is described only as Core process-contract/test evidence; retained-state K2 is real, manual procedure is sanctioned, live host enforcement is unvalidated |
| DOCUMENTARY | N-06 mutation count | reconciled to 64 deterministic negative mutations and 74 total focused checks |
| TEST-REASONING | N-08 positive-test claim | corrected: negative mutations prove forbidden-state rejection; positive controls only prevent over-rejection |
| LATER | N-09 positive nonzero evidence-role coexistence fixture | not implemented |
| DOCUMENTARY | N-10 adapter boundary | predecessor changed adapter manifests/tests and adapter-protocol docs/schema; no adapter source changed and this repair changes no adapter files |
| MUST PRESERVE | F-03 live LedgerWriter/orchestrator wiring remains unvalidated end to end | no live integration or agent-mode claim added |
| MUST PRESERVE | F-04 path/case portability remains unresolved | no portability-closure claim |
| MUST PRESERVE | F-05 post-S4 lineage BLOCK remains tied to F-03 | test helper does not overwrite the unrelated halt |
| MUST PRESERVE | relations remain non-evidentiary and manual mode remains the sole sanctioned path | unchanged |
| LATER | A4-07 claim-to-claim evidential relation ownership | not reopened |
| LATER | A4-14 source-locus self-reference precision | not reopened |
| CONFIRMED | A4-15 exact VER-target behavior | independently confirmed correct; no expansion added |
| LATER | A4-16 producer payload-charset architecture | not reopened |
| LATER | A4-17 editorial cleanup beyond changed diagnostics | not reopened |

`requireRelationWriteWindow()` has no production call site. Its isolated tests
show the intended refusal contract before and after the S4 closure phase; they
do not prove that a live Loa canonical writer invokes it. Retained-state K2
checks remain enforced. Manual procedure remains the sanctioned temporal
enforcement path. Agent/live host enforcement remains unvalidated.

## Status boundary

After the complete structural battery and exact-commit identity reproduction
are green, the repaired successor may be described only as:

`STRUCTURALLY IMPLEMENTED`

`CHECKER-CLEAN AFTER REPAIR`

`FIRST INDEPENDENT AUDIT BLOCKED THE PREDECESSOR CANDIDATE`

`RE-AUDIT REQUIRED`

`NOT REPLAY-VALIDATED`

`NOT SEMANTICALLY VALIDATED`

`NOT AGENT-SANCTIONED`

`NOT ACCEPTED`

`NOT PRODUCTION-READY`

`NOT GOLDEN`

`NOT v1`

DoD-21 remains `OPEN — fresh successor audit required`.
