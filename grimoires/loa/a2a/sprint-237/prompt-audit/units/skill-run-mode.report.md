
**Scope & target model.** Single file: `.claude/skills/run-mode/SKILL.md` (32,958 B). Target model: Claude Fable 5.1, per the brief. Read `METHOD-prompt-audit.md`, `METHOD-fable-5.1-migration.md`, `tools/prompt-keeplist.txt`, `keep-list.md`, the unit file, and skimmed `resources/{state-schemas,render-templates}.md` (not audited, per instructions).

**Headline finding: this file is mostly *not* prompt cruft.** It is a mechanical orchestration script (exact `jq`/`git`/state-machine steps) — the keep-list's "fragile operations keep exact scripts" class, not over-specification. Grepped for the whole Group-1 signal set (pressure language, hedges, chatty-model suppressors, step choreography for judgment tasks, prohibition walls, grader vocabulary) — none found beyond what's below. The dated-pattern findings are small (History-rule violations + one emphasis marker); they alone don't clear the 16,384 B budget, so the rest of the reduction is the brief's explicit fallback: moving conditionally-needed procedures (three secondary commands, an alternate `--bug` workflow, the whole `/run sprint-plan` wrapper, two optional gates, and the rare rate-limit-wait path) into six new `resources/*.md` files behind **guarded** (non-imperative) pointers, so `tools/check-prompt-budget.sh` doesn't charge them.

**Byte count**: 32,958 B → my manual estimate is **≈13,300 B**, comfortably under the 16,384 B budget. I have no Bash tool in this role, so I could not run `check-prompt-budget.sh` to confirm; please verify mechanically before merging.

**Pattern findings** (confidence-ordered):

| Location | Evidence | Pattern | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| `## Pre-Execution Guardrails` header | `(mechanized — cycle-119)` | History rule / Group 1d migration-relative phrasing | `cycle-NNN` in rule text, not a Provenance footer or backticked path; "mechanized" implies a retired unmechanized predecessor | High | remove; token moved to new `## Provenance` footer |
| guardrail fallback row | `Continue — fail-open, preserving pre-cycle-119 semantics` | Group 1d migration-relative phrasing (`preserving X semantics`) | diffs against a prompt version the model never saw | High | rewrite → `Continue — fail-open.` |
| `### Rate-limit wait` header | `(replaces prior "Sleep (in real implementation...)" placeholder)` | Group 1d migration-relative / patch-accretion phrasing | states history instead of the current rule | High | rewrite → header text alone (moved into `resources/conditional-procedures.md`) |
| `### Git-Aware State Sync` header | `(cycle-056, Issue #474)` | History rule | `cycle-NNN`/`#NNNN` in rule text | High | remove; tokens moved to Provenance footer |
| Beads-first check | `(autonomous mode requires beads by default, v1.29.0)` | Group 2 pinned version number | rots as the codebase advances past it; carries no instruction | Medium | remove version token |
| `### Post-PR Validation (v1.25.0)` | version marker | same | same | Medium | remove |
| `### Completion PR (Consolidated, default v1.15.1)` | version marker | same | same | Medium | remove (also dropped vestigial "default" — no alternative is documented in this file) |
| `## Completion and PR Creation (v1.30.0)` | version marker | same | same | Medium | remove |
| Bug PR line | `**CRITICAL**: Bug PRs are ALWAYS draft. Never auto-merged. Human approval required.` | Group 1a pressure language (emphasis marker stacked on an already-enforced rule) | current models are steerable at normal volume; stacked emphasis dilutes markers that matter elsewhere | Medium | rewrite, citing the mechanism: "Bug PRs are always draft and never auto-merged — ICE never creates a ready-for-review PR — so human approval is required before merging." |

**MUST/NEVER/ALWAYS kept** (each names its enforcing mechanism): the atomic-write `MUST` (names the pattern itself); "`MUST` go through the ICE wrapper" (names `run-mode-ice.sh`); ICE's never-push/never-merge/never-delete/always-draft-PR list (a contract description of what the script does, not a booster).

**Untrusted input**: none found — the audited text contains no strings that read as instructions addressed to the auditor.

**Budget moves (not pattern findings)** — each replaced in `SKILL.md` by a short, guarded (non-imperative) summary paragraph, per the brief's explicit fallback clause:

| Moved section | → Resource file |
|---|---|
| RED_TEAM_CODE gate, Post-PR Validation, Rate-limit wait | `resources/conditional-procedures.md` |
| `/run-status` | `resources/run-status.md` |
| `/run-halt`, `/run-resume` | `resources/halt-resume.md` |
| Bug Run Mode (`/run --bug`) | `resources/bug-run-mode.md` |
| Sprint Plan Execution Loop (`/run sprint-plan`) | `resources/sprint-plan-mode.md` |
| Completion and PR Creation's LOCAL/PROMPT/AUTO bodies | `resources/completion-modes.md` |

Each pointer avoids the budget script's imperative-verb charge trigger (`read|load|source|include`) and most also carry an explicit guard word (`if`/`when`/`see`). K-39 (`JACKED_OUT`) and K-40 (`verdict-derive`) both still occur verbatim in the retained `SKILL.md` body (Core Behavior diagram, Main Loop pseudocode, Issue Hash Tracking) — unaffected by the moves. Frontmatter (K-41/K-42) is copied byte-for-byte, untouched.

**Deliberately kept although a grep would flag it**: all numbered step lists (Pre-flight, Main Loop, Circuit Breaker trip, Sprint Discovery) — these are genuinely order-dependent state-machine/git procedures, not judgment-task choreography. The "Opus 4.7 + GPT-5.3-codex" cost-section mention — checked against `.claude/loa/reference/flatline-reference.md`, which cites the same models; left as a verified-current fact, not a stale pin. The frontmatter `description`'s calibrated routing language — protected as trigger text (Group 3 exception + K-42).

**Residual above target**: none expected; see the byte-count caveat above.

