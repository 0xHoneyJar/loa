# Sprint 274 — Task 3.0 spike: Claude Code scope facts in `loa-ablation:259` under the egress block

**Lead (Fable 5.1), 2026-10-24 07:50–07:53Z.** Driver `spike-3.0/driver.sh` (scratch, not shipped). Image `loa-ablation:259` `sha256:61e88d02d78519f3ecf20fc3bc162cc1b7a56cd927673ce9d94a7fdb78246dbb`, Claude Code **2.1.299** (image label), proxy `loa-egress-proxy:259` `sha256:10fc90b6…`. Model `global.anthropic.claude-sonnet-5-5` via Bedrock through the egress block (allowlist 10 hosts; **0 denied connects in every arm** — the Bedrock route honours `HTTPS_PROXY`). Launch flags as the harness: `claude -p <prompt> --output-format stream-json --verbose --model … --permission-mode bypassPermissions --dangerously-skip-permissions --tools Bash --max-turns 4`, plus the arm's `--setting-sources`. Container: `--user uid:gid --network loa-egress-<batch> --dns 0.0.0.1 --read-only --tmpfs /tmp --pids-limit 512 --memory 4g --cpus 2`, `/workspace` (project) and `/home/evaluser` (user scope) mounted rw, `ENV_SHIM` from `lib/session-exec.sh`. Process capture: a 1-second `ps -eo pid,ppid,etimes,args` sampler beside `claude` (48–76 samples per arm). Spend: USD 0.0106 + 0.0046 + 0.0119 = **USD 0.027** of the ≤ 2 spike allowance.

## Layout

User scope (`/home/evaluser/.claude/`): `CLAUDE.md` (instructs `touch …/user-claude-md`), `settings.json` (SessionStart and UserPromptSubmit hooks → markers), `commands/usercmd.md`, `agents/useragent.md`, `skills/userskill/SKILL.md`; `.claude.json` with the trust flag for `/workspace`.

Project scope (`/workspace`): every surface item sprint.md Task 3.0 names, each with a deterministic effect — `.claude/settings.json` (SessionStart, UserPromptSubmit, PreToolUse(Bash) hooks → markers; `outputStyle: spikestyle`), `.claude/settings.local.json` (SessionStart hook → marker), `.mcp.json` (server `spikemcp` = `sh -c 'touch …/project-mcp-server && exec sleep 3600'`), `.claude/commands/pcmd.md`, `.claude/skills/pskill/SKILL.md`, `.claude/agents/pagent.md`, `.claude/output-styles/spikestyle.md`, `CLAUDE.md` (instruction + `@.claude/imported.md`), `.claude/imported.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, `.claude/rules/spike.md`, `.claude/scripts/spike.sh` (run by the project hook), `.claude/plugins/pplugin/{plugin.json,hooks/hooks.json}`. Hashes: `spike-3.0/<arm>/{user-scope,project-scope}.sha256`.

## Results

| Surface item | `--setting-sources ""` (cycle-132 harness) | `--setting-sources user` (design a′) | `--setting-sources user,project` (positive control) |
|---|---|---|---|
| user `CLAUDE.md` instruction | not followed | **followed** (marker) | followed |
| user hooks (SessionStart, UserPromptSubmit) | not run | **run** (markers) | run |
| user `commands/`, `skills/`, `agents/` | absent from init | **listed** (`usercmd`, `userskill`, `useragent`) | listed |
| project `.claude/settings.json` hooks (3 events) | not run | **not run** | run (3 markers) + `.claude/scripts/spike.sh` executed via the hook |
| project `.claude/settings.local.json` hook | not run | not run | **not run** (the `local` source was not named) |
| project `.mcp.json` server | not started | **not started** (init `mcp_servers: []`, 0 process samples) | started: init `{spikemcp, pending, source: project}`, marker written, 10 process samples |
| project `commands/`, `skills/`, `agents/` | absent | **absent** (init lists no `pcmd`/`pskill`/`pagent`) | listed |
| project output style | `default` | **`default`** | `spikestyle` active (marker) |
| root `CLAUDE.md` + `@import` + `.claude/CLAUDE.md` + `.claude/rules/` | not followed | **not followed** | all followed (markers `root-claude-md`, `import`, `dot-claude-claude-md`, `rules`) |
| `CLAUDE.local.md` | not followed | not followed | **not followed** (`local` source) |
| `.claude/plugins/` under the project | not loaded | not loaded | **not loaded** (plugins are not a project-scope location) |
| egress denials | 0 | 0 | 0 |
| model reply | `SPIKE-OK` | `SPIKE-OK` | `SPIKE-OK` |

Init events: `spike-3.0/<arm>/init.json`; markers: `canaries.txt`; process samples: `ps-samples.txt`; results: `result.json`.

## Reading

1. **Design (a′) is confirmed.** With `--setting-sources user`, nothing from the project scope loads or executes: no project hook, no `.mcp.json` server process, no project skill/command/agent in the init event, no project output style, no CLAUDE.md-class instruction (root, `.claude/CLAUDE.md`, `@import`, `rules/`). The user scope loads fully — the pinned framework materialised under `/home/evaluser/.claude/` will run its hooks, skills, commands and agents.
2. **The launch must change** from the cycle-132 `--setting-sources ""` (nothing loads — the bare arm) to `--setting-sources user` for the mounted arms; the `local` source stays excluded (it governs `CLAUDE.local.md` and `settings.local.json`).
3. **The overlay's removal of the executable and prompt surface from the root (C-10) is defence in depth, not the mechanism**: under `user` the root's `.claude/`, `CLAUDE.md`, `.mcp.json` are inert. Keeping them out of the root still matters for the oracle-exposure threat (addendum 9: the agent *reading* the installed framework), which is about file visibility, not loading — the PR's own `.claude/` changes stay readable under `pr/head/`.
4. **Plugins**: a project `.claude/plugins/` directory is not a load location in 2.1.299; plugins come from user-scope marketplaces, which the sandbox HOME does not contain.
5. **Egress**: the Bedrock route works through the sidecar (0 denials); the allowlist for Claude Code's non-model endpoints was not exercised (no telemetry/update connects were attempted — none denied).
6. **Caveat**: the facts are pinned to Claude Code 2.1.299 in image 259; a version change re-runs this spike (the driver is in `spike-3.0/driver.sh`). The instruction-class canaries (CLAUDE.md, rules, imports, output style) are model-mediated; the positive control fired all of them, and the `user` arm fired none, so the absence is evidence, not luck, but they remain weaker than the hook/MCP/init-event canaries.

**Decision:** the run continues (no HALT); implementer A lands the `home-scope` mount mode with the launch switched to `--setting-sources user` for the mounted arms. DEC row: Task 3.0 outcome.
