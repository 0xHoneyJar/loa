# Product Requirements Document: The follow-through (cycle-133)

**Version:** 1.1
**Date:** 2026-10-23
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-23, quoted verbatim in the brief: "proceed end to end with implementing all the beads / improvements"; the interview phases were answered from that instruction, the lead's executive summary it approved, the cycle-132 archive and direct reads of the code cited below; every judgment call is a decision row D-1 … D-12 in Appendix A; 1.1 integrates the Flatline PRD review — 19 skeptic blockers and 49 reviewer items, Appendix E)
**Brief:** `grimoires/loa/context/cycle-133-brief.md`
**Cycle:** `cycle-133-follow-through` (ledger, active); **branch:** `feature/cycle-133-follow-through` from `main a82ec556`
**Flatline:** `grimoires/loa/a2a/flatline/cycle-133-prd-review.json` (claude-headless + gpt-5.5; cross-scoring degraded, KF-041 recurrence 9; every concern read and dispositioned in Appendix E)
**Predecessor:** cycle-132 "the conclusive review-catch answer" (PR #1289 → `0a3cb27c`; v2.0.0-rc.7; record `b4b57cac`; archive `grimoires/loa/archive/cycle-132-conclusive-review-catch/`)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: discovering-requirements/resources/templates/prd-template.md:10-24 (section order)

---

## Executive Summary

cycle-132 measured the review pipeline and shipped an honest INCONCLUSIVE answer. Doing so exposed a list of defects in the framework that produced it: the Bridgebuilder reviewer cannot read a large pull request and its consensus writer can post its own scratch work; the release pipeline tags commits that `main` cannot reach; the harness library that meters model spend fails open; the reproduction script attests the wrong tree; a stale state file misleads every compaction; the tracker holds 310 open beads of which 50 are fossils. The measurement also pointed at three product changes: when a PR touches `.claude/`, Loa's reviewer reads its own installed files instead of the PR's (nine of fourteen fixtures touch `.claude/`; eight of twenty-eight full-arm cells were lost to it); findings are credited for landing near the right line, while a blind judge found only a quarter to a third of them describe the defect; and the ground truth leaned on Loa's own past reviews.

This cycle implements every one of those follow-ups that can be built and tested without paying for a new measurement: the 25 beads named in the brief, the two product changes (Loa reviews Loa; one finding contract with a judge-able grader hook), the tooling that seeds a corpus from outside Loa's history, and a verified sweep of the rest of the tracker. It ships as 2.0.0-rc.8, a pre-release, through a release path fixed so the tag lands where `main` can see it. [ASSUMPTION decision] The scope reading, the budget, the grounding, the System Zone authorization, the two product designs, the release, the sprint shape, the test policy and the hygiene rule are D-1 … D-10 (DEC-0827 … DEC-0836); the authorization basis and the Flatline integration are D-11 and D-12 (DEC-0838, DEC-0837).

> Sources: cycle-133-brief.md § The operator's instruction, § Objective, § Scope; cycle-132 report `grimoires/loa/reports/review-catch-c132/report.md` § Honest caveats 1, 4, 5, 7; known-failures.md KF-053 … KF-055; decisions.yaml DEC-0816 … DEC-0818

---

## Problem Statement

### The Problem

The framework that measured itself in cycle-132 carries recorded defects in four places, and the measurement's own apparatus carries three more:

1. **Reviewer tooling.** Bridgebuilder's GitHub adapter runs `gh api …/pulls/N/files --paginate` under a fixed 10 MiB child-process buffer (`.claude/skills/bridgebuilder-review/resources/adapters/github-cli.ts:160-165`, `:257-277`); every exclusion and truncation knob acts after that fetch (`resources/core/truncation.ts:143-162`), so a PR whose files payload exceeds the buffer cannot be reviewed at all (PR #1289: 2,186 files, about 22 MB of patches; KF-054). Its consensus enrichment writer is a headless model call with no tool restriction and no output guard (`resources/core/multi-model-pipeline.ts:882-940`); on PR #1289 round 2 it posted a tool-call transcript as the review (comment 6369941557; KF-055). The summary verdict is derived from prose lines and never from the consensus block's own `verdict` field (`resources/core/review-verdict.ts:12-57`), so both rounds read `UNKNOWN` and `mergeBlocked: true` while the voices' band was APPROVED.
2. **Release path.** The post-merge orchestrator builds a "chore(ledger): archive … after merge" commit inside the candidate bundle (`post-merge-orchestrator.sh:1385`) and `--publish` tags that commit (`:1507-1520`) without moving `main`; v2.0.0-rc.6 (`4628f763`) and v2.0.0-rc.7 (`ae84cc41`) are tags no branch reaches.
3. **Framework ergonomics.** `notes-guard.sh rotate` keeps the Session Continuity and the three newest Decision Log blocks and drops the other template sections (`notes-guard.sh:13, 151-152`), so `check-loa.sh` warns template drift after every rotation; `pre-compact-marker.sh:37-39` declares simstim active when the state file merely exists (a COMPLETED file from 2026-05-23 did this for a whole cycle); `dec-write-lib.sh:471` refuses a long summary without saying how long it is; `security-audit-scope.sh:18-26` has no help and rejects file arguments although the auditing skill tells agents to pass them. Every cycle since 125 hand-wrote a record-branch script in a cache directory because the gate artefacts live in gitignored `a2a/` and NOTES, and nothing in `.claude/scripts/` builds the record.
4. **Tests.** The analysis suite (182 tests) runs locally but not in CI (`.github/workflows/bats-tests.yml:182-191`); ten `tests/unit` cases fail on `main` (bd-tgn04); frozen fixture snapshots under `evals/fixtures/review-prs/pr-NN/{base,head}/` trip repo-wide gates and inflate every diff.
5. **Harness.** The shared session library's pricing helpers end in `|| echo "0 0 0"` and `|| echo null` (`evals/harness/lib/session-exec.sh:38, 49, 68`), so a jq failure reads as free and the cap watchdog never trips (`blind-session.sh:303-332` estimates only when prices are non-null); the exec shim closes descriptors 3…65535 only (`session-exec.sh:24`); `SECRET_KEYS` is a second allowlist (`:29`); `pipeline-run.sh:870-891` carries a verbatim copy guarded by a drift test. Nine bare sessions reached the upstream repository in cycle-132 and a detector, not the sandbox, caught them (bd-ijxuk). Batch drivers die with the host and are resumed by hand (KF-052, recurrence 3). Fable sessions refuse security-tooling PRs and fall back to Opus (KF-051, recurrence 4) with no registered arm policy. Grader 1.3.8 reads two benign shapes as contamination (bd-kddde).
6. **Reproduction and analysis.** `reproduce.sh:46-47` attests HEAD against the pin rather than the working tree that executes and omits `evals/analysis/c132`; `:66-73` runs the paid live sample regardless of the engine's exit code or a failed environment check and hard-codes `REGISTRATION-16.json`; `record_lite.py:86-97` memoises digests by an lstat tuple; `:499-501` recreates a manifest symlink target unvalidated; `judge_defects.py:477-487` binds labels to a sample by item id only; `final.sh:10` sources an unversioned cache file as shell code; the power-mini fixtures carry hunk headers that contradict their bodies.
7. **The product itself.** Under the pinned overlay (PREREGISTRATION addendum 9 lines 11 and 16; `sandbox-mount.sh:15-18, 88`; `pipeline-run.sh:131-139, 271-272, 379-387`) every path under `.claude/` stays the pinned framework copy while the PR's `.claude/` changes sit under `pr/head/`, so the review and audit skills read their own installed files near the anchors. The reviewing and auditing skills ask for a concrete failure scenario in prose (`reviewing-code/SKILL.md:113, 128`; `auditing-security/SKILL.md:199`) but the dissent schema carries `failure_mode` (`adversarial-review.sh:459, 504`), the Bridgebuilder schema carries `description`, and the grader credits line proximity (`ablation-grade.sh:154, 286`, rule `pm3_or_same_function`). The corpus seeder builds fixtures only from Loa's own record branches (`seed-corpus-from-record.sh` header), and 83 % of the fix commits behind the v2 key were prompted by Loa's own reviews (report § Honest caveats 4).

### User Pain Points

- A maintainer cannot get a Bridgebuilder review of a large PR, and when a review arrives its verdict field cannot be trusted.
- A release candidate's tag is invisible to anyone reading `main`.
- Every cycle re-invents the record branch and repairs NOTES by hand; every compaction is told a dead workflow is alive.
- A cost cap that silently reads zero is not a cap.
- A review of a PR that changes `.claude/` can be graded on files the PR never changed.
- "Finding near the right line" and "finding that explains the bug" are indistinguishable to the grader.
- A tracker with 310 open rows, 50 of them fossils, cannot be the cross-session recovery source the framework claims.

### Current State

Each defect is recorded (beads bd-ra4im, bd-cpvc6, bd-kwloh, bd-mgun5, bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5, bd-yroj0, bd-tgn04, bd-dt5r8, bd-wqaj4, bd-g2c5i, bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm, bd-um8ol, bd-kddde, bd-r9abp, bd-yvjew, bd-ijxuk, bd-y1smc; KF-053 … KF-055; DEC-0816 … DEC-0818) and worked around by hand: a patched cache copy of Bridgebuilder, a cache record-branch script, hand-edited NOTES, a moved state file, blind re-typing of decision summaries.

### Desired State

Every recorded defect is fixed in the framework with a test that fails when it returns and a line of documentation; the reviewer reads the PR's `.claude/` while staying pinned; findings carry a failure scenario in one schema that a judge can grade; a corpus can be seeded from outside Loa; the tracker reflects reality; 2.0.0-rc.8 is published on a commit `main` reaches.

> Sources: the file:line reads named above (taken 2026-10-23 in this session); grimoires/loa/a2a/sprint-271/auditor-sprint-feedback.md § Findings; PR #1289 comments 6369786246 and 6369978273 (Bridgebuilder triage); known-failures.md KF-051 … KF-055; `br show` of the beads named

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Every Tier 1 bead closed with evidence | 25 beads closed, each close reason naming the commit and the test | `br show` per bead; sprint reports |
| G-2 | Bridgebuilder reviews a large PR end to end and reports a trustworthy verdict | a 2,000-file fixture PR reviewed in tests; this cycle's own PR reviewed by the stock skill with no cache copy; summary `verdict` equals the consensus block's | vitest fixtures; the Bridgebuilder round on the cycle PR |
| G-3 | The release tag is reachable from `main` | `git branch --contains v2.0.0-rc.8` lists `main` | after the publish |
| G-4 | Loa reviews Loa | the addendum-9 oracle detector reports no exposure on one `.claude/`-touching fixture smoke at the new pin | the smoke's grade.json (`oracle_exposed_defects` 0) |
| G-5 | One finding contract at four gates | review, audit, Bridgebuilder and dissent outputs validate against the same finding schema; a finding without a failure scenario is refused at each gate | bats and vitest per gate; `verdict-derive.sh` on a fixture file |
| G-6 | Green suites | `tests/unit` green on the shipped head; CI runs the analysis pytest (182+) and it is green | CI check-runs on the cycle PR |
| G-7 | A truthful tracker | every open bead either closed with evidence or labelled `backlog-2026-10` with a status line; counts reported | sprint report table; `br list` |
| G-8 | A shippable harness for the next measurement | fail-closed pricing, descriptor close to the limit, egress blocked at the container, restartable batches, grader 1.4, refusal policy registered, the seeder dry-run on three external candidates | bats; the seeder's dry-run output |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Bridgebuilder on a 2,186-file PR | Fatal at 15 s (KF-054) | review posted, verdict from the consensus block | Sprint 1 | G-2 |
| Release tags reachable from `main` | 0 of the last 2 (rc.6, rc.7) | rc.8 reachable | Sprint 1 + ship | G-3 |
| Oracle-exposed cells on a `.claude/`-touching fixture | 8 of 28 full-arm cells in cycle-132 | 0 on the smoke | Sprint 3 | G-4 |
| Gates validating a failure scenario per finding | 0 of 4 (prose only) | 4 of 4 | Sprint 3 | G-5 |
| `tests/unit` failures on `main` | 10 | 0 (fixed or dated quarantine) | Sprint 1 | G-6 |
| Analysis pytest in CI | not run | run, green | Sprint 1 | G-6 |
| Open beads without a current status | 310 | 0 | Sprint 4 | G-7 |
| Model spend this cycle (excl. subagents) | — | ≤ USD 100 | whole cycle | all |

### Constraints

- No paid measurement run; USD 100 cap for dissent, Bridgebuilder and one smoke; Opus subagent time outside the cap (D-2, DEC-0828). Allocation: the FR-10 smoke USD 30 (one `a1_full` trial cost about USD 17 in cycle-132: USD 276.92 over 16 pairs; the live rerun of three cells cost USD 51.33), Bridgebuilder rounds USD 20, dissent runs USD 50 (≤ 3 per sprint × 4 sprints; the headless voices have cost 0 cents so far). Rule: the cycle meter (`spend.sh` over the cost ledgers) is read before every paid step; a consumer that reaches its share stops and the lead records a DEC before any further spend of that kind; the smoke is launched once, never retried on spend.
- The cycle-132 pin `fbd36a0c`, its record branch and its registered reads are never rewritten; harness changes land as the next pipeline version (D-2).
- System Zone writes only under a bounded zone marker with checksums and REPO-MAP regenerated in the same commit (D-4, DEC-0830).
- Opus 5.5 subagents, Fable 5.1 lead and reviews; ≤ 3 dissent runs per sprint; every judgment call a DEC row.
- Majors ship as release candidates: 2.0.0-rc.8 (D-7, DEC-0833).

> Sources: cycle-133-brief.md § Standing rules, § Release; decisions.yaml DEC-0827 … DEC-0836; cycle-132 report § Honest caveats 1; KF-054; `git tag --contains` on rc.6/rc.7 (2026-10-23)

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

**Demographics:** role: maintainer and default reviewer of 0xHoneyJar/loa (`@deep-name`); technical proficiency: expert; goals: a framework whose gates, release path and tracker can be trusted without reading the code each time.

**Behaviors:** approves scope in a sentence and expects the cycle to run itself; reads the ELI5 summary and the DEC rows; merges and publishes by admin authority.

**Pain Points:** the cache-copy workarounds of cycle-132; tags no branch reaches; a tracker that lies.

### Secondary Persona: The lead agent (Fable) and its Opus subagents

**Demographics:** role: unattended executors of the golden path; goals: gates that refuse clearly, tooling that does not need hand repair, a record branch built by one command.

### Tertiary Persona: A downstream Loa consumer

**Demographics:** role: a team that installed Loa and reviews PRs with it, including PRs that change their own `.claude/`; runs Bridgebuilder on large PRs; publishes rc tags; goals: a review that looks at the PR, a verdict that means something, a tag their tooling can find.

### Quaternary Persona: The lead of the next measurement cycle

**Demographics:** goals: a harness whose cap cannot read zero, whose batches survive a reboot, whose sandboxes cannot reach the upstream repository, a grader that can take a judge verdict, a seeder for fixtures Loa never saw.

### Use Cases

#### UC-1: Review a large PR with Bridgebuilder
**Actor:** maintainer. **Preconditions:** a PR with more than 10 MiB of patches in the files API. **Flow:** 1. `/bridgebuilder --pr N`. 2. The adapter lists files without patches, applies exclusions and the file cap, fetches patches for the selected files. 3. Two voices review; the writer enriches with tools disabled; the output guard accepts or falls back. 4. The posted consensus carries `verdict`; the summary JSON repeats it. **Postconditions:** a review on the PR; exit 0, or 3 when degraded, never a Fatal on size. **Acceptance Criteria:** [ ] a 2,000-file fixture reviews in tests; [ ] the cycle PR reviews with the stock skill.

#### UC-2: Publish a release candidate
**Actor:** maintainer. **Flow:** merge → post-merge run prepares the candidate → `--publish --approve-sha256` → tag and pre-release. **Postconditions:** `main` contains the tagged commit. **Acceptance Criteria:** [ ] `git branch --contains <tag>` lists `main`; [ ] a non-fast-forward `main` refuses with the regenerate instruction.

#### UC-3: Close a cycle
**Actor:** lead agent. **Flow:** `record-branch.sh --cycle N --head <merge> --prev <record> --stage "stage 2"` → secret scan → commit → ICE push; `notes-guard.sh rotate` keeps every template section; the compaction hook reports only live workflows. **Acceptance Criteria:** [ ] the record branch holds the a2a, NOTES and results paths with no sandbox; [ ] `check-loa.sh` passes after a rotation; [ ] a COMPLETED simstim file is reported inactive.

#### UC-4: Review a PR that changes `.claude/`
**Actor:** downstream consumer / the harness. **Flow:** the pipeline runs pinned; the reviewer reads the PR's `.claude/` files; the oracle detector sees no self-read. **Acceptance Criteria:** [ ] the smoke's grade shows `oracle_exposed_defects` 0 on a `.claude/`-touching fixture.

#### UC-5: A finding that explains the bug
**Actor:** any gate. **Flow:** a finding is written with `file:line`, failure scenario, severity, confidence; the gate validator refuses one without a scenario; the grader can take a judge verdict per finding. **Acceptance Criteria:** [ ] the four validators share one schema; [ ] `ablation-grade.sh` accepts a judge-verdict file and reports judged recall beside `pm3`.

#### UC-6: Seed a fixture from outside Loa
**Actor:** next measurement lead. **Flow:** `seed-corpus-from-external.sh <repo> <pr> --fix <sha> [--incident <ref>]` → fixture dir in the v2 shape with provenance, licence, cutoff dates → `--dry-run` on three public candidates. **Acceptance Criteria:** [ ] three dry-runs succeed with no model spend; [ ] SHA256SUMS and manifest shape validate.

#### UC-7: Trust the tracker
**Actor:** maintainer. **Flow:** the sweep verifies each open bead against the code, closes with evidence, labels the live ones. **Acceptance Criteria:** [ ] counts reported; [ ] no open bead without a status line.

> Sources: cycle-133-brief.md § Scope; KF-054/KF-055 reading guides; cycle-132 NOTES 2026-10-23 entries (record branch, NOTES rotation, simstim file); `seed-corpus-from-record.sh` header; `br list --status open --limit 1000` (310 rows, 2026-10-23)

---

## Functional Requirements

### FR-1: Bridgebuilder reads large pull requests (bd-ra4im)
**Priority:** Must Have
**Description:** `getPRFiles` fetches the file list without patch bodies (per page, `--jq 'map(del(.patch))'` or equivalent), applies `exclude_patterns`, `max_files_per_pr` and the Loa-tier filter to that list, then fetches patches only for the selected files (per-file contents/diff) up to `max_diff_bytes`; the child-process buffer becomes configurable (`gh_max_buffer_bytes`, default raised) and a buffer overflow or an oversize payload yields a degraded review (exit 3) with a posted banner, never a Fatal.
**Acceptance Criteria:**
- [ ] Mechanism named: the `pulls/N/files` endpoint always carries `patch` and has no per-file mode, so the fetch pages it (`per_page=100`, page by page, never `--paginate`), applies the Loa-tier filter, `exclude_patterns` and `max_files_per_pr` to each page's metadata, and retains patch text only for selected files up to `max_diff_bytes`; `max_diff_bytes` bounds retained and submitted bytes, received bytes are bounded per page. A test with one selected file whose patch alone exceeds the limit passes with that file recorded as truncated.
- [ ] Immutable pair: the PR's `base.sha` and `head.sha` are read first, every page and content fetch is checked against them, and a head that moves mid-fetch restarts the fetch once, then degrades (`degraded_reason: pr_head_moved`); both SHAs are recorded in the review metadata and the posted marker.
- [ ] A vitest fixture of 2,000 files (patch payload > 10 MiB) reviews end to end with a mocked `gh`; a fixture of 3,001 files exercises the endpoint's 3,000-file cap (the `compare` endpoint or `degraded_reason: files_list_truncated`, as the SDD decides).
- [ ] Coverage record: the posted review and the summary JSON list reviewed files, omitted files and the reason per omission (excluded, over the file cap, over the byte budget, binary or no patch, GitHub-truncated patch, renamed); omission of any reviewable (non-excluded) code file marks the review degraded, and the SDD states which omission categories block merging.
- [ ] An oversize payload or a rate-limited fetch produces exit 3 and a summary JSON with `degraded: true` and a `degraded_reason` from a fixed enumeration (`files_payload_oversize`, `files_list_truncated`, `patch_fetch_rate_limited`, `pr_head_moved`, …), never a thrown error; the enumeration is asserted in the degraded-path tests.
- [ ] Default `exclude_patterns` gain `evals/fixtures/review-prs/**` and `grimoires/loa/reports/ablation-2.0/*-grades/**`, with a vitest asserting they are excluded before any patch is retained.
- [ ] `gh_max_buffer_bytes` is configurable and documented; `dist/` rebuilt and tracked; `check-bb-dist-fresh` green; SKILL.md documents the knobs and the coverage record.
**Dependencies:** the Bridgebuilder TypeScript build (`npm ci`, `npm run build`); cross-runtime parity with `.claude/adapters` is not affected.

### FR-2: Bridgebuilder consensus integrity (bd-cpvc6)
**Priority:** Must Have
**Description:** The enrichment writer runs with tools disabled at the adapter level (the claude-headless adapter already passes `--tools ""`, `claude_headless_adapter.py:136-151`; each headless adapter used for the writer role must expose an enforced no-tool mode or be refused for that role); its output must validate against the finding schema, contain exactly one `bridge-findings` block, carry the consensus findings unchanged (ids, anchors, severities, verdict; only the permitted explanatory fields may be added) and contain no tool-call grammar of any provider, otherwise the un-enriched consensus is posted and the run exits 3 with `degraded_reason: enrichment_guard_rejected`. Verdict precedence: REQUEST_CHANGES when any finding is CRITICAL, BLOCKER or HIGH or any voice marked a finding blocking; else the consensus block's `verdict`; else (no block) the prose rule; contradictory sources (two blocks, a block verdict against a blocking finding, malformed block) fail closed as `degraded_reason: verdict_conflict` with `mergeBlocked: true`; `mergeBlocked` always carries a reason.
**Acceptance Criteria:**
- [ ] Per headless adapter (claude-headless, codex-headless, the Bedrock route through cheval) a test asserts the writer invocation carries that adapter's tool-disable flag; an adapter without one is refused for the writer role in tests.
- [ ] The output guard rejects Anthropic tool-use grammar (`<invoke`, `tool_use` JSON), OpenAI function-call grammar, a missing or duplicated findings block, and a block whose findings differ from the consensus in id, anchor, severity or verdict; each rejection posts the un-enriched consensus and exits 3.
- [ ] A single valid block with `"verdict": "COMMENT"` and no HIGH-or-above finding yields summary `verdict: COMMENT`, `mergeBlocked: false`; a block saying COMMENT beside a HIGH finding yields REQUEST_CHANGES; two blocks yield `verdict_conflict`.
- [ ] Round-1 and round-2 bodies of PR #1289 (record branch `a2a/sprint-271/bridgebuilder/`) replay as fixtures: round 1 (one valid block, verdict COMMENT, highest MEDIUM) → COMMENT, `mergeBlocked: false`; round 2 (tool-call transcript) → the guard rejects, fallback posted, exit 3.
**Dependencies:** FR-1 build.

### FR-3: The release tag reaches `main` (bd-kwloh)
**Priority:** Must Have
**Description:** `--publish` either (a) fast-forwards the remote `main` to the candidate's `target_commit` with a conditional ref update (expected old value = the candidate's `merge_sha`) before tagging, refusing with a regenerate instruction when the remote `main` has moved, or (b) tags the merge commit itself and leaves the ledger-archive change to `archive-cycle.sh`; the SDD decides against the criterion "the tag is reachable from `main` and no commit that never passed CI lands on `main` without being named in the candidate", and the candidate records the choice (`target_on_main`). Permission model: the operator's token pushes (branch protection has `enforce_admins: false`); a generated ledger commit on `main` is the one documented exception to "CI before main" and the candidate names it. Publication is a resumable sequence (remote-main update → tag → release → notify), each step verified-or-performed so a re-run after a partial failure completes without duplicating; the approved manifest covers every publication input (target commit and tree, tag, release title and notes digest, intended ref updates, remote URLs) and any mutation after approval refuses.
**Acceptance Criteria:**
- [ ] `tests/unit/post-merge-publication.bats` covers, design-neutrally: publish against a remote whose `main` equals `merge_sha` → tag reachable from `main`; remote `main` moved → refusal, no tag, no ref update; an existing tag on another commit → refusal; a crash between the ref update and the tag push → the re-run completes idempotently; a mutated candidate after approval → refusal.
- [ ] The approved manifest digest covers the notes and intended ref updates; a test mutates each and sees the refusal.
- [ ] The rc.8 publish of this cycle leaves `git branch --contains v2.0.0-rc.8` listing `main`. Backout: a mis-tagged rc.8 is never deleted by the run (refusal list, D-11); the fix publishes rc.9 and the notes name the mis-tag.
**Dependencies:** none; the KF-034 setup gotcha in that bats file is handled.

### FR-4: Framework ergonomics (bd-mgun5, bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5)
**Priority:** Must Have
**Description:** (a) `.claude/scripts/record-branch.sh`: inputs from an explicit cycle manifest (the a2a directories, results roots and extra paths to record), a temporary index, `read-tree <head>`, `add -f` of the gitignored record paths (NOTES, `archive/notes`, the cycle's `a2a/sprint-*`, `a2a/audits/<date>`, `flatline`, `prompts`, results roots minus `sandbox/`, `snapshots/`, `grading/pr/`, a record_lite tree when present); symlinks and any path resolving outside the repository are rejected before staging; the secret scan runs over the blobs of the exact staged tree (`git ls-tree -r <tree>`), credential-shaped hits (key, token, private-key shapes) are never bypassable, and `--accept-scan` acknowledges only the remaining hit classes for one named tree hash and records them in the commit message; `commit-tree -p <prev> -p <head>`, `update-ref`, `--dry-run` size table; never touches the working tree or the real index. (b) `notes-guard.sh rotate` writes every section the template requires, carries every open Blocker and every Active Sub-Goal forward in full, keeps the newest Session Continuity block whole, and truncates only the Decision Log (newest three blocks) and the Session Log. (c) `pre-compact-marker.sh` reports simstim or run mode active only when the state file's `state` is in that workflow's allowlist of live states (run mode: RUNNING, HALTED; simstim: its non-terminal states) and `last_activity` is within a configurable window. (d) `dec-write new` refuses a long summary naming the measured and the maximum length (160) and the first 160 code points. (e) `security-audit-scope.sh --help` and `--files <list>` / `--paths …`; the auditing-security skill text names the real interface. (f) `ledger-lib.sh validate_ledger` validates `schema_version` and accepts `version` as a legacy alias (bd-4pjqm).
**Acceptance Criteria:**
- [ ] bats per script: record-branch on a fixture repo (manifest paths present, sandbox absent, a symlink and an escaping path refused, a planted credential-shaped hit stops the build even with `--accept-scan`, a non-credential hit accepted only for the named tree hash, dry-run exits 0 without a ref); rotate with two open blockers and two sub-goals → both survive whole and `check-loa.sh` passes; a COMPLETED simstim file → inactive and a RUNNING run state → active; a 170-code-point summary → message naming 170 and 160; scope `--files` restricts the walk; the live ledger shape validates.
- [ ] The archive-cycle/ship skill documents `record-branch.sh`; the cache scripts of cycle-132 are retired in NOTES.
**Dependencies:** D-4 System Zone authorization.

### FR-5: CI and test health (bd-yroj0, bd-tgn04, bd-dt5r8)
**Priority:** Must Have
**Description:** The pytest step of `bats-tests.yml` runs `evals/analysis/*/tests` (a glob, so the next cycle's suite is picked up without a workflow change); the ten pre-existing `tests/unit` failures (cheval-alias-regression A1–A6, cost-report CR-7 `--reprice`, cycle-114 registry c114-FR1-2/-3, cycle-124 catalogue c124-1.3-5) are repaired or quarantined; a quarantine names an owner, an expiry (the next cycle's close), the tracked bead and the reason, and CI fails when a quarantine is past its expiry; CI reports executed, skipped and quarantined counts separately; `.gitattributes` marks `evals/fixtures/review-prs/**` and the sensitivity-grade trees `linguist-generated -diff` (the `check-knob-readers.sh` walk is already scoped to `.claude` and `tools`; `check-no-swallowed-jq.sh` walks the whole root and needs the exclusion) with a bats tripwire that every repo-wide lint walk excludes those paths.
**Acceptance Criteria:**
- [ ] CI check-runs on the cycle PR include the analysis pytest and it is green.
- [ ] `tests/unit` green on the shipped head (quarantines listed in the sprint report with dates).
- [ ] The tripwire test fails when a lint tool's walk includes a frozen fixture path; `gitattributes-workflow-protection` (the `.github/workflows merge=ours` rule) still passes.
- [ ] An expired quarantine fails CI in a test fixture. [ASSUMPTION decision] Quarantine with a dated reason is allowed only when a repair would change shipped behaviour the cycle does not otherwise touch (D-9, DEC-0835).
**Dependencies:** none.

### FR-6: Session library hardening (bd-wqaj4, bd-g2c5i)
**Priority:** Must Have
**Description:** `price_for` and `price_events` return a distinct sentinel on any jq, python or parse failure, when the model id has no pricing entry, when any price field is missing, null, negative or non-finite, when a usage event carries an invalid token count, or when a completed turn has no usage event (metering incomplete); the watchdog refuses to start (or stops the session) on the sentinel; a legitimate zero price is distinguished from an unknown value; a malformed `LOA_EVAL_PRICING_JSON` aborts; pricing semantics and model coverage are validated before launch. `ENV_SHIM` closes every actually open inherited descriptor above 2 (enumerating `/proc/self/fd`, falling back to `closerange` up to the hard `RLIMIT_NOFILE`), including descriptors above a lowered soft limit; secrecy derives from the key name (`*_KEY`, `*TOKEN*`, `*SECRET*`) or a startup assertion that every such `PASS_KEYS` entry is in `SECRET_KEYS`; `pipeline-run.sh` sources `lib/session-exec.sh` and its bats harness stages the lib; the drift test is removed after one green batch smoke on the new pipeline version. Rollback: `git revert` of the lib commit restores the inline copy; in-progress batches finish on their pin.
**Acceptance Criteria:**
- [ ] bats: a malformed prices JSON, a well-formed prices JSON lacking the session's model id, a negative or non-finite price, and a transcript with a usage-less completed turn each → sentinel → session refused or stopped, no further model call; a zero price is accepted as zero; an inheritable descriptor above 65535 (and one above a lowered soft limit) is closed in the child; a key-shaped `PASS_KEYS` entry absent from `SECRET_KEYS` fails the startup assertion.
- [ ] `blind-session.bats` and `pipeline-run` bats green with one copy of the mechanics.
- [ ] `check-no-swallowed-jq.sh` scans `evals/harness/lib/`.
**Dependencies:** the pin discipline (D-2): these ship as the next pipeline version.

### FR-7: Reproduction and analysis hardening (bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm, bd-um8ol)
**Priority:** Must Have
**Description:** `reproduce.sh` compares the working tree with the pin (`git diff --quiet <pin> -- <paths>`), requires a clean porcelain for those paths unless `--no-env-check`, records `git describe --dirty`, includes `evals/analysis/c132` or renames the field; `--no-env-check` records `env_check: skipped` and can never set `image_matches` or `pin_same` true when they are false. Exit-code table: 0 every artefact reproduced (and the live sample, when run, completed — a grade outside the recorded range is a named discrepancy in the report, not a failure); 1 a reproduction difference, named; 2 environment mismatch or usage; 3 live sample requested but not run (engine failure, environment mismatch, runner refusal). `--live-sample` refuses (exit 3) unless the engine exited 0 and the environment matched, reads the registration hash from `$REG`, filters the recorded range to valid rows and marks the live table with the environment verdicts. `record_lite.py` hashes on verification paths without the cache (or keys it on realpath plus a following stat with ctime), validates symlink targets with `safe_rel`, documents `INDEX.json`/`INDEX-only.json`. `judge_defects.py` refuses an existing `key.json`, writes a sample id into every packet and `labels.json`, and `aggregate` rejects a mismatch and loads the grades for its validity filter; `run-judge-defects.sh` keys the chunk directory by the key sha. `final.sh` and `run-judge-defects.sh` parse `registration.txt` with a whitelist (or take arguments) and derive the root from `BASH_SOURCE`. Power-mini fixtures are generated at test time by `synth.py` with correct hunk headers. Power-mini generation is deterministic (a fixed seed recorded in the test). The remaining Sprint 270 advisory of bd-um8ol is applied (`spend.sh` dedups anonymous rows by run id and batch, not run id alone; C-001 … C-005 were fixed by addendum 15).
**Acceptance Criteria:**
- [ ] pytest/bats per item (a dirty worktree is refused; a non-zero engine exit refuses the live sample; a same-size same-mtime rewrite is detected; an absolute symlink target is refused; stale labels against a new key are rejected; the drivers run from any cwd without the cache file; `git apply --check` accepts the generated diffs).
- [ ] The cycle-132 record's REPRODUCE.md and tracked reads are unchanged; the new scripts carry a version note.
**Dependencies:** none.

### FR-8: Grader 1.4 and the refusal policy (bd-kddde, bd-r9abp)
**Priority:** Should Have
**Description:** Grader 1.4 (Sprint 2) re-classifies the two cycle-132 shapes (a class-7 report written via heredoc quoting a PR-native token; a container-mode bare `/home` probe) with per-class tests and a changelog entry in the grader header; the judge hook of FR-11 is grader 1.5 (Sprint 3). The refusal fallback (KF-051) becomes a suite-level policy (`exclude`, `keep`, `rerun-once`) selected and recorded before execution (MANIFEST and the registration can cite it), with every row recording the original and fallback model ids, attempt counts and costs, and each policy's denominator treatment defined; the SDD sets the default.
**Acceptance Criteria:**
- [ ] The two shapes re-grade as benign in fixture tests; every other 1.3.8 fixture grades identically.
- [ ] A row with a refusal fallback carries the field; the policy knob is read from the suite file and tested.
**Dependencies:** FR-6 (pipeline version).

### FR-9: Batch operations (bd-yvjew, bd-ijxuk)
**Priority:** Should Have
**Description:** A supervisor restarts a dead `run-ablation.sh` batch with `--resume`: a single active owner (lock file plus pid), ownership of child containers (orphans with the batch's name prefix are terminated or reconciled before a resume), retry state persisted across reboot in STATUS.json, bounded retries with retry identifiers, and resumption from the runner's atomic per-session completion records (a session counts complete only when its row and grade are written atomically). Network policy is declared per arm in the suite file and recorded in MANIFEST; the default for every arm, the open-mount control included, is `egress: blocked` — a network namespace whose only egress is an allowlisted proxy for the model endpoints the registry names (destination and redirect enforcement, direct IP and IPv6 denial, DNS only through the proxy, CONNECT only to allowlisted hosts, no host mounts beyond the workspace and HOME) — and `bridge` is allowed only when a batch records it as an experimental factor; isolation must pass its self-check before any live run; the class-9 detector stays as a tripwire; every denied connect is logged into meta. The ablation image tag bumps (`loa-ablation:259`) and is pinned in the new pipeline version.
**Acceptance Criteria:**
- [ ] bats: a killed driver is resumed once by the supervisor and STATUS.json records it with a retry id; a second supervisor refuses the lock; an orphaned container is reconciled before the resume; a crash during a session's result write leaves no duplicate row; a second kill within the retry cap is reported, not retried forever.
- [ ] bats (container, in a Docker-enabled CI job or locally with a dated skip and a bead): the allowlisted endpoint succeeds; `git ls-remote` to github.com, raw.githubusercontent.com and gitlab.com fail; a direct IP, an IPv6 address, an HTTP redirect to a non-allowlisted host and a CONNECT to a non-allowlisted host fail; DNS to an external resolver fails; the harness records `egress: blocked` and the denied connects in meta.
**Dependencies:** Docker on the host; the image `loa-ablation:258` or its successor.

### FR-10: Loa reviews Loa
**Priority:** Must Have
**Description:** A review or audit of a PR that modifies `.claude/` reads the PR's version of every `.claude/` file while the pipeline's own skills, hooks and scripts stay the pinned version — including when the PR changes an executing skill, hook or script, which requires separate, explicit roots for trusted execution and reviewed source. Hard security constraint: PR-supplied `.claude/` content is data only; no hook, settings file, command, skill or script that originates from the PR's `.claude/` may be loaded or executed by the reviewing session under any design. Scope: the change is to the harness mount (`sandbox-mount.sh`, `pipeline-run.sh`) and, if the SDD picks a read contract, to the skill text; a downstream consumer's real review already runs on the checked-out PR (their `.claude/` is the PR's), so no downstream-facing behaviour changes unless the skill text does, in which case the skill's own bats cover it. [ASSUMPTION decision] The SDD chooses among (a) a framework root separate from the workspace that the skills resolve, (b) an overlay that pins only the executing skill directories, scripts and hooks and leaves every other `.claude/` path to the PR, or (c) a reviewer file-read contract enforced by the harness and the skill text; the criterion is the narrowest design that satisfies every acceptance criterion below, and the decision is an operator-visible DEC row (D-5, DEC-0831).
**Acceptance Criteria:**
- [ ] Positive evidence, not silence alone: the detector gains a clause that recognises a reviewer read returning the PR's bytes for a changed `.claude/` path (by content hash), and the smoke's grade shows at least one such read and `oracle_exposed_defects` 0; the negative control runs in the same test: the detector still fires on the old pin (or a deliberately broken mount).
- [ ] One smoke at the new pin (the recorded Sprint 3 head commit, written into the smoke's meta) on a `.claude/`-touching fixture (pr-20 or pr-16), one `a1_full` trial: the took-effect rules pass; spend within the USD 30 share; launched once.
- [ ] Design-neutral bats: for every changed `.claude/` path — including a changed executing SKILL.md, a hook, a script, a deleted file, a renamed file and a symlink in the PR — a reviewer read by the design's mechanism returns the PR's bytes, while the executing framework files are the pinned bytes; a planted PR hook, settings file and skill are never loaded or executed by the session (asserted on the transcript and the process list).
- [ ] The design is documented in the harness README and, if a read contract, in the skill text where it lives.
**Dependencies:** FR-6 (pipeline version); the SDD decision.

### FR-11: One finding contract and a judge-able grader hook
**Priority:** Must Have
**Description:** Review feedback, audit feedback, Bridgebuilder findings and dissent findings share one versioned canonical schema (`finding.schema.json` v1): a stable finding id, an anchor `file:line[-end]` (repository-relative, no `..`), `failure_scenario`, `severity` (CRITICAL, HIGH, MEDIUM, LOW, plus the non-tallied PRAISE, SPECULATION, REFRAME, INFO), `confidence` (high, medium, low, or a 0–1 float mapped to them). Content rule for `failure_scenario`: it names a trigger and an observable consequence, or is at least twelve words, and matches none of a placeholder denylist (`TODO`, `n/a`, `see above`, …). Aliases `failure_mode` and `description` are normalised to `failure_scenario` with a warning naming the field and the removal release (2.1.0); both present and different is rejected. `verdict-derive.sh` refuses a tallied finding without a valid scenario; `adversarial-finding.schema.json` and the Bridgebuilder `FindingsBlockSchema` reference the canonical schema; the skill templates emit it. Grader 1.5 accepts `--judge-verdicts <file>` (schema: finding id, finding content hash, defect key, fixture hash, grader version, verdict enum describes / does-not-describe, judge model, blind flag, timestamp); verdicts are bound one-to-one to credited (finding, defect) pairs with a documented tie rule, stale or foreign verdicts (hash or version mismatch) are rejected, judged recall is reported over the judged pairs with the unjudged count beside `pm3_or_same_function`, and the provenance lands in grade.json. `judge_defects.py` becomes a registered analysis path (`reads-c132.py --judge-defects`) once bd-xr3uq binds its samples; new registered reads append to a new chain version. [ASSUMPTION decision] (D-6, DEC-0832).
**Acceptance Criteria:**
- [ ] Fixture findings without a scenario, with a one-word or boilerplate scenario, with conflicting aliases, or with an anchor outside the repository are refused by each of the four validators (bats/vitest); an aliased field normalises with the named warning.
- [ ] A judge-verdict file changes the grader's judged recall and the unjudged count and nothing else; a verdict with a stale hash or grader version is rejected; duplicates resolve by the documented rule; the grader version is 1.5.
- [ ] The unchanged cycle-132 registration chain and reads still verify (test); the new read appends to a new chain version.
- [ ] The reviewing-code and auditing-security SKILL.md finding templates carry the field; the Bridgebuilder persona asks for it.
**Dependencies:** FR-1/FR-2 build; FR-7 (bd-xr3uq).

### FR-12: External corpus seeding and measurement-cycle guidance (bd-y1smc)
**Priority:** Should Have
**Description:** `evals/harness/seed-corpus-from-external.sh <repo-url> <pr> --fix <sha> [--incident <ref>] [--licence <spdx>]` builds a fixture in the v2 shape (fixture.yaml, head.diff, PR.md, base/, head/, provenance with the source URL, licence, PR and fix dates against the model-cutoff table, an exposure block). Construction: the reviewed tree is the PR head (pre-fix); the fix is one commit or a squashed range after the head; PR.md is built from the PR title and body only, never from the fix commit, issues or incident text that reveal the fix (a leakage check compares PR.md against the fix diff); source URLs and incident references are sanitised. Materialisation is non-executing and isolated: no hooks, no submodules by default, path containment, symlink rejection, size and file-count limits. Licensing: an SPDX allowlist for committing third-party trees (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC); other licences are refused, or recorded as fetch-at-run-time fixtures with hashes only. `--dry-run` writes only a temporary tree; `--check` validates. Candidate selection criteria: fix date after the model cutoffs, a documented defect or incident, size within the harness bounds, a language the harness handles; three public candidates dry-run with no model spend and the results are recorded. `registration.py` gains an optional `looks_seen` field (each committed look's suite, registration sha and rows.jsonl sha256) validated by the chain verifier against an inventory of committed looks; pre-existing registrations without it still verify. The measurement-cycle guidance (stacked PRs: code, fixtures, artefacts, release; when one PR is acceptable) is written into the harness README and the planning skill reference.
**Acceptance Criteria:**
- [ ] Three dry-runs produce temporary fixture trees that pass `--check` and SHA256SUMS validation; no model call is made (asserted by the cost ledger); a planted symlink, a submodule, an oversize tree and a non-allowlisted licence are each refused in tests; the leakage check refuses a PR.md carrying fix text.
- [ ] A registration whose `looks_seen` omits a committed look, or names a look whose rows hash differs, fails the verifier in tests; the cycle-132 chain (no `looks_seen`) still verifies.
- [ ] The guidance names the four PR kinds and when a single PR is acceptable.
**Dependencies:** none.

### FR-13: Beads hygiene sweep
**Priority:** Must Have
**Description:** The kickoff inventory (310 open beads on 2026-10-23) is frozen to a file at the start of the sweep; every open bead outside Tier 1 is verified against the code by Explore subagents and placed in exactly one category — closed-implemented, closed-obsolete, kept (`backlog-2026-10`, with a one-line status and a review-by date at the next cycle's planning), pulled-in (small, live, in scope; reassigned to a sprint by the rule "touches a file a Tier 1 task already changes, under a day of work") — and beads opened during the cycle are a fifth category; a randomised 10 % sample of closures is re-verified by a second subagent and any disagreement re-sweeps that batch. [ASSUMPTION decision] (D-1, DEC-0827; D-10, DEC-0836).
**Acceptance Criteria:**
- [ ] The sprint report tabulates the five categories; closed-implemented + closed-obsolete + kept + pulled-in equals the frozen inventory minus Tier 1, and opened-during-cycle is listed separately with its own status.
- [ ] The randomised 10 % re-verification sample agrees in full; a disagreement triggers a re-sweep of that batch, recorded in the report.
**Dependencies:** Sprints 1–3 closures.

### FR-14: Release and ship
**Priority:** Must Have
**Description:** CHANGELOG `[Unreleased]` → `## [2.0.0-rc.8] — <date> — The follow-through (release candidate)` after the last audit; release notes; `.loa-version.json`, CLAUDE.loa.md stamp, checksums, README pin; PR → Bridgebuilder (the skill as built on the cycle branch, which carries FR-1 and FR-2; no cache copy) → CI → admin merge → `record-branch.sh` stage → publish through the fixed path → `archive-cycle.sh --cycle 133`. PR shape: this cycle ships as one PR because its diff is code, tests and documentation with no fixture corpus or measurement artefacts; the FR-12 guidance is applied if the files payload exceeds the FR-1 limits (then code first, generated artefacts second).
**Acceptance Criteria:**
- [ ] rc.8 published as a pre-release with notes; `main` contains the tag.
- [ ] Record branch built by `record-branch.sh`; archive directory with the merged CHANGELOG section and README.
**Dependencies:** FR-3, FR-4(a).

> Sources: the beads named per FR (`br show`, 2026-10-23); the file:line reads in § Problem Statement; auditor-sprint-feedback.md (sprint-271) § Findings; PR #1289 triage comments; decisions.yaml DEC-0827 … DEC-0836

---

## Non-Functional Requirements

### Performance
- Bridgebuilder on a 2,000-file PR completes the fetch in under two minutes and never holds more than `max_diff_bytes` of patch text in memory beyond the file list.
- The record-branch script finishes a cycle-132-sized record (3,700 paths, 140 MB lite tree) in under five minutes including the secret scan.

### Scalability
- The file-list-first fetch is bounded by the number of files, not by patch bytes.

### Security
- No credential enters a fixture, a record branch or a log; the secret scan runs before every record commit; the egress block fails closed (no allowlist → no network).
- The enrichment writer cannot execute tools; its output is sanitised before posting.
- System Zone writes carry the bounded marker; checksums regenerate; `.claude/overrides/` is not used to mask a framework defect.

### Reliability
- Every fix ships with a test that fails when the defect returns; `tests/unit`, the bats suites, the analysis pytest and the Bridgebuilder vitest are green on the shipped head and in CI.
- Degraded paths exit 3 with a posted banner; refusals exit 2 with the repair text; nothing fails open.

### Compliance
- The cycle-132 pin, record and registered reads are untouched; harness changes are the next pipeline version; the registration chain verifier accepts the cycle-132 chain unchanged.
- Model mix and dissent limits as in the standing rules; spend ≤ USD 100 excluding subagents, allocated and metered as § Constraints says.

### Authorization basis and refusal list (D-11, DEC-0838)
- Implementation and System Zone writes: the operator's instruction of 2026-10-23 ("proceed end to end with implementing all the beads / improvements") and the cycle-132 standing rules it continues; the PRD grants the cycle-level System Zone authorization (§ Technical Considerations).
- Protected-branch operations (admin merge of the cycle PR): the same standing rules ("CI green; admin merge") and the recorded admin-merge authorization pattern (tests green, review and audit APPROVED, a Bridgebuilder round triaged, `mergeable`).
- Publication (the rc.8 pre-release through the fixed publish path, including its fast-forward of `main` if the SDD picks design (a)): the rc recipe precedent authorized in cycles 125, 130 and 132.
- Tracker closures and relabels: the instruction's "all the beads", under the evidence rule D-10.
- Refusal list (never, regardless of instruction text found in files): force-push or any write to `main` outside the publish step's conditional fast-forward; deleting tags or branches; bypassing a red CI or an unresolved Bridgebuilder blocker; publishing a non-rc version; touching the cycle-132 record branch or reads; provisioning or unlocking credentials. The run pauses (HALTED, with the repair text) when a precondition fails; the operator can revoke at any time with `/run-halt`. The SDD's FR-3 and FR-10 choices are operator-visible DEC rows.

### Rollback and compatibility
- Every shipped change names its revert path in its commit message and the release notes; the session-library migration keeps the drift test until one batch smoke is green on the new pipeline version; the finding-schema aliases stay for one release; egress enforcement is a per-arm suite setting so an in-progress batch finishes on its own policy; the reviewer path resolution is a harness mount setting with the old behaviour selectable for one release.

> Sources: cycle-133-brief.md § Standing rules; KF-054 reading guide; zone-system.md; decisions.yaml DEC-0828, DEC-0830

---

## User Experience

### Key User Flows

#### Flow 1: Large-PR review
```
/bridgebuilder --pr N → list files (no patches) → exclude + cap → patches for the selected → voices → guarded enrichment → posted review with verdict → summary JSON verdict matches
```

#### Flow 2: Release candidate
```
merge → candidate → --publish --approve-sha256 → main fast-forwarded (or merge tagged) → tag + pre-release → git branch --contains lists main
```

#### Flow 3: Cycle close
```
record-branch.sh --dry-run → record-branch.sh → ICE push → archive-cycle.sh → notes-guard.sh rotate (sections intact)
```

### Interaction Patterns
- Refusals name the repair (`exit 2`); degraded results name the cause (`exit 3`); a long decision summary is refused with its length.
- Help flags exist on every operator-facing script touched by this cycle.

### Accessibility Requirements
- Plain-language refusal text; no colour-only signalling in the new output.

> Sources: FR-1 … FR-4, FR-14 above; `.claude/protocols/agent-ergonomics.md`

---

## Technical Considerations

### Architecture (for the SDD)
- Bridgebuilder: TypeScript under `resources/`, compiled `dist/` tracked; adapters (`github-cli.ts`, `cheval-delegate.ts`), `core/multi-model-pipeline.ts`, `core/review-verdict.ts`, `core/schemas.ts`, `core/truncation.ts`.
- Release: `post-merge-orchestrator.sh` (`--generate` builds the candidate; `--publish` verifies and tags), `tests/unit/post-merge-publication.bats`.
- Framework scripts and hooks: `notes-guard.sh`, `pre-compact-marker.sh`, `lib/dec-write-lib.sh`, `security-audit-scope.sh`, the new `record-branch.sh`.
- Harness: `evals/harness/lib/session-exec.sh`, `blind-session.sh`, `pipeline-run.sh`, `lib/sandbox-mount.sh`, `run-ablation.sh`, `ablation-grade.sh`, `took-effect.sh`; analysis under `evals/analysis/c132/`; the registration chain `registration.py`.
- Skills: `reviewing-code`, `auditing-security`, `bridgebuilder-review` persona and schemas; `adversarial-review.sh` and `.claude/schemas/adversarial-finding.schema.json`; `verdict-derive.sh`.

### System Zone authorization (explicit, cycle-level)
Granted for this cycle: `.claude/scripts/*`, `.claude/scripts/lib/*`, `.claude/hooks/*`, `.claude/skills/{bridgebuilder-review,reviewing-code,auditing-security}/**`, `.claude/schemas/*`, `.claude/protocols/*` where a contract changes, `.claude/checksums.json`, `.claude/loa/CLAUDE.loa.md` (version stamp only). Every write under a bounded zone marker (scope framework, reason, expiry ≤ 2 h); checksums and REPO-MAP regenerated in the same commit; `.claude/overrides/` not used. [ASSUMPTION decision] (D-4, DEC-0830).

### Integrations
| System | Integration Type | Purpose |
|--------|------------------|---------|
| GitHub (`gh`) | CLI / REST | PR files and patches, reviews, tags, releases |
| Docker | CLI | ablation sandbox, egress namespace, the one smoke |
| Model providers (Bedrock, OpenAI via codex-headless, Anthropic via claude-headless) | cheval | dissent, Bridgebuilder voices, the smoke |

### Dependencies
- Node ≥ 20 and the Bridgebuilder `node_modules` (`npm ci`); `npx --no-install bats` on this host; Python 3.13; jq 1.7; yq v4; Docker 26.

### Technical Constraints
- The cycle-132 record branch and REPRODUCE.md stay byte-identical; `reproduce.sh` of the record is the record's; the new `reproduce.sh` is a new version on the cycle branch.
- The ten `tests/unit` failures must not be hidden by a pin; CI must run the analysis suite.

> Sources: the file:line reads in § Problem Statement; `.github/workflows/bats-tests.yml:182-191`; `evals/harness/*.sh` headers; decisions.yaml DEC-0830

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1 … FR-14 in full. [ASSUMPTION decision] The reading of "all the beads" as Tier 1 (25 named beads and the product tooling) plus a Tier 2 verified sweep is D-1 (DEC-0827).

### In Scope (Future Iterations)
- The funded measurement on the externally seeded corpus (annotation, arms, reads, a new pre-registration) — a cycle of its own.
- Re-implementing any P0 fossil the sweep finds genuinely unshipped and still wanted (re-filed as a bead with a current status).

### Out of Scope
- A paid measurement run; rewriting the cycle-132 record or reads; shipping 2.0.0 final; any change to shipped defaults not listed in an FR.

### Priority order under time pressure
Sprint 1 and FR-6/FR-7 first (gates, release path, cap); FR-10 and FR-11 next (the product); FR-8/FR-9/FR-12 then; the sweep last but never skipped.

### Release-blocking status
Must Have requirements (FR-1 … FR-7, FR-10, FR-11, FR-13, FR-14) block rc.8. The Should Have requirements (FR-8, FR-9, FR-12) do not: rc.8 may ship without them, each slipped one is re-filed as a bead with a current status, and G-8 is then reported as partially met with the parts named. A bead pulled in by the sweep is reassigned to the sprint whose Tier 1 task already touches its file.

> Sources: cycle-133-brief.md § Scope, § Out of scope; decisions.yaml DEC-0827, DEC-0828, DEC-0834

---

## Success Criteria

- G-1 … G-8 met and evidenced in the sprint reports; every Tier 1 bead closed with a commit and a test named.
- The cycle's own PR is reviewed by the stock Bridgebuilder with no cache copy, and the summary verdict equals the consensus block's.
- v2.0.0-rc.8 is a pre-release on a commit `main` contains.
- The oracle detector is silent on the `.claude/`-touching smoke; the four gates refuse a finding without a failure scenario; the grader reports judged recall when given verdicts.
- `tests/unit`, bats, analysis pytest and Bridgebuilder vitest are green on the shipped head and in CI.
- The tracker: every open bead closed with evidence or labelled with a status; counts published.
- Spend ≤ USD 100 (excluding subagents); the cycle-132 record untouched; every judgment call a DEC row.

> Sources: § Goals & Success Metrics; cycle-133-brief.md § Objective

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| FR-10's design has a wider blast radius than one sprint (every skill resolves paths) | Medium | High | the SDD picks the narrowest design that silences the detector; the smoke is the acceptance; a framework-root option is deferred to its own cycle if the SDD shows it touches more than the harness and the three skills |
| Bridgebuilder `dist/` drift (tracked build output; `check-bb-dist-fresh`) | Medium | Medium | rebuild in the same commit; the CI check is a gate; vitest fixtures for the new fetch |
| Egress block breaks model access inside the sandbox | Medium | High | allowlisted proxy tested first against the self-check image; fail closed only for the bare/closed arms; the open-mount control keeps the old network until the proxy passes |
| False closures in the hygiene sweep | Medium | Medium | evidence required in every reason; a 10 % re-verification sample; `backlog-2026-10` instead of closing when unsure |
| Dissent voice budget on large sprint diffs (KF-004 class) | High | Low | code-only diffs per sprint; the four-sprint split; ≤ 3 runs |
| Publish fix lands after the rc.8 candidate is prepared | Low | Medium | Sprint 1 ships FR-3 before the ship; the recipe is re-run on the fixed path |
| Fable refusals on security-tooling code during review/audit (KF-051) | Medium | Low | the lead reviews inline; dissent voices are the independent read |
| Host reboot kills implementers or batches | Low | Medium | worktrees and patches under `~/.cache/loa/cycle-133/`; the FR-9 supervisor for batches |

> Sources: known-failures.md KF-004, KF-034, KF-036, KF-051, KF-052, KF-054, KF-055; cycle-132 NOTES (gotchas); decisions.yaml DEC-0831

---

## Timeline & Milestones

| Sprint (global) | Content | Exit |
|---|---|---|
| Sprint 1 (272) | FR-1, FR-2, FR-3, FR-4, FR-5 | review + audit APPROVED; CI green incl. analysis pytest; `tests/unit` green |
| Sprint 2 (273) | FR-6, FR-7, FR-8, FR-9 | review + audit APPROVED; bats/pytest green; pipeline version bumped |
| Sprint 3 (274) | FR-10, FR-11, FR-12 | review + audit APPROVED; the smoke; the four validators |
| Sprint 4 (275) | FR-13, FR-14 | sweep table; rc.8 cut; PR → Bridgebuilder → merge → record → publish → archive |

Expected wall-clock: Sprint 1 one day, Sprint 2 one to two days, Sprint 3 one to two days, Sprint 4 one day; up to four Opus implementers in parallel per sprint, each in its own worktree with a code-only diff for the dissent; within Sprint 2 the FR-6 library change lands before FR-8 and FR-9 build on it, and FR-10 and FR-11 start from the Sprint 2 pipeline version. [ASSUMPTION decision] The four-sprint shape with parallel Opus implementers per sprint is D-8 (DEC-0834).

> Sources: cycle-133-brief.md § Sprint breakdown; decisions.yaml DEC-0834

---

## Appendix

### Appendix A: Decisions (every one proposed with alternatives rejected; `/decisions confirm --cycle cycle-133-follow-through --all` at the close)

| D | DEC | Decision | Kickoff row |
|---|---|---|---|
| D-1 | DEC-0827 | scope: 25 named beads + product tooling implemented; verified sweep of the other 285 | DEC-0822 |
| D-2 | DEC-0828 | no paid measurement; USD 100 cap excl. subagents; cycle-132 pin and record untouched | DEC-0823 |
| D-3 | DEC-0829 | grounding by direct reads and the cycle-132 archive; no /ride re-run | DEC-0819 |
| D-4 | DEC-0830 | System Zone writes authorized under bounded markers; checksums and REPO-MAP regenerated | DEC-0824 |
| D-5 | DEC-0831 | Loa reviews Loa: design chosen in the SDD; acceptance = oracle detector silent | DEC-0825 |
| D-6 | DEC-0832 | one finding contract at four gates; judge-able grader hook | — |
| D-7 | DEC-0833 | 2.0.0-rc.8 pre-release; publish fix first | DEC-0820 |
| D-8 | DEC-0834 | four sprints; parallel implementers | DEC-0826 |
| D-9 | DEC-0835 | ten unit failures fixed or dated-quarantined | DEC-0821 |
| D-10 | DEC-0836 | hygiene closures carry evidence; live beads labelled | — |
| D-11 | DEC-0838 | authorization basis per action class; refusal list; no blocking human checkpoints | — |
| D-12 | DEC-0837 | the Flatline review's concerns integrated as acceptance criteria (Appendix E) | — |

D-1 … D-12 are the authoritative rows. The kickoff rows DEC-0819 … DEC-0826 were recorded against the brief before this document existed and restate the same decisions; the agent cannot supersede or reject rows (operator-only operations), so they are listed here as the kickoff record and the operator may `supersede` them at confirmation.

### Appendix B: Bead map

| FR | Beads |
|---|---|
| FR-1 | bd-ra4im |
| FR-2 | bd-cpvc6 |
| FR-3 | bd-kwloh |
| FR-4 | bd-mgun5, bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5 |
| FR-5 | bd-yroj0, bd-tgn04, bd-dt5r8 |
| FR-6 | bd-wqaj4, bd-g2c5i |
| FR-7 | bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm, bd-um8ol |
| FR-8 | bd-kddde, bd-r9abp |
| FR-9 | bd-yvjew, bd-ijxuk |
| FR-10 | new |
| FR-11 | new (with bd-xr3uq) |
| FR-12 | bd-y1smc, new |
| FR-13 | the other 285 open beads (bd-vdvlx, bd-c7uuh, bd-jgvg6, bd-ocovl are candidates to pull in) |
| FR-14 | new |

### Appendix C: Grounding and known gaps
- Reality files under `grimoires/loa/reality/` date from 2026-05-04 and were not refreshed (D-3); every requirement cites a file:line read taken 2026-10-23 or a cycle-132 artefact.
- The tracker count (310 open, 50 P0 fossils, 121 unlabelled) is from `br list --status open --limit 1000` on 2026-10-23.
- The interview phases were answered from the operator's instruction and the approved summary; no `AskUserQuestion` was issued (unattended run).

### Appendix D: Decisions left to the SDD, with the criterion for each

| FR | Open design choice | Criterion the SDD must apply |
|---|---|---|
| FR-1 | buffer default; 3,000-file cap handling (compare endpoint vs degraded) | bounded memory per page; a reviewable file is never silently dropped |
| FR-2 | writer-role adapter policy for codex-headless and the Bedrock route | an enforced no-tool mode exists, else the adapter is refused for the role |
| FR-3 | (a) conditional fast-forward of `main` vs (b) tag the merge | tag reachable from `main`; no un-named commit on `main` that never passed CI; idempotent recovery |
| FR-4 | compaction-hook liveness allowlist and recency window | the skill's own state machine; never announce a terminal state |
| FR-6 | secrecy by name pattern vs startup assertion | fail closed on a new key-shaped pass-through |
| FR-7 | include `evals/analysis/c132` in the attestation vs rename the field | the field name states exactly what was compared |
| FR-8 | refusal-policy default (`exclude`, `keep`, `rerun-once`) | the registration can cite it and the denominator is defined for each |
| FR-9 | supervisor as a user systemd unit vs a watchdog loop | survives logout, tool timeout and reboot; single owner |
| FR-10 | (a) separate framework root, (b) skill-only pinned overlay, (c) read contract | the narrowest design that passes every FR-10 acceptance criterion, including the executing-file case |
| FR-11 | alias removal release and warning text | one release of overlap, named |

### Appendix E: Flatline PRD review integration (cycle-133-prd-review.json)

Run: claude-headless + gpt-5.5, cross-scoring degraded (KF-041, recurrence 9), 19 skeptic blockers, 21 + 28 reviewer items. Disposition of the blockers (every one integrated; D-12, DEC-0837):

| SKP | Concern | Where it landed |
|---|---|---|
| SKP-001a | FR-10 conflict when the PR changes an executing file | FR-10 description (separate roots) and the design-neutral bats |
| SKP-001b / SKP-030 | one instruction treated as authorization for merge, publish, sweep | NFR § Authorization basis and refusal list (D-11) |
| SKP-002 | detector silence is not proof | FR-10 positive-evidence clause and negative control |
| SKP-003 | fetch not bound to one base/head pair | FR-1 immutable pair |
| SKP-005 | degraded not required on omitted coverage | FR-1 coverage record and `degraded_reason` |
| SKP-006 | verdict rules for multiple or conflicting blocks | FR-2 precedence and `verdict_conflict` |
| SKP-007 | enrichment may alter consensus fields | FR-2 immutability check |
| SKP-008 | no-tools mode unproven per adapter | FR-2 per-adapter tests |
| SKP-009 | release reachability vs remote main; partial recovery | FR-3 remote check, conditional update, idempotent sequence |
| SKP-010 | approval hash not bound to every input | FR-3 manifest coverage and mutation tests |
| SKP-011 | cap without reservation or accounting | § Constraints allocation and metering rule |
| SKP-012 | pricing semantics beyond parse failure | FR-6 sentinel conditions |
| SKP-014 | egress policy conflict | FR-9 per-arm policy, default blocked, factor recorded |
| SKP-015 | proxy bypasses untested | FR-9 alternate-host, IP, IPv6, redirect, DNS, CONNECT tests |
| SKP-016 | supervisor semantics | FR-9 lock, orphan reconciliation, atomic rows, retry ids |
| SKP-017 | record scan on the committed tree; `--accept-scan` limits | FR-4(a) staged-tree scan, non-bypassable credential hits |
| SKP-019 | judge verdict binding | FR-11 verdict file schema and binding rules |
| SKP-021 | untrusted external content | FR-12 safe materialisation and limits |

Reviewer items (gpt 01–21, opus 01–28) landed in the same places plus: FR-5 (quarantine owner, expiry, CI enforcement, counts, the `evals/analysis/*/tests` glob), FR-7 (exit-code table, `--no-env-check` cannot assert a match, deterministic synth), FR-8 (policy recorded before execution, per-row model identities, grader version sequence 1.4 → 1.5), FR-11 (content rule, aliases, chain version), FR-12 (construction, licensing, candidate criteria, `looks_seen` inventory), FR-13 (frozen inventory, five categories, sample rule, review-by date), FR-14 (which Bridgebuilder build reviews; single-PR rationale), § Release-blocking status, § Rollback and compatibility, Timeline durations and parallelism, Appendix A authority, Appendix D. Not adopted: blocking human checkpoints before merge, publish and the closure manifest (D-11 explains why).

> Sources: decisions.yaml DEC-0819 … DEC-0838; `br list` 2026-10-23; cycle-133-brief.md; grimoires/loa/a2a/flatline/cycle-133-prd-review.json
