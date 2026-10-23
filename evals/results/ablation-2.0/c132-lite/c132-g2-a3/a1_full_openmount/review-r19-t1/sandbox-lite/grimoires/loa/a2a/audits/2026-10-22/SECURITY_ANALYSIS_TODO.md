# Security analysis working file — sprint-1 (PR sprint-255), 2026-10-22

Sources (untrusted → trust level) and sinks catalogued from pr/head.diff; status per item.

| # | Item | Trust | Sink | Status |
|---|------|-------|------|--------|
| 1 | `.run/audit.jsonl` rows → guard-yield.sh jq join (ids, pattern_id, cwd, command) | low (any hook writes it) | jq string ops, markdown table cells, `heredoc_nonexec "$cmd"` argv | CONFIRMED-SAFE for injection (ids regex-gated, `cell` strips control chars; privacy probe: no cwd/command/model text in outputs). PARTIAL: numeric pattern_id aborts join (exit 3); `.lock` beside log read as segment |
| 2 | `.claude/settings.json` hook commands → guard-yield.sh | medium (tracked) | regex parse, `readlink`, path join `$ROOT/.claude/$rel` | SAFE: canonical-schema regex, `badpath` rejects `..`/empty, symlink leaving `.claude/` refused |
| 3 | `guard-origins.yaml` rows → register / hooks table | medium (tracked) | GFM table cells, yq→jq | SAFE: schema check exit 5, `cell` sanitiser |
| 4 | `$ROOT/.claude/scripts/lib/heredoc-classifier.sh` → `source` | medium (tracked, optional) | in-process `source` | CONFIRMED: top-level `exit` in the library ends the generator with exit 0 and no files (reproduced) |
| 5 | Audit-row `replay` flag ← `LOA_AUDIT_REPLAY` env | low (ambient env) | yield classification | CONFIRMED (low): any process exporting the var tags live blocks as replay |
| 6 | Prompt tree / `--source-commit` → execute-agent.sh sandbox + toggles | medium | file removals in sandbox; `yq -i`; python paragraph drop | CONFIRMED: `rule_files` toggle no-op when rules absent (exit-2 contract violated) |
| 7 | Agent stdout/stderr → run-arms.sh `is_transport_failure` grep | low (model output) | retry decision | CONFIRMED (low): broad patterns |
| 8 | Git record branches / commits → seed-corpus-from-record.sh | medium (operator-chosen refs) | fixture file writes, label TSVs, no-secrets.sh gate | delegated scout; fail-closed when no-secrets.sh missing (observed SC-1) |
| 9 | Sprint plan text → validate_sprint_kinds awk | low | regex only, no eval | SAFE: KINDS-1..11 pass; fenced code excluded via md-fence.awk |
| 10 | CI: `guard-yield.sh --check` in bats-tests.yml | n/a | exit 1 on drift / missing register | PARTIAL: tracked register not in this fixture; cannot confirm sync |
| 11 | block-destructive-bash.sh diff | n/a | fence regexes | SAFE: comment markers + replay flag only; no pattern changed |
