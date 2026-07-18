# 13 — Build Handoff (for any implementing agent or human)

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> You are reading the entry point for **building** the Aleph Method. Everything
> needed for the substrate is in this repo; this document sequences it into
> work packages with definitions of done. Where this brief and accepted
> doctrine disagree, doctrine wins.
>
> **Local implementation status (2026-07-16):** WP1-WP8 content is present in
> this worktree and the deterministic fixture suite is green. The handoff's
> governance completion signal still requires independent review, publication,
> and merge; local implementation is not that acceptance.

## 0. Mission

Build the product defined by ADR 0001's goal: a repo a person can download,
drop research into, and get finished documents out of — agent mode or manual
mode — with every invariant held and every capability claim backed by replay
evidence. You are building the *substrate* (templates, fixtures, checker,
prompt-pack): the execution runs themselves (dry run, instance #1) are
performed later, under supervision, per the runbooks.

## 1. Read order (before any work)

1. Accepted doctrine: `README.md`, `docs/precis-wedge.md`,
   `docs/responsibility-map.md`, `docs/routing-and-clustering.md`,
   `docs/decisions/0001…`, `0002…`, `docs/PRECIS-CONFORMANCE-CHECKER.md`.
2. The accepted fixtures end to end: `docs/fixtures/slice-1/`, `slice-2/`
   (corpus → precis, README self-checks), and the checker source
   `scripts/validate-precis-fixtures.ts` (all of it — its style is the
   style you will extend).
3. This architecture tree in its README reading order (docs 01–12).
4. The build kits: [`templates/`](templates/), [`prompts/`](prompts/),
   [`checker-spec/`](checker-spec/).
5. Historical context: PR #16 supplied the first front-door draft, but its
   pre-implementation status text is superseded by the `AGENTS.md` in this
   worktree and must be reconciled or closed before publication. Issue #18
   supplies the evidence-role research implemented by WP4.

Sanity check before starting: `node scripts/validate-precis-fixtures.ts`
must print `RESULT: PASS`.

## 2. Governance you operate under

- Roles per `docs/responsibility-map.md`: the authority (Eileen) approves
  scope and accepts; you implement; an independent audit precedes every PR
  merge. Whoever builds is not the one who audits — if you have historically
  played the auditor role in this repo, someone else audits your build work;
  never self-audit.
- **Default: one work package = one branch = one PR.** Decision 0003 permits
  the current substrate build to combine implementation commits on one branch.
  That exception does not combine capability or acceptance claims: each WP's
  evidence, boundaries, audit result, and authority disposition remain
  separately reviewable. Branch naming otherwise follows
  `aleph-slice-⟨n⟩-⟨slug⟩`; PR descriptions name what the change proves, files,
  boundaries, validation evidence, and audit status.
- **Authority gates for the builder:** starting a WP whose slice the
  authority has not green-lit; any doctrine amendment (only WP5 contains
  one, and it is confined to the paragraphs listed there); any deviation
  from a spec that you believe is wrong (propose in the PR, don't
  improvise); anything touching `docs/fixtures/slice-1|2` content (frozen —
  never edit).
- **Scope discipline:** each WP lists Not-in-scope items. Building ahead of
  the sequence — an extractor script, a generator, an endpoint, CI wiring —
  is a scope violation even if convenient. The do-not-build list
  (doc 12 §3) binds you.

## 3. Work packages

Dependencies: WP1 → WP2 → WP3; WP4 and WP5 after WP3 (they extend the run
kernel); WP6 anytime after WP3; WP7 after WP2 (needs the golden Précis);
WP8 last. Roadmap mapping in parentheses.

### WP1 — Review-and-land the build kits (slice 7 + 8)

The templates, prompts, and checker specs are accepted for implementation by
Decision 0003 and remain provisional where marked. Q2, Q4, Q5, and Q11 have
recorded dispositions in that decision and doc 12. Independent review and
merge remain the governance work needed to land them.

**DoD:** authority dispositions recorded per file; open questions Q2/Q4/Q5/
Q11 decided and folded in; audit passed; merged. **Not in scope:** any code.

### WP2 — The golden run fixture (slice 9, fixture half)

Hand-author the complete run directory for the slice-2 corpus at
`docs/fixtures/run-slice-2/`, following the **manual runbook** (doc 09) and
the templates verbatim. This is the master worked example every later
consumer (human, agent, checker, replay) learns from.

Work, in order: copy slice-2's `corpus.md` sources into the run layout
(split into per-source files under `corpus/sources/`, preserving content
exactly; manifest rows per T2.1); write criteria (T2.2) consistent with
slice-2's precis §3; walk S2–S11 by hand. Fixture evidence found fourteen
claim-bearing paragraphs, so the golden uses fourteen tight, non-overlapping
packets rather than manufacturing overlap to meet the original rough estimate.
Carry the existing 14 claims (CC-101..114 with their accepted dispositions —
the golden must agree with the accepted Précis), the accepted merge map,
evidence-role edges (new work), tags/cards/routing (new work — expect 3–5
route clusters; the CC-105/106 contradiction cluster is adversarial-
weighted; at least one cluster should carry a genuine `REF` need to
exercise taint), the STM-1..7 rows carried over plus evidence-removal rows,
synthesis consistent with the accepted §13, and an assembled `precis.md`
whose §1–§17 match the accepted slice-2 Précis in substance (differences
enumerated in the fixture README). Add the `aleph-fixture` declaration
(`kind: run`) and a README with self-check tables in the house style.
Respect forbidden tokens throughout (write "stage", never the roadmap
grouping word; never name the deferred business-intelligence consumer).

**DoD:** every artifact present per K2's layout table for state ACCEPTED
(simulated sign-off rows marked `fixture-simulated`); two randomly chosen
packet locators per source manually re-opened and verified in the PR
description; fixture README self-checks complete; audit; merged. **Not in
scope:** checker changes (same slice, next PR half — or same PR if the
authority prefers strict lockstep in one PR; default: one PR for both
halves, fixture commits first).

### WP3 — Run-mode kernel (slice 9, code half): `scripts/validate-run.ts`

Implement [`checker-spec/K1-K2-fixtures-and-runs.md`](checker-spec/K1-K2-fixtures-and-runs.md)
K2.1–K2.12 against the WP2 golden, under the constraints of
[`checker-spec/README.md`](checker-spec/README.md). Update
`docs/PRECIS-CONFORMANCE-CHECKER.md` with a run-mode section (same doc
style: what it proves, what it does not, failure posture, battery record).

**DoD:** golden run passes; the 11-case battery fails closed with the
intended check-ids (documented in the PR); legacy checker untouched and
green; doc updated; audit; merged.

### WP4 — Evidence-role fixture + K3 (slice 10)

Author the issue-18 adversarial fixture (new corpus, ~6 sources seeded per
the issue: decorative citation, uncited-load-bearing, synthetic source,
contradictory source, independent corroboration, restatement), its run-lite
artifacts (inventory + evidence-roles minimum, `kind: evidence-role`), and
implement K3.

**DoD:** issue #18's acceptance criteria demonstrably met (quote them in the
PR against evidence); K3 battery (8+ cases incl. the two seeded must-fails);
validation-ledger entry added; audit; merged.

### WP5 — Routed fixture + K4/K5 (slice 11)

Author the routed-corpus fixture (may extend WP2's golden run with its
clusters/ tree if the authority prefers one exemplar — default: extend the
golden) exercising: 3+ cards, one pending referent with taint, one supplied
referent with re-route, tags-stay-tags. Implement K4/K5. **This WP contains
the one doctrine touch:** amend `docs/routing-and-clustering.md` §13's
"nothing is checker-enforced" paragraphs to name what now is — same PR,
minimal diff, ADR-0002-consistent.

**DoD:** K4/K5 battery (9+ cases); smallest-manual-mode-invariant
demonstrably enforced; doctrine paragraph amended; audit; merged.

### WP6 — Discovered-fixtures mode + `--json` (slice 12)

K1 on the legacy script + `--json` on both scripts per spec.

**DoD:** byte-identical legacy output (modulo the discovery PASS line);
5-case K1 battery; `--json` schema documented in the checker doc; audit;
merged.

### WP7 — Projection kit: product-doctrine + PRD templates and fixtures (slices 16/18, template halves)

Author the two projection-type packages (doc 07 §2 items 1, 2, 3, 5 — the
template, authoring instructions, trace/selection instantiation, fixture)
rendering from the WP2 golden Précis: `product-doctrine` (Tier 1) and `prd`
(Tier 2, with explicit domain assumptions and at least one honest `gap`
row). Then implement K6 against them.

**DoD:** both packages complete per doc 07 §2 DoD; K6 battery (8+ cases);
traces resolve end to end (spot-verified in PR); audit; merged.

### WP8 — Wire the front door

The current `AGENTS.md` incorporates and extends PR #16's front-door intent so
a zero-context agent is routed: "running a distillation? → runbook 08 +
templates + prompts; building? → this handoff; consuming? → artifact
contracts." Its status table reflects the implemented local substrate. PR #16
still carries the older pre-implementation status and must be reconciled or
closed before this front door is published.

**DoD:** a zero-context reader can reach every kit in ≤2 hops from the repo
root; links verified; audit; merged.

## 4. What you explicitly do NOT build (yet)

The dry run (slice 13), instance #1 (slice 14), mode-equivalence (15),
remaining Tier-1 types (17), convergent golden (19), envelope review (20),
v1 (21) — these are execution-and-review slices run under authority
supervision, not substrate builds. Also binding: the full do-not-build list
in [`12-risks-open-questions-do-not-build.md`](12-risks-open-questions-do-not-build.md) §3 —
no extractor/generator tooling, no endpoint, no CI (until the authority
asks), no schema freeze, no scope growth into business intelligence or
product surfaces.

## 5. Completion signal

The substrate handoff is DONE when WP1–WP8 are merged: at that point the
repo contains — approved contracts and templates; a complete golden run any
runner can imitate; a kernel that validates fixtures AND runs AND evidence
roles AND routing AND projections, each proven by negative batteries; a
reviewed prompt-pack; two projection kits; and a front door that routes
anyone to any of it. Everything after that is *running the method* (Phase C
onward), which begins with the supervised dry run — a different kind of
work, gated by the authority, executed under runbook 08.
