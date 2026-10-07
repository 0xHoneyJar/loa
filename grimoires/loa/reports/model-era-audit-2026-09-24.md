# Model-era audit — where Loa still caps or under-uses the current Claude generation (2026-09-24)

**Question asked by the maintainer:** "is there any other work which we can do which works to improve loa as a framework and ensure it does not impede or get in the way of the modern latest claude / anthropic models? … code etc rather than project infra."

**Method.** Three inputs, all measured on `main` `2079e719` (`v2.0.0-rc.2` + the cycle-125 follow-ups): (1) a read-only code survey of `.claude/` for generation-era assumptions (an Explore agent, 72 tool calls; every finding below that carries a `file:line` was re-verified by hand by the lead); (2) a documentation inventory of current Claude Code and Claude API features (a claude-code-guide agent over the official docs); (3) direct measurements on this repository: the 12 cross-model dissents of the last 24 hours, prompt budgets, hook-chain latency, permission-list size. Nothing here is a guess about model behaviour; each item is a constant, a code path or a measurement.

## 1. Direct caps on the current models (verified)

| # | Where | What it assumes | Effect on Opus 5 / Sonnet 5 / Fable 5.1 |
|---|---|---|---|
| C1 | `.claude/defaults/model-config.yaml:376` (and the same literal on every Anthropic HTTP entry), enforced by `.claude/adapters/cheval.py` (`effective_input_ceiling` → exit 7) | `effective_input_ceiling: 180000`, "streaming-probed KF-002 ceiling (cycle-102 Sprint 4A)", `ceiling_calibration.calibrated_at: null` | Models declared at `context_window: 1000000` are refused above 180K input — about 82 % of their context is unreachable through cheval. Never re-probed. |
| C2 | `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:262,559` | `anthropic-version: 2023-06-01`, no `anthropic-beta` header anywhere | The wire never opts into any long-context handling the provider gates behind a header. |
| C3 | `.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:20-34` (codegen constant, header `:6-9`), fallback `truncation.ts:662-670` | `maxOutput: 8192` for every Anthropic id incl. `claude-opus-5`, `claude-fable-5-1`; `maxInput: 160000` | Bridgebuilder reviews on 128K-output models run at 1/16 of the output budget; the table is not read from the catalog. |
| C4 | `.claude/skills/bridgebuilder-review/resources/config.ts:168`, `SKILL.md:98`, personas `security.md:2`, `quick.md:2` | built-in default `model: "claude-opus-4-7"`; persona-pinned ids | Every Bridgebuilder run without `BRIDGEBUILDER_MODEL` uses a two-generations-old model. |
| C5 | `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts:52-71` | `isReasoningClass`: Anthropic matches only `/opus/i` | Fable 5.1 and Sonnet 5 (thinking-on) get the 120–300 s timeout ladder instead of the 30-minute reasoning budget — timeout-classified failures on the top tier. |
| C6 | `.claude/scripts/flatline-orchestrator.sh:127-128` | `FLATLINE_REVIEW_MAX_TOKENS=16000`, `FLATLINE_SCORE_MAX_TOKENS=16000`, thinking shares the budget | Flatline voices on 128K-output models are capped at 16K including thinking. |
| C7 | `.claude/adapters/loa_cheval/providers/base.py:163-186`, `types.py:18-19` | `_LEGACY_DEFAULT_MAX_TOKENS = 4096` for every non-Anthropic provider and any entry without `max_output_tokens`; dataclass defaults `temperature 0.7`, `max_tokens 4096`; `_nonstreaming_read_timeout` lengthens only when `max_tokens > 4096` | Long-form output through a non-Anthropic hop truncates at 4K; the stale `0.7` is dropped with a warning on every thinking model (noise on the dominant path). |
| C8 | `.claude/adapters/loa_cheval/providers/base.py:837-861`, `.claude/scripts/lib-multipass.sh:105` | `estimate_tokens` uses `cl100k_base` (an OpenAI encoding) or `len/3.5`, and feeds `enforce_context_window()` | A mis-estimate becomes a hard pre-flight rejection for Anthropic requests. |
| C9 | `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:562` | health probe pings `claude-3-haiku-20240307`; docstring says "Anthropic doesn't have a models endpoint" | A retired probe id trips the circuit breaker on a healthy provider. |

## 2. Cross-model review runs on one voice and drops findings (measured)

- All 12 dissents run in the last 24 hours (cycle-125 sprints 241–244 review+audit, sprint-bug-245/246 review+audit rounds) report `voices_planned: 1`, `voices_succeeded_ids: ["codex-headless"]`, `schema_enforced: false`. The configured chain (`.loa.config.yaml` `flatline_protocol.models`: `primary: opus` over the API, `secondary: gpt-5.5`, no tertiary) has no Anthropic voice that works without an API key; `claude-headless` (Claude Code CLI on subscription) exists as a hop but is never planned as a dissent voice.
- Five dissent payloads were rejected on schema (`missing-or-empty-failure_mode`) and written to the `adversarial-rejected-*.jsonl` sidecar without reaching the reviewer; **three of the five were real defects** (cycle-125 S1 `if T=/; then rm -rf "$T"` fence bypass; sprint-bug-245 F-3 row-supplied pricing authority; sprint-bug-245 negative token counts → negative cost). They were caught only because the lead hand-triaged the sidecar. KF-004 (`validate_finding silent rejection`) has 31 recurrences. The repair loop (`_repair_finding_via_model`) reports `repair_attempted: true, repair_succeeded: false` on every one.

## 3. Instruction surface at its ceilings and 200K-era context discipline (measured)

- Budgets: `CLAUDE.loa.md` 10,225 / 10,240 B; protocols 199,593 / 200,000 B; 12 of 36 skills within 400 B of the 16,384 B cap; 44 generated include blocks across 11 skills (`context_discipline` ×10). Imperative density is low (0.14 `MUST|NEVER|ALWAYS` per KB in skills). One skill is over the 500-line guidance (`loa-setup`, 512).
- `.claude/protocols/tool-result-clearing.md:9-12`: single search result 2,000 tokens → clear; accumulated 5,000 → MANDATORY clear; full file 3,000; **session total 15,000 → STOP and synthesize to NOTES.md**; `:34` "never load a >1,000-line file whole". Restated verbatim in ten skills through the `context_discipline` include, and echoed in `session-continuity.md:123` and `trajectory-evaluation.md:302`. These are 200K-era numbers; on a 1M-context model they force lossy round-trips through NOTES for work that fits in context.
- Related caps: `notes-guard.sh` `READ_CAP=69632`; `context-manager.sh` `DEFAULT_MAX_EAGER_LOAD_LINES=500`; `lib-multipass.sh` pass budgets 4,000/20,000/6,000/6,000; `karpathy-surgical-diff-check.sh` warns above 100 diff lines per task; parallelism gated on `wc -l` thresholds (2,000/3,000 lines) in `auditing-security`, `implementing-tasks`, `reviewing-code`.
- Largest protocols (candidates for on-demand loading): `helper-scripts.md` 16,830 B, `session-continuity.md` 14,638, `constructs-integration.md` 14,434, `trajectory-evaluation.md` 13,314, `recommended-hooks.md` 11,773.

## 4. Stale generation residue in routing and governance (verified)

- `aliases.cheap: anthropic:claude-sonnet-4-6` (`model-config.yaml:894`) feeds `flatline-scorer`, `translating-for-executives`, `jam-synthesizer` and `tier_groups.mappings.mid`.
- `model-adapter.sh:111-121` last-resort map `opus → anthropic:claude-opus-4-7` (reached only when the overlay and canonical resolvers fail); no entries for the 5-family; `--help` at `:344` repeats the claim.
- `flatline-orchestrator.sh:565-577` forward-compat regexes reject `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1`, `fable`, `gpt-5.5-pro` (the generated SSOT map covers them, so only the fallback path is wrong); stub allowlist `:555` lists 4.x.
- `.claude/data/model-permissions.yaml` (trust scopes / epistemic `context_access`, consumed by `routing/context_filter.py:409-416`): no 5-family entries; `:145` calls Opus 4.7 "current default"; unlisted models get no context filtering.
- `flatline-proposal-review.sh:74` default `gpt-4o`; `data/personas/alternative-model.md:30` recommends `bedrock:claude-3-5-sonnet`; `hitl-jury-panel/SKILL.md:65,68` and `loa-aleph/SKILL.md:34` pin `claude-opus-4-8` in copyable examples; `deep-thinker`/`fast-thinker` pin `gemini-2.5-pro`/`gemini-3-flash`.

## 5. Harness features and probes (verified)

- `detect-platform-features.sh:53-74` checks a never-set env var and claims a version check it does not perform, so it always writes `active_skill_available: false`; `implement-gate.sh:98-131` therefore runs permanently in heuristic mode and its authoritative `active_skill` branch (`:157-190`) is dead code.
- `validate-skill-capabilities.sh:108` `WRITE_CAPABLE_AGENTS=("general-purpose")` — a one-element allow-list of agent types.
- Permissions: 381 shared allow rules, 62 deny; current guidance prefers per-skill `allowed-tools` and hooks over large allow lists; the rule grammar has a second form (`Bash(git add *)`) that `check-permissions.sh` does not parse (documented limitation in sprint-bug-246).
- Already fine: PreToolUse chain 45 ms per Bash call; SessionStart ≈ 2 s (`check-updates.sh` 1.3 s, `loa-kf-surface.sh` 0.46 s), five hooks already async; skills use `disallowed-tools`, `context: fork`, `effort`; the adapter emits adaptive thinking, `output_config.effort`, `output_config.format`, one cache breakpoint, and drops sampling params where rejected.

## 6. Current-feature inventory (from the docs agent; items Loa does not use yet)

Batch API for the offline phases (Flatline, dissent, red-team, scoring — non-interactive, half price); `strict: true` on tool definitions; cache breakpoints on tools and stable history for multi-turn flows; a real token count when a CLI hop reports no usage; hook events `PostToolUseFailure`, `PermissionDenied`, `SessionEnd`; skill frontmatter `when_to_use`, `argument-hint`, `paths`; subagent `memory`, `isolation: worktree`, `maxTurns`; `/skill-doctor` and `claude plugin eval` for pruning unused surface.

## 7. Ranking

1. C1–C9: lift the caps (cycle-126 Sprint 1).
2. §2: a second dissent voice by default and no silently dropped findings (Sprint 2).
3. §3: context discipline and Flatline caps sized for the current generation, then the instruction diet under the eval gate (Sprint 3).
4. §4 + §5: routing residue, governance registry, probe repair, permission grammar (Sprint 4 / micro-sprints).
5. §6: cost and latency levers (later).
