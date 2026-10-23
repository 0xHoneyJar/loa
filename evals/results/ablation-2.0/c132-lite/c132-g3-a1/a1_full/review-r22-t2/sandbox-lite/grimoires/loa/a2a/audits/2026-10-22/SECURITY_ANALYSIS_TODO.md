# Security analysis working file — /audit-sprint sprint-1 (task review-r22), 2026-10-22

Scope: `pr/head.diff` (72 files). Trust levels: `operator` (suite/task yaml, harness repo),
`pr` (the tree under evaluation; untrusted in the eval.yml model), `agent` (what the agent under
test writes inside `sandbox/`; untrusted for evidence per DEC-0413), `cli` (stream-json the CLI
emits; semi-trusted).

## Phase 1A — sources and sinks

| # | Item | file:line | Trust | Status |
|---|------|-----------|-------|--------|
| S1 | task.yaml / suite yaml → jq/yq programs, argv | pipeline-run.sh:178-262 | operator | SAFE (validated: trial int, arm regex in lib, effort enum) |
| S2 | agent-written feedback trailer → gate_verdict | pipeline-run.sh:870-878 | agent | SAFE (awk+jq -r, enum-gated) |
| S3 | stream-json events → price_events / result / session_id → `--resume` argv | pipeline-run.sh:756-761, 655 | cli | SAFE in container mode (transcripts/ not mounted) |
| S4 | sandbox `.eval/cost-ledger.jsonl` rows → SPENT_MICRO / cap | pipeline-run.sh:769-771, 854 | agent | PARTIAL (no sign/shape clamp; LOW) |
| S5 | ARM_ENV_FILE lines → phase env | pipeline-run.sh:672-676 | lib | SAFE (`^LOA_[A-Z0-9_]+=` filter) |
| S6 | PASS_KEYS / SECRET_KEYS → docker argv, captures | pipeline-run.sh:629-632, 692-696, 702-710 | operator env | SAFE (secrets by name only, `<set>` in capture) |
| S7 | `~/.codex/auth.json` → `<run>/meta/home/` | pipeline-run.sh:562-574 | operator cred | CONFIRMED (persists after SIGKILL; MEDIUM) |
| S8 | `$EVAL_PROMPT_TREE/tools/gen-checksums.sh` executed by the harness | lib/sandbox-mount.sh:383-387 | pr | CONFIRMED (trust-boundary; MEDIUM, narrow conditions) |
| S9 | sandbox `.claude/scripts/beads/update-beads-state.sh` executed | lib/sandbox-mount.sh:511-514 | source tree | SAFE in pipeline mode (pinned tree); noted with S8 |
| S10 | `pricing.py` from harness `.claude/adapters` | pipeline-run.sh:586 | harness | SAFE (trusted copy); doc mismatch LOW |
| S11 | arm id → `grep -rIl -F -e "$ARM"` leak guard | pipeline-run.sh:506 | operator | SAFE (regex-validated in lib:163 before use) |
| S12 | review_catch.fixture → path join | lib/sandbox-mount.sh:487-489 | operator | SAFE (`..`/absolute refused) |
| S13 | sandbox envelopes / MODELINV copy → row fields | ablation-row.sh:200-206, 192-198, 236-247 | agent | CONFIRMED (LOW; design accepts) |
| S14 | transcripts tool_use paths → zone_violations | ablation-row.sh:214-221 | cli | PARTIAL (Bash writes invisible; LOW) |
| S15 | `.loa/.claude` heuristic → not-mounted outcome | check-loa.sh:64, 75-76 | local fs | CONFIRMED (MEDIUM, submodule Missing never fires) |
| S16 | `git ls-files` count vs manifest | preflight.sh:188-197 | local fs | CONFIRMED (MEDIUM, count blind to on-disk drift) |
| S17 | sandbox checksums.json vs recorded digest | took-effect.sh:233-268 | agent | CONFIRMED (MEDIUM, digest mismatch not a FAIL) |
| S18 | Dockerfile external deps | Dockerfile.ablation:60-74 | supply chain | PARTIAL (ranges / tag without SHA; LOW) |
| S19 | host executor: operator HOME + bypassPermissions | pipeline-run.sh:657, 723-725 | design | N/A (documented dev mode; observation) |
| S20 | fresh-mount-proof hermetic git | tools/fresh-mount-proof.sh:91-99 | operator | SAFE |
| S21 | gen-checksums path handling | tools/gen-checksums.sh:89-102 | repo | SAFE (NUL-safe, tab/newline/backslash refused) |

## Phase 1B — traced flows

- S4: `ledger_micro` sums `.cost_micro_usd` without a non-negative clamp; a negative row reduces SPENT_MICRO. Agent-authored; cap is a cost control, not a security boundary → LOW.
- S7: `make_home` copies the codex OAuth file; `finish`/`on_exit` remove it; SIGKILL/OOM of the driver leaves it under `evals/results/...` → MEDIUM (CWE-538).
- S8: `regen_sandbox_manifest` runs `${EVAL_PROMPT_TREE}/tools/gen-checksums.sh` when the sandbox is a git work tree tracking `.claude` files; that script `source`s its own tree's `.claude/scripts/compat-lib.sh`. In execute-agent.sh EVAL_PROMPT_TREE is the PR → PR code runs in the trusted harness process. The bats trust-boundary scan (pipeline-run.bats:248-260) covers 4 files and `source` lines only → MEDIUM, confidence medium (conditions rarely hold in current callers).
- S15/S16/S17: integrity surface weakened in three places (see findings).
- Functional blockers (not security, tallied as quality HIGHs): missing `runs/` fixtures; jq 1.6 incompatibility; manifest not regenerated against the new gate.

## Deferred / scope limits

- `.github/workflows/eval.yml` is not in the PR snapshot; the exact EVAL_PROMPT_TREE wiring in CI is inferred from execute-agent.sh:146.
- The upstream tree's committed `.claude/checksums.json` is not in the snapshot; finding on the manifest gate is confidence medium.
- bridgebuilder `dist/*.generated.*` files: generated model-map additions only (gpt-6.1-sol); not audited line by line.
