# Operator prompt — cut `2.0.0-rc.1` (stable candidate) from PR #1266

**Issued by:** Jani (Loa creator/maintainer) · **Date:** 2026-09-23 · **Authorization:** the rc plan was approved 2026-09-22 ("this will need to be a stable candidate … however we achieve that formally is the way to go"). Unattended run; do not stop to ask unless an item below says *operator-only*.

## 1. Where things stand (verified 2026-09-22, do not re-derive)

- Branch `feature/cycle-124-model-generation-floor`, head `a20fffeb`, draft PR **#1266** → `main`, assigned to @deep-name (the author, so a review request is impossible). CI on that head: 64 pass, 2 skipping (`Verify install` — Aleph opt-in; `GH audit-log admin-bypass scan`), 0 fail. Title classifies as `cycle` (`classify-pr-type.sh --title`), so a merge would run the **full** post-merge pipeline.
- Content: cycle-124 sprints 235–238 (adapter floor Opus 5 / Sonnet 5 / Fable 5.1, `default_max_tokens`, adaptive thinking, prompt caching, structured outputs, verdict gates, ledger isolation, prompt byte budgets + 49-unit audit, coverage-first review/audit, eval A/B harness, bounded NOTES.md), the post-close `/bug` that made **Aleph opt-in** (`aleph.enabled`, default false), the record-branch move, and six Bridgebuilder iterations of workflow hardening (`check-prompt-budget.yml`, `live-floor-check.yml`).
- The per-sprint a2a record is on the never-merged branch `record/cycle-124-a2a` (`e0ccc783`); this template repo forbids `grimoires/loa/a2a/sprint-*` and `a2a/trajectory/` as new files on `main`. Bug dir `grimoires/loa/a2a/bug-20260922-13a3d1/` stays in the PR.
- Version state: latest tag `v1.202.1`; `semver-bump.sh --from-tag` → `next 2.0.0, bump major` (upstream `2af691ac fix(release)!:` plus this cycle's operator-visible changes). `.loa-version.json` is stale at `1.196.0`. A parked candidate v1.203.0 and the #1251 "prepare, then approve-and-publish" flow are still unresolved (framework-review §9 item 4).
- Release policy (memory `feedback_release_candidate_before_stable`): a major ships first as a **pre-release** `2.0.0-rc.1`, soaks with real users, fixes land as `-rc.N`, then promotion to `2.0.0`. Deliverables follow `feedback_named_release_pattern`.
- Known host facts: no valid Anthropic HTTP credential (the `.env` key returns 401 — do not rely on it; the sanctioned path is the `claude-headless` CLI; never borrow the Claude Code OAuth token); Bridgebuilder has only the OpenAI voice here; `gh pr edit` fails on the deprecated projectCards field — update PR bodies with `gh api --method PATCH repos/0xHoneyJar/loa/pulls/1266 --input -` (KF-031).

## 2. Objective

Make PR #1266 the **release-candidate PR** for `2.0.0-rc.1`: every named-release deliverable in place, the formal mechanism for cutting a *pre-release* through the existing pipeline determined (and, if missing, built with tests), and the operator's publish/soak/promotion steps written down. Do **not** merge, tag, publish or push to `main`. The operator merges and approves publication.

## 3. Constraints (all still in force)

- Never merge, never push to `main`, never create tags by hand (`semver-bump.sh` owns version computation; the post-merge pipeline owns tags). Push only through `.claude/scripts/run-mode-ice.sh push origin <branch>`.
- Smallest diff; failing test first for any code change; no new config surfaces beyond what the mechanism strictly needs; `// loa:shortcut:` markers where you take one.
- Never weaken fences (`block-destructive-bash.sh`, `zone-write-guard.sh`, `implement-gate.sh`, audit-envelope fail-closed, the new `FR-NOTES`/`notes-size-guard.sh`). Aleph stays opt-in; do not touch Aleph-managed files.
- `.claude/` edits need the framework-dev marker: `printf '{"scope":"framework","reason":"<why>","expires_at":"<RFC3339 Z>"}' > .run/zone-guard-authorization.json`; regenerate `grimoires/loa/REPO-MAP.md` (`repo-map-gen.sh`) and `.claude/checksums.json` after every `.claude/` change; delete the marker when done.
- Keep the PR under GitHub's 300-file diff limit and Bridgebuilder's 10 MiB files payload: release docs are small; nothing under `grimoires/loa/a2a/sprint-*` or `a2a/trajectory/` is added to the PR (put any new record on `record/cycle-124-a2a`).
- No secrets in tracked state. Prompt byte budgets stay green (`tools/check-prompt-budget.sh`; protocols are at 199,593 B of 200,000 — do not add protocol bytes).
- Code changes go through `/review-sprint` + `/audit-sprint` with cross-model dissent (the `adversarial-review.sh` path works on this host); docs-only commits do not need Bridgebuilder (memory: skip BB kaironic on chore-release PRs). If code changes land, run one Bridgebuilder pass and triage it.
- Every claim in the report cites `file:line` or observed output. Record KF recurrences with `kf-write-lib.sh` (sandbox with `--file <copy>` first). File follow-ups as beads with the `cycle-124-followup` label.

## 4. Work plan

### Phase A — the formal pre-release mechanism (decide first, build only if missing)

Read `.claude/scripts/semver-bump.sh` (prerelease handling: `X.Y.Z-PRE.N` increments N; entering a prerelease from a release version and promoting out of one are called "operator-driven"), `.claude/scripts/post-merge-orchestrator.sh`, `.github/workflows/post-merge.yml` (the `cycle` path prepares a complete candidate without publication), `grimoires/loa/runbooks/post-merge-candidates.md` (`--publish <candidate.json> --approve-sha256 <digest>`), `PROCESS.md` §Versioning Contract, and `.claude/scripts/release-notes-gen.sh`. Answer, with evidence: when #1266 merges, what version does the prepared candidate carry, and how does an operator make the published artifact `2.0.0-rc.1` marked **pre-release** on GitHub instead of `2.0.0`?

If the pipeline has no formal way to enter a prerelease, implement the smallest one as a bug micro-sprint on this branch (`/bug` conventions: triage + `sprint.md` under `grimoires/loa/a2a/bug-<id>/`, ledger bugfix cycle, bead, tests first, review, audit, COMPLETED): for example a `--enter-prerelease rc` mode for `semver-bump.sh` that maps a computed `2.0.0` to `2.0.0-rc.1`, driven by an explicit, documented operator signal the orchestrator reads (a CHANGELOG heading of the rc form is the least new surface; prefer that over a new config key), and `gh release create --prerelease` whenever the version string carries a prerelease tag. Cover: entering rc, `rc.1 → rc.2` on the next cycle merge, promotion `rc.N → 2.0.0` as an operator-driven step, and the CHANGELOG/`.loa-version.json`/README sync. Document the runbook steps in `grimoires/loa/runbooks/post-merge-candidates.md` (a new short section) and PROCESS.md.

If a dry-run or `--generate` mode can be exercised in a clean worktree without network side effects, run it and record the candidate's version and release flags as evidence.

### Phase B — breaking-surface audit (the honest list, verified in code)

Enumerate every operator-visible change since `v1.202.1` and classify it with the semver rules in `feedback_named_release_pattern` (removed/renamed config keys, default changes, new runtime errors, schema tightening = MAJOR; additive = MINOR). Known candidates to verify at the line: `default_max_tokens()` (4096 → 16K/64K/≥64K at xhigh/max) and `--max-tokens 0` ⇒ `INVALID_INPUT`; adaptive thinking on 4.6+ (omitted for Fable); the model floor and catalog ids; `repair_loop` keys removed; forced `tool_choice` modes raise; three protocols archived (`risk-analysis.md`, `sprint-completion.md`, `upgrade-process.md`) and the `.constraint-*` twins deleted; LOA-VERDICT one-way rule enforced by the golden path (legacy files keep old behaviour — check); `excluded`/`excluded_confirmed` trailer fields; NOTES.md fences (`notes-size-guard.sh`, `FR-NOTES`, writer gate) and the Level-1 read change; `aleph.enabled` default false (**breaking for Aleph users**); `live-floor-check.yml` now a release precondition on `main`/`release/*`; `check-prompt-budget.yml` on every PR; eval executor `--restricted --tools`. For each: what breaks, the kill switch or compat path (`aleph.enabled: true`, explicit `--max-tokens`, `LOA_RUN_LIVE_TESTS`, `LOA_ALEPH_ENABLED`, etc.), and the migration step.

### Phase C — named-release deliverables (docs; keep the diff small)

1. `CHANGELOG.md`: move `## [Unreleased]` into `## [2.0.0-rc.1] — <date> — Model-generation floor (release candidate)` with a **Breaking** section first, then Added/Changed/Fixed/Security; leave `[Unreleased]` empty. Keep one line per shipped item; do not paste sprint reports.
2. `docs/migration/v2.0-model-generation-floor.md` (pattern: `docs/migration/v1.196-mechanical-floor.md`): 3–5 worked recipes (downstream mount upgrade; a repo that relies on Aleph; a repo with pinned `max_tokens`/`tool_choice`; a repo consuming the archived protocols; operators of the eval harness), the compat guarantees, and the rc soak/feedback instructions.
3. `docs/architecture/ADR-004-model-generation-floor.md` (pattern: `ADR-003-mechanical-floor.md`): context → decision → alternatives → trade-offs → outcomes, including "Aleph opt-in" and "rc before stable" as recorded decisions.
4. `README.md`: a "What's new in v2.0.0-rc.1 (release candidate)" block above "What Is This?" linking the migration guide and ADR; note that the install pin example should move to the rc tag once it exists. Run `.claude/scripts/sync-readme-version.sh --apply` only if it supports a prerelease string (check first; otherwise leave the badge and say so).
5. `.loa-version.json`: `framework_version: "2.0.0-rc.1"` (currently `1.196.0`; confirm `update-loa-bump-version.sh` or the schema accepts a prerelease string — if not, that is a Phase-A finding).
6. Release notes: `grimoires/loa/reports/release-notes-2.0.0-rc.1.md` (2,000–3,000 chars) — what changed, the breaking list with kill switches, operator steps, the soak plan, and the **rc exit criteria** (e.g. ≥ 2 downstream mounts upgraded via the migration guide; no CRITICAL/HIGH issue open against the rc for 14 days; `live-floor-check.yml` recorded a pass on the release branch; `check-loa.sh` green on a fresh mount with Aleph absent). The operator uses this as the GitHub release body.
7. PR body (REST PATCH per KF-031): add a "Release candidate 2.0.0-rc.1" section with the mechanism decided in Phase A, the operator publish steps, and links to the docs; keep the title containing `cycle-124` so classification stays `cycle`.

### Phase D — operator steps to record (operator-only; write them, do not perform them)

- Rotate or remove the Anthropic key in the local `.env` (rejected with 401).
- Create the `live-floor` GitHub environment with required reviewers and a deployment-branch policy limited to `main` and `release/*`, then store `ANTHROPIC_API_KEY` there.
- Decide the vendored Aleph tree's fate (bead bd-c7ma).
- Resolve the parked v1.203.0 candidate / #1251 flow, then: mark #1266 ready, merge, let the pipeline prepare the candidate, inspect it per the runbook, publish with `--publish … --approve-sha256`, verify the release is flagged pre-release.
- Soak; collect feedback as issues labelled `2.0.0-rc`; promotion `rc → 2.0.0` per the rc exit criteria.

### Phase E — verification before you stop

CI green on the final head (`gh pr checks 1266`); `tools/check-prompt-budget.sh` ok; doc-lock suites for anything you touched (`npx --no-install bats tests/unit/<suite>.bats`); if code changed, `tests/unit/` full run (33 known reds: 25 pre-existing + 8 time-dependent licence fixtures; anything new is yours) and the ledgers untouched (`sha256sum .run/model-invoke.jsonl .run/cost-ledger.jsonl` before/after); `semver-bump.sh --from-tag` and `classify-pr-type.sh --title` outputs recorded; `repo-map-gen.sh --validate`; zone marker deleted; `git status` clean; NOTES.md Decision Log entry; memory file `session-2026-09-17-cycle124-model-floor.md` updated with the outcome and the next operator step.

## 5. Stop conditions

Stop when: the Phase-A answer is written with evidence (and, if built, its micro-sprint has COMPLETED with consistent LOA-VERDICT trailers), all Phase-C deliverables are pushed to #1266 with CI green, the PR body carries the release-candidate section and the operator steps, and NOTES/memory are updated. Also stop on an operator-only blocker (credentials, environment settings, publication) after writing down exactly what is needed.

## 6. Pointers

- Memory: `feedback_release_candidate_before_stable.md`, `feedback_named_release_pattern.md`, `reference_release_process.md`, `feedback_aleph_opt_in_not_a_constraint.md`, `session-2026-09-17-cycle124-model-floor.md` (gotchas: verdict trailer scanner, ledger-lib from bash, hook template wiring, BB payload limits, CI-only gates).
- Beads to keep in view: bd-c7ma (vendored Aleph), bd-pr59 (BB anthropic voice), bd-eohi (BB unposted review), bd-7g2d (hash-pinned installs), bd-rk9o (guardrails `--mode run`), bd-vq7v (confined A/B re-measure), bd-72fq (protocol warn line).
- Records: `record/cycle-124-a2a` (sprint reports, feedback, dissent, prompt audit, A/B); `grimoires/loa/a2a/framework-review-2026-09-17.md` §9 (status column filled); the six Bridgebuilder triage comments on #1266.
