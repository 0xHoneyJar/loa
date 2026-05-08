# Product Requirements Document: Adversarial Jailbreak Corpus

**Cycle:** `cycle-100-jailbreak-corpus` *(actual ID confirmed at `/sprint-plan` time; cycle-099-model-registry remains active in parallel)*

**Version:** 1.0
**Date:** 2026-05-08
**Author:** PRD Architect (deep-name + Claude Opus 4.7 1M)
**Status:** Draft — awaiting `/architect`

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

Cycle-098 shipped the L1-L7 agent-network primitives with layered prompt-injection defense (Layer 1 pattern detection, Layer 2 structural sanitization, Layer 3 policy engine). **Layer 4 — an empirical adversarial test corpus that falsifies those defenses — was deferred** (Sprint 7D carved out per cycle-098 RESUMPTION.md:26 because "the corpus is qualitatively different work (security research + curation, not engineering)"). Without Layer 4, every claim about L6/L7 SessionStart sanitization being effective is unfalsified.

Cycle-100 closes that gap by shipping (1) a curated corpus of documented attack vectors at `tests/red-team/jailbreak/`, (2) a bats + pytest runner that exercises each vector against the existing `sanitize_for_session_start` lib, and (3) a GitHub Actions CI gate that blocks any PR touching `prompt_isolation` / L6 / L7 / SessionStart hooks until the suite passes.

The cycle adopts a **registry-driven JSONL vector catalog** (lifted from `dcg`, `ubs`, `testing-fuzzing` patterns), **exit-code-disciplined CI enforcement**, and a **multi-pass runner organization** (lifted from `multi-pass-bug-hunting`). Layer 5 tool-call-resolver, Bridgebuilder-feedback append-handler skill, and production telemetry are explicitly deferred to cycle-101+ to keep this cycle bounded.

---

## Problem Statement

### The Problem

The L6/L7 SessionStart hooks surface untrusted operator-and-downstream-authored content into agent context. Cycle-098 layered three defenses (Layer 1 pattern detection, Layer 2 structural sanitization wrapping in `<untrusted-content>`, Layer 3 policy engine via per-source rules) — but with no empirical adversarial test, the defenses are unfalsified. A novel vector that bypasses sanitization today would only be discovered after it landed in production agent context.

> From cycle-098 sdd.md:944-957 §1.9.3.2: "Layer 4 — Adversarial test corpus (Sprint 7): Red-team test corpus at `tests/red-team/prompt-injection/` with 50+ documented attack vectors (role-switch, tool-call exfiltration, credential leakage, indirect prompt injection via Markdown links, Unicode obfuscation, encoded payloads). Sprint 7 ships corpus; CI runs it on every change to L6/L7 + `prompt_isolation` lib."

> From cycle-098 sdd.md:967 §1.9.3.2 Layer 5: "Automated jailbreak CI suite — `tests/red-team/jailbreak/` with attack corpus: role-switch, indirect injection via Markdown, Unicode obfuscation, encoded payloads, **multi-turn conditioning**. CI gate: every PR touching `prompt_isolation`, L6, L7, or SessionStart hook MUST pass jailbreak suite. New attacks added by Bridgebuilder reviews appended to corpus."

The Opus 740 Flatline finding specifically called out that Layer 5's "first N turns" heuristic is defeated by **multi-turn conditioning** attacks; static-body sanitization tests are insufficient.

### User Pain Points

- **Maintainer**: "I want to refactor `sanitize_for_session_start`, but I have no regression test that proves the refactor preserves all the defenses cycle-098's cypherpunk reviewers found."
- **Cycle-098 cypherpunk subagent**: "I caught NFKC bypass (HIGH-2), control-byte heading (HIGH-4), and INDEX row-injection (E6 PoC) inline — but those were found in a single review pass and may not be exhaustive."
- **Future cycle (101+)**: "I'm landing a new SessionStart hook integration. Does it preserve defenses?" Today: no answer. Tomorrow: green CI gate or red CI gate, citing the specific vector that broke.
- **Downstream operator forking Loa**: "Has Loa been red-teamed against published prompt-injection corpora?" Today: implicit "yes by some reviewers", no audit trail. Tomorrow: a registry of named vectors with expected outcomes.

### Current State

- Layer 1 + Layer 2 + Layer 3 defenses ship at `lib/context-isolation-lib.sh::sanitize_for_session_start` and the L6 / L7 SessionStart hooks.
- L6 sprint 6E E4-E6 / C9-C10 introduced runtime-construction `_make_evil_body` pattern for bats fixtures (keeps adversarial trigger strings out of source files where they could spuriously match grep / bridgebuilder reviewers).
- Cycle-098 cypherpunk subagent reviews caught defects ad-hoc; PoCs exist in test E6 (INDEX injection) and HIGH-2 (NFKC bypass) but are **scattered across sprint-specific bats files**, not consolidated into a regression corpus.
- `tests/red-team/` directory does not exist yet (`ls tests/red-team/ 2>/dev/null` → empty).
- CI runs the existing bats + pytest suites on every PR, but no gate specifically guards `prompt_isolation` / L6 / L7 / SessionStart paths.

### Desired State

- A curated, append-friendly corpus at `tests/red-team/jailbreak/` holds 50-100 documented attack vectors in JSONL form. Each entry has stable id (e.g. `RT-RS-001`), category, title, payload-construction recipe, expected sanitization outcome, defense-layer-probed, and source citation.
- A bats + pytest runner exercises each vector against `sanitize_for_session_start` and the L6/L7 SessionStart hooks; multi-turn vectors run via a thin Python replay harness over a list-of-messages fixture.
- A GitHub Actions workflow gates PRs that modify `prompt_isolation` / L6 / L7 / SessionStart paths: any failing vector blocks merge.
- Suppression discipline (UBS pattern): excluded vectors carry mandatory justification text; running with no suppressions is the default.
- Audit trail: each runner invocation appends a JSONL summary (vector id → status → reason) to `.run/jailbreak-run-{date}.jsonl` for replay analysis.

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Ship a defensible-per-vector corpus covering the categories named in cycle-098 sdd.md:953,967 | Corpus contains ≥50 vectors (SDD floor); each vector has a paragraph-or-better justification surviving cypherpunk per-vector pushback review | Cypherpunk subagent reviews each vector; cycle exit gate fails if any vector lacks justification |
| G-2 | Wire CI gate that blocks PRs touching `prompt_isolation` / L6 / L7 / SessionStart hooks until the corpus passes | GitHub Actions workflow with `paths:` filter triggers on every relevant PR; failing run sets PR check status to red | Smoke-test PR introducing a deliberate sanitization regression — must be blocked |
| G-3 | Multi-turn replay harness validates Opus 740 finding's class of attack | Multi-turn vectors (≥10) execute against a session-replay simulation; multi-turn-conditioning attempts that bypass first-N-turn heuristic fail closed | Synthetic multi-turn vector with confirmed first-N-turn bypass produces RED status |
| G-4 | Corpus is **append-friendly** for future Bridgebuilder-discovered vectors | Schema is stable + documented + JSONL one-line-per-vector; new entries land via simple PR (no schema migration) | Operator authors a novel vector by hand following docs in <10 minutes; runner picks it up automatically |
| G-5 | Audit trail exists for every cycle-100 runner invocation | `.run/jailbreak-run-{date}.jsonl` records every vector × every run; pass/fail/suppressed status structured + queryable | `jq` query selecting "vectors that have ever been suppressed" returns expected entries |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Documented adversarial vectors | 0 (scattered PoCs in sprint-specific bats files) | 50 minimum, ~100 aspiration per RESUMPTION quality bar | cycle-100 ship | G-1 |
| Vector-categories covered (per sdd.md:953,967 + Opus 740) | 0 | 6 (role-switch, tool-call exfiltration, credential leakage, Markdown indirect, Unicode obfuscation, encoded payloads) + 1 (multi-turn conditioning) = 7 | cycle-100 ship | G-1 |
| CI gate enforcement on touched paths | Manual review only | Automated; PR check status reflects suite result | cycle-100 ship | G-2 |
| Multi-turn replay vectors | 0 | ≥10 | cycle-100 ship | G-3 |
| Vectors with full schema (id + category + title + payload + expected_outcome + defense_layer + source_citation) | 0 | 100% of shipped vectors | cycle-100 ship | G-4 |
| Audit-log fields per run | 0 | ≥6 (vector_id, status, reason, run_id, timestamp, defense_layer) | cycle-100 ship | G-5 |

### Constraints

- **No new external dependencies** beyond what cycle-098 already brought in (bats 1.10+, pytest 8.x, python 3.11+, `cryptography` 42+, `yq` 4+, `jq` 1.6+).
- **Vectors must be shippable as text in repository** — no remote-fetched content, no third-party API calls during corpus runs (R-Net dependency hostility).
- **Adversarial trigger strings must NOT appear verbatim in source files** outside the corpus directory — runtime construction (`_make_evil_body`) keeps them out of bridgebuilder-review scans and false-positive grep hits (per L6 sprint 6E E4-E6 / C9-C10 idiom).
- **Cypherpunk-defensible per vector** — every shipped vector survives subagent paranoid-cypherpunk review of inclusion justification; vectors that fail review are dropped or revised, not shipped with weak rationale.

---

## User Personas & Use Cases

### Primary Persona: Loa Framework Maintainer

**Demographics:**
- Role: Loa repository maintainer; touches `lib/context-isolation-lib.sh`, L6/L7 SKILL.md + lib + hook, `prompt_isolation`, SessionStart hooks routinely
- Technical Proficiency: Senior — bash/python/CI fluent; familiar with cycle-098 layered defense model
- Goals: Refactor / extend defenses without regressions; trust CI as the regression oracle

**Behaviors:**
- Authors PRs that modify `lib/context-isolation-lib.sh` or hook scripts ~weekly
- Reviews cypherpunk-subagent findings inline before merge
- Curates lore (`.claude/data/lore/agent-network/`) when new patterns are discovered

**Pain Points:**
- Today: "Did my refactor preserve the NFKC bypass defense?" → only answerable by re-running the cycle-098-sprint-7 review thread, which is ad-hoc.
- Today: "Where are the adversarial PoCs documented?" → scattered across cycle-098 sprint-specific bats files; no central index.

### Secondary Persona: Future-Cycle Author

**Demographics:**
- Role: Author of cycle-101+ work (e.g., Layer 5 tool-call-resolver, additional SessionStart sources)
- Technical Proficiency: Equivalent to maintainer; opens PRs touching the surfacing path

**Pain Points:**
- "I'm adding a new untrusted source to SessionStart. Did I miss a defense layer?" → corpus answers definitively.
- "I need to extend the corpus with a new vector class." → schema is stable, append is safe.

### Tertiary Persona: Downstream Operator (Loa Fork)

**Demographics:**
- Role: Operator running Loa in their own org; may fork or upstream contribute
- Technical Proficiency: Bash + python comfortable; prompt-injection naive

**Pain Points:**
- "Has Loa been red-teamed?" → corpus is the auditable answer.
- "How do I add my own attack vectors?" → docs + schema enable extension.

### Use Cases

#### UC-1: Maintainer refactors `sanitize_for_session_start`

**Actor:** Loa Framework Maintainer
**Preconditions:** PR opens modifying `lib/context-isolation-lib.sh`; cycle-100 corpus + CI gate are live.
**Flow:**
1. Maintainer pushes branch with refactor.
2. GitHub Actions detects path match (`paths: ['lib/context-isolation-lib.sh', '.claude/hooks/session-start/**', '.claude/skills/structured-handoff/**', '.claude/skills/soul-identity-doc/**']`) and runs jailbreak workflow.
3. Workflow runs the bats + pytest corpus. Each vector → status (pass / fail / suppressed).
4. Workflow uploads `.run/jailbreak-run-*.jsonl` audit log as artifact.
5. PR status check reflects pass/fail.

**Postconditions:** PR is mergeable iff suite passes (or suppressed vectors carry justification reviewed by maintainer).
**Acceptance Criteria:**
- [ ] Workflow runs only on path-matched PRs (no full-suite cost on unrelated PRs)
- [ ] Failed vector produces output identifying vector_id + defense_layer + the assertion that broke
- [ ] Audit log artifact attached to workflow run

#### UC-2: Cypherpunk reviewer adds novel vector during cycle-101 review

**Actor:** Future-Cycle Author / cypherpunk subagent
**Preconditions:** Cycle-101 dual-review surfaces a novel attack the existing corpus does not cover.
**Flow:**
1. Reviewer authors new corpus entry following schema (one JSONL line + payload-construction recipe in companion bats fixture).
2. Reviewer adds runner test exercising the vector against current `sanitize_for_session_start`.
3. CI runs; the new vector's status reflects the current defense state (likely RED if it's a real bypass).
4. If RED: reviewer files / fixes the underlying defense in same PR or follow-up issue; vector lands GREEN once defense lands.

**Postconditions:** Corpus grows; new vector becomes a regression gate.
**Acceptance Criteria:**
- [ ] Vector authoring docs (corpus README) describe the schema clearly enough that a hand-author needs <10 min
- [ ] No schema migration required for normal vector additions
- [ ] Append-only: existing vectors are not edited, only deprecated (status: `superseded` with pointer to replacement)

#### UC-3: Operator audits Loa pre-fork

**Actor:** Downstream Operator
**Preconditions:** Operator clones Loa.
**Flow:**
1. Operator runs `bats tests/red-team/jailbreak/` and `pytest tests/red-team/jailbreak/`.
2. Output reports number of vectors, categories covered, sources cited.
3. Operator inspects `.run/jailbreak-run-*.jsonl` for a structured audit.

**Postconditions:** Operator has empirical evidence for Loa's prompt-injection defense surface.
**Acceptance Criteria:**
- [ ] Suite executes from a fresh clone with only documented dependencies
- [ ] Output includes vector counts grouped by category + source-of-vector citation

---

## Functional Requirements

### FR-1: Corpus Schema (JSONL + companion fixtures)

**Priority:** Must Have
**Description:** Each vector lives as one line in `tests/red-team/jailbreak/corpus/<category>.jsonl`. Stable schema:

```json
{
  "vector_id": "RT-RS-001",
  "category": "role_switch | tool_call_exfiltration | credential_leak | markdown_indirect | unicode_obfuscation | encoded_payload | multi_turn_conditioning",
  "title": "short human-readable name",
  "defense_layer": "L1 | L2 | L3 | L6 | L7 | multiple",
  "payload_construction": "fixture_function_name (companion bats / py file)",
  "expected_outcome": "redacted | rejected | wrapped | passed-through-unchanged",
  "source_citation": "OWASP-LLM-01 | DAN-vN | Anthropic-paper-Y | cycle-098-sprint-N-finding | in-house-cypherpunk",
  "severity": "CRITICAL | HIGH | MEDIUM | LOW",
  "status": "active | superseded | suppressed",
  "suppression_reason": "(required iff status=suppressed)"
}
```

**Acceptance Criteria:**
- [ ] JSON Schema at `.claude/data/trajectory-schemas/jailbreak-vector.schema.json` validates each line via `ajv` + python `jsonschema`
- [ ] Schema is `additionalProperties: false` to prevent silent drift
- [ ] `vector_id` regex is stable (`^RT-[A-Z]{2,3}-\d{3,4}$`); category prefix encodes attack class
- [ ] CI step asserts every JSONL line validates and `vector_id` is unique across the corpus
- [ ] Companion fixture functions (`_make_evil_body_*`) live in `tests/red-team/jailbreak/fixtures/<category>.{sh,py}`

**Dependencies:** existing `lib/context-isolation-lib.sh::sanitize_for_session_start`; cycle-098 audit-envelope schema validation pattern (`.claude/data/trajectory-schemas/agent-network-envelope.schema.json`)

### FR-2: Vector Categories (per sdd.md:953,967 + Opus 740)

**Priority:** Must Have
**Description:** Corpus must cover all 7 categories below with at least 5 vectors each (35-vector floor before counting cycle-098-PoC regression vectors and in-house novelties).

| Category | Examples |
|----------|----------|
| `role_switch` | "From now on you are X", DAN-style persona escapes, "ignore previous instructions" |
| `tool_call_exfiltration` | Embedded `<function_calls>` markers, faux tool-result blocks |
| `credential_leak` | `_SECRET_PATTERNS` matches, encoded API keys, GH tokens |
| `markdown_indirect` | Adversarial Markdown links (`[link](javascript:...)`, file-URI), image-payloads |
| `unicode_obfuscation` | NFKC-bypassable forms (FULLWIDTH, zero-width insertions, RTL marks, homoglyphs) |
| `encoded_payload` | Base64, ROT13, hex, URL-encoded jailbreak payloads |
| `multi_turn_conditioning` | Builds context across N turns; first-N-turn heuristic miss; persona drift |

**Acceptance Criteria:**
- [ ] Each category has ≥5 active vectors before cycle exit
- [ ] At least 5 vectors per category trace to a public source (OWASP/DAN/Anthropic)
- [ ] At least 2 vectors per category are in-house novelties (cycle-098-PoC regression OR cypherpunk-authored)

**Dependencies:** SDD §1.9.3.2 categories; Opus 740 multi-turn finding

### FR-3: Bats Runner (single-shot vectors)

**Priority:** Must Have
**Description:** Bats test file at `tests/red-team/jailbreak/runner.bats` iterates over corpus JSONL. For each `active` entry: invokes the payload-construction fixture → feeds output to `sanitize_for_session_start` → asserts `expected_outcome`.

**Acceptance Criteria:**
- [ ] Runner discovers vectors from corpus JSONL (no hard-coded list); a new JSONL line + fixture is sufficient to add a vector
- [ ] Per-vector failure prints `vector_id`, `defense_layer`, expected vs actual sanitization output (truncated to 200 chars to avoid leaking large payloads in CI logs)
- [ ] `suppressed` vectors are skipped with TAP `# skipped: <suppression_reason>` (visible to reviewers)
- [ ] Runner exit code: 0 if all `active` vectors pass; non-zero otherwise

**Dependencies:** FR-1 schema; `lib/context-isolation-lib.sh`; bats 1.10+; jq 1.6+

### FR-4: Multi-Turn Replay Harness (Python)

**Priority:** Must Have
**Description:** Thin python harness at `tests/red-team/jailbreak/replay_harness.py` replays a list-of-messages fixture against `sanitize_for_session_start` (called once per turn). Validates that no turn produces a sanitization-bypass even when context built across earlier turns.

**Acceptance Criteria:**
- [ ] Harness consumes a JSON fixture: `{ "vector_id": "...", "turns": [{ "role": "operator|downstream", "content": "..." }, ...], "expected_outcome": "..." }`
- [ ] Per-turn sanitization output captured; final-state assertion confirms no leak
- [ ] At least 10 multi-turn vectors covering category `multi_turn_conditioning`
- [ ] Harness is invokable via `pytest tests/red-team/jailbreak/test_replay.py` and via standalone CLI for ad-hoc operator runs

**Dependencies:** existing python `lib/context-isolation-lib.sh` adapter (or a new minimal python wrapper if absent); pytest 8.x; cycle-098 SessionStart hook contract for what "surfacing" means

### FR-5: Differential Oracle (testing-fuzzing Archetype 3)

**Priority:** Should Have
**Description:** A subset of vectors run against TWO sanitizer paths (current `sanitize_for_session_start` + a documented baseline pinned at cycle-100 ship time). Divergence flags potential regression in either direction.

**Acceptance Criteria:**
- [ ] Baseline sanitizer captured as `lib/context-isolation-lib.sh.cycle-100-baseline` (frozen copy at cycle-100 ship date)
- [ ] At least 20 vectors run differentially
- [ ] Divergent results: runner reports both outputs + reasons; does not auto-fail (informational signal — operator inspects)

**Dependencies:** cycle-100 ship-time copy of `sanitize_for_session_start`

### FR-6: GitHub Actions CI Gate

**Priority:** Must Have
**Description:** New workflow `.github/workflows/jailbreak-corpus.yml` runs the suite. Triggered by PRs that modify any of:
- `lib/context-isolation-lib.sh`
- `.claude/hooks/session-start/**`
- `.claude/skills/structured-handoff/**`
- `.claude/skills/soul-identity-doc/**`
- `tests/red-team/jailbreak/**` (so changes to corpus run themselves)

**Acceptance Criteria:**
- [ ] Workflow uses `paths:` filter (no full-suite cost on unrelated PRs)
- [ ] Workflow runs bats + pytest in matrix `[ubuntu-latest, macos-latest]` (cycle-098 NFR-Compat2 parity)
- [ ] Failed run sets PR check status RED with first-failing-vector summary in check title
- [ ] Audit log uploaded as workflow artifact (retention 90 days)
- [ ] Smoke-test PR (deliberate regression) confirms gate fires

**Dependencies:** existing cycle-098 / cycle-099 GitHub Actions patterns (yq pinning, matrix Linux+macOS)

### FR-7: Run Audit Log

**Priority:** Must Have
**Description:** Every runner invocation appends a JSONL summary to `.run/jailbreak-run-{ISO-date}.jsonl`. One line per vector × per run. Schema mirrors cycle-098 audit-envelope shape (without Ed25519 signing — out of scope for cycle-100; see Deferred).

**Acceptance Criteria:**
- [ ] Each entry: `{ run_id, vector_id, category, defense_layer, status (pass|fail|suppressed), reason, ts_utc }`
- [ ] `run_id` content-addressed (SHA-256 over canonicalized run-context: workflow_run_id || `manual-{ts}`)
- [ ] Old run logs gitignored (`.run/` already gitignored by Loa convention)
- [ ] Operator query examples documented (e.g., `jq -s 'group_by(.vector_id) | map({id: .[0].vector_id, fails: map(select(.status=="fail")) | length})' .run/jailbreak-run-*.jsonl`)

**Dependencies:** cycle-098 audit-envelope idiom (without sig)

### FR-8: Suppression Discipline (UBS pattern)

**Priority:** Must Have
**Description:** `status: suppressed` vectors carry mandatory `suppression_reason` text. Empty/missing reason → schema validation fails. CI step prints suppression report (count + reason summary) on every run.

**Acceptance Criteria:**
- [ ] Schema enforces `suppression_reason` length ≥ 20 chars when `status == suppressed`
- [ ] Runner output ends with: `Active: N | Superseded: M | Suppressed: K (reasons: <summary>)`
- [ ] Cycle-100 ship-time count: `Suppressed == 0` (every shipped vector is active or superseded)

**Dependencies:** FR-1 schema

### FR-9: Operator Documentation

**Priority:** Must Have
**Description:** README at `tests/red-team/jailbreak/README.md` covers: schema, how to add a vector, how to run locally, how to read audit logs, how the CI gate fires, what suppression means. Mirrors cycle-098 SKILL.md tone (operator-facing, minimal jargon).

**Acceptance Criteria:**
- [ ] README has "Add a vector" section: ≤10-step recipe an operator follows in <10 minutes
- [ ] README cross-links to cycle-098 sdd.md §1.9.3.2 + cycle-100 PRD/SDD
- [ ] README documents the runtime-construction `_make_evil_body` idiom (why trigger strings don't appear in source verbatim)

**Dependencies:** FR-1 through FR-8 documented

### FR-10: Cycle-098 PoC Regression Replay

**Priority:** Must Have
**Description:** Each cypherpunk-caught defect from cycle-098 (NFKC bypass HIGH-2, control-byte heading HIGH-4, INDEX row-injection E6 PoC, sentinel-leak HIGH-3, etc.) becomes a corpus vector that fails closed if the defense regresses. Per RESUMPTION quality bar: "every cypherpunk-caught defect becomes a regression vector."

**Acceptance Criteria:**
- [ ] At least 8 cycle-098 defects mapped to corpus vectors with `source_citation: cycle-098-sprint-N-finding`
- [ ] Each regression vector cites the sprint + finding number
- [ ] Manual smoke-test: revert the defense (in scratch branch) and confirm corresponding vector turns RED

**Dependencies:** cycle-098 sprint history (1A through 7-rem) + audit findings

---

## Non-Functional Requirements

### Performance

- **NFR-Perf1**: Full corpus run completes in <60s on `ubuntu-latest` (typical PR CI cost budget)
- **NFR-Perf2**: Multi-turn replay harness completes in <120s for 10 multi-turn vectors

### Maintainability

- **NFR-Maint1**: New vector authoring takes <10 min for a maintainer following docs (UC-2 acceptance)
- **NFR-Maint2**: Schema is `additionalProperties: false`; schema migrations require an explicit major-version bump in JSONL header comment
- **NFR-Maint3**: No relational database — JSONL only (cycle-098 §3 idiom)

### Security

- **NFR-Sec1**: Adversarial trigger strings MUST NOT appear verbatim in source files outside corpus directories — runtime construction idiom enforced via lint (CI step grep for known dangerous markers in `lib/`, `.claude/`)
- **NFR-Sec2**: Corpus runner must NOT execute payload content (it's data, not code) — runner only feeds payload to sanitizer + asserts output
- **NFR-Sec3**: Audit log redaction: `_SECRET_PATTERNS` matches in any captured output get redacted before write to `.run/jailbreak-run-*.jsonl`
- **NFR-Sec4**: CI workflow runs with default-locked-down GH token scopes (`contents: read` only) — no write/release surface

### Reliability

- **NFR-Rel1**: Schema validation runs first; corpus errors stop the runner before any payload is constructed
- **NFR-Rel2**: A failing vector does not abort other vectors — runner is per-vector resilient, reports all failures in the run
- **NFR-Rel3**: Audit log writes are append-only (no rewrite); partial writes recover on next run

### Compatibility

- **NFR-Compat1**: Linux + macOS parity (cycle-098 NFR-Compat2 idiom); CI matrix runs both
- **NFR-Compat2**: bash 4.0+ portability (existing Loa minimum); no bash 5.x-only features

---

## User Experience

### Key User Flows

#### Flow 1: Maintainer adds a vector

```
1. Read tests/red-team/jailbreak/README.md "Add a vector" section
2. Append JSONL line to corpus/<category>.jsonl
3. Add fixture function to fixtures/<category>.{sh,py}
4. (multi-turn only) Add JSON fixture to fixtures/replay/<vector_id>.json
5. Run: bats tests/red-team/jailbreak/runner.bats (or pytest)
6. Iterate until vector status matches expected_outcome
7. Open PR; CI workflow runs; merge on green
```

#### Flow 2: CI gate fires on a refactor PR

```
1. Maintainer pushes branch with `lib/context-isolation-lib.sh` change
2. GH Actions detects path match → runs jailbreak-corpus workflow
3. Bats + pytest matrix (ubuntu+macos)
4. RED status: PR check shows "Vector RT-UN-007 failed: NFKC bypass"
5. Maintainer inspects audit log artifact, fixes defense or vector, re-pushes
```

### Interaction Patterns

- Operator reads JSONL with `jq`; corpus is human-readable
- Operator reads README before authoring vectors; schema is self-documenting via JSON Schema
- CI feedback is exit-code-driven (UBS pattern); no manual triage required for green runs

### Accessibility Requirements

- Output is plain text (no ANSI required); CI artifacts viewable in browser
- README + JSONL are markdown / plain text; screen-reader compatible

---

## Technical Considerations

### Architecture Notes

The cycle adopts the **registry-driven JSONL catalog** pattern lifted from `dcg` (rule packs), `ubs` (categorized findings), and `testing-fuzzing` (corpus seed strategy). The directory layout:

```
tests/red-team/jailbreak/
├── README.md                          # FR-9
├── corpus/
│   ├── role_switch.jsonl              # one line per vector
│   ├── tool_call_exfiltration.jsonl
│   ├── credential_leak.jsonl
│   ├── markdown_indirect.jsonl
│   ├── unicode_obfuscation.jsonl
│   ├── encoded_payload.jsonl
│   └── multi_turn_conditioning.jsonl
├── fixtures/
│   ├── role_switch.sh                 # _make_evil_body_<vector_id> functions
│   ├── role_switch.py
│   ├── ... (one per category)
│   └── replay/
│       └── RT-MT-001.json             # per-vector multi-turn JSON fixture
├── runner.bats                        # FR-3
├── test_replay.py                     # FR-4
├── differential.bats                  # FR-5
└── lib/
    ├── corpus_loader.sh               # JSONL parsing + validation helpers
    └── corpus_loader.py
```

### Reusable Patterns from User-Level Skills

(Per Phase 0 deep-inspection of `~/.claude/skills/`; see Appendix C.)

| Pattern | Source skill | Cycle-100 use |
|---------|--------------|---------------|
| Registry-driven catalog | `dcg` (rule packs), `ubs` (categories), `testing-fuzzing` (corpus seed) | FR-1 JSONL schema; per-category corpus files |
| Exit-code discipline + structured audit logs | `dcg` (24h codes + audit), `ubs` (jsonl findings), `cc-hooks` (exit 0/2) | FR-3 / FR-7 / FR-8 |
| Multi-pass test organization | `multi-pass-bug-hunting` | Pass 1 (pytest unit) / Pass 2 (bats integration) / Pass 3 (CI gate) / Pass 4 (manual cypherpunk discovery → next-cycle corpus appends) |
| Differential oracle | `testing-fuzzing` Archetype 3 | FR-5 |
| Suppression with mandatory justification | `ubs` `// ubs:ignore — [why]` | FR-8 |
| Risk tier stratification | `slb` CRITICAL/DANGEROUS/CAUTION/SAFE | FR-1 `severity` field |
| Runtime-construction trigger isolation | Loa-internal: L6 sprint 6E `_make_evil_body` | NFR-Sec1 + FR-9 docs |

### Integrations

| System | Integration Type | Purpose |
|--------|------------------|---------|
| `lib/context-isolation-lib.sh::sanitize_for_session_start` | Direct call | The system under test |
| GitHub Actions | Workflow | FR-6 CI gate |
| `ajv` + python `jsonschema` | Library | FR-1 schema validation |
| Loa audit-envelope idiom | Pattern reuse | FR-7 (without Ed25519 signing) |
| `_SECRET_PATTERNS` registry | Library | NFR-Sec3 redaction |

### Dependencies

- bats 1.10+ (existing)
- pytest 8.x (existing)
- python 3.11+ (existing)
- `cryptography` (existing — for `_SECRET_PATTERNS` redaction; not for signing)
- `jq` 1.6+ (existing)
- `yq` 4+ (existing)
- `ajv` 8.x (existing per cycle-098 CC-11; falls back to python `jsonschema` 4.x)
- Existing GitHub Actions runners (`ubuntu-latest`, `macos-latest`)

### Technical Constraints

- Single-machine, single-tenant (cycle-098 PRD §Technical Constraints inherited)
- No remote-fetched corpus content; vectors are repo-resident text
- No network listeners (cycle-098 NFR §1.9.4)
- Adversarial strings live ONLY under `tests/red-team/jailbreak/` (NFR-Sec1 lint)

---

## Scope & Prioritization

### In Scope (cycle-100 MVP)

- Corpus schema (FR-1) + 7 categories (FR-2)
- Bats runner (FR-3) + multi-turn replay harness (FR-4)
- Differential oracle (FR-5) — Should-Have but in scope
- GitHub Actions CI gate (FR-6) with path filter
- Audit log (FR-7) + suppression discipline (FR-8)
- Operator documentation (FR-9)
- Cycle-098 PoC regression vectors (FR-10)
- Minimum 50 vectors (SDD floor); aspiration ~100; **count emerges from cypherpunk-defensible source mining**

### In Scope (Future Iterations — cycle-101+)

- Layer 5 tool-call-resolver mechanism (provenance tagging + deny-by-default + per-tool allowlists per cycle-098 sdd.md:959-971)
- Bridgebuilder feedback append-handler skill (auto-extracts novel vectors from BB iter-N findings into corpus PRs)
- Production telemetry pipeline (sanitization hit rate, per-vector pass tracking aggregated across runs)
- Ed25519 signing of `.run/jailbreak-run-*.jsonl` (matches cycle-098 audit-envelope; out of scope here)

### Explicitly Out of Scope

- **Cross-language corpus (JS/Go bindings)** — Reason: Loa is bash + python; no JS/Go surface to defend
- **GUI / web dashboard for corpus browsing** — Reason: jq + markdown is the operator surface; no web UI per Loa convention
- **Coverage-guided fuzzing infrastructure (libFuzzer / AFL++ / cargo-fuzz)** — Reason: cycle-100 is documented-vector regression, not exploration. Fuzzing's coverage-guided exploration is a separate (likely cycle-102+) workstream
- **Tool-call resolver runtime enforcement** — Reason: that's Layer 5 mechanism, deferred per operator answer
- **Multi-host / cross-machine handoff scenarios** — Reason: cycle-098 PRD v1.3 narrowed L6 to same-machine; corpus inherits that scope

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1 Schema | P0 | S | High — load-bearing |
| FR-2 7 categories × 5 vectors | P0 | L | High — coverage floor |
| FR-3 Bats runner | P0 | M | High — runs the corpus |
| FR-4 Multi-turn harness | P0 | M | High — Opus 740 finding |
| FR-6 CI gate | P0 | S | High — regression oracle |
| FR-7 Audit log | P0 | S | Medium — observability |
| FR-9 README | P0 | S | High — append-friendliness |
| FR-10 Cycle-098 PoC regressions | P0 | M | High — known-defect coverage |
| FR-5 Differential oracle | P1 | M | Medium — informational signal |
| FR-8 Suppression discipline | P1 | S | Medium — UBS hygiene |

---

## Success Criteria

### Cycle Exit Criteria

- [ ] ≥50 active vectors in corpus (SDD floor)
- [ ] All 7 categories have ≥5 active vectors
- [ ] At least 8 cycle-098 PoC regression vectors active (FR-10)
- [ ] Multi-turn harness has ≥10 vectors (FR-4)
- [ ] CI gate workflow lives at `.github/workflows/jailbreak-corpus.yml`; smoke-test PR confirms it fires
- [ ] Suppression count == 0 at ship time (FR-8 NFR)
- [ ] Cypherpunk dual-review (subagent + general-purpose) passes per-vector defensibility check; vectors that fail are dropped or revised
- [ ] BridgeBuilder kaironic review reaches plateau (matches cycle-098 sprint cadence)
- [ ] PR merges to main; cycle-100 ledger entry archived

### Post-Ship Validation (next 30 days)

- [ ] At least one cycle-101+ PR triggers the gate; gate behavior matches FR-6 acceptance
- [ ] Operator-authored vector landed via UC-2 flow in <10 min (Goal G-4 validation)
- [ ] No false-positive blocks on PRs that don't touch the surfacing path (path filter precision)

### Long-term (90 days)

- [ ] Corpus has grown by ≥5 BridgeBuilder-discovered vectors (validates append-friendliness)
- [ ] No prompt-injection production incident attributable to a category covered by the corpus

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| **R-Curation**: Curating 50-100 cypherpunk-defensible vectors takes longer than planned (security research is qualitatively different from engineering — see RESUMPTION.md:26 framing) | HIGH | MEDIUM | Sprint cadence ships in waves: Sprint 1 ships schema + runner + 20-vector seed (5 categories × 4 vectors); Sprint 2 fills remaining categories + multi-turn; Sprint 3 cycle-098 PoC regressions + cypherpunk per-vector pushback round; Sprint 4 CI gate wiring + docs. Cycle exit is gated on ≥50 active, not on hitting 100. |
| **R-FalsePositive**: Vector incorrectly assumes a sanitization that the lib does not actually provide → vector RED on first run, blocks own merge | MEDIUM | LOW | Vectors authored against current `sanitize_for_session_start` behavior; expected_outcome is the OBSERVED-and-CYPHERPUNK-CONFIRMED defense, not aspirational. If a vector's expected outcome diverges from observed, treat divergence as a finding (defense bug or test bug — investigate before shipping). |
| **R-CorpusBloat**: Corpus grows beyond curation capacity; vectors lose individual cypherpunk-defensibility | MEDIUM | MEDIUM | Hard rule: every vector survives subagent paranoid-cypherpunk review of inclusion justification. Quality > count (per RESUMPTION quality bar). Suppression discipline (FR-8) for vectors that lose defensibility over time. |
| **R-PathFilterDrift**: CI gate path filter falls out of sync with actual surfacing-path file paths | LOW | HIGH | Path filter list is a single YAML stanza in `.github/workflows/jailbreak-corpus.yml`; documented in cycle-100 SDD with explicit pointers. Cycle-100 reviewer's last-pass check: "Did any new SessionStart-touching path land in cycle-099/100 that's not in the filter?" |
| **R-MultiTurnComplexity**: Multi-turn replay harness is more complex than a thin python wrapper; scope creeps | MEDIUM | MEDIUM | Harness explicitly thin: list-of-messages fixture + per-turn `sanitize_for_session_start` call + final-state assertion. No Claude API replay, no provider mocking. If thinness fails to validate the Opus 740 finding, the gap is documented and follow-up cycle scopes a richer harness. |
| **R-AdversarialStringLeak**: Adversarial trigger strings end up in source files (non-runtime construction) → false-positive grep matches across the codebase, bridgebuilder reviewer confusion | MEDIUM | LOW | NFR-Sec1 lint: CI step greps `lib/`, `.claude/` for known-adversarial markers; fails closed. Runtime-construction `_make_evil_body` idiom mandatory per FR-9 docs. |
| **R-CIGateBypass**: PR author bypasses gate by claiming "this PR doesn't touch the surfacing path" — and is wrong | MEDIUM | HIGH | Path filter is conservative (broad path globs). Reviewer training note in cycle-100 SDD: "If in doubt, run the suite locally." Cycle-101 follow-up may add a runtime check (a hook fires if a PR labeled "no-surfacing-touch" actually modified one of the protected paths). |
| **R-CypherpunkPushback**: Per-vector defensibility review fails for some vectors mid-cycle | MEDIUM | LOW | Drop or revise — do not ship weak vectors. Cycle exit floor is 50, so dropping 5-10 vectors is tolerable. Document drops in cycle-100 RESUMPTION for audit trail. |
| **R-PerformanceDrift**: Corpus run > 60s on CI as corpus grows | LOW | MEDIUM | NFR-Perf1 budget. Parallelize bats by category if needed (bats `--jobs N`). Periodic corpus minimization pass (testing-fuzzing seed strategy: dedupe overlapping vectors). |

### Assumptions

- Cycle-099-model-registry remains active in parallel; cycle-100 does not displace it (operator confirmed at session start)
- Existing cycle-098 layered defenses (Layer 1-3) are the system under test; cycle-100 does not modify them
- `~/.claude/skills/` patterns (dcg / slb / cc-hooks / ubs / testing-fuzzing / multi-pass-bug-hunting) are stable and reusable as inspiration; cycle-100 does not import or depend on them at runtime
- Cypherpunk subagent is available for per-vector defensibility review (matches cycle-098 sprint-7 idiom)

### Dependencies on External Factors

- GitHub Actions availability (cycle-100 CI gate hosted there)
- Public corpora (OWASP LLM Top 10, DAN variants, Anthropic red-team papers) remain accessible / citable; if a source disappears, citation falls back to archive snapshot URL

---

## Timeline & Milestones

| Milestone | Target | Deliverables |
|-----------|--------|--------------|
| `/architect` complete (SDD) | +2 days | SDD with detailed component contracts, schema specs, runner architecture |
| `/sprint-plan` complete | +3 days | 4-sprint slicing (schema+runner / categories / cycle-098 regressions / CI gate) |
| Sprint 1: schema + runner + 20-vector seed | +1 week | FR-1, FR-3, FR-7 partial, 4 categories × 5 vectors |
| Sprint 2: remaining categories + multi-turn | +2 weeks | FR-2 full coverage, FR-4 multi-turn harness, ≥45 active vectors |
| Sprint 3: cycle-098 PoC regressions + cypherpunk per-vector pushback | +3 weeks | FR-10, suppression scrub, ≥50 active vectors, FR-5 differential subset |
| Sprint 4: CI gate + docs + smoke-test PR | +4 weeks | FR-6, FR-9, smoke-test confirms gate fires, BridgeBuilder kaironic plateau |
| Cycle-100 ship + archive | +5 weeks | Merge to main; ledger archive; RESUMPTION.md handoff to cycle-101 |

(Targets are aspirational; cycle-098 sprint cadence ran over multiple weeks per primitive, and cycle-100's curation work may follow similar timeline elasticity.)

---

## Appendix

### A. Stakeholder Insights

**Operator (deep-name) at cycle-098 close (2026-05-08)**: "Sprint 7D was carved out of cycle-098 because the corpus is qualitatively different work (security research + curation, not engineering). The previous Claude's handoff explicitly granted permission to question the framing for exactly this scope decision; operator confirmed split at session start."

**Operator at cycle-100 open (2026-05-08)**: confirmed via batch interview — minimal interview depth, corpus + runner + CI gate scope, unified `tests/red-team/jailbreak/` directory, multi-turn in scope. Open count (50 floor, 100 aspiration). Standard schema (id + category + title + payload + expected_outcome + defense_layer + source_citation). Standard sources (OWASP LLM Top 10 + DAN + Anthropic + cycle-098 PoCs). Defer Layer-5 resolver + BB-append-handler + telemetry to cycle-101+.

### B. Competitive / Reference Analysis

External corpora referenced for source mining:

- **OWASP LLM Top 10** (LLM01: Prompt Injection) — industry-standard taxonomy
- **DAN corpus + variants** — public jailbreak archives
- **Anthropic constitutional-AI / red-team papers** — published research
- **Cycle-098 sprint-7 cypherpunk findings** — internal regression replay
- **(Stretch / explicitly out of scope per operator answer)**: Garak / PromptFoo / Lakera red-team suites

### C. Bibliography

**Internal Resources:**
- cycle-098 SDD §1.9.3.2 (`grimoires/loa/cycles/cycle-098-agent-network/sdd.md:944-971`)
- cycle-098 RESUMPTION.md (`grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md:26-49`)
- cycle-098 sprint-7 cypherpunk findings (commit `5677da7e`)
- L6 sprint-6E `_make_evil_body` idiom (cycle-098 sprint-6 bats fixtures)
- Loa audit-envelope schema (`.claude/data/trajectory-schemas/agent-network-envelope.schema.json`)
- Loa context-isolation lib (`lib/context-isolation-lib.sh`)

**User-level skill patterns mined (read-only inspiration; not runtime dependencies):**
- `~/.claude/skills/dcg/` — registry-driven destructive-command guard
- `~/.claude/skills/slb/` — two-person-rule risk tier model
- `~/.claude/skills/cc-hooks/` — PreToolUse hook contract + exit-code discipline
- `~/.claude/skills/ubs/` — categorized findings + suppression-with-justification
- `~/.claude/skills/testing-fuzzing/` — corpus seed/minimize strategy + differential-oracle archetype
- `~/.claude/skills/multi-pass-bug-hunting/` — multi-pass audit organization

**External Resources:**
- OWASP LLM Top 10 — https://owasp.org/www-project-top-10-for-large-language-model-applications/
- DAN corpus — public jailbreak archive (PR-time citation per active source)
- Anthropic red-team papers — published research (PR-time citations)

### D. Glossary

| Term | Definition |
|------|------------|
| Adversarial vector | A documented attack input (or sequence) intended to bypass one or more sanitization layers |
| Corpus | The full registry of vectors at `tests/red-team/jailbreak/corpus/*.jsonl` |
| Defense layer | One of L1 (pattern detection), L2 (structural sanitization), L3 (policy engine), L6 (handoff body sanitize-on-surface), L7 (SOUL.md sanitize-on-surface) |
| Multi-turn conditioning | An attack that builds context across N turns to bypass first-N-turn heuristic windows (per Opus 740 Flatline finding) |
| Runtime construction | Idiom (`_make_evil_body_*`) that builds adversarial trigger strings at fixture-execution time, keeping them out of source files where they could spuriously match grep / bridgebuilder reviewers |
| Suppression | Marking a vector inactive with mandatory justification (per UBS pattern); cycle-100 ships with zero suppressions |
| Cypherpunk per-vector pushback | Subagent paranoid-cypherpunk review of each vector's inclusion justification; vectors that fail are dropped or revised |
| Append-friendly | Schema and runner contract is stable enough that future operators add vectors via simple PR (no schema migration, no runner refactor) |

---

> **Sources**: cycle-098 sdd.md:944-971 §1.9.3.2 (Layer 4 + Layer 5 spec); cycle-098 RESUMPTION.md:26-49 (Sprint 7D framing + cycle-100 forward-handoff); cycle-098 sprint-7 cypherpunk findings (commit `5677da7e`); cycle-098 sprint-6E `_make_evil_body` idiom; Phase 0 deep-inspection of `~/.claude/skills/` (dcg, slb, cc-hooks, ubs, testing-fuzzing, multi-pass-bug-hunting); operator batch interview 2026-05-08 confirming scope, directory, multi-turn-in-scope, count target, schema richness, source set, deferred items.

*Generated by PRD Architect (deep-name + Claude Opus 4.7 1M)*
