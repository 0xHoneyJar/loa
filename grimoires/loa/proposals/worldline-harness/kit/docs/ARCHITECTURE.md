# Architecture Overview: Portable LOA Harness for Claude CLI

## Why this exists

The failure mode to avoid is a prose-only state machine: the agent says “I reviewed,” “I audited,” or “I advanced to build,” but no external mechanism verifies that the evidence exists. The harness solves this by moving governance out of the prompt and into an executable boundary.

The model can propose work. The harness controls the loop.

```text
human goal
   │
   ▼
agent runtime: Claude Code / Cursor / Codex / Gemini CLI
   │ proposes tool calls, writes artifacts, requests transitions
   ▼
portable hook adapter
   │ normalizes lifecycle events
   ▼
LOA harness policy
   │ validates tools, evidence, zones, transitions
   ▼
worldline store
   │ hash-chained JSONL + SQLite mirror
   ▼
continuity context injected back into the next turn
```

## Source alignment

Claude Code hooks are a strong enforcement point because they fire at lifecycle boundaries and pass JSON to hook handlers. Claude’s documentation describes hooks as deterministic controls that run at specific lifecycle points, with stdin JSON, stdout/stderr/exit-code outputs, and structured JSON for more nuanced decisions. It also explicitly distinguishes events such as `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolBatch`, `Stop`, `PreCompact`, `PostCompact`, and `SessionEnd`.

LOA already has the governance vocabulary this harness needs: a three-zone model (`.claude/` system, `grimoires/loa/` and `.beads/` state, application code), BUTTERFREEZONE as an agent-facing interface, capability contracts, trust levels, integrity enforcement, and a spiral harness proposal where bash/script gates are unskippable and the model cannot self-certify quality gates.

Cursor is attractive tastewise because it is compact and editor-native. The portable harness design here does not depend on Claude-only semantics: it defines a small event protocol that any runtime can call. For Claude, hooks call `loa_harness.py` directly. For Cursor or another runtime, an adapter can call `portable_gate.sh` before tool execution, after tool execution, and at turn stop.

## Core concepts

### 1. Event normalization

Each runtime emits different lifecycle events. The harness normalizes them into a small vocabulary:

```text
SessionStart      initialize or resume continuity
UserPromptSubmit  inject state and detect bypass intent
PreToolUse        deny unsafe tool calls before execution
PostToolUse       record observed tool result
PostToolBatch     record batch boundary
PreCompact        checkpoint before context loss
PostCompact       re-inject continuity after compaction
Stop              validate transition request and block/advance
SessionEnd        close the session boundary
```

Claude supports these events directly. Other runtimes should synthesize them around their own loop.

### 2. Zone enforcement

The policy divides a repository into zones:

```text
System zone: .claude/, .loa-harness/bin/, .git/
State zone:  grimoires/loa/, .beads/, .run/, .ck/, .loa-harness/runtime/
App zone:    src/, lib/, app/, packages/, tests/
```

The model may write app artifacts when permitted. It may write state artifacts. It may not directly mutate system-zone governance machinery except through explicit override surfaces such as `.claude/overrides/`.

### 3. Transition requests

The state machine advances only through a transition request file:

```text
.loa-harness/runtime/transition.request.json
```

The Stop hook validates:

- source state matches current state;
- destination is allowed by `policy.json`;
- required evidence files exist;
- evidence is large enough to be non-trivial;
- evidence contains configured markers;
- the event is recorded into a hash-chained flight recorder.

This is the critical anti-prose mechanism. The model can request a transition, but the harness performs it.

### 4. Flight recorder

Every hook event is appended to:

```text
.loa-harness/runtime/events.jsonl
.loa-harness/runtime/harness.sqlite3
```

Each JSONL record contains:

- sequence number;
- timestamp;
- worldline id;
- hook event name;
- state before and after;
- decision;
- reason;
- redacted payload;
- previous event hash;
- current event hash.

This is a lightweight “trusting trust” mitigation: behavior is not trusted just because the agent says it happened. You can verify the chain with:

```bash
python3 .loa-harness/bin/loa_harness.py verify
```

### 5. Continuity injection

On `SessionStart`, `UserPromptSubmit`, and `PostCompact`, the harness emits compact state context:

```text
worldline_id
current state
allowed next states
event sequence
head hash
transition request instructions
```

This gives the agent continuity without depending on an enormous prompt or an unverifiable memory blob.

## Reference state machine

```text
INIT
  └─ ORIENTING
       └─ PLANNING
            └─ ARCHITECTING
                 └─ SPRINTING
                      └─ IMPLEMENTING
                           └─ REVIEWING ──┐
                                │          │ changes required
                                ▼          │
                             AUDITING ─────┘
                                │
                                ▼
                             SHIPPING
                                │
                                ▼
                             ARCHIVED
```

The back-edges from review/audit to implementation are first-class transitions, not failures. They are how dissent and quality gates compound.

## Claude adapter

Claude hooks are configured in `.claude/settings.json`. The provided example uses exec-form command hooks:

```json
{
  "type": "command",
  "command": "python3",
  "args": [
    "${CLAUDE_PROJECT_DIR}/.loa-harness/bin/loa_harness.py",
    "hook",
    "--event",
    "PreToolUse"
  ]
}
```

Exec-form avoids shell quoting issues and keeps stdout clean for structured JSON. The harness uses `permissionDecision: deny` for `PreToolUse`, top-level `decision: block` for `Stop`, and `additionalContext` for continuity injection.

## Cursor and other runtime adapters

The portable adapter contract is smaller than Claude’s hook API:

```bash
portable_gate.sh SessionStart      < event.json
portable_gate.sh UserPromptSubmit  < event.json
portable_gate.sh PreToolUse        < event.json
portable_gate.sh PostToolUse       < event.json
portable_gate.sh Stop              < event.json
```

A Cursor adapter should translate terminal/file/editor operations into this JSON shape and obey deny/block outputs. Cursor CLI’s headless mode and stream JSON output make it a good candidate for wrapper-level orchestration, even when the editor UI hook surface differs.

## Trust boundary

Do not let the same agent both perform and approve a critical gate. For planning and implementation, the model can work inside a bounded prompt. For review, audit, shipping, and worldline advancement, the harness should require either deterministic checks or a fresh independent session whose output is captured as evidence.

The rule is simple:

```text
Agent proposes. Harness disposes.
```
