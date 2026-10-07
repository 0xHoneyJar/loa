# Skill Frontmatter Invariants

SKILL.md frontmatter keys interact across two permission layers: the skill's own `capabilities` / `allowed-tools` declarations, and Claude Code's per-agent-type tool allowlist. When the two disagree, the agent-type allowlist wins — silently. Agents that declare write capability but dispatch through a read-only agent type produce correct output and then refuse to persist it.

## The invariant

When a skill declares write capability — either `capabilities.write_files: true` OR `allowed-tools` listing `Write`/`Edit` — it MUST NOT set `agent:` to a type that excludes those tools.

Allowed: omit the `agent:` key (skill runs in the caller's context), or set `agent:` to a write-capable type (`general-purpose`, `claude`, `fork`).

## Agent type tool allowlists

| Agent type | Write / Edit / NotebookEdit | Use for |
|------------|-----------------------------|---------|
| `general-purpose`, `claude`, `fork` | ✓ all tools | Skills that author files |
| `Plan` | ✗ excluded | Read-only planning / exploration |
| `Explore` | ✗ excluded | Read-only codebase analysis |
| `loa-scout`, `prompt-auditor`, `prompt-auditor-io` | ✗ excluded | Read-only project agents (`.claude/agents/`) |
| (unset) | inherited from caller | Default; safe for write-capable skills |

Source: Claude Code agent-type definitions in the system prompt, and `.claude/agents/*.md`.

## Enforcement

`.claude/scripts/validate-skill-capabilities.sh` checks this invariant on every SKILL.md. A violation exits with code 1 and message:

> agent type '<name>' excludes Write/Edit tools but skill declares write capability …

The allowlist is maintained in `.claude/data/agent-types.yaml` (one `write_capable` flag per agent type); the script loads the `true` entries into `WRITE_CAPABLE_AGENTS` and falls back to `general-purpose` alone when the file is missing, unparsable, or lists no `write_capable: true` entry. Adding a new write-capable agent type is intentionally a one-line edit with reviewer visibility.

## Mechanical C-PROC-001 enforcement via `disallowed-tools` (cycle-114 FR-4)

`disallowed-tools` frontmatter (Claude Code ≥2.1.152) removes tools from the
model while a skill is active — a harness-level barrier that instructions
cannot override. Cycle-114 uses it to make C-PROC-001 ("NEVER write application
code outside `/implement`") mechanical for review skills rather than prose-only.

| Skill class | `disallowed-tools` | Why |
|-------------|--------------------|-----|
| Pure-review (`write_files: false`, no report artifacts) | `Write`, `Edit`, `NotebookEdit` | Never writes anything — remove the write tools outright |
| Sprint review/audit (`reviewing-code`, `auditing-security`; `write_files: true`) | `NotebookEdit` | Write STATE-zone feedback/checkmarks/COMPLETED markers, run the allowed verdict check and run `adversarial-review.sh` (forks the provider CLIs, appends the `.run` cost and MODELINV ledgers, moves the previous round's a2a envelope aside as `.prev`, writes the new one; review also runs `qmd-context-query.sh`); System remains `none` and App remains `read` |
| Report-authoring review (`red-teaming`, `bridgebuilder-review`; `write_files: true`) | `NotebookEdit`, `Bash(git add/commit/push *)` | Legitimately write STATE-zone reports/vision/lore, so `Write` is retained; app-code prevention is governed by **zones**, and the implementation-only git mutations are removed |

**`REVIEW_WRITE_EXCEPTIONS`** (in `validate-skill-capabilities.sh`):
`red-teaming`, `bridgebuilder-review`, `spiraling`, `autonomous-agent`,
`run-bridge`, `run-mode`, `reviewing-code`, `auditing-security`. These `role: review` skills keep `Write` by design —
the adversarial/report authors write STATE-zone artifacts, and the autonomous
orchestrators dispatch implementation through the harness (which runs inside
`/implement`, where writes are sanctioned). The validator emits a WARN for any *other* `role: review`
skill that declares `write_files: true` without disallowing `Write` — surfacing
a new C-PROC-001 gap at lint time. `disallowed-tools` is tool-granular, not
path-granular; it cannot express "no `src/` writes but yes `grimoires/` writes",
which is why report-authoring skills rely on zones for path-level control.

## Scope

Applies to every `.claude/skills/**/SKILL.md`. The lint runs as part of the normal validation suite (`bats tests/unit/skill-capabilities.bats`).

## Origin

- Defect: [#553](https://github.com/0xHoneyJar/loa/issues/553) — `/architect` and `/sprint-plan` produced correct output but refused to write their target files. Three independent reproductions across two repos.
- Tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557) — Tier 1 cycle-083 framework boundary fixes.
- Sprint: `sprint-bug-102` — test-first patch landing the invariant lint + the three frontmatter fixes.

## Related rules

- [zone-system.md](zone-system.md) — `.claude/` is framework-managed; SKILL.md edits require cycle-level authorization.
- [shell-conventions.md](shell-conventions.md) — file-creation safety when authoring SKILL.md via heredoc.
