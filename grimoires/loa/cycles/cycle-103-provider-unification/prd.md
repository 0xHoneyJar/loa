# Cycle-103 PRD — Provider Boundary Unification

**Status**: DRAFT — pending operator approval before `/plan-and-analyze` formalization
**Drafted**: 2026-05-11 (session 10, end of cycle-102 Sprint 4A)
**Author**: Claude (cycle-102 closure pass)
**Predecessor**: cycle-102 model-stability (PR #844 ready for HITL merge)

---

## How to pick this up in a fresh context window

If you're starting cold on this cycle, read these files first **in order** before doing anything else:

1. **`grimoires/loa/known-failures.md`** (Read-FIRST per `CLAUDE.md`) — the operational ledger. KF-002 + KF-008 are the load-bearing entries for this cycle.
2. **`grimoires/loa/cycles/cycle-102-model-stability/sprint.md`** — Sprint 4A section (the predecessor structural fix) and Sprint 4 main scope ACs (the carry-forwards).
3. **`grimoires/loa/a2a/sprint-4A/reviewer.md`** + **`auditor-sprint-feedback.md`** — the BB + cypherpunk reviews that surfaced the cycle-103 candidate work.
4. **`grimoires/loa/runbooks/cheval-streaming-transport.md`** — operator-visible behavior of the substrate this cycle extends.
5. **This file** — cycle-103 scope, sprint plan skeleton, AC mapping.
6. **GitHub issues**: #843 (provider unification) + #823 (opus >40K layer 2). Both have substantive context the operator already wrote.

Cycle-102 Sprint 4A's commit trail on PR #844 is the canonical "what this builds on": `ec65cdbf` → `8a60774d` (14 commits on `feature/feat/cycle-102-sprint-4A`).

---

## 0. Cycle relationship & decisions locked

Cycle-103 follows cycle-102 immediately. Cycle-102 closed 7 of 8 multi-model KFs and shipped cheval's streaming transport as the structural answer to KF-002 layer 3. Cycle-103 does **two things**:

1. **Propagate cheval's hardening to BB + Flatline + future tools** (#843). Today, BB has its own Node fetch path that re-discovers KF-001/KF-008-class bugs that cheval already solved. Each tool re-inventing the HTTP boundary is the substrate-fragmentation pattern cycle-102 deferred.
2. **Close KF-002 layer 2** (#823). claude-opus-4-7 empty-content at >40K input is the next-zoom level of the cycle-102 empty-content failure class. The fallback chain mitigates it; structural fix is overdue.

Plus a third sprint absorbing cycle-102's documented carry-forwards (BB cycle-2 findings F-002/F-003/F-007 + cypherpunk audit DISS-002/003/004 + Sprint 4 main scope AC-4.5c parallel-dispatch).

**Decisions locked at draft time**:

- Cycle-103 is a stabilization-and-unification cycle, not a feature cycle. Goal: every multi-model surface in Loa goes through the same hardened cheval substrate. After cycle-103, KF-001-class and KF-008-class failures should be impossible to re-introduce by accident in new tools.
- Cycle-103 does NOT add new model providers, new agents, or new orchestration patterns. It tightens the boundary between Loa code and provider HTTP.
- Sprint 1 (provider unification) is the load-bearing deliverable. Sprints 2-3 can re-prioritize based on Sprint 1 findings.

---

## 1. Problem & vision

### 1.1 The problem

Loa's multi-model surface today has **three parallel HTTP boundaries** to the same provider endpoints:

| Tool | HTTP path | Language | Status |
|---|---|---|---|
| `cheval` | `httpx` Python + streaming (Sprint 4A) | Python | Hardened: KF-001-resolved, KF-002-layer-3-resolved, retry-typed, audit-emitted |
| `bridgebuilder-review` | Node 20 undici `fetch` | TypeScript | Partial: KF-001 fixed via NODE_OPTIONS; KF-008 still OPEN at >290KB |
| `flatline-orchestrator.sh` + adapters | Bash → cheval (some paths) OR direct API (other paths) | bash | Mixed: some routes through cheval, some don't |

The cycle-102 substrate gains (streaming, retry-typed, audit-emitted, kill-switched) only apply to the cheval path. BB and Flatline each re-discover the same failure classes from a different angle:

- KF-001 (Happy Eyeballs) hit BB first; would have hit cheval if Python httpx had the same default
- KF-008 (Google body-size) hits BB at ~300KB; cheval Python httpx may or may not have an equivalent threshold (verified at 172KB on 2026-05-11; not tested at 300KB+)
- #823 (opus >40K empty-content) hits adversarial-review.sh through cheval AND has a parallel manifestation in BB through Node fetch

The repeated discovery pattern is the cost. Each tool's HTTP boundary is operator-visible code that needs the same hardening Sprint 4A just shipped.

### 1.2 The thesis

**Cheval is the substrate. BB and Flatline are consumers, not parallel implementations.**

Cycle-103 makes this true. After cycle-103:

- BB invokes provider APIs through cheval (Python subprocess or Python adapter) instead of Node fetch
- Flatline orchestrator's direct-API paths route through cheval uniformly
- KF-001-class fixes ship once and propagate
- KF-002 / KF-008 / future-class fixes ship once and propagate

### 1.3 Axioms

Inherits cycle-102 vision-019 axioms:

1. **Fail loud**: every silent-degradation surface gets a typed error
2. **Audit observed state, not configured state** (Sprint 4A DISS-001 closure + BB cycle-2 F-003)
3. **Substrate as answer**: structural fixes propagate to all consumers automatically

Cycle-103 adds:

4. **One HTTP boundary, one hardening codepath**: any new tool needing provider HTTP delegates to cheval rather than rolling its own
5. **Provider-side failure classification is data, not text**: parser exceptions carry typed error category (rate-limit / overloaded / malformed / policy / transient) so retry routing has full signal (BB cycle-2 F-002)

### 1.4 Why now

- Cycle-102 Sprint 4A just landed the streaming substrate; the value is highest when BB + Flatline consume it
- KF-008 (Google body-size) was discovered DURING Sprint 4A validation — exactly the substrate-fragmentation pattern this cycle addresses
- The Sprint 4A cypherpunk audit + BB cycle-2 review identified 5 carry-forward items that all belong at the cheval boundary
- #843 was filed during cycle-102 (#843 → 2026-05-11) by the same observation: BB rediscovering the bug class cheval already solved

---

## 2. Goals & success metrics

### 2.1 Cycle-exit invariants (M1-M5 — all must hold at ship)

- **M1**: BB invokes provider APIs through cheval (subprocess or in-process Python adapter); no direct Node fetch to provider endpoints from BB. Verified by `grep -rn "fetch(" .claude/skills/bridgebuilder-review/dist/` showing no provider URL strings.
- **M2**: All flatline-orchestrator code paths route provider calls through cheval; the residual direct-API paths in `flatline-*.sh` are eliminated or documented as out-of-scope.
- **M3**: KF-008 closes (either via the unified path that doesn't have the body-size issue, OR via documented operator workaround if upstream confirms it's vendor-side).
- **M4**: KF-002 layer 2 (#823 opus >40K empty-content) has a structural fix that doesn't depend on the fallback chain.
- **M5**: Sprint 4A carry-forwards close — F-002 (retry classification), F-003 (audit observed state), F-004/BF-004 (error-body redaction), F-007 (kill-switch+gate auto-revert), BF-005 (MAX_SSE_BUFFER cap).

### 2.2 Out-of-scope deliverables (cycle-103 does NOT do these)

- New provider adapters (Bedrock, Vertex AI, etc.) — separate cycle when business need exists
- New agent classes / personas — separate cycle
- Frontend / UI changes — separate cycle
- Loa-vendor split (separate constructs ecosystem) — separate cycle

### 2.3 Timeline

| Sprint | Estimated duration | Risk |
|---|---|---|
| Sprint 1 (provider unification) | 5-7 days | Medium — touches TS + Python + bash; cross-language testing |
| Sprint 2 (#823 opus layer 2 structural) | 2-3 days | Medium — depends on upstream Anthropic behavior; may end up being a documented workaround if upstream is the root |
| Sprint 3 (Sprint 4A carry-forwards) | 3-5 days | Low — items are individually small but additive |
| Total | 10-15 days |

---

## 3. Users & stakeholders

Same set as cycle-102 (see `cycle-102-model-stability/prd.md` §3). Primary stakeholder remains @janitooor; cycle-102 review/audit/HITL discipline applies.

---

## 4. Functional requirements

### 4.1 Sprint 1 — Provider boundary unification (#843)

**AC-1.1** — BB invokes cheval for provider calls. Replace `adapters/anthropic.ts`, `adapters/openai.ts`, `adapters/google.ts` direct-fetch implementations with `adapters/cheval-delegate.ts` that spawns `python3 .claude/adapters/cheval.py invoke ...` or invokes a long-lived cheval daemon over Unix socket. Decision: spawn-per-call vs daemon — Sprint 1 evaluates both; default to whichever has acceptable per-call latency (<1s overhead).

**AC-1.2** — All three TS adapter test suites under `.claude/skills/bridgebuilder-review/resources/__tests__/` pass against the new delegate. Existing test scaffolds (HTTP mock fixtures) continue to work — cheval-delegate accepts a `--mock-fixture-dir` flag for the test path.

**AC-1.3** — KF-001 NODE_OPTIONS fix becomes vestigial. Document the entry.sh patch as legacy-compatibility and mark for removal in cycle-104.

**AC-1.4** — flatline-orchestrator.sh + flatline-* scripts: every direct-API path replaced with `model-invoke` (which already routes to cheval). The mixed-mode behavior (#794 A5 root cause) becomes uniform.

**AC-1.5** — BB's review-marker logic, .reviewignore handling, comment-posting (`postComment` in `github-cli.ts`) STAY in TypeScript. Only the LLM-API boundary moves. Network calls to GitHub stay as-is.

**AC-1.6** — Verification: re-run today's BB cycle-1 + cycle-2 test on PR #844 after unification. Google's KF-008 failure either (a) closes because cheval Python httpx handles 318KB body successfully, or (b) reproduces, in which case the failure is provider-side and the cheval response is well-classified.

**AC-1.7** — Audit consolidation: BB's review pass emits the same `MODELINV/model.invoke.complete` envelope that cheval already does, via the delegate. No more parallel audit chains for BB vs cheval.

### 4.2 Sprint 2 — KF-002 layer 2 structural (#823)

**AC-2.1** — Empirically characterize the failure threshold: at what input size does claude-opus-4-7 return empty-content under what conditions (input shape, `thinking` config, `max_tokens` setting)? Replay-test at 30K / 40K / 50K / 60K / 80K input.

**AC-2.2** — If the failure is structural (model-side reasoning-budget exhaustion before visible output), apply the same kind of upstream-workaround Sprint 1F shipped for OpenAI: gate `max_input_tokens` per-model with empirically-validated values, OR force `thinking.budget_tokens` explicitly so the visible-output budget is preserved.

**AC-2.3** — If the failure is server-side (Anthropic API quirk), file upstream + document the workaround in `grimoires/loa/known-failures.md` KF-002 layer 2 attempts table. Recurrence-≥3 already triggered per the original observation.

**AC-2.4** — The adversarial-review.sh provider fallback chain (Sprint 1B/1F) continues to handle the residual failure when the structural fix can't fully eliminate it. Verify the chain still routes correctly post-Sprint-2.

### 4.3 Sprint 3 — Sprint 4A carry-forwards consolidation

**AC-3.1** — F-002 (BB cycle-2 HIGH): structured parser exception type. Parsers raise `ProviderStreamError(category=Literal["rate_limit","overloaded","malformed","policy","transient","unknown"], message, raw_payload)`. Adapter dispatch maps category → typed exception (RateLimitError, ProviderUnavailableError, InvalidInputError, retryable-transient). Restores retry classification that cycle-3 flattened.

**AC-3.2** — F-003 (BB cycle-2 MEDIUM): audit `streaming` field derived from observed transport. `CompletionResult.metadata['streaming']` populated by the adapter at completion time; `emit_model_invoke_complete` reads from there instead of env. Falls back to env-derived for legacy callers.

**AC-3.3** — F-004 / BF-004 (cypherpunk audit + BB cycle-2 MEDIUM): error-body redaction across exception construction. Helper `sanitize_provider_error_message(s: str) -> str` invoked at every adapter exception-construction site that touches upstream bytes. Tests pin AKIA / PEM / Bearer / sk-ant-* shapes scrubbed before they reach exception args.

**AC-3.4** — F-007 (BB cycle-2 MEDIUM): kill-switch + gate auto-revert. When `LOA_CHEVAL_DISABLE_STREAMING=1` is set, the per-model `max_input_tokens` gate returns the legacy-safe value (24K / 36K) automatically instead of the streaming-default value (200K / 180K). Split into `streaming_max_input_tokens` + `legacy_max_input_tokens` in the YAML, with `_lookup_max_input_tokens` selecting based on `_streaming_disabled()`.

**AC-3.5** — BF-005 (cypherpunk audit + BB cycle-2 MEDIUM): MAX_SSE_BUFFER_BYTES cap in SSE parser. `_iter_sse_events` + `_iter_sse_events_raw_data` raise `ValueError` (mapped to `ConnectionLostError` at adapter layer) when buffer exceeds `4 * 1024 * 1024` bytes without an event terminator. Also cap per-event accumulators (text_parts, arguments_parts, etc.) at reasonable limits.

**AC-3.6** — DISS-003 (cypherpunk carry-forward): `redact_payload_strings` nested-dict walk. The current redactor checks field names at the immediate parent level only. Extend to walk nested structures with a path-aware redaction policy: a nested string under any ancestor in `_REDACT_FIELDS` is redacted regardless of its immediate parent key.

**AC-3.7** — DISS-004 (cypherpunk carry-forward): `_GATE_BEARER` regex coverage gap. Extend the pattern to cover `bearer:` (without space), percent-encoded forms, and the bare token shape in JSON-escaped contexts. Add tests for each escape variant.

**AC-3.8** — A6 (from #794 partial close): parallel-dispatch concurrency. AC-4.5c from cycle-102 Sprint 4 main scope: per-provider connection-pool tuning + sequential-fallback strategy when parallelism degrades >50%. May be deferred to a separate sub-sprint depending on Sprint 1's findings about cheval-delegate spawn vs daemon architecture.

---

## 5. Technical & non-functional requirements

### 5.1 Performance

- BB + cheval-delegate spawn latency: <1s per call. Daemon mode (if pursued) <100ms.
- Sprint 2 empirical replay test budget: ~$2-3 (running opus-4-7 against test prompts at 5 input sizes).
- Sprint 3 changes are pure-Python refactors; no new performance budget.

### 5.2 Security

- AC-3.3 (error-body redaction) is the security-critical deliverable. Sanitize-at-exception-boundary is the canonical pattern (mirrors Cloudbleed-class lesson noted in BB cycle-2 finding F-006).
- AC-3.6 (nested-dict redactor) closes the cypherpunk audit DISS-003 carry-forward.
- AC-3.7 (Bearer regex) closes DISS-004.
- After Sprint 3, the full upstream-bytes-to-operator-stderr path has redaction coverage.

### 5.3 Audit & observability

- AC-3.1 (typed exception category) + AC-3.2 (audit observed state) together complete the cycle-098 audit-envelope vision for multi-model invocations.
- After cycle-103, vision-019 M1 silent-degradation query has:
  - `streaming: bool` (observed)
  - `models_failed[].error_category` (typed)
  - `operator_visible_warn: bool` (per Sprint 1A)
  - `kill_switch_active: bool` (per Sprint 1A)
- Together these support an audit-driven "find every silent failure" SQL-style query.

### 5.4 Backwards compatibility

- Cheval Python CLI contract unchanged (`model-invoke` invocations still work the same way for non-BB callers).
- BB's external GitHub-side behavior unchanged (PR comments, review markers, .reviewignore semantics).
- Operator config (`.loa.config.yaml`, `model-config.yaml`) unchanged at the field level. AC-3.4 adds optional fields; legacy configs continue to work.

### 5.5 Drift detection

- AC-1.2 test substrate ensures cheval-delegate is the only LLM-API path BB uses.
- Drift gate: `tools/check-no-direct-llm-fetch.sh` greps BB TS code for `api.anthropic.com|api.openai.com|generativelanguage.googleapis.com` outside the cheval delegate. Fails CI if found.

---

## 6. Scope & prioritization

### 6.1 In scope

| Sprint | Deliverables | Issues |
|---|---|---|
| Sprint 1 | Provider boundary unification (BB → cheval; flatline → cheval) | #843 |
| Sprint 2 | KF-002 layer 2 structural | #823 |
| Sprint 3 | Sprint 4A carry-forwards consolidated | #810 partial, BF-005, F-002/3/4/7, DISS-002/003/004, A6 |

### 6.2 Out of scope (explicit)

- New providers / models / agents
- KF-008 root-cause fix (upstream #845 owns this; cycle-103 just verifies if it closes via unification path)
- BB GitHub-side behavior changes (markers, ignore patterns, etc.)
- Vendor work on Loa framework itself

### 6.3 Phasing

Sequential: Sprint 1 → Sprint 2 → Sprint 3. Sprint 2 is parallelizable with Sprint 3 if operator wants; they touch disjoint code surfaces. Default to sequential for review-cycle simplicity.

---

## 7. Risks & dependencies

### 7.1 Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| **R1** | cheval-delegate spawn latency unacceptable (>2s/call) | Medium | High | Daemon mode (Unix socket) as fallback; benchmark in Sprint 1 first week |
| **R2** | BB consumes cheval but loses some TS-specific behavior (response shape normalization quirks) | Medium | Medium | AC-1.2 test substrate catches divergence; sprint plan budget for adapter-shape reconciliation |
| **R3** | #823 opus layer 2 is upstream-only — no Loa-side structural fix possible | Medium | Low | Sprint 2 AC-2.3 (file upstream + document) accepts this outcome; fallback chain already mitigates |
| **R4** | F-002 typed-exception refactor cascades through retry.py + cheval.py + all 3 adapter wrappers | High | Medium | Sprint 3 sequencing: F-002 first (foundational), then F-003/4/5/6/7 on top |
| **R5** | KF-008 doesn't close via unification (cheval Python also has the body-size issue at 300KB+) | Low | Medium | AC-1.6 verification surfaces this; if reproduced, file second upstream + accept as vendor-side |
| **R6** | Sprint 4A's streaming default introduced concurrency bugs that surface only in Sprint 1 cross-language testing | Low | High | Roll back to non-streaming default + investigate; Sprint 4A's `LOA_CHEVAL_DISABLE_STREAMING=1` is the operator-facing safety valve |

### 7.2 Dependencies

- **Inbound**: PR #844 (Sprint 4A) merged + KF-005 beads workaround OR formal beads recovery
- **Outbound**: cycle-104 (when planned) inherits a unified provider boundary, makes new-tool authoring much cheaper

---

## 8. Assumptions

- @janitooor will review + merge PR #844 before cycle-103 work begins. If PR #844 isn't merged, cycle-103 either rebases on the sprint-4A branch OR delays until merge.
- The cheval Python adapter is the canonical hardened path. If a future cycle decides to move to a different language for the substrate, this cycle's work would need to be reshaped — but at draft time, Python httpx + streaming + retry-typed is the stable choice.
- KF-008 (#845) upstream investigation timeline is not on cycle-103's critical path. Cycle-103 closes the operator-visible failure via unification; root-cause fix is independent.
- The operator has API budget for Sprint 2's empirical replay tests (~$3) and Sprint 1's cross-language smoke (~$2).

---

## 9. Inbound state (the cold-start checklist for cycle-103 kickoff)

**Branch state at cycle-103 start**:
- `feature/feat/cycle-102-sprint-4A` should be merged to `main` (PR #844)
- Latest cheval test count: 937 (post Sprint 4A cycle-4)
- KF-008 upstream: #845 OPEN
- Cycle-102 Sprint 4 main scope (AC-4.5c parallel-dispatch concurrency) carry-forward absorbed by cycle-103 Sprint 3 AC-3.8

**Files to confirm exist before starting**:
```bash
test -f grimoires/loa/known-failures.md
test -f grimoires/loa/cycles/cycle-102-model-stability/sprint.md
test -f grimoires/loa/a2a/sprint-4A/reviewer.md
test -f grimoires/loa/a2a/sprint-4A/auditor-sprint-feedback.md
test -f grimoires/loa/runbooks/cheval-streaming-transport.md
test -f .claude/adapters/loa_cheval/providers/base.py  # http_post_stream + _streaming_disabled
test -f .claude/skills/bridgebuilder-review/resources/entry.sh  # NODE_OPTIONS Happy Eyeballs fix
```

**Commands to run before starting**:
```bash
# Confirm cheval test surface is stable
cd .claude/adapters && python3 -m pytest tests/ -q \
  --deselect tests/test_bedrock_live.py \
  --deselect tests/test_flatline_routing.py::TestValidateBindingsCLI::test_validate_bindings_includes_new_agents
# Expected: 937 passed, 3 skipped, 4 deselected

# Confirm BB substrate works
.claude/skills/bridgebuilder-review/resources/entry.sh --help

# Confirm beads state
br --version  # Should be 0.2.4
# Note: br has known JSONL data corruption (KF-005); --no-db mode works for create
```

**Skills to invoke**:

```bash
# Cold-start kickoff:
/plan-and-analyze cycle-103
# Will read this draft + cycle-102 context + #843 + #823 + create PRD/SDD/sprint-plan

# OR if you want to skip formal planning and execute directly:
/run sprint-1  # Once Sprint 1 plan exists
```

---

## 10. References

- **Predecessor**: `grimoires/loa/cycles/cycle-102-model-stability/prd.md` (model-stability)
- **Predecessor sprints**: Sprint 4A on PR #844 (streaming substrate)
- **GitHub issues**: [#843](https://github.com/0xHoneyJar/loa/issues/843) (provider unification) + [#823](https://github.com/0xHoneyJar/loa/issues/823) (opus >40K layer 2) + [#845](https://github.com/0xHoneyJar/loa/issues/845) (KF-008 Google body-size, may close as side-effect)
- **Known failures**: KF-002 (layer 2 still open in #823) + KF-008 (upstream filed)
- **Visions touching this cycle**: vision-019 (fail-loud), vision-024 (substrate-speaks-twice / fractal recursion)
- **Audit verdict carry-forwards**: `grimoires/loa/a2a/sprint-4A/auditor-sprint-feedback.md` — DISS-002 / DISS-003 / DISS-004 / MAX_RESPONSE_BYTES
- **BB review carry-forwards**: cycle-2 BB review consensus comment on PR #844 — F-002 / F-003 / F-005 / F-006 / F-007 + KF-008 recurrence

---

## 11. Definition of Done (cycle-103)

A cycle-103 ship requires all of:

- [ ] Sprint 1 closed: AC-1.1 through AC-1.7. BB invokes cheval; flatline routes through cheval; KF-001 NODE_OPTIONS fix marked vestigial.
- [ ] Sprint 2 closed: AC-2.1 through AC-2.4. #823 has a structural fix OR documented workaround per AC-2.3 with operator sign-off.
- [ ] Sprint 3 closed: AC-3.1 through AC-3.8. All Sprint 4A carry-forwards resolved or explicitly re-deferred with rationale.
- [ ] Test count: ≥1000 cheval pytest cases pass (current 937 + Sprint 1 cross-language additions + Sprint 3 redactor / parser hardening tests).
- [ ] Adversarial review: cycle-3 BB pass on the cycle-103 PR returns ≤1 HIGH-consensus finding (improvement from cycle-102 Sprint 4A cycle-2's 2 HIGH).
- [ ] Cypherpunk audit: APPROVED with no NEW critical-class findings (carry-forwards from prior cycles acceptable if documented).
- [ ] KF status updates: KF-002 layer 2 → RESOLVED or documented-vendor-side; KF-008 → either closed (if unification path doesn't reproduce) or carry-forward with upstream #845 progress noted.
- [ ] PR review: HITL `/run-bridge` plateau ≤3 iterations on the cycle-103 PR; ship/no-ship decision logged in NOTES.md.
- [ ] Runbook updates: `grimoires/loa/runbooks/cheval-streaming-transport.md` + new `grimoires/loa/runbooks/cheval-delegate-architecture.md` (Sprint 1 deliverable).

---

## Coda

Cycle-102's structural fix made KF-002 layer 3 impossible by construction. Cycle-103's goal is to make that fix universal — every tool that talks to a model provider goes through the same hardened path. After cycle-103, "cheval" stops being a tool you can choose between vs the Node fetch path; it becomes the substrate, and BB / Flatline / future tools are consumers.

The lesson cycle-102 keeps teaching is that **substrate fragmentation is the recurring-bug-class generator**. Three HTTP paths means each tool re-discovers each failure mode. Cycle-103 collapses to one path so the lesson only has to be learned once.
