# Corpus Manifest — RUN-exact-evidence-fragments

## Scope

Synthetic text used only to exercise exact source bytes, ordered fragments,
display rendering, normalization separation, and a degraded non-exact record.

## Span-addressing schemes in use

| scheme id | applies to | locator format |
|-----------|------------|----------------|
| md-lines | UTF-8 Markdown source files | `L<start>-L<end>`; one-based inclusive complete lines, including the following LF unless the span ends on the final line |

## Source inventory

| source_id | kind | locus | scheme | content_hash | date(s) | trust_class | sensitivity | admission note |
|-----------|------|-------|--------|--------------|---------|-------------|-------------|----------------|
| SRC-301 | design-note | sources/SRC-301-exact-evidence.md | md-lines | sha256:f53ee9454205a5ca11c300add045a2cccf2748063383b68c79029b65fa831e6c | 2026-08-13 | model-generated | none | synthetic bytes selected to exercise the exact-evidence format |

## Corpus-hash procedure

This one-source fixture hashes the lowercase source content digest, without
the `sha256:` prefix, as UTF-8 with no terminal LF.

## Freeze declaration

The source file is frozen for this fixture. Display and normalized text live
only in transformation rows and never replace its exact bytes.
