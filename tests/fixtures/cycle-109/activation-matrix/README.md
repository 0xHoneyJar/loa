# cycle-109 Sprint 3 T3.1 — Activation Regression Matrix Scaffolding

810-cell CI matrix per PRD §FR-3.10 / SDD §5.3.5 / IMP-009. Tests every
substrate-touching consumer against every (role × response_class ×
dispatch_path) combination so Cluster-B-class regressions
(#864 / #863 / #793 / #820) are impossible by construction.

## Dimensions

| Dimension | Count | Source |
|---|---|---|
| Consumers | 9 | `dimensions.json::consumers[]` (BB / FL / RT / /bug / /review-sprint / /audit-sprint / flatline-readiness / adversarial-review / post-pr-triage) |
| Substrate roles | 5 | `dimensions.json::roles[]` (review / dissent / audit / implementation / arbiter) |
| Provider response classes | 6 | `dimensions.json::response_classes[]` (success / empty-content / rate-limited / chain-exhausted / provider-disconnect / context-too-large-preempt) |
| Dispatch paths | 3 | `dimensions.json::dispatch_paths[]` (single / chunked-2 / chunked-5) |
| **Total cells** | **810** | 9 × 5 × 6 × 3 |

## Sprint 3 commit sequence (SDD §5.3.1)

| Commit | Task | Matrix behavior |
|---|---|---|
| A | T3.1 (THIS) | Scaffolding + dimensions + harness. Cells SKIP (legacy still on disk). |
| B | T3.2-T3.5 | Cluster B fixes at cheval path. Cells still SKIP. |
| C | T3.6 | `is_flatline_routing_enabled` branches removed. Matrix wires up against cheval path; cells run. |
| D | T3.7 | **DESTRUCTIVE — operator-approval marker C109.OP-S3 required first**. Legacy file deletion. |
| E | T3.8 | `hounfour.flatline_routing` flag fully removed. |
| F | T3.9 | CLAUDE.md + runbook updates. |

## How to extend

1. Add new consumer / role / response class / dispatch path to `dimensions.json`.
2. Recompute expected cell count (`consumers × roles × response_classes × dispatch_paths`).
3. Bats harness reads from `dimensions.json`; tests auto-generate from data.

## Fixture inputs

Per-cell fixture inputs live at
`tests/fixtures/cycle-109/activation-matrix/cells/<consumer>/<role>/<response_class>/<dispatch_path>.json`.
Fixtures are loaded by `tests/integration/activation-path/activation-matrix.bats`
via the cycle-099 sprint-1C curl-mock harness — mock-only, no live provider
calls (FR-3.10 / C109.OP-7: `requires-substrate-billing: false`).

## CI workflow

`.github/workflows/activation-regression.yml` (lands in T3.10) runs the matrix
on every PR touching substrate code. Matrix-job split per consumer (9 jobs);
strategy.fail-fast=false; per-job sequential roles × response_classes ×
dispatch_paths (90 cells per job). Wall-time budget <15 min.
