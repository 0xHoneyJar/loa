# ledger-hygiene sentinel fixtures (cycle-124 FR-6)

Contract fixtures for `tools/check-ledger-hygiene.sh`, consumed by
`tests/integration/ledger-hygiene-tripwire.bats` and the positive/negative
control steps in `.github/workflows/bats-tests.yml`. Each directory is a
miniature `.run/` holding both production ledger files.

| Directory | Expected scan result |
|-----------|----------------------|
| `clean/` | exit 0 — one real-shaped row per ledger |
| `mock-row/` | exit 1 — `cost-ledger.jsonl:3` carries a `mock-review` identity (line 2 is a deliberately corrupt line the scanner must skip) |
| `e2e-path/` | exit 1 — `model-invoke.jsonl:2` names a `/tmp/cheval-e2e-empty-*` fixture dir |

Rows are copies of real ledger shapes (2026-05); the MODELINV rows are not a
verifiable chain and are never passed to `audit-envelope.sh verify-chain`.
