All good

# sprint-bug-277 (bug 20261025-c47e71, bd-ahxmh) — Senior Technical Lead Review, round 2 (final)

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `b1acf9a64` (red `893a68eb3`, fix `cfdd94f9d`, round-1 wording `b1acf9a64`) on `fix/post-ship-bugs-classifier-bb-glob` · **Round 1:** `engineer-feedback-r1.md` (CHANGES_REQUIRED, 1 MEDIUM, 2 LOW) · **Dissent:** one review run (`adversarial-review.json`, codex-headless + claude-headless 2/2, chain ok, consensus APPROVED, 3 ADVISORY) — not re-run for the wording round (no behaviour change) · **Implementation report:** `reviewer.md`

## Summary

The round-1 MEDIUM is closed: the rule comment (`classify-pr-type.sh:52-68`), the PCT comment block (`post-merge-classifier.bats:258-263`) and the CHANGELOG line now state the true effect — the archive, ledger and decisions-confirm merges no longer run the cycle release pipeline ("Prepare Release (Cycle)"); they take the Bugfix-or-Other job like any non-cycle merge, which still prepares an inspectable candidate, and publication stays explicit. No "spurious candidate" claim survives (grep). The rule itself is unchanged from `cfdd94f9d` and remains right and minimal: one shape rule after the labels rule and before the cycle-id rule, narrowed to the housekeeping scopes so a named release (`chore(release): … (cycle-098 …)`, PR #747) keeps the cycle route (DEC-1001 … DEC-1003). Nine cases pin both directions.

## Verified

- Red-then-green: `red-test-check.sh --red 893a68eb3 --green cfdd94f9d -- bats tests/unit/post-merge-classifier.bats` → **VERIFIED** (`bats` supplied from the npx cache on the caller's PATH, which the check keeps because it is absolute and outside the repository).
- Suites at `b1acf9a64`: `post-merge-classifier.bats` 36/36, `classify-merge-pr.bats` 31/31, `post-merge-workflow-guards.bats` 4/4 (1..71 ok); `bash -n` ok; manifests regenerated under the bounded marker in both commits (`gen-checksums.sh --check` OK, `repo-map-gen.sh --validate` consistent, `check-manifest-paths.sh` 0/0).
- E2E on the live subjects at `b1acf9a64`: PR #1297 archive merge → `other`; PR #1298 decisions-confirm merge (its real subject) → `other`; PR #1296 sprint merge → `cycle`.
- The destination route, dry-run by the lead (detached worktree at `3e903cb83`, `post-merge-orchestrator.sh --generate --pr 1297 --type other`): `[PREPARED] … v2.0.0-rc.9 … (target_on_main)`, release_type `other`, nothing tagged or published — the basis of the round-1 correction and the answer to the dissent's spurious-PATCH-tag worry.
- Triage amended (Expected Behavior and Live effect) to the landed contract; bead bd-ahxmh carries the correction.

## Observations (non-blocking, carried from round 1)

- **LOW** (confidence: medium) `.claude/scripts/classify-pr-type.sh:71` — `chore(cycle-NNN):` squash subjects keep classifying cycle. Failure: when a writer emits a `chore(cycle-NNN):` squash subject that ships nothing, then the merge still runs the cycle pipeline; no writer emits that shape today (grep of `.claude/scripts`, `.claude/skills`).
- **LOW** (confidence: medium) `.claude/scripts/classify-pr-type.sh:75` — `fix/`-branch merges naming a cycle (PR #1288 shape) still classify cycle. Failure: when a fix branch named after a cycle merges without a label, then the cycle pipeline runs for a bugfix; out of the observed failure (DEC-1002 alternative).

## Dissent dispositions

Unchanged from round 1: advisory 1 → the round-1 MEDIUM, fixed in `b1acf9a64`; advisory 2 → DEC-1001 + triage amendment; advisory 3 → manifests are in the commits.

## Rejected dissent payloads

None.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"sprint_id":"sprint-bug-277","ts":"2026-10-26T00:55:00Z"} -->
