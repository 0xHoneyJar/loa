# 10 — Build Roadmap: Phases and Slices

> Status: ACCEPTED AS AN EVIDENCE SEQUENCE by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> This roadmap follows the repo's established rhythm: small audited slices, fixtures before checks,
> checks in lockstep with fixtures, doctrine before machinery, independent
> audit before PR, authority acceptance at every checkpoint. Slice numbers
> continue the existing sequence (slices 1–5 landed; slice 6 = PR #16 in
> flight). Numbers after 6 are proposals — the authority re-orders freely.

## Phase map

```
Phase A  CONTRACTS ON PAPER      slices 6–8    front door, plan acceptance,
         (docs only)                           prompt-pack doctrine
Phase B  MECHANICAL TRUST        slices 9–12   run fixture + run-mode checker,
         (fixtures + kernel)                   evidence roles, route cards,
                                               discovered-fixtures mode
Phase C  AGENT EXECUTION         slices 13–15  supervised dry-run replay,
         (validated runners)                   instance #1 live run,
                                               mode-equivalence exercise
Phase D  PROJECTION              slices 16–18  Tier-1 types, projection kernel
         (Précis → documents)                  checks, first Tier-2 plugin (PRD)
Phase E  SECOND ARM + V1         slices 19–21  convergent golden corpus,
         (hardening)                           envelope review, v1 declaration
```

Sequencing rules: Phase B before C (an agent is never validated against
checks that do not exist); C before D-at-scale (project from Précis artifacts
whose production you trust); the convergent golden (Phase E) can start
anytime material exists — it gates v1, not earlier phases. Daily-research
issues keep feeding candidate adjustments throughout, via their own
PROPOSE/audit path.

Every slice below inherits the **standing slice contract**:

> Scope stated up front; explicit not-in-this-slice list; docs/fixtures and
> checks land in lockstep or not at all; negative battery extended when the
> kernel changes; independent audit precedes the PR; authority accepts;
> validation ledger updated when a capability claim changes. A slice that
> cannot state its Definition of Done is not ready to start.

---

## Phase A — Contracts on paper

### Slice 6 — Front door (in flight: PR #16)
Already open. AGENTS.md routes zero-context readers into agent / manual /
repo-consumption paths with status honesty. **DoD:** merged after audit; links
resolve; checker untouched and green.

### Slice 7 — Architecture plan acceptance
This tree (`docs/architecture/`) reviewed by the authority; pruned, amended,
and either accepted *as a proposal of record* or promoted piecewise into
doctrine (the tenets and stage graph are candidates for promotion; the
provisional field lists deliberately are not).
**DoD:**
- [ ] authority has read and dispositioned each of the 13 documents
      (accept / amend / defer — recorded)
- [ ] contradictions with accepted doctrine: zero (audit checks this
      explicitly)
- [ ] the open decisions in doc 12 §2 each have an owner and a
      decide-by slice noted
- [ ] a decision record captures what, if anything, was promoted to doctrine

### Slice 8 — Prompt-pack doctrine (docs only)
The stage prompts (role charters, lens charters, refute-first verifier
framing, orchestrator autonomy envelope) written as reviewable documents under
`docs/architecture/prompts/` (or location the authority prefers). No tooling —
prompts are docs that agent mode will later load verbatim.
**DoD:**
- [ ] one prompt doc per role in doc 05 §2 and per verifier lens in doc 06 §3
- [ ] each prompt states goal, constraints, output contract, blind rule — and
      contains no step-scripts (prompt doctrine rule 1 verified by audit)
- [ ] no prompt asks a worker to invent external facts, and every judgment
      prompt carries the referent rule verbatim (audit greps this)

---

## Phase B — Mechanical trust

### Slice 9 — Golden run fixture + run-mode kernel (K2)
Hand-author (manual mode) a **complete run directory** for the slice-2
adversarial corpus — the existing fixture re-expressed as a full run: manifest,
criteria, packet index, inventory, ledgers, tags, cards, matrix, synthesis,
precis, worksheets. Then extend the checker with run-directory mode (K2),
negative battery included.
**Why slice-2 corpus:** already accepted, already adversarial, small enough to
hand-author honestly; its Précis becomes the cross-check.
**DoD:**
- [ ] run directory complete per doc 03; every packet locator manually
      verified to reopen its span
- [ ] the run's assembled Précis is envelope-equivalent to the accepted
      slice-2 `precis.md` (differences enumerated and justified)
- [ ] K2 checks pass on the golden and fail closed on ≥8 mutation cases
      (missing manifest field, dangling `PKT`, unordered state log, hash
      mismatch, criteria postdating packets, …)
- [ ] existing fixture checks all still green; audit; acceptance

### Slice 10 — Evidence-role fixture + checks (K3)
ALEPH-EVIDENCE-ROLE-001 (issue #18) executed: a bounded corpus seeded with a
cited-but-decorative source, an uncited-but-load-bearing source, a synthetic/
unverifiable source, a contradictory source; evidence-role ledger authored;
K3 checks + battery.
**DoD:** issue #18's acceptance criteria, verbatim, plus: existing fixtures
unaffected (evidence roles are additive; no retrofit forced on slice-1/2);
manual-mode sparse rule (doc 09 S6) confirmed or amended by the experience;
validation-ledger entry: evidence-role ledger fixture-validated.

### Slice 11 — Routed-corpus fixture + card checks (K4 + K5)
First worked demonstration of the four-layer cluster model: pre-cluster tags,
route cards with postures and shape vectors, a pending external referent with
its `REF` record and visible taint, resolution of that referent by recorded
authority supply, and the resulting re-route. K4/K5 checks + battery.
**DoD:**
- [ ] the smallest manual-mode invariant is now *enforced*, not just stated
- [ ] taint computation demonstrated: fixture shows the marker present
      pre-resolution, absent post-resolution, with the cone listed
- [ ] routing doctrine §13's "no conformance check yet" paragraphs amended in
      the same PR (doctrine and enforcement move together)

### Slice 12 — Discovered-fixtures mode (K1) + `--json` (K7 first half)
The checker generalizes beyond hardcoded slice-1/slice-2 expectations to
declared-expectation fixtures, and gains the machine-readable report agent
mode will consume.
**DoD:** all existing fixtures pass undeclared-behavior-identical; a new
minimal fixture passes purely via declared expectations; `--json` output
schema documented; battery extended.

---

## Phase C — Agent execution

### Slice 13 — Supervised dry run (replay of the golden run)
Agent mode executes the slice-9 corpus end-to-end under the runbook (doc 08)
with the prompt-pack (slice 8), a human watching every gate, and **no
acceptance authority**. Output: a replay report against the golden — the first
real measurements of extraction recall, disposition agreement, merge
precision, phantom rate, cost.
**DoD:**
- [ ] full run directory produced by the agent; kernel green
- [ ] replay metrics computed and reported per doc 06 §5 (thresholds are
      *set* by the authority on seeing this data, not required in advance)
- [ ] every deviation between agent run and golden dispositioned by the
      authority as agent-error / golden-error / acceptable-variance
- [ ] runbook and prompt-pack amended from the experience (`lessons.md`
      seeded)
- [ ] validation ledger: agent-mode fixture-scale replay recorded with its
      numbers — *sanctioning decision explicitly reserved*

### Slice 14 — Instance #1 (the 333-conversation corpus)
The first real corpus: curated ~20-thread export, supervised agent mode,
every gate held, PII/sensitivity handling per S0. This is simultaneously the
first production Précis and the second golden (adversarial-arm at real
scale).
**DoD:**
- [ ] S0 sensitivity review completed by the authority before any extraction
- [ ] run reaches ACCEPTED through the full S13 path (audit included)
- [ ] cost/wall-clock/coverage reported against the slice-13 calibration
- [ ] the accepted run is frozen as golden corpus #2
- [ ] validation ledger: agent-mode-at-scale entry with evidence; decision
      recorded on whether agent mode is now a sanctioned path (and with what
      supervision requirements)

### Slice 15 — Mode-equivalence + reconstructability exercise
Per doc 06 §6, on a bounded corpus: manual run and agent run compared at the
contract level; agent rebuilds the full graph from the manual run's sparse
cards + raw source.
**DoD:** equivalence report; zero unresolvable references in the
reconstruction; divergences fed into runbooks or the validation ledger;
validation ledger: mode-equivalence entry.

---

## Phase D — Projection

### Slice 16 — First Tier-1 projection type (product-doctrine)
Template + authoring instructions + fixture (rendered from the slice-9 golden
Précis) + trace/selection ledger + K6 checks + battery. The Straylight manual
precedent is the reference shape.
**DoD:** the five-part package of doc 07 §2, complete; audit confirms every
load-bearing statement traces; validation ledger entry.

### Slice 17 — Remaining Tier-1 types
architecture/primitive-map, responsibility/environment-verification map,
mvp-wedge selection — same package each, may land as one slice or three at
the authority's pace. **DoD:** per-type five-part package.

### Slice 18 — First Tier-2 plugin: PRD
The headline promise. Template with explicit domain assumptions; renders from
Tier-1 + Précis; gaps-stay-gaps demonstrated in the fixture (the fixture
Précis deliberately lacks something the template wants).
**DoD:** five-part package; a full corpus→PRD walk on golden material passes
P1–P3 including audit and acceptance.

---

## Phase E — Second arm and v1

### Slice 19 — Convergent-arm golden corpus
The long-standing gap (validation ledger): author a known-category /
novel-delta hybrid corpus with supplied referents; run manual-mode
distillation with a heavy convergent weighting; freeze as the second replay
corpus; name the reconciliation artifact shape from the evidence.
**DoD:** golden accepted; routing doctrine §12 validation ledger updated —
convergent-heavy and hybrid move to validated *only if the evidence says so*;
reconciliation artifact contract (doc 03 artifact 13) amended to match
reality.

### Slice 20 — Envelope review
With real runs, evidence roles, cards, and projections in hand: the authority
revisits the v0 acceptance envelope — amend (fold in evidence-role summary?
routing summary?), then freeze or explicitly re-provisionalize. Checker moves
in lockstep either way.
**DoD:** decision record; fixtures + kernel updated together; no orphaned
"provisional" language left contradicting the decision.

### Slice 21 — v1 declaration
Audit the system-level Definition of Done ([doc 01 §5](01-vision-and-tenets.md))
item by item against evidence. Anything unmet spawns its slice; when all six
hold, declare v1 in the README with the validation ledger as the proof.
**DoD:** the six items, each citing its artifact/PR; known-limits section
still present and true.

---

## Standing tracks (not slices)

- **Daily-research intake:** the existing issue pipeline keeps proposing;
  proposals map onto this roadmap or extend it via slice 7's amendment path.
- **Validation ledger upkeep:** every slice that changes a capability claim
  touches it, in the same PR.
- **Lessons:** `lessons.md` accrues from slice 13 onward; runbook/prompt-pack
  amendments cite lessons entries.
- **Risk review:** doc 12's register is re-walked at each phase boundary.

## Dependency graph (summary)

```
6 ──► 7 ──► 8 ──────────────► 13 ──► 14 ──► 15
      │                        ▲      │
      ├──► 9 ──► 12 ───────────┘      │
      │    │                          ▼
      ├──► 10 ─┤                16 ──► 17 ──► 18 ──► 21
      └──► 11 ─┘                              ▲      ▲
                     19 ──────────────────────┘      │
                     20 ─────────────────────────────┘
```
(9→13: the dry run replays the golden run; 10/11 feed 13's checks; 19 and 20
gate only 21.)
