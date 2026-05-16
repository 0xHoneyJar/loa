# ADR-002: Multi-Model Cheval Substrate — One HTTP Boundary, Within-Company Chains, Voice-Drop

> **Status**: Accepted
> **Released**: v1.157.0 (2026-05-12)
> **Predecessor**: ADR-001 (model-registry consolidation, cycle-099)
> **Sources**: cycle-103 (provider unification), cycle-104 (multi-model stabilization), cycle-107 (multi-model activation)

---

## Context

Pre-cycle-103, Loa had three review consumers — Bridgebuilder (BB, TypeScript), Flatline (FL, bash), and Red-team (RT, bash) — each speaking to provider APIs through separate HTTP clients:

- BB used Node `fetch` via per-provider adapter classes (`adapters/anthropic.ts`, `openai.ts`, `google.ts`).
- FL used `curl` and `lib-curl-fallback.sh::call_flatline_chat`.
- RT used `model-adapter.sh.legacy` which had its own dispatch.

Three observable consequences:

1. **Provider-side failure isolation broke at the consumer boundary.** KF-001 (Happy Eyeballs IPv6 hang) affected BB only, not FL. KF-008 (Google API SocketError at ≥300KB) affected BB only. Same provider, different code paths, different bugs.
2. **Fixes shipped per-language.** KF-001's NODE_OPTIONS workaround lived in TS-land; the redaction layer lived in bash-land. Three places to fix what should be one bug.
3. **Audit chains diverged.** BB emitted its own envelope shape; FL emitted a separate one via `model-invoke`; RT emitted a third. Cross-consumer audit was non-trivial.

Cycle-099 (v1.130.0) had already centralized the **model registry** (`model-config.yaml` + the FR-3.9 resolver). The next architectural shift was centralizing the **HTTP boundary**.

## Decision

Adopt a single Python substrate (`cheval.py`, also accessible via `model-invoke`) as the canonical HTTP boundary for all provider calls from BB + FL + RT. All three consumers delegate to cheval via:

- **BB**: `ChevalDelegateAdapter` (TypeScript) `spawn`s `python3 cheval.py` and reads stdout JSON.
- **FL**: `flatline-orchestrator.sh::call_model` invokes `model-invoke` (cheval shim) when `hounfour.flatline_routing: true`.
- **RT**: `adversarial-review.sh` → `model-adapter.sh` (compatibility shim) → `model-invoke` when flag is on.

Cheval's responsibilities:

1. Resolve the requested model alias via the FR-3.9 resolver (ADR-001).
2. Walk the within-company `fallback_chain` declared in `model-config.yaml`.
3. Honor `LOA_HEADLESS_MODE` (4 modes: prefer-api / prefer-cli / api-only / cli-only) — routes the chain through HTTP adapters OR CLI subprocesses.
4. Surface typed errors per the cycle-103 exit code taxonomy (EmptyContent → 1, RateLimited → 1, ProviderUnavailable → 1, RetriesExhausted → 1, ContextTooLarge → 7, ChainExhausted → 12, NoEligibleAdapter → 11, InteractionPending → 8).
5. Emit a signed MODELINV v1.1 envelope at `.run/model-invoke.jsonl` recording the resolved chain shape + final model + transport + observed config.

Consumer-side responsibilities:

- **BB**: pure delegation. The Node-fetch adapter registry was retired (PR #846, cycle-103 T1.4).
- **FL**: in addition to delegation, implements voice-drop on `CHAIN_EXHAUSTED` (cycle-104 T2.8) — drop the voice from consensus rather than substitute another company's model.
- **RT**: outer `fallback_chain` per-call (cycle-102 sprint-1F) composes with cheval's inner within-company chain.

## Rationale

### Why one HTTP boundary

- **Bug class isolation by transport, not by consumer.** When KF-008 surfaced, it was a Node-fetch HTTP/1.1 keep-alive interaction with the Google API gateway at large body sizes. Cheval's `httpx` did NOT reproduce (T1.0 spike). Routing every consumer through cheval means provider-side bugs ship one fix.

- **Operator-visible auditability.** One MODELINV envelope shape across BB + FL + RT means operator can query `.run/model-invoke.jsonl` for the full picture of every model call the framework made.

- **One place to apply policy** (rate limits, budget tracking, secret redaction, chain-walk semantics).

### Why within-company chains (not cross-company)

The cycle-102 T1B.4 swap was a cross-company anti-pattern: when `gpt-5.5-pro` empty-contented at ≥27K input, the operator-config substituted `claude-opus-4-7` as the dissenter. That preserved availability but lost cross-model diversity — the entire dissent signal collapsed to a single company. When that company's own bug class hit (KF-002 Anthropic empty-content at higher input sizes), the substitute had the same failure class as the original.

Within-company chains preserve diversity by design:
- OpenAI voice tries `gpt-5.5-pro → gpt-5.5 → gpt-5.3-codex → codex-headless` — all OpenAI variants. If all exhaust, OpenAI voice is gone, but the consensus still has Anthropic + Google.
- T2.8 voice-drop completes the pattern: dropped voice's slot stays empty; consensus engine knows.

The rule: **dispatch substitution within a company; never across.**

### Why voice-drop (not silent substitution)

Three reasons:

1. **Consensus integrity**. A consensus that silently substitutes another company's model conflates "we have 3-model agreement on this finding" with "we have 2-model + 1-substituted agreement". Operators reading the consensus output can't tell which.
2. **Failure-class observability**. Voice-drop emits `consensus.voice_dropped` to the trajectory log. Operators can see when a voice exhausted, what its chain was, and which models it tried.
3. **Cycle-102 anti-pattern retirement**. The T1B.4 swap was operationally necessary at the time but architecturally wrong. Voice-drop is the operationally-equivalent + architecturally-correct primitive.

### Why the activation flag

Backward compatibility. The cycle-103/104 work shipped in code; the cycle-107 work flipped the default. Operators on legacy deployments can still opt out:

```yaml
hounfour:
  flatline_routing: false
```

This restores FL + RT to the legacy `model-adapter.sh.legacy` path. BB is unaffected — it has no legacy path (cycle-103 T1.4 deleted it).

The flag stays. We don't force a hard cutover; the legacy path is operator-controllable for the foreseeable future.

## Alternatives considered

### A. Per-consumer HTTP boundary improvements (rejected)

Keep BB on Node fetch but fix KF-001 / KF-008. Keep FL on curl. Keep RT on its dispatch shim.

**Why rejected**: requires 3x the engineering work per provider-side fix. Same bugs would surface at different consumers as the codebases drift. Doesn't centralize the audit envelope.

### B. Unify on a different substrate (e.g., Rust, Go, TS) (rejected)

We picked Python (cheval) because:
- Python's `httpx` has proven KF-008-resilient (T1.0 spike + cycle-104 T3.4 4/4 trial).
- The provider SDKs (`anthropic`, `openai`, `google.genai`) have mature Python bindings with active maintenance.
- The cheval substrate already existed pre-cycle-103 (it was the model-invoke surface). Unifying onto it was incremental.
- Subprocess overhead (BB spawns python3 per call) is acceptable — the latency is dominated by the provider API round-trip (~1-30s) not the subprocess startup (~50-100ms).

### C. Cross-company substitution preserved (rejected)

Keep the cycle-102 T1B.4 swap pattern (Opus dissenter when GPT empty-contents). Don't ship voice-drop.

**Why rejected**: see "Why voice-drop" above. Cross-company substitution violates consensus integrity + masks failure-class signals.

### D. Mandatory activation (rejected for now)

Force `flatline_routing: true` with no opt-out.

**Why rejected**: some operators have legacy deployments / integrations that depend on the model-adapter.sh.legacy path. We flip the default + keep the legacy reachable. Full deprecation is a separate cycle decision with downstream coordination.

## Consequences

### Positive

- **One bug fix, all consumers**: provider-side cycle-103 T1.0 spike + cycle-104 T3.4 verified the substrate. Future bugs ship one fix per failure class.
- **Audit transparency**: `.run/model-invoke.jsonl` is the canonical trail. Every model call emits a signed MODELINV envelope.
- **Failure isolation**: voice-drop lets consensus survive partial provider outages without silent substitution.
- **Headless mode**: operators with subscription quotas can route through CLI binaries without API-key infrastructure.

### Negative

- **Subprocess overhead**: ~50-100ms per BB call to spawn `python3 cheval.py`. Acceptable for review-class workloads; would be noticeable for high-QPS use cases (not Loa's domain).
- **Two layers of chain logic in RT**: cycle-102 sprint-1F outer per-call chain + cycle-104 cheval inner within-company chain. Composes cleanly but operators reading the code see two chain mechanisms. Documented in cycle-107 sprint-1 SDD §Q2.
- **Activation flag dependency**: cycle-104 work was INERT until cycle-107 flipped the flag. Operators who upgrade to cycle-104 without flipping the flag get no benefit. Cycle-107 fixed the default; legacy operators still need to know the flag exists.

### Neutral

- **MODELINV v1.1 envelope volume**: every call emits an envelope. `.run/model-invoke.jsonl` grows monotonically; operators may want to rotate. Out of scope for this ADR; rotation can be a future operational concern.

## Verification

Live evidence captured at v1.157.0 release time (2026-05-12):

| Consumer | Verification | Status |
|----------|--------------|--------|
| BB | cycle-104 sprint-3 T3.4 — 4/4 trials at 297-539KB Google substrate clean | ✅ |
| FL | cycle-107 T1.4 — live 3-model run (Opus + GPT-5.5-pro + Gemini-3.1-pro-preview), 549s, MODELINV envelopes correct, chains populated | ✅ |
| RT | cycle-107 T1.5 — live review, 1 MODELINV envelope, cheval audit signature confirmed, legacy NOT invoked | ✅ |
| Chain-walk mechanism | cycle-104 sprint-2 T2.5+T2.6 — `test_chain_walk_audit_envelope.py` (5 tests, mocked) | ✅ |
| Voice-drop mechanism | cycle-104 sprint-2 T2.8 — `tests/integration/flatline-orchestrator-voice-drop.bats` (6 tests, stubbed cheval) | ✅ |
| Cross-runtime parity | cycle-104 sprint-2 T2.13 — bash + Python + Node byte-equal canonical JSON for `kind: cli` entries | ✅ |
| KF-008 closure | cycle-104 sprint-3 T3.4 live replay | RESOLVED-architectural-complete |
| KF-003 absorption (rate) | cycle-104 sprint-2 T2.10 — 25-trial live replay; 0 reproductions | NOT REPRODUCED at OpenAI in current deployment |

The KF-003 non-reproduction means voice-drop has NOT been exercised in production this release. The mechanism is bats-tested; live trajectory evidence would require a fault-injection harness (cycle-108 candidate if operator wants production proof).

## References

- ADR-001 (model-registry consolidation, cycle-099)
- Cycle-103 SDD: `grimoires/loa/cycles/cycle-103-provider-unification/sdd.md` (operator-local)
- Cycle-104 SDD: `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md` (operator-local)
- Migration guide: `docs/migration/v1.157-multimodel-live.md`
- KF entries: `grimoires/loa/known-failures.md` KF-001, KF-002, KF-003, KF-005, KF-008

🤖 Generated as ADR-002 for v1.157.0 milestone release, 2026-05-12.
