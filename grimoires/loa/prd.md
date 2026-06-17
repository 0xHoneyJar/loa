# Cycle-114 PRD — Harness Modernization: Opus 4.8

> **Version**: 1.0
> **Cycle**: cycle-114-harness-modernization-opus-4.8
> **Status**: Draft (awaiting operator sign-off)
> **Source of requirements**: `grimoires/pub/research/anthropic-updates-2026-05-31.md` (the `/oracle` audit; requirements already discovered + code-grounded there — no fresh interview conducted, per operator direction)
> **Branch**: `feature/sprint-plan-cycle-114`

---

## 0. System Zone Authorization (REQUIRED — read first)

Every change in this cycle modifies the Loa framework itself under `.claude/`
(the **System Zone**), plus framework state/docs. In this repository the
framework *is* the product, and `.claude/` rules (`zone-system.md`) permit
System Zone writes when **explicitly authorized at cycle level in the PRD**.

**This PRD authorizes the following System Zone write surfaces for cycle-114, and no others:**

| Path | Why |
|------|-----|
| `.claude/defaults/model-config.yaml` | Add Opus 4.8 model entry + aliases + Bedrock profile (FR-1) |
| `.claude/scripts/generated-model-maps.sh` + `gen-adapter-maps.sh` outputs | Regenerated maps after FR-1 (never hand-edited) |
| `.claude/skills/bridgebuilder-review/resources/config.generated.*` | Regenerated BB registry after FR-1 |
| `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`, `types.py` | Thread `output_config.effort` (FR-2) |
| `.claude/skills/{designing-architecture,red-teaming,auditing-security,bridgebuilder-review,reviewing-code,...}/SKILL.md` | `effort:` + `disallowed-tools:` frontmatter (FR-3, FR-4) |
| `.claude/scripts/validate-skill-capabilities.sh` | New validation rule for FR-4 |
| `.claude/hooks/safety/run-mode-stop-guard.sh` | `background_tasks`/`session_crons` awareness (FR-5) |
| `.claude/hooks/safety/block-destructive-bash.sh` | `$HOME/` regex precision (FR-6) |
| `.claude/data/trajectory-schemas/model-events/*.schema.json` | `effort` field in MODELINV envelope (FR-8) |
| `.claude/hooks/session-start/` (new hook) | `sessionTitle` recovery (FR-9) |
| `.claude/loa/reference/hooks-reference.md` + Safety section docs | Egress non-guarantee (FR-7) |
| `grimoires/loa/**`, `tests/**`, `.github/workflows/**` | State Zone + tests + CI (normal) |

**Out of scope / explicitly forbidden this cycle:** any `.claude/` path not
listed above; any orchestration-engine migration (FR-10 is documentation only);
reconciling cycle-112's stale ledger status (separate pre-existing drift).

---

## 1. Problem Statement

The local Claude Code harness is already at **2.1.158 running Opus 4.8**, but the
Loa framework that rides on top of it was last calibrated for the Opus 4.7 era.
The `/oracle` audit (2026-05-31) found, with verified `file:line` grounding,
that the framework lags the harness in five concrete ways:

1. **The model registry has no Opus 4.8.** `.claude/defaults/model-config.yaml`
   tops out at `claude-opus-4-7` (L343) and the `opus` alias still resolves to
   4-7 (L578). The framework cannot dispatch the model the operator is already
   running.
2. **The `effort` reasoning-depth control is unreachable on the API path.**
   `claude_headless_adapter.py` passes `--effort` (L293), but
   `anthropic_adapter.py` only *reads back* thinking traces (L316–354) — it
   cannot *send* `output_config.effort`. So Flatline / Bridgebuilder / audit
   runs that dispatch via the HTTP API cannot run at `xhigh`.
3. **A load-bearing safety rule is advisory, not enforced.** "NEVER write
   application code outside `/implement`" (C-PROC-001) is enforced only by prose
   in `CLAUDE.loa.md` + `constraints.json`. Claude Code 2.1.152 shipped
   `disallowed-tools` frontmatter — a *mechanical* enforcement primitive Loa
   does not yet use.
4. **New Stop-hook signals are ignored.** Claude Code 2.1.145 added
   `background_tasks` / `session_crons` to Stop/SubagentStop input.
   `run-mode-stop-guard.sh` checks only `.run/*-state.json`, so autonomous runs
   can now orphan background agents.
5. **A destructive-command guard has a precision gap.** `block-destructive-bash.sh`
   recognizes `~/` and `/home/` but not `$HOME/` (trailing slash) in its BLOCK
   alternation; `rm -rf $HOME/` falls to the AMBIGUOUS branch — still exit-2
   blocked, but mislabeled. Anthropic fixed the analogous class in 2.1.154.

Secondary: the Empirical Model Economy roll-up cannot report cost-per-clean-output
*by effort level* (no `effort` in the MODELINV envelope), and post-compact
recovery UX could use the new SessionStart `sessionTitle` return.

> **Source**: `grimoires/pub/research/anthropic-updates-2026-05-31.md` — Executive
> Summary + Gaps Analysis + Verification Notes.

## 2. Goals & Success Metrics

| Goal | Success metric (verifiable) |
|------|------------------------------|
| Opus 4.8 dispatchable | `model-resolver` resolves `opus` and `claude-opus-4-8`/`claude-opus-4.8` to a valid 4.8 entry; `validate_model_registry()` exits 0; all four maps + BB `config.generated.*` contain 4.8; drift gate green |
| Effort expressible on API | A cheval HTTP-adapter request with `effort="xhigh"` serializes `output_config.effort` and omits any `thinking.budget_tokens`; unit test asserts both |
| Gate enforced mechanically | `role: review` skills carry `disallowed-tools:[Write,Edit,NotebookEdit]`; validator fails a deliberately mis-configured fixture; bats green |
| No orphaned background agents | `run-mode-stop-guard.sh` soft-blocks (decision=block) when Stop input carries a non-empty `background_tasks`; bats with mocked input green |
| rm precision | `rm -rf $HOME/`, `${HOME}/`, `~/` hit FR-2-BLOCK (not AMBIGUOUS); `rm -rf ~/subdir` stays AMBIGUOUS; bats green |
| Economy effort-aware | MODELINV envelope schema accepts optional `effort`; economy roll-up groups by effort; schema-validation test green |
| Recovery UX | A SessionStart hook returns `hookSpecificOutput.sessionTitle` reflecting active run-mode state; bats green |
| Zero regressions | Existing bats + pytest + drift gates remain green; no model-registry inconsistency |

## 3. Users & Stakeholders

- **Primary**: Loa operators (e.g. @janitooor) running autonomous `/run`,
  `/run-bridge`, `/spiral`, Flatline, and Bridgebuilder against the framework.
- **Secondary**: Loa agents themselves (the review/audit/planning skills whose
  tool access FR-4 hardens; the Stop guard FR-5 protects).
- **Downstream**: operators of repos that consume Loa via `/update-loa`.

> Persona priority: the **autonomous-run operator** is primary — every FR is
> framed around making autonomous cycles safer (FR-4/5/6), cheaper-per-quality
> (FR-2/3/8), and current (FR-1).

## 4. Functional Requirements

Each FR maps to one audit action (audit "Recommended Actions" table #) and one sprint.

### Sprint S1 — Model Substrate

**FR-1 (audit #1) — Add Opus 4.8 to the model registry.**
Add `claude-opus-4-8` to `.claude/defaults/model-config.yaml`: model entry
(capabilities, context window, `max_tokens` token param, pricing $5/$25 per Mtok,
fast-mode $10/$50, fallback chain → 4.7 → sonnet-4.6 → headless); retarget the
`opus` alias from 4-7 → 4-8; add backward-compat aliases in **both** dash
(`claude-opus-4-8`) and dot (`claude-opus-4.8`) form (per the cycle-108 BB
substrate alias-gap learning); add the Bedrock `us.anthropic.claude-opus-4-8`
inference profile. Regenerate all four maps via `gen-adapter-maps.sh` and the BB
`config.generated.*`. **Acceptance**: `validate_model_registry()` exits 0;
resolver resolves all three alias forms; drift gate green; no map left without 4.8.

**FR-2 (audit #2) — Thread `effort` through the Anthropic HTTP adapter.**
Add an optional `effort: Optional[str]` field to `CompletionRequest`
(`loa_cheval/types.py`) and serialize it as `output_config: {effort: <value>}`
in `anthropic_adapter.py`. **CRITICAL**: use `output_config.effort`, NOT
`thinking.budget_tokens` — Opus 4.8 rejects manual `budget_tokens` with HTTP 400
(verified against platform.claude.com effort doc). Validate the level against
`{low,medium,high,xhigh,max}`; omit the field entirely when unset (preserve
current default-high behavior). **Acceptance**: unit test proves `effort="xhigh"`
→ body contains `output_config.effort=="xhigh"` and contains no `thinking` block;
unset → body unchanged from today.

**FR-3 (audit #5) — Declare `effort:` on deep-reasoning skills.**
After FR-2 lands, add `effort:` frontmatter to the deep-reasoning skills:
`designing-architecture` → `high`, `auditing-security` → `high`,
`red-teaming` → `xhigh`, `bridgebuilder-review` → `xhigh`. **Acceptance**:
frontmatter present + valid; `validate-skill-capabilities.sh` accepts the
`effort` enum and warns on `cost-profile: lightweight` + `effort: xhigh`.

### Sprint S2 — Gate & Safety Hardening

**FR-4 (audit #3) — Mechanically enforce C-PROC-001 via `disallowed-tools`.**
Add `disallowed-tools: [Write, Edit, NotebookEdit]` (plus
`Bash(git push *)`, `Bash(git commit *)`, `Bash(git add *)`) to `role: review`
skills (`reviewing-code`, `auditing-security`, `red-teaming`,
`bridgebuilder-review`). Skills that legitimately author artifacts
(`designing-architecture`→SDD, `planning-sprints`→sprint.md) are **excluded** —
they keep Write but may disallow application-code Bash. `spiraling` (role:review
but dispatches writes via harness) is **excluded** and documented as an
exception. Add a `validate-skill-capabilities.sh` rule: if `role: review` and
`capabilities.write_files: true` and no `disallowed-tools` Write entry → WARN.
**Acceptance**: bats proves a review skill cannot Write; validator flags a
deliberately mis-configured fixture; exception list documented.

**FR-5 (audit #4) — Stop-guard `background_tasks`/`session_crons` awareness.**
Teach `run-mode-stop-guard.sh` to parse the new `background_tasks` and
`session_crons` arrays from Stop/SubagentStop hook input and soft-block
(`{"decision":"block","reason":...}`) when tasks are still live, with guidance to
`TaskStop <id>` or force-stop. Graceful no-op when fields are absent (back-compat).
**Acceptance**: bats with mocked Stop input (non-empty `background_tasks`) →
decision=block; absent → exit 0.

**FR-6 (audit #7) — `block-destructive-bash.sh` `$HOME/` precision.**
Extend the BLOCK alternation to recognize `$HOME/`, `${HOME}/`, and `~/`
(currently `$HOME` matches only exact, `~/` already partial) so they hit
FR-2-BLOCK with the correct catastrophic-path message instead of AMBIGUOUS.
Preserve `rm -rf ~/subdir` → AMBIGUOUS (not a catastrophic collapse).
**Acceptance**: bats cases for `$HOME/`, `${HOME}/`, `~/` → BLOCK; `~/subdir` →
AMBIGUOUS; existing cases unchanged.

**FR-7 (audit #10) — Document the egress/exfiltration non-guarantee.**
Add a "Known Scope Boundaries" note to the Safety Hooks documentation
(`.claude/loa/reference/hooks-reference.md` and/or the CLAUDE.md Safety section
context): the destructive-bash hook + `settings.deny.json` defend filesystem and
credential-read surfaces but do **not** monitor network egress / bulk data
exfiltration; that is operator responsibility (network policy external to Claude
Code). **Acceptance**: doc note present + cross-references cycle-111 SDD §11
accepted-bypass list. (Documentation-only; no code.)

### Sprint S3 — Economy, Recovery UX & ADR

**FR-8 (audit #6) — Effort dimension in MODELINV + `workload_tier_map`.**
Add an optional `effort` field to the MODELINV envelope schema
(`model-invoke-complete.payload.schema.json`) and have the economy roll-up group
cost-per-clean-output by `(skill × model × effort)`. Add an optional `effort`
key to `tier_groups`/`workload_tier_map` entries (informational only this cycle,
mirroring the Phase-A invariant that `workload_tier_map` is non-binding).
**Acceptance**: schema accepts/omits `effort`; roll-up test shows an effort
column; the informational-only invariant has a pinning test.

**FR-9 (audit #8) — SessionStart `sessionTitle` recovery.**
Add a SessionStart hook returning `{"hookSpecificOutput":{"sessionTitle":...}}`
that reflects active run-mode state (e.g. `LOA: [sprint-plan RUNNING] resume
sprint-N`) by reading `.run/*-state.json`. No-op when no active run.
**Acceptance**: bats with a RUNNING `.run/sprint-plan-state.json` → emits a
sessionTitle; with none → no title / exit 0.

**FR-10 (audit #9) — Native Workflow adoption ADR (DOCUMENTATION ONLY).**
Produce an ADR / proposal at `grimoires/loa/proposals/native-workflow-adoption.md`
documenting: where the native `Workflow` tool could serve as a dispatch engine
for Claude-only fan-out (parallel sprint-task impl, parallel audit file review,
spiral/run-bridge loops); where Loa must keep its bespoke substrate (cross-vendor
flatline consensus, circuit breakers, MODELINV audit); a scoped pilot design; and
go/no-go decision criteria. **No orchestration code.** **Acceptance**: ADR exists
with a decision-criteria section and an explicit "no code this cycle" statement.

## 5. Technical & Non-Functional Requirements

- **NFR-1 (Determinism / drift)**: generated maps are never hand-edited;
  `gen-adapter-maps.sh` is the only writer; the drift CI gate must pass.
- **NFR-2 (Back-compat)**: every new field (`effort`, schema `effort`,
  `disallowed-tools`) is optional; absence reproduces today's behavior exactly.
- **NFR-3 (Test-first)**: each FR lands with failing-first tests (bats/pytest)
  that assert the new behavior, per Karpathy goal-driven execution.
- **NFR-4 (No 400-regression)**: FR-2 must never emit `thinking.budget_tokens`
  for 4.7/4.8 (adaptive-thinking models); a test asserts its absence.
- **NFR-5 (Hook fail-open)**: FR-5/FR-9 hooks must not break sessions on
  malformed/absent input (exit 0 / no-op).
- **NFR-6 (Zone discipline)**: only the surfaces in §0 are touched.

## 6. Scope & Prioritization

- **MVP (must land)**: FR-1, FR-2, FR-4, FR-5, FR-6 (the five gaps the audit
  rated High value or safety-relevant).
- **Should land**: FR-3, FR-7, FR-8, FR-9.
- **Doc-only**: FR-10 (ADR).
- **Explicitly out of scope**: native-Workflow migration code; effort as a
  *binding* tier control (informational only this cycle); cycle-112 ledger
  reconciliation; any egress-guard implementation (FR-7 documents the gap, does
  not close it).

## 7. Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Model-registry edit causes cross-map drift → `validate_model_registry()` exit 2 | Edit YAML source only, regenerate via `gen-adapter-maps.sh`, run drift gate before commit (the audit & memory both flag this fragility) |
| FR-2 mis-implemented as `budget_tokens` → 400 on 4.8 | NFR-4 test asserts absence of `thinking` block; PRD §0 + FR-2 call it out explicitly |
| FR-4 `disallowed-tools` over-restricts a skill that legitimately writes | Explicit exclusion list (architect/sprint-plan/spiraling); validator WARN not ERROR for ambiguous cases |
| FR-3 effort frontmatter unsupported by installed Claude Code | Local harness is 2.1.158 (supports it); field is inert on older versions |
| Dispatching at `xhigh` raises token cost | Effort is opt-in per skill; FR-8 makes the cost observable |
| Flatline/BB (multi-model) may be degraded (KF-002/003 cross-model fatigue) during review gates | Known-failures protocol; voice-drop; do not block on transient cross-model degradation |

## 8. Sprint Mapping

| Sprint | Local | Global | FRs | Theme |
|--------|-------|--------|-----|-------|
| S1 | sprint-1 | 177 | FR-1, FR-2, FR-3 | Model substrate (Opus 4.8 + effort) |
| S2 | sprint-2 | 178 | FR-4, FR-5, FR-6, FR-7 | Gate & safety hardening |
| S3 | sprint-3 | 179 | FR-8, FR-9, FR-10 | Economy, recovery UX & ADR |

> **Sources**: `grimoires/pub/research/anthropic-updates-2026-05-31.md`
> (Recommended Actions #1–#10, Verification Notes); operator scope decisions
> (2026-06-01): #9 → ADR-only, one cycle full-gates, approve-plan-then-autonomous.

---

## 4b. Functional Requirements — Sprint S4 (Cost Telemetry & Tiering)

> Added 2026-06-17. Continuation of cycle-114's economy/MODELINV theme (FR-8),
> grounded in the merged research `grimoires/loa/proposals/cost-telemetry-scope.md`
> and `grimoires/loa/proposals/anthropic-advances-oracle-2026-06-17.md` (§3a/§5).
> Scope discipline: **observability + cost-routing only** — NO memoization, NO
> `cache_control` writes (that is the separate bd-w7bh caching cycle), NO change
> to *what* re-runs. All new fields optional (NFR-2 back-compat).

### Sprint S4 — Cost Telemetry & Tiering

**FR-11 (bd-kyn5) — Per-iteration cost telemetry.**
loa records `cost_micro_usd`/`tokens_*` per MODELINV invocation and rolls up
per-(skill, model) in `economy.py`, but carries **no iteration dimension**, so
it cannot answer "is a bridge/audit loop's cost O(depth) or sub-linear?" — the
central question of the linear-nonlinear cost research (risk R3). Add optional
`loop_context` (enum `bridge|audit|e2e|spiral`, or absent) + `loop_iteration`
(int ≥1) to the MODELINV envelope, threaded from the orchestrators that already
track an iteration; add a per-(`loop_context`,`loop_iteration`) roll-up + a
cost-delta-per-iteration series to `economy.py`; add a `--by-iteration` view to
`cost-report.sh`. Absent fields ⇒ today's behavior byte-for-byte.

**FR-12 (oracle C2) — Cache-token telemetry.**
The `Usage` dataclass + the Anthropic streaming parser + `economy.py` do not
capture `cache_read_input_tokens` / `cache_creation_input_tokens` (the
bedrock/headless adapters already read them). Surface them end-to-end so a
future prompt-caching cycle (bd-w7bh) is **provable** (`cache_read>0` on
reuse). **Surfacing only — no `cache_control` writes in this sprint.**

**FR-13 (oracle C5) — Cheap-tier binding for cheap subtasks.**
`flatline-scorer` runs on the expensive `reviewer` tier and the `tiny`/Haiku
tier has zero bindings. Bind mechanical subtasks (severity/convergence scoring,
triage/classification) to the cheap/tiny tier, reserving Opus-class budget for
the adversarial voices where dissent is the load-bearing quality signal. Voice
dispatch for CRITICAL/BLOCKER review is **unchanged** (that redundancy is the
quality mechanism, per the cost research §6).

**FR-14 (oracle C6) — Wire the budget DOWNGRADE (decision: WIRE, not delete).**
`retry.py` logs "Budget downgrade triggered — continuing with current model" and
never invokes `walk_downgrade_chain`, while `model-config.yaml` advertises
`downgrade: reviewer: [cheap]` / `on_exceeded: downgrade`. **Decision: wire the
DOWNGRADE path to actually invoke `walk_downgrade_chain`** (rather than delete the
config) — cost-aware downgrade is a genuine lever that FR-13 makes first-class,
and wiring makes behavior match the documented config. Fail-open: if no downgrade
target resolves, keep current behavior (log + proceed), never error.

| Sprint | Local | Global | FRs | Theme |
|--------|-------|--------|-----|-------|
| S4 | sprint-4 | 180 | FR-11, FR-12, FR-13, FR-14 | Cost telemetry & tiering |

> **Sources (S4)**: `grimoires/loa/proposals/cost-telemetry-scope.md`;
> `grimoires/loa/proposals/anthropic-advances-oracle-2026-06-17.md` §3a/§5
> (C2/C5/C6) + §4 (NOT memoizing verdicts); beads bd-kyn5/bd-w7bh.
