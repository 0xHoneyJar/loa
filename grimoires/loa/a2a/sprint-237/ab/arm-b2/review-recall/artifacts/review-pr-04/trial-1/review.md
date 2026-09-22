# Review: chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

## Summary

Three unrelated simplifications bundled in one PR. Each one removes a small piece of
error-handling or a stripped-var entry that was added deliberately (and documented as
deliberate) in the code it edits. None of the removals are justified in the PR
description beyond "simplifies" — none of the invariants they were protecting are shown
to be obsolete.

## Changes Required

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/base.py:472-478` — `_HEADLESS_STRIPPED_AUTH_VARS` drops the four auth-mode-selector vars (`GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`, `GOOGLE_GEMINI_BASE_URL`, `GEMINI_CLI_USE_COMPUTE_ADC`), keeping only the credential vars. The removed docstring text (visible in `head.diff`, base.py:19-24 of the hunk) explicitly explained why both sub-classes had to be stripped: "operator opt-out via `LOA_HEADLESS_KEEP_API_KEY=1` preserves ALL entries verbatim (credentials AND mode-selectors — the opt-in is a full env-bypass, not credential-only)". With this change, an operator whose shell exports `GOOGLE_GENAI_USE_VERTEXAI=1` (a common gcloud/Vertex workstation setup) will now have that var silently forwarded into the headless subprocess even without opting in via `LOA_HEADLESS_KEEP_API_KEY`. The Gemini CLI will pick up Vertex/ADC auth mode instead of the intended OAuth-subscription path, silently defeating the headless adapter's isolation guarantee that issues #879/#880 were opened to fix (per the surrounding comment at `base.py:466-471`, still present in `head/`). This is a functional regression of the exact bug the function was written to close, not a harmless line trim.

- **HIGH** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:2281-2283` — the `mktemp` guard around `arbiter_prompt_file` was removed. This call sits inline in `run_consensus()` (`flatline-orchestrator.sh:1563`), which is invoked as a plain command substitution — `result=$(run_consensus ...)` at `flatline-orchestrator.sh:2222` — with no `||` or `if` wrapping it. The file sets `set -euo pipefail` (`flatline-orchestrator.sh:47`), and this call site is NOT one of the contexts where `-e` is ignored, so a `mktemp` failure here (full `/tmp`, a sandboxed environment with no writable temp dir, etc.) now aborts the entire orchestrator process mid-run instead of the previous behavior — log `"ERROR: mktemp failed for arbiter prompt — skipping arbiter step for $phase"` and `continue`, letting phase1/phase2 results and the rest of consensus processing complete. The fail-soft design (explicitly documented at `flatline-orchestrator.sh:552-554`: "Fail-soft: missing python module / empty input / aggregator error logs a warning but does NOT abort the orchestrator") is contradicted by this specific code path once the arbiter branch is reached.

## Observations

- **MEDIUM** (confidence: high) `head/.claude/scripts/flatline-orchestrator.sh:576-580` — the `mktemp` guard around the per-voice `tmp` file in `aggregate_and_write_final_consensus()` was also removed. This function is called at `flatline-orchestrator.sh:2195` as `aggregate_and_write_final_consensus "$phase" "${vq_phase1_files[@]}" || true`. Because the call is part of an `||` list, bash disables `-e` enforcement for the entire function body (a well-known bash gotcha: `set -e` is ignored throughout a function invoked in a tested context, not just at the call site), so a `mktemp` failure here does not crash the script — but it does silently produce `tmp=""`, then `printf '%s' "$vq" > ""` errors out (ambiguous redirect) with no log line, and the empty string is still pushed onto `vq_files`/`cleanup_files`. That empty entry is later passed as a positional arg to `python3 -m loa_cheval.verdict.aggregate` (`flatline-orchestrator.sh:598-601`), which will fail to open path `""` and turn the whole aggregate step into an unexplained aggregator failure instead of cleanly skipping the one bad voice, with no warning telling an operator why. Same category as the HIGH finding above but bounded impact (no process crash) is why this is filed as an observation rather than blocking.

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:62-66` — the unknown-flag validation (`USAGE_LINE`/`UNKNOWN_ARGS`/`dx_unknown_flag` block, removed per `head.diff` lines 105-115 of that hunk) is gone. An unrecognized flag — e.g. a typo like `--jsonn` — now falls through to the `*)` case, is appended to `ECONOMY_ARGS`, and then silently discarded because `ECONOMY_MODE` is `false` (`loa-status.sh:71`, `ECONOMY_ARGS` is only consumed inside the economy branch). Previously this printed "Unknown option: …" plus usage and exited 2. Now the script runs to completion in the default (human-readable, non-JSON) mode with no indication the flag was ignored — a caller in a script expecting `--json` output from a typo'd flag would silently get the wrong format instead of a `set -e`-friendly exit 2.

- **MEDIUM** (confidence: high) `head/.claude/scripts/loa-status.sh:29-35` — the `NO_COLOR`/`[[ -t 1 ]]` gate around the color variable assignments was removed; `RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`NC` are now unconditionally set to their ANSI escape sequences (used at, e.g., `loa-status.sh:188,194,200-206,233-241,411,432,505-547`). Piping `loa-status.sh` output to a file, a log aggregator, or any non-tty consumer — or running with `NO_COLOR=1` set, which this script previously honored — now embeds raw escape codes in the captured text. This breaks any downstream text processing (grep, log viewers that don't interpret ANSI, CI log capture) that previously got clean output, and silently drops support for the `NO_COLOR` convention this file explicitly implemented.

## Overall Assessment

All four findings are simplifications that removed intentional, documented protective
behavior without replacing it or justifying the removal. Two are HIGH severity because
they either reintroduce a named, closed security/isolation bug (`base.py`) or convert a
documented fail-soft path into a hard process crash (`flatline-orchestrator.sh:2281`).
Recommend restoring the four mode-selector vars to `_HEADLESS_STRIPPED_AUTH_VARS`, restoring
both `mktemp` failure guards (or wrapping the call sites so a synthetic failure is provably
non-fatal), and restoring the `NO_COLOR`/tty gate and unknown-flag validation in
`loa-status.sh`.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":0},"excluded":0,"sprint_id":"pr-04","ts":"2026-09-22T00:00:00Z"} -->
