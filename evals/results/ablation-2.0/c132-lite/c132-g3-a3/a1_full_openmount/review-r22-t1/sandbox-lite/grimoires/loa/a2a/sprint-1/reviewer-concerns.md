# Reviewer concerns — sprint-1 (PR: sprint-258, cycle-130)

Scope: 72 files. Substantive code: evals/harness/{pipeline-run.sh, lib/sandbox-mount.sh, ablation-row.sh, took-effect.sh, spend.sh, validate-suite.sh, freeze.sh, fingerprint.sh, run-arms.sh, execute-agent.sh}, tools/{gen-checksums.sh, check-manifest-paths.sh, fresh-mount-proof.sh}, .claude/scripts/{check-loa.sh, preflight.sh}, Dockerfile.ablation, plus bats tests and fixtures.

Initial concerns to pressure-test:
- Dockerfile.ablation: `brbuild` stage installs beads_rust 0.2.6 which the same file says is not on crates.io; stage is never referenced. Dead/failing build stage?
- check-loa.sh check_integrity: new `return 0` — does the caller depend on the return status to fail the run on drift?
- preflight.sh symlink resolution of checksums.json for submodule mounts — relative readlink handling.
- pipeline-run.sh container executor: mount set, --user, HOME copy of codex auth.json (credential handling), --read-only, env passing of AWS_BEARER_TOKEN_BEDROCK; argument quoting; cleanup traps; exit-code propagation.
- sandbox-mount.sh: symlink/mount scoping, path traversal from manifest paths, beads opt-out marker.
- spend.sh caps: integer/float arithmetic in bash, ledger parsing, cap enforcement semantics (>= vs >).
- took-effect.sh / ablation-row.sh: jq construction with untrusted strings, row schema consistency with fixtures.
- validate-suite.sh / run-arms.sh: yq parsing, arm toggles correctness.
- Tests: do bats assertions actually exercise the failing paths, or only happy paths? Stubs (docker-stub, claude-stub) fidelity.
