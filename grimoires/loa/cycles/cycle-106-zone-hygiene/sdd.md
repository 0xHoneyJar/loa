# Cycle-106 SDD: Framework Template Hygiene

> **Predecessor**: `prd.md`
> **Cycle**: cycle-106-zone-hygiene
> **Created**: 2026-05-12

---

## 1. Architecture

The framework currently ships with NO explicit zone boundary. Both
framework-zone files (`.claude/`) and project-zone files (`grimoires/loa/`)
sit under the same tree. The implicit rule "edit `.claude/` only via
overrides" is human convention, not machine-enforced. `/update-loa`
merges the entire framework repo wholesale; downstream gets ADDs into
paths it should own.

Cycle-106 lands a 3-part fix:

1. **`zones.yaml` manifest** — operator-readable + machine-readable
   declaration of which paths are framework / project / shared.
2. **PreToolUse hook** — write-time enforcement against the manifest.
3. **/update-loa merge filter** — read-time enforcement during framework
   merges; skips ADDs that would cross zone boundaries.

```
  +---------------------------+      +--------------------------+
  | grimoires/loa/zones.yaml  |─────▶| zone-write-guard.sh      |
  | (project-authored)        |      | (PreToolUse:Write/Edit)  |
  +---------------------------+      +--------------------------+
              │                                  │ blocks zone-violating
              │                                  │ writes
              ▼                                  ▼
  +---------------------------+      +--------------------------+
  | .claude/data/zones.schema |      | git working tree         |
  | (framework-authored)      |      | (writes filtered)        |
  +---------------------------+      +--------------------------+
              ▲                                  ▲
              │ validates                        │
              │                                  │
  +---------------------------+      +--------------------------+
  | /update-loa Phase 5.X     |─────▶| --diff-filter=A ADDs     |
  | zone-aware merge filter   |      | into project-zone paths  |
  +---------------------------+      | are dropped before commit│
                                     +--------------------------+
```

## 2. The zone manifest

### 2.1 Schema (`.claude/data/zones.schema.yaml`)

Versioned JSON Schema (Draft 2020-12). Validates the shape of
`grimoires/loa/zones.yaml`. Ships in framework-zone.

```yaml
$schema: "https://json-schema.org/draft/2020-12/schema"
$id: "https://0xhoneyjar.github.io/loa/schemas/zones.schema.json"
title: "Loa Zone Manifest"
description: |
  Declares which paths in a Loa-mounted project belong to framework-zone
  (propagate from upstream via /update-loa) vs project-zone (owned by
  the operator; never overwritten by /update-loa) vs shared (merge with
  conflict surfacing).

type: object
required: [schema_version, zones]
additionalProperties: false
properties:
  schema_version:
    type: string
    pattern: "^1\\."
    description: "Schema major.minor version. Currently 1.0."
  zones:
    type: object
    required: [framework, project]
    additionalProperties: false
    properties:
      framework:
        $ref: "#/$defs/zone"
      project:
        $ref: "#/$defs/zone"
      shared:
        $ref: "#/$defs/zone"

$defs:
  zone:
    type: object
    required: [tracked_paths]
    additionalProperties: false
    properties:
      tracked_paths:
        type: array
        items:
          type: string
          # Path globs (POSIX); ** for recursive match.
        minItems: 1
      description:
        type: string
```

### 2.2 Framework instance (`grimoires/loa/zones.yaml`)

```yaml
schema_version: "1.0"

zones:
  framework:
    description: |
      Framework-managed; /update-loa propagates from upstream.
      Operators should NOT modify these directly — use overrides or
      issue/PR upstream.
    tracked_paths:
      - ".claude/loa/**"
      - ".claude/scripts/**"
      - ".claude/data/**"
      - ".claude/skills/**"
      - ".claude/hooks/**"
      - ".claude/protocols/**"
      - ".claude/rules/**"
      - ".claude/commands/**"
      - "tools/**"
      - "grimoires/loa/runbooks/**"     # framework-shipped runbooks
      - "grimoires/loa/.gitignore"

  project:
    description: |
      Operator-owned; /update-loa MUST NOT propagate the framework's
      version of these. Each project's content is sovereign.
    tracked_paths:
      - "grimoires/loa/cycles/**"        # operator's cycle history
      - "grimoires/loa/NOTES.md"         # operator's decision log
      - "grimoires/loa/handoffs/**"      # operator's session handoffs
      - "grimoires/loa/a2a/**"           # operator's agent-to-agent state
      - "grimoires/loa/visions/**"       # operator's visions registry
      - "grimoires/loa/memory/**"        # operator's persistent memory
      - "grimoires/loa/proposals/**"     # operator's proposals
      - "grimoires/loa/legacy/**"        # operator's legacy artifacts
      - "grimoires/loa/context/**"       # operator's context docs
      - "grimoires/loa/archive/**"       # already gitignored; declared for completeness
      - "grimoires/loa/ledger.json"      # operator's sprint ledger
      - "grimoires/loa/ledger.json.bak*" # backup snapshots
      - "BUTTERFREEZONE.md"
      - "CHANGELOG.md"
      - "README.md"
      - "SOUL.md"

  shared:
    description: |
      Both framework and project contribute. /update-loa merges
      sections; overlap surfaces as a conflict for operator resolution.
    tracked_paths:
      - "grimoires/loa/known-failures.md"   # framework ships universal entries; projects add their own
      - "grimoires/loa/MEMORY.md"           # if shared between framework + projects
```

### 2.3 New-install seeding

`mount-loa` reads the framework's `grimoires/loa/zones.yaml` and:
- Copies framework-zone paths verbatim
- Creates project-zone paths as EMPTY directories (or empty files for single-file paths like `NOTES.md`)
- For shared paths: copies the framework's content as the initial seed; operator can edit going forward

## 3. PreToolUse hook — `.claude/hooks/safety/zone-write-guard.sh`

### 3.1 Surface

Triggered by `PreToolUse:Write` and `PreToolUse:Edit`. Reads the
target path + actor identity + `grimoires/loa/zones.yaml`. Decides
ALLOW / BLOCK.

Inputs (via hook env):
- `CLAUDE_TOOL_FILE_PATH` — the path being written
- `LOA_ACTOR` — caller identity (`project-work` / `update-loa` /
  `sync-constructs` / `unknown`). When unset, the hook treats the
  caller as `project-work` (the default + most common case).

Decision matrix:

| Path zone | Actor | Decision |
|-----------|-------|----------|
| framework | `project-work` | BLOCK with "framework-zone is upstream-managed; use overrides" |
| framework | `update-loa` | ALLOW |
| framework | other | BLOCK + log |
| project | `project-work` | ALLOW |
| project | `update-loa` | BLOCK with "update-loa MUST NOT write project-zone paths" |
| project | other | ALLOW (let other tools work; project-zone is operator-owned) |
| shared | any | ALLOW |
| (not classified) | any | ALLOW (zones.yaml is positive declaration; unclassified = no opinion) |

### 3.2 Escape hatches

- `LOA_ZONE_GUARD_BYPASS=1` — environment-level operator override.
  Hook emits a stderr WARNING + logs to trajectory + ALLOWs.
- `LOA_ZONE_GUARD_DISABLE=1` — disables the hook entirely (skips even
  the check). Reserved for framework upgrade bootstrap.

### 3.3 Diagnostic format

When BLOCKING:

```
[zone-write-guard] BLOCKED: actor=<actor> path=<path> zone=<zone>
  Reason: <human readable>
  Override: LOA_ZONE_GUARD_BYPASS=1 <retry command>
  Reference: grimoires/loa/runbooks/zone-hygiene.md
```

## 4. `/update-loa` merge filter — Phase 5.X

After the existing Phase 5.3 deletion-protection step but before
Phase 5.5 protected-paths revert:

```bash
# Phase 5.X (NEW): drop ADDs into project-zone paths.
# Required because the framework's tracked grimoires/loa/cycles/, NOTES.md
# etc. would otherwise propagate into downstream consumers' history.

if [ -f grimoires/loa/zones.yaml ]; then
    project_zone_paths=$(yq '.zones.project.tracked_paths[]' grimoires/loa/zones.yaml)
    added=$(git diff --cached --diff-filter=A --name-only)
    dropped=()
    for f in $added; do
        for pat in $project_zone_paths; do
            if path_matches_glob "$f" "$pat"; then
                git rm --cached -- "$f" 2>/dev/null
                rm -f "$f"
                dropped+=("$f ($pat)")
                break
            fi
        done
    done
    if [ ${#dropped[@]} -gt 0 ]; then
        echo "[update-loa] Zone-filter: dropped ${#dropped[@]} ADD(s) into project-zone:" >&2
        printf '  - %s\n' "${dropped[@]}" >&2
    fi
fi
```

`path_matches_glob` uses bash `[[ "$path" == $pattern ]]` with
`extglob` enabled (handles `**` and `*` correctly).

## 5. Gitignore tightening

`.gitignore` adds (cycle-106 sprint-1):

```
# cycle-106: framework-zone vs project-zone separation.
# Framework's own operator history must NOT track into the template.
# Each operator's working tree keeps these locally; git ignores them.
grimoires/loa/cycles/
grimoires/loa/NOTES.md
grimoires/loa/handoffs/
grimoires/loa/a2a/
grimoires/loa/visions/
grimoires/loa/memory/
grimoires/loa/proposals/
grimoires/loa/legacy/
grimoires/loa/context/
grimoires/loa/ledger.json.bak*
```

NOT gitignored (still tracked):
- `grimoires/loa/zones.yaml` (project-authored, version-controlled)
- `grimoires/loa/runbooks/` (framework-shipped runbooks)
- `grimoires/loa/known-failures.md` (shared zone)
- `grimoires/loa/ledger.json` (project sprint ledger; tracked per project)

## 6. Migration: `git rm --cached` going forward

Cycles 098-105 are currently tracked. The cycle-106 inflection commit
runs:

```bash
git rm --cached -r grimoires/loa/cycles/ \
                    grimoires/loa/NOTES.md \
                    grimoires/loa/handoffs/ \
                    grimoires/loa/a2a/ \
                    grimoires/loa/visions/ \
                    grimoires/loa/memory/ \
                    grimoires/loa/proposals/ \
                    grimoires/loa/legacy/ \
                    grimoires/loa/context/ \
                    grimoires/loa/ledger.json.bak*
```

**Important**: `--cached` un-tracks WITHOUT deleting from working tree.
The operator's local files are preserved. After commit, `git ls-files`
shows the project-zone paths absent; `find grimoires/loa/cycles/` still
shows the directories on disk.

History is NOT rewritten. Old commits still contain the cycle files;
new commits forward of the inflection point don't. This is intentional:
- Downstream consumers who already pulled the framework history keep
  the legacy files in their git log (cleanup is their concern, per
  their own cycle-0 plan).
- Future `/update-loa` merges only propagate post-inflection commits;
  the merge filter from §4 covers the bridge period.

## 7. `mount-loa` seeding

Update `.claude/skills/mounting-framework/` (or whatever the install
skill is) to:

1. Read framework's `grimoires/loa/zones.yaml`.
2. For each `project` path:
   - If it's a directory pattern (`grimoires/loa/cycles/**`), create
     empty `grimoires/loa/cycles/.gitkeep` in the new install.
   - If it's a single file (`grimoires/loa/NOTES.md`), create an empty
     stub with a comment block: "Operator working notes — gitignored
     by the framework, owned by your project."
3. For each `framework` path: copy verbatim.
4. For each `shared` path: copy as initial seed.
5. Write a CLAIM marker `grimoires/loa/.zones-claim` recording the
   schema_version and instance hash at mount time.

## 8. Test strategy

### 8.1 Unit tests

`tests/unit/zone-write-guard.bats` (10-12 tests):
- ZWG-T1 project work writes project-zone path → ALLOW
- ZWG-T2 project work writes framework-zone path → BLOCK
- ZWG-T3 update-loa writes framework-zone path → ALLOW
- ZWG-T4 update-loa writes project-zone path → BLOCK
- ZWG-T5 shared zone any actor → ALLOW
- ZWG-T6 unclassified path → ALLOW (positive declaration only)
- ZWG-T7 LOA_ZONE_GUARD_BYPASS=1 + WARN to stderr → ALLOW
- ZWG-T8 LOA_ZONE_GUARD_DISABLE=1 → ALLOW with no diagnostic
- ZWG-T9 missing zones.yaml → ALLOW with WARN (graceful degradation)
- ZWG-T10 malformed zones.yaml → BLOCK with schema validation error
- ZWG-T11 glob pattern matching (`/foo/**` matches `/foo/bar/baz`)
- ZWG-T12 trajectory log entry for blocked + bypassed events

### 8.2 Integration tests

`tests/integration/update-loa-zone-filter.bats` (5-6 tests):
- ULZF-T1 synthetic ADD into `grimoires/loa/cycles/cycle-test/` → filtered, file absent from working tree post-merge
- ULZF-T2 synthetic ADD into `.claude/scripts/new.sh` (framework zone) → propagated, file present
- ULZF-T3 synthetic ADD into `grimoires/loa/known-failures.md` modification → propagated (shared zone)
- ULZF-T4 stdout/stderr diagnostic includes the dropped file list
- ULZF-T5 missing zones.yaml → noop (legacy behavior preserved)
- ULZF-T6 malformed zones.yaml → bail with diagnostic (no merge proceed)

### 8.3 Schema validation

`tests/unit/zones-schema.bats` (4-5 tests):
- ZS-T1 valid framework zones.yaml validates clean
- ZS-T2 missing required field (`schema_version`) → schema error
- ZS-T3 unknown zone (`evil_zone`) → schema error
- ZS-T4 path that's not a string → schema error
- ZS-T5 schema_version 2.x → schema error (until 2.0 specced)

## 9. CI gate

`.github/workflows/zone-hygiene.yml` (new):

- Runs zone-write-guard.bats + update-loa-zone-filter.bats +
  zones-schema.bats on every PR touching:
  - `.claude/hooks/safety/zone-write-guard.sh`
  - `.claude/data/zones.schema.yaml`
  - `grimoires/loa/zones.yaml`
  - `.claude/scripts/update-loa.sh` (or wherever the merge logic lives)
  - test files
- Asserts `git ls-files grimoires/loa/cycles/` returns zero entries
  on main (regression gate against future leaks).

## 10. Q&A

**Q1: Why declare `grimoires/loa/runbooks/` as framework-zone? Operators write runbooks for their projects.**
A1: The framework SHIPS canonical runbooks (cheval-delegate-architecture, headless-mode, chain-walk-debugging) — those should propagate via /update-loa. Operators authoring their OWN runbooks for their own project use a different location (`docs/`, `RUNBOOKS.md`, or wherever) so they don't conflict. The framework's runbooks/ directory belongs to the framework.

**Q2: What about `grimoires/loa/known-failures.md` — universal entries vs operator-specific reproductions?**
A2: Shared zone. /update-loa propagates the framework's KF library, but doesn't touch project-specific evidence rows. The merge surfaces conflicts when both sides edit the same KF entry; operator resolves. Per §2.2 the schema allows `shared` zone for this case.

**Q3: How does the migration handle Loa-the-framework's OWN /update-loa?**
A3: Loa-the-framework doesn't run /update-loa against itself. The inflection commit on `main` is just a normal commit. Downstream consumers receive the filter logic via their next /update-loa, which will then drop any framework-cycle ADDs.

**Q4: Will this break existing downstream consumers who already pulled the cycle history?**
A4: No. Their git history is unchanged (we don't force-push); their working tree is unchanged (they keep the legacy files). The bleed STOPS forward. Downstream's cycle-0 (per issue #818) handles their own legacy cleanup.

**Q5: Why not just rewrite framework history?**
A5: Force-push to main breaks every downstream consumer's existing clone. Cost-benefit is wrong. "Stop the bleed forward" is the canonical answer.

---

🤖 Generated as cycle-106 SDD, 2026-05-12. Next step: `/sprint-plan` to break this into ~12 tasks across 2 sprints.
