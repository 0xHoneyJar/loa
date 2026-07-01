# Sources and design references

- Claude Code Hooks reference: https://code.claude.com/docs/en/hooks
- Claude Code hooks guide: https://code.claude.com/docs/en/hooks-guide
- Claude Code CLI reference: https://code.claude.com/docs/en/cli-reference
- Cursor hooks page: https://cursor.com/docs/hooks
- Cursor documentation index: https://cursor.com/llms.txt
- Cursor CLI headless docs: https://cursor.com/docs/cli/headless.md
- LOA repository: https://github.com/0xHoneyJar/loa
- LOA `PROCESS.md`: https://github.com/0xHoneyJar/loa/blob/main/PROCESS.md
- LOA spiral harness proposal: https://github.com/0xHoneyJar/loa/blob/main/grimoires/loa/proposals/spiral-harness-architecture.md
- Ken Thompson, “Reflections on Trusting Trust”: https://dl.acm.org/doi/10.1145/358198.358210

Notes:

- The Claude adapter is implemented directly against the public Claude Code hook model.
- Cursor support is intentionally expressed as an adapter protocol because the package is for Claude CLI, and Cursor’s current docs surface should be checked in the target environment before binding to exact editor-hook names.
