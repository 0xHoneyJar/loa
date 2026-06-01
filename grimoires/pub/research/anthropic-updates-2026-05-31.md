# Anthropic Updates Analysis — Opus 4.8 Era

**Date**: 2026-05-31
**Oracle Run**: 2026-05-30T22:24:12Z (cache fetch) + live WebFetch verification
**Analyst**: Claude (Opus 4.8, via /oracle audit)
**Scope**: Claude Code 2.1.143 → 2.1.158, Opus 4.8 release, `effort` API parameter, native dynamic workflows
**Local harness at audit time**: Claude Code **2.1.158**, model **claude-opus-4-8**

---

## Executive Summary

- **Opus 4.8 shipped May 28 2026** (Claude Code 2.1.154; API id `claude-opus-4-8`). Pricing unchanged from 4.7 ($5/$25 per Mtok; fast mode $10/$50). Defaults to **high effort**; adds **`xhigh`** and **`max`** levels. **Loa's model registry does not contain it** — `.claude/defaults/model-config.yaml` tops out at `claude-opus-4-7` and the `opus` alias still resolves to 4-7. This is the single highest-value, lowest-effort upgrade.
- **The `effort` API parameter** (`output_config.effort`: low/medium/high/xhigh/max) is now the canonical way to control reasoning depth on Opus 4.5–4.8 and Sonnet 4.6. Loa's `claude -p` headless adapter already passes `--effort`, but the **Anthropic HTTP adapter cannot express it** — so Flatline/BB/audit cross-vendor runs on the API path can't run at `xhigh`.
- **`disallowed-tools` skill frontmatter** (2.1.152) is a *mechanical* tool-removal primitive. Loa currently enforces "NEVER write application code outside `/implement`" via **prose constraints only** (CLAUDE.loa.md + constraints.json C-PROC-001). `disallowed-tools` can convert that load-bearing rule into a harness-enforced barrier — a genuine quality-gate hardening.
- **Native dynamic workflows** (2.1.154, the `Workflow` tool) now orchestrate tens–hundreds of Claude subagents deterministically (pipeline/parallel/worktree-isolation/resume). This overlaps Loa's bespoke spiral/run/run-bridge bash orchestration — but **not** Loa's irreplaceable value: cross-vendor adversarial consensus (Opus+GPT+Gemini) and the implement→review→audit→flatline quality gates with circuit breakers.
- **New hook surfaces**: `MessageDisplay` event (2.1.152), SessionStart `reloadSkills`/`sessionTitle` returns (2.1.152), Stop/SubagentStop input now carries `background_tasks`/`session_crons` (2.1.145). Loa's Stop guard (`run-mode-stop-guard.sh`) is unaware of background tasks — a real orphaning risk now that autonomous runs can spawn background agents.
- **Safety**: Anthropic's 2.1.154 `rm -rf $HOME` trailing-slash fix maps to a **precision gap** in Loa's `block-destructive-bash.sh` (`$HOME/` falls to the AMBIGUOUS branch, not BLOCK — still exit-2, so blocked, but mislabeled). The env-var-prefix bypass class (2.1.145) is **already covered**. Loa has **no egress/exfiltration guard** (architectural gap, honestly out of the current hook's scope).

---

## New Features Identified

### Feature 1: Claude Opus 4.8 (`claude-opus-4-8`)

**Source**: https://www.anthropic.com/news/claude-opus-4-8 · Claude Code changelog 2.1.154 (May 28 2026)
**Relevance to Loa**: **HIGH**

**Description**: Upgrade to the Opus class. 84% on Online-Mind2Web (browser automation); highest Legal Agent Benchmark; **4× less likely than its predecessor to let code flaws pass unremarked** (directly relevant to Loa's review/audit/flatline mandate). Pricing identical to 4.7. Fast mode now 2× standard rate for 2.5× speed (3× cheaper than prior fast). Messages API now accepts **system entries mid-array** (mid-task instruction updates without breaking prompt cache).

**Potential Integration**: Add `claude-opus-4-8` to the model registry (all four maps + BB `config.generated.*`), retarget the `opus` alias, add the 4.7→4.8 backward-compat aliases (dash **and** dot form — recall the BB substrate alias gap, cycle-108), add the Bedrock inference profile. This makes 4.8 dispatchable for executor/advisor tiers and BB/flatline voices.

**Implementation Effort**: **Low** (registry edit + `gen-adapter-maps.sh` regenerate + drift gate). Must go through a normal cycle/PR — `validate_model_registry()` exits 2 on cross-map drift.

---

### Feature 2: The `effort` API parameter (output_config.effort)

**Source**: https://platform.claude.com/docs/en/build-with-claude/effort
**Relevance to Loa**: **HIGH**

**Description**: A single behavioral control over total token spend (text + tool calls + thinking). Levels: `low | medium | high(default) | xhigh | max`. Supported on Opus 4.8/4.7/4.6/4.5 and Sonnet 4.6. **Sent as `output_config: {effort: "..."}`** — *not* `thinking.budget_tokens`. On Opus 4.8 manual `thinking:{type:"enabled",budget_tokens:N}` is **rejected with a 400**; 4.8 uses adaptive thinking and effort is the depth control. Recommended start for coding/agentic/exploratory work: **`xhigh`** with a large `max_tokens` (≥64k). `max` reserved for frontier problems (overthinks structured output).

**Potential Integration**: (a) thread `effort` through the cheval Anthropic HTTP adapter via `output_config` (the CLI path already has `--effort`); (b) add an optional `effort` field to `CompletionRequest`; (c) let deep-reasoning skills declare `effort:` frontmatter (architect/red-team/audit/bridgebuilder → `high`/`xhigh`); (d) add an effort dimension to `tier_groups` / `workload_tier_map` and surface it in the MODELINV envelope so the Empirical Model Economy can report cost-per-clean-output *by effort*.

**Implementation Effort**: **Medium** (adapter + type + schema; correct the budget_tokens mis-mapping).

> **Correction to a tempting wrong path**: do **not** implement Anthropic effort as `thinking.budget_tokens` — that 400s on 4.8. Use `output_config.effort`.

---

### Feature 3: `disallowed-tools` skill/command frontmatter

**Source**: Claude Code changelog 2.1.152
**Relevance to Loa**: **HIGH** (quality-gate hardening)

**Description**: Skills and slash commands can set `disallowed-tools` in frontmatter to **remove** tools from the model while the skill is active — a hard, harness-level restriction that instructions cannot override.

**Potential Integration**: Loa enforces "NEVER write application code outside `/implement`" only via prose (`.claude/loa/CLAUDE.loa.md`; `constraints.json` C-PROC-001). Adding `disallowed-tools: [Write, Edit, NotebookEdit]` (plus dangerous `Bash(git push *)` etc.) to `role: review` skills (reviewing-code, auditing-security, red-teaming, bridgebuilder-review) makes the gate **mechanically unbypassable**. Planning skills that legitimately write artifacts (architect→SDD, sprint-plan→sprint.md) keep Write but can disallow application-code Bash. Pair with a `validate-skill-capabilities.sh` check.

**Implementation Effort**: **Low–Medium** (per-skill frontmatter + one validator rule + bats). Care needed for `spiraling` (role: review but dispatches writes via harness).

---

### Feature 4: Native dynamic workflows (the `Workflow` tool)

**Source**: Claude Code changelog 2.1.154; effort-doc "ultracode" note
**Relevance to Loa**: **MEDIUM** (strategic, not urgent)

**Description**: `Workflow` orchestrates tens–hundreds of background Claude subagents from a deterministic JS script (`agent()/parallel()/pipeline()`, structured-output schemas, per-agent worktree isolation, token budgets, resume-from-runId). `/workflows` shows runs. "ultracode" = `xhigh` + standing permission to launch workflows.

**Potential Integration**: This is a superior **dispatch engine** for the parts of Loa that are pure Claude fan-out — e.g. parallel sprint-task implementation, parallel per-file audits, the spiral/run-bridge iteration loops. It does **not** replace Loa's cross-vendor flatline consensus, circuit breakers, or MODELINV audit envelopes. Realistic near-term win: pilot the `Workflow` tool as the fan-out layer for **one** read-only, Claude-only stage (e.g. parallel audit-sprint file review) and measure, rather than a wholesale rewrite of the bash substrate.

**Implementation Effort**: **High** (and partly speculative). Recommend a scoped pilot + ADR, not a migration commitment.

---

### Feature 5: New hook surfaces

**Source**: Claude Code changelog 2.1.145 / 2.1.152
**Relevance to Loa**: **MEDIUM**

- **Stop/SubagentStop input now includes `background_tasks` + `session_crons`** (2.1.145). `run-mode-stop-guard.sh` checks only `.run/*-state.json`; it should soft-block (or warn) when background tasks are still live so autonomous runs don't orphan background agents. **High value / low effort.**
- **SessionStart can return `sessionTitle`** (2.1.152). Loa's post-compact / run-mode recovery could set a title like `LOA: [sprint-plan RUNNING] resume sprint-N`, improving recovery UX. **Medium value / low effort.**
- **`MessageDisplay` hook event** (2.1.152) could visually flag `<untrusted-content>` (L6/L7) or BLOCKER markers. **Lower priority.**
- **SessionStart `reloadSkills:true`** — low applicability (Loa skills are static).

**Implementation Effort**: Low for the first two.

---

## API Changes

| Change | Type | Impact on Loa | Action Required |
|--------|------|---------------|-----------------|
| `claude-opus-4-8` model id | New | Not in registry; `opus` alias stale at 4-7 | **Yes** — add + retarget + regenerate maps |
| `output_config.effort` (low…max) | New | CLI path supports `--effort`; HTTP adapter does not | **Yes** — wire through `anthropic_adapter.py` |
| Manual `thinking.budget_tokens` on Opus 4.8 | Removed (400 error) | Any future code that sets budget_tokens for 4.8 will 400 | Guard — use effort instead |
| System entries accepted mid-array | New | Could let flatline update reviewer instructions mid-turn without breaking cache | Optional |
| `effort` forced on non-supporting models | Behavior | `CLAUDE_CODE_ALWAYS_ENABLE_EFFORT` caused 400s (fixed harness-side 2.1.154) | Awareness only |
| Plugins auto-load from `.claude/skills` | New | Loa skills already auto-load; no marketplace dependency | No |

---

## Deprecations & Breaking Changes

- **`CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE`** removed 06/01/2026. Loa does not reference it (verified no occurrences). No action.
- **`thinking.budget_tokens`** deprecated on 4.6/Sonnet 4.6, **unsupported on 4.7/4.8**. Loa's `anthropic_adapter.py` only *reads back* thinking traces; it does not *send* budget_tokens, so no break today — but the effort-wiring work must not introduce it.
- No breaking change affects Loa's current registry (it simply lacks the new model).

---

## Best Practices to Adopt

1. **Set effort explicitly** for agentic/coding/review skills — start at `xhigh` for deep-reasoning skills, `medium` for cost-sensitive triage, `low` for high-volume subagents. Pair `xhigh` with `max_tokens ≥ 64k`.
2. **Prefer mechanical tool restriction** (`disallowed-tools`) over prose for load-bearing safety constraints.
3. **Treat native primitives as a dispatch engine, not a replacement for judgment** — Loa's differentiated value is convergence detection + cross-vendor consensus, which native workflows do not provide.

---

## Gaps Analysis (what Anthropic offers that Loa lacks)

| Area | Anthropic capability | Loa state | Gap |
|------|----------------------|-----------|-----|
| Model | Opus 4.8 + effort levels | Registry stops at 4.7 | **Missing model + alias** |
| Reasoning control | `output_config.effort` on API | Only CLI `--effort` | **HTTP adapter can't express effort** |
| Tool restriction | `disallowed-tools` (mechanical) | Prose NEVER-rules | **Quality gate is advisory, not enforced** |
| Orchestration | Native `Workflow` (deterministic fan-out) | Bespoke bash spiral/run/bridge | Overlap; selective adoption only |
| Stop safety | `background_tasks`/`session_crons` in hook input | Stop guard ignores them | **Orphaning risk in autonomous + bg runs** |
| Egress | Auto-mode exfiltration classifier | None | Architectural gap (out of current hook scope) |
| rm-path precision | `$HOME` trailing-slash recognized | Falls to AMBIGUOUS branch | Precision gap (still blocked) |

---

## Recommended Actions (prioritized)

| # | Action | Value | Effort | Suggested vehicle |
|---|--------|-------|--------|-------------------|
| 1 | Add `claude-opus-4-8` to `model-config.yaml` (4 maps + BB `config.generated.*` + Bedrock profile + dash/dot aliases), retarget `opus` alias, regenerate via `gen-adapter-maps.sh` | **High** | Low | `/bug` or small cycle |
| 2 | Wire `output_config.effort` through `anthropic_adapter.py` + add optional `effort` to `CompletionRequest`; **do not** use `thinking.budget_tokens` | High | Med | cycle sprint |
| 3 | Add `disallowed-tools: [Write, Edit, NotebookEdit]` to `role: review` skills + validator rule + bats; mechanically enforce C-PROC-001 | High | Low–Med | cycle sprint |
| 4 | Teach `run-mode-stop-guard.sh` to read `background_tasks`/`session_crons` and soft-block on live tasks | Med-High | Low | `/bug` |
| 5 | Add `effort:` frontmatter to deep-reasoning skills (architect/red-team/audit/bridgebuilder) once #2 lands | Med | Low | cycle sprint |
| 6 | Surface `effort` in MODELINV envelope + `workload_tier_map` so the Empirical Model Economy reports cost-per-clean-output by effort | Med | Med | Phase B economy |
| 7 | Tighten `block-destructive-bash.sh` BLOCK regex to recognize `$HOME/`, `${HOME}/`, `~/` explicitly; add bats cases | Low | Low | `/bug` |
| 8 | SessionStart `sessionTitle` on run-mode/post-compact recovery | Low-Med | Low | `/bug` |
| 9 | Scoped pilot: `Workflow` tool as fan-out engine for one Claude-only read-only stage (e.g. parallel audit file review) + ADR | Strategic | High | proposal/ADR |
| 10 | Document the egress/exfiltration non-guarantee in the Safety Hooks section | Low | Trivial | docs |

---

## Verification Notes (grounding)

- Registry absence: `grep 'opus-4-8' .claude/defaults/model-config.yaml` → none; latest is `claude-opus-4-7` (line 343); `opus` alias → 4-7 (line 578). Local `claude --version` → 2.1.158.
- Effort adapter gap: `anthropic_adapter.py` has thinking-trace *read* (lines 316–354) but no `effort`/`output_config` *send*; `claude_headless_adapter.py` passes `--effort` (line 293).
- rm-path: `block-destructive-bash.sh` BLOCK regex `^(/|\$HOME|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/)` — `$HOME/` matches neither alternation → AMBIGUOUS branch (both branches `emit_block`, exit 2).
- Effort mechanism: per platform.claude.com effort doc, Opus 4.8 uses `output_config.effort`; manual `thinking.budget_tokens` returns 400.

---

*Generated via `/oracle` audit. Sources cached at `~/.loa/cache/oracle/` (fetched 2026-05-30T22:24:12Z) and verified live against platform.claude.com / anthropic.com on 2026-05-31.*
