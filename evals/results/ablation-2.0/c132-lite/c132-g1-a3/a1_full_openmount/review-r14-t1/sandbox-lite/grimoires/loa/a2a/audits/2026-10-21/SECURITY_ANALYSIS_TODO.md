# Security analysis working file — sprint-1 audit (task review-r14), 2026-10-21

Scope: `pr/head.diff` (88 files). Trust levels: MODEL = text the governed model authors (tool_input, files in `.run/`, `grimoires/`, project root config); OPERATOR = `.claude/` System Zone and `.claude/settings*.json`; REMOTE = provider stderr/stdout.

## Sources (untrusted entry points)

| # | Source | Trust | Status | Note |
|---|--------|-------|--------|------|
| S1 | `tool_input.active_skill` on PreToolUse stdin — `head/.claude/hooks/compliance/implement-gate.sh:41,120` | MODEL | CONFIRMED | Reaches an allow decision when `.loa.config.yaml implement_gate.mode: authoritative` (HIGH-001) |
| S2 | `.loa.config.yaml` `implement_gate.mode` — `implement-gate.sh:113-116`, `detect-platform-features.sh:30-33` | MODEL (project root, unfenced by every PreToolUse hook) | CONFIRMED | Selector for S1 (HIGH-001) |
| S3 | `.run/platform-features.json` — `detect-platform-features.sh:35-36,62`, `implement-gate.sh:43-44` | MODEL | SAFE | Never selects the mode (IG-5, CH-T10 pass); `--line` output passes `tr -d '[:cntrl:]' \| cut -c1-120` before `/loa` prints it |
| S4 | Review text graded by `head/evals/graders/recall-vs-defects.sh:66` | MODEL (the evaluated agent) | CONFIRMED | LOA-VERDICT trailer JSON parsed as bare `:N` citations (HIGH-002) |
| S5 | `.claude/settings*.json` permission rules — `head/.claude/scripts/check-permissions.sh:197-205` | OPERATOR | SAFE | `rule_key` pure parameter expansion; non-`Bash(...)` skipped; CP-11..13 pass |
| S6 | `.claude/data/agent-types.yaml` — `head/.claude/scripts/validate-skill-capabilities.sh:110-117` | OPERATOR | SAFE | `^[A-Za-z0-9_-]+$` filter; fallback `general-purpose` |
| S7 | cheval stderr — `head/.claude/scripts/model-adapter.sh:657-658` | REMOTE | PARTIAL | Only the fixed agy WARN line is forwarded (600 chars); temp file holds the rest (LOW-006) |
| S8 | diff `--git` header paths — `head/.claude/scripts/lib-content.sh:295` | MODEL/REMOTE | SAFE | Control bytes stripped before stderr (CMP-278) |
| S9 | License fixture JSON — `head/tests/fixtures/ensure_license_fixtures.sh:48-55` | LOCAL test | SAFE | grep-extracted ISO timestamp only |

## Sinks (dangerous operations)

| # | Sink | Status | Note |
|---|------|--------|------|
| K1 | `exit 0` allow on App-Zone write — `implement-gate.sh:126-130` | CONFIRMED | Reached from S1+S2 (HIGH-001) |
| K2 | `mv -f` into `.run/platform-features.json` — `implement-gate.sh:45-47`, `detect-platform-features.sh:63-68` | SAFE | mktemp in `$RUN_DIR` + atomic mv; content fixed strings + timestamp; model-triggerable but no injection (LOW-004 shape note) |
| K3 | `>> "$RUN_DIR/audit.jsonl"` — `implement-gate.sh:139-148` | SAFE | jq-built record, constant fields |
| K4 | Recall score / `pass` — `recall-vs-defects.sh:102-107` | CONFIRMED | Inflated by S4 (HIGH-002) |
| K5 | `yq eval` / `jq` reads of operator YAML/JSON | SAFE | No shell interpolation of values |
| K6 | `mktemp "${TMPDIR:-/tmp}/..."` — `model-adapter.sh:656` | PARTIAL | No trap; failure path aborts silently under `set -e` (LOW-006) |

## Auth / LLM surfaces

- `head/.claude/data/model-permissions.yaml:207-471,622-645`: 11 new remote-model rows, all `none` side-effect scopes, copied from 4.7. `anthropic:claude-headless` row (446-471) declares `command_execution: false` while the catalog entry is `kind: cli`; head catalog `extra` = `{cli_model: fable}`, no `allowed_tools` → row accurate today, no cross-check test (LOW-007).
- `security-audit-scope.sh --json` on the head tree: sources 5, sinks 4, auth 0, llm 0.

## Deferred / scope limits

- Full-suite bats in the frozen `pr/head` snapshot: suites needing `compat-lib.sh`, `lib/model-resolver.sh`, executable bits or fixture trees not in the 88 files fail for environmental reasons (eval-recall-grader RG-*, model-adapter MA-3..6, hook-guard, license-fixture-freshness). Subjects re-run by hand where possible (grader reproduction below). implement-gate 11/11, check-permissions 13/13, model-adapter MA-1..2 pass.
- Grader reproduction (head script, manifest `{file: .claude/scripts/a.sh, anchor_line: 2}`, review = `` `head/.claude/scripts/a.sh:400` `` + standard trailer): `recall 1.0, citations 6`; trailer removed: `recall 0.0, citations 1`; base 1.0.0 script: `recall 0.0, citations 1`.
