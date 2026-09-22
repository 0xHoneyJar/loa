# 2.0.0-rc.1 — operator-only steps (recorded 2026-09-23, not performed)

The unattended run that prepared PR #1266 as the release-candidate PR stopped at these steps by design. Each needs a credential, a repository setting or a publication decision that only the maintainer holds. Order matters where noted.

## Before merging

1. **Rotate or remove the Anthropic key in the local `.env`.** The key there is rejected with HTTP 401 (observed 2026-09-22 by Bridgebuilder's Anthropic voice, bead `bd-pr59`); a dead credential in a dotfile is a liability and it misleads tooling into a fetch path that cannot work. The sanctioned local path is the `claude-headless` CLI hop; never borrow the Claude Code OAuth token.
2. **Create the `live-floor` GitHub environment**: required reviewers = you; deployment-branch policy limited to `main` and `release/*` (this is the load-bearing control named in `.github/workflows/live-floor-check.yml:37-42` — a dispatched branch runs its own copy of the YAML); store `ANTHROPIC_API_KEY` there as an environment secret. Then dispatch the workflow once on `main` after the merge; a recorded pass is one of the rc exit criteria.
3. **Decide the vendored Aleph tree's fate** (bead `bd-c7ma`): keep inert (current), quarantine, or remove. With `aleph.enabled: false` the tree is unverified while present. This does not block the rc.
4. **Resolve the parked v1.203.0 candidate and the #1251 flow** (framework review §9 item 4): the pipeline now prepares candidates and publishes only an approved digest; decide whether the parked v1.203.0 candidate is published, superseded by the rc, or discarded. Publishing it after the rc would put a `1.203.0` tag above `2.0.0-rc.1` in version order only nominally (SemVer precedence keeps `2.0.0-rc.1` higher), but it would confuse the "latest stable" story — recommendation: supersede.

## Merge and publish

5. Mark #1266 ready for review and merge it (squash or merge — either way the merge-commit subject must keep `cycle-124` so `classify-merge-pr.sh` routes to the full pipeline; the current title does). The post-merge run prepares `release-candidate-<merge sha>` with `tag: v2.0.0-rc.1`, `prerelease: true` — the untagged `## [2.0.0-rc.1]` heading steers `semver-bump.sh` (verified locally: `next: 2.0.0-rc.1`, `prerelease_transition.kind: enter`).
6. Inspect the artifact per `grimoires/loa/runbooks/post-merge-candidates.md` (patch, bodies, `prepared_state.phases.semver.result`, `prerelease: true`, target tree). From the recovered exact checkout: `.claude/scripts/post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 <digest>`.
7. Verify on GitHub that `v2.0.0-rc.1` is flagged **Pre-release** (the publisher already refused to record `DONE` otherwise), then replace the commit-list body: `gh release edit v2.0.0-rc.1 --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.1.md`.
8. Dispatch `live-floor-check.yml` on `main` (step 2 must exist first).

## Soak and promote

9. Announce the rc; downstream mounts upgrade via `docs/migration/v2.0-model-generation-floor.md`; issues labelled `2.0.0-rc`.
10. Fixes merge to `main` normally; each merge on the rc tag prepares `-rc.2`, `-rc.3`, … (no CHANGELOG action needed for increments; `[Unreleased]` content is finalized under the next rc heading by the pipeline).
11. Promotion, when the exit criteria in the release notes hold: a PR that moves the rollup under `## [2.0.0] — <date> — Model-generation floor` (above the rc headings), sets `.loa-version.json`, the `CLAUDE.loa.md` header and the README references to `2.0.0` (`sync-readme-version.sh --apply`), and keeps `cycle-124` or a `feat(cycle-…)` shape in its title. The merge prepares `2.0.0` with `prerelease: false`, `prerelease_transition.kind: promote`; inspect, publish, edit the notes.

## What the run did NOT do

No merge, no tag, no release, no push to `main`, no change to repository settings, no use of any credential beyond the OpenAI dissent voice already configured for `adversarial-review.sh`.
