APPROVED - LET'S FUCKING GO

# sprint-bug-266 Security Audit (round 2, final)

**Auditor:** Fable 5.1 lead (auditing-security contract; dissent via adversarial-review.sh --type audit on round 1; round 2 verified directly)
**Date:** 2026-10-21T02:45:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-ba367a/sprint.md (sprint-bug-266)
**Review:** grimoires/loa/a2a/bug-20261021-ba367a/engineer-feedback.md (All good)
**Commits audited:** `868e22e7` → `86755261` → `048c35fc` → audit-round `c3277c8d` on `fix/cycle-132-bugs`
**Dissent:** round 1 — adversarial-audit.json (gpt-5.5-pro; clean; 4 findings, 0 schema-rejected); round 2 — direct verification (dissent runs used for this sprint: 2 of ≤ 3)
**Red-then-green:** `red-test-check.sh --red 868e22e7 --green c3277c8d -- bats tests/unit/archive-cycle-default-and-ledger.bats` → VERIFIED

---

## Previous Findings (round 1)

- MEDIUM-1 containment on the basename — **Resolved**: a ledger-derived `cycle_id` must match `^cycle-[0-9]+(-[A-Za-z0-9._-]+)?$` and carry no `..`, checked before any path use and in dry runs (`archive-cycle.sh:305`); after `mkdir` the created directory's real path must sit under the archive directory's real path, else the empty directory is removed with `rmdir` and the run exits 1 (ACL-11).
- LOW-1 git failure fallback — **Resolved**: only "git absent" or exit 128 "not a git repository" fall back to the mtime rule; any other `rev-parse` failure, and a `false` answer, keep every archive with a WARN (`:526`; ACL-12 with a dubious-ownership stub).
- LOW-2 swallowed options — **Resolved**: unknown options print `ERROR: unknown option` plus usage and exit 1 (ACL-13; no automated caller passes extra arguments — the implementer checked `.claude`, `.github`, `tools`, `evals`).
- LOW-3 gate outside the lock — **Resolved by option (b)**: the archive directory is created with a plain `mkdir` (parent with `-p`), so an existing directory or symlink exits 1 (`archive already exists`) and is never overwritten (`:387`; ACL-14); the lead accepts the implementer's reason for not holding the ledger flock across `generate-changelog.sh` and `trajectory-export.sh`.

## Findings (round 2)

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |

## Verification
- Suites: default-and-ledger 14/14, retention 5/5, per-subdir 6/6, post-merge-archive-gate 8/8, ledger-lib 42/42, ledger-transactions 16/16 (lead's run: 91 ok, 0 not ok); `bash -n` clean.
- E2E on this repository (ledger byte-identical afterwards): a no-argument dry run refuses with the stale-cycle message; `--cycle 131 --dry-run` reports the existing tracked archive and that a real run would refuse; `--dryrun` is refused as an unknown option.
- No credential handling; ledger writes through `ledger-lib.sh`; destructive paths now fail closed on every ambiguous state (unknown git state, existing archive, unknown option, unsafe id).

## Improvements noted (non-blocking)
- Re-archiving a cycle now requires removing the old archive directory first (`git rm` when tracked); the error says so. Reasonable for a script that must never overwrite history.
- The ledger's 53 stale `active` cycles make the no-argument form refuse on this repository until a hygiene pass marks them archived (follow-up bead for the ledger, not this script).

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-266","ts":"2026-10-21T02:45:00Z"} -->
