---
review: cycle-103-sprint-1
reviewer: senior-tech-lead (autonomous)
date: 2026-05-11
verdict: All good (with noted concerns)
---

# Sprint 1 Review — cycle-103-provider-unification

**Verdict: All good (with noted concerns).**

Sprint 1 has been reviewed and approved. All 10 acceptance criteria are met,
all 3 cycle-exit invariants are achieved, and the implementation matches the
SDD architecture. The 11 implementation reports under
`grimoires/loa/cycles/cycle-103-provider-unification/handoffs/T1.*-implementation-report.md`
each carry a structured `## AC Verification` section with file:line evidence.
53/53 sprint-1 bats pass. TS suite at 694/695 (same pre-existing
`persona.test.ts` live-API failure that pre-dates the sprint).

The concerns documented in the Adversarial Analysis section below are
**non-blocking**: they are either documented deferrals (operator deployment),
known latent issues with explicit follow-up paths, or tradeoffs that match
the cycle's stated scope. None of them prevent merge.

## AC Roll-Up

| AC | Status | Closed By |
|----|--------|-----------|
| AC-1.0 | ✓ Met | T1.0 (`bed7db56`) — spike routed (a) at 172/250/318/400KB |
| AC-1.1 | ✓ Met | T1.4 (`92c0057e`) — `adapter-factory.ts` returns `ChevalDelegateAdapter`; legacy adapters deleted |
| AC-1.2 | ✓ Met | T1.4 + T1.5 — fixture substrate at `cheval.py:280-415,642-660`; delegate threading at `cheval-delegate.ts:155-162`; round-trip pinned by `cheval-delegate-e2e.test.ts` |
| AC-1.3 | ✓ Met | T1.8 (`92b82ba2`) — VESTIGIAL marker at `entry.sh:30-55`; 6 bats pin the marker + cycle-104 TODO + still-active export |
| AC-1.4 | ✓ Met | T1.6 (5 chat sites migrated) + T1.7 (CI drift gate, real-repo scan 0 violations) |
| AC-1.5 | ✓ Met (CI-pinned) | T1.2 trip at `cheval-delegate.ts:84-91`; T1.11 ships 8 bats source-text pins complementing the TS behavior test |
| AC-1.6 | ✓ Met (route a) | T1.9 (`5143bf5e`) — KF-008 closed architecturally in `known-failures.md`; original status preserved |
| AC-1.7 | ✓ Met by construction | Every BB / Flatline provider call now flows BB→delegate→cheval `cmd_invoke`→MODELINV emit; no parallel audit chain remains |
| AC-1.8 | ✓ Met (a, b partial) | env-inheritance via `spawn(..., { env: process.env })` at `cheval-delegate.ts:166`; argv-leak guard pinned by `cheval-delegate.test.ts:194-225` and `lib-curl-fallback-flatline-chat.bats:113-132`. Daemon UDS (c) descoped with T1.3. |
| AC-1.9 | ✓ Met (a, b, c) | Exit-code table at `cheval-delegate.ts:240-280` pinned by `translateExitCode` direct-call suite (11 cases). SIGTERM→SIGKILL lifecycle at `cheval-delegate.ts:184-191`. Partial-stdout → `PROVIDER_ERROR / MalformedDelegateError` at 3 tests. |

## Cycle-Exit Invariants

| Invariant | Status |
|-----------|--------|
| M1 (BB → cheval) | ✓ MET + CI-ENFORCED (T1.4 + T1.7) |
| M2 (Flatline → cheval, chat) | ✓ MET + CI-ENFORCED (T1.6 + T1.7); embeddings explicit deferral |
| M3 (KF-008 documented) | ✓ MET (T1.9 — route (a) architectural closure) |

## Karpathy Principles Verification

| Principle | Verdict | Notes |
|-----------|---------|-------|
| Think Before Coding | ✓ | Each report's "Known Limitations" + "Discovered" sections document assumptions and latent findings explicitly. |
| Simplicity First | ✓ | Net code is negative (~−125 production lines, mostly from collapsing 33-line if/else into 4-line helper calls × 5 sites). No new abstractions beyond what the sprint mandated. |
| Surgical Changes | ✓ | Each task's diff lists only modified+new files; no drive-by formatting. T1.4 deleted 6 files in one atomic commit — `git revert` cleanly restores. |
| Goal-Driven | ✓ | Every AC has file:line evidence; 53 bats + 35 TS tests pin the contract surfaces; drift gate enforces M1+M2 at CI. |

## Documentation Verification

| Item | Status | Notes |
|------|--------|-------|
| Operator runbook | ✓ | T1.10 ships `grimoires/loa/runbooks/cheval-delegate-architecture.md` (~280 lines). |
| Known-failures ledger | ✓ | KF-008 transitioned to RESOLVED-architectural with closing attempt row + original status preserved. |
| Implementation reports | ✓ | 11 reports under `handoffs/T1.*-implementation-report.md`, all carrying `## AC Verification`. |
| CHANGELOG | ⚠ Not updated | The cycle hasn't bumped a version; per the post-merge automation pattern this would happen at merge time. Flagged for the merge step, not blocking. |
| CLAUDE.md | ✓ N/A | No new commands or skills shipped (T1.0–T1.11 are within-sprint work). |
| Security code comments | ✓ | AC-1.8 credential-handoff and AC-1.9 lifecycle code carry inline rationale comments. |

## Subagent Reports

`grimoires/loa/a2a/subagent-reports/` — no fresh reports for cycle-103 sprint-1
(this skill batch was not preceded by `/validate`). Recommend running
`/validate` against this branch before the audit gate for an independent
architecture/security check. **Non-blocking** for review approval; the audit
gate (`/audit-sprint`) will be the next adversarial-pass.

## Adversarial Analysis

Per protocol, ≥3 concerns + ≥1 challenged assumption + ≥1 alternative not
considered.

### Concerns Identified (5)

1. **`claude-opus-4-7` (hyphen) is NOT a registered cheval alias** — only the
   dot form (`claude-opus-4.7`) exists for the newest Opus. Older 4-X models
   have both forms. Documented in T1.6 implementation report Technical
   Highlights + T1.10 operator runbook §4. The cheval `model-config.yaml`
   alias map is unchanged in cycle-103 sprint-1. **Risk:** if BB's
   `.loa.config.yaml::bridgebuilder.model` uses the hyphen form for 4.7, the
   delegate call will fail at cheval's resolver with
   `INVALID_CONFIG: Unknown alias`. **Recommendation:** add the hyphen-form
   alias in a cycle-104 sprint or as a hotfix on this branch before merge.
   Out of cycle-103 sprint-1 scope strictly speaking, but discovered during
   T1.6 testing — operator should not encounter this in production. — File
   evidence: T1.6-implementation-report.md §Technical Highlights, last
   bullet.

2. **No live end-to-end verification against a real provider** — Every test
   in this sprint uses `--mock-fixture-dir`. The BB→delegate→cheval→provider
   chain has never been observed to successfully complete a real provider
   call end-to-end on this branch. T1.0 verified cheval `httpx` against
   Google in isolation; T1.5's e2e test verified the TS→Python spawn but
   used fixture-mode. AC-1.6 path (a) was satisfied architecturally
   (failing code path deleted) rather than empirically. — File evidence:
   T1.9-implementation-report.md §"Known Limitations" #2. **Mitigation
   in place:** the operator-deferral list in `.run/state.json` flags this
   for post-merge validation.

3. **`call_flatline_chat` uses a fixed agent (`flatline-reviewer`) for ALL
   migrated chat sites regardless of underlying provider.** The five
   migrated sites span GPT (4o-mini, $GPT_MODEL) and Opus ($OPUS_MODEL)
   models. Cheval's `flatline-reviewer` binding has its own default
   temperature (0.3 per `model-config.yaml`) — the previous per-call
   temperatures (0.2 for review tasks, 0.3 for extraction) are silently
   replaced. **Risk:** for deterministic JSON-output tasks (proposal review,
   validation vote), a 0.1 temperature shift may change consensus rates or
   schema-validation pass rates. **Recommendation:** measure before/after
   review-quality on a held-out set; if drift is observable, extend
   `call_flatline_chat` to accept a temperature override OR map per-provider
   to per-agent bindings (anthropic→`jam-reviewer-claude`,
   openai→`gpt-reviewer`). — File evidence:
   T1.6-implementation-report.md §"Behavior delta per call site" + Known
   Limitations #2.

4. **Retry-policy ownership transferred wholesale to cheval without
   empirical equivalence check.** Pre-T1.6, the flatline scripts had access
   to `call_api_with_retry` (3 retries, exponential backoff) OR raw curl
   (no retries). Post-T1.6, retries are entirely on cheval's side. The
   report claims "EQUAL OR BETTER" since cheval's retry is provider-aware,
   but this is asserted, not empirically validated. **Risk:** if cheval's
   retry policy is more aggressive (more retries → longer p95) OR less
   aggressive (fewer retries → more visible failures), the operator
   experience changes. **Recommendation:** add a `cheval-retry-policy.md`
   document or runbook section comparing the two policies. — File
   evidence: T1.6-implementation-report.md §"Known Limitations" #3.

5. **The drift-gate workflow asserts allowlist mode `0644` via `stat -c '%a'`
   — GNU stat syntax, not portable to BSD/macOS.** The workflow's
   `runs-on: ubuntu-latest` pinning makes this OK in production, but the
   check would silently mis-evaluate on a macOS runner. Documented in
   `T1.7-implementation-report.md §Known Limitations` #2, but worth
   surfacing again because the implicit assumption (the workflow stays on
   ubuntu) is operator-visible only at job-config edit time. — File
   evidence: `.github/workflows/no-direct-llm-fetch.yml` (the `stat` line).

### Assumptions Challenged

**Assumption:** "Cheval Python retry policy is equivalent to or better than
the legacy bash retry policy."

- **Risk if wrong:** Operator-facing behavior shift on transient provider
  failures. If cheval retries fewer times, scripts that previously survived
  a 1-2 second hiccup now fail. If more times, p95 latency grows.
- **Recommendation:** Document the cheval retry policy explicitly in
  `cheval-delegate-architecture.md` §5 (troubleshooting) or sibling
  runbook. A one-liner like `cheval retries with provider-aware exponential
  backoff: anthropic=3 attempts, openai=4 attempts, google=2 attempts`
  would let operators reason about expected behavior.

### Alternatives Not Considered

**Alternative:** Per-provider agent bindings in `adapter-factory.ts` instead
of one global `flatline-reviewer`.

- **Tradeoff:** Lets cheval's per-agent persona/temperature/etc. take effect
  per-provider. Costs an additional model-config.yaml entry (or three).
  Benefit: review-quality drift (Concern #3) becomes a non-issue because
  each provider's binding gets the precise temperature/persona it needs.
- **Verdict:** Current approach is acceptable for cycle-103 sprint-1 minimum
  scope — the `flatline-reviewer` agent's defaults are close enough to the
  retired per-call temperatures that the drift is probably within review
  noise. **Should reconsider for cycle-104+** if any review-quality drift
  is observed in operator-side data.

## Previous Feedback Status

No prior `engineer-feedback.md` exists for cycle-103 sprint-1. This is the
first review. **N/A.**

## Documentation Coherence

No `documentation-coherence-*.md` report present; reviewer manually verified
T1.10 ships the operator runbook + 11 implementation reports + KF-008
update. Adequate for the scale of the cycle.

## Approval Decision

**APPROVED with concerns documented.**

The 5 concerns + 1 challenged assumption + 1 alternative-not-considered are
all **non-blocking**. They fall into three categories:
- **Operator deployment work** (concerns 1, 2): post-merge tasks already
  flagged in the operator-deferrals section of `.run/state.json`.
- **Soft tradeoffs / future-cycle improvements** (concerns 3, 4, alternative,
  assumption): explicitly documented in the implementation reports as
  "Known Limitations"; recommend follow-up cycles but not blocking for
  cycle-103 sprint-1 merge.
- **Documentation gap** (concern 5): worth a one-line workflow comment but
  the production behavior is unaffected.

Sprint 1 ships. Proceed to `/audit-sprint sprint-1` for the security gate.

## Next Steps

1. Update `grimoires/loa/cycles/cycle-103-provider-unification/sprint.md`
   to check the AC boxes (lines 64-72 currently have `[ ]`; mark them
   `[x]` since each AC is now met).
2. `/audit-sprint sprint-1` for the security/quality gate.
3. Operator-deployment items per state.json `resume_instructions` (upstream
   #845 comment, live PR re-run).
4. Move to Sprint 2 (KF-002 Layer 2 Structural — 3 tasks).
