# R&D Scoping — What loa Can Learn from OKF and ICM/MWP, with a Grounded Competitive Landscape

**Date:** 2026-06-27
**Status:** Draft for review (research/scoping; not an implementation commitment)
**Method:** Multi-agent adversarial workflow — 8 grounded research/mapping agents + completeness critic (phase 1), then a 4-lens principal-engineer panel + per-lens adversarial review + chief-architect synthesis (phase 2). Primary sources re-verified by direct fetch (OKF `SPEC.md`, arXiv 2603.16021).
**Sources under study:**
- OKF — *How the Open Knowledge Format can improve data sharing*, Google Cloud (McVeety & Hormati), June 2026. Spec: `github.com/GoogleCloudPlatform/knowledge-catalog/okf/SPEC.md` (Apache-2.0).
- ICM/MWP — *Interpretable Context Methodology: Folder Structure as Agentic Architecture*, Van Clief & McDermott, arXiv [2603.16021](https://arxiv.org/abs/2603.16021), Mar 2026 (CC-BY 4.0). The paper's title names **ICM**; its abstract introduces the **Model Workspace Protocol (MWP)** as the method. We use "ICM/MWP" for the single proposal.

---

## 1. Executive thesis

**loa should treat OKF and ICM/MWP as a _discipline_ and an _export skin_ — never as a replacement for its trust core.** The single durable lesson both works teach is the one loa has been quietly violating *internally*: a knowledge corpus must be **one traversable, minimally-uniform graph**, not five bespoke encodings across six disjoint ID namespaces. OKF's "one required field, tolerate everything else" and ICM's "declare exactly which files load per stage, glass-box by construction" are both arguments for *normalization and legibility* — which loa needs — while neither touches the fail-closed audit / multi-model substrate that is loa's genuine moat.

The uncomfortable counterpart the adversarial panel surfaced — and the most important finding in this report: **that moat is half-dormant.** The fail-closed `verify_for_merge` gate (merged in #1103) has **zero callers**; the trust-store is `BOOTSTRAP-PENDING` with an empty root signature; all **1,143 MODELINV entries are unsigned**; and the ~1,652-line L4 graduated-trust tier has **zero runtime footprint**. loa's running system is therefore **tamper-_evident_ (a plain hash-chain) but not tamper-_proof_ (signing dormant)** — half the marketed crypto lead is a design document. The rational spend is to **(a) normalize and index the corpus, (b) wire the one fail-closed gate that defends a real boundary, and (c) stop carrying dormant crypto ceremony as if it were a live control** — i.e. apply loa's own Karpathy YAGNI ladder to its crown jewel for the first time.

The one-sentence version: **OKF and ICM/MWP are both the deliberate _mirror image_ of loa** — they push knowledge and orchestration down to plain markdown + filesystem + git with *minimal* required structure and *zero* trust machinery; loa pushes the same surfaces _up_ into schema-enforced, multi-model, cryptographically-audited, fail-closed gates. The high-value learning is **not** to abandon loa's heavy end (its audit + multi-model dissent are a verified, defensible lead) but to (a) adopt the cheap interop surface the field has converged on, (b) borrow OKF/ICM's *legibility* primitives where loa's complexity is accidental rather than essential, and (c) recognize loa already ships — and should now _name and harden_ — the provenance layer the rest of the ecosystem is only now racing toward.

---

## 2. The two sources (verified)

### 2.1 OKF — knowledge as portable, fail-soft markdown

OKF v0.1 formalizes the "LLM-wiki" pattern into a vendor-neutral interchange format. Verified against `SPEC.md`:

- **A bundle is a directory of markdown files.** Each non-reserved `.md` = one *concept*. YAML frontmatter carries the queryable fields; the markdown body carries everything else.
- **Directory-as-identity.** Concept ID = file path minus `.md` (`tables/users.md` → `tables/users`). No UUID, no registry, no central authority — identity is *positional*.
- **Exactly one required field: `type`.** Everything else (which types exist, which fields, which sections) is left to the producer. "The spec defines the interoperability surface, not the content model."
- **Fail-soft consumption is normative.** Consumers **MUST tolerate broken links** ("not-yet-written knowledge") and **SHOULD NOT reject** on missing optional fields, unknown `type` values, or unknown keys. Hard MUST-level conformance is only: parseable frontmatter + non-empty `type` + reserved-file structure (`index.md`, `log.md`).
- **Untyped relationship graph.** Concepts link via ordinary markdown links; the *kind* of relationship lives in prose, recovered by the reading LLM — not in a typed schema.
- **Trust is entirely delegated to the carrier.** **Verified by direct word-search: `SPEC.md` contains _zero_ occurrences of trust, provenance, signature/signing, integrity, auth, tamper, verify, checksum, or hash.** Git is the *recommended* carrier "(provides history, attribution, diffs)." OKF makes **no security claims by design.**
- **Reference tooling (proof-of-concept, not required):** a two-pass enrichment agent (BigQuery walk → LLM doc-crawl) and a single-file static HTML graph visualizer (Cytoscape.js, "no data leaves the page").

### 2.2 ICM/MWP — orchestration as a walkable folder structure

ICM/MWP argues that for **sequential, human-in-the-loop** work, a *single* agent walking a **numbered-folder** structure replaces framework-level multi-agent orchestration:

- **Numbered folders = stages; markdown files = per-stage role/prompt/context.** One agent plays each role in turn by reading the right files at the right moment.
- **Local scripts do the mechanical (non-AI) work**; the LLM does only the judgment.
- **Four design lineages:** Unix pipelines (compose small stages), modular decomposition, multi-pass compilation (each folder = a pass), literate programming (instructions == documentation, à la Knuth/Diátaxis).
- **Explicit anti-framework stance.** The paper names CrewAI/LangChain/AutoGen as over-engineered for sequential reviewable work, and concedes (§5.2) that "automated branching would move ICM toward being a framework itself" — i.e. it deliberately stops at the line loa crossed on purpose.
- **Honest scope limits.** ICM is *not* for high-concurrency, tight-loop, or programmatically-branching workflows. Its headline quantitative figures (≈2–8k vs 42k tokens; a 33-practitioner U-shaped intervention curve) are the paper's **own uncontrolled, single-model, content-production-only** numbers (§4.6 admits no controlled comparison) — **illustrative, not evidence.**

### 2.3 The unifying insight: both are loa's mirror image

| Axis | OKF / ICM-MWP | loa |
|---|---|---|
| Knowledge structure | 1 required field, producer-defined rest | 33 JSON Schemas + ~5 bespoke encodings (KF-NNN, lore YAML, GT, vision, handoffs) |
| Failure posture | **fail-soft** (broken links = future knowledge) | **fail-closed** (dangling refs = defects; ATK-3/4 verify-for-merge) |
| Relationship graph | untyped, prose-carried, grep-resolved | typed/lifecycle (lore Active/Challenged/Deprecated/Superseded) + grounding (`file:line`) |
| Orchestration | one agent walks folders; "no framework" | multi-gate pipeline + cheval multi-model + run-mode autonomy |
| Trust/provenance | **none in spec** — delegated to git | Ed25519 hash-chained MODELINV + JCS canonicalization + trust-store root |
| Adoption model | format-not-platform, vendor-neutral | bespoke single-repo framework |

loa is at the opposite, heavyweight end of *every* axis — much of it on purpose. The analysis below separates the *essential* heavy end (keep, and lead with it) from the *accidental* heavy end (where OKF/ICM legibility is a genuine, cheap win).

---

## 3. loa architecture mapping (3 layers)

### 3.1 Knowledge / context layer
loa maintains a **heterogeneous federation** of agent-consumed artifacts across three zones (`zone-system.md`): State (`grimoires/loa/` — PRD/SDD/sprint, NOTES.md, known-failures.md, lore, gt/ground-truth, vision, a2a/handoffs, memory `*.yaml` + `observations.jsonl`), System (`.claude/data/`, `.claude/schemas/` — 33 schemas), and semantic sidecars (`.ck/`, qmd). Consumption is JIT/progressive-disclosure (QMD semantic → CK embeddings → grep). **loa independently converged on the OKF pattern before OKF existed** — `gt/` (one-concept-per-file markdown + index hub + `checksums.json`) and `lore/` (linked YAML with lifecycle state + lineage) are OKF-shaped *and add the provenance + lifecycle OKF v0.1 lacks*. loa also natively implements `llms.txt`. **But:** five bespoke encodings, **no cross-family ID space**, and cross-links are free-text resolved by grep — *not* a typed/path-identity graph. (`MEMORY.md` is already 366 lines / 112KB with a self-warning to compress — an early scaling signal.)

### 3.2 Orchestration layer
The plan→architect→sprint→implement→review→audit→deploy pipeline with NEVER/ALWAYS rules **mechanically enforced** (harness-level `disallowed-tools`, PreToolUse hooks `block-destructive-bash`/`zone-write-guard`), run-mode circuit breakers, cheval multi-model dispatch (chain-walk on retryable errors, voice-drop on exhaustion, never cross-company substitution), and Flatline multi-model consensus. This is the layer ICM/MWP attacks most directly — and the layer where loa's complexity is *mostly essential* (autonomy, audit, multi-model dissent are explicitly out of ICM's scope).

### 3.3 Trust / provenance / audit layer
A two-tier stack: (1) a shared cryptographic audit-envelope primitive — hash-chain + optional Ed25519 + RFC-8785 JCS canonicalization + Ed25519-signed trust-store root-of-trust (the `audit_envelope.py` / `audit-envelope.sh` family, recently hardened to fail-closed for verify-for-merge, ATK-3/4); and (2) higher-level primitives on top — L4 graduated-trust ledger, L6 content-addressable signed handoffs, L7 SOUL.md, per-invocation MODELINV records (`.run/model-invoke.jsonl`), and verdict-quality gating ("status:clean is impossible when verdict quality is degraded"). **This is loa's single biggest structural differentiator** vs OKF (trust = git, implicit) and ICM/MWP (trust unaddressed).

---

## 4. Competitive landscape (June 2026)

The field has settled into a **layered standards stack** (complementary, not competing) and **two orchestration camps**.

**The stack:** `AGENTS.md` (instructions, fires first) → `llms.txt` / **OKF** (curated knowledge in) → **MCP** (agent↔tool/data) → **A2A / AGNTCY** (agent↔agent). All four sit under Linux Foundation / Agentic AI Foundation governance — vendors deliberately ceded single-company control, which *de-risks adoption*.

**The two orchestration camps:** (a) **code/runtime** frameworks (LangGraph, CrewAI, AutoGen/AG2→Microsoft Agent Framework GA, Google ADK, OpenAI Agents SDK) — compiled graphs/classes + persistence backend; and (b) **filesystem/markdown** frameworks (GitHub Spec-Kit, BMAD, ICM/MWP, **loa**) — orchestration *is* the repo's folder+markdown structure. loa is squarely in camp (b), plus an audit layer nobody in either camp ships.

**2026 cross-cutting trends:** AGENTS.md convergence (60k+ repos, 25+ tools); **spec-driven development "eating" the segment** (Spec-Kit, Kiro, Factory, Antigravity, BMAD) — loa's PRD→SDD→sprint is an *early, opinionated* instance; generator-verifier / separate-context review as the consensus verification primitive (Cognition's published doctrine, Amp's Oracle, Aider architect/editor) — direct external validation of Flatline; context-isolated subagents as table-stakes; and **trust/provenance as the hardening frontier** (MCP Sigstore/SBOM/ETDI signed tool-defs landing in the 2026-07-28 spec; A2A signed Agent Cards).

### Where loa LEADS
1. **Cryptographic tamper-evident provenance.** *No* competitor in any segment ships signed, hash-chained audit — they stop at OpenTelemetry tracing (code camp), git-trailer links (Amp), platform CI logs (Copilot), or A2A signed Agent Cards. The whole ecosystem is *racing toward what loa already has*. **This is loa's clearest, most defensible lead.**
2. **Cross-company multi-model adversarial review** (Flatline + cheval) vs competitors' single second-opinion model.
3. **Mechanically-enforced multi-gate pipeline** (disallowed-tools + hooks) vs advisory `constitution.md`/YAML.
4. **Compounding failure-recurrence memory** (known-failures.md, recurrence ≥3 = structural signal) — no competitor formalizes anti-repeat memory.

### Where loa LAGS
1. **Semantic codebase retrieval at scale** — the biggest gap. Augment Context Engine (400k+ files), Sourcegraph Deep Search, Aider repo-map (tree-sitter + PageRank), Cursor indexing all provide ranked retrieval; loa relies on grep + CLAUDE.md (fine for its own repo, weak for large/unfamiliar/multi-repo).
2. **No root `AGENTS.md`** — the 2026 lingua franca. loa *reads* it but doesn't *emit* one; cheap portability/discoverability gap.
3. **Async cloud-VM / zero-setup execution** (Jules, Copilot agent, Devin, Factory) — loa is local-only.
4. **Single-vendor model dependency / cost exposure** (KF-002/017/020 substrate fragility).
5. **MCP-server trust = static allowlist** (verifies the registry *file*, not server *artifacts*) — lacks the Sigstore/SBOM/ETDI frontier.
6. **Concurrency / hosted observability UX** — sequential pipeline (the class ICM/MWP concedes filesystem-orch isn't for); grep-over-JSONL vs LangSmith/AgentOps dashboards.
7. **Adoption / portability / single-maintainer surface** vs Spec-Kit/BMAD's zero-lock-in ecosystems.

*(Full citation set in the appendix.)*

---

## 5. The core decision frame

Three questions decide everything below, and the synthesis (§6–§8) answers them:
1. **Is OKF an export/interchange layer _on top of_ loa, or a replacement for loa's bespoke knowledge encodings?** (interop-of-format vs interop-of-meaning)
2. **Where is loa's orchestration complexity _essential_ (audit/multi-model/autonomy — keep and lead) vs _accidental_ (could collapse to ICM-style folders + plain files)?**
3. **Which standards does loa _adopt_ (AGENTS.md, MCP provenance), which does it _contribute to_ (its audit envelope as an optional OKF/standards provenance profile), and which does it _ignore_?**

---

## 6. Recommendations — prioritized roadmap

14 recommendations, each having survived an independent adversarial review (the rival killed/modified the rest). Ranked by value × confidence ÷ effort. `kind` ∈ {add, augment, adapt, remove, keep}.

| # | Kind | Recommendation | Source | Effort | Conf. |
|---|---|---|---|---|---|
| 1 | add | **Global cross-family grimoire index** (`grimoire-index.sh` → `INDEX.md` + `.run/grimoire-index.json`): one catalog spanning KF-NNN / vision / L-NNNN / lore / obs / handoff IDs. Generator-only. | cross-cutting | M | high |
| 2 | augment | **Wire `verify_for_merge` into one real merge boundary + run the trust-store signing ceremony** (hard-ordered: bootstrap *then* wire; until then REFUSE on `BOOTSTRAP-PENDING`, never the producer-writable fallback). | cross-cutting | M | high |
| 3 | add | **Generated root `AGENTS.md`** projecting tool-agnostic governance (NEVER/ALWAYS/MAY, zones, golden path) from CLAUDE.md, with a CI drift gate. | competitor | M | high |
| 4 | add | **OKF read-only export layer** (`okf-export.sh`, modeled on `butterfreezone-gen.sh`) → `.run/okf-bundle/`; v1 scoped to handoffs + observations only. | OKF | M | high |
| 5 | add | **ICM Layer-2 advisory `inputs:` manifest in SKILL.md frontmatter** (`known-failures`-first), WARN-only rot-lint. Sold as glass-box/drift, *not* token budget. | ICM/MWP | M | high |
| 6 | remove | **Quarantine + honestly relabel the dormant Ed25519 / L4 tier** EXPERIMENTAL/build-ahead; stop loading L4 by default. Relabel, not delete. | cross-cutting | L | high |
| 7 | add | **KF/NOTES minimal-conformance write helper** — block only on the load-bearing KF Evidence cell (SHA/PR/run-ID); free-text the rest. | OKF | M | med |
| 8 | adapt | **Make file-presence authoritative for workflow _position_**; demote `.run/sprint-plan-state.json` position fields to a derived cache (keep autonomy counters first-class). Ship with a drift-repro test. | ICM/MWP | L | med |
| 9 | add | **Cross-session edit-the-source recurrence detector** (read-only, propose-only; never auto-writes `.claude/` or appends KF). Closes ICM §6.3. | ICM/MWP | L | med |
| 10 | keep | **Keep the cheval/Flatline multi-model substrate + independent review/audit gates as-is.** ICM §5.2 disclaims this territory; the field validates it. | competitor | S | high |
| 11 | keep | **Explicit non-adoption: OKF fail-soft consumption MUST NOT enter any loa validator/gate.** Write it into `zone-state.md`. | OKF | S | high |
| 12 | add | **OKF ingest contract — DOC ONLY** (parse-soft / promote-strict, route through `cross-repo-status-lib.sh`). No code until a real feed exists. | OKF | S | med |
| 13 | add | **OKF detached provenance-profile sidecar PROTOTYPE** (`okf.provenance.jsonl`, JCS hash-chain) — the upstream-contribution hedge. No maintainer engagement yet. | cross-cutting | L | spec. |
| 14 | add | **Self-contained OKF HTML graph visualizer** — defer to LAST, after the index resolves real edges (v2). | OKF | S | med |

### Tier 1 — do now (the high-confidence core)

- **#1 Index the corpus.** This is the keystone: nothing else in the interop story works without it (the "OKF visualizer for free" claim is *false* until free-text references are normalized into edges — verified). Highest-leverage target is the ~325 un-indexed `a2a/` directories. It's also the corpus-level analog of OKF's `index.md` and ICM's Layer-1 routing — progressive disclosure instead of blind grep.
- **#2 Activate the dormant moat.** `audit_verify_chain(verify_for_merge=True)` is correct and tested but unwired (#1104). An audit gate that never fires is ceremony, not security. The ordering is a hard dependency: run the offline signing ceremony (`runbooks/audit-keys-bootstrap.md`) to populate the trust-store root, *then* wire the gate into one boundary (post-merge / run-mode PR path) behind an operator opt-in. **This is the single change that turns loa's marketed crypto lead from a design document into a live control.**
- **#3 Emit `AGENTS.md`.** loa already *parses* AGENTS.md (`autonomous-agent/SKILL.md`) but doesn't *emit* one — it consumes the 2026 lingua franca without speaking it. Generated-not-hand-edited, with a drift gate (the `model-config.yaml.checksum` lockfile is the precedent). Cheap portability + discoverability for mixed-toolchain teams.
- **#4 OKF export, scoped small.** Prove the near-zero-work claim on the two already-typed families (handoffs, observations) before touching the harder encodings. The grimoire stays source of truth; OKF is a derived projection downstream of every gate — exactly like BUTTERFREEZONE.
- **#5 Inputs manifest as glass-box, not scoping.** Advisory `inputs:` in SKILL.md frontmatter + a WARN-only rot lint (a declared path that has vanished). Explicitly **not** justified on token budget (the ICM figures are uncontrolled anecdote); justified on legibility + drift-resistance, which survive even if context windows grow unboundedly.

### Tier 2 — hygiene & honesty
**#6** apply loa's own YAGNI ladder to its crown jewel (relabel the dormant crypto tier rather than carry it as a live guarantee); **#7** put a thin tamper-resistance floor under the two files CLAUDE.md mandates reading first; **#8** fix the documented `RUNNING`-while-committed state drift by making the filesystem authoritative for *position* (loa is already MWP-isomorphic at the sequencing level — `.run` position is the accidental in-memory layer that drifts); **#9** close ICM's own §6.3 doctrine-vs-mechanism gap with a propose-only recurrence detector.

### Keep / hold (the moat and its guardrails)
**#10** the multi-model substrate and gates are the moat — don't let an over-zealous simplicity pass delete loa's clearest lead (bound "simplify" to the prose-heavy orchestration *wrappers* and the 4 overlapping orchestrators, never the substrate); **#11** the explicit fail-soft non-adoption line; **#12** the ingest contract as a doc, not code (building it now manufactures a 7th dormant security surface — the exact pattern #6 removes).

### Speculative (hedges, low cost/benefit today)
**#13** the detached provenance sidecar is where loa genuinely *exceeds* OKF and could contribute upstream — but only after OKF shows traction (it is days-old v0.1) *and* loa's signing tier is bootstrapped; **#14** the visualizer is a thin late consumer of the index, not a justification for it.

### Quick wins (S-effort, high-confidence, this week)
1. Write the **OKF fail-soft non-adoption line** into `.claude/rules/zone-state.md` (#11).
2. Capture the **OKF ingest contract** as a one-paragraph proposal doc (#12).
3. **Relabel the dormant Ed25519/L4 tier** EXPERIMENTAL in its header + `agent-network-reference.md` (#6b), noting standards-contribution intent.
4. **Schedule the offline trust-store signing ceremony** (`runbooks/audit-keys-bootstrap.md`) — the operator-task unblocker for #2.

---

## 7. Tensions resolved

The six sharpest decision-relevant collisions the phase-1 critic surfaced, and how the synthesis resolves each:

1. **Interop-of-format vs interop-of-meaning.** *Not* in conflict — they live at different boundaries. loa keeps interop-of-*meaning* internally (validators stay fail-closed, schema-rigorous) and adds interop-of-*format* only on the export wire. Verified hard limit: `structured-handoff-lib.sh` enforces `additionalProperties:false` and `sys.exit(2)` on unknown keys — the literal inverse of OKF's tolerate-unknown-keys — so "rigorous producer, permissive wire format" is achievable **only as export**, never as OKF extension-keys inside loa's own validators.
2. **Fail-soft vs fail-closed.** Resolved by *direction* + the **parse-soft / promote-strict** split: at a (future) ingest boundary loa tolerates a bundle's broken links at parse time but refuses to *promote* any unverified claim into a grounded artifact. fail-closed posture reinforced, not breached.
3. **ICM-simplicity vs loa audit/autonomy gates — spectrum or different problems?** **Different problems.** ICM §5.2 explicitly disclaims concurrency, automated branching, error recovery, multi-model review — the exact territory loa crossed on purpose. So partition: the multi-model/audit/autonomy *substrate* is essential (keep); the *accidental* complexity is the prose-heavy skill bodies, 4 overlapping orchestrators, and the drifting `.run` position-state.
4. **Per-skill context-scoping vs monolithic front-load.** Per-skill scoping *cannot* actually scope what loads in loa — the safety floor (destructive-bash guard, zone-write-guard, known-failures-first, the Karpathy/guardrail prelude) is hook/CLAUDE.md-injected regardless. So the inputs manifest ships **advisory + WARN-only-rot-lint**, and the "replace the front-load" framing is *rejected* (it carries the mechanical C-PROC-001 process-compliance floor).
5. **The obsolescence hedge (ICM §5.4).** We bisect along it and refuse to spend on the time-limited side: **no recommendation is justified primarily on token budget.** Index, inputs manifest, and file-presence authority are all justified on the durable axis (glass-box, editability, auditability, drift-resistance) that survives unbounded context growth.
6. **Uniform frontmatter + global index vs five bespoke encodings.** Take the **index unconditionally** (#1, strongest survivor) but normalize encodings only where cheap + safe: leave handoffs alone (content-addressed reference shape), skip prd/sdd/sprint blockquotes (no machine consumer — `golden-path.sh` detects by file presence), and give visions + KF real frontmatter *purely to enable export* — framed as internal normalization, never "adopt OKF's permissive contract internally."

---

## 8. Positioning & explicit do-not-do

### Positioning statement
In the June-2026 field, agentic-dev has bifurcated into a **code/runtime camp** (LangGraph, CrewAI, AutoGen/AG2, Google ADK, Microsoft Agent Framework — all outsourcing trust to OpenTelemetry/LangSmith observability) and a **filesystem/markdown camp** (Spec-Kit, BMAD, ICM/MWP, **loa**). loa is **the most heavily-governed member of the filesystem camp** — the only framework in *either* camp shipping agent-decision-level tamper-evident hash-chained audit, cross-*company* multi-model adversarial dissent with honest voice-drop, and mechanically-enforced (disallowed-tools / zone-hook) gates. The field is racing toward exactly loa's frontier (EU AI Act Art.12 lifecycle logging, MCP Sigstore/ETDI, A2A signed Agent Cards) and loa is *already there in design*. **The honest position: "tamper-evident and uniquely adversarial, not yet tamper-proof"** — because the signing tier is dormant. loa should position as **the governance-and-audit layer that _speaks_ the settled interop standards on the wire** (AGENTS.md as portable lingua franca, OKF as a knowledge export skin) **while keeping its bespoke fail-closed trust core as the differentiator the standards are silent on by design — and it should _activate_ that core, not only defend it in prose.**

### Explicit do-not-do (anti-recommendations)
- **Do NOT replace the grimoire with OKF as source of truth** — that discards the hash-chain/Ed25519/verdict-quality layer that is loa's only clear field-wide lead. OKF is an export skin.
- **Do NOT import OKF fail-soft consumption into any validator/gate** — it is the inverse of loa's grounding contract; write the non-adoption down so no future contributor cites OKF to soften a check.
- **Do NOT touch the handoffs frontmatter** to make it OKF-shaped — `handoff_id` is content-addressed; changing the key set breaks determinism.
- **Do NOT convert prd/sdd/sprint blockquote frontmatter** as a portability play — nothing machine-parses it; pure churn.
- **Do NOT build the OKF ingest wrapper/sanitizer/MODELINV wiring now** — no ingest path exists; it manufactures a 7th dormant security surface (the exact pattern #6 removes). Ship the contract as a doc.
- **Do NOT delete the Ed25519/L4 tier outright** — relabel EXPERIMENTAL; deletion forecloses the contributable-standard/multi-tenant future. The bug is it *reading* as a live control, not its existence.
- **Do NOT sell any scoping/index work on token-budget grounds** — the ICM figures are uncontrolled single-model anecdote (§4.6).
- **Do NOT make the inputs-manifest lint a fail-closed "declared-but-not-read" gate** — skills read conditionally by phase; such a gate is wrong-by-construction (the skill-invariants silent-refusal class).
- **Do NOT let any recurrence detector auto-write `.claude/` or auto-append known-failures.md** — a bot appending Evidence rows is the exact tamper surface the Evidence column defeats. Propose-only.
- **Do NOT collapse the cheval/Flatline/gate substrate** in the name of ICM simplicity — simplify the prose-heavy wrappers and parallel state files instead.
- **Do NOT adopt RDF/heavy-KG or A2A networked inter-org comms now** — agent-memory is the one pre-standard layer (wait-and-watch); A2A only matters if loa goes cross-host, which its handoffs deliberately refuse.
- **Do NOT wire `verify_for_merge` to silently fall back to the producer-writable local-pubkey path** — until bootstrap, the only honest behavior is to REFUSE on `BOOTSTRAP-PENDING` with a loud DEGRADED verdict.

---

## Appendix — method & citations

**Method.** Two sequential multi-agent workflows under the "ultracode" orchestration mode:
- *Phase 1 (research + mapping):* 8 grounded agents (2 source deep-dives, 3 loa-architecture-layer maps, 3 competitive-landscape segments) + 1 completeness critic. ~736K subagent tokens.
- *Phase 2 (panel + synthesis):* a 4-lens principal-engineer panel (interop / simplicity / security / strategy), one adversarial rival per lens, and a chief-architect synthesizer. ~1.02M subagent tokens. **The `strategy` lens dropped on a mid-response connection error;** its competitive-positioning material is fully covered by the phase-1 competitive segment and folded into §4/§8, so no perspective was lost.
- *Primary-source verification:* OKF `SPEC.md` and arXiv 2603.16021 were re-fetched directly to confirm load-bearing claims (the "zero trust-terms" negative-existence claim; the ICM/MWP naming; the uncontrolled nature of the quantitative figures). loa-side facts (dormant `verify_for_merge`, `BOOTSTRAP-PENDING` trust-store, unsigned MODELINV, L4 zero-footprint, 33 schemas, ~325 a2a dirs) were grep/disk-verified by the mapping agents.

**Honesty caveats carried throughout:** ICM/MWP's token + practitioner figures are the paper's own uncontrolled, single-model, content-production-only numbers — illustrative, not evidence. loa-side counts are agent-verified but should be re-confirmed before any implementation cycle.

**Selected citations** (full set ~72 URLs across the three competitive segments; representative):
- OKF: [Google Cloud blog](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) · [`okf/SPEC.md`](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
- ICM/MWP: [arXiv 2603.16021](https://arxiv.org/abs/2603.16021)
- Standards: [agents.md](https://agents.md/) (AAIF/Linux Foundation, 60k+ repos) · [MCP registry](https://registry.modelcontextprotocol.io/) · [MCP 2026-07-28 RC](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/) · [A2A → Linux Foundation](https://www.linuxfoundation.org/press/a2a-protocol-surpasses-150-organizations-lands-in-major-cloud-platforms-and-sees-enterprise-production-use-in-first-year)
- Dev tools / frameworks: [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) · [Aider repo-map](https://aider.chat/docs/repomap.html) · [CrewAI](https://docs.crewai.com/) · [LangGraph](https://docs.langchain.com/oss/python/langgraph/graph-api) · [MetaGPT](https://github.com/FoundationAgents/MetaGPT) · [ICM reference impl](https://github.com/RinDig/Interpreted-Context-Methdology)

> **Status note.** This is an R&D scoping artifact, not an implementation commitment. Each Tier-1 recommendation that touches code (`#1`–`#9`) must go through loa's normal `/plan` → `/implement` → review → audit pipeline; the quick wins (#11, #12 docs; #6b relabel; #2 ceremony) are the cheapest first steps and several are doc/operator-only.
