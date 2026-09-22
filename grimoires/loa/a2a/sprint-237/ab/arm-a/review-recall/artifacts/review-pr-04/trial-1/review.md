# Review: chore(cheval,flatline,status): shorten headless env scrub, temp-file handling, flag parsing

## Overall Assessment

This PR frames itself as a pure simplification/cleanup ("shorten", "drops the mktemp guards",
"simplifies... argument handling and colour setup"), but two of its three hunks are not neutral
simplifications — they delete behavior that was added deliberately to fix specific problems, and
the deletions are not called out anywhere in the PR description. The `base.py` change in
particular silently reopens the exact bug that issues #879/#880 closed. This is CHANGES_REQUIRED.

## Critical Issues

### 1. Reopens issues #879/#880 by un-stripping the auth-mode-selector vars

`head/.claude/adapters/loa_cheval/providers/base.py:472-478`

The diff removes `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`,
and `GEMINI_CLI_USE_COMPUTE_ADC` from `_HEADLESS_STRIPPED_AUTH_VARS`. The section header comment
directly above the tuple, unchanged by this PR, still reads:

> `head/.claude/adapters/loa_cheval/providers/base.py:462` — `# Headless adapter subprocess env helper (closes issues #879 / #880)`

and the surviving prose comment (`base.py:465-470`) still explains the exact mechanism this PR
breaks:

> "The CLI tools (claude / codex / gemini) prefer their OAuth-subscription auth path, but if any
> of these vars are exported in the parent process the CLI falls back to API mode — defeating the
> headless adapter's purpose."

`GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` / `GEMINI_CLI_USE_COMPUTE_ADC` are exactly
this class of "auth-mode-selector" var (not a credential, but a switch that redirects the Gemini
CLI away from OAuth-subscription mode). The pre-PR docstring at
`base/.claude/adapters/loa_cheval/providers/base.py:488-494` spelled this out explicitly:
"every entry in `_HEADLESS_STRIPPED_AUTH_VARS` — both the credential sub-class (e.g.,
`GOOGLE_API_KEY`) and the auth-mode-selector sub-class (e.g., `GOOGLE_GENAI_USE_VERTEXAI`)". The
new docstring (`head/.claude/adapters/loa_cheval/providers/base.py:484-486`) quietly drops that
distinction along with the vars themselves.

**Concrete failure**: an operator (or CI environment) that has `GOOGLE_GENAI_USE_VERTEXAI=true`
set in the parent shell — e.g., because they also use Vertex AI directly for other tooling — will
now have that var silently inherited by the headless Gemini subprocess. The Gemini CLI falls back
to Vertex/API-key routing instead of OAuth-subscription mode, silently defeating the headless
adapter and (depending on the operator's Vertex billing setup) incurring API costs the headless
adapter was specifically built to avoid. There is no test in the touched paths guarding
`build_headless_subprocess_env`'s var list, so nothing in CI would catch this regression.

This looks like an accidental revert of a change landed for #879/#880 rather than an intentional,
reviewed narrowing of scope — nothing in `PR.md` mentions removing mode-selector stripping, only
"shorten the headless env scrub". Recommend restoring the four removed vars, or if the intent is
genuinely to narrow scope to credentials only, updating the still-present `(closes issues
#879/#880)` header comment and getting explicit sign-off that this is a deliberate scope reduction
tied to a rationale, not a byproduct of trimming the docstring.

## Non-Critical Improvements

### 2. `mktemp` failure now crashes the whole orchestrator run instead of degrading gracefully

`head/.claude/scripts/flatline-orchestrator.sh:577`, `head/.claude/scripts/flatline-orchestrator.sh:2282`

Both call sites dropped the `if ! tmp=$(mktemp ...); then log "WARNING/ERROR: mktemp failed..."; continue/skip; fi` guard. The script runs under `set -euo pipefail` (`head/.claude/scripts/flatline-orchestrator.sh:47`), so on a `mktemp` failure (e.g., `/tmp` full, `TEMP_DIR` pointing at a non-writable path, tmpfs exhaustion under autonomous/CI load) the assignment's non-zero exit status now terminates the entire orchestrator process immediately, rather than skipping the one voice's verdict-quality envelope (line 577) or the one phase's arbiter step (line 2282) and continuing. That is a strictly worse failure mode for what the PR calls a no-op cleanup: previously a transient `/tmp` hiccup degraded one input; now it aborts an entire Flatline review run (PRD/SDD/sprint phase) that might otherwise have succeeded on unaffected inputs. If the guards were considered unnecessary defensive code, that's a judgment call worth stating explicitly in the PR description — as written, this reads as an unintentional simplification that removes a real (if rare) safety net without discussion.

### 3. `loa-status.sh` colour codes are now unconditional — ignores `NO_COLOR` and non-TTY output

`head/.claude/scripts/loa-status.sh:30-35`

The `[[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]` guard was removed, so `RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`NC` are now always set to raw ANSI escape sequences and unconditionally emitted by every `echo -e` call that uses them (e.g. `head/.claude/scripts/loa-status.sh:188`, `194`, `200-206`, `233-234`, `241`, `411`, `432`, `505`, `516`, `547`). Any consumer that pipes or redirects this script's human-readable output — `loa-status.sh > status.log`, `loa-status.sh | tee`, CI logs, an agent capturing stdout for parsing — will now get raw escape sequences embedded in the text, and operators who export `NO_COLOR=1` (a widely respected convention this script previously honored) will no longer get plain output. `--json` mode is presumably unaffected content-wise, but the default human-readable path (used by `/loa` per `CLAUDE.loa.md`'s Golden Path table) regresses for every non-interactive caller.

### 4. Unknown-flag detection silently removed — typos are now swallowed instead of erroring

`head/.claude/scripts/loa-status.sh:43-66`

The `UNKNOWN_ARGS` array and the post-loop `dx_unknown_flag`/"Unknown option" + `exit 2` block were deleted. Previously, an unrecognized flag outside `--economy` mode (e.g. a typo like `--jsno` or `--verion`) produced `Unknown option: ... / Usage: ...` and a non-zero exit. Now the `*)` branch in the arg loop (`loa-status.sh:62-65`) unconditionally appends every unrecognized arg to `ECONOMY_ARGS`, but that array is only ever consumed when `ECONOMY_MODE == true` (`loa-status.sh:69-77`); outside economy mode the mistyped flag is silently discarded and the script proceeds as if nothing happened. A user who typos `--json` will now get plain-text output with no error rather than an actionable message pointing at the mistake — a quiet UX regression for a script the Golden Path routes `/loa` through.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/adapters/loa_cheval/providers/base.py:472-478` — mode-selector auth vars removed from the strip list, silently reopening #879/#880 (see Critical Issues above).
2. `head/.claude/scripts/flatline-orchestrator.sh:577` and `:2282` — removing the `mktemp` guards changes a per-item, loggable failure into a whole-process crash under `set -euo pipefail`.
3. `head/.claude/scripts/loa-status.sh:30-35` — unconditional ANSI colour codes break `NO_COLOR` and non-TTY/piped consumers.
4. `head/.claude/scripts/loa-status.sh:43-66` — removing unknown-flag validation turns user typos into silent no-ops instead of actionable errors.

### Assumptions Challenged
- **Assumption**: The engineer treated all three hunks as pure "shortening" with no behavioral change, per the PR title/description.
- **Risk if wrong**: As shown above, at least two of the three files (base.py, loa-status.sh) have observable behavior changes beyond line-count reduction, and the third (flatline-orchestrator.sh) changes failure semantics from recoverable to fatal.
- **Recommendation**: Re-scope the PR description to explicitly name every behavior change (which vars are no longer stripped, which failure paths are no longer guarded, which output now always includes colour codes, which flag errors are no longer reported), and get explicit confirmation that each is intended — especially the base.py change, which contradicts the "closes issues #879/#880" comment still sitting directly above the edited tuple.

### Alternatives Not Considered
- **Alternative**: For `loa-status.sh`, if the goal was genuinely to simplify colour setup, keep the `NO_COLOR`/`-t 1` guard but hoist it into a one-line helper (e.g. `$(supports_color && printf ... || printf '')`) rather than deleting the check — preserves the shortening goal without regressing `NO_COLOR`/pipe behavior.
- **Tradeoff**: Slightly more code than the current unconditional assignment, but avoids leaking ANSI codes into logs/pipes.
- **Verdict**: Current approach should be reconsidered — the guard was cheap (7 lines) relative to the regression it prevents.

## Previous Feedback Status

N/A — no prior `engineer-feedback.md` exists for this change (standalone PR review, no sprint context).

## Next Steps

1. Restore `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC` to `_HEADLESS_STRIPPED_AUTH_VARS` in `base.py`, or provide explicit justification + doc/comment updates if the scope reduction is intentional.
2. Restore the `mktemp` failure guards in `flatline-orchestrator.sh` (or explicitly justify why crashing the whole run is acceptable and update the PR description accordingly).
3. Restore the `NO_COLOR`/`-t 1` conditional in `loa-status.sh`, or otherwise ensure colour codes are suppressed for non-TTY/`NO_COLOR` consumers.
4. Restore unknown-flag detection in `loa-status.sh` (or explicitly justify silently forwarding/dropping unrecognized flags outside `--economy` mode).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":3,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
