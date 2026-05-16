# Zone Hygiene (operator runbook)

> **Audience**: Loa operators who want to understand the framework-zone vs project-zone boundary, edit their project's `zones.yaml`, or handle a zone-write-guard BLOCK diagnostic.
>
> **Cycle**: cycle-106 sprint-2 T2.5. Closes the boundary leak documented in [#818](https://github.com/0xHoneyJar/loa/issues/818).

---

## 1. What the zones are

Loa-mounted projects have content from two sources:

1. **The framework** — code, scripts, schemas, hooks, protocols, runbooks shipped by `0xHoneyJar/loa` upstream.
2. **The operator** — your project's cycles, decision notes, agent-to-agent state, sprint handoffs, vision entries.

Before cycle-106 these mingled. Result: framework operators' history leaked into downstream installs via `/update-loa` merges (#818); downstream operators couldn't tell which files were "their work" vs "the framework's lived experience".

Cycle-106 lands a 3-mode zone manifest at `grimoires/loa/zones.yaml`:

| Mode | Semantics | Who writes? | Propagates via /update-loa? |
|------|-----------|-------------|----------------------------|
| `framework` | Owned by the framework upstream | `update-loa` actor | yes |
| `project` | Owned by you, the operator | `project-work` actor | **no** |
| `shared` | Both contribute | both actors | merge; conflict on overlap |

The manifest at `grimoires/loa/zones.yaml` lists path globs per mode. The framework's own seed instance is what you got at `mount-loa` time; you can edit it to match your project's conventions.

## 2. The three enforcement layers

### 2.1 Schema (compile-time)

`.claude/data/zones.schema.yaml` is the JSON Schema validating the manifest. If you edit `grimoires/loa/zones.yaml` to add a path or rename a zone, run:

```bash
bats tests/unit/zones-schema.bats
```

Schema rejects: unknown zone names, non-string paths, empty `tracked_paths` arrays, future `schema_version` values.

### 2.2 Hook (write-time)

`.claude/hooks/safety/zone-write-guard.sh` runs as PreToolUse on Write/Edit. It reads zones.yaml + the actor identity (`LOA_ACTOR` env var, defaults to `project-work`) and ALLOWs or BLOCKs the write.

**Decision matrix**:

| Path zone | Actor | Decision |
|-----------|-------|----------|
| framework | `project-work` | **BLOCK** ("framework-zone is upstream-managed; use overrides") |
| framework | `update-loa` | ALLOW |
| project | `project-work` | ALLOW |
| project | `update-loa` | **BLOCK** ("/update-loa MUST NOT write project-zone paths") |
| shared | any | ALLOW |
| unclassified | any | ALLOW (positive declaration only) |

### 2.3 Gitignore (commit-time)

The framework's `.gitignore` keeps project-zone paths out of the framework's own tracked tree. New operators cloning `0xHoneyJar/loa` get an empty project-zone scaffolding via `mount-loa`'s `clean_grimoire_state`, not the framework's lived history.

## 3. When you see a BLOCK diagnostic

The hook emits:

```
[zone-write-guard] BLOCKED: actor=<actor> path=<path> zone=<zone>
  Reason: <human readable>
  Override: LOA_ZONE_GUARD_BYPASS=1 <retry command>
  Reference: grimoires/loa/runbooks/zone-hygiene.md
```

Three common causes + responses:

### 3.1 "framework-zone is upstream-managed"

You tried to edit a framework file (e.g., `.claude/scripts/some-script.sh`) directly. **Don't do this** — your edit will conflict with the next `/update-loa`.

**The right path:**
- For configuration knobs: edit `.loa.config.yaml`
- For tool overrides: use `.claude/overrides/`
- For genuine framework bugs/missing features: file an issue at `0xHoneyJar/loa`

If you need to override the hook for a one-shot (legitimate framework debugging, etc.):

```bash
LOA_ZONE_GUARD_BYPASS=1 <retry command>
```

The bypass emits a stderr WARN + logs to trajectory. Don't bake it into your workflow — bypasses are for triage, not routine work.

### 3.2 "update-loa MUST NOT write project-zone paths"

Something is invoking the hook with `LOA_ACTOR=update-loa` and trying to write a project-zone path. This means /update-loa or sync-constructs is attempting to pull a project-zone file from upstream. The hook blocks it — your project state is sovereign.

You shouldn't see this in normal use. If you do, file an issue with the path that was blocked.

### 3.3 "actor=<X> not authorized to write framework zone"

Some other actor (not `project-work` and not `update-loa`) tried to write a framework path. Most likely a misconfigured script set `LOA_ACTOR` to something unexpected. Inspect your env + retry with the correct actor identity.

## 4. Editing your `zones.yaml`

The framework seeds your `grimoires/loa/zones.yaml` with reasonable defaults. You own the file going forward.

**Common edits:**

- Add a project-specific path: append to `zones.project.tracked_paths`. E.g., if your project has `docs/operator-notes/` that should never be framework-overwritten:

  ```yaml
  zones:
    project:
      tracked_paths:
        # ... existing ...
        - "docs/operator-notes/**"
  ```

- Mark a path as shared (both framework + project contribute): move it from `project` (or `framework`) into `shared`. E.g., custom rules:

  ```yaml
  zones:
    shared:
      tracked_paths:
        - "grimoires/loa/known-failures.md"
        - "docs/operator-rules.md"   # shared between framework guidelines + your additions
  ```

Validate after edits:

```bash
bats tests/unit/zones-schema.bats
```

## 5. The `shared` zone — conflict handling

Files in shared zone (default: `known-failures.md`, `MEMORY.md`) accumulate framework content AND project additions. When `/update-loa` merges, an overlap surfaces as a git merge conflict for you to resolve.

**Conflict resolution pattern:**

1. Framework's section (universal entries like KF-001 through KF-008) — accept upstream.
2. Project's section (your additions like KF-100 if you've added project-specific entries) — accept yours.
3. If both sides edited the same entry: read both, pick the better one, hand-merge.

Use `git diff --cc` to see the 3-way merge view; resolve; `git add` the file; continue the merge.

## 6. New operator install: what you get

When a new operator runs `mount-loa` on a fresh project, the `clean_grimoire_state` function ensures:

- `grimoires/loa/zones.yaml` — seeded from framework
- `grimoires/loa/runbooks/` — framework-shipped runbooks (this file among them)
- `grimoires/loa/known-failures.md` — framework's universal KF library
- `grimoires/loa/ledger.json` — empty (`{"cycles": [], "active_cycle": null}`)
- `grimoires/loa/NOTES.md` — empty template
- `grimoires/loa/cycles/`, `handoffs/`, `visions/entries/`, `a2a/trajectory/`, `archive/`, `context/`, `memory/`, `legacy/` — empty directories

You do NOT get:
- The framework's cycle history (cycles 098-105)
- The framework's operator's NOTES.md entries
- The framework's operator's vision registry entries
- Any framework operator-specific lived experience

You DO get all the framework knowledge needed to operate: protocols, schemas, scripts, hooks, runbooks (including this one), known-failures library.

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Hook BLOCKs every Write attempt | `LOA_ACTOR` not set + path is framework-zone | Operator's day-to-day writes shouldn't touch `.claude/` — use `.loa.config.yaml` or `.claude/overrides/` |
| Hook silently allows everything | Hook not registered with Claude Code | Run `.claude/scripts/install-loa-hooks.sh` (or check your harness's PreToolUse registration) |
| Schema validation fails after edit | YAML typo or unknown key | Run `bats tests/unit/zones-schema.bats` for the exact line + reason |
| `git ls-files grimoires/loa/cycles/` shows files | gitignore not applied OR pre-cycle-106 history | If pre-cycle-106 clone, run `git rm --cached -r grimoires/loa/cycles/` locally |

## 8. Related

- Issue [#818](https://github.com/0xHoneyJar/loa/issues/818) — original zone-leak bug
- `.claude/data/zones.schema.yaml` — the schema
- `.claude/hooks/safety/zone-write-guard.sh` — the hook
- `tests/unit/zone-write-guard.bats` — hook behavior pins
- `tests/unit/zones-schema.bats` — schema validation pins
- `grimoires/loa/cycles/cycle-106-zone-hygiene/sdd.md` — full design doc
