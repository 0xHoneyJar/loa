# Session Continuity Protocol

Reference protocol. The full text lives at `.claude/protocols/reference/session-continuity.md` — read it on
demand (it is outside the prompt budget); this stub keeps the old path and its anchors stable.

| Level | When | Recipe |
|-------|------|--------|
| 1 | default (all recoveries) | `notes-guard.sh read` — Blockers + newest Session Continuity + 3 newest Decision Logs, ≤ 68 KiB |
| 2 | one section | `notes-guard.sh read --file F --section <H>` (`--index` lists them) |
| 3 | user explicit request only | `notes-guard.sh read --full` |
