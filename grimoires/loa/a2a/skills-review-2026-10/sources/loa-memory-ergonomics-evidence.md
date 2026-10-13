# Loa memory, decision records and skill ergonomics — evidence

Gathered 2026-10-12, read-only, repo `0xHoneyJar/loa` on `main` at `76e7650b` (framework 2.0.0-rc.3).
Purpose: comparison input against Matt Pocock's skills repo (GLOSSARY.md + ADRs, Claude plugin distribution, user- vs model-invoked split, stateless /grill-me, /writing-for-agents, /handoff).
All quotes ≤ 2 lines. Paths are repo-relative.

---

## PART 1 — Memory and decision records

### M1. grimoires/loa/NOTES.md

- **Size**: 136,559 B, 356 lines (`wc -c -l`). **Gitignored, per operator**: `.gitignore:299: grimoires/loa/NOTES.md`; context-engineering.md:14 calls it "untracked per-operator NOTES.md (gitignored)".
- **Section types present** (by heading): `## Session Continuity — <date> (...)` (lines 3, 24, 307), `## Decision Log — <date> (<cycle/sprint context>)` (≈20 headings, lines 30–294), ad-hoc `## Sprint N CLOSED` / `## Late … input` (245–273), `## Blockers` (321), `## Archive pointers` (325), `## Observation — <date> (...)` (331, 337, 343), `## Learnings` (351, empty: "*Extracted learnings will be added here.*").
- **Decision Log entry shape (actual)**: one heading per cycle/sprint/session, then a narrative bullet list. Example NOTES.md:30 "## Decision Log — 2026-10-07 (cycle-127 "operator decisions": maintainer delegation with admin preapproval)". Inside, decisions are ad-hoc labelled bullets: NOTES.md:37 "**D1 — agy opt-in, default off** (bd-ugmi). Facts: … Decision: a config key (default off) gates the agy route". Bullets often carry a bead ID (`bd-ugmi`, `bd-9qe2`) and commit SHAs, and sometimes "Facts / Decision" sub-structure, plus GOTCHA bullets (NOTES.md:41).
  - No per-decision ID scheme, no status field, no superseded-by, no formal alternatives/consequences sections. Linking is one-way: the note cites beads; beads/sprint plans do not link back to NOTES entries (none found).
- **Prescribed format (protocol) vs practice**: `.claude/protocols/reference/session-continuity.md:156-189` prescribes `## Session Continuity` with `### Active Context`, `### Lightweight Identifiers` (path table with `${PROJECT_ROOT}` prefix), `### Decision Log` with `#### <ISO ts> - Decision Title` + **Decision / Rationale / Evidence / Test Scenarios**, and `### Pending Questions`. The live file uses top-level dated Decision Log sections with narrative bullets instead — the template is not followed.
- **Truth hierarchy**: session-continuity.md:57 "code … > Beads … > `NOTES.md` (decision log, session continuity) > trajectory > PRD/SDD (design intent, may drift)".
- **Compaction/size rules** (`.claude/loa/reference/context-engineering.md`, 40 lines, a pointer map):
  - :9 tool-result clearing + NOTES.md synthesis is "the live context rule" (`context_discipline` blocks in each SKILL.md, `.claude/protocols/tool-result-clearing.md`).
  - :11 compaction survival = `pre-compact-marker.sh` (PreCompact) + `post-compact-reminder.sh` (UserPromptSubmit), "mechanical, zero thinking-budget".
  - :15 memory size gate: "`notes-guard.sh` (`check` 100 KiB warn / 200 KiB block, `read` ≤ 68 KiB by heading, `rotate`) + `notes-size-guard.sh` (PreToolUse Write/Edit…)". The live file (136.5 KB) is above the warn line.
  - session-continuity.md:96 tier-1 recovery reads "Blockers + newest Session Continuity + 3 newest Decision Logs, ≤ 68 KiB"; :121 "Write decisions to the NOTES.md Decision Log immediately."
  - :14 cross-session memory = Claude Code auto-memory (per user) + git-tracked team surfaces (KF ledger, GT files) + NOTES.md.
  - :20-22 the "Five-YAML memory schema" was "Never built; auto-memory owns the scope".
- **Rotation**: older notes archived to `grimoires/loa/archive/2026-07-29-notes-pre-cycle-121.md` (NOTES.md:327).

### M2. ADRs / decision records

ADRs **do exist**, but outside `grimoires/` (the scoped grep in the task misses them):

| File | Bytes | Status line | Sections |
|---|---|---|---|
| docs/architecture/ADR-001-cycle-099-model-registry.md | 13,905 | table "Status \| Decided", Date 2026-05-06, Deciders, Tags, Supersedes, Related | Context / Decision / Alternatives considered / Trade-offs accepted / Outcomes / Open questions / Refs |
| docs/architecture/ADR-002-multimodel-cheval-substrate.md | 14,452 | "> **Status**: Accepted", Released v1.157.0 | Context / Decision / Rationale / Alternatives considered / Consequences / Verification / References |
| docs/architecture/ADR-003-mechanical-floor.md | 5,535 | Accepted, v1.196.0 | Context / Decision / Alternatives / Consequences / Outcome |
| docs/architecture/ADR-004-model-generation-floor.md | 9,138 | "Accepted (release candidate)", v2.0.0-rc.1 | Context / Decision / Alternatives / Trade-offs / Outcomes / Open questions |

- **How produced**: hand-written at named-release milestones, one per release epoch, not per decision. `git log`: ADR-001 in `cb633ca4` "chore(release): v1.130.0 — named milestone", ADR-003 in `bbd85506` "release(v1.196.0): Mechanical Floor — CHANGELOG rollup, migration guide, ADR-003", ADR-004 in `53ea2168` "docs(release): 2.0.0-rc.1 release-candidate deliverables". CHANGELOG links them (CHANGELOG.md:359, :395). Four ADRs across ~127 cycles.
- **No skill or command produces ADRs.** grep of `.claude/skills .claude/commands .claude/scripts` for "docs/architecture/ADR" / "ADR-00" returns only template/marker examples (`riding-codebase/resources/context-templates.md:35` "### ADR-001: [Decision Title]").
- **Unbuilt decision-record protocol**: `docs/architecture/decision-lineage.md` specifies `grimoires/loa/decisions.yaml` with `id: DEC-0001`, timestamp, phase, category, summary, decision, rationale, `alternatives_considered`, `consequences` (positive/negative), and a "Rule of Thumb: Would someone ask 'why?' about this in 6 months?". The file **does not exist** (`ls grimoires/loa/decisions.yaml` → no such file). Readers exist for it: `.claude/scripts/loa-learnings-index.sh:421`, `path-lib.sh:483`.
- **ADR consumption (read side)**: `/ride --enriched` Phase 13 "Decision Archaeology" (`riding-codebase/resources/references/enrichment-phases.md:165-250`) detects `docs/decisions/`, `docs/adr/`, `adr/`, `knowledge/decisions/`, `docs/architecture/decisions/`, `.adr-dir`; parses Status/Date/Decision/Alternatives/Consequences/"revisit when"; flags staleness; writes `grimoires/loa/reality/decisions.md`. Loa's own run (`grimoires/loa/reality/decisions.md:1-30`, 2026-05-04) concluded "The framework does NOT use the standard `docs/adr/` convention" and found decisions in `grimoires/loa/proposals/` (29 files, RFC-060..062 etc.) and per-cycle decision dirs. It did not find `docs/architecture/ADR-*` (not in its search list).
- **Other decision-ish surfaces**: `grimoires/loa/proposals/*.md` (RFCs, e.g. `rfc-060-spiral.md`, `copyset-ungitignore-decision-2026-07-07.md`); SDD design decisions numbered per cycle (NOTES.md:31 cites "SDD §1.5 (D-1.5…D-3.9)"); beads comments.

### M3. Glossary / shared domain language

- `find . -iname 'GLOSSARY*'` → only `.claude/data/lore/mibera/glossary.yaml` — a **lore** glossary of the framework's mythic vocabulary (`id: glossary-loa`, `term: "Loa"`, `short: "Spirits of Vodou tradition via Gibson's Sprawl trilogy …"`). Not a project domain glossary.
- Glossary **templates** only: PRD template appendix `discovering-requirements/resources/templates/prd-template.md:277` "### D. Glossary" (Term/Definition table); SDD template `designing-architecture/resources/templates/sdd-template.md:384` "### A. Glossary"; SOUL.md optional `## Glossary` (`soul-identity-doc/SKILL.md:82`); exec-translation templates. Some PRDs filled it (`grimoires/loa/prd-destructive-command-guard.md:591`, `prd-post-pr-validation.md:447`) — per-document, not shared.
- No "ubiquitous language" / "domain language" concept anywhere in skills/protocols (grep empty apart from a BB persona line on "data model"). No per-project glossary file, no skill that maintains one. `designing-architecture` has a domain-model **class-diagram** template (`resources/templates/diagrams/class-domain.md`).
- **BUTTERFREEZONE.md** (root, 11,987 B, 243 lines): skill description "the agent-grounded README (token-efficient, provenance-tagged project summary)" (`butterfreezone-gen/SKILL.md:3`). Starts with an `<!-- AGENT-CONTEXT … -->` YAML block (name, type, purpose, key_files, interfaces, dependencies, ecosystem, capability_requirements, version, trust_level), then `<!-- provenance: CODE-FACTUAL -->`-tagged sections: Key Capabilities, Slash commands, Key bash entry points, Architecture, Interfaces, Module Map, Verification, Agents, Culture, Quick Start. **No glossary section.** It is **stale**: `version: v1.147.0` (BUTTERFREEZONE.md:30) and "40 specialized skills" (:40) vs 36 SKILL.md today; last commit `7fc875ff` 2026-05-12.
- **AGENTS.md** (root, 4,104 B) generated by `.claude/scripts/agents-md-gen.sh` — "GOVERNANCE + CONVENTIONS surface read first by 25+ agent tools", deterministic with a `--check` drift gate (header lines 2-19). Also no glossary.

### M4. Lore

- Two lore stores: framework `.claude/data/lore/` (README, `index.yaml`, `mibera/{core,cosmology,rituals,glossary}.yaml`, `neuromancer/{concepts,mappings}.yaml`, `discovered/{patterns,visions}.yaml`) and project `grimoires/loa/lore/` (`index.yaml`, `patterns.yaml` 659 lines, two design docs).
- What it is: `.claude/data/lore/README.md:3` "Cultural and philosophical context for agent skills … naming context, architectural metaphors, and philosophical grounding". Entry schema: `id, term, short, context, source, source_model, tags, loa_mapping` (`discovered/patterns.yaml` header). Discovered entries are engineering patterns mined from reviews, e.g. `graceful-degradation-cascade`.
- **Written by** the run-bridge loop: `run-bridge/SKILL.md:191-197` LORE_DISCOVERY "Invokes `lore-discover.sh` to extract patterns from bridge reviews" then `vision_check_lore_elevation()` / `vision_append_lore_entry()`; "Data flow: bridge finding JSON → vision entry → index update → lore elevation check".
- **Read back** at review time: `run-bridge/SKILL.md:219-227` "Lore Load: Query lore index … Load `short` fields inline in the review prompt. Use `context` for teaching moments." `grimoires/loa/lore/index.yaml:2-3` "Updated by: bridge vision elevation, retrospective analysis, manual curation / Queried by: bridge lore loading …, memory-query.sh".
- Lore is the nearest thing to a shared vocabulary, but it names patterns and metaphors, not project domain terms.

### M5. Known-failures ledger (compounding memory)

- `grimoires/loa/known-failures.md`: 226,714 B, 1,671 lines, 42 `## KF-NNN:` entries. Header :3-12 "Read this file at session start … records what *didn't* fix the problem … **Append-only.**" with three allowed mutations (recurrence++, add Attempts row, flip status).
- Schema (:19-41): Status, Feature, Symptom, First observed, **Recurrence count**, Current workaround, Upstream issue, Related visions/lore, an **Attempts** table (Date / What we tried / Outcome / **Evidence**), and a **Reading guide**. :43-46 "A recurrence_count ≥ 3 means the failure is structural; stop re-attempting prior fixes". :48-51 the Evidence column "protects against demotion-by-relabel".
- Writer: `.claude/scripts/lib/kf-write-lib.sh:1-33` — ops `new`, `attempt` (evidence REQUIRED), `recur`, `notes-header`; flock + verify (never shrinks, never drops a KF id) + atomic rename; "never a bot auto-append, never `git stash`".
- Reader: generated `grimoires/loa/INDEX.md` (22,539 B) via `grimoire-index.sh`, sections `## handoff (2)`, `## kf (40)`, `## lore (4)`, `## notes (31)`, `## vision (8)` (INDEX.md:7,14,59,68,104). The kf section is a table ID / Status / Recurrence / Symptom / Title / Path; e.g. KF-004 recurrence 31. Surfaced at SessionStart by `loa-kf-surface.sh` (default-off config gate). Three-tier progressive disclosure: INDEX row → entry Reading guide → full file (context-engineering.md:12; project CLAUDE.md "Context Intake Discipline").
- This is a failure memory, not a decision or vocabulary memory, but it is the one Loa memory surface with a schema, a writer library, a generated index and session-start surfacing.

### M6. Handoff and compaction

- `.claude/skills/structured-handoff/SKILL.md` (5,418 B): "L6 structured-handoff — schema-validated markdown+frontmatter handoff documents with content-addressable handoff_id, atomic INDEX.md update, and OPERATORS.md cross-check". Writes to `grimoires/loa/handoffs/` (2 handoffs + INDEX.md exist, both 2026-05). Use for "Operator ↔ operator (or operator ↔ session) context handoff that must survive multiple sessions"; not for quick observations (→ NOTES.md) or preferences (→ auto-memory). `handoff_id = sha256:` of canonical JSON. `allowed-tools: Read, Bash`; writes via its lib script, so `write_files: false`. Triggered explicitly (operator/agent call), not by compaction. It is a structured mailbox; it does not compact a conversation the way Pocock's `/handoff` does.
- Compaction is handled by hooks, not a skill: `pre-compact-marker.sh` "creates a marker file that the post-compact-reminder hook will detect"; `post-compact-reminder.sh` "outputs a reminder message … then deletes the marker (one-shot delivery)". Recovery content = run state file + `notes-guard.sh read` tiers.
- SessionStart hooks (`.claude/settings.json` `.hooks.SessionStart`, all `once: true`):
  | Hook | Prints / does |
  |---|---|
  | `.claude/scripts/check-updates.sh --notify` (async) | update-available notice |
  | `session-start/loa-l6-surface-handoffs.sh` (async) | unread L6 handoffs addressed to the operator (git email → OPERATORS.md slug), body sanitized |
  | `session-start/loa-l7-surface-soul.sh` (async) | SOUL.md identity body, schema-validated and sanitized; silent unless `soul_identity_doc.enabled` |
  | `session-start/loa-run-mode-session-title.sh` (async) | sets session title when an autonomous run is active |
  | `hooks/loa-kf-surface.sh` | compact symptom → KF table; default-off (`known_failures.surface_at_session_start`) |
  | `session-start/loa-run-state-surface.sh` (via hook-guard) | "Run: <file> <STATE> (<age>) → <command>" resume line |
  | `session-start/loa-context-class.sh` (via hook-guard) | writes `.run/context-class` (long ≥1M vs standard) for the context-discipline thresholds |

---

## PART 2 — Skill ergonomics

### S1. The 16 KiB SKILL.md budget, and sizes

- Enforced by `tools/check-prompt-budget.sh` (header :3-19; constants :53 `SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 160000, 114688`). The charge includes resources: ":8 charged with every resources/*.md the skill reads UNCONDITIONALLY". An unguarded "read/load/source/include" line naming a resource is charged. A line with a guard word ("if / when / only / see …") is a pointer, not charged.
- CI: `.github/workflows/check-prompt-budget.yml` (every PR, plus sentinel steps that prove the gate bites). Its header comment still says "protocols total ≤ 200,000 B (warn > 143,360 B)" while the script enforces 160,000 / 114,688 — comment drift.
- Test: `tests/unit/prompt-budget.bats` — PB-1 "a SKILL.md of exactly 16,384 bytes passes" (:29); breach message "skill s1: 16385 B > 16384 B" (:39).
- Origin: ADR-004:25 "Byte budgets (skill ≤ 16,384 B, kernel ≤ 10,240 B, …) enforced on every PR" (cycle-124, 2026-09).
- Kernel `.claude/loa/CLAUDE.loa.md` ≤ 10,240 B; cycle-126 took it 10,225 → 9,199 B (commit `41b783a1`).

**36 SKILL.md files** in 41 skill directories. Five dirs hold only a `persona.md` for model-invoked review voices: flatline-attacker, flatline-reviewer, flatline-scorer, flatline-skeptic, gpt-reviewer. Total SKILL.md bytes 416,502, mean 11,570. 12 skills sit within 340 B of the 16,384 cap, so the cap binds.

| Skill dir | Bytes | Lines |
|---|---|---|
| planning-sprints | 16370 | 403 |
| simstim-workflow | 16368 | 420 |
| riding-codebase | 16346 | 345 |
| discovering-requirements | 16304 | 352 |
| deploying-infrastructure | 16294 | 363 |
| loa-setup | 16289 | 512 |
| reviewing-code | 16287 | 304 |
| auditing-security | 16268 | 297 |
| implementing-tasks | 16221 | 256 |
| autonomous-agent | 16211 | 261 |
| bug-triaging | 16181 | 444 |
| scheduled-cycle-template | 16049 | 276 |
| continuous-learning | 15747 | 462 |
| run-mode | 15372 | 295 |
| rtfm-testing | 15317 | 422 |
| designing-architecture | 15006 | 386 |
| translating-for-executives | 14531 | 367 |
| run-bridge | 14237 | 333 |
| mounting-framework | 11327 | 373 |
| graduated-trust | 10863 | 230 |
| hitl-jury-panel | 10536 | 199 |
| spiraling | 9108 | 208 |
| cost-budget-enforcer | 8934 | 228 |
| browsing-constructs | 8077 | 282 |
| enhancing-prompts | 7948 | 277 |
| bridgebuilder-review | 7729 | 159 |
| soul-identity-doc | 7652 | 181 |
| validating-construct-manifest | 7432 | 139 |
| loa-aleph | 6705 | 146 |
| cross-repo-status-reader | 6417 | 173 |
| flatline-knowledge | 6299 | 238 |
| red-teaming | 6264 | 164 |
| structured-handoff | 5418 | 133 |
| managing-credentials | 4273 | 119 |
| butterfreezone-gen | 3918 | 138 |
| eval-running | 2204 | 90 |

The full skill directory, including `resources/*.md` loaded on demand, is much larger. Examples: auditing-security 88,445 B across 14 files, riding-codebase 81,017 B, reviewing-code 78,335 B, autonomous-agent 72,380 B. Figures exclude dist/node_modules.

**Commands**: 54 `.claude/commands/*.md`.

| Statistic | Bytes |
|---|---|
| min | 500 |
| median | 4,744 |
| max | 22,505 |
| total | 313,545 |

`/loa` is 21,645 B. The golden-path commands are plan 7,575, build 2,238, review 2,979 and ship 2,997 B. Commands have **no byte budget**.

### S2. The cycle-116 skill diet

- CHANGELOG.md:142 "skill token diet (−20.7%)". The method is in commit `4dcfc770` (2026-07-06), "feat(skill-diet): progressive-disclosure restructure of top-5 SKILL.md bodies": "Every SKILL.md loads in full on each invocation; content moved to resources/*.md loads only when the skill directs a read. Verbatim relocations + two authorized dedups; nothing deleted".
  | Skill | Before (B) | After (B) | Change |
  |---|---|---|---|
  | discovering-requirements | 48,555 | 37,712 | −22.3% |
  | implementing-tasks | 43,367 | 36,301 | −16.3% |
  | riding-codebase | 42,330 | 28,391 | −32.9% |
  | reviewing-code | 39,432 | 32,377 | −17.9% |
  | auditing-security | 37,314 | 32,454 | −13.0% |
  | total | 210,998 | 167,235 | −20.7% |
- Rules followed: "Decision logic (approve/reject gates, YAGNI taxonomy, skip-conditions) stays in-body; lookup tables/templates move". Retrospective postludes went to `resources/RETROSPECTIVE.md`. Lookup material went to `resources/REFERENCE.md` and templates to `resources/templates/`. riding-codebase's opt-in Phases 11–15 (16.1 KB) moved behind skip stubs. A word-bag content-preservation verifier passed on all five. A `skill-resource-read-correlator.sh` mines transcripts for which resources are actually read.
- The follow-on cycles made the diet mechanical. Cycle-121 ran a context diet that deleted 13 dead protocols (`69f9bee8`). Cycle-124 added the 16 KiB gate, a 49-unit prompt audit and `no-history-in-rule-text.bats`. Cycle-126 moved five protocols to `protocols/reference/` (`41b783a1`). At that time the five skills were still 28–38 KB, so a second cut to ≤16 KiB happened in cycle-124 (ADR-004:62 "13/13 skills ≤ 16,384 B").

### S3. Frontmatter schema; user- vs model-invoked

- `.claude/scripts/validate-skill-capabilities.sh` header (:5-12) checks: `capabilities:` presence (deny-all if missing), `schema_version: 1`, capabilities vs `allowed-tools` consistency, no `capabilities: all`, strict `execute_commands` grammar, and a `cost-profile` that is present, valid and matches the capabilities. Further checks:
  - `model:`/`agent:` invariants: "role: $role MUST NOT declare agent: frontmatter" for verdict-bearing roles (:145-171).
  - a write-capable `agent:` type, using the allowlist from `.claude/data/agent-types.yaml` (:119-140).
  - `REVIEW_WRITE_EXCEPTIONS` (:90).
  - the `role`/`primary_role` and `inputs:` manifest (:264-433).
- Keys observed in the three representative frontmatters:
  | Key | discovering-requirements | implementing-tasks | reviewing-code |
  |---|---|---|---|
  | name | `plan-and-analyze` | `implement` | `review-sprint` |
  | description | yes | yes | yes |
  | role | planning | implementation | review |
  | effort | — | xhigh | xhigh |
  | allowed-tools | Read, Grep, Glob, AskUserQuestion, WebFetch, Write, Bash(git log *), Bash(wc *) | (absent) | Read, Grep, Glob, Write, Edit, WebFetch, scoped Bash(...) |
  | disallowed-tools | — | — | NotebookEdit |
  | capabilities.* | schema_version, read_files, search_code, write_files, execute_commands{allowed[], deny_raw_shell}, web_access, user_interaction, agent_spawn, task_management | same, execute_commands: true | same |
  | cost-profile / parallel_threshold / timeout_minutes | moderate/2000/90 | heavy/3000/120 | moderate/3000/60 |
  | zones{system,state,app} | yes | yes | yes |
  | inputs[] (ICM advisory manifest) | — | known-failures.md, CLAUDE.md | known-failures.md, CLAUDE.loa.md |
  | agent / model / triggers / user-invocable | none | none | none |
- **No key marks a skill as user-invoked or model-invoked.** No SKILL.md uses `user-invocable` or `disable-model-invocation`. The only use is in the command `.claude/commands/gpt-review.md:4` `disable-model-invocation: true`. Every skill is therefore both model-loadable and `/`-invocable.
- **The command ↔ skill relationship.** The split is carried by `.claude/commands/*.md`, the user slash commands, against `.claude/skills/`, the skill bodies.
  - A command links to its skill through frontmatter `agent:` + `agent_path:`. For example `.claude/commands/plan-and-analyze.md:18-19` has `agent: "discovering-requirements"` and `agent_path: "skills/discovering-requirements/"`, plus `context_files[]` (priority-ordered), `pre_flight[]` checks and `arguments[]`.
  - The command body carries the user-facing phase description. 24 of 54 commands link a skill this way. The other 30 are pure command workflows (loa, plan, build, review, ship, update-loa, ledger, archive-cycle, …).
  - The skill's own `name:` is set to the **command name**: discovering-requirements is `name: plan-and-analyze`, implementing-tasks is `implement` and reviewing-code is `review-sprint`. Each pipeline phase therefore surfaces twice, as the command and as the skill directory. This session's skill list shows both "discovering-requirements" and "plan-and-analyze".
  - Golden-path commands such as `/plan` route on to the truename commands. `.claude/commands/plan.md` says "routes to the existing truename commands (`/plan-and-analyze`, `/architect`, `/sprint-plan`) based on your current state" using `golden_detect_plan_phase`.
- The `agent:` key in SKILL.md is set to `general-purpose` on 6 skills: bug-triaging, cost-budget-enforcer, cross-repo-status-reader, graduated-trust, hitl-jury-panel and scheduled-cycle-template. `.claude/rules/skill-invariants.md` governs it: write-capable skills MUST NOT dispatch to a read-only agent type.

### S4. Distribution

- **Install**: README.md:47-53 has `curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash`, or a pinned `… | bash -s -- --tag v2.0.0-rc.3`. The README notes that v1.202.1 is the latest stable. README.md:66 says "you should see `.loa/` (submodule), `.claude/` (symlinks), `grimoires/loa/`, and `.loa.config.yaml`". README.md:68 lists three ways to install: submodule (default), clone template, and vendored (legacy).
- `mount-loa.sh` uses `SUBMODULE_MODE=true` by default (:289), with flags `--vendored` (:346) and `--migrate-to-submodule` (:333). It handles curl-pipe detection by re-downloading its helper scripts (:2-12, :62).
- **Version and integrity**: `.loa-version.json` holds `framework_version: "2.0.0-rc.3"`, `schema_version: 2`, zones and `migrations_applied`. `.claude/checksums.json` holds `{algorithm, files, generated}`.
- **Update**: `.claude/commands/update-loa.md` (v1.3.0, `command_type: "git"`). It runs pre-flight checks for a clean tree and a `loa`/`upstream` remote, configures the `merge.ours` driver, then fetches, previews, confirms and merges "with conflict guidance". The mounted framework is a git submodule, symlinked into `.claude/`. Releases come from semver tags and the CHANGELOG, through `semver-bump.sh` and `post-merge-orchestrator.sh`.
- **No Claude plugin manifest.** `find` for `plugin.json`, `marketplace.json` and `.claude-plugin/` (depth ≤3, excluding node_modules) returned nothing. Loa ships no marketplace or plugin packaging and no Codex/Copilot/Gemini/`npx skills` variant. The cross-tool reach is `AGENTS.md` (agents-md-gen.sh, "read first by 25+ agent tools").
- **Constructs** are Loa's add-on packaging. `.run/construct-index.yaml` exists. It is generated 2026-10-07 and lists `pack_count: 1`: `gtm-collective` v1.1.0 with 8 skills and commands such as `analyze-market` and `position`, plus `persona_path: null` and `quick_start`.
  - A construct is a pack: `construct.yaml` (schema_version, slug, name, version, description), `skills[].path`, `commands[].path`, optional `personas:`, `reads:`/`writes:` typed streams, and a `CLAUDE.md` with a `grimoires/<path>` interface declaration (`validating-construct-manifest/SKILL.md` Purpose §1-5, Concepts).
  - Distribution goes through the Constructs Network registry API, `LOA_CONSTRUCTS_API_URL`, default `https://api.constructs.network/v1`, with an API key for premium packs (`browsing-constructs/SKILL.md` API Configuration). `/constructs install <slug>` runs `.claude/scripts/constructs-install.sh pack <slug>`. "Installed packs go to `.claude/constructs/packs/` which is gitignored" (browsing-constructs/SKILL.md:272).
  - The validator is "not yet" wired into install (validating-construct-manifest/SKILL.md, Invocation).
  - Resolution uses `construct-resolve.sh resolve|compose`, per the project CLAUDE.md.

### S5. Statelessness

`capabilities.write_files: false` is set on 15 skills:

- browsing-constructs
- butterfreezone-gen
- cost-budget-enforcer
- cross-repo-status-reader
- enhancing-prompts
- eval-running
- flatline-knowledge
- graduated-trust
- hitl-jury-panel
- managing-credentials
- rtfm-testing
- scheduled-cycle-template
- soul-identity-doc
- structured-handoff
- validating-construct-manifest

Caveat: `write_files: false` means the skill does not use the Write/Edit tools. It does not mean the skill leaves no state. Several of these skills persist through allowed scripts:

- butterfreezone-gen runs `butterfreezone-gen.sh`, which writes BUTTERFREEZONE.md.
- structured-handoff and soul-identity-doc use `Bash` and lib scripts. structured-handoff writes `grimoires/loa/handoffs/`.
- browsing-constructs installs packs.

The truly read-only set, with no execute_commands or only test/eval execution, is:

- flatline-knowledge (`allowed-tools: Read, Grep, Glob`, execute_commands false)
- enhancing-prompts (Read, Grep, Glob)
- validating-construct-manifest (execute_commands false)
- eval-running and rtfm-testing (test runners only)

None of them disallows `Write` through `disallowed-tools`. Only 4 skills declare `disallowed-tools`: reviewing-code and auditing-security disallow NotebookEdit, and red-teaming and bridgebuilder-review disallow NotebookEdit plus git add/commit.

There is no stateless interview skill like `/grill-me`. The interview-driven skills are discovering-requirements (`user_interaction: true`, AskUserQuestion) and bug-triaging ("hybrid interview"). Both write artifacts: the PRD, and the triage plus micro-sprint.

### S6. Composability and routing

- Skills compose by naming **slash commands in prose and shell steps**, not by `Skill(...)` calls. A grep for "Skill(" or "Skill tool" in SKILL.md files is empty.
  - The orchestrators sequence the phase skills. run-mode/SKILL.md:104-113 lists "1. /implement $target … 4. /review-sprint $target … 7. /audit-sprint $target". simstim-workflow, autonomous-agent, run-bridge and spiraling also orchestrate.
  - Counts of `/implement|/review-sprint|/audit-sprint` mentions per skill: run-mode 8, autonomous-agent 6, continuous-learning 4, bug-triaging 3.
  - Handoffs between phases are **files**: prd.md → sdd.md → sprint.md → a2a/ reviewer/feedback → COMPLETED markers. They are gated by `verdict-derive.sh` on the LOA-VERDICT trailer.
- **Router** is `/loa` (`.claude/commands/loa.md`, `command_type: wizard`, 21,645 B). It says to "Show current workflow state, health, progress, and suggest the next command. The **universal entry point** … the only command you need to remember." Its flags include `--help`, which shows the 5 Golden Path commands, `--help-full` for all 43+, `--json`, `doctor` and `status --economy`.
  - `.claude/scripts/golden-path.sh` header :1-20 calls it "Porcelain & Plumbing (git model): Golden Path = porcelain (5 commands for 90% of users), Truenames = plumbing (43 commands for power users)".
  - Its functions include `golden_detect_plan_phase`, `golden_detect_sprint`, `golden_suggest_command` (:722) and `golden_resolve_truename` (:1042). This is a state-machine router: it detects which artifacts exist and suggests the next command. It does not route on topic the way `/ask-matt` does.

### S7. Writing for agents

Loa has no general "how to write agent-readable docs" skill. The guidance is spread across generators, gates and an audit method.

- **BUTTERFREEZONE** is described as "provenance-tagged, checksum-verified, token-efficient" (`butterfreezone-gen.sh:5`). It carries an `AGENT-CONTEXT` YAML block and `<!-- provenance: CODE-FACTUAL|OPERATIONAL|… -->` tags per section (:365, :969).
- **AGENTS.md** is generated deterministically, with no timestamps, by `agents-md-gen.sh` and drift-gated with `--check`.
- **The prompt-audit method** lives at `grimoires/loa/archive/2026-09-23-cycle-124-model-generation-floor/a2a/sprint-237/prompt-audit/METHOD-prompt-audit.md` (34,966 B). Its anti-pattern groups are pressure language, scaffolds replaced by API features, over-specification, fossils, prohibition clusters, output-shaping choreography, brittle skill files and tool descriptions, plus a keep list. "Prime directive: distinguish cruft from load-bearing content."
  - It is applied by the read-only agents `.claude/agents/prompt-auditor.md` and `prompt-auditor-io.md`. Their rules include "Every deletion cites a named pattern from the method …; a deletion justified by byte count alone is not a deletion."
  - The method lives only in a sprint a2a/archive directory, not in `.claude/protocols/`.
- **No history in rule text**: `tests/unit/no-history-in-rule-text.bats` (cycle-124 FR-8) says `cycle-NNN`, `#NNNN` and `KF-NNN` may appear only in a `## Provenance` footer, a provenance comment, a KF pointer or a backticked path. In addition, "Every surviving MUST/NEVER/ALWAYS line … names the hook or validator that enforces it, or reads as plain rule + reason."
- **Byte budgets and resource charging** (S1) and the **progressive-disclosure** split into `resources/` (S2).
- **Context discipline**: `context_discipline` include blocks, `.claude/protocols/tool-result-clearing.md` (context classes), Karpathy principles (`.claude/protocols/karpathy-principles.md`), and the `${PROJECT_ROOT}`-prefixed "Lightweight Identifiers" convention (session-continuity.md:171).
- **Citations and grounding** protocols: `.claude/protocols/citations.md` and `grounding-enforcement.md`.
