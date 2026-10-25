# took-effect fixtures (cycle-134 Sprint 276, Tasks 1.1-1.3)

Used by `evals/tests/took-effect-hooks.bats`, `took-effect-transcripts.bats` and `took-effect-integrity.bats`.
The run directories themselves are built per test by `te-lib.bash`. The builder writes a one-path PR fixture,
a two-commit pinned source repository and a home-scope sandbox through the real mount library.

- `hook-events-real-sessionstart-startup.jsonl`: REAL. These are the 8 `hook_started` events of the lead's Q-1
  one-turn probe (Claude Code 2.1.310, `~/.cache/loa/cycle-134/q1/events.jsonl`), copied verbatim. They
  are `SessionStart:startup` events for a pinned SessionStart group whose matcher is empty and which holds
  8 commands. The suffix after the colon is the trigger's match query (the session source), not the
  configured matcher.
- `hook-events-synthetic.jsonl`: SYNTHETIC. No PreToolUse, PostToolUse, UserPromptSubmit or Stop
  `hook_started` event has ever been observed in `claude -p` stream-json mode (Q-1;
  `grimoires/loa/a2a/sprint-276/regression.md`). These lines follow the SessionStart shape
  (`<event>[:<query>]`). The first live home-scope run that emits such an event re-checks the grammar (bd-bex39).

JSONL fixtures carry no comment lines, because the transcript rule requires every non-empty line to be a JSON
object. This file is their comment.
