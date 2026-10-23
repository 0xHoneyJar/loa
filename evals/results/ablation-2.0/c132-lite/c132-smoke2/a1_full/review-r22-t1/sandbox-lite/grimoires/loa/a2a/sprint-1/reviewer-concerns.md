# Reviewer concerns (Phase 2, preliminary) — sprint-1 / PR sprint-258

Scope: pr/head.diff (72 files): check-loa.sh mount integrity (#1267), evals/harness spend.sh,
took-effect.sh, ablation-row.sh, run-arms.sh, pipeline-run.sh, execute-agent.sh, sandbox-mount.sh,
validate-suite.sh, freeze.sh, fingerprint.sh, tools/check-manifest-paths.sh, tools/gen-checksums.sh,
tools/fresh-mount-proof.sh, bats tests and fixtures, model-config gpt-6.1-sol repoint.

Initial concerns:
- check-loa.sh check_integrity now ends with `return 0` — drift may no longer affect the exit code.
- not-mounted classification relies only on `.loa/.claude` being a directory and `.loa/<path>` existing.
- spend caps "as scripts": verify cap arithmetic, jq numeric parsing, and fail-closed on malformed ledgers.
- took-effect evidence: verify row schema matches what ablation-row.sh writes.
- container executor (pipeline-run.sh / execute-agent.sh): verify docker arg quoting, mount read-only flags,
  env leakage of credentials into the container, and cleanup on failure.
- tests: do assertions actually exercise the new branches, or stub everything away?
