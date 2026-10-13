# Sprint Plan: Decision Surfaces (cycle-128)

**Version:** 1.3
**Date:** 2026-10-13
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md
**Ledger:** cycle `cycle-128-decision-surfaces`, sprints global 252 / 253 / 254 (local sprint-1 / sprint-2 / sprint-3)
**Branch:** `feature/cycle-128-decision-surfaces` from `main` `76e7650b`

---

## Executive Summary

Three sprints deliver the eight functional requirements of the cycle-128 PRD without changing verdict derivation, gate ordering or the dissent artefact gate (the review skill gains two checklist rows and one citation line; nothing it gates changes). Sprint 1 lands the small, high-leverage changes and the decision ledger the later sprints write to. Sprint 2 builds the decision map (`/chart`) and the prototype-ticket discipline on top of the ledger. Sprint 3 adds the glossary, the seams-under-test and red-before-green checks, the documentation, and the end-to-end validation of every PRD goal. Each sprint is implemented by Opus 5.5 subagents in worktrees, reviewed and audited on Fable 5.1 with at most three dissent runs per gate, and closed through the run loop. Sequencing constraint: tasks that edit shared files (`validate-artifact.sh`, `golden-path.sh`, `settings.json`, `.gitignore`, the planning SKILL.md files) are serialised through the lead's merge of patches; independent tasks run in parallel worktrees. The lead's main checkout is the only writer of `grimoires/loa/decisions.yaml`; implementers and tests write fixtures only (`--file`). Evidence for every acceptance criterion lives under `grimoires/loa/a2a/sprint-<global>/` (implementation report `reviewer.md`, triage tables, transcripts, command output).

**Total Sprints:** 3
**Sprint Duration:** 1 day each (unattended)
**Estimated Completion:** 2026-10-16

> Sources: prd.md §Executive Summary, §Timeline & Milestones; sdd.md §8 Development Phases

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 (252) | Rounds, fact/decision attribution, decision ledger, operator-only commands | `rounds` pacing (FR-1); fact/decision rule and PR-body section (FR-2); `decisions.yaml` + `dec-write-lib.sh` + INDEX + SessionStart surface (FR-3); `disable-model-invocation` allowlist and lint (FR-8) | None |
| 2 (253) | Decision map (`/chart`) and prototype tickets | `/chart` command + `charting-decisions` skill, map doc, lint, golden-path phase, research subagents (FR-4); spike template, validator, ICE rule, interview sentence (FR-5) | Sprint 1 (ledger, rounds) |
| 3 (254) | Glossary, seams under test, red-test check, E2E | `GLOSSARY.md` + drift check (FR-6); Seams Under Test block + `red-test-check.sh` (FR-7); CHANGELOG, README, hooks-reference, REPO-MAP; Task 3.E2E | Sprints 1–2 |

---

## Sprint 1: Rounds, fact/decision attribution, decision ledger, operator-only commands

**Duration:** 1 day
**Dates:** 2026-10-13 - 2026-10-14

### Sprint Goal
Make the interview ask in prerequisite-ordered rounds, make every unattended decision attributable through a built decision ledger, and take operator-only commands out of the model's reach.

### Deliverables
- [ ] `interview.pacing: rounds` implemented in `discovering-requirements` (REFERENCE.md §Question Pacing + ≤ 3-line SKILL.md pointer), default for `thorough`, documented in `.loa.config.yaml.example`; the Mode Behavior and Input Style tables moved to `resources/REFERENCE.md`; `planning-sprints` and `designing-architecture` Phase 2 point at the same rule
- [ ] Fact/decision rule in the Backpressure Protocol; the unattended-decision sentence in `karpathy-principles.md` §1 and `autonomous-agent/SKILL.md`; "Decisions taken on your behalf" section in the run-mode completion PR template
- [ ] `grimoires/loa/decisions.yaml` (tracked; `.gitignore:149` negated; `validate-gitignore-state.sh` row) with the schema from SDD §3, seeded with cycle-127 D1–D3 as `decided` and this cycle's PRD D1–D16 and SDD A1–A11 as `proposed` (`decided_by: agent`)
- [ ] `.claude/scripts/lib/dec-write-lib.sh` (`new`, `decide`, `confirm`, `reject`, `supersede`, `list --format md`) with flock, append-only verify, atomic rename, context-derived `decided_by`, yq v4 writes with values passed by environment, duplicate-id refusal, and a fixture corpus of hostile strings (quotes, colons, `#`, leading `-`, multiline, Unicode, control characters, YAML-looking values)
- [ ] `validate-artifact.sh --type decisions`; `grimoire-index.sh` `## decisions` section; SessionStart surface script behind `decisions.surface_at_session_start` (default false); the two existing readers (`loa-learnings-index.sh`, `path-lib.sh`) resolve the live file
- [ ] An automated harness check (bats: a temp project with a fixture command carrying the flag, `claude -p --max-turns 1` asked to invoke it, the skill reported unavailable; skipped when the CLI is absent) recorded first; then `disable-model-invocation: true` on the safe set (`loa-eject`, `toggle-gpt-review`, `permission-audit`, `loa-setup`), the referenced set triaged per reference with a table row and a `DEC` row each, `.claude/data/user-invoked-commands.txt`, `tests/unit/user-invoked-commands.bats`; if the flag does not hide the command, FR-8 is recorded as lint-only and G-7 partial
- [ ] CHANGELOG `[Unreleased]` entries for Sprint 1 and the pacing-default migration note (explicit `pacing` values are unchanged; only the `thorough` default moves; `sequential` is the opt-out)

### Acceptance Criteria
- [ ] `tools/check-prompt-budget.sh` green; `discovering-requirements/SKILL.md` ≤ 16,384 B
- [ ] `.loa.config.yaml.example` documents `pacing: rounds` (frontier rule, numbered format, "yes accepts the recommendation", the `sequential` opt-out)
- [ ] A fixture transcript in `rounds` mode carries `<!-- round: N; questions: [{id, depends_on}] -->` blocks; `tools/check-round-independence.sh` reports ≥ 2 questions per round (final round exempt) and no same-round dependency (bats); transcript in the sprint a2a directory
- [ ] `dec-write-lib.sh` bats: ids allocate max+1 under the lock in the main checkout; a linked worktree writes the pending file and `import` allocates real ids and rewrites references; the file never shrinks and never drops an id; content edits to an existing row are rejected; a failed write leaves the previous file intact; `decide`/`confirm` without `--evidence` and `reject` without a follow-up exit non-zero; under every unattended signal (run-state marker, `LOA_UNATTENDED`, autonomous Flatline mode, PRD Status line) a write lands `proposed` with `proposed_by: agent` and `decided_by` null whatever the flags; `CI=1` makes the writer exit 1; the hostile-string corpus round-trips against the sanitised input
- [ ] `validate-artifact.sh --type decisions` exits 0 on the live file and 1 on each negative fixture: missing `decided_by`, duplicate id, illegal transition (`rejected` → `decided`), `decided` row without evidence, `operator` row without an answer reference, a content edit to an existing row; `supersede` leaves the old row `superseded` and removes nothing
- [ ] `validate-artifact.sh --type prd` fails a fixture where an `[ASSUMPTION decision]` tag has no `DEC` row; `--type sdd` WARNs on a Resolved open question without a `DEC` id; `prd-template.md` and `sdd-template.md` carry the decisions appendix; `loa-learnings-index.sh` and `path-lib.sh` resolve the tracked ledger (bats)
- [ ] The SessionStart surface wraps its block in the L6 data fence, caps summaries at 100 chars, and a negative bats case shows control characters and instruction-like text neutralised
- [ ] Existing suites for `validate-artifact`, `grimoire-index`, `prompt-budget` and `skill-capabilities` stay green (backward compatibility)
- [ ] `grimoire-index.sh` emits `## decisions` with ID / status / decided_by / summary / source (bats for TSV, JSON and markdown, and the no-yq skip); the SessionStart surface prints nothing when the key is off
- [ ] No skill's `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`; `/decisions` carries `disable-model-invocation: true` and is the only caller (bats over frontmatter) and the open rows when on
- [ ] `tests/unit/user-invoked-commands.bats` green; the automated harness check passes or is recorded as skipped (CLI absent) with the lint-only contingency stated; the triage table and its `DEC` rows exist under `grimoires/loa/a2a/sprint-252/triage-fr8.md`
- [ ] `no-history-in-rule-text.bats`, `skill-capabilities.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-artifact` suites green

### Technical Tasks

<!-- → **[G-N]** = contributing goal(s); ⇐ = blockers (becomes --deps at bead creation) -->

- [ ] Task 1.0: Automated harness check for `disable-model-invocation` (fixture command in a temp project, `claude -p --max-turns 1`, skip when the CLI is absent); record the outcome and the lint-only contingency → **[G-7]** ⇐ none
- [ ] Task 1.1: Move the Mode Behavior and Input Style tables from `discovering-requirements/SKILL.md:66-79` to `resources/REFERENCE.md` behind guarded pointers; free at least the bytes this cycle adds to that file (rounds pointer ≤ 3 lines, fact/decision rule ≤ 3 lines, prototype sentence ≤ 2 lines, glossary sentence ≤ 3 lines) plus 400 B headroom; record the bytes freed → **[G-3]** ⇐ none
- [ ] Task 1.2: `rounds` pacing: REFERENCE.md §Question Pacing text (frontier rule, ❓/➡ format, answer semantics, recompute per round, the per-round `<!-- round -->` comment block), SKILL.md pointer, config default `rounds` for `thorough` with the key's scope, `.loa.config.yaml.example` block, `planning-sprints` and `designing-architecture` Phase 2 pointers, `tools/check-round-independence.sh` → **[G-3]** ⇐ Task 1.1
- [ ] Task 1.3: `decisions.yaml` schema (SDD §3: provenance fields, `status` enum with `proposed`, `transitions`), an empty-but-valid ledger (header and `decisions: []`; rows come only from Task 1.6), `.gitignore` negation, `validate-gitignore-state.sh` row, `validate-artifact.sh --type decisions` with the negative fixtures (schema, transition invariants, `decided_by` consistency, duplicate id, content edit), SDD Open Questions `DEC` column WARN, PRD/SDD template appendix → **[G-1]** ⇐ none
- [ ] Task 1.4: `dec-write-lib.sh` (`new`, `decide`, `confirm`, `reject`, `supersede`, `import`, `list --format md`, `context`) modelled on `kf-write-lib.sh`: every unattended write lands `proposed` with `proposed_by: agent` (`decided_by` null until confirmed), operator attribution only via `/decisions`, linked worktrees write the per-sprint pending file and `import` allocates real ids, portable lock, append-only transitions with `by`/`evidence`, ref grammars and artifact hashes, `jq`/`yq` v4 preflight, mechanical CI/hook write refusal → **[G-1]** ⇐ Task 1.3
- [ ] Task 1.5: `grimoire-index.sh` `## decisions` section; SessionStart surface script + `settings.json` row (L6 data fence, stale-marker notice); `decisions.surface_at_session_start` config key (default false); operator-only command `.claude/commands/decisions.md` (`confirm|reject|supersede|list`, `disable-model-invocation: true`, added to the FR-8 allowlist); existing readers resolve the live file → **[G-1, G-7]** ⇐ Task 1.4
- [ ] Task 1.6: Seed the ledger through the lib, run by the lead in the main checkout, before Task 1.9 exercises the PRD gate: cycle-127 D1–D3 (source NOTES Decision Log 2026-10-07), cycle-128 PRD D1–D21 and SDD A-decisions, all `proposed` with `proposed_by: agent` → **[G-1]** ⇐ Task 1.4
- [ ] Task 1.7: Fact/decision split — Backpressure Protocol rule and `[ASSUMPTION fact|decision]` tag classes (≤ 3 lines), `karpathy-principles.md` §1 and the autonomous-agent prime directive ("a linked worktree writes the pending file automatically"), `render-templates.md` PR section rendered by `list --not-decided-by operator --format md` with a Voice column, `validate-artifact --type prd` tag-to-row rule with the `BARE_ASSUMPTION_FAILS_FROM` date constant and the `**Deferred:**` line → **[G-1]** ⇐ Task 1.4
- [ ] Task 1.8: FR-8 allowlist file, frontmatter flags on the safe set, per-reference triage table of the referenced set (`a2a/sprint-252/triage-fr8.md`) with a `DEC` row each written by the lead, `tests/unit/user-invoked-commands.bats`, CHANGELOG entries for Sprint 1 and the pacing migration note → **[G-7]** ⇐ Task 1.0, Task 1.4
- [ ] Task 1.9: Sprint 1 verification: `dec-write-lib.bats` (hostile-string corpus, derived `decided_by` refusal, content-edit rejection, duplicate id), decisions-validator negative fixtures, `check-round-independence.bats` over the fixture transcript, surface negative case, readers check, budget and regression suites → **[G-1, G-3, G-7]** ⇐ Task 1.2, Task 1.5, Task 1.6, Task 1.7, Task 1.8

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `dec-write-lib.sh` CLI (subcommands, exit codes, file after each op) | lost ids, shrinking file, missing evidence, lock contention | the content quality of a row | `tests/unit/kf-write-lib.bats` |
| `validate-artifact.sh --type decisions` exit code + stderr | schema drift, missing `decided_by` | semantic duplicates | `tests/unit/validate-artifact.bats` |
| `grimoire-index.sh` output section | missing or malformed `## decisions` | INDEX ordering vs other sections | `tests/unit/grimoire-index.bats` |
| `user-invoked-commands.bats` over `.claude/commands/*.md` | missing flag, operative reference to a flagged command | the harness actually hiding the command (manual check) | `tests/unit/skill-capabilities.bats` |
| `check-prompt-budget.sh` on the touched skills | budget breach, unguarded resource charge | prose quality | `tests/unit/prompt-budget.bats` |
| `tools/check-round-independence.sh` over the rounds fixture transcript | a same-round dependency, a one-question round | that the live skill produces rounds at all | new |
| SessionStart surface script stdout (key off / key on / hostile row) | leaking when off, missing rows when on, unsanitised text | the hook's ordering among other SessionStart hooks | `tests/unit/loa-kf-surface.bats` |

### Dependencies
- None (first sprint). `br` 0.2.6, `jq`, `yq` v4, bats-core present on the host.
- Rollback: `interview.pacing: sequential` restores the old default; `decisions.surface_at_session_start` is already off by default; removing the `.gitignore` negation and the flagged frontmatter lines reverts FR-3 tracking and FR-8.

### Security Considerations
- **Trust boundaries**: `decisions.yaml` rows are agent-authored text surfaced at SessionStart; the surface prints only id, status and summary with control characters stripped, inside the L6 data fence; rows are never interpreted as instructions; a negative bats case proves it. Only the lead's main checkout writes the live ledger.
- **External dependencies**: none added; `dec-write-lib.sh` uses the same `flock` + atomic-rename pattern as `kf-write-lib.sh`.
- **Sensitive data**: none; `pii-filter.sh` runs on `--type decisions` validation; the zone-state rule (no secrets in tracked state) applies to the ledger.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Budget: `discovering-requirements/SKILL.md` has 80 B headroom | High | Med | Task 1.1 first; charged-resource rule respected (guard words on pointers); budget gate in CI |
| Default pacing flip surprises operators | Med | Low | `sequential` documented as the opt-out in the example config and CHANGELOG |
| `.gitignore` negation ordering swallows the ledger anyway | Med | Med | `validate-gitignore-state.sh` row; `git check-ignore -v` in the bats |
| A flagged command is reached by an orchestrator as a step | Low | High | Only the zero-reference safe set is flagged without triage; lint for operative references |
| Parallel implementers allocate the same `DEC` id | High | High | Linked worktrees write a pending file with provisional ids; the lead imports in the main checkout; duplicate-id FAIL in the validator |
| An agent confirms its own rows or clears the unattended marker | Med | High | Operator transitions exist only behind the operator-only `/decisions` command; no skill may call them (bats over frontmatter) |
| `flock`/`timeout` absent on macOS | Med | Med | Portable lock and timeout fallbacks; BSD bats matrix; yq v4 named as a hard dependency |
| Hostile strings corrupt the YAML ledger | Med | High | yq v4 with environment-passed values; hostile-string fixture corpus; validate before rename |

### Success Metrics
- `discovering-requirements/SKILL.md` ≤ 16,384 B with `rounds` present
- At least 34 `DEC` rows in the live ledger, all `proposed` with `proposed_by: agent` (3 from cycle-127, 20 from this PRD, the SDD A-decisions, one per triaged FR-8 command)
- ≥ 4 commands flagged; lint green
- Review and audit APPROVED with consistent LOA-VERDICT trailers

> Sources: prd.md FR-1, FR-2, FR-3, FR-8, Appendix E; sdd.md §1.5 D-1.x, D-2.x, D-3.x, D-8.x, §7 Testing Strategy

---

## Sprint 2: Decision map (`/chart`) and prototype tickets

**Duration:** 1 day
**Dates:** 2026-10-14 - 2026-10-15

### Sprint Goal
Give multi-cycle efforts a decision map on beads that plans and cannot build, and give ungrillable questions a prototype route with a spike discipline.

### Deliverables
- [ ] `.claude/commands/chart.md` and `.claude/skills/charting-decisions/SKILL.md` (+ `resources/`), ≤ 16,384 B, capability frontmatter passing `validate-skill-capabilities.sh`
- [ ] Chart algorithm (destination round, breadth-first fog round, no-fog stop, `map` epic, `question` beads with one `decision:<type>` label each, `br dep` second pass, map doc, research subagents) and work algorithm (load, claim, resolve by type, record via `br comments add` + `br close` + `dec-write-lib.sh decide`, graduate fog, one ticket per session)
- [ ] Map doc template and `validate-artifact.sh --type map`; `grimoires/loa/maps/` convention; `grimoires/loa/research/<slug>.md` convention
- [ ] Lint in `create-sprint-task.sh` and `validate-artifact --type sprint`: a `question` bead under a sprint epic or with a `sprint:` label is rejected
- [ ] `golden-path.sh`: `golden_detect_plan_phase` returns `charting` while a map doc says `**Status**: charting` and `discovery` once it says `handed-off` or `abandoned` (file-based, so it degrades to today's behaviour without `br`); `/plan` reports it and, with several open maps, asks interactively or exits 1 unattended with the message and no artifacts; `/plan-and-analyze` consumes a handed-off map and its `DEC` rows as priority-1 context
- [ ] `interview.unattended_prototype: defer|halt` (default `defer`) in `.loa.config.yaml.example` with bats for both values; `/chart` refuses under an unattended marker (bats via the env override); research subagents capped at 5 per chart and 20 minutes each; CHANGELOG `[Unreleased]` entries for Sprint 2
- [ ] Integration checkpoint at sprint start: the Sprint 1 ledger commands, schema and the live `decisions.yaml` are verified before any `/chart` work
- [ ] Spike discipline: `grimoires/loa/spikes/TEMPLATE.md`, `validate-artifact.sh --type spike`, `run-mode-ice.sh` rule (allow `spike/*` push, refuse `spike/*` merge), the "I need to see it" sentence in the three planning skills, `planning-sprints/resources/REFERENCE.md` "High-Risk Early" pointer

### Acceptance Criteria
- [ ] A fixture one-cycle idea stops at the no-fog check without creating beads
- [ ] A fixture map creates the epic, children, labels and edges under `br --dry-run` and the map doc validates
- [ ] A `question` bead with a `sprint:` label or under a sprint epic is rejected by the lint (bats)
- [ ] `golden-path.sh` returns `charting` with a charting map, `discovery` without one, `discovery` after `/chart close`, and `discovery` with exit 0 when `br` is absent (bats with a `br` stub)
- [ ] Resolving a fixture `question` bead writes a `DEC` row via `decide` with evidence, closes the bead and appends to the map doc; `/plan-and-analyze` Phase 0 with a handed-off fixture map loads the map doc and its `DEC` rows as priority-1 context (bats)
- [ ] `get-ready-work.sh` omits a `question` bead even when it carries a `sprint:` label or sits under a sprint epic (bats)
- [ ] Existing `golden-path`, `run-mode-ice` and `validate-artifact` suites stay green (backward compatibility)
- [ ] `validate-artifact --type spike` passes the template and fails on a missing verdict
- [ ] Fence corpus: `spike/x` push allowed; merging `spike/x` into another branch refused; `main` merged into `spike/x` allowed; `gh pr create --head spike/x` refused; cherry-pick from a `spike/*` ref listed under Misses (bats)
- [ ] The charting skill's frontmatter passes `validate-skill-capabilities.sh`; `check-prompt-budget.sh` green
- [ ] The planning skills carry the prototype sentence (≤ 2 lines each) with budgets green

### Technical Tasks

- [ ] Task 2.1: `charting-decisions` skill + `/chart` command: frontmatter, chart and work algorithms (write order DEC row → bead → map doc, idempotent by source), map doc template with `## Closed`, label and type conventions, unattended refusal, `/chart close`, research-subagent scope (read-only + WebFetch, writes `grimoires/loa/research/` only) → **[G-2]** ⇐ none
- [ ] Task 2.2: Lints: `create-sprint-task.sh` rejects `question` under a sprint epic or with `sprint:`; `get-ready-work.sh` and the implement path exclude `question` beads regardless of labels; `validate-artifact.sh --type map`; sprint validator cross-check → **[G-2]** ⇐ none
- [ ] Task 2.3: `golden-path.sh` `charting` phase (open `map` epic; `discovery` again after `## Closed`); `/plan` routing line and the multiple-open-maps rule (ask interactively, refuse unattended); `/plan-and-analyze` Phase 0 priority-1 load of the map doc and `DEC` rows and closure of the consumed map → **[G-2]** ⇐ Task 2.1
- [ ] Task 2.4: Frontier helper for a map (`get-ready-work.sh --graph` filtered by the map epic) and the claim/resolve shell steps the skill calls → **[G-2]** ⇐ Task 2.1
- [ ] Task 2.5: Spike discipline: `spikes/TEMPLATE.md`, `validate-artifact.sh --type spike`, `run-mode-ice.sh` `spike/*` rule (push allowed; merge into any other branch refused; `main` into spike allowed), `interview.unattended_prototype: defer|halt`, the working-branch rule for report and row, interview sentence in three planning skills, REFERENCE.md pointer → **[G-4]** ⇐ none
- [ ] Task 2.6: Sprint 2 verification: `charting-lint.bats`, `golden-path-charting.bats`, `spike-validator.bats`, ICE fence-corpus case, fixture map dry-run, no-fog stop fixture, budget and capability lints → **[G-2, G-4]** ⇐ Task 2.2, Task 2.3, Task 2.4, Task 2.5

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `create-sprint-task.sh` exit code on a `question` type / `sprint:` label | a decision ticket entering a sprint | a hand-run `br create` that bypasses the helper | `tests/unit/beads-*.bats` |
| `golden_detect_plan_phase` stdout | wrong phase with an open map | `/plan` prose routing | `tests/unit/golden-path.bats` |
| `validate-artifact.sh --type map|spike` | malformed map/spike docs | the quality of a verdict | `tests/unit/validate-artifact.bats` |
| `run-mode-ice.sh` decision for `spike/*` push and merge | a spike merged to a protected branch | a spike copied by hand into `src/` (the implement gate asks) | ICE fence corpus |
| `validate-skill-capabilities.sh` on the new skill | capability/tool mismatch, write-capable agent type | runtime behaviour of the skill | `tests/unit/skill-capabilities.bats` |

### Dependencies
- Sprint 1: `dec-write-lib.sh decide` (resolution rows), `rounds` pacing (the grilling rounds inside `/chart`); verified by the integration checkpoint before Task 2.1 starts
- Rollback: `/chart` is a truename with no auto-start, so removing the command file and the `charting` branch of `golden_detect_plan_phase` restores `/plan`; the ICE spike rule and the `question` exclusion are single `if` blocks; `interview.unattended_prototype: halt` is the conservative setting

### Security Considerations
- **Trust boundaries**: map docs, ticket bodies and research subagent output are agent- or operator-authored text; surfaced as data, never as instructions; research output is sanitised like L6 handoff bodies.
- **External dependencies**: none added; `br` is the only tracker.
- **Sensitive data**: none; `pii-filter.sh` on `--type map|spike`; no execution override exists on the map, so a map cannot authorise App-Zone writes (the implement gate asks on any).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| `decision:unblock` drifts into build work | Med | High | Pocock's `task` type renamed `decision:unblock`; the lint and work algorithm depend on exactly the four labels `decision:grilling|prototype|research|unblock` (SDD §3.2); no `sprint:` label by lint; App-Zone writes ask; body must name the decision it unblocks |
| `/chart` adds ceremony | Med | Med | Multi-cycle trigger only; mandatory no-fog stop; a chart under three tickets is deleted |
| `br` label semantics differ from the design (one `decision:` label per bead) | Low | Med | `question` is a supported `br` type (schema enum); the dry-run fixture in Task 2.6 confirms labels and edges before the skill text is final |
| Phase detection misreads a stale map | Low | Med | Detection keys on the map doc's `**Status**` line (file-based, works without `br`); `/chart close` sets it; maps open over 30 days are listed by the SessionStart surface |

### Success Metrics
- Fixture map: 1 epic, ≥ 3 `question` children, edges present, 0 `sprint:` labels
- `golden-path.sh` phase table has `charting`; bats green
- `spike/*` corpus case green; spike template validates

> Sources: prd.md FR-4, FR-5, UC-2, UC-3; sdd.md §1.5 D-4.x, D-5.x, §5 API Specifications, §7 Testing Strategy

---

## Sprint 3 (Final): Glossary, seams under test, red-test check, E2E

**Duration:** 1 day
**Dates:** 2026-10-15 - 2026-10-16

### Sprint Goal
Complete the decision surfaces with a shared vocabulary and two verifiable test-discipline checks, document the cycle, and validate all PRD goals end to end.

### Deliverables
- [ ] Framework glossary `.claude/loa/GLOSSARY.md` seeded for Loa's vocabulary and the root project `GLOSSARY.md` convention; `validate-artifact.sh --type glossary`; `tools/check-glossary-terms.sh` + `.claude/data/glossary-allowlist.txt` (≤ 30) wired into CI; planning-skill challenge/update sentences; `riding-codebase` reads both glossaries; `reviewing-code` checklist row for undefined new terms
- [ ] `sprint-template.md` `### Seams Under Test` block; sprint validator rule (version-gated so older plans still validate); `planning-sprints` Phase 2 asks seams as a round; `reviewing-code` spec-axis seam check
- [ ] `.claude/scripts/red-test-check.sh` with `--setup` and default symlinking of `node_modules`, `.venv`, `vendor`, `target`, `.tox` into the temp worktrees, a per-run timeout with a `TIMEOUT` verdict, trap-based worktree cleanup; `micro-sprint.md` two-commit rule; `reviewing-code` cites the script's output
- [ ] A report-only run of the glossary checker against `CLAUDE.loa.md` before Task 3.1 sizes the seed and the allowlist; false positives are reviewed before any allowlist entry
- [ ] Docs: CHANGELOG `[Unreleased]`, README what's-new, `hooks-reference.md` rows for the new SessionStart surface and ICE rule, `REPO-MAP.md` regenerated with `.checksum` and `checksums.json` staged together, migration note for the pacing default
- [ ] Task 3.E2E completed with evidence per goal

### Acceptance Criteria
- [ ] `check-glossary-terms.sh` exits 0 on the kernel and 1 when a term is removed from the glossary (bats)
- [ ] `.claude/loa/GLOSSARY.md` validates; every backticked framework term in `CLAUDE.loa.md` resolves (exclusion heuristic applied; allowlist ≤ 30)
- [ ] Sprint validator fails on a missing Seams block for a plan dated on or after 2026-10-13 and still passes the archived cycle-127 plan and undated fixtures
- [ ] `red-test-check.sh` bats: red+green passes; a decoy passing at both commits exits 3; a missing test file or collection error at the red commit exits 4; a timeout yields `TIMEOUT`; a fixture whose test imports an external dependency passes through the bootstrap; `git worktree list` is clean after every case; the red output is printed
- [ ] `micro-sprint.md` Task 1 requires the separate red commit; `reviewing-code` names the script
- [ ] CHANGELOG, README, hooks-reference, REPO-MAP updated; `repo-map` checksum consistent
- [ ] Task 3.E2E: every goal G-1…G-7 validated with documented evidence in a report table (goal, command run, artifact path, pass/fail) under `grimoires/loa/a2a/sprint-254/e2e.md`; G-3 scores a transcript other than the Sprint 1 fixture
- [ ] Existing `validate-artifact`, `reviewing-code` and CI suites stay green (backward compatibility)

### Technical Tasks

- [ ] Task 3.1: Report-only sizing run of the checker over `CLAUDE.loa.md`, then `.claude/loa/GLOSSARY.md` framework glossary seed (incl. `_Aliases_` lines) and the root project `GLOSSARY.md` convention; `validate-artifact.sh --type glossary` → **[G-5]** ⇐ none
- [ ] Task 3.2: `tools/check-glossary-terms.sh` (token exclusion heuristic, case-insensitive plural and alias matching, allowlist ≤ 30) + CI workflow step; planning-skill sentences; `riding-codebase` read; `reviewing-code` checklist row → **[G-5]** ⇐ Task 3.1
- [ ] Task 3.3: Seams Under Test: template block, validator rule gated on the plan `Date` ≥ 2026-10-13 (undated plans WARN), `planning-sprints` Phase 2 round, `reviewing-code` seam check → **[G-6]** ⇐ none
- [ ] Task 3.4: `red-test-check.sh --red <commit> [--green] [--test-file] [--setup] [--timeout] -- <test command...>` (detached temp worktrees with dependency symlinks or `--setup`; red must fail with the output printed; green must pass; decoy exit 3; missing test file or collection error exit 4; `TIMEOUT` verdict via `timeout`/`gtimeout`/bash wrapper; trap cleanup), `micro-sprint.md` two-commit rule, `reviewing-code` citation line → **[G-6]** ⇐ none
- [ ] Task 3.5: Sprint 3 verification: `glossary-terms.bats`, sprint-validator seams bats (new plan fails without the block; cycle-127 plan passes), `red-test-check.bats` with decoy → **[G-5, G-6]** ⇐ Task 3.2, Task 3.3, Task 3.4
- [ ] Task 3.6: Docs and release surfaces: CHANGELOG `[Unreleased]` entries for Sprint 3 and reconciliation of Sprints 1–2, README, `hooks-reference.md`, REPO-MAP + checksums → **[G-1, G-2, G-3, G-4, G-5, G-6, G-7]** ⇐ Task 3.5
- [ ] Task 3.E2E: End-to-End Goal Validation → **[G-1, G-2, G-3, G-4, G-5, G-6, G-7]** ⇐ Task 3.6

### Task 3.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1 … G-7)

**Description:**
Validate that all PRD goals are achieved through the complete implementation, with evidence recorded in the sprint report.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Every planning decision recorded with who decided it | `grimoire-index.sh` → `## decisions`; cycle-127 D1–D3, cycle-128 D1–D21 and the SDD A-decisions as `proposed` rows with `proposed_by: agent`, plus the FR-8 triage rows; PR-body section rendered by `list --not-decided-by operator --format md` (a `proposed` row counts as an agent decision for attribution) | ≥ 34 rows; the section lists every `proposed` row |
| G-2 | A decision map plans and cannot build | fixture map dry-run; lint rejects `question` + `sprint:`; `golden-path.sh` reports `charting` | all three green |
| G-3 | Interview asks in prerequisite-ordered rounds | `check-round-independence.sh` over a transcript other than the Sprint 1 fixture | ≥ 2 questions per round (final exempt), no dependent pair |
| G-4 | Ungrillable questions become prototype tickets | spike template validates; ICE corpus case; prototype sentence in three skills | green |
| G-5 | Shared vocabulary that does not rot | `check-glossary-terms.sh` on `CLAUDE.loa.md` | exit 0; removing a term → exit 1 |
| G-6 | Review verifies test discipline from artefacts | sprint validator on this plan (seams present) and on cycle-127's (no gate); `red-test-check.sh` bats | green; decoy exits 3 |
| G-7 | Operator-only commands unreachable to the model | `user-invoked-commands.bats`; the automated harness check's recorded outcome | green; verified, or partial with the lint-only contingency stated |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence
- [ ] Integration points verified (ledger → INDEX → SessionStart; map → `/plan-and-analyze` context; spike → `DEC` row)
- [ ] No goal marked as "not achieved" without explicit justification

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `check-glossary-terms.sh` exit code on the kernel | an undefined framework term | prose that avoids backticks | `tests/unit/prompt-budget.bats` (CI-check style) |
| `validate-artifact.sh --type sprint` on new vs archived plans | missing Seams block; false failure on old plans | the quality of a declared seam | `tests/unit/validate-artifact.bats` |
| `red-test-check.sh` exit codes on fixture repos | decoy tests, missing red commit | a red test whose assertion is weak (reviewer reads it) | `tests/unit/validate-ac-verification.bats` |
| REPO-MAP checksum consistency | stale map after script changes | nothing beyond drift | `repo-map-gen.sh` sidecar |

### Dependencies
- Sprint 1: ledger rows for the E2E check; Sprint 2: map and spike surfaces for the E2E check
- Rollback: the glossary CI step and the Seams validator rule each sit behind one gate (`check-glossary-terms.yml` and `SEAMS_REQUIRED_FROM`); `red-test-check.sh` is review-time only and can be bypassed by reverting the one `reviewing-code` line

### Security Considerations
- **Trust boundaries**: `GLOSSARY.md` is tracked prose; the drift check reads only the kernel and the glossary; `red-test-check.sh` runs project tests in a temporary worktree it creates and removes (never the live tree).
- **External dependencies**: none added.
- **Sensitive data**: none; the glossary is implementation-free by rule.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Glossary rots | High | Low | Drift check in CI; glossary small by rule; the kernel is the only extraction scope; aliases via `_Aliases_:`; allowlist entries reviewed as false positives first |
| Fresh worktrees lack dependencies for the red test | High | Med | Default symlinks of dependency dirs; `--setup` hook; a fixture with an external dependency in the bats |
| Seams rule breaks validation of archived plans | Med | Med | Date gate (plan header Date ≥ 2026-10-13; undated plans WARN); bats case on cycle-127's plan |
| `red-test-check.sh` gamed by a decoy | Low | Low | Decoy exit 3; reviewer reads the assertion |
| REPO-MAP / checksums drift at commit | Med | Low | Stage REPO-MAP.md, its `.checksum` and `checksums.json` together |

### Success Metrics
- `check-glossary-terms.sh` exit 0 in CI; ≥ 18 glossary entries
- Sprint validator: this plan passes, cycle-127 plan passes
- `red-test-check.bats` 3/3; E2E table complete

> Sources: prd.md FR-6, FR-7, UC-4, §Success Criteria; sdd.md §1.5 D-6.x, D-7.x, §7 Testing Strategy, §11 Appendix

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | `discovering-requirements` budget breach | 1 | High | Med | Task 1.1 first; guarded pointers; CI gate | implementer |
| R2 | `.gitignore` negation ineffective | 1 | Med | Med | `validate-gitignore-state.sh` row; `git check-ignore` bats | implementer |
| R3 | Flagged command needed by an orchestrator | 1 | Low | High | safe set only without triage; operative-reference lint | implementer |
| R9 | Parallel `DEC` id allocation across worktrees | 1–3 | High | High | pending-file import by the lead; duplicate-id FAIL | lead |
| R11 | Agent-forgeable attribution or self-confirmation | 1 | Med | High | operator-only `/decisions`; unattended writes always `proposed`; tamper-evident refs | implementer |
| R10 | Red test cannot run in a bare worktree | 3 | High | Med | dependency symlinks + `--setup`; external-dependency fixture | implementer |
| R4 | `decision:unblock` becomes build work | 2 | Med | High | lint, gate ask, body rule | implementer |
| R5 | `/chart` ceremony | 2 | Med | Med | multi-cycle trigger; no-fog stop | lead |
| R6 | Seams rule breaks old plans | 3 | Med | Med | version gate; archived-plan bats | implementer |
| R7 | Flatline cross-scoring degraded (KF-041) | all | High | Low | integrate raw reviews by judgment | lead |
| R8 | Dissent companion contention (KF-037) | all | Med | Low | ≤ 3 runs per gate; retry when the CLI is idle | lead |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| `DEC` rows seeded | ≥ 34, all `proposed`, all `proposed_by: agent` | `grimoire-index.sh` `## decisions` | 1 |
| Questions per round (fixture) | ≥ 2 | rubric over the transcript | 1 |
| Flagged operator commands | ≥ 4, lint green | `user-invoked-commands.bats` | 1 |
| `question` beads with `sprint:` label | 0, enforced | lint bats | 2 |
| `golden-path.sh` charting detection | correct on both fixtures | bats | 2 |
| Spike corpus case | push allowed, merge refused | ICE bats | 2 |
| Kernel terms without glossary entry | 0 | `check-glossary-terms.sh` | 3 |
| `red-test-check.sh` decoy detection | exit 3 | bats | 3 |
| Review + audit per sprint | APPROVED, consistent trailers | `verdict-derive.sh` | all |

---

## Dependencies Map

```
Sprint 1 (252) ──────────────▶ Sprint 2 (253) ──────────────▶ Sprint 3 (254)
   │ rounds, DEC ledger,          │ /chart on the ledger,        │ glossary, seams,
   │ fact/decision, FR-8          │ prototype tickets            │ red test, docs, E2E
```

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| FR-1 Rounds | Sprint 1 | Planned |
| FR-2 Fact/decision split | Sprint 1 | Planned |
| FR-3 Decision ledger | Sprint 1 | Planned |
| FR-8 Operator-only commands | Sprint 1 | Planned |
| FR-4 Decision map (`/chart`) | Sprint 2 | Planned |
| FR-5 Prototype tickets and spikes | Sprint 2 | Planned |
| FR-6 Glossary | Sprint 3 | Planned |
| FR-7 Seams and red-test check | Sprint 3 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| D-1.x rounds pacing (REFERENCE.md §Question Pacing, config default) | Sprint 1 | Planned |
| D-2.x fact/decision rule and PR-body section | Sprint 1 | Planned |
| D-3.x `decisions.yaml` schema, `dec-write-lib.sh`, INDEX section, SessionStart surface, validator type | Sprint 1 | Planned |
| D-8.x user-invoked command allowlist and lint | Sprint 1 | Planned |
| D-4.x `/chart` command, `charting-decisions` skill, map doc, lints, golden-path phase, frontier helper | Sprint 2 | Planned |
| D-5.x spike template, validator type, ICE rule, interview sentence | Sprint 2 | Planned |
| D-6.x `GLOSSARY.md`, drift check, validator type, skill sentences | Sprint 3 | Planned |
| D-7.x Seams Under Test block, validator gate, `red-test-check.sh`, micro-sprint rule | Sprint 3 | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Every planning decision recorded with who decided it | Sprint 1: Task 1.3, Task 1.4, Task 1.5, Task 1.6, Task 1.7, Task 1.9 | Sprint 3: Task 3.E2E |
| G-2 | A decision map that plans and cannot build | Sprint 2: Task 2.1, Task 2.2, Task 2.3, Task 2.4, Task 2.6 | Sprint 3: Task 3.E2E |
| G-3 | Interview asks in prerequisite-ordered rounds | Sprint 1: Task 1.1, Task 1.2, Task 1.9 | Sprint 3: Task 3.E2E |
| G-4 | Ungrillable questions become prototype tickets | Sprint 2: Task 2.5, Task 2.6 | Sprint 3: Task 3.E2E |
| G-5 | Shared vocabulary that does not rot | Sprint 3: Task 3.1, Task 3.2, Task 3.5 | Sprint 3: Task 3.E2E |
| G-6 | Review verifies test discipline from artefacts | Sprint 3: Task 3.3, Task 3.4, Task 3.5 | Sprint 3: Task 3.E2E |
| G-7 | Operator-only commands unreachable to the model | Sprint 1: Task 1.0, Task 1.8, Task 1.9 | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All PRD goals have at least one contributing task
- [x] All goals have a validation task in the final sprint
- [x] No orphan tasks (Task 3.6 contributes to every goal through documentation)

### D. Flatline review integration (2026-10-13)

Two voices (codex-headless as `gpt-5.5`, claude-headless), cross-scoring degraded (KF-041, exit 6); integrated by judgment. Blockers integrated: ledger single-writer rule (later refined into the pending-file import mechanism by the SDD review) and duplicate-id FAIL, yq v4 writer with a hostile-string fixture corpus, red-test dependency bootstrap, automated harness check for FR-8 with a lint-only contingency. The SDD review's seven blockers (forgeable attribution, self-confirmation via an agent-controlled marker, unmergeable ledger, portability, operator-row supersession) are reflected in Tasks 1.4–1.7, the acceptance criteria and risks R9 and R11. Improvements integrated into the task lines, acceptance criteria, rollback lines, risk tables and the E2E report format (gpt IMP-001…015, opus IMP-001…030). Narrowed: the glossary CI step lands as FAIL after a report-only sizing run rather than a WARN-first release (opus IMP-017); the `red-test-check.sh` test command stays free-form, taken from the micro-sprint's `Test command:` line, rather than an allowlisted runner (opus IMP-014).

**Per-Sprint Goal Contribution:**

Sprint 1: G-1 (complete: ledger + attribution), G-3 (complete: rounds), G-7 (complete: flag + lint)
Sprint 2: G-2 (complete: map), G-4 (complete: spikes)
Sprint 3: G-5 (complete: glossary), G-6 (complete: seams + red test), E2E validation of all goals

---

*Generated by Sprint Planner Agent*
