# ADR-004: The Model-generation Floor — the framework assumes the current Claude generation, ships behind an rc, and keeps Aleph opt-in

> **Status**: Accepted (release candidate)
> **Released**: v2.0.0-rc.1 (2026-09-23); promotion to v2.0.0 after the soak
> **Deciders**: @deep-name (maintainer); cycle-124 run (PR #1266) with Flatline, cross-model dissent and six Bridgebuilder iterations
> **Predecessors**: ADR-002 (multi-model cheval substrate), ADR-003 (mechanical floor)
> **Sources**: `grimoires/loa/a2a/framework-review-2026-09-17.md` §9; cycle-124 PRD/SDD (FR-1…FR-10); `grimoires/loa/reports/breaking-surface-audit-2.0.0-rc.1.md`; maintainer directives of 2026-09-22 (Aleph, rc)

---

## Context

The framework review of 2026-09-17 found Loa's own use of Claude a generation behind the models it dispatched to: the catalog aliased `opus` to 4.8 and `fable` to 5.0, every hop was capped at 4,096 output tokens regardless of model, no hop used adaptive thinking, prompt caching or structured outputs, the verdict gates the golden path relied on were still prose-matched in places, prompts had grown past what a cheaper executor could hold, and a test run could silently write the production cost ledger. Three pressures made this a floor problem rather than a feature list:

1. **Gates are only as strong as their weakest executor** (ADR-003). Under-sized output budgets truncated dissent payloads into malformed findings (KF-004 recurred 31 times) and made structured verdicts impossible.
2. **Token economy.** The prompt surface had to shrink to the point where a Sonnet-class executor could carry the mechanical majority, which required measuring the diet rather than asserting it.
3. **Operator trust.** Every one of these changes is felt immediately by downstream mounts (defaults, removed keys, archived files), and a third-party component (Aleph) had begun turning Loa's own CI red.

## Decision

1. **Catalog and adapters at the current generation.** `opus` → `claude-opus-5`, `fable` → `claude-fable-5-1`, Sonnet 5 at reference pricing; the 4.6+ family at its real 1M / 128K envelope; typed capability flags (`thinking_adaptive`, `temperature_supported`, `structured_json`, cache rates) drive per-model emission instead of hand tables. One regen script rebuilds every generated twin; values stay `reference` until `live-floor-check.yml` records a live pass.
2. **Per-hop defaults sized to the model.** Anthropic hops default to 16K (non-streaming) / 64K (streaming) output, clamped to the catalog; `--max-tokens 0` is an input error; bounded dispatchers pass explicit budgets. Adaptive thinking is emitted where the catalog says so and never for Fable; persona.md is the single prompt-cache breakpoint on every transport.
3. **Structured outputs where a verdict is parsed.** Five wire schemas; `--json-schema` enforced on `structured_json` entries and forwarded to the CLI hop; dissent and Flatline parse enforced payloads strictly and mark DEGRADED on any rejected finding — the repair loop stays for unenforced voices and is no longer a flag.
4. **Machine-checkable gates, closed.** The golden path derives verdicts from the trailer through `verdict-derive.sh` (one-way rule, `excluded` / `excluded_confirmed` cross-check); review and audit are coverage-first (every finding cited, no quotas); ledgers are isolated in every harness and tripwired in CI.
5. **A measured prompt diet.** Byte budgets (skill ≤ 16,384 B, kernel ≤ 10,240 B, protocols ≤ 200,000 B) enforced on every PR, a 49-unit prompt audit, and an eval A/B harness that recorded recall, false positives and tokens per call before and after — the diet was kept only where the pre-registered gates held.
6. **Bounded session memory.** NOTES.md has a 100 KiB warn / 200 KiB block line on growth across the hook, the Bash fence and the writer, and recovery reads a heading-selected ≤ 68 KiB slice; the memo comparing this with a memory tool records why NOTES.md stays.
7. **Aleph is opt-in** (`aleph.enabled`, default false). Loa never verifies, installs, tests or syncs a component the maintainer did not author unless an operator says so; the opted-in behaviour is unchanged.
8. **The 2.0 line ships as a release candidate first.** `2.0.0-rc.1` is a GitHub pre-release; fixes land as `-rc.N`; promotion to `2.0.0` follows written exit criteria. The pipeline gained the formal mechanism: the topmost untagged CHANGELOG heading enters or promotes a pre-release, the candidate carries the flag, publication verifies it.

```
                 catalog (typed params) ──► adapters (per-model emission)
                        │                          │ LOA_CHEVAL_LEGACY_WIRE=1 ◄── kill switch
                        ▼                          ▼
   CHANGELOG heading ─► semver-bump ─► candidate ─► --publish --approve-sha256 ─► tag + release (prerelease?)
                        │
   SKILL.md frontmatter ► effort / budgets ─► dissent + Flatline (wire schemas) ─► LOA-VERDICT ─► golden path
                                                                                       ▲
                                              prompt byte budgets ── eval A/B ─────────┘ (measured, not asserted)
```

## Alternatives considered

- **A. Bump the aliases only, keep 4,096 everywhere.** Rejected: it leaves the truncation class (KF-004) in place and makes structured outputs unusable; the review named the budgets, not the ids, as the blocker.
- **B. Flag every new default off (`legacy` by default, opt-in to the new wire).** Rejected: a floor that is off by default is not a floor; instead one switch (`LOA_CHEVAL_LEGACY_WIRE=1`) restores the whole pre-2.0 body for comparison and rollback.
- **C. Keep the prompts and raise the model tier instead of dieting.** Rejected: token cost is the operator's constraint (ADR-003), and the A/B showed the audited prompts held recall at −24 % audit tokens per call; where a gate failed (review false positives), the diet was iterated once and the result recorded honestly as partially met.
- **D. Bend Loa's gates to keep Aleph green** (revert the `capabilities:` block on the Aleph-managed skill). Rejected by the maintainer: Loa's rules win in Loa's repo; the coupling was removed instead.
- **E. Ship `2.0.0` directly.** Rejected by the maintainer: downstream mounts need a soak window for default changes; a pre-release is the promise that feedback lands before the stable cut.
- **F. Hand-edit the candidate / tag `v2.0.0-rc.1` manually.** Rejected: the candidate contract binds tag to computed version and the publisher verifies bytes; the formal path (sprint-bug-240) is thirteen tests, not a runbook footnote.

## Trade-offs accepted

- **Higher per-call ceilings** on Anthropic hops raise the worst-case spend of an unbounded caller; bounded dispatchers pass explicit budgets and the switch exists.
- **Stricter dissent** turns some previously-passing reviews DEGRADED; that is the signal working, and it costs a re-run.
- **Removed keys never error** (no schema rejects unknown config), so an operator gets no upgrade nudge beyond the CHANGELOG.
- **Aleph users must act** (`aleph.enabled: true`) or their installed tree goes stale silently — accepted because the alternative was Loa's CI depending on third-party bytes.
- **An rc delays the stable cut** and asks downstream operators to report; accepted as the price of changing defaults.
- **More CI surface** (prompt budgets, ledger hygiene, live floor, budget sentinels) and a documented, not mechanical, release precondition for the live floor.

## Outcomes (verified at the candidate)

- Sprints 235–238 COMPLETED with review + audit APPROVED and cross-model dissent; six Bridgebuilder iterations on PR #1266 plateaued at no HIGH; CI 64 pass / 2 skipped / 0 fail on the pre-rc head.
- Prompt budgets green: 13/13 skills ≤ 16,384 B, kernel 10,222 B, protocols 199,593 B; A/B: audit recall and clean-PR false positives unchanged, review recall within tolerance after one iteration, audit tokens per call −24 % (gate target −50 %, recorded as not met).
- The unit suite no longer writes the production ledgers (two offenders fixed, KF-033).
- The pipeline cuts pre-releases formally: `semver-bump.sh --from-tag` on this branch reports `next: 2.0.0-rc.1`, `prerelease_transition.kind: enter`; publication posts and verifies `prerelease: true` (13 new tests).

## Open questions / follow-ups

- Live floor: the recorded pass of `live-floor-check.yml` on `main` / `release/*` is the release precondition and needs the `live-floor` environment with a branch policy and a rotated key (operator step).
- Vendored Aleph tree: keep inert, quarantine or remove (bead `bd-c7ma`).
- Executor-tier flips remain pre-registered A/B decisions; the confined re-measure of the Sprint 3 arms is bead `bd-vq7v`.
- `LOA_FORCE_LEGACY_ALIASES` snapshot predates 2.0; refresh or document as cycle-095-only.
- MODELINV schema growth without a `writer_version` bump; multi-changelog parity for the pre-release transition; hermetic git config in the publication test suite.
