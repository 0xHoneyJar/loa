# Corpus Manifest — RUN-slice-2

## Scope

A bounded synthetic corpus of four source fragments about a token-gated
membership product. Candidate claims include the access primitive, tiering,
retention, referrals, open implementation choices, conflicting free-tier
positions, and proposals that require an explicit non-load-bearing or negative
disposition. The declared scope is the token-gated access model and its immediate
community and growth mechanics. Token-price operations, real market conclusions,
and downstream document generation are outside scope.

## Span-addressing schemes in use

| scheme id | applies to | locator format |
|-----------|------------|----------------|
| md-lines | UTF-8 Markdown source files | `L<start>-L<end>`; 1-based inclusive complete lines joined with LF, including the following LF when the span does not end on the frozen file's final line |

## Source inventory

| source_id | kind | locus | scheme | content_hash | date(s) | trust_class | sensitivity | admission note |
|-----------|------|-------|--------|--------------|---------|-------------|-------------|----------------|
| SRC-101 | deep-research-output | sources/SRC-101-access-model.md | md-lines | sha256:f880cd3abe42bec7bc4000605622d4a1e29d08c8153b4ebf5c958cea48c8181f | 2026-07-16 | model-generated | none | synthetic access-model material inside the declared subject |
| SRC-102 | conversation-export | sources/SRC-102-growth-thread.md | md-lines | sha256:4b7ec8da0d3d6dbc18c3b36169c605bdb167ce9a6ce516c627821a05e732c92e | 2026-07-16 | model-generated | none | synthetic growth discussion containing conflicting and out-of-scope proposals |
| SRC-103 | design-note | sources/SRC-103-gating-rules.md | md-lines | sha256:b6f8c6e31e5274a0aef8493c76d0e6371c6d837d6ee0ed6f8db8896933733538 | 2026-07-16 | model-generated | none | synthetic gating constraints and unresolved implementation choices |
| SRC-104 | design-note | sources/SRC-104-dashboard-profiles.md | md-lines | sha256:f3fa444fc818dca17c3069aa147c30342ee0cdf1dd6344b0a6b15a83fc075c5a | 2026-07-16 | model-generated | none | synthetic longitudinal, cosmetic, and privacy-harm material |

## Corpus-hash procedure

Sort source rows by `source_id`, take each lowercase 64-character content digest
without its `sha256:` prefix, join the four digests with LF and no terminal LF,
then hash those UTF-8 bytes with SHA-256. The result is
`sha256:ccf27103ab6e9855057688bd861df942feec1597fde0283932bbbcc4f2f606a1`.

## Freeze declaration

All four source files were frozen together at S0. The source files reproduce the
four source sections of the accepted slice-2 corpus without summary or semantic
rewriting. Later authority rulings are run-control records, not corpus facts.
