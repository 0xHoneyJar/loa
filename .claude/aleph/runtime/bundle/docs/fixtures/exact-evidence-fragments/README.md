# Exact Evidence and Ordered Fragments Fixture

```aleph-fixture
kind: run
src_ids: SRC-301
```

This synthetic `1.1.0-provisional` `DISTILLING` run exercises the mandatory
forward K2.2 execution-identity shape and the
`aleph-exact-evidence/v1` packet-ledger extension. Its content-addressed
identity values are fixture-simulated structural pins, not claims about the
repository's current bundle or runtime. It contains:

- one exact single fragment with curly quotation marks and a ligature;
- two exact adjacent fragments;
- two ordered discontiguous exact fragments;
- rendered and normalized text that differs from exact source bytes; and
- one explicitly degraded, source-bound non-exact rendering with no packet or
  exact hash.

The fixture proves only deterministic source-byte and structural fidelity. It
does not prove semantic entailment, normalization quality, packetization
quality, extraction completeness, source trustworthiness, or live compatibility
with retained host authority.

## Validation

```text
node scripts/validate-run.ts --run docs/fixtures/exact-evidence-fragments
node scripts/test-conformance-mutations.ts --group K2E
```
