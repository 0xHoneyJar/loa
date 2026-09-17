# MODELINV mixed-writer fixture (cycle-124 Sprint 1 U0)

`mixed-writer-rows.jsonl` is a committed `.run/model-invoke.jsonl` stand-in that
mixes MODELINV writer generations so every consumer can be exercised against
rows that both lack and carry the cycle-124 optional payload fields
(`tokens_cache_read`, `tokens_cache_creation`, `schema_enforced`,
`output_schema_sha256`). Row shapes are copied from real rows in the live log
(secrets: none; paths: none).

Pinned by `.claude/adapters/tests/test_modelinv_optional_fields.py`, which runs
`economy.py`, `health.py`, `journal.py`, `tools/modelinv-rollup.sh` and
`tools/modelinv-coverage-audit.py` over it and asserts each produces the same
aggregate with the four fields stripped (no consumer aggregates cache tokens
today; absent == 0 is pinned as invariance).

## Row inventory

| # | ts_utc | writer | shape | cycle-124 fields |
|---|--------|--------|-------|------------------|
| 1 | 2026-05-12 | v1.1 (no `writer_version`) | anthropic HTTP, minimal | absent |
| 2 | 2026-05-21 | 1.3 | anthropic HTTP + tokens | absent |
| 3 | 2026-05-21 | 1.3 | codex-headless (cli) | absent |
| 4 | 2026-05-23 | 1.3 | claude-headless (cli) | absent |
| 5 | 2026-06-11 | 1.3 | chain exhausted (4 failures, nothing succeeded) | absent |
| 6 | 2026-06-20 | 1.3 | anthropic HTTP, priced | explicit `0 / 0 / false` |
| 7 | 2026-06-20 | 1.3 | anthropic HTTP, first call | `tokens_cache_creation: 18432`, `schema_enforced: true`, sha |
| 8 | 2026-06-20 | 1.3 | anthropic HTTP, second call | `tokens_cache_read: 18432`, `schema_enforced: true`, sha |
| 9 | 2026-06-21 | 1.3 | claude-headless with `--json-schema` | `0 / 0 / true`, sha |
| 10 | 2026-06-21 | 1.3 | codex-headless (schema not forwarded) | `schema_enforced: false` only |
| 11 | 2026-06-28 | 1.3 | chain walked codex-headless -> gpt-5.5-pro | explicit `0 / 0 / false` |

No row carries `writer_version: "1.2"` on purpose: `modelinv-rollup.sh`
hard-pins `"1.2"` in its strip detector and would exit 1 on any later row that
is not `"1.2"` (the live-log false positive tracked as a separate bead).

## Hash chain

The file is a valid GENESIS-rooted, unsigned audit chain: `modelinv-rollup.sh`
fail-closes on `audit_verify_chain` before aggregating, so the test runs it
with default flags (no `--no-chain-verify`, no `LOA_AUDIT_VERIFY_SIGS=0`).
Unsigned rows verify only while `ts_utc` is earlier than
`trust_cutoff.default_strict_after` in `grimoires/loa/trust-store.yaml`
(`2026-06-29T00:00:00Z` at authoring time). Keep every timestamp before that
cutoff, or sign the rows.

To edit a payload: change the row, then recompute `prev_hash` for it and every
later row (the test module's `_rechain()` helper does exactly this with
`loa_cheval.audit_envelope._chain_input_bytes`). The test asserts the committed
hashes equal a fresh rechain, so a stale chain fails loudly.

## `output_schema_sha256` value

Rows 7 to 9 carry the canonical hash
(`json.dumps(schema, sort_keys=True, separators=(",", ":"))`) of this output
schema:

```json
{"type":"object","additionalProperties":false,"required":["verdict","findings"],
 "properties":{"verdict":{"enum":["APPROVED","CHANGES_REQUIRED"]},
  "findings":{"type":"array","items":{"type":"object",
   "required":["file","line","severity","confidence","summary"],
   "properties":{"file":{"type":"string"},"line":{"type":"integer","minimum":1},
    "severity":{"enum":["critical","high","medium","low"]},
    "confidence":{"enum":["high","medium","low"]},"summary":{"type":"string"}}}}}}
```
