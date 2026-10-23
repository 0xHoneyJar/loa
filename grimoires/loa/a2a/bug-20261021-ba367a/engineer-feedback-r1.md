# sprint-bug-266 Review Feedback (round 1)

**Reviewer:** Fable 5.1 lead (reviewing-code contract; dissent via adversarial-review.sh)
**Date:** 2026-10-21T01:35:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-ba367a/sprint.md (sprint-bug-266)
**Implementation Report:** grimoires/loa/a2a/bug-20261021-ba367a/reviewer.md (implementer A, Opus 5.5)
**Commits under review:** red `868e22e7` (tests/unit/archive-cycle-default-and-ledger.bats, ACL-1…7), fix `86755261` on `fix/cycle-132-bugs`
**Dissent:** adversarial-review.json (gpt-5.5-pro primary + claude-headless companion; status clean; 7 advisories, 0 blocking; 0 schema-rejected)

---

## Overall Assessment

The fix does what the triage asked and does it cleanly: `get_current_cycle` derives the active cycle's number (else the maximum) with a single jq program; the retention default is 0 unless the CLI or the yaml names a value; `cleanup_old_archives` partitions candidates into tracked (kept, warned) and untracked (deleted) with a fail-safe `ls-files --error-unmatch`; a real archive mutates the live ledger through ledger-lib's lock and `_write_ledger` after the pre-mutation copy was archived; the completeness gate runs before any write and `--force` overrides it. The seven new tests drive the real script against a hermetic scratch repo and ledger, fail by assertion at the red commit (6 of 7; ACL-6 pins the no-write dry run) and pass at the fix. The existing archive, post-merge-gate and ledger suites stay green (89 cases). The E2E on the real ledger names `archive/cycle-131-honest-measurement` and deletes nothing.

Two semantics gaps the dissent and I agree on stand between this and approval, both small: a second no-argument run after a successful archive would re-archive the cycle this script just archived (the newest cycle is now `archived` and `active_cycle` is null), and a missing `ledger-lib.sh` is detected only after the archive directory exists and then exits 0, which the header itself says must be exit 1.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Default cycle re-archives an already-archived cycle (dissent DISS-C-001)

- **MEDIUM** (confidence: high) `.claude/scripts/archive-cycle.sh:173-186` — when `active_cycle` is null the default is the highest-numbered cycle regardless of `status`. After this script runs once (it nulls `active_cycle` and marks the cycle `archived`), a second no-argument run picks the same cycle, passes the completeness gate (its sprints are complete) and re-stamps `archived`/`archive_path`.
**Required Fix:** active cycle when set; else the highest-numbered cycle whose `status` is not `archived`; else exit 1 with `ERROR: every cycle in the ledger is archived; pass --cycle N to re-archive one`. ACL-2's fixture must make the newest cycle unarchived; add ACL-8 (all archived, no `--cycle` → exit 1, nothing written). Header updated.

### 2. Missing ledger-lib.sh is detected after the archive exists and exits 0 (dissent DISS-C-005)

- **MEDIUM** (confidence: high) `.claude/scripts/archive-cycle.sh:345-357` — the lib check runs after `mkdir -p "$archive_path"` and the copies; on a missing lib it prints a WARN and returns 0, leaving an archive whose cycle is still `active` in the ledger, while the header promises `exit 1` on a ledger update failure.
**Required Fix:** check the lib in the pre-write gate (before `mkdir -p`) whenever the cycle has a ledger entry; exit 1 with a clear message. The reviewer authorizes adding ledger-lib.sh (and what it sources) to the hermetic copy in `tests/unit/archive-cycle-per-subdir.bats` so AC-1.4 keeps passing; its assertions stay as they are.

### 3. Pathspec glob magic in the tracked check (dissent DISS-C-002)

- **LOW** (confidence: high) `.claude/scripts/archive-cycle.sh:366-370` — the candidate directory is a plain pathspec, so `[ ] * ?` in a name are glob magic and a tracked directory can read "no match". Fix: `-- ":(literal)$1"`. The fail-safe (rc ≠ 1 ⇒ kept) stays.

### 4. A yq failure is indistinguishable from an absent key (dissent DISS-C-003)

- **LOW** (confidence: medium) `.claude/scripts/archive-cycle.sh:99-110` — a missing yq or a YAML parse error collapses into `yaml_retention=""`, so a configured retention is silently ignored (in the safe direction). Fix: WARN on stderr when yq fails; silent only when the key is absent.

### 5. `rel_archive_path` prefix strip can leave an absolute path in the ledger (dissent DISS-C-004)

- **LOW** (confidence: medium) `.claude/scripts/archive-cycle.sh:248` — a trailing slash on `PROJECT_ROOT`, a symlinked component or an archive dir outside the root defeats the strip and writes a machine-specific absolute path. Fix: resolve both with `pwd -P`; keep an absolute path only when the archive is outside the root, with a WARN.

---

## Observations (non-blocking)

- DISS-C-006: the completeness gate counts every sprint whose `status != "completed"`, exactly as `ledger-lib.sh archive_cycle` does; parity is the point. Accepted.
- DISS-C-007: `get_current_cycle` returns the number and `_resolve_cycle_id` re-derives the id with `^cycle-0*N(-|$)`, which tolerates zero padding; numbers are unique in this ledger. Accepted.
- Implementer DECISION (a WARN and exit 0 on a missing lib) is overruled by item 2 above; every other DECISION bullet in the report stands.
- The red-test-check must be invoked with `bats` on PATH (the checker refuses an absolute runner path as a "script runner"); recorded for the lead's recipe, not a defect in the sprint.

## Rejected dissent payloads
None (0 rows in adversarial-rejected-review*.jsonl).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":2,"low":3},"excluded":0,"sprint_id":"sprint-bug-266","ts":"2026-10-21T01:35:00Z"} -->
