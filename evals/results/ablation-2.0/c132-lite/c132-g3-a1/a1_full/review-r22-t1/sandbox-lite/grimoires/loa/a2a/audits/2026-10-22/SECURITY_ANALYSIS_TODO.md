# Security analysis working file — sprint-1 (review-r22), 2026-10-22

Scope: `pr/head.diff` (72 files). Trust levels: `sandbox/` = UNTRUSTED (agent-writable, PR `.claude/` under test); `--source-tree` = PR-controlled in eval.yml, operator-pinned in ablation-2.0; task/suite yaml = operator; host env = operator.

## Sources (untrusted entry points)

| # | Source | File:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | `sandbox/.eval/model-invoke.jsonl`, `cost-ledger.jsonl` (paths + content) | pipeline-run.sh:713,715,769,773,774 | UNTRUSTED | CONFIRMED → HIGH-001 (symlink), MED-001 (negative rows) |
| S2 | `sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json` | pipeline-run.sh:776; ablation-row.sh:201; took-effect.sh:87 | UNTRUSTED | CONFIRMED → HIGH-001 (copy), LOW-002 (metrics) |
| S3 | `sandbox/grimoires/loa/a2a/sprint-1/*-feedback.md` (gate_verdict) | pipeline-run.sh:793-794,870-878 | UNTRUSTED | SAFE (awk/jq extract only; verdict enum-checked) |
| S4 | `sandbox/.claude/**` executed on host | sandbox-mount.sh:513 (:386) | UNTRUSTED | CONFIRMED → HIGH-002 |
| S5 | CLI stream-json result event (`total_cost_usd`, `num_turns`) | pipeline-run.sh:756-761,853 | CLI (trusted-ish; JSON-escaped tool output) | SAFE |
| S6 | `ARM_ENV_FILE` lines → phase env | pipeline-run.sh:672-676 | library | SAFE (regex `^LOA_[A-Z0-9_]+=` only; tested :231) |
| S7 | task.yaml `fixture`, `review_catch.fixture` | pipeline-run.sh:452-467; sandbox-mount.sh:487-489 | operator | SAFE (hidden-dir refusal; `..`/abs rejected in lib) |
| S8 | suite yaml arm ids / toggles | sandbox-mount.sh:163,255-371 | operator | SAFE (regex id; only `false`/effort enum) |
| S9 | `.claude/checksums.json` symlink target | preflight.sh:183-187 | downstream fs | PARTIAL → LOW-001 |
| S10 | `$HOME/.codex/auth.json` copy into run tree | pipeline-run.sh:570 | operator secret | CONFIRMED → MED-003 |
| S11 | Host env secrets → container/transcripts | pipeline-run.sh:631-632,664-666,694,725 | operator secret | PARTIAL → MED-004 (no redaction); shim/argv path SAFE |
| S12 | `--worktree` overlay of untracked files | fresh-mount-proof.sh:133 | operator fs | PARTIAL → LOW-006 |
| S13 | `git ls-files` manifest paths (names) | gen-checksums.sh:89-102; check-manifest-paths.sh:80 | repo | SAFE (NUL-safe, refuses \n \t \\) |
| S14 | `$HOME/.local/dotfiles/...bats` default | fingerprint.sh:54 | host fs | CONFIRMED → LOW-003 |

## Sinks (dangerous operations)

| # | Sink | File:line | Status |
|---|------|-----------|--------|
| K1 | `docker run` argv/flags | pipeline-run.sh:685-696 | PARTIAL → MED-002 (no cap-drop/no-new-privileges); mounts/env SAFE |
| K2 | `exec "${full[@]}"` host shim | pipeline-run.sh:723-725 | SAFE (no eval; env via export; keys exact) |
| K3 | `bash "$ubs"` / `"$tool" --root` | sandbox-mount.sh:513,386 | CONFIRMED → HIGH-002 |
| K4 | `yq -i` on sandbox config, `jq … > file` | sandbox-mount.sh:249,286,332 | SAFE (sandbox copy only, verified after) |
| K5 | `cp -a "$FIXTURE_DIR/." "$WS/"` | pipeline-run.sh:457 | SAFE (operator fixture; path rule) |
| K6 | `git -C "$MANIFEST_TREE" ls-files` | preflight.sh:190 | CONFIRMED → HIGH-003 (index not worktree), LOW-001 (tree choice) |
| K7 | `check_integrity` Missing/not-mounted | check-loa.sh:69-80 | CONFIRMED → HIGH-004 |
| K8 | Spend arithmetic (`SPENT_MICRO`, `budget`) | pipeline-run.sh:719,854,864; spend.sh:129; ablation-row.sh:242,312 | CONFIRMED → MED-001 |
| K9 | Integrity evidence rule | took-effect.sh:254-267 | CONFIRMED → MED-005 |
| K10 | `sed -i … "$f"` path hygiene in fixtures | regen.sh:83 | SAFE (fixture tree only; dev tool) |
| K11 | `mv -f "$GEN" "$OUT"` manifest write | gen-checksums.sh:137 | SAFE (replaces symlink, no write-through) |
| K12 | CI gate `gen-checksums.sh --check` | bats-tests.yml:178 | CONFIRMED → MED-006 (red as shipped) |
| K13 | npm ignore-scripts | Dockerfile.ablation:77,91 | CONFIRMED → MED-007 |
| K14 | `FROM rust:1-bookworm` + unlocked cargo | Dockerfile.ablation:19-20 | CONFIRMED → LOW-005 |
| K15 | `zone_violations` extraction | ablation-row.sh:208-222 | PARTIAL → LOW-007 |

## Deferred / not traced

- `evals/harness/execute-agent.sh`, `freeze.sh`, `validate-suite.sh` changes: read for header/contract only; no new sink found in the diff hunks beyond what the review covers.
- Live bats runs not repeated (review's runs relied on). `shellcheck` unavailable.
- Dissent DISS-C-007 (managed header hash): body sha256 identical base/head → not a defect.
