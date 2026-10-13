# Helper Scripts Reference

Core scripts in `.claude/scripts/`. Run any script with `--help` for usage details.

> **Machine-readable contract**: `loa-capabilities.sh --json` lists the
> agent-facing scripts with their JSON modes, help support, exit-code and env
> conventions in one call — prefer it over grepping docs. One-call triage:
> `loa-status.sh --triage --json` (state + health + next command).

## Core Scripts

| Script | Purpose |
|--------|---------|
| `mount-loa.sh` | Install Loa onto existing repo |
| `update.sh` | Framework updates with atomic commits |
| `upgrade-health-check.sh` | Post-upgrade migration and config validation |
| `check-loa.sh` | CI validation |

## Context Management

| Script | Purpose |
|--------|---------|
| `context-manager.sh` | Context compaction + semantic recovery |
| `cache-manager.sh` | Semantic result caching |
| `condense.sh` | Result condensation engine |
| `early-exit.sh` | Parallel subagent coordination |

## Workflow Support

| Script | Purpose |
|--------|---------|
| `synthesize-to-ledger.sh` | Continuous synthesis to NOTES.md/trajectory |
| `schema-validator.sh` | Output validation |
| `permission-audit.sh` | Permission request analysis |
| `search-orchestrator.sh` | ck-first semantic search with grep fallback |
| `compound-orchestrator.sh` | `/compound` command orchestration |
| `collect-trace.sh` | Execution trace collection for `/feedback` |

## Decision Surfaces (cycle-128)

Exit codes are `0` ok, `1` refused or failed, `2` usage unless the row says otherwise. Paths are under `.claude/scripts/` unless they start with `tools/`.

| Script | Contract | Exit codes |
|--------|----------|------------|
| `lib/dec-write-lib.sh` | Single writer of `grimoires/loa/decisions.yaml`: `new`, `decide`, `confirm`, `reject`, `supersede`, `import --from PENDING`, `list [--status] [--decided-by] [--not-decided-by] [--format md]`, `context [--why] \| --set-unattended \| --clear`. Lock, yq v4, verify before rename; attribution from the run context; unattended writes land `proposed`; a linked worktree writes the sprint pending file; refuses the live ledger under CI or a hook context. | 0 ok; 1 refused (preflight, CI/hook context, lock busy, verify, validation, unknown id, illegal transition, ref grammar, missing artifact, ambiguous confirm); 2 usage |
| `../hooks/session-start/loa-decisions-surface.sh` | SessionStart surface of pending rows, default off (`decisions.surface_at_session_start`); sanitised and L6-fenced. | always 0 |
| `chart-guard.sh [--close-consumed] [--root DIR]` | First step of `/chart`: prints `interactive` and exits 0, or refuses when the context is unattended or `br` is missing. | 0 go; 1 refused; 2 usage |
| `chart-ticket.sh <subcommand> [--dry-run]` | The `/chart` write steps: `epic`, `ticket`, `edge`, `claim`, `resolve`, `rule-out`, `handoff`, `close`, `research-begin`, `research-end`. Idempotent by ledger `source` and bead `external_ref`; every write refuses an unattended context (`--dry-run` and `close --consumed-by` exempt). | 0 ok; 1 refused or failed, nothing further written; 2 usage |
| `chart-frontier.sh <epic-id\|map-slug> [--json] [--root DIR]` | Lists a map's unclaimed, unblocked `question` tickets through `br ready`; an empty frontier prints nothing. | 0 ok; 1 unknown map or unreadable `br` output; 2 usage or `br` missing |
| `chart-unblock-probe.sh --ticket <bead> [--timeout <s>] -- <cmd…>` | Runs a `decision:unblock` probe argv in a throwaway detached worktree under a scrubbed environment and prints `probe-exit: N` (124 on a timeout) as information. | 0 nothing it watches changed; 1 something changed or the worktree could not be created; 2 usage |
| `red-test-check.sh --red <commit> [--green <rev>] [--test-file <path>] [--setup <cmd>] [--no-link-deps] [--timeout <s>] [--json] -- <test cmd…>` | Runs the test at the red commit and the green revision in temporary worktrees with dependency directories linked; prints the red run's tail; `--json` prints `{red, green, red_exit, green_exit, verdict, red_tail, green_tail, linked_deps}`. | 0 `VERIFIED`; 1 `GREEN_FAILS`; 2 usage, unresolvable commit, red not an ancestor, worktree or `--setup` failure; 3 `DECOY`; 4 `NOT_A_RED`; 5 `TIMEOUT` |
| `tools/check-round-independence.sh <transcript> [--min-average N] [--json]` | Scores an interview transcript's `<!-- round: … -->` blocks: no same-round or forward dependency, no repeated id, increasing rounds, at least N (default 2) new questions per round on average, the final round exempt. | 0 independent; 1 violation; 2 usage, unreadable file or no round block |
| `tools/check-glossary-terms.sh [--kernel P] [--glossary P] [--allowlist P] [--json] [--report]` | Every identifier-shaped backticked span of `CLAUDE.loa.md` outside fenced code resolves to a glossary entry or alias, or to `.claude/data/glossary-allowlist.txt` (at most 30 entries); stale or redundant allowlist entries WARN. | 0 every token resolves; 1 a miss or more than 30 allowlist entries; 2 usage or unreadable input |

`validate-artifact.sh` gains `--type decisions`, `--type map`, `--type spike` and `--type glossary`, the Seams Under Test rule in `--type sprint`, and fact/decision tag checks in `--type prd` and `--type sdd`. `run-mode-ice.sh` gains `is-spike`; `golden-path.sh` reports the `charting` phase.

## Visual & Documentation

| Script | Purpose |
|--------|---------|
| `mermaid-url.sh` | Beautiful Mermaid preview URL generation |

## Integrations

| Script | Purpose |
|--------|---------|
| `mcp-registry.sh` | MCP server management |
| `gh-label-handler.sh` | GitHub issue creation with label fallback |
| `feedback-classifier.sh` | Smart feedback routing |

---

## Search Orchestration (v1.7.0)

Skills use `search-orchestrator.sh` for ck-first semantic search with automatic grep fallback.

### Usage

```bash
# Semantic/hybrid search (uses ck if available, falls back to grep)
.claude/scripts/search-orchestrator.sh hybrid "auth token validate" src/ 20 0.5

# Regex search (uses ck regex mode or grep)
.claude/scripts/search-orchestrator.sh regex "TODO|FIXME" src/ 50 0.0
```

### Search Types

| Type | ck Mode | grep Fallback | Use Case |
|------|---------|---------------|----------|
| `semantic` | `ck --sem` | keyword OR | Conceptual queries |
| `hybrid` | `ck --hybrid` | keyword OR | Discovery + exact |
| `regex` | `ck --regex` | `grep -E` | Exact patterns |

### Environment Override

```bash
LOA_SEARCH_MODE=grep  # Force grep fallback
```

---

## Clean Upgrade (v1.4.0+)

Both `mount-loa.sh` and `update.sh` create single atomic git commits:

```
chore(loa): upgrade framework v1.3.0 -> v1.4.0
```

Version tags: `loa@v{VERSION}`. Query with `git tag -l 'loa@*'`.

---

## Post-Upgrade Health Check

Runs automatically after `update.sh`. Manual usage:

```bash
.claude/scripts/upgrade-health-check.sh          # Check for issues
.claude/scripts/upgrade-health-check.sh --fix    # Auto-fix where possible
.claude/scripts/upgrade-health-check.sh --json   # JSON output for scripting
```

Checks: bd->br migration, deprecated settings, new config options, recommended permissions.

---

## MCP Registry

```bash
.claude/scripts/mcp-registry.sh list      # List servers
.claude/scripts/mcp-registry.sh info <s>  # Server details
.claude/scripts/mcp-registry.sh setup <s> # Setup instructions
```

Pre-built configs available in `.claude/mcp-examples/` for Slack, GitHub, Sentry, PostgreSQL.

---

## Context Tooling (recursive-JIT scripts)

```bash
.claude/scripts/context-manager.sh   # Session context orchestration (status/init)
.claude/scripts/cache-manager.sh     # Semantic cache get/set/invalidate (.claude/cache/)
.claude/scripts/condense.sh          # Condense long docs for context injection
.claude/scripts/early-exit.sh        # Parallel-subagent early-exit signaling
```

Each script's `--help` is the authoritative interface doc. Durable rule: externalize decisions/findings to `grimoires/loa/NOTES.md` before context loss (owned by `session-continuity.md` + skill context_discipline blocks).

---

## Error Codes (LOA-EXXX)

Structured error codes: registry `.claude/data/error-codes.json`, renderer `.claude/scripts/lib/dx-utils.sh` (errors teach: every code carries a what + a fix, surfaced by `/loa doctor`). Ranges: `E0xx` framework/env, `E1xx` workflow/lifecycle, `E2xx` beads, `E3xx` events/bus, `E4xx` security/guardrails, `E5xx` constructs/packs. Add codes in the JSON registry, never hardcoded strings.

---

## Full Documentation

See `.claude/protocols/reference/helper-scripts.md` for comprehensive script documentation (read on demand).
