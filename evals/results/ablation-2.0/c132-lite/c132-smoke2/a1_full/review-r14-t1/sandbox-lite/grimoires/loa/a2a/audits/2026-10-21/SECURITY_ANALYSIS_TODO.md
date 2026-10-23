# Security analysis working file — sprint-1 audit (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Date: 2026-10-21. Scope: `pr/head.diff` (88 files). `pr/head/` holds the non-dotfile files; the
`.claude/` and `.loa.config.yaml.example` hunks were read from the diff and the workspace `.claude/`
tree (CLAUDE.loa.md hash and agent-types.yaml match head; the Python adapter package does not import).

## Phase 1A — sources (untrusted entry points)

| # | Source | Trust | File:line | Status |
|---|--------|-------|-----------|--------|
| S1 | PreToolUse stdin payload (`tool_input.active_skill`, `agent_id`) — model-authored | untrusted | `.claude/hooks/compliance/implement-gate.sh:37-47` | SAFE — evidence only; `active_skill_available` forced false; mode never read from payload or `.run/` |
| S2 | `.loa.config.yaml` `implement_gate.mode` | operator (model-writable, unfenced) | `.claude/hooks/compliance/implement-gate.sh:113-117` | PARTIAL — opt-in trusts S1 when set; file has no write fence (pre-existing trust boundary; tightening vs base which keyed off `.run/`) |
| S3 | settings.json allow/deny rule strings | operator | `.claude/scripts/check-permissions.sh:87-98` | SAFE — `rule_key` is pure parameter expansion, no glob/eval; `rule_key \|\| continue` drops non-`Bash(...)` |
| S4 | `.run/platform-features.json` contents (surfaced by `/loa`) | semi-trusted state | `.claude/scripts/detect-platform-features.sh:31-37` | SAFE — `tr -d '[:cntrl:]' \| cut -c1-120` before echo |
| S5 | review.md text parsed by the eval grader | untrusted (model output) | `pr/head/evals/graders/recall-vs-defects.sh:72-92` | CONFIRMED — bare `:N` alternative over-credits (HIGH-001) |
| S6 | cheval stderr forwarded by the shim | provider output | `.claude/scripts/model-adapter.sh:656-659` | SAFE — fixed-string filter, 600-char cap; mktemp unguarded (LOW) |
| S7 | diff `--git` header paths logged by lib-content | untrusted (PR content) | `.claude/scripts/lib-content.sh:295,339,354` | SAFE — C0/DEL stripped for the two stderr lines |
| S8 | `agent-types.yaml` keys loaded into `WRITE_CAPABLE_AGENTS` | repo data | `.claude/scripts/validate-skill-capabilities.sh:112-117` | SAFE — `^[A-Za-z0-9_-]+$` filter; missing/unparsable → general-purpose only |
| S9 | catalog YAML (`model-config.yaml`) keys added (`probed_ceiling`, `account_limits`, `beta_headers`) | repo data | `.claude/data/schemas/model-config-v3.schema.json:154-180,219-250` | SAFE — typed, `additionalProperties: false`, dated beta-header pattern |

## Phase 1A — sinks

| # | Sink | File:line | Status |
|---|------|-----------|--------|
| K1 | `.run/platform-features.json` write (mktemp + mv) | `implement-gate.sh:41-47` | SAFE — atomic, lead-only, write-once, tmp removed |
| K2 | gate decision `{"decision":"ask"}` / silent allow | `implement-gate.sh:113-117` | SAFE under default; see S2 |
| K3 | model dispatch target (`MODEL_TO_ALIAS`, `MODEL_TO_PROVIDER_ID`) | `model-adapter.sh:111-116`, `flatline-orchestrator.sh:697-702`, `red-team-model-adapter.sh:66-71` | SAFE — RES-2 agreement with catalog verified by test |
| K4 | trust scopes for new remote models | `.claude/data/model-permissions.yaml:204-470, 622-645` | SAFE — all rows mirror 4.7 (all `none`, `security: redacted`); covered by `test_current_generation_rows_mirror_the_4_7_scopes` |
| K5 | grader recall score → replay A/B decision | `recall-vs-defects.sh:101-109` | CONFIRMED over-report (HIGH-001) |
| K6 | stderr of `/loa` and the shim | S4, S6 | SAFE |

## Phase 1B — traced paths

- S1→K1: payload with `active_skill` and no `agent_id`, lead session → one timestamp written. Forged `.run/` state (IG-5) does not flip the mode. SAFE.
- S2→K2: `implement_gate.mode: authoritative` → `tool_input.active_skill` in {implement,/bug,…} silently allows an App-Zone write (IG-7). The key is undocumented by test (IG-11). Trust boundary = operator config; not fenced by zone-write-guard. PARTIAL (observation, not tallied).
- S3→K3-ish (requirement coverage): verified CP-11..13 pass; Claude Code docs confirm `:*` ≡ trailing ` *`. Bare `Bash` / `Bash(*)` / `Bash(git*)` not credited (conservative) and a deny-all `Bash` not detected — pre-existing at base. Observation.
- S5→K5: reproduced three ways (trailer counts, inline JSON, all-zero trailer vs anchor ≤3). Base 1.0.0 parser does not credit. CONFIRMED.
- Documentation surface: `constraints.json` C-TEAM-001..005 reverted but the rendered `agent_teams_constraints` block in CLAUDE.loa.md is STALE (`generate-constraints.sh --validate-only` FAIL). Pre-existing drift the revert was meant to close. MEDIUM.
- Registry completeness: `.claude/agents/chart-researcher.md` exists; `agent-types.yaml` omits it → SC-T-AGENT-7 loop fails; the same test's `yq -r … tostring` also errors on yq v4.40.5. MEDIUM + LOW.

## Deferred / unable to assess

- Python adapter tests (5 files) — `loa_cheval` snapshot package fails to import (`TransportPolicy`).
- RG-16/17, PB-8, PR-1, c124-1.3-11 — fixture corpus, allowlist and regen script absent from the snapshot.
- `.loa.config.yaml.example` edits — file absent from the snapshot (read from the diff only).
- Bridgebuilder `dist/` rebuild — `tsx` absent; hashes in `.build-manifest.json` taken on trust.
