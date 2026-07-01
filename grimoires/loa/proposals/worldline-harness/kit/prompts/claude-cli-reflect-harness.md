# LOA Harness Reflection Prompt for Claude CLI

You are working inside a repository that should be governed by a portable LOA-compatible harness. Your job is to reflect the harness into the repository without turning the state machine into prose.

## Prime directive

The state machine is executable policy, not a reminder. Do not claim a phase is complete unless an artifact exists and the harness can verify it. Do not self-certify review, audit, or shipping gates. Create evidence and transition requests; let hooks and scripts advance the worldline.

## First actions

1. Inspect the repository root.
2. Read `CLAUDE.md`, `AGENTS.md`, `BUTTERFREEZONE.md`, `.loa.config.yaml`, and `PROCESS.md` if present.
3. Check whether `.loa-harness/policy.json` and `.loa-harness/bin/loa_harness.py` already exist.
4. If the harness is not installed, install it from this kit:
   - create `.loa-harness/bin/` and `.loa-harness/runtime/`;
   - copy `bin/loa_harness.py` into `.loa-harness/bin/`;
   - copy `bin/portable_gate.sh` into `.loa-harness/bin/` if present;
   - copy `config/policy.example.json` to `.loa-harness/policy.json`;
   - initialize with `python3 .loa-harness/bin/loa_harness.py init`.
5. Merge `config/claude.settings.example.json` into `.claude/settings.json` without deleting existing hooks.

## Operating rules

- Treat `.claude/` and `.loa-harness/bin/` as system zone. Do not edit framework-managed content directly unless explicitly requested by the human.
- Use `.claude/overrides/`, `grimoires/loa/`, `.beads/`, `.run/`, or `.loa-harness/runtime/transition.request.json` for project-specific state.
- Before any phase transition, write `.loa-harness/runtime/transition.request.json` with `from`, `to`, `actor`, `reason`, and evidence.
- Let the Stop hook validate the transition. If it blocks, read the reason and fix the evidence.
- Review and audit gates must be independent sessions or external deterministic checks. Never write “approved” for your own implementation unless the requested reviewer/auditor artifact exists.
- If Cursor, Codex, Gemini CLI, or another runtime is used, call `.loa-harness/bin/portable_gate.sh <EventName>` around tool execution so the same policy still gates actions.

## Expected deliverables

Produce or update the following, preserving existing LOA conventions:

- `.loa-harness/policy.json` with the executable state machine and tool policy;
- `.loa-harness/bin/loa_harness.py` as the hook adapter;
- `.claude/settings.json` hooks for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolBatch`, `PreCompact`, `PostCompact`, `Stop`, and `SessionEnd`;
- a short `grimoires/loa/harness-reflection.md` describing what was installed, what was merged, and how to verify it;
- a successful `python3 .loa-harness/bin/loa_harness.py verify` run.

## Transition request template

When ready to advance, write:

```json
{
  "schema_version": "loa-harness.transition-request/v0.1",
  "from": "CURRENT_STATE",
  "to": "NEXT_STATE",
  "actor": "claude-cli",
  "reason": "Why this transition is justified.",
  "evidence": [
    {
      "path": "grimoires/loa/prd.md",
      "min_bytes": 500,
      "contains_any": ["Acceptance", "Requirements", "PRD"]
    }
  ]
}
```

Then finish the turn. The Stop hook owns the actual transition.

## Final response format

Report:

1. what files changed;
2. which hooks are installed;
3. current harness state from `loa_harness.py status`;
4. verification result from `loa_harness.py verify`;
5. any unresolved adapter gaps.
