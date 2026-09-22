# PR Review: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**Scope:** `head.diff` against `base/` → `head/`, 3 files touched

---

## Overall Assessment

The stated intent is a pure simplification/cleanup ("shorten... scrub, drop mktemp guards, simplify flag parsing"), but the diff is not behavior-preserving. One change (`base.py`) directly reopens a previously-closed security/correctness bug by shrinking a documented auth-var strip-list. The other two changes (`flatline-orchestrator.sh`, `loa-status.sh`) trade explicit, diagnosed error handling for either an uncontrolled `set -e` abort or silently-dropped input validation. This is a "simplification" PR that removes real behavior rather than restating it more concisely — a direct violation of the "never simplify away input validation / data-loss handling" floor.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security/Correctness — headless auth-mode-selector vars no longer stripped

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/base.py:472` — headless Gemini subprocess calls can silently fall back to API/Vertex auth mode instead of OAuth-subscription auth, defeating the headless adapter's contract.

**File:** `head/.claude/adapters/loa_cheval/providers/base.py:472-478`

**Issue:** `_HEADLESS_STRIPPED_AUTH_VARS` dropped `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, and `GEMINI_CLI_USE_COMPUTE_ADC` from the strip list. The unmodified module comment directly above the tuple (`head/.claude/adapters/loa_cheval/providers/base.py:466-471`) still states:

> "The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."

That comment was written precisely to justify stripping the *auth-mode-selector* sub-class, not only literal credential vars — the base file's own (now-shortened) docstring used to say this explicitly: "both the credential sub-class (e.g., GOOGLE_API_KEY) and the auth-mode-selector sub-class (e.g., GOOGLE_GENAI_USE_VERTEXAI)" (see `base/.claude/adapters/loa_cheval/providers/base.py:492-496`, removed by this PR). The docstring text was trimmed along with the vars, but the code's actual job — "never let CLI fall back to API mode" — is now only half done for Gemini: `GOOGLE_API_KEY`/`GEMINI_API_KEY`/`GOOGLE_APPLICATION_CREDENTIALS` are still stripped, but `GOOGLE_GENAI_USE_VERTEXAI=true` (or `GOOGLE_GEMINI_BASE_URL` pointing at an arbitrary endpoint, or `GEMINI_CLI_USE_COMPUTE_ADC=1`) set in the parent process now passes straight through to the headless subprocess, unconditionally, even without `LOA_HEADLESS_KEEP_API_KEY=1` opt-in.

**Why This Matters:** The function's own docstring says it "Closes issues #879 / #880 (and symmetric for codex / gemini)" — this PR reopens that class of bug for the Gemini provider specifically. `GOOGLE_GEMINI_BASE_URL` passthrough is also a redirect vector: if that var is set anywhere in the parent environment (CI, a misconfigured shell profile, or a compromised upstream step), headless Gemini calls would silently route to a different base URL than intended, with no log or error — a same-class risk to the credential vars this function exists to strip.

**Required Fix:** Restore the four auth-mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS` (or, if there is a genuine reason a subset should now pass through, restore the two-subclass docstring language and state explicitly and separately why each dropped var is now considered safe to inherit — this needs a deliberate decision, not a line-count trim).

---

### 2. Correctness — dropped `mktemp` failure guards turn graceful skip into full-script abort

- **HIGH** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:577` — under `set -euo pipefail` (line 47), a bare `tmp=$(mktemp ...)` failure now aborts the entire orchestrator run instead of skipping one verdict-quality envelope.

**File:** `head/.claude/scripts/flatline-orchestrator.sh:577` and `head/.claude/scripts/flatline-orchestrator.sh:2282`

**Issue:** Both call sites previously wrapped the `mktemp` assignment in `if ! tmp=$(mktemp ...); then log "WARNING/ERROR: ..."; continue; fi`. Because the assignment sat inside an `if` condition, `set -e` did not apply, and a transient `mktemp` failure (e.g. `/tmp` full or unwritable) produced a clear log line and let the loop continue with the next input file / phase. The PR removes the guard and leaves a bare `tmp=$(mktemp ...)` (line 577, inside a `for f in "${input_files[@]}"` loop) and `arbiter_prompt_file=$(mktemp)` (line 2282, inside an `if [[ "$disputed_count" -gt 0 ... ]]` block reached per-phase). Since the file has `set -euo pipefail` active (`head/.claude/scripts/flatline-orchestrator.sh:47`) and these are now simple (non-conditional) command substitutions, a `mktemp` failure triggers immediate script exit with only bash's generic error — no "skipping verdict-quality envelope for $f" / "skipping arbiter step for $phase" diagnostic, and no chance to finish processing the remaining files/phases.

**Why This Matters:** This is exactly the "never simplify away data-loss handling" case the project's own Karpathy principles call out. The prior behavior degraded gracefully (partial consensus without one envelope, or without one arbiter round) with a diagnosable log line; the new behavior hard-kills a consensus/arbitration run over a transient filesystem hiccup, with a much less actionable error, and does so silently as far as any caller-level continuation logic is concerned.

**Required Fix:** Restore the `if ! tmp=$(mktemp ...); then log ...; continue; fi` guards at both sites (or an equivalent explicit check), so `mktemp` failures degrade the same way they did before.

---

## Observations

### 1. `loa-status.sh` — unconditional ANSI colors regressions

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:29-35` — color codes (`RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`NC`) are now assigned unconditionally, whereas `base/.claude/scripts/loa-status.sh:26-40` only assigned real escape sequences when `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]`, otherwise blanking them.

**File:** `head/.claude/scripts/loa-status.sh:29-35` (definitions), used at e.g. `head/.claude/scripts/loa-status.sh:188,194,200-206,233-234,241,411,432,505,516,547`

**Suggestion:** Any invocation with stdout redirected to a file/log, piped into another tool, or run with `NO_COLOR=1` set (a widely-respected convention, https://no-color.org/) will now emit raw `\033[...]` escape sequences into non-interactive output. This is a real, user-visible regression, not just cosmetic — logs and piped consumers of the human-readable status output get corrupted with control codes. Restore the `[[ -t 1 ]]` / `NO_COLOR` gate, or gate on `[[ "$JSON_OUTPUT" != "true" ]]` at minimum plus the tty check.

**Benefit:** Preserves `NO_COLOR` compliance and keeps piped/redirected output clean, matching prior behavior.

### 2. `loa-status.sh` — silently dropped unknown-flag validation

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:62-65` — unrecognized flags outside `--economy` mode are now silently absorbed into `ECONOMY_ARGS` (which is never consulted when `ECONOMY_MODE=false`) instead of producing a usage error and `exit 2`.

**File:** `head/.claude/scripts/loa-status.sh:62-65`

**Suggestion:** `base/.claude/scripts/loa-status.sh:96-115` explicitly detected unknown args when not in economy mode, printed a usage line (via `dx_unknown_flag` if available, else a plain error) and exited 2. That whole block, plus the `UNKNOWN_ARGS` array that fed it, was removed. A typo like `--jso` or `--eco` now runs the default status path with no warning at all instead of failing fast — this is input validation at a CLI trust boundary being simplified away, which the project's own Karpathy principles explicitly disallow doing without justification.

**Benefit:** Restoring the unknown-flag check (or at minimum re-adding a warning) prevents silent misuse of the script from going unnoticed, especially in automation/CI contexts where a swallowed typo produces a "successful" but wrong invocation.

---

## Security Checklist

- [ ] No hardcoded secrets or credentials — N/A, no secrets introduced
- [ ] Input validation and sanitization present — **regressed**, see Observation 2
- [ ] Authentication/authorization correct — **regressed**, see Changes Required #1 (auth-mode fallback for headless Gemini)
- [x] No SQL/XSS injection vulnerabilities
- [x] Dependencies secure (no known CVEs)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The three changes are individually small and easy to review in isolation.
- `loa-status.sh`'s `--economy` short-circuit and JSON-output logic are untouched and still correct.

**Areas for Improvement:**
- Each of the three hunks removes a documented safety/behavior guarantee (an auth strip-list closing a named issue, an explicit `mktemp`-failure recovery path, tty/`NO_COLOR` detection, and CLI flag validation) in the name of "shortening" — none of these are restatements, they are behavior deletions. Per this repo's own Karpathy principles ("never simplify away: input validation at trust boundaries, data-loss handling, security... anything explicitly requested"), each removal needs either a one-line justification of why the removed behavior is no longer needed, or should be reverted.

---

## Next Steps

1. Restore the four auth-mode-selector vars in `_HEADLESS_STRIPPED_AUTH_VARS` (`base.py`), or provide an explicit justification per var.
2. Restore the `mktemp` failure guards at both call sites in `flatline-orchestrator.sh`.
3. Restore `NO_COLOR`/tty-aware color gating and the unknown-flag validation in `loa-status.sh`.
4. Re-submit for review.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":0},"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
