# Security analysis working file — sprint-1 audit (pr/head.diff), 2026-10-21

Trust levels: AGENT = the sandboxed agent session (untrusted; runs the PR's `.claude/` with bypassPermissions); FIXTURE = task/PR fixture content (operator corpus, may carry third-party PR text); SUITE = suite/task yaml (operator); OPERATOR = env/argv.

## Sources (untrusted entry points)

| # | Source | Trust | Status | Note |
|---|--------|-------|--------|------|
| S1 | `sandbox/` tree after a phase (incl. `.git/`) | AGENT | CONFIRMED | → K1 host git (HIGH-001); → K2 cp/awk symlink follow (LOW-001) |
| S2 | `sandbox/grimoires/loa/a2a/sprint-1/*.md` verdict trailers | AGENT | SAFE | awk + jq parse only (`pipeline-run.sh:870-878`); measurement by design |
| S3 | `transcripts/events-*.jsonl` (CLI stdout) | AGENT-adjacent | SAFE | `fromjson?` in jq; arithmetic only (`:599-613`) |
| S4 | dissent envelopes under sandbox/ | AGENT | PARTIAL | read first by row/took-effect readers (LOW-002) |
| S5 | `pr/` fixture (base/head/PR.md) | FIXTURE | SAFE | `cp -a` into sandbox; `.git` nested dirs never executed; leak guards |
| S6 | task.yaml / suite yaml | SUITE | SAFE | ids regex-checked (`sandbox-mount.sh:163, 442, 446`); toggles validated (`:265-269`) |
| S7 | `ARM_ENV_FILE` lines | SUITE via lib | SAFE | `^LOA_[A-Z0-9_]+=` filter (`pipeline-run.sh:673`) |
| S8 | `$CREDS_HOME/.codex/*` | OPERATOR | PARTIAL | copied into run dir; lifetime (MED-001) |
| S9 | `.claude/checksums.json` symlink target | LOCAL WRITE | N/A | needs checkout write access (dissent DISS-C-003 part 2; not recorded) |

## Sinks (dangerous operations)

| # | Sink | Status | Note |
|---|------|--------|------|
| K1 | `sgit add/commit/bundle` on `$WS/.git` (`pipeline-run.sh:783-787`) | CONFIRMED | hooks + fsmonitor reproduced on host → HIGH-001 |
| K2 | `cp`/`wc`/`awk` on sandbox paths (`:713, :715, :773-777, :793-794`) | CONFIRMED (low) | symlink follow → LOW-001 |
| K3 | `docker run` argv (`:685-696`) | SAFE | secrets by `-e KEY` only; name sanitised (`:681`) |
| K4 | `python3 -I -c ENV_SHIM` (`:624-628`) | SAFE | no eval; allowlist keys |
| K5 | `price_for` → `.claude/adapters/.../pricing.py` (`:586`) | PARTIAL | trusted harness tree; silent null → MED-003 |
| K6 | `yq -i` / `jq` rewrites of sandbox config (`sandbox-mount.sh:249, 286, 332`) | SAFE | pre-agent, operator values, verified after |
| K7 | `init_sandbox_beads` runs `$ws/.claude/scripts/beads/update-beads-state.sh` (`sandbox-mount.sh:513`) | SAFE | pre-agent; the mounted tree is the pinned source tree, not the PR's |
| K8 | `regen_sandbox_manifest` runs `$EVAL_PROMPT_TREE/tools/gen-checksums.sh` (`:383-386`) | SAFE | pre-agent; harness/pinned tree |
| K9 | `preflight.sh` / `check-loa.sh` integrity decisions | CONFIRMED | detection regressions → HIGH-003, HIGH-004 |
| K10 | `cargo install` in Dockerfile stage (`Dockerfile.ablation:19-20`) | PARTIAL | legacy builder only → MED-004 |
| K11 | `run-arms.sh` budget gate arithmetic (awk) | SAFE | numeric regex on inputs (`usd_ok`) |

## Deferred / scope limits

- `mount-submodule.sh` read only for link-set persistence (unchanged by the PR).
- Host executor mode (`--executor host`) runs the agent on the operator host by design; not a defect of the change.
