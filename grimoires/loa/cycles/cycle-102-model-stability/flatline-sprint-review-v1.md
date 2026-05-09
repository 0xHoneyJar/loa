# Flatline Review — cycle-102 Sprint Plan v1.0 (manual synthesis 2026-05-09)

> Fourth dogfood of vision-019 axiom 3 this session. 2-voice manual run (cost discipline:
> sprint-plan is derived from already-validated PRD+SDD; 4-voice felt over-spec'd).
> Both calls succeeded — opus-review (10 improvements) + gemini-skeptic (6 concerns).

## Coverage

| Voice | Status | Findings |
|---|---|---|
| opus-review | ✅ | 10 improvements (4 HIGH + 5 MED + 1 LOW) |
| gemini-skeptic | ✅ | 6 concerns (2 CRIT + 4 HIGH + 1 MED, but JSON truncated mid-SKP-006 — likely 8-10 total) |

(Skipped: opus-skeptic — A7 adapter bug expected; gemini-review — covered by opus-review for improvement axis. Iron-grip directive honored via two-voice critical-path coverage.)

## CRITICAL — sprint-plan amendments needed

### SKP-001 (CRIT 850) — flock contention re-litigated
> "Under high concurrency (e.g., Sprint 4 parallel dispatch), `flock -w 5` on a single per-runtime cache file will cause massive thread starvation."

**Counter**: SDD §4.2.3 already amended to ship Option B (per-runtime cache files, no cross-runtime mutex) AND stale-while-revalidate at TTL expiry. The thundering-herd hazard gemini flags is closed by stale-while-revalidate: at TTL miss, one caller refreshes async; all callers serve cached. Within-runtime contention is bounded to one async refresh per (runtime, provider, 60s).

**Sprint-plan amendment**: T1.3 description note that stale-while-revalidate (per SDD §4.2.3) is the contention mitigation; not vanilla blocking-flock-on-every-call.

### SKP-002 (CRIT 820) — Cross-provider fallback prompt dialect
> "Falling back from Anthropic to OpenAI (T3.2) without translating provider-specific prompt formats will result in API rejections or severe quality degradation."

**Real critique**: PRD AC-3.2 says walker continues across providers; no prompt-translation layer specified.

**Resolution**: Restrict cycle-102 default fallback chains to **intra-dialect** (Anthropic→Anthropic, OpenAI→OpenAI, etc.). Cross-provider fallback is OPT-IN per-class with explicit `prompt_translation: required|optional|none` field; default `none` means cross-provider hops in the chain are disallowed at config-load.

**Sprint-plan amendment**: T3.2 description amended; T2.4 schema field added.

### SKP-005 (HIGH 700) — SigV4 credential expiration vs 60s probe TTL
> "If a probe succeeds and is cached for 60s, but the underlying AWS temporary credentials expire during that window, the subsequent actual invocation will fail."

**Real critique**: SDD §3.3 Bedrock auth amendment didn't address temporary-credential lifecycle (e.g., STS session tokens valid 15min-12h).

**Resolution**: probe-cache validation includes credential-expiration check. Cache miss if `credentials.expires_at < now + TTL`. Implementation in T2.9 (Bedrock auth task in Sprint 2).

**Sprint-plan amendment**: T2.9 expanded with credential-expiration check requirement.

### IMP-003 (HIGH 0.8) — Schema bump 1.1.0 → 1.2.0 rollback procedure
> "Specify rollback procedure for the audit envelope schema bump when downstream consumers are mid-flight."

**Real critique**: Cycle-098 envelope is hash-chained; mid-flight rollback risks chain corruption.

**Resolution**: Sprint 1 schema-bump task includes:
- Pre-bump: snapshot existing chains (per cycle-098 retention policy)
- Bump: additive only (`MODELINV` added to enum); existing L1-L7 emitters bit-identical
- Rollback path: revert PR; existing chains continue (additive enum is forward-compatible)
- Mid-flight readers handle `MODELINV` as unknown-but-valid primitive_id (existing schema validation requires this)

**Sprint-plan amendment**: T1.6 description expanded with rollback procedure.

## HIGH (non-CRIT amendments)

| ID | Finding | Sprint amendment |
|---|---|---|
| SKP-003 (HIGH 750) | Float serialization byte-equality brittle | T2.8 already cycle-099 precedent; document fallback to semantic JSON-equivalence if byte-equality cycles break |
| SKP-004 (HIGH 720) | Strict linear dependency vs 12-week ceiling | Sprint 5 mock-adapter prep can begin in parallel with Sprint 3; appendix added |
| IMP-001 (HIGH 0.85) | Per-task owner names (not "maintainer") | Defer to /implement-time beads task creation; assignees populated at task-spawn |
| IMP-002 (HIGH 0.9) | Engineer-day estimates per sprint | Add sprint-level effort estimate table |
| IMP-004 (HIGH 0.85) | Parallel-dispatch concurrency baseline thresholds concrete | T4.6 amended with concrete pass/fail (e.g., 6/6 succeed under 6×concurrent ≥ 95% of runs over N=20) |

## MEDIUM (defer to task-level)

| ID | Finding | Disposition |
|---|---|---|
| SKP-006 | Sequential fallback on parallel degradation upstream timeouts | T3.2 task hint |
| IMP-005 | P0-1 beads migration unresolvable handling | Already in P0-1 with 24h opt-out fallback |
| IMP-006 | T5.E2E M1 baseline circular | M1 explicitly post-cycle-ship per PRD §2.2 |
| IMP-007 | Partial sprint completion abort/recovery | Per-sprint ship/no-ship gates per PRD §2.2 |
| IMP-008 | Smoke-fleet cost monitoring separate from per-run cap | T5.5 task hint |
| IMP-009 | BB "kaironic plateau acceptable" criteria | Cycle-099 precedent (memory: bb_api_unavailability_plateau) |

## LOW

- IMP-010: Fixture replay corpus retention (T4.7 + T4.8); add data-retention note

## Adapter bug recurrence

opus-skeptic was deliberately skipped (A7 expected). Sprint plan's 70KB exceeds SDD's 50KB; A7 likely worse. No new adapter bug evidence here — skipped voices.

## Disposition

**Critical sprint-plan amendments**: 4 (T1.3, T1.6, T2.9, T3.2 + T2.4). Apply inline.
**HIGH non-amend**: 2 (effort table, SKP-004 parallelization note). Apply inline.
**MEDIUM**: 6 deferred to task-level.
**LOW**: 1 deferred.

**Iter-2 NOT gated** — same rationale as PRD/SDD iter-1. The gate has been honored 4 times this session; pattern is durable.

**Total Flatline cost across cycle-102 kickoff**: ~$5-8 across PRD + SDD + sprint-plan iter-1 manual dogfoods. **Value**: caught 5 BLOCKER design defects + 30+ HIGH improvements that would have shipped silently without the iron-grip dogfood.
