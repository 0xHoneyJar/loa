# Reviewer concerns — sprint-1 (PR: cycle-129 sprint-256)

Phase 2 notes handed to the adversarial dissent as context. Line numbers are in `pr/head/`.

## Verified by execution

1. `.claude/scripts/run-checkpoint.sh:378` — `--arg label "$label"` and `$label` inside the jq program. `label` is a jq keyword; jq 1.6 (Debian stable default) rejects `$label` with "unexpected label, expecting IDENT or __loc__". `derive` exits 3, `write` prints the compile errors plus a misleading "not valid JSON — not written" and never stamps `derived_at`. The whole FR-5 derive path (and the `/loa` Run line, run-resume step 0a, `mark`) is dead on jq 1.6. Reproduced locally with jq-1.6.
2. `.claude/scripts/run-checkpoint.sh:456` and `:294-295` — `derive --write` on a repo with no `.run/circuit-breaker.json` calls `atomic_update "$breaker"`, which feeds `{}` to `merge_breaker`; `merge_breaker` only falls back to `skeleton` when the input is not an object, so `{}` passes and the written breaker has no `threshold`, `limit`, `timeout.started` or `limit_hours`. A following `record-round` prints `cycle 2/null, same_issue 2/null` and the timeout trigger can never fire (`$start` is null). Reproduced (with the `$label` clash patched out).
3. `.claude/hooks/safety/block-destructive-bash.sh:542-575` (`_bdb_hd_same_line_exec`) — the target basename is compared token-by-token after quote stripping, so a reference inside a quoted argument or a substitution is invisible. Reproduced against base vs head hook: `cat > x <<'EOF' / echo $(rm -rf src) / EOF / sh -c 'bash x'` → base BLOCK, head ALLOW; same for `sh -c "bash x"` and `bash $(echo x)`. The classifier reports `nonexec` for these. A quoted-delimiter body with the destructive text inside `$(...)` or after a non-fence word (`echo $(rm -rf src)`) is dropped by `_bdb_hd_scan_body`, and the same-command execution is missed.
4. `.claude/hooks/safety/block-destructive-bash.sh:187` (`_bdb_hd_re_sys`) — `.git/hooks` is executable content but `.husky/` (the common git-hook manager) is not: `tee .husky/pre-commit <<'EOF' / echo $(rm -rf src) / EOF` → base BLOCK, head ALLOW.

## Design/attribution concerns

5. `.claude/hooks/quality/karpathy-surgical-diff-check.sh:131-137` — the per-task key comes from `run-checkpoint.sh read --json`, whose `checkpoint.task` is by contract the last CLOSED bead (state-schemas.md:107; `read` discards an open task). So every write made while implementing task N+1 is attributed to task N's file and summary; the review's SURGICAL axis reading `.run/karpathy-surgical/<bead>.jsonl` sees the wrong task's lines. KS-1 pins this behaviour with a fake `br` that reports every bead closed.
6. `.claude/hooks/compliance/implement-gate.sh:545-553` — the implementing-skill marker is valid for two hours from `started_at` and nothing re-marks it; a direct `/implement` longer than two hours under `mode: deny` with a known position is denied mid-sprint.
7. `.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — every Write/Edit now forks `run-checkpoint.sh read --json`, which forks `br show` when a task is named; the old perf caches were removed. Latency on the PostToolUse path is unmeasured in the PR.
8. `.claude/scripts/loa-status.sh:1016-1022` — `/loa` runs a full `derive` (verdict-derive.sh twice per sprint + git log per sprint) on every invocation.

## Things I checked and consider fine

- implement-gate mode matrix logic, trust-input handling, deny only with a known position (tests IG-24..IG-33).
- profile-lib precedence, floor exclusion, cache id, malformed-key guard.
- heredoc classifier fail-closed paths for unreadable headers, variable delimiters, nested heredocs, interpreters, exec flags, shebang bodies, rc/sys destinations (corpus D101–D142).
- Agent Teams table removal, generator pruning, lint invariant 4b.
