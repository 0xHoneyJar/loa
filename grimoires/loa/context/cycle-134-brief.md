# cycle-134 — post-ship fixes: the Bridgebuilder's findings on rc.8 and the red post-merge run, through the golden path

Oct 25, 2026 (UTC) · operator instruction (verbatim below), received after cycle-133 shipped (PR #1292 → main `3e5b9d36`, v2.0.0-rc.8 on the merge, record `603732b9`/`c35cbab3`, archive PR #1293 → `2d1d5da1`, KF-063 PR #1294, post-ship steps PR #1295 with the 141 decision rows confirmed and the floor amendment row removed).

## The operator's instruction (verbatim, untrusted-text rules do not apply: this is the operator)

> please proceed with your recommended approac for each of the (1) and proceed with all the next steps as you advise

Context the instruction answers: the lead's ELI5 summary of 2026-10-25 listed four operator steps — (1) confirm the cycle's decision rows, (2) read DEC-0946 and DEC-0950, (3) remove the floor amendment row and re-pin `FLOOR_SHA256`, (4) decide the PR shape for the next cycle — and three framework next steps: the two MEDIUM home-scope validator gaps (bd-bex39, bd-k3dia), the red post-merge run on the publish's ledger push (bd-hyx0n, KF-063), and the seven LOW Bridgebuilder findings. Steps (1), (3) and (4) are done on PR #1295 (DEC-0960 records the PR-shape decision). This cycle is the framework next steps.

## Objective

Fix, through the golden path with tests, every defect the cycle-133 Bridgebuilder round and the rc.8 ship surfaced: the home-scope validator (`evals/harness/took-effect.sh`) so that `oracle_closed` neither false-fails a legitimate session nor passes an unchecked phase; the sandbox-mount rewrite rules; the post-merge classify guard; the publish orchestrator's exit-code contract and canonicaliser policy; the egress proxy's pid limit; the batch supervisor's reclaim identity check; the external seeder's blob fetch. No model spend is needed to build or test any of them.

## Scope (the lead's reading of "all the next steps as you advise"; the PRD records it as a decision)

**In scope — nine beads, each with its Bridgebuilder finding (PR #1292 comments 6386303901 / 6386296457 / 6386296833; triage comment 6386491267) or its observed failure:**
- bd-bex39 (P2, MEDIUM 0.99, F-001): `took-effect.sh` clause (g) compares accumulated `hook_started` events per (transcript, event) against `home_hook_counts` = the number of configured hook commands, so a session that fires a recurring event (PreToolUse, UserPromptSubmit) more than once false-fails. Fix: verify each `hook_started`'s identity (hook name/command) against the pinned user settings, or count per triggering invocation; regression with two legitimate PreToolUse invocations and a negative control (a project hook that must still fail).
- bd-k3dia (P2, MEDIUM 0.98, F-002): an executed phase (in `labels_run`) without a readable `events-<label>.jsonl` carrying a `system/init` event passes clause (g). Fix: require the transcript and the init event per executed phase; reject truncated captures; fixture tests both ways.
- bd-hyx0n (P2, observed: run 40112013975, KF-063): `post-merge.yml` classifies the publisher's ledger fast-forward push (author github-actions[bot], no PR) as a cycle merge and `--generate` aborts with `--pr is required`. Fix: the classify job routes a push without an associated PR (or the bot's `chore(ledger)` subject) to a no-op outcome; a workflow-level test or a classify-script fixture covers the ledger-commit shape.
- bd-htzy2 (P3, LOW): `integrity_clean` under home-scope trusts the driver-written `meta/home-integrity.json`; add an independent hash walk of the mounted HOME against the pin (or verify the record against a hash the validator computes).
- bd-kgfh5 (P3, two LOWs): sandbox-mount home-scope rules R5 (rewrites `.claude/` string literals in any Python context; verify does not re-check R5) and R3 (rewrites every relative `.claude/` mention in skill and rules prose). Assess which rewrites the mount needs, narrow them, extend verify to R5; the home-scope bats stay green and the existing negative control stays negative.
- bd-1br0v (P3, LOW): `egress-proxy.sh:205` starts the proxy with `--pids-limit 128` while `Dockerfile.proxy:101` sets tinyproxy `MaxClients 200` (threaded tinyproxy counts threads against the pid limit). Align the two and assert the pair in `evals/tests/egress-proxy.bats`.
- bd-ruo5b (P3, LOW): `batch-supervisor.sh` reclaim signals the process group recorded under `.jobs/` without verifying it still belongs to the recorded job. Record and compare an identity (start time, cmdline hash) before signalling; test with a stale pgid.
- bd-kdk3l (P3, LOW): `seed-corpus-from-external.sh` computes the fix diff over tree entries whose blobs the bounded fetch never retrieved. Fetch the blobs the diff needs or refuse with the omitted paths named; dry-run test.
- bd-4pv1j (P3, LOW + SPECULATION): `post-merge-orchestrator.sh` `phase_tag` returns 2 after PUBLISHING state and the progress file were written, contradicting the header's exit-2 contract; decide the float policy of the stdlib canonicaliser fallback (assert no floats in `prepared_state`, or implement RFC 8785 number serialisation). Move the local-tag identity check into pre-write validation; remote-identity failure returns 1; bats for both.

**Out of scope (named so the planner does not pull them in):** bd-oik13 (chunked Bridgebuilder review — DEC-0960 chose per-sprint PRs as the remedy; the bead stays); the cycle-133 carry-overs bd-ci4g9, bd-yv0d4, bd-nzblj, bd-ivmtk, bd-yt1k1, bd-afz2p, bd-znx6q, bd-868s1, bd-vlgk1, bd-mopz7, bd-aun97 (a later cycle; several need a funded home-scope smoke); any measurement run; any change to the cycle-132 or cycle-133 records; a new release candidate (see Release).

## Standing rules (from the cycle-133 brief, unchanged unless noted)

- Autonomous through the golden path: `/plan-and-analyze` → `/architect` → `/sprint-plan` → `/run sprint-plan`; implement → review → audit per sprint; Bridgebuilder round(s) on the PR; CI green; admin merge; record branch; archive. Do not stop to ask; every judgment call is a DEC row with alternatives.
- Models: Opus 5.5 subagents (implementers in worktrees), Fable 5.1 lead and reviews; ≤ 3 dissent runs per sprint; implementers make no live model calls.
- System Zone: `.claude/` and `.github/` changes are the deliverable here; every System Zone write goes through a bounded zone marker (`.run/zone-guard-authorization.json`, scope framework, reason, expiry ≤ 2 h) with `checksums.json` and REPO-MAP regenerated (DEC-0824).
- Quality: every change ships with its test (bats or pytest) and its documentation (skill text, reference, CHANGELOG `[Unreleased]`); nothing lands red.
- **PR shape (DEC-0960, new):** one PR per sprint (`/run sprint-plan --no-consolidate` or `consolidate_pr: false` for this run); generated artefacts and evidence trees, if any, in a checksum-reviewed follow-up PR; the Bridgebuilder round on each sprint PR must reach a non-degraded verdict (coverage within `max_files_per_pr`), else the PR is split before merge.
- Security: never echo or commit the keys in the operator's `~/.local/dotfiles/zsh/.zshenv`; secret scan (detect-secrets + the repository scanners) before any public push; the refusal list of cycle-133 (no force-push, no writes to `main` outside the publish fast-forward, no tag or branch deletion, no bypass of red CI or an unresolved Bridgebuilder blocker, no credential provisioning).
- Spend: cap USD 20 for the cycle (Bridgebuilder rounds; Flatline reviews and dissent run on subscription routes at USD 0; no smoke, no measurement); the cycle meter is read before every paid call.
- Process lessons from cycle-133: `bats` runs through `npx --no-install bats` on this host; the dec-write summary limit is 160 code points; URLs belong in a DEC row's `source`; PR comments need `--paginate`; `date -u` is the clock; the record branch's scan accepts prose mentions of the audit-key pattern name by `scan_tree`.

## Release

No new release candidate: the rc.8 soak continues and these fixes ride `main` into rc.9 or 2.0.0 when the exit criteria hold. CHANGELOG `[Unreleased]` carries every fix; the PRD records "no rc this cycle" as a decision with the alternative (cut rc.9) rejected.

## Sprint breakdown (proposal for `/sprint-plan`; global ids from 276)

1. **Sprint 1 (276) — all nine beads, four implementers in parallel:** A took-effect (bd-bex39, bd-k3dia, bd-htzy2); B sandbox-mount rules (bd-kgfh5); C post-merge classify guard + orchestrator contract (bd-hyx0n, bd-4pv1j); D harness libs (bd-1br0v, bd-ruo5b, bd-kdk3l). Goal validation: the home-scope bats and the two smoke evidence trees under `grimoires/loa/reports/ablation-2.0/c133-smoke/` still validate (`took-effect.sh` on run-1 and run-2 → same verdicts), a classify fixture for the ledger-commit shape passes, every bead closes with commit and test. Ship: PR → Bridgebuilder (non-degraded) → CI → admin merge → record branch → archive.
