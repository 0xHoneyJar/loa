# Templates 07 — Verification Records

## T7.1 Verifier verdict → `runs/<run-id>/verification/harness/⟨stage⟩/VER-⟨NNNN⟩.md`

```markdown
# Verdict VER-⟨NNNN⟩
| field | value |
|-------|-------|
| target | ⟨artifact path + ID(s) under review⟩ |
| lens | ⟨lens id from prompts/verifier-lenses.md⟩ |
| stage | ⟨S2 coverage \| S3 entailment \| S4 merge \| S5 disposition \| …⟩ |
| shown | ⟨exact bundle contents: files/sections provided⟩ |
| withheld | ⟨what the blind rule kept out — state it explicitly⟩ |
| verdict | ⟨upheld \| refuted \| cannot-determine⟩ |
| consequence | ⟨none \| flagged \| forced-unresolved \| superseding row ⟨ref⟩⟩ |

## Rationale
⟨One paragraph. The written rationale is the audit record. For `refuted`:
the specific failure and the evidence. For `cannot-determine`: what was
missing. Never "looks fine".⟩
```

Rules: `shown`/`withheld` are mandatory — a verdict without a fresh-context
attestation is invalid; consequences are applied by the orchestrator as
superseding ledger rows citing this `VER` id (verdicts never edit ledgers);
quorum panels produce one verdict file per member plus a one-line quorum
summary in the stage folder's `README.md`.

For a typed-relation review, `target` is exactly
`relation-review-subject:sha256:<64 lowercase hex>`, identifying one complete
pre-canonical relation subject. Only `upheld` may be cited by a REL row.
`refuted` recommends `revise`, `reject`, or `not-applicable`; a revision is a
new complete subject/digest/review. `cannot-determine` cannot authorize the
original row; retaining an indeterminate canonical assessment requires its
own complete proposal and upheld verdict. Exact target binding proves neither
semantic correctness nor fresh-context independence.

<!-- example -->
| target | ledgers/claim-inventory.md CC-107 |
| lens | disposition-refuter |
| stage | S5 |
| shown | CC-107 row (without rationale), PKT-0044/0045 quotes+locators, scope statement, extraction criteria |
| withheld | judge's rationale; all other claims' dispositions; merge map |
| verdict | upheld |
| consequence | none |

## T7.2 Sampling record → `runs/<run-id>/verification/sampling-record.md`

```markdown
# Sampling Record — ⟨RUN-slug⟩
<!-- Honesty artifact: what verification actually covered. Renders into
     Précis §16/§17. -->
| stage | check | policy | population | checked | exhaustive-classes covered | changes caused (VER ids) |
|-------|-------|--------|------------|---------|----------------------------|--------------------------|
```

Rules: `policy` names the rule used ("all exclusions + all contradictions +
5/disposition-class stratified"); `population`/`checked` are counts; every
row's exhaustive classes (doc 06 §3: all `excluded-with-reason`, all
contradictions, merges above threshold, all load-bearing edges in
adversarial clusters) must show full coverage or the gap is carried verbatim
into Précis §17.

<!-- example -->
| S5 | disposition adversarial review | all exclusions + contradictions; 5/class sample | 14 claims | 9 | yes | VER-0032 (CC-104 note) |

## L2F exact material use review (1.6)

Use the existing VER field table with lens `L2F`, stage `S3` or `S4`, and target `representation-use-subject:sha256:<64-lowercase-hex>`. Verdicts remain `upheld`, `refuted`, or `cannot-determine`; candidate_evidence is empty. Only upheld permits the identical reserved usable CC/REL subject. The canonical use receipt names that VER. Show the exact subject, packet bytes/hashes, selected structural dependencies and provenance/limitations; withhold producer rationale, other batches, dispositions, authority responses, narratives and calibration answers. A retained VER is structural evidence, not proof of live freshness.

## Slice 7 semantic review (1.7)

L2S has the dedicated closed SemanticResult contract in T3.7. Keep the canonical JSON plus the T7.1 companion with exact target semantic-review-subject:sha256:<hex>, L2S lens and stage. Every field has an ordered review slot; candidate_evidence is exactly []. Assignment and execution evidence are retained outside reviewer attachments.
