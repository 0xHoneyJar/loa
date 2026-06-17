<!-- /oracle adoption review — research artifact, not an implementation plan. -->
<!-- Produced 2026-06-17 by an ultracode /oracle workflow (4 web-grounded lenses + synthesis). -->

# Recent Anthropic Advances loa Should Pull In — /oracle Adoption Report

**Analyst:** Claude (Opus 4.8) · **Date:** 2026-06-17 · **Scope:** advances newer than / deeper than `grimoires/pub/research/anthropic-updates-2026-05-31.md` · **Lenses synthesized:** 4 (COST/efficiency, models/tiering, agent/API capabilities, Claude Code platform) · **Companion cost research:** `grimoires/loa/proposals/linear-thinking-nonlinear-costs-loa-research.md`

All loa claims below are grounded by my own Grep/Read this session (file:line). All Anthropic claims carry a URL I fetched/verified, or are flagged as unverified.

---

## 1. Executive Summary

The single highest-value adoption is **prompt caching on the main streaming Anthropic adapter** — and it is the exact mechanical fix for the cost research's #1 risk (R1/R3: "repeated context across iterations with no per-iteration telemetry"). I verified the headline directly: `grep -rn "cache_control" .claude/adapters/loa_cheval/` returns **nothing** — the API path that Flatline/BB/red-team use sends **zero** cache breakpoints, and the `Usage` dataclass (`types.py:48-53`) has **no** cache fields, so loa can neither save nor even *measure* the repeated-context cost. cache_control appears only in `bedrock_adapter.py:595` and `claude_headless_adapter.py:475-480`, which merely **read** cache counts back.

The 3–5 highest-value adoptions, ranked:

1. **Prompt caching (cache_control) on the Anthropic HTTP path** — up to 90% off the repeated system+diff prefix that all Flatline voices and bridge iterations re-send. **[COST]**
2. **Parse + surface cache_read/cache_creation tokens end-to-end** (streaming parser + `Usage` + `economy.py`) — the observability prerequisite the cost research names as load-bearing. **[COST]**
3. **Structured Outputs (strict tool use)** for the adversarial/verdict path — makes a finding missing `id`/`failure_mode` *impossible to generate*, attacking the KF-004 silent-malformed class (recurrence ≥28) at the source rather than post-hoc rejecting to a sidecar. **[QUALITY]**
4. **Bind cheap subtasks (convergence/triage) to Haiku 4.5** — `flatline-scorer` runs on the expensive `reviewer` tier (`model-config.yaml:814-815`); `model: tiny` has **0** bindings. **[COST]**
5. **Wire the budget DOWNGRADE to actually swap models** — `retry.py:367` logs `"continuing with current model"`; the advertised cost-aware swap is a verified **no-op**. **[COST]**

Items 1, 2, 4, 5 all tie directly to the cost research moment. Item 3 is pure quality-gate hardening.

---

## 2. What loa Already Adopted (do NOT re-propose)

The 2026-05-31 grounding doc's top recommendations have nearly all shipped in cycle-114. Credit, with file:line:

| Already adopted | Evidence |
|---|---|
| **Claude Opus 4.8** in registry, `opus` alias retargeted to 4-8 | `model-config.yaml:372` (claude-opus-4-8), `:664` alias |
| **Claude Fable 5** registered as top tier | `model-config.yaml:343` |
| **Claude Sonnet 4.6** + Haiku 4.5 registered | `model-config.yaml:471`, `:512` (claude-haiku-4-5-20251001) |
| **`output_config.effort`** wired through the Anthropic HTTP adapter (cycle-114 FR-2) with `_VALID_EFFORT` validation and the **never-emit-`thinking.budget_tokens`** guard the prior doc warned about | `anthropic_adapter.py:130-148` |
| `CompletionRequest.effort` field | `types.py:26` |
| `tier_groups.effort_hints` (advisory) | `model-config.yaml` effort_hints block |
| Per-effort run-count telemetry (FR-8) | `economy.py:432,474,558` (`effort_counts`) |
| **`disallowed-tools`** mechanical C-PROC-001 enforcement on review skills | `.claude/rules/skill-invariants.md` (Mechanical C-PROC-001 section) |
| Stop guard reads `background_tasks`/`session_crons` (FR-5) | `run-mode-stop-guard.sh:45-58` (per prior doc; not re-verified this session) |
| Bedrock + headless adapters already **read** cache token counts | `bedrock_adapter.py:595`, `claude_headless_adapter.py:475-480` |
| Adversarial-finding **JSON Schema already authored** (so strict tool use is wiring, not authoring) | `.claude/schemas/adversarial-finding.schema.json` (exists, verified) |
| Within-company HTTP fallback chain fable→opus-4-8→… | `model-config.yaml:359-362` |
| Chunking deleted, input gates raised (cycle-109) | per `known-failures.md` / cost research; gates now `streaming_max_input_tokens: 180000-200000` |

**Note on the native Workflow tool / Agent Teams** (prior-doc Feature 4): correctly assessed as a Claude-only fan-out engine that does NOT replace cheval's cross-vendor consensus. That verdict holds — see §4.

---

## 3. Prioritized Adoption Recommendations

Ranked by payoff/effort. **COST?** = ties to the linear-nonlinear cost research.

### (a) Cost / efficiency wins — the cost-research cluster

| # | Advance | Concrete loa application (file) | Effort | Payoff | COST? |
|---|---|---|---|---|---|
| C1 | **Prompt caching via `cache_control` on the Anthropic HTTP path** | In `anthropic_adapter.py`: make the `system` string a text block `[{type:text,text:…,cache_control:{type:ephemeral}}]` (today it's a plain string at `:122-123`); optionally mark the large user content block. `base.py http_post_stream` already forwards arbitrary headers, so no transport change. Targets the shared Flatline context+diff passed as `cheval --system "$context"` / `--input "$input"` (orchestrator `:700,:715`) and the serial bridge-depth re-send. | **M** | Up to **90% off** the repeated prefix (read = 0.1× base; Opus 4.8 $5→$0.50/MTok). Serial bridge loop = near-pure win; concurrent Flatline wave = best-effort (first voice writes, others race). | ✅ |
| C2 | **Parse + surface cache tokens end-to-end** | Add `cache_read_input_tokens`/`cache_creation_input_tokens` to the streaming parser (`anthropic_streaming.py:255-260` parses only input/output today) → add fields to `Usage` (`types.py:48-53`, currently input/output/reasoning only) → roll up in `economy.py` (which has **zero** cache fields; `effort_counts` exists at `:432/474/558` as the precedent). Mirror `claude_headless_adapter.py:475-480`. | **M** | Makes the caching win **provable** (cache_read>0 on iteration 2+); closes the cost research's R3 ("loa sees cost but not its nonlinearity"). Prerequisite for C1's ROI claim. | ✅ |
| C3 | **Optional `cache`/`ttl` field on `CompletionRequest`** | Add an opt-in `cache` to `CompletionRequest` (`types.py:13-26`, which has `effort` but no cache control) so Flatline/BB opt large-context voices into caching; body stays byte-identical when unset (the effort-field precedent at `anthropic_adapter.py:135-144`). | **S** | Clean opt-in plumbing; high-volume review voices on, small one-off calls (below the 1,024-tok min) off. | ✅ |
| C4 | **1-hour cache TTL for the serial bridge path** | For the bridge loop (context re-sent every iteration) set `ttl:"1h"` so the cache survives >5-min gaps (default is 5 min — see §6 caveat). Pairs with C1; gate on whether a session re-sends the same prefix within the hour. | **S** | Converts a 5-min miss into a 1h hit at a 2× write premium that pays off after the 2nd reuse. | ✅ |
| C5 | **Bind cheap subtasks to Haiku 4.5 (tiny tier)** | Retarget convergence/classification off expensive tiers: `flatline-scorer` is `model: reviewer` (`model-config.yaml:814-815`, verified — an expensive tier), and there are no `model: tiny` bindings anywhere (`grep "model: tiny"` = 0; only `model: cheap` is used). Severity-scoring/finding-classification is exactly the work Anthropic positions Haiku for. | **S** | ~5× cheaper per convergence/triage call; preserves Opus-class budget for the adversarial voices where dissent is the load-bearing quality signal. | ✅ |
| C6 | **Wire budget DOWNGRADE to actually swap models** | `retry.py:367` logs `"Budget downgrade triggered — continuing with current model"` and never calls `walk_downgrade_chain` (`routing/chains.py:140`, exported at `routing/__init__.py:14,113` but invoked nowhere outside tests — verified). Config promises a swap: `model-config.yaml:922-923` `downgrade: reviewer: [cheap]`, `:946 on_exceeded: downgrade`. Either invoke the walker on DOWNGRADE or delete the dead config so behavior matches docs. | **S** | Makes the advertised cost-aware swap real (or removes a correctness gap between config and behavior). | ✅ |
| C7 | **Message Batches API (50%) + caching stack — autonomous-only** | Pilot the batch endpoint for the **non-interactive** subset (autonomous post-PR Bridgebuilder, scheduled flatline, large red-team fan-outs, parallel per-file audit). loa uses **no** batch API today. Discounts stack: 50% async + up to 90% caching; use `ttl:"1h"` inside batches (verified: caching supported in batches; `max_tokens:0` pre-warming disallowed inside a batch). Out of scope for interactive gates. | **L** | ~50% on top of caching for latency-tolerant fan-outs; architecturally invasive (async submit/poll lifecycle) → pilot + ADR, not blanket. | ✅ |
| C8 | **`count_tokens` for pre-flight budget/cache-eligibility** | Optionally call the free `count_tokens` endpoint in the budget pre-call path (cross-check `base.py:770-797` which uses `tiktoken cl100k_base` > `len/3.5` — both undercount Claude tokens). Feeds the input-size gate and lets the substrate skip caching for sub-1,024-tok prompts. | **M** | More accurate gating (fewer false ContextTooLargeError / KF-002 oversized-input attempts) + accurate predicted cost. Lower priority than C1-C2. | ✅ |

### (b) Capability / quality wins

| # | Advance | Concrete loa application (file) | Effort | Payoff | COST? |
|---|---|---|---|---|---|
| Q1 | **Structured Outputs (strict tool use) for the adversarial/verdict path** | In `.claude/scripts/adversarial-review.sh`, replace the free-form `OUTPUT: JSON object {"findings": [...]}` prompt (`:545`, `:573`) with a forced strict tool call whose `input_schema` is the already-authored `adversarial-finding.schema.json` + `strict:true` + `additionalProperties:false`; thread `strict` through `_transform_tools_to_anthropic` (`tools`/`tool_choice` already forwarded in `anthropic_adapter.py`). Makes a finding missing `id`/`failure_mode` impossible to generate, collapsing the `validate_finding` (`:239`) reject-to-sidecar path. Keep `validate_finding` as belt-and-suspenders for non-Anthropic voices (Gemini/GPT/headless can't be strict-constrained). | **M** | Eliminates the dominant silent-degradation class (KF-004, recurrence ≥28) for Anthropic voices; cuts the whack-a-mole audit re-passes (~5-6 min/round of cross-model dispatch). | ❌ |
| Q2 | **strict tool use for the verdict_quality envelope producer** | Where any model PRODUCES envelope-shaped JSON, gate behind `output_config.format` so INV-1..INV-6 violations are prevented at generation. Lower priority — the envelope is mostly computed in Python, not model-emitted. | **S** | Defense-in-depth for the second silent-degradation surface; cheap once Q1's wiring exists. | ❌ |

### (c) Platform wins (Claude Code, harness layer — not cheval)

| # | Advance | Concrete loa application | Effort | Payoff | COST? |
|---|---|---|---|---|---|
| P1 | **`--safe-mode` / `CLAUDE_CODE_SAFE_MODE`** (2.1.169) | Document in `known-failures.md` (KF-002 reading guide) + headless runbook as the **first** triage step when the substrate degrades: `claude --safe-mode` disables CLAUDE.md/plugins/skills/hooks/MCP → one-command layer-bisection (model/API vs loa's own layer). MEMORY.md shows many KF-002 sessions burned chasing the wrong layer. | **S** | Faster KF-002 / substrate-down triage; pure docs, zero code. | ❌ |
| P2 | **`fallbackModel` setting** (2.1.166) | Set in `.claude/settings.json` for the **native/interactive harness path only** (NOT cheval — cheval has its own within-company chain at `model-config.yaml:359-362`) so the interactive harness degrades on Opus 4.8 overload. | **S** | Resilience for the interactive path cheval's chain doesn't cover; cheap. | ❌ |
| P3 | **`post-session` lifecycle hook** (2.1.169, self-hosted runner) | Snapshot `.run/` state + `.run/model-invoke.jsonl` (MODELINV) + cost-ledger before workspace teardown — strengthens cross-session continuity beyond the happy path. Applies only to self-hosted-runner deployments. | **M** | Durable end-of-session audit capture for CI/autonomous runs. | ❌ |
| P4 | **`Stop`/`SubagentStop` `additionalContext` return** (2.1.163/2.1.169) | Upgrade `run-mode-stop-guard.sh` to optionally return `hookSpecificOutput.additionalContext` (sprint/bridge state + next step) instead of only `decision:block` — richer autonomous-run recovery. | **S** | Better autonomous continuity; small hook edit. | ❌ |
| P5 | **`Tool(param:value)` / `Agent(model:opus)` permission syntax** (2.1.178) | Add to `.claude/settings.json` permissions to harden C-PROC-001 / Agent-Teams rules mechanically (e.g., deny `Agent(model:*)` for teammate types). Settings-level analog of the shipped `disallowed-tools` work. **(See §6 — I could not independently re-confirm the exact 2.1.178 syntax from search; relies on the lens citation.)** | **S** | Finer harness-level enforcement of existing prose constraints. | ❌ |

---

## 4. Deliberately NOT Adopting (avoid hype-driven adoption)

- **Memoizing/caching AUDIT or CONSENSUS VERDICTS** — explicitly harmful per cost research §6 + KF-004 (recurrence ≥28): a cached "APPROVED/0 findings" cements false-clean closures while the sidecar holds real HIGHs. Cache the **input prefix** (cheap, safe); never the **decision**. Prompt caching does not do this — but any home-grown decision cache built "to save cost" would be a mistake. (All four lenses converge here.)
- **Context editing (`clear_tool_uses` / `clear_thinking`) + Compaction (`compact-2026-01-12`)** — designed for LONG multi-turn tool-using agent loops that accumulate history. loa's cheval review calls are **single-shot** completions (one `--input` + one `--system`, no tool-execution loop in the cheval path). Adopting these adds complexity for zero benefit AND would *invalidate the very prompt cache* C1 sets up.
- **Message Batches for INTERACTIVE gates** (`/review-sprint`, `/audit-sprint` foreground) — 50% off comes with async submit/poll and up to a 24h SLA cap; synchronous quality gates with a circuit breaker can't tolerate it. Only the autonomous subset is a candidate (C7).
- **Anthropic memory tool (`memory_20250818`)** — loa deliberately built grimoire-file memory + `known-failures.md` (`memory.schema.json:5` documents the intentional divergence). The Anthropic tool targets intra-session context-window exhaustion in long runs; adopting it would duplicate, not replace, loa's lore layer.
- **Self-hosted sandboxes / MCP tunnels** — solve enterprise tool-execution isolation and private-network MCP reachability. loa's adversarial adapters explicitly do NOT forward tools (gemini/codex headless adapters). No current need.
- **Files API for large diffs** — loa already chunks and the cost research found the large-diff issue handled; the >100K-token sandbox auto-spill is harness-side and free. Low priority vs caching.
- **Native subagents / Workflow tool as a cheval REPLACEMENT** — Claude-only; cannot express loa's cross-vendor (OpenAI/Google/Anthropic) consensus, the within-company `fallback_chain` invariant, circuit breakers (`retry.py`), or the MODELINV envelope. These ARE loa's differentiated value. Scoped pilot of native fan-out for one Claude-only read-only stage at most — same verdict as the 2026-05-31 doc.
- **Fable 5 / Mythos 5 as a deepened dependency** — **Fable 5 and Mythos 5 were SUSPENDED June 12-13 2026** by a US export-control directive (foreign-national access ban, no restoration date; verified via Anthropic's official statement). loa's HTTP path already degrades fable→opus-4-8 (`model-config.yaml:359-362`), but the **headless `cli_model:fable` pin has no such chain**. Do not deepen the Fable dependency; **document the suspension in `known-failures.md` and consider repinning the headless cli_model to opus-4-8** (S-effort awareness/doc item, not a code emergency — other models unaffected).
- **`effort: max` as a default for review/audit** — Anthropic states `high` is the best quality/UX balance on Opus 4.8; keep the advisory `effort_hints` rather than forcing `max`.
- **1-hour cache TTL by default everywhere** — 1h write is 2× (vs 1.25× for 5min) and only pays off at ≥3 reads. Use 1h ONLY for the bridge/serial prefix; 5min default elsewhere.

---

## 5. Sequencing

The natural pairing with the cost-telemetry work (**bd-kyn5**) is the spine of this plan — **measure, then cache, then re-measure**:

**Phase 0 — Quick, cheap, low-risk (do first; pairs with bd-kyn5):**
1. **C2 (cache token parsing) + C8 (count_tokens preflight)** — instrument BEFORE optimizing. This is the cost research's prerequisite. Land the `Usage`/streaming/economy fields so iteration-N input size is recorded.
2. **C5 (Haiku binding for flatline-scorer + triage)** and **C6 (fix or delete the DOWNGRADE no-op)** — both S-effort, both close real config/behavior gaps, independent of caching.
3. **P1 (--safe-mode runbook)** — pure docs, immediate KF-002 triage payoff.
4. **Document the Fable 5 suspension** in `known-failures.md` + consider headless repin (S).

**Phase 1 — The headline cost win (after telemetry exists):**
5. **C3 (opt-in cache field) → C1 (cache_control on the Anthropic adapter) → C4 (1h TTL for bridge)**. With C2 already landed, re-measure: prove `cache_read > 0` on iteration 2+ and report the cache-hit ratio per skill/model. This is the empirical answer to the cost research's "is cost O(depth) or sub-linear?".

**Phase 2 — Quality hardening (parallel, independent of cost work):**
6. **Q1 (structured outputs / strict tool use for adversarial findings) → Q2 (verdict envelope)**.

**Which should be /plan cycles vs quick changes:**
- **/plan cycles (multi-file, cross-map, gated):** C1 (adapter + Bedrock cachePoint parity + per-model `supports_caching` flag), C7 (Message Batches — new async lifecycle; pilot + ADR), Q1 (adversarial path + cheval strict passthrough), C8 (count_tokens helper + gate integration), P3 (post-session hook).
- **Quick changes (single-subsystem, gate-able fast):** C2/C3 (substrate fields), C5 (`model-config.yaml` bindings), C6 (retry/config reconciliation), P1/P2/P4/P5 (settings + hook + docs).

Recommended first cycle: bundle **C2 + C5 + C6 + P1 + Fable-doc** as one "cost telemetry + cheap-tiering + triage-doc" sprint (all S, all independent), then a dedicated **prompt-caching cycle (C1/C3/C4)** once telemetry can prove the win.

---

## 6. Open Questions / Verification Gaps

1. **The "1h→5min default TTL change on 2026-03-06"** (asserted by lenses 1 and 2) is **NOT corroborated** by the live prompt-caching doc I fetched. The doc states the default is "5-minute lifetime" but gives **no historical 1h→5min transition date**. *Confirmed:* default IS 5 min (so C4's rationale stands); *unconfirmed:* the specific "silently dropped on Mar 6" claim — do not cite the date. (Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching)

2. **opus-4-8 context_window — lenses disagree, lens-2 is correct.** Lens-1 claimed opus-4-8 is `context_window: 400000` at `model-config.yaml:46/70/119`. I verified those lines belong to OTHER registry entries; **claude-opus-4-8 is `context_window: 200000` (`:382`), fable-5 `200000` (`:356`), sonnet-4-6 `200000` (`:476`)**. The 1M-context blog claims for Opus 4.8 are **not stated in Anthropic's own Opus 4.8 announcement**. Do NOT raise context_window/max_input_tokens on unverified blog claims — it would re-open the KF-002 input-size failure class. (Lens-2's "do not chase 1M" verdict holds.)

3. **prompt-caching minimum tokens — knowledge-source disagreement, resolved.** Lens-4's claude-api skill listed 4096 for Opus 4.8; the **live docs say 1,024** for Opus 4.8 and Sonnet 4.6 (4,096 for Haiku 4.5) — I fetched this. Use **1,024** for Opus 4.8/Sonnet 4.6.

4. **retry.py DOWNGRADE no-op — CONFIRMED, with corrected path.** The lens cited `retry.py:366-367`; the file is at `.claude/adapters/loa_cheval/providers/retry.py:366-367`, log text verified: `"Budget downgrade triggered — continuing with current model"`, and `walk_downgrade_chain` is invoked nowhere outside tests. C6 is solid.

5. **`Tool(param:value)` / `Agent(model:opus)` permission syntax (2.1.178)** — I confirmed 2.1.178 exists ("22 changes") but could **not independently re-confirm the exact param-matching permission syntax** from search results. P5 relies on the lens citation; verify against https://code.claude.com/docs/en/changelog before implementing.

6. **Batch + caching stacking — CONFIRMED.** Live batch doc: 50% off, most batches <1h (24h SLA cap), 100k req/256MB cap, `max_tokens:0` pre-warming disallowed inside a batch, and 1h cache duration explicitly recommended for shared-context batches (i.e., caching IS supported inside batches and the discounts stack). C7 is well-grounded. (Source: https://platform.claude.com/docs/en/build-with-claude/batch-processing)

7. **Structured Outputs GA — CONFIRMED.** `output_config.format` + `strict:true` tool use, GA, no beta header required, supported on Opus 4.8/Sonnet 4.6 (and Fable 5/Mythos 5, now suspended). (Source: https://platform.claude.com/docs/en/build-with-claude/structured-outputs)

8. **Bedrock caching parity not deep-dived this session.** C1's Bedrock half (cachePoint blocks) was not file-verified beyond confirming `bedrock_adapter.py:595` reads cache usage. The Anthropic-API half is the priority and is fully grounded; scope Bedrock as a follow-up within the caching cycle.

**Sources:** [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) · [Batch processing](https://platform.claude.com/docs/en/build-with-claude/batch-processing) · [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) · [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting) · [Anthropic statement on Fable 5 / Mythos 5 suspension](https://www.anthropic.com/news/fable-mythos-access) · [Anthropic on X (export-control directive)](https://x.com/AnthropicAI/status/2065597531644743999) · [Claude Code changelog](https://code.claude.com/docs/en/changelog) · [Claude Code v2.1.169 notes](https://dev.classmethod.jp/en/articles/20260609-cc-updates-v2-1-169/)