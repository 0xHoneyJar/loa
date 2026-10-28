# Publish summary — v2.0.0-rc.9 (cycle-137, R-6 / R-7)

**Written:** 2026-10-28 by the lead, before S-7. **Intended release sha:** a1360dac2efcab4c9e4f6ac6ddea98a4f05b95e9 (the merge commit of PR #1309 on `main`; tree c222c1f6be4bb461679ebcadc88d17421adeec4a = the PR head 3215c141f's tree, `git diff --quiet` identical).

## The candidate

| Field | Value | Check |
|---|---|---|
| Post-Merge Pipeline run | 40656882547 on a1360dac2 — completed, success (phases: 5 completed, 0 failed, 2 skipped — `changelog` skipped: "version already in CHANGELOG", as designed for the pre-cut rc heading) | ✓ |
| Artifact | `release-candidate-a1360dac2efcab4c9e4f6ac6ddea98a4f05b95e9` → `~/.cache/loa/cycle-137/candidate-rc9/` (bundle, json, patch, sha256, ledger patch, state) | ✓ |
| `merge_sha` | a1360dac2efcab4c9e4f6ac6ddea98a4f05b95e9 | = intended release sha ✓ |
| `target_commit` / `target_on_main` | a1360dac2… / true | ✓ |
| `pr_number` / `pr_type` | 1309 / `cycle` | classification as planned ✓ |
| `tag` / `release_title` / `prerelease` | `v2.0.0-rc.9` / `v2.0.0-rc.9` / true | majors ship as an rc first ✓ |
| Printed digest (`post-merge-candidate.sha256`) | `0467e73bf510965f7281efb391e5c864cb545e6654eaa816fe648f6e8da76430` | |
| Lead-recomputed digest (`sha256_portable` over the fetched `post-merge-candidate.json` bytes, from compat-lib) | `0467e73bf510965f7281efb391e5c864cb545e6654eaa816fe648f6e8da76430` | equal ✓ |
| Bundle | `git bundle verify` ok (sha1 object format) | ✓ |
| Remotes recorded | origin `https://github.com/0xHoneyJar/loa`, push the same (CI records the URL without `.git`; the publish clone's remotes are set to match byte-for-byte) | ✓ |
| Ledger commit in the candidate | `chore(ledger): archive cycle-137-performance-followups after merge` (github-actions[bot]); `ledger_patch_sha256` 72b76614… | applied by `--publish` (or `--ledger-only` on rc 3) |
| CHANGELOG heading on the release sha | `## [2.0.0-rc.9] — 2026-10-28 — Performance follow-ups (release candidate)` with a fresh `[Unreleased]` above (cut in 8d63417b0) | ✓ |
| Version stamps on the release sha | `.loa-version.json`, `.claude/loa/CLAUDE.loa.md` header, README version / badges / install pin at `2.0.0-rc.9` (README version sync check green on main) | ✓ |
| Release notes | the candidate's generated body (commit list; `release_notes_sha256` 55e6afb0…); after the publish the release page notes are replaced with `grimoires/loa/reports/release-notes-2.0.0-rc.9.md` (sha256 fa944df5c5bd100f98a9ca623c2f57225a28cdbf711075f4bff8980f624ee96a) via `gh release edit --notes-file` | S-7 |
| Assets | none listed by the candidate (`assets: []`); the release's only artefact is the tag + notes | R-8 asset check is vacuous |

## Release predicate (prd.md § Scope)

| Rule | Evidence |
|---|---|
| R-1 both sprints `COMPLETED` with `All good` + `APPROVED` bound to SHAs | 281: review d005a771a / audit 747b5db0d; 282: review + audit on 03f910129, bound to the PR head 3215c141f (docs-only tail, D-1.1) — `a2a/sprint-28{1,2}/` on the record branch 5610a68ba |
| R-2 every bead landed or deferred by a class-S row | six beads landed (e2e.md § G-2); no deferral |
| R-3 merge gate on the exact PR head | `ship-1-merge.sh 3215c141f`: six required checks completed/success, 0 pending, 0 not green; 46/46 check runs pass; admin merge a1360dac2; identical trees |
| R-4 full `tests/unit` on the final head fails only the allowed three | 03f910129: 7315 planned / 7312 ok / 3 not ok (`semver evidence` ×3, KF-034) / 135 skipped, skip names identical to 8d63417b0; `evidence/tap/unit-03f910129.tap` |
| R-5 main CI on the merge commit | `CI` 40656882541 completed success; `BATS Tests` 40656882501 completed success (Shell Tests job ~75 min; observed 2026-10-28T09:20Z) — both green before the publish ✓ |
| R-6 digest recomputed and equal | above ✓ |
| R-7 this summary before the publish | this file (record branch stage 2 / archive PR) |
| R-8 post-publish identity | filled in `e2e.md` Part 2 (tag peel = a1360dac2, remote tag object = local, ancestor of origin/main, release page target, smoke test) |

## Beads at publish time

Sprint 281: bd-520lp bd-4wpi0 bd-0qnop bd-0zfjg closed. Sprint 282: bd-7e8v2 bd-eakaf bd-acolw bd-2uj7p bd-svmkr bd-3de6b (tasks) closed provisionally — ship-4 updates their close reasons with a1360dac2; bd-93bee closed (gates); bd-qyi0c (e2e) and bd-b83ij (ship) close at ship-4. Follow-ups open: bd-0h7kq bd-3qed8 bd-4sikh bd-kdzc3 (281) · bd-20bh1 bd-z6gxn bd-aceil bd-rq6gk bd-5v1oa bd-j34zb bd-hyah6 bd-7utms bd-yos4s bd-y5fy4 (282).

## Class-S rows written this cycle

DEC-1109 … DEC-1138 on the merged branch; DEC-1139 (Bridgebuilder degraded exit) and DEC-1140 (loaded re-baseline caveat) plus the KF-037 recurrence (13) ride the archive PR. No class-H row. Confirm with `/decisions confirm --cycle cycle-137-performance-followups --all`.

## Rollback (S-9, written before S-7 runs)

Revert the merge commit on `main` with manifests regenerated (version pins return with it); mark the GitHub release as a withdrawn pre-release and leave the tag; the record branch and archive stay as history with a note; reopen the beads; a DEC row records the withdrawal and the cause.
