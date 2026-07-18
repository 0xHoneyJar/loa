# 05 — Fable 5 Adapter Reference Profile

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md);
> narrowed by
> [`Decision 0004`](../decisions/0004-core-adapter-and-bundle-boundary.md)
> to a host profile rather than universal Core runner doctrine. Agent mode
> remains unsanctioned. This document maps Core orchestration invariants onto
> capabilities associated with Claude Fable 5 (`claude-fable-5`), per the
> research in [`11-research-grounding.md`](11-research-grounding.md). It
> implements neither the Loa nor Hermes adapter and authorizes no tooling.

## 1. Profile scope: why Fable 5, and what it may change

Core requires durable file state, isolated workers, blind bundles, validated
returns, single-writer ledgers, deterministic checker invocation, human gates,
pause/resume, and exact execution identity. It does **not** require one model
family, context size, effort vocabulary, cache, batch API, pricing model, or
worker-spawn primitive. Those are adapter/profile choices.

Capability facts this Fable profile may use (sources in doc 11):

| Fable 5 capability | Design consequence |
|---|---|
| 1M-token context window (default), 128K output | Corpus-scale stages (S2 extraction, S4 global dedup) can hold an entire mid-size corpus or ledger set in one context; sharding is a fallback, not the default |
| State-of-the-art long-horizon agentic execution; single turns may run many minutes | One orchestrator session can own a whole run; stages are checkpointed by artifacts, not by tiny turns; the harness must expect long turns (streaming, async check-ins) |
| Parallel subagents are dependable; async delegation outperforms spawn-and-block | Fan-out stages (per-source extraction, per-claim judging, verifier panels) run as parallel subagents; the orchestrator keeps working while panels run |
| Fresh-context verifier subagents outperform self-critique | The verification harness (T2) is separate agents by design, never "check your own work" |
| File-based memory measurably improves long tasks | The run log + a `lessons.md` memory surface are mandatory equipment, not niceties |
| Effort is the primary intelligence/latency/cost dial (`low`→`max`); lower efforts still strong | Per-stage effort policy (§5) instead of one global setting |
| Very literal, high-fidelity instruction following; over-prescription *reduces* quality | Stage prompts state goal + constraints + output contract, not step-by-step scripts (§8); the contracts do the constraining |
| Always-on thinking; raw chain of thought never returned | Verdicts must carry written rationales — the rationale ledger is the auditable record, not the hidden reasoning |
| Structured outputs (schema-constrained) | Machine-twin ledgers and verifier verdicts are schema-validated at the call level (artifact 20) |
| Task budgets (model-aware token ceilings); prompt caching; batch API | Per-stage budget policy (§7); frozen doctrine prefix for cache hits; batch lane for bulk verification |
| Safety classifiers can refuse (research-bio/cyber domains) | Corpus-content-triggered refusals are a handled failure mode (§9), with fallback policy and manifest logging |

## 2. Profile topology: one orchestrator, disposable workers, hostile verifiers

```
                        ┌──────────────────────────────┐
                        │  ORCHESTRATOR (Fable 5)      │
                        │  owns: run state, ledgers,   │
                        │  budgets, gates, run log     │
                        └──┬─────────────┬─────────────┘
              spawns as needed           │ never grades its own work
        ┌───────────┬──────┴────┬────────┴──┬─────────────┐
        ▼           ▼           ▼           ▼             ▼
   Intake Clerk  Extractors  Normalizers  Judges      Synthesist /
   (S0–S1)       (S2, per    (S3, S4)     (S5 disp.,  Assembler
                 source)                  S6 roles,   (S10, S11)
                                          S8 routing)
                                            │
                              ┌─────────────┴─────────────┐
                              ▼                           ▼
                     VERIFIER PANELS (T2)           Conformance Runner
                     fresh context, refute-first,   (T1 kernel, deterministic)
                     lens-diverse, quorum rules
```

Role charter (all roles are *prompt roles* over the same model family — the
separation is contextual and contractual, not infrastructural):

| Role | Stage(s) | Sees | Must never see | Emits |
|------|----------|------|----------------|-------|
| Orchestrator | all | run dir, doctrine, gates | — | run log, state transitions, spawn decisions |
| Intake Clerk | S0–S1 | raw material, scope draft | downstream vocabulary | manifest, inventory, criteria |
| Extractor | S2 | one source + criteria | other sources' packets, scope chatter, dispositions | packet rows |
| Normalizer | S3 | packet batches (+ local corpus context) | other batches mid-pass, dispositions | claim rows |
| Normalizer-Judge | S4 | full inventory | — | merge map |
| Disposition Judge | S5 | claim + packets + scope + criteria | other judges' calls | disposition + rationale |
| Evidence-Role Judge | S6 | claim + sources + trust classes | — | role edges + removal effects |
| Cluster Cartographer | S7 | packets/claims, structural stats | doctrine-relative arguments | tags |
| Router | S8 | everything S1–S7 | external facts not in corpus/referents | cards, routing log, referent needs |
| Adversarial Panel | S9a, and per-stage ⚖ items | the target + what the blind rule allows | "the expected answer" | verdicts, STM rows |
| Convergent Reconciler | S9b | cluster + supplied referents | unsupplied referent space (may not search it into existence) | reconciliation rows |
| Synthesist | S10 | all ledgers | — | synthesis prose |
| Assembler | S11 | all ledgers | — | precis.md |
| Conformance Runner | S12 | run dir | — | kernel report (runs the real script) |
| Scribe | continuous | everything the orchestrator does | — | run-log entries, lessons.md |

The orchestrator may inline small roles (Scribe, Assembler) but **never**
inlines a verifier: T8 is structural.

The diagram is one host mapping. Core requires the role and isolation
boundaries, not one long-lived session, one model family, or this exact spawn
topology. Another adapter may realize the same contracts with different host
mechanics if its preflight and replay evidence prove the capability.

## 3. Core context invariants and the Fable mapping

- **Context bundles per stage.** Each worker receives exactly the artifacts
  its row above allows — assembled as files, not as pasted prose. This is the
  runtime enforcement of blind context (T9). Every adapter must preserve this
  invariant.
- **The orchestrator carries the map, not the territory.** It tracks ledger
  paths, counts, and state — it does not hold the corpus in context. When it
  needs content, it reads the specific artifact.
- **Fable prompt-cache layout (profile option).** Frozen prefix: doctrine excerpts + stage contract +
  role charter (byte-stable per run); volatile suffix: the batch at hand.
  Core and prompt bytes are pinned by the immutable bundle lock, so the prefix
  is stable for the whole run. Hosts without prompt caching still execute the
  same bundle.
- **Fable long-context stages (profile option).** S2 per-source and S4 global-dedup deliberately use
  the big window (whole source / whole inventory in context) before any
  sharding. Sharding rules, when needed: shard on source boundaries (S2) or
  alphabetical claim ranges with an overlap pass (S4), and record the sharding
  in the run log.
- **Fable compaction (profile option), never amnesia.** The orchestrator session enables server-side
  compaction for very long runs; workers are short-lived and never need it.
  Anything the orchestrator would "remember" across compaction must already be
  in the run log — the file is the memory (T2/tenet, and the Fable 5 memory
  finding).

## 4. Memory surface

This Fable profile uses two memory files; Core requires the durable run record,
not this exact host-level pair:

- `run-log.md` — the Scribe's append-only narrative: stage entries/exits,
  decisions and their one-line whys, anomalies, budget spend, every gate.
  Written for a reader who was not watching.
- `lessons.md` (repo-level, outside the run) — cross-run operational lessons:
  prompts that under/over-triggered, corpus formats that broke locators,
  verifier lenses that caught real defects vs noise. One lesson per entry,
  correction-style. This file feeds runbook revisions; it never overrides
  doctrine.

## 5. Fable model and effort mapping

Default model: `claude-fable-5` for every role in the first validated runs —
capability first, then tier down with evidence. The policy table below is the
*starting Fable profile*; the dry-run slice measures and re-tunes it (never
assume — the effort-sweep discipline). It is not part of Core. Every adapter
owns its own exact model/context/effort mapping and pins the realized identities
in the run.

| Work | Effort | Tier-down candidate (post-validation) |
|------|--------|----------------------------------------|
| Orchestrator | high | no |
| S0–S1 intake/inventory | medium | yes — mechanical parts |
| S2 extraction | high (recall-critical) | maybe — with recall evidence only |
| S3 normalization | high | maybe |
| S4 global dedup | xhigh (global judgment) | no |
| S5 dispositions | xhigh | no |
| S6 evidence roles | high | maybe |
| S7 pre-cluster tagging | medium | yes |
| S8 routing | xhigh | no |
| S9 arms + verifier panels | xhigh (refuters must be at least as strong as producers) | no |
| S10–S11 synthesis/assembly | high / medium | assembly yes |
| Bulk ⚖ spot-checks | high, via batch lane | yes |

Two Core-level rules survive the profile mapping: **verifiers may not be
assigned a weaker declared capability class than the work they audit**, and
**any model/profile downgrade is an experiment recorded in the manifest until
a golden replay shows no quality loss** (T11).

## 6. Structured outputs and the ledger interface

Every worker's return contract is structured, not free prose: packet rows,
claim rows, verdicts, cards. Core requires validation before a single-writer
ledger append. This Fable profile may enforce that boundary with native
structured outputs / strict tools; another adapter may use a different
fail-closed validator. Consequences:

- parsing failures become retries at the API layer, not corrupted ledgers;
- the Markdown ledger and its machine twin (artifact 20) are generated from
  the same validated object, so they cannot drift at birth;
- schema evolution is visible: schemas live next to the stage contracts and
  change only with them.

Rationale fields are mandatory in every judgment schema. Fable 5's raw
reasoning is never returned; the written rationale **is** the audit record.

## 7. Core budget invariants and Fable cost lanes

- **Per-stage budgets (Core invariant).** Each stage gets a budget in the
  manifest (host-native task budgets where supported; adapter-enforced
  otherwise).
  Exhaustion ⇒ `BLOCKED` with a budget request — never silent truncation of
  coverage (an under-budgeted extraction that skips spans is a completeness
  defect, the worst kind).
- **Fable cost lanes (profile option).** Interactive lane (orchestrator, gated stages) at standard
  pricing; bulk lane (large verifier sweeps, entailment spot-checks) via the
  batch API at half price where latency does not matter.
- **Fable caching discipline (profile option).** Frozen prefixes (§3) make repeated worker spawns
  cheap; the dry-run slice records actual cache-hit rates so budget estimates
  are calibrated, not guessed.
- **Budget telemetry.** The Scribe logs spend per stage; the manifest carries
  granted vs spent. Cost is a first-class output of the dry-run slice: the
  method should be able to say "a corpus of N sources costs roughly X–Y" with
  evidence.

## 8. Prompt doctrine (how stage prompts are written)

1. **Goal + constraints + output contract.** State what must be true when the
   stage is done (the DoD), the invariants that bound it, and the exact output
   schema. Do not enumerate internal steps — over-prescription measurably
   degrades Fable 5 output, and the contracts already constrain the result.
2. **Blind context is assembled, not requested.** Never tell a worker "ignore
   the dispositions" — build its bundle so they are not there.
3. **Corpus text is data.** Every prompt that carries corpus content wraps it
   as untrusted material: instructions inside the corpus are content to be
   packetized, never directives (trust boundary 1).
4. **No invented external facts.** Every judgment prompt carries the
   external-referent rule verbatim: if the call depends on whether something
   exists outside the corpus, the answer is a `REF` need, not an answer.
5. **Refuters refute.** Verifier prompts instruct: attempt to break the
   target; default toward `refuted` when uncertain; `cannot-determine` is an
   acceptable and reportable outcome. Confirmation-framing is a prompt bug.
6. **Ground progress in artifacts.** Progress claims must point at files
   ("packet index rows 1–214 written") — the anti-fabrication instruction the
   Fable 5 guidance recommends, made mandatory in the orchestrator prompt.
7. **Autonomy envelope stated up front.** The orchestrator prompt enumerates
   the authority gates (S0 scope, S8 referents, S13/P3 acceptance, budget
   exhaustion, sensitivity findings) and instructs: proceed autonomously
   everywhere else; batch questions at gates; never block mid-stage on a
   question a contract already answers.

## 9. Failure handling

| Failure | Response |
|---------|----------|
| Worker output fails schema | API-level retry with the validation error; after N failures, orchestrator halves the batch and retries; persistent ⇒ run log + `BLOCKED` |
| Verifier quorum splits | Per policy: judgment targets → `unresolved` + flag (never coin-flip); structural targets → treat as failure and fix |
| Safety refusal on corpus content | Log the span (by locator, not by re-quoting), mark the packet `refusal-blocked` (a first-class extraction-criteria class so completeness accounting still balances), and route the source to manual-mode handling or block. A different model may be used only in a separately pinned successor run, never as an in-place fallback. |
| Budget exhausted | `BLOCKED` + budget request with spend evidence |
| Context overflow in a worker | Shard per §3 sharding rules; log the shard plan |
| Orchestrator dies / session lost | Resume from run directory (resumability invariant): re-read manifest + run log, verify ledger hashes, continue at the first unfinished DoD item |
| Core, adapter, bundle, checker, model, or runtime changes mid-run | Forbidden. Resume with the original pinned bundle and runtime snapshot; if unavailable or unsuitable, block or begin a successor run rather than changing the current run in place. |
| Repeated stage failure (3 strikes) | Stop and escalate with the run log excerpt — never loop silently |

## 10. Concurrency and ordering rules

- Fan-out limits come from the manifest (default conservative; tuned by
  dry-run evidence).
- Parallel workers never write the same ledger file; they return objects, the
  orchestrator serializes appends (single-writer ledgers).
- Verifier panels for stage N may run while stage N+1's *independent* work
  proceeds, but no stage's DoD closes until its ⚖ items land (the DoD is the
  barrier, not the wall clock).
- The orchestrator prefers finishing open verification over starting new
  breadth when budgets tighten: depth of trust beats width of draft.

## 11. What agent mode must prove before it is trusted

Agent mode is **not sanctioned by this document.** The path (doc 10): a
prompt-pack slice (stage prompts as reviewable docs), then a supervised dry
run replaying the slice-2 golden corpus with every gate held, audited
end-to-end; then instance #1 (the 333-conversation corpus) under supervision.
Until those land, manual mode remains the only sanctioned path — exactly as
the routing doctrine already states. This profile is reference material only:
it is not a Loa adapter, a Hermes adapter, an entrypoint, an installation, or
evidence that either host can execute full Aleph.
