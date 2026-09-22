# Review: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

## Overall Assessment

This PR bills itself as a "shorten/simplify" chore but each of its three hunks removes
behavior that was added deliberately and for a stated reason (closing specific issues,
handling `NO_COLOR`, catching `mktemp` failure, rejecting unknown flags). None of the
removed logic is dead code or speculative — each piece traces to a real, documented
requirement. This is not simplification; it's a regression dressed as cleanup.

**Verdict: CHANGES_REQUIRED.**

## Critical Issues

### 1. Silently reintroduces the bug that issues #879/#880 fixed for Gemini

`head/.claude/adapters/loa_cheval/providers/base.py:478` removes four vars from
`_HEADLESS_STRIPPED_AUTH_VARS`:

```
"GOOGLE_GENAI_USE_VERTEXAI",
"GOOGLE_GENAI_USE_GCA",
"GOOGLE_GEMINI_BASE_URL",
"GEMINI_CLI_USE_COMPUTE_ADC",
```

The base-state docstring (`base/.claude/adapters/loa_cheval/providers/base.py:489-491`)
explains exactly why these were present: they are the "auth-mode-selector sub-class"
that, if left in a headless subprocess's env, cause the Gemini CLI to route through
Vertex/API mode instead of its OAuth-subscription path — the precise failure this
helper exists to prevent. The surrounding comment block
(`head/.claude/adapters/loa_cheval/providers/base.py:463`, `:493`) still reads
"closes issues #879 / #880 (and symmetric for codex / gemini)" — that claim is now
false for Gemini: any parent process with `GOOGLE_GENAI_USE_VERTEXAI=1` (or the other
three) set will leak straight into the headless adapter's subprocess and silently
switch Gemini out of OAuth mode again.

**Fix**: restore the four mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS`, or if
there's a genuine reason to stop stripping them, update the "closes #879/#880" claim
and get explicit sign-off that the Gemini-specific regression is intentional.

### 2. Removing `mktemp` failure handling turns a local degrade into a full-script abort

`head/.claude/scripts/flatline-orchestrator.sh:577` and `:2282-2283` drop the
`if ! tmp=$(mktemp ...); then log WARNING/ERROR; continue; fi` guards. The script runs
under `set -euo pipefail` (`head/.claude/scripts/flatline-orchestrator.sh:47`), so this
isn't a no-op refactor: previously a `mktemp` failure (full `/tmp`, restrictive
sandbox, `TEMP_DIR` misconfigured) caused the loop to skip just that one input file
(line 577, verdict-quality aggregation) or that one phase (line 2282, arbiter step)
with a logged warning and continued execution. Now the same failure trips `set -e` and
kills the entire orchestrator run — an unrelated phase's arbiter step failing to
`mktemp` now takes down verdict aggregation for phases that already succeeded.

**Fix**: keep the explicit failure branches; if the goal is fewer lines, at minimum
preserve the `continue`-on-failure behavior (a one-line `tmp=$(mktemp ...) || { log ...; continue; }` still nets a line-count win without losing resilience).

## Non-Critical Improvements

### 3. `NO_COLOR` / non-TTY detection removed from `loa-status.sh`

`head/.claude/scripts/loa-status.sh:29-35` hardcodes the ANSI color variables
unconditionally, replacing the base version's
`if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then ... else ... fi` guard
(`base/.claude/scripts/loa-status.sh:26-40`). Color codes are only interpolated on the
human-readable (non-JSON) path (e.g. `head/.claude/scripts/loa-status.sh:505`,
`:516`), so this doesn't corrupt `--json` output, but it does mean: piping
`loa-status.sh` to a file/log/CI artifact, or running with `NO_COLOR=1` set (a
convention this repo otherwise respects — see the original guard), now embeds raw
`\033[...]` escape sequences in the captured text. Any downstream `grep`/diff/log
viewer that isn't a color-aware terminal now sees garbage.

**Fix**: restore the `NO_COLOR`/`-t 1` guard.

### 4. Unknown-flag validation silently dropped

`head/.claude/scripts/loa-status.sh:64` still pushes unrecognized args into
`ECONOMY_ARGS`, but the code that previously surfaced them as an error
(`base/.claude/scripts/loa-status.sh:74-84`: build `USAGE_LINE`, source
`dx-utils.sh`, call `dx_unknown_flag` or fall back to a manual "Unknown option"
message, then `exit 2`) is gone entirely, along with the `UNKNOWN_ARGS` array that fed
it. Outside `--economy` mode, a typo'd flag (e.g. `--jsonn`) is now silently
swallowed — `loa-status.sh` runs as if no flag was passed and exits 0, instead of
failing fast with a usage message. This directly undoes the "unknown flag → clear
error" pattern the codebase deliberately built via `dx_unknown_flag` (see
`.claude/skills/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools`), which
matters even more for a CLI driven mostly by agents than by humans, since a swallowed
typo is a silent no-op that only surfaces as "the status looks wrong" much later.

**Fix**: restore the `UNKNOWN_ARGS` tracking and `dx_unknown_flag`/usage-error exit.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/adapters/loa_cheval/providers/base.py:478` — stripped-vars list no
   longer matches the "closes #879/#880" claim in the same file's comments; regresses
   Gemini auth-mode isolation specifically.
2. `head/.claude/scripts/flatline-orchestrator.sh:577` — `mktemp` failure now aborts
   the whole `set -euo pipefail` script instead of degrading one input file.
3. `head/.claude/scripts/flatline-orchestrator.sh:2282-2283` — same class of issue for
   the arbiter-prompt tempfile; failure now kills the run instead of skipping one
   phase's arbiter step.
4. `head/.claude/scripts/loa-status.sh:29-35` — `NO_COLOR` and TTY detection dropped,
   reintroducing ANSI codes into non-terminal output.
5. `head/.claude/scripts/loa-status.sh:64` — unknown flags no longer rejected; typos
   silently no-op instead of exiting 2.

### Assumptions Challenged
- **Assumption**: The engineer appears to have assumed these were "extra ceremony"
  additions that could be trimmed without changing behavior for the common case.
- **Risk if wrong**: All five removals are common-case-invisible and only manifest
  under specific conditions (Vertex-mode env vars present, `/tmp` exhaustion, piped
  output, or a mistyped flag) — exactly the conditions the removed code was written to
  handle. "It still works in my manual test" is not evidence these paths are unused.
- **Recommendation**: Restore the removed guards; if the intent really is to drop
  `NO_COLOR` support or unknown-flag rejection as a product decision, that should be a
  stated, reviewed decision — not an incidental line-count reduction folded into an
  unrelated "shorten mktemp handling" PR.

### Alternatives Not Considered
- **Alternative**: If the goal was genuinely to reduce line count/complexity, the
  `mktemp` guards could have collapsed to `tmp=$(mktemp ...) || { log ...; continue; }`
  (one line each) rather than deleting the failure handling outright, and the color
  block could have stayed a 2-branch `if`/`else` (it already was one — nothing to
  simplify there without dropping the feature).
- **Tradeoff**: The one-liner guard keeps identical behavior at effectively the same
  line count as what was removed; the PR gets none of its stated "shorten" benefit by
  deleting the checks instead.
- **Verdict**: Current approach should be reconsidered — none of the three files
  needed a behavior change to get shorter.

## Previous Feedback Status
N/A — no prior `engineer-feedback.md` exists for this PR (no sprint context provided).

## Next Steps
1. Restore the four Gemini auth-mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS`
   in `base.py`, or explicitly justify and re-document their removal against
   issues #879/#880.
2. Restore `mktemp`-failure handling in `flatline-orchestrator.sh` (both call sites),
   even in a minimized one-line form.
3. Restore `NO_COLOR`/TTY-aware color gating in `loa-status.sh`.
4. Restore unknown-flag rejection (`UNKNOWN_ARGS` + `dx_unknown_flag`/usage exit) in
   `loa-status.sh`.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":0,"medium":2,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
