# Skill Frontmatter Invariants

SKILL.md frontmatter keys interact across two permission layers: the skill's own `capabilities` / `allowed-tools` declarations, and Claude Code's per-agent-type tool allowlist. When the two disagree, the agent-type allowlist wins — silently. Agents that declare write capability but dispatch through a read-only agent type produce correct output and then refuse to persist it.

## The invariant

When a skill declares write capability — either `capabilities.write_files: true` OR `allowed-tools` listing `Write`/`Edit` — it MUST NOT set `agent:` to a type that excludes those tools.

Allowed: omit the `agent:` key (skill runs in the caller's context), or set `agent: general-purpose`.

## Agent type tool allowlists

| Agent type | Write / Edit / NotebookEdit | Use for |
|------------|-----------------------------|---------|
| `general-purpose` | ✓ all tools | Skills that author files |
| `Plan` | ✗ excluded | Read-only planning / exploration |
| `Explore` | ✗ excluded | Read-only codebase analysis |
| (unset) | inherited from caller | Default; safe for write-capable skills |

Source: Claude Code agent-type definitions in the system prompt.

## Enforcement

`.claude/scripts/validate-skill-capabilities.sh` checks this invariant on every SKILL.md. A violation exits with code 1 and message:

> agent type '<name>' excludes Write/Edit tools but skill declares write capability …

The allowlist is maintained in the `WRITE_CAPABLE_AGENTS` array near the top of the script. Adding a new write-capable agent type is intentionally a one-line edit with reviewer visibility.

## Scope

Applies to every `.claude/skills/**/SKILL.md`. The lint runs as part of the normal validation suite (`bats tests/unit/skill-capabilities.bats`).

## Origin

- Defect: [#553](https://github.com/0xHoneyJar/loa/issues/553) — `/architect` and `/sprint-plan` produced correct output but refused to write their target files. Three independent reproductions across two repos.
- Tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557) — Tier 1 cycle-083 framework boundary fixes.
- Sprint: `sprint-bug-102` — test-first patch landing the invariant lint + the three frontmatter fixes.

## Related rules

- [zone-system.md](zone-system.md) — `.claude/` is framework-managed; SKILL.md edits require cycle-level authorization.
- [shell-conventions.md](shell-conventions.md) — file-creation safety when authoring SKILL.md via heredoc.
