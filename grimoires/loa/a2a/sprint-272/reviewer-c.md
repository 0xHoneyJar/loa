# Sprint 272 (cycle-133 Sprint 1) — implementer C: Tasks 1.4 and 1.5

Implementer: Claude Opus 5.5 (global.anthropic.claude-opus-5-5), worktree `loa-wt-s1c`. Specification: sdd.md § 1.4 C-4, § 5.2, § 5.4; sprint.md Tasks 1.4, 1.5; prd.md FR-4.

## Task 1.4 — `record-branch.sh` (bd-mgun5)

- New `.claude/scripts/record-branch.sh`: header documents usage, order and exit codes. Flow: argument and ledger checks; parents on origin and the compare-and-swap expectation (`on_origin`, `CUR` at lines 139–149); the Python helper (`cmd_collect` at 248) builds the manifest from the ledger cycle or `--manifest`, refuses escaping paths, symlinked parents, nested `.git`, non-regular files and every symlink of the final tree whose target is absolute, escaping or not recorded (`check_links` at 212, over inherited `<head>` entries, additions and the lite tree); `--dry-run` prints the size table (`cmd_table` at 394). Temp index `read-tree <head>` → `add -f` → `write-tree` (513–519); export of `git diff-tree -r <head> <scan_tree>` to a bounded temp dir by streaming `cat-file --batch` (`cmd_export` at 414); `audit-secret-redaction-scan.sh` plus eight credential classes (`CRED` at 436); credential hits refuse (538), a mismatched `--accept-scan` refuses (541), non-credential hits refuse unless accepted; the manifest joins the tree (553); `commit-tree -p prev -p head` (572); `update-ref` CAS (574).
- Docs: `.claude/commands/archive-cycle.md` § Record Branch (line 121); `.claude/commands/ship.md:64`.

## Task 1.5 — framework ergonomics (bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5, bd-4pjqm)

- `notes-guard.sh`: `build_retained` (268), `session_log_part` (247); `cmd_rotate` uses it (311); header documents the retention.
- `pre-compact-marker.sh`: `_pcm_recent`/`_pcm_read`/`_pcm_liveness` (40–75), `LOA_HOOK_LIVE_WINDOW_DAYS` (36); marker gains `liveness` (and `simstim.state`).
- `dec-write-lib.sh:472–473`: `N code points (limit 160): <first 160>…`.
- `security-audit-scope.sh`: `--help`, `--files FILE`, `--paths P…` (36–68), JSON `scope`; `auditing-security/SKILL.md:169`.
- `ledger-lib.sh:775` `validate_ledger`: `schema_version` (alias `version`), positive integer.

## Tests

New: `tests/unit/record-branch.bats` (14), `notes-guard-rotate.bats` (4), `pre-compact-liveness.bats` (7), `dec-write-length.bats` (2), `security-audit-scope.bats` (5), `ledger-validate.bats` (4). Each new suite was run red before its fix (record-branch 14/14 red, rotate 4/4, liveness 7/7, dec-write 1/2, scope 5/5, ledger 3/4). Existing suites green: notes-guard (22), post-compact-active-skill (8), test_pcr_hooks.sh (13), dec-write-lib (52), ledger-lib / ledger-transactions / ledger-compound-validation / ledger-isolation-discovery / archive-cycle-default-and-ledger (84), plus the related unit suites listed in the implementer report.

Judgment calls and lead actions: see `~/.cache/loa/cycle-133/reports/s1-c.md`.
