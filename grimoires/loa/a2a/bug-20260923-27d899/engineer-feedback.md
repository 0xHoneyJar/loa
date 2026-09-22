All good

Observations documented and non-blocking. See Observations below.

# sprint-bug-240 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent gpt-5.5-pro over the diff plus the reviewer's ten-point concern list — `adversarial-review.json`, status `reviewed`, 1 advisory finding, 0 rejected payloads)
**Date:** 2026-09-23
**Bug:** 20260923-27d899 — the post-merge pipeline cannot cut a pre-release · **Plan:** `grimoires/loa/a2a/bug-20260923-27d899/sprint.md`
**Implementation Report:** `grimoires/loa/a2a/bug-20260923-27d899/reviewer.md`
**Range:** working tree over `a20fffeb` — three scripts, three test suites, runbook, PROCESS.md, CHANGELOG `[Unreleased]` line, ledger, plus regenerated REPO-MAP and checksums

---

## Overall Assessment

The bug is real and reproduced in the triage sandbox: an untagged `## [2.0.0-rc.1]` heading over commits that warrant `2.0.0` still produced `next: 2.0.0`; `sync-readme-version.sh --check` exited 2 on `2.0.0-rc.1`; the release POST had no `prerelease` field. The fix is the smallest one that gives the pipeline a formal transition and nothing else, verified in the code rather than the report:

- **One signal, two transitions, one place.** `changelog_prerelease_transition()` (`.claude/scripts/semver-bump.sh:140-168`) reads the topmost versioned heading (`:145`), refuses tagged headings (`:149-151`), validates the identifier with the same SemVer §9 grammar `bump_version` uses (`:152-154`), enters only when the heading's release triple equals the computed `next` (`:155-159`), warns and ignores otherwise (`:160-161`), and promotes only when the current tag is a prerelease of exactly the heading (`:163-166`). `main()` consults it after `bump_version` and replaces `next` but not `bump` (`:507-511`), so `semver-evidence.bats`' classification contract holds. The field is additive (`:521-524`); a repository without a CHANGELOG gets `null` (test 6).
- **Every consumer inherits the version.** The candidate tag is `"v" + next` (`.claude/scripts/post-merge-orchestrator.sh:1467`), `phase_version_bump` stamps `next` into both markers unchanged (`:378-433`; `update-loa-bump-version.sh:213` already accepts the shape), and `_write_changelog_entry` finds the rc heading already documented (`:655-660`) instead of auto-generating a `2.0.0` section.
- **The flag cannot drift from the tag.** `prepare_candidate` records `prerelease` from the version string (`:1459-1462`), `publish_candidate` refuses a candidate whose flag disagrees with its tag (`:1502-1503`), and `phase_release` derives the same flag again (`:1062-1065`), posts it (`:1110-1111`) and requires it on read-back for both a freshly created and a pre-existing release (`:1119-1120`). Publication test 22 shows a hand-made release without the flag is refused before the PR comment is posted.
- **README check accepts the rc.** `sync-readme-version.sh:56-60` validates with the §9 grammar after this round's fix, `:63-68` builds the shields `--` badge, `:91-93` rewrites both references in lock-step in either direction (tests 10-13).
- **Tests first, isolated.** Red/green record in `reviewer.md` matches what the throwaway-worktree run showed (semver 4 red / 2 regression locks, publication 2 red / 1 vacuous-pass now discriminating, README sync 3 red); after the fix 49 / 22 / 13 pass and the twelve sibling release-pipeline suites hold at 137.
- **Karpathy.** Assumptions are stated in `reviewer.md` (newest-first CHANGELOG, untagged = intent, mismatch = ignore-with-warning). No new config key, no new flag; the `--help` line and the runbook section are the only surface additions. No shortcut markers needed.

**Verdict:** APPROVED

---

## Observations

### 1. Input validation (resolved in this round)

- **MEDIUM** (confidence: high) `.claude/scripts/sync-readme-version.sh:56` — as first submitted the guard was `-[0-9A-Za-z.-]+`, looser than SemVer §9: a hand-edited `.loa-version.json` holding `2.0.0-01` or `2.0.0-rc..1` would pass `--check` and `--apply` would stamp a non-SemVer string into the README while `semver-bump.sh` rejects the same identifier. Cross-model finding DISS-001 (advisory; the dissenter's anchor was demoted as out of diff scope, the content stands). **Resolved in-round:** the script now shares the `pre_id` grammar (`:57-58`); test 13 pins four invalid and four valid dotted forms.

### 2. Fallback version source (documented limitation)

- **LOW** (confidence: high) `.claude/scripts/semver-bump.sh:112` — `get_version_from_changelog` still matches release triples only, so in `--from-changelog` mode or a tag-less repository an rc heading on top is skipped and the next tagged release heading becomes `current`. Not on the pipeline's path (auto mode prefers tags, and this repository has them); recorded in `reviewer.md` §Out of scope and the runbook.

### 3. Release body shape (pre-existing)

- **LOW** (confidence: medium) `.claude/scripts/post-merge-orchestrator.sh:1453-1454` — the candidate's `release_body` is the commit-subject list, not the CHANGELOG section `release-notes-gen.sh` can extract; for a 104-commit rc the published body is long and the operator applies the rich notes after publication with `gh release edit`. Unchanged by this fix; a follow-up could prefer the CHANGELOG section when the heading exists.

### Cross-Model Observations

The dissenter reviewed the diff with the concern list and returned the single advisory above; its `verdict_quality.voices_succeeded_ids` reads `codex-headless` while `metadata.final_model` is `gpt-5.5-pro` — a labelling quirk of the dissent tooling, outside this diff, noted for the tooling backlog.

---

## Acceptance Criteria Check

### Task 1: Write Failing Tests

| Criterion | Status | Notes |
|-----------|--------|-------|
| Tests fail with current code, proving the bug exists | Pass | pre-fix worktree run: semver 4/6 red (2 regression locks), publication 2/3 red, README sync 3/3 red — reasons match the triage |
| Test names clearly describe the bug scenario | Pass | `sprint-bug-240:` / `publication: … prerelease …` |
| Tests are isolated | Pass | temp git repos, mocked `gh`, `GIT_CONFIG_GLOBAL` independence noted; no repo or `.run/` writes |

### Task 2: Implement Fix

| Criterion | Status | Notes |
|-----------|--------|-------|
| Failing tests now pass | Pass | 49 / 22 / 13 |
| No regressions in existing tests | Pass | 137/137 across the twelve sibling suites; `semver-evidence` contract intact |
| Fix addresses root cause | Pass | transition in the version computer; flag derived and verified; no hand edits |

### Task 3: Documentation and record

| Criterion | Status | Notes |
|-----------|--------|-------|
| Runbook + PROCESS.md | Pass | `post-merge-candidates.md` §Pre-release candidates; PROCESS.md §Versioning Contract paragraph |
| REPO-MAP / checksums / `bash -n` | Pass | `repo-map-gen.sh --validate` consistent; checksum regen `--check` clean; syntax clean |
| CHANGELOG entry; `reviewer.md` AC Verification with `file:line` | Pass | `[Unreleased]` line; four AC rows cite lines |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Fences and hooks untouched (`git diff -- .claude/hooks` empty); clean-tree, digest, checkout and origin guards unchanged
- [x] Heading input restricted to `[0-9A-Za-z.-]` by the extraction regex before reaching `git rev-parse` or `jq --arg`; no shell interpolation of CHANGELOG content
- [x] Read-back verification strengthened, never weakened
- [x] No new dependency; no network in the changed paths

---

## Next Steps

1. `/audit-sprint sprint-bug-240` — independent dissent (no context file), `excluded_confirmed: 0`.
2. Commit with the release-candidate docs on PR #1266.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-bug-240","ts":"2026-09-22T22:10:00Z"} -->
