# Security analysis working file — sprint-1 (PR in `pr/`, cycle-126 sprint-250 tasks 4.1–4.8)

Date: 2026-10-21. Scope: `pr/head.diff` (88 files). Trust levels: `model` = text the fenced agent writes (tool_input, `.run/`, `.loa.config.yaml`, review prose); `operator` = settings/config an operator edits; `vendor` = catalog data copied from vendor pages.

## Sources (untrusted entry points)

| # | Source | Trust | File:line (head) | Status |
|---|--------|-------|------------------|--------|
| S1 | PreToolUse stdin `tool_input.active_skill` | model | `.claude/hooks/compliance/implement-gate.sh:41,123` | CONFIRMED → sink K1 (grant) and K2 (evidence write) |
| S2 | `.loa.config.yaml` `implement_gate.mode` | model-writable (repo root, outside `.claude/` fence) | `implement-gate.sh:114-116`, `detect-platform-features.sh:30-32` | CONFIRMED → selects K1 |
| S3 | `.run/platform-features.json` (`active_skill_seen_at`, `active_skill_source`) | model-writable | `detect-platform-features.sh:35-36,62` | PARTIAL → echoed into `/loa` output after `[:cntrl:]` strip only |
| S4 | settings `permissions.allow/deny` rule strings | operator | `check-permissions.sh:197-204` | SAFE for injection (assoc-array keys); CONFIRMED grammar gap (universal rule, `*` key) |
| S5 | `AGENT_TYPES_FILE` env + `agent-types.yaml` | CI env / System Zone | `validate-skill-capabilities.sh:110-117` | PARTIAL (env seam, all-false fallback) |
| S6 | diff `--git` header paths | model/PR author | `lib-content.sh:295` | PARTIAL (C0/DEL stripped, C1/bidi not) |
| S7 | review prose parsed by grader | model | `evals/graders/recall-vs-defects.sh:71-88` | CONFIRMED (comma continuation over-binds) |
| S8 | cheval stderr relayed by shim | provider | `model-adapter.sh:656-659` | SAFE (one fixed-string line, cut to 600) |
| S9 | catalog pricing/ceiling data | vendor | `model-config.yaml:470-509` | CONFIRMED inconsistency (long_context) |

## Sinks (dangerous operations)

| # | Sink | File:line (head) | Guard | Status |
|---|------|------------------|-------|--------|
| K1 | silent allow of App Zone Write/Edit (`exit 0`) | `implement-gate.sh:128-129` | only `implement_gate.mode: authoritative` (S2) | CONFIRMED: S1 → K1 with S2 set; run live, exit 0, no JSON |
| K2 | write `.run/platform-features.json` | `implement-gate.sh:43-48` | lead session only, once, atomic | PARTIAL: fires on any payload with S1 before file_path check; wholesale replace when file not a single object |
| K3 | hook decision JSON on stdout | `implement-gate.sh:135,230` | — | CONFIRMED: `{"decision":"ask"}` is not a PreToolUse decision (docs: `hookSpecificOutput.permissionDecision`); fence never asks |
| K4 | run preflight verdict (found/denied/missing) | `check-permissions.sh:233-250` | rule grammar | CONFIRMED gap for `Bash`, `Bash(*)`, `Bash(:*)`; bare `rule_key` under `set -e` at :235 |
| K5 | `mktemp` under `set -euo pipefail` | `model-adapter.sh:33,656` | none | CONFIRMED hard-fail regression |
| K6 | `/loa` status line (agent-visible text) | `detect-platform-features.sh:35-36` → `loa-status.sh:884` | `tr -d '[:cntrl:]'`, `cut -c1-120` | PARTIAL |
| K7 | model calls with `max_tokens` 300/500 on adaptive-thinking aliases | `flatline-validate-learning.sh:264,315`; `flatline-proposal-review.sh:182,233`; `flatline-learning-extractor.sh:317` | none | CONFIRMED path (`call_flatline_chat` → `--max-tokens`) |
| K8 | trust registry row for a CLI hop | `model-permissions.yaml:446-473` | prose note only | PARTIAL (adapter default `--tools ""`, `extra.allowed_tools` widens, no test) |

## Deferred / out of reach

- `cheval.py` and `providers/base.py` hunks are help-text/comment only; full-file review deferred (not changed functionally).
- Bridgebuilder `dist/` and `resources/*.generated.ts`: regenerated outputs; `.build-manifest.json` hashes and `model-config.yaml.checksum` verified against head files.
- `evals/fixtures/review-prs/SHA256SUMS`: only the two manifest rows in the PR are verifiable here (both OK).
