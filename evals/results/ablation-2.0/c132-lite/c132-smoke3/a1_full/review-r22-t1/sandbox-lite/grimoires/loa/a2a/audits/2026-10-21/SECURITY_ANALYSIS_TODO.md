# Security analysis working file — sprint-1 audit (PR: Sprint 258, 72 files)

Date: 2026-10-21. Scope: `pr/head.diff`; lines cite `pr/head/`. Trust levels: OPERATOR (the
person running the harness), MOUNTED TREE (`--source-tree` / `$EVAL_PROMPT_TREE`, copied into the
sandbox `.claude/`), AGENT (the model under test, writes anywhere under `sandbox/`), FIXTURE
(task/review-catch data), CI (checkout of the PR).

## Sources (untrusted entry points)

| # | Source | file:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | `--source-tree` → `mount_prompt_surface` copies the whole `.claude/` into the sandbox | pipeline-run.sh:484, sandbox-mount.sh:131 | MOUNTED TREE | CONFIRMED → sink K1 (init_sandbox_beads executes a copied script on the host) |
| S2 | `$EVAL_PROMPT_TREE/tools/gen-checksums.sh` | sandbox-mount.sh:383 | MOUNTED TREE | PARTIAL (branch dead from pipeline-run.sh; sources that tree's compat-lib.sh when taken) |
| S3 | task.yaml / TASK.md / suite.yaml fields (`id`, `type`, `criterion`, `fixture`, arm ids, toggles) | pipeline-run.sh:178-262, sandbox-mount.sh:163,444-447 | FIXTURE | SAFE (regex-validated ids, enum-checked toggles, `..`/absolute refused for review_catch.fixture at :488) |
| S4 | Agent-written files under `sandbox/` (feedback trailers, adversarial-*.json, model-invoke.jsonl, cost-ledger.jsonl, transcripts) | pipeline-run.sh:756-777,793-794; ablation-row.sh:200-203; took-effect.sh:86-89 | AGENT | PARTIAL (parsed by jq only; envelopes decide `degraded`/`voices_run` — L2) |
| S5 | Transcript events (stream-json) | pipeline-run.sh:599-613,756-767; ablation-row.sh:214-221 | AGENT | SAFE as data; measurement gap for Bash writes — L3 |
| S6 | Environment: `AWS_BEARER_TOKEN_BEDROCK`, `PASS_KEYS`, `LOA_EVAL_*`, `$HOME/.codex/*` | pipeline-run.sh:562-573,629-632,661-676 | OPERATOR | SAFE for leakage into argv/captures (`<set>` redaction verified :705-706); exposure scope — M4 |
| S7 | `.claude/checksums.json` entries (path, hash) | check-loa.sh:60-77, preflight.sh:181-191 | SYSTEM ZONE / mount symlink | PARTIAL (not-mounted classification — M1; symlink-chosen tree — L1) |
| S8 | `$HOME/.local/dotfiles/.../bats` fallback | fingerprint.sh:54 | HOST FS | CONFIRMED (L4) |

## Sinks (dangerous operations)

| # | Sink | file:line | Reached by | Status |
|---|------|-----------|-----------|--------|
| K1 | `bash "$ws/.claude/scripts/beads/update-beads-state.sh" --opt-out` on the HOST | sandbox-mount.sh:513 | S1 via pipeline-run.sh:489 when `br` is not on PATH | CONFIRMED (H1) |
| K2 | `"$tool" --root "$ws"` (gen-checksums.sh from the prompt tree; it `source`s compat-lib.sh) | sandbox-mount.sh:386 | S2 when `$ws` is a git repo tracking `.claude` | PARTIAL (dead from pipeline-run.sh: :476 excludes `/.claude/`) — M2 |
| K3 | `docker run … --network bridge -v sandbox -v meta/home` with `-e KEY` by name for secrets | pipeline-run.sh:685-696 | S6 | SAFE (secrets by name; two mounts; read-only root; pids/mem/cpu limits) |
| K4 | `python3 -I -c "$ENV_SHIM" … exec` (host) with exported allowlist | pipeline-run.sh:723-725 | S6 | SAFE (allowlist keys only; no eval) |
| K5 | `cp $CREDS_HOME/.codex/{auth.json,config.toml}` into `meta/home` mounted rw in the container | pipeline-run.sh:569-571 | S6 → AGENT-readable | CONFIRMED (M4: copied for every arm; survives SIGKILL) |
| K6 | `yq -i` / `jq` rewrites of the sandbox `.loa.config.yaml`, `CLAUDE.loa.md`, `SKILL.md`, `constraints.json` | sandbox-mount.sh:249-250,286,332 | S3 toggles (enum-checked) | SAFE (sandbox copy only, verified after write) |
| K7 | `jq --argjson` with whole ledgers/pipeline.json/envelopes as argv strings | ablation-row.sh:224-228 | S4 size | CONFIRMED (H4, E2BIG reproduced at 140 KB) |
| K8 | `git -C "$SRC" ls-files` / `mount-submodule.sh` inside a temp dir | fresh-mount-proof.sh:118-156 | OPERATOR | SAFE (hermetic git env, temp dir only) |
| K9 | `mv -f "$GEN" "$OUT"` (manifest write) | gen-checksums.sh:137 | OPERATOR | SAFE (replaces a symlinked manifest instead of writing through; documented) |
| K10 | `price_for` → `python3 -I $REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py` | pipeline-run.sh:586 | HARNESS (trusted copy) | SAFE (trusted copy, not the mounted tree; header wording at :125 is imprecise) |

## Second-order flows

- Agent writes `grimoires/loa/a2a/sprint-1/adversarial-*.json` → copied to `eval/` (pipeline-run.sh:776-778) → read by ablation-row.sh / took-effect.sh as evidence. Both copies are agent-authored. (L2)
- Agent-controlled `.claude/` edits via Bash are invisible to `dot_claude_writes` (ablation-row.sh:216-220); took-effect `integrity_clean` (took-effect.sh:233-268) would catch content drift when the arm lists that rule. (L3)

## Deferred / not assessed

- `evals/harness/run-arms.sh` spend arithmetic (awk floats) — read, no sink; not traced further.
- `evals/harness/validate-suite.sh` python validator — allowlist for `test_command[0]` read (`:118`), not fuzzed.
- `.claude/skills/bridgebuilder-review/dist/*` generated JS — catalog entry only (`gpt-6.1-sol`), not reviewed line by line.
