# 12 — Risks, Open Questions, Do-Not-Build

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> Re-walk this document at every phase boundary of
> [`10-build-roadmap-slices.md`](10-build-roadmap-slices.md); resolved questions
> below retain their recorded disposition.

## 1. Risk register

| # | Risk | Likely? | Hurts? | Mitigation (where) | Residual truth |
|---|------|---------|--------|--------------------|----------------|
| R1 | **Schema ossification** — provisional shapes harden by habit before evidence names them | high | med | every contract marked provisional; envelope review is its own slice (10 §20); checker follows doctrine, never leads | some de-facto freezing is inevitable; make it deliberate at slice 20 |
| R2 | **Bureaucratic overgrowth / false precision** — ledgers metastasize; the method becomes forms about forms | med | high | sparse manual-mode rules (doc 09); bounded vocabularies; one-adversarial-layer ceiling; "tags not documents"; slice audits ask "what did this field earn?" | vigilance is the only real control; prune fields that never changed a decision |
| R3 | **Silent completeness loss at extraction** — spans never packetized are invisible to every later guarantee | med | **highest** | over-extraction bias; per-source completion declarations; blind coverage spot-checks; extraction recall as the headline replay metric (docs 04 S2, 06 §5) | sampling can miss; recall numbers come with confidence, not certainty |
| R4 | **Fabrication at normalization/synthesis** — restatements smuggle outside knowledge; synthesis asserts beyond dispositions | med | high | entailment spot-checks; refute-first synthesis review; phantom-rate metric; no-external-facts rule in every judgment prompt | LLM-judged entailment is itself fallible; audit keeps humans in the loop |
| R5 | **Verifier gaming / theater** — producers learn what refuters check; declared removal effects gamed; upheld-everything panels | med | high | lens diversity; blind bundles; adversarial fixtures seeded with traps; "panel upholds everything ⇒ suspect leakage" (doc 08 S9a); independent audit stays mandatory | acknowledged unsolved in general; the audit layer is the backstop |
| R6 | **Orchestrator failure modes** — state drift, skipped DoD boxes, silent loops (the literature says failures concentrate here) | med | high | single-writer ledgers; DoD-as-barrier; resumption-from-files; 3-strikes escalation; run-log discipline (docs 05 §9–10, 08) | a sufficiently wrong orchestrator can still narrate compliance; replay + audit catch it after the fact |
| R7 | **Cost blowup** — verification multiplies tokens; 1M-context stages are expensive | high | med | budgets per stage with BLOCKED-not-truncate; batch lane; cache discipline; cost as a reported replay metric before scale-up (doc 05 §7) | first real-corpus run (slice 14) is the honest price tag |
| R8 | **Prompt/answer-key leakage between stages** — the runtime version of the corpus-blindness problem | med | high | bundles-not-requests; X3 generalized (later-stage vocabulary must not appear in earlier-stage artifacts); leakage as a named defect class | subtle leakage (phrasing echoes) is hard to detect mechanically |
| R9 | **PII / confidentiality in real corpora** — instance #1 is real conversations | high | high | S0 sensitivity flags + authority rulings before extraction; sensitivity handling rules travel with sources; projections inherit flags | policy for redaction-vs-exclusion is an open question (Q8) |
| R10 | **Checker brittleness / prose-policing creep** — T1 grows regexes that false-positive on legitimate prose | med | med | hard/soft split (T1 structural only); deferred-as-brittle list honored; negative batteries include false-positive guards | the checker doc's discipline has held for five slices; keep it |
| R11 | **Convergent arm stays unvalidated but gets used anyway** — schedule pressure normalizes S9b output | med | high | unvalidated-arm notice is mandatory in manifest + Précis known-limits; validation ledger is checked by audit | culture risk more than mechanism risk |
| R12 | **Model, runtime, or bundle drift / non-reproducibility** — the same run silently resumes with different Core, adapter, checker, host, or model behavior | high | med | pin Core/adapter/bundle/checker digests, adapter-protocol and run-format versions, exact host/model identities, and an immutable runtime snapshot per run; resume only from the original bundle; goldens remain permanent | model outputs need not be bitwise identical, but execution identity and contract-level equivalence are mandatory |
| R13 | **Refusal-blocked content skews completeness** — safety classifiers refuse spans of a legitimate corpus | low | med | `refusal-blocked` as a recorded extraction class; manual-mode fallback for those sources; accounting still balances (doc 05 §9) | a heavily-affected corpus may need a different model or manual run (authority call at S0) |
| R14 | **Scope creep into business/market-intelligence territory or Freeside's product/platform territory** — projections quietly become market intel or product surfaces | med | med | responsibility map; projection plugin registry reviewed at acceptance; do-not-build list below | fan-out pressure is permanent; the boundary is doctrinal |
| R15 | **The plan itself over-specifies** — this tree becomes step-scripts that degrade execution (the de-prescription finding, applied to us) | med | med | contracts state *what must be true*, runbooks state judgment calls; slice 7 review explicitly prunes; prompt-pack audit checks for step-scripts | the tension is real; err toward invariants over instructions |

## 2. Open questions (each needs an owner and a decide-by slice)

| # | Question | Context | Decide by |
|---|----------|---------|-----------|
| Q1 | **Recipe vs invariants** — how prescriptive may instructions be before they fight the doctrine's method-neutrality (the fork PR #16 stayed independent of)? | tenets T1/T10 vs R15 | slice 7 |
| Q2 | **RESOLVED by Decision 0003:** T1 is structural and fail-closed; T2 produces judgment evidence, not truth exit codes. | doc 06 §1 | confirmed in practice by the golden run and kernel |
| Q3 | **Envelope amendments** — do evidence-role summary and routing/card summary join the 17 fields, and when? | artifact 17; R1 | slice 20 (informed by 10, 11, 14) |
| Q4 | **PARTIALLY RESOLVED by Decision 0003:** `md-lines` byte semantics are fixed; `chat-msg` remains mechanically unverified pending a fixture. | artifact 4; ID rules | next conversation-export fixture |
| Q5 | **RESOLVED PROVISIONALLY by Decision 0003:** retain the closed claim-type field as unchecked routing metadata and revisit it at envelope review. | artifact 5 | slice 20 evidence review |
| Q6 | **ID stability mechanics** — hash-matched reuse across re-runs: exact matching rules, collision policy | doc 02 §2 | slice 9 (paper), slice 13 (practice) |
| Q7 | **PARTIALLY RESOLVED by Decision 0003:** material received after freeze always starts a successor run whose manifest names the prior run; Précis versioning and diff mechanics remain open. | corpus-freeze rule | after slice 14 for version/diff mechanics |
| Q8 | **Redaction vs exclusion for sensitive spans** — how does a redacted span keep a working locator and honest accounting? | R9 | before slice 14's S0 |
| Q9 | **Verifier quorum/sampling defaults** — the doc 06 §3 numbers are placeholders | doc 06 | slice 13 sets, slice 14 confirms |
| Q10 | **Hybrid-mode manifest conventions** — per-stage actor recording when humans and agents split a run | doc 09 §5 | slice 15 |
| Q11 | **RESOLVED by Decision 0003:** verdict files are run-internal portable companions; Précis §16 carries summary and sampling honesty. | artifacts 15/17; portability contract | implemented by the golden run |
| Q12 | **RESOLVED by Decision 0004:** Aleph ships one complete immutable, harness-neutral Core plus one host adapter. Prompt packs remain Core; harness-native entrypoints and model/runtime mappings remain adapter/profile mechanics. Adapters may invoke but never fork, restate, or weaken Core. | Decision 0004; adapter protocol; packaging contract | implemented by the Core manifest and bundle validator; Loa is structurally `implemented` only, Hermes remains `planned`, and adapter validation plus agent-mode sanction remain separately evidence-gated |

## 3. Do-not-build (consolidated, standing)

Carried from doctrine, issue #18's anti-collapse notes, and this plan's own
boundaries. Building any of these requires a doctrine change first, not a
slice:

- **No served endpoint / API / live service.** File-first stands. Integration
  surfaces, if ever, project from artifacts.
- **No web crawler / live citation resolver / general search engine.**
  External material enters through scoped S0/REF intake; material received
  after freeze enters only in a successor run whose manifest names the prior
  run. The current run may resolve a referent only through a recorded authority
  statement/sign-off without corpus mutation.
- **No truth engine.** The method verifies *support within a declared
  corpus*, never facthood at large. The checker never judges semantics; the
  harness never claims more than "survived attack".
- **No AI-content detector.** Source trust classes record provenance; nothing
  guesses authorship.
- **No causal model-internals attribution.** Evidence roles are declared,
  attackable honesty — not attention forensics.
- **No graph database / knowledge-graph product.** Typed tables in Markdown;
  the graph is reconstructable, not enshrined.
- **No ranking/recommendation product; no citation-count scoring.** Volume is
  never quality (T12).
- **No business/market-intelligence projections inside Aleph** (a future
  business/market-intelligence consumer's lane) and **no product/platform
  surfaces** (Freeside's lane).
- **No blanket bans on AI-generated sources.** Classify and bound them
  (trust class, evidence roles); don't censor the corpus.
- **No invisible pre-extraction discard path** under any label ("low
  quality", "obviously irrelevant") — the criteria + dispositions are the
  only gate.
- **No schema freeze by accident** — only by slice-20-style decision.
- **No autonomous authority** — the agent never accepts its own work, merges
  to `main`, supplies external facts, or overrides a gate. Ever.
