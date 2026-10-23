# Security analysis working file — sprint-1 audit (PR: sprint-261 suite v2 + per-type run caps, KF-048, grader 1.2.11)

Scope: `pr/head.diff` (12 files, +720/-164). `security-audit-scope.sh` found no src/-style sources or sinks (harness lives under `evals/`); catalogued by hand.

## Sources (untrusted or semi-trusted inputs)

| # | Source | Trust | file:line | Status |
|---|--------|-------|-----------|--------|
| S1 | Agent sandbox tree copied to the grading tree (file names, contents) | UNTRUSTED (agent under test) | ablation-grade.sh:1090 (os.walk tree) | SAFE — only files with a reserved basename and not at a fixture/overlay path are unlinked; grader-owned paths kept; writes stay in grading/ |
| S2 | Hidden overlay manifest / fixture tree | TRUSTED (task author) | ablation-grade.sh:1079-1087 | PARTIAL — reserved set over-broad (HIGH-1), directory overlays missed (HIGH-2) |
| S3 | `~/.codex/auth.json` (operator credential) | TRUSTED, SECRET | run-ablation.sh:783, 807-813; pipeline-run.sh:623-642 | SAFE for secrecy (path only in argv/messages, exp only printed); PARTIAL for availability (HIGH-3, MED-1, MED-2) |
| S4 | Suite file `caps.run_usd_by_type` | TRUSTED (operator) | run-ablation.sh:500-507 | PARTIAL — null/false entry silently skipped (LOW-3) |
| S5 | MANIFEST.json caps on --resume | TRUSTED (own output) | run-ablation.sh:448-452 | SAFE — usd_ok on all three caps |
| S6 | `--run-cap`, `--types` argv | TRUSTED (operator) | run-ablation.sh:366-367, 565 | SAFE — usd_ok; jq --arg |

## Sinks

| # | Sink | file:line | Status |
|---|------|-----------|--------|
| K1 | `os.unlink` of grading-tree files | ablation-grade.sh:1098 | CONFIRMED over-deletion (HIGH-1/2); no escape outside tree |
| K2 | Write of `auth.json` copy into per-run HOME (0600) | pipeline-run.sh:636-639 | SAFE — O_CREAT|O_TRUNC 0600 in a fresh dir; host file never opened for write |
| K3 | `refuse` → REFUSED.txt + exit 2 | run-ablation.sh:478-483, 841 | CONFIRMED availability regressions (HIGH-3, MED-1, MED-2) |
| K4 | `pipeline-run.sh --max-run-usd <cap>` | run-ablation.sh:1186 | SAFE — cap validated |
| K5 | `python3 -I -` heredocs with paths in argv | run-ablation.sh:784, pipeline-run.sh:624 | SAFE — no interpolation of data into code |

## Deferred / not assessable here
- The twelve v2 task directories, `seed-bugfix.sh`, `seed-refactor.sh` are outside the PR files (MED-3 confidence low).
- `pr/head/.run/audit.jsonl` is a review-session hook artifact in the workspace, not part of `pr/head.diff`.
