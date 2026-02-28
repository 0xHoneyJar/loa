# PRD: Compassionate Excellence — Bridgebuilder Deep Review Integration

> Cycle-047 | Created: 2026-02-28
> Sources: PR #433 Bridge Review (iter 1), Deep Bridgebuilder Review (Parts 1-5), User Observations (Gemini/Red Team verification)

## 1. Problem Statement

Cycle-046 (Bridgebuilder Constellation) delivered the Deliberative Council, Pipeline Self-Review, and Governance Isomorphism lore. The subsequent 5-part deep Bridgebuilder review and bridge iteration surfaced improvements across four categories:

1. **Verification Gaps**: Two user-observed gaps — Gemini may not actually participate in Flatline, and Red Team may not execute during simstim. Additionally, the bridge review found defensive hardening needs (F-004 glob boundary matching, F-007 fence stripping fragility).

2. **Constitutional Promotion**: The `pipeline-sdd-map.json` functions as a constitution (defines which specifications govern which implementations) but is treated as a data file. It should be promoted to constitutional status with appropriate scrutiny and reverse mapping. (R-1)

3. **Shared Library Extraction**: Functions like `extract_prior_findings()` are trapped inside single scripts but needed across the pipeline. Compliance gate evaluation is conflated with extraction. These need factoring into shared libraries. (R-3, R-4)

4. **Adaptive Intelligence**: Token budget allocation is static (equal 3-way split) when information density varies across channels. Lore entries lack lifecycle semantics. Deliberation observability is absent — no mechanism to track which prior findings influenced which conclusions. (R-2, R-5, Part 5 "Missing" items)

> Sources: PR #433 comments (bridge iter 1: F-001 through F-013, deep review Parts 1-5: R-1 through R-6, SPEC-1 through SPEC-5)

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Gemini verified as live Flatline participant | End-to-end test with Gemini response | Gemini output visible in Flatline logs |
| Red Team documented in simstim workflow | SKILL.md + config reference updated | Clear on/off documentation |
| Pipeline SDD map promoted to constitutional status | Change detection triggers human-level scrutiny | Reverse mapping (SDD → implementations) exists |
| Shared library for findings/compliance functions | Functions importable from `.claude/scripts/lib/` | At least 2 scripts source the shared lib |
| Lore entries gain lifecycle fields | status, challenges, lineage fields in schema | Existing entries updated |
| Deliberation observability introduced | Bridge iterations log input channel metadata | Token allocation + prior findings influence visible |

## 3. Functional Requirements

### FR-1: Verification + Defensive Hardening (P0)

Verify that claimed capabilities actually work. Address accepted LOWs from bridge review.

| ID | Requirement |
|----|------------|
| FR-1.1 | Investigate Gemini participation in Flatline — trace from config through model-adapter.sh to actual API call |
| FR-1.2 | Document Red Team integration in simstim SKILL.md — clarify current on/off status, when it fires, how to enable |
| FR-1.3 | Fix F-004: glob `*` matching across `/` boundaries — add anchored path segment matching or document the flat-path assumption |
| FR-1.4 | Harden F-007: fence stripping when model returns preamble before JSON — add pre-JSON text detection |
| FR-1.5 | Add deliberation observability — log which input channels were used, their char counts, and token budget allocation per Red Team invocation |

### FR-2: Constitutional Architecture (P0)

Promote governance artifacts from data files to constitutional status.

| ID | Requirement |
|----|------------|
| FR-2.1 | Promote pipeline-sdd-map.json to constitutional status — changes trigger pipeline self-review AND flag for human review |
| FR-2.2 | Implement reverse mapping: given an SDD, find all implementations it governs |
| FR-2.3 | Add lifecycle fields to lore entries: status (Active/Challenged/Deprecated/Superseded), challenges array, lineage field |
| FR-2.4 | Add lore discoverability — bridge reviews should surface relevant lore entries for the files being reviewed |

### FR-3: Shared Library Extraction (P1)

Factor shared functions out of monolithic scripts into importable libraries.

| ID | Requirement |
|----|------------|
| FR-3.1 | Create `.claude/scripts/lib/findings-lib.sh` with `extract_prior_findings()` and related utilities |
| FR-3.2 | Create `.claude/scripts/lib/compliance-lib.sh` with `extract_sections_by_keywords()` and gate profile loading |
| FR-3.3 | Separate compliance gate extraction from evaluation — extraction returns sections, evaluation interprets them |
| FR-3.4 | Add `prompt_template` field support in compliance gate profiles — different gates can use different evaluation prompts |

### FR-4: Adaptive Intelligence + Ecosystem Design (P1)

Enable the review system to learn from its own operation.

| ID | Requirement |
|----|------------|
| FR-4.1 | Design adaptive token budget allocation — weight channels by estimated information density rather than equal split |
| FR-4.2 | Add cost tracking metadata to bridge iterations — inference cost per Red Team invocation logged to bridge state |
| FR-4.3 | Create economic feedback signal — marginal value estimation for additional bridge iterations |
| FR-4.4 | Document cross-repo governance protocol — how changes in one repo's SDD trigger review in dependent repos |
| FR-4.5 | Design capability-driven orchestration vision — bridge discovers available review capabilities via config/registry rather than hardcoded signals |

## 4. Non-Functional Requirements

| Requirement | Details |
|-------------|---------|
| Backward compatibility | All shared library extractions must maintain backward-compatible wrappers in original scripts |
| Config-gated | Adaptive token allocation default to disabled; classic equal split remains default |
| No new external dependencies | Libraries use existing bash/jq/yq tooling only |
| Performance | Reverse SDD mapping must complete in <1s for the full pipeline-sdd-map |

## 5. Out of Scope

- Cross-repo compliance implementation (design doc only — requires multi-repo infrastructure)
- ModelPort integration (depends on loa-finn #31 — design reference only)
- Reputation-weighted deliberation (SPEC-2 — requires metrics collection over multiple cycles)
- loa-dixie conviction voting integration (SPEC-4, R-6 — requires dixie API availability)
- Capability markets (SPEC-1 — strategic vision, not this cycle)
