# Security analysis working file — sprint-1 audit (PR: sprint-261 suite v2 + per-type run caps)

Scope: `pr/head.diff` (12 files under `evals/`). `security-audit-scope.sh --json` found no web
sources/sinks (shell + embedded python harness); recon done by hand.

## Sources (untrusted or semi-trusted input)

| # | Source | file:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | `$HOME/.codex/auth.json` read by the pre-flight | run-ablation.sh:784,812 | operator-owned, local | SAFE (path argv, no token printed; RAB-28) — edge: huge `exp` → uncaught OverflowError (LOW-006) |
| S2 | `$HOME/.codex/auth.json` read by make_home | pipeline-run.sh:622-645 | operator-owned, local | SAFE (python -I, argv paths, 0600 fd) |
| S3 | suite yaml `caps.run_usd_by_type` | run-ablation.sh:500-515 | repo file | SAFE (usd_ok; malformed refused) |
| S4 | MANIFEST.json caps on --resume | run-ablation.sh:447-452 | self-written | SAFE (usd_ok on all three) |
| S5 | task.yaml `.type` (--types filter) | run-ablation.sh:565 | repo file | SAFE (jq --arg) |
| S6 | agent-produced sandbox tree (grading input) | ablation-grade.sh:1074-1104 | UNTRUSTED (LLM output) | CONFIRMED defect: over-broad delete (HIGH-001) |
| S7 | hidden overlay / fixture file names | ablation-grade.sh:1081,1087 | grader-owned | PARTIAL (basename set too wide; MED-001/002) |

## Sinks (dangerous operations)

| # | Sink | file:line | Status |
|---|------|-----------|--------|
| K1 | `os.unlink(p)` on grading trees | ablation-grade.sh:1099 | CONFIRMED over-broad predicate (HIGH-001) |
| K2 | credential file write (`os.open … 0o600`) | pipeline-run.sh:637-641 | SAFE |
| K3 | `refuse` → REFUSED.txt / stderr (info leak?) | run-ablation.sh:841 | SAFE (path + timestamps only) |
| K4 | MANIFEST.json `codex_token_exp`, `codex_preflight` | run-ablation.sh:903 | SAFE (expiry instant only) |
| K5 | pipeline dispatch argv `--max-run-usd` | run-ablation.sh:1186 | SAFE (usd_ok-validated) |
| K6 | spend arithmetic (awk) with per-kind caps | arms-common.sh:128-150, run-ablation.sh:1043-1055 | SAFE |

## Second-order
- Token expiry mid-batch (placeholder refresh ⇒ no renewal): horizon formula has no per-trial floor (MED-003) and over-counts for big batches (MED-004); API-key mode refused (MED-005).
- Pre-existing, not introduced: the container HOME still carries the live access token and id_token readable by the agent under evaluation; the PR narrows this (refresh token replaced). Not tallied.

Deferred: none. Dissent: adversarial-audit.json (Phase 1C) — see feedback file.
