# Context Engineering Reference

Pointer map for Loa's context/memory surfaces: what exists, where the detail lives, and what is actually wired. (cycle-121 rewrite — this file previously duplicated ~63% of its bytes from protocol files and taught pre-Claude-5 manual token accounting; the live mechanisms below replaced that.)

## What is wired (use these)

| Surface | Detail lives at | Status |
|---------|-----------------|--------|
| Tool-result clearing + NOTES.md synthesis | `context_discipline` blocks in each SKILL.md; `.claude/protocols/tool-result-clearing.md` | Active — the live context rule |
| Session recovery (tiered) | `.claude/protocols/session-continuity.md` | Active |
| Compaction survival | `pre-compact-marker.sh` (PreCompact) + `post-compact-reminder.sh` (UserPromptSubmit) — mechanical, zero thinking-budget | Active (hooks registered in settings.json) |
| Pre-clear validation | `.claude/protocols/synthesis-checkpoint.md` | Active |
| KF ledger surfacing | `loa-kf-surface.sh` (SessionStart) → generated `grimoires/loa/INDEX.md` → `known-failures.md` | Active — three-tier progressive disclosure |
| Cross-session memory | Claude Code auto-memory (harness-managed, per-user) + git-tracked team surfaces (KF ledger, GT files) + untracked per-operator NOTES.md (`.gitignore:293`) | Active |
| Context tooling scripts | `context-manager.sh`, `cache-manager.sh`, `condense.sh`, `early-exit.sh` — each script's `--help` | Available (low adoption) |

## What is NOT wired (do not rely on)

| Spec | Where it moved | Why |
|------|----------------|-----|
| Context-editing API-beta design (CONTEXT_NEAR_LIMIT signals) | `docs/integration/context-editing.md` | Unimplemented spec; only consumer is `docs/integration/runtime-contract.md` |
| Five-YAML memory schema | `docs/integration/memory-schema.md` | Never built; auto-memory owns the scope |
| Attention-budget zones, semantic decay timers, manual token estimation | deleted (cycle-121) | Old-model workarounds; contradicted live thresholds; zero KF evidence of the failure mode they guarded |

## Effort / extended thinking

Configured via `.loa.config.yaml` (see `.loa.config.yaml.example`); model tiers and budgets are governed by the multi-model substrate — see `.claude/loa/reference/multi-model-reference.md`. Do not hardcode model names from this file's history.

## Prompt caching (cycle-124 FR-4)

cheval marks the stable prefix as the single Anthropic `cache_control: ephemeral` breakpoint — the persona (`.claude/skills/<agent>/persona.md`) when the agent has one, with the per-call `--system` context sent after it; otherwise the whole `--system` payload (PRD FR-4). No code decides eligibility — the marker is always emitted and the returned counts (`usage.cache_read_input_tokens`, MODELINV `tokens_cache_read`) tell the truth. Reads bill at 0.1× input (Fable 5.1: 0.025×), writes at 1.25×; `LOA_CHEVAL_LEGACY_WIRE=1` removes the marker.

| Caller | Cacheable prefix | Min. cacheable prefix (reference, 2026-06-24) | Expected outcome |
|---|---|---|---|
| Flatline review/skeptic/scorer, adversarial dissent (agents with a persona.md) | persona.md (stable across calls of one agent) | 512 tokens on Opus 5 / Fable; 1024 on Opus 4.8 / Sonnet 5 / Sonnet 4.6 / Sonnet 4.5; 2048 on Opus 4.7; 4096 on Opus 4.6 / Haiku 4.5 | second and later calls within 5 min read the prefix (`cache_read > 0`); personas shorter than the minimum are never cached — the count stays 0, not an error |
| Bridgebuilder voices (`--agent reviewing-code`, no persona.md) | the whole `--system` file: `INJECTION_HARDENING` + `.claude/data/bridgebuilder-persona.md` (~9 KB, stable per voice) | same minimums | second and later calls of a voice read the prefix; the per-PR diff travels in the user turn and is never cached |
| Ad-hoc `cheval --prompt` with neither persona nor `--system` | none | — | no system block, no marker, no cache traffic |
| claude-headless (CLI) | Claude Code's own system prompt; persona rides in the prompt body | CLI-managed | counts come from the CLI's `usage` block; Loa does not add a marker |
| Non-Anthropic providers | n/a (marker ignored; single joined system string) | — | bodies byte-identical to pre-cycle-124 |
