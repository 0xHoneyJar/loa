# Product Doctrine - {{SUBJECT}}

<!-- Replace every {{...}} placeholder and delete all instructional comments
     before review. Keep numbered headings stable after tracing. Separate
     substantive paragraphs with blank lines. -->

| field | value |
|-------|-------|
| Taint | {{TAINT STATUS AND REF IDS}} |
| Projection ID | {{PRJ-NNN FROM COMMISSION}} |
| Projection type | product-doctrine |
| Projection trace | projections/traces/product-doctrine-trace.md |
| Source run | {{RUN-ID}} |
| Intended consumer | {{REPO / TEAM / PERSON}} |
| Commission | {{RELATIVE PATH}} |
| Source Precis | {{RELATIVE PATH AND SHA-256}} |
| Projection status | candidate pending P3 acceptance |

<!-- Keep the Taint field in the first ten lines. Use "none" only when the
     selected claims have no unresolved external-referent taint. For tainted
     output, use the exact marker required by trace-and-selection.md. -->

## 1. Purpose and Scope

{{State the product purpose this doctrine governs and the commissioned scope.
Purpose statements that assert research findings are load-bearing and need
claim backing. Commission parameters are identified as parameters, not findings.}}

{{State what this doctrine does not govern.}}

## 2. Product Intent

{{Describe the outcome or change the product is intended to create. Preserve the
strength, uncertainty, and scope of the backing claims.}}

## 3. Governing Principles

### 3.1 {{PRINCIPLE NAME}}

{{State one principle as an actionable rule.}}

{{Explain the implication for a downstream decision without adding a new fact.}}

### 3.2 {{PRINCIPLE NAME}}

{{Repeat as needed. Each principle and implication receives its own trace row.}}

## 4. Decision Rules and Tradeoffs

### 4.1 {{DECISION AREA}}

{{State what the doctrine prefers when this tradeoff arises, the conditions
under which it applies, and any unresolved branch.}}

### 4.2 {{DECISION AREA}}

{{Repeat as needed. Do not collapse conflicting claims into a false rule.}}

## 5. Boundaries and Prohibitions

### 5.1 In Scope

{{State supported positive boundaries.}}

### 5.2 Out of Scope

{{State commissioned scope exclusions and claim-backed negative boundaries.}}

### 5.3 Must Not

{{Carry do-not-use and harm boundaries forward without reproducing excluded
material as support.}}

## 6. Open Questions and Tensions

### 6.1 {{OPEN ITEM}}

{{Phrase deferred or unresolved material as a question, tension, or decision
still required. State what evidence or authority decision would resolve it.}}

## 7. Evidence Gaps

### 7.1 {{GAP}}

{{Name information the doctrine would need but the Precis does not contain.
Do not propose an unsupported answer.}}

## 8. Known Limits and Change Conditions

{{State taints, sampling limits, unvalidated arms, and other relevant known
incompleteness carried from the source run.}}

{{State which new evidence or authority decisions should trigger a new
distillation or projection, rather than a silent edit to this document.}}
