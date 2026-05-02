# Product Requirements Document: AWS Bedrock Provider + Provider-Plugin Hardening

**Version:** 1.3 (live-probe ground-truth integrated)
**Date:** 2026-05-02
**Author:** PRD Architect (deep-name + Claude Opus 4.7 1M)
**Status:** Draft — two Flatline passes + Sprint 0 partial probes integrated; cycle-095 archived; SDD v1.2 + sprint v1.2 also updated with same corrections; awaiting Sprint 0 close (G-S0-1 survey + remaining probes + token-lifecycle + backup) before Sprint 1 entry

> **v1.2 → v1.3 changes** (Sprint 0 G-S0-2 partial probes against live Bedrock 2026-05-02):
> - **Model IDs corrected**: `us.anthropic.claude-opus-4-7-v1:0` → `us.anthropic.claude-opus-4-7` (no version suffix on newest); `us.anthropic.claude-sonnet-4-6-v1:0` → `us.anthropic.claude-sonnet-4-6`; Haiku 4.5 keeps `us.anthropic.claude-haiku-4-5-20251001-v1:0` (older naming convention). Source: live `/inference-profiles` listing
> - **Bare `anthropic.*` IDs do NOT work** — HTTP 400 with "on-demand throughput isn't supported"; **inference profile IDs are REQUIRED** for all Day-1 models. This validates v1.x FR-12's MVP-promotion of cross-region profiles
> - **Bedrock API Key regex broadened**: `ABSKY[A-Za-z0-9+/=]{32,}` → `ABSK[A-Za-z0-9+/=]{36,}` (sample token prefix is `ABSKR`; safe fallback to 4-char `ABSK` prefix per AWS convention; min length raised to 36 for fewer false positives)
> - **Thinking traces format on Bedrock**: `thinking.type: "adaptive"` + `output_config.effort` (NOT direct-Anthropic's `thinking.type: "enabled"` + `budget_tokens: N`, which returns HTTP 400). Adapter must translate; per-provider mapping not exposed to callers
> - **Response usage shape is camelCase**: `inputTokens, outputTokens, totalTokens, cacheReadInputTokens, cacheWriteInputTokens, serverToolUsage` (NOT direct Anthropic's snake_case `input_tokens, output_tokens`). Bedrock includes prompt-cache tracking out of the box
> - **Error taxonomy expanded**: 7 categories → 9 categories. Added `OnDemandNotSupported` (HTTP 400 when bare model ID used) and `ModelEndOfLife` (HTTP 404 with explicit retirement message). Wrong model name returns 400 ("provided model identifier is invalid"), not 404 as v1.2 assumed
> - **`global.*` inference profiles documented**: alongside `us.*`, AWS now provides `global.anthropic.*` profiles for cross-region (including non-US) availability — new option for FR-12
> - **Empty-content edge refined**: empty `text` field returns HTTP 400 (caller error, no retry); model-side empty `content[]` array on 200 OK (NFR-R4 retry case) was NOT reproduced in probe but stays in NFR-R4 as a defensible edge-case guard
> - **PRD §A8 confirmed**: URL-encoding model ID is required (Haiku ID `:0` becomes `%3A0`)
> Source: probe captures at `tests/fixtures/bedrock/probes/` and forthcoming `tests/fixtures/bedrock/contract/v1.json`. No re-Flatline (factual ground-truth corrections, not opinions; previous Flatline rounds at 100% agreement remain valid for the unchanged scope).
**Cycle (proposed):** `cycle-096-aws-bedrock` (assigned by ledger after cycle-095 archive)
**Source issue:** [#652](https://github.com/0xHoneyJar/loa/issues/652) — "[FEATURE] add amazon bedrock to loa"

> **Routing note**: This file lives at `grimoires/loa/issue-652-bedrock-prd.md` because `grimoires/loa/prd.md` is the active cycle-095 (model-currency) PRD. After `/ship` or `/archive-cycle` runs for cycle-095, move this file to `grimoires/loa/prd.md` (or re-run `/plan-and-analyze` on the archived state).

> **v1.0 → v1.1 changes**: Added Sprint 0 "Contract Verification Spike" (5 gates G-S0-1 through G-S0-5); revised NFR-R1 for compliance-aware fallback (default `bedrock_only` fail-closed); added NFR-Sec6/7/8/9/10 for key lifecycle + value-based redaction; added FR-11 (Bedrock error taxonomy), FR-12 (cross-region profiles, promoted from future to MVP), FR-13 (thinking-trace parity verification); fixed env var name to `AWS_BEARER_TOKEN_BEDROCK`; updated model IDs to region-prefix format (`us.anthropic.*`); changed `api_format` to per-capability schema; added colon-bearing model ID handling to FR-1 ACs. Source: Flatline pass #1 (Opus + GPT-5.3-codex + Gemini-2.5-pro) at `grimoires/loa/a2a/flatline/issue-652-bedrock-prd-review.json` — 80% agreement, 6 BLOCKERS + 5 HIGH-CONSENSUS + 2 DISPUTED, all addressed.

> **v1.1 → v1.2 changes**: Tightened G-S0-1 with sample-size rule (≥3 floor, ≥5 target, ≥70% Bearer threshold), 5-day timeout, and 4-way outcome decision tree (PASS / PASS-WITH-CONSTRAINTS / FAIL / INCONCLUSIVE); added deterministic `compliance_profile` defaulting rule (4-step ordered logic) with one-shot migration notice; locked initial Bedrock secret-redaction regex (`ABSK[A-Za-z0-9+/=]{36,}`); locked NFR-Sec8 cost-ledger and audit-log schemas (concrete JSON shapes); added new `[SDD-ROUTING]` section explicitly handing two architectural concerns (recurring CI smoke + centralized colon parser) to /architect with concrete SDD requirements. Source: Flatline pass #2 at `grimoires/loa/a2a/flatline/issue-652-bedrock-prd-v11-review.json` — 100% agreement, 5 BLOCKERS + 4 HIGH-CONSENSUS + 0 DISPUTED on v1.1; 3 PRD-level findings integrated here (SKP-001/003/004 + IMP-001/002/003), 3 architectural findings routed to SDD (SKP-002 + SKP-006 + IMP-005). Stopping criterion: Kaironic finding-rotation pattern at 100% agreement on increasingly fine-grained refinements.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

---

## Executive Summary

**The ask in one sentence.** Loa users on AWS Bedrock have asked Loa to support Bedrock as a first-class provider so they can use their existing Bedrock-managed credentials instead of running a parallel direct-vendor API setup.

**The architectural ask underneath.** While addressing Bedrock, the issue body asks: "look into making it easier to add other providers if it is not already easy to do so" (#652). Today the path to add a provider is non-trivial — six coordinated touch points across YAML, Python, generated bash, security allowlist, trust scopes, and health probe. Bedrock is the forcing function for codifying and documenting that path.

**The shape of the proposed solution.**

| Track | Sprint | Risk |
|---|---|---|
| **v1 — Bedrock API Keys (Bearer-token auth)** | Sprint 1 | Low: matches existing `auth: "{env:VAR}"` LazyValue pattern as-is |
| **v2 — AWS SigV4 / IAM auth** (designed in this PRD; built in follow-up cycle) | Sprint 3 (deferred or split-out) | Medium: SigV4 signing module + boto3-or-equivalent dependency |
| **Provider-plugin documentation + add-provider scaffold** | Sprint 2 | Low: derived from v1 implementation as worked example |

The issue is small in user-visible surface (one config field + one new env var) but spans the full provider plugin layer. v1 is shippable in 1–2 sprints; v2 is designed-but-deferred so we don't over-commit before a real SigV4 user appears.

> **Sources**: issue #652 body; user reply 2026-05-01 ("we have people who use bedrock who use loa and so they have asked that loa be able to use bedrock managed keys / i am not sure how bedrock works so will defer to you on how to enable this easily"); existing provider scaffolding in `.claude/defaults/model-config.yaml:8-181` and `.claude/adapters/loa_cheval/providers/base.py:158-211`.

---

## Problem Statement

### The Problem

Loa today supports three model providers natively: `openai`, `google`, `anthropic` (`.claude/defaults/model-config.yaml:8-181`). Users running on AWS Bedrock — including downstream Loa adopters with established AWS billing, IAM, and data-residency setups — cannot point Loa at their Bedrock endpoint. They must either (a) maintain a parallel set of direct-vendor API keys outside their AWS environment, or (b) not use Loa.

A secondary problem: even if a sufficiently motivated user wanted to add Bedrock (or any new provider) themselves today, the path is undocumented and crosses six files. We don't know if that's hard until we walk it; the issue's "if it is not already easy to do so" framing acknowledges the unknown.

### User Pain Points

- **Adoption blocker** (primary): Loa users on Bedrock can't use Loa with their managed credentials — direct quote from #652 reply: "we have people who use bedrock who use loa and so they have asked that loa be able to use bedrock managed keys"
- **Dual-credential management**: Bedrock users who *do* adopt Loa must keep direct-vendor API keys in addition to their Bedrock setup, increasing key-rotation, audit, and compliance surface area
- **Data plane mismatch**: Some users selected Bedrock specifically for AWS-resident inference (compliance, data residency, audit logging via CloudTrail); routing through direct vendor APIs negates that choice
- **Unclear extension path**: A user (or contributor) who wants to add a fourth provider has no guide. They'd reverse-engineer from the three existing examples, with no canonical "how to add a provider" doc

### Current State

- Three-provider system: openai, google, anthropic
- Single SSOT YAML drives a generated bash map and three Python adapter classes (`base.py:158`)
- Auth uniformly via `{env:VAR}` LazyValue tokens — `.claude/adapters/loa_cheval/providers/base.py:177-207`
- Six coordinated edit sites for any new provider:
  1. `.claude/defaults/model-config.yaml` — `providers.<name>` registry entry + models + pricing + aliases
  2. `.claude/adapters/loa_cheval/providers/<name>_adapter.py` — Python adapter subclass
  3. `.claude/scripts/generated-model-maps.sh` — auto-regenerated by `gen-adapter-maps.sh`
  4. `.claude/data/model-permissions.yaml` — trust scope entries per `provider:model`
  5. `.claude/scripts/lib-security.sh` `_SECRET_PATTERNS` — secret-redaction allowlist
  6. `.claude/scripts/model-health-probe.sh` — provider-specific health check + UNAVAILABLE/UNKNOWN gating
- No "add a provider" reference doc

### Desired State

- Four-provider system: openai, google, anthropic, **bedrock**
- Bedrock users drop in `AWS_BEARER_TOKEN_BEDROCK` and pick a model — same UX as `OPENAI_API_KEY` today
- Bedrock-routed Anthropic models available (Opus 4.7, Sonnet 4.6, Haiku 4.5) on Day 1
- Provider-plugin walkthrough at a discoverable location, with the Bedrock implementation as the worked example
- v2 path (SigV4) designed and documented; built only when a user actually surfaces the need

> **Sources**: `.claude/defaults/model-config.yaml:8-244`; `.claude/adapters/loa_cheval/providers/base.py:158-211`; `.claude/scripts/generated-model-maps.sh:12-50`; `.claude/data/model-permissions.yaml`; `.claude/scripts/lib-security.sh:40-50`; user reply 2026-05-01.

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Loa works end-to-end against AWS Bedrock with API-Key auth | A live integration test invokes `bedrock:us.anthropic.claude-opus-4-7` (or Bedrock equivalent) via `model-invoke --agent <agent> --model bedrock:...` and returns a usable completion | Live API contract test (key-gated like existing live OpenAI/Anthropic tests); manual smoke from a Bedrock-enabled AWS account |
| G-2 | Adding a fifth provider takes ≤ 1 day of work for a contributor familiar with the codebase | Walk-through of "Adding a Provider" doc; time-box test: contributor adds a stub provider following the doc end-to-end | Internal dogfood — the next provider request (e.g., Mistral La Plateforme) completes within timeline |
| G-3 | Existing users see zero behavior change | All current model aliases (`opus`, `cheap`, `reviewer`, `tiny`, `deep-thinker`, etc.) continue resolving to direct-vendor providers; no entries renamed; no env vars changed | Existing test suite (BATS unit + pytest unit + integration) passes unchanged; `model-invoke --validate-bindings` passes |
| G-4 | Bedrock-routed Anthropic models are usable as drop-in replacements for direct Anthropic models | Per-agent override in user `.loa.config.yaml` retargets `opus` alias to `bedrock:us.anthropic.claude-opus-4-7` and all Loa workflows (Flatline, Bridgebuilder, /implement, /audit) continue to function | Override-and-run-cycle smoke test on a non-trivial workflow (e.g., a Flatline review on a sample PR) |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Provider count | 3 (openai, google, anthropic) | 4 (+ bedrock) | Sprint 1 ship | G-1 |
| Edit-sites per provider addition | 6 (undocumented) | 6 (documented + scaffold) | Sprint 2 ship | G-2 |
| Bedrock-via-API-Key smoke test | Does not exist | Passes against live Bedrock account | Sprint 1 ship | G-1 |
| Backward-compat regression | 0 | 0 | Sprint 1 ship | G-3 |
| Loa workflows running on Bedrock-Anthropic | 0 | ≥ 1 verified end-to-end (Flatline review) | Sprint 1 ship | G-4 |

### Constraints

- **Backward compatibility**: Every existing alias, every existing env var, every existing model entry continues to work. No silent retargeting of `anthropic:claude-opus-4-7` to Bedrock-hosted equivalent (#652 explicitly does *not* ask for this; users who want it must opt in via `.loa.config.yaml` overrides). Constraint mirrors cycle-082 / #207 alias-stability discipline (memory: "PR #207 merged: backward compat aliases").
- **No new heavyweight dependencies in v1**: Bedrock API Keys auth uses Bearer token + `httpx`/`urllib`. No `boto3`, no `awscli`, no SigV4 library on the v1 critical path. (See FR-3 / NFR-2.)
- **Same SSOT discipline**: No hand-edited `generated-model-maps.sh`. All Bedrock entries flow from `model-config.yaml` through `gen-adapter-maps.sh`. Cycle-094 sprint-2 G-7 invariant (test in `tests/integration/model-registry-sync.bats`) must continue to pass.
- **No System Zone edits without cycle authorization**: Bedrock implementation lives in `.claude/` (System Zone, per `.claude/rules/zone-system.md`). This PRD authorizes those edits at cycle scope.

> **Sources**: G-3 from user constraint inference (no breaking change is the standing Loa convention; cycle-082 + #207 precedent); existing provider count from `.claude/defaults/model-config.yaml:9-138`; cycle-094 G-7 from `grimoires/loa/NOTES.md:38-46`.

---

## User Personas & Use Cases

### Primary Persona: "Bedrock-First AWS Engineer"

**Demographics:**
- Role: Senior engineer or platform owner at a company running on AWS
- Technical Proficiency: High — comfortable with AWS IAM, regional services, Bedrock console
- Goals: Adopt Loa for sprint planning / code review / Flatline orchestration without leaving AWS data plane

**Behaviors:**
- Has Bedrock model access already configured for at least one Anthropic Claude model
- Manages credentials through AWS — IAM, Secrets Manager, or AWS-managed Bedrock API keys
- Has CloudTrail / data-residency / billing-consolidation requirements that direct-vendor APIs don't satisfy

**Pain Points:**
- Today: Loa requires `ANTHROPIC_API_KEY` from console.anthropic.com — separate billing relationship, separate audit trail
- Doesn't want to maintain two API key sets for the same Anthropic models
- May be in a regulated environment where direct API egress is restricted but Bedrock-via-VPC-endpoint is allowed

### Secondary Persona: "Loa Maintainer Adding a Provider"

**Demographics:**
- Role: Loa contributor (core or community) responding to a future "add provider X" request
- Technical Proficiency: Familiar with Loa's adapter pattern but may not have authored the original three providers

**Goals:**
- Add a new provider with confidence, knowing the contract is documented and complete
- Know where the trust scopes / pricing / health probe / secret patterns live without reverse-engineering from `git log`

**Pain Points:**
- Today: Six coordinated edits across `.claude/defaults/`, `.claude/adapters/`, `.claude/scripts/`, `.claude/data/` — none cross-linked, easy to miss one
- No worked example showing the *full* path including `validate_model_registry()` cross-map invariant (memory: "validate_model_registry() now catches cross-PR map inconsistencies at startup")

### Use Cases

#### UC-1: Bedrock User Adopts Loa with Existing Bedrock API Key

**Actor:** Bedrock-First AWS Engineer
**Preconditions:**
- AWS account with Bedrock model access enabled for at least one Anthropic Claude model
- A Bedrock API Key generated via AWS Console → Bedrock → API keys
- Loa cloned/installed on the user's workstation

**Flow:**
1. User exports `AWS_BEARER_TOKEN_BEDROCK=<value>` in their shell (or sets in `.env`)
2. User adds to `.loa.config.yaml`: `hounfour.bedrock.region: us-east-1` (or accepts default)
3. User invokes a Loa workflow targeting Bedrock — e.g., `model-invoke --agent flatline-reviewer --model bedrock:us.anthropic.claude-opus-4-7 --input <file>`
4. `bedrock_adapter.py` resolves auth via `_get_auth_header()`, signs no SigV4, sends Bearer-token POST to `https://bedrock-runtime.us-east-1.amazonaws.com/model/<modelId>/invoke` (or Converse equivalent)
5. Response normalized into `CompletionResult`, cost metered into `grimoires/loa/a2a/cost-ledger.jsonl`

**Postconditions:**
- User has working Loa setup with no direct-vendor API keys
- Cost ledger entry shows `provider: bedrock`
- Health probe cache (`.run/model-health-cache.json`) records `bedrock:<model>` AVAILABLE state

**Acceptance Criteria:**
- [ ] User does not need a `boto3` install
- [ ] User does not need an `~/.aws/credentials` file
- [ ] `model-invoke --validate-bindings` returns clean (no missing-alias errors)
- [ ] Bedrock-resolved completion is byte-equivalent in shape to a direct-Anthropic completion (downstream parsers don't fork)

#### UC-2: User Overrides `opus` Alias to Bedrock-Hosted Variant

**Actor:** Bedrock-First AWS Engineer
**Preconditions:** UC-1 is functioning

**Flow:**
1. User edits `.loa.config.yaml`:
   ```yaml
   hounfour:
     aliases:
       opus: "bedrock:us.anthropic.claude-opus-4-7"
   ```
2. User runs `/implement sprint-N` (or `/run sprint-plan`)
3. The `implementing-tasks` agent (which uses `model: opus`) routes through Bedrock instead of direct Anthropic

**Postconditions:** All `opus`-aliased agents flow through Bedrock without code change

**Acceptance Criteria:**
- [ ] No source file edits needed
- [ ] `model-invoke --validate-bindings` passes after override
- [ ] Cost ledger reflects bedrock pricing (not direct Anthropic pricing)

#### UC-3: Maintainer Adds a Fifth Provider Following the Guide

**Actor:** Loa Maintainer (or community contributor)
**Preconditions:**
- Maintainer has read the new provider-plugin guide
- Bedrock implementation exists in tree as the worked example

**Flow:**
1. Maintainer follows the six-step checklist from the guide
2. Each step references the exact bedrock implementation location for comparison
3. Maintainer runs the validation suite: `bash .claude/scripts/gen-adapter-maps.sh --check && bats tests/integration/model-registry-sync.bats && pytest tests/unit/providers/`

**Postconditions:**
- New provider entry passes all cross-map invariants on first try (Loa's existing tests catch any miss)

**Acceptance Criteria:**
- [ ] Provider-plugin guide enumerates all six edit sites with file:line anchors
- [ ] Guide includes the validation checklist
- [ ] Guide warns about the cycle-094 G-7 invariant (cross-map drift)

> **Sources**: UC-1/2/3 derived from issue body + user reply + codebase grounding; no direct user input on per-flow steps (skipped to PRD generation).

---

## Pre-Sprint-1 Validation Gate (Sprint 0 — "Contract Verification Spike")

> **Status**: BLOCKING for Sprint 1 coding. Added in v1.1 PRD revision in response to Flatline BLOCKERS SKP-001 (×2) and SKP-002 (×2). The original v1.0 PRD treated auth modality and API contract as Sprint 1 [ASSUMPTION]s; the multi-model adversarial review correctly identified that those assumptions, if wrong, force a Sprint 1 reset. Sprint 0 retires the assumption risk **before** code is written.

### Sprint 0 deliverable: `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md`

A markdown report with five sections, each gating Sprint 1 entry on a documented PASS/FAIL result. Sprint 1 does not start until all five gates are PASS or PASS-WITH-CONSTRAINTS (no FAILs).

### G-S0-1: Auth-Modality User Confirmation (closes BLOCKER SKP-001 + v1.1 SKP-001/003 + IMP-001)

**Trigger**: A short async survey (issue comment, Discord, email — operator's call) to **all known Bedrock-using Loa users**, with explicit outreach to at least one enterprise platform owner if any are reachable.

**Sample size & threshold rule** (revised v1.2 per Flatline v1.1 SKP-001 + IMP-001):
- **Target sample**: ≥ 5 respondents drawn from all known Bedrock-using Loa users; the operator (`@janitooor`) tries reasonable outreach (issue comment, Discord ping, direct message) over a 5-day window
- **Hard floor**: ≥ 3 respondents — below this, the gate is INCONCLUSIVE and Sprint 0 cannot be marked PASS without explicit operator override (documented in Sprint 0 spike report)
- **Hard threshold for Bearer-token-as-v1**: ≥ 70% of respondents use Bearer-token API Keys exclusively. < 70% promotes SigV4 to v1 alongside Bearer (PASS-WITH-CONSTRAINTS, see below)
- **Timeout**: 5 calendar days from survey send. After 5 days, gate evaluates with whatever responses are in. If < 3 responses, operator override required.

**Survey content** — three questions, ≤ 2 minutes per respondent:
1. Do you use Bedrock API Keys (long-lived bearer tokens generated in the AWS console / IAM `CreateBedrockApiKey` flow), AWS IAM access keys + SigV4 signing, or AWS IAM roles + STS?
2. Is your Bedrock access scoped to a single AWS account, or do you route through cross-account inference profile ARNs? (Cross-account ARNs require SigV4; this question explicitly probes the boundary that Bearer auth can NOT cross.)
3. Do you have any compliance posture that prohibits cross-provider fallback (e.g., HIPAA, FedRAMP, single-data-plane requirements)? (Feeds G-S0-3 compliance defaulting decision.)

**PASS condition**: ≥ 3 respondents AND ≥ 70% Bearer-token. Cross-account ARN usage is confirmed absent or scoped out for v1.
**PASS-WITH-CONSTRAINTS**: ≥ 3 respondents AND mixed Bearer/SigV4 (between 30%–70% Bearer) — promote FR-4 SigV4 implementation INTO this cycle (currently deferred); Sprint 1 ships Bearer for early users, Sprint 2 adds SigV4. Cycle scope expands by ~1 sprint.
**FAIL → reframe**: ≥ 3 respondents AND < 30% Bearer-token (majority IAM/SigV4) — scope flips entirely: SigV4 becomes v1, FR-3 deferred to v2. Issue #652 gets a status update; PRD revisits Phase 1.
**INCONCLUSIVE**: < 3 respondents — Sprint 0 cannot mark this gate PASS. Operator override path: document the response shortfall, ship Bearer-token v1 as a "best signal we have" with an explicit roadmap commitment to revisit at the 30-day post-launch checkpoint.

### G-S0-2: Live API Contract Verification (closes BLOCKER SKP-002 ×2)

**Trigger**: A maintainer-side smoke test against a real Bedrock account (use the maintainer's account; this is documented one-time effort, not a recurring CI dependency).

**Probes** (all must succeed; capture full request/response):
1. **`ListFoundationModels` GET** with `Authorization: Bearer <token>` → confirm endpoint URL, auth contract, exact returned model IDs
2. **Converse POST** for each of the three Day-1 Anthropic models — minimal `{"messages": [...], "inferenceConfig": {"maxTokens": 16}}` body — **CONFIRMED v1.3 by live probe 2026-05-02**: response shape is camelCase: `output.message.{role, content[].text}`, `stopReason`, `metrics.latencyMs`, `usage.{inputTokens, outputTokens, totalTokens, cacheReadInputTokens, cacheWriteInputTokens, serverToolUsage}`. Bedrock's prompt-cache token tracking adds 4 fields beyond direct Anthropic. Note: bare `anthropic.*` model IDs return HTTP 400 ("on-demand throughput isn't supported"); inference profile IDs (`us.anthropic.*` or `global.anthropic.*`) are REQUIRED.
3. **Converse POST** with `toolConfig.tools[].toolSpec.inputSchema.json: <schema>` — confirm Bedrock-specific tool schema wrapping is required (publicly documented at https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html, but verify by-call)
4. **Converse POST** with thinking traces — **CONFIRMED v1.3 by live probe 2026-05-02**: Bedrock Converse requires `additionalModelRequestFields.thinking.type: "adaptive"` plus `output_config.effort` (not the direct-Anthropic `thinking.type: "enabled"` + `budget_tokens: N` form, which returns HTTP 400 "not supported for this model" on Bedrock-routed Opus 4.7). The adapter MUST translate caller-side thinking-trace requests into Bedrock's adaptive format; this is per-provider mapping, not exposed to callers
5. **Empty-content edge case**: Probe with one of the prompt patterns known to elicit empty `content[]` arrays from Anthropic-on-Bedrock (publicly reported behavior); record whether retry recovers
6. **Cross-region inference profiles**: **CONFIRMED v1.3 by live probe 2026-05-02**: `us.anthropic.*` and `global.anthropic.*` profiles are accessible via the control-plane endpoint `bedrock.{region}.amazonaws.com/inference-profiles` with Bearer auth. Both `us.*` (US-region multi-region) and `global.*` (cross-region including non-US) profiles are SYSTEM_DEFINED for the three Day-1 Anthropic models. Profile IDs deviate from the foundation-models listing — newest models drop the `-v1:0` suffix in profile IDs (`us.anthropic.claude-opus-4-7`, `us.anthropic.claude-sonnet-4-6`) while Haiku 4.5 retains it (`us.anthropic.claude-haiku-4-5-20251001-v1:0`). FR-12 schema must accommodate both forms. (Cross-account ARN format probe deferred — not relevant for v1 single-account scope.)

**Output artifact**: `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md` records each probe's URL, headers (redacted), body, response, and PASS/FAIL judgment with citation.

**PASS condition**: All probes succeed and document concrete response shapes. The exact model IDs from probe #1 replace the placeholder IDs in FR-5.
**FAIL → narrow**: If thinking traces don't traverse Converse cleanly (probe #4), scope FR-13 explicitly: ship without thinking-trace claim, document gap, defer to v2 InvokeModel-per-capability path.

### G-S0-3: Compliance Profile & Fallback Policy (closes BLOCKER SKP-005 + v1.1 SKP-004)

**Trigger**: G-S0-1 question #3 informs this gate. If any Bedrock-using respondent has a compliance posture that prohibits cross-provider egress, NFR-R1's "fallback to direct Anthropic on Bedrock outage" default behavior is unacceptable.

**Decision**: Add a new YAML schema field `providers.bedrock.compliance_profile` with values:
- `none` (enables fallback as in original NFR-R1)
- `bedrock_only` (fail-closed; Bedrock outage produces a clear error rather than silent direct-Anthropic routing)
- `prefer_bedrock` (try Bedrock first; fall back to direct Anthropic with explicit warning logged to cost ledger and stderr)

**Deterministic defaulting rule** (revised v1.2 per Flatline v1.1 SKP-004):

The defaulting logic must be deterministic and predictable. The loader applies this exact rule, in this order, on every config load:

1. **If user `.loa.config.yaml` explicitly sets `hounfour.bedrock.compliance_profile: <value>`** → use that value, no further inference.
2. **Else if `AWS_BEARER_TOKEN_BEDROCK` env var is set AND no `ANTHROPIC_API_KEY` env var is set** → default `bedrock_only` (user has Bedrock-only auth posture; fail-closed protects compliance).
3. **Else if `AWS_BEARER_TOKEN_BEDROCK` env var is set AND `ANTHROPIC_API_KEY` is also set** → default `prefer_bedrock` (user has dual credentials; warned-fallback is the safer middle path — never silent).
4. **Else if `AWS_BEARER_TOKEN_BEDROCK` is unset** → field is irrelevant (Bedrock provider not in use); no default emitted.

**Migration path** (for users upgrading from a Loa version that predated `compliance_profile`): on first load that detects `AWS_BEARER_TOKEN_BEDROCK`, emit a one-shot stderr notice naming the auto-defaulted profile and the `.loa.config.yaml` override path. No silent migration.

**PASS condition**: Schema field added, defaulting rule documented in code AND in FR-9 plugin guide, three behaviors tested (mocked outage → fail-closed for bedrock_only; mocked outage → warned-fallback for prefer_bedrock; mocked outage → silent fallback for none). **Migration test**: simulate fresh user with only `AWS_BEARER_TOKEN_BEDROCK` set → loader resolves `compliance_profile: bedrock_only` AND emits the migration notice. Test for `none → bedrock_only → prefer_bedrock` defaulting transitions across all 4 rule paths.

### G-S0-4: Bedrock-Specific Error Taxonomy Stub (closes HIGH-CONSENSUS IMP-003)

**Trigger**: Sprint 0 must enumerate Bedrock error categories so Sprint 1's retry/circuit-breaker logic isn't generic-only.

**Categories to enumerate** (publicly documented; verify exact response shapes via probe #2):
- `ThrottlingException` (429) — retry with exponential backoff + jitter
- `ServiceUnavailableException` (5xx) — retry with backoff
- `ModelTimeoutException` — surface timeout to caller, don't retry blindly
- `ValidationException` (400) — caller error, do not retry
- `AccessDeniedException` (403) — auth issue, do not retry, surface clearly
- `ResourceNotFoundException` (404) — model/profile mismatch, do not retry
- `Daily quota exceeded` (response body pattern, not always HTTP-coded) — circuit-break for the day, fail-closed

**PASS condition**: Each category has a documented Loa retry decision (retry / no-retry / circuit-break) and is mapped into `bedrock_adapter.py` retry classifier in Sprint 1.

### G-S0-5: Cross-Region Inference Profiles (closes HIGH-CONSENSUS IMP-004)

**Trigger**: Newer Anthropic models on Bedrock are increasingly available only via cross-region inference profiles (publicly documented Bedrock limitation). The original v1.0 PRD deferred this to "future iterations"; Flatline correctly flagged this as a Day-1 availability blocker.

**Decision**: Day-1 model IDs use the region-prefixed format (e.g., `us.anthropic.claude-opus-4-7` rather than `anthropic.claude-opus-4-7-v1:0`). Adapter resolves the user's `region_default` against the prefix and surfaces a clear error when the user's region doesn't match the inference profile's available regions.

**PASS condition**: Probe #6 from G-S0-2 confirms the region-prefix format works with Bearer auth for all three Day-1 models. FR-5 model IDs are updated from probe #1's actual response.

### Sprint 0 timeline

- T+0 to T+2 days: G-S0-1 user survey runs in parallel with G-S0-2 probe authoring
- T+3 days: Survey results analyzed; G-S0-3 compliance decision locked
- T+4 days: G-S0-4 + G-S0-5 written from probe results
- T+5 days: Sprint 0 spike report ships; Sprint 1 entry gate evaluated

If any FAIL: revisit PRD (especially Phase 1) before Sprint 1 entry.

---

## Functional Requirements

> **EARS notation** is used for security-critical and trigger-based requirements per `resources/templates/ears-requirements.md`. Standard descriptive form for the rest.

### FR-1: Bedrock Provider Registry Entry

**Priority:** Must Have (Sprint 1)

**Description:**
Add `providers.bedrock` to `.claude/defaults/model-config.yaml` mirroring the structure of `providers.openai` / `providers.google` / `providers.anthropic` (cited at `model-config.yaml:9-138`).

Required structure:
```yaml
providers:
  bedrock:
    type: bedrock                              # New adapter type discriminator
    endpoint: "https://bedrock-runtime.{region}.amazonaws.com"
    region_default: us-east-1                  # Overridable per-user via .loa.config.yaml
    auth: "{env:AWS_BEARER_TOKEN_BEDROCK}"          # v1: Bearer-token API key
    auth_modes:                                # v2 schema seed (designed; not enforced v1)
      - api_key                                # implemented in v1
      - sigv4                                  # designed only; loader rejects with clear error in v1
    compliance_profile: bedrock_only           # NEW v1.1 (BLOCKER SKP-005). Default fail-closed.
                                               # Set to 'prefer_bedrock' or 'none' to opt into fallback.
    models:
      "us.anthropic.claude-opus-4-7":     # Region-prefixed Bedrock model ID — confirmed via Sprint 0 G-S0-2 probe #1
        capabilities: [chat, tools, function_calling, thinking_traces]
        context_window: 200000
        token_param: max_tokens
        # api_format is PER-CAPABILITY (revised v1.1 per BLOCKER SKP-002 second instance).
        # Different capabilities can route to Converse or InvokeModel as Sprint 0 G-S0-2
        # probes determine. Default 'converse' per-capability; override per-capability if probe shows gap.
        api_format:
          chat: converse                       # Bedrock Converse API for chat
          tools: converse                      # Bedrock Converse with toolConfig.tools[].toolSpec.inputSchema.json wrapping
          thinking_traces: converse            # Verified via Sprint 0 G-S0-2 probe #4; if probe FAILS, override to 'invoke'
        params:
          temperature_supported: false         # Mirrors direct Anthropic Opus 4 (#641 gate); verify in Sprint 0 G-S0-2
        pricing:
          input_per_mtok: <Bedrock-rate>       # Live-fetched at Sprint 1 start (Sprint 0 G-S0-2 probe #2 latency observation only; pricing requires AWS pricing page)
          output_per_mtok: <Bedrock-rate>
      # Sonnet 4.6 + Haiku 4.5 entries follow same pattern with the same region-prefix and per-capability api_format
```

**Acceptance Criteria:**
- [ ] `bash .claude/scripts/gen-adapter-maps.sh --check` passes (no drift)
- [ ] `bash .claude/scripts/gen-adapter-maps.sh` regenerates `generated-model-maps.sh` with bedrock entries in all four arrays (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT`)
- [ ] `bats tests/integration/model-registry-sync.bats` passes (cycle-094 G-7 invariant)
- [ ] `bats tests/integration/model-config-validation.bats` (new) confirms bedrock entry shape
- [ ] No existing provider entries modified
- [ ] **Colon-bearing model IDs handled correctly** (closes DISPUTED IMP-007): The model ID `us.anthropic.claude-opus-4-7` contains a colon, which is also the `provider:model-id` separator in Loa's discrimination convention. `gen-adapter-maps.sh` and the loader MUST split on the FIRST colon only when resolving `bedrock:us.anthropic.claude-opus-4-7`. Test fixture (new): `tests/integration/colon-bearing-model-ids.bats` asserts both bash and Python paths handle this correctly, covering: (a) provider parsing, (b) generated-map key shape, (c) `validate_model_registry()` cross-map invariant, (d) `MODEL_TO_ALIAS` resolution in `model-adapter.sh`.

**Dependencies:**
- `gen-adapter-maps.sh` may need a small extension if `region_default` / `auth_modes` / `compliance_profile` are net-new YAML fields the generator hasn't seen (verify in /architect)
- Colon-handling: confirm via Sprint 0 G-S0-2 probe that real Bedrock model IDs from `ListFoundationModels` have the expected `<region>.<vendor>.<family>-vN:M` shape

### FR-2: Bedrock Python Adapter

**Priority:** Must Have (Sprint 1)

**Description:**
New file `.claude/adapters/loa_cheval/providers/bedrock_adapter.py` subclassing `ProviderAdapter` from `.claude/adapters/loa_cheval/providers/base.py:158-211`.

Required methods:
- `complete(self, request: CompletionRequest) -> CompletionResult` — dispatch on per-capability `api_format` (chat → Converse; tools → Converse with `toolConfig` wrapping; thinking_traces → Converse or InvokeModel per FR-1 entry); normalize response into `CompletionResult` shape
- `validate_config(self) -> List[str]` — verify `auth` resolves, region is valid string, model ID matches region-prefixed Bedrock convention (`<region>.<vendor>.<family>-<datestamp>-vN:M`)
- `health_check(self) -> bool` — quick reachability probe (`GET /foundation-models` on the control-plane endpoint with Bearer auth; no token usage)
- `_classify_error(self, response) -> RetryDecision` — Bedrock-specific error taxonomy (FR-11) — examines status code + body pattern; returns `retry` / `no_retry` / `circuit_break_daily`

Implementation guidance:
- **Endpoint URL pattern** (publicly documented at https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html): `https://bedrock-runtime.{region}.amazonaws.com/model/{url_quoted_model_id}/converse`. **The model ID MUST be URL-encoded** because it contains colons and dots. Use `urllib.parse.quote(model_id, safe='')`.
- **Bedrock Converse API** for v1 (provider-agnostic body schema; works for Anthropic + future Mistral/Cohere/Meta without per-vendor branching). Reserve `InvokeModel` (per-vendor body) for capabilities where Sprint 0 G-S0-2 probe shows Converse gaps.
- **Tool schema wrapping** (Bedrock-specific gotcha, publicly documented): `toolConfig.tools[].toolSpec.inputSchema` requires a `{ json: <schema> }` wrapper around the JSON Schema, distinct from direct Anthropic API which takes the schema directly. Failing to wrap silently breaks tool calling.
- **Request body shape**: `{messages: [{role, content: [{text}|{image}|{toolUse}|{toolResult}]}], inferenceConfig: {maxTokens, temperature}, system: [{text}]}` — mirror Sprint 0 G-S0-2 probe captures.
- **Response shape**: `{output: {message: {content: [{text}]}}, usage: {inputTokens, outputTokens}}` — distinct from direct Anthropic's `{content: [{type, text}], usage: {input_tokens, output_tokens}}` (note camelCase vs snake_case).
- **Reuse `http_post()` from `base.py:49-99`** — no new HTTP client; httpx with urllib fallback.
- **Mirror `anthropic_adapter.py` patterns** for thinking traces / token usage normalization where Converse exposes equivalent fields; otherwise document gap explicitly per FR-13.
- **Endpoint resolution**: `endpoint.replace("{region}", config.region or region_default)` — region is resolved per request from (a) `request.extras.region` if set, (b) `AWS_BEDROCK_REGION` env var, (c) provider `region_default`.
- **Vision support**: Set timeout to 120s for vision-capable requests (Bedrock-Anthropic vision can take 30-60s — publicly reported empirical observation). The base `read_timeout` of 120s in `model-config.yaml:380` already covers this.
- **Empty-response handling** (NFR-R4): Single retry with same prompt if `output.message.content[]` is empty on 200 OK; surface `EmptyResponseError` if second attempt also empty.

**Acceptance Criteria:**
- [ ] Class instantiable from a `ProviderConfig` populated by the loader
- [ ] `complete()` returns `CompletionResult` with `usage.input_tokens` and `usage.output_tokens` populated
- [ ] `validate_config()` returns empty list on a well-formed config
- [ ] `health_check()` returns `True` on a reachable Bedrock endpoint with a valid API key
- [ ] Unit tests with mocked `http_post` cover: (a) successful Converse response, (b) 4xx with structured error, (c) 5xx, (d) timeout
- [ ] Live integration test (key-gated, runs only when `AWS_BEARER_TOKEN_BEDROCK` and `AWS_BEDROCK_REGION` are set in CI secrets)

**Dependencies:** FR-1 (config entry); base.py contracts

### FR-3: API-Key Auth (v1 Default) — Bearer Token via `AWS_BEARER_TOKEN_BEDROCK`

> **Sprint 0 dependency**: G-S0-1 (auth-modality user confirmation) MUST PASS before this FR enters Sprint 1 implementation. If G-S0-1 fails, FR-3 and FR-4 swap priority — SigV4 becomes v1.

**Priority:** Must Have (Sprint 1)

**EARS form:**

> **When** the `bedrock` provider receives a `CompletionRequest`, **the system shall** read the API key from the resolved `auth` LazyValue (default: `AWS_BEARER_TOKEN_BEDROCK` env var), set HTTP header `Authorization: Bearer <key>`, and proceed without any AWS SigV4 signing.

> **If** `AWS_BEARER_TOKEN_BEDROCK` is unset or empty, **the system shall** raise `ConfigError` with a message explicitly naming the missing env var and pointing to the Bedrock console URL for key generation. (Mirrors `base.py:_get_auth_header()` empty-check at line 203.)

> **The system shall NOT** read AWS credentials from `~/.aws/credentials`, instance metadata, or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars in v1. (Reserves the SigV4 path for v2 without ambiguity about which auth modality is active.)

**Acceptance Criteria:**
- [ ] `validate_config()` returns a clear error string when `AWS_BEARER_TOKEN_BEDROCK` is unset
- [ ] No `boto3` import anywhere in `bedrock_adapter.py` (assert via test scanning imports)
- [ ] No `botocore` import; no `aws_signing.py`
- [ ] Bearer-token request format verified by mocked `http_post` capturing the exact `Authorization` header value
- [ ] `lib-security.sh _SECRET_PATTERNS` extended with a Bedrock API Key pattern (verify exact format from AWS docs at sprint time; existing `AKIA[0-9A-Z]{16}` regex at `lib-security.sh:48` covers IAM access key IDs but not Bedrock API Keys, which appear to follow a different format)

**Dependencies:** FR-2; lib-security.sh extension

### FR-4: SigV4 Auth — Designed, Not Built (v2)

**Priority:** Should Have (deferred to follow-up cycle; design lands in this PRD)

**Description:**
The PRD locks the v2 design space so the v1 implementation doesn't paint us into a corner. v2 is **not implemented in this cycle** — but the v1 architecture must accommodate v2's eventual addition without retrofit.

v2 contract (locked in this PRD; built later):
- New auth strategy class `BedrockSigV4Auth` plugged in via `auth_modes: [sigv4]` in user `.loa.config.yaml`
- Reads credentials from the standard AWS chain: env vars → `~/.aws/credentials` profile → IAM instance/task role
- Wraps each request with SigV4 signing (likely via `boto3.session.Session().get_credentials()` + `botocore.auth.SigV4Auth`)
- Optional dependency: `boto3 >= 1.34` declared in a new `requirements-bedrock-sigv4.txt` (kept off the default install path)
- v1 loader rejects `auth_modes: sigv4` with a clear "not yet supported in this version of Loa, see issue #XXX for status" error rather than silently failing

**Acceptance Criteria (this cycle):**
- [ ] `auth_modes` field present in `model-config.yaml` schema (FR-1)
- [ ] Loader recognizes `sigv4` value but rejects it with the documented error
- [ ] Architecture doc (SDD output of `/architect`) reserves the strategy-class slot
- [ ] No SigV4 code, no boto3 import, no IAM credential reading in v1 sources

**Acceptance Criteria (deferred to follow-up cycle):**
- [ ] Implementation of `BedrockSigV4Auth`
- [ ] Integration with AWS credential chain
- [ ] Documentation update for v2 auth path

**Dependencies:** FR-1 schema; future follow-up cycle

> **User decision context**: User selected "Both, API Keys first then SigV4" in Phase 1 routing (2026-05-01). v2 is designed-not-built so we can ship v1 in 1–2 sprints without committing to SigV4 implementation timeline.

### FR-5: Initial Bedrock Model Coverage (Day 1)

**Priority:** Must Have (Sprint 1)

**Description:**
Day 1 model coverage spans the Anthropic family hosted on Bedrock — this is the highest-overlap with Loa's current default agent assignments and most likely to satisfy the user-driven request that motivated this cycle.

| Model alias on Bedrock | Bedrock model ID (verify exact ID at sprint time) | Mirrors direct provider |
|---|---|---|
| `bedrock:us.anthropic.claude-opus-4-7` | TBD-confirm-via-Bedrock-ListFoundationModels | `anthropic:claude-opus-4-7` |
| `bedrock:us.anthropic.claude-sonnet-4-6` | TBD-confirm-via-Bedrock-ListFoundationModels | `anthropic:claude-sonnet-4-6` |
| `bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0` | TBD-confirm-via-Bedrock-ListFoundationModels | `anthropic:claude-haiku-4-5-20251001` |

Each entry in `model-config.yaml` includes:
- `capabilities` (mirrors direct Anthropic entry)
- `context_window` (200,000 — same as direct Anthropic)
- `token_param: max_tokens`
- `api_format: converse` (Sprint 1 default)
- `params.temperature_supported: false` for Opus 4.7 (Anthropic-side gate at #641 holds whether routed direct or via Bedrock — verified at sprint time)
- `pricing.input_per_mtok` and `pricing.output_per_mtok` — **live-fetched once at Sprint 1 execution** (Bedrock pricing differs from direct Anthropic; values frozen in YAML per cycle-095 SDD §5.7 precedent)

**Acceptance Criteria:**
- [ ] All three Bedrock-Anthropic models invocable end-to-end (UC-1 succeeds for each)
- [ ] Pricing values live-fetched and committed in PR with citation comment (e.g., `# Bedrock pricing per https://aws.amazon.com/bedrock/pricing/ as of YYYY-MM-DD`)
- [ ] `model-permissions.yaml` entries added for each `bedrock:anthropic.*` model — trust scopes mirror `anthropic:claude-opus-4-7` entry (`model-permissions.yaml:147-173`)

**Out-of-scope for this cycle (deferred):**
- Non-Anthropic Bedrock-hosted models: Mistral, Cohere Command, Meta Llama, AI21, Amazon Titan, Stability — separate cycle once we have a real consumer
- Bedrock-only provider features: Bedrock Agents, Knowledge Bases, Guardrails

**Dependencies:** FR-1, FR-2, FR-3

### FR-6: Region Configuration

**Priority:** Must Have (Sprint 1)

**Description:**
Bedrock is regional. Default region in `model-config.yaml` (`us-east-1`); override via:
1. `.loa.config.yaml` — `hounfour.bedrock.region: <region>` (per-user override)
2. `AWS_BEDROCK_REGION` env var (per-shell override)
3. Per-request override via `request.extras.region` (per-call, advanced; documented but not promoted)

Resolution priority: (3) > (2) > (1) > YAML default.

**Acceptance Criteria:**
- [ ] Region resolution chain implemented in `bedrock_adapter.py`
- [ ] Test fixture covers each precedence layer
- [ ] Invalid region (string format check; not network probe) raises `ConfigError` at config-load time

**Dependencies:** FR-1, FR-2

### FR-7: Same-Model Dual-Provider Naming Discipline

**Priority:** Must Have (Sprint 1)

**EARS form:**

> **When** a user references model name `claude-opus-4-7` (no provider prefix), **the system shall** resolve to `anthropic:claude-opus-4-7` (direct vendor) via the existing aliases table — preserving every existing user's behavior.

> **When** a user references `bedrock:us.anthropic.claude-opus-4-7` (explicit Bedrock prefix), **the system shall** route through the Bedrock adapter regardless of any `anthropic` alias.

> **The system shall NOT** add an alias entry that maps any unprefixed name (e.g., `opus`, `claude-opus-4-7`) to a `bedrock:` provider in the default `model-config.yaml`. Users who want Bedrock-routing for an alias must opt in explicitly via `.loa.config.yaml` overrides (UC-2).

**Acceptance Criteria:**
- [ ] `model-invoke --validate-bindings` produces identical output before and after the cycle
- [ ] Existing aliases table (`model-config.yaml:182-211`) untouched
- [ ] Test asserts no Bedrock entry present in default `aliases:` block (regression guard)
- [ ] Documentation explicitly calls out the override pattern as the supported way to retarget

**Rationale:** Cycle-082 / #207 established backward-compat alias discipline. Silently retargeting `opus` to Bedrock would break every existing user who has a direct-Anthropic key but no Bedrock account. The override path covers users who explicitly want Bedrock-routing.

**Dependencies:** FR-1; alignment review with cycle-082 alias-stability discipline (memory: "PR #207 merged: backward compat aliases")

### FR-8: Health Probe Extension

**Priority:** Should Have (Sprint 1, can slip to Sprint 2)

**Description:**
Extend `.claude/scripts/model-health-probe.sh` to recognize `bedrock` provider:
- Probe: `GET https://bedrock.{region}.amazonaws.com/foundation-models` with `Authorization: Bearer <AWS_BEARER_TOKEN_BEDROCK>` (control-plane endpoint, no token cost)
- Cache state: AVAILABLE / UNAVAILABLE / UNKNOWN (same vocabulary as existing entries)
- Pre-flight cache consult in `model-adapter.sh` (`_probe_cache_check()`, `model-adapter.sh:207-268`) auto-extends since it's keyed on `provider:model-id` regardless of provider

**Acceptance Criteria:**
- [ ] Probe handles bedrock provider
- [ ] BATS test: probe transitions a bedrock model from UNKNOWN to AVAILABLE on a successful probe
- [ ] BATS test: probe records UNAVAILABLE when API returns 4xx
- [ ] LOA_PROBE_BYPASS audit-log path covers bedrock (no provider-specific code paths in audit)

**Dependencies:** FR-1, FR-2; verify control-plane endpoint URL pattern at sprint time (the foundation-models endpoint may differ from the runtime endpoint)

### FR-9: Provider-Plugin Documentation + Worked Example

**Priority:** Must Have (Sprint 2)

**Description:**
New documentation deliverable: a "How to Add a Provider" guide that walks through the six edit sites enumerated in [Current State](#current-state), with the Bedrock implementation as the citable worked example.

Location: `grimoires/loa/proposals/adding-a-provider-guide.md` (State Zone, append-only-friendly path) **OR** `.claude/loa/reference/adding-a-provider.md` (System Zone — would require explicit cycle-level authorization in this PRD).

**Recommendation:** Land in `grimoires/loa/proposals/adding-a-provider-guide.md` first (no System Zone touch needed); promote to `.claude/loa/reference/` in a follow-up cycle once content stabilizes.

Required content:
- Six-step checklist with file:line anchors and Bedrock-implementation references
- Validation commands (`gen-adapter-maps.sh --check`, `bats tests/integration/model-registry-sync.bats`, `pytest tests/unit/providers/`)
- Cross-map invariant warning (cycle-094 G-7) — explain why the test exists, what it catches
- Decision table: Bearer-token vs SigV4-style auth (when does each apply?)
- Pricing-source guidance (live-fetch at sprint time, freeze in YAML, document refresh cadence per `model-config.yaml:170-180` Haiku 4.5 precedent)

**Acceptance Criteria:**
- [ ] Guide enumerates all six edit sites with current file paths
- [ ] Bedrock implementation referenced as worked example at each step
- [ ] Validation checklist runnable as documented (no missing steps)
- [ ] Reviewed by `/review-sprint` against the actual Bedrock implementation for fidelity

**Dependencies:** FR-1 through FR-8 (the Bedrock implementation must exist before the guide can cite it)

### FR-10: Tests

**Priority:** Must Have (Sprint 1, completed by Sprint 2)

**Description:**
Test coverage spans unit + integration + invariants:

| Layer | Test | Location |
|---|---|---|
| Unit (Python) | `BedrockAdapter` complete/validate/health with mocked `http_post` | `tests/unit/providers/test_bedrock_adapter.py` (new) |
| Unit (Python) | Region resolution chain | (same file) |
| Unit (Python) | Auth-mode rejection — sigv4 raises clear error | (same file) |
| Integration (live, key-gated) | End-to-end Bedrock-Anthropic invocation | `tests/integration/test_bedrock_live.py` (new, gated by `AWS_BEARER_TOKEN_BEDROCK` env) |
| BATS | Bedrock entries present in all four `generated-model-maps.sh` arrays | `tests/integration/model-registry-sync.bats` (extend existing) |
| BATS | `validate_model_registry()` recognizes bedrock | `tests/unit/model-adapter.bats` (extend existing) |
| BATS | Health probe transitions bedrock model state | `tests/unit/model-health-probe.bats` (extend existing) |
| BATS | `lib-security.sh` redacts Bedrock API Keys (regex coverage) | `tests/unit/secret-redaction.bats` (extend existing) |

**Acceptance Criteria:**
- [ ] All new tests pass in CI
- [ ] Live integration test skips cleanly when env vars absent (no fork-PR no-keys regression — cycle-094 G-E2E precedent)
- [ ] Coverage of bedrock_adapter.py ≥ 85% (unit only; integration not counted)

**Dependencies:** FR-1 through FR-9

### FR-11: Bedrock-Specific Error Taxonomy + Retry Classifier (new in v1.1)

**Priority:** Must Have (Sprint 1) — promoted from generic "use existing retry" assumption per HIGH-CONSENSUS IMP-003.

**Description:**
`bedrock_adapter.py` includes a `_classify_error()` method that maps Bedrock response status + body to a Loa retry decision. Generic `5xx → retry` is insufficient because (a) Bedrock daily-quota responses can arrive as 200 OK with a quota-message body, (b) `ValidationException` and `AccessDeniedException` are HTTP 400/403 but require distinct caller treatment, (c) the daily-quota condition is process-lifetime and must trip a circuit breaker rather than retry.

**Implementation:** Sprint 0 G-S0-4 produces the enumerated category table; FR-11 wires it into the adapter retry loop.

**Acceptance Criteria:**
- [ ] `_classify_error()` covers all G-S0-4 categories
- [ ] Daily-quota detection trips a process-scoped `_daily_quota_exceeded` flag; subsequent calls fail-fast with clear error
- [ ] `ValidationException`, `AccessDeniedException`, `ResourceNotFoundException` all surface immediately (no retry)
- [ ] Empty-response edge case (200 OK with empty `content[]`) gets exactly one retry, then surfaces as `EmptyResponseError`
- [ ] Unit tests cover each category with realistic fixture responses captured from Sprint 0 G-S0-2 probes
- [ ] Daily-quota circuit-breaker test verifies recovery (release on process restart)

**Dependencies:** Sprint 0 G-S0-4; FR-2

### FR-12: Cross-Region Inference Profiles — MVP Day-1 (promoted from "future" in v1.1)

**Priority:** Must Have (Sprint 1) — promoted per HIGH-CONSENSUS IMP-004 (originally listed as "future iterations" in v1.0).

**Description:**
Bedrock's newer Anthropic models are increasingly available **only via cross-region inference profiles** with region-prefix model IDs (`us.anthropic.*`, `eu.anthropic.*`, etc.). Treating this as future work risks Day-1 model unavailability for users in regions outside the primary inference profile's coverage. FR-12 makes region-prefixed IDs the Day-1 default and surfaces a clear error when the user's region doesn't match the profile.

**Acceptance Criteria:**
- [ ] All three Day-1 model IDs (FR-5) use region-prefix format (`us.anthropic.claude-*-vN:M`)
- [ ] Adapter logic: when user's `region_default` doesn't match the model's region prefix, surface `ConfigError` at request time with actionable message ("Model `us.anthropic.*` requires region in {us-east-1, us-east-2, us-west-2}; you have `region_default: eu-west-1`. Set `AWS_BEDROCK_REGION` or `hounfour.bedrock.region` to a supported region.")
- [ ] Sprint 0 G-S0-5 probe confirms cross-region inference profile availability for all three Day-1 models with Bearer auth
- [ ] Unit test covers region/prefix mismatch error path
- [ ] Documentation in FR-9 plugin guide explains the region-prefix convention as a Bedrock-specific gotcha

**Out of v1 scope (future iteration):** Cross-account inference profile ARNs (which require SigV4 auth — incompatible with Bearer tokens per Sprint 0 G-S0-2 probe #6 expectation); deferred to v2 along with FR-4.

**Dependencies:** Sprint 0 G-S0-5; FR-1, FR-5

### FR-13: Thinking-Trace Parity Verification (new in v1.1, addresses DISPUTED IMP-009)

**Priority:** Must Have (Sprint 1) — explicit verification rather than declared support.

**Description:**
The original v1.0 PRD declared `capabilities: [chat, tools, function_calling, thinking_traces]` for Bedrock-Anthropic models without verifying that Bedrock Converse exposes thinking traces identically to direct Anthropic API. Flatline DISPUTED IMP-009 flagged this as risky for downstream workflows that depend on thinking content. FR-13 adds an explicit verification step.

**Acceptance Criteria:**
- [ ] Sprint 0 G-S0-2 probe #4 (thinking-trace probe) produces a captured response that confirms either: (a) Converse exposes thinking content blocks identically, OR (b) Converse exposes thinking via a different shape that the adapter can normalize, OR (c) Converse does NOT expose thinking traces — in which case `capabilities` in FR-1 is amended to remove `thinking_traces` for the affected models, and `api_format.thinking_traces: invoke` is set to route thinking-trace requests to InvokeModel
- [ ] Whatever the probe finding, FR-1 YAML reflects ground truth (no aspirational capabilities)
- [ ] Unit test verifies the adapter's thinking-trace handling matches the probe-confirmed shape
- [ ] If thinking traces are NOT supported via Converse: FR-9 plugin guide documents the gap and the v2 InvokeModel route

**Dependencies:** Sprint 0 G-S0-2 probe #4

> **Sources for FR-1 through FR-13**: `.claude/defaults/model-config.yaml:8-244` for SSOT structure; `.claude/adapters/loa_cheval/providers/base.py:158-211` for adapter contract; `.claude/scripts/generated-model-maps.sh:12-50` for bash maps; `.claude/data/model-permissions.yaml:147-173` for trust scopes template; `.claude/scripts/lib-security.sh:40-50` for redaction patterns; `.claude/scripts/model-adapter.sh:207-268` for probe-cache contract; `grimoires/loa/NOTES.md:38-46` for cycle-094 G-7 invariant. User confirmation context: 2026-05-01 Phase 1 reply. Flatline review: 6 BLOCKERS + 5 HIGH-CONSENSUS + 2 DISPUTED integrated in PRD v1.1 (`grimoires/loa/a2a/flatline/issue-652-bedrock-prd-review.json`).

---

## Non-Functional Requirements

### Performance

- **NFR-P1**: Bedrock request latency budget matches direct Anthropic (p50 < 3 seconds for short prompts; defer measurement to /architect SDD)
- **NFR-P2**: Health probe completes in < 1 second on cache hit, < 3 seconds on miss
- **NFR-P3**: No new latency added to existing direct-vendor request paths (zero-cost addition for non-Bedrock users)

### Scalability

- **NFR-S1**: Concurrency model matches existing providers — no provider-specific rate limiting in v1 (Bedrock has its own per-account quotas; defer to AWS-side limits)
- **NFR-S2**: Adapter must support concurrent invocations (existing `concurrency.py` patterns apply unchanged)

### Security

- **NFR-Sec1** (EARS): **The system shall NOT** log the value of `AWS_BEARER_TOKEN_BEDROCK` in any code path — including stderr, trajectory logs, audit logs, or error messages
- **NFR-Sec2** (EARS, revised v1.2 per Flatline v1.1 IMP-002): **When** the secret-redaction filter (`lib-security.sh redact_secrets`) processes a Bedrock API Key, **the system shall** replace the value with `[REDACTED]` via TWO layered mechanisms:
  - **Layer 1 (locked v1.2)**: `_SECRET_PATTERNS` array extended with the regex `ABSK[A-Za-z0-9+/=]{36,}` covering AWS-issued Bedrock API Keys (the publicly-documented prefix as of cycle start). If AWS evolves the prefix, Sprint 1 detects via Sprint 0 G-S0-2 probe response capture and updates the regex before merge.
  - **Layer 2 (NFR-Sec10)**: Value-based redaction — any string equal to the resolved env var value is also replaced regardless of pattern match.
  Both layers are mandatory; neither is sufficient alone. Test fixture in `tests/unit/secret-redaction.bats` covers both paths.
- **NFR-Sec3**: API key validation in `validate_config()` checks **presence and non-empty**, not format — vendor format may evolve; let Bedrock reject malformed keys with its own 401 error (avoid format brittleness)
- **NFR-Sec4**: Trust scopes in `model-permissions.yaml` for `bedrock:anthropic.*` models mirror `anthropic:*` entries — these are remote review oracles with no side effects (data_access: none, financial: none, etc., per `model-permissions.yaml:147-173` template)
- **NFR-Sec5**: Cycle-095 cost guardrails (`max_cost_per_session_micro_usd` in `model-config.yaml:344`) apply unmodified — Bedrock requests count toward the same budget
- **NFR-Sec6** (new in v1.1 per BLOCKER SKP-003): Key-rotation cadence — **The system shall** document a recommended rotation cadence of **≤ 90 days** for `AWS_BEARER_TOKEN_BEDROCK` in the operator runbook. Rotation procedure: generate new token in AWS console → update env var → restart Loa processes → revoke old token. No code-level enforcement (operator responsibility) but the runbook is shipped in the FR-9 plugin guide.
- **NFR-Sec7** (new in v1.1 per BLOCKER SKP-003): Revocation procedure — **When** an operator suspects token compromise, **the system shall** support immediate revocation by: (a) revoking in AWS console (effective within minutes), (b) clearing the env var, (c) restarting Loa processes. The runbook documents the AWS console URL and the Loa cache-invalidation step (`.claude/scripts/model-health-probe.sh --invalidate bedrock`).
- **NFR-Sec8** (new in v1.1, schema locked v1.2 per Flatline v1.1 IMP-003): Detection signals — **The system shall** log the following events distinctly in `grimoires/loa/a2a/cost-ledger.jsonl` and `.run/audit.jsonl` using the schema below:

  ```jsonc
  // cost-ledger.jsonl entries — Bedrock-relevant fields (additive to existing ledger schema)
  {
    "timestamp": "2026-MM-DDTHH:MM:SSZ",
    "provider": "bedrock",
    "model_id": "us.anthropic.claude-opus-4-7",
    "input_tokens": 0,
    "output_tokens": 0,
    "cost_micro_usd": 0,
    "event_type": "completion" | "fallback_cross_provider" | "circuit_breaker_trip" | "token_rotation",
    "fallback": null | "cross_provider" | "demoted_model",  // present when event_type == fallback_cross_provider
    "token_hint": null | "abc1"  // last-4-chars of token's SHA256 prefix; present on first call from new token (token_rotation event_type)
  }

  // .run/audit.jsonl entries — Bedrock-relevant security events
  {
    "timestamp": "2026-MM-DDTHH:MM:SSZ",
    "category": "auth" | "compliance" | "circuit_breaker",
    "subcategory": "token_revoked" | "fallback_cross_provider_warned" | "daily_quota_exceeded",
    "provider": "bedrock",
    "details": "...",  // human-readable
    "actor": "loa-cheval" | "model-adapter.sh"
  }
  ```

  Specific events:
  - First successful Bedrock call from a new token (token-rotation indicator) — `event_type: token_rotation`, `token_hint` populated; NEVER log the full token
  - 401/403 responses from Bedrock (potential revoked token) — `category: auth`, `subcategory: token_revoked` in audit log + stderr
  - Daily-quota circuit-breaker trips — `event_type: circuit_breaker_trip` in cost ledger + `category: circuit_breaker` in audit log + stderr
  - Compliance fallback events (only when `compliance_profile != bedrock_only`) — `event_type: fallback_cross_provider`, `fallback: cross_provider` in cost ledger + `category: compliance, subcategory: fallback_cross_provider_warned` in audit log + stderr warning
- **NFR-Sec9** (new in v1.1 per BLOCKER SKP-003): Incident-response runbook ownership — The Bedrock provider plugin guide (FR-9) includes an "If your Bedrock token is compromised" section documenting: detection signals, immediate revocation steps, blast-radius assessment (which Loa workflows used the token, by ledger query), and cycle-095 cost guardrails as a damage-cap layer. Runbook owner: Loa maintainer (`@janitooor` per CODEOWNERS).
- **NFR-Sec10** (new in v1.1 per HIGH-CONSENSUS IMP-002): Secret-redaction value-based fallback — **When** the redaction filter (`lib-security.sh redact_secrets`) cannot pattern-match a Bedrock token (because the format may evolve), **the system shall** also support **value-based redaction**: any string equal to the resolved `AWS_BEARER_TOKEN_BEDROCK` env var value is replaced with `[REDACTED]` regardless of pattern match. This is a defense-in-depth layer over the regex pattern (which catches AWS-pattern tokens like `ABSKY*` and `AKIA*`).

### Reliability

- **NFR-R1** (revised in v1.1 per BLOCKER SKP-005): Bedrock provider participates in existing fallback chain **only when user opts in** via `providers.bedrock.compliance_profile`. **Default `bedrock_only` for users who set Bedrock as a primary provider** — fail-closed on Bedrock outage rather than silent cross-provider egress. Three modes (locked in Sprint 0 G-S0-3):
  - `compliance_profile: bedrock_only` (default for Bedrock-configured users) — Bedrock outage → fail-closed with actionable error
  - `compliance_profile: prefer_bedrock` — Try Bedrock first, fall back to direct Anthropic with **explicit warning logged to stderr + cost ledger** entry tagged `fallback: cross_provider`
  - `compliance_profile: none` — Original v1.0 behavior (silent fallback) — only applied when user explicitly sets it
- **NFR-R2**: Bedrock failures count toward circuit breaker thresholds (`model-config.yaml:355-360`) on a per-provider basis
- **NFR-R3**: Probe-gated rollout (`probe_required` mechanism, cycle-093 sprint-3 / cycle-095 sprint-2 precedent) available but **not enabled** for the three Day-1 Anthropic models since they are GA on Bedrock at cycle start
- **NFR-R4** (new in v1.1 per HIGH-CONSENSUS IMP-003): Bedrock adapter uses a Bedrock-specific error taxonomy enumerated in Sprint 0 G-S0-4. Generic "5xx → retry" logic is insufficient; daily-quota responses (which may arrive as 200 OK with a quota-message body, not just HTTP-coded errors) trigger a process-lifetime circuit breaker for the bedrock provider. Specific behaviors:
  - `ThrottlingException` (429) — exponential backoff + jitter, max 3 retries (matches existing `model-config.yaml:362-367`)
  - `ServiceUnavailableException` / 5xx — exponential backoff + jitter
  - `ValidationException` (400) / `AccessDeniedException` (403) / `ResourceNotFoundException` (404) — no retry, surface immediately
  - Daily-quota body pattern (e.g., text containing "too many tokens per day", "daily", "quota") — set process-scoped `_daily_quota_exceeded` flag, fail subsequent calls fast until process restart
  - Empty `content[]` array on 200 OK — single retry with same prompt; if second response also empty, surface as `EmptyResponseError` (publicly documented Bedrock-Anthropic edge case)

### Compliance

- **NFR-C1**: AWS data residency — Bedrock requests originate from the user's AWS account; no Loa-side data egress to non-AWS endpoints when bedrock is the configured provider
- **NFR-C2**: Audit trail — Bedrock requests appear in user's CloudTrail (provided by AWS, not Loa); Loa's cost ledger entries tag `provider: bedrock` distinctly

### Compatibility

- **NFR-Compat1** (EARS): **The system shall** preserve every existing alias resolution result. **If** a user's `model-invoke --validate-bindings` output differs after this cycle from before, **the system shall** treat that as a regression and block release
- **NFR-Compat2**: Loa-as-submodule downstream consumers (memory: "loa-as-submodule projects (e.g., #642 reporter pattern) must not break on `git submodule update --remote`") see no breaking changes — all additions are additive
- **NFR-Compat3**: No Python version bump, no new heavyweight dependency in v1 (httpx already present)

> **Sources**: NFR-Sec5 from `model-config.yaml:341-344` cycle-095 cost guardrails; NFR-R1 from `model-config.yaml:347-351`; NFR-Compat2 from `grimoires/loa/context/model-currency-cycle-preflight.md:88` cycle-095 stability constraint #4; security pattern from `lib-security.sh:40-50` and `model-permissions.yaml:147-173`.

---

## User Experience

### Key User Flows

#### Flow 1: First-Time Bedrock Setup

```
Generate Bedrock API Key in AWS Console
  → export AWS_BEARER_TOKEN_BEDROCK=<value>
  → (optional) edit .loa.config.yaml region
  → model-invoke --agent flatline-reviewer --model bedrock:us.anthropic.claude-opus-4-7 --input <file>
  → Completion returned; cost ledger entry written
```

#### Flow 2: Migrate `opus` Alias to Bedrock

```
Existing Loa setup with ANTHROPIC_API_KEY
  → AWS_BEARER_TOKEN_BEDROCK also set
  → Edit .loa.config.yaml: hounfour.aliases.opus: bedrock:us.anthropic.claude-opus-4-7
  → /implement sprint-N
  → All opus-using agents now route through Bedrock; no code change
```

#### Flow 3: Maintainer Adds a Fifth Provider

```
Open grimoires/loa/proposals/adding-a-provider-guide.md
  → Walk through 6-step checklist with bedrock as worked example
  → Run validation commands (gen-adapter-maps --check, bats, pytest)
  → All cross-map invariants green on first try
```

### Interaction Patterns

- **Configuration over code**: All user-facing decisions live in `.loa.config.yaml` overrides; no source edits required
- **Symmetry with existing providers**: `bedrock:` follows same `provider:model-id` discrimination pattern users already know from `anthropic:`, `openai:`, `google:`
- **Failure modes communicated clearly**: Missing `AWS_BEARER_TOKEN_BEDROCK` produces an actionable error message with a link to the Bedrock console (mirrors patterns in `lib-security.sh ensure_codex_auth` family)

### Accessibility Requirements

- **A11y-1**: All error messages parseable as plain text in monospace terminals (no ANSI-only formatting)
- **A11y-2**: Documentation guide rendered in standard markdown, no diagrams that lose meaning when read by a screen reader

---

## Technical Considerations

### Architecture Notes

The Bedrock adapter slots into the existing four-layer provider plugin architecture:

```
┌───────────────────────────────────────────────────────────────────┐
│  Layer 1: SSOT YAML                                                │
│  .claude/defaults/model-config.yaml — providers / models /         │
│  aliases / agent bindings / pricing / fallback / circuit breaker   │
└─────────────┬───────────────────────────────────────┬─────────────┘
              │ gen-adapter-maps.sh                   │ Python loader
              ▼                                       ▼
┌──────────────────────────────────┐  ┌────────────────────────────┐
│ Layer 2: Generated bash maps     │  │ Layer 3: Python adapters   │
│ generated-model-maps.sh          │  │ loa_cheval/providers/      │
│ MODEL_PROVIDERS / MODEL_IDS /    │  │ base.py: ProviderAdapter   │
│ COST_INPUT / COST_OUTPUT         │  │ {anthropic,openai,google,  │
│ Used by: model-adapter.sh,       │  │  bedrock}_adapter.py       │
│   red-team-model-adapter.sh,     │  │ Used by: cheval CLI,       │
│   flatline-orchestrator.sh,      │  │   model-invoke,            │
│   etc.                           │  │   /flatline workflows      │
└──────────────────────────────────┘  └────────────────────────────┘
              │                                       │
              │           Layer 4: Cross-cutting concerns               │
              │                                       │
   ┌──────────┴───────────────────────────────────────┴──────────┐
   │ model-permissions.yaml (trust scopes)                        │
   │ lib-security.sh (secret redaction)                           │
   │ model-health-probe.sh (probe + cache)                        │
   │ cost-ledger.jsonl (metering)                                 │
   └──────────────────────────────────────────────────────────────┘
```

Bedrock additions touch all four layers — no architectural shape change, just new entries and a new adapter class.

### Integrations

| System | Integration Type | Purpose |
|---|---|---|
| AWS Bedrock Runtime | HTTPS POST (Converse API) | Model inference |
| AWS Bedrock control plane | HTTPS GET (ListFoundationModels) | Health probe |
| AWS Bedrock Console (manual) | User flow | API key generation |
| Loa cost-ledger | Append JSONL | Cost metering with `provider: bedrock` tag |

### Dependencies

**Added in v1:**
- *(none — uses existing httpx + jq + yq stack)*

**Considered and rejected for v1:**
- `boto3` — only needed for SigV4 / IAM auth (deferred to v2)
- `aws-requests-auth` — same rationale
- `requests-aws4auth` — same rationale

**Reserved for v2 (follow-up cycle):**
- `boto3 >= 1.34` (or pure-Python SigV4 implementation if dependency footprint becomes a concern)

### Technical Constraints

- **Python ≥ 3.9** (existing Loa floor; httpx requires it)
- **No System Zone edits without authorization**: This PRD authorizes edits to `.claude/defaults/model-config.yaml`, `.claude/adapters/loa_cheval/providers/`, `.claude/scripts/{model-adapter,model-health-probe,gen-adapter-maps,lib-security}.sh`, `.claude/scripts/generated-model-maps.sh`, `.claude/data/model-permissions.yaml` at cycle-096 scope
- **Configurable paths preserved**: `LOA_GRIMOIRE_DIR`, `LOA_BEADS_DIR`, `LOA_CACHE_DIR` continue to work unchanged
- **Cycle-094 G-7 invariant**: `tests/integration/model-registry-sync.bats` cross-map drift test must continue to pass after bedrock additions

### [SDD-ROUTING] Flatline-v1.1 architectural concerns explicitly handed off to /architect

The following Flatline v1.1 findings are **architectural** in nature and belong in the SDD, not the PRD. They are NOT defects in the PRD; they are concerns that the SDD must address with concrete design choices.

#### SDD-1: Recurring CI smoke for Bedrock contract (closes Flatline v1.1 SKP-002 + IMP-005)

**Problem**: Sprint 0 G-S0-2 contract probes are one-shot. If AWS Bedrock changes a response shape between Sprint 1 and a later sprint, Loa silently drifts. Flatline correctly identifies this as a regression risk.

**SDD must specify**:
- Which subset of G-S0-2 probes promote to recurring CI smoke (recommendation: probe #2 minimal Converse + probe #3 tool schema verification)
- CI cadence (daily? weekly? per-PR-on-bedrock-touched-paths?)
- Cost-control mechanism: max smoke spend per CI run; abort if exceeded; cost-ledger entry per smoke run
- Secret-handling: where the Bedrock token lives in CI (org secret? env-injected via OIDC?), fork-PR no-keys default (skip cleanly, mirror cycle-094 G-E2E precedent)
- Fixture-diffing: capture probe responses to a `tests/fixtures/bedrock/` directory; CI fails on response-shape change with a clear diff

**Out of PRD scope**: PRD asserts the requirement exists; SDD designs the mechanism.

#### SDD-2: Centralized colon-bearing model ID parser (closes Flatline v1.1 SKP-006)

**Problem**: The provider-model parser logic appears in multiple places — `gen-adapter-maps.sh` (bash), `model-adapter.sh` (bash), the cheval Python loader, and the `validate_model_registry()` cross-check. Each location must independently get colon-handling right when bedrock-namespaced model IDs (e.g., `us.anthropic.claude-opus-4-7`) contain colons that conflict with the `provider:model-id` separator.

**SDD must specify**:
- A single canonical parser (recommend: a helper function in `gen-adapter-maps.sh` that all bash callers source; a corresponding `loa_cheval/types.py` helper for Python callers)
- The contract: split on FIRST colon only; everything after is the literal model ID
- A property test (cross-language) — same set of inputs runs through both bash and Python parsers and produces equivalent results; lives in `tests/integration/parser-cross-language.bats`
- Failure mode: parser surfaces clear error for malformed IDs (e.g., `bedrock:` with empty model component, or no colon at all)

**Out of PRD scope**: PRD asserts the parser must be consistent (FR-1 AC closes IMP-007); SDD designs the centralization.

---

### [ASSUMPTION] flagged for /architect to verify

- **A1** Bedrock API Keys (Bearer-token style) are the auth modality the user's customers want — based on user reply 2026-05-01 ("bedrock managed keys"). If sprint-time investigation reveals these users actually mean SigV4 / IAM credentials, scope changes significantly: see FR-4 v2 path.
- **A2** Bedrock Converse API supports the full feature set Loa uses against direct Anthropic (thinking_traces, tools, function_calling, max_tokens). Verify at sprint time; fall back to InvokeModel per-vendor body if Converse gaps appear.
- **A3** Bedrock pricing for the three Day-1 Anthropic models is roughly competitive with direct Anthropic rates. Verify at sprint time before committing model coverage; if pricing is significantly worse, surface to user via FR-5 acceptance.
- **A4** Bedrock model IDs follow the `<vendor>.<family>-vN:M` pattern (e.g., `anthropic.claude-opus-4-7-v1:0`). Confirm exact IDs via live `ListFoundationModels` call at Sprint 1 start; the values written here are placeholders.
- **A5** Loa's existing httpx + urllib HTTP layer (`base.py:30-99`) is sufficient for Bedrock — no AWS-specific HTTP middleware (e.g., for retries on `ProvisionedThroughputExceededException`) needed in v1. Sprint 1 can add a Bedrock-specific 4xx → retry-classification map if needed.

---

## Scope & Prioritization

### In Scope (Sprint 0 — Contract Verification Spike, blocks Sprint 1)

- G-S0-1: Auth-modality user survey (≥ 2 Bedrock users confirm Bearer-token usage)
- G-S0-2: Live API contract probes (6 probes against real Bedrock account)
- G-S0-3: Compliance profile schema decision (locks NFR-R1 fallback default)
- G-S0-4: Bedrock error taxonomy enumeration (feeds FR-11)
- G-S0-5: Cross-region inference profile verification (feeds FR-12)
- Output: `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md`

### In Scope (MVP — Sprint 1, gated on Sprint 0 PASS)

- FR-1: Bedrock provider entry in YAML SSOT (with per-capability `api_format`, `compliance_profile`, region-prefixed model IDs)
- FR-2: `bedrock_adapter.py` Python adapter (URL-encoded model ID, tool schema wrapping, per-capability dispatch)
- FR-3: Bedrock API Keys (Bearer-token) auth via `AWS_BEARER_TOKEN_BEDROCK`
- FR-5: Three Day-1 Anthropic-on-Bedrock models (Opus 4.7, Sonnet 4.6, Haiku 4.5) with region-prefix IDs — pricing live-fetched
- FR-6: Region configuration (default + override chain)
- FR-7: Same-model dual-provider naming discipline (no default alias retargeting; explicit `bedrock:` prefix)
- FR-8: Health probe extension (Bedrock control-plane reachability)
- **FR-11 (promoted)**: Bedrock-specific error taxonomy + retry classifier
- **FR-12 (promoted from future)**: Cross-region inference profiles — Day-1 model IDs use region-prefix format
- **FR-13 (new)**: Thinking-trace parity verification
- FR-10 (partial): Unit tests for adapter; BATS extension for cross-map invariants; live integration test (key-gated); colon-bearing model ID test fixture

### In Scope (Sprint 2)

- FR-4 (design-only, this cycle): `auth_modes` schema field + loader rejection of unsupported `sigv4` value with clear error
- FR-9: Provider-plugin guide at `grimoires/loa/proposals/adding-a-provider-guide.md` (now includes the **NFR-Sec9 incident-response runbook** section)
- FR-10 (completion): Health probe BATS tests; secret-redaction BATS test extension; daily-quota circuit-breaker test
- Documentation: extend `.claude/loa/reference/` provider summary if cycle-level authorization is granted in /architect SDD; otherwise stay in grimoires/proposals/

### In Scope (Future Iterations — Out of This Cycle)

- **v2 SigV4 / IAM implementation** (FR-4 build-out) — gated on Sprint 0 G-S0-1 finding (PASS-WITH-CONSTRAINTS could promote to this cycle)
- Cross-account inference profile ARNs (require SigV4 — bundled with v2)
- Non-Anthropic Bedrock-hosted models (Mistral, Cohere Command, Meta Llama, AI21, Amazon Titan, Stability)
- Bedrock-only features (Agents, Knowledge Bases, Guardrails)
- Multi-region failover routing (single region with prefix-aware error in v1)
- Bedrock Provisioned Throughput tier-aware pricing (today's pricing entries assume on-demand)

### Explicitly Out of Scope

- **Default-alias retargeting** — `opus`, `cheap`, `reviewer`, etc. continue resolving to direct vendors. Reason: backward compatibility (NFR-Compat1, FR-7); users opt in via `.loa.config.yaml` override.
- **`boto3` dependency in v1** — Reason: User asked for "easy"; SigV4 is deferred to v2.
- **Bedrock-routed OpenAI / Google models** — Reason: not the v1 user motivation; revisit when a user surfaces the need.
- **Anthropic SDK direct integration via Bedrock** — Reason: stays under the cheval Python adapter abstraction; matches existing Anthropic adapter pattern.
- **Per-organization Bedrock account routing** — Reason: not a v1 user request; defer to ops-tier work.

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| Sprint 0 — G-S0-1 user survey | P0 | S | Critical (gates auth scope) |
| Sprint 0 — G-S0-2 contract probes | P0 | S | Critical (gates Sprint 1) |
| Sprint 0 — G-S0-3 compliance schema | P0 | S | High (gates NFR-R1) |
| Sprint 0 — G-S0-4 error taxonomy | P0 | S | High (feeds FR-11) |
| Sprint 0 — G-S0-5 region verification | P0 | S | High (feeds FR-12) |
| FR-1 — YAML entry | P0 | S | High |
| FR-2 — Python adapter | P0 | M | High |
| FR-3 — API-Key auth | P0 | S | High |
| FR-4 — SigV4 design | P1 | S (this cycle) | Medium (this cycle) / High (v2 cycle) |
| FR-5 — Day-1 models | P0 | S | High |
| FR-6 — Region config | P0 | S | Medium |
| FR-7 — Naming discipline | P0 | S | High (regression prevention) |
| FR-8 — Health probe | P1 | M | Medium |
| FR-9 — Plugin guide + IR runbook | P0 | M | High (issue's secondary ask + NFR-Sec9) |
| FR-10 — Tests | P0 | M | High |
| **FR-11 — Error taxonomy** | **P0** | M | High (reliability) |
| **FR-12 — Cross-region profiles** | **P0** | S | High (Day-1 availability) |
| **FR-13 — Thinking-trace parity** | **P0** | S | High (capability honesty) |
| **NFR-R1 — Compliance fallback** | **P0** | S | High (compliance posture preserved) |
| **NFR-Sec6/7/8/9 — Key lifecycle** | **P0** | M | High (security baseline) |
| **NFR-Sec10 — Value-based redaction** | **P0** | S | Medium (defense-in-depth) |

---

## Success Criteria

### Launch Criteria (Sprint 1 → 2 ship gate)

- [ ] All P0 FRs (FR-1, FR-2, FR-3, FR-5, FR-6, FR-7) acceptance criteria met
- [ ] Live integration test passes against a real Bedrock account (CI secret or maintainer dogfood)
- [ ] `model-invoke --validate-bindings` byte-identical before/after the cycle for non-Bedrock-overridden configs
- [ ] All existing test suites pass without modification (regression check)
- [ ] FR-9 plugin guide reviewed by `/review-sprint` against the actual implementation
- [ ] Pricing values for the three Bedrock-Anthropic models live-fetched and committed with citation
- [ ] Cycle-094 G-7 invariant (`bats tests/integration/model-registry-sync.bats`) passes
- [ ] Flatline review run on the bedrock branch shows no BLOCKER findings

### Post-Launch Success (30 days)

- [ ] At least one Bedrock-using Loa user confirms successful adoption (issue comment or feedback channel)
- [ ] No P0/P1 bugs filed against bedrock provider
- [ ] No regression reports against existing providers
- [ ] Plugin guide referenced in at least one community-driven provider-add discussion (or zero, if no other provider was requested — that's also a valid outcome for 30 days)

### Long-term Success (90 days)

- [ ] If a non-Anthropic Bedrock model or non-Bedrock new provider is added, it follows the FR-9 plugin guide and lands in ≤ 1 day of contributor work (G-2 validation)
- [ ] If SigV4 / IAM auth becomes user-required, the v2 build-out cycle finds the v1 architecture accommodates it without retrofit (FR-4 design validation)
- [ ] Bedrock cost ledger entries traceable to user attribution at the same fidelity as existing providers

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|---|---|---|---|
| **R-1**: Bedrock API Keys are still maturing as a feature; vendor edge cases (rate limits, key-rotation, regional inconsistency) surface during integration | Medium | Medium | Live integration test against real Bedrock account before merge; canary with a maintainer's Bedrock account ahead of public ship; document known limitations at sprint close |
| **R-2**: User's "managed keys" intent turns out to be SigV4/IAM, not Bearer-token API Keys — auth scope misread | Low | High | Surface this assumption (A1) explicitly; PRD review with user confirms before /architect; if confirmed wrong, reframe Phase 1 and rescope |
| **R-3**: Bedrock Converse API has feature gaps vs direct Anthropic (thinking traces, tool use) | Medium | Medium | Verify Converse coverage at Sprint 1 start; fall back to InvokeModel per-vendor body for affected capabilities; update `api_format` field per-model |
| **R-4**: Same-model dual-provider naming confusion — user mistakenly picks `claude-opus-4-7` thinking it's Bedrock | Low | Low | FR-7 enforces explicit `bedrock:` prefix; cost ledger tags `provider:` field distinctly; documentation calls out the distinction |
| **R-5**: Bedrock pricing diverges significantly from direct Anthropic mid-cycle (vendor change before sprint ships) | Low | Low | Cycle-095 sprint-2 SKP-004 precedent — pricing is YAML-frozen at sprint execution with documented refresh cadence (`model-config.yaml:171-180` Haiku 4.5 comment); add quarterly pricing-refresh reminder to operator runbook |
| **R-6**: Cross-map invariant test (cycle-094 G-7) misses a new edge case introduced by bedrock-namespaced model IDs containing colons (`anthropic.claude-opus-4-7-v1:0`) | Low | Medium | Sprint 1 test extension covers colon-bearing keys; review parsing in `gen-adapter-maps.sh` for `:`-handling against literal model IDs vs `provider:model-id` aliases |
| **R-7**: Plugin guide bit-rots — Bedrock implementation drifts and guide gets stale | Medium | Low | Sprint 2 acceptance: guide is reviewed against actual implementation by `/review-sprint`; consider a CI check that asserts file:line anchors in the guide still resolve |
| **R-8**: Loa-as-submodule downstream consumers break on the schema additions (`region_default`, `auth_modes`, `api_format`) | Low | Medium | Cycle-095 stability constraint #4 (memory: "loa-as-submodule projects must not break on `git submodule update --remote`") — additive YAML changes; loader treats missing fields as defaults |
| **R-9**: AWS Bedrock control-plane probe endpoint `/foundation-models` requires different auth or path than expected | Medium | Low | Verify URL pattern at Sprint 0 G-S0-2 probe #1 before health probe code lands; FR-8 priority is P1 (slippage is acceptable) |
| **R-10** (new v1.1): Empty `content[]` array on 200 OK from Bedrock-Anthropic — caller code path mishandles as success or as fatal error | Medium | Medium | NFR-R4 single-retry policy; `EmptyResponseError` surface; test fixture replays a captured empty response from Sprint 0 G-S0-2 probe #5 |
| **R-11** (new v1.1): Daily-quota exhaustion trips a circuit breaker that stays tripped until process restart, leaving Loa silently unable to call Bedrock for the rest of the session | Medium | Medium | Surface in stderr + audit log + cost ledger (NFR-Sec8); operator runbook documents restart procedure; consider supporting time-windowed reset (24h after last quota error) in v2 |
| **R-12** (new v1.1): Bedrock tool-schema wrapping requirement (`inputSchema: { json: <schema> }`) is missed during implementation, silently breaking tool calls | Medium | High | FR-2 implementation guidance documents the wrapping; Sprint 0 G-S0-2 probe #3 confirms the requirement; unit test verifies the wrapping is applied |
| **R-13** (new v1.1): User's region doesn't match available cross-region inference profiles for Day-1 models (e.g., user is in `eu-west-1` but `us.anthropic.*` only available in US regions) | Medium | Medium | FR-12 region-prefix mismatch error path; Sprint 0 G-S0-5 probes both `us.*` and `eu.*` to confirm coverage; documentation in FR-9 plugin guide |

### Assumptions

> v1.1 status legend: ✅ VALIDATED via public Bedrock docs and Sprint 0 plan / 🟡 NEEDS-VALIDATION (gates Sprint 1) / 🔴 OPEN (depends on user/probe)

- **A1** (recap, status: 🔴 OPEN → resolved by Sprint 0 G-S0-1): "managed keys" = Bedrock API Keys (Bearer token), not SigV4/IAM. Flatline BLOCKER SKP-001 elevated this from a flag to a blocking gate.
- **A2** (status: 🟡 NEEDS-VALIDATION → resolved by Sprint 0 G-S0-2 probe #4 + FR-13): Bedrock Converse API has parity with direct Anthropic for the v1 capability set. Per-capability `api_format` schema (FR-1) accommodates partial-parity outcomes.
- **A3** (status: 🟡 NEEDS-VALIDATION → resolved by Sprint 1 pricing fetch): Bedrock pricing for Day-1 Anthropic models is competitive enough with direct Anthropic that users rationally choose Bedrock for non-cost reasons.
- **A4** (status: ✅ TENTATIVELY VALIDATED via public Bedrock docs; final via Sprint 0 G-S0-2 probe #1): Exact Bedrock model IDs follow region-prefixed `<region>.<vendor>.<family>-<datestamp>-vN:M` shape; confirmable via live `ListFoundationModels`.
- **A5** (status: ✅ VALIDATED via codebase grounding): Loa's existing HTTP stack (httpx + urllib fallback at `base.py:30-99`) is sufficient — no AWS-SDK middleware needed for v1.
- **A6** (status: 🔴 OPEN — operator action): `cycle-095` archives cleanly via `/ship` or `/archive-cycle` before this cycle starts, freeing `grimoires/loa/prd.md`.
- **A7** (new v1.1, status: 🟡 NEEDS-VALIDATION → resolved by Sprint 0 G-S0-3): Bedrock-using Loa users have at least one user with a compliance posture that requires fail-closed behavior on Bedrock outage — making `compliance_profile: bedrock_only` the right default. If no user has such posture, default may flip to `prefer_bedrock`.
- **A8** (new v1.1, status: ✅ VALIDATED via public Bedrock docs): URL-encoding the Bedrock model ID (which contains colons) in the request URL is required; raw colons in URL paths break HTTP routing.
- **A9** (new v1.1, status: ✅ VALIDATED via public Bedrock docs): Bedrock Converse `toolConfig.tools[].toolSpec.inputSchema` requires `{ json: <schema> }` wrapping (distinct from direct Anthropic tool-use shape).

### Dependencies on External Factors

- **D-1**: AWS Bedrock service availability in user's region (out of Loa's control)
- **D-2**: Bedrock API Key feature stability (vendor surface; out of Loa's control)
- **D-3**: Anthropic model availability via Bedrock (vendor surface; out of Loa's control — though current state shows full Anthropic family available)
- **D-4**: Cycle-095 archival completing before this cycle's PRD lands at canonical path

---

## Timeline & Milestones

> **Caveat**: Sprint sizing is /architect's responsibility; the table below is a rough framing per `grimoires/loa/context/model-currency-cycle-preflight.md:90-98` precedent for cycle structure proposals.

| Milestone | Target | Deliverables |
|---|---|---|
| Cycle-095 archived | Pre-Sprint 0 | `/ship` or `/archive-cycle` cycle-095; `grimoires/loa/prd.md` available for this PRD |
| /architect completes SDD | Pre-Sprint 0 | `grimoires/loa/sdd.md` covering provider plugin contract evolution, Bedrock Converse mapping, FR-4 v2 design, A1–A9 verification plan, Sprint 0 spike scope |
| /sprint-plan generates plan | Pre-Sprint 0 | `grimoires/loa/sprint.md` with Sprint 0 + FR breakdown into sprint tasks |
| **Sprint 0 ship** — Contract Verification Spike (NEW v1.1) | T+5 days | `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md` with G-S0-1 through G-S0-5 PASS verdicts; FR-1 model IDs updated with Sprint 0 probe-confirmed values; pricing live-fetched |
| **Sprint 1 ship** — Bedrock v1 (API-Key) functional | T+10–12 days | FR-1, FR-2, FR-3, FR-5, FR-6, FR-7, FR-11, FR-12, FR-13, FR-10 (unit + live integration); NFR-R1 compliance-aware fallback; NFR-R4 error taxonomy; UC-1 + UC-2 verified |
| **Sprint 2 ship** — Plugin guide + IR runbook + FR-4 design | T+15–18 days | FR-4 schema-only, FR-8 health probe, FR-9 plugin guide with NFR-Sec9 IR runbook section, NFR-Sec10 value-based redaction, FR-10 BATS extensions; UC-3 dry-run by maintainer |
| Post-merge | T+18–25 days | Cost ledger validation; user adoption confirmation; quarterly pricing-refresh reminder added to operator runbook; key-rotation cadence documented (NFR-Sec6) |
| **Sprint 3 (deferred / split-out)** — SigV4 implementation | T+? (gated on Sprint 0 G-S0-1 finding + user demand) | FR-4 v2 build-out — promoted into this cycle if Sprint 0 G-S0-1 returns PASS-WITH-CONSTRAINTS |

---

## Appendix

### A. Stakeholder Insights

- **User (deep-name / @janitooor)**: "we have people who use bedrock who use loa and so they have asked that loa be able to use bedrock managed keys / i am not sure how bedrock works so will defer to you on how to enable this easily" (issue #652 reply, 2026-05-01)
- **Phase 1 routing decisions** (2026-05-01):
  - PRD path: Treat #652 as new cycle (archive cycle-095 first)
  - Codebase grounding: Manual (skip /ride; surface area is one subsystem)
  - Auth approach: Both API Keys (v1) + SigV4 (v2 designed-not-built)
  - Phase 1→2: Skipped to PRD generation with user trust ("defer to you")
- **Flatline multi-model review pass #1** (v1.1 integration, 2026-05-01):
  - Models: Opus 4.7 + GPT-5.3-codex + Gemini-2.5-pro
  - Outcome: 80% agreement, 6 BLOCKERS, 5 HIGH-CONSENSUS, 2 DISPUTED — all integrated into v1.1
  - Cost: ~$0.68 (Phase 1 $0.59 + Phase 2 $0.09)
  - Key surfaces: Sprint 0 contract verification gate; compliance-aware fallback; key lifecycle NFRs; per-capability `api_format`; colon-bearing model ID parsing
  - Artifact: `grimoires/loa/a2a/flatline/issue-652-bedrock-prd-review.json`
- **Flatline multi-model review pass #2** (v1.2 integration, 2026-05-02):
  - Same model triplet
  - Outcome: **100% agreement, 5 BLOCKERS, 4 HIGH-CONSENSUS, 0 DISPUTED on v1.1**
  - Cost: ~$0.81 (Phase 1 $0.72 + Phase 2 $0.09; v1.1 PRD is longer)
  - Pattern: All 5 v1.1 BLOCKERS were higher-order refinements of v1.0 BLOCKERS (finding-rotation Kaironic stopping signal)
  - Triage: 3 PRD-level findings integrated into v1.2 (SKP-001/003 sample-size + threshold rule, SKP-004 defaulting determinism, IMP-001/002/003 quick fixes); 3 architectural findings explicitly routed to SDD via new `[SDD-ROUTING]` section (SKP-002 recurring CI smoke, SKP-006 centralized parser, IMP-005 CI cost controls)
  - Stopping decision: Kaironic finding-rotation at 100% agreement on increasingly fine-grained concerns — additional iterations expected to surface even finer concerns; remaining concerns are architectural and belong in SDD
  - Artifact: `grimoires/loa/a2a/flatline/issue-652-bedrock-prd-v11-review.json`

### B. Competitive Analysis

- **Direct Anthropic API**: Loa's existing path. Pros: lowest latency, full feature parity, simpler auth. Cons: separate billing relationship, no AWS data plane.
- **Bedrock-Anthropic**: New path. Pros: AWS billing consolidation, CloudTrail audit trail, VPC endpoint for data plane. Cons: separate model IDs, separate pricing, possible feature lag (Converse API maturity), regional availability constraints.
- **Other AI gateways** (Cloudflare AI Gateway, OpenRouter, Portkey): Not on Loa roadmap; mentioned only to clarify that Bedrock is *not* an AI gateway pattern — it's a vendor-managed inference plane on AWS, with its own model IDs and pricing.

### C. Bibliography

**Internal Resources:**
- Issue #652: https://github.com/0xHoneyJar/loa/issues/652
- Provider SSOT: `.claude/defaults/model-config.yaml`
- Adapter base class: `.claude/adapters/loa_cheval/providers/base.py`
- Generated bash maps: `.claude/scripts/generated-model-maps.sh`
- Model permissions: `.claude/data/model-permissions.yaml`
- Health probe: `.claude/scripts/model-health-probe.sh`
- Secret redaction: `.claude/scripts/lib-security.sh`
- Cycle-095 PRD (sibling cycle, model-currency): `grimoires/loa/prd.md` (active)
- Cycle-095 preflight: `grimoires/loa/context/model-currency-cycle-preflight.md`
- Cycle-094 G-7 invariant: `grimoires/loa/NOTES.md:38-46` and `tests/integration/model-registry-sync.bats`
- Backward-compat alias precedent: cycle-082 / PR #207 (memory)

**External Resources:**
- AWS Bedrock pricing: https://aws.amazon.com/bedrock/pricing/ (live-fetch at sprint time)
- AWS Bedrock API Keys docs: AWS Bedrock console → API keys section (verify URL at sprint time)
- AWS Bedrock Converse API reference: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html
- AWS Bedrock ListFoundationModels: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_ListFoundationModels.html

### D. Glossary

| Term | Definition |
|---|---|
| **Bedrock API Key** | Long-lived Bearer token issued by AWS Bedrock console for programmatic Bedrock access without SigV4 signing. Distinct from IAM access key IDs (`AKIA...`). |
| **SigV4** | AWS Signature Version 4 — the standard request-signing protocol used across AWS services. Requires Access Key ID + Secret Access Key + region + service. |
| **Converse API** | Bedrock's provider-agnostic inference API (`POST /model/{modelId}/converse`). Same body schema across all hosted vendors. Recommended default for v1. |
| **InvokeModel API** | Bedrock's per-vendor inference API (`POST /model/{modelId}/invoke`). Body schema differs per vendor (Anthropic uses Messages format, Mistral uses Chat Completions, etc.). Reserved for v2 fallback. |
| **Cross-map invariant** | Cycle-094 G-7 test asserting that for every key shared between `red-team-model-adapter.sh` MODEL_TO_PROVIDER_ID and generated-model-maps.sh MODEL_PROVIDERS, the provider value matches. Catches drift. |
| **Same-model dual-provider** | The case where the same underlying model is reachable via two distinct Loa providers — e.g., `anthropic:claude-opus-4-7` (direct Anthropic API) and `bedrock:us.anthropic.claude-opus-4-7` (Bedrock-hosted Anthropic). Different IDs, different pricing, identical model weights. |
| **Probe-gated rollout** | Pattern from cycle-093 sprint-3 / cycle-095 sprint-2 where a model entry is committed to YAML but marked `probe_required: true`, keeping it latent until `model-health-probe.sh` confirms vendor availability. |
| **Backward-compat alias** | Pattern (cycle-082 / #207) where legacy model names continue resolving to current canonical models so existing user `.loa.config.yaml` files keep working across model migrations. |

---

*Generated by /discovering-requirements skill, 2026-05-01. Source-traced to issue #652 + user reply + provider-subsystem codebase grounding (no /ride; manual grounding sufficient per Phase 0 routing).*
