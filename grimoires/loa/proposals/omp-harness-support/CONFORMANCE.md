# Loa → OMP Conformance Matrix

> Method: spec-derived conformance (SPEC = OMP integration contract per `omp://`
> docs; IMPL = Loa framework surfaces). Score = Passing / (MUST + SHOULD);
> MUST-score < 0.95 per surface ⇒ not conformant for that surface.

## OMP discovery model (the spec, in one paragraph)

OMP loads config through a capability registry: providers are priority-sorted
(`native .omp` 100 > `omp-plugins` 90 > `claude .claude` 80 > `agents .agent[s]` /
`codex` 70 > `opencode` 55 > `github` 30 > `agents-md` standalone `AGENTS.md` 10),
first-wins per capability key. **Each capability enumerates its own provider
set** — a provider that supplies one surface does not automatically supply the
others (`omp://config-usage.md` §5).

## Coverage matrix

| # | Surface | MUST | SHOULD | Passing | Score | Verdict | Evidence |
|---|---|:--:|:--:|:--:|:--:|---|---|
| 1 | Context / kernel | 2 | 1 | 0 | 0.00 | **FAIL** | `omp://context-files.md` |
| 2 | Slash commands | 3 | 1 | 4 | 1.00 | **PASS** | `omp://slash-command-internals.md` |
| 3 | Skills | 3 | 2 | 3 | 0.60 | **PARTIAL** | `omp://skills.md` |
| 4 | Hooks (governance) | 2 | 1 | 0 | 0.00 | **FAIL** | `omp://hooks.md` |
| 5 | Subagents | 2 | 1 | 0 | 0.00 | **FAIL** | `omp://task-agent-discovery.md` |
| 6 | MCP servers | 2 | 1 | 1 | 0.33 | **PARTIAL** | `omp://mcp-config.md` |
| 7 | Settings / permissions | 2 | 1 | 0 | 0.00 | **FAIL** | `omp://settings.md` |
| 8 | Rules / sticky | 1 | 1 | 0 | 0.00 | **FAIL** | `omp://rulebook-matching-pipeline.md` |
| 9 | Autonomous dispatch | 1 | 1 | 0 | 0.00 | **FAIL** | `scripts/spiral-harness.sh` |

**Aggregate MUST coverage: 1/18 ≈ 0.06 as-shipped.** After the kit (R1–R3) +
sequenced core integration: ≥ 0.90. Loa is *operable* under OMP (commands +
skills discover) but **not governed** (enforcement + kernel + autonomy inert).

## Findings

### 1. Context / kernel — FAIL
Loa injects its ~25KB kernel via `@`-import from root `CLAUDE.md`. OMP's `claude`
context provider reads `<cwd>/.claude/CLAUDE.md` (Loa doesn't create it) — **not**
root `CLAUDE.md`. Only the generated root `AGENTS.md` (agents-md provider,
priority 10) is discovered, and it is a lossy summary that does not `@`-import
the kernel. `@`-imports *are* honored by OMP (5 hops) — the gap is the entrypoint,
not the mechanism. **Fix:** R1 (kit) / R1' (`agents-md-gen.sh` emits the import).

### 2. Slash commands — PASS
`.claude/commands/**/*.md` discovered recursively at priority 80, with `dir:cmd`
aliasing. Loa's commands (incl. the Golden Path) are first-class. Only risk:
name-collision loss to a future omp-native/omp-plugin command.

### 3. Skills — PARTIAL (0.60)
Flat `.claude/skills/<name>/SKILL.md` is OMP-compatible (non-recursive, realpath
dedup is symlink-safe). Gaps: some skill dirs are persona-only (no `SKILL.md` →
not discovered); some skills have frontmatter `name` ≠ directory (so
`skill://<dir>` fails; only `skill://<name>` resolves — exact-match rule); some
construct skills omit `description` (tolerated by the `claude` provider; **fatal**
if repackaged native/omp-plugins/github). **Fix:** skill hygiene (follow-up).

### 4. Hooks (governance) — FAIL — PRIMARY BLOCKER
OMP hooks are TS/JS factory modules (`export default (pi)=>{ pi.on("tool_call",…) }`)
under `.omp/hooks/pre|post/`; `tool_call` returning `{block:true}` vetoes. **There
is no `.claude/hooks` discovery provider and no settings.json shell-hook
execution.** Loa's 25 shell guards (stdin-JSON, exit-2-blocks, `$CLAUDE_*` env)
are inert under OMP — every PreToolUse safety guard, PostToolUse logger, and
SessionStart surfacing silently no-ops. **Verified empirically** (OMP Write/Edit
produced no `.run/audit.jsonl` entries; concurrent Claude sessions did). **Fix:**
R3 (kit) — `.omp/hooks/pre/loa-guards.ts` shells the canonical guards.

### 5. Subagents — FAIL
`discoverAgents` merges `.omp/agents` + `~/.omp/agent/agents` + installed Claude-
*plugin* `agents/`. `.claude/agents` is **explicitly skipped**
(`TASK_AGENT_CONFIG_SOURCE=".omp"`). Loa's subagents live in `.claude/subagents/`
(non-standard) → not OMP-discovered. Impact LOW-MEDIUM (skill-invoked; OMP's
bundled `task` agents substitute).

### 6. MCP servers — PARTIAL (0.33)
OMP reads `.claude/` MCP configs and the `mcpServers` shape is ~identical, so
server *definitions* are discoverable. The Claude-specific `enabledMcpjsonServers`
toggle + "restart Claude Code" choreography are not honored. **Fix:** emit
`.omp/mcp.json` or a portable root `.mcp.json` (follow-up).

### 7. Settings / permissions — FAIL
`.claude/settings.json` `permissions.allow/deny` grammar + hooks schema are not
OMP's model; native settings live at `.omp/config.yml` (arrays replace, not
append). The ~365 pre-approvals + deny rules do not apply under OMP (OMP owns its
approval model). **Fix:** port critical denies into the R3 guard; document the
OMP approval posture.

### 8. Rules / sticky — FAIL
No `claude` rules provider. Loa invariants in `.claude/rules/*.md` are not an OMP
rules source; no `RULES.md`. **Fix:** R2 (kit) — native `.omp/RULES.md`.

### 9. Autonomous dispatch — FAIL
`spiral-harness.sh` / `spiral-simstim-dispatch.sh` (engines behind `/run`,
`/simstim`, `/spiral`) hardcode the `claude` CLI (`command -v claude || exit 127`;
`claude -p …`). This is the agent-session dispatcher, distinct from the swappable
`cheval` model router (which is already multi-harness). `cheval` has one coupling:
`native_runtime = claude-code:session` hardcoded in `routing/resolver.py`.
**Fix:** OMP headless backend + parameterized native-runtime id (follow-up).

## Divergences (accepted vs will-fix)

| Divergence | Resolution |
|---|---|
| Loa is Claude-native by design; `claude` provider covers commands/skills/MCP free | **ACCEPTED** baseline |
| Persona-only skill dirs; `name`≠dir; missing `description` | **WILL-FIX** (skill hygiene) |
| Subagents in `.claude/subagents/` not discovered | **ACCEPTED** (skill-invoked) |
| Claude permissions/deny not honored | **ACCEPTED** (OMP owns approval; port critical denies via R3) |
| No OMP rules/sticky | **FIXED** by R2 |
| `native_runtime` hardcoded | **WILL-FIX** (parameterize) |
