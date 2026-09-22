# Implementation Report — sprint-bug-240: the post-merge pipeline cannot cut a pre-release

**Bug:** 20260923-27d899 · **Triage:** `grimoires/loa/a2a/bug-20260923-27d899/triage.md` · **Plan:** `grimoires/loa/a2a/bug-20260923-27d899/sprint.md`
**Implementer:** Fable 5.1 lead (`/bug`, executed inside PR #1266 on `feature/cycle-124-model-generation-floor`, unattended per `grimoires/loa/a2a/prompts/release-2.0.0-rc1-2026-09-23.md` §4 Phase A) · **Date:** 2026-09-23 · **Bead:** bd-t1fm

## Summary

The release policy for cycle-124 is a `2.0.0-rc.1` pre-release before the stable `2.0.0`. The pipeline could not express that: `semver-bump.sh` had no transition from a release tag into a prerelease (only `rc.N → rc.N+1`), the orchestrator's release POST never set `prerelease`, and `sync-readme-version.sh` rejected a prerelease `framework_version`, which would have turned the `README version sync check` red on the rc PR. The fix gives the pipeline one operator signal it already has — the topmost versioned CHANGELOG heading — and honours it for exactly two transitions (enter a prerelease of the computed version; promote a prerelease to its release), flags the GitHub release from the version string and verifies the flag on read-back, and teaches the README sync script the prerelease grammar plus shields' `--` dash escape. No new flag or config key.

Assumptions (Karpathy rule 1): the CHANGELOG is newest-first (Keep a Changelog; `get_version_from_changelog` already relies on it); a heading is intent only while untagged; a prerelease heading whose release triple differs from what the commits warrant is an operator mistake and must not silently jump the version, so it is ignored with a `WARN`; the candidate's `prerelease` field is informational for the inspector and is tied to the tag at publish time, while `phase_release` derives the flag from the version string so the two cannot disagree.

## Changes

| File | Change |
|---|---|
| `.claude/scripts/semver-bump.sh:121-168` | new `changelog_prerelease_transition()` — topmost `## [X.Y.Z(-PRE)?]` heading (`:145`), tagged headings ignored (`:149-151`), SemVer §9 identifier grammar reused (`:152-154`), `enter` (`:155-159`), mismatch `WARN` (`:160-161`), `promote` (`:163-166`) |
| `.claude/scripts/semver-bump.sh:495-511` | `main()` consults the transition after `bump_version`; `next` is replaced, `bump` is not (`:507-511`) |
| `.claude/scripts/semver-bump.sh:521-524` | additive output field `prerelease_transition` (`{kind, source: "changelog", heading}` or `null`) |
| `.claude/scripts/semver-bump.sh:175-180, 333-335` | header comment and `--help` describe the signal |
| `.claude/scripts/post-merge-orchestrator.sh:1059-1065` | `phase_release` derives `prerelease` from the version string |
| `.claude/scripts/post-merge-orchestrator.sh:1110-1111, 1119-1120, 1124` | POST body carries `prerelease:$pre`; read-back requires `.prerelease == $pre` (also for a pre-existing release); phase result records the flag; dry-run state records it (`:1074`) |
| `.claude/scripts/post-merge-orchestrator.sh:1457-1472` | `prepare_candidate` writes `prerelease` next to `tag` in the candidate JSON |
| `.claude/scripts/post-merge-orchestrator.sh:1502-1503` | `publish_candidate` validation: `(.prerelease // false) == (.tag | test("-"))` |
| `.claude/scripts/sync-readme-version.sh:54-61` | accepts `X.Y.Z(-PRE)?` with the SemVer §9 identifier grammar shared with `semver-bump.sh` (tightened in review round 1 after dissent DISS-001); error text keeps `not semver` |
| `.claude/scripts/sync-readme-version.sh:63-68` | `badge_version="${version//-/--}"`; expected badge uses it |
| `.claude/scripts/sync-readme-version.sh:91-93` | both sed patterns match existing prerelease references, so release→rc and rc→release rewrite in lock-step |
| `tests/unit/semver-bump.bats` (+6) | `sprint-bug-240:` enter / mismatch-ignored / tagged-no-reenter / promote / invalid-identifier / additive-null |
| `tests/unit/post-merge-publication.bats` (+3) | rc heading → candidate `v1.1.0-rc.1` + `prerelease: true` → publish posts and verifies the flag; release posts `false`; pre-existing release with the wrong flag fails read-back |
| `tests/unit/sync-readme-version.bats` (+4) | `--check` accepts the rc; `--apply` release→rc; `--apply` rc→release; invalid §9 identifiers exit 2 while valid dotted forms pass validation |
| `grimoires/loa/runbooks/post-merge-candidates.md` §Pre-release candidates | the signal table, enter / increment / promote, marker sync |
| `PROCESS.md` §Versioning Contract | one paragraph on pre-releases |
| `grimoires/loa/ledger.json` | bugfix cycle `cycle-bug-20260923-27d899`, counters 240 |
| `grimoires/loa/REPO-MAP.md` (+checksum), `.claude/checksums.json` | regenerated (`repo-map-gen.sh --validate`: consistent; checksum regen `--check`: 0 drift) |

## Test-first record

Observed 2026-09-23 with `GIT_CONFIG_GLOBAL=/dev/null` (the host's global git config makes `git tag v1.0.0` demand a message, which is why `post-merge-publication.bats` reads as red locally and was mis-filed as a pre-existing red; every case passes under an isolated config).

- Before the fix, the new tests run against the pre-fix scripts in a throwaway worktree: `semver-bump.bats` 4 red / 2 green (the two green cases — tagged heading does not re-enter, invalid identifier ignored — are regression locks that hold with or without the fix); `post-merge-publication.bats` 2 red / 1 green (the third case, a pre-existing release with the wrong flag, passed vacuously because the pre-fix candidate was `v1.1.0` and the mocked release's tag mismatched; with the fix in place it is the flag comparison that fails publication — removing `.prerelease == $pre` from the read-back makes it red); `sync-readme-version.bats` 3 red.
- After the fix: `semver-bump.bats` 49/49, `post-merge-publication.bats` 22/22, `sync-readme-version.bats` 12/12; the twelve remaining release-pipeline suites (`post-merge-orchestrator`, `post-merge-version-bump`, `semver-evidence`, `semver-bump-downstream`, `release-notes-gen`, `post-merge-changelog-routing`, `post-merge-classifier`, `post-merge-preflight-guard`, `post-merge-archive-gate`, `post-merge-gt-regen`, `post-merge-lore-promote`, `bug-986-post-merge-symlink-reconcile`) 137/137. `bash -n` clean on the three scripts.
- The triage sandbox re-run against the fixed script returns `{"current":"1.2.3","next":"2.0.0-rc.1","bump":"major"}`.

## AC Verification (sprint.md)

### Bug is no longer reproducible: the sandbox from triage returns `next 2.0.0-rc.1`, the candidate carries `prerelease: true`, the mocked release POST carries `prerelease: true`, `--check` exits 0 on the rc version
- **Status**: ✓ Met
- **Evidence**: `tests/unit/semver-bump.bats` "untagged rc heading … enters the prerelease" asserts `next == 2.0.0-rc.1`, `bump == major`, `prerelease_transition.kind == enter` (`semver-bump.sh:155-159`, `:507-511`); `tests/unit/post-merge-publication.bats` "an untagged rc heading prepares a prerelease candidate …" asserts `.tag == "v1.1.0-rc.1" and .prerelease == true` on the candidate (`post-merge-orchestrator.sh:1459-1471`) and `.prerelease == true` in the mocked release payload the POST wrote (`:1110-1111`); "`--check` accepts a prerelease framework_version" exits 0 (`sync-readme-version.sh:56-66`). Real-repo check: with the rc heading not yet on top of this repo's CHANGELOG, `semver-bump.sh --from-tag` still reports `2.0.0` and `prerelease_transition: null` (no accidental entry); the Phase C CHANGELOG rollup is what flips it.

### Failing test proves the fix
- **Status**: ✓ Met
- **Evidence**: red/green record above; the twelve new cases are named `sprint-bug-240:` / `publication: … prerelease …` and are isolated (temp git repos, mocked `gh`, no writes to the repository or `.run/`).

### No regressions in existing tests
- **Status**: ✓ Met
- **Evidence**: 49 + 22 + 12 + 137 = 220 passing across the fifteen release-pipeline suites; `semver-evidence.bats` still pins `bump == major` and the `classification` block, which the fix leaves untouched (`semver-bump.sh:518-530`); the `not semver` error text that `sync-readme-version.bats` case 6 greps for is retained (`sync-readme-version.sh:57`).

### Fix addresses root cause (not just symptoms)
- **Status**: ✓ Met
- **Evidence**: the pipeline now has a formal, tested state transition instead of a hand-edited candidate or a manual tag: the transition lives in the one place that computes versions (`semver-bump.sh:140-168`) and every consumer — candidate tag (`post-merge-orchestrator.sh:1467`), `version_bump` markers (`:378-433`, unchanged, reads `.next`), CHANGELOG finalize (`:655-690`, unchanged, matches the rc heading), tag and release — inherits it; the release flag is derived from the same string and verified on read-back so a mis-flagged release cannot be recorded as `DONE` (`:1119-1122`); `rc.1 → rc.2` and promotion are covered by tests, not prose.

## Out of scope, noted

- `get_version_from_changelog()` (`semver-bump.sh:107-119`) still matches release triples only; it is the fallback current-version source for `--from-changelog` / tag-less repositories and is documented as unchanged (a prerelease heading there is skipped, as before).
- The candidate's `release_body` remains the commit list built by `prepare_candidate` (`:1453-1454`); the rich notes are applied by the operator after publication (`gh release edit … --notes-file`), as the release runbook already prescribes.
- `update-loa-bump-version.sh:213` (`validate_target_format`) accepts a looser `([-.][A-Za-z0-9._-]+)?` prerelease shape than the §9 grammar now enforced by `sync-readme-version.sh`; the pipeline only ever passes it a `semver-bump.sh` result, so the two cannot disagree on the pipeline's path. Left as-is (surgical).
