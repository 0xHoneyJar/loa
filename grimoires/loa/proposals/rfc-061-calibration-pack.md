# RFC-061: Polycentric Model-Calibration Pack (v2, Progen-style)

**Status**: Draft (supersedes v1 — closed on PR #572)
**Tracker**: [#556](https://github.com/0xHoneyJar/loa/issues/556)
**Meta tracker**: [#557](https://github.com/0xHoneyJar/loa/issues/557) (Tier 3)
**Author**: Agent (proposal for maintainer review)
**Date**: 2026-04-18
**Design lineage**: Google Progen, Protocol Buffers, Meta Thrift, Netflix Genie, Google SLSA / Sigstore, Bazel, OPA

---

## Why v2

v1 framed calibrations as YAML instances read at runtime by a bash/jq scanner. That's the "right answer without prior design inspiration." This project already has the substrate for the **right answer given our lineage**: `gen-adapter-maps.sh` (PR #566) is a small Progen pattern; `flatline-orchestrator.sh` is a small shadow-eval engine; `adapters/loa_cheval/metering/` is typed-config-over-YAML. The Progen upgrade costs ~2-3 sprints and removes a class of defects that v1 would accept at runtime.

**Core shift**: a calibration is a **typed value of a schema**, not raw YAML. The schema compiles to typed bindings in each language we use (Python, bash, TypeScript). Ill-formed calibrations fail at compile time, not runtime.

## Motivation (unchanged)

Three recent issues (#553, #554, #555) filed in a single 2-hour window trace a "calibration seam": Loa idioms were designed against Claude behaviors that have since shifted under Opus 4.7. Without a pack mechanism, updating idioms for a new model means either a Loa major bump or scattered if/else. A calibration pack expresses "posture for model X" as data. Multiple calibrations coexist. Switching is one config line. Release cadences decouple.

## Architecture — Schema-First + Codegen

```
.claude/schemas/
  calibration.yaml               ← Type definition (source of truth, YAML-as-schema)

.claude/scripts/
  gen-calibration-bindings.sh    ← protoc-like compiler (YAML-authored, bash-runnable)

.claude/generated/               ← All artifacts are DO-NOT-EDIT
  calibration_schema.json        ← JSON Schema (editor autocomplete)
  calibration.py                 ← Typed Python dataclasses
  calibration-accessors.sh       ← Bash getters (per field, safely sourced)
  calibration-lints.jq           ← jq programs for each verify rule
  calibration-docs.md            ← Auto-generated field documentation

.loa/constructs/packs/model-calibrations/  ← Pack (contains instances)
  manifest.json
  calibrations/
    claude-opus-4-7.yaml         ← Typed against the schema
    claude-sonnet-4-6.yaml
    gemini-2.5-pro.yaml
  goldens/                        ← Canonical task/output pairs per calibration
    claude-opus-4-7/
      task-001-write-prd/
        prompt.md
        expected.md
        rubric.yaml
  skills/
    calibrate/                    ← /loa calibrate <id>
    audit-calibration/            ← /loa audit-calibration
```

## Five FAANG Patterns

### P1. Schema + codegen (Progen / protoc)

The calibration schema is authored once. It compiles to N language bindings. Downstream code imports typed values, not dicts. Same pattern as Google's Progen, Meta's Thrift, Netflix's Genie.

**Shape (YAML-as-schema, protobuf-inspired field numbering)**:

```yaml
# .claude/schemas/calibration.yaml
schema_version: 1
message: Calibration
fields:
  - { num: 1,  name: calibration_id,    type: string,  required: true }
  - { num: 2,  name: model_family,      type: string,  required: true }
  - { num: 3,  name: effective,         type: iso_date }
  - { num: 4,  name: last_verified,     type: iso_date }
  - { num: 5,  name: sources,           type: repeated_string }

  - { num: 10, name: interview,         type: InterviewPosture }
  - { num: 11, name: subagents,         type: SubagentPosture }
  - { num: 12, name: thinking,          type: ThinkingPosture }
  - { num: 13, name: effort,            type: EffortPosture }
  - { num: 14, name: rule_phrasing,     type: RulePhrasing }
  - { num: 15, name: tool_calling,      type: ToolCallingPosture }

  - { num: 30, name: known_antipatterns, type: "repeated<Antipattern>" }
  - { num: 31, name: verify,             type: VerifySpec }

  - { num: 50, name: calibration_hash,   type: sha256 }
  - { num: 51, name: signed_by,          type: string, optional: true }
  - { num: 52, name: goldens,            type: GoldenCorpusRef }
```

**Why numbered fields**: structural backward compat (see D2 below). New fields land without breaking existing calibrations. Deprecated fields are marked, not deleted. This is how Google's RPC surface survives 20+ years of evolution.

**Author-side realism**: we don't need actual `protoc` as a dependency. `gen-calibration-bindings.sh` reads the YAML-authored schema and emits the bindings. Same pattern as `gen-adapter-maps.sh` we already ship — just over a richer schema.

### P2. Golden corpus (Google, Meta)

Every calibration ships with a canonical task set — prompts paired with expected outputs and a rubric for "did the calibrated skill produce the expected shape?" Applying a calibration becomes **"skills pass this calibration's goldens."** Regression detection is structural, not ad-hoc.

**Shape**:

```
goldens/claude-opus-4-7/task-001-write-prd/
  prompt.md                      # Input: the user's /plan-and-analyze prompt
  expected.md                    # Output: a PRD that would satisfy the calibration
  rubric.yaml                    # Grading: which sections must be present, token budget, etc.
```

**Hermetic runner**: a `.claude/scripts/run-goldens.sh <calibration_id>` fires each prompt through the calibrated pipeline, grades the output, emits pass/fail. Borrowed from Google's "goldens" testing pattern and Meta's model-card validation.

**Bootstrap**: when a calibration is authored, operator invokes `/loa calibrate --build-goldens <id>` which runs the canonical tasks through the current skill stack and captures the output as the expected. Future runs grade against that baseline.

### P3. Shadow evaluation via Flatline (Meta Gatekeeper, Netflix Dark Canary)

Before fully switching a project to a new calibration, **shadow-evaluate** it: run a representative sprint through the candidate calibration in parallel with the active one. Compare outputs via Flatline. Surface divergence; operator accepts or rejects.

**Use of existing primitive**: Flatline Protocol is already a multi-model adversarial evaluator. A shadow eval is Flatline configured to:
- **Model A** = your active calibration's primary
- **Model B** = the candidate calibration's primary
- Run both on the same diff, score divergence, emit consensus or disagreement

No new engine needed. A wrapper script (`calibration-shadow-eval.sh`) routes the invocation.

**Gate**: `/loa calibrate --apply <id> --require-shadow-pass` refuses the swap if shadow eval shows >N% divergence on the golden corpus. Operator can `--force` with a logged reason.

### P4. Provenance + content hash (SLSA, Sigstore)

Every calibration carries a content hash computed from its canonical serialization (schema forces deterministic ordering). `calibration_hash:abc123def` pinnable in `.loa.config.yaml`:

```yaml
model_calibration:
  active: claude-opus-4-7
  pinned_hash: sha256:a3f2b1...       # byte-identical behavior across sessions
```

Optional Sigstore signing lets operators require calibrations signed by a trusted identity before application. Defense against supply-chain tampering on the pack itself.

**Reproducibility property**: given `(schema@version, calibration_id, calibration_hash)`, the full posture applied to skills is deterministic and verifiable. Operators running the same triple on different machines get identical behavior.

### P5. Telemetry tagging (all of them)

Every skill invocation logs `active_calibration_id + calibration_hash` to trajectory. Quality metrics (review findings by severity, audit severity, cost per phase) bucket by calibration. Answers questions empirically:

- "Did switching from Sonnet 4.5 to Sonnet 4.6 calibration regress review quality?"
- "Is the Opus 4.7 calibration's batch-interview posture actually faster than 4.6's sequential?"
- "Which known_antipattern fired most often in the last 100 cycles?"

**Existing primitive**: trajectory JSONL at `grimoires/loa/a2a/trajectory/`. New skill wrappers emit the calibration tag; downstream queries bucket.

## Revised Three Decisions

### D1: Pack location

**v1**: bundled in core for simplicity.
**v2**: **schema in core, calibrations as pack (mixed location c).**

Rationale: schema evolution is rare and coordinated (like protobuf releases) — belongs in core, versioned with Loa. Calibration instances churn with model releases — belong in a pack that can evolve independently. The `.claude/schemas/calibration.yaml` ships with Loa; `.loa/constructs/packs/model-calibrations/` is downloadable.

**v1's rationale still holds** for MVP: bundle the pack initially alongside the schema. Satellite split is a later move if cadence diverges. But the schema/instance separation is baked in from day 1 — we don't have to migrate later.

### D2: Schema versioning

**v1**: independent `schema_version` field.
**v2**: **protobuf-style field numbers + deprecation markers. Keep `schema_version` as the human-readable tag.**

Rationale: numbered fields give structural backward compat. `schema_version: 1` becomes a human pointer to the set of field numbers considered "stable." `schema_version: 2` adds fields without breaking v1 readers; deprecates fields without deleting them. Same discipline protobuf uses to keep gRPC APIs forward/backward compatible.

Operators pin `schema_version: 1` for determinism; Loa maintainers add v2 fields freely; migration is a well-defined operation (rename field X number N, add `deprecated: true`, add replacement field at new number).

### D3: Re-calibration trigger

**v1**: manual only.
**v2**: **manual + opt-in shadow-eval gate.**

Rationale: manual is still the baseline — operator deliberately applies calibrations, trust-boundary reasoning. Shadow eval adds optionality: `/loa calibrate --apply <id> --require-shadow-pass` runs the golden corpus through shadow Flatline and refuses the swap on high divergence. Operator can `--force` with logged reason (telemetry captures the override for later analysis).

No auto-detection of vendor releases — that infrastructure still doesn't exist. Manual remains the trigger; shadow eval is the safety net.

## MVP Scope

**Sprint 1** (schema + codegen skeleton, mirrors `gen-adapter-maps.sh`):
- `.claude/schemas/calibration.yaml` (YAML-authored schema; proto-shape)
- `.claude/scripts/gen-calibration-bindings.sh` (emit Python + bash + JSON Schema)
- `.claude/generated/calibration_schema.json`, `calibration-accessors.sh`
- BATS tests: schema compiles, bindings resolve canonical calibrations

**Sprint 2** (golden corpus + hermetic runner):
- `goldens/claude-opus-4-7/` with 3-5 canonical tasks
- `.claude/scripts/run-goldens.sh <calibration_id>`
- Emits pass/fail + divergence metrics
- Wire into `/loa audit-calibration`

**Sprint 3** (shadow eval + telemetry + provenance):
- `calibration-shadow-eval.sh` wrapper around Flatline
- `/loa calibrate --apply <id> [--require-shadow-pass] [--force]`
- Trajectory tagging with `active_calibration_id + calibration_hash`
- Content-hash computation + `pinned_hash` config key

**Out of MVP (Phase 2)**:
- Sigstore signing
- Auto-vendor-release detection
- Per-skill calibration overrides
- Lens authoring patterns

## Composition with Existing Loa Primitives

| Existing | Role in Progen-style calibration |
|----------|-----------------------------------|
| `gen-adapter-maps.sh` (PR #566) | Template for `gen-calibration-bindings.sh`. Same pattern, richer schema. |
| `flatline-orchestrator.sh` | Reused as shadow-eval engine via wrapper. No new model-plumbing. |
| `adapters/loa_cheval/metering/pricing.py` | Example of typed Python over YAML. Calibration bindings follow same pattern. |
| Trajectory JSONL | Telemetry substrate; skill wrappers add `calibration_id` tag. |
| BATS suite | Hermetic testing for codegen + golden corpus runners. |
| `validate_model_registry()` | Model used: runtime consistency check. Calibration gets an analogous `validate_calibration()` that checks schema + goldens + hash on load. |
| `.claude/rules/skill-invariants.md` | Invariant pattern. Calibrations augment with posture-specific invariants (interview mode, fork rationale, etc.) |

## Non-Goals

- Replace `.claude/rules/` — rules are prose invariants; calibrations are structured posture. Orthogonal.
- Runtime schema changes — schema evolves deliberately, field numbers assigned, deprecations land.
- Per-operator calibration authoring — MVP ships the bundled pack; bring-your-own-calibration is a Phase 2 consideration.
- Block-merge gate on calibration mismatch — `/update-loa` can warn, not refuse (conservative).

## Open Questions

- Should the schema be authored in protobuf, CUE, JSON Schema, or YAML-that-we-treat-as-schema? Leaning **YAML-as-schema** (matches Loa's existing idiom; avoids new deps); open to protobuf if it earns its weight in downstream toolchain integration.
- Does `calibration_hash` go over canonical YAML or canonical JSON? Leaning **canonical JSON** (existing `jq -S` gives deterministic order).
- Pack distribution format — single zipped tarball, or directory synced via git subtree? Leaning **git subtree** (fits existing Loa/construct-pack patterns).

## Roadmap vs v1

| Dimension | v1 | v2 (this RFC) |
|-----------|-----|---------------|
| Source of truth | YAML instance | Schema definition |
| Compile-time checking | None | JSON Schema + typed bindings |
| Regression detection | Lint scanner | Golden corpus |
| Pre-apply validation | None | Shadow eval via Flatline |
| Reproducibility | Operator trust | Content hash + optional signature |
| Telemetry | None | Skill tag + trajectory bucketing |
| Effort | 1 sprint | 3 sprints |
| Technical debt for model #4 | Lower than no-pack | Near zero — schema already handles evolution |

## Ask

Maintainer review of the three revised decisions (D1 mixed-location, D2 protobuf-style versioning, D3 manual + shadow-eval gate) and the five FAANG-patterns list. On approval, Sprint 1 (schema + codegen skeleton) is a standard `/bug` or `/plan` sprint — mechanical, template-able from `gen-adapter-maps.sh`.

If any pattern is too ambitious for MVP, say which and I reshape the scope. Sprint 1 alone delivers the core value (schema-first, typed bindings); Sprints 2-3 are additive.

## References

- Source issue: [#556](https://github.com/0xHoneyJar/loa/issues/556)
- Meta tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557)
- Closed v1: PR #572 (for historical context — design path)
- Substrate we build on: PR #566 (`gen-adapter-maps.sh`), PR #571 (legacy adapter swap)
- Adjacent: [#553](https://github.com/0xHoneyJar/loa/issues/553), [#554](https://github.com/0xHoneyJar/loa/issues/554), [#555](https://github.com/0xHoneyJar/loa/issues/555) — the "calibration seam" filing window
- Anthropic Opus 4.7 + Claude Code blog: [link](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- Design lineage: Google Progen, Protocol Buffers, Meta Thrift, Netflix Genie, SLSA (supply-chain), Sigstore (signing), Bazel (hermetic builds), Google's "goldens" testing pattern
