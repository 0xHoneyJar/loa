# Aleph Slice 1 — v0 Précis Fixture

This directory is a **synthetic, docs-only fixture**. It proves Aleph's
file-first doctrine by carrying one concrete v0 Research Précis artifact,
distilled from a small bounded corpus, with a complete candidate-claim
disposition trail.

**This fixture is instance #1, not Aleph's full scope or boundary.** It is
synthetic: it contains no real ChatGPT export content, no real competitor
claims, and no market conclusions. It is **docs / fixture only** — no code, no
endpoint, no package files, no runtime, no schema freeze.

## Files

| file | role |
|------|------|
| `corpus.md` | the bounded input: three synthetic source fragments (`SRC-001…003`) |
| `precis.md` | the v0 Research Précis artifact distilled from the corpus |
| `README.md` | this guide + self-check tables + out-of-scope list |

How to read it: start with `corpus.md` (the raw bounded input), then read
`precis.md` (the distilled, normalized, disposition-bearing artifact). The
tables below let you verify the Précis against the wedge contract in
`../../precis-wedge.md`.

## Self-check — 10 wedge acceptance criteria

Mapping each criterion from `../../precis-wedge.md` to where it is satisfied in
`precis.md`.

| # | wedge acceptance criterion | satisfied at |
|---|----------------------------|--------------|
| 1 | Source inventory exists | `precis.md` §2 (SRC-001/002/003) |
| 2 | Extraction method / inclusion criteria recorded | `precis.md` §3 |
| 3 | Candidate-claim inventory exists | `precis.md` §4 (CC-001…CC-010) |
| 4 | Every candidate claim has a disposition | `precis.md` §4 (10 claims, 10 dispositions) |
| 5 | `judged-non-load-bearing` is an explicit disposition | `precis.md` §4/§5 (CC-009) |
| 6 | Duplicate claims merged with provenance retained | `precis.md` §7, §11 (CC-002 ← CC-007) |
| 7 | Excluded claims carry reasons | `precis.md` §9 (CC-008) |
| 8 | Deferred / unresolved claims remain visible | `precis.md` §8 (CC-003), §14 (CC-010) |
| 9 | No downstream projection generated yet | `precis.md` §15 (projections named, none generated) |
| 10 | Output is a portable, projection-neutral Précis file | `precis.md` (single self-contained file) |

## Self-check — seven-disposition coverage

Every disposition in the valid set appears on at least one candidate claim.

| disposition | claim_id(s) | shown at |
|-------------|-------------|----------|
| carried | CC-001, CC-004, CC-006 | `precis.md` §6 |
| merged | CC-002 (← CC-007) | `precis.md` §7, §11 |
| deferred | CC-003 | `precis.md` §8 |
| excluded-with-reason | CC-008 | `precis.md` §9 |
| backgrounded | CC-005 | `precis.md` §10 |
| judged-non-load-bearing | CC-009 | `precis.md` §4, §5 |
| unresolved | CC-010 | `precis.md` §14 |

## A vs B note (presentation vs inventory)

Per `../../precis-wedge.md`, **B compresses presentation only, never inventory.**
In this fixture, non-load-bearing material (e.g. CC-009, portal color) is grouped
out of the cluster-synthesis narrative (`precis.md` §13) for readability, but
**every candidate claim — including CC-009 — still has its own individual entry
and disposition in the §4 inventory.** Grouping never created an off-ledger
discard path.

## Fixture-design notes (why each fragment was seeded)

These notes are fixture scaffolding for auditors — they explain why each source
fragment in `corpus.md` exists. They live here, in the README, deliberately:
`corpus.md` must read as a blind bounded input, not as an answer key.

- **Duplicate to merge:** SRC-001 "gated access keeps members engaged" and
  SRC-003 "token gating improves retention" are near-duplicate retention claims
  → merged in the Précis (provenance from both retained) → CC-002 ← CC-007.
- **Carried (load-bearing):** SRC-001 token-gated membership primitive (CC-001);
  SRC-002 tiered holder levels (CC-004); SRC-002 gated perks drive referrals
  (CC-006).
- **Deferred:** SRC-001 fungible-vs-multi-token choice (CC-003).
- **Excluded-with-reason:** SRC-003 "launch its own L2 chain" (CC-008) — out of
  declared corpus scope and contrary to the read-only PoC posture; no supporting
  evidence.
- **Backgrounded:** SRC-002 "token-gated communities are common" (CC-005) —
  market context, not load-bearing to the access model.
- **Judged-non-load-bearing:** SRC-003 "accent color should be teal" (CC-009) —
  a real candidate claim that entered the inventory, then judged
  non-load-bearing (recorded, not silently discarded).
- **Unresolved:** SRC-003 referral reward denomination, token vs points (CC-010).

## Out of scope (for this fixture and slice)

- No code, no endpoint, no API.
- No `package.json`, no npm/pnpm/yarn, no lockfiles.
- No runtime or config files; no generated files.
- No machine schema; no schema freeze (Markdown prose + tables only).
- No PRD, GTM plan, market landscape, product spec, or any downstream projection.
- No adjacent-consumer formalization; no Freeside implementation.
- No real ChatGPT export material; no real market/competitor conclusions.
- Not the full 333-chat export; not Aleph's scope or boundary — instance #1 only.
