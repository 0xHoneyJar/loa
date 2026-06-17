<!-- Research artifact — NOT an implementation plan. -->
# Research: "Linear Thinking, Nonlinear Costs" applied to loa

- **Source article:** https://www.oreilly.com/radar/linear-thinking-nonlinear-costs/
- **Produced:** 2026-06-17, ultracode research workflow (5 grounded lenses + synthesis, citations verified against source)
- **Status:** RESEARCH / DISCUSSION — no code changes proposed for merge; opportunities are framed as investigate/design.

---


## Executive summary (5 lines)

1. The article's CS-to-agents mapping (memoization / pruning / DP) is sound for *single-voice deterministic* pipelines but materially overreaches on adversarial multi-voice systems, where re-running N independent voices on the same input is the **quality mechanism itself**, not waste.
2. loa is a near-perfect test case because it *is* a multi-model orchestrator — the article applies recursively — and it already embodies most of the article's discipline: circuit breakers as pruning (`retry.py:371`), kaironic FLATLINE convergence (`bridge-state.sh:568`), chain-walk-on-changed-state (`chains.py:26`), a queryable-by-humans decision memo in `known-failures.md`, and a real "invoice" via MODELINV + `economy.py`.
3. The genuine, ranked nonlinear-cost risks are: **bridge iterations re-reading the codebase without a findings-IR (DP anti-pattern)**, **within-entry retries that never mutate the request** (`retry.py:383`), and **no per-iteration cost telemetry** (`economy.py` aggregates per-(skill,model) only) — so loa *sees* cost but not its *nonlinearity*.
4. The highest-leverage research is cheap **observability** (tag MODELINV with `bridge_iteration`, surface cost-delta-per-iteration) before any architectural memoization — you cannot prove the nonlinear-cost claim against loa without it.
5. Where the article would *harm* loa: memoizing audit/consensus verdicts would propagate stale or false-clean verdicts — directly the **KF-004** failure class (recurrence ≥28), where the canonical channel said "0 findings / APPROVED" while the sidecar held real HIGHs. Some quality gates *must* re-run.

---

## 1. The article in one paragraph + critical take

**The article.** "Linear Thinking, Nonlinear Costs" argues that AI agent systems scale cost non-linearly even when their architecture looks linear, because one request fans out into routing/retrieval/reasoning/reflection/guardrails/tools/synthesis. It names three cost-escalation mechanisms — (a) **backtracking without state change** (LLM retries are *not* independent trials: "you sample different paths through the same flawed map"); (b) **repeated context in stateful computation** (overlapping subproblems re-loading shared context); (c) **no decision caching** (the planner state `π(S_t)→a_{t+1}` is re-evaluated rather than stored). It maps three classical CS optimizations onto these — memoization, pruning, dynamic programming — and insists they are **topology-specific**, not a uniform checklist. Its sharpest line: coding agents make systems "easier to GENERATE, but not easier to OPTIMIZE … the invoice is where the hidden computation finally shows up."

**Critical take.** The CS mapping is correct and the vocabulary is genuinely useful, but it has four real gaps, all of which the loa codebase exposes:

- **Adversarial redundancy is the point, not waste.** The article treats "repeated context" and "correlated retries" as pure cost. But loa's Flatline/Bridgebuilder deliberately spend N× to obtain N *independent* voices — diversity is the quality signal (`multi-model-reference.md:30`: `status: clean | APPROVED` is *definitionally impossible when verdict quality is degraded`). The article never distinguishes "redundant computation that wastes" from "redundant computation that triangulates." A memoization pass applied naively here would *delete the feature*.
- **Quality-vs-cost is not addressed.** The article optimizes for cost while assuming quality is fixed. In an adversarial system, pruning voices early trades confidence for dollars — a real tradeoff the article never names. (The findings independently flag this; lens 1 critique point 2, lens 2 article_critique.)
- **Nonstationary state makes memoization unsafe.** The article's `π(S_t)→reuse` assumes stationary state. Code changes, models get swapped (this very session migrated opus-4-7→4-8 per MEMORY.md), prompts evolve. A memo keyed on "codebase state" needs rigorous invalidation that the article hand-waves.
- **The optimization layer has its own cost.** The article *acknowledges* it doesn't discuss "when these optimizations are unnecessary or add their own overhead" — but that omission is load-bearing. A semantic-similarity convergence detector (findings lens 1, FC-001) needs 1-2 extra model calls *per iteration* to score similarity; a decision cache needs maintenance, invalidation, and a correctness story. For a 2-3 iteration bridge loop, the memo machinery can cost more than it saves.

**Steelman.** The core insight — "the invoice is where hidden computation shows up" — is correct and timely, and naming three concrete mechanisms gives teams a cost-audit vocabulary they lacked. loa's own history validates the warnings: KF-002 (empty-content retries at scale), the per-cycle spiral cost, and the absence of cross-iteration findings reuse are all real instances.

---

## 2. Why loa is a near-perfect test case

The article is about multi-model agent orchestrators. **loa is one** — so the article applies *recursively*: every claim can be tested against loa's own substrate.

- loa fans a single `/run` or `/bridge` request into routing (`chains.py` chain-walk), retrieval (`load_bridge_context`, `qmd-context-query.sh`), reasoning (sprint-plan), reflection (Flatline/Bridgebuilder iterations), guardrails (input-size gates, budget enforcer), tool calls, and synthesis (findings parser) — the article's exact fan-out list.
- It is a **hybrid topology**: a centralized orchestrator (`bridge-orchestrator.sh`) dispatching decentralized multi-model voices (`cheval.py` chain-walk per voice). The article claims optimizations are topology-specific but never tests its framework against a hybrid — loa is precisely the untested case (lens 2 article_critique).
- It has the *instrumentation the article wishes generic teams had*: a per-invocation audit envelope (MODELINV, `multi-model-reference.md:29`) and a cost aggregator (`economy.py`). So loa lets us ask not just "does the article apply?" but "given full visibility, *is the cost actually nonlinear*?" — which is the empirically interesting question.

---

## 3. Where loa ALREADY embodies the article's discipline

This is the most important section: **loa is materially more mature than the article's generic reader.** Specific, verified citations:

**Pruning — halt loops yielding no structural gain.** loa has *three* independent pruning gates:
- **Kaironic FLATLINE convergence** (`bridge-orchestrator.sh:41` `FLATLINE_THRESHOLD=0.05`, `:42` `CONSECUTIVE_FLATLINE=2`; `bridge-state.sh:568` `is_flatlined()`, `:558` increments `consecutive_below_threshold`). The bridge loop halts when the severity-weighted score stays below threshold for N consecutive iterations — exactly the article's "halt reflection loops yielding no structural gain."
- **Audit circuit breaker** (`post-pr-orchestrator.sh:194-201`): "same finding 3×" → `halt_reason=audit_circuit_breaker`, with a hard `max_iterations` cap (`:163`, default 5).
- **E2E circuit breaker** (`post-pr-orchestrator.sh:323-330`): "same failure 2×" → halt, `max_iterations` default 3 (`:292`).

**Pruning at the provider level (circuit breaker as the article's "kill unproductive exchanges").** `retry.py:371` `_check_circuit_breaker(adapter.provider, auth_type)` — when the `(provider, auth_type)` bucket is OPEN, the next attempt skips that provider. `_record_failure`/`_record_success` (`retry.py:255/275`) mutate the breaker state *before* the next attempt. This is the article's "stop re-attempting when state hasn't changed," implemented per-provider.

**Chain-walk-on-changed-state (backtracking *with* state change — the productive kind the article under-credits).** `chains.py:26` `walk_fallback_chain` checks **capabilities** (`:105` "missing capability"), **health** (`:115`), and **cycle prevention** (`:83` visited-set) for each candidate. A failed entry does *not* re-run under the same constraint — the entry index advances and the capability/health predicate is re-evaluated against a new provider. This is exactly the article's prescription ("try again under a CHANGED state"), already built in. The within-company invariant in chain resolution prevents the cross-company correlated-retry pattern.

**Input-size gate (fail-fast at zero cost — preempting "expensive failed retries").** Per KF-002 (`known-failures.md:198`), `cheval.cmd_invoke` raises `ContextTooLargeError` (exit 7) *before* adapter setup when estimated input exceeds a per-model `max_input_tokens`. **Correction to the input findings:** the findings repeatedly cite "24K/36K" gates as current — these are the *initial* thresholds. Per `known-failures.md:160`, cycle-109 **raised the walk gate to 200K/180K** and the `loa_cheval.chunking` package was **deleted** (#937/sprint-bug-211, "never load-bearing"). So the lens-1/lens-2 "Cartesian-product cost explosion from a 24K gate" risk is largely stale — the gate now sits far above typical review inputs. The mechanism (fail before paying) is real; the specific cost-explosion numbers are not current.

**Budget enforcement (the article's "invoice," made *predictive at the call boundary*).** `budget.py:91` `pre_call` returns `ALLOW/WARN/DOWNGRADE/BLOCK` *before* the API call; `:132` `pre_call_atomic` does a flock-protected check+reserve. Cost escalation is gated, not merely recorded after the fact. DOWNGRADE (`budget.py:58`) routes to cheaper models on budget pressure — cost-aware model selection.

**MODELINV + economy.py as the article's "invoice."** Every invocation records `models_requested`, `final_model_id`, `models_failed[]`, `verdict_quality` (`multi-model-reference.md:29`). `economy.py` stream-parses `.run/model-invoke.jsonl` into per-(skill, model) cost+quality roll-ups (`economy.py:1-3`). loa *sees the invoice*, step by step — better than the article's assumed baseline.

**known-failures.md as cross-session *decision* memoization.** This is loa's strongest, most under-credited match to the article's "decision caching." KF entries are decision-failure pairs; `Recurrence count ≥ 3` (`known-failures.md:44`) is the load-bearing "this is structural — route through upstream, do not retry the listed attempts" signal. CLAUDE.md mandates reading it *before triaging* — a literal "don't re-reason a failed state" cache. It is human/agent-readable lore rather than a programmatic gate (see §4), but it is genuinely a memoized planner-decision store.

**Shared context within a Flatline phase (the DP "share analysis" pattern, already present).** `flatline-orchestrator.sh` dispatches all voices against the *same* `$doc`/`$context_file` (findings lens 2: `flatline-orchestrator.sh:1299-1300`) — a single shared input, not three independent re-reads. That is DP-style sharing within the phase.

**Net:** loa already implements pruning (3 gates), state-changing backtracking (chain-walk + circuit breaker), fail-fast guardrails, predictive budget gating, full cost observability, and a cross-session decision memo. The article's generic reader has *none* of these.

---

## 4. Genuine nonlinear-cost risks in loa (ranked)

Distinguishing real risks from deliberate quality features:

**R1 — HIGH — Bridge iterations re-instantiate sprint-plan with no findings-IR (the true DP anti-pattern).**
`bridge-orchestrator.sh:424` emits `SIGNAL:GENERATE_SPRINT_FROM_FINDINGS:$iteration` and `:516` calls `load_bridge_context` *every* iteration. Each iteration ≥2 re-runs `/run sprint-plan` (re-reads the codebase to regenerate the architectural decision surface) → Flatline (3 voices re-read) → findings synthesis (re-parse). Cost scales O(iterations × codebase) rather than O(codebase) + O(Δ). This is the genuine "overlapping subproblems without memoization" case — the recomputation is real and *not* a quality feature (re-discovering an unchanged dependency adds no signal). Three findings converge on this (lens 1 opp. for DP sharing, lens 2 IP-001, lens 4 high-severity risk). Mitigant in place: FLATLINE caps depth at converging cases; default `DEPTH=3` bounds the blast radius.

**R2 — HIGH/MEDIUM — Within-entry retries never mutate the request.**
`retry.py:383` `result = adapter.complete(request)` uses the *same* `request` object across attempts 1..N (`MAX_TOTAL_ATTEMPTS=6`, `:30`). On a *transient* failure (network blip, rate-limit-then-recover) this is fine and cheap to recover. On a *structural* failure (prompt rejection, capability mismatch), all retries fail identically — the article's "same flawed map." This is the one place loa does *not* change state before retry (the circuit breaker changes *routing*, not the *request*). Severity is bounded because: the circuit breaker (`:371`) and chain-walk eventually route away, and the most expensive structural case (oversized input) is now preempted by the input gate. Real, but narrower than the findings frame it (lens 2/3 rate it high; lens 3 rates it low — I side with MEDIUM: the escape hatches limit the worst case).

**R3 — MEDIUM — No per-iteration cost telemetry: loa sees cost but not its *nonlinearity*.**
Verified: `economy.py` has **no** `bridge_iteration`, `cost_per_iteration`, or `cost_delta` field (grep returned empty); it aggregates per-(skill, model) only (`economy.py:1-3`). MODELINV records per-invocation but carries no iteration ID. So an operator cannot answer the article's central empirical question — "is cost O(depth) or sub-linear (DP/convergence working)?" This is the meta-risk: the *measurement gap* prevents proving or refuting the other risks. (lens 4 risk + BCP-001/iteration-telemetry opp.)

**R4 — MEDIUM — Voices are not pruned across iterations.**
`bridge-orchestrator.sh` re-invokes the statically configured {primary, secondary, tertiary} voices each iteration regardless of prior-iteration health. `verdict_quality` records a *dropped* voice within an iteration (`multi-model-reference.md:30`), but there is no per-session "voice X exhausted 3× consecutively → skip it next iteration" memo. A persistently-degraded provider is re-attempted every iteration. (lens 1 medium, lens 2 VH-001, lens 4 chain-health-memo opp.) **Caveat:** this is partly *intentional* — re-attempting allows recovery after a transient outage; aggressive pruning risks dropping a voice that has since recovered.

**R5 — LOW — Cross-phase / cross-orchestrator chain re-learning.**
Flatline, Bridgebuilder, and Red-team each run *independent* chain walks; a chain that exhausted in PHASE1 is re-walked in PHASE2 with no memo (lens 4 risk). Budget is post-accounted on failed attempts inside the walk loop, so a multi-entry walk can spend before surfacing CHAIN_EXHAUSTED (lens 2 medium). Low because per-call pre_call gates still fire and the walk is bounded by chain length.

**Explicitly NOT a real risk (deliberate quality feature):** "3 voices read the same input = 3× cost for zero new info." This is the consensus mechanism. The findings' "consensus-early-termination" idea (lens 1) is only safe for LOW-severity findings — for CRITICAL/BLOCKER, full dissent *is* the quality check. Treat as a quality feature, not waste.

---

## 5. Research opportunities (ranked; investigate/design — not implement)

### (a) Cheap instrumentation / observability wins — do these first

- **[S] Per-iteration cost telemetry (article: "make repeated context visible").** Investigate adding a `bridge_iteration` field to the MODELINV envelope and extending `economy.py` to emit cost-delta-per-iteration. This is the prerequisite for everything else: it answers empirically whether loa's cost is O(depth) or already sub-linear (convergence/DP working). Highest signal-per-effort. (lens 4 iteration-telemetry; lens 1 observability opp.)
- **[S] `context_reuse` event on the MODELINV log** when the same (code tree, prompt template, model) is dispatched twice in a session, aggregated into `cost-report.sh` ("X% of cost was repeated context"). Data-driven cost-audit, no behavior change. (lens 1.)
- **[S] Convergence checkpoint surfacing** — read `economy.py`'s `verdict_quality_healthy_pct` and *display* whether iterations 2/3 add structural gain, without yet changing depth. (lens 4.)

### (b) Deeper architectural research — gated on (a)'s data

- **[M] Findings-IR for bridge iterations (article: dynamic programming).** Design an "amendment IR" — `{finding → affected file regions}` — so iteration N+1's sprint-plan re-analyzes only changed regions instead of the full codebase. Addresses R1, the largest real risk. Hard part: defining "region equivalence" and an accurate Git-diff→region map. (lens 1 DP opp; lens 2 IP-001.)
- **[M] Within-entry request-state mutation on *transient* failures (article: backtracking WITH state change).** Investigate a "degraded request" generator for R2: on RATE_LIMITED/CONNECTION_LOST, retry with reduced `max_output_tokens` / "be concise" before walking to the next entry. Must validate it doesn't push quality below threshold. (lens 2 CR-001.)
- **[M] Programmatic known-failures.md gate (article: memoization).** Design a queryable check so an agent *mechanically* consults `Recurrence count ≥ 3` entries before retrying a failure class — converting the human-read lore into a closed-loop decision cache. Note the false-closure risk in §6. (lens 4.)
- **[M] Per-session voice-health memo for R4** — track consecutive CHAIN_EXHAUSTED per voice, demote (not delete) after a threshold, re-probe later. (lens 1 VH-001; lens 2.)
- **[L] Structural (semantic) convergence detector (article: pruning).** Investigate whether findings_N are near-duplicates of findings_N-1 by embedding/phrase overlap rather than raw count, to catch "different rewrites of the same issue." Explicitly weigh the article's unacknowledged cost: this *adds* 1-2 model calls per iteration — only worth it if (a)'s data shows count-based flatline is mis-firing. (lens 1 FC-001.)

**Note where findings are thin/disagree:** the payoff percentages in the findings (e.g., "30-50% cost reduction," "10-30%") are *unvalidated estimates* — none cite measured cost data, precisely because R3 (no per-iteration telemetry) means the data doesn't exist yet. Treat all quantified payoffs as hypotheses to be tested by opportunity (a), not as established savings.

---

## 6. Where the article does NOT apply to loa — or would HARM it

- **Memoizing audit/consensus verdicts would propagate stale or FALSE-CLEAN verdicts — directly the KF-004 failure class.** `known-failures.md:387` (KF-004, recurrence **≥28**): the adversarial-review canonical channel repeatedly reported "0 findings / APPROVED" while the sidecar held real HIGHs (e.g., sprint-bug-213/#1044: 4 HIGH State-Zone guard gaps, all recovered only because every zero-findings verdict is *re-checked*). If loa cached and reused that "APPROVED" decision under the article's memoization principle, it would *cement the false closure* and skip the very re-read that catches it. The operator heuristic — "always suspicious when there are 0" — is the *opposite* of decision caching. **Quality gates that produce clean verdicts must re-run, not memoize.**
- **Correlated-multi-voice is the point, not a correlated-retry bug.** The article's "correlated retries" critique assumes redundancy is accidental. loa's N-voice dispatch is intentional defense-in-depth; `status: clean | APPROVED` is *definitionally impossible when verdict quality is degraded* (`multi-model-reference.md:30`). Pruning voices to save cost on a CRITICAL/BLOCKER finding sacrifices exactly the diversity that makes the gate trustworthy. Consensus-early-termination is safe *only* for LOW-severity findings.
- **Nonstationary state breaks codebase-keyed memos.** loa operates on a mutable codebase and a churning model roster (this session alone: opus-4-7→4-8, grok-adapter added, model-config edits per MEMORY.md). A memo keyed on "codebase/model state" needs invalidation rigor the article never specifies; a stale memo would silently reuse a decision computed under a now-deleted model.
- **The optimization layer's own cost can exceed the saving on short loops.** For the common `DEPTH=3` bridge run, a semantic-convergence detector that adds 1-2 model calls/iteration (FC-001) plus cache-maintenance overhead can cost *more* than the 1-2 iterations it might prune. The article admits it "does not discuss when these optimizations are unnecessary or add their own overhead" — for loa's typical loop depths, that caveat is decisive: instrument first (§5a), and only build memo machinery where measured nonlinearity justifies it.

**Bottom line:** loa is the article's framework already half-built — strong on pruning, state-changing backtracking, guardrails, and cost *visibility*; weak on cross-iteration *analysis reuse* and *iteration-level cost telemetry*. The single most valuable, lowest-risk next step is observability (R3 → §5a), because it is the only way to test whether loa's cost is actually nonlinear before spending effort on memoization that, applied to its adversarial quality gates, could do real harm.

---

**Verified-against-source notes (where findings diverge from current reality):**
- Input-size gate is **200K/180K** (cycle-109, `known-failures.md:160`), not the "24K/36K" the findings cite as current; `loa_cheval.chunking` is **deleted** (#937). The R3-class "Cartesian cost explosion from a 24K gate" in lens 1/2 is largely **stale**.
- KF-004 recurrence is **≥28** (`known-failures.md:387`), not "≥24" as one finding states.
- `economy.py` confirmed to have **no** per-iteration field (grep empty) — the "no per-iteration telemetry" claim is correct and load-bearing.
- All bridge/post-pr/retry/budget/chains line citations above were verified directly against the files at the listed line numbers.