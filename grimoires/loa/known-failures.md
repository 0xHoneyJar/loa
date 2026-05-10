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
| [KF-001](#kf-001-bridgebuilder-cross-model-provider-network-failures-non-openai) | RESOLVED 2026-05-10 (Node 20 Happy Eyeballs autoselection-attempt-timeout) | bridgebuilder cross-model dissent | 3 |
| [KF-002](#kf-002-adversarial-reviewsh-empty-content-on-review-type-prompts-at-scale) | PARTIALLY-MITIGATED 2026-05-10 (text.format=text shipped for OpenAI; opus + connection-lost layers remain) | adversarial-review.sh review-type | 3 |
| [KF-003](#kf-003-gpt-55-pro-empty-content-on-27k-input-reasoning-class-prompts) | RESOLVED (model swap) | flatline_protocol code review | 1 |
| [KF-004](#kf-004-validate_finding-silent-rejection-of-dissenter-payloads) | RESOLVED 2026-05-10 (sidecar dump landed; #814 mitigation shipped) | adversarial-review.sh validation pipeline | ≥4 |
| [KF-005](#kf-005-beads_rust-021-migration-blocks-task-tracking) | DEGRADED-ACCEPTED | beads_rust task tracking | many |
| [KF-006](#kf-006-t114-migrate-model-config-v2-schema-rejects-max_output_tokens) | OPEN | T1.14 migrate-model-config v2 schema | every PR since dd54fe9c |
| [KF-007](#kf-007-red-team-pipeline-hardcoded-single-model-evaluator-vestigial-config) | RESOLVED 2026-05-10 (multi-model evaluator) | red team pipeline hardcoded single-model evaluator | n/a — resolved in same session as discovery |

---

## KF-001: bridgebuilder cross-model provider network failures (non-OpenAI)

**Status**: RESOLVED 2026-05-10 (root cause identified, patch landed in `.claude/skills/bridgebuilder-review/resources/entry.sh`)

### Resolution

Diagnosed root cause: Node 20+ undici fetch's RFC 8305 Happy Eyeballs uses a
default `--network-family-autoselection-attempt-timeout=250ms`. On networks
where the IPv4 TCP handshake to specific provider endpoints takes >250ms
(common with Cloudflare/Cloud DDoS-protected anthropic + google endpoints),
Node aborts the IPv4 attempt before the handshake completes and reports
`TypeError: fetch failed; cause=AggregateError`. Curl, Python httpx, and
other HTTP clients don't have this issue because they use sequential or
longer-timeout connection logic. OpenAI's faster IPv4 path completed
inside 250ms which is why it kept working while anthropic + google failed.

Patch: bump the timeout to 5000ms via `NODE_OPTIONS` in `entry.sh`. Honors
existing operator NODE_OPTIONS (appends rather than overwrites). Set
`LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX=1` to opt out.

Diagnostic evidence (preserved here for future agents):
- Direct curl to `api.anthropic.com` IPv4 (160.79.104.10) succeeds with HTTP 404 in 0.9-3s
- Python httpx via cheval.py succeeds against all 3 providers (got "Pong!" from claude-opus-4.7, "pong" from gemini-3.1-pro)
- Node raw `fetch()` fails with: `sub-error[0]: ETIMEDOUT 160.79.104.10:443`, `sub-error[1]: EADDRNOTAVAIL 2607:6bc0::10:443`
- Operator's machine has NO local IPv6 stack (`ip -6 addr show` returns empty)
- With `--network-family-autoselection-attempt-timeout=5000`: Node fetch returns HTTP 401 (correct auth-failure response) immediately

Future agents observing similar fetch failures in OTHER Node-based skills
should check whether those skills also need the same NODE_OPTIONS fix.
The pattern is upstream-known: any Node 20+ undici fetch on networks
with slow-but-reachable IPv4 paths will hit this.

(Original entry preserved below for the trail.)
---

**Original Status**: OPEN — STRUCTURAL (upstream filed)
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
| 2026-05-10 ~06:30Z | Diagnostic sprint: direct curl + Python httpx + raw Node fetch + AggregateError sub-error inspection | ROOT CAUSE IDENTIFIED — Node 20 Happy Eyeballs autoselection-attempt-timeout=250ms killing IPv4 handshake before TCP completes | this entry's "Resolution" section |
| 2026-05-10 ~06:35Z | Patch entry.sh to set `NODE_OPTIONS=--network-family-autoselection-attempt-timeout=5000` | RESOLVED — Node fetch reaches anthropic + google instantly; HTTP 401 / 400 responses received | this entry's "Resolution" section |

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

**Status**: PARTIALLY-MITIGATED 2026-05-10 (text.format=text shipped for OpenAI; structural opus + connection-lost layers remain)

### Upstream cross-references (added 2026-05-10 during KF-002 deep-dive)

| Provider | Upstream issue | Status | Mechanism |
|----------|---------------|--------|-----------|
| OpenAI | [openai/openai-python#2546](https://github.com/openai/openai-python/issues/2546) | CLOSED Aug 2025 (as "normal behavior") | gpt-5-mini Responses API returns ONLY a `ResponseReasoningItem` when reasoning consumes the visible-output budget; `output_text` aggregates from message items only, so it's empty. Same family/mechanism as gpt-5.5-pro KF-002. **Workaround documented**: `text: { format: { type: "text" } }` forces a text message item. **SHIPPED 2026-05-10 as Loa-side default** in `.claude/adapters/loa_cheval/providers/openai_adapter.py:_build_responses_body`. |
| Anthropic | [anthropics/anthropic-sdk-typescript#913](https://github.com/anthropics/anthropic-sdk-typescript/issues/913) | OPEN, filed 2026-05-05 | claude-opus-4-6 returns empty `content` array when using `output_config` json_schema. Different trigger from KF-002 (output_config vs input scale) but same empty-content class. Workarounds: switch to opus-4-5; **enable thinking mode**; remove output_config. Loa hit the same class on opus-4-7 at >40K input (cycle-102 sprint-1C BB iter, Issue #823). |
| Anthropic (related) | [anthropics/anthropic-sdk-python#958](https://github.com/anthropics/anthropic-sdk-python/issues/958) | OPEN | Inconsistent failure to use thinking with Claude 4 Sonnet. Similar mechanism. |
| Google | [google-gemini/api-examples#89](https://github.com/google-gemini/api-examples/issues/89) | OPEN | `max_output_tokens` parameter does not affect response, setting it causes empty or missing outputs. Loa hasn't observed Gemini empty-content empirically yet, but mechanism class is identical. |

### Loa-side mitigation shipped 2026-05-10

`.claude/adapters/loa_cheval/providers/openai_adapter.py:_build_responses_body` now adds `body["text"] = {"format": {"type": "text"}}` to every `/v1/responses` request. Per upstream openai-python#2546 closing comment: this forces the Responses API to emit a text message item even when reasoning exhausts the visible budget, eliminating the empty-`output_text` failure mode for that mechanism. Harmless when not in the empty-content scenario — the model returns the same content it would have returned anyway, just also bound to a typed `ResponseOutputMessage` (which the parser already expects).

**Smoke-validated 2026-05-10**:
- Small prompt ("Say hello in one sentence"): ✅ "Hello!" returned (would have been empty without the fix per upstream)
- Realistic medium prompt + `max_tokens=4000` and `=8000`: ❌ `RemoteProtocolError` connection-lost — **this is a SEPARATE bug class** ([#774](https://github.com/0xHoneyJar/loa/issues/774)), server-side disconnect on long prompts. Not addressable by `text.format=text`.

### Outstanding layers (NOT mitigated by 2026-05-10 patch)

1. **gpt-5.5-pro connection-lost on long prompts** (Loa Issue #774). Server-side disconnect during streaming on prompts that take a long time to generate. Different mitigation needed (HTTP/1.1 instead of HTTP/2; smaller request payloads via aggressive truncation; or upstream OpenAI server-side fix).
2. **claude-opus-4-7 empty-content at >40K input on review-type prompts** (Loa Issue #823). Workaround #913 suggests "enable thinking mode" — counterintuitive but reportedly works. **Not yet tested in Loa context.** Sprint 1B T1B.4 model swap (gpt-5.5-pro → opus-4-7) remains the operational workaround for adversarial-review.sh; if opus also degrades, `flatline_protocol.code_review.model` can be re-routed to claude-sonnet-4-6 or gemini-3.1-pro. No new upstream filing recommended yet — #913 covers the bug class for now.
3. **Gemini empty-content** — not yet observed in Loa traffic. Watch for it; if observed, cross-link #89.

(Original entry preserved below for the trail.)
---

**Original Status**: DEGRADED-ACCEPTED (workaround in place; structural fix pending)
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

**Status**: RESOLVED 2026-05-10 (rejected-finding sidecar landed; suspicion-lens automated)

### Resolution

Patched `.claude/scripts/adversarial-review.sh` with a per-sprint sidecar JSONL that captures every rejected dissenter payload alongside the canonical output:

- **Sidecar path**: `grimoires/loa/a2a/${sprint_id}/adversarial-rejected-${type}.jsonl`
- **Schema** (one entry per rejected finding):
  ```json
  {"ts_utc": "...", "sprint_id": "...", "type": "review|audit", "model": "...",
   "index": <position-in-batch>, "reject_reason": "<why>", "payload": <the dropped finding>}
  ```
- **Reject reason** comes from new `_validate_finding_reason` companion function; possible values include `missing-or-non-string-id`, `missing-severity`, `severity-not-in-enum (got: PURPLE)`, `category-not-in-enum (got: sparkles)`, `missing-or-empty-description`, `missing-or-empty-failure_mode`
- **Aggregate signal in main output**: `metadata.rejected_count` (integer) and `metadata.rejected_sidecar` (relative path or null) added to every `adversarial-{review,audit}.json`. Consumers see the rejection signal without needing to grep stderr
- **Idempotent**: sidecar is truncated at start of every `process_findings` invocation; multiple runs on the same sprint do NOT accumulate entries
- **Opt-out**: `LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1` for environments that can't write the sidecar

The original cycle-102 manifest of this bug — 5 silent rejections during the Sprint 1D `/audit-sprint` adversarial-audit — would now produce `grimoires/loa/a2a/cycle-102-sprint-1D/adversarial-rejected-audit.jsonl` with 5 lines, each capturing the dissenter's actual payload + the reject reason. The operator suspicion-lens that we ran manually this session is now automatic.

(Original entry preserved below.)
---

**Original Status**: OPEN (upstream filed)
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

## KF-006: T1.14 migrate-model-config v2 schema rejects `max_output_tokens`

**Status**: OPEN (CI-blocking on every PR touching model-config; pre-existing since cycle-102 sprint-1A merge)
**Feature**: `tools/migrate-model-config.{sh,py}` smoke test step in workflow `T1.13 log-redactor + T1.14 migrate-model-config CLI`
**Symptom**: The smoke step "Smoke test — migrate the production cycle-095 yaml" exits 78 with `MIGRATION-PRODUCED-INVALID-V2` errors for ~7 fields: `Additional properties are not allowed ('max_output_tokens' was unexpected)` on every model entry under `providers.{openai,anthropic,google}.models.*`. The migrator successfully translates v1 → v2 but the v2 schema validation step rejects the output because the schema doesn't list `max_output_tokens` as a known property.
**First observed**: 2026-05-09 (cycle-102 sprint-1A merge of `dd54fe9c` — that commit added `max_output_tokens: 32000` per-model fields per T1.9, while the cycle-099 sprint-1E.a v2 schema did not extend to allow that field)
**Recurrence count**: every PR since `dd54fe9c` that touches `model-config.yaml` or related paths (workflow only triggers on PRs, not main pushes — so main is "passing" by virtue of not running)
**Current workaround**: Per operator standing authorization, treat the T1.14 step as pre-existing-main-failure when merging cycle-102 PRs. The cross-runtime parity step in the same job (T1.13) is the load-bearing assertion; T1.14 smoke is informational about a pre-existing schema gap.
**Upstream issue**: not filed yet — the fix is to extend `.claude/data/model-config.schema.json` (or whatever the v2 schema artifact is) to permit `max_output_tokens` on per-model objects. Sprint 1A's T1.9 should have included this schema bump.
**Related visions / lore**: not vision-class; pure schema-evolution oversight

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | Sprint 1A T1.9 added `max_output_tokens` fields without bumping v2 schema | INTRODUCED THE REGRESSION | commit `dd54fe9c` |
| 2026-05-10 | Sprint 1D PR #826 hit the same failure on T1.14 smoke step; cross-runtime T1.13 step itself passed 59/59 | OBSERVED — pre-existing not introduced | run `25621265130` / PR #826 |

### Reading guide

If your PR's CI shows `T1.13 log-redactor + T1.14 migrate-model-config CLI`
job FAILURE: check whether the cross-runtime parity step (T1.13) inside the
job passed (look for `ok 59 T16.2 mixed: idempotent` near the end of step
log). If T1.13 is green and only the T1.14 smoke step exits 78 with
`max_output_tokens` rejection: that's this entry — pre-existing, do NOT
attempt to "fix" by removing the field from `model-config.yaml` (that
would break Sprint 1A T1.9's cheval `_lookup_max_output_tokens` function).
The right fix is upstream: extend the v2 schema. Until then, treat as
pre-existing-main-failure for merge purposes.

## KF-007: red team pipeline hardcoded single-model evaluator (config keys vestigial)

**Status**: RESOLVED 2026-05-10 (multi-model evaluator landed in same session as discovery)
**Feature**: `.claude/scripts/red-team-pipeline.sh` Phase 2 (cross-validation) — the evaluator phase that scores attacker-generated attacks
**Symptom**: `red_team.models.{attacker_primary, attacker_secondary, defender_primary, defender_secondary}` config keys existed in `.loa.config.yaml` but were not read by any script (`grep -rn "attacker_primary"` returned 0 matches across `.claude/scripts/`). Pipeline hardcoded `--model opus` (attacker line 351), `--model gpt` (evaluator line 419), `--model opus` (defender line 565). Net effect: red team only invoked anthropic + openai providers — **google was never reached** despite operator config implying multi-provider support.
**First observed**: 2026-05-10 (during operator-requested verification of "all 3 pipelines reach all 3 providers" — caught by config-vs-code grep)
**Recurrence count**: n/a — resolved in same session as discovery (cycle-102 sprint-1E)

### Resolution

Added multi-model evaluator to red team Phase 2 (mirrors the BB pattern that PR #830 restored). Phase 2 now fan-outs three parallel evaluator calls — one per provider — when the new `red_team.models.evaluator_multi_model` flag is true (default). First non-empty valid-JSON response is canonical for downstream Phase 3 consensus; all three outputs are captured in `phase2-multi-model.json` sidecar for cross-model dissent visibility.

Config additions:
```yaml
red_team:
  models:
    evaluator_multi_model: true
    evaluator_primary: claude-opus-4-7   # anthropic
    evaluator_secondary: gpt-5.5-pro     # openai
    evaluator_tertiary: gemini-3.1-pro   # google
```

Verification (live test, this session):
```
Running 3 evaluator calls in parallel against /tmp/rt-mm/prompt.md...
✓ claude-opus-4-7: 730 tokens
✓ gemini-3.1-pro: 702 tokens
✓ gpt-5.5-pro: 1308 tokens
```

All 3 providers returned valid JSON. Total Phase 2 latency = max of the three (parallel, not serial). Total token cost = sum of the three (~3x single-model). Operator can revert to legacy single-model behavior by setting `evaluator_multi_model: false`.

Side fix: `.claude/scripts/red-team-model-adapter.sh` `--help` advertised stale enum `opus|gpt|kimi|qwen`. Updated to reflect that any cheval alias is accepted (resolved at invocation time).

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-10 | Discovered config keys are vestigial via `grep -rn "attacker_primary"` returning 0 matches | DIAGNOSIS — not a regression, original architecture gap | grep output in operator session |
| 2026-05-10 | Probed adapter with `gemini-3.1-pro` directly; verified routing to `google:gemini-3.1-pro-preview` works | CONFIRMED ADAPTER LAYER OK | run via `red-team-model-adapter.sh --role attacker --model gemini-3.1-pro --live` |
| 2026-05-10 | Implemented multi-model evaluator fan-out in pipeline + 3-provider config defaults | RESOLVED | this entry's "Resolution" section |

### Reading guide

If your red team Phase 2 produces results from only 1 provider:
- Check `red_team.models.evaluator_multi_model` is `true` in `.loa.config.yaml`
- Check the per-provider evaluator outputs at `$TEMP_DIR/phase2-evaluator-*.json` — at least one should be non-empty valid JSON
- Check the sidecar at `$TEMP_DIR/phase2-multi-model.json` — should contain `{evaluators: [...]}` array with one entry per successful provider
- If only 1 of 3 succeeded: check stderr for adapter errors per provider; KF-001 should NOT recur (resolved 2026-05-10) but other failure modes may
- Total token cost on Phase 2 is roughly 3x single-model; this is by design for cross-model dissent. Set `evaluator_multi_model: false` to revert to legacy single-model behavior if budget-constrained.

The defender phase (line ~565) and attacker phase (line ~351) still use single-model invocation. Multi-model defender doesn't combine well (3 different counter-designs); multi-model attacker is plausible future work but out of sprint-1E scope.

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
