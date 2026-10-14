---
name: loa-eject
description: Eject from Loa framework - transfer full ownership of all framework files to user
output: Ejected project with all framework files owned by user
command_type: wizard
---

# /loa eject - Framework Eject Command

## Purpose

Transfer full ownership of all Loa framework files to the user, permanently detaching from the managed framework model. After ejection:
- All framework files become user-owned
- Framework updates via `/update-loa` no longer work
- Magic markers and integrity hashes are removed
- The `loa-` prefix is removed from skill/command names (if present)

## Invocation

```
/loa eject              # Full eject with confirmation
/loa eject --dry-run    # Preview what would change
/loa eject --force      # Skip confirmation prompt
/loa eject --include-packs  # Also eject pack-installed content
```

## Workflow

### 1. Pre-flight Check

Before starting, verify:
- `.claude/` directory exists (Loa is mounted)
- Not already ejected (`ejected: true` not in config)
- Required tools available (grep, sed)

### 2. Display Warning

Show comprehensive warning about implications:

```
=======================================================================
                    LOA FRAMEWORK EJECT WARNING
=======================================================================

This will permanently transfer ownership of all Loa framework files
to your project. After ejection:

  x Framework updates via /update-loa will no longer work
  x All automatic integrity verification will be disabled
  x You will be responsible for all future maintenance

  + You gain full control over all framework files
  + Magic markers and hashes will be removed
  + All files become your files

A backup will be created at: .claude.backup.{timestamp}/

=======================================================================
```

### 3. Require Confirmation

Unless `--force` is passed, require user to type "eject" to confirm:

```
To confirm ejection, type 'eject' and press Enter:
>
```

### 4. Execute Eject Script

Run the eject script:

```bash
.claude/scripts/loa-eject.sh [--dry-run] [--force] [--include-packs]
```

The script performs:

1. **Backup Creation**: `.claude.backup.{timestamp}/`
2. **Marker Removal**: Remove `@loa-managed` markers from all files
3. **Prefix Removal**: Remove `loa-` prefix from skills/commands (if present)
4. **CLAUDE.md Merge**: Merge framework instructions into CLAUDE.md
5. **Import Removal**: Remove `@.claude/loa/CLAUDE.loa.md` import
6. **Config Update**: Set `ejected: true` and `ejected_at` timestamp

### 5. Post-Eject Instructions

Display guidance for next steps:

```
=======================================================================
                    EJECT COMPLETE
=======================================================================

Your project is now fully independent from the Loa framework.

What changed:
  - Backup created at: .claude.backup.{timestamp}/
  - Magic markers removed from all framework files
  - Framework instructions merged into CLAUDE.md
  - Config updated with ejected: true

Next steps:
  1. Review CLAUDE.md to ensure instructions are as expected
  2. Commit the changes: git add -A && git commit -m 'chore: eject from Loa'
  3. Consider deleting the backup once verified

If something went wrong:
  1. Restore from backup: rm -rf .claude && cp -r .claude.backup.* .claude
  2. Restore config files from backup
```

## Options Reference

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would change without making changes |
| `--force` | Skip the confirmation prompt |
| `--include-packs` | Also eject pack-installed content from `.claude/constructs/` |

## What Gets Ejected

### Always Ejected

| Category | Files | Action |
|----------|-------|--------|
| Scripts | `.claude/scripts/*.sh` | Remove markers |
| Skills | `.claude/skills/*/index.yaml`, `SKILL.md` | Remove markers, rename if `loa-*` |
| Commands | `.claude/commands/*.md` | Remove markers, rename if `loa-*` |
| Protocols | `.claude/protocols/*.md` | Remove markers |
| Schemas | `.claude/schemas/*.json` | Remove `_loa_marker` key |
| Framework Instructions | `.claude/loa/CLAUDE.loa.md` | Merge into CLAUDE.md |

### Conditionally Ejected (--include-packs)

| Category | Path | Action |
|----------|------|--------|
| Pack Skills | `.claude/constructs/packs/*/skills/` | Remove markers |
| Pack Commands | `.claude/constructs/packs/*/commands/` | Remove markers |
| Registry Skills | `.claude/constructs/skills/` | Remove markers |

### Never Modified

| Category | Path | Reason |
|----------|------|--------|
| User Overrides | `.claude/overrides/` | Already user-owned |
| User Config | `.loa.config.yaml` | Only `ejected` fields added |
| State Files | `grimoires/loa/` | State zone, user-owned |

## Prefix Removal Details

If skills/commands have the `loa-` prefix:

### Skills

```
.claude/skills/loa-discovering-requirements/
  -> .claude/skills/discovering-requirements/

index.yaml:
  name: loa-discovering-requirements
  -> name: discovering-requirements
```

### Commands

```
.claude/commands/loa-implement.md
  -> .claude/commands/implement.md

Frontmatter:
  name: loa-implement
  -> name: implement
```

**Note**: The `/loa` command file (`loa.md`) is NOT renamed.

## CLAUDE.md Merge

Before eject:

```markdown
@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions
...user content...
```

After eject:

```markdown
# Combined Instructions (Ejected from Loa)

> This file was created by loa-eject. The framework instructions have been
> merged with your project-specific instructions. You now own all content.

---

...framework content...

---

# Project-Specific Instructions

...user content...
```

## Recovery

If you need to undo the eject:

```bash
# Restore from backup
rm -rf .claude
cp -r .claude.backup.{timestamp} .claude
cp .claude.backup.{timestamp}/.loa.config.yaml.backup .loa.config.yaml
cp .claude.backup.{timestamp}/.loa-version.json.backup .loa-version.json

# Or re-mount Loa fresh
rm -rf .claude
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --force
```

## Error Handling

| Error | Resolution |
|-------|------------|
| Not a Loa project | "No .claude/ directory found. Is Loa mounted?" |
| Already ejected | "This project has already been ejected from Loa" |
| Backup failed | Check disk space, permissions |
| Merge failed | Manually merge CLAUDE.md from backup |

## Configuration

No configuration required. Eject is an opt-in action.

After eject, the config will contain:

```yaml
# Ejected from Loa framework
ejected: true
ejected_at: "2026-02-02T15:30:00Z"
```

## Use Cases

### When to Eject

- **Fork for customization**: You want to heavily customize the framework
- **Freeze version**: Lock to a specific version without updates
- **Remove dependency**: Eliminate the Loa upstream requirement
- **Simplify**: Reduce complexity by owning all code

### When NOT to Eject

- **Just want customization**: Use `.claude/overrides/` instead
- **Just want to disable features**: Use feature gates in config
- **Want to contribute**: Keep connected for `/contribute`
- **Want updates**: Ejection is permanent

## Implementation Notes

1. **Run eject script**: Call `.claude/scripts/loa-eject.sh` with appropriate flags
2. **Handle dry-run mode**: If `--dry-run`, pass to script and show preview
3. **Pass through all flags**: `--force`, `--include-packs`
4. **Show progress**: Display script output to user
5. **Handle errors gracefully**: If script fails, show recovery instructions

## Examples

### Preview Eject

```
User: /loa eject --dry-run

[loa-eject] ---------------------------------------------------------------
[loa-eject]   Loa Framework Eject
[loa-eject] ---------------------------------------------------------------
[loa-eject]   Mode: Dry Run (no changes will be made)

[loa-eject] Running pre-flight checks...
[loa-eject] Pre-flight checks passed
[loa-eject] Starting eject process...
[loa-eject] -> [dry-run] Would create backup at: .claude.backup.20260202_153000
[loa-eject] -> [dry-run] Would remove marker from: .claude/scripts/cache-manager.sh
...
[loa-eject] -> [dry-run] Would merge .claude/loa/CLAUDE.loa.md into CLAUDE.md
[loa-eject] -> [dry-run] Would set ejected: true in .loa.config.yaml

[loa-eject] Dry run complete. No changes were made.
```

### Full Eject

```
User: /loa eject

=======================================================================
                    LOA FRAMEWORK EJECT WARNING
=======================================================================

This will permanently transfer ownership of all Loa framework files
to your project. After ejection:

  x Framework updates via /update-loa will no longer work
  x All automatic integrity verification will be disabled
  x You will be responsible for all future maintenance

  + You gain full control over all framework files
  + Magic markers and hashes will be removed
  + All files become your files

A backup will be created at: .claude.backup.{timestamp}/

=======================================================================

To confirm ejection, type 'eject' and press Enter:
> eject

[loa-eject] Creating backup...
[loa-eject] -> Created backup at: .claude.backup.20260202_153000
[loa-eject] Processing scripts...
[loa-eject] Processed 91 scripts
[loa-eject] Processing skills...
[loa-eject] Processed 15 skills
...
[loa-eject] Eject process complete!

=======================================================================
                    EJECT COMPLETE
=======================================================================

Your project is now fully independent from the Loa framework.

Next steps:
  1. Review CLAUDE.md to ensure instructions are as expected
  2. Commit the changes: git add -A && git commit -m 'chore: eject from Loa'
```
