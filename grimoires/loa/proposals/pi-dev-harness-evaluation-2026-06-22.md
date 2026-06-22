# pi.dev (Pi) Harness — Adoption / Adaptation / Fusion Evaluation

> **Decision class:** multi-model substrate / dependency strategy
> **Date:** 2026-06-22
> **Question:** Can/should loa adopt, adapt, fuse-with, or migrate to **pi** (pi.dev) to fix
> multi-model-provider instability? Spectrum from partial adoption → wholesale migration → fusion.
> **Method:** ultracode multi-agent workflow — 15 agents (6 parallel research [pi-ai provider/auth/failover,
> pi engine extensibility, maturity-vs-alternatives, cheval grounding, harness portability, economics/capacity],
> 5 spectrum option-models, 3 adversarial challenges, 1 PhD-principal synthesis). ~1.08M tokens.
> Findings cross-validated against independent maintainer web-fetches of pi.dev docs + GitHub.
> **Bottom line:** **S0 — keep & harden cheval. pi does not fix the instability.** (See §1.)

---

# OPTIONS MEMO: pi (pi.dev) for loa's Multi-Model-Provider Instability

**To:** @deep-name (maintainer) · **From:** Principal Eng review · **Date:** 2026-06-22 · **Decision class:** substrate / dependency strategy

---

## 1. TL;DR / Bottom line

**Recommendation: S0 — keep cheval, harden it. Do not adopt, fuse-with, or migrate to pi.** The instinct that pi is the answer rests on a misdiagnosis of where loa's pain lives. pi-ai is a thin, *stateless transport surface* that sits **below** loa's value layer; loa's documented instabilities (KF-002 streaming/all-voice-fail, KF-017 chain-walk-past-`INVALID_CONFIG`, KF-018 tier-death) are auth/billing/tier-death and **caller-side routing** conditions that pi explicitly delegates to the caller — i.e., to exactly the cheval layer pi lacks. So **pi does not fix the instability**: it neither causes nor cures it. Worse on the second motivation: pi's subscription economics are *narrower* (Anthropic/Codex/Copilot OAuth only, vs loa's five-CLI headless fleet) and confer **zero flat-rate Claude advantage**, because pi drives Claude Pro/Max through the identical `claude -p` OAuth path loa already uses — now billed per-token "extra usage" under Anthropic's ~Apr-4-2026 policy (pi #3670, claude-code #43333). The honest narrow exception: pi-ai is a credible *reference* and a legitimate *single-adapter library* for long-tail API-key transport breadth, behind cheval's existing seam. Everything above S0 is negative-to-zero EV for a solo+AI maintainer.

## 2. What pi actually is (and what it isn't)

pi is two distinct things, and conflating them is the first error to avoid:

- **pi-ai** (`@earendil-works/pi-ai`) — a standalone, batteries-or-minimal **provider/transport library** (Node + browser). `getModel(provider, modelId)` + `complete(model, context)`. 25+ API-key providers; OAuth for **exactly three** (Anthropic, OpenAI Codex, GitHub Copilot — verified in `packages/ai/src/utils/oauth/index.ts`: `loginAnthropic`, `loginOpenAICodex(+DeviceCode)`, `loginGitHubCopilot`, refresh helpers). **No `loginGeminiCli`, no Cursor, no Grok** subscription login — the earlier "Gemini CLI login" claim is **wrong** and should be struck from the requester's prior.
- **pi-agent-core / pi-coding-agent** — pi's *own harness* (agent loop, TUI, extension system). This is what an "S3 fusion / S4 wholesale" would subordinate loa to.

**Correcting the over-claim that pi is "widely respected/stable":** the evidence is thinner than the prior assumes. The npm page returned HTTP 403 — release cadence and version are *unverifiable*; the project is described as young and fast-moving. pi-ai has **no** built-in failover, retries, circuit-breaking, streaming recovery, or normalized error taxonomy (README + source: no `retry/` or error-taxonomy file). Its error model collapses everything except `length` into free-text `stopReason: 'error'`. It is a clean *call surface*, not a resilient *substrate*. "Respected reference implementation for transport breadth and OAuth ergonomics" is defensible. "Stable foundation to bet a governance-critical framework on" is **not yet** supported.

## 3. What loa's instability actually is

Three categories, only one of which an architecture swap could touch:

| Class | Examples | Can pi help? |
|---|---|---|
| **Operational (upstream/vendor)** | KF-002 all-voice-fail = dead subscription/auth/billing/tier; KF-018 gemini-headless tier deprecated; the `claude -p` per-token policy | **No.** A library swap cannot revive a dead Max subscription or a deprecated tier. KF-002 is RESOLVED-STRUCTURAL precisely because it's not an abstraction bug. |
| **Failover-logic (caller-side, owned code)** | KF-017 prefer-api chain hard-aborts on a leading CLI `INVALID_CONFIG` instead of walking to the valid HTTP leg; streaming-recovery thresholds | **No — and pi makes it harder.** This is the *chain-walk* layer pi disclaims. You'd rebuild it on coarser primitives. |
| **Detection gaps** | KF-018 `gemini --version` probe can't detect tier-death (only real inference's `IneligibleTierError` does) | **No.** This is a health-probe design fix in loa's own adapter. |

**Key insight:** the instability is *above* where pi operates. pi replaces the transport tier (the thinnest, most-replaceable, *least-volatile, already-working* part) and disclaims the resolution/resilience tier (the part that's actually flaky AND the part that closed KF-002/017/018). An engine swap therefore relocates loa's most defensible code onto a foundation that provides none of its machinery — replacing a solved problem with a harder unsolved one.

## 4. The pivotal constraints

1. **Subscription-auth economics.** loa shells to five vendor CLIs (claude/codex/gemini/cursor/grok) for *flat-rate* subscription inference — this *is* the cost model. pi's OAuth covers three (Anthropic/Codex/Copilot); routing any of gemini/cursor/grok through pi pushes them to **metered API-key** paths — a quantifiable regression. And pi's Claude OAuth = the same metered `claude -p` path loa already eats (verified in `claude_headless_adapter.py:1-27`: OAuth-managed store, no `ANTHROPIC_API_KEY`). **Net Claude economics from pi: nil-to-negative.**
2. **The governance/compliance moat.** MODELINV envelope per call (`.run/model-invoke.jsonl`), Ed25519 hash-chain (`audit_envelope.py` 648 LoC + `jcs.py`), company-family no-cross-company fallback + voice-drop (data-declared in `model-config.yaml`, lint-enforced), compliance_profile routing, verdict-quality envelope, typed exits (`ContextTooLargeError`=7, `INVALID_RESPONSE`=5, `EMPTY_CONTENT`, `PROVIDER_DISCONNECT`). pi gives raw `onPayload`/`usage.cost` *hooks*, **not a signed audit artifact** — and it's *unverified* whether `onPayload` even fires on every streaming/tool-call turn (an unacceptable gap for a per-call audit guarantee). Any pi path must rebuild the moat as a consumer.
3. **Python/bash vs TS reality.** cheval is ~22.6K LoC Python; the harness is ~560K LoC across 353 bash scripts, 35–40 skills, 24 hooks. The *only* TS in the repo is bridgebuilder-review. The existing TS↔Python seam runs **TS→Python** (`cheval-delegate.ts` spawns `python3 cheval.py`). Any pi-as-transport option **inverts** this — Python spawning a TS sidecar on every governed call (BB benchmark: spawn worst p95≈126ms; daemon-mode explicitly deferred).
4. **Solo+AI capacity & compounded bus-factor.** Putting a young, externally-controlled, bus-factor-1 TS engine *under* loa's stability layer (known-failures.md, audit chain, beads) inverts the direction of trust. A breaking `onPayload`/`usage` change silently corrupts MODELINV → the Ed25519 chain and economy rollup. You'd make your *governance artifacts* hostage to an upstream you can't reliably pin.

## 5. The adoption spectrum

| Option | Thesis | Preserves | Sacrifices | Cost | Risk | Reversibility | Verdict |
|---|---|---|---|---|---|---|---|
| **S0** status-quo + harden | Fix KF-017/018 in owned code; moat untouched | Everything (moat, economics, Python/bash) | Provider breadth; chance to shrink adapter surface | Low (2 micro-sprints) | Low | Easily reversible | **RECOMMEND** |
| **S1** pi-ai as transport (under cheval) | Swap ~9 HTTP adapters for pi; keep cheval on top | Moat + resilience; partial economics | 9 working adapters; single-language purity; in-process httpx; typed-error fidelity | High, no benefit | Med-High | Reversible w/ effort | **NOT-ADVISED** |
| **S2** pi-core sidecar over RPC | pi as dispatch engine, harness above | Only in strict pi-below-cheval pilot | Economics (metered conversion); typed exits; in-engine MODELINV | Pilot low/multi-month real | High | Reversible w/ effort | **NOT-ADVISED** |
| **S3** fusion (pi=engine, loa=extensions) | Re-express loa as pi extensions | Nothing automatically — all moat must be rebuilt | Architectural control; Python substrate; 5-CLI breadth; simplicity invariant | Very high (multi-month) | High | One-way door | **NOT-ADVISED (TRAP)** |
| **S4** wholesale migration | loa becomes a pi distribution | Almost nothing (philosophy only) | Cost model; resilience layer; signed audit; language fluency; release independence; identity | Very high (multi-quarter) | Existential | One-way door | **NOT-ADVISED** |

**S0** — The two named defects are small, local, in owned code: KF-017 is a missing walkable-disposition arm in cheval.py's chain-walk loop (it already has clean `except→continue` arms for CONTEXT_TOO_LARGE/EMPTY/RATE_LIMITED/etc.; `INVALID_CONFIG` is the missing one); KF-018 is swapping a `--version` probe for a rate-limited real-inference auth probe. Both are test-first patches the 85-test suite can pin, landed through loa's own `/bug → implement → review → audit` gates. Zero new runtime, zero external dep, zero moat disruption. It does *not* cure upstream vendor billing/tier-death — by design, nothing can.

**S1** — Scoped correctly it keeps the moat, but it inverts the TS↔Python seam onto the hot path of every governed call, forces a lossy TS-free-text→typed-exit translation shim (re-creating classification pi threw away), can dilute economics if any non-OAuth voice routes through pi, and introduces an audit-trust seam where un-redacted payloads transit a third-party process *before* loa's fail-closed redactor. High integration cost for a layer that already works.

**S2** — Architecturally redundant: `cheval.py` (2,358-line CLI with `--output-format json`/`--json-errors`) *already is* the dispatch sidecar reached over an RPC-shaped boundary (cheval-delegate.ts). pi-above-cheval duplicates it; pi-replaces-cheval guts the moat. The narrow pilot is feasible but its payoff is ~nil (metered breadth loa doesn't need).

**S3** — **The trap.** It misidentifies the moat as "skills on top, swap the engine," when loa's actual moat is the *middle resilience tier* + *subscription economics* — pi is weakest at the first and dilutive to the second. It preserves loa's IP only by *refusing to actually fuse* (keep your own headless adapters anyway), contradicting its own premise.

**S4** — Self-liquidation. "loa" is not its model layer; it's 560K LoC of harness. Re-homing onto pi's agent model loses 3 of 4 headless subscription paths, destroys the signed audit chain, and ends with strictly fewer capabilities plus a young external single-point-of-failure — against a *misdiagnosed* root cause.

## 6. Recommendation

**Execute S0. Treat S1's narrow tactic as a conditional, gated, single-adapter library borrow — never as an engine.**

Reasoning: the two motivations were (a) instability and (b) economics. On (a), pi sits below the layer that fails; the fix lives in cheval's chain-walk loop and health probes — code loa fully owns and can land in two bounded micro-sprints. On (b), pi is *narrower and dilutive*, not cheaper. Every option above S0 pays a rewrite tax in a foreign runtime, keeps loa's hard requirements, gains no stability, and risks the economics — strictly dominated.

**Sequenced path:**

1. **Now:** KF-017 micro-sprint — add the walkable `INVALID_CONFIG`/adapter-wiring disposition arm in cheval.py's chain-walk loop + chain_resolver coverage; test-first bats/cheval pins. *Gate to step 2:* review+audit APPROVED, MODELINV envelope unchanged, prefer-api now walks past a leading dead CLI leg to a valid HTTP leg (reproducible test).
2. **Next:** KF-018 micro-sprint — replace `gemini --version` (audit the other four headless) with a rate-limited/cached real-inference auth probe that surfaces tier-death. *Gate:* probe detects `IneligibleTierError` without burning meaningful subscription quota (caching/rate-limit validated).
3. **Only if** a genuine need for a long-tail API-key provider cheval lacks arises (DeepSeek/Mistral/new Bedrock model): run the SPIKE in §7 before vendoring one pi-ai transport behind `_get_adapter_for_entry`.

**Kill-criteria for ever escalating beyond S0:**
- Abandon any pi adoption if the SPIKE shows pi's `onPayload` does **not** fire on every streaming/tool-call turn (breaks MODELINV per-call guarantee).
- Abandon if a pi transport leg cannot be made to emit loa's existing typed-exit taxonomy without a fragile regex shim.
- Never proceed to S2/S3/S4: the moment pi becomes the *engine* (not a single leg), economics regress and the audit chain must be rebuilt against a moving external API — one-way doors with negative EV.

## 7. A concrete next step — time-boxed SPIKE (≤ 2 days, no one-way door)

**Goal:** de-risk the *only* defensible pi tactic (single API-key transport leg behind cheval) without committing the substrate.

**Build (throwaway branch, not merged):**
- A minimal Node script using `@earendil-works/pi-ai/base` registering *one* transport (e.g., DeepSeek or Mistral), invoked via `getModel()+complete()`.
- Wrap it behind a stub matching cheval's adapter contract; have it emit a MODELINV-shaped envelope from `onPayload`+`usage`.

**Measure / success criteria:**
1. Does `onPayload` fire on **every** turn including streaming + a tool-call turn? (binary; if no → **kill**, MODELINV guarantee fails)
2. Can pi's free-text `errorMessage` be mapped to cheval's typed exits (7/5/EMPTY_CONTENT/PROVIDER_DISCONNECT) for ≥4 forced error cases **without** brittle string-matching? (if no → **kill**)
3. Spawn p95 latency for the Node leg vs the in-process httpx baseline (must be within the BB-measured ≈126ms envelope; document daemon-mode cost if exceeded).
4. Is `usage.cost.total` byte-stable and trustworthy enough to feed the economy rollup? (sample 20 calls; compare to provider billing)

**Decision rule:** all four green → vendoring *one* pi transport behind cheval's seam for a *net-new long-tail provider* is reasonable (dependency stays below a thin loa-owned wrapper, typed taxonomy preserved, economics untouched). Any red → **stop at S0 permanently**; do not revisit pi for transport.

## 8. Risks & open questions

- **Upstream-attribution uncertainty:** whether the Claude OAuth per-token billing is *fixed, partial, or permanent* is contested (pi frames it as deliberate Anthropic policy; claude-code #43333 marked closed/resolved). Either way it hits loa's existing `claude -p` adapter *identically* — pi neither causes nor cures it. **No option controls this residual upstream risk.**
- **Codex/Copilot billing unverified:** whether pi's Codex/Copilot OAuth still maps to plans (vs metered) was not confirmed — relevant only if loa ever wanted those voices via pi (not recommended).
- **pi transport-level retry:** confidence is *high* that pi has no cross-provider failover, *medium* that there's zero undocumented transport-level retry (no `retry/` file, but not line-audited). Immaterial to S0.
- **pi stability profile:** version/cadence unverifiable (npm 403). This alone disqualifies pi as a *foundation* dependency for a solo-maintained governance-critical repo; it does not disqualify pi as a vendored *reference* for one leg.
- **KF-018 probe cost:** a real-inference auth probe burns a small amount of subscription quota per health check — must be rate-limited/cached. Known, manageable design point flagged in the S0 sprint.

**Relevant grounding files:** `/home/merlin/Documents/thj/code/loa/.claude/adapters/cheval.py` (2,358-line resolution core), `/home/merlin/Documents/thj/code/loa/.claude/adapters/loa_cheval/audit_envelope.py` (Ed25519 chain), `/home/merlin/Documents/thj/code/loa/.claude/defaults/model-config.yaml` (data-declared fallback_chain/dispatch_group), `/home/merlin/Documents/thj/code/loa/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:1-27` (the metered `claude -p` path), `/home/merlin/Documents/thj/code/loa/grimoires/loa/known-failures.md` (KF-002/017/018).

---

## Appendix A — Provenance & method

Produced by a deterministic multi-agent workflow (`pi-dev-adoption-options-memo`), 2026-06-22:
- **Research (6 agents, parallel):** pi-ai provider/auth/failover; pi engine extensibility (fusion feasibility);
  pi maturity vs alternatives (LiteLLM / Vercel AI SDK / OpenRouter / Aider / OpenCode); cheval current-state
  grounding (KF-002/017/018/019, MODELINV, Ed25519, company-family chains); loa harness portability; economics & capacity.
- **Options (5 agents):** modeled the spectrum S0–S4 with a structured pros/cons/cost/risk/reversibility schema.
- **Adversarial challenges (3 agents):** fusion stress-test; "does pi fix the instability?"; status-quo-vs-minimal.
- **Synthesis (1 agent):** PhD-principal-engineer voice, high reasoning effort.

Two pivotal facts independently re-verified by the maintainer against live pi.dev docs/GitHub:
1. **Subscription auth is partial & economically nil-to-negative for loa.** pi `/login` OAuth covers only
   Anthropic (Claude Pro/Max), OpenAI Codex, GitHub Copilot — *not* Gemini/Cursor/Grok (API-key-only). And pi
   drives Claude Pro/Max through the *same* `claude -p` OAuth path loa already uses, now billed **per-token
   "extra usage"** under Anthropic's ~Apr-2026 policy change (pi #3372/#3670, claude-code #43333).
2. **pi-ai has no failover.** No cross-provider fallback chains, no retries, no circuit-breaking — failover is
   explicitly the caller's responsibility, i.e. exactly the cheval layer pi lacks.

## Appendix B — Key sources

- https://raw.githubusercontent.com/earendil-works/pi/main/packages/ai/src/utils/oauth/index.ts
- https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md
- https://pi.dev/docs/latest/providers
- https://github.com/earendil-works/pi/issues/3670
- https://github.com/earendil-works/pi/issues/3372
- https://github.com/anthropics/claude-code/issues/43333
- https://raw.githubusercontent.com/earendil-works/pi/main/packages/ai/README.md
- https://github.com/earendil-works/pi/blob/main/packages/ai/README.md
- https://github.com/earendil-works/pi/tree/main/packages/ai/src
- https://github.com/earendil-works/pi
- https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/extensions.md
- https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/extensions/types.ts
- https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md
- https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/README.md
- https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/packages.md
- https://github.com/earendil-works/pi/releases/tag/v0.63.0
- https://github.com/earendil-works/pi/issues/2696
- https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/CHANGELOG.md (grep -in breaking/removed/migrat; 251 '## [' headers)
