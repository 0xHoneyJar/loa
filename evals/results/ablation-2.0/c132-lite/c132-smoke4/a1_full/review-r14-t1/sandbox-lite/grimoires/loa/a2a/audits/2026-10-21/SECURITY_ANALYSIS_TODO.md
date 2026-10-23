# Security analysis working file — sprint-1 audit (PR cycle-126 sprint-250 tasks 4.1–4.8)

Scope: `pr/head.diff` (88 files). Scope script over `pr/head/`: 6 command-exec sinks, 6 file-op sinks, 6 auth files, 7 LLM/AI files, 0 HTTP entry points.

## Sources (untrusted entry points)

| # | Source | Trust | Status | Note |
|---|--------|-------|--------|------|
| S1 | PreToolUse stdin JSON (`tool_input.*`) → `head/.claude/hooks/compliance/implement-gate.sh:33` | model-authored | CONFIRMED | `active_skill` becomes an authorization signal only under `implement_gate.mode: authoritative` (:115, :128); config edit itself is a non-App-Zone write the same hook allows silently |
| S2 | `.loa.config.yaml` `implement_gate.mode` → `implement-gate.sh:115`, `detect-platform-features.sh:31` | operator file, agent-writable | CONFIRMED | no trust-input fence on this path in the head tree (the live install's later revision adds one) |
| S3 | `.run/platform-features.json` → `implement-gate.sh:42`, `detect-platform-features.sh:36,61` | agent-writable state | SAFE | read only for evidence; `active_skill_available` never selects the mode (IG-5, CH-T10) |
| S4 | settings.json allow/deny strings → `check-permissions.sh:197-204` | operator JSON | SAFE | `rule_key` pure parameter expansion; non-`Bash(` rules skipped; malformed file WARN |
| S5 | `REQUIRED_*` requirement strings → `check-permissions.sh:235` | code constant | PARTIAL | bare `rule_key` call under `set -e` (dead path today); `base` derivation wrong for an exact key (:237) |
| S6 | review.md text → `evals/graders/recall-vs-defects.sh:71-87` | model output | CONFIRMED | bare `:N` alternative binds JSON pairs / markdown tokens as phantom citations |
| S7 | diff `--git` header paths → `lib-content.sh:295` | repo content | SAFE | control bytes stripped before stderr |
| S8 | cheval stderr → `model-adapter.sh:655-658` | subprocess | SAFE | only the agy WARN line forwarded, cut to 600 chars |
| S9 | `agent-types.yaml` keys → `validate-skill-capabilities.sh:112-115` | repo data | SAFE | `^[A-Za-z0-9_-]+$` filter; fallback to general-purpose |
| S10 | license fixture JSON timestamps → `ensure_license_fixtures.sh:47-54` | test fixture | SAFE | regex-extracted, unparseable → regenerate |

## Sinks

| # | Sink | Status | Note |
|---|------|--------|------|
| K1 | `mv -f` onto `.run/platform-features.json` (`implement-gate.sh:45`, `detect-platform-features.sh:66`) | SAFE | mktemp in `.run/`, atomic, fixed-string content |
| K2 | `exit 0` silent allow on App Zone write (`implement-gate.sh:129`) | CONFIRMED | reachable from S1+S2 without any RUNNING state |
| K3 | `jq -nc --argjson b` (`implement-gate.sh:44`) | SAFE | base defaults to `{}` on non-object |
| K4 | `yq eval` on data file (`validate-skill-capabilities.sh:115`) | SAFE | `|| true`, filtered |
| K5 | `grep -F ... >&2` (`model-adapter.sh:657`) | SAFE | fixed-string match, truncated |
| K6 | recall metric → replay A/B decision (Task 4.8 revert) | CONFIRMED | inflated by S6 |

## Second-order
- `.run/platform-features.json` evidence (`active_skill_seen_at`) is surfaced on `/loa` via `detect-platform-features.sh --line`: `tr -d '[:cntrl:]' | cut -c1-120` — SAFE.
- `model-permissions.yaml` rows are informational unless `hounfour.feature_flags.context_filtering` is on; `claude-headless` row asserts no side effects while `extra.allowed_tools` can widen the CLI — PARTIAL (LOW).

## Deferred / scope limits
- Head snapshot holds touched files only: `.claude/agents/*.md` presence, CHANGELOG, fixture corpus (`pr-05/head`) not assessable. RG-16/17, RES-6, SC-T-AGENT-7 cannot run here for that reason.
- `cheval.py` / `base.py` hunks are docstring/comment only; not traced.
