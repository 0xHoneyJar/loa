# Flatline Integration — cycle-093 SDD

> **Document**: `grimoires/loa/cycles/cycle-093-stabilization/sdd.md`
> **Phase**: sdd
> **Timestamp**: 2026-04-24T04:18:20Z
> **Models**: 3-model (opus + gpt-5.3-codex + gemini-2.5-pro)
> **Agreement**: 100% (HIGH=7, DISPUTED=0, LOW=0, BLOCKER=5)
> **Confidence**: full
> **Cost/Latency**: 92s total, 66+9 = 75 cents

## Summary

Second consecutive 100%-agreement Flatline run with all 5 blockers again sourced from the tertiary skeptic (Gemini 2.5 Pro). **Two CRITICAL blockers**: cache atomic-write gap (SKP-001 #2, score 930) and manual 4-file registry sync (SKP-002, score 890).

**SKP-002 is the sharpest finding of the whole cycle so far.** The SDD proposes T2.1/T2.3 update 4 files by hand (`model-config.yaml` + 2 adapter bash maps + `flatline-orchestrator.sh` allowlist). But the Loa repo already has `.claude/scripts/generated-model-maps.sh` — delivered in [PR #566](https://github.com/0xHoneyJar/loa/pull/566) and `PR #571` (`vision-011 / #548 "YAML → bash map generator"` and `"swap legacy adapter to generated maps"`). That generator was built specifically to eliminate the 4-file drift class. The SDD ignored it. Left unfixed, this cycle would have re-introduced the exact defect class it claims to eliminate.

## Blockers (5) — must resolve

### SKP-001 #2 (CRITICAL, 930) — Cache atomic-write gap
- **Concern**: Readers read `.run/model-health-cache.json` lock-free; writers use flock + in-place write. Reader can observe truncated/partial JSON → parse failures → false UNKNOWN/UNAVAILABLE.
- **Fix**: Atomic write — write to `.run/model-health-cache.json.tmp.<pid>`, `fsync`, `mv` replace. Readers retry-on-parse-failure (1 retry, 50ms backoff). Keeps 50ms config-load target.
- **Location**: SDD §1.5 Runtime flow, §3.6 Concurrency Discipline

### SKP-002 (CRITICAL, 890) — 4-file manual sync still required
- **Concern**: T2.1/T2.3 in SDD require hand-updating `model-config.yaml`, `model-adapter.sh` MODEL_TO_PROVIDER_ID, `flatline-orchestrator.sh` VALID_FLATLINE_MODELS, `red-team-model-adapter.sh` MODEL_TO_PROVIDER_ID. Identical to the drift class that produced #574.
- **Existing infrastructure**: `.claude/scripts/generated-model-maps.sh` (PR #566) + generator-consuming code path (PR #571). YAML is already the canonical source.
- **Fix options (pick one or both)**:
  1. **SSOT via generator**: T2.1/T2.3 mandate adding entries to `model-config.yaml` ONLY; run `gen-adapter-maps.sh` as a build step to regenerate bash maps. Allowlist in `flatline-orchestrator.sh` also derived (via its own generator or a shared one).
  2. **CI invariant check**: Belt-and-suspenders. New test `.claude/tests/integration/model-registry-sync.bats` diffs canonical model IDs across all 4 surfaces; fails on mismatch with actionable message.
- **Recommendation**: both. Generator as primary mechanism; invariant check as drift fuse.
- **Location**: SDD §1.4 C4, §4.3 Flow 1

### SKP-001 #1 (HIGH, 720) — Background probe proliferation
- **Concern**: Runtime flow spawns background probes via `& + trap` on every stale-cache read. Under concurrent harness invocations, dozens of probe processes race for flock, exhaust API budgets, trigger rate-limits — the failure mode the design tries to prevent.
- **Fix**: Introduce `.run/model-health-probe.<provider>.pid` sentinel/lockfile separate from cache lock. Before spawning background probe, check if one already running for that provider (`kill -0 $pid`); if alive, no-op. Per-provider concurrency cap = 1.
- **Location**: SDD §1.5 Data Flow (Runtime flow), §5.1 Invocation Matrix

### SKP-003 (HIGH, 760) — `degraded_ok: true` default masks real failures
- **Concern**: If probe infra is down or auth breaks, system serves last-known-good indefinitely — masks real model removals.
- **Fix**: Hard staleness cutoff. Config key `model_health_probe.max_stale_hours: 72` (default). When cache age > max_stale_hours AND probe failing: fail-closed (reject model use) with actionable error. Operator alert emitted via `.run/audit.jsonl` and optional webhook (if configured) when serving stale beyond 24h.
- **Location**: SDD §4.1 Config defaults, §3.2 UNKNOWN runtime behavior

### SKP-004 (HIGH, 730) — Provider API assumptions brittle
- **Concern**: Hardcoded response-shape and error-message parsing (Google NOT_FOUND regex, OpenAI pagination field paths, Anthropic error-body string-match "model"). Upstream API changes flip availability logic.
- **Fix**:
  1. Contract-test adapters against **recorded fixtures** in `.claude/tests/fixtures/provider-responses/` — one success + one not-found + one transient error per provider.
  2. Schema-tolerant parsers: bias to UNKNOWN on shape mismatch rather than AVAILABLE/UNAVAILABLE.
  3. Telemetry: log schema-mismatch events to trajectory so version bumps in upstream APIs surface quickly.
- **Location**: SDD §3.3 Provider-Specific Correctness Rules

## High Consensus (7) — auto-integrate

### IMP-008 (avg 870) — Cache concurrency (TOP PRIORITY)
Duplicates SKP-001 #2 — resolve together via atomic-write pattern.

### IMP-003 (avg 870) — Background re-probe lifecycle
Duplicates SKP-001 #1 — resolve together via PID sentinel.

### IMP-001 (avg 880) — `_invoke_claude --skill` contract undefined
T1.1's preferred path depends on `_invoke_claude --skill` working cleanly, but the invocation contract is not specified in the SDD. Define: `_invoke_claude --skill <skill-name> --context <path> --evidence-out <path>` with stdout JSON schema + exit code semantics. Required before T1.1 can be implemented without divergence.

### IMP-002 (avg 840) — Cold-start + offline + degraded mode
Undefined behavior when cache doesn't exist AND probe infra unreachable (new install, air-gapped env). Define: cold-start cache defaults to empty; offline + no cache → all models UNKNOWN; `degraded_ok: true` + fresh cache-miss UNKNOWN behaves as per §3.2.

### IMP-004 (avg 745) — Cache persistence / git-tracking policy
SDD should explicitly state: `.run/model-health-cache.json` is gitignored (already is — `.run/` is gitignored). Operator machine, CI runner, submodule consumer each have independent caches. Per-CI-runner cache is populated on first run or cold-start; cache is NOT an artifact passed between runners.

### IMP-006 (avg 755) — Unknown provider handling
If user adds a model under a provider not in `providers.{openai,google,anthropic}`, probe must fail gracefully: log warning, mark provider UNKNOWN, skip (don't error). Behavior: `probe_required: false` entries are passed through; `probe_required: true` with unknown provider → CI warning, not CI failure.

### IMP-007 (avg 750) — Probe misfire runbook
Gate-blocking behavior requires an incident-response playbook. Add `.claude/docs/runbooks/model-health-probe-incident.md` documenting: how to diagnose `override-probe-outage` label, `LOA_PROBE_BYPASS=1` emergency use, cache invalidation command, audit-log query for override history, post-incident review requirement.

## SDD Changes Required

### §1.4 C4 diagram
- Add `generated-model-maps.sh` as a named component linking YAML → adapters (SSOT flow)
- Add CI invariant check `model-registry-sync.bats` as a quality gate box

### §1.5 Data Flow
- Revise runtime probe spawn to use PID sentinel check
- Revise cache write to show atomic temp-file + mv
- Revise cache read to show retry-on-parse-failure

### §3.2 UNKNOWN runtime behavior
- Add `max_stale_hours` cutoff (default 72)
- Add fail-closed escalation after cutoff
- Add operator alert emission on stale > 24h

### §3.3 Provider-Specific Correctness Rules
- Reference contract-test fixtures in `.claude/tests/fixtures/provider-responses/`
- Add schema-tolerant fallback path (shape mismatch → UNKNOWN + telemetry)

### §3.6 Concurrency Discipline
- Atomic write semantics (write-temp + fsync + mv)
- Reader retry-on-parse-failure
- Separate PID sentinel lockfile for probe-in-progress tracking

### §4.1 Config defaults
- Add `model_health_probe.max_stale_hours: 72`
- Add `model_health_probe.alert_on_stale_hours: 24`

### §4.3 Flow 1 — Model registry update path (MAJOR)
Rewrite from hand-edit-4-files to:
1. Operator adds entry to `model-config.yaml` ONLY
2. Pre-commit hook (or build step) runs `gen-adapter-maps.sh` to regenerate bash maps
3. Operator commits both YAML + generated maps
4. CI runs `model-registry-sync.bats` as invariant check (diff canonical IDs across surfaces, fail on mismatch)
5. Then model-health-probe CI gate runs

### §5.1 Invocation Matrix
- Add PID sentinel check to runtime background-probe invocation
- Add `--invalidate [model-id]` CLI entry point

### §6.6 T1.1 wiring section
- Specify `_invoke_claude --skill` contract: CLI signature, stdin schema, stdout JSON schema, exit code semantics, evidence path convention
- Document fallback selection criteria explicitly

### §9 Risks
- Add R18: Generator regressed without CI guard (new risk introduced by SKP-002 resolution)
- Upgrade R4 (cache concurrency) to CRITICAL in priority ordering
- Add R19: API schema drift at provider (SKP-004 mitigation tracking)

### New section §11 Runbook reference
- Point to `.claude/docs/runbooks/model-health-probe-incident.md`
- Specify post-incident review requirement

## Agreement detail

| Finding | Opus | GPT-5.3-codex | Gemini-2.5-pro | Delta | Avg |
|---------|-----:|--------------:|---------------:|------:|----:|
| IMP-001 | 880  | 880           | 950            | 0     | 880 |
| IMP-002 | 820  | 860           | 920            | 40    | 840 |
| IMP-003 | 830  | 910           | 900            | 80    | 870 |
| IMP-004 | 720  | 770           | 880            | 50    | 745 |
| IMP-006 | 780  | 730           | 860            | 50    | 755 |
| IMP-007 | 750  | 750           | 780            | 0     | 750 |
| IMP-008 | 800  | 940           | 980            | 140   | 870 |

**Observation**: Same pattern as PRD Flatline — Gemini 2.5 Pro is the source of every blocker. The SDD-blocker cluster (SKP-001 #1/#2, SKP-002, SKP-003, SKP-004) shows the tertiary skeptic focusing on **concurrency and drift-enforcement** concerns that primary/secondary models approved.

SKP-002 (4-file manual sync regression) is the finding that single-handedly justifies the cost of two Flatline runs this cycle — it would have produced a cycle that shipped its own failure mode.

## Next step

SDD updated in place with all 5 blockers + 7 high-consensus findings integrated. Major additions: SSOT model registry via existing generator + CI invariant check (SKP-002), atomic-write cache pattern (SKP-001 #2 / IMP-008), PID sentinel for background probe dedup (SKP-001 #1 / IMP-003), staleness cutoff + fail-closed escalation (SKP-003), provider adapter contract-test fixtures (SKP-004), `_invoke_claude --skill` contract specification (IMP-001), cold-start/offline behavior (IMP-002), cache persistence policy clarification (IMP-004), unknown-provider fallthrough (IMP-006), incident runbook (IMP-007).

Recommendation: skip re-Flatline of SDD (integration was mechanical + 1:1 with findings) and proceed to `/sprint-plan`. Sprint-plan Flatline will validate that the implementation sequencing honors the design constraints.
