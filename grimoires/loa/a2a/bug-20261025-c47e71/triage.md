# Bug Triage: `classify-pr-type.sh` classifies housekeeping merges from a `chore/` branch as `cycle` when the branch name carries the cycle id — archive PRs prepare a spurious release candidate (bd-ahxmh)

## Metadata
- **schema_version**: 1
- **bug_id**: 20261025-c47e71
- **classification**: logic_bug (rule order: the cycle-id keyword rule runs before any conventional-prefix rule, so a housekeeping subject that merely names the cycle is routed to the cycle release path)
- **severity**: medium
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): `classify-pr-type.sh --title "Merge pull request #1297 from 0xHoneyJar/chore/cycle-134-archive — cycle-134 archive"` prints `cycle` (expected `other`). Production incident logs (+1): Post-Merge Pipeline runs 40112908074 (archive merge 2d1d5da1, PR #1293) and 40182103691 (archive merge 3e903cb83, PR #1297) each ran "Prepare Release (Cycle)" and prepared an unpublished candidate for a merge that changed only the archive directory and the ledger. No disqualifier (no new endpoint, UI, schema or configuration).
- **test_type**: unit
- **risk_level**: low
- **created**: 2026-10-25T23:47:44Z

## Reproduction
### Steps
1. `bash .claude/scripts/classify-pr-type.sh --title "Merge pull request #1297 from 0xHoneyJar/chore/cycle-134-archive — cycle-134 archive"` → prints `cycle`.
2. `bash .claude/scripts/classify-pr-type.sh --title "chore(archive): cycle-134 post-ship fixes — archive directory, ledger archived (#1297)"` (the squash form) → prints `cycle`.
3. `bash .claude/scripts/classify-pr-type.sh --title "Merge pull request #1298 from 0xHoneyJar/chore/cycle-134-decisions-confirm — confirmed rows"` → prints `cycle`.
4. Live: `gh run view 40182103691` (merge 3e903cb83, PR #1297) and `gh run view 40112908074` (merge 2d1d5da1, PR #1293): job "Prepare Release (Cycle)" success, "Prepare Release (Bugfix or Other)" skipped; the classify step log reads `pr_type=cycle` although `gh pr view` shows no `cycle` label (labels: `bridgebuilder:self-review`).

### Expected Behavior
- Steps 1–3 print `other`: a merge from a `chore/…` branch, or a subject with a housekeeping prefix (`chore(archive):`, `chore(ledger):`, `chore(decisions):`), takes the "Bugfix or Other" path like any non-cycle merge. *(Amended at review round 1, DEC-1001: the first draft promised `other` for every `chore:` / `chore(scope):` subject; a bare `chore:` or `chore(release):` that names a cycle can be a named release — PR #747 — and keeps the cycle route. Amended too: the other path also prepares an inspectable candidate under the publication contract — the lead's dry run of `post-merge-orchestrator.sh --generate --type other` for PR #1297 prepared v2.0.0-rc.9 unpublished — so the fix changes which job runs, not whether a candidate is prepared; nothing is tagged or published on either path.)*
- A subject that names the cycle in a `feature/…` branch merge (`Merge pull request #1296 from 0xHoneyJar/feature/cycle-134-post-ship-fixes — …`), a `feat(cycle-NNN):` or `feat(sprint-N):` subject, `Run Mode:` / `Sprint Plan:` subjects and release merges keep classifying `cycle`.
- Labels keep their precedence: a PR carrying a `cycle` label classifies `cycle` whatever its subject.

### Actual Behavior
- Steps 1–3 print `cycle` because `classify_pr_type` (`.claude/scripts/classify-pr-type.sh:56-59`) matches `\bcycle-[0-9]+\b` anywhere in the title before any prefix rule, and the archive branch name `chore/cycle-134-archive` carries the cycle id by convention (`archive-cycle.sh`).
- Live effect: the archive merge runs the cycle release pipeline ("Prepare Release (Cycle)" and its cycle-only phases) although nothing was shipped; publication still needs the operator's approved digest (post-merge-orchestrator `validate_candidate_v2`), so no wrong tag was created (tags: v2.0.0-rc.8 is the latest). *(Amended at review round 1: the "Bugfix or Other" job prepares a candidate as well, so the defect is the misclassification and the cycle-only work, not the existence of a candidate.)*
- Pre-existing: both cycle-133 and cycle-134 archive merges; also PR #1295 (`feature/cycle-133-post-ship`, a post-ship housekeeping PR) and PR #1288 (`fix/cycle-132-bugs`) classified `cycle` by the same rule — those are outside this fix (a `feature/` or `fix/` branch naming a cycle is ambiguous and stays as is).

### Environment
main `3e903cb83`; `.claude/scripts/classify-pr-type.sh` (the function) and `.claude/scripts/classify-merge-pr.sh` (the wrapper: subject from `git log -1 --format=%s`, label enrichment, KF-063 no-PR guard); consumer `.github/workflows/post-merge.yml` classify job → `full-pipeline` (`pr_type == 'cycle' && pr_number != ''`); `tests/unit/post-merge-classifier.bats` 27 cases green, `tests/unit/classify-merge-pr.bats` KF063-T1 … T14 green.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/classify-pr-type.sh` | 46-59 | high | labels rule, then `\bcycle-[0-9]+\b` on the whole title with no housekeeping exception; the three later rules (`Run Mode|Sprint Plan|feat(sprint|feat(cycle`, release merges, `^fix`) never see a chore subject that names a cycle |
| `.claude/scripts/classify-pr-type.sh` | 1-41 | medium | header comment documents the rules; must name the new one |
| `.claude/scripts/classify-merge-pr.sh` | 118-160 | low | wrapper: unchanged; it feeds the merge subject to the function and lets a `cycle` label override |
| `tests/unit/post-merge-classifier.bats` | 1-262 | high | the function's contract (PCT cases, backtest); the new cases land here |
| `tests/unit/classify-merge-pr.bats` | all | medium | wrapper contract (KF063-T1 … T14) — must stay green; T1 (ledger push subject → other) already covers the no-PR path |
| `.github/workflows/post-merge.yml` | 150-190 | low | consumer of `pr_type`; unchanged |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/post-merge-classifier.bats` | labels → cycle; `cycle-NNN` title (case-insensitive) → cycle; `Run Mode`/`Sprint Plan`/`feat(sprint`/`feat(cycle` → cycle; release merges → cycle; `^fix` → bugfix; feat without cycle id → other; usage errors |
| `tests/unit/classify-merge-pr.bats` | wrapper: subject source, `(#NNN)` trailer, `--pr-number`, gh failure, KF-063 no-PR → other |
| (none) | a housekeeping (`chore`) subject that names a cycle |

### Test Target
Extend `tests/unit/post-merge-classifier.bats` (PCT-T28 …), failing first:
- the two real archive merge subjects (PR #1293, PR #1297) → `other`;
- the squash form `chore(archive): cycle-134 post-ship fixes — … (#1297)` → `other`;
- the publisher's ledger push subject `chore(ledger): archive cycle-134-post-ship-fixes after merge` → `other` from the function itself (defence in depth under KF-063's wrapper guard);
- a decisions-confirm housekeeping merge `Merge pull request #1298 from 0xHoneyJar/chore/cycle-134-decisions-confirm — …` → `other`;
- a chore-branch merge subject with `--labels cycle` → `cycle` (labels keep precedence);
- the sprint merge `Merge pull request #1296 from 0xHoneyJar/feature/cycle-134-post-ship-fixes — cycle-134 post-ship fixes (Sprint 276)` → `cycle` (unchanged);
- `chore: bump deps` (no cycle id) → `other` (already true; pins the prefix rule's range).

### Constraints
- Fixed regexes over the untrusted subject only (no new input, no `eval`, no network); the wrapper and the workflow are unchanged.
- One new rule, placed after the labels rule and before the cycle-id rule: a merge subject from a `chore/` branch (`^Merge pull request #[0-9]+ from [^ ]+/chore/`) or a conventional `chore` prefix (`^chore(\([^)]*\))?:`) returns `other`. `fix`-prefixed subjects keep returning `bugfix`; `feature/`- and `fix/`-branch merges naming a cycle keep their current result (out of scope; noted).
- System Zone file: edit under the bounded marker (DEC-0824), `checksums.json` and `REPO-MAP.md` regenerated in the fix commit; `gen-checksums.sh --check`, `check-manifest-paths.sh` pass.
- The 27 existing cases and `classify-merge-pr.bats` stay green; the red commit lands alone first (`test(20261025-c47e71): failing test`) and `red-test-check.sh` exits 0 on the fix commit.
- No live model calls; CHANGELOG `[Unreleased]` `### Fixed` entry names bd-ahxmh.

## Fix Strategy
Add a housekeeping rule to `classify_pr_type` between the labels rule and the cycle-id rule: when the title is a branch merge from `…/chore/…` or carries the conventional `chore` prefix, return `other` — the archive, ledger and decisions-confirm merges name the cycle in their branch by convention but ship nothing. Document the rule in the header comment (with the two live runs as the incident), add the PCT cases in both directions, keep labels as the escape hatch (a `cycle` label still wins), and regenerate the System Zone manifests in the same commit.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/classify-pr-type.sh` | fix | new rule before `\bcycle-[0-9]+\b`: chore-branch merge or `chore` prefix → `other` | after the labels rule; fixed regex; no other rule changes |
| `.claude/scripts/classify-pr-type.sh` | fix | header comment: name the rule and the incident (runs 40112908074, 40182103691) | one paragraph |
| `tests/unit/post-merge-classifier.bats` | add | PCT-T28 … cases: archive merges, squash form, ledger push, decisions merge → other; chore + label → cycle; feature-branch sprint merge → cycle | red first; fixed subjects quoted verbatim |
| `CHANGELOG.md` | add | `[Unreleased]` `### Fixed` entry (bd-ahxmh) | one line |
