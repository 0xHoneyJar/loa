# sprint-bug-266 Security Audit (round 1)

**Auditor:** Fable 5.1 lead (auditing-security contract; dissent via adversarial-review.sh --type audit)
**Date:** 2026-10-21T02:12:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-ba367a/sprint.md (sprint-bug-266)
**Review:** grimoires/loa/a2a/bug-20261021-ba367a/engineer-feedback.md (All good, after round 1)
**Commits audited:** `868e22e7` → `86755261` → `048c35fc` on `fix/cycle-132-bugs` (diff vs `70330e48`: `.claude/scripts/archive-cycle.sh`, `.claude/commands/archive-cycle.md`, `tests/unit/archive-cycle-default-and-ledger.bats`, `tests/unit/archive-cycle-per-subdir.bats`)
**Dissent:** adversarial-audit.json (gpt-5.5-pro; status clean; 4 findings, 0 schema-rejected; 2 of ≤ 3 dissent runs used for this sprint)

---

## Scope

A script that deletes directories and mutates the project ledger. The audit read the diff for path handling, destructive-action gating, privilege and concurrency, and the tests for isolation from the live tree.

## Findings

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 3 |

### MEDIUM-1 — The repo-root containment check tests the basename, not the path written (dissent DISS-C-001)
`.claude/scripts/archive-cycle.sh:288-296` — the round-1 `pwd -P` containment builds `real_archive_path` from `${archive_path##*/}`, so any directory component carried by the ledger-derived `cycle_id` (`archive_path="${ARCHIVE_DIR}/${cycle_id}"`) is discarded before the `== "$root_real"/*` test. `cycle_id` is a string from `ledger.json` `.cycles[].id` that passed only `^cycle-0*N(-|$)`; an id such as `cycle-131-../../x` keeps the regex happy, and the archive is then created and the relative path recorded outside the archive directory while the check passes. **Required:** validate `cycle_id` against a strict slug (`^cycle-[0-9]+(-[A-Za-z0-9._-]+)?$`, no `/`, no `..`) when it is read from the ledger, and run the containment check on the real path of the directory actually created (`pwd -P` of `archive_path` itself under `ARCHIVE_DIR`'s real path); refuse (exit 1, nothing written) otherwise. Test: a ledger id with a traversal component is refused before `mkdir`.

### LOW-1 — A git failure disables the tracked-archive protection (dissent DISS-C-002)
`:467-471` — `in_git` is false on any `git rev-parse` failure (dubious ownership, corrupt `.git`, missing git), which falls back to the mtime-only `rm -rf`. **Required:** distinguish "not a work tree" (git exit 128 with that message, or `git` absent) from any other failure; on the latter keep every candidate with a WARN (fail safe toward keeping).

### LOW-2 — Unknown options are swallowed (dissent DISS-C-003)
`:88-96` — `*) shift ;;` means `--dry_run`, `--dryrun` or `--retention=3` are ignored and the run proceeds as a real archive and prune. Pre-existing, but the script now has `--force` and irreversible steps. **Required:** unknown options exit 1 with usage.

### LOW-3 — The gate and the archived ledger snapshot read the ledger outside the lock (dissent DISS-C-004)
`:252-300` — `_count_incomplete_sprints`, `_resolve_cycle_id` and the `ledger.json` copy run unlocked; only `_update_ledger_archived` takes the ledger-lib lock. Two concurrent invocations can both pass the gate and write the same `archive_path`. **Required:** take `_lock_ledger_transaction` once around gate → copy → mutation for a real run (dry-run stays unlocked), or document the race and fail closed when `archive_path` already exists (`mkdir` without `-p` of the final component). Either is acceptable; say which.

## Secrets, zones, dependencies
- No credential handling; the ledger write goes through `ledger-lib.sh` (lock, backup, atomic rename); no new dependency; System Zone edit under `/bug` with the triage's authorization.
- Tests are hermetic (`$BATS_TEST_TMPDIR` repos; the live `grimoires/` never read or written); `--no-verify` in the test commit is inside the scratch repo.

## Verdict

CHANGES REQUIRED — one MEDIUM (path containment on a destructive script) and three LOW hardening items; all small, all testable. The review's approval stands; this round is the audit's.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-266","ts":"2026-10-21T02:12:00Z"} -->
