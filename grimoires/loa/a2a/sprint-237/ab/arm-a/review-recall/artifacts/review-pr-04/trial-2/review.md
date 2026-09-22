# Review: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

## Overall Assessment

This PR is framed as a pure "shorten/simplify" chore across three files, but at least two of the three hunks are **behavior changes disguised as cleanup**, not simplifications that preserve semantics. One removes security-relevant entries from an auth-var stripping list; the other removes error-recovery around `mktemp` in a script running under `set -euo pipefail`, which changes a graceful degrade into a hard crash. Neither is safe to land as "chore." Changes required.

## Critical Issues

### 1. Auth-mode-selector env vars silently un-stripped from headless subprocess env — reopens issues #879/#880

`head/.claude/adapters/loa_cheval/providers/base.py:472-478`

```python
_HEADLESS_STRIPPED_AUTH_VARS: tuple = (
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
)
```

The base version stripped four additional vars: `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC` (`base/.claude/adapters/loa_cheval/providers/base.py:478-481`). The module comment directly above the tuple (`head/.claude/adapters/loa_cheval/providers/base.py:466-471`) still says:

> "Auth-class env vars that headless adapters MUST strip from their subprocess environment by default. The CLI tools ... prefer their OAuth-subscription auth path, but if any of these vars are exported in the parent process the CLI falls back to API mode — defeating the headless adapter's purpose."

That comment was written to justify stripping *both* sub-classes (credentials AND auth-mode-selectors) — the pre-PR docstring at `base/.claude/adapters/loa_cheval/providers/base.py:489-494` says so explicitly ("both the credential sub-class ... and the auth-mode-selector sub-class"). The PR deletes the mode-selector vars from the tuple but leaves the comment's rationale unchanged, so the code no longer matches its own justification. `GOOGLE_GENAI_USE_VERTEXAI=1` (or `GOOGLE_GENAI_USE_GCA=1`/`GEMINI_CLI_USE_COMPUTE_ADC=1`) exported in the parent process will now leak into the headless gemini subprocess and force Vertex AI / Compute-ADC routing instead of the intended OAuth-subscription path — the exact failure mode issues #879/#880 were opened to close. This is a functional regression, not a shortening of prose.

The updated docstring at `head/.claude/adapters/loa_cheval/providers/base.py:485-486` ("remove auth-class vars per `_HEADLESS_STRIPPED_AUTH_VARS`") is now internally consistent with the smaller tuple, which is exactly the problem: the doc was quietly narrowed to match the code instead of the code being deliberately narrowed for a stated reason. Nothing in the PR description ("shorten... env scrub") discloses that the var set — not just the doc — shrank.

**Fix**: restore the four mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS`, or if there's a genuine reason drop them (e.g., they're no longer meaningful for current CLI versions), state that reasoning explicitly in the PR description and get it reviewed as a behavior change, with issues #879/#880 referenced and a regression test showing the mode-selector vars stay stripped.

## Non-Critical Improvements (blocking — see High below)

### 2. `mktemp` failure now crashes the whole orchestrator instead of degrading gracefully

`head/.claude/scripts/flatline-orchestrator.sh:577` and `head/.claude/scripts/flatline-orchestrator.sh:2282`

```bash
tmp=$(mktemp "${TEMP_DIR:-/tmp}/vq-input.XXXXXX.json")
```
```bash
arbiter_prompt_file=$(mktemp)
```

The base versions guarded these with `if ! tmp=$(mktemp ...); then log "WARNING..."; continue; fi` (and `... ERROR ... continue` for the arbiter case). The script runs under `set -euo pipefail` (`head/.claude/scripts/flatline-orchestrator.sh:47`). A bare `var=$(mktemp ...)` assignment propagates the command substitution's exit status; if `mktemp` fails (full `/tmp`, no permissions, `TEMP_DIR` pointing at a missing directory), `set -e` now kills the entire flatline run instead of skipping the one input file (line 577, inside a `for` loop over `input_files`) or the one arbitration step (line 2282, inside a `case`/`if` block reached per-phase). This turns a per-item failure into an unconditional hard stop of a long-running orchestration process — worse operator experience than what was removed, and inconsistent with the file's own established pattern of defensive `mktemp` handling elsewhere. This is a correctness regression, not dead-weight error handling; it should not be removed silently under the "chore" framing.

**Fix**: restore the guard (or equivalent — e.g., `tmp=$(mktemp ...) || { log ...; continue; }`), or if intentional, justify why letting the whole run die on a transient `mktemp` failure is preferable, and cover it with a test.

### 3. `loa-status.sh` colors always emitted — drops `NO_COLOR` and non-TTY detection

`head/.claude/scripts/loa-status.sh:29-35`

```bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
```

The base version (`base/.claude/scripts/loa-status.sh:29-42`, per `head.diff`) only set these to escape sequences `if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]`, else set them to empty strings. Dropping that guard means every invocation of `loa-status.sh` (non-JSON path) now always emits raw ANSI escapes via `echo -e`, even when: (a) stdout is piped/redirected to a file or another tool (breaks anything that greps/diffs the human-readable output), or (b) the well-known `NO_COLOR` env var is set. This is a real behavioral regression for any consumer that isn't an interactive terminal, and the PR description doesn't call it out.

**Fix**: restore the `NO_COLOR`/`-t 1` guard.

### 4. Unknown-flag validation removed — `loa-status.sh` now silently swallows typoed flags

`head/.claude/scripts/loa-status.sh:43-67`

The base version tracked `UNKNOWN_ARGS` separately from `ECONOMY_ARGS` and, outside `--economy` mode, called `dx_unknown_flag` (or a fallback `echo ... >&2; exit 2`) when an unrecognized flag was passed. The PR removes `UNKNOWN_ARGS` and the whole validation block (`head.diff` shows the removed lines after the `for arg in "$@"` loop). Now, outside `--economy` mode, an unrecognized flag like `--jsonn` or `--verbose` is silently appended to `ECONOMY_ARGS` and then never read (since `ECONOMY_MODE` is false) — the script proceeds as if nothing was wrong, with exit code 0, instead of the previous `exit 2` + usage message. A caller (human or another script) that mistypes a flag now gets no signal at all rather than a clear error.

**Fix**: restore the unknown-flag check for the non-`--economy` path, or explicitly document that `loa-status.sh` ignores unrecognized flags outside `--economy` mode (and confirm that's the desired UX).

## Previous Feedback Status

N/A — no `engineer-feedback.md` exists for this change; this is a standalone PR review with no sprint plan or prior review round.

## Incomplete Tasks

N/A — no sprint/acceptance-criteria doc was provided; this review is against the diff and PR description only, per the review instructions.

## Adversarial Analysis

### Concerns Identified

1. `head/.claude/adapters/loa_cheval/providers/base.py:472-478` — the auth-mode-selector vars are gone from the strip list, but the surrounding comment (`base.py:466-471`) still describes stripping both sub-classes; the code and its own justification now disagree, and nothing in the PR calls this out as a behavior change rather than a doc trim.
2. `head/.claude/scripts/flatline-orchestrator.sh:577,2282` — removing the `mktemp` guards under `set -euo pipefail` converts a per-item skip into a whole-process crash; this is a strictly worse failure mode for a long-running, possibly-unattended orchestrator (Run Mode / autonomous bridge use cases per `CLAUDE.loa.md`'s Run Mode section).
3. `head/.claude/scripts/loa-status.sh:29-35` — colors are now unconditional, which will corrupt any downstream tooling or logs that capture `loa-status.sh` output without a TTY, and violates the `NO_COLOR` convention the base code explicitly supported.
4. `head/.claude/scripts/loa-status.sh:43-67` — losing `dx_unknown_flag`/exit-2 behavior for unrecognized flags means CLI typos fail silently instead of loudly, which cuts against this repo's own stated "agent-ergonomics" and DX conventions (see `agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` skill area, `dx-utils.sh` reference in the removed code) without any discussion of the tradeoff.

### Assumptions Challenged

- **Assumption**: The engineer/author treated all three hunks as equivalent, low-risk "shortening" — i.e., that removing lines that don't change the *intended* behavior is always safe.
- **Risk if wrong**: Two of the three hunks (env-var list, mktemp guards) change actual runtime behavior — one reopens a previously-fixed auth-leak bug (#879/#880), the other changes a script's failure mode from "log and continue" to "abort the whole run." Both are exactly the kind of thing a "chore" label is supposed to exclude.
- **Recommendation**: Split this PR. The `loa-status.sh` help-text/`USAGE_LINE` cleanup and any truly cosmetic parts can land as chore; the env-var list and `mktemp` guard removals need to be justified individually (or reverted) and reviewed as behavior changes, each referencing the issues/invariants they touch.

### Alternatives Not Considered

- **Alternative**: For the `base.py` env-var list, if the goal was genuinely to "shorten" without changing behavior, the four mode-selector vars could have been kept in the tuple and only the *docstring* prose condensed (as the diff's `-`/`+` for the docstring alone would suggest was the intent). The PR conflates "shorten the doc comment" with "shorten the list," and only the latter is destructive.
- **Tradeoff**: Keeping the list intact costs nothing — the tuple was already correct and covered by the original issue numbers cited in the comment. There's no simplicity gain from dropping four string literals from a tuple; the "simplification" only manifests in the prose, not the runtime set.
- **Verdict**: The doc-only trim should be kept; the tuple should be reverted to the base version.

## Next Steps

1. Restore the four auth-mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS` in `head/.claude/adapters/loa_cheval/providers/base.py` (or justify their removal explicitly, referencing #879/#880, and add a regression test).
2. Restore `mktemp` failure guards in `head/.claude/scripts/flatline-orchestrator.sh:577` and `:2282` (or an equivalent `|| { log ...; continue; }`), so a transient `mktemp` failure degrades one item instead of killing the run.
3. Restore the `NO_COLOR`/`-t 1` guard around the color variable assignments in `head/.claude/scripts/loa-status.sh:29-35`.
4. Restore unknown-flag validation (or explicitly document/accept silent-ignore) in `head/.claude/scripts/loa-status.sh:43-67`.
5. Re-submit with a description that discloses these are behavior changes, not just line-count reductions, or split into a true chore PR (help text / genuinely dead code) plus separate behavior-change PRs for the rest.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":3,"medium":0,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
