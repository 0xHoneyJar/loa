# Decision 0003 - Architecture build kit accepted for implementation

- **Status:** Accepted for implementation - provisional shapes remain provisional
- **Date:** 2026-07-16
- **Authority:** Eileen (product / architecture authority), explicit direction to
  build the product described by PR #19
- **Relates to:** PR #19; `docs/architecture/`; issue #18; Decisions 0001 and
  0002
- **Amends implementation status:** Decision 0001's initial projection packages
  and Decision 0002's fixture-gated routing checks.

## Context

PR #19 supplied an end-to-end architecture, templates, prompts, checker
specifications, and a build handoff. It deliberately did not implement the
method. Implementation could not start safely until the build-kit questions
that affect deterministic parsing and run semantics had concrete answers.

This decision accepts the architecture tree as the implementation plan while
preserving its evidence discipline:

- accepted doctrine still wins over an architecture document if they conflict;
- artifact field shapes remain provisional until fixtures exercise them;
- deterministic checks prove structure, accounting, and references, not truth;
- agent mode, mode equivalence, convergent-heavy routing, and v1 remain
  unvalidated until their named replay evidence exists.

The instruction to build the product authorizes the substrate work packages in
`docs/architecture/13-build-handoff.md`. It is not authority for an agent to
accept its own run, supply external facts, or claim replay evidence that does
not exist.

## Build-kit disposition

| Item | Disposition | Boundary |
|------|-------------|----------|
| `01-vision-and-tenets.md` | accept for implementation | System v1 criteria remain evidence-gated |
| `02-system-architecture.md` | accept with clarifications below | Run files remain canonical |
| `03-artifact-contracts.md` | accept provisionally | Fixture evidence may amend field shapes |
| `04-pipeline-stages-and-dod.md` | accept for implementation | T1/T2/T3 markers keep their separate meanings |
| `05-orchestration-on-fable-5.md` | accept as runner doctrine | Agent mode remains unsanctioned until replay |
| `06-verification-and-conformance.md` | accept with Q2 decision below | T1 never judges semantic truth |
| `07-projection-stage.md` | accept for implementation | Projection types require the full five-part package |
| `08-runbook-agent-mode.md` | accept as an unsanctioned runbook | Supervised replay must precede sanctioning |
| `09-runbook-manual-mode.md` | accept with packet-row correction | Manual mode remains the sanctioned path |
| `10-build-roadmap-slices.md` | accept as evidence sequence | Current build may combine implementation commits, not evidence claims |
| `11-research-grounding.md` | accept as rationale | Sources do not substitute for replay |
| `12-risks-open-questions-do-not-build.md` | accept with Q2/Q4/Q5/Q11 resolved here | Remaining questions stay open |
| `13-build-handoff.md` | accept as builder entry point | Substrate completion is not v1 completion |
| `templates/` | accept provisionally | Golden fixtures may amend shapes in lockstep with checks |
| `prompts/` | accept provisionally | Agent-mode validation still requires supervised replay |
| `checker-spec/` | accept with this decision's clarifications | T1 stays structural, read-only, and fail-closed |
| Product-doctrine and PRD projection packages | authorize | Each requires a fixture, trace, checks, audit, and acceptance |
| Extractor or autonomous research generator | defer | The procedure remains agent/human judgment, not a truth engine |
| Endpoint, service, crawler, graph product, or autonomous authority | reject | Existing do-not-build boundaries remain binding |

## Decisions on blocking questions

### Q2 - Hard versus soft conformance

Ratify the split in architecture document 06:

- T1 contains deterministic structure, accounting, reference, hash, state, and
  boundary checks. T1 failures are exact and fail closed.
- T2 contains semantic attacks and judgment. T2 produces verdict evidence and
  consequences; it does not encode research truth as an exit code.
- T3 alone supplies authority decisions and acceptance.

### Q4 - Span locators

`md-lines` is the first mechanically verified scheme:

- locator format is `L<start>-L<end>`, one-based and inclusive;
- span bytes are the selected complete lines joined with `\n`;
- a trailing `\n` is included when the selected span is not the final line of
  the frozen file, matching the bytes returned by slicing the file's line
  offsets;
- `span_hash` is `sha256:<lowercase hex>`.

`chat-msg` remains a declared but mechanically unverified scheme until a
conversation-export fixture freezes message and sentence serialization.
K2.4 reports that such a scheme was not verified; it does not guess.

External research material supplied after corpus freeze starts a new run whose
manifest names the prior run. An authority statement may resolve a referent in
the current run through a sign-off row because it does not mutate corpus
content. A frozen corpus is never silently extended in place.

### Q5 - Claim type

Keep `claim_type` in the run ledger as provisional routing metadata using the
template's five-value vocabulary. The kernel checks the closed value set but
does not infer whether the chosen type is semantically correct. The Précis
four-column projection still omits it. Envelope review may remove or amend the
field if replay evidence shows that it did not earn its cost.

### Q11 - Verifier detail

Full verdict files remain run-internal portable companions under
`verification/harness/`. Précis section 16 carries only the verification
summary and sampling honesty record. A handed-off Précis may be accompanied by
the run directory or a content-addressed archive, but embedding every verdict
inside the Précis is not required.

## Additional implementation clarifications

1. The run mode vocabulary is `agent`, `manual`, or `hybrid`.
2. Ledgers are append-over-mutate. Stage prose that says "update" means append a
   superseding row and retain the old row.
3. During S3 an active claim may have a blank disposition. Once S5 has been
   entered, every active claim must carry exactly one valid disposition.
4. `survives-independent-support` is the canonical evidence-removal value.
5. The coarse `DISTILLING` state cannot prove which S1-S10 artifact is due.
   K2.1 requires the base S1-S5 artifacts while the run is distilling and
   requires the complete S1-S11 set once `ASSEMBLED` is reached. Stage-specific
   DoD remains recorded in the run log and checked by T2/audit until a finer
   state representation earns a fixture.
6. A Tier-2 projection may consume an accepted Précis directly or a Tier-1
   projection whose trace resolves transitively to that Précis.
7. Projection states are repeatable per commission:
   `ACCEPTED|PROJECTION-ACCEPTED -> PROJECTING -> PROJECTION-ACCEPTED`.
   Each projection keeps its own commission and acceptance record.
8. A standalone `kind: projection` fixture need not embed a run manifest. K6.1
   checks acceptance chronology only when a run manifest is present; fixture
   acceptance provenance is an audit/README responsibility.

## Consequences

- The build kits now provide a stable implementation target without claiming a
  schema freeze.
- The golden run fixes exact Markdown forms before the kernel depends on them.
- Every new checker group still lands with a passing fixture and a mutation
  battery.
- Completing the substrate does not by itself declare v1. The system-level
  Definition of Done in architecture document 01 remains the completion audit.
