# RFC-061: Polycentric Model-Calibration Pack (v3, Flatline-addressed)

**Status**: Draft (supersedes v1 closed #572, v2 closed #580)
**Tracker**: [#556](https://github.com/0xHoneyJar/loa/issues/556)
**Meta tracker**: [#557](https://github.com/0xHoneyJar/loa/issues/557) (Tier 3)
**Author**: Agent (proposal for maintainer review)
**Date**: 2026-04-18
**Review provenance**: Flatline 3-model adversarial review on v2 surfaced 9 BLOCKERs + 6 HIGH_CONSENSUS at 100% agreement / full confidence. v3 addresses all 15.

---

## What v3 fixes vs v2

v2 borrowed patterns from deterministic-software lineage (Google Progen, SLSA, Bazel) without adapting for LLM-specific reality. Flatline flagged 5 structural issues:

| # | v2 flaw | Flatline ref | v3 fix |
|---|---------|--------------|--------|
| 1 | "Reinvented protobuf poorly" via custom YAML-as-schema | SKP-001×2, IMP-001 | **Drop custom DSL. Use JSON Schema** (draft-07) as authoring surface. Validate with ajv at load time. |
| 2 | Golden corpus assumed exact-match on LLM output | SKP-002×2, SKP-004, IMP-005 | **Rubric-based LLM-as-judge scoring** with semantic-equivalence tolerance. Bootstrap from a pinned reference calibration, not current production. |
| 3 | "Compile-time safety" overstated for bash/YAML runtime | SKP-002-dup, SKP-003 | Renamed throughout: **load-time validation**, not compile-time. Bash accessors generated with strict quoting + explicit untrusted-input posture. |
| 4 | Supply-chain deferred to Phase 2 while MVP ships packs | SKP-007 | **Minimal SHA256 verification is MVP-required**. Sigstore remains Phase 2 but mandatory-hash is not. |
| 5 | Claims without specification (canonicalization, threshold, migration) | IMP-002/003/004, SKP-005, SKP-006 | Normative specs added inline (§§ below). |

## Architecture (v3)

```
.claude/schemas/
  calibration.schema.json        ← JSON Schema (draft-07), authored & versioned

.claude/scripts/
  gen-calibration-bindings.sh    ← emits typed Python + JSON + bash-safe getters from schema

.claude/generated/               ← DO-NOT-EDIT artifacts
  calibration.py                 ← pydantic-validated dataclasses (runtime-checked via ajv equivalent)
  calibration-getters.sh         ← bash getters using `jq -r` + explicit escaping
  calibration-lints.jq           ← jq programs for verify rules
  calibration-docs.md            ← auto-generated from schema $comment fields

.loa/constructs/packs/model-calibrations/
  manifest.json                  ← includes pack_sha256, required_schema_version
  calibrations/
    claude-opus-4-7.json         ← JSON (not YAML) for canonical hashing
    claude-sonnet-4-6.json
  goldens/
    claude-opus-4-7/
      task-001/
        prompt.md
        reference_output.md      ← not "expected", reference (see §Golden Semantics)
        rubric.json              ← judge criteria, not regex assertions
  skills/
    calibrate/
    audit-calibration/
```

## The Five Patterns (v3 form)

### P1. Schema + codegen via JSON Schema

**Was**: custom YAML-as-schema.
**Is**: **JSON Schema draft-07** as authoring surface. Existing standard, mature tooling, ajv/jsonschema validators available in every language we use.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://loa.sh/schemas/calibration.v1.json",
  "title": "Calibration",
  "type": "object",
  "properties": {
    "schema_version": {"const": 1},
    "calibration_id":  {"type": "string", "pattern": "^[a-z0-9-]+$"},
    "model_family":    {"type": "string", "enum": ["anthropic", "openai", "google"]},
    "effective":       {"type": "string", "format": "date"},
    "interview":       {"$ref": "#/definitions/InterviewPosture"},
    "known_antipatterns": {
      "type": "array",
      "items": {"$ref": "#/definitions/Antipattern"}
    },
    "calibration_hash": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"}
  },
  "required": ["schema_version", "calibration_id", "model_family", "calibration_hash"]
}
```

Python consumes via `jsonschema.validate(instance, schema)` at load time. Bash consumes via generated getters that `jq -r` the validated instance — never source untrusted content. TypeScript gets types via `json-schema-to-typescript`.

**Load-time validation, not compile-time.** The schema ensures: required fields present, types correct, enum values within allowed set, regex patterns match. Ill-formed instances fail at `/loa calibrate --apply` or `--audit-calibration` — not at some theoretical compile step.

### P2. Golden corpus with stochastic-tolerant semantics

**Was**: "skills pass this calibration's goldens" — implicit exact-match.
**Is**: **rubric-based scoring with LLM-as-judge.** Two modes:

- **Structural rubric** (deterministic, fast): must-have sections, token budget, valid JSON/YAML, required field names. jq predicates over parseable output.
- **Semantic rubric** (LLM-graded, slower): "did the PRD cover the stated goals?" graded by a separate judge model (Opus) with a scoring prompt. Pass threshold operator-configurable (default 7/10).

```yaml
# goldens/claude-opus-4-7/task-001/rubric.json
{
  "structural": {
    "must_contain_sections": ["Goals", "Acceptance Criteria", "Risks"],
    "max_token_count": 4000,
    "min_token_count": 800
  },
  "semantic": {
    "judge_model": "opus",
    "criteria": [
      "Goals are measurable (specific numeric / observable outcomes)",
      "Acceptance criteria are testable (each has a clear pass condition)",
      "Assumptions are explicit (not implied)"
    ],
    "pass_threshold": 7
  }
}
```

**Bootstrap strategy**: the **first** calibration's goldens are authored by a human reviewer, not captured from current production. Subsequent calibrations can bootstrap goldens via diff against a pinned reference calibration (explicitly documented as "regression baseline" — no blind institutionalization).

**Stochasticity tolerance**: each golden evaluates pass-rate over N invocations (default N=3, operator-configurable). A golden "passes" if ≥⌈2N/3⌉ pass the rubric. Pins a floor for consistency without requiring determinism.

### P3. Shadow evaluation with specified threshold

**Was**: `--require-shadow-pass` refuses swap on ">N% divergence."
**Is**: divergence defined normatively as **golden-corpus pass-rate delta**:

```
divergence = pass_rate(active_calibration) − pass_rate(candidate_calibration)
```

Computed over the candidate's full golden corpus. Operator-configurable threshold (default: refuse swap if divergence > 0.15 i.e. candidate passes 15 percentage points fewer goldens than active). Explicit `--force` with logged reason allows override.

Routes through Flatline for the judge-model calls — existing primitive, no new model-plumbing.

### P4. Provenance with specified canonicalization

**Was**: `calibration_hash` pinnable.
**Is**: `calibration_hash` computed over **RFC 8785 JSON Canonicalization Scheme (JCS)** output of the calibration instance, excluding the hash field itself. Normative spec:

```python
def compute_hash(calibration: dict) -> str:
    # Per RFC 8785:
    # - Remove the `calibration_hash` field (self-referential)
    # - Canonicalize keys (sort, UTF-8, lowercase hex escapes)
    # - Strip whitespace
    canonical = rfc8785.canonicalize({k: v for k, v in calibration.items() if k != "calibration_hash"})
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
```

**Mandatory-hash is MVP** (closes SKP-007 gap): `/loa calibrate --apply` refuses to load a calibration whose stored `calibration_hash` doesn't match computed-hash. Prevents accidental tampering without requiring Sigstore.

**Optional Sigstore** signing remains Phase 2.

**Pinning**:

```yaml
model_calibration:
  active: claude-opus-4-7
  pinned_hash: sha256:a3f2b1...  # must match computed-hash of active calibration
```

Operators running identical (schema_version, calibration_id, pinned_hash) across machines get identical behavior at the configuration layer. Vendor nondeterminism (SKP-005) is explicitly **not** claimed — the hash covers calibration CONTENT, not OUTPUTS. Downstream goldens + shadow eval handle model drift empirically.

### P5. Telemetry tagging (unchanged from v2)

Skill wrappers log `active_calibration_id + calibration_hash` to trajectory. Quality metrics (review severity, audit severity, cost per phase, golden pass-rate) bucket by calibration. Uses existing trajectory JSONL infra.

## Decisions (v3)

| Decision | v3 |
|----------|-----|
| **D1 Location** | Schema in `.claude/schemas/` (core); calibrations in `.loa/constructs/packs/model-calibrations/` (pack). Schema evolves with Loa releases; calibrations ship independently via pack registry. |
| **D2 Versioning** | JSON Schema `$id` URL carries version (`calibration.v1.json`). Compat contract: **writers may add optional fields freely**; **removing or changing the type of a field requires a version bump AND retention of old field as deprecated for ≥2 Loa minor cycles**. Migration rules specified inline in schema change log. |
| **D3 Trigger** | Manual via `/loa calibrate --apply <id>`. Opt-in shadow-eval gate via `--require-shadow-pass`. Mandatory hash verification in all paths (MVP requirement). |

## Schema/Instance Compat Contract (closes SKP-006, IMP-004)

| Change class | Permitted without version bump? | Reader behavior |
|--------------|----------------------------------|-----------------|
| Add optional field | ✓ | v1 readers ignore |
| Add required field with a default in the schema | ✓ | v1 readers ignore; downstream defaults apply |
| Add required field WITHOUT default | ✗ — requires major bump | — |
| Remove field | ✗ — requires major bump; field stays as `deprecated: true` for 2 minor cycles | v1 readers warn on deprecated, refuse after 2 cycles |
| Change field type | ✗ — requires major bump | — |
| Tighten enum values | ✗ — requires major bump | — |
| Loosen enum values (add value) | ✓ | v1 readers may encounter unknown values; schema says how to handle (reject, passthrough, warn — specified per field) |

Explicit rule: if a pack's `required_schema_version` > local Loa's `schema_version`, `/loa calibrate --apply` **refuses** with message pointing at the needed upgrade.

## Failure Semantics (closes IMP-007)

Explicit on each failure path:

| Failure | Behavior | Error exit |
|---------|----------|-----------|
| Schema validation fails | Refuse apply; stderr lists failing JSON pointers | 10 |
| Hash mismatch on `pinned_hash` | Refuse apply; print "Pinned hash doesn't match computed. Pack may have been tampered with, or pin is stale." | 11 |
| Schema version skew (pack > local) | Refuse apply; print "Pack needs Loa ≥ $minimum_version. Run /update-loa." | 12 |
| Golden run fails (structural) | Emit finding, mark calibration `status: failing_goldens`; downstream `audit-calibration` reports | 0 (soft) |
| Golden run fails (semantic judge unavailable) | Skip semantic checks, emit WARN, fall through to structural-only | 0 (soft) |
| Shadow eval unavailable (Flatline down) | `--require-shadow-pass` refuses apply; `--force` allows with logged reason | 13 without force, 0 with |
| Calibration file missing from pack | Refuse apply; print available calibrations in the pack | 14 |

## MVP Scope (revised)

**Sprint 1 — Schema + validation**:
- `.claude/schemas/calibration.schema.json` (JSON Schema draft-07)
- `.claude/scripts/gen-calibration-bindings.sh` (emits Python dataclasses, bash getters, TS types)
- `validate_calibration()` function + hash verification
- BATS + pytest: schema validates canonical instances; invalid instances fail with JSON Pointer locations

**Sprint 2 — Pack + hash + apply**:
- `.loa/constructs/packs/model-calibrations/` skeleton with claude-opus-4-7 seed
- `/loa calibrate list` / `/loa calibrate --apply <id>` with hash verification
- `.loa.config.yaml` keys: `model_calibration.active`, `model_calibration.pinned_hash`
- Telemetry tagging on skill invocations

**Sprint 3 — Goldens + shadow eval**:
- `goldens/claude-opus-4-7/` with 3-5 canonical tasks
- `.claude/scripts/run-goldens.sh <calibration_id>` (structural + semantic rubrics)
- `calibration-shadow-eval.sh` wrapper around Flatline
- `/loa calibrate --apply <id> --require-shadow-pass`
- `/loa audit-calibration` (dry-run against active)

**Phase 2 (post-MVP)**:
- Sigstore signing
- Auto-vendor-release detection
- Per-skill calibration overrides
- Golden authoring tooling (bootstrap from reference + diff visualization)
- Pack registry for third-party calibrations

## Non-Goals

- Replace `.claude/rules/` prose invariants
- Block merge on calibration mismatch (warn in `/update-loa`, don't refuse)
- Sandbox untrusted pack content (beyond hash + MVP posture of "don't source raw YAML as bash")
- Auto-detect vendor model releases (Phase 2+)

## Anti-Patterns Cited by Flatline, Not Introduced in v3

- ❌ Custom DSL for schema → use JSON Schema
- ❌ Exact-match golden eval on prose → rubric-based with stochastic tolerance
- ❌ "Compile-time" claims over bash/YAML runtime → load-time validation
- ❌ Unbounded bash-sourced artifacts → `jq -r` + explicit escaping in generated getters, never `source` pack content
- ❌ Handwavy "N% divergence" → normative pass-rate delta with default threshold 0.15
- ❌ Deferred supply-chain while MVP ships packs → mandatory SHA256 verification in MVP
- ❌ Claims of reproducibility that conflate content-hash with output-determinism → hash explicitly scoped to content

## Ask

Maintainer review of the decisions, compat contract, failure semantics, and sprint breakdown. The v3 doc is honest about limits (stochastic model output, load-time-not-compile-time, content-hash-not-output-determinism) and explicit about claims (canonicalization via RFC 8785, pass-rate delta metric, migration rules).

If any pattern is still too ambitious for MVP, say which. Sprint 1 alone delivers core value (schema + validated bindings + hash verification). Sprints 2-3 are additive.

## References

- Source issue: [#556](https://github.com/0xHoneyJar/loa/issues/556)
- Meta tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557)
- Closed v1: PR #572 (YAML-instance-first)
- Closed v2: PR #580 (Progen-framed, missed LLM-stochastic realities)
- Flatline review on v2: `/tmp/flatline-rfc61v2.json` — 9 BLOCKER + 6 HIGH_CONSENSUS, 100% agreement
- Substrate: PR #566 (gen-adapter-maps.sh template), PR #571 (legacy adapter swap)
- Design standards: JSON Schema draft-07, RFC 8785 (JCS), SWE-bench/HumanEval rubric patterns, SLSA supply-chain levels
