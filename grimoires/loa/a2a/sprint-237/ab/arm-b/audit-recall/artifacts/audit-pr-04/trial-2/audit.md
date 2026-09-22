# Security Audit — PR: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

## Scope

This PR touches three files:

- `.claude/adapters/loa_cheval/providers/base.py` — headless subprocess env-scrub allowlist
- `.claude/scripts/flatline-orchestrator.sh` — `mktemp` error handling in two call sites
- `.claude/scripts/loa-status.sh` — colour setup and CLI argument parsing

No sprint plan, beads DB, or `grimoires/loa/a2a/` implementation report exists for this change; this audit is based solely on `PR.md`, `head.diff`, `base/`, and `head/` as provided.

## Findings

### 1. HIGH — Headless subprocess env scrub no longer strips auth-mode-selector vars, defeating the documented headless-isolation control

`head/.claude/adapters/loa_cheval/providers/base.py:472-477`

```python
_HEADLESS_STRIPPED_AUTH_VARS: tuple = (
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
)
```

The diff removes four entries from this tuple: `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC`. The surrounding module comment (`base.py:466-471`, unchanged by this PR) states the design intent explicitly:

> "Auth-class env vars that headless adapters MUST strip from their subprocess environment by default. The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."

The pre-PR docstring for `build_headless_subprocess_env` (removed by this diff, visible in `base/.claude/adapters/loa_cheval/providers/base.py`) made the two sub-classes explicit: "both the credential sub-class (e.g., `GOOGLE_API_KEY`) and the auth-mode-selector sub-class (e.g., `GOOGLE_GENAI_USE_VERTEXAI`)". This PR removes the auth-mode-selector sub-class from the stripped set entirely, and rewrites the docstring (`head/.claude/adapters/loa_cheval/providers/base.py:484-486`) to erase that distinction ("remove auth-class vars per `_HEADLESS_STRIPPED_AUTH_VARS`"), masking the behavior change as a wording simplification rather than a functional one.

**Failure scenario:** `build_headless_subprocess_env()` (`head/.claude/adapters/loa_cheval/providers/base.py:481-503`) is used to build the env for headless Gemini CLI subprocess invocations. If `GOOGLE_GEMINI_BASE_URL` is set in the parent process — e.g. via a compromised CI env, an inherited shell profile, or a malicious `.env` sourced before Loa runs — it is now passed through unstripped to the headless subprocess. The Gemini CLI will send its requests (including document/prompt content passed for review) to that attacker-controlled base URL instead of Google's endpoint, exfiltrating the review content and any bearer material the CLI attaches to the request. Likewise `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` / `GEMINI_CLI_USE_COMPUTE_ADC` being inherited silently switches the auth backend the headless subprocess uses, again "defeating the headless adapter's purpose" per the code's own stated threat model (closing issues #879/#880, referenced at `head/.claude/adapters/loa_cheval/providers/base.py:462,491`) — this is exactly the failure mode those issues were opened to close.

No tests reference `_HEADLESS_STRIPPED_AUTH_VARS` or `build_headless_subprocess_env` anywhere in the repository (confirmed via search), so this regression is not caught mechanically.

CWE reference: [CWE-668: Exposure of Resource to Wrong Sphere](https://cwe.mitre.org/data/definitions/668.html) (subprocess inherits environment-controlled routing/auth data outside its intended trust boundary); also relevant: [CWE-441: Unintended Proxy or Intermediary ('Confused Deputy')](https://cwe.mitre.org/data/definitions/441.html) for the base-URL redirection case.

**Remediation:** Restore the four removed entries to `_HEADLESS_STRIPPED_AUTH_VARS`, or justify in the PR description why the auth-mode-selector sub-class no longer needs stripping (e.g. if the CLI itself changed to ignore these vars in headless mode) and add a regression test asserting `build_headless_subprocess_env()` strips all of them by default.

### 2. MEDIUM — Removing `mktemp` failure guards turns a per-item skip into a full-script abort under `set -euo pipefail`

`head/.claude/scripts/flatline-orchestrator.sh:577` and `head/.claude/scripts/flatline-orchestrator.sh:2282`

```bash
tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")
```
```bash
arbiter_prompt_file=$(mktemp)
```

The file sets `set -euo pipefail` at `head/.claude/scripts/flatline-orchestrator.sh:47`. The pre-PR code (visible in `base/.claude/scripts/flatline-orchestrator.sh`) explicitly guarded both `mktemp` calls with `if ! tmp=$(mktemp ...); then log "WARNING..."; continue; fi`, so a transient `mktemp` failure (full `/tmp`, permission issue, restrictive `TMPDIR`) logged a warning and skipped only that one verdict-quality envelope or arbiter step, leaving the rest of the Flatline consensus run to complete. With the guard removed, a single `mktemp` failure now propagates as an unhandled command failure under `set -e` and aborts the entire orchestrator process — turning a recoverable single-item degradation into termination of the whole review/audit pipeline run.

**Failure scenario:** In a CI runner or shared `/tmp` where disk fills up or a `TMPDIR` policy briefly rejects file creation (e.g. concurrent job contention, quota), the Flatline consensus aggregation step for one document aborts the entire run instead of degrading gracefully and completing the rest, which is a worse availability posture than before, especially since Flatline is itself a security-relevant gate (feeds `LOA-VERDICT` decisions).

CWE reference: [CWE-755: Improper Handling of Exceptional Conditions](https://cwe.mitre.org/data/definitions/755.html).

**Remediation:** Restore the `if ! tmp=$(mktemp ...); then log ...; continue; fi` guards at both call sites (or an equivalent explicit check), since `set -e` makes silent hard-fail the default behavior once the guard is removed.

### 3. LOW — `NO_COLOR` / non-TTY detection removed; ANSI escapes now always emitted

`head/.claude/scripts/loa-status.sh:29-34`

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
```

The removed `if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then ... else ... fi` guard (visible in `base/.claude/scripts/loa-status.sh`) meant colour codes were only emitted to an interactive terminal and were blank otherwise (respecting the `NO_COLOR` convention and avoiding escape sequences leaking into piped/redirected output, logs, or files). Now ANSI escapes are unconditionally emitted regardless of destination or the `NO_COLOR` env var. This is not itself an injection vector (the values are fixed literals, not attacker-influenced), but any downstream consumer of `loa-status.sh` output that scrapes or parses stdout (log aggregators, other scripts, terminal-unaware CI viewers) will now see raw escape sequences mixed into the text, which can corrupt naive parsers or terminal-replay logs.

CWE reference: [CWE-116: Improper Encoding or Escaping of Output](https://cwe.mitre.org/data/definitions/116.html) (best-fit; this is an output-hygiene regression rather than an exploitable vulnerability).

**Remediation:** Restore the `NO_COLOR`/`-t 1` guard, or at minimum gate colour output on `-t 1` so redirected/piped output stays escape-free.

### 4. LOW — Unknown CLI flags to `loa-status.sh` are now silently swallowed instead of erroring

`head/.claude/scripts/loa-status.sh:62-65`

```bash
*)
  # In --economy mode, forward unknown args to the roll-up tool.
  ECONOMY_ARGS+=("$arg")
  ;;
```

The removed post-loop block (visible in `base/.claude/scripts/loa-status.sh`) rejected unrecognized flags with `exit 2` and a usage message when not in `--economy` mode (via `dx_unknown_flag` or a plain fallback). After this change, any unrecognized argument passed outside `--economy` mode is captured into `ECONOMY_ARGS` and then silently discarded (that array is only consumed inside the `--economy` branch). A caller that mistypes a flag (e.g. `--jso`) gets no error and no indication their flag was ignored — this is a correctness/UX regression rather than a security hole, since `loa-status.sh` only reads local state and does not execute the unknown argument as code, but it removes a defense against operator error in scripts/hooks that construct this command line programmatically.

CWE reference: [CWE-392: Missing Report of Error Condition](https://cwe.mitre.org/data/definitions/392.html).

**Remediation:** Restore the unknown-flag validation for the non-`--economy` path.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 2 |

## Verdict

One HIGH-severity finding (headless auth-mode-selector env vars no longer stripped, undermining the documented headless-isolation guarantee from issues #879/#880) and one MEDIUM (removal of `mktemp` error guards causing full-script abort instead of graceful per-item skip under `set -e`) are present. Per the one-way rule, critical+high > 0 forces changes required.

**CHANGES_REQUIRED**

Immediate (24h): restore the four auth-mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS` (Finding 1) and restore the `mktemp` failure guards in `flatline-orchestrator.sh` (Finding 2).
Short-term (1wk): restore `NO_COLOR`/TTY detection and unknown-flag validation in `loa-status.sh` (Findings 3–4), and add a regression test asserting `build_headless_subprocess_env()` strips the full auth-class + auth-mode-selector var set by default.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":2},"ts":"2026-09-22T00:00:00Z"} -->
