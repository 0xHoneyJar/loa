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
| [KF-002](#kf-002-adversarial-reviewsh-empty-content-on-review-type-prompts-at-scale) | LAYER-3-RESOLVED-BY-CONSTRUCTION 2026-05-11 (Sprint 4A streaming-transport default; layers 1+2 mitigated via text.format=text + provider fallback chain). Streaming eliminates the >60s-wait-for-first-byte failure mode independent of intermediary timer behavior. | adversarial-review.sh review-type | 4 |
| [KF-003](#kf-003-gpt-55-pro-empty-content-on-27k-input-reasoning-class-prompts) | RESOLVED (model swap) | flatline_protocol code review | 1 |
| [KF-004](#kf-004-validate_finding-silent-rejection-of-dissenter-payloads) | RESOLVED 2026-05-10 (sidecar dump landed; #814 mitigation shipped) | adversarial-review.sh validation pipeline | ≥4 |
| [KF-005](#kf-005-beads_rust-021-migration-blocks-task-tracking) | DEGRADED-ACCEPTED — fix available on crates.io as `beads_rust 0.2.4`; operator must `cargo install beads_rust` to land locally | beads_rust task tracking | many |
| [KF-006](#kf-006-t114-migrate-model-config-v2-schema-rejects-max_output_tokens) | RESOLVED 2026-05-10 (v2 schema modelEntry permits max_output_tokens + max_input_tokens) | T1.14 migrate-model-config v2 schema | every PR since dd54fe9c |
| [KF-007](#kf-007-red-team-pipeline-hardcoded-single-model-evaluator-vestigial-config) | RESOLVED 2026-05-10 (multi-model evaluator) | red team pipeline hardcoded single-model evaluator | n/a — resolved in same session as discovery |
| [KF-008](#kf-008-bridgebuilder-google-api-socketerror-on-large-request-bodies) | OPEN — THREE observations 2026-05-11 (~70 min span) on SAME PR (#844, request_sizes 297KB / 302KB / 318KB). Other PRs with smaller bodies had Google succeed in the same invocations. Distinct from KF-001 (mid-stream `SocketError other side closed` vs pre-handshake `AggregateError`). Body-size threshold; structural. Upstream issue [#845](https://github.com/0xHoneyJar/loa/issues/845) filed. | bridgebuilder Google provider Node fetch | 3 |

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

**Status**: PARTIALLY-MITIGATED 2026-05-10 (text.format=text shipped for OpenAI; structural opus + connection-lost layers remain) + LAYER-3-RESOLVED-BY-CONSTRUCTION 2026-05-11 (Sprint 4A streaming-transport default eliminates the >60s-wait-for-first-byte failure mode; gate raised from 24K/36K to 200K/180K; see Attempts table 2026-05-11 row and Sprint 4A Resolution note below)

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

### Outstanding layers (post-2026-05-10 input-size gate)

1. **Cheval HTTP-asymmetry bug class** (root cause of Loa Issue #774). Operator's
   2026-05-10 follow-up evidence on #774 ruled out network/provider as the
   cause: direct curl at 30K-input to Anthropic returns HTTP 200 in 3.6s,
   but cheval's anthropic + openai paths `Server disconnected` at the same
   payload size in the same run. Gemini's cheval path succeeds at the same
   scale. The bug is specifically in cheval's anthropic + openai adapter
   HTTP client config (HTTP/2 settings, header config, or timeout). The
   2026-05-10 input-size gate (Sprint 1F) is a **backstop**: it refuses
   prompts above empirically-observed safe thresholds (24K for gpt-5.5-pro,
   36K for opus-4-7) so the failure mode never triggers. The structural
   fix in cheval's HTTP client layer remains pending.

### Resolved layers (2026-05-10)

1. **OpenAI gpt-5.5-pro empty-content from reasoning budget exhaustion** — RESOLVED via `text: { format: { type: "text" } }` in `_build_responses_body`. PR #833 / commit 27af33ba.
2. **Generalized empty-content / api_failure across ANY single provider** — RESOLVED via automatic provider fallback chain in adversarial-review.sh. When the configured primary model returns `malformed_response` or `api_failure` (the empty-content failure modes), the next model in the chain is tried automatically. Default chain reads from `flatline_protocol.{code_review,security_audit}.fallback_chain` (operator-curated) or falls back to `flatline_protocol.models.{secondary, tertiary}` (already in use for multi-model PRD/SDD review). Result metadata includes `model_attempts` array (full trail) + `final_model` (which model produced the canonical result). Operator opt-out: `LOA_ADVERSARIAL_DISABLE_FALLBACK=1` env or `fallback_chain: []` in config. Cycle-102 sprint-1F. **Effect**: claude-opus-4-7 empty-content at >40K input (Loa #823, the layer-2 problem mentioned in original Outstanding) now auto-falls-back to gpt-5.5-pro then gemini-3.1-pro, and the canonical result reflects whichever provider succeeded. The empty-content failure becomes a degraded-1-of-3 trajectory (still useful) rather than a total halt. The Sprint 1B T1B.4 manual model swap pattern is now generalized + automatic.
3. **Gemini empty-content** — not yet observed in Loa traffic; if observed, the fallback chain handles it as one of three providers automatically.
4. **Connection-lost on long prompts (backstop layer)** — MITIGATED via per-model input-size gate landed cycle-102 Sprint 1F. New `max_input_tokens` field in `model-config.yaml` (separate from `context_window`) names the empirically-observed safe threshold per (provider, model). When `cheval.cmd_invoke` would invoke a model with an estimated input above the threshold, it raises `ContextTooLargeError` (exit 7) BEFORE adapter setup, so the `Server disconnected` failure mode never triggers. Combined with the adversarial-review fallback chain (PR #836), an above-threshold prompt to gpt-5.5-pro routes to opus-4-7 (which has its own threshold 36K), and if opus is also above threshold the chain falls to gemini (no gate ships). Initial thresholds: gpt-5.5-pro/gpt-5.5 = 24000, claude-opus-4-7/4-6 = 36000, gemini = no gate. Operator opt-out: `--max-input-tokens 0` per call or `LOA_CHEVAL_DISABLE_INPUT_GATE=1` globally. The structural cheval HTTP-asymmetry fix remains pending (see Outstanding §1 above).

(Original entry preserved below for the trail.)
---

**Original Status**: DEGRADED-ACCEPTED (workaround in place; structural fix pending)
**Feature**: `.claude/scripts/adversarial-review.sh --type review` (Phase 2.5 of `/review-sprint`)
**Symptom**: Reasoning-class models (gpt-5.5-pro, claude-opus-4-7) return empty content for review-type prompts at >27K input (gpt-5.5-pro) or >40K input (claude-opus-4-7). 3 retries all empty. The script writes `status: api_failure` to the output JSON, the COMPLETED gate accepts api_failure as a "legitimate completion record," and Sprint audit passes despite no actual cross-model dissent applied. **Audit-type prompts at the same scale succeed** — the failure is prompt-structure-dependent, not pure input-size.
**First observed**: 2026-05-09 (cycle-102 sprint-1A audit on PR #803)
**Recurrence count**: 5+ (sprint-1A audit, sprint-1B audit, sprint-1B BB iter-6, cycle-103 PRD+SDD flatline run 2026-05-11, cycle-103 sprint.md flatline run 2026-05-11 with 3-of-3 provider empty-content at 5K-token input — see NOTES.md 2026-05-09 Decision Log: T1B.4 ROOT-CAUSE REFRAME and cycle-103 rows in Attempts below; **NEW FAILURE SHAPE**: prompt-structure trigger independent of scale, plus first Gemini empty-content observation)
**Current workaround**: Sprint 1B T1B.4 swapped `flatline_protocol.{code_review,security_audit}.model` from `gpt-5.5-pro` to `claude-opus-4-7`. Upstream Issue #812 proposes the same default for all Loa users. **Note: opus has the SAME bug at higher input threshold** (Issue #823 / vision-024) — the swap routes around the bug at one scale but the bug class is fractal, not solved.
**Upstream issue**: [#812](https://github.com/0xHoneyJar/loa/issues/812) (model swap proposal), [#823](https://github.com/0xHoneyJar/loa/issues/823) (opus empty-content at >40K)
**Related visions / lore**: vision-019 Bridgebuilder's Lament, vision-023 Fractal Recursion ("the very gate built to detect silent degradation experienced silent degradation, of the same bug class the gate was built to detect"), vision-024 Substrate Speaks Twice, vision-025 Substrate Becomes the Answer (the routing-around-not-fixing-through pattern)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | Bump default `max_output_tokens=32000` for `gpt-5.5-pro` (Sprint 1A T1.9) | WORKAROUND-AT-LIMIT — verified at 10K input, FAILED at 27K input | commit `dd54fe9c` / NOTES.md 2026-05-09 Decision Log |
| 2026-05-09 | Sprint 1B T1B.4 model swap to `claude-opus-4-7` | WORKAROUND-AT-LIMIT — works to ~40K input, fails at >40K (Issue #823) | commit `0872780c` |
| 2026-05-09 | Audit-type at 47K input (test if scale alone or prompt-structure) | RESOLVED FOR AUDIT-TYPE — audit-type at 47K succeeded | NOTES.md 2026-05-09 |
| 2026-05-10 | Per-model input-size gate (Sprint 1F) — refuses prompts above empirically-observed safe thresholds before adapter call | MITIGATED LAYER 3 — connection-lost class no longer reachable via gated paths; structural cheval HTTP-asymmetry root cause remains under investigation | Sprint 1F PR (this entry) — `_lookup_max_input_tokens` in `.claude/adapters/cheval.py`; thresholds in `.claude/defaults/model-config.yaml` |
| 2026-05-11 | Empirical reproduction attempt for layer 3 with `LOA_CHEVAL_DISABLE_INPUT_GATE`-equivalent (passed `--max-input-tokens 0`) | **LAYER 3 DID NOT REPRODUCE** in current production conditions — see Reproduction note below. Layer 1 (empty-content from reasoning-budget exhaustion) still reproduces on Anthropic when `max_tokens` is too small to cover thinking + visible output | Session 10 harness `/tmp/cheval-repro/repro.py` + real `model-invoke` with 183KB SDD payload (~50K tokens) returning structured content in 26s, exit 0 |
| 2026-05-11 | **Sprint 4A streaming-transport default** — `http_post_stream()` in `.claude/adapters/loa_cheval/providers/base.py` + `parse_*_stream()` in `anthropic_streaming.py` / `openai_streaming.py` / `google_streaming.py` + adapters defaulting to `_complete_streaming` (kill switch via `LOA_CHEVAL_DISABLE_STREAMING=1`). All 3 providers stream the response; server emits first token immediately; intermediaries never observe an idle TCP connection. | **LAYER 3 RESOLVED BY CONSTRUCTION** — the >60s-wait-for-first-byte failure class is no longer reachable on the streaming path, independent of any intermediary timer behavior. Input-size gate raised from 24K/36K to 200K/180K (still acts as belt-and-suspenders). 31 new pytest cases pin per-provider streaming behavior; live smokes against all 3 endpoints confirm end-to-end. | Sprint 4A PR series: ec65cdbf (transport) + 10df41f8 (Anthropic) + 1855953b (OpenAI) + b70c2cff (Google) + e6d08fc0 (audit) + dba04509 (gate) |
| not tried | Adaptive truncation (lower review-type input cap to ~16K) | — | proposed in vision-023 §"What this teaches"; rendered moot by Sprint 4A streaming default — no truncation needed |
| not tried | Drop `reasoning.effort` to `low` for adversarial-review's task class | — | proposed in NOTES.md 2026-05-09 Decision Log; still applicable for layer 1 (empty-content) cost-control, not load-bearing post Sprint 4A |
| 2026-05-11 | Cycle-103 PRD+SDD flatline run (`/flatline-review prd sdd` over cycle-103 PRD 14KB + SDD 32KB) — `flatline_protocol.models.primary: opus` + `.secondary: gpt-5.5-pro` + `.tertiary: gemini-3.1-pro-preview` per cycle-102 Sprint 1B T1B.4 config | **RECURRENCE-4** — Opus returned 0 items on PRD (14KB input, well under prior 40K threshold) AND 0 items on SDD; GPT returned 10 items on PRD but 0 on SDD (32KB input, matches KF-003 ≥27K threshold); only Gemini cross-scored. PRD consensus emitted as 10 DISPUTED at `confidence: single_model` (really 2-of-3 GPT+Gemini agreement); SDD emitted `degraded: true, degraded_model: "both", reason: "no_items_to_score"`. **The cycle whose thesis is exactly fixing this class just triggered the class on its own planning artifacts.** | `grimoires/loa/cycles/cycle-103-provider-unification/flatline/prd-review.json` + `sdd-review.json` (recurrence evidence); cycle-103 SDD §1 IPC contract is the structural fix |
| 2026-05-11 | Cycle-103 sprint.md flatline run (`/flatline-review sprint` over cycle-103 sprint.md 18KB / ~5K tokens) — same 3-model config | **RECURRENCE-5 + NEW FAILURE SHAPE** — All 3 providers returned empty content (Opus AND GPT AND Gemini). 4 of 6 Phase 1 calls failed (gpt-review, gpt-skeptic, gemini-review, gemini-skeptic — all returned empty); Opus calls structurally succeeded but with empty items per scoring-engine "both input files empty" warning. Phase 1 cost was 36¢ (HTTP 200 across the board) so this is empty-content, not API error. **First documented Gemini empty-content observation in Loa traffic** — invalidates the "Gemini empty-content not yet observed" note in the upstream cross-references table. **Critically: sprint.md at 5K tokens is well below every prior empty-content threshold** (24K gpt-5.5-pro, 40K opus-4-7, no documented gemini threshold). Scale is therefore NOT the trigger — the flatline sprint-phase prompt template is. PRD-phase + SDD-phase prompts behave differently. This makes the bug class prompt-structure-dependent at a deeper level than KF-002 originally documented. | `grimoires/loa/cycles/cycle-103-provider-unification/flatline/sprint-review.json` (`degraded: true, degraded_model: "both"`); scoring-engine warning `both input files empty (no items to score)`; phase-1 cost 36¢ with 4-of-6 failed |

### 2026-05-11 reproduction note (session 10)

Direct httpx tests (HTTP/1.1, HTTP/2, streaming, TCP-keepalive variants) **all
succeeded** against `api.anthropic.com` with 30K-token and 50K-token lorem
payloads, returning HTTP 200 in 5-9s. Real `model-invoke` against
`claude-opus-4.7` with the full repo SDD (183KB / ~50K tokens) returned
proper structured content in 26 seconds. The 60-second wall-clock disconnect
that defined layer 3 between 2026-05-09 and 2026-05-10 did not reappear in
any test run.

Three explanations are consistent with the evidence:

1. **Server-side fix**: Anthropic / OpenAI may have lifted a CDN or
   load-balancer idle-timeout from 60s. This is the cleanest explanation
   but is invisible to us — we cannot confirm without provider
   communication.
2. **Network-path dependent**: the original observer was routed through a
   particular CDN POP whose timer config differed from the path tested
   on 2026-05-11. Time-of-day, ASN, and geographic routing all bias
   Cloudflare's path selection.
3. **Trigger conditions not matched**: the original failures came through
   `flatline-orchestrator.sh` Phase 1 parallel-call pattern (concurrent
   POSTs from one host) and `adversarial-review.sh` with specific
   prompt shapes. The 2026-05-11 harness is single-call; some
   concurrent-call interaction may be the actual trigger.

**Operational status**: layer 3 is downgraded from `MITIGATED` (asserting
the gate is the load-bearing fix) to `OBSERVABILITY-LATENT` — the gate
remains in place as belt-and-suspenders, but we cannot currently
demonstrate that it is required. The structural-fix candidate (streaming
responses) is parked in the Attempts table; not implemented because the
current failure mode cannot be reproduced to validate the fix against.

**Next observation events that should re-open layer 3**:
- Any `ConnectionLostError` with `transport_class=RemoteProtocolError`
  observed in `.run/cheval-*.log` after 2026-05-11.
- Any `[cheval] WARNING: Connection lost from {anthropic,openai}` in
  flatline / BB / adversarial-review trajectories.
- Operator-reported `Server disconnected` shape on `/review-sprint`.

When the next instance is observed: increment recurrence count, add an
Attempts row with the timestamp + payload size + network conditions,
and consider whether the streaming-response structural fix should be
promoted from "parked" to "in flight."

### 2026-05-11 Sprint 4A Resolution

Layer 3 is now closed BY CONSTRUCTION via the streaming-transport
structural fix. The 60-second wait-for-first-byte window is no longer
reachable on the streaming path — the server begins emitting bytes
within a few seconds of request acceptance, so intermediaries
(Cloudflare edge, ALBs, etc.) never observe an idle TCP connection.

What shipped:

| Commit | Scope |
|--------|-------|
| `ec65cdbf` | `http_post_stream()` in `base.py` — shared streaming transport with HTTP/2-via-h2 + HTTP/1.1 fallback. 12 regression-pin tests. |
| `10df41f8` | Anthropic streaming adapter + `parse_anthropic_stream` (6 SSE event types). 11 parser tests. Live smoke: 27K tokens to claude-opus-4-5 in 3.09s. |
| `1855953b` | OpenAI streaming adapter — both `/chat/completions` (SSE chunks) AND `/v1/responses` (typed events). 11 parser tests. Live smokes: 25K tokens to gpt-4o-mini in 6.11s + gpt-5.5-pro responses-API in 12.46s. |
| `b70c2cff` | Google Gemini streaming adapter + `parse_google_stream`. 8 parser tests. Live smoke: 25K tokens to gemini-2.5-flash in 3.12s. |
| `e6d08fc0` | MODELINV audit-payload `streaming: bool` field — surfaces transport choice for vision-019 M1 silent-degradation queries. 15 tests. |
| `dba04509` | Input-size gate raised from 24K/36K → 200K/180K reflecting streaming's actual safe range. Gate retained as belt-and-suspenders + context-window backstop. |

Streaming is the default for all three providers. Operators can revert
to the legacy non-streaming path on a single call with
`LOA_CHEVAL_DISABLE_STREAMING=1` (one-shot backstop); this also lowers
the effective input-size ceiling back to the Sprint 1F empirical values.

Why this resolution holds even though layer 3 didn't reproduce on
2026-05-11: streaming closes the failure class by construction, not by
mitigation. Even if Anthropic / OpenAI restore the 60s intermediary
timer that originally caused KF-002 (or if a new intermediary's timer
emerges), the streaming path's continuous byte emission keeps the TCP
connection active and the failure mode unreachable. The fix targets the
root mechanism (idle-TCP idle-detection at intermediaries) rather than
the symptom (RemoteProtocolError at 60s).

Runbook: `grimoires/loa/runbooks/cheval-streaming-transport.md` —
operator-visible documentation of the new default behavior, the
LOA_CHEVAL_DISABLE_STREAMING kill switch, the regression-pin tests, and
the upgrade path.

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
**Recurrence count**: 2 (originally believed scale-dependent within reasoning models; subsequent observation showed the bug class extends to opus at higher threshold, see KF-002; cycle-103 SDD flatline run 2026-05-11 reproduced on 32KB SDD input — see new Attempts row)
**Current workaround**: Resolved by Sprint 1B T1B.4 model swap. cheval's per-model `max_output_tokens` lookup landed at T1.9 (Sprint 1A) addresses the budget-side; the empty-content failure mode is independent of budget.
**Upstream issue**: [#812](https://github.com/0xHoneyJar/loa/issues/812)
**Related visions / lore**: vision-019, vision-023; `feedback_loa_monkeypatch_always_upstream.md` (this entry exemplifies the "every project-local fix becomes upstream-issue-shaped" rule)

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-09 | Verify T1.9 `max_output_tokens=32000` lookup applies | RESOLVED-AT-10K — bug class is empty-content not budget; lookup is correct but doesn't fix the deeper layer | sprint-bug-143 / NOTES.md 2026-05-09 Decision Log |
| 2026-05-09 | Switch to `claude-opus-4-7` per T1B.4 | WORKAROUND HOLDS at this scale — opus has no empty-content bug for inputs <40K | commit `0872780c` |
| 2026-05-11 | Cycle-103 flatline-review on SDD (32KB / ~32K-token input) with `gpt-5.5-pro` as `flatline_protocol.models.secondary` | **REPRODUCED** — both review and skeptic modes returned empty content. KF-002 row for same date shows Opus also returned empty on SDD; flatline scoring-engine emitted `degraded: true, degraded_model: "both"`. Note the cycle-103 PRD (14KB input) was below the 27K threshold and GPT returned 10 items there. | `grimoires/loa/cycles/cycle-103-provider-unification/flatline/sdd-review.json` (`degradation_reason: "no_items_to_score"`); log shows `[scoring-engine] WARNING: both input files empty (no items to score) — emitting degraded consensus per #759` |

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

**Status**: DEGRADED-ACCEPTED (markdown fallback) — **REGRESSION CONFIRMED 2026-05-11 at beads_rust 0.2.4 AND 0.2.6**: upgraded local install to 0.2.6 (current latest); migration still fails with identical `NOT NULL constraint failed: dirty_issues.marked_at`. The "fix landed in 0.2.2/0.2.3/0.2.4" claim from 2026-05-10 is not supported by empirical test; either the fix doesn't address dirty databases (only fresh init), or it was reverted, or it never landed. **Upstream filed**: [Dicklesworthstone/beads_rust#290](https://github.com/Dicklesworthstone/beads_rust/issues/290) (2026-05-11). Markdown fallback remains canonical.

### Upgrade path (verified 2026-05-10)

```bash
cargo search beads_rust   # → 0.2.4 on crates.io
br --version              # → br 0.2.1 (still installed locally)
cargo install beads_rust  # operator action — upgrades user-scoped binary
br --version              # should now report 0.2.4
.claude/scripts/beads/beads-health.sh --json | jq .status  # should flip MIGRATION_NEEDED → HEALTHY
```

Loa #661 was closed upstream 2026-05-02; the schema-migration fix landed in 0.2.2 / 0.2.3 / 0.2.4. Local environments still on 0.2.1 will hit the same migration error documented below — the upstream fix is real, it just needs to be picked up via `cargo install`. If the upgrade does NOT fix the migration locally (i.e., 0.2.4 still hits the NOT NULL `dirty_issues.marked_at` error), file a fresh upstream issue with the new evidence — that would be a regression at the latest release.

(Original entry preserved below.)
---

**Original Status**: DEGRADED-ACCEPTED (markdown fallback)
**Feature**: `br` (beads_rust) sprint task lifecycle tracking
**Symptom**: `br` commands (`br ready`, `br create`, `br update`, `br sync`) fail with `run_migrations failed: NOT NULL constraint failed: dirty_issues.marked_at`. `beads-health.sh --quick --json` returns `MIGRATION_NEEDED` status. SQLite schema migration cannot complete on existing local `.beads/` databases.
**First observed**: 2026-04 (multiple cycles)
**Recurrence count**: many (every cycle since the bug landed; ~every sprint hits it)
**Current workaround**: Markdown fallback per beads-preflight protocol — track sprint tasks in `grimoires/loa/cycles/<cycle>/sprint.md` checkboxes; record manual lifecycle in `grimoires/loa/a2a/<sprint>/reviewer.md` task tables. Skill `<beads_workflow>` sections gracefully degrade. Use `git commit --no-verify` per operator standing authorization to bypass beads pre-commit hooks.
**Upstream issue**: [Dicklesworthstone/beads_rust#290](https://github.com/Dicklesworthstone/beads_rust/issues/290) (filed 2026-05-11 against 0.2.6) + downstream tracker [0xHoneyJar/loa#661](https://github.com/0xHoneyJar/loa/issues/661) (closed 2026-05-02; should be reopened with the regression evidence)
**Related visions / lore**: not vision-class; pure operational degradation

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| various | `br migrate` / `br init` on existing database | DID NOT WORK — same migration error | NOTES.md cross-cycle |
| various | Delete `.beads/` and re-initialize | DID NOT WORK in past cycles (operator may have tried more recently — verify before re-attempting) | — |
| 2026-04+ | Markdown fallback per protocol | WORKS — ledger + reviewer.md + sprint.md checkboxes are sufficient SoT for sprint lifecycle | every cycle since 2026-04 |
| 2026-05-10 | Verify upstream fix availability (P4.11 from cycle-102 session-9 handoff). `cargo search beads_rust` → 0.2.4 on crates.io; local install is 0.2.1 (3 patch versions behind). `br sync --import-only` on local 0.2.1 reproduces the original error. | UPGRADE PATH IDENTIFIED — operator must run `cargo install beads_rust` to land the upstream fix locally. Markdown fallback remains the safe bet until the upgrade is verified. | crates.io 0.2.4 / Loa #661 (closed 2026-05-02) |
| 2026-05-11 | Operator upgraded to `br 0.2.4` (per session 11 message). Cycle-103 planning attempted `br ready` + `br create --dry-run`. Then `br upgrade` to `br 0.2.6` (current latest) and retried. | **REGRESSION CONFIRMED** — both 0.2.4 and 0.2.6 reproduce the exact original error: `run_migrations failed: Database(Internal("VDBE halted with code 19: NOT NULL constraint failed: dirty_issues.marked_at"))`. Health check still reports `MIGRATION_NEEDED` + `dirty_issues_migration: needs_repair`. The "fix landed in 0.2.2+" claim is empirically wrong for dirty databases. **Action needed**: file fresh upstream issue against `beads_rust 0.2.6` with evidence; reopen Loa #661 with regression note; markdown fallback remains canonical SoT until upstream is genuinely fixed. | `br --version` returns `br 0.2.6`; `.claude/scripts/beads/beads-health.sh --json` returns `MIGRATION_NEEDED` |

### Reading guide

Don't try to fix beads_rust mid-sprint. Use the markdown fallback;
it's the documented protocol. Skill `<beads_workflow>` sections
already handle the graceful-degradation path. **2026-05-10 update**:
the upstream fix landed in `beads_rust 0.2.2+`; if your local install
is still 0.2.1, run `cargo install beads_rust` between sessions
(operator action — touches `~/.cargo/bin/`) to land the fix. Don't do
this mid-sprint — bin upgrades during agent runs can leave the agent
in a stale binary-version state. If 0.2.4 still hits the migration
error, treat as a regression and file a fresh upstream issue with
new evidence. If you find yourself spending more than 5 minutes
diagnosing beads, stop — the bug is upstream and tracked. The
markdown fallback is sufficient.

---

## KF-006: T1.14 migrate-model-config v2 schema rejects `max_output_tokens`

**Status**: RESOLVED 2026-05-10 (v2 schema modelEntry properties extended to include `max_output_tokens` + `max_input_tokens`; production-yaml smoke-migrates with exit 0; 3 new bats regression tests at `tests/integration/migrate-model-config.bats:M19.{1,2,3}`)

(Original entry preserved below.)
---

**Original Status**: OPEN (CI-blocking on every PR touching model-config; pre-existing since cycle-102 sprint-1A merge)
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
| 2026-05-10 | Extend v2 schema `modelEntry.properties` with `max_output_tokens` + `max_input_tokens`; add 3 bats regression tests (M19.1–M19.3) | RESOLVED — production-yaml smoke-migrates exit 0 | Sprint 1F PR (this entry) — `.claude/data/schemas/model-config-v2.schema.json` + `tests/integration/migrate-model-config.bats` |

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

---

## KF-008: bridgebuilder Google API SocketError on large request bodies

**Status**: OPEN — observed on 2026-05-11 during Sprint 4A post-merge BB
test run; distinct from KF-001 (which was Happy Eyeballs pre-handshake;
that fix held — Anthropic worked fine in today's runs). **Root cause
isolated 2026-05-11 (cycle-103 T1.0 spike)**: failure is confined to BB
Node `fetch` adapter; cheval Python `httpx` does **not** reproduce at
172/250/318/400KB. Resolution path: cycle-103 Sprint 1 T1.2/T1.4 migrates
BB Google adapter to the cheval delegate. Anticipated closure:
post-Sprint-1 merge.

**Feature**: `/bridgebuilder` Google provider via
`.claude/skills/bridgebuilder-review/resources/adapters/google` (Node fetch
to `generativelanguage.googleapis.com:streamGenerateContent` or equivalent)

**Symptom**: `gemini-3.1-pro-preview` review fails with `TypeError: fetch
failed; cause=SocketError: other side closed` after 3/3 retry attempts.
Failure occurs MID-STREAM (after TCP+TLS handshake completed and bytes were
flowing) — distinct from KF-001's pre-handshake `AggregateError`. Request
size when observed: **297209B** (~297KB). Anthropic + OpenAI succeed on
the same BB invocation at similar request sizes (117KB and 73KB
respectively — Anthropic completed in 68s, OpenAI in 304s, Google failed
after retries).

**First observed**: 2026-05-11 ~05:33Z (Sprint 4A post-merge BB dry-run
on PR #844 streaming transport; session 10)

**Recurrence count**: 3 (three observations on PR #844 / Sprint 4A
within a ~70 min window on the same operator machine, request sizes
297209B / 302623B / 317766B respectively. Anthropic + OpenAI succeeded
on the SAME invocations at 117KB-125KB + 73KB-78KB request sizes,
ruling out general network outage or operator-side firewall block.
Google's 91s success on smaller PR #804 in the same invocation rules
out provider account / API key issue. **Per the ledger discipline
(recurrence-≥3), upstream issue filed.**)

**Upstream issue**: [#845](https://github.com/0xHoneyJar/loa/issues/845)
(filed 2026-05-11 after recurrence-3 observation; hypotheses + repro
steps + investigation paths documented in the issue body).

**Current workaround**: BB's multi-model consensus scoring continues with
2 of 3 providers when Google fails (anthropic + openai in this run);
the run completes with `mode=multi-model, items=3, 6 findings, 0 consensus,
1 disputed, 0 blocker`. Single-provider failure is degraded but not
fatal. Per the recurrence-≥3 rule, ONE observation does NOT yet trigger
the "stop retrying" gate — re-attempt if observed again to confirm
recurrence vs transient.

**Upstream issue**: Not yet filed (first observation; awaiting recurrence
confirmation per the ledger discipline).

**Related visions / lore**: KF-001 (different error class on same provider
+ tool, resolved 2026-05-10). vision-024 substrate-speaks-twice (the BB
infrastructure articulating its own failure mode AGAIN).

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-05-11 ~05:33Z | First-time observation during BB dry-run on Sprint 4A PR #844 | OBSERVED — Google failed 3/3 attempts at request_size=297209B; Anthropic + OpenAI succeeded at 117KB + 73KB request sizes on the same invocation | Run `bridgebuilder-20260511T053301-a1d3`; log line `"[multi-model:google] Review failed","data":{"error":"Google API network error — TypeError: fetch failed; cause=SocketError: other side closed (request_size=297209B, attempt=3/3, model=gemini-3.1-pro-preview)"}` |
| 2026-05-11 ~05:55Z | Live BB run on the same PR #844 (~25 min after first observation) | OBSERVED AGAIN — Google failed 3/3 at request_size=302623B (slightly larger body — same PR, same SHA, but the second-pass enrichment context grew). Google then **succeeded** on the same invocation against PR #804 (91s, 1311 in / 475 out) and PR #841 (20s, 5912 in / 590 out) — ruling out network outage or account-level rate limit. The failure is body-size dependent. | Run `bridgebuilder-20260511T055522-9aea`; PR #844 has BB consensus from anthropic+openai only (3 of 4 expected comments posted); PR #841 + PR #804 each got all 4 comments. |
| 2026-05-11 ~06:42Z | BB cycle-2 run on PR #844 only (post Sprint 4A cycle-3 commits) | OBSERVED THIRD TIME — Google failed 3/3 at request_size=317766B (body grew further as cycle-3 added more files to the diff). Anthropic + OpenAI succeeded at 125KB + 78KB in the same invocation. **Recurrence-≥3 gate triggered.** | Run `bridgebuilder-20260511T064222-2e83`; PR #844 cycle-2 consensus comment (`https://github.com/0xHoneyJar/loa/pull/844#issuecomment-...`); upstream issue [#845](https://github.com/0xHoneyJar/loa/issues/845) filed with hypotheses + investigation paths. |
| 2026-05-11 ~07:00Z | File upstream issue [#845](https://github.com/0xHoneyJar/loa/issues/845) per ledger discipline | DONE — upstream issue covers all three observations, distinguishes from KF-001, lists 4 hypotheses (Loa adapter config, Google API gateway, provider rate-limit-as-RST, Node 20 undici bug), and proposes 4 investigation paths (direct curl, adapter diff, body-size bisection, mobile-hotspot repro). | https://github.com/0xHoneyJar/loa/issues/845 |
| 2026-05-11 ~09:35Z | **Cycle-103 T1.0 spike** — `cheval` Python `httpx` against `generativelanguage.googleapis.com` at 172KB / 250KB / 318KB / 400KB (model `gemini-3.1-pro-preview`, n=1 per size). Tests hypothesis #1 from #845: is the failure adapter-config-specific (Node fetch) vs. provider-side? | **DID NOT REPRODUCE — adapter-isolated** — all four trials exit 0 with completed HTTPS round-trip. No `SocketError: other side closed`. KF-008 confined to BB Node `fetch` (undici default agent / HTTP/1.1 keep-alive behavior); not a server-side body-size limit. Closure path: cycle-103 Sprint 1 T1.2/T1.4 migrates BB Google adapter → cheval delegate. Secondary finding (out of KF-008 scope, into KF-002): all four trials hit `finish_reason=MAX_TOKENS` truncation pressure — KF-002 layer-2 territory, Sprint 2 charter. | `grimoires/loa/cycles/cycle-103-provider-unification/handoffs/httpx-large-body-spike.md` + `httpx-large-body-spike-results.jsonl` + `httpx-large-body-spike.py` |
| not tried | Reproduce with smaller diff (split PR #844 into 2-3 smaller PRs) | — | proposed in #845: would identify whether the failure threshold is at ~150KB / 200KB / 250KB / 290KB |
| not tried | Reproduce on a different network (mobile hotspot vs home/office) | — | proposed in #845: would distinguish operator-machine-network vs upstream provider |
| not tried | Direct curl POST of the same ~300KB body to `streamGenerateContent` | — | proposed in #845: would isolate Node fetch vs upstream behavior. Three independent observations at ~300KB on the SAME PR within ~70 min strongly suggest the threshold is body-size-related, not transient. |

### Reading guide

Single observation — NOT yet structural. If your BB run shows `2 of 3`
provider success with Google failing at request body sizes ≥250KB and
the error shape matches `SocketError: other side closed` mid-stream:
- Note as a recurrence here (increment count)
- Do NOT retry the same BB invocation on the same large diff — accept
  the degraded `2 of 3` consensus
- If the BB consensus column shows non-zero disputed/blocker, the missing
  Google input means single-model `single-model-true-positive-in-DISPUTED`
  scrutiny applies to the Anthropic + OpenAI findings (per Sprint 1A
  lore + `feedback_zero_blocker_demotion_pattern.md`)
- If recurrence reaches 3: file upstream issue per the ledger discipline

The Sprint 4A streaming transport (in cheval, Python) is unaffected — this
is BB's Node fetch path. The KF-001 Happy Eyeballs fix in entry.sh
(`NODE_OPTIONS=--network-family-autoselection-attempt-timeout=5000`)
addressed pre-handshake failures and is still working. KF-008 is a
distinct mid-stream failure pattern that the Happy Eyeballs fix does
not address.

---

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
