# RFC-061: Polycentric Model-Calibration Pack

**Status**: Draft
**Tracker**: [#556](https://github.com/0xHoneyJar/loa/issues/556)
**Meta tracker**: [#557](https://github.com/0xHoneyJar/loa/issues/557) (Tier 3)
**Author**: Agent (proposal for maintainer review)
**Date**: 2026-04-18

## Summary

Ship a construct pack (`.loa/constructs/packs/model-calibrations/`) that carries multiple live model profiles (Opus 4.7, Sonnet 4.6, Haiku 4.5, Gemini 2.5 Pro, GPT-5.3-codex), switchable per-project and per-skill. Schema + verification substrate in Loa core; seed calibrations as pack data.

## Motivation

Three recent issues (#553, #554, #555) filed in a single 2-hour window by the same operator. Each valid independently; together they trace a "calibration seam" pattern — Loa's idioms were designed against Claude behaviors that have since shifted under Opus 4.7. Without a pack mechanism, updating idioms for a new model means either:

1. A Loa major bump pinned to one model's posture → debt the moment the next model lands
2. Scattered if/else throughout skill files → hard to audit and evolve

A calibration pack expresses "posture for model X" as data, not code. Multiple calibrations coexist. Switching is one config line. Loa's release cadence decouples from model vendor cadence.

## Three Open Decisions — Proposed Answers

### D1: Pack location

**Options**:
- (a) Bundled in `0xHoneyJar/loa` core — always available, tied to release cycle
- (b) Separate `0xHoneyJar/loa-model-calibrations` repo — independent cadence
- (c) Mixed — schema in core, seeds in satellite

**Proposed: (a) bundled in core, for v1.**

Rationale: bundled is simplest for the MVP. One install surface, one release artifact. If calibration update cadence materially diverges from Loa's (e.g., a model vendor ships faster than Loa), we can split out a satellite repo at that point. Premature split adds operational complexity for speculative benefit. The directory structure under `.loa/constructs/packs/model-calibrations/` can be lifted out to a satellite repo verbatim if needed.

**Revisit trigger**: if calibration updates require >2 Loa point releases in a single quarter to ship them, split.

### D2: Schema versioning

**Options**:
- (a) Calibration schema bound to Loa minor version
- (b) Independent `schema_version` on the pack
- (c) Live-follows latest — no versioning

**Proposed: (b) independent `schema_version` on the pack.**

Rationale: calibrations evolve on a different rhythm than Loa framework. Binding to Loa minor means every schema tweak forces a Loa minor bump. Live-follows-latest erodes determinism — operators can't pin. Independent `schema_version: 1` field on each calibration YAML lets us evolve without synchronizing releases; `/loa calibrate` can warn on schema mismatches.

```yaml
schema_version: 1
calibration_id: claude-opus-4-7
# ...
```

### D3: Re-calibration trigger

**Options**:
- (a) Manual operator command — `/loa calibrate <id>`
- (b) Auto-trigger on vendor release announcement
- (c) Scheduled `/tend` poll

**Proposed: (a) manual only, for v1.**

Rationale: auto-trigger and scheduled polls require vendor-release detection infrastructure that doesn't exist today. Manual keeps the operator in the loop, which is correct for a design that changes agent posture (trust boundary). Downstream projects apply calibrations deliberately, not reactively. If vendor-release monitoring materializes as its own service later, (b) becomes possible as a follow-up.

**Operator workflow**:

```bash
# List available calibrations
/loa calibrate list

# Apply a calibration to the current project
/loa calibrate claude-opus-4-7

# Audit: does the current project conform to the active calibration?
/loa audit-calibration
```

## Proposed Structure

```
.loa/constructs/packs/model-calibrations/
  manifest.json                          # Pack metadata
  calibrations/
    claude-opus-4-7.yaml                 # Seed
    claude-sonnet-4-6.yaml               # Seed
    claude-haiku-4-5.yaml                # Seed (when available)
    gemini-2.5-pro.yaml                  # Seed (cross-provider proof)
    gpt-5.3-codex.yaml                   # Seed
  lenses/
    interview-pacing.md                  # Governs /plan-and-analyze gates
    subagent-dispatch.md                 # Governs context: fork decisions
    rule-phrasing.md                     # Governs NEVER/INSTEAD pair generation
    thinking-budget.md                   # Governs adapter thinking config
    tool-calling-posture.md              # Governs prescriptive vs latitude skills
  skills/
    calibrate/                           # `/loa calibrate <id>` command
      SKILL.md
    audit-calibration/                   # `/loa audit-calibration` command
      SKILL.md
  CLAUDE.md                              # Pack identity + usage
```

## Calibration YAML Shape (illustrative, from #556 body)

```yaml
schema_version: 1
calibration_id: claude-opus-4-7
model_family: anthropic
effective: 2026-01-15
last_verified: 2026-04-18
sources:
  - https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code

interview:
  default_mode: minimal
  default_pacing: batch

subagents:
  default_context: inline
  fork_requires_rationale: true

thinking:
  budget: dynamic
  fixed_budget_allowed: false

effort:
  default: xhigh
  avoid: [max]

rule_phrasing:
  style: paired
  new_rules_require_pairing: true

tool_calling:
  prescriptive_sequences: discouraged
  agency_level: capable_engineer

known_antipatterns:
  - id: "opus47-AP-001"
    pattern: "SKILL.md declares write_files: true AND agent: Plan"
    fix: "remove agent: Plan OR swap to general-purpose"
    affects: [architect, sprint-plan]
    upstream_issue: "0xHoneyJar/loa#553"
  - id: "opus47-AP-002"
    pattern: "context: fork without stated rationale"
    fix: "add rationale in skill frontmatter OR drop fork"
    affects: [architect, sprint-plan, ride, audit, bug]

verify:
  lint_targets:
    - path: ".claude/skills/**/SKILL.md"
      invariants:
        - id: "write-capable-agent-for-write-skills"
          rule: "if capabilities.write_files == true, agent must be in write_capable_agents"
          write_capable_agents: [general-purpose, "(unset)"]
```

## MVP Scope

1. **Pack skeleton** — directory structure, `manifest.json`, stub lens files, stub skill files.
2. **`claude-opus-4-7.yaml` seed** — fully populated with the 4 known_antipatterns surfaced in the #553 filing window (Plan-blocks-Write, context:fork without rationale, fixed thinking budget, thorough+sequential interview default).
3. **`/loa calibrate list`** — read-only command to enumerate available calibrations.
4. **`/loa audit-calibration`** — dry-run scanner that reports calibration violations against `.claude/skills/`. Does NOT auto-fix.

Phase 2 (separate sprint):
- Add Sonnet / Gemini / GPT / Haiku seeds
- `/loa calibrate <id>` application command (modifies `.loa.config.yaml` to pin calibration)
- Wire `audit-calibration` into `/update-loa` verify step

Phase 3 (separate sprint):
- Lens authoring patterns (interview-pacing, subagent-dispatch, rule-phrasing, etc.)
- Per-skill calibration overrides in `.loa.config.yaml`

## Non-Goals

- Auto-applying calibrations on vendor release (D3 answer rules this out for v1)
- Replacing `.claude/rules/` invariant docs — calibrations add structured lint; rules remain the prose source
- Downstream fork/override mechanism — v1 assumes single calibration source (the bundled pack)

## Composition with Existing Loa Concepts

| Existing | Relationship to calibrations |
|---|---|
| Constructs / packs | Calibrations are a **new pack type** alongside `artisan`, `observer`, etc. |
| Lenses | **Orthogonal**. Calibrations govern *how* skills speak to a model; lenses govern *how* operators think about work. |
| `.loa.config.yaml` | New key: `model_calibration.active: claude-opus-4-7`. Per-skill override: `model_calibration.per_skill.{name}: gemini-2.5-pro`. |
| `adapters/loa_cheval/` | Adapters are transport; calibrations are intent. Adapter reads calibration for thinking/effort defaults. |
| `/update-loa` | Phase 2 gains verify step: run `audit-calibration`, refuse merge on invariant violation. |
| Flatline | Each reviewer's calibration honored on its turn — Opus posture for Opus, Gemini posture for Gemini. |

## Open Questions After This RFC

- Should `model_calibration.active` default to the calibration matching the project's primary reviewer model, or be explicit-opt-in?
- Do lenses belong in the pack or in `.claude/lenses/`?
- What's the upgrade path when an operator's active calibration's `schema_version` < the pack's `schema_version`?

None of these block MVP shipping. They surface in Phase 2.

## Ask

Maintainer review of the three proposed design decisions (D1 bundled, D2 independent versioning, D3 manual trigger). On approval, Phase 1 MVP (pack skeleton + Opus 4.7 seed + `calibrate list` + `audit-calibration` dry-run) is a standard bug/feature sprint.

## References

- Source issue: [#556](https://github.com/0xHoneyJar/loa/issues/556)
- Adjacent: [#553](https://github.com/0xHoneyJar/loa/issues/553), [#554](https://github.com/0xHoneyJar/loa/issues/554), [#555](https://github.com/0xHoneyJar/loa/issues/555) — the "calibration seam" filing window
- Anthropic Opus 4.7 + Claude Code best-practices blog: [link](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code) (referenced by #553 enrichment comment)
- Meta tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557)
