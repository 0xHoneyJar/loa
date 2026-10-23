# Pre-registration addendum 5 — cycle-132

**Supersedes:** `REGISTRATION-4.json` sha256 `f2c0e8f99083a742318e9d3e2197d63d3ee8768fb20f2190325403b5a694e70c` (pin `09fb09005843aa3097906a26c6cce007784443c7`). **Registered as:** `REGISTRATION-5.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §2's runtime-leakage statement is read with the exception below.

## What the smoke found

The second smoke's `a1_full` run on review-r15 was refused before any phase: `mount_cheval_broken: ImportError: cannot import name 'EFFORT_LEVELS' from 'loa_cheval.types'` — KF-050. The closed mount writes the PR's and fix commit's touched paths at the PR's head commit; five registered fixtures (pr-11, pr-14, pr-15, pr-21, pr-22) touch `.claude/adapters/`, the cheval transport the pipeline's dissent runs on, so the pinned importers meet an older module and every dissent-enabled arm is refused on a third of the corpus.

## What changed

`lib/sandbox-mount.sh` leaves every path under `.claude/adapters/` pinned (excluded from the overlay) and records the excluded paths in the arm evidence (`overlay_excluded`); took-effect `oracle_closed` holds when every other PR/fix path is overlaid. The PR's own versions of those files remain fully visible under `pr/head/`, `pr/base/` and `pr/head.diff`.

## What this costs, stated

For those five fixtures the sandbox copy of each adapter file is the pinned (later, fixed) version, so the KF-049 oracle — diffing the PR's file against the workspace copy — is open on exactly those files. The grader's oracle detector marks such a run `oracle_exposed_defects`, which makes the cell invalid under §4 and counts in the 25 % guard and the missingness bounds; the report prints the oracle-exposure rate per PR and arm. The five PRs may therefore lose cells to exclusion; that is the honest price of running the pinned pipeline on PRs that modify its own transport. The alternatives — dropping the five PRs, or running a PR-era cheval — would respectively halve the harness-PR share of the corpus and change the pipeline under test.

## Why this is a correction, not a design change

The arm definition, estimands, k, groups, looks, boundaries, cap and seed are untouched; the pipeline under test is the pinned one, as registered. No graded Phase 1 row exists.
