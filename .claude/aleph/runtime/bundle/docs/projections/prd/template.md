# Product Requirements Document - {{PRODUCT}}

<!-- Replace every {{...}} placeholder and delete all instructional comments
     before review. Keep numbered headings stable after tracing. Separate
     substantive paragraphs with blank lines. -->

| field | value |
|-------|-------|
| Taint | {{TAINT STATUS AND REF IDS}} |
| Projection ID | {{PRJ-NNN FROM COMMISSION}} |
| Projection type | prd |
| Projection trace | projections/traces/prd-trace.md |
| Source run | {{RUN-ID}} |
| Intended consumer | {{REPO / TEAM / PERSON}} |
| Commission | {{RELATIVE PATH}} |
| Source Precis | {{RELATIVE PATH AND SHA-256}} |
| Domain assumption | software product, supplied by commission |
| PRD scope | {{COMMISSIONED BOUNDARY}} |
| Projection status | candidate pending P3 acceptance |

<!-- Keep the Taint field in the first ten lines. Use "none" only when the
     selected claims have no unresolved external-referent taint. For tainted
     output, use the exact marker required by trace-and-selection.md. -->

## 1. Document Purpose and Boundaries

{{State what decision or delivery boundary this PRD governs. Identify commission
parameters as parameters, not research findings.}}

{{State what this PRD explicitly does not decide.}}

## 2. Problem or Opportunity

{{State the supported problem, opportunity, and affected context. If the Precis
does not establish one, write an explicit gap instead of a generic problem
statement.}}

## 3. Users and Stakeholders

### 3.1 {{USER OR STAKEHOLDER}}

{{State only supported needs, responsibilities, or constraints. Do not invent a
persona, demographic, or behavior.}}

## 4. Product Outcomes and Success Measures

### 4.1 Intended outcomes

{{State supported outcomes in the strength and scope earned by their claims.}}

### 4.2 Measures

{{List claim-backed measures and thresholds. Where the Precis supplies no
measure or threshold, create a gap entry.}}

## 5. Scope

### 5.1 In scope

{{List claim-backed capabilities or decisions included by the commission.}}

### 5.2 Out of scope

{{List commissioned exclusions and relevant negative boundaries.}}

## 6. Functional Requirements

### FR-01 - {{REQUIREMENT NAME}}

**Requirement:** {{Use MUST only when the backing claims require it.}}

**Rationale:** {{Explain the supported product reason without adding facts.}}

**Open conditions:** {{None, or name the unresolved condition and its CC ID.}}

<!-- Repeat FR sections as needed. Each paragraph gets a trace row. -->

## 7. User and System Workflows

### 7.1 {{WORKFLOW NAME}}

{{Describe the supported actors, trigger, observable steps, and outcome. Mark
unspecified interaction details as gaps.}}

## 8. Constraints and Non-Functional Requirements

### NFR-01 - {{CONSTRAINT NAME}}

**Constraint:** {{State a claim-backed operational, safety, privacy, performance,
reliability, accessibility, or compatibility constraint.}}

**Unspecified target:** {{None, or an explicit gap.}}

## 9. Dependencies and Integrations

### 9.1 {{DEPENDENCY}}

{{State only dependencies carried by the Precis or supplied as commission
parameters. External existence claims remain referent needs.}}

## 10. Delivery Boundary

{{Describe the smallest supported delivery boundary or explicitly state that the
Precis does not establish one. Do not invent sequencing, staffing, dates, or
estimates.}}

## 11. Verification and Acceptance

### 11.1 {{REQUIREMENT OR OUTCOME}}

{{State a claim-backed observable acceptance condition. If no acceptance
condition is supported, record the gap rather than manufacturing one.}}

## 12. Risks, Open Questions, and Decisions Required

### 12.1 {{OPEN ITEM}}

{{Phrase deferred or unresolved material as open. State what evidence or
authority decision would resolve it and what it blocks.}}

## 13. Gaps and Known Limits

### 13.1 {{GAP OR LIMIT}}

{{Carry template gaps, source-run taints, sampling limits, and unvalidated
machinery notices. Do not hide a gap in an appendix or fill it with convention.}}
