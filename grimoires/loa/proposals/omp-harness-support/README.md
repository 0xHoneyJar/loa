# Proposal: First-class OMP (Pi) harness support

> Status: proposal + runnable kit. **Merging this wires nothing** — it adds a
> proposal directory with an opt-in, tested adapter kit. Core-installer
> integration is the sequenced follow-up (below), gated separately.
>
> Prior art: `grimoires/loa/proposals/pi-dev-harness-evaluation-2026-06-22.md`
> (Pi harness eval, verdict S0) and `native-workflow-adoption.md`. OMP
> ("Oh My Pi") is a Pi-lineage runtime; this proposal drives the
> "run Loa first-class under OMP" claim to ground with a conformance matrix
> and a runnable enforcement bridge.

## TL;DR

Loa ships **exclusively** Claude-Code provider surfaces (`.claude/`). Under OMP,
the `claude` discovery provider makes **commands, skills, MCP, marketplace, and
system-prompt** first-class for free — but **three governance-critical surfaces
are not discovered at all** and silently degrade to advisory:

| Surface | Under OMP | Why |
|---|---|---|
| Kernel / context | ❌ not loaded | OMP's `claude` provider reads `.claude/CLAUDE.md` (absent in Loa) or root `AGENTS.md` (a lossy summary that does not `@`-import the kernel), **not** root `CLAUDE.md`. |
| Hooks (25 guards) | ❌ inert | No `.claude/hooks` discovery provider; OMP hooks are TS/JS factory modules under `.omp/hooks/pre|post/`, not `settings.json` shell commands. |
| Rules / sticky invariants | ❌ not loaded | No `claude` rules provider; sticky rules come only from native `.omp/RULES.md`. |

Full analysis: [CONFORMANCE.md](./CONFORMANCE.md).

## The empirical finding (not a claim)

OMP does **not** execute Loa's `.claude/settings.json` shell hooks. Verified by
side-effect: an OMP `write` + `edit` (both matched by Loa's `Write|Edit|…`
PostToolUse matcher) produced **zero** `.run/audit.jsonl` entries, while
concurrent Claude Code sessions logged their Writes/Edits to the same file. The
mutation-logger — and therefore every PreToolUse safety guard — is inert under
OMP. Grounded in `omp://hooks.md` (hook = TS factory, no settings.json shell
execution) and `omp://config-usage.md` §6 (documented hook roots are native
`.omp` / omp-plugins / explicit only).

## The kit (`kit/`)

An opt-in, dependency-light bridge that restores parity under OMP. Three moves,
matching the three gaps:

- **R1 — kernel entrypoint.** Ensure the OMP-discovered `AGENTS.md` `@`-imports
  the kernel (`@.claude/loa/CLAUDE.loa.md`). OMP reads `AGENTS.md` via the
  agents-md provider and expands `@`-imports (5 hops).
- **R2 — sticky invariants.** Install native `.omp/RULES.md` (OMP re-attaches
  it across long sessions). [`kit/RULES.md`](./kit/RULES.md)
- **R3 — enforcement bridge.** Install `.omp/hooks/pre/loa-guards.ts`, an OMP
  `tool_call` factory that translates OMP events into the Claude PreToolUse wire
  contract and **shells Loa's canonical bash guards verbatim** (single source of
  policy truth — same pattern as the worldline kit's `portable_gate.sh`).
  [`kit/hooks/pre/loa-guards.ts`](./kit/hooks/pre/loa-guards.ts)

Safe by design: the installer **never edits `.claude/`** (System Zone), never
overwrites existing `.omp/` files without `--force`, and the `AGENTS.md` edit is
append-only + idempotent.

### Install (opt-in, per repo)

```bash
bash grimoires/loa/proposals/omp-harness-support/kit/install-omp.sh --root .
# then restart OMP (hooks + skills + context load at startup)
```

### Review by running it

```bash
# adapter unit test — drives mock OMP events through the guard bridge
bun grimoires/loa/proposals/omp-harness-support/kit/tests/test_loa_guards.mjs
# → 4/4: rm -rf / BLOCKS (canonical guard reason relayed), ls ALLOWS,
#        write ALLOWS, edit hashline path parsed
```

The adapter blocks `rm -rf /` with the real `block-destructive-bash.sh` reason —
enforcement is a passing test under OMP, not a claim.

## What already works first-class under OMP (no action)

- **Slash commands** — `.claude/commands/**` read recursively (priority 80).
- **Skills** — flat `.claude/skills/*/SKILL.md` (symlink farm is realpath-safe).
- **MCP** — `.claude/` MCP configs discovered.
- **cheval model routing** — already multi-harness (headless + HTTP adapters).

## Sequencing (proposal → opt-in → core)

1. **This PR** — proposal + runnable kit reviewed as spec. Wires nothing.
2. **Opt-in adoption** — operators run `install-omp.sh`; validate in real OMP sessions.
3. **Core-installer integration** (follow-up PR, gated):
   - **R1' in `agents-md-gen.sh`** — emit the kernel `@`-import at the top of the
     generated `AGENTS.md` (updates the determinism `--check` golden).
     Insertion point: after the generated banner, before the first section.
   - **Installer generates `.omp/`** — `mount-loa.sh` / method-1 symlinks add an
     `.omp/hooks/pre/` + `.omp/RULES.md` projection alongside the `.claude/` set.
   - **Parameterize `native_runtime`** — `adapters/loa_cheval/routing/resolver.py`
     hardcodes `claude-code:session`; make the native runtime id configurable so
     `requires.native_runtime` agents dispatch under OMP.
   - **OMP headless dispatch backend** — add a `pi`/`omp` provider to
     `spiral-harness.sh` / cheval so `/run`,`/simstim`,`/spiral` can drive an OMP
     session instead of hardcoded `claude -p`.

## Honesty caveats

- The kit bridges the two **universal** PreToolUse guards
  (`block-destructive-bash`, `zone-write-guard`). Team/spiral-mode guards need
  their runtime env and are left as documented extension points.
- `zone-write-guard` enforces only when `grimoires/loa/zones.yaml` exists; a
  Loa install without it fail-opens under **both** harnesses (Claude leans on
  `settings.json permissions.deny`, which OMP also ignores). Shipping a default
  `zones.yaml` is orthogonal, tracked separately.
- The adapter is validated by unit test + a live in-session bridge check; a full
  end-to-end run inside a fresh OMP session (hooks load at startup) is the next
  confirmation step.
- `curl | sh` is not currently in `block-destructive-bash`'s pattern set — the
  adapter faithfully relays the guard's decision; broadening the guard is a
  separate change.
