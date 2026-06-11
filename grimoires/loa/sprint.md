# Sprint Plan: Cycle-114 — Harness Modernization: Opus 4.8

> **Cycle**: cycle-114-harness-modernization-opus-4.8
> **PRD**: `grimoires/loa/prd.md` · **SDD**: `grimoires/loa/sdd.md`
> **Branch**: `feature/sprint-plan-cycle-114`
> **Sprints**: 3 (global 177, 178, 179) · **Beads**: `bd-c114-fr1` … `bd-c114-fr10`
> **Execution**: `/run sprint-plan` (autonomous, implement→review→audit→flatline per sprint, circuit breaker on)
> **Test-first**: every task writes failing tests before implementation (NFR-3).

---

## Global conventions (all sprints)

- **Zone**: System Zone writes are limited to the surfaces authorized in PRD §0.
- **Determinism**: generated model maps are written ONLY by `gen-adapter-maps.sh`.
- **Back-compat**: every new field is optional; absent → today's behavior (NFR-2).
- **Definition of Done (per task)**: failing test written first → implementation →
  test green → existing suites + drift gates still green → bead closed.
- **Definition of Done (per sprint)**: `/review-sprint` APPROVED + `/audit-sprint`
  approved (COMPLETED marker) + Flatline no unresolved BLOCKER.

---

## Sprint 1 (global 177) — Model Substrate

**Theme**: Make Opus 4.8 dispatchable and the `effort` control reachable on the API path.
**FRs**: FR-1, FR-2, FR-3 · **Scope**: LARGE

### T1.1 — FR-1: Opus 4.8 in the registry  ·  bead `bd-c114-fr1-nlrw`  ·  P1
- **Do**: add `claude-opus-4-8` to `.claude/defaults/model-config.yaml` (entry modeled
  on 4-7 @L343; pricing $5/$25, fast $10/$50; fallback → 4-7 → sonnet-4.6 → headless);
  retarget `opus` alias 4-7→4-8 (@L578); add dash **and** dot backward-compat aliases
  (+ BB self-map); add Bedrock `us.anthropic.claude-opus-4-8` profile; regenerate via
  `gen-adapter-maps.sh`.
- **Test-first**: bats asserting resolver resolves `opus`/`claude-opus-4-8`/`claude-opus-4.8`
  to a 4.8 entry; `validate_model_registry()` exit 0.
- **Accept**: all four bash maps + BB `config.generated.*` contain 4.8; drift gate green;
  no generated file hand-edited.

### T1.2 — FR-2: effort through the Anthropic HTTP adapter  ·  bead `bd-c114-fr2-xhf8`  ·  P1
- **Do**: add `effort: Optional[str]=None` to `CompletionRequest` (`types.py`); in
  `anthropic_adapter.py` serialize `output_config:{effort}` with `{low,medium,high,xhigh,max}`
  validation; precedence `request.effort` > `metadata["effort"]`. **Never** emit
  `thinking.budget_tokens` (400 on 4.7/4.8).
- **Test-first**: pytest — `xhigh` → `output_config.effort` set + no `thinking` block; `None`
  → baseline body; invalid → `ValueError`.
- **Accept**: NFR-4 (no thinking block) test green; NFR-2 (unset == baseline) green.

### T1.3 — FR-3: effort: frontmatter on deep-reasoning skills  ·  bead `bd-c114-fr3-yfjt`  ·  P2
- **Depends on**: T1.2.
- **Do**: add `effort:` to `designing-architecture`(high), `auditing-security`(high),
  `red-teaming`(xhigh), `bridgebuilder-review`(xhigh); extend
  `validate-skill-capabilities.sh` to accept the enum + WARN on `lightweight`+`xhigh`.
- **Test-first**: bats — bad enum → non-zero; good → zero; lightweight+xhigh → WARN.
- **Accept**: 4 skills carry valid `effort:`; validator handles the new key.

---

## Sprint 2 (global 178) — Gate & Safety Hardening

**Theme**: Convert a prose safety rule into a mechanical one; close hook gaps.
**FRs**: FR-4, FR-5, FR-6, FR-7 · **Scope**: LARGE

### T2.1 — FR-4: disallowed-tools on review skills + validator  ·  bead `bd-c114-fr4-g5zs`  ·  P1
- **Do**: add `disallowed-tools:[Write,Edit,NotebookEdit,Bash(git add *),Bash(git commit *),Bash(git push *)]`
  to `reviewing-code`, `auditing-security`, `red-teaming`, `bridgebuilder-review`;
  document exclusions (`designing-architecture`, `planning-sprints`, `spiraling`) in
  `skill-invariants.md`; add validator WARN rule with `REVIEW_WRITE_EXCEPTIONS` array.
- **Test-first**: bats — review skill cannot Write; misconfigured fixture → WARN; excepted
  skills don't WARN.
- **Accept**: C-PROC-001 mechanically enforced for review skills; exception list explicit.

### T2.2 — FR-5: stop-guard background_tasks/session_crons  ·  bead `bd-c114-fr5-ykvt`  ·  P1
- **Do**: parse `background_tasks`/`session_crons` from Stop input in
  `run-mode-stop-guard.sh`; soft-block (`decision:block`) on live `background_tasks` with
  `TaskStop` guidance; `session_crons` surfaced but non-blocking; fail-open on absent/bad input.
- **Test-first**: bats — non-empty bg_tasks → block; absent/malformed → exit 0.
- **Accept**: NFR-5 fail-open green; no orphaned-agent path on Stop.

### T2.3 — FR-6: block-destructive-bash $HOME/ precision  ·  bead `bd-c114-fr6-kkn0`  ·  P1
- **Do**: extend BLOCK alternation to recognize `$HOME/`, `${HOME}/`, `~/` (home-root +
  trailing slash) → FR-2-BLOCK; preserve `~/subdir`, `$HOME/child` → AMBIGUOUS.
- **Test-first**: bats — `$HOME/`,`${HOME}/`,`~/` → BLOCK; `~/subdir`,`$HOME/projects` →
  AMBIGUOUS; full existing suite unchanged.
- **Accept**: precision fix with zero regression to existing BLOCK/ALLOW cases.

### T2.4 — FR-7: egress non-guarantee doc  ·  bead `bd-c114-fr7-8eex`  ·  P2
- **Do**: add "Known Scope Boundaries" note to `hooks-reference.md` Safety section;
  cross-ref cycle-111 SDD §11. Documentation only.
- **Accept**: section present + cross-reference; no code change.

---

## Sprint 3 (global 179) — Economy, Recovery UX & ADR

**Theme**: Make effort observable; improve recovery UX; record the Workflow decision.
**FRs**: FR-8, FR-9, FR-10 · **Scope**: MEDIUM

### T3.1 — FR-8: effort in MODELINV + economy roll-up + tier_groups  ·  bead `bd-c114-fr8-6f18`  ·  P2
- **Do**: add optional `effort` enum to `model-invoke-complete.payload.schema.json`; emit it
  post-flight when present; extend `economy.py` roll-up group key to `(skill,model,effort)`;
  add optional informational `effort:` to `tier_groups` (non-binding — pin with a test).
- **Test-first**: schema validates record w/ & w/o effort; roll-up shows effort column;
  informational-only invariant pinned.
- **Accept**: economy reports cost-per-clean-output by effort; tier_groups effort non-binding.

### T3.2 — FR-9: SessionStart sessionTitle recovery  ·  bead `bd-c114-fr9-ln4t`  ·  P2
- **Do**: new `.claude/hooks/session-start/loa-run-mode-session-title.sh` returning
  `hookSpecificOutput.sessionTitle` from active `.run/*-state.json`; register in
  `settings.json`; no-op when jacked-out/absent.
- **Test-first**: bats — RUNNING sprint-plan → title; jacked-out/malformed → exit 0.
- **Accept**: NFR-5 fail-open; recovery title appears only when a run is active.

### T3.3 — FR-10: Native Workflow adoption ADR (doc only)  ·  bead `bd-c114-fr10-3ryo`  ·  P3
- **Do**: write `grimoires/loa/proposals/native-workflow-adoption.md` (context,
  where-it-fits, where-Loa-keeps-bespoke, scoped-pilot, go/no-go criteria, explicit
  "no code this cycle"). No `.claude/` changes.
- **Accept**: ADR exists with decision-criteria section + "no code" statement.

---

## Execution order & gates

1. **S1 → S2 → S3** sequentially (S1 unblocks FR-3's substrate; S2/S3 independent).
2. Within S1: **T1.1 ∥ T1.2**, then **T1.3** (after T1.2).
3. Each sprint: `/implement sprint-N` → `/review-sprint sprint-N` → `/audit-sprint sprint-N`.
   Autonomous via `/run sprint-plan`; do not pause at task boundaries (operator
   autonomous-run preference); halt only on circuit-breaker / hard blocker.
4. **MVP gate**: FR-1, FR-2, FR-4, FR-5, FR-6 must land green. FR-3/7/8/9 should land.
   FR-10 is doc-only.

> **Sources**: PRD FR-1…FR-10, SDD §2.1–§2.10; beads `bd-c114-fr1`…`bd-c114-fr10`;
> Sprint Ledger globals 177/178/179.
