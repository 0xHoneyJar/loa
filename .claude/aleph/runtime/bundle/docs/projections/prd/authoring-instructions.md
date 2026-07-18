# PRD Authoring Instructions

## Goal

Render an accepted Research Precis into a software product requirements
document that a delivery team can act on without mistaking unsupported
conventions for research-backed requirements.

The PRD is domain-specific. The authority supplies the software-product context
and PRD boundary in the commission. Those parameters select a use for the
Precis; they do not add facts to it.

## Required order

1. Verify the source run is `ACCEPTED`.
2. Verify the commission records a unique `PRJ-NNN`, the trace path, software-
   product assumption, intended consumer, PRD scope, and Precis hash.
3. Complete the selection ledger using
   [`trace-and-selection.md`](trace-and-selection.md).
4. If using a Tier-1 projection, verify it is accepted and resolve every reused
   statement through its trace to the underlying `CC-` IDs.
5. Copy [`template.md`](template.md) to the commissioned run output path.
6. Write and trace one paragraph at a time.
7. Run available structural checks and a fresh-context projection review.
8. Re-verify the Precis hash and submit the candidate for independent audit and
   P3 authority acceptance.

Do not start prose before selection is complete.

## Requirement discipline

- `MUST` means the backing carried/merged claims establish a hard requirement.
- `SHOULD` means the backing claims establish a preference or default with room
  for an exception.
- `MAY` means the backing claims permit an option; it does not make the option a
  delivery commitment.
- If the Precis does not establish requirement strength, use neutral wording
  and record the decision required.

Requirement IDs such as `FR-01` and `NFR-01` are projection-local navigation
labels. They do not replace `CC-` backing and do not become new corpus claims.

## Section guidance

### Purpose and Boundaries

Separate authority-supplied commission parameters from corpus-derived
assertions. The commission may narrow the projection scope but may not widen the
accepted corpus scope.

### Problem or Opportunity

Do not manufacture a standard product problem statement. If the research
establishes a constraint, opportunity, or desired change but not a user pain,
say exactly that.

### Users and Stakeholders

Use only supported actors, needs, responsibilities, and constraints. Do not
invent personas, demographic details, market segments, or behavior.

### Outcomes and Measures

Preserve the difference between an aspiration, an outcome, a signal, and a
threshold. Missing metrics are healthy gaps. Do not infer a number from
industry convention or model knowledge.

### Scope

Combine the commission boundary with supported positive and negative claims.
Do-not-use boundaries bind the PRD. Out-of-scope material cannot return as an
optional requirement.

### Functional Requirements

Each requirement must express an observable product behavior licensed by its
backing claims. Separate requirements when combining them would hide different
actors, conditions, or certainty.

### Workflows

Describe only supported actors, triggers, steps, and outcomes. Where interaction
order, error behavior, or recovery is unspecified, write a gap.

### Constraints and Non-Functional Requirements

Do not add generic performance, security, reliability, accessibility, privacy,
or compliance targets. Include a category only when backed by a claim or name
the missing target as a gap.

### Dependencies and Integrations

An external system, competitor, prior art item, or platform is not established
by model knowledge. It must already be a supplied referent or remain marked
`external-referent unresolved`.

### Delivery Boundary

Do not invent milestones, staffing, dates, estimates, or implementation
sequence. If the selected claims support an MVP boundary, render it. Otherwise,
state that delivery slicing remains an authority decision.

### Verification and Acceptance

Acceptance conditions must be observable consequences of backed requirements.
Do not write synthetic precision merely to make the PRD look complete.

### Risks, Open Questions, Gaps, and Limits

Carry every relevant deferred/unresolved claim, referent taint, sampling gap,
and unvalidated-arm notice. State what each open item blocks.

## Writing rules

- Keep one substantive assertion per paragraph where practical.
- Preserve source hedges, actors, conditions, and scope.
- Use open voice for deferred and unresolved material.
- Use explicit `gap` language when the template demands unsupported content.
- Do not include `PKT-` IDs or copy the claim/disposition table.
- Do not invent facts from software-product convention.
- Do not mutate the source Precis, ledgers, or Tier-1 projection.
- Cite the commissioned `PRJ-NNN` in the rendered metadata and trace; never
  assign or redefine it outside the commission.

## Review questions

- Does every requirement resolve to active carried/merged claims?
- Did a preference become a MUST?
- Did a gap become a plausible-looking default?
- Did the PRD invent users, metrics, workflows, dependencies, or delivery dates?
- Are conflicting requirements still visibly in tension?
- Does every reused Tier-1 statement trace through to claims?
- Are negative boundaries and external-referent taints visible?
- Does the Precis hash still match the commission?
