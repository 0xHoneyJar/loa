# Security Audit — PR: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

**Scope**: `head.diff` (3 files) — `.claude/adapters/loa_cheval/providers/base.py`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/loa-status.sh`.
**Audit type**: Codebase/PR audit (no sprint plan, beads DB, or `grimoires/loa/a2a/` present — none required per `AUDIT-INSTRUCTIONS.md`).

## Summary

The PR frames itself as a pure simplification/cleanup ("shorten... drops the mktemp guards... simplifies... argument handling"), but one of the three hunks is a **security-relevant narrowing of a credential-isolation control**, not a no-op refactor: it silently removes 4 of 8 entries from the headless-subprocess auth-var strip list, re-widening exactly the attack surface the function's own docstring says it "MUST" close (issues #879/#880). The other two files trade defensive error handling for terser code, which converts scoped-degradation failure modes into whole-process crashes (flatline-orchestrator.sh, under `set -euo pipefail`) or silently-swallowed caller errors (loa-status.sh).

## Findings

### [HIGH] Headless subprocess env scrub no longer strips auth-mode-selector vars — reopens #879/#880

**Location**: `head/.claude/adapters/loa_cheval/providers/base.py:472-478` (tuple), `head/.claude/adapters/loa_cheval/providers/base.py:481-504` (`build_headless_subprocess_env`)

`_HEADLESS_STRIPPED_AUTH_VARS` previously stripped 8 vars in two sub-classes: credentials (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`) and auth-mode-selectors (`GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC`). The diff (`head.diff:5-12`) deletes the four mode-selector entries from the tuple, and rewrites the docstring at `head/.claude/adapters/loa_cheval/providers/base.py:484-486` to only promise stripping "auth-class vars per `_HEADLESS_STRIPPED_AUTH_VARS`" — i.e. the docstring was edited to match the *narrowed* list rather than the list being restored to match the original docstring's stated guarantee ("both the credential sub-class... and the auth-mode-selector sub-class").

The comment directly above the tuple (`head/.claude/adapters/loa_cheval/providers/base.py:466-471`, unchanged by this PR) still states the intent this code exists to enforce: *"The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."* That statement is still true of the four removed vars, but they are no longer covered by the strip loop at `head/.claude/adapters/loa_cheval/providers/base.py:502-503`.

**Failure scenario**: The parent environment (CI runner, developer shell, a compromised dependency's `.env`, or any process whose env this codebase's subprocess-spawning callers inherit from) has `GOOGLE_GEMINI_BASE_URL` set. `build_headless_subprocess_env()` no longer removes it (it is absent from `_HEADLESS_STRIPPED_AUTH_VARS`), so the headless Gemini CLI subprocess inherits it and sends its request traffic — which can include repository content, diffs, or other prompt material being processed by the headless adapter — to an attacker-controlled base URL instead of Google's real endpoint. Independently, `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` / `GEMINI_CLI_USE_COMPUTE_ADC` leaking through lets an inherited env silently force the subprocess onto a different auth/billing/logging path (Vertex vs. Gemini API vs. ambient Application Default Credentials) than the one the caller believes it is using, with no `LOA_HEADLESS_KEEP_API_KEY=1` opt-in required — the very isolation guarantee the function exists to provide is now conditional on an env-var *sub-class* nobody asked to relax.

Neither `head.diff` nor the touched file contains any explanation for why the mode-selector vars are safe to stop stripping (no updated threat model, no note that #879/#880 no longer apply) — the PR description calls this a "shorten" of the scrub, not a scope change, which understates what happened.

**Standard**: [CWE-668: Exposure of Resource to Wrong Sphere](https://cwe.mitre.org/data/definitions/668.html); [OWASP A05:2021 – Security Misconfiguration](https://owasp.org/Top10/A05_2021-Security_Misconfiguration/).

**Remediation**: Restore the four auth-mode-selector entries to `_HEADLESS_STRIPPED_AUTH_VARS` (or, if the intent is genuinely to relax them, that must be a deliberate, reviewed decision documented in the code and ideally gated behind the existing `LOA_HEADLESS_KEEP_API_KEY=1` opt-out rather than made unconditional) and revert the docstring back to describing both sub-classes.

---

### [MEDIUM] `mktemp` failure in `vq-aggregate` now crashes the whole orchestrator instead of skipping one input

**Location**: `head/.claude/scripts/flatline-orchestrator.sh:576-581`

The removed guard (`head.diff:37-40`) previously caught `mktemp` failure, logged a warning, and `continue`d to the next input file — degrading gracefully by dropping just that voice's `verdict_quality` envelope. `flatline-orchestrator.sh:47` sets `set -euo pipefail`; with the guard gone, `tmp=$(mktemp ...)` returning non-zero (e.g. `/tmp` full, unwritable, or `TMPDIR` misconfigured) now terminates the entire script immediately inside the `for f in "${input_files[@]}"` loop, aborting verdict aggregation for every remaining input file and phase in the run, not just the one that hit the transient error.

**Standard**: [CWE-703: Improper Check or Handling of Exceptional Conditions](https://cwe.mitre.org/data/definitions/703.html).

**Remediation**: Restore the `if ! tmp=$(mktemp ...); then log ...; continue; fi` guard (or an equivalent explicit check) so a single bad temp-file allocation degrades one input rather than aborting the whole aggregation pass.

---

### [MEDIUM] `mktemp` failure building the arbiter prompt now crashes the run instead of skipping the phase

**Location**: `head/.claude/scripts/flatline-orchestrator.sh:2281-2283`

Same pattern as above: the deleted guard (`head.diff:49-52`) logged an error and `continue`d past just the current `phase`'s arbiter step. With `set -euo pipefail` active, a failing `mktemp` here now kills the process outright, and the subsequent `chmod 600 "$arbiter_prompt_file"` at line 2283 is unreachable on that failure path anyway (the script has already exited), so the removed guard was not dead weight — it was the only thing standing between one arbiter-input-directory problem and the loss of the entire Flatline arbitration run.

**Standard**: [CWE-703: Improper Check or Handling of Exceptional Conditions](https://cwe.mitre.org/data/definitions/703.html).

**Remediation**: Restore the guard, mirroring the previous `if ! arbiter_prompt_file=$(mktemp); then log "ERROR..."; continue; fi` behavior.

---

### [LOW] `loa-status.sh` now always emits ANSI color escapes, ignoring `NO_COLOR` and non-TTY output

**Location**: `head/.claude/scripts/loa-status.sh:29-35`

The removed `if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then ... else ... fi` branch (`head.diff:64-78`) made colors conditional on both the `NO_COLOR` convention and stdout being a terminal. The new code unconditionally sets `RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`NC` to their escape-sequence values. Any caller that pipes `loa-status.sh` output into a log file, another tool's parser, or a CI transcript now gets raw ANSI escape codes even when `NO_COLOR=1` is set or stdout is redirected, which can corrupt downstream text processing and violates the documented `NO_COLOR` opt-out users may depend on.

**Standard**: Relates to [CWE-116: Improper Encoding or Escaping of Output](https://cwe.mitre.org/data/definitions/116.html) (uncontrolled escape sequences reaching non-terminal consumers).

**Remediation**: Restore the `NO_COLOR`/`-t 1` conditional before setting the color variables.

---

### [LOW] Unknown-flag validation removed — typos are silently swallowed instead of failing fast

**Location**: `head/.claude/scripts/loa-status.sh:62-66` (removed validation previously followed the arg-parsing loop, calling `dx_unknown_flag` / printing usage and `exit 2`; see `head.diff:96-115`)

`UNKNOWN_ARGS` tracking and the subsequent check (`if [[ "$ECONOMY_MODE" != "true" ]] && [[ ${#UNKNOWN_ARGS[@]} -gt 0 ]]; then ... exit 2; fi`) were deleted. Now any unrecognized argument (e.g. a mistyped `--jscon` instead of `--json`) falls into the `*)` case at `head/.claude/scripts/loa-status.sh:62-65`, is appended to `ECONOMY_ARGS`, and — outside `--economy` mode — is silently discarded with no error and no usage message. A caller (human or an automation wrapper) that mistypes a flag now gets normal-looking status output instead of a clear `exit 2` failure, masking the mistake.

**Standard**: Relates to [CWE-253: Incorrect Check of Function Return Value](https://cwe.mitre.org/data/definitions/253.html) (class: silently ignored error condition) / general fail-fast principle.

**Remediation**: Restore the unknown-argument validation and `exit 2` behavior for non-economy-mode invocations.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 2 |

## Verdict

One HIGH finding (auth-mode-selector env vars no longer stripped from the headless subprocess environment, reopening the exact class of issue #879/#880 was closed for) is sufficient on its own to require changes before this PR merges — it re-widens a credential/routing-isolation boundary under the guise of a "shorten the env scrub" cleanup, with no accompanying justification, test, or threat-model update. The two MEDIUM findings each convert a previously-scoped degradation (skip one input / one phase) into a whole-process crash under `set -euo pipefail`, which is a meaningful reliability regression for the Flatline orchestrator even though it is not directly attacker-triggerable in the same way. The two LOW findings are UX/observability regressions in `loa-status.sh`.

**Recommendation**: Revert the four auth-mode-selector entries in `_HEADLESS_STRIPPED_AUTH_VARS` (or land that removal as its own reviewed, justified change) and restore the `mktemp` failure guards in `flatline-orchestrator.sh` before merging. The `loa-status.sh` color/flag-validation simplifications are lower priority but should be restored or explicitly re-justified.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":2},"ts":"2026-09-22T00:00:00Z"} -->
