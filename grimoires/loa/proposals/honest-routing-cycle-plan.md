# Proposal: Honest-Routing Cycle — sequence #1027 / #1006 / #1001 (+ #1058, #1032)

**Status**: DRAFT (sequencing plan; operator-gated — no admin-merge for the dispatch-core items)
**Author**: Synthesized 2026-06-15 from RFC review of #1006 / #1001 against current `main` (counter=221)
**Related**: #1006, #1001, #1027 (R8), #1032 (R2), #1058 (zkSoju draft), #999, #1000, #1055, #1013, KF-002/KF-004
**Scope**: cheval dispatch core — model identity (headless leg) + budget actuation (meter→router)

---

## The throughline

Loa has been on a multi-cycle arc toward **honest, operator-asserted model routing** — the dispatched
model must be the one that was actually requested/intended, and the audit envelope must not lie about it:

| Cycle work | Contribution to the arc |
|---|---|
| #999 | `claude-fable-5` as a first-class model identity |
| #1000 | per-actor attribution (who spent / who dispatched) |
| #1055 (merged 2026-06-15) | bedrock forward-routing — dispatch the operator-asserted equivalent, not a silent default |
| #1013 (merged 2026-06-15) | headless reasoning timeout — the headless leg finishes instead of being killed |

The two open RFCs are the **last two teeth** of this arc, and both rhyme with Loa's deepest recurring
failure family (KF-002/KF-004: *"the headline says X, the reality is weaker"*):

- **#1006** makes the headless leg honest about **which model actually ran**.
- **#1001** makes budget pressure **actually act** (meter→router) and be honestly audited.

Both are `strongly-validated` (grounded line-refs, not speculative). Both change the dispatch core that
**every quality gate depends on**, so both are operator-gated, full-Flatline, `/plan`-grade cycle work —
**not** the autonomous `/bug` lane.

---

## Why this matters (the integrity hole)

`claude-headless` pins `extra.cli_model: sonnet` (model-config.yaml). All four headless adapters
(`claude_/codex_/cursor_/gemini_headless_adapter.py`) resolve `cli_model = extra.cli_model or request.model`
identically. So **any** chain-walk to the headless terminal — and every historical council / Flatline
claude-voice in the fallback path — silently ran **sonnet** while MODELINV recorded `claude-headless`.
A "3-voice opus consensus" verdict, in the fallback path, was partly weaker than recorded. For a framework
whose review/audit/Flatline gates are load-bearing, that is an audit-integrity defect, not cosmetic tech debt.

---

## Sequenced plan (smallest-blast-radius first; each reinforces the next)

### Phase 1 — #1027 (R8): shared `HeadlessCLIAdapter` base
**Why first.** There are now **four** ~75%-clone headless adapters. Phase 2's `cli_model_map` must land in
**one** place, not be forked 4×; R8 also consolidates the security posture (#1008 codex hardening, #1048
cursor sandbox) into a single base instead of four divergent copies.
**Scope.** Extract the shared command-build / model-resolution / sandbox-flag surface into a base class;
the four adapters become thin provider-specific subclasses.
**Gate.** Refactor — behavior byte-identical; pin with the existing adapter test suites (no MODELINV change).
**Blast radius.** Medium (all headless dispatch), but mechanically a no-op if the suites stay green.

### Phase 2 — #1006: model-aware headless dispatch (+ supersede #1058, fold #1032)
**Design.** Extend the (now shared) base with `extra.cli_model_map` (requested-model → CLI literal), keyed
on the **originally requested** model (pre-chain-walk; `models_requested[]` already carries it in MODELINV).
Add `cli_model_dispatched` to the MODELINV envelope so it is honest about what ran. `claude-headless`
default stays `sonnet`; consumers ask for the one alias (`fable`/`opus`) and get HTTP when a key exists,
subscription-headless dispatching the requested model otherwise.
**Reconcile #1058 (zkSoju).** Soju's draft "anthropic voice → Opus 4.8" is attacking the **same** problem
from the config-fork side. Adopt `cli_model_map` as the canonical design and redirect/supersede #1058 —
do not land two overlapping mechanisms.
**Fold #1032 (R2).** Single-source model/pricing registries is a natural companion (model-identity
coherence) — do it adjacent or within this phase.
**Gate.** Operator-gated; full Flatline; ship with **before/after MODELINV evidence** proving a `fable`
request through the headless leg now records `cli_model_dispatched: fable` (not silent sonnet).
**Blast radius.** Contained to the headless leg + the envelope schema.

### Phase 3 — schema reconciliation (hard prerequisite for #1001)
**The contradiction.** `validate_tier_groups` (routing/tier_groups.py) requires `mappings` to be
string→string, but the shipped config uses per-provider dicts (`max: {anthropic: fable, openai: gpt-5.5-pro,
google: gemini-3.1-pro}`, pinned by the c114-FR8 test). Resolve **before** any actuator work: either the
validator learns the per-provider-dict shape (preferred — keeps the richer config), or the config flattens.
**Gate.** Schema/validator change with the c114-FR8 test updated in lockstep.

### Phase 4 — #1001: DOWNGRADE actuator + `apply_tier_groups`
**Design.** Bind `BudgetEnforcer.pre_call`'s DOWNGRADE (budget.py:91) to an actuator at the dispatch sites
(cheval.py ~:1942/~:1962, currently `== "BLOCK"`-only) — rung-down **within provider** on the unified
hounfour ladder, with `routing.downgrade` as an explicit override map. Implement `apply_tier_groups`
(currently a stub). The model must still be mutable when DOWNGRADE arrives (chain entries are resolved
earlier by `chain_resolver` — bind at `invoke_with_retry` / the manual-fallback site).
**Gating.** Per-agent-binding `downgrade_allowed` (default true; false = never touch this binding) — this is
finally the consumer that earns the construct-manifest field. Prereq attribution (#1000) is already merged.
**Audit.** Every actuated downgrade lands in MODELINV (`models_requested` vs `final_model_id` already exist)
plus a WARN log.
**Gate.** Operator-gated; full Flatline; the riskiest item (changes the dispatch core of *every* cheval call)
— do it last and alone.
**Blast radius.** High (every cheval call) — hence last, after the honesty work and the schema fix.

---

## Ordering rationale

```
#1027 (R8 base)  →  #1006 (honest model identity, +#1058 supersede, +#1032)  →  schema fix  →  #1001 (honest budget actuation)
   refactor            audit-integrity bug                                        prereq          dispatch-core change
   (no behavior Δ)     (contained, high value)                                    (validator)     (broad, high value, riskiest)
```

Smallest blast radius first; honesty before actuation; the prerequisite schema fix isolated as its own
step so #1001 doesn't fight the validator. Each phase ships with MODELINV before/after evidence — the arc's
acceptance test is "the envelope stopped lying."

## Per-phase acceptance evidence (the honest-routing bar)

| Phase | Evidence that it landed honestly |
|---|---|
| #1027 | adapter suites green; zero MODELINV/output delta on a fixed dispatch |
| #1006 | a `fable` request via the headless leg records `cli_model_dispatched: fable`; no entry-fork added |
| schema | `validate_tier_groups` accepts the per-provider-dict config; c114-FR8 green |
| #1001 | a budget-pressured call records an actuated downgrade in MODELINV + WARN; `downgrade_allowed:false` binding is never touched |

## Out of scope / decisions for the operator
- Whether #1058 is **closed-as-superseded** or **redirected** to implement #1006's design (coordinate with @zkSoju).
- Whether to run this as one multi-phase cycle or four sequential `/bug`-sized micro-cycles (recommend: cycle
  for #1006 and #1001 given their blast radius; #1027/#1032 can be standard refactor sprints).
