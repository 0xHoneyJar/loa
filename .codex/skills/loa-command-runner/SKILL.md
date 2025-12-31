---
name: loa-command-runner
description: Interpret and run a Loa command definition from .claude/commands in Codex.
---
When invoked, run a Loa command by reading its definition in `.claude/commands` and executing the referenced skill or workflow.

Input format (from the calling prompt or user):
- Command: <name>
- Args: <raw arguments, positional and/or KEY=value>

Steps:
1. Read `.claude/commands/<Command>.md` and parse the YAML front matter.
2. Extract: name, description, arguments, command_type, agent, agent_path, context_files, pre_flight, outputs, mode.
3. Map arguments:
   - If mode.allow_background is true, treat a trailing `background` token as mode and remove it from args.
   - Treat `--flag` as `flag=true`, and `--key=value` or `--key value` as named arguments.
   - Keep KEY=value pairs as named arguments.
   - Drop filler tokens like `for` before mapping (used in translate commands).
   - If the command defines named arguments, map remaining positional args to those names in order.
   - Expose $ARGUMENTS.* placeholders by substituting the resolved values.
4. Run pre_flight checks in order. Supported checks:
   - file_exists: verify path exists.
   - file_not_exists: verify path does not exist.
   - directory_exists: verify directory exists.
   - command_exists: verify command is in PATH.
   - command_succeeds: run the shell command and require exit code 0.
   - pattern_match: apply regex to the provided value.
   - content_contains: confirm file contains the regex/text.
   - script: run the script and capture output if store_result is set.
   If a check is marked soft: true, warn and ask the user whether to proceed.
5. Load context_files:
   - Expand globs and recursive matches.
   - Respect required=true; stop and report if missing.
   - Respect priority ordering when present.
6. If command_type is set:
   - wizard: follow the workflow section in the command file and ask for confirmation before running shell commands.
   - survey: ask the survey questions and summarize answers; do not send analytics unless explicitly requested.
   - git: follow the git workflow, confirm before running git commands.
7. If agent is set:
   - Read `.claude/skills/<agent>/SKILL.md` and follow it as the primary workflow.
8. Produce the listed outputs at the specified paths.
9. Summarize what was done and any follow-up steps.

Constraints:
- Never edit `.claude/` directly.
- If a workflow touches app code (`src/`, `lib/`, `app/`), ask for confirmation before writing.
