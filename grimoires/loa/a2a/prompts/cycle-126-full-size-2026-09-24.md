# Operator prompt — cycle-126 "Full size" (2026-09-24)

**Issued by:** Jani (Loa creator/maintainer), after the model-era assessment of 2026-09-24: *"proceed."* Unattended run on branch `feature/cycle-126-full-size` from `main` `2079e719` (`v2.0.0-rc.2` + the cycle-125 follow-ups). Same shape as cycle-125: PRD → SDD → sprint plan (Flatline dissent integrated) → `/run sprint-plan` with `/review-sprint` and `/audit-sprint` (cross-model dissent, every schema-rejected payload hand-triaged) per sprint → draft PR with `cycle-126` in the title → CI green → one Bridgebuilder pass triaged → merge. The merge prepares the next release candidate; **nothing is published** in this cycle.

## 1. Why (evidence, do not re-derive)

`grimoires/loa/reports/model-era-audit-2026-09-24.md` (tracked) — verified `file:line` findings. In one sentence: the adapters, Bridgebuilder, Flatline and the skills' context discipline still carry constants and code paths from the 200K-context / 4K-output / non-thinking generation, so Opus 5, Sonnet 5 and Fable 5.1 run through Loa at a fraction of their size; cross-model review plans one voice and drops schema-rejected findings on the floor (three of five were real this week); the instruction surface is at its byte ceilings; and routing/governance tables still name the previous generation as current.

## 2. Scope — four functional requirements

### FR-1 Full-size adapters and reviewers (audit §1 C1–C9)
- Input ceiling: replace the single `effective_input_ceiling: 180000` literal with a family-aware policy derived from the catalog (`context_window − default max output`, streaming transport), kept behind the existing calibration record (`ceiling_calibration.source: catalog_derived`, `calibrated_at: null` until `tools/ceiling-probe-live.py` runs with a key) and a kill switch that restores 180K. The 36K legacy wall stays for the non-streaming transport. Long-context request headers are a per-entry catalog field (`params.beta_headers`), never a hard-coded string.
- Output: `_LEGACY_DEFAULT_MAX_TOKENS = 4096` only when the catalog has no `max_output_tokens`; dataclass defaults stop emitting a temperature the model rejects; the non-streaming read-timeout heuristic keys on the resolved max_tokens, not 4096.
- Bridgebuilder: the truncation table is generated from the catalog's `max_output_tokens` / ceiling (no codegen literal); the default model is the `opus` alias; persona pins resolve through aliases; `isReasoningClass` derives from the catalog (`thinking_adaptive` / `thinking_traces`) so Fable 5.1 and Sonnet 5 get the reasoning budget.
- Flatline: per-voice `max_tokens` from the catalog (bounded), not a 16K literal shared with thinking.
- Token estimation: an Anthropic request is never rejected pre-flight on an OpenAI-encoding estimate — use the provider's count endpoint when a key exists, else a conservative bytes-based bound that cannot exceed the ceiling.
- Health probe: alias-resolved id, or the models endpoint; never a retired snapshot.
- Acceptance: catalog tests assert the computed ceiling per entry; a fixture request of 600K tokens to `claude-fable-5-1` passes pre-flight in streaming mode and is refused at 36K in legacy mode; BB truncation table test derives 128000 for the 5-family; `isReasoningClass` unit test for `claude-fable-5-1`, `claude-sonnet-5`, `claude-opus-5`; Flatline cap test; health-probe test.

### FR-2 Two voices and no dropped findings (audit §2)
- Dissent plans an Anthropic voice that works without an API key: when `flatline_protocol.models.primary` resolves to an Anthropic HTTP entry and no key is present, the chain walks to `claude-headless` (it already exists as a hop) — `voices_planned ≥ 2` on a subscription-only host, `voices_succeeded_ids` shows both.
- Schema tolerance: a finding missing `failure_mode` is not dropped — the field is derived from `description`/`title` (marked `derived: true`) or left optional for `advisory` severities; every rejected payload that survives (still unparseable) is summarised in the envelope (`rejected_summary[]` with severity, title, anchor) and the reviewing-code / auditing-security contracts require the lead to triage that list in the feedback file (a `## Rejected dissent payloads` section, `none` allowed).
- The repair loop uses a current cheap model (`tiny`/`cheap` alias) or the headless hop, and its success rate is recorded.
- Acceptance: KF-004 fixtures (the three real rejected payloads of this week) produce findings, not sidecar rows; a two-voice run on this host; `verdict-derive.sh` enforces the new section's presence when the envelope has rejected rows.

### FR-3 Context discipline and instruction surface sized for the current generation (audit §3)
- `tool-result-clearing.md` thresholds and the `context_discipline` include become generation-aware: one source of truth (a small table keyed by the session model's context class), with the 200K numbers retained for that class and 1M-class numbers that stop the 15K "STOP and synthesize" reflex; NOTES/artefact caps unchanged (they are about files, not context).
- Instruction diet: move the reference-grade protocols (`helper-scripts`, `session-continuity` details, `constructs-integration`, `trajectory-evaluation`, `recommended-hooks`) to on-demand loading (`@import`-style pointers from CLAUDE.loa.md, read when needed), regain ≥ 20 % headroom on the protocol budget and ≥ 1 KB on `CLAUDE.loa.md`, and remove `wc -l`-gated parallelism choreography from the three skills — all under the existing eval harness A/B gate (no recall regression on the review/audit gold sets).
- Acceptance: budgets green with headroom; eval A/B not worse; include block regenerated; the three skills' byte counts drop.

### FR-4 Routing residue, governance registry, probes (audit §4–§5)
- `cheap` → `claude-sonnet-5` (or Haiku 4.5 where latency matters — decide per role and record); bash fallback map and Flatline regexes/stub learn the 5-family; `model-permissions.yaml` gains 5-family entries and stops calling 4.7 current; stale example pins and the `gpt-4o` default fixed; Gemini pins updated to ids the catalog serves.
- `detect-platform-features.sh` detects `active_skill` from a real hook payload (record on first sight) instead of a never-set env var; `implement-gate.sh` authoritative mode becomes reachable; `WRITE_CAPABLE_AGENTS` reads the agent types from the harness registry the repo already ships or documents the rule.
- `check-permissions.sh` understands both rule grammars.
- Acceptance: tests per item; `/loa` and preflight unchanged for operators.

## 3. Constraints (all in force)
- Never weaken a fence's genuine catch; never publish a release in this cycle; no merge until CI is green and the Bridgebuilder pass is triaged.
- No secrets in tracked state; fixture rows scrubbed.
- `.claude/` edits under the framework marker (`.run/zone-guard-authorization.json`, created at kickoff, deleted after the last framework edit) with `repo-map-gen.sh` + `.checksum` sidecar + `checksums.json` regenerated together.
- Push only via `.claude/scripts/run-mode-ice.sh push origin feature/cycle-126-full-size`; a2a sprint records go to `record/cycle-126-a2a` (built from a temporary index, never a checkout).
- Prompt budgets must end green with more headroom than they started; protocol changes net-negative.
- Every code change test-first; review + audit with cross-model dissent per sprint; every schema-rejected dissent payload hand-triaged in the feedback file.
- Aleph untouched. Do not touch the Claude Code OAuth token or borrow credentials; the live probe (`ceiling-probe-live.py`) is an operator step and is not run here.

## 4. Suggested sprint shape
1. FR-1 adapters/BB/Flatline caps (largest blast radius, most tests).
2. FR-2 dissent second voice + tolerant schema + contract changes.
3. FR-3 context discipline table + instruction diet under the eval gate.
4. FR-4 residue/registry/probes + docs (migration guide addendum, CHANGELOG) + E2E goal validation.

## 5. Stop conditions
Operator-only blocker (credential, repository setting, publication decision); a fence catch that would have to be weakened; eval A/B regression that cannot be closed within the sprint; anything that needs the live ceiling probe to decide.
