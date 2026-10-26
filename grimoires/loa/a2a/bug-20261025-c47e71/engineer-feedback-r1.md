CHANGES_REQUIRED

# sprint-bug-277 (bug 20261025-c47e71, bd-ahxmh) — Senior Technical Lead Review, round 1

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `cfdd94f9d` (red `893a68eb3`) on `fix/post-ship-bugs-classifier-bb-glob` · **Dissent:** one review run (`adversarial-review.json` in this directory; codex-headless + claude-headless, 2/2, chain ok, consensus APPROVED, 3 ADVISORY payloads) · **Implementation report:** `reviewer.md` · **Code read:** the rule and its comment (`classify-pr-type.sh:52-68`), the header rule list (`:32`), PCT-T28 … T36, the CHANGELOG line; `red-test-check.sh --red 893a68eb3 --green cfdd94f9d -- bats tests/unit/post-merge-classifier.bats` → VERIFIED

## Summary

The rule is right and minimal: one shape rule after the labels rule and before the cycle-id rule, narrowed to the housekeeping scopes so a named release (`chore(release): … (cycle-098 …)`, PR #747) keeps the cycle route — a judgment call the implementer made over the brief, with the pinned case and the live PR as evidence (DEC-1001). Nine cases pin both directions. What is wrong is the **stated effect**. The report, the rule comment, the bats comment and the CHANGELOG line all say the housekeeping merges "no longer prepare a spurious release candidate". The lead's dry run of the destination route says otherwise: `post-merge-orchestrator.sh --generate --pr 1297 --type other --sha 3e903cb8…` in a detached worktree prepared a candidate (`[PREPARED] … tag v2.0.0-rc.9 on the merge 3e903cb8 (target_on_main)`, release_type `other`), because the "Prepare Release (Bugfix or Other)" job runs the same `--generate` step. The fix therefore changes **which job runs** — housekeeping merges leave the cycle pipeline — not whether a candidate is prepared. Nothing is tagged or published on either path (publication stays explicit; the latest tag is v2.0.0-rc.8), which also answers the dissent's worry about a spurious PATCH tag on the `other` path.

## Findings

- **MEDIUM** (confidence: high) `CHANGELOG.md:12`, `.claude/scripts/classify-pr-type.sh:56-57`, `tests/unit/post-merge-classifier.bats:258-261` — the effect is misstated. Failure: when an operator reads the CHANGELOG or the comment, then they believe archive merges stop producing candidates and are surprised by the next `other`-path artifact. Fix: state the true effect — the merges no longer run the cycle release pipeline; they take the Bugfix-or-Other job like any non-cycle merge, which still prepares an inspectable candidate; publication stays explicit. Same correction in the triage's Expected Behavior and the bead (lead).

## Observations

- **LOW** (confidence: medium) the triage's Expected Behavior promised `other` for every `chore:` / `chore(scope):` subject; the landed contract is narrower (`chore(archive|ledger|decisions):`) and `chore(cycle-NNN):` squash subjects keep classifying cycle. No writer emits `chore(cycle-NNN):` today (grep of `.claude/scripts` and `.claude/skills`: none), so this is a documentation amendment, not a gap: the lead amends the triage and records DEC-1001 (dissent advisory 2).
- **LOW** (confidence: high) the dissent's third advisory ("no checksums/REPO-MAP in the diff") is an artefact of the dissent input: the lead's diff file excluded the regenerated manifests; they are in the fix commit (`cfdd94f9d`: `checksums.json`, `REPO-MAP.md`, `REPO-MAP.md.checksum`; `gen-checksums.sh --check` OK, `check-manifest-paths.sh` 0/0, `repo-map-gen.sh --validate` consistent; the edit was made under the DEC-0824 bounded marker by the landing script).

## Dissent dispositions (3 advisories)

- Destination route asserted, not evidenced → confirmed by the lead's dry run; becomes the MEDIUM above (the claim is wrong, the rule is right); no spurious tag on the `other` path (candidate only, nothing published).
- Prefix narrowed vs the triage's expected behaviour → observation 1; DEC-1001; triage amended by the lead.
- Manifests missing from the diff → observation 2 (present in the commit).

## Rejected dissent payloads

None.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-bug-277","ts":"2026-10-26T00:40:00Z"} -->
