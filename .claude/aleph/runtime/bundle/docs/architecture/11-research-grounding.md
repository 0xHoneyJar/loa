# 11 — Research Grounding

> Status: ACCEPTED AS IMPLEMENTATION RATIONALE by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> This document records the research this plan rests on and maps each finding to the design decision it
> grounds — so a future reader can re-audit the reasoning when the landscape
> moves. Findings are dated July 2026. Single-source or paywalled items are
> marked; treat them as weaker evidence.

## 1. Fable 5 capability facts (primary sources)

Sources: the Anthropic announcement
([anthropic.com/news/claude-fable-5-mythos-5](https://www.anthropic.com/news/claude-fable-5-mythos-5)),
the platform docs ("Introducing Claude Fable 5", model catalog, migration
guide — [platform.claude.com/docs](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5)),
and the API reference material bundled with Anthropic's own tooling (authoritative
for parameters and behavioral guidance).

| Fact | Design consequence (where) |
|---|---|
| `claude-fable-5`; 1M-token context (default = max); 128K output; $10/$50 per MTok; same tokenizer as Opus 4.8 | corpus-scale single-context stages; budget math (doc 05 §3, §7) |
| Thinking always on; raw chain of thought never returned; summaries opt-in | written rationales are the audit record, mandatory in every judgment schema (doc 05 §6) |
| Effort dial `low`–`max`; lower efforts still outperform prior models' ceilings; effort is the primary cost/quality lever | per-stage effort policy + evidence-gated tier-downs (doc 05 §5, T11) |
| Structured outputs / schema-constrained returns; strict tools | ledger interface contract (doc 05 §6; artifact 20) |
| Task budgets (model-aware ceilings); prompt caching (~90% read discount); batch API (50%) | budget lanes and caching discipline (doc 05 §7) |
| Long single turns (minutes) are normal at high effort; plan streaming/async check-ins | orchestrator turn design + checkpoint-by-artifact (doc 05 §1) |
| Safety classifiers can refuse (bio/cyber); `refusal` stop reason; fallback parameter exists | refusal handling as a first-class failure mode with completeness-preserving accounting (doc 05 §9) |
| 30-day data retention required for Fable 5 | run-manifest records the model per run; a sensitivity-constrained corpus may force a different model — recorded as an S0 authority matter (doc 12 risk table) |
| Announcement: SOTA long-horizon agentic execution; file-based memory improved a long-game eval ~3× more than the prior model; "higher effort enables reflection and validation"; SOTA on document-based reasoning benchmarks | the whole agent-mode bet (doc 05 §1); mandatory memory surface (doc 05 §4) |

**Behavioral guidance from Anthropic's migration/prompting material** (the
most load-bearing single source for doc 05 and the runbook):

| Guidance | Where it landed |
|---|---|
| Parallel subagents are dependable; prefer async delegation over spawn-and-block; give explicit when-to-delegate guidance | topology + concurrency rules (doc 05 §2, §10) |
| Separate fresh-context verifier subagents outperform self-critique; make self-verification explicit with a cadence | T8; the verification harness (doc 06 §3); ⚖ items throughout doc 04 |
| De-prescribe: goal + constraints beats step enumeration; over-prescriptive prompts reduce output quality | prompt doctrine rule 1 (doc 05 §8); prompt-pack slice DoD (doc 10 slice 8) |
| Ground progress claims in tool/artifact evidence (near-eliminates fabricated status) | runbook rule; orchestrator prompt requirement (docs 05 §8, 08 §1) |
| Give it a memory surface with a format; one lesson per entry; update-don't-duplicate | `run-log.md` + `lessons.md` (doc 05 §4) |
| State the autonomy envelope; batch questions; act on reversible things | gates-and-autonomy design (docs 05 §8, 08 §1) |
| Watch for: early stopping, context anxiety, unrequested adjacent actions; give the reason behind requests | runbook prohibitions and turn-ending rules (doc 08 §5–§6) |

## 2. Community practice (secondary, July 2026)

- Checkpointed pipelines where **each phase emits a durable, verifiable
  artifact** the next phase consumes; quality gates between milestones
  ([lushbinary.com guide](https://lushbinary.com/blog/build-long-horizon-ai-agents-claude-fable-5-guide/),
  [RockB pipeline guide](https://baeseokjae.github.io/posts/claude-fable-5-agentic-coding-pipeline-guide-2026/))
  → converges with tenet T2; the run directory is exactly this pattern.
- **Cost tiering**: route the hardest work to Fable 5, mechanical work to
  cheaper tiers; per-milestone budgets; cache-first prompt layouts
  ([MindStudio results](https://www.mindstudio.ai/blog/claude-fable-5-agentic-coding-real-world-results),
  [postsyntax practical guide](https://postsyntax.substack.com/p/the-practical-guide-to-claude-fable) — *paywalled preview; partial*)
  → doc 05 §5/§7, with the stricter Aleph rule that tier-downs need replay
  evidence.
- **Orchestrators treat worker output as provisional until structurally
  validated**; reviewer/fact-checker agents materially reduce hallucination
  ([codebridge orchestration guide](https://www.codebridge.tech/articles/mastering-multi-agent-orchestration-coordination-is-the-new-scale-frontier),
  [SudoAll coordination playbook](https://sudoall.com/multi-agent-coordination-2026-playbook/))
  → schema-validated returns (doc 05 §6) + T2 harness.
- **Failures concentrate in the orchestrator, not the workers** (ICML 2026
  orchestrator-entropy result, via [Pandaily summary](https://pandaily.com/icml-2026-orchestrator-entropy-dynamics-multi-agent-systems-jul2026-v2)
  — *single-source summary; treat direction, not detail*) → the runbook's
  heavy weighting toward orchestrator discipline: single-writer ledgers,
  DoD-as-barrier, resumption-from-files, 3-strikes escalation (docs 05 §9–10,
  08).

## 3. Claim-level distillation and verification literature

- **Decompose-then-verify** is the established backbone: FActScore
  (atomic-claim decomposition + per-claim verification;
  [emergentmind topic](https://www.emergentmind.com/topics/factscore-113e12f4-d246-433f-8289-063e105dc511)),
  **VeriScore** (extract only *verifiable* claims; verify against retrieved
  evidence; [arxiv 2406.19276](https://arxiv.org/pdf/2406.19276)),
  **DnDScore** (decontextualization matters — claims must be verifiable
  *in context*; [arxiv 2412.13175](https://arxiv.org/html/2412.13175)),
  **VeriFastScore** / **FaStfact** (efficiency variants;
  [arxiv 2505.16973](https://arxiv.org/html/2505.16973),
  [arxiv 2510.12839](https://arxiv.org/html/2510.12839)),
  **AFEV** (iterative decomposition with fine-grained retrieval;
  [arxiv 2506.07446](https://arxiv.org/html/2506.07446v1)).
  → Grounds S2/S3's packet→claim design; the entailment spot-check (claims
  must be entailed by their packets); the "extract verifiable units, judge
  them individually" spine of the whole method. Aleph's twist: dispositions
  generalize verification verdicts (a claim can be *carried, deferred,
  excluded, backgrounded…* — richer than true/false), and the reference set is
  the corpus itself, not the open web (no crawler — do-not-build).
- **Decontextualization warning** (DnDScore): atomizing claims loses meaning
  unless context travels with them → the normalization rule that a
  restatement must be entailed by its packets, plus packet-widening rather
  than invisible context imports (doc 08, S3 amplification).
- **Citation ≠ influence** (ProvenAI, arxiv 2606.26449, plus the
  synthetic-sources findings — surfaced by the repo's own issue #18 research):
  a source can be cited without shaping the conclusion; synthetic sources
  contaminate citation graphs → the evidence-role ledger and
  evidence-removal stress rows (artifact 8, S6, S9a) — the plan's most direct
  adoption of an external finding, matching the issue's PROPOSE verdict.
- **Verification-cost asymmetry** (FT / ITPro maintainer-burden reporting, via
  issue #18): cheap generation floods expensive review → T12 (expose the
  burden): sampling rates in the verification summary, verification-cost
  visibility as a first-class artifact property.

## 4. Multi-agent research-system patterns

- **Orchestrator–worker with parallel search fan-out and citation-carrying
  subagents** is the published Anthropic pattern for research systems
  (Anthropic engineering, "How we built our multi-agent research system",
  2025; summarized at
  [theaiengineer substack](https://theaiengineer.substack.com/p/how-anthropic-built-multi-agent-deep))
  → doc 05 topology; fan-out points in doc 04's stage graph.
- Claim-verification-specific multi-agent work (e.g. Thucy, verifier-with-
  expert-agents-as-tools; [arxiv 2512.03278](https://arxiv.org/pdf/2512.03278))
  supports the lens-diverse panel design over one monolithic checker
  (doc 06 §3).
- LLM-as-judge hygiene (position/self-preference biases; panels over single
  judges; rubric-anchored grading — established literature) → quorum rules,
  refute-first framing, lens diversity, and the rule that verifiers run at
  ≥ producer effort (docs 05 §5, 06 §3–4).

## 5. Provenance and audit standards

- **W3C PROV** (entity/activity/agent lineage model) is the reference frame
  for the run directory's who-produced-what records (manifest actor fields,
  verdict attestations) — borrowed as *vocabulary discipline*, deliberately
  not as an RDF implementation (do-not-build: no graph database).
- Reproducibility practice from data/ML pipelines (pin versions; freeze
  inputs; append-only logs; content-address artifacts) → corpus freeze,
  immutable Core/adapter/bundle/checker/runtime pins, exact model identities,
  and hash-stable IDs (docs 02, 03; Decision 0004).

## 6. Findings that argue *against* parts of the design (kept visible)

- **Bureaucratic overgrowth / false precision** is the named risk of the
  evidence-role ledger (issue #18 itself flags it) — hence the sparse
  manual-mode rule, the bounded role vocabulary, and the one-adversarial-layer
  ceiling (docs 03 §8, 06 §3, 09 S6).
- **Judge gaming**: authors can game declared removal effects; adversarial
  fixtures and independent audit are the mitigations, and doc 12 keeps it on
  the register — the plan does not claim to have solved it.
- **Metric optimism**: replay metrics (recall/agreement) can be satisfied by
  memorization-shaped behavior on small goldens; hence multiple goldens of
  different characters (fixture-scale, real-scale, convergent) before any
  "validated" claim generalizes (doc 06 §5, doc 10 Phase C/E).

## 7. Most load-bearing sources (short list)

1. Anthropic Fable 5 announcement + platform docs/migration guidance —
   capability facts and agent-design guidance (§1).
2. The repo's own accepted doctrine + issue #18 — the evidence-role gap and
   its bounded, falsifiable remedy.
3. FActScore / VeriScore / DnDScore / AFEV line — decompose-then-verify with
   decontextualization caveats.
4. Anthropic multi-agent research system write-up — orchestrator/worker
   research topology.
5. Community long-horizon pipeline reports (Lushbinary, MindStudio, RockB;
   SudoAll / codebridge orchestration guides) — durable-artifact checkpoints,
   cost tiering, validate-worker-output (secondary confidence).
