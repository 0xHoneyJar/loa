# Security Audit Report

**PR**: `chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing`
**Audit type**: Ad-hoc PR audit (diff-only, no sprint/beads context)
**Files touched**: `.claude/adapters/loa_cheval/providers/base.py`, `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/loa-status.sh`

## Executive Summary

This PR presents itself as a pure simplification ("shorten... to credential variables only", "drops mktemp guards", "simplifies... flag parsing"), but one of the three changes silently reopens a previously-patched security control. `build_headless_subprocess_env()` in `base.py` was hardened (per its own docstring and comment, "closes issues #879 / #880") to strip both API-credential env vars *and* auth-mode-selector env vars from headless adapter subprocess environments, specifically because leaving the mode-selectors in place lets the wrapped CLI silently switch away from the intended OAuth-subscription auth path. This PR removes four of those nine stripped variables — precisely the mode-selector sub-class — while leaving the surrounding "MUST strip" comment intact and rewriting the docstring to no longer mention the distinction it used to warn about. This is the headline finding and should block merge as-is.

The other two files trade documented fail-soft error handling for terser code under `set -euo pipefail`, which converts what used to be a locally-contained, logged skip into an unconditional full-script abort on a transient `mktemp` failure — a correctness/availability regression, not a new attack surface, but a real behavior change that contradicts an adjacent code comment. The `loa-status.sh` changes are cosmetic/UX regressions (NO_COLOR support and unknown-flag validation removed) with no direct security impact.

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 2 |

## High Priority Issues

### H-1: Headless subprocess env scrub no longer strips Google auth-mode-selector variables, reopening issues #879/#880

**Component**: `head/.claude/adapters/loa_cheval/providers/base.py:472-478` (tuple definition), `head/.claude/adapters/loa_cheval/providers/base.py:484-486` (docstring rewrite), `head/.claude/adapters/loa_cheval/providers/base.py:502-503` (strip loop, unchanged logic — now iterates a shorter list)

**Description**: The pre-PR version of `_HEADLESS_STRIPPED_AUTH_VARS` (see `base/.claude/adapters/loa_cheval/providers/base.py:472-482`) contained nine entries in two documented sub-classes:

```
"ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
"GOOGLE_APPLICATION_CREDENTIALS",              # credential sub-class
"GOOGLE_GENAI_USE_VERTEXAI", "GOOGLE_GENAI_USE_GCA",
"GOOGLE_GEMINI_BASE_URL", "GEMINI_CLI_USE_COMPUTE_ADC",   # auth-mode-selector sub-class
```

The base docstring (`base/.claude/adapters/loa_cheval/providers/base.py:488-494`) explicitly explained *why* both sub-classes must be stripped: stripping only the credential sub-class is insufficient, because the mode-selector vars (`GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GEMINI_CLI_USE_COMPUTE_ADC`) can redirect the wrapped Gemini CLI to a different auth backend (Vertex AI / Google Cloud auth / Compute Engine ADC) entirely independent of API keys — defeating the headless adapter's isolation contract just as effectively as leaking a key would.

This PR deletes exactly those four mode-selector entries (`head.diff:5-11`) and rewrites the docstring to drop the explanation of the two sub-classes (`head.diff:16-26`), leaving the class-level comment directly above the tuple (`head/.claude/adapters/loa_cheval/providers/base.py:466-471`, unchanged by the diff) still claiming "Auth-class env vars that headless adapters MUST strip from their subprocess environment by default" — now factually inaccurate, since the mode-selectors are no longer in that list. The function-level comment `# Headless adapter subprocess env helper (closes issues #879 / #880)` at line 463, and `Closes issues #879 / #880` at line 493, are also left unchanged, even though the change reopens whatever behavior those issues originally described for the mode-selector vars.

**Impact**: Any parent process environment that carries `GOOGLE_GENAI_USE_VERTEXAI=true`, `GOOGLE_GENAI_USE_GCA=1`, `GOOGLE_GEMINI_BASE_URL=<url>`, or `GEMINI_CLI_USE_COMPUTE_ADC=1` will now have those variables silently forwarded into every headless Gemini-adapter subprocess, even without `LOA_HEADLESS_KEEP_API_KEY=1` set. A headless run that is supposed to be isolated to the OAuth-subscription auth path can instead be redirected to Vertex AI, an operator-supplied base URL, or Compute Engine ADC-derived credentials — none of which the operator opted into for this specific subprocess. This is exactly the failure mode the original fix (issues #879/#880) closed for the credential-key sub-class; the mode-selector sub-class is equally capable of defeating the "never inherit subprocess env" contract stated at `head/.claude/adapters/loa_cheval/providers/base.py:497-499`.

**PoC**: With this PR applied, an environment where `GOOGLE_GENAI_USE_GCA=1` is exported (e.g., set globally in a shared CI runner or dev shell for an unrelated interactive gemini session) will leak into `build_headless_subprocess_env()`'s output unchanged, because it is no longer in `_HEADLESS_STRIPPED_AUTH_VARS`:
```python
os.environ["GOOGLE_GENAI_USE_GCA"] = "1"
env = build_headless_subprocess_env()
assert "GOOGLE_GENAI_USE_GCA" not in env   # FAILS post-PR; passed pre-PR
```

**Remediation**: Restore the four removed entries to `_HEADLESS_STRIPPED_AUTH_VARS` (`head/.claude/adapters/loa_cheval/providers/base.py:472-478`), and restore or replace the docstring text that explains the two sub-classes so a future edit doesn't repeat this silent narrowing. If there is a genuine reason to stop stripping mode-selectors (e.g., a design decision that headless adapters should now inherit auth-mode routing), that must be an explicit, reviewed decision documented in the PR description and the comment block, not folded into a "shorten the env scrub" chore commit with no mention of the behavior change.

**References**: CWE-923 (Improper Restriction of Communication Channel to Intended Endpoints), OWASP A05:2021 (Security Misconfiguration — unintended credential/auth-path inheritance).

## Medium Priority Issues

### M-1: Removed `mktemp` failure guard converts a documented fail-soft path into a full-script abort

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:577`

**Description**: `aggregate_and_write_final_consensus()` is documented immediately above (`head/.claude/scripts/flatline-orchestrator.sh:552-554`) as: *"Fail-soft: missing python module / empty input / aggregator error logs a warning but does NOT abort the orchestrator. The final consensus calculation runs regardless."* The pre-PR code enforced that contract for `mktemp` failures too:
```bash
if ! tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json"); then
    log "WARNING: mktemp failed for vq-input ($(date)) — skipping verdict-quality envelope for $f"
    continue
fi
```
The PR replaces this with a bare `tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")` (`head/.claude/scripts/flatline-orchestrator.sh:577`). The script runs under `set -euo pipefail` (confirmed at the top of the sibling `loa-status.sh`; `flatline-orchestrator.sh` is part of the same script family and the removed `if !` guards were the only thing preventing `set -e` from firing here). If `mktemp` fails (e.g., `/tmp` full, permissions issue, `TEMP_DIR` pointing at a non-writable path), the bare assignment's non-zero exit status now trips `set -e` and terminates the entire orchestrator run — not just this one voice's verdict-quality aggregation — directly contradicting the fail-soft guarantee stated three lines above the loop.

**Impact**: A transient, single-file temp-directory problem escalates from "one voice's verdict-quality envelope is skipped, orchestration continues" to "the whole Flatline review aborts," which is a meaningful availability regression for an autonomous/unattended workflow (Run Mode) where nobody is present to notice and retry.

**Remediation**: Restore the `if ! tmp=$(mktemp ...); then log WARNING; continue; fi` guard, or wrap the call in a form that doesn't trip `set -e` (`tmp=$(mktemp ...) || { log ...; continue; }`).

**References**: CWE-755 (Improper Handling of Exceptional Conditions).

### M-2: Removed `mktemp` failure guard for the arbiter prompt file has the same `set -e` full-abort effect

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:2282`

**Description**: Same pattern as M-1, in the Round-Robin Arbiter block (cycle-070 FR-4). Pre-PR:
```bash
if ! arbiter_prompt_file=$(mktemp); then
    log "ERROR: mktemp failed for arbiter prompt — skipping arbiter step for $phase"
    continue
fi
chmod 600 "$arbiter_prompt_file"
```
Post-PR (`head/.claude/scripts/flatline-orchestrator.sh:2282-2283`):
```bash
arbiter_prompt_file=$(mktemp)
chmod 600 "$arbiter_prompt_file"
```
As in M-1, under `set -e` a `mktemp` failure now aborts the whole orchestrator run instead of skipping arbitration for the current phase and continuing (the previously intended behavior per the removed `ERROR:` log message's own wording, "skipping arbiter step for $phase"). Additionally, note that even without `set -e`, if `mktemp` ever printed nothing to stdout while still returning 0 in some exotic environment, `chmod 600 ""` would fail on an empty path — the old code avoided reaching `chmod` at all in the failure case, the new code executes it unconditionally.

**Impact**: Same availability class as M-1, scoped to disputed/blocker arbitration during autonomous Flatline runs.

**Remediation**: Restore the guard, matching the pattern used elsewhere.

**References**: CWE-755.

## Low Priority Issues

### L-1: `loa-status.sh` no longer respects `NO_COLOR` or non-TTY output, always emitting ANSI escape codes

**Component**: `head/.claude/scripts/loa-status.sh:29-35`

**Description**: Pre-PR, color variables were only set to ANSI codes when `NO_COLOR` was unset *and* stdout was a TTY (`base/.claude/scripts/loa-status.sh:26-40`); otherwise they were set to empty strings. Post-PR, the variables are unconditionally assigned ANSI escape sequences (`head/.claude/scripts/loa-status.sh:30-35`), regardless of `NO_COLOR` or whether stdout is a pipe/file. This breaks the documented `NO_COLOR` convention and will inject raw escape sequences into any redirected/piped output of `loa-status.sh` (log files, CI captures, output consumed by other tooling), including in `--json` mode if any of these variables happen to be interpolated into non-JSON diagnostic lines printed alongside the JSON.

**Impact**: Low — cosmetic corruption of logs/non-interactive output rather than an exploitable vulnerability, but it is a real regression against an accessibility/tooling convention the codebase previously honored.

**Remediation**: Restore the `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]` conditional.

**References**: N/A (tooling convention, not a CWE).

### L-2: Unknown CLI flags to `loa-status.sh` are now silently swallowed instead of rejected

**Component**: `head/.claude/scripts/loa-status.sh:62-65`

**Description**: Pre-PR, an unrecognized argument outside `--economy` mode triggered `dx_unknown_flag` (or a fallback `echo ... >&2`) and `exit 2` (`base/.claude/scripts/loa-status.sh:96-113`). Post-PR, the `UNKNOWN_ARGS` tracking array and the post-loop validation block are removed entirely (`head.diff:88-115`); any unrecognized argument is now unconditionally appended to `ECONOMY_ARGS` and otherwise ignored when not in `--economy` mode, so the script exits 0 having silently done nothing with the typo'd flag.

**Impact**: Low — a usability/DX regression (a typo like `--jsn` now silently no-ops instead of erroring), not a security issue, but it removes existing input validation without a stated reason and could mask automation/scripting bugs in CI.

**Remediation**: Restore the `UNKNOWN_ARGS` tracking and the `dx_unknown_flag`/usage-and-exit-2 fallback for non-economy-mode unknown arguments.

**References**: N/A.

## Security Checklist Status

- [x] Secrets & Credentials — **FAILS**: see H-1 (auth-mode-selector env vars no longer scrubbed from headless subprocess env)
- [x] Error Handling — **FAILS**: see M-1, M-2 (fail-soft contract broken by `set -e` interaction)
- [ ] Input Validation — **regressed**: see L-2 (not security-critical here, but weakened)
- [x] Supply Chain / Infra — N/A, no dependency or infra changes in this diff
- [x] API Security — N/A, no API surface touched

## Threat Model Summary

The primary trust boundary at risk is the headless-adapter subprocess environment isolation contract ("never inherit subprocess env," `base.py:497-499`). This PR narrows that boundary without acknowledging it in the commit message, which is the most concerning aspect independent of the technical severity: a reviewer skimming "shorten the headless env scrub... to credential variables only" would reasonably assume this is a no-op refactor, not a scope reduction of a security control tied to two closed issues.

## Verdict

**CHANGES_REQUIRED**

Required before merge:
1. Restore the four auth-mode-selector entries to `_HEADLESS_STRIPPED_AUTH_VARS` (H-1), or provide an explicit, reviewed justification for removing them and update the now-inconsistent comments accordingly.
2. Restore the `mktemp` failure guards in `flatline-orchestrator.sh` (M-1, M-2) so the documented fail-soft behavior holds under `set -e`.
3. (Recommended, not blocking) Restore `NO_COLOR`/TTY detection and unknown-flag validation in `loa-status.sh` (L-1, L-2).

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":2},"sprint_id":"n/a","ts":"2026-09-21T00:00:00Z"} -->
