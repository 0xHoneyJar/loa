# Mechanical Floor — Methodology Report (cycle-119, 2026-07-07)

> **Audience**: future models (and operators) extending Loa's model-economy work.
> This documents the reasoning behind every change and every deliberate NON-change,
> so the strategy can be continued without re-deriving it.
>
> **Operator directive** (verbatim intent): *"with fable as orchestrator use whichever
> token efficient model sufficient for the job providing fable ensures results are fable
> level quality. review and refactor where needed all loa skills and key processes to
> allow models less competent than fable to achieve near fable method, processes and
> outcomes… make loa as competent, effective whilst being as token efficient as possible."*
> Admin pre-approved end-to-end. Epic `bd-pluh`; branch `feat/cycle-119-mechanical-floor`.

## 1. Thesis

**Intelligence the model must supply is intelligence the framework failed to encode.**
Every place a skill says "assess", "use judgment", or walks the model through a
5-step rubric it must simulate, the framework is renting capability from the model —
paid in tokens on every invocation and in reliability whenever the model is weak.
The refactor direction is therefore always the same:

- move model-simulated work into **scripts, hooks, and schemas** (the mechanical floor),
- keep expensive judgment **only where evidence says it is load-bearing**,
- and let orchestrators dispatch the **cheapest sufficient model** because the gates,
  not the model, hold the quality floor.

Quality is protected by making weak-model failures **loud and repairable**
(validators with exact repair text, repair loops, one-way verdict rules), not by
using big models everywhere.

## 2. Evidence base (how we knew, not just what we did)

A 20-agent analysis fan-out (run `wf_17474c97-480`) mined ~4.5 GB of real session
transcripts across the loa repo and 16 hosaka fleet repos, the MODELINV audit log
(1,183 envelopes), the full 40-skill census, the 53-command census, and both
pipeline/multi-model process censuses. Load-bearing findings:

| # | Finding | Number |
|---|---------|--------|
| E1 | Usage concentrates in the pipeline core | implement ~505, review ~352, audit ~328, bug ~256 invocations; long tail ≈ noise |
| E2 | #1 mechanical error: write-before-read | ~2,312 occurrences fleet-wide (prose ALWAYS-rule demonstrably insufficient) |
| E3 | Skills carried model-simulated middleware | input_guardrails ×9, prompt-enhancement ×4, retrospective ×3, attention/memory/clearing ×8 — re-emitted per invocation |
| E4 | Every pipeline gate was self-attestation | `grep -q` for a verdict string written by the same model being gated |
| E5 | Cheap-tier usage in real work ≈ 0% | opus ~83K message-tags vs sonnet 3 in one repo group; cheval `advisor_strategy` production-dormant |
| E6 | Claude Code natively supports the needed knobs | SKILL.md `model:`/`context: fork`; `.claude/agents/*.md` with `model:`; benign failure (unknown keys ignored) |
| E7 | The tiering boundary is rubric-vs-judgment | PR #885: executor −60% findings on open-ended review (UNSAFE); cycle-116 D3: Sonnet = Opus (0.90/0.90) on constrained scoring |
| E8 | KF-004 (rec 4): schema-strict parsing silently ate findings | no repair loop; flatline's tolerant parser proved the pattern |
| E9 | Pseudocode-as-spec was the #1 weak-model hazard | run.md's bash-shaped functions defined nowhere |
| E10 | Largest single token sink: unbudgeted fan-outs | one adversarial verification pass = 892K subagent tokens |

## 3. Principles (decision rules — reuse these)

- **P1 Mechanize before economize.** Never downtier a stage whose output gate is
  self-attestation. Build the mechanical gate first; the cheap model comes second.
- **P2 Rubric tasks downtier; open-ended judgment does not.** (E7.) Review, audit,
  red-team, BB stay advisor/session-model. Scoring, triage, extraction, mining are
  candidates — with gates.
- **P3 Additive + default-off + benign-failure.** Fleet consumers on old harness
  versions must see zero behavior change.
- **P4 One canonical home per rule.** Skills reference protocols/scripts; restating
  CLAUDE.loa.md content in a skill is a bug.
- **P5 The block message is the repair prompt.** Every gate/hook failure text must
  contain the exact corrective command a weak model can follow.
- **P6 Instrument what you change.** Reuse the #1177-D degraded-trajectory schema and
  MODELINV attribution; never invent a parallel telemetry channel.

## 4. What shipped (with reasoning)

| Change | Reasoning trace |
|--------|-----------------|
| Middleware mechanization across 12 workflow skills (−9,251 words measured on the skills+commands surface, −17.2%) | E3: the blocks asked the LLM to emulate scripts. Guardrails → one `guardrails-orchestrator.sh` call with an explicit fail-open exit contract; enhancement/retrospective → 2-line config-gated pointers to their owning skills; attention/memory/clearing trio → one compact context_discipline block. Tokens saved per invocation AND diligence-dependence removed. |
| LOA-VERDICT trailer + `verdict-derive.sh` | E4: gates grep'd self-written prose. The trailer is machine-checkable; the validator enforces prose/trailer agreement and the **one-way rule** (critical+high>0 ⇒ CHANGES_REQUIRED; zero counts never force approval — panel caught that a bidirectional rule would invite severity-label gaming). Golden-path consults the trailer structured-first with byte-identical legacy fallback (7-consumer inventory verified by execution). |
| `validate-ac-verification.sh`, `validate-artifact.sh` (prd/sdd/sprint/bug-triage) | Census P0s on the highest-usage skills. Honest scoping documented in-script: these prevent ABSENT evidence/sections, not fabricated ones. One parameterized artifact validator instead of four near-identical scripts (ROI-lens cut). |
| run-family fold + de-pseudocode | E9. State machine now lives in run-mode SKILL.md as numbered imperative steps invoking real scripts; 5 commands are thin routers; the literal "Sleep" suggestion replaced with the until-loop/Monitor snippet. |
| `.claude/agents/loa-scout.md` (Haiku, read-only) + manifest distribution + C13 lint | The ONE agent the evidence justified (fan-out evidence gathering, E10-adjacent). The C13 lint (`role: review\|audit` forbids `model:`/`agent:` frontmatter) is the Claude-harness twin of cheval's NFR-Sec1 — tier-demotion of verdict-bearing work is now mechanically impossible on both dispatch layers. |
| KF-004 repair loop (default OFF) | E8. Four panel-mandated safety constraints: case-fold-only normalization, ONE bounded round-trip, full-pipeline re-entry, byte-immutability of non-violated fields (anti-laundering). Rejected/repaired counts emit into the existing degraded-trajectory channel so eaten findings become visible. |
| Safety-hook find-exec root classification + block-text audit | The mined FP corpus was stale (redirect FPs already fixed at HEAD; fleet runs old hooks — a rollout item, not code). Only the find-exec shape still reproduced. Fixtures-first; `$`-expansion operands NEVER allowed; exactly-one-root token walk; nested-find disqualifier. Block texts now name concrete alternatives (P5). |
| MODELINV skill attribution (flatline-`<mode>`, adversarial-`<type>`) | D-6 slice: the economy roll-up was 100% (unattributed); cheval `--skill` already existed and threads to `calling_primitive` — two dispatch sites now pass it. Future tier decisions become per-skill empirical. |
| zone-guard framework-dev authorization marker | Discovered mid-cycle: the guard (inert until #1002) blocks agent framework-zone writes, and its documented env escape can't reach hook subprocesses from agent tool calls. The marker (`.run/zone-guard-authorization.json`: scope+reason+expiry, 24h mtime cap) is equal-trust with zones.yaml per the hook's own argument, but audited per-write and expiring. ZWG-T20..25. |
| `validate-gitignore-state.sh`, gpt-review stub, butterfreezone chain fix | Small mined-error burndowns: 168 gitignored-state-add failures; 1,814 dead deprecated words with no invocation guard; a skippable validation phase. |

## 5. What was deliberately NOT done (equally load-bearing)

| Cut | Reasoning |
|-----|-----------|
| 7 long-tail skill `model:` pins + a `loa-executor` agent | Zero measured traffic on those skills (E1) → pins would be **decorative config**, the exact antipattern the dormant `agents:` tier table already demonstrates (E5). Pin only where traffic exists AND a gate holds the floor. |
| `enhancing-prompts` Haiku pin | Its output (a rewritten prompt) feeds every downstream skill invisibly with NO mechanical fidelity gate — P1 violation. Gate first, then pin. |
| Flipping `stage_routing.flatline_scorer` | The D3 A/B is INCONCLUSIVE (n=5×6, CI ±0.10). Flag stays false per the runbook; gold-set expansion filed as a bead. Empirical-over-intuition is the whole point. |
| cheval executor-alias refresh to Sonnet 5 | SSOT codegen + pricing + probe risk in the substrate; the Claude-harness layer already gets current-gen models natively. Filed as a bead. |
| Loosening $-expansion blocking in the safety hook | Panel produced concrete false-negative attack strings; conservative blocking of `$`-bearing rm operands is intended behavior, not a false positive. |
| Global `~/.claude/settings.json` changes | **No change is the change.** The operator wants Fable as orchestrator (model stays `claude-fable-5[1m]`, effort high). Tiering ships in-repo at the skill/agent layer, so it follows the repo across machines and the fleet — user-level settings would fork behavior per machine and rot. |

## 6. Live calibration data (this session as its own experiment)

The cycle was executed with the strategy it ships. Model assignment and outcomes:

| Stage | Model | Outcome |
|-------|-------|---------|
| 20-agent analysis fan-out | Sonnet (mechanical recipes) | 1.74M tokens, 0 errors, evidence held up under Fable verification |
| Design | Fable (lead) | v1 design had 14 blocking flaws… |
| Design panel (3 lenses) | Fable | …all 14 caught pre-implementation (existing-script duplication, 7-consumer breakage paths, decorative pins, verdict-rule gaming, hook false-negatives) |
| Implementation (8 ownership groups) | Sonnet | All contracts landed; word deltas as specced; 2 pre-existing defects flagged unprompted |
| Lead verification | Fable | Caught the multi-root find bypass Sonnet's implementation + tests missed |
| Adversarial review (4 lenses, execution-based) | Sonnet | Caught a CRITICAL nested-find bypass **that Fable's own fix had missed**, plus 9 verified gate/compat defects |
| Audit | Sonnet | (final gate; see PR) |

**The load-bearing observation**: the nested-find CRITICAL was introduced under Fable
review and caught by a Sonnet reviewer with an execution-based mandate. Layered
independent verification with mechanical mandates ("run the thing, show the output")
outperformed any single model tier. That is the mechanical-floor thesis, observed live.

## 7. Extension playbook (for the next model working on this)

1. **Before pinning a model to anything**: check traffic (mining recipes in this
   report's fan-out are reusable), check what gates its output, cite evidence in
   `workload_tier_map` form. No traffic or no gate → don't pin.
2. **Before trusting a new gate**: write the fixture that should fail, prove it fails,
   then wire the gate. Every gate's failure text must contain the fix (P5).
3. **Tier changes at the cheval layer**: run the A/B harness
   (`tools/stage-tier-benchmark.sh`, gold sets under `tests/fixtures/`), require a
   resolved (non-INCONCLUSIVE) result, carry `Tier-Change-Evidence:` in the PR.
4. **Framework-zone work in this repo**: create the authorization marker with a real
   reason + short expiry; delete it when done. Every write is trajectory-logged.
5. **Watch the attribution**: `/loa status --economy` now receives per-skill rows from
   flatline + adversarial dispatches. When ≥30 healthy runs accumulate for a rubric
   stage, that is the evidence bar for the next downtier proposal (model-economy
   runbook §2).
6. **Do not re-add prose middleware to skills.** If a behavior needs enforcement, it
   goes in a hook/script/validator; if it needs stating, it goes in ONE canonical
   protocol file and gets referenced.

## 8. Deferred (beads)

- Scorer gold-set expansion + A/B rerun (flip `stage_routing.flatline_scorer` only on PASS).
- cheval Sonnet-5/Haiku executor-alias catalog entry.
- Live-fire weak-model skill trial harness (run /implement + /review-sprint on Sonnet in a throwaway worktree; capture actual failure modes — the census extrapolated from strong-model transcripts).
- Repair-loop observation cycle → default-on decision (instrument rejection volume first).
- spiral-evidence trailer-preference upgrade (currently ordering-fixed only).
- translating-for-executives citation/health-score validator (needed before any pin).
- FR-2 inert-carrier allowlist gap: commit messages mentioning find-exec shapes still trip the hook (observed this cycle).
- Fleet hook rollout: mined FPs came from repos on ~1.180.0 hooks — the fix is `update-loa`, not more hook patches.

## 9. Numbers

- 56 files changed, +5,215/−4,788 lines; skills+commands surface −9,251 words (−17.2%),
  paid on every invocation of the pipeline core (~1,400 core invocations/quarter fleet-wide).
- New: 6 validators/scripts, 1 agent definition, 1 protocol, ~90 new tests
  (all suites green; safety-hook suite 184 tests incl. 12 new attack fixtures).
- Session cost of the cycle itself: ~6.3M subagent tokens across 44 agents
  (analysis 1.74M, panel 0.37M, implementation 2.29M, review 0.55M, audit + fixes remainder)
  — roughly 80% of it on Sonnet-tier pricing under Fable orchestration.

## 10. Cycle-120 follow-up (2026-07-07, same arc)

Executed the deferred beads with the same scout → design → adversarial-panel →
implement → review → audit method (branch feat/cycle-120-mf-followups). Shipped:
`claude-sonnet-5` in the cheval catalog (1M context / $3-15, verified via the
claude-api reference — the design's 200K guess was a panel catch); the FR-2
inert-carrier fix (bd-7qc2) via the panel-approved post-hoc content-test, NOT
the naive consuming ERE the design proposed (a safety reviewer execution-proved
that ERE would swallow past the closing quote); spiral-evidence structured-first
verdict; the first citation-**resolution** gate (validate-artifact --type
translation, bd-4ylz); the repair-loop dogfood flip; and the flatline-scorer
gold-set 6→20 + live-fire fixture/runbook (execution deferred to bd-ge58).

### bd-nh7u resolution (fan-out budget lint) — closed, no code
Every repo-side orchestrator already carries a budget: red-team
50K/200K/500K max-tokens + 20-attack cap; flatline max_iterations 5 +
200¢/invocation; run-bridge 30K token_budget; spiral per-phase USD caps;
jury-panel bounded by cheval per-call max_tokens. The 892K-token fan-out class
that motivated the bead lives in **harness workflow sessions** (Claude Code
subagent parallelism), where the repo has no enforcement point. A repo-side
lint would therefore be decorative config — the E5 antipattern this methodology
warns against. The mechanical defenses that actually apply are the
agent-ergonomics fan-out budget rule (per-lens tool-use cap + short-circuit)
and loa-scout delegation, both enforced at dispatch time, not repo-config time.
Guidance stands; bead closed with this reasoning.

### The pattern held again
Layered independent verification kept paying: the design panel caught a
context-window guess and REJECTED a hook approach that would have shipped a
bypass; the review wave then execution-proved a *different*, pre-existing
decoy-flag bypass (`git commit -m "-m " && rm -rf …`) that the fix's own header
comment claimed was impossible — fixed at root (bar quotes from the carrier
prefix) plus a contiguous-flag tail-consumer so multi-message commits stay
allowed; the audit caught a MUST-gate wired into a skill with no Bash grant
(the skill-invariants #553 class). 15 verified findings caught pre-merge across
the three gates (2 design + 10 review incl. 1 CRITICAL + 3 audit incl. 1 HIGH).
