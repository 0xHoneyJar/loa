# LOA Claude Harness Kit

A small, portable harness reference for Claude CLI / Claude Code workflows where the state machine must be enforced by executable hooks rather than prose.

This kit is intentionally minimal. It gives you:

- a Claude CLI prompt you can issue directly;
- an architectural overview for reflecting Claude/Cursor-style harnessing into LOA;
- a Python reference implementation with no third-party dependencies;
- a Claude Code `settings.json` hook example;
- a hash-chained JSONL flight recorder plus SQLite mirror;
- evidence-checked transition requests so agents cannot advance a worldline just by saying they did.

## Quick install into a repo

From this kit directory, inside the target repository:

```bash
mkdir -p .loa-harness/bin .loa-harness/runtime .claude
cp bin/loa_harness.py .loa-harness/bin/
cp bin/portable_gate.sh .loa-harness/bin/
cp config/policy.example.json .loa-harness/policy.json

# Merge config/claude.settings.example.json into .claude/settings.json.
# Do not blindly overwrite an existing settings file unless this is a fresh repo.
python3 .loa-harness/bin/loa_harness.py init
```

Then add the hooks from `config/claude.settings.example.json` to `.claude/settings.json`. In Claude Code, run `/hooks` to confirm they loaded.

## Claude CLI prompt

The install/reflection prompt is in:

```text
prompts/claude-cli-reflect-harness.md
```

A typical invocation:

```bash
claude -p \
  --init \
  --output-format stream-json \
  --verbose \
  --include-hook-events \
  --append-system-prompt-file prompts/claude-cli-reflect-harness.md \
  "Reflect the portable LOA harness into this repository. Preserve existing LOA conventions and do not overwrite project hooks without merging."
```

## Test the reference implementation

```bash
python3 -m unittest discover -s tests
./scripts/smoke_test.sh
```

Manual policy checks:

```bash
# Dangerous Bash is denied by PreToolUse.
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | python3 .loa-harness/bin/loa_harness.py hook --event PreToolUse

# Protected system-zone write is denied.
echo '{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json"}}' \
  | python3 .loa-harness/bin/loa_harness.py hook --event PreToolUse

# Current worldline state.
python3 .loa-harness/bin/loa_harness.py status

# Verify event-log hash chain.
python3 .loa-harness/bin/loa_harness.py verify
```

## Transition model

The model does not advance the harness by writing prose. It must create:

```text
.loa-harness/runtime/transition.request.json
```

Example:

```json
{
  "schema_version": "loa-harness.transition-request/v0.1",
  "from": "PLANNING",
  "to": "ARCHITECTING",
  "actor": "claude-cli",
  "reason": "PRD exists and acceptance criteria are ready for architecture.",
  "evidence": [
    {
      "path": "grimoires/loa/prd.md",
      "min_bytes": 500,
      "contains_any": ["Acceptance", "Requirements", "PRD"]
    }
  ]
}
```

On the `Stop` hook, the harness validates the request. If evidence passes, it advances state and archives the request. If evidence fails, it returns a `decision: block` response so Claude keeps working with the harness reason.

## Files

```text
prompts/claude-cli-reflect-harness.md   Prompt to issue to claude -p

docs/ARCHITECTURE.md                    Design rationale and LOA mapping
docs/ADAPTER_PROTOCOL.md                Portable event protocol for non-Claude runtimes
docs/TRANSITION_REQUESTS.md             State transition request format

config/policy.example.json              Executable state/policy config
config/claude.settings.example.json     Claude Code hook configuration

bin/loa_harness.py                      Reference implementation
bin/portable_gate.sh                    Thin adapter for runtimes without native hooks

examples/*.json                         Example hook events and transition requests
tests/test_harness.py                   Unit tests
scripts/smoke_test.sh                   End-to-end smoke test
```

## Design stance

The harness treats an LLM as a worker, not the supervisor of its own governance. The model may propose actions, generate artifacts, or request a transition. The harness validates tools, writes the event ledger, checks evidence, and decides whether the worldline advances.
