# Aleph Slice 2 — Adversarial Précis Fixture + Stress-Test Matrix

This directory is a **synthetic, docs-only fixture**. It proves that Aleph's
file-first Research Précis doctrine **survives adversarial compression pressure**:
contradiction, three-way near-duplicates, plausible-but-excluded claims, tempting
silent discards, ambiguous unresolved material, architecture-dependent deferrals,
and do-not-use harm claims — all without losing candidate-claim disposition
coverage.

**This fixture is instance #2, not Aleph's full scope or boundary.** It is
synthetic: no real ChatGPT export content, no real competitor claims, no market
conclusions. It is **docs / fixture only** — no code, no endpoint, no package
files, no runtime, no schema freeze.

## What this fixture proves

```
bounded adversarial synthetic corpus
  → candidate-claim inventory
    → disposition ledger
      → stress-test matrix
        → projection-neutral Précis
```

The claim under test is the doctrine's load-bearing promise: *nothing
load-bearing silently vanishes, and the compression trail is inspectable.* Slice 1
proved the envelope on a benign corpus. Slice 2 proves it holds when the corpus is
actively trying to break it.

## How it differs from Slice 1

| aspect | Slice 1 (v0 fixture) | Slice 2 (adversarial fixture) |
|--------|----------------------|-------------------------------|
| corpus | 3 benign sources (SRC-001…003) | 4 adversarial sources (SRC-101…104) |
| candidate claims | 10 (CC-001…010) | 14 (CC-101…114) |
| merge | pairwise (CC-002 ← CC-007) | **three-way** (CC-104 ← CC-113, CC-114) |
| contradiction | none | **direct contradiction held unresolved** (CC-105 ↔ CC-106) |
| do-not-use | scope-based exclusion only | scope **and** a privacy-harm do-not-use claim (CC-110) |
| stress-test matrix | not instantiated | **instantiated** (trail step §94–107) |
| envelope | demonstrated | demonstrated; envelope **not amended** (Choice A) |

Slice 2 instantiates the `stress-test matrix` step named in the completeness
trail of `../../precis-wedge.md` but skipped by Slice 1. Per Choice A, the matrix
is demonstrated at fixture level only; the accepted provisional v0 envelope in
`../../precis-wedge.md` is **not** amended by this slice.

## Files

| file | role |
|------|------|
| `corpus.md` | the bounded input: four synthetic source fragments (`SRC-101`–`104`) |
| `precis.md` | the v0 Research Précis (17 envelope fields + stress-test matrix) |
| `README.md` | this guide + self-check tables + out-of-scope list |

How to read it: start with `corpus.md` (the blind bounded input), then read
`precis.md` (the distilled, disposition-bearing artifact, including the
stress-test matrix between §12 and §13).

## Self-check — seven required adversarial cases

| case | requirement | claim_id(s) | matrix row | resolved at |
|------|-------------|-------------|------------|-------------|
| Direct contradiction | two sources incompatible; not merged; visible | CC-105, CC-106 | STM-1 | `precis.md` §14, §4 |
| Three-way merge | three claims merged, all provenance retained | CC-104 ← CC-113, CC-114 | STM-2 | `precis.md` §7, §11 |
| Plausible but excluded | sounds useful, excluded-with-reason | CC-107 | STM-3 | `precis.md` §9 |
| Near-miss silent discard | normal summary would drop it; recorded instead | CC-109 | STM-4 | `precis.md` §4, §13 |
| Ambiguous unresolved | cannot be safely carried or excluded | CC-112 | STM-5 | `precis.md` §14 |
| Deferred | depends on a future consumer decision | CC-111 | STM-6 | `precis.md` §8 |
| Do-not-use / negative boundary | must not silently vanish | CC-110 | STM-7 | `precis.md` §9, §12 |

## Self-check — seven-disposition coverage

Every disposition in the valid set appears on at least one candidate claim.

| disposition | claim_id(s) | shown at |
|-------------|-------------|----------|
| carried | CC-101, CC-102, CC-103 | `precis.md` §6 |
| merged | CC-104 (← CC-113, CC-114) | `precis.md` §7, §11 |
| deferred | CC-111 | `precis.md` §8 |
| excluded-with-reason | CC-107, CC-110 | `precis.md` §9 |
| backgrounded | CC-108 | `precis.md` §10 |
| judged-non-load-bearing | CC-109 | `precis.md` §4, §13 |
| unresolved | CC-105, CC-106, CC-112 | `precis.md` §14 |

Ledger total = 14 = inventory count (`precis.md` §4, §5).

## Self-check — stress-test matrix coverage

The matrix in `precis.md` maps each case to: adversarial pressure, source refs,
candidate claim IDs, risk if handled badly, correct Aleph handling, and where
resolved. Every named risk is represented at least once.

| risk named in the brief | matrix row(s) covering it |
|-------------------------|---------------------------|
| silent disappearance | STM-4, STM-7 |
| lazy merge | STM-1 |
| false certainty | STM-5 |
| unsupported exclusion | STM-3 |
| projection leakage | STM-6, STM-7 |
| duplicate conviction | STM-2 |
| contradiction hidden by synthesis | STM-1 |

## A vs B note (presentation vs inventory)

Per `../../precis-wedge.md`, **B compresses presentation only, never inventory.**
In this fixture, non-load-bearing and refused material (e.g. CC-109 dashboard
color; CC-107/CC-110 do-not-use) is grouped out of the cluster-synthesis narrative
(`precis.md` §13) for readability, but **every candidate claim still has its own
individual entry and disposition in the §4 inventory.** Grouping never created an
off-ledger discard path.

## Out of scope (for this fixture and slice)

- No code, no endpoint, no API.
- No `package.json`, no npm/pnpm/yarn, no lockfiles.
- No runtime or config files; no generated files.
- No machine schema; no schema freeze (Markdown prose + tables only).
- **No edits to `../../precis-wedge.md`** — the accepted doctrine doc is not
  amended by this slice; the stress-test matrix is demonstrated, not formalized
  into the envelope yet.
- No PRD, GTM plan, market landscape, product spec, or any downstream projection.
- No adjacent-consumer formalization; no Freeside implementation.
- No real ChatGPT export material; no real market/competitor conclusions.
- Not Aleph's scope or boundary — instance #2 only.
