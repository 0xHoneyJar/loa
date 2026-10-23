# Security analysis working file — sprint-1 (PR: sprint-258, cycle-130)

Date: 2026-10-23. Scope: `pr/head.diff` (72 files). Trust context assumed: the harness under `evals/harness/` is the trusted grader copy; the `.claude/` tree it mounts (source tree, prompt tree, sandbox copy) is the artefact under evaluation and is untrusted (eval.yml "Validate grader trust boundary", quoted at `head/evals/harness/pipeline-run.sh:125-126`). The agent that runs inside the sandbox is semi-trusted (a Claude session over untrusted fixture content).

## Sources (untrusted or semi-trusted inputs)

| # | Source | Trust | Status |
|---|--------|-------|--------|
| S1 | Sandbox `.claude/` copy (`<ws>/.claude/**`) | untrusted (PR tree) | CONFIRMED → sink K1 |
| S2 | `$REPO_ROOT/.claude/adapters/**` (harness checkout's .claude) | untrusted in eval.yml layout | CONFIRMED → sink K2 |
| S3 | `$EVAL_PROMPT_TREE/tools/gen-checksums.sh` | untrusted (prompt tree) | PARTIAL → sink K3 (gated) |
| S4 | task.yaml / suite yaml | operator-trusted | SAFE (regex-validated ids, `..` rejected) |
| S5 | Agent-written sandbox files: `.eval/cost-ledger.jsonl`, `grimoires/loa/a2a/sprint-1/adversarial-*.json`, transcripts | semi-trusted | PARTIAL → sinks K4, K5 |
| S6 | `claude` stream-json events | semi-trusted | SAFE (parsed with jq, `fromjson?`) |
| S7 | Fixture tree contents (`cp -a`) | operator-trusted | SAFE (hidden-path and arm-id guards) |
| S8 | Operator credentials: `$HOME/.codex/auth.json`, `AWS_BEARER_TOKEN_BEDROCK` | secret | PARTIAL → sinks K6, K7 |
| S9 | `.claude/checksums.json` manifest + working tree | integrity data | CONFIRMED → sinks K8, K9 |

## Sinks

| # | Sink | File:line | Status |
|---|------|-----------|--------|
| K1 | `bash "$ubs" --opt-out` executes sandbox `.claude/scripts/beads/update-beads-state.sh` on the host | `head/evals/harness/lib/sandbox-mount.sh:513` | CONFIRMED (HIGH-001) |
| K2 | `python3 -I .../.claude/adapters/loa_cheval/metering/pricing.py` with cwd in `.claude/adapters` | `head/evals/harness/pipeline-run.sh:586` | CONFIRMED (HIGH-002) |
| K3 | `"$tool" --root "$ws"` where tool = `${EVAL_PROMPT_TREE}/tools/gen-checksums.sh` (sources prompt tree's compat-lib.sh) | `head/evals/harness/lib/sandbox-mount.sh:383-386` | PARTIAL — gated on sandbox tracking `.claude` (MED-008) |
| K4 | Ledger rows summed into `SPENT_MICRO` without sign/shape validation | `head/evals/harness/pipeline-run.sh:770,854` | PARTIAL (LOW-009) |
| K5 | Dissent envelopes read from sandbox path for row quality fields / took-effect rule | `head/evals/harness/ablation-row.sh:201`, `head/evals/harness/took-effect.sh:87` | PARTIAL (LOW-010) |
| K6 | codex `auth.json` copied into `<run>/meta/home`, mounted rw into the agent container | `head/evals/harness/pipeline-run.sh:570,690` | CONFIRMED by design (MED-003, MED-004) |
| K7 | `AWS_BEARER_TOKEN_BEDROCK` forwarded by name into the agent container | `head/evals/harness/pipeline-run.sh:694` | SAFE in argv/capture (`<set>`); exposed to agent by design (MED-004) |
| K8 | preflight count from `git ls-files` (index, not working tree) | `head/.claude/scripts/preflight.sh:190` | CONFIRMED (HIGH-005) |
| K9 | check-loa `not-mounted` informational branch | `head/.claude/scripts/check-loa.sh:76` | CONFIRMED (MED-005) |
| K10 | jq programs binding `$label` / `{label}` shorthand | `head/evals/harness/pipeline-run.sh:708,816,882`, `head/evals/harness/ablation-row.sh:285` | CONFIRMED on jq 1.6 (HIGH-003) |
| K11 | `printf '%s\0' … \| jq -Rs 'split("\u0000") \| .[:-1]'` | `head/evals/harness/pipeline-run.sh:704-707` | CONFIRMED on jq 1.6 (HIGH-004) |

## Dismissed

- DISS-C-002 (review round) `check_integrity` `return 0`: `fail()` increments `FAILURES` (`head/.claude/scripts/check-loa.sh:36`) and `main` exits 1 on it (`:603-605`). Not a defect.
- `ENV_SHIM` `os.execvpe` PATH lookup: `PATH` is in both key sets, so the search path is the allowlisted one. Safe.
- `remove_tree` on `$HOME_DIR`: `find -depth -delete` does not follow symlinks; `HOME_DIR` is under the validated-empty run dir. Safe.
- `write_sandbox_grimoire` `rcfx`: `*..*|/*` rejected before path assembly. Safe.
- Model catalog `gpt-6.1-sol` fallback cycle: `codex-headless` is a chain terminal with no `fallback_chain` ("Chain terminals MUST NOT declare fallback_chain", `head/.claude/defaults/model-config.yaml:213-214`). No cycle today; placeholder pricing kept as LOW-012.

## Deferred (time budget)

- Full trace of `tools/fresh-mount-proof.sh` overlay copying untracked, non-ignored files into the temp clone (temp-only, deleted; no finding).
- `run-arms.sh --screen` batch-dir handling beyond the regex checks already present.
