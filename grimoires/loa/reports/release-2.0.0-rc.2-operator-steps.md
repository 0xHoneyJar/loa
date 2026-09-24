# 2.0.0-rc.2 — release steps (cycle-125, PR #1269)

Recorded 2026-09-24. The maintainer answered the cycle-125 close-out with "proceed as you suggest", the same authorization that published `2.0.0-rc.1` on 2026-09-23, so the unattended session executes the merge-and-publish steps below with the rc.1 recipe and records each outcome here. Anything that needs a credential the session does not hold stays with the maintainer.

## Before merging (on the branch)

1. CHANGELOG: the `[Unreleased]` block becomes `## [2.0.0-rc.2] — 2026-09-24 — Friction floor (release candidate)` (rc increment: `semver-bump.sh --from-tag` must still compute `2.0.0-rc.2` with no heading warning); a fresh empty `[Unreleased]` sits above it.
2. Framework markers at `2.0.0-rc.2` (`update-loa-bump-version.sh --target 2.0.0-rc.2` → `.loa-version.json`, `CLAUDE.loa.md` header), README version references (`sync-readme-version.sh --apply`), README what's-new for rc.2, release badge renamed, pin example at `v2.0.0-rc.2` (resolves once published).
3. `grimoires/loa/reports/release-notes-2.0.0-rc.2.md` (this candidate's notes) and this file.
4. REPO-MAP + `.checksum` sidecar + `.claude/checksums.json` regenerated together; `tools/check-prompt-budget.sh` ok; `repo-map-gen.sh --validate` consistent; `sync-readme-version.sh --check` clean; CI green on the final head.
5. Delete `.run/zone-guard-authorization.json` after the last `.claude/` edit.

## Merge and publish

6. Mark #1269 ready and merge with a merge commit (`--admin`: the sole maintainer cannot review their own PR); the subject keeps `cycle-125` so `classify-merge-pr.sh` routes to the full pipeline.
7. Wait for `post-merge.yml`; download `release-candidate-<merge sha>`; recover in an isolated clone per `grimoires/loa/runbooks/post-merge-candidates.md` (bundle verified, tree matched, `prerelease: true`, `tag v2.0.0-rc.2`).
8. `post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 <digest>` from the recovered checkout; verify the tag, the release id and `prerelease: true`; state `DONE`.
9. `gh release edit v2.0.0-rc.2 --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.2.md`; the repository "latest" release stays the last stable tag.
10. Local: `main` → `origin/main`, delete the local feature branch, NOTES Session Continuity, memory.

## Still maintainer-only (unchanged from rc.1)

- A valid `ANTHROPIC_API_KEY` in the `live-floor` environment, then `gh workflow run live-floor-check.yml --ref main` (a recorded pass is an rc exit criterion).
- The soak itself and the promotion PR (`## [2.0.0]` heading) when the exit criteria hold.
- Follow-up beads `bd-ypbg` (re-pricing pass) and `bd-n7v3` (check-permissions scope) as `/bug` cycles after the rc.2 publication.

## Outcome

This file is the plan of record and is committed on the branch before the merge. The outcome of steps 6–10 (merge sha, candidate digest, tag object, release id, `prerelease` flag) is recorded where it can be written after the merge without another PR: the release comment on PR #1269 and the `grimoires/loa/NOTES.md` Session Continuity block.
