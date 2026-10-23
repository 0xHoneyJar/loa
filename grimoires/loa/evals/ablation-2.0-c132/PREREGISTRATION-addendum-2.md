# Pre-registration addendum 2 — cycle-132

**Supersedes:** `REGISTRATION-1.json` sha256 `277a6effd8634004b32947bf151dc1fb4ff87a21f601d75dde9666bb4af3a978` (pin `664c45164764462fd4c5676f10e8cffce9c3aad6`). **Registered as:** `REGISTRATION-2.json`. **Governing text:** `PREREGISTRATION.md` is unchanged except as read through this addendum: in §3 the dissent's budget cap is 1,200 cents, not 600, and in §4 the took-effect rule set of the three pipeline arms gains `dissent_present`.

## What the smoke found

The smoke's first `a1_full` row (review-r19, a 6,794-line diff, 2026-10-21T09:15Z) ran both gates **without their dissent**: the eval config variant's `budget_scale: diff` with `budget_cents_max: 600` made `adversarial-review.sh` refuse itself on both gates (`status budget_exceeded (estimate 627c > effective cap 600c); review proceeds single-voice`), the row recorded `dissent_absent_reason {review: error, audit: budget}` with `degraded: false`, and every took-effect rule read true. The registered arm is "REVIEW → AUDIT, both with the codex dissent"; a run without the dissent is the no-dissent arm, and four of the fourteen registered diffs exceed 5,800 lines, so the full arm would have degenerated on the largest quarter of the corpus while counting as valid.

## What changed

1. **Budget cap:** `lib/sandbox-mount.sh apply_eval_config_variant` sets `budget_cents_max: 1200` for both gates (the largest registered diff estimates about 660 cents; `budget_scale: diff` still scales small PRs down). The k table is unchanged: the cost fits behind it come from runs in which the dissent did run, so the planned full-arm cost already carries it; the realized cost on the largest PRs rises only by the dissent that was being skipped (≈ USD 6 per gate), which the dollar-matching flag and the exact-dollar trim cover.
2. **Took-effect rule `dissent_present`** on `a1_full`, `a1_full_openmount` and `a1_review_only`: every executed gate must carry its dissent envelope with at least one voice succeeded and no refused or budget-exceeded status; otherwise the cell is invalid under §4 (and counted in the 25 % guard and the missingness bounds), instead of silently passing as the arm.

## Why this is a correction, not a design change

The arm definition, estimands, groups, looks, boundaries, cap and seed are untouched; the change makes the registered arm enforceable and lets it run as registered. No graded Phase 1 row exists: the smoke rows decide nothing, and the smoke is re-run after this addendum under a new batch name (`c132-smoke2`); the first smoke's rows are kept in the shared runs file for the record and are excluded from every read by batch name.

## Reporting

The final report names addenda 1 and 2 beside the registration hashes and states the dissent-presence rate per arm and group.
