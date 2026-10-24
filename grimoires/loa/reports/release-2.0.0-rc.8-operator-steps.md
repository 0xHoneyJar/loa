# 2.0.0-rc.8 — release steps (cycle-133, PR #1292)

Recorded 2026-10-25 before the merge, as the plan of record (the rc.2 precedent). The operator's instruction for cycle-133 was "proceed end to end with implementing all the beads / improvements" under the refusal list of PRD § Authorization basis: never force-push or write `main` outside the publish fast-forward, never delete tags or branches, never bypass red CI or an unresolved Bridgebuilder blocker, never publish a non-rc.

## Before merging (on the branch) — done

1. CHANGELOG: `[Unreleased]` → `## [2.0.0-rc.8] — 2026-10-25 — The follow-through (release candidate)` with a fresh `[Unreleased]` (`f898c739e`); `semver-bump.sh --from-tag` computes `2.0.0-rc.8` from `v2.0.0-rc.7`.
2. Framework markers at `2.0.0-rc.8` (`update-loa-bump-version.sh --target 2.0.0-rc.8` under the bounded zone marker → `.loa-version.json`, `CLAUDE.loa.md` header with its hash preserved); README version line, badges, install pin and the rc.8 "What's new" block (`sync-readme-version.sh --check`: in sync).
3. `grimoires/loa/reports/release-notes-2.0.0-rc.8.md` and this file.
4. REPO-MAP + `.checksum` + `.claude/checksums.json` regenerated together; `check-prompt-budget.sh` ok; gates PASS; the zone marker removed after the last `.claude/` edit.
5. Review and audit APPROVED for Sprints 272–275 (the Sprint 275 audit carries its own `adversarial-audit.json` envelope); Shell Tests green on the head that merges.

## Merge and publish

6. PR #1292: body from the sprint reports (`~/.cache/loa/cycle-133/reports/pr-1292-body.md` → the PR), marked ready; the subject keeps `cycle-133` so `classify-merge-pr.sh` routes to the full pipeline.
7. Bridgebuilder round(s) with the skill built from the cycle branch (`.claude/skills/bridgebuilder-review/resources/entry.sh --pr 1292`; dist fresh per `check-bb-dist-fresh`), triaged by the lead: plateau rule (stop after a round adding no new HIGH or MEDIUM; at most three rounds; ≤ USD 20); a HIGH → fix, re-review, re-audit before the merge; the verdict JSON's `degraded_reason` (must be absent) and the summary-vs-consensus equality are G-2's evidence. If the PR's shape degrades the review, split per the FR-12 guidance before reading G-2.
8. Required checks (`Template Protection`, `Validate Framework Files`, `Lint Markdown`, `Lint YAML`, `Shell Tests`; strict, one approving review required, admins not enforced) green on the final head; any later patch re-runs them.
9. Admin merge with a merge commit (`gh pr merge 1292 --merge --admin`; the sole maintainer cannot review their own PR); record the merge sha.
10. `record-branch.sh --cycle 133 --head <merge sha> --prev record/cycle-132-conclusive-review-catch --stage "stage 1"` (a2a sprint directories 272–275 incl. the smoke evidence and the sweep, audits, NOTES; the C-4 scan refuses a credential-shaped hit) → ICE push of `refs/heads/record/cycle-133-follow-through`.
11. Wait for `post-merge.yml` on the merge; download `release-candidate-<merge sha>`; recover in an isolated FULL clone per `grimoires/loa/runbooks/post-merge-candidates.md` (bundle verified, `target_commit` = the merge, candidate JSON and `post-merge-ledger.patch` restored under `.run/`); inspect the candidate (version `2.0.0-rc.8`, `prerelease: true`, the notes digest).
12. `post-merge-orchestrator.sh --publish .run/post-merge-candidate.json --approve-sha256 <digest>` from that checkout; exit 3 (main moved) → `--ledger-only` with the same digest. Verify: the tag `v2.0.0-rc.8` is annotated on the merge commit and `git branch -r --contains v2.0.0-rc.8` on a fresh fetch names `origin/main`; the release exists with `prerelease: true` (G-3).
13. `gh release edit v2.0.0-rc.8 --notes-file grimoires/loa/reports/release-notes-2.0.0-rc.8.md`; the repository "latest" stays the last stable tag.
14. `archive-cycle.sh --cycle 133 --retention 50` on a `chore/cycle-133-archive` branch (the generated CHANGELOG template replaced by the merged rc.8 section; README by hand if needed) → PR → admin merge; ledger cycle-133 archived.
15. e2e.md rows G-2, G-3 and FR-14 filled; the ship DEC rows; run state JACKED_OUT with the completion record; NOTES Session Continuity; memory.

## Still maintainer-only

- Confirm the cycle's decision rows (DEC-0819 … the ship rows) by id list; read DEC-0946 (floor amendment) and DEC-0950 (FR-10 deferred) with their alternatives.
- Remove the `floor_amendments` row for `verdict-derive.sh` once this merge is on `main` (re-pin `FLOOR_SHA256`).
- The soak and the `2.0.0` promotion PR when the rc.1 exit criteria hold; `live-floor-check.yml` with a valid key.
