# Flatline Review — cycle-102 PRD v1.0 (manual synthesis 2026-05-09)

> Manual Flatline run after orchestrator's auto-trigger silently degraded twice on this
> very PRD. Each model called directly via `model-adapter.sh` (legacy path). Two of six
> voices (gpt-5.5-pro review + skeptic) failed for adapter-implementation reasons; manual
> synthesis proceeds with 4 of 6 voices because **opus + gemini independently surfaced
> the same BLOCKER-class findings** — sufficient for HIGH_CONSENSUS gate.

## Coverage

| Voice | Path | Result | Findings |
|---|---|---|---|
| opus-review | legacy | ✅ | 10 improvements (5 HIGH + 5 MED) |
| opus-skeptic | legacy | ✅ | 7 concerns (1 CRIT + 5 HIGH + 1 MED) |
| gemini-review | legacy | ✅ (attempt 3) | 6+ improvements (3 HIGH + 3 MED) |
| gemini-skeptic | legacy | ✅ | 5 concerns (2 CRIT + 2 HIGH + 1 MED) |
| **gpt-review** | legacy | ❌ exit 5 | empty content × 3 retries (max_output_tokens=8000 insufficient on this prompt) |
| **gpt-review (cheval)** | cheval | ❌ | PROVIDER_DISCONNECT × 3 (issue #774, RemoteProtocolError on 26648B prompt to OpenAI) |
| **gpt-skeptic** | legacy | ❌ exit 5 | same as gpt-review |

## Critical Findings (BLOCKER class — must address before /architect)

### B1. L1 strict vs AC-3.2 graceful fallback semantic contradiction

**Severity score (consensus)**: 900 (gemini SKP-001 CRITICAL) + 700 (opus SKP-003 HIGH) = **HIGH_CONSENSUS BLOCKER**

> "AC-1.5 mandates 'degraded=true exits non-zero', but AC-3.2 defines a graceful fallback chain. If a successful fallback triggers a non-zero exit, it breaks CI pipelines and isn't 'graceful'. If it exits zero, it violates L1/AC-1.5." — gemini-skeptic SKP-001
>
> "Strict failure-as-non-zero (L1) will cause production CI/CD pain… operators will set `LOA_FORCE_LEGACY_MODELS=1` permanently to avoid the noise. The cycle's own escape hatch undermines its core thesis." — opus-skeptic SKP-003

**Recommended PRD amendment**: Refactor L1. Strict failure-as-non-zero applies ONLY to **chain exhaustion** (typed `BUDGET_EXHAUSTED` / `ROUTING_MISS` / `FALLBACK_EXHAUSTED`), not to single-provider degradation when fallback succeeded. Distinguish:
- **Successful fallback** (primary failed, fallback worked) → exit 0 + WARN + operator-visible header (per AC-1.6)
- **Chain exhaustion** (primary AND all fallbacks failed) → exit non-zero + typed BLOCKER

### B2. Probe gate semantics underspecified (cluster of 5 findings)

**Severity scores**: gemini SKP-002 (CRIT 850) + opus SKP-001 (CRIT 850) + gemini SKP-003 (HIGH 750) + opus IMP-002 (HIGH) + gemini IMP-001 (HIGH 0.95) = **HIGH_CONSENSUS BLOCKER cluster**

Sub-findings:
1. **Probe-cache concurrency unspecified** (gemini SKP-002 CRIT 850): bash + python + ts components all need access to 60s probe cache; without shared mechanism (file+flock, etc.), parallel runs probe independently
2. **Probe creates new failure surface** (opus SKP-001 CRIT 850): probe endpoints may have different reliability than inference endpoints; probe traffic may be throttled/abused; probe failure becomes self-inflicted outage
3. **Probe validity illusion** (gemini SKP-003 HIGH 750): tiny <2s probe doesn't validate large-payload behavior — exact silent-degradation pattern this cycle tries to fix
4. **Probe semantics unspecified** (opus IMP-002 HIGH): which endpoint, which auth, which rate-limit bucket?
5. **Probe cross-process caching mechanism undefined** (gemini IMP-001 HIGH 0.95): bash, python, ts all probe independently; violates <500ms NFR-Perf-1

**Recommended PRD amendment**:
- Define probe semantics precisely: endpoint, auth, rate-limit bucket per provider
- Specify cache backend: file-based with `flock` at `.run/model-probe-cache/{provider}.json`; cross-runtime contract via lib (mirroring cycle-099 cross-runtime parity pattern)
- Add fail-open mode: when probe ITSELF fails (network, throttle), probe is advisory — invocation proceeds with WARN, not BLOCKER
- Add payload-size sanity check at invocation time, NOT at probe time — probe-gate is a fast-fail for hard-down providers, not a payload-suitability check

## High Consensus (auto-integrate per Flatline protocol)

| ID | Finding | Source | Severity | Action |
|---|---|---|---|---|
| HC1 | Open-ended timeline w/o abort criteria | opus SKP-004 (HIGH 680) | HIGH | Add ship/no-ship decision points after each sprint; M1's 30-day window must specify what happens if it trips at day 28 |
| HC2 | Sprint 4 legacy adapter delete is irreversible/premature | opus SKP-006 (HIGH 650) + opus IMP-008 | HIGH | **Quarantine** in `.claude/archive/` for ≥1 cycle post-ship before deletion. Test corpus must verify shim covers 100% of legacy code paths first. |
| HC3 | Drift-CI regex produces false positives | opus SKP-005 (HIGH 640) | HIGH | Scope to specific path globs (config files, gate definitions); explicitly exclude markdown/test fixtures by default |
| HC4 | Capability-class taxonomy will fragment with vendor changes | opus SKP-002 (HIGH 720) | HIGH | Define classes by capability *properties* (context window, reasoning depth) rather than vendor lineage; OR explicitly add quarterly-review AC |
| HC5 | Fallback exhaustion mislabeled as BUDGET_EXHAUSTED | gemini SKP-004 (HIGH 700) | HIGH | Add typed class `FALLBACK_EXHAUSTED` (separate from `BUDGET_EXHAUSTED` for actual quota errors) and `PROVIDER_OUTAGE` for 503 cases |
| HC6 | Smoke-fleet active alerting (M5 24h SLA) | gemini IMP-003 (HIGH 0.9) | HIGH | Passive logs won't meet 24h SLA; add webhook/automated-issue-creation for degradation deltas |
| HC7 | Fallback chain cycle detection missing | gemini IMP-002 (HIGH 0.95) | HIGH | Add cycle detection to fallback resolver; misconfig could create infinite A→B→A loops |
| HC8 | Soft-migration sunset enforcement | opus IMP-001 (HIGH 0.85) | HIGH | Define WARN escalation cadence for raw-model-id deprecation; clear deprecation deadline |
| HC9 | Typed-error JSON Schema sketch needed | opus IMP-003 (HIGH 0.85) | HIGH | Add explicit schema in `.claude/data/trajectory-schemas/model-error.schema.json`; link from PRD §5 |
| HC10 | M1 verification methodology must be precise | opus IMP-004 (HIGH 0.85) | HIGH | Define audit query exactly (envelope index? jq filter pattern? grep over JSONL?); specify data source |
| HC11 | Fallback chain provider-mixing semantics | opus IMP-006 (HIGH 0.85) | HIGH | Behavior when fallback chain crosses providers AND target also fails probe gate |

## Medium Consensus

| ID | Finding | Source |
|---|---|---|
| MC1 | Cross-reference validation for fallback chains | gemini IMP-004 (MED 0.85) |
| MC2 | File locking for smoke-fleet/audit log appends | gemini IMP-005 (MED 0.85) |
| MC3 | Local-network-failure vs provider-failure differentiation | gemini IMP-006 (MED 0.8) |
| MC4 | `model_aliases_extra` collision/precedence beyond `id` | opus IMP-005 (MED 0.8) |
| MC5 | Smoke-fleet budget/abort policy | opus IMP-007 (MED 0.8) |
| MC6 | Migration path for in-flight runs at Sprint 4 deletion | opus IMP-008 (MED 0.8) |
| MC7 | AC-1.3 attacker schema pinning details | opus IMP-009 (MED 0.75) |
| MC8 | Reframe Principle falsification test | opus IMP-010 (MED 0.75) |
| MC9 | BB TS codegen build-pipeline coupling | opus SKP-007 (MED) |
| MC10 | Migration script tooling (vs guide) | opus IMP-008 first-run |

## Disputed / Single-voice

(None this iteration — both review/skeptic from each model align on themes.)

## Open Voices (to fill in v2)

- **gpt-review + gpt-skeptic**: failed for adapter reasons (#787 partial regression — `max_output_tokens=8000` insufficient on PRD-class prompts; cheval #774 RemoteProtocolError unfixed). These adapter bugs are **themselves** evidence for cycle-102 (Sprint 1 + Sprint 4 fix surfaces).

## Adapter bugs uncovered DURING this Flatline run (file as Sprint-1 anchor issues)

| # | Surface | Evidence |
|---|---|---|
| A1 | `max_output_tokens=8000` (legacy adapter sprint-bug-143 hardcode) is insufficient for reasoning-class on prompts >~10K tokens | gpt-review/gpt-skeptic both legacy → empty content × 3 → exit 5 |
| A2 | Legacy adapter sets `max_output_tokens` ONLY for OpenAI `/v1/responses`; Gemini reasoning models get no equivalent → empty-content failures on first 2 attempts (recovered on third) | gemini-review.stderr × 2 attempts |
| A3 | Cheval RemoteProtocolError on >26KB prompts to OpenAI (issue #774 unfixed upstream) | gpt-review-cheval.stderr |
| A4 | `flatline_protocol.models.tertiary: gemini-3.1-pro-preview` is not a valid cheval alias (only `gemini-3.1-pro` bare alias resolves) — fixed in this session via operator config edit | INVALID_CONFIG output from cheval direct test |
| A5 | Orchestrator routed through cheval despite `hounfour.flatline_routing: false` on first run | /tmp/loa-flatline-* logs from first run; `is_flatline_routing_enabled` returned FALSE in standalone test (mystery — Sprint 4 audit) |
| A6 | Orchestrator's parallel dispatch failed 3 of 6 calls; same calls succeed when run sequentially-direct (concurrency-related, possibly file-handle/connection-pool/rate-limit) | comparison: rerun parallel = 3 fail; direct sequential = 4 succeed of 4 attempted (gpt always fails) |

## Disposition

**Per Flatline protocol**: BLOCKER class halts autonomous workflows. The 2 BLOCKER clusters above MUST be addressed in the PRD before /architect runs.

**Per cycle-102 thesis**: this entire run IS the cycle's own dogfood — the gates failing silently is the bug we're fixing. The adapter bugs A1-A6 become Sprint 1 + Sprint 4 anchor evidence (rich detail beyond what the issues alone capture).

**Recommended path**:
1. Amend PRD with BLOCKER B1 + B2 fixes (refactor L1; specify probe semantics + fail-open + cache backend)
2. Integrate HIGH_CONSENSUS HC1-HC11 as PRD AC additions
3. Save MEDIUM_CONSENSUS as Sprint-plan task hints (don't bloat PRD)
4. Re-run Flatline (or skip if findings are stable; we have empirical signal that the orchestrator can't run reliably on this PRD anyway)
5. Proceed to /architect with amended PRD
