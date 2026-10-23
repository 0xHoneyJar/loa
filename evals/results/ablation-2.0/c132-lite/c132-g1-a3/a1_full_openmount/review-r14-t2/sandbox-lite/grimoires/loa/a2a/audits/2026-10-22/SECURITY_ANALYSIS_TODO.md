# Security analysis working file — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Scope: `pr/head.diff` (88 files). Trust levels: `model` = model-authored (PreToolUse `tool_input`, review text), `operator` = operator-written config/settings, `repo` = checked-in data.

## Sources (untrusted entry points)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | PreToolUse stdin `tool_input.active_skill` | model | implement-gate.sh recorder (:40-48), authoritative branch (:124-136) | CONFIRMED — authoritative branch trusts it (MED-001); recorder stores only a constant source string (SAFE) |
| S2 | PreToolUse stdin `tool_input.file_path` | model | implement-gate.sh zone check, stderr echo (:134) | PARTIAL — raw echo to stderr (LOW-004); zone check unchanged from base |
| S3 | `.loa.config.yaml` `implement_gate.mode` | operator (model-writable, no Write fence in head) | implement-gate.sh (:115), detect-platform-features.sh --line | CONFIRMED — the enabling condition for MED-001 |
| S4 | `.run/platform-features.json` | model-writable state | recorder base object (:43), detect --line evidence (:33) | SAFE — never selects the mode (IG-5); evidence line passes `tr -d '[:cntrl:]' \| cut -c1-120` |
| S5 | `settings.json` permission rules (3 layers) | operator | check-permissions.sh rule_key (:162), maps, JSON report via `jq -R` | SAFE for injection (jq --arg / -R); grammar gaps LOW-001 / LOW-006 |
| S6 | Review text (`review.md`) | model | recall-vs-defects.sh CITE regex (:72-74) | CONFIRMED — verdict-trailer JSON numbers bind as citations (MED-002) |
| S7 | Diff `--- a/` header paths | model/repo | lib-content.sh log lines (:295, :339, :354) | SAFE — C0/DEL stripped (CMP-278) |
| S8 | cheval stderr | provider | model-adapter.sh temp file (:656-660) | PARTIAL — only the agy WARN forwarded; temp file not trap-cleaned (LOW-003) |
| S9 | `.claude/data/agent-types.yaml` | repo | validate-skill-capabilities.sh (:111-117) | SAFE — key allowlist `^[A-Za-z0-9_-]+$`, fallback general-purpose |
| S10 | catalog `params.beta_headers` | operator | anthropic adapter header | SAFE — schema pattern never looser than adapter regex (V3 cross-check) |

## Sinks (dangerous operations)

| # | Sink | Guard | Status |
|---|------|-------|--------|
| K1 | implement-gate `exit 0` allow on App Zone write (:129) | mode must be `authoritative` via config; default heuristic | CONFIRMED (MED-001, CWE-807) — same primitive existed in base behind `.run/` flags |
| K2 | `mv -f` into `.run/platform-features.json` (:46) | mktemp in RUN_DIR, lead-session only, once | SAFE |
| K3 | `jq -nc --argjson b "${_ig_base:-{\}}"` (:45) | base from `select(type == "object") \| tail -n 1` | SAFE |
| K4 | `yq` on `.loa.config.yaml` per App-Zone write (:115) | `2>/dev/null \|\| ""` | SAFE (cost only) |
| K5 | `claude -p` CLI hop as terminal fallback of every Anthropic chain | adapter default `--tools ""`, `--permission-mode plan`; `extra.allowed_tools` widens | PARTIAL — registry row is static (LOW-002) |
| K6 | `mktemp "${TMPDIR:-/tmp}/..."` under `set -euo pipefail` (:656) | none | PARTIAL (LOW-003) |
| K7 | eval grader detection credit (:100-103) | ±3 window per anchor | CONFIRMED (MED-002) |

## Verified consistent (no finding)

- `marker-utils.sh verify-hash` → VALID for head `CLAUDE.loa.md` (hash `99948d56…`) and base (`ad303e10…`).
- `model-config.yaml.checksum` = sha256 of head catalog (review verified; not re-derived).
- FR-1.3 non-Anthropic default (`_NON_ANTHROPIC_DEFAULT_OUTPUT_CAP = 16_000`) is already in head `base.py:170` — the help/test changes describe existing behaviour.
- bats on an executable copy of `pr/head`: implement-gate 11/11, check-permissions 13/13, compliance-hook 14/14, hook-guard 6/8 (2 need `block-destructive-bash.sh`, outside snapshot), model-adapter 2/6 (4 need `lib/model-resolver.sh`, outside snapshot).
- Grader phantom citation reproduced: one real citation + a verdict trailer + `port :8080` → 7 citations.
