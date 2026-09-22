# Bug Triage: The post-merge pipeline cannot cut a pre-release — no entry into `X.Y.Z-rc.1` from a release tag, the GitHub release is never flagged `prerelease`, and the README version check rejects a prerelease string

## Metadata
- **schema_version**: 1
- **bug_id**: 20260923-27d899
- **classification**: release-pipeline defect (missing state transition + wrong API payload + over-strict validator)
- **severity**: high
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): a fixture repository whose top CHANGELOG heading is `## [2.0.0-rc.1]` and whose commits warrant a major bump still yields `next: 2.0.0` from `semver-bump.sh --from-tag`; the error text is captured (+1): `sync-readme-version.sh --check` prints `ERROR: .framework_version='2.0.0-rc.1' is not semver (expected X.Y.Z)` and exits 2, which would fail the `README version sync` CI job on any PR that sets `.loa-version.json` to the release-candidate version. The release POST body in `post-merge-orchestrator.sh` carries no `prerelease` field (0 occurrences of the word in the script), so even a correctly versioned rc would be published as a normal, "latest" release. No disqualifier: no new endpoint, UI, schema migration or configuration key — the operator signal is the CHANGELOG heading that already exists. Maintainer authorization 2026-09-22: "this will need to be a stable candidate … however we achieve that formally is the way to go" (operator prompt `grimoires/loa/a2a/prompts/release-2.0.0-rc1-2026-09-23.md` §4 Phase A).
- **test_type**: unit
- **risk_level**: medium
- **created**: 2026-09-22T22:04:43Z

## Reproduction
### Steps
1. Create a repository with tag `v1.2.3`, then add a commit `feat!: model floor` whose CHANGELOG puts `## [2.0.0-rc.1] — 2026-09-23 — …` as the topmost versioned heading (above `## [1.2.3]`), leaving `## [Unreleased]` empty.
2. Run `.claude/scripts/semver-bump.sh --from-tag` in that repository.
3. Set `.loa-version.json` `framework_version` to `2.0.0-rc.1`, write the matching `Version: 2.0.0-rc.1` comment and `version-2.0.0--rc.1-blue.svg` badge into `README.md`, and run `.claude/scripts/sync-readme-version.sh --check`.
4. Read the release creation call in `.claude/scripts/post-merge-orchestrator.sh` (`phase_release`) and the candidate contract in `prepare_candidate` / `publish_candidate`.

### Expected Behavior
- Step 2 returns `next: 2.0.0-rc.1`: the operator has named a release candidate of exactly the version the commits warrant, so the prepared candidate, its tag and its release use the prerelease version. A later merge on the `v2.0.0-rc.1` tag increments to `2.0.0-rc.2` (already implemented); an untagged `## [2.0.0]` heading on top of a `2.0.0-rc.N` tag promotes to `2.0.0`.
- Step 3 exits 0: a SemVer prerelease is a valid framework version.
- Step 4: a version carrying a prerelease identifier is created with `prerelease: true` and the read-back verifies the flag; a release version is created with `prerelease: false`.

### Actual Behavior
- Step 2 (observed 2026-09-23, sandbox `/tmp/tmp.5UIJESzvUT/semver`): `{"current":"1.2.3","next":"2.0.0","bump":"major"}` — the rc heading is ignored. `bump_version()` only knows two shapes: a release `X.Y.Z` bumps by major/minor/patch (`semver-bump.sh:170-181`) and a prerelease `X.Y.Z-PRE.N` increments N (`:147-168`); the header comment states that promotion is "operator-driven and out of scope" (`:129-130`) and nothing enters a prerelease from a release tag. On PR #1266 this means the candidate prepared after merge would be tagged `v2.0.0` (`post-merge-orchestrator.sh:1437-1458`, `tag: "v" + .phases.semver.result.next`), `phase_version_bump` would stamp `2.0.0` over the rc markers (`:430-433`, `update-loa-bump-version.sh --target 2.0.0`), and `_write_changelog_entry` would auto-generate a `## [2.0.0]` section above the hand-written rc one (`:655-690`).
- Step 3 (observed): `ERROR: .framework_version='2.0.0-rc.1' is not semver (expected X.Y.Z)`, exit 2 (`sync-readme-version.sh:54-58`). The `README version sync check` workflow runs `--check` on every pull request that touches `.loa-version.json` (`.github/workflows/readme-version-sync.yml:4-8, 23-26`), so the rc PR would go red. The badge pattern also cannot express a prerelease: shields.io needs a literal dash escaped as `--`, and the script builds `version-$version-blue.svg` verbatim (`:61-62, 85-88`).
- Step 4: `phase_release` posts `{tag_name, name, body, draft:false}` (`post-merge-orchestrator.sh:1103-1105`) and reads back only `.draft == false` (`:1111-1113`); `grep -c prerelease` on the script returns 0. The candidate JSON records `tag` but no release flag (`:1455-1459`), and `publish_candidate` validates `.tag == "v" + next` only (`:1483-1489`).

### Environment
Linux 6.16, bash 5, jq 1.7, git 2.47; branch `feature/cycle-124-model-generation-floor` at `a20fffeb`; latest tag `v1.202.1`; `semver-bump.sh --from-tag` on the branch: `current 1.202.1 → next 2.0.0 (major)` from `2af691ac fix(release)!:` (upstream) and `ae4cf1df fix(aleph)!:`.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/semver-bump.sh` | 121-131, 147-185, 441-448 | high | `bump_version()` has no release→prerelease transition; `main()` computes `next` without consulting the CHANGELOG's intended version |
| `.claude/scripts/semver-bump.sh` | 107-119 | medium | `get_version_from_changelog()` matches release triples only (`## [X.Y.Z]`); a prerelease heading is invisible to it (fallback source; unchanged by this fix, documented) |
| `.claude/scripts/post-merge-orchestrator.sh` | 1049-1119 | high | `phase_release` never sets `prerelease`; read-back cannot detect a mis-flagged release |
| `.claude/scripts/post-merge-orchestrator.sh` | 1430-1468, 1476-1492 | high | candidate JSON has no `prerelease` field for the inspector; publish validation does not tie the flag to the tag |
| `.claude/scripts/sync-readme-version.sh` | 54-58, 61-62, 85-88 | high | strict `X.Y.Z` regex; badge built without shields `--` escaping; sed patterns match release strings only |
| `.github/workflows/readme-version-sync.yml` | 4-8, 23-26 | high | runs `--check` on PRs touching `.loa-version.json` → the rc PR fails CI |
| `.claude/scripts/update-loa-bump-version.sh` | 213 | low | already accepts `1.2.3-rc1`-style targets (`validate_target_format`); no change needed |
| `.claude/scripts/release-notes-gen.sh` | 65 | low | `^## \[${version}\]` already matches a `## [2.0.0-rc.1] — …` heading for the rc version and does not match it for `2.0.0`; no change needed |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/semver-bump.bats` | tag/CHANGELOG sources, bump classes, prerelease increment (`rc.1 → rc.2`, bug-745 grammar) — no entry/promotion case |
| `tests/unit/post-merge-publication.bats` | `--generate` candidate shape, `--publish` verification against a mocked `gh` — no prerelease flag assertion |
| `tests/unit/sync-readme-version.bats` | `--check`/`--apply`, non-semver exit 2 — asserts the `X.Y.Z`-only behaviour indirectly (`not-a-version` case) |
| `tests/unit/post-merge-version-bump.bats` | version_bump phase wiring (reads `.next`, calls `update-loa-bump-version.sh --target`) — unchanged |
| `tests/unit/semver-evidence.bats` | `classification` evidence fields — must keep passing |

### Test Target
Extend the three existing suites, failing first:
- `semver-bump.bats`: (a) an untagged `## [2.0.0-rc.1]` top heading with commits warranting `2.0.0` → `next 2.0.0-rc.1`, `prerelease_transition.kind == "enter"`; (b) an rc heading whose release triple differs from the computed version is ignored with a stderr warning; (c) an already-tagged rc heading does not re-enter (`rc.1 → rc.2`); (d) an untagged `## [2.0.0]` heading on a `v2.0.0-rc.2` tag promotes → `2.0.0`, `kind == "promote"`; (e) a heading with an invalid prerelease identifier (leading zero) is ignored.
- `post-merge-publication.bats`: an rc heading prepares a candidate with `tag v1.1.0-rc.1` and `prerelease: true`, and `--publish` posts `prerelease: true` and verifies it on read-back; a release candidate posts `prerelease: false`.
- `sync-readme-version.bats`: `--check` accepts `2.0.0-rc.1` with the shields-escaped badge; `--apply` rewrites release → rc and rc → release in lock-step.

### Constraints
- No new configuration surface: the operator signal is the topmost versioned CHANGELOG heading, honoured only for the two transitions (enter a prerelease of the computed version; promote a prerelease to its release). Any other untagged heading keeps today's behaviour (ignored).
- `bump` keeps the conventional-commit classification (`semver-evidence.bats` contract); the transition is reported in a new additive `prerelease_transition` field.
- Candidate `schema_version` stays 1; `prerelease` is additive and validated as `(.prerelease // false) == (.tag | test("-"))` so an older parked candidate still validates.
- Never weaken the clean-tree guard, the digest/checkout/origin checks or the read-back rule; `phase_release` must verify the flag on read-back, including for a pre-existing release.
- Smallest diff; `.claude/` edits under the framework marker; regenerate `grimoires/loa/REPO-MAP.md` and `.claude/checksums.json`.

## Fix Strategy
1. `semver-bump.sh`: after `next` is computed, read the topmost `## [X.Y.Z(-PRE)?]` heading of `CHANGELOG.md`; if it is untagged and (enter) `current` is a release, the heading is a prerelease and its release triple equals `next`, or (promote) `current` is a prerelease of triple T and the heading is exactly T, then `next = heading` and `prerelease_transition = {kind, source: "changelog", heading}`; otherwise `prerelease_transition = null` (a prerelease heading with a different triple warns on stderr). Prerelease identifiers are validated with the existing SemVer §9 grammar.
2. `post-merge-orchestrator.sh`: `prepare_candidate` records `prerelease: (tag has "-")`; `publish_candidate` validates the flag against the tag; `phase_release` sends `prerelease:$pre` and requires `.prerelease == $pre` on read-back (dry-run prints the flag).
3. `sync-readme-version.sh`: accept `X.Y.Z(-PRE)?`, build the badge with `--` for each literal dash, and widen the two sed patterns so an existing prerelease reference is rewritten in lock-step.
4. Runbook `grimoires/loa/runbooks/post-merge-candidates.md` (new section "Pre-release candidates") and `PROCESS.md` (Versioning Contract) document the signal, `rc.1 → rc.2`, promotion, and the marker sync.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/semver-bump.sh` | add | `changelog_prerelease_transition()` consulted after `bump_version` in `main()`; new `prerelease_transition` output field | only the two transitions; untagged heading; SemVer §9 grammar; `bump` unchanged |
| `.claude/scripts/post-merge-orchestrator.sh` | fix | `phase_release` POST body + read-back; `prepare_candidate` / `publish_candidate` candidate contract | additive field; `(.prerelease // false)` tolerance; read-back must verify |
| `.claude/scripts/sync-readme-version.sh` | fix | version regex, badge escaping, sed patterns | keep exit codes and messages (`not semver` text retained) |
| `tests/unit/semver-bump.bats` | add | five prerelease-transition cases | failing first |
| `tests/unit/post-merge-publication.bats` | add | rc candidate + flagged publication; release flag false | reuse the mocked `gh` fixture |
| `tests/unit/sync-readme-version.bats` | add | rc accepted; release→rc and rc→release `--apply` | reuse `_write_synced` |
| `grimoires/loa/runbooks/post-merge-candidates.md`, `PROCESS.md` | add | pre-release section | short; no protocol bytes |
