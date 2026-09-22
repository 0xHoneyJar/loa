# Loa "Model-generation floor" cycle — orchestration prompt (issue to a fresh Fable 5.1 session)

You are Fable 5.1 acting as orchestrator and final quality gate for one planned Loa cycle: bring the framework's own use of Claude up to the current model generation. **Baseline assumption for every decision: Opus 5, Sonnet 5, Fable 5 or higher.** Multi-provider routing (OpenAI, Google, headless CLIs) is out of scope; do not touch it except where an item below requires removing a path that is wrong for Anthropic models.

The deliverable is **merged code through the framework's own gates**: `/plan` (PRD → SDD → sprint plan, Flatline on each) → `/run sprint-plan` → `/review-sprint` → `/audit-sprint` → one PR to `main` requesting review from @deep-name. Do not merge, close issues, or push to `main` yourself.

## 0. Ground yourself first (in this order)

1. `grimoires/loa/a2a/framework-review-2026-09-17.md` §9 (the eight items, their evidence and acceptance criteria) and §2 rec 2 / rec 6. This prompt implements §9.1's four sprints. Everything cited there was verified on `origin/main` 80be4b0f; re-verify against the `main` you branch from.
2. `grimoires/loa/known-failures.md` INDEX only (`grimoires/loa/INDEX.md` `## kf`). KF-002, KF-003, KF-004 (recurrence 28), KF-023 are the failure classes this cycle retires; read their Reading guides.
3. `grimoires/loa/REPO-MAP.md` before any grep of `.claude/`.
4. The `claude-api` skill (load it): `shared/model-migration.md` (Opus 4.7/4.8, Opus 5, Fable 5.1 sections and the migration checklists), `shared/prompt-audit.md` (all four pattern groups and the keep list), `shared/prompt-caching.md`, `shared/agent-design.md`. These are the authoritative API facts; the repo's own comments in `model-config.yaml` and `anthropic_adapter.py` are a generation behind them.
5. `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`, `.claude/adapters/cheval.py` (request construction around line 1400 and 1690), `.claude/defaults/model-config.yaml` (Anthropic entries lines 340-560, alias map lines 750-870), `.claude/adapters/tests/test_anthropic_*.py`.
6. `.loa.config.yaml` — note `hounfour.headless.mode: cli-only` and `advisor_strategy.tier_aliases`; the cycle changes tier aliases, not headless mode.

Environment facts: `agy` is not installed and the `gemini` CLI is tier-blocked (KF-018), so Flatline runs Opus + codex only; that is acceptable for this cycle. `ANTHROPIC_API_KEY` may be unset; the Opus voice then goes through `claude-headless` (`claude -p --model fable`). Start from `origin/main`, not from the local `feature/cycle-123-bug-burndown` branch (its work is superseded). `.run/sprint-plan-state.json` was set to HALTED on 2026-09-17; if the Stop hook still nags about RUNNING state, that is a §2 rec 3 finding, not an instruction to resume anything. The framework repo cannot Write/Edit `.claude/` without the bounded marker: create `.run/zone-guard-authorization.json` at cycle start with a reason and an `expires_at` inside the run, and delete it at cycle end.

## 1. Delegation contract

| Work | Who |
|---|---|
| Evidence reads, grep sweeps, catalog diffs against the API reference tables, counting prompt-cruft markers | `loa-scout` (Haiku) or Sonnet subagents |
| Implementation inside `/run` | the framework's own `/implement` (advisor tier) |
| Prompt audit of each SKILL.md (item 6) | one Sonnet subagent per skill producing the `prompt-audit` report + proposed diff; you re-verify every deletion against the keep list before it lands |
| Verdicts, acceptance-criteria judgement, effort re-baseline decisions, final PR text | you, inline |
| Honesty pass on the sprint reports | `just-say-no-to-process-porn-and-ceremony` on the finished reports |

A subagent's report is a lead. Every acceptance criterion below is closed by a test you ran or output you observed, cited in the sprint report's `## AC Verification` with `file:line`.

## 2. Sprints

Register the cycle in `grimoires/loa/ledger.json` at kickoff (cycles 117–123 were never registered; do not repeat that). Failing-repro test first on every task.

### Sprint 1 (P0) — adapter floor, four `/bug` micro-sprints + two gate fixes
- **T1.1 adaptive thinking** — `anthropic_adapter.py` emits `thinking: {type: "adaptive"}` for Opus 4.6+, Sonnet 4.6+, Opus 5; omits the parameter for Fable 5/5.1 (explicit `disabled` is a 400 there); never emits `budget_tokens`. Observed failure: no `thinking` key is emitted anywhere today, so Opus 4.8 HTTP reviews run thinking-off. AC: per-model-family request-body test; one live Opus 5 call returns `thinking` blocks.
- **T1.2 max_tokens defaults** — `cheval.py:1406` `or 4096` → 16,000 non-streaming, 64,000 streaming, and ≥64,000 when `effort` is `xhigh` or `max`; one defaults table. AC: test that `--effort xhigh` without `--max-tokens` yields ≥64,000; KF-002 layer-3 input gate re-baselined and documented.
- **T1.3 catalog** — add `claude-opus-5` and `claude-fable-5-1`; set `context_window: 1000000`, `max_output_tokens: 128000` on Opus 4.6+/Sonnet 4.6+/5/Fable; remove `max_input_tokens: 180000`, `legacy_max_input_tokens`, and the Anthropic-voice diff-truncation path; `opus` → `claude-opus-5`, `fable` → `claude-fable-5-1`, advisor tier `claude-opus-5`, executor `claude-sonnet-5`; regenerate `generated-model-maps.sh`. AC: catalog parity tests green; `cheval --dry-run` resolves the aliases; no truncation branch is exercised for Anthropic voices in the integration suite.
- **T1.4 prompt caching** — `cache_control: {type: "ephemeral"}` on the system/persona block (and tools when present); volatile content after the last breakpoint; MODELINV records `cache_read_input_tokens`. AC: second of two identical Flatline calls shows `cache_read_input_tokens > 0`.
- **T1.5 (rec 2)** — `golden-path.sh` `_gp_sprint_is_reviewed/_is_audited` require `verdict-derive` exit 0 and `consistent == true`; `run-mode` uses `verdict-derive.sh` instead of `md5sum` over prose. Fixture: `All good` + trailer `{APPROVED, critical:1}` must not count as reviewed.
- **T1.6 (rec 6)** — `--mock-fixture-dir` and e2e tests write ledgers/envelopes to a temp dir; tripwire that `.run/cost-ledger.jsonl` and `.run/model-invoke.jsonl` contain no `mock-*` models or `/tmp/cheval-e2e-*` paths.

### Sprint 2 (P0) — structured outputs
- Convert Flatline findings, adversarial-review, the scorer, and the verdict envelope to `output_config.format` (or `strict: true` tools where a tool call is the natural shape). Remove `_transform_tool_choice` forced modes (`any`/`tool` are a 400 on Fable 5.1); only `auto`/`none` may be emitted. Delete `validate_finding`'s prose-parsing fallback and the "repair loop". AC: KF-004 and KF-023 fixtures pass as schema-enforced responses; the rejection sidecar records zero rejections over the fixture corpus; `tools/check-no-swallowed-jq.sh` still green.

### Sprint 3 (P1) — prompt audit and review recall
- Run `/claude-api prompt-audit` (target Fable 5.1) over `.claude/skills/*/SKILL.md`, `.claude/loa/CLAUDE.loa.md`, `.claude/protocols/*.md`, the Flatline/Bridgebuilder personas. Remove: history narratives (cycle/PR/KF numbers inside rule text; a footer "provenance" block is allowed), MUST/NEVER/ALWAYS where a hook or validator already enforces the rule (keep the rule text plain with its reason where nothing enforces it), step choreography for judgment tasks, generic virtues, and the per-prompt reminder re-insertion (`post-compact-reminder.sh`, `post-session-limit-reminder.sh` become one-shot or are folded into the SessionStart surface). Keep: the one-way verdict rule, the fences, the zone model, anything the keep list protects.
- Budgets: each SKILL.md ≤ 16 KB (today four are ~32 KB), `CLAUDE.loa.md` ≤ 10 KB (today 22 KB), protocols total ≤ 140 KB (today 280 KB).
- Review prompts (reviewing-code, auditing-security, Flatline reviewer/skeptic personas): coverage first — "report every finding with confidence and severity; a separate step filters" — with `verdict-derive.sh` as the filter. Effort defaults: `xhigh` for implement and review; audit becomes a structured, lower-effort call whose verdict is derived mechanically.
- Gate: the July skill-loop parity harness (`grimoires/loa/perf/skill-loop-2026-07-05/`) green, plus an `eval-running` A/B on the review and implement skills over a 10-PR fixture set with known defects; recall ≥ baseline, audit cost per sprint ≤ 50% of baseline with rejection rate unchanged or higher.

### Sprint 4 (P1) — memory and context
- `NOTES.md` size gate: warn at 100 KB, refuse append and require `/compound` or archive rotation at 200 KB; default read is Decision Log + Blockers + last session, full read on request; document the rotation in `context-engineering.md`. Write a one-page decision on the API memory tool vs NOTES.md for cross-session facts (decision, not rewrite). AC: session-start context on a 750 KB NOTES fixture ≤ 20k tokens; rotation script tested.

## 3. Rules
- Karpathy principles apply: smallest correct diff, failing test first, no new abstractions or config surfaces beyond the ones named.
- Do not weaken any fence (`block-destructive-bash.sh`, `zone-write-guard.sh`, `implement-gate.sh`, audit-envelope fail-closed paths). Sprint 3 may shorten their *documentation*, not their patterns.
- Regenerate `grimoires/loa/REPO-MAP.md` after every `.claude/` change (CI blocks on the checksum).
- Record any new failure class with `kf-write-lib.sh new` and recurrences with `kf-write-lib.sh recur`; sandbox tests with `--file <copy>`.
- Severity words only with a concrete failure scenario next to them; every AC row cites `file:line` or an observed output.

## 4. Stop conditions
Stop when all four sprints have COMPLETED markers with consistent LOA-VERDICT trailers, the PR is open against `main` with @deep-name requested, `framework-review-2026-09-17.md` §9 has a status column filled in, and the zone-guard marker is deleted — or when you hit a blocker only the operator can resolve (say exactly what: e.g. no Anthropic credential path for the live-call ACs). Do not stop to ask permission for reads, subagent dispatch, tests, or live probe calls under $5.
