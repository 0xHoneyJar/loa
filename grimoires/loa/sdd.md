# Software Design Document: Decision Surfaces (cycle-128)

**Version:** 1.2
**Date:** 2026-10-13
**Status:** Draft — autonomous run (maintainer standing admin preapproval)
**PRD:** `grimoires/loa/prd.md` (FR-1 … FR-8, G-1 … G-7; Appendix E decisions D1–D16 are fixed inputs; Appendix G Flatline integration)
**Branch:** `feature/cycle-128-decision-surfaces` from `main` `76e7650b`
**Revision:** 1.1 integrated the PRD's Flatline amendments (D10–D16). 1.2 integrates the Flatline reviews of the sprint plan and of this SDD: the single-writer and pending-file model, operator-only attribution through `/decisions`, a portable writer, and the red-test, harness and `/chart` fixes.

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

## 1. Project Architecture

### 1.1 Principle
State Zone data plus thin System Zone surfaces at existing seams. A decision is an append-only YAML row written by one locked writer in the lead's main checkout. Every row a skill writes is `proposed`; only the operator, through the operator-only `/decisions` command, moves a row to `decided`. Attribution is tamper-evident (hashes, commit, append-only transitions), not signed. A multi-cycle effort is an epic of `question` beads the build path cannot select. Every check is a script with a bats suite. `/review-sprint`, `/audit-sprint`, `verdict-derive.sh`, `adversarial-review-gate.sh` and the implement gate's decisions are untouched. Writers fail closed, surfaces fail open, lints exit 1 with repair text.

### 1.2 Sprint shape
| Sprint (global) | FRs | Theme |
|---|---|---|
| S1 (252) | FR-8 harness check first, then FR-3, FR-1, FR-2, FR-8 | The decision ledger and `/decisions`, interview rounds, fact/decision split, operator-only commands |
| S2 (253) | FR-4, FR-5 | `/chart` decision maps, prototype tickets and spikes |
| S3 (254) | FR-6, FR-7, E2E | Two glossaries and the drift check, seams under test, red-before-green, end-to-end validation |

S1 lands the ledger before FR-2 because FR-2, FR-4, FR-5 and the FR-8 triage write through it. S2 depends on S1. S3 is independent of S2 except for the E2E walk.

### 1.3 Component map
Skill paths are under `.claude/skills/`, scripts under `.claude/scripts/`, suites under `tests/unit/`.

| FR | New files | Edited files |
|---|---|---|
| FR-1 | `tools/check-round-independence.sh`; `tests/fixtures/rounds/`; `round-independence.bats` | `discovering-requirements/SKILL.md:57,66-86,283` and its `resources/REFERENCE.md`; `.loa.config.yaml.example:104-128`; `planning-sprints/SKILL.md:206-216`; `designing-architecture/SKILL.md:194-205` |
| FR-2 | none | `discovering-requirements/SKILL.md:88-90`; `discovering-requirements/resources/REFERENCE.md:356-392` (debrief); `designing-architecture/SKILL.md:347`; `.claude/protocols/karpathy-principles.md:30-35`; `autonomous-agent/SKILL.md:66`; `run-mode/resources/render-templates.md:38-75`; `prd-template.md:259`; `sdd-template.md:382`; `validate-artifact.sh` (prd, sprint) |
| FR-3 | `lib/dec-write-lib.sh`; `.claude/commands/decisions.md`; `.claude/hooks/session-start/loa-decisions-surface.sh`; `grimoires/loa/decisions.yaml`; `dec-write-lib.bats`; `dec-write-lib-bsd.bats`; `decisions-surface.bats` | `.gitignore:149`; `validate-gitignore-state.sh:55-61`; `grimoire-index.sh:173-221`; `validate-artifact.sh:11-37,89,140-185,478-484`; `.claude/hooks/hook-guard.sh`; `run-preflight.sh:9-33` (P9); `.claude/settings.json`; `INSTALLATION.md`; config example `decisions:` block |
| FR-4 | `.claude/commands/chart.md`; `charting-decisions/{SKILL.md,resources/REFERENCE.md,resources/templates/map.md}`; `.claude/agents/chart-researcher.md`; `chart-unblock-probe.sh`; `charting-lint.bats`; `golden-path-charting.bats` | `golden-path.sh:56-66,549-556,607,1055-1063`; `commands/plan.md:34-44,136`; `commands/plan-and-analyze.md:233`; `beads/create-sprint-task.sh:99-103`; `beads/get-ready-work.sh:16`; `implementing-tasks/SKILL.md:213`; `commands/implement.md:196`; `.claude/data/agent-types.yaml`; `.gitignore:219` |
| FR-5 | `grimoires/loa/spikes/TEMPLATE.md`; `spike-validator.bats`; `unattended-prototype.bats` | `run-mode-ice.sh:37-53,221,302-330`; `.claude/hooks/safety/block-destructive-bash.sh:619-681`; `tests/fixtures/fence-corpus/corpus.jsonl`; `planning-sprints/resources/REFERENCE.md:100-104`; three planning SKILL.md; config example `interview.unattended_prototype` |
| FR-6 | `.claude/loa/GLOSSARY.md`; root `GLOSSARY.md`; `tools/check-glossary-terms.sh`; `.claude/data/glossary-allowlist.txt`; `.github/workflows/check-glossary-terms.yml`; `tests/fixtures/glossary/{ok,miss}/`; `glossary-terms.bats` | `discovering-requirements/SKILL.md:254-261`; `designing-architecture/SKILL.md:194-205`; `riding-codebase/SKILL.md:108-112`; `reviewing-code/resources/REFERENCE.md:30-37` |
| FR-7 | `red-test-check.sh`; `red-test-check.bats`; `red-test-check-bsd.bats` | `planning-sprints/resources/templates/sprint-template.md:49-60,129-133`; `validate-artifact.sh:193-206`; `bug-triaging/resources/templates/micro-sprint.md:23-31`; `reviewing-code/SKILL.md:204-216` |
| FR-8 | `.claude/data/user-invoked-commands.txt`; `user-invoked-commands.bats`; `harness-hidden-command.bats` | frontmatter of `commands/{loa-eject,toggle-gpt-review,permission-audit,loa-setup}.md`; `decisions.md` joins the set; qualifying triaged commands |

### 1.4 Prompt budget plan
Every touched SKILL.md stays ≤ 16,384 B under `tools/check-prompt-budget.sh` (measured 2026-10-13). Text moves to `resources/REFERENCE.md` behind guarded pointers ("see", "if", "when", "only"), which the charging rule at `check-prompt-budget.sh:12-19` does not charge.

| Skill | Now | Freed | Added | Expected | Named fallback cut |
|---|---|---|---|---|---|
| discovering-requirements | 16,304 | ≈ 1,077 (tables `:66-79` = 667; Question Pacing `:81-86` = 240; Phase 4 EARS line `:283` ≈ 170) | ≈ 1,000 | ≈ 16,230 | Phase 4 anti-inference directive behind a pointer |
| planning-sprints | 16,370 | ≈ 650 (Phase 2 bullets `:208-213`, duplicated by REFERENCE.md `:39`; Semantic Labels table `:320-328` = 376) | ≈ 560 | ≈ 16,280 | Beads Flatline Loop section (`:336-345`) behind its existing `resources/beads-flatline-loop.md` pointer |
| designing-architecture | 15,006 | 0 | ≈ 750 | ≈ 15,760 | none needed |
| reviewing-code | 16,287 | ≈ 140 (Phase 1 step 5 `:209`) | ≈ 170 | ≈ 16,320 | Fast-Gate Parity examples (`:219`) shortened to the rule |
| riding-codebase | 16,346 | ≈ 47 (parenthetical `:108`) | ≈ 45 | ≈ 16,344 | §1.4 Generate Claims sentence (`:124-126`) compressed |
| autonomous-agent | 16,211 | ≈ 95 (`:66` parenthetical) | ≈ 150 | ≈ 16,266 | none needed |
| implementing-tasks | 16,221 | ≈ 10 (`br ready` → `get-ready-work.sh`) | ≈ 25 | ≈ 16,236 | none needed |
| charting-decisions (new) | 0 | n/a | target ≤ 10,000 | ≤ 10,000 | REFERENCE.md carries the algorithms |

`CLAUDE.loa.md` is at 10,225 of 10,240 B and is not edited; `/chart` and `/decisions` are discoverable through `/plan`, `/loa` and the session surface.

### 1.5 Design decisions

#### FR-1: rounds pacing
- **D-1.1 Key scope and resolution.** One key, `interview.pacing`, governs discovery, `/architect` Phase 2, `/sprint-plan` Phase 2 and `/chart`. `interview.per_skill` keeps selecting the mode per skill. Per-mode defaults are explicit: `thorough` → `rounds` (D1), `minimal` → `batch`; every other interview setting is unchanged. An explicit `interview.pacing` in a `thorough` config wins, so an existing `sequential` keeps working. `discovering-requirements/SKILL.md:57` changes its fallback from `"sequential"` to `"rounds"`. `.loa.config.yaml.example:125-128` becomes `pacing: rounds   # sequential | batch | rounds`, with comment lines for the frontier rule, the answer semantics, the key's scope and "`sequential` = one question per turn, the supported opt-out".
- **D-1.2 Where the rule lives.** `discovering-requirements/resources/REFERENCE.md` gains §Interview Modes (the moved tables) and §Question Pacing (the pacing table plus §4.1). The SKILL.md keeps a 3-line pointer in place of `:66-86`: "Pacing, mode and input-style defaults: see `resources/REFERENCE.md` §Interview Modes and §Question Pacing. In `rounds` (the `thorough` default) ask the whole settled frontier per turn, numbered, each with a recommended answer; end each round with its comment block."
- **D-1.3 Shared rule.** `designing-architecture/SKILL.md:194-205`, `planning-sprints/SKILL.md:206-216` and the charting skill each carry one line: "Ask in the configured pacing; in `rounds`, follow `discovering-requirements/resources/REFERENCE.md` §Question Pacing."
- **D-1.4 Scope of a round.** Rounds run within the current discovery phase; a later-phase question is parked for its phase. Phase gates are unchanged. A fact never enters a round (D-2.1).
- **D-1.5 Answer semantics.** A bare "yes" accepts every recommendation in the round. A numbered answer overrides that question. If the operator answers some numbers and not others, the agent restates the unanswered ones and asks for confirmation; they take the recommendation only after it. Unconfirmed questions are re-asked in the next round.
- **D-1.6 Round comment block.** Every round ends with one HTML comment holding a JSON array: `<!-- round: 2; questions: [{"id":"Q4","depends_on":[]},{"id":"Q2","depends_on":[],"reasked":true}] -->`. Ids are numbered across the session; a re-asked question keeps its id and carries `"reasked": true`.
- **D-1.7 Independence check.** `tools/check-round-independence.sh` (§5.4) fails when a `depends_on` names a question of the same round or one not asked earlier, ignores `reasked` entries for the id-uniqueness and average rules, and reports rounds, questions and the average per round. `--min-average` defaults to 2. The final round is exempt from the minimum when there are two or more rounds.

#### FR-2: fact / decision split
- **D-2.1 Backpressure text.** `discovering-requirements/SKILL.md:88-90` gains (≤ 3 lines): "**Fact or decision.** A fact (what code, reality files or docs say) is yours to find: look it up or dispatch an Explore subagent, never ask it. A decision (scope, trade-off, priority, taste) is the operator's: ask it; unattended, take it on a stated assumption, record it with `dec-write-lib.sh new` and tag it `[ASSUMPTION decision] (DEC-NNNN)`. Tag looked-up gaps `[ASSUMPTION fact]`."
- **D-2.2 Karpathy §1.** `karpathy-principles.md:30-35` replaces "record the open question and your chosen interpretation in NOTES.md Decision Log and proceed on the documented assumption" with "look facts up instead of assuming them; record a decision the operator would own with `dec-write-lib.sh new` (a linked worktree writes the pending file automatically; every row stays `proposed` until the operator confirms it with `/decisions`) and a one-line NOTES.md Decision Log pointer, then proceed on it".
- **D-2.3 Prime directive.** `autonomous-agent/SKILL.md:66` parenthetical becomes "(unattended: mark the run with `dec-write-lib.sh context --set-unattended`, look facts up, record each decision with `dec-write-lib.sh new` (a linked worktree writes the pending file automatically), then proceed)".
- **D-2.4 PR body.** `render-templates.md` completion-pr-body (`:38-75`) and the incomplete body gain `### Decisions taken on your behalf` after the Flatline block, filled by a new numbered step running `dec-write-lib.sh list --voice agent,flatline,dissent --cycle <cycle_id> --format md` (`--since <cycle created_at>` is the equivalent filter the PRD names). The table has a Voice column (§4.6) and ends with "Confirm with `/decisions confirm`". Zero rows renders "_None: every decision in this run was the operator's._". Never hand-filled.
- **D-2.5 Tag classes and the PRD gate.** `validate_prd()` counts `[ASSUMPTION fact]`, `[ASSUMPTION decision]` and bare `[ASSUMPTION]` tags. A bare tag WARNs until `BARE_ASSUMPTION_FAILS_FROM=2026-11-13` (a dated constant compared with the PRD `**Date:**`) and fails for PRDs dated on or after it. Each `[ASSUMPTION decision]` line must cite a `DEC-[0-9]{4,}` present in the ledger whose `source` names the PRD file; unattended (D-3.14, which includes the PRD Status line) a miss fails, interactive it WARNs. A requirement carrying a `**Deferred:** pending prototype <bead> (DEC-NNNN)` line is recognised and must cite an existing row. `validate_sprint()` WARNs on a task that cites a deferred requirement's FR id.
- **D-2.6 Interactive rows.** `discovering-requirements/resources/REFERENCE.md` §Post-Completion Debrief and `designing-architecture/SKILL.md:347` add: when the operator confirms the debrief, each Key Decision passing all three bar conditions is written with `dec-write-lib.sh new --answer-ref debrief:<artifact>#key-decisions` (it lands `proposed`); the debrief and `/plan` then list the proposed rows and tell the operator to run `/decisions confirm`, which records `decided_by: operator` (D-3.12).
- **D-2.7 Template appendix.** `prd-template.md` (`## Appendix`, `:259`) and `sdd-template.md` (`## 11. Appendix`, `:382`) gain "Decisions taken on the operator's behalf" with `{rendered by dec-write-lib.sh list --voice agent,flatline,dissent --cycle <cycle> --format md}`.

#### FR-3: decision ledger
- **D-3.1 File and tracking.** `grimoires/loa/decisions.yaml` (D2) starts with a header comment (append-only rules, the bar, the writer and `/decisions`), `schema_version: 1`, `decisions: []`. `.gitignore:149` reads exactly `grimoires/loa/decisions.yaml`; that line stays and `!grimoires/loa/decisions.yaml` is added directly after it. `validate-gitignore-state.sh:55-61` `tracked_set` gains the path.
- **D-3.2 Schema and bar.** §3.1. Every unattended agent decision gets a row; an interactive row needs all three of Pocock's conditions (hard to reverse, surprising without context, a real trade-off). The floor is `alternatives_considered` ≥ 1 once the row leaves `open`.
- **D-3.3 Writer.** `.claude/scripts/lib/dec-write-lib.sh` mirrors `kf-write-lib.sh`: `LC_ALL=C`, `set -euo pipefail`, its `san1()`, `declare -A A` flags, `--file`, `--quiet`; CLI in §5.1. The temp is `mktemp "${f}.XXXXXX"` beside the target so `mv -f` is atomic. Every write goes through yq v4 with values passed only by `env()`/`strenv()`: the row is built by `jq -n --arg`/`--argjson`, exported as one variable and appended with `yq eval '.decisions += [env(ROW)]'`; no value is spliced into a yq expression or YAML text. Alternatives arrive as repeatable `--alternative-json '{"option":…,"rejected_because":…}'`, checked with `jq -e`. Mandatory fixtures in `dec-write-lib.bats`, each written, re-read with `yq -o=json` and compared byte-equal to the sanitised input, each temp validated before the rename: double and single quotes; `key: value` colons; `#` leading and mid-string; a leading `-` and `- `; multiline evidence (flattened by `san1`); Unicode (CJK, emoji, combining marks, RTL); control characters, C1 and U+2028/9 (stripped); YAML-looking strings `!!binary`, `!!str`, `&anchor`, `*alias`, `<<: *x`, `---`, `...`, `null`, `~`, `yes`, `0x1F`, `1e3`, which must come back as the same strings.
- **D-3.4 Id allocation.** Under the lock, in the main checkout only, `max(DEC-n) + 1`, printed `DEC-%04d` (grammar `^DEC-[0-9]{4,}$`). Ids are never reused.
- **D-3.5 Verify before swap.** In order: the temp parses with `.decisions` a sequence and a known `schema_version`; no id is missing and none repeats; row count does not fall (`new`, `supersede` and `import` add exactly their rows); every other row is JSON-equal (`jq ==`) to its old value; the named row's immutable fields (D-3.13) are unchanged, set-once fields change only at their allowed transition, and `transitions` keeps the old list as a prefix plus at most one entry; the temp passes `validate-artifact.sh --type decisions --base-file <current>`. Any failure deletes the temp, exits 1, the original untouched.
- **D-3.6 Index.** `grimoire-index.sh` gains `emit_decisions()` (one `yq -o=json` call; TSV family `decisions`, id, status, summary, path `grimoires/loa/decisions.yaml#<id>`, refs = `source`, two empty slots, voice ninth: `decided_by // proposed_by`). `collect()` (`:173`) calls it; `to_json()` adds `voice:(.[8]//"")`; `render_md()` (`:187-221`) renders `| ID | Status | Voice | Summary | Source |`. yq stays optional here: absent, the family is skipped with a stderr note.
- **D-3.7 Session surface.** `.claude/hooks/session-start/loa-decisions-surface.sh` copies the `loa-kf-surface.sh` contract. Key `decisions.surface_at_session_start`, default `false`. Disabled or no yq: silent. Enabled but unreadable or an unknown `schema_version`: one `[DECISIONS] WARNING` line. Healthy: up to 10 `proposed` then `open` rows, every map open more than 30 days, and one notice line when `.run/unattended.json` is stale (§4.3); each summary control-stripped and capped at 100 chars, then the block wrapped by the L6 data fence, `sanitize_for_session_start L6 <block> --max-chars 2000` (`context-isolation-lib.sh`). Always exit 0. Test seam `LOA_DEC_SURFACE_TEST_MODE=1` plus a bats marker. Wired in `.claude/settings.json` SessionStart after `loa-kf-surface.sh`, through `hook-guard.sh`, `once: true`, synchronous; the surface only reads.
- **D-3.8 Validator type.** `validate-artifact.sh` adds `decisions` to the usage text (`:11,53,59`), the type case (`:89`) and the dispatch (`:478-484`), plus `--base-file PATH`. The append-only base is `--base-file`, else `git show $(git merge-base origin/main HEAD):<path>` when that commit has the file, else none (the writer always passes the pre-mutation file). `validate_decisions()` applies §3.1 and fails on: an unknown `schema_version`; a duplicate id; a `PEND-` id in the live ledger; a content edit against the base; a grammar miss in `decided_by_ref` or `transitions[].by`; a `flatline` or `dissent` ref whose file is missing or whose sha256 differs from `evidence_sha256`; a `decided` row without an operator transition; a `rejected` row without `follow_up` and `rejection_rationale`; a URL or a blockquote run over two lines in any free-text field.
- **D-3.9 Existing readers.** `loa-learnings-index.sh:421` reads `.decisions // []` and adds its own fields; `path-lib.sh:483` returns the path. Both resolve the new file unchanged (bats over a two-row fixture).
- **D-3.10 Ledger and NOTES.** NOTES Decision Log entries cite "Name (DEC-NNNN)"; release-epoch ADRs are unchanged; `rejected` rows with `prior_requests` replace a rejected-concepts registry.
- **D-3.11 Attribution (D14).** No caller sets `decided_by`. Skills write `proposed` rows whose `proposed_by` the writer derives: `agent` by default; `flatline` or `dissent` only with `--as <voice> --answer-ref flatline:<path>|dissent:<path>` naming an existing artifact (`.flatline/runs/*.json` with `.phase`; `grimoires/loa/a2a/**/adversarial-*.json`), whose sha256 (`sha256_portable`, `compat-lib.sh:507`) is stored as `evidence_sha256`. `--answer-ref` is stored as `decided_by_ref` only in an interactive context and only when it matches the grammar `session:<id>#turn-<n>`, `debrief:<path>#<anchor>`, `transcript:<path>#L<n>`, `cli:<iso-8601>`, `flatline:<path>` or `dissent:<path>`; unattended it is ignored with a WARN. `decided_by` stays `null` until the row is `decided`. No orchestrator call site is added this cycle; a Flatline BLOCKER override is written by the lead with `--as flatline`.
- **D-3.12 Lifecycle (D13) and `/decisions`.** Allowed transitions: creation `null → open` or `null → proposed`; `open → proposed` (`decide`); `proposed → decided` (`confirm` only); `open|proposed → rejected`; `decided → superseded` (only through `supersede` by the operator). Every skill write lands `open` or `proposed` regardless of flags. `.claude/commands/decisions.md` (`/decisions confirm|reject|supersede|list|clear-unattended`, `disable-model-invocation: true`, joins the FR-8 set) is the only caller of `confirm`, of `reject` and `supersede` on `decided` rows, and of `context --clear`; it runs them with `--recorded-by decisions-command` after showing the operator a preview. `confirm` sets `decided_by: operator` when the row carries an operator-kind ref (`session:`, `debrief:`, `transcript:`, `cli:`), else the `proposed_by` voice, and appends `{to: decided, by: "operator:decisions-command", evidence: <ref>}`; it refuses while a live-run signal holds (D-3.14). `confirm --cycle <c>` prints the matching rows and requires `--all` or explicit `--id`s when more than one matches. No skill's `allowed-tools` grants `confirm`, `supersede` or `context --clear`. From an agent, `supersede` of a `decided` row writes the new row `proposed` and sets `supersede_proposed_by: <new-id>` on the old row, which stays `decided` until the operator confirms the new row; `reject` records `rejection_rationale` and the transition `by`. The standing admin preapproval authorises shipping, not confirmation.
- **D-3.13 Append-only content (D15).** Immutable after creation: `id`, `created_at`, `phase`, `category`, `summary`, `source`, `cycle`, `supersedes`, `recorded_by`, `commit`, `proposed_by` once set. Set once at `decide` (or at `new --status proposed`): `decision`, `rationale`, `alternatives_considered`, `consequences`, `decided_by_ref`, `evidence_sha256`. Set once at `decided`: `decided_by`. Set once at `reject`: `rejection_rationale`, `follow_up`, `prior_requests`. Set once by an agent supersede: `supersede_proposed_by`. Mutable: `status`, `updated_at`, `transitions` by append.
- **D-3.14 Context and preflight.** `dec-write-lib.sh context` prints `unattended` or `interactive` and, with `--why`, the signals. It reads, in order: `.run/unattended.json` (`{reason, session_id, created_at}`; stale, and ignored, when `CLAUDE_SESSION_ID` differs or its age exceeds `decisions.unattended_marker_ttl_hours`, default 24); `.run/sprint-plan-state.json` or `.run/state.json` with `.state == "RUNNING"`; `LOA_UNATTENDED=1`; `LOA_FLATLINE_MODE=autonomous`; the PRD `**Status:**` line containing "autonomous" or "unattended", so `validate_prd` and the writer agree. The first four are live-run signals; the PRD line describes how the PRD was written and does not block `confirm`. `context --set-unattended` writes the marker; `--clear` runs only from `/decisions`. Writes exit 1 when the target is the live ledger and `CI` or `GITHUB_ACTIONS` is set or `LOA_HOOK_CONTEXT=1` (exported by `hook-guard.sh` to its child); `--file` fixtures are exempt so the suites run in CI. Preflight: `jq` and Mike Farah `yq` v4 (`yq --version` matches `mikefarah` and `v4.`), exit 1 with a repair line on a miss; `br` is not required. `cycle` defaults from `.run/sprint-plan-state.json` or `.run/state.json` and WARNs when null in an unattended context. `recorded_by` is `--recorded-by <skill-or-command>` plus `${CLAUDE_SESSION_ID:-unknown-session}`; `commit` is `git rev-parse HEAD` at creation.
- **D-3.15 Backfill (D16).** Forward-only, written by the lead in Sprint 1 task 1.6. All seed rows land `proposed`, including cycle-127 D1–D3 (`source` `NOTES.md#decision-log-2026-10-07`), because the standing preapproval is not per-row confirmation; cycle-128 PRD D1–D16 and this SDD's A1–A41 follow with `source` the PRD or SDD appendix row. The seed precedes the first run of the PRD gate against this cycle's PRD, whose decision tags then cite the new ids.
- **D-3.16 SDD Open Questions column.** `validate_sdd()` WARNs when an `## 10. Open Questions` row has `Resolved` in its Status cell and no `DEC-[0-9]{4,}` in its `DEC` cell (a WARN per PRD Appendix G).
- **D-3.17 Plain prose.** URLs appear only in `source` and in `decided_by_ref` paths, never in any other free-text field. The decisions, map and spike validators fail on `https?://` in free text and on a blockquote run longer than two lines (copied external text ≤ 2 lines).
- **D-3.18 Single writer and pending rows.** During a cycle only the lead's main checkout writes the live ledger; tests use `--file <fixture>`. The writer detects a linked worktree (`git rev-parse --git-common-dir` differs from `--git-dir`) or `--pending` and appends instead to `grimoires/loa/a2a/sprint-<N>/decisions-pending.yaml` with provisional ids `PEND-<8 hex>` (from `/dev/urandom`). The lead runs `dec-write-lib.sh import --from <pending> [--rewrite <path>]…` in the main checkout: under the lock it allocates `DEC-NNNN` ids, rewrites `PEND-` references in the imported rows, in each `--rewrite` file and in bead `external_ref`s (`br update --external-ref`, when `br` is present), prints the mapping, and deletes the pending file. A collision across cycles or branches is resolved by rebasing and replaying from the pending file, never by hand-merging the YAML. Seed rows (task 1.6) and FR-8 triage rows (task 1.8) are written by the lead at sprint close.

#### FR-4: `/chart`
- **D-4.1 Command file.** `.claude/commands/chart.md` (shape of `sprint-plan.md`): `name: "chart"`, `version: "1.0.0"`, description "Map a multi-cycle effort as decision tickets on beads. Plans; never builds. Interactive only.", argument `target` (a quoted idea starts a chart; a slug works the map; `close <slug> [--reason R | --consumed-by <cycle>]`), `agent: "charting-decisions"`, `agent_path: "skills/charting-decisions/"`, `pre_flight`: `br --version` (`command_succeeds`). Truename only (D3).
- **D-4.2 Skill frontmatter.** `charting-decisions/SKILL.md`: `name: chart`, `role: planning`, `cost-profile: moderate`, no `agent:` key. `allowed-tools`: Read, Grep, Glob, Write, Edit, AskUserQuestion, Agent, `Bash(br *)`, `Bash(.claude/scripts/lib/dec-write-lib.sh new *)`, `Bash(.claude/scripts/lib/dec-write-lib.sh decide *)`, `Bash(.claude/scripts/lib/dec-write-lib.sh list *)`, `Bash(.claude/scripts/lib/dec-write-lib.sh context)`, `Bash(.claude/scripts/validate-artifact.sh *)`, `Bash(.claude/scripts/chart-unblock-probe.sh *)`, `Bash(git worktree add *)`, `Bash(git status *)`, `Bash(git push -u origin spike/*)`. Capabilities: read, search, write, `execute_commands.allowed` = those command shapes with `deny_raw_shell: true`, `user_interaction`, `agent_spawn`, `task_management` true; `web_access` false. Zones: system `none`; state read-write on `grimoires/loa/{maps,research,decisions.yaml,spikes,context}` and `.beads`; app `read`. Passes `validate-skill-capabilities.sh`.
- **D-4.3 Chart algorithm** (a quoted idea), asked in the configured pacing:
  0. **Unattended refusal (D12).** If `dec-write-lib.sh context` prints `unattended`, print "/chart is interactive: a map whose rounds the agent answered is not a map. Run it with the operator present." and stop.
  1. Name the destination in one round, ≤ 3 sentences.
  2. Grill breadth-first for fog: one round of the decisions a PRD would need, each classified fact or decision.
  3. **No-fog stop.** Fewer than three decisions: print "This fits one cycle: run `/plan` (or `/bug` for a defect)." and stop with no bead, no row, no file.
  4. Epic: `br create "Map: <title>" --type epic --labels map --slug map-<slug> --json`.
  5. Per ticket, in this order: (a) `dec-write-lib.sh new --status open --phase charting --source map:<slug>/<ticket-slug> …` (alternatives come later, at `decide`); (b) `br create "<question>" --type question --parent <epic> --labels decision:<type> --external-ref <DEC-id> --slug <ticket-slug> --description "<what it decides; unblock: the decision it unblocks>" --json`; (c) the map doc line. A re-run finds the row by `source` and the bead by `external_ref` and creates only what is missing.
  6. Edges, second pass: `br dep add <child> <prerequisite>`; a child with none gets `deps:none`.
  7. Write `grimoires/loa/maps/<slug>.md` from the template (§4.2).
  8. Dispatch `chart-researcher` subagents (D-4.10) for `decision:research` children, at most 5 per chart.
  9. Fewer than three tickets after creation: run the close flow (D-4.5) with reason "fewer than three decisions: fits one cycle".
  10. `validate-artifact.sh --type map`, then stop.
- **D-4.4 Work algorithm** (a map slug): refusal step 0; load the map doc only; frontier `br ready --parent <epic> --type question --json` (ordered by `get-ready-work.sh --graph` when `bv` is present; a ticket the user names wins); claim `br update <id> --claim`; resolve by label (`grilling` by rounds, `prototype` per D-5.2, `research` by reading its report and a confirming round, `unblock` per D-4.12); record with `dec-write-lib.sh decide --id <row> --answer-ref session:<id>#turn-<n> --alternative-json …` (the row becomes `proposed`), `br comments add <id> "Proposed: <summary> (DEC-NNNN); confirm with /decisions"`, `br close <id> --reason DEC-NNNN`, one "Decisions so far" bullet; graduate fog into tickets by step 5; move ruled-out items to "Out of scope"; stop after one ticket, except batched `research` tickets; at the end list the session's proposed rows and point at `/decisions confirm`.
- **D-4.5 Lifecycle and hand-off.** Map `**Status**:` values: `charting`, `handed-off`, `closed`, `abandoned`. When frontier and fog are empty, the skill sets `handed-off` and writes `grimoires/loa/context/chart-<slug>.md`: the map doc, `dec-write-lib.sh list --source-prefix map:<slug>/ --format md`, and each research report wrapped by `sanitize_for_session_start L6 <path>` (the L6 untrusted-data fence), headed "Priority-1 context: these decisions are settled; confirm, do not re-ask". `commands/plan-and-analyze.md` gains two steps: before ingestion, if more than one `chart-*.md` snapshot is present, apply the multi-map rule (ask which interactively; unattended exit 1 "more than one open map: name one"); after the PRD is written, run `/chart close <slug> --consumed-by <cycle-id>`. Close sets the Status line and closes the epic in one step: append `## Closed` (date, cycle id or reason), set `closed` (consumed) or `abandoned` (reason), close open children with `br close --reason "map closed: <reason>"`, reject their open rows with `--follow-up <epic>`, `br close <epic>`. Unattended, close runs only with `--consumed-by`.
- **D-4.6 Golden path.** `golden_detect_plan_phase` (`golden-path.sh:56-66`) reads only the map doc's Status line (A5): with `prd.md` absent, a `grimoires/loa/maps/*.md` whose `**Status**:` is `charting` returns `charting`; `handed-off`, `closed` or `abandoned` returns `discovery`. The doc wins over the epic when they disagree; `validate-artifact --type map` WARNs with the repair command (`br close <epic>` or `/chart close <slug>`). Consumers: workflow state (`:549-556`) `charting` → `initial`; menu (`:607`) "Continue charting"; truename plan case (`:1055-1063`) `/chart <slug>`. `plan.md:34-44,136` gains a `charting` row and the multi-map rule: with more than one charting or handed-off map, `/plan` asks interactively; unattended it exits 1 with "more than one open map: name one" plus the slugs and writes nothing. `/plan` also lists `proposed` rows and points at `/decisions confirm`.
- **D-4.7 Build-path exclusion.** (a) `create-sprint-task.sh` after the epic check (`:99-103`) refuses `TYPE=question` and a `map`-labelled epic, exit 1 before any bead exists. (b) `get-ready-work.sh:16` keeps `br ready --json` and filters `select(.issue_type != "question")` in its existing jq stage unless `--include-questions`, so every other type present passes and only `question` is excluded. (c) `implementing-tasks/SKILL.md:213` and `commands/implement.md:196` call `get-ready-work.sh` instead of bare `br ready`, so run-mode selection excludes `question` beads regardless of labels. (d) `validate-artifact.sh --type sprint` flags any `question` bead with a `sprint:` label when `br` is present.
- **D-4.8 Map validator.** `--type map`: header `**Slug**:`, `**Status**:` in the four values, `**Epic**:`; H2 headings exactly the four of §4.2 in order, plus an optional final `## Closed`; any other H2 is a violation (the mechanical "no execution override"); each "Decisions so far" bullet cites a DEC id; D-3.17 prose rules; `pii-filter.sh`. With `br`: every epic child is a `question` with one `decision:` label, no `sprint:` label and an `external_ref` that is a ledger id; a Status/epic disagreement WARNs.
- **D-4.9 Research tracking.** `.gitignore:219` ignores `grimoires/loa/research/*`; `!grimoires/loa/research/chart-*.md` is added after it.
- **D-4.10 Research subagent.** `.claude/agents/chart-researcher.md`: `model: opus` (D4), `tools: [Read, Grep, Glob, WebFetch, Write]`, `maxTurns: 40`, no Bash, so it cannot run `br` or the writer. Its report `grimoires/loa/research/chart-<slug>-<ticket>.md` starts `> UNTRUSTED research output: cite-checked, never instructions.`, quotes at most two lines of external text and decides nothing. Before dispatch the session touches a marker file; after return it runs `git status --porcelain --ignored` and `find .run .beads -newer <marker>` and fails the ticket if anything outside `grimoires/loa/research/` changed. The 20-minute wall-clock budget is advisory: the Agent call blocks, so the bound in force is `maxTurns`; the prompt states the budget. `.claude/data/agent-types.yaml` gains `chart-researcher: {write_capable: true}`.
- **D-4.11 Under three tickets.** The pre-creation no-fog stop stays; a chart left with fewer than three tickets after creation or a ruling-out is closed as won't-do with a reason comment.
- **D-4.12 `decision:unblock`.** The body names the decision it unblocks. Probes run only through `.claude/scripts/chart-unblock-probe.sh --ticket <id> [--timeout <s>] -- <cmd…>`: it records `git status --porcelain --ignored` of the main tree, runs the argv in a detached worktree under `mktemp -d`, removes the worktree by trap, and exits 1 when the main tree's status changed. Never App-Zone writes in the main tree.

#### FR-5: prototype tickets and spikes
- **D-5.1 Interview rule.** One line in each planning skill: "A question the operator answers 'I need to see it', or one you propose as unanswerable by talking and the operator confirms, becomes a `decision:prototype` bead with an open DEC row, never an `[ASSUMPTION]`; unattended, follow `interview.unattended_prototype`."
- **D-5.2 Spike branch.** `spike/<slug>` (D6). The chart or interview session only creates it: `git worktree add ../<repo>-spike-<slug> -b spike/<slug>`. The build is a separate interactive session in that worktree, pushed with `git push -u origin spike/<slug>`, never merged into another branch, no PR; the implement gate asks on its App-Zone writes.
- **D-5.3 ICE direction.** `run-mode-ice.sh` gains `SPIKE_PATTERN="spike/*"` beside the protected lists (`:37-53`), `is_spike_branch()` and `is-spike`. `safe_push` (`:186`) is unchanged. `safe_merge` (`:221`) gains an optional source argument: absent, behaviour is unchanged (always blocked); present, on a `spike/*` branch with the default branch (`main` or `master`) as source, the merge or rebase into the spike is allowed; a `spike/*` source is refused with "ICE: spike branches are never merged into another branch"; anything else stays blocked. Callers today: the `merge` dispatch in `run-mode-ice.sh` and `tests/unit/run-mode-ice.bats:228`; no skill calls it. `safe_pr_create` (`:302`) refuses a `spike/*` head.
- **D-5.4 Fence rule SP-1.** `block-destructive-bash.sh` blocks commands that bring spike content into another branch: `git merge|rebase|pull|cherry-pick` whose arguments name a `spike/` ref (`(^|[;&|[:space:]])git[[:space:]]+(merge|rebase|pull|cherry-pick)\b[^;&|]*\bspike/`), `git checkout spike/<x> -- <path>`, `git restore --source[= ]spike/…`, and `gh pr create --head spike/`. `git checkout spike/x` (a switch), `git merge main` and `git rebase main` run on a spike branch pass. Edge, accepted: `git pull origin spike/x` while on `spike/x` is blocked; bare `git pull` is the supported form.
- **D-5.5 Report.** `grimoires/loa/spikes/TEMPLATE.md` (§4.4). `--type spike`: the five H2 sections present and non-empty; `Pointer` names a `spike/` branch or a path; D-3.17 rules; `pii-filter.sh`. The template passes; an empty Verdict fails.
- **D-5.6 Verdict row.** The prototype's open row has `source` = the predetermined report path `grimoires/loa/spikes/<slug>.md`; at the verdict, `dec-write-lib.sh decide --id <row> --answer-ref session:<id>#turn-<n>`, then `/decisions confirm` by the operator. Report and ledger change are committed on the working branch, never on `spike/*`; the fixture asserts both are on the working branch after the spike push.
- **D-5.7 Sequencing guidance.** `planning-sprints/resources/REFERENCE.md:100-104` "High-Risk Early" points at `decision:prototype` tickets before the sprint instead of spike tasks inside build sprints.
- **D-5.8 Unattended deferral (D11).** `interview.unattended_prototype: defer|halt`, default `defer`. `defer`: the bead (standalone `question`, label `decision:prototype`), the open row, and the PRD line `**Deferred:** pending prototype <bead-id> (DEC-NNNN)` under the dependent requirement, then continue. `halt`: the same bead and row, then stop planning with that pointer.
- **D-5.9 Spike deletion.** The fence's force-delete rule P5 (`block-destructive-bash.sh:619-681`) gains a positive predicate beside `_fr11_all_merged`: `git branch -D spike/<slug>` passes when the ledger holds a `decided` row whose `source` is `grimoires/loa/spikes/<slug>.md`. A failed lookup leaves the block in place.

#### FR-6: glossaries
- **D-6.1 Two files (D10).** `.claude/loa/GLOSSARY.md` is mounted into every project and seeds: Flatline, voice, dissent, Bridgebuilder, cheval, ICE, jack in, grimoire, lore, construct, beads (alias `br`), run mode (aliases `RUNNING`, `HALTED`, `JACKED_OUT`), zone, Karpathy principles, kaironic, implement gate, verdict trailer (alias `LOA-VERDICT`), known failure, decision ticket, map epic, seam, spike, round, frontier, DEC row, truename, golden path, and the four `decision:` labels. The project glossary is the root `GLOSSARY.md`, created lazily; in this repo it holds record branch, zone marker and cycle. Format §4.5; lore stays in `.claude/data/lore/`.
- **D-6.2 Drift check.** `tools/check-glossary-terms.sh` (§5.3) checks `CLAUDE.loa.md` against `.claude/loa/GLOSSARY.md`, keeping backticked spans matching `^[A-Za-z][A-Za-z0-9_-]*$`. That shape admits none of `/`, `.`, `--`, `:` or `(` and no leading `/`, so every PRD exclusion holds; it also drops spaced phrases and operators (today `hit your session limit`, `out of extra usage`, `*_TEST_MODE=1`, `>>`, `jq -S`). Matching is case-insensitive on `**Term**` or `_Aliases_:` tokens with plural `s`/`es` folded; the PRD was aligned to the `_Aliases_:` line. The allowlist seeds 11 tokens; more than 30 fails.
- **D-6.3 CI.** `.github/workflows/check-glossary-terms.yml` runs in this repo only: every PR and push to main, one gate step, a positive control (`tests/fixtures/glossary/miss/` exits 1) and a negative control (`ok/` exits 0). Pinning `actions/checkout` by commit SHA, as the existing workflows do, is an implementation requirement.
- **D-6.4 Validator type.** `--type glossary` on either file: an H1; a context paragraph; `## Language`; entries `^\*\*[^*]+\*\*: .+` with ≤ 2 sentences and ≤ 300 chars; `_Avoid_:` and `_Aliases_:` follow an entry; no duplicate term or alias; WARN on paths or file extensions in `## Language`.
- **D-6.5 Planning rules.** `discovering-requirements` Phases 1-7 and `designing-architecture` Phase 2: "Challenge fuzzy or conflicting terms against `.claude/loa/GLOSSARY.md` and the project `GLOSSARY.md` (create it if needed); update only the project one, inline." `riding-codebase/SKILL.md:108-112` reads both as reality inputs. `reviewing-code/resources/REFERENCE.md:30-37` gains "- [ ] New domain terms are defined in a glossary (LOW if not)".

#### FR-7: seams and red-before-green
- **D-7.1 Template.** `sprint-template.md` gains `### Seams Under Test` (`| Seam | Catches | Misses | Prior art |`) after `### Technical Tasks` (`:49-60`, `:129-133`); `planning-sprints` Phase 2 asks the seams as one round.
- **D-7.2 Validator gate.** `SPRINT_REQUIRED_SECTIONS` (`validate-artifact.sh:193-201`) is unchanged. `validate_sprint()` (`:206`) reads the header `**Date:**`: on or after `SEAMS_REQUIRED_FROM=2026-10-13` every sprint block must carry the block; earlier or undated plans WARN. The archived cycle-127 plan and the undated fixtures pass; this cycle's plan carries the block in all three sprints.
- **D-7.3 Spec-axis check.** `reviewing-code/SKILL.md` Phase 2 (`:213-216`): "Tests exist at each declared `### Seams Under Test` seam. For a `/bug` micro-sprint, run `.claude/scripts/red-test-check.sh --red <Red commit from reviewer.md> -- <test command>` and cite its output for 'Test fails with current code'." Room comes from compressing Phase 1 step 5 (`:209`).
- **D-7.4 Two commits.** `micro-sprint.md:23-31` Task 1: "Committed alone (`test(<bug_id>): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`"; Task 2: "The fix is a later commit and does not weaken the test".
- **D-7.5 The check.** `red-test-check.sh` (§5.2) takes the test command as argv after `--`, never through `bash -c` (this supersedes the PRD's positional form; the sprint plan carries the new CLI). It runs in two detached temporary worktrees, so uncommitted state never counts and no stash is used, and always prints the red run's output. Honest scope, as in `validate-ac-verification.sh:10-14`: it proves failed-before and passes-after, not that the assertion is right.
- **D-7.6 Not-a-red detection.** Exit 4 when the named test file is absent at red, or the red run fails for a non-assertion reason matched on its output: bats `not found` or a syntax error, pytest `ERROR collecting` or `ImportError while importing`, node `Cannot find module` or `SyntaxError`, cargo `could not compile`, Go 1.22 toolchain `build failed` or `[setup failed]`. Patterns live in one array with a comment per runner.
- **D-7.7 Worktree bootstrap, timeout and cleanup.** By default the script symlinks `node_modules`, `.venv`, `vendor`, `target` and `.tox` from the live tree into each temp worktree when they exist there and are absent in the worktree; `--no-link-deps` turns that off; `--setup <cmd>` runs in each worktree before the test (failure exits 2). `--timeout <s>` (default 600) bounds each run; it uses `timeout`, else `gtimeout`, else a bash wrapper (background run, `sleep`, `kill -TERM` then `-KILL`); a timed-out run yields `TIMEOUT`, exit 5. One `trap … EXIT INT TERM` removes both worktrees (`git worktree remove --force`, then `git worktree prune`) on every exit path; bats assert `git worktree list` shows only the main tree afterwards.

#### FR-8: operator-only commands
- **D-8.1 Flag set.** `disable-model-invocation: true` on the safe set (D8): `loa-eject`, `toggle-gpt-review`, `permission-audit`, `loa-setup` (command file only), plus the new `/decisions`. `toggle-gpt-review.md` and `loa-setup.md` gain a minimal frontmatter block. The `loa-setup` skill is flagged too only if the harness check shows the operator's own `/loa-setup` still works with the skill flagged.
- **D-8.2 Triage.** Each reference to `update-loa`, `mount`, `contribute`, `feedback`, `deploy-production`, `archive-cycle`, `ship`, `run-halt`, `run-resume` in another body is classified "advice to the human" or "orchestrator step"; a command is flagged only if every reference is advice. `ship.md:60,64` executes `/deploy-production` and `/archive-cycle`, so both stay unflagged.
- **D-8.3 Allowlist and lint.** `.claude/data/user-invoked-commands.txt` lists flagged names, `gpt-review` and `decisions` included. `user-invoked-commands.bats` asserts: each listed command carries the flag; no other body has an operative line for a listed name (`(Execute|Invoke|Run|Call)[[:space:]]+`?/<name>\b` or `Skill\(.*<name>`, with none of `user|operator|human|manually|suggest|recommend|tell|ask` on the line); every flagged command file is listed; no SKILL.md `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`.
- **D-8.4 Live check first, automated.** Sprint 1 task 1.1, before any flag lands, adds `tests/unit/harness-hidden-command.bats`:
  1. Skip (bats `skip`, never a pass) when `claude` is not on PATH or `LOA_LIVE_HARNESS != 1`.
  2. Build a temp project under `BATS_TEST_TMPDIR`: `git init`, `.claude/commands/fixture-hidden.md` with `disable-model-invocation: true`, and a control `fixture-visible.md` without it; each body says "reply with the word FIXTURE-OK".
  3. In that directory run `timeout 180 claude -p --max-turns 3 --output-format stream-json --verbose --no-session-persistence "Use the Skill tool to invoke the skill named fixture-hidden, then report the tool's response verbatim."`, then the same for `fixture-visible`, and parse the JSON events with `jq`.
  4. Outcomes. CLI error, timeout or unparsable output: skip with the reason. Control without a Skill `tool_use` for `fixture-visible` whose `tool_result` contains FIXTURE-OK: skip, "inconclusive: control not invocable". Hidden run with a `tool_result` containing FIXTURE-OK: fail, "flag does not hide the command". Hidden run with no Skill `tool_use` for it, or one whose `tool_result` is an error: pass.
  The lead runs it once with `LOA_LIVE_HARNESS=1` and records the output in the sprint a2a. A failure records FR-8 as lint-only and G-7 as partial; the flags and the lint still land.
- **D-8.5 Triage rows.** Each triage outcome is a row in `grimoires/loa/a2a/sprint-252/triage-fr8.md` (command, reference type, decision, rationale, evidence) and a `proposed` DEC row with `source` = the command file, written by the lead at sprint close (task 1.8, D-3.18).

## 2. Software Stack
| Component | Version | Use |
|---|---|---|
| GNU bash | 5.2 (`set -euo pipefail`; bash-4 constructs guarded per `shell-conventions.md`) | every script and hook |
| jq | 1.7 | row assembly, equality checks, INDEX JSON, round blocks, harness events |
| yq (Mike Farah) | v4.44; a new hard dependency for the ledger (writer preflight, `run-preflight.sh` P9, `INSTALLATION.md`; already a README prerequisite at `README.md:45`); optional for `grimoire-index.sh` | ledger read and append (`strenv`/`env` only) |
| beads_rust `br` | 0.2.6 (`--type question`, `--parent`, `--labels`, `--external-ref`, `--slug`, `dep add`, `update --claim`, `update --external-ref`, `comments add`, `ready --parent --type`) | decision tickets; not required by the writer |
| Lock | util-linux flock 2.41 when present, else a `mkdir` lock | writer lock |
| Timeout | coreutils `timeout` 9.x, or `gtimeout`, else a bash wrapper | `red-test-check.sh`, `chart-unblock-probe.sh` |
| bats-core | 1.x, plus the BSD PATH-shim twins (`*-bsd.bats`, as `validate-artifact-bsd.bats`) | unit suites |

## 3. Database Design

### 3.1 `grimoires/loa/decisions.yaml`
```yaml
schema_version: 1
decisions:
  - id: DEC-0004                        # ^DEC-[0-9]{4,}$, never reused       (immutable)
    created_at: "2026-10-13T12:00:00Z"  # writer clock, UTC                  (immutable)
    updated_at: "2026-10-14T09:00:00Z"
    phase: discovery                    # discovery|architecture|sprint-planning|implementation|review|charting|spike|operations
    category: scope
    summary: "rounds is the thorough default"           # one line, <= 160 chars, plain prose
    decision: "interview.pacing defaults to rounds in thorough mode"   # set at decide
    rationale: "brief recommendation; supported opt-out"                # set at decide
    alternatives_considered:                                           # set at decide, >= 1
      - {option: "keep sequential default", rejected_because: "one question per turn is the slow path"}
    consequences: {positive: ["fewer turns"], negative: ["a default changes"]}
    proposed_by: agent                  # agent|flatline|dissent, derived (D-3.11)
    decided_by: operator                # null until decided; set by /decisions confirm
    decided_by_ref: "session:4f2a#turn-12"   # grammar D-3.11, interactive only
    evidence_sha256: null               # flatline/dissent artifact hash
    recorded_by: "plan-and-analyze/4f2a"
    commit: 76e7650b                    # HEAD at creation
    source: "grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf-unattended-planning (D1)"
    cycle: cycle-128
    supersedes: null
    supersede_proposed_by: null
    status: decided                     # open|proposed|decided|superseded|rejected
    transitions:
      - {at: "2026-10-13T12:00:00Z", from: null, to: proposed, by: "agent:plan-and-analyze", evidence: "prd.md Appendix E"}
      - {at: "2026-10-14T09:00:00Z", from: proposed, to: decided, by: "operator:decisions-command", evidence: "session:4f2a#turn-12"}
    rejection_rationale: null           # set at reject
    follow_up: null                     # set at reject: bead id or NOTES anchor
    prior_requests: []
```
Rules (`validate_decisions`): known `schema_version`; unique `DEC-` ids and no `PEND-` id; identity and provenance fields present; enums enforced; `decided_by` null unless `decided|superseded`; `transitions` start with `null → open|proposed`, each `from` equals the previous `to`, the last `to` equals `status`, every step allowed (D-3.12), every `by` matches `^(operator|agent|flatline|dissent):[A-Za-z0-9_.-]+$`; every `→ decided` and every `decided → superseded|rejected` step has `by: operator:*`; `decided_by_ref` matches its grammar; `flatline`/`dissent` rows' artifact exists and hashes to `evidence_sha256`; `rejected` rows carry `rejection_rationale` and `follow_up`; `supersedes` names an existing `superseded` row; content unchanged against the base (D-3.8, D-3.13); D-3.17 rules on every free-text field; `pii-filter.sh`. Pending files use the same schema with `PEND-<8 hex>` ids.

### 3.2 Beads conventions
| Object | Type | Labels | Links |
|---|---|---|---|
| Map | `epic` | `map` (never `sprint:`) | parent of its tickets |
| Decision ticket | `question` | exactly one `decision:grilling|prototype|research|unblock`; `deps:none` when unblocked; never `sprint:` | `--external-ref <DEC-id>`; `br dep add <ticket> <prerequisite>` |
| Interview prototype | `question`, no parent | `decision:prototype` | `--external-ref <DEC-id>` |
| Resolution | comment + close | n/a | `br comments add <id> "Proposed: … (DEC-NNNN)"`; `br close <id> --reason DEC-NNNN` |

## 4. UI Design

### 4.1 A round (REFERENCE.md §Question Pacing)
The frontier is every open question whose prerequisites are settled. A question that depends on another still open waits. Questions are numbered across the session, each worded so "yes" accepts the recommendation. Answers follow D-1.5. The frontier is recomputed before the next round. There is no cap on round size, and "wrap up" ends the phase.
```
Round 2 (Functional Requirements)

❓ Q4: Ledger location
Should the decision ledger live at grimoires/loa/decisions.yaml, tracked?
➡ Recommended: yes (the spec and two readers already point there; decision-lineage.md:23)

❓ Q5: Unattended record
Should unattended runs write a DEC row for every decision they take for you?
➡ Recommended: yes (makes "which did a human decide?" answerable)

"yes" accepts both; answer by number to override one.
<!-- round: 2; questions: [{"id":"Q4","depends_on":[]},{"id":"Q5","depends_on":["Q1"]}] -->
```

### 4.2 Map doc (`charting-decisions/resources/templates/map.md`)
```
# Map: {title}

**Slug**: {slug}
**Status**: charting
**Epic**: {bead-id}
**Created**: {YYYY-MM-DD}

## Destination
{What is true when the effort is done, ≤ 3 sentences.}

## Decisions so far
- {Decision name} ({DEC-NNNN}, {bead-id}): {one line}

## Not yet specified
- {fog item}

## Out of scope
- {item}: {why}
```
The only other H2 allowed is a final `## Closed` (D-4.8).

### 4.3 Session-start surface (inside the L6 fence)
```
[DECISIONS] 2 proposed, 1 open (grimoires/loa/decisions.yaml):
- DEC-0007 proposed: rounds is the thorough default
- DEC-0008 proposed: decided_by is derived by the writer
- DEC-0031 open: Which transport measures the Opus ceiling
[DECISIONS] map ceiling-arc open 41 days: /chart ceiling-arc, or /chart close ceiling-arc --reason <why>
[DECISIONS] .run/unattended.json is stale (other session or older than 24 h): ignored; clear it with /decisions clear-unattended
Confirm proposed rows with /decisions confirm.
```
More than 10 rows adds "… and K more: dec-write-lib.sh list --status proposed".

### 4.4 Spike report (`grimoires/loa/spikes/TEMPLATE.md`)
H1 `# Spike: {slug}`, header lines `**Bead**:`, `**Branch**: spike/{slug}`, `**Date**:`, then H2 `Question`, `What was built`, `Verdict` (one line), `Pointer` (branch and commit, or path), `Decided by` (`operator` or `agent`, plus the DEC id).

### 4.5 Glossary
```
# Glossary: Loa framework
The shared language of the Loa agent framework, for humans and agents.

## Language

**Dissent**: A second model's independent review of the same diff, triaged before a gate verdict.
_Avoid_: second opinion, cross-check

**Run mode**: Unattended execution of a sprint plan with a circuit breaker.
_Aliases_: RUNNING, HALTED, JACKED_OUT
```

### 4.6 PR body section
```
### Decisions taken on your behalf
| Decision | Voice | Status | Why | Source |
|---|---|---|---|---|
| rounds is the thorough default (DEC-0007) | agent | proposed | brief recommendation | prd.md Appendix E D1 |
| ceiling route policy (DEC-0019) | flatline | proposed | BLOCKER override | .flatline/runs/…json |
Confirm with /decisions confirm.
```

## 5. API Specifications

### 5.1 `dec-write-lib.sh`
| Op | Required | Optional | Effect | Caller |
|---|---|---|---|---|
| `new` | `--summary --phase --category --recorded-by --source` | `--status open\|proposed` (default `open`), `--decision --rationale --alternative-json` (repeatable; required for `proposed`), `--consequence-pos/-neg`, `--answer-ref`, `--as flatline\|dissent`, `--cycle`, `--pending` | appends a row; prints the id (`PEND-…` in a worktree) | skills, lead |
| `decide` | `--id --decision --rationale --alternative-json --recorded-by` | `--answer-ref`, `--as`, `--consequence-pos/-neg` | `open` → `proposed` | skills, lead |
| `confirm` | `--recorded-by` and `--id …` or `--cycle <c>` | `--all`, `--answer-ref` | `proposed` → `decided`; preview; refused on a live-run signal | `/decisions` only |
| `reject` | `--id --rationale --follow-up --recorded-by` | `--prior-request` (repeatable) | `open\|proposed` → `rejected`; on a `decided` row, `/decisions` only | skills (open/proposed), `/decisions` |
| `supersede` | `--id <old>` plus the `new` flags | none | operator: new row, old → `superseded`; agent: new `proposed` row, old gains `supersede_proposed_by` | `/decisions` for decided rows |
| `import` | `--from <pending>` | `--rewrite <path>` (repeatable) | pending rows → `DEC-` ids; refs rewritten; pending file deleted | lead, main checkout |
| `list` | none | `--status --voice --decided-by --cycle --since --source-prefix --format tsv\|md\|json` | read-only; unknown `schema_version` WARNs | anyone |
| `context` | none | `--why`, `--set-unattended --reason R`, `--clear` | prints `unattended\|interactive`; `--clear` from `/decisions` only | anyone |
Common: `--file PATH`, `--quiet`. Exit: 0 ok; 1 refused (preflight, CI or hook context on the live ledger, validation, verify, lock busy, unknown id, illegal transition, ref grammar, missing artifact, ambiguous `confirm --cycle`); 2 usage. Lock: `flock -w 10` when present, else `mkdir "$LOCK.d"` with a pid file, broken only when older than 60 s and its pid is not alive.

### 5.2 `red-test-check.sh`
```
red-test-check.sh --red <commit> [--green <rev>] [--test-file <path>] [--setup <cmd>]
                  [--no-link-deps] [--timeout <s>] [--json] -- <test command...>
```
1. Resolve both commits; red must be a strict ancestor of green (default HEAD), else exit 2.
2. With `--test-file`, it must exist at red (`git cat-file -e <red>:<path>`), else exit 4.
3. Install the cleanup trap, then `git worktree add --detach` both under `mktemp -d`.
4. In each worktree, link the present dependency dirs (D-7.7), then run `--setup` if given (failure exits 2).
5. Run the argv in each under the timeout (default 600 s); print the red output (last 80 lines) and keep both exit codes.
6. Verdict: red fails by assertion and green passes → 0 `VERIFIED`; green fails → 1 `GREEN_FAILS`; red passes → 3 `DECOY`; red fails by a D-7.6 pattern → 4 `NOT_A_RED`; a run times out → 5 `TIMEOUT`. `--json` adds `{red, green, red_exit, green_exit, verdict, red_tail, green_tail, linked_deps}`. No non-test file changed between red and green → WARN.

### 5.3 `check-glossary-terms.sh`
`tools/check-glossary-terms.sh [--kernel PATH] [--glossary PATH] [--allowlist PATH] [--json]`; defaults `.claude/loa/CLAUDE.loa.md`, `.claude/loa/GLOSSARY.md`, `.claude/data/glossary-allowlist.txt`. Exit 0 ok (WARN on stale allowlist entries), 1 a miss or an allowlist over 30 entries, 2 usage.

### 5.4 `check-round-independence.sh`
`tools/check-round-independence.sh <transcript> [--min-average N] [--json]` (default N = 2). Extract each `<!-- round: N; questions: […] -->` and parse the array with `jq`. Fail when a non-reasked id repeats, a `depends_on` names a question of the same round, or names one not asked in an earlier round. `reasked` entries are skipped for uniqueness and the average. Report rounds, questions and the average per round, excluding the final round when there are two or more. Exit 0/1, 2 when no block is found.

### 5.5 Validator types and other contracts
- `validate-artifact.sh --type prd|sdd|sprint|bug-triage|translation|decisions|map|spike|glossary --file <path> [--base-file <path>] [--json]`, exit 0/1/2. `prd` gains tag classes, the dated bare-tag rule and `**Deferred:**` (D-2.5); `sdd` the DEC column WARN (D-3.16); `sprint` the Seams date gate, the beads cross-check and the deferred-requirement WARN.
- `/decisions confirm [--id …|--cycle <c> [--all]] | reject --id … | supersede --id … | list | clear-unattended`.
- `golden_detect_plan_phase` → `discovery|charting|architecture|sprint_planning|complete`.
- `create-sprint-task.sh` exits 1 on `type=question` or a `map` epic before creating anything.
- `get-ready-work.sh [limit] [--ids-only] [--graph] [--include-questions]`.
- `chart-unblock-probe.sh --ticket <id> [--timeout <s>] -- <cmd…>`, exit 0, or 1 when the main tree changed.
- `run-mode-ice.sh is-spike <branch>`; `merge [<source>]` per D-5.3; `pr-create` exits 1 on a `spike/*` head.
- `run-preflight.sh` P9: Mike Farah yq v4 present, FAIL otherwise.
- Config: `interview.pacing: sequential|batch|rounds`; `interview.unattended_prototype: defer|halt`; `decisions.surface_at_session_start: false`; `decisions.unattended_marker_ttl_hours: 24`.

## 6. Error Handling Strategy
| Surface | Posture | Behaviour |
|---|---|---|
| `dec-write-lib.sh` writes | fail closed | preflight miss, live-ledger write under `CI`/`GITHUB_ACTIONS`/`LOA_HOOK_CONTEXT`, lock wait over 10 s, ref or attribution refusal, any verify failure: exit 1, temp deleted, original untouched |
| Live ledger writers | single writer (D-3.18) | only the lead's main checkout writes; a linked worktree writes the pending file; `import` allocates ids; a duplicate or `PEND-` id fails `--type decisions` |
| Operator-only ops | `/decisions` only | `confirm`, decided-row `reject`/`supersede`, `context --clear` are absent from every skill's `allowed-tools` (bats-checked) |
| `dec-write-lib.sh list`, `context` | read-only | unparsable ledger: exit 1; unknown `schema_version`: one WARN |
| `loa-decisions-surface.sh` | fail open | disabled silent; broken or unknown schema: one WARNING line; stale marker: one notice; always exit 0; `hook-guard.sh` |
| `grimoire-index.sh` decisions family | fail soft | no yq or unparsable ledger: skipped with a stderr note |
| `/chart` unattended | refuse | message names the interactive path; nothing written; close only with `--consumed-by` |
| `/plan` or `/plan-and-analyze` with several open maps, unattended | exit 1 | "more than one open map: name one" plus the slugs; nothing written |
| Research subagents | bounded | ≤ 5 per chart; `maxTurns: 40`; 20 min advisory; out-of-scope writes fail the ticket |
| `create-sprint-task.sh` lint | fail closed | exit 1 with repair text before `br create` |
| `validate-artifact.sh` | fail closed | 0 pass, 1 violations with repair text, 2 usage; beads cross-checks skipped with an info line without `br` |
| `red-test-check.sh`, `chart-unblock-probe.sh` | verdict codes | 0/1/2/3/4/5 (§5.2); worktrees removed by the EXIT/INT/TERM trap on every path |
| `harness-hidden-command.bats` | skip, never pass | every outcome defined in D-8.4 |
| `check-glossary-terms.sh`, `check-round-independence.sh` | fail closed in CI and bats | exit 1 lists each miss |
| ICE spike rules, SP-1, the spike-delete predicate | fail closed | exit 1 (ICE) or 2 (fence); an unestablished predicate keeps the block |

## 7. Testing Strategy
Red first for every behaviour.

| Suite | Cases |
|---|---|
| `dec-write-lib.bats` (mirrors `kf-write-lib.bats`, always `--file <copy>`) | next id; never shrinks; never drops an id; held lock makes a second writer exit 1; failed write leaves the file intact; missing `jq` or a non-v4 `yq` fails closed, missing `br` does not; live-ledger write refused under `CI=1` and `LOA_HOOK_CONTEXT=1`; every write lands `open`/`proposed` and `decided_by` stays null; `--answer-ref` ignored with a WARN under a RUNNING marker, a fresh `.run/unattended.json`, `LOA_UNATTENDED=1` and the PRD Status line; a stale marker is ignored; ref grammar refusal; `--as flatline` refused for a missing artifact and stores `evidence_sha256`; `confirm` sets `operator` for an operator ref and refuses on a live-run signal; `confirm --cycle` with two matches refuses without `--all`; agent `supersede` of a decided row sets `supersede_proposed_by`; `reject` without `--follow-up` refused and records `rejection_rationale`; content edits refused while a transition append is accepted; linked worktree writes `PEND-` rows to the pending file; `import` allocates ids, rewrites refs and deletes the file; duplicate id fails validation; the D-3.3 fixture set round-trips byte-equal against the sanitised input; 1,000-row op < 1 s; `list --format md --voice --cycle` output |
| `dec-write-lib-bsd.bats`, `red-test-check-bsd.bats` | PATH shims hide `flock` and `timeout` and force POSIX regex: the `mkdir` lock serialises two writers and breaks a stale lock; the bash timeout wrapper yields exit 5 |
| `decisions-surface.bats` | disabled silent; healthy table with proposed first; stale map line; stale-marker notice; unknown schema WARN; negative case: ESC sequences, a NUL, `</untrusted-content>` and "ignore previous instructions" text come out control-stripped, capped at 100 chars, inside the L6 fence with the closing tag neutralised |
| `round-independence.bats` | independent fixture passes at the default minimum; a final one-question round does not lower the average; `reasked` entries are ignored; a same-round `depends_on` fails; an unknown or later dependency fails; no block → exit 2 |
| `unattended-prototype.bats` | `defer`: bead, open row and the PRD `**Deferred:**` line, planning continues; `halt`: same bead and row, planning stops |
| `harness-hidden-command.bats` | D-8.4 outcomes |
| `user-invoked-commands.bats` | the D-8.3 assertions, including `/decisions` flagged and no skill granting operator-only ops |
| `charting-lint.bats` | `create-sprint-task.sh` refuses `question` and `map` epics (stub `br` proves `create` never ran); `get-ready-work.sh` drops `question` and keeps every other type present; implement path calls `get-ready-work.sh`; sprint cross-check; `--type map` passes the template, fails on an extra H2, a URL, a bullet without a DEC id, WARNs on a Status/epic disagreement; fixture chart under `br --dry-run` creates epic, children, labels, edges and open rows in order; re-run idempotent by `source`; refusal with `LOA_UNATTENDED=1`; unattended close without `--consumed-by` refused; close flow; ≤ 5 research dispatches; scope check catches a write under `.beads/`; `chart-unblock-probe.sh` exits 1 when a probe touches the main tree |
| `golden-path-charting.bats` | Status `charting`, no PRD → `charting`; none → `discovery`; `handed-off`, `closed` or `abandoned` → `discovery`; PRD plus open map → `architecture`; two open maps or two `chart-*.md` snapshots under `LOA_UNATTENDED=1` → exit 1 "more than one open map: name one", nothing written |
| `spike-validator.bats`, `run-mode-ice.bats`, fence corpus | template passes, empty Verdict fails; `is-spike`; `merge` without a source unchanged; `merge main` on `spike/x` allowed, `merge spike/x` refused, `merge main` on a feature branch blocked, spike `pr-create` refused; corpus: `git push -u origin spike/x`, `git checkout spike/x`, `git merge main`, `git rebase main` allow; `git merge spike/x`, `git rebase origin/spike/x`, `git pull origin spike/x`, `git cherry-pick spike/x~1`, `git checkout spike/x -- src/a.ts`, `git restore --source spike/x src/a.ts`, `gh pr create --head spike/x` block; `git branch -D spike/x` blocked without a decided row, allowed with one |
| `glossary-terms.bats` | live pair passes; undefined token named; alias and plural resolve; allowlist over 30 fails; stale allowlist WARN; `--type glossary` fails a three-sentence definition and a duplicate alias |
| `red-test-check.bats` | `--red … -- cmd` VERIFIED → 0 with red output printed; decoy → 3; test file absent → 4; bats syntax error and pytest collection error at red → 4; non-fix → 1; non-ancestor → 2; a test importing a fixture `node_modules` dependency passes through the default link and is not-a-red under `--no-link-deps`; `--setup` runs in both worktrees; a sleeping test → 5; after every case, including an interrupted run, `git worktree list` shows only the main tree |
| `validate-artifact.bats` additions | `decisions` (live file, duplicate id, `PEND-` id, missing operator transition, content edit, rejected without follow-up, bad ref grammar, hash mismatch, unknown schema); `prd` fixtures: tag classes, bare WARN before and FAIL after `BARE_ASSUMPTION_FAILS_FROM`, an unattended PRD with N `[ASSUMPTION decision]` tags each citing its row, an uncited tag failing unattended and WARNing interactive, `**Deferred:**` recognised; `sprint`: Seams date gate, deferred-requirement WARN; `sdd` DEC column WARN |
| `grimoire-index` additions | `emit_decisions()` rows and the `## decisions` table from a two-row fixture; the same fixture through `loa-learnings-index.sh` and `get_decisions_path` |
| `render-templates` check | the PR-body step renders the §4.6 table from a fixture ledger, and the zero-row line from an empty one |

**Rounds fixture** (G-3): a scripted headless transcript on a fixture context in `rounds` mode is checked by `check-round-independence.sh` in bats; turns against a `sequential` run of the same fixture are recorded in `grimoires/loa/a2a/sprint-252/rounds-rubric.md`.

Regression suites that stay green: `prompt-budget.bats`, `skill-capabilities.bats`, `skill-capabilities-role-lint.bats`, `no-history-in-rule-text.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-artifact.bats`, `validate-artifact-bsd.bats`, `kf-write-lib.bats`, `run-mode-ice.bats`, `block-destructive-bash.bats` (baseline unchanged except new rows), `tests/integration/test_golden_path.bats`. Before the PR: `check-no-raw-sha256sum.sh`, the shell-compat greps, `repo-map-gen.sh` with `REPO-MAP.md`, `.checksum` and `checksums.json` staged together.

## 8. Development Phases

### Sprint 1 (global 252): ledger, rounds, attribution, operator-only commands
1. FR-8 live-harness check, before any flag lands: `harness-hidden-command.bats`, run once by the lead with `LOA_LIVE_HARNESS=1` (D-8.4).
2. FR-3 writer: `dec-write-lib.sh` with context, preflight, portable lock, attribution, lifecycle, pending/import, append-only verify, the YAML fixture set, and its bats and BSD twin (D-3.3–D-3.5, D-3.11–D-3.14, D-3.18). Implementers use `--file` fixtures only.
3. FR-3 surfaces: ledger file and tracking, `/decisions`, `--type decisions`, index family, session surface, `hook-guard.sh` export, `run-preflight.sh` P9, settings and config, `INSTALLATION.md`, readers check, SDD DEC-column WARN (D-3.1, D-3.6–D-3.10, D-3.12, D-3.16, D-3.17).
4. FR-1: table moves, §Question Pacing, pointer, key scope, answer semantics, round block, `check-round-independence.sh`, config example, Phase 2 lines (D-1.1–D-1.7); budget check.
5. FR-2: Backpressure with tag classes, Karpathy §1, prime directive, PR-body section, PRD and sprint validator rules, debrief rows, template appendices (D-2.1–D-2.7).
6. Seed the live ledger, written by the lead at sprint close and before the PRD gate first runs on this cycle's PRD: cycle-127 D1–D3, cycle-128 D1–D16 and A1–A41, all `proposed` (D-3.15).
7. Rounds fixture transcript and rubric (§7).
8. FR-8: flags on the safe set and `/decisions`, the conditional `loa-setup` skill flag, triage table, allowlist, bats; triage DEC rows written by the lead at sprint close (D-8.1–D-8.3, D-8.5).

### Sprint 2 (global 253): `/chart`, prototypes, spikes
1. Build-path exclusion lints with bats (D-4.7).
2. `chart.md`, `charting-decisions`, map template, `chart-researcher`, `chart-unblock-probe.sh` (D-4.1–D-4.4, D-4.10–D-4.12); capabilities lint; budget.
3. Lifecycle: hand-off snapshot, close, `plan-and-analyze.md` steps, golden path, `plan.md` rules (D-4.5, D-4.6).
4. Map validator and research negation (D-4.8, D-4.9).
5. FR-5: interview rule, unattended deferral key, ICE direction, SP-1 and the spike-delete predicate with corpus rows, spike template and validator, verdict row on the working branch, High-Risk Early text (D-5.1–D-5.9).
6. Fixture map walked end to end under `br --dry-run`; one-cycle idea stops without beads.

### Sprint 3 (global 254): glossaries, seams, red test, E2E
1. `.claude/loa/GLOSSARY.md`, root `GLOSSARY.md`, allowlist, `check-glossary-terms.sh`, CI with controls, `--type glossary` (D-6.1–D-6.4).
2. Planning-skill glossary rules and the review checklist row (D-6.5).
3. Seams block, dated validator rule, this cycle's `sprint.md` blocks (D-7.1, D-7.2).
4. `red-test-check.sh` with the `--red … --` CLI, dependency links, timeout, not-a-red detection and its BSD twin; micro-sprint two commits; review Phase 2 line (D-7.3–D-7.7).
5. E2E: an unattended planning fixture writes `proposed` agent rows, the PRD validator passes its cited tags, the PR-body section renders them, `/decisions confirm` moves them to `decided`; a worktree writes a pending row and `import` lands it; a fixture chart from idea to `## Closed`; a spike report and verdict row on the working branch; the glossary drift check green; every regression suite green; CHANGELOG `[Unreleased]` entries.

## 9. Known Risks and Mitigation
| Risk | Mitigation |
|---|---|
| Attribution is forgeable: an agent with Bash can run the writer directly, edit `.run/`, or invent a ref | honest limit: attribution is tamper-evident (`evidence_sha256`, `commit`, append-only transitions, ref grammar, review of the diff), not cryptographically signed; operator ops live only in `/decisions` and no skill grants them; signing rows through the existing `audit_emit_signed` chain (`audit-envelope.sh:551`) is a future iteration |
| Parallel writers collide on ids or produce unmergeable YAML | single writer plus pending file and `import` (D-3.18); duplicate and `PEND-` ids fail validation |
| Budgets: `discovering-requirements` margin ≈ 150 B, `planning-sprints` starts at 14 B | moves land first in their own commit; measure after each edit; named fallback cuts per skill (§1.4) |
| yq v4 is now required for the ledger | preflight with repair text, `run-preflight.sh` P9, `INSTALLATION.md`; the index and surface degrade without it |
| Portability (macOS has no `flock` or `timeout`) | `mkdir` lock and bash timeout fallbacks; BSD shim twins |
| Old sprint plans break under the Seams rule | dated gate (D-7.2); a bats case pins archived and undated plans |
| `br ready` lists `question` beads to `/implement` | exclusion in `get-ready-work.sh`, the implement path routed through it, the creation lint, the sprint cross-check |
| yq round-trip reformats the ledger | verification is by row equality, not lines; a bats case pins comment survival |
| `br` flag semantics drift (`--external-ref`, `--parent`, `ready --type`) | `br` 0.2.6 pinned; charting-lint runs the real binary in `--dry-run` and a stub |
| SessionStart ordering hides the KF surface | synchronous, after the KF hook, `once: true`, `hook-guard.sh`, default off |
| The ICE merge exception widens ICE | optional argument, one direction only; bats pin the refusals and the unchanged default |
| `/chart` adds ceremony; `decision:unblock` drifts into build work | interactive only, no-fog stop, under-three close, one ticket per session; unblock only through the probe helper |
| Glossary rots | CI drift check with controls; allowlist cap of 30 |
| `disable-model-invocation` on a command an orchestrator needs | triage by reference class (D-8.2); bats assert no operative reference |
| Flatline cross-scoring degraded (KF-041) | integrate raw reviews by judgment; record the degradation |

## 10. Open Questions
There are no open questions. Every question raised by the PRD and this design is resolved; each resolution becomes a ledger row in Sprint 1 task 1.6.

| # | Question | Status | Resolved by | DEC |
|---|---|---|---|---|
| 1 | Default pacing for `thorough` | Resolved | D1, D-1.1 | pending seed, Task 1.6 |
| 2 | Ledger location and tracking | Resolved | D2, D-3.1 | pending seed, Task 1.6 |
| 3 | `/chart` as porcelain or truename | Resolved | D3, D-4.1 | pending seed, Task 1.6 |
| 4 | Research tickets via cheval or the Agent tool | Resolved | D4, D-4.10 | pending seed, Task 1.6 |
| 5 | Name of Pocock's `task` type | Resolved | D5, §3.2 | pending seed, Task 1.6 |
| 6 | Spike branch lifecycle | Resolved | D6, D-5.2–D-5.4, D-5.9 | pending seed, Task 1.6 |
| 7 | Glossary location | Resolved | D7 amended by D10, D-6.1 | pending seed, Task 1.6 |
| 8 | Which commands get the flag | Resolved | D8, D-8.1–D-8.2 | pending seed, Task 1.6 |
| 9 | B7 and LEARN items | Resolved (out of scope) | D9 | pending seed, Task 1.6 |
| 10 | Unattended prototype questions | Resolved | D11, D-5.8 | pending seed, Task 1.6 |
| 11 | `/chart` unattended | Resolved | D12, D-4.3 step 0 | pending seed, Task 1.6 |
| 12 | Confirmation of agent decisions | Resolved | D13, D-3.12 | pending seed, Task 1.6 |
| 13 | Who sets `decided_by` | Resolved | D14, D-3.11, D-3.12 | pending seed, Task 1.6 |
| 14 | Row mutability | Resolved | D15, D-3.13 | pending seed, Task 1.6 |
| 15 | Backfill scope | Resolved | D16, D-3.15 | pending seed, Task 1.6 |
| 16 | How `charting` is detected | Resolved | D-4.6 (A5) | pending seed, Task 1.6 |
| 17 | How old sprint plans survive the Seams rule | Resolved | D-7.2 (A10) | pending seed, Task 1.6 |
| 18 | Whether the flag hides commands | Resolved by a first-task check | D-8.4 | pending seed, Task 1.6 |
| 19 | Parallel writers and merges | Resolved | D-3.18 (A33) | pending seed, Task 1.6 |
| 20 | Where operator attribution comes from | Resolved | D-3.12 (A31) | pending seed, Task 1.6 |

## 11. Appendix

### 11.1 File inventory
Per-FR paths are in §1.3.

| Kind | Count | Items |
|---|---|---|
| New files and fixture dirs | 22 | round checker, rounds fixtures, writer, `/decisions`, surface hook, ledger, `/chart`, charting skill with REFERENCE and template (3), researcher agent, probe helper, spike template, two glossaries, glossary checker, allowlist, workflow, glossary fixtures (2), red-test check, command allowlist |
| New bats suites | 13 | round-independence, dec-write-lib, dec-write-lib-bsd, decisions-surface, charting-lint, golden-path-charting, spike-validator, unattended-prototype, glossary-terms, red-test-check, red-test-check-bsd, user-invoked-commands, harness-hidden-command |
| Modified scripts and hooks | 10 | validate-gitignore-state, grimoire-index, validate-artifact, golden-path, create-sprint-task, get-ready-work, run-mode-ice, block-destructive-bash, hook-guard, run-preflight |
| Modified config and data | 5 | `.gitignore`, config example, `settings.json`, `agent-types.yaml`, `INSTALLATION.md` |
| Modified protocol and render docs | 2 | karpathy-principles, render-templates |
| Modified SKILL.md | 7 | discovering-requirements, designing-architecture, planning-sprints, autonomous-agent, reviewing-code, riding-codebase, implementing-tasks (plus `loa-setup` only if D-8.1's condition holds) |
| Modified REFERENCE.md | 3 | discovering-requirements, planning-sprints, reviewing-code |
| Modified templates | 4 | prd-template, sdd-template, sprint-template, micro-sprint |
| Modified command files | 7 | plan, plan-and-analyze, implement, loa-eject, toggle-gpt-review, permission-audit, loa-setup |
| Modified fixtures and suites | 3 | fence corpus, `validate-artifact.bats`, `run-mode-ice.bats` |

Totals: 35 new, 41 modified, plus the triaged commands that qualify in Sprint 1.

### 11.2 PRD → SDD map
| FR | SDD |
|---|---|
| FR-1 | D-1.1–D-1.7, §4.1, §5.4 |
| FR-2 | D-2.1–D-2.7, §4.6 |
| FR-3 | D-3.1–D-3.18, §3.1, §4.3, §5.1 |
| FR-4 | D-4.1–D-4.12, §3.2, §4.2 |
| FR-5 | D-5.1–D-5.9, §4.4 |
| FR-6 | D-6.1–D-6.5, §4.5, §5.3 |
| FR-7 | D-7.1–D-7.7, §5.2 |
| FR-8 | D-8.1–D-8.5 |
| NFR Security | D-3.7, D-3.11, D-3.12, D-3.17, D-4.10, §9 attribution limit |

### 11.3 Decisions taken on the operator's behalf (this SDD, `decided_by: agent`)
Seeded as `proposed` rows in Sprint 1 task 1.6. Honest limit, restated: these rows and every ledger row are tamper-evident, not signed (§9).

| # | Decision | Alternatives | Why |
|---|---|---|---|
| A1 | Ledger lock fails closed after 10 s | best-effort lock (kf-write) | a lost update on a tracked ledger is worse than a retry |
| A2 | Temp file beside the target | `/tmp` | a cross-filesystem `mv` is not atomic |
| A3 | Verify by row equality plus field classes | line and id checks only | YAML re-serialisation moves lines |
| A4 | Optional `cycle` field, defaulted from run state | filter by timestamp only | a run spans days; `--since` is kept as the PRD's equivalent |
| A5 | `charting` from the map doc Status line | an open `map` epic in beads | golden-path must work without `br`; the doc wins on disagreement |
| A6 | Hand-off context snapshot; chart zones add `context` and `spikes` | edit discovering-requirements | no budget there. Widens the PRD's four-path zone list by two |
| A7 | `research/chart-*.md` tracked by a negation | track all research, or none | maps need their cites |
| A8 | Exclude `question` in `get-ready-work.sh` and route `/implement` through it | the `sprint:` lint alone | `br ready` is unfiltered today |
| A9 | Fence rule SP-1 plus the ICE spike rules | ICE only | ICE covers run mode only |
| A10 | Seams rule gated by Date ≥ 2026-10-13 | version gate, or always | old fixtures have no Date (PRD adopted it) |
| A11 | `_Aliases_:` lines; identifier-shaped tokens only | one entry per token | run states are one concept (PRD adopted it) |
| A12 | Flag the `loa-setup` skill only if the harness check shows the operator's command still works | always flag, never flag | a shared name may leave the skill reachable, but the operator's own command must keep working |
| A13 | Rounds within a phase | one frontier across phases | keeps phase gates and section order |
| A14 | Claim with `br update --claim` | `--status in_progress` | atomic assignee plus status |
| A15 | Synchronous surface after the KF hook | async | async output is not reliably injected |
| A16 | Sprint validator cross-checks beads | creation-time lint only | catches a `sprint:` label added by hand |
| A17 | Map docs allow exactly four H2s plus `## Closed` | a heading denylist | an allowlist cannot be dodged by a new name |
| A18 | `flatline`/`dissent` attribution needs an existing artifact and its sha256; no orchestrator call site this cycle | wire the orchestrators now | keeps the sanctioned review path unchanged; the hash makes the claim checkable |
| A19 | `confirm --cycle` previews and needs `--all` or `--id`s for several rows | confirm every match silently | batch confirmation stays explicit |
| A20 | The writer does not require `br` (superseded preflight rule) | preflight `br` everywhere | the ledger has no beads dependency; PR bodies render without beads |
| A21 | The PRD Status line is an unattended signal for the gate and the writer, not for `confirm` | ignore it, or let it block `confirm` | the writer and the gate agree, and the operator can still confirm later |
| A22 | Chart ticket rows use `source: map:<slug>/<ticket>`; the bead carries `--external-ref <DEC-id>` | `source` = bead id | the row is written before the bead exists and `source` is immutable |
| A23 | A `chart-researcher` agent without Bash, plus an ignored-files and mtime scope check | a general-purpose subagent told not to write | tool removal is mechanical; prompts are not |
| A24 | Spike deletion through a fence predicate on a decided row | operator deletes by hand only | the PRD allows deletion once decided; the predicate is positive and fails closed |
| A25 | `.run/unattended.json` with session id and TTL, plus a `context` subcommand | env variables only | Bash calls do not share env; a stale marker must not outlive its session |
| A26 | `/plan-and-analyze` closes a consumed map and applies the multi-map rule via command-file steps | edit discovering-requirements | no SKILL budget; the command file is not budgeted |
| A27 | Each `[ASSUMPTION decision]` line cites its DEC id | count tags against rows | a per-tag link is checkable; counts are not |
| A28 | ICE allows only the default branch into a `spike/*` branch, behind an optional argument | allow any merge into spikes | the narrowest exception, default behaviour unchanged |
| A29 | The live-harness bats is opt-in (`LOA_LIVE_HARNESS=1`) and every outcome is defined | run it in every CI job | a model call per CI run costs money and flakes; a skip is visible, a false pass is not |
| A30 | `red-test-check.sh` timeout is its own exit 5 and dependency linking is on by default | fold timeouts into exit 1; require `--setup` | a hung test is not a failing fix; fresh worktrees mostly fail on missing dependencies |
| A31 | `proposed_by` records the proposing voice; `decided_by` is set once, by `confirm` | one `decided_by` set at proposal | lets `decided_by` stay null until a human acts, without rewriting a set-once field |
| A32 | `/decisions` runs operator ops in the session, previewing first; no fence on the writer | a fence that blocks the ops for the model | the fence would also block the command itself; the boundary is the allowlists plus tamper evidence |
| A33 | Linked worktrees write `PEND-` rows to a sprint pending file; the lead imports | worktrees write the live ledger and merge | max+1 ids collide and an append-only YAML list does not merge |
| A34 | `mkdir` lock fallback with a 60 s stale check when `flock` is absent | require util-linux | macOS ships without `flock` |
| A35 | `hook-guard.sh` exports `LOA_HOOK_CONTEXT=1`; live-ledger writes refuse under it and under CI | prose prohibition only | makes "no bot auto-append" mechanical while fixtures still run in CI |
| A36 | `BARE_ASSUMPTION_FAILS_FROM=2026-11-13` | "one release" | a date is checkable; a release boundary is not |
| A37 | `get-ready-work.sh` filters out `question` instead of allowlisting types | `--type task --type bug --type feature` | new types keep flowing; only decision tickets are excluded |
| A38 | `decision:unblock` probes run only through `chart-unblock-probe.sh` | free Bash in the charting skill | the helper proves the main tree is untouched |
| A39 | BSD coverage through PATH-shim twins | a macOS runner | follows `validate-artifact-bsd.bats`; no new CI runner |
| A40 | `run-preflight.sh` P9 fails without yq v4 | WARN only | the ledger cannot be written without it |
| A41 | The append-only base defaults to `git merge-base origin/main HEAD` | `HEAD` | rows added on the branch remain checkable against main |
