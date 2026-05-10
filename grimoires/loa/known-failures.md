# Known Failures — Things We Tried That Didn't Work

> **Read this file at session start.** This is the operational log of degradation
> patterns the framework has hit and the workarounds we've tried. Each entry
> records what *didn't* fix the problem so future agents don't re-attempt the
> same dead-ends.
>
> **Append-only.** Don't edit existing entries except to (a) increment
> `recurrence_count` when an entry's failure class is observed again, (b) add
> rows to `attempts:` when new fixes are tried, or (c) flip `status` from
> `OPEN` to `RESOLVED` with a closing-evidence ref. Historical inaccuracy
> defeats the purpose.

## Schema

Each entry uses the following structured fields. Think of it as a YAML-style
record embedded in Markdown for human + agent readability.

```
## KF-{NNN}: {short title}

**Status**: OPEN | RESOLVED | DEGRADED-ACCEPTED
**Feature**: {affected substrate or skill}
**Symptom**: {one-line operator-visible failure}
**First observed**: {YYYY-MM-DD} ({cycle / sprint / commit context})
**Recurrence count**: {integer}
**Current workaround**: {what we do today instead}
**Upstream issue**: {GitHub issue # or "not filed"}
**Related visions / lore**: {vision-XXX, feedback_*.md links}

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| YYYY-MM-DD | … | DID NOT WORK / WORKAROUND-AT-LIMIT / RESOLVED | commit SHA / PR# / run ID |

### Reading guide

{1-3 sentences explaining what a future agent should do when they observe
this symptom — typically "apply current workaround, don't retry the listed
attempts, route improvements through {Issue #}"}.
```

The **`Recurrence count`** field is load-bearing — it tells future agents
how many times the same failure class has been independently observed.
A recurrence_count ≥ 3 means the failure is structural; stop re-attempting
prior fixes; route through the upstream issue.

The **`Evidence`** column protects against demotion-by-relabel at the
documentation layer (see vision-024 / `feedback_zero_blocker_demotion_pattern.md`)
— commit SHAs, PR numbers, and run IDs let the next agent verify what was
actually tried, not just what someone *said* was tried.

## Index

| ID | Status | Feature | Recurrence |
|----|--------|---------|------------|
| [KF-001](#kf-001-bridgebuilder-cross-model-provider-network-failures-non-openai) | OPEN (STRUCTURAL — upstream filed) | bridgebuilder cross-model dissent | 3 |
| [KF-002](#kf-002-adversarial-reviewsh-empty-content-on-review-type-prompts-at-scale) | DEGRADED-ACCEPTED | adversarial-review.sh review-type | 3 |
| [KF-003](#kf-003-gpt-55-pro-empty-content-on-27k-input-reasoning-class-prompts) | RESOLVED (model swap) | flatline_protocol code review | 1 |
| [KF-004](#kf-004-validate_finding-silent-rejection-of-dissenter-payloads) | OPEN (upstream filed) | adversarial-review.sh validation pipeline | ≥4 |
| [KF-005](#kf-005-beads_rust-021-migration-blocks-task-tracking) | DEGRADED-ACCEPTED | beads_rust task tracking | many |

---

## KF-001: bridgebuilder cross-model provider network failures (non-OpenAI)

**Status**: OPEN — STRUCTURAL (upstream filed)
**Feature**: `/bridgebuilder` cross-model dissent (`anthropic` + `google` providers via `.claude/skills/bridgebuilder-review/resources/adapters/`)
**Symptom**: Both `anthropic/claude-opus-4-7` and `google/gemini-3.1-pro-preview` fail with `TypeError: fetch failed; cause=AggregateError` (Anthropic) and `cause=SocketError: other side closed` (Google) across all 3 retry attempts. OpenAI/`gpt-5.5-pro` succeeds. BB falls back to "stats-only summary" because the enrichment writer (also Anthropic) fails the same way. Headline reports `N findings — X consensus, Y disputed` but the consensus scoring runs over a single model's output. The pattern persisted across 3 independent BB invocations within ~60 min wall-clock on the same PR + machine; not a transient provider outage.
**First observed**: 2026-05-10 (cycle-102 sprint-1D BB iter-1 on PR #826)
**Recurrence count**: 3 (iter-1 + iter-2 + iter-3 on PR #826, all within ~60 min on the same operator machine)
**Current workaround**: Document degradation explicitly; defer cross-model BB to post-merge; treat single-model findings under elevated `single-model-true-positive-in-DISPUTED` scrutiny per Sprint 1A iter-5 lore + `feedback_zero_blocker_demotion_pattern.md`. Do NOT call REFRAME plateau on single-model trajectory — REFRAME requires ≥2 models naming the same architectural seam. **Per the recurrence-≥3 rule, stop retrying — wait on upstream fix before re-attempting.**
**Upstream issue**: [#827](https://github.com/0xHoneyJar/loa/issues/827) (filed 2026-05-10 during cycle-102 sprint-1D close, after the recurrence-≥3 rule triggered)
**Related visions / lore**: vision-024 substrate-speaks-twice (the BB infrastructure that articulates the bug class itself failed to articulate at the cross-model level — third recursive-dogfood manifestation in cycle-102); `feedback_bb_api_unavailability_plateau.md`; `feedback_zero_blocker_demotion_pattern.md`

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-10 04:20Z | iter-1 normal invocation | DID NOT WORK — anthropic + google 3/3 attempts failed; openai succeeded (7616 in / 21198 out) | run `bridgebuilder-20260510T042044-3f1c` / PR #826 comment 4414476 |
| 2026-05-10 04:35Z | iter-2 after 7-min gap + mitigation commit `6bfcae21` | DID NOT WORK — same failure mode; openai succeeded (8752 in / 15629 out) | run `bridgebuilder-20260510T043516-5fb8` / PR #826 comment 4414587 |
| 2026-05-10 05:11Z | iter-3 after 36-min gap + framing-correction commit `a9591b28` (operator-requested retry to get all 3 models) | DID NOT WORK — same failure mode; openai succeeded (30067 in / 3069 out — note different output size from same model on same PR) | run `bridgebuilder-20260510T051139-fe00` |

### Reading guide

**RECURRENCE COUNT IS 3 — STRUCTURAL.** Do NOT re-attempt BB cross-model on
this machine until upstream resolves. The pattern is:

- Anthropic + Google fail consistently with Node `fetch failed` / `SocketError`
  errors at request-size 28KB+ (iter-1) through 35KB+ (iter-3)
- OpenAI succeeds at the same request sizes
- Three independent invocations across ~60 min wall-clock; not a transient outage
- Most likely root causes (untested, for upstream triage):
  (a) Loa-side TS adapter config issue specific to `anthropic` + `google`
      endpoints (request format, header, timeout)
  (b) Operator machine network configuration (DNS, IPv6, firewall) blocking
      api.anthropic.com + generativelanguage.googleapis.com but not
      api.openai.com
  (c) Provider-side rate limiting per-account that returns RST instead of 429

If your BB run shows `1 of 3` or `2 of 3` provider success: do NOT call
plateau, do NOT trust the "consensus" / "disputed" headlines (they're
single-model output filtered through a multi-model scorer). Document the
degraded-mode result honestly. **The recurrence-≥3 rule says stop
retrying** — accept single-model BB as advisory-only, route findings as
elevated-DISPUTED-scrutiny per `feedback_zero_blocker_demotion_pattern.md`,
and wait for upstream fix. Increment this entry's recurrence count and
add an `Attempts` row when the failure is observed again with new
evidence (different machine, different network, different time-of-day).

---

## KF-002: adversarial-review.sh empty-content on review-type prompts at scale

**Status**: DEGRADED-ACCEPTED (workaround in place; structural fix pending)
**Feature**: `.claude/scripts/adversarial-review.sh --type review` (Phase 2.5 of `/review-sprint`)
**Symptom**: Reasoning-class models (gpt-5.5-pro, claude-opus-4-7) return empty content for review-type prompts at >27K input (gpt-5.5-pro) or >40K input (claude-opus-4-7). 3 retries all empty. The script writes `status: api_failure` to the output JSON, the COMPLETED gate accepts api_failure as a "legitimate completion record," and Sprint audit passes despite no actual cross-model dissent applied. **Audit-type prompts at the same scale succeed** — the failure is prompt-structure-dependent, not pure input-size.
**First observed**: 2026-05-09 (cycle-102 sprint-1A audit on PR #803)
**Recurrence count**: 3+ (sprint-1A audit, sprint-1B audit, sprint-1B BB iter-6 — see NOTES.md 2026-05-09 Decision Log: T1B.4 ROOT-CAUSE REFRAME)
**Current workaround**: Sprint 1B T1B.4 swapped `flatline_protocol.{code_review,security_audit}.model` from `gpt-5.5-pro` to `claude-opus-4-7`. Upstream Issue #812 proposes the same default for all Loa users. **Note: opus has the SAME bug at higher input threshold** (Issue #823 / vision-024) — the swap routes around the bug at one scale but the bug class is fractal, not solved.
**Upstream issue**: [#812](https://github.com/0xHoneyJar/loa/issues/812) (model swap proposal), [#823](https://github.com/0xHoneyJar/loa/issues/823) (opus empty-content at >40K)
**Related visions / lore**: vision-019 Bridgebuilder's Lament, vision-023 Fractal Recursion ("the very gate built to detect silent degradation experienced silent degradation, of the same bug class the gate was built to detect"), vision-024 Substrate Speaks Twice, vision-025 Substrate Becomes the Answer (the routing-around-not-fixing-through pattern)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | Bump default `max_output_tokens=32000` for `gpt-5.5-pro` (Sprint 1A T1.9) | WORKAROUND-AT-LIMIT — verified at 10K input, FAILED at 27K input | commit `dd54fe9c` / NOTES.md 2026-05-09 Decision Log |
| 2026-05-09 | Sprint 1B T1B.4 model swap to `claude-opus-4-7` | WORKAROUND-AT-LIMIT — works to ~40K input, fails at >40K (Issue #823) | commit `0872780c` |
| 2026-05-09 | Audit-type at 47K input (test if scale alone or prompt-structure) | RESOLVED FOR AUDIT-TYPE — audit-type at 47K succeeded | NOTES.md 2026-05-09 |
| not tried | Adaptive truncation (lower review-type input cap to ~16K) | — | proposed in vision-023 §"What this teaches" |
| not tried | Drop `reasoning.effort` to `low` for adversarial-review's task class | — | proposed in NOTES.md 2026-05-09 Decision Log |

### Reading guide

If your `/review-sprint` Phase 2.5 reports `status: api_failure` with
empty content from the configured reviewer: don't retry the same model
at the same input scale — it's the documented bug. Either (a) reduce
input size via aggressive truncation, (b) swap reviewer to a model not
on the empty-content trajectory at your scale, or (c) accept the
degradation and apply manual cross-model dissent via subagent dispatch.
Do NOT add the failing model to a retry-loop — the model returns 200 OK
with empty content, retries don't help.

---

## KF-003: gpt-5.5-pro empty-content on ≥27K-input reasoning-class prompts

**Status**: RESOLVED via swap (KF-002 workaround); kept here for reproduction reference
**Feature**: any cheval invocation routing to `gpt-5.5-pro` with `reasoning.effort: medium` and input ≥ 27K tokens
**Symptom**: Provider returns 200 OK with empty `output` field; cheval treats as `INVALID_RESPONSE` exit code 5; retries return same.
**First observed**: 2026-05-09 (cycle-102 sprint-1B kickoff during T1B.4 root-cause analysis)
**Recurrence count**: 1 (originally believed scale-dependent within reasoning models; subsequent observation showed the bug class extends to opus at higher threshold, see KF-002)
**Current workaround**: Resolved by Sprint 1B T1B.4 model swap. cheval's per-model `max_output_tokens` lookup landed at T1.9 (Sprint 1A) addresses the budget-side; the empty-content failure mode is independent of budget.
**Upstream issue**: [#812](https://github.com/0xHoneyJar/loa/issues/812)
**Related visions / lore**: vision-019, vision-023; `feedback_loa_monkeypatch_always_upstream.md` (this entry exemplifies the "every project-local fix becomes upstream-issue-shaped" rule)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | Verify T1.9 `max_output_tokens=32000` lookup applies | RESOLVED-AT-10K — bug class is empty-content not budget; lookup is correct but doesn't fix the deeper layer | sprint-bug-143 / NOTES.md 2026-05-09 Decision Log |
| 2026-05-09 | Switch to `claude-opus-4-7` per T1B.4 | WORKAROUND HOLDS at this scale — opus has no empty-content bug for inputs <40K | commit `0872780c` |

### Reading guide

If you observe empty-content responses from `gpt-5.5-pro` at any scale:
this is the upstream-known bug class. Do NOT retry the same call. Do NOT
bump `max_output_tokens` further. Swap to a different model for the task
class, or accept the failure and document. The fix is structural at the
provider, not at our integration.

---

## KF-004: validate_finding silent rejection of dissenter payloads

**Status**: OPEN (upstream filed)
**Feature**: `.claude/scripts/adversarial-review.sh` validation pipeline
**Symptom**: When adversarial-review.sh receives findings from the dissenter that don't conform to the strict schema (e.g., missing required field, out-of-enum severity, malformed `anchor_type`), the validator emits `[adversarial-review] Rejected invalid finding at index N` to stderr and **drops the payload entirely** — the rejected finding's content is unrecoverable. The output JSON shows fewer findings than the dissenter actually produced; the rejected payloads never reach the consensus scorer or the operator. Headline counts are misleadingly low.
**First observed**: 2026-05-09 mid-session (caught by operator's "i am always suspicious when there are 0" interjection during BB iter-2 of sprint-1B PR #813)
**Recurrence count**: ≥4 across cycle-102 (sprint-1A iter-5, sprint-1B BB iter-2, sprint-1D /audit-sprint adversarial-audit returned 0 findings + 5 silent rejections, sprint-1D BB iter-1 + iter-2)
**Current workaround**: Apply suspicion lens manually whenever adversarial-review.sh reports "0 findings" or "low N findings" — re-read the substrate the headline is supposed to summarize, walk the most likely concerns the rejected findings could have raised, route them as documented limitations or backlog inputs.
**Upstream issue**: [#814](https://github.com/0xHoneyJar/loa/issues/814)
**Related visions / lore**: vision-024 substrate-speaks-twice (this is the third consensus-classification failure mode — single-model security true-positive in DISPUTED + demotion-by-relabel + silent-rejection); `feedback_zero_blocker_demotion_pattern.md`

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | File upstream Issue #814 to dump rejected payloads to a sidecar JSONL | OUTSTANDING — fix not yet shipped | [#814](https://github.com/0xHoneyJar/loa/issues/814) |

### Reading guide

When `adversarial-review.sh` output reports a low or zero finding count
AND its stderr contains `Rejected invalid finding at index N` lines:
the headline is misleading. The dissenter saw something; the validator
ate it. Do NOT trust "0 BLOCKER, 0 HIGH_CONSENSUS" without applying
the suspicion lens. Until #814 lands, document the rejection count
prominently in your audit feedback (not just in passing). The
recursive-dogfood pattern from vision-024 says: the cycle that's
trying to close a substrate concern will trip the same substrate gap
again.

---

## KF-005: beads_rust 0.2.1 migration blocks task tracking

**Status**: DEGRADED-ACCEPTED (markdown fallback)
**Feature**: `br` (beads_rust) sprint task lifecycle tracking
**Symptom**: `br` commands (`br ready`, `br create`, `br update`, `br sync`) fail with `run_migrations failed: NOT NULL constraint failed: dirty_issues.marked_at`. `beads-health.sh --quick --json` returns `MIGRATION_NEEDED` status. SQLite schema migration cannot complete on existing local `.beads/` databases.
**First observed**: 2026-04 (multiple cycles)
**Recurrence count**: many (every cycle since the bug landed; ~every sprint hits it)
**Current workaround**: Markdown fallback per beads-preflight protocol — track sprint tasks in `grimoires/loa/cycles/<cycle>/sprint.md` checkboxes; record manual lifecycle in `grimoires/loa/a2a/<sprint>/reviewer.md` task tables. Skill `<beads_workflow>` sections gracefully degrade. Use `git commit --no-verify` per operator standing authorization to bypass beads pre-commit hooks.
**Upstream issue**: [#661](https://github.com/0xHoneyJar/loa/issues/661)
**Related visions / lore**: not vision-class; pure operational degradation

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| various | `br migrate` / `br init` on existing database | DID NOT WORK — same migration error | NOTES.md cross-cycle |
| various | Delete `.beads/` and re-initialize | DID NOT WORK in past cycles (operator may have tried more recently — verify before re-attempting) | — |
| 2026-04+ | Markdown fallback per protocol | WORKS — ledger + reviewer.md + sprint.md checkboxes are sufficient SoT for sprint lifecycle | every cycle since 2026-04 |

### Reading guide

Don't try to fix beads_rust mid-sprint. Use the markdown fallback;
it's the documented protocol. Skill `<beads_workflow>` sections
already handle the graceful-degradation path. If you find yourself
spending more than 5 minutes diagnosing beads, stop — the bug is
upstream and tracked. The markdown fallback is sufficient.

---

## How to add a new entry

1. Pick the next available `KF-{NNN}` ID (sequential).
2. Use the schema at the top of this file.
3. Add a row to the **Index** table at the top.
4. Lead with the *symptom* (operator-visible failure), not the *cause* (which may not be known yet).
5. Be specific in `Evidence` — commit SHAs, PR numbers, run IDs. Future agents will verify.
6. Set `Recurrence count` to 1 on first entry. Future agents increment when they observe again.
7. Don't blame; describe. The point of this file is operational efficiency, not retrospective.

## How to retire / resolve an entry

When a workaround promotes to a structural fix:

1. Flip `Status` to `RESOLVED` with date.
2. Add a final row to `Attempts` with the closing fix and evidence.
3. Keep the entry — it's load-bearing as a "we already solved this, here's how" reference.
4. The Index table's status column reflects the change.

## Why this file exists

Per @janitooor 2026-05-10 (cycle-102 session 7, sprint-1D close):

> "we might need to keep track of stuff which we have tried which HAS NOT
> worked, so that future instances of claude don't waste cycles trying
> stuff which we have tried which hasn't worked. it feels like we have
> had major degradation in this core feature since moving from the older
> models. we do want the newer models so we should keep going with this
> work so i am just communicating this in the interests of trying to
> figure out how to be most effective"

The newer-model substrate (gpt-5.5-pro, claude-opus-4-7, gemini-3.1-pro-preview)
is genuinely more capable. It also has degradation modes the older models
didn't have. We're carrying both: the capability gains AND the substrate
work to make the new models reliable. This file is the operational ledger
of that work — what we've tried, what didn't fix it, what we do today
instead. Future agents read it at session start so we don't pay the
re-discovery cost on every cycle.
