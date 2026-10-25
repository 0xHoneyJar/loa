# Product Requirements Document: Post-ship fixes (cycle-134)

**Version:** 1.2
**Date:** 2026-10-25
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-25, quoted verbatim in the brief: "please proceed with your recommended approac for each of the (1) and proceed with all the next steps as you advise"; the interview phases were answered from that instruction, the brief and the defect sites; every decision taken on the operator's behalf is a DEC row in Appendix A)
**Brief:** `grimoires/loa/context/cycle-134-brief.md`
**Cycle:** `cycle-134-post-ship-fixes` (ledger, active); **branch:** `feature/cycle-134-post-ship-fixes` from `chore/cycle-133-post-ship c533d760` (PR #1295, so the confirmed decision rows are the base)
**Flatline:** `grimoires/loa/a2a/flatline/cycle-134-prd-review.json` (codex-headless + claude-headless, 2/2 voices, cross-scoring degraded — KF-041 shape; 7 skeptic blockers and 37 medium items, every one read and dispositioned in Appendix C; 1.1 integrates the accepted ones)
**Predecessor:** cycle-133 "the follow-through" (PR #1292 → `3e5b9d36`; v2.0.0-rc.8; record `603732b9`/`c35cbab3`; archive `grimoires/loa/archive/cycle-133-follow-through/`; the Bridgebuilder round 2 findings and triage: PR #1292 comments 6386303901, 6386296457, 6386296833, 6386491267)

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
13. [Appendix A — Decisions taken on the operator's behalf](#appendix-a--decisions-taken-on-the-operators-behalf)
14. [Appendix B — Grounding reads](#appendix-b--grounding-reads)
15. [Appendix C — Flatline PRD review dispositions](#appendix-c--flatline-prd-review-dispositions-10--11)
16. [Appendix D — Bridgebuilder round 2 findings: traceability](#appendix-d--bridgebuilder-round-2-findings-traceability)

> Sources: this document's sections

---

## Executive Summary

cycle-133 shipped 2.0.0-rc.8 and, on its own pull request, ran the Bridgebuilder it had just repaired. The round could not reach a non-degraded verdict on a 374-file PR (G-2 not met, DEC-0957), but its 17 findings were real: two MEDIUM defects in the home-scope validator `evals/harness/took-effect.sh` (a legitimate session with a recurring hook false-fails; a phase whose transcript is missing passes unchecked), seven LOW defects across the harness libraries and the publish orchestrator, and a REFRAME about the PR shape (now DEC-0960). The ship itself exposed one more: the publisher's ledger fast-forward re-triggers `post-merge.yml`, which classifies the bot push as a cycle merge and fails with `--pr is required` (KF-063).

This cycle fixes those nine defects through the golden path, with a test for each and a regression against the two recorded smoke evidence trees, in one sprint PR shaped for a non-degraded Bridgebuilder verdict (DEC-0960). No model spend is needed to build or test anything in scope; the only paid step is the Bridgebuilder round. No new release candidate is cut: the rc.8 soak continues and the fixes ride `main` into rc.9 or 2.0.0 ([ASSUMPTION decision] (DEC-0967)).

> Sources: cycle-134-brief.md § Objective, § Scope; PR #1292 triage comment 6386491267; KF-063 (`grimoires/loa/known-failures.md`); DEC-0957, DEC-0960

---

## Problem Statement

### The Problem

The home-scope validator is the only thing that will tell the next measurement cycle whether a sandboxed Loa session loaded or ran anything of the PR under review. Two of its clause (g) checks are wrong in opposite directions: the hook check counts executions against a count of configured commands, so a longer legitimate session fails; the transcript discovery lists whatever files exist, so an executed phase with a missing or truncated transcript is never examined. The remaining defects are small but each lets a guard silently under-deliver: an integrity record the validator trusts instead of recomputing; rewrite rules broader than the mount needs with one of them unverified; a proxy pid limit below its configured client ceiling; a reclaim path that signals a recorded process group without checking it is still that job; a fix diff computed over blobs never fetched; an exit-code contract the publisher's own tag check breaks after it has written state. And every rc publish now turns the post-merge pipeline red for a reason that has nothing to do with the release.

### User Pain Points

- The maintainer cannot trust a green `oracle_closed` until the hook and transcript gaps close, and cannot trust a red one on a long session.
- A red "Post-Merge Pipeline" after every publish is a false alarm that trains the operator to ignore the pipeline.
- The LOW findings are each a sentence to fix and a test to write; left open they recur in the next audit as "known, not fixed".

### Current State

Every defect is filed as a bead with its finding text, file and line (`bd-bex39`, `bd-k3dia`, `bd-hyx0n`, `bd-htzy2`, `bd-kgfh5`, `bd-1br0v`, `bd-ruo5b`, `bd-kdk3l`, `bd-4pv1j`); the triage comment on PR #1292 records the dispositions; KF-063 records the post-merge shape with its reading guide. Nothing is fixed.

### Desired State

Nine beads closed with commit and test; the validator correct in both directions against fixtures and against the recorded smoke evidence; the post-merge pipeline green on the publisher's own push; the publisher's exit-code contract true; the harness libraries' guards doing what their comments say.

> Sources: `evals/harness/took-effect.sh:600-601, 624-625, 865-871, 1102-1113` (Appendix B); `.github/workflows/post-merge.yml:110, 182`; run 40112013975; `grimoires/loa/known-failures.md` § KF-063; `br show` of the nine beads (2026-10-25)

---

## Goals & Success Metrics

### Primary Goals

| # | Goal | Measure |
|---|------|---------|
| G-1 | Every in-scope bead closed with evidence | 9 beads closed, each close reason naming the commit and the test |
| G-2 | The validator is right in both directions | fixtures: a legitimate recurring-hook session passes, a project hook still fails, a phase without transcript or init fails, a complete capture passes; the recorded c133-smoke run-1/run-2 re-validate to the recorded verdicts |
| G-3 | The post-merge pipeline is green on a push without a PR | a classify fixture (or workflow-level test) for the bot's ledger-commit shape passes; the next publish's ledger push produces no red run |
| G-4 | One PR, one non-degraded Bridgebuilder verdict | the sprint PR's Bridgebuilder summary carries no `degraded_reason`; the summary verdict equals the consensus block's |
| G-5 | Green suites at no model spend | CI green on the merged head; cycle spend ≤ USD 20, all of it the Bridgebuilder |

### Key Performance Indicators (KPIs)

| KPI | Baseline (today) | Target |
|-----|------------------|--------|
| took-effect clause (g) false-fail on a session with N>1 PreToolUse invocations and one configured hook | fails (count > declared) | passes |
| took-effect clause (g) on an executed phase with no transcript | passes | fails naming the phase |
| Post-Merge Pipeline on the publisher's ledger push | red (`--pr is required`) | green or skipped |
| Bridgebuilder verdict on the cycle's PR | UNKNOWN/degraded (cycle-133) | non-degraded |

### Constraints

- Autonomous; every judgment call is a DEC row (the decision rows are listed in Appendix A).
- Opus 5.5 implementers in worktrees; Fable 5.1 lead for review and audit; ≤ 3 dissent runs per sprint; no live model calls by implementers.
- Spend cap USD 20 ([ASSUMPTION decision] (DEC-0969)): every paid model call recorded in `.run/cost-ledger.jsonl` during the cycle (the Bridgebuilder's voices and writer; any paid Flatline or dissent voice); the lead's own session and the Opus implementer sessions are subscription-routed and excluded, as in cycle-133 (IMP-021 accepted).
- System Zone (`.claude/`, `.github/`) writes only under the bounded zone marker with `checksums.json` and REPO-MAP regenerated (DEC-0824 carries over); the marker (expiry ≤ 2 h) is re-issued per write session with its reason, and the regeneration happens in the final commit of each System Zone change so the manifests never lag the files (IMP-019 accepted).
- No change to the cycle-132 or cycle-133 records; no measurement run.

> Sources: cycle-134-brief.md § Objective, § Standing rules; DEC-0960, DEC-0969; PR #1292 comment 6386303901 (coverage record)

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

Reads the pipeline's colour, the validator's verdict and the bead ledger; wants each to mean what it says.

### Secondary Persona: The lead agent (Fable) and its Opus subagents

Implement, review and audit the fixes; need file:line grounding and fixtures that fail before and pass after.

### Tertiary Persona: The lead of the next measurement cycle

Will run `took-effect.sh` on hundreds of sessions and cannot afford a validator that false-fails long sessions or passes unexamined phases.

### Use Cases

| ID | Actor | Scenario | Outcome |
|----|-------|----------|---------|
| UC-1 | measurement lead | a home-scope session invokes Bash twice with one configured PreToolUse hook | `oracle_closed` passes; only a hook outside the pinned configuration fails it |
| UC-2 | measurement lead | the AUDIT phase ran but its transcript is missing or truncated | `oracle_closed` fails naming the phase |
| UC-3 | operator | the publisher fast-forwards the ledger commit onto `main` | the post-merge pipeline does not fail; the publish stays verified by the publisher's own checks |
| UC-4 | operator | a publish finds a pre-existing tag with another identity | the run refuses before writing state (exit 2) or fails after (exit 1) — never exit 2 after a write |
| UC-5 | harness operator | the egress proxy serves many concurrent sandbox connections | connections are refused by `MaxClients`, not by the container's pid limit |
| UC-6 | harness operator | a batch is resumed after the recorded process group's pid was reused | nothing unrelated is signalled |
| UC-7 | corpus curator | an external PR's fix touches files whose blobs the bounded fetch skipped | the seeder fetches them or refuses naming the paths — never a silent partial diff |

> Sources: cycle-134-brief.md § Scope; the bead descriptions (`br show`, 2026-10-25)

---

## Functional Requirements

### FR-1: took-effect clause (g) verifies hook identity, not a count (bd-bex39)
**Priority:** Must Have
**Description:** `took-effect.sh` counts every `hook_started` event per (transcript, event) — `"hook_counts[k] = hook_counts.get(k, 0) + 1"` (took-effect.sh:625) — and fails when the count exceeds `home_hook_counts`, the number of configured hook commands per event: `"if cnt > decl.get(evn, 0): fail("g", "-", "%d %s hook(s) ran in %s; the pinned user settings declare %d (home_hook_counts)" …)"` (took-effect.sh:1112-1113). A recurring event (PreToolUse, UserPromptSubmit) legitimately runs its commands on every trigger, so a session with more triggers than configured commands false-fails (Bridgebuilder F-001, MEDIUM 0.99). The check must instead establish that every hook that ran belongs to the pinned user configuration. The stream-json `hook_started` event carries `hook_id`, `hook_name` and `hook_event` and no command text; the retained cycle-130 smoke transcripts show `hook_name` as `<event>:<matcher>` (`SessionStart:startup`, 16 events for 8 configured commands), so the identity available is the (event, matcher) group. The rule therefore has three parts, all required (Flatline SKP-001, IMP-001, IMP-016 accepted): (a) every `hook_started`'s (event, matcher) group must exist in the pinned user settings read from the HOME copy (groups with the same key merge); (b) per group the observed count c equals k·n for an integer k ≥ 0, n being the group's configured command count — k = 0 is legal, because clause (g) asks whether a hook of the PR ran, not whether the pinned hooks fired (the retained smoke sessions emitted no tool-hook events beside 31–66 Bash uses); (c) where the transcript yields the trigger count for the event (init events, user turns, matching `tool_use` blocks, result events) k may not exceed it. The evidence producer is in scope: the mount's `sandbox-mount.sh hooks` emits a `home_hook_groups` line whose group ids are hex digests of the matcher strings (no verbatim matcher text), beside the unchanged `home_hook_counts`; the validator falls back to event-level aggregates for recorded runs (IMP-003 accepted; SDD D-1.1a).
**Acceptance Criteria:**
- [ ] A fixture transcript with one configured PreToolUse hook and two Bash invocations passes clause (g); the same fixture with a `hook_started` whose (event, matcher) group is not in the pinned configuration fails naming it; a count that is not a whole multiple of the group's command count, or a multiple above the transcript's trigger count, fails naming the group and the counts.
- [ ] The `hook_name` grammar is confirmed on a real event for a matcher-less group and for a regex matcher (a one-turn `claude -p` under the pinned user settings on the lead host, or the first live home-scope run), and the parser accepts both `<event>` and `<event>:<matcher>` (IMP-012 opus accepted).
- [ ] `home_hook_counts` (or its successor evidence line) is still required; absence still fails with the existing message.
- [ ] `took-effect.sh` over the retained smoke batch run directories `evals/results/ablation-2.0/smoke-c133-s274` and `smoke-c133-s274-r2` (host-local, gitignored; they hold the transcripts — the report trees under `grimoires/loa/reports/ablation-2.0/c133-smoke/` keep `meta/` only and cannot replay clause (g)) reproduces their recorded verdicts before and after the change, with the verdict lines captured in the sprint report ([ASSUMPTION decision] (DEC-0970), amended by DEC-0980; SKP-002, IMP-004 accepted). A verdict that legitimately changes is investigated and recorded as a DEC row and a bead, never accepted silently (IMP-002 opus accepted).
- [ ] The header comment at took-effect.sh:106-107 describes the new rule.
**Dependencies:** none.

> Sources: `evals/harness/took-effect.sh:600-640, 1102-1113` (Appendix B); PR #1292 comment 6386296833 finding F-001; `grimoires/loa/reports/ablation-2.0/c133-smoke/run-*/meta/arm-evidence.txt` (`home_hook_counts=PermissionRequest:1,PostToolUse:4,PreCompact:1,PreToolUse:11,SessionStart:8,Setup:1,Stop:2,UserPromptSubmit:2`)

### FR-2: took-effect clause (g) requires a transcript and an init event per executed phase (bd-k3dia)
**Priority:** Must Have
**Description:** The per-phase loop requires a process capture — `"psf = os.path.join(run, "meta", "ps-%s.txt" % lab); if not os.path.isfile(psf) …: fail("g", "-", "no process capture for %s …")"` (took-effect.sh:868-870) — but transcripts are discovered from whatever files exist: `"tfiles = sorted(n for n in (os.listdir(tdir) if os.path.isdir(tdir) else []) if re.match(r"^events-[A-Za-z0-9_-]+\.jsonl$", n))"` (took-effect.sh:601). An executed phase with a missing or truncated transcript therefore leaves its loaded MCP servers, plugins, skills, commands and Bash commands unchecked while another phase's reads satisfy clause (f) (Bridgebuilder F-002, MEDIUM 0.98).
**Acceptance Criteria:**
- [ ] For every label in `labels_run` (the non-skipped phases of `meta/pipeline.json`, the authoritative list — IMP-006 accepted), a readable, non-symlink `transcripts/events-<label>.jsonl` is required in which every non-empty line parses as a JSON object, exactly one `result` event is the final non-empty line (every `claude -p` session ends with one), at least one `system`/`init` event precedes it and every event carrying a `session_id` shares the init's; a missing file, an empty file, no init, no result, a result that is not last, or a malformed line anywhere fails clause (g) naming the phase and the line (SKP-002; SDD review SKP-006 accepted); a transcript whose label is not in `labels_run` is reported in the evidence line. Lines longer than `EVENT_CAP` must still be complete lines and are counted as skipped-for-size. A session the harness killed before its result therefore fails (g) as unexamined — the retained `smoke-c133-s274` REVIEW capture is the first such case and is pre-registered in the SDD (D-4.3).
- [ ] A fixture run with complete captures for every executed phase passes; the recorded smoke runs re-validate to their recorded verdicts.
- [ ] The header comment at took-effect.sh:98-107 describes the requirement.
**Dependencies:** none (shares the file with FR-1; one implementer).

> Sources: `evals/harness/took-effect.sh:590-601, 860-876` (Appendix B); PR #1292 comment 6386296833 finding F-002

### FR-3: The post-merge pipeline is green on a push without an associated PR (bd-hyx0n, KF-063)
**Priority:** Must Have
**Description:** `post-merge.yml` gates the non-cycle job on a PR number — `"if: needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''"` (post-merge.yml:110) — but the cycle job only on the type: `"if: needs.classify.outputs.pr_type == 'cycle'"` (post-merge.yml:182). The publisher's ledger fast-forward (`chore(ledger): archive <cycle> after merge`, author github-actions[bot], no PR) was classified `pr_type=cycle` with an empty `pr_number`, and `--generate` aborted: `ERROR: --pr is required` (run 40112013975 on `928b3b9e`). A push to `main` that is not a PR merge must not fail the pipeline; the SDD chooses the mechanism (job guard, classifier rule for the bot subject, or both) and must not hide the commit from the other workflows.
**Acceptance Criteria:**
- [ ] A classifier fixture for the ledger-commit subject and for an empty PR number yields a non-cycle outcome (or an explicit `skip`), with a bats test; the PR number is taken from the subject's trailing `(#NNN)` (GitHub's squash form) or the anchored `Merge pull request #N` prefix (GitHub's merge-commit form — this repository's), validated as a positive decimal, so `fix: … closes #12 (#345)` yields 345 and a subject without either yields none (SDD review IMP-011 accepted; implementation amendment I-1.6a).
- [ ] The cycle job is guarded on `pr_number != ''` (or the equivalent in the chosen design) with a workflow-syntax check in the test suite that reads the guard.
- [ ] A push without a PR (no `#NNN` in the subject) is distinguished from a failed PR lookup: a `gh` failure on a subject that carries `#NNN` still classifies by subject with the number kept, as today (IMP-007 accepted).
- [ ] The change is confined to `post-merge.yml` and the classifier; the other workflows that run on a push to `main` are listed in the sprint report and unchanged (IMP-020 accepted).
- [ ] The CHANGELOG entry and KF-063's status line record the fix; the next publish's ledger push is the live confirmation (recorded in the KF attempt row after the fact).
**Dependencies:** none.

> Sources: `.github/workflows/post-merge.yml:76-110, 176-186`; `.claude/scripts/classify-merge-pr.sh:15-19, 102-137`; run 40112013975 (job "Prepare Release (Cycle)", step "Prepare release candidate"); `grimoires/loa/known-failures.md` § KF-063

### FR-4: integrity_clean under home-scope verifies the HOME copy independently (bd-htzy2)
**Priority:** Should Have
**Description:** Under home-scope the rule reads a driver-written record — `"local hi="$R/meta/home-integrity.json""` … `"[[ -f "$hi" && ! -L "$hi" ]] || { EVID="home-scope: no meta/home-integrity.json (the HOME framework was never checked)"; return 1; }"` (took-effect.sh:373-374) — written by `pipeline-run.sh` "before the HOME is deleted" (pipeline-run.sh:191). The validator thus trusts the driver about the thing the driver is accused of. It must recompute what it can. The HOME is deleted before the validator runs (pipeline-run.sh:552-554), so a byte walk is possible only when a run retains the copy (a debugging option); in every run the validator binds the record to the pin independently of the driver: it derives the manifest digest from the pinned commit's `.claude/checksums.json` (which it already resolves for the surface names), requires `record.manifest_sha256`, `arm_evidence.manifest_sha256` and that digest to agree, and requires `record.files` to equal the manifest's entry count with `tampered` and `missing` zero. 'Unverifiable' in the Security requirement means a record that cannot be bound to the pin this way, and that fails; 'record cross-checked against the pin' and 'independent walk' are the two passing modes, each named in the evidence line (SKP-004, SKP-005, IMP-002/IMP-003 gpt accepted). Per-file tampering after the driver's check remains undetectable without a retained HOME; the limit is stated in the evidence line.
**Acceptance Criteria:**
- [ ] A fixture whose record digest differs from the pin's manifest digest fails; one whose `files` differs from the entry count fails; a retained HOME with a tampered file fails; a clean record (and a clean retained copy) passes with the mode named in the evidence line.
- [ ] The recorded smoke runs re-validate to their recorded verdicts.
**Dependencies:** FR-1/FR-2 (same file, same implementer).

> Sources: `evals/harness/took-effect.sh:363-380`; `evals/harness/pipeline-run.sh:74, 191`; PR #1292 comment 6386296457 (LOW, integrity_clean)

### FR-5: sandbox-mount rewrite rules R3 and R5 are as narrow as the mount needs, and verify covers R5 (bd-kgfh5)
**Priority:** Should Have
**Description:** `"R3 = re.compile(r"(?<![A-Za-z0-9_./$~{}\\-])\.claude/")"` (sandbox-mount.sh:1496) rewrites every relative `.claude/` mention in skill and rules prose to the HOME copy; `"R5 = re.compile(r"(?<!/ )(?<!/)(['\"])(\.claude/[A-Za-z0-9_./-]*)\1")"` (sandbox-mount.sh:1503) rewrites any Python string literal that is exactly a `.claude/…` path. The Bridgebuilder found both broader than the mount needs and reported that the verify step does not re-check R5 ([ASSUMPTION fact] the verify gap is taken from finding text; the SDD confirms it against sandbox-mount.sh:1600-1620). The rules must be narrowed to the forms the mount actually requires, verify must cover every rule, and the existing negative control must stay negative.
**Acceptance Criteria:**
- [ ] For each of R3 and R5, a table in the SDD of what must be rewritten and what must not, each row a test case; the rewritten corpus of the pinned framework is diffed before and after and every difference is explained.
- [ ] `verify` re-checks R5 (and every other rule) and fails on a planted un-rewritten literal.
- [ ] `evals/tests/sandbox-mount-home-scope.bats` and the home-scope negative control stay green.
**Dependencies:** none.

> Sources: `evals/harness/lib/sandbox-mount.sh:152, 1470-1505, 1576-1580, 1613`; PR #1292 comment 6386296457 (two LOWs on sandbox-mount.sh)

### FR-6: The egress proxy's pid limit is not below its client ceiling (bd-1br0v)
**Priority:** Should Have
**Description:** The proxy container starts with `"--security-opt no-new-privileges --pids-limit 128 --memory 256m"` (egress-proxy.sh:205) while its image configures `"MaxClients 200"` (Dockerfile.proxy:101); tinyproxy 1.11 is threaded, so threads count against the pid limit and connections fail before `MaxClients` is reached (Bridgebuilder LOW 0.3). The two values must be aligned (either direction, with the reasoning recorded) and asserted together.
**Acceptance Criteria:**
- [ ] `evals/tests/egress-proxy.bats` asserts that the launcher's `--pids-limit` is at least `MaxClients` plus the proxy's base task allowance, reading both values from the files; the allowance is observed once in a running proxy container (`/sys/fs/cgroup/pids.current` at idle) and pinned as a commented constant in the test (IMP-015, IMP-017 accepted). Every launch path of the proxy image uses the same limit.
- [ ] The Dockerfile comment at Dockerfile.proxy:45 (the documented run line) matches the launcher.
**Dependencies:** none.

> Sources: `evals/harness/lib/egress-proxy.sh:205, 283, 603`; `evals/harness/Dockerfile.proxy:45, 101`; PR #1292 comment 6386296457 (LOW, pids limit)

### FR-7: The batch supervisor's reclaim checks the identity of every group it signals (bd-ruo5b)
**Priority:** Should Have
**Description:** The reclaim comment promises "Same boot: the recorded runner (identity-checked) and every .jobs/ group still alive are terminated" (batch-supervisor.sh:237-238): the runner is identity-checked, the `.jobs/` groups are not, so a reused pgid on the same boot could be signalled (Bridgebuilder LOW 0.35). Each `.jobs/` record must carry an identity (start time and a command-line hash, as the runner's does) and `reclaim` must compare it before `kill_group`.
**Acceptance Criteria:**
- [ ] A bats fixture with a `.jobs/` record whose pgid is alive but whose identity differs is not signalled and is reported as stale; a matching record is terminated as before; a record without an identity file (written before this change) is treated as stale, never signalled (SKP-007, IMP-009 accepted).
- [ ] The identity is re-read immediately before `TERM` and again before `KILL`; the residual window between the read and the signal is documented in the lib header as the pid-namespace limit (SKP-007 accepted in part: the race cannot be closed with numeric pgids).
- [ ] Existing supervisor tests stay green; the record format change is documented in the lib header.
**Dependencies:** none.

> Sources: `evals/harness/lib/batch-supervisor.sh:31, 44-45, 228-240`; PR #1292 comment 6386296457 (LOW, supervisor reclaim)

### FR-8: The external seeder never diffs an unfetched blob (bd-kdk3l)
**Priority:** Should Have
**Description:** The seeder selects blobs from tree metadata with bounds — "the blobs to fetch … (default 5000) and --max-bytes (default 200M) — no blob has been fetched yet" (seed-corpus-from-external.sh:40-42) — fetches them in one batch (:43-44), then computes the fix diff (:50). The Bridgebuilder found the fix diff computed over entries whose blobs were never fetched (LOW 0.4) ([ASSUMPTION fact] the exact code path is confirmed in the SDD read). The seeder must fetch every blob the fix diff needs within the bounds, or refuse naming the omitted paths.
**Acceptance Criteria:**
- [ ] A fixture repository reachable over `file://` (no network) exercises the real bounded fetch and diff creation: a fix touching a file outside the PR's changed set is fetched within the bounds; one outside the bounds refuses with the path named; no partial diff is written (IMP-010 accepted). The existing dry-run refusal tests stay.
- [ ] Existing seeder tests (refusals, leakage, SHA256SUMS) stay green.
**Dependencies:** none.

> Sources: `evals/harness/seed-corpus-from-external.sh:11-67`; PR #1292 comment 6386296457 (LOW, seeder)

### FR-9: The publish orchestrator's exit-code contract holds, and its canonicaliser's float policy is decided (bd-4pv1j)
**Priority:** Should Have
**Description:** The header defines "2 - Refusal before any write (digest, schema, v1, ancestry, tag identity, …)" (post-merge-orchestrator.sh:47), yet `phase_tag` (:1062) returns 2 for an existing tag with another identity after `publish_candidate` has written the PUBLISHING state and the progress file (Bridgebuilder LOW 0.4). The stdlib canonicaliser used where `rfc8785` is absent — "the stdlib form below is used" (:1545), `jcs_stdlib_file` (:1558) — refuses floats, so `--generate` on a CI host depends on `prepared_state` carrying none (SPECULATION 0.3) ([ASSUMPTION fact] the float refusal is taken from the finding; the SDD confirms it at :1558-1600). Both tag identity checks move into the pre-write validation — the local one and the remote one, since `git ls-remote` needs no write (IMP-014 opus accepted) — so an existing tag of another identity refuses with exit 2 before any state is written; `phase_tag` keeps its checks for the race between validation and the tag push and returns 1 there (a step failed after a write). The float policy is decided and enforced independently of whether `rfc8785` is installed (IMP-012 gpt accepted): `prepared_state` numbers are integers with no fraction and no exponent, |n| ≤ 2^53−1, −0 refused; `--generate` refuses a non-integer number before canonicalisation with exit 2 (nothing written — the § 5.4 contract), and the publish-time validation enforces the same domain on the candidate (exit 2). The question whether any current field carries a float is resolved: the rc.8 candidate holds 10 integers and no float (SDD Q-3). A failed or timed-out remote tag lookup during pre-write validation is `remote unreachable, identity unverified` and exits 2; tag identity is the orchestrator's existing annotated-tag rule, so a lightweight tag of the same name is a refusal.
**Acceptance Criteria:**
- [ ] A bats fixture with a pre-existing local or remote tag of another identity, a lightweight tag, or an unreachable remote refuses with exit 2 and no state file written; a tag that appears between validation and the tag phase exits 1 with the state FAILED; a re-run with an identical-identity tag skips the push and continues.
- [ ] A bats test pins the float policy: `--generate` refuses a state containing a float (also nested), an exponent form or `−0` with exit 2 and the JSON path named, with and without `rfc8785` installed; the same value in a candidate refuses at `--publish` with exit 2; the integer domain canonicalises identically on both paths; the real rc.8 candidate passes.
- [ ] The header's exit-code table stays true.
**Dependencies:** none.

> Sources: `.claude/scripts/post-merge-orchestrator.sh:44-49, 1062, 1543-1558, 2063`; PR #1292 comments 6386296457 (LOW, phase_tag) and 6386303901 (F-009)

### FR-10: Ship — one PR per sprint, a non-degraded Bridgebuilder verdict, record, archive, no release
**Priority:** Must Have
**Description:** The sprint ships as its own PR (DEC-0960): review and audit APPROVED on the PR head, the Bridgebuilder round from the merged skill reaching a verdict with no `degraded_reason`, every required check green on the exact head, admin merge with a merge commit, `record-branch.sh` stage over the merge, `archive-cycle.sh`; CHANGELOG `[Unreleased]` carries every fix; no tag or release ([ASSUMPTION decision] (DEC-0967)).
**Acceptance Criteria:**
- [ ] The PR's Bridgebuilder summary has no `degraded_reason` and its verdict equals the consensus block's; if coverage would be cut, the PR is split before merge.
- [ ] Record branch `record/cycle-134-post-ship-fixes` built by `record-branch.sh` with the a2a sprint directory; archive directory with the `[Unreleased]` entries and a README.
- [ ] No tag `v2.0.0-rc.9` exists at the end of the cycle; the post-merge candidate for the merge is left unpublished.
**Dependencies:** FR-1, FR-2, FR-3 (Must Have; the merge gate); FR-4 … FR-9 as landed — a slipped Should Have is re-filed on its bead and named in the sprint report, and G-1 is reported as partially met (IMP-013 gpt accepted).
**Split fallback (IMP-014 gpt accepted):** if the Bridgebuilder's coverage record would omit a reviewable file, the sprint PR is split along the implementer areas (A validator, B mount rules, C publish path, D harness libraries) into stacked PRs, each with its own round, review and audit binding; the record stage is built over the last merge.

> Sources: cycle-134-brief.md § Release, § Standing rules; DEC-0960, DEC-0967; `grimoires/loa/reports/release-2.0.0-rc.8-operator-steps.md` steps 9-15 (the ship recipe, minus the publish)

---

## Non-Functional Requirements

### Performance

`took-effect.sh` keeps its per-run cost (one pass over the transcripts and process samples); the independent hash walk of FR-4 is bounded by the HOME manifest (hundreds of files) and runs once per session.

### Security

- The validator's new checks fail closed: a missing identity, a missing transcript or an unverifiable HOME copy is a failure, never a skip.
- The reclaim identity check (FR-7) prevents signalling a reused pid; the seeder (FR-8) keeps its refusal-before-write discipline.
- System Zone writes only under the bounded zone marker; the secret scan before every public push; the keys in the operator's dotfiles are never read, echoed or committed.

### Reliability

Every fix ships with a fixture that fails before and passes after; the two recorded smoke evidence trees are the regression corpus for the validator (DEC-0970); nothing lands red.

### Compliance

The refusal list of cycle-133 stands: no force-push, no write to `main` outside a merge, no tag or branch deletion, no bypass of red CI or an unresolved Bridgebuilder blocker, no credential provisioning, no new release.

### Authorization basis and refusal list

The operator's instruction of 2026-10-25 (brief § The operator's instruction) authorises the cycle through the golden path; the System Zone authorization of cycle-133 (DEC-0824: bounded marker, checksums and REPO-MAP regenerated) carries over for `.claude/` and `.github/` writes.

> Sources: cycle-134-brief.md § Standing rules; DEC-0824, DEC-0960, DEC-0967, DEC-0970

---

## User Experience

### Key User Flows

1. **Measurement lead validates a session.** `took-effect.sh <run>` → `oracle_closed` evidence line names each phase's transcript, init event, hook identities within the pinned configuration, and whether the HOME integrity walk was independent.
2. **Operator publishes an rc.** `--publish` → tag, release, ledger fast-forward → the post-merge pipeline on the ledger push is green or skipped; a pre-existing tag of another identity refuses with exit 2 before any write.
3. **Lead ships the sprint.** PR → Bridgebuilder round (non-degraded) → CI → admin merge → record branch → archive; no publish.

### Interaction Patterns

Evidence lines over booleans: every rule says what it checked and how (as the existing clauses do).

### Accessibility Requirements

Not applicable (command-line tooling and CI); output stays plain text.

> Sources: `evals/harness/took-effect.sh:76-107` (the clause evidence format); `grimoires/loa/reports/release-2.0.0-rc.8-operator-steps.md`

---

## Technical Considerations

### Architecture (for the SDD)

Nine local changes in five areas: the validator (`evals/harness/took-effect.sh`: FR-1, FR-2, FR-4), the mount transform (`evals/harness/lib/sandbox-mount.sh`: FR-5), the harness libraries (`egress-proxy.sh` + `Dockerfile.proxy`, `batch-supervisor.sh`, `seed-corpus-from-external.sh`: FR-6 … FR-8), the publish path (`.github/workflows/post-merge.yml`, `.claude/scripts/classify-merge-pr.sh`, `.claude/scripts/post-merge-orchestrator.sh`: FR-3, FR-9). The SDD decides per area: the hook identity source in Claude Code's stream-json `hook_started` events; the transcript completeness rule; the independent-walk input; the R3/R5 narrowing tables; the pid-limit direction; the `.jobs/` identity fields; the seeder's fetch-or-refuse; the classify guard mechanism and the float policy.

### System Zone authorization (explicit, cycle-level)

`.claude/scripts/classify-merge-pr.sh`, `.claude/scripts/post-merge-orchestrator.sh` and `.github/workflows/post-merge.yml` are System Zone; their edits run under the bounded marker (`.run/zone-guard-authorization.json`, scope framework, reason, expiry ≤ 2 h) with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824).

### Integrations

GitHub Actions (post-merge.yml), the Bridgebuilder (the round on the sprint PR), `record-branch.sh`, `archive-cycle.sh`.

### Dependencies

`npx --no-install bats` on this host; Docker only for the egress bats that already require it (the pid-limit assertion reads files and needs no container).

### Technical Constraints

No live model calls by implementers; the recorded smoke evidence trees are read-only inputs; the cycle-132/133 records are untouched.

> Sources: cycle-134-brief.md § Scope, § Standing rules; the file:line reads in Appendix B

---

## Scope & Prioritization

### In Scope (MVP — this cycle)

FR-1 … FR-10 ([ASSUMPTION decision] (DEC-0966)).

### In Scope (Future Iterations)

bd-oik13 (chunked Bridgebuilder review); the cycle-133 carry-overs bd-ci4g9, bd-yv0d4, bd-nzblj, bd-ivmtk, bd-yt1k1, bd-afz2p, bd-znx6q, bd-868s1, bd-vlgk1, bd-mopz7, bd-aun97; the home-scope claim (FR-10 of cycle-133) once a smoke at a recorded pin passes.

### Out of Scope

Any measurement run; any change to the cycle-132 or cycle-133 records; a new release candidate (DEC-0967); re-opening the audited rc.8 head.

### Priority order under time pressure

FR-1, FR-2, FR-3 first (the Must Haves: the validator's two directions and the red pipeline); FR-9 next (the publish contract); FR-4 … FR-8 then; FR-10 closes.

### Release-blocking status

Must Have requirements (FR-1, FR-2, FR-3, FR-10) block the cycle's merge. A slipped Should Have (FR-4 … FR-9) is re-filed on its bead with a current status and named in the sprint report; G-1 is then reported as partially met with the parts named.

> Sources: cycle-134-brief.md § Scope, § Out of scope; DEC-0966, DEC-0967

---

## Success Criteria

| Goal | Criterion | Evidence |
|------|-----------|----------|
| G-1 | 9 beads closed with commit and test | `br show` per bead; the sprint report |
| G-2 | validator right in both directions | the FR-1/FR-2/FR-4 fixtures; `took-effect.sh` over c133-smoke run-1 and run-2 → the recorded verdicts (DEC-0970) |
| G-3 | pipeline green on a push without a PR | the FR-3 fixture; the next publish's ledger push (after the cycle; recorded on KF-063) |
| G-4 | non-degraded Bridgebuilder verdict on the sprint PR | the PR's Bridgebuilder summary (no `degraded_reason`; verdict = consensus block) |
| G-5 | green suites, spend ≤ USD 20 | CI check-runs on the merged head; the cost ledger rows of the cycle |

> Sources: § Goals & Success Metrics; DEC-0969, DEC-0970

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Claude Code's `hook_started` event carries no stable hook identity | medium | FR-1 falls back to a per-invocation bound | the SDD reads the stream-json shape from the recorded smoke transcripts' event fields (not available in the report trees) or the harness fixtures; the fallback rule is stated and tested |
| Narrowing R3/R5 breaks a home-scope rewrite the mount relies on | medium | the home-scope bats fail | the before/after corpus diff per rule with every difference explained; the negative control stays |
| The classify guard hides a real cycle merge | low | a release candidate is not prepared | the guard keys on an empty PR number, not on the subject alone; a fixture for a real cycle merge subject with a PR number stays `cycle` |
| The Bridgebuilder round degrades again | low | G-4 not met | the PR is code and tests only (well under 50 files); evidence stays out of the PR |
| The float policy choice breaks CI generation | low | the post-merge candidate fails | the policy is tested both ways before the choice lands |

> Sources: § Functional Requirements; DEC-0960; PR #1292 comment 6386303901 (coverage record)

---

## Timeline & Milestones

| Milestone | Deliverable | Gate |
|-----------|-------------|------|
| Sprint 1 (276) | FR-1 … FR-9 with tests; CHANGELOG `[Unreleased]`; the smoke-evidence regression | review + audit APPROVED; bats/pytest green |
| Ship | PR → Bridgebuilder (non-degraded) → CI → admin merge → record → archive | G-4, G-5; no release |

Expected wall-clock: one sprint of one day with up to four Opus implementers in parallel (A validator, B mount rules, C publish path, D harness libraries); the sprint plan decides the split.

> Sources: cycle-134-brief.md § Sprint breakdown

---

## Appendix A — Decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1 | Scope: the nine advised beads; the carry-overs and bd-oik13 out | DEC-0966 (restates DEC-0966, the kickoff row sourced to the brief) |
| D-2 | No new release candidate this cycle | DEC-0967 (restates DEC-0967, the kickoff row sourced to the brief) |
| D-3 | Grounding by direct file:line reads; no /ride | DEC-0968 (restates DEC-0968, the kickoff row sourced to the brief) |
| D-4 | Spend cap USD 20 (Bridgebuilder only) | DEC-0969 (restates DEC-0969, the kickoff row sourced to the brief) |
| D-5 | took-effect acceptance = fixtures both ways + the recorded smoke evidence re-validates | DEC-0970 (restates DEC-0970, the kickoff row sourced to the brief) |

Design rows (SDD § 11.D): DEC-0971 … DEC-0986. Standing decisions carried over: DEC-0824 (System Zone marker), DEC-0957 (G-2 reading), DEC-0960 (per-sprint PRs). The rows of this cycle stay `proposed` until the operator confirms them (`/decisions confirm --cycle cycle-134-post-ship-fixes --all`, offered at the cycle close as the first operator to-do, as cycle-133's were); the autonomous run never confirms its own rows (IMP-018 accepted).

> Sources: `grimoires/loa/decisions.yaml` DEC-0966 … DEC-0970 (PRD rows, phase discovery, cycle `cycle-134-post-ship-fixes`, proposed; each restates a kickoff row DEC-0966 … DEC-0970 sourced to the brief)

---

## Appendix B — Grounding reads

| Requirement | File:line | Quote |
|---|---|---|
| FR-1 | `evals/harness/took-effect.sh:625` | `hook_counts[k] = hook_counts.get(k, 0) + 1` |
| FR-1 | `evals/harness/took-effect.sh:1112-1113` | `if cnt > decl.get(evn, 0): fail("g", "-", "%d %s hook(s) ran in %s; the pinned user settings declare %d (home_hook_counts)" …)` |
| FR-2 | `evals/harness/took-effect.sh:601` | `tfiles = sorted(n for n in (os.listdir(tdir) if os.path.isdir(tdir) else []) if re.match(r"^events-[A-Za-z0-9_-]+\.jsonl$", n))` |
| FR-2 | `evals/harness/took-effect.sh:868-870` | `psf = os.path.join(run, "meta", "ps-%s.txt" % lab)` … `fail("g", "-", "no process capture for %s (meta/ps-%s.txt)" …)` |
| FR-3 | `.github/workflows/post-merge.yml:110` | `if: needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''` |
| FR-3 | `.github/workflows/post-merge.yml:182` | `if: needs.classify.outputs.pr_type == 'cycle'` |
| FR-3 | run 40112013975 | `pr_type=cycle` … `PM_PR_NUMBER:` (empty) … `ERROR: --pr is required` |
| FR-4 | `evals/harness/took-effect.sh:373-374` | `local hi="$R/meta/home-integrity.json"` … `EVID="home-scope: no meta/home-integrity.json (the HOME framework was never checked)"` |
| FR-4 | `evals/harness/pipeline-run.sh:191` | `before the HOME is deleted, meta/home-integrity.json checks the HOME framework against its manifest` |
| FR-5 | `evals/harness/lib/sandbox-mount.sh:1496` | `R3 = re.compile(r"(?<![A-Za-z0-9_./$~{}\\-])\.claude/")` |
| FR-5 | `evals/harness/lib/sandbox-mount.sh:1503` | `R5 = re.compile(r"(?<!/ )(?<!/)(['\"])(\.claude/[A-Za-z0-9_./-]*)\1")` |
| FR-6 | `evals/harness/lib/egress-proxy.sh:205` | `--security-opt no-new-privileges --pids-limit 128 --memory 256m` |
| FR-6 | `evals/harness/Dockerfile.proxy:101` | `MaxClients 200` |
| FR-7 | `evals/harness/lib/batch-supervisor.sh:237-238` | `Same boot: the recorded runner (identity-checked) and every .jobs/ group still alive are terminated` |
| FR-8 | `evals/harness/seed-corpus-from-external.sh:40-44` | `the blobs to fetch … — no blob has been fetched yet` … `the blobs are fetched in one batch` |
| FR-9 | `.claude/scripts/post-merge-orchestrator.sh:47` | `2 - Refusal before any write (digest, schema, v1, ancestry, tag identity,` |
| FR-9 | `.claude/scripts/post-merge-orchestrator.sh:1545, 1558` | `the stdlib form below is used` … `jcs_stdlib_file() {` |

> Sources: direct reads on 2026-10-25 at branch head `5e7219a3` (the files are unchanged from `main 1fc6d150`)


---

## Appendix C — Flatline PRD review dispositions (1.0 → 1.1)

Two voices (codex-headless, claude-headless), cross-scoring degraded (KF-041 shape), 0 high-consensus items, 37 medium items, 7 skeptic blockers. Every item was read; the dispositions:

| Item | Concern (short) | Disposition |
|---|---|---|
| SKP-001 (both voices) | a count bound cannot establish that a hook belongs to the pinned configuration; the identity may not exist | **Accepted.** The real event shape was read from retained transcripts (`hook_name` = `<event>:<matcher>`); FR-1 now requires group identity (a) and the count rules (b)+(c) together, and brings the evidence producer into scope |
| SKP-002 (gpt) | truncation at a valid line boundary is not detected | **Accepted.** FR-2 requires the final `result` event |
| SKP-002 (opus) | the recorded report trees cannot replay clause (g) | **Accepted.** FR-1/FR-2/FR-4 acceptance runs on the retained batch directories (DEC-0980 amends DEC-0970); the report trees' contents are stated |
| SKP-004, SKP-005 | record-only integrity contradicts "unverifiable must fail"; metadata cannot prove bytes | **Accepted.** FR-4 defines the two passing modes and the failing one; the per-file limit without a retained HOME is stated |
| SKP-007 | check-then-signal race; legacy records | **Accepted in part.** Re-read before TERM and KILL; legacy records stale; the residual numeric-pgid window is documented, not closable |
| IMP-001/016 (gpt), IMP-016 (opus) | define hook identity; per-invocation bound in addition | **Accepted** (FR-1) |
| IMP-002/003 (gpt), IMP-003 (opus) | HOME verification artefacts; the evidence producer | **Accepted** (FR-4, FR-1) |
| IMP-004 (gpt), IMP-001 (opus) | inventory the recorded trees | **Accepted** (FR-1 AC; D-4.2) |
| IMP-005 (gpt) | reject malformed JSON anywhere | **Partially accepted:** the result requirement covers tail loss; interior loss cannot occur in an append-only capture; skipped oversize lines are counted |
| IMP-006 (gpt), IMP-011 (opus) | authoritative `labels_run`; non-session phases | **Accepted:** `meta/pipeline.json` non-skipped phases; every executed label is a Claude Code session here |
| IMP-007 (gpt) | push without PR vs failed lookup | **Accepted** (FR-3 AC) |
| IMP-008 (gpt) | live confirmation separate from acceptance | **Accepted:** FR-3 AC already separates the fixture (acceptance) from the next publish (recorded on KF-063 after the fact) |
| IMP-009 (gpt) | legacy job records, leader exited | **Accepted** (FR-7 AC) |
| IMP-010 (gpt) | a non-dry-run seeder fixture | **Accepted** (`file://` fixture repository) |
| IMP-011/012 (gpt) | write boundary; numeric policy independent of `rfc8785` | **Accepted** (FR-9) |
| IMP-013 (gpt) | Should-Have deferral vs FR-10 dependency | **Accepted** (FR-10 dependencies restated) |
| IMP-014 (gpt) | fallback if the PR must be split | **Accepted** (FR-10 split fallback) |
| IMP-015/017 | the proxy's base task allowance | **Accepted** (observed once, pinned as a constant) |
| IMP-012 (opus) | a concrete source of a real `hook_started` event | **Accepted:** retained cycle-130 smoke transcripts (`~/.cache/loa/cycle-130/smoke/*/transcripts`) and the SDK message types; the matcher-less grammar is confirmed on a one-turn session (FR-1 AC) |
| IMP-013 (opus) | traceability of all 17 findings | **Accepted** (Appendix D) |
| IMP-014 (opus) | remote tag identity check pre-write too | **Accepted** (FR-9) |
| IMP-015 (opus) | name the took-effect test files | **Accepted** in the SDD § 7.3 (`evals/tests/took-effect-{hooks,transcripts,integrity}.bats`) |
| IMP-018 (opus) | when proposed rows are confirmed | **Accepted** (Appendix A) |
| IMP-019 (opus) | zone-marker re-issue across the sprint | **Accepted** (Constraints) |
| IMP-020 (opus) | other workflows on push to `main` | **Accepted** (FR-3 AC) |
| IMP-021 (opus) | what counts toward USD 20 | **Accepted** (Constraints) |
| remaining medium items (restatements of the above, or wording) | — | **Noted;** no further change |

> Sources: `grimoires/loa/a2a/flatline/cycle-134-prd-review.json` (blockers, medium_value, raw_reviews); the Flatline SDD review's dispositions are in `grimoires/loa/sdd.md` § 11.G (`cycle-134-sdd-review.json`)

---

## Appendix D — Bridgebuilder round 2 findings: traceability

| Finding (PR #1292 round 2) | Severity | Disposition | Where |
|---|---|---|---|
| F-001 hook executions vs configured count | MEDIUM 0.99 | fix | FR-1, bd-bex39 |
| F-002 missing phase transcript passes | MEDIUM 0.98 | fix | FR-2, bd-k3dia |
| integrity_clean trusts the driver record | LOW 0.45 | fix | FR-4, bd-htzy2 |
| R5 rewrites literals broadly; verify skips R5 | LOW 0.45 | fix (narrowing); the verify claim is corrected in the SDD (verify round-trips R5) | FR-5, bd-kgfh5 |
| R3 rewrites every relative mention | LOW 0.35 | fix (narrowing) | FR-5, bd-kgfh5 |
| sidecar pids limit below MaxClients | LOW 0.3 | fix | FR-6, bd-1br0v |
| supervisor reclaim without identity check | LOW 0.35 | fix | FR-7, bd-ruo5b |
| seeder diffs unfetched blobs | LOW 0.4 | fix | FR-8, bd-kdk3l |
| phase_tag exits 2 after a write | LOW 0.4 | fix | FR-9, bd-4pv1j |
| F-009 stdlib JCS fallback and floats | SPECULATION 0.3 | fix (policy) | FR-9, bd-4pv1j |
| F-008 literal control characters in jq programs | SPECULATION 0.1 | rejected with evidence (`\u0000` escapes on disk) | PR #1292 triage comment; DEC-0958 |
| F-010 one 374-file PR | REFRAME 0.6 | decided | DEC-0960; bd-oik13 (out of scope here) |
| seven PRAISE items | — | noted | PR #1292 triage comment |

> Sources: PR #1292 comments 6386303901, 6386296457, 6386296833, 6386491267; `grimoires/loa/decisions.yaml` DEC-0957, DEC-0958, DEC-0960
