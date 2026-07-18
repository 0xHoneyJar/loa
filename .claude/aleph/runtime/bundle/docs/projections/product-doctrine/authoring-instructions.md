# Product-Doctrine Authoring Instructions

## Goal

Render an accepted, projection-neutral Research Precis into a product doctrine
that a downstream team can use to make consistent decisions. The doctrine
should be compact and committed, but no more certain, complete, or specific
than its backing claims allow.

## Required order

1. Verify the source run is `ACCEPTED`.
2. Verify and record the commission's `PRJ-NNN`, trace path, and Precis hash.
3. Complete the selection ledger using
   [`trace-and-selection.md`](trace-and-selection.md).
4. Copy [`template.md`](template.md) to the commissioned run output path.
5. Write and trace one paragraph at a time.
6. Run the available structural checks and a fresh-context projection review.
7. Re-verify the Precis hash and submit the candidate for independent audit and
   P3 authority acceptance.

Do not start prose before selection is complete.

## What belongs

Prefer active carried/merged claims that establish:

- durable product intent;
- invariant-bearing behavior or experience;
- design intent that constrains downstream choices;
- explicit constraints and negative boundaries;
- supported tradeoff rules;
- unresolved tensions that change how decisions should be made; and
- known incompleteness that a user of the doctrine must see.

Claims do not become doctrine merely because they are memorable, repeated, or
convenient. Use the evidence-role and stress-test records to understand burden,
but do not turn citation count into authority.

## Section guidance

### Purpose and Scope

Use the commission to state intended consumer and scope. Distinguish an
authority-supplied purpose parameter from a corpus-derived assertion. The
projection may narrow its purpose; it may not widen the accepted corpus scope.

### Product Intent

Express the carried outcome claims in the register they earned. A preference is
not an invariant. An unresolved aspiration is not a promise.

### Governing Principles

Each principle must be actionable enough to resolve a class of future choices.
If the backing claims support only context, omit the principle or surface the
limitation. Keep separate principles separate when merging them would hide a
tension.

### Decision Rules and Tradeoffs

State the condition, preferred direction, and boundary. If different conditions
lead to different choices, preserve the branches. Do not resolve a
contradiction by writing smoother prose.

### Boundaries and Prohibitions

Carry relevant negative boundaries forward. A do-not-use claim cannot reappear
as evidence. An excluded claim may be mentioned only when needed to state the
boundary and must never be presented as supporting the doctrine.

### Open Questions and Tensions

Every in-scope deferred or unresolved claim from a selected cluster appears
here or in another explicitly named open section. Use open voice. Record what
would resolve the item; do not answer it from model knowledge.

### Evidence Gaps

When the template asks a question the Precis cannot answer, write a gap. A
useful gap names the missing decision or evidence and the consequence of not
having it. It does not guess.

### Known Limits and Change Conditions

Propagate relevant run notices, external-referent taint, sampling gaps, and
unvalidated machinery. State when the doctrine should be recommissioned or
preceded by a corrective distillation run.

## Writing rules

- Use direct declarative prose for carried claims.
- Preserve hedges and conditional scope from the source claims.
- Use question or pending-decision language for open items.
- Keep each paragraph focused on one traceable assertion.
- Do not include `PKT-` IDs or copy the claim/disposition table.
- Do not add market analysis, competitor claims, implementation architecture,
  delivery estimates, or product requirements unless the selected claims
  actually support them and the commission includes them.
- Do not mutate the source Precis or its ledgers.
- Cite the commissioned `PRJ-NNN` in the rendered metadata and trace; never
  assign or redefine it outside the commission.

## Review questions

Before submitting:

- Can a reviewer trace every actionable rule to active claims?
- Did any repeated claim gain false weight through repetition?
- Did any contradiction disappear inside a principle?
- Does any principle depend on an unresolved external referent?
- Are all selected-cluster open items visible?
- Did the document quietly become a PRD, architecture spec, or market report?
- Does the Precis hash still match the commission?
