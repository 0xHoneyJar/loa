# Portable Adapter Protocol

This protocol lets non-Claude runtimes integrate with the same LOA harness without copying Claude-specific hook semantics.

## Canonical event shape

```json
{
  "session_id": "runtime-session-id",
  "cwd": "/absolute/project/path",
  "hook_event_name": "PreToolUse",
  "runtime": "cursor|claude|codex|gemini|custom",
  "tool_name": "Bash|Write|Edit|mcp__server__tool|custom-tool",
  "tool_input": {}
}
```

Only `hook_event_name` is required. `tool_name` and `tool_input` are required for `PreToolUse` and useful for `PostToolUse`.

## Event names

Use the smallest useful set:

```text
SessionStart
UserPromptSubmit
PreToolUse
PostToolUse
PostToolBatch
PreCompact
PostCompact
Stop
SessionEnd
```

A runtime that lacks compaction can omit `PreCompact` and `PostCompact`. A runtime that lacks batches can omit `PostToolBatch`.

## Calling the gate

```bash
echo "$EVENT_JSON" | .loa-harness/bin/portable_gate.sh PreToolUse
```

or directly:

```bash
echo "$EVENT_JSON" | python3 .loa-harness/bin/loa_harness.py hook --event PreToolUse
```

## Decision outputs

For `PreToolUse`, the Claude-compatible denial shape is:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "reason"
  }
}
```

For `Stop`, the block shape is:

```json
{
  "decision": "block",
  "reason": "transition evidence failed"
}
```

For context injection:

```json
{
  "additionalContext": "compact worldline state"
}
```

Adapters for runtimes other than Claude must translate these outputs into that runtime’s control path. If the runtime cannot block after a tool proposal, wrap the tool executor so the harness is called before the tool runs.

## Adapter responsibilities

A runtime adapter must:

1. emit canonical events;
2. call the harness before side effects;
3. obey deny/block outputs;
4. append harness stdout/stderr to a runtime-visible log;
5. preserve the harness event log;
6. never “simulate” state advancement in prose.

## Cursor sketch

Cursor CLI can be wrapped in a process that emits `SessionStart`, streams model/tool events when available, and calls `PreToolUse` before file or terminal operations. If only coarse-grained events are available, place the harness around high-risk boundaries:

```text
before terminal command     -> PreToolUse/Bash
before file write           -> PreToolUse/Write
turn completion             -> Stop
session start/resume        -> SessionStart
```

The same `transition.request.json` mechanism remains valid even when the runtime is not Claude.
