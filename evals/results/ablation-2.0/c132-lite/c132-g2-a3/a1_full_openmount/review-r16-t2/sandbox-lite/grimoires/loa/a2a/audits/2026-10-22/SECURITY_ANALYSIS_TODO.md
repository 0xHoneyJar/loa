# Security analysis working file — sprint-1 audit (PR: sprint-252 decision surfaces part 1)

| # | Source / sink | file:line | Trust | Status |
|---|---------------|-----------|-------|--------|
| 1 | `--recorded-by` caller string → operator gate | dec-write-lib.sh:359 | untrusted (any Bash session) | CONFIRMED (advisory fence) |
| 2 | `.run/*.json` + marker → `live_run_signal` pipeline | dec-write-lib.sh:184 | internal | CONFIRMED (SIGPIPE false negative, 2+ signals) |
| 3 | PRD `**Status:**` line → `is_unattended` | dec-write-lib.sh:178-183 | agent-authored file | CONFIRMED (demotes operator ops) |
| 4 | `--file` path → TARGET_KIND fixture | dec-write-lib.sh:251 | caller | CONFIRMED (CI/hook/worktree bypass on live path) |
| 5 | pending YAML (hand-writable) → `import` append | dec-write-lib.sh:627-647 | agent-authored | CONFIRMED (pre-decided row lands decided/operator) |
| 6 | `--rewrite` / `--from` paths → mv/rm | dec-write-lib.sh:649-655 | caller | CONFIRMED (no containment; symlink replaced) |
| 7 | `--answer-ref` at new/decide (interactive) → decided_by_ref kept at confirm | dec-write-lib.sh:498, 537-538 | agent | CONFIRMED (operator ref discarded) |
| 8 | `.flatline/runs/*.json` symlink → artifact_path containment | dec-write-lib.sh:294-295 | agent | CONFIRMED (file-level symlink passes) |
| 9 | ledger text → `list --format md` → operator session / PR body / PRD+SDD appendix | dec-write-lib.sh:696; render-templates.md:112 | untrusted | CONFIRMED (no fence, `<` `>` pass) |
| 10 | ledger text → INDEX.md | grimoire-index.sh:189 | untrusted | PARTIAL (controls flattened only) |
| 11 | ledger text → SessionStart hook | loa-decisions-surface.sh:69-119 | untrusted | SAFE (L6 fence, brackets replaced, capped) |
| 12 | yq values via env(), rows via jq --arg | dec-write-lib.sh:386-390, 443 | — | SAFE |
| 13 | lock keyed per checkout `.run` → pending file in import | dec-write-lib.sh:203-207, 628-655 | — | CONFIRMED (no cross-checkout exclusion) |
| 14 | validator merge-base path vs single-write rules | validate-artifact.sh:550-554, 671, 682 | — | CONFIRMED (false fail) |
| 15 | hook config read `yq` → string compare | loa-decisions-surface.sh:46-48 | config | SAFE |
| 16 | `claude -p` live call in unit suite | user-invoked-harness.bats:134-151 | — | CONFIRMED (paid call by default) |
