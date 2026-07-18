# Spec K3 — Evidence-Role Checks (slice 10)

**Target:** `ledgers/evidence-roles.md` (template T4.1) within a run
directory or an evidence-role fixture (`kind: evidence-role` — a fixture
that carries corpus + inventory + evidence-roles at minimum). Implements the
mechanical half of issue #18's acceptance criteria; the semantic half
(are the roles *right*?) is the L6 harness lens, not the kernel.

**Closed vocabularies (constants):**

- roles: `load-bearing`, `corroborative`, `contradictory`, `contextual`,
  `decorative`, `unresolved-source`
- verification: `verified-primary`, `verified-secondary`, `unverifiable`
- removal effects: `downgrades-to-unresolved`, `confidence-decreases`,
  `survives-independent-support`, `must-be-excluded`

**Checks (scope = fixture/run id):**

- K3.1 (`edge shape`): edge rows have exactly 7 columns; `role` and
  `verification` from the closed sets; `status` per the status discipline.
  `FAIL … K3.1 (edge shape): row ⟨n⟩ role "supportive" not in vocabulary`.
- K3.2 (`edge resolution`): every edge's `claim_id` exists in the inventory
  (`active`) and `source_id` in the corpus manifest.
- K3.3 (`removal effect presence`): `removal_effect` non-empty iff
  `role = load-bearing`; value from the closed set.
- K3.4 (`coverage`): recompute — every `active` claim with disposition
  `carried` or `merged` has (≥1 edge with role `load-bearing` or
  `corroborative`) OR (a row in the synthesis/inference markers table). The
  ledger's own "coverage accounting" block must match the recomputation
  (declared counts = actual), and the NEITHER count must be 0.
- K3.5 (`decorative never counts`): the coverage recomputation in K3.4 must
  ignore `decorative` and `contextual` edges — enforced structurally by the
  recomputation itself; additionally fail if the ledger's accounting block
  arithmetic could only balance by counting them
  (`K3.5 (decorative counted)`).
- K3.6 (`unresolved-source cannot confirm`): fail any `carried` claim whose
  entire edge set consists of `unresolved-source` (and/or decorative/
  contextual) edges and which lacks an inference marker —
  `FAIL … K3.6 (unverifiable support): CC-x carried on unresolved-source only`.
- K3.7 (`contradiction preservation`): for every merge-map row, any
  `contradictory` edge attached to an absorbed claim must exist (same
  source, role) on the canonical claim — merges may not shed contradictions.
- K3.8 (`inference markers resolve`): every marker's `claim_id` is `active`
  + carried/merged; every structured `basis_ids` token belongs to the
  `CC`/`PKT` families and resolves; `uncertainty` non-empty.

**False-positive guards:** claims with dispositions other than
carried/merged need no edges at all (sparse manual mode) — K3.4 only ranges
over carried+merged; an *empty* evidence-roles ledger in a run whose
manifest never reached the S6-producing state is fine (K2.1 owns
presence-by-state).

**Battery (minimum 8):** bad role word → K3.1; edge to retracted claim →
K3.2; load-bearing edge with blank effect → K3.3; carried claim with only a
`contextual` edge and no marker → K3.4; accounting block claiming coverage
via a decorative edge → K3.5; carried claim with only `unresolved-source`
support → K3.6; merge where canonical lacks the absorbed claim's
contradictory edge → K3.7; marker citing `CC-999` → K3.8. Clean fixture →
exit 0. Plus the issue-18 seeded cases as **must-fail-somewhere** checks:
the decorative-only-support corpus case must trip K3.4, and the
synthetic-source case must trip K3.6.
