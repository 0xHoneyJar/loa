# Migration Guide: ck Semantic Search Integration

**From**: Loa v0.7.x
**To**: Loa v0.8.0 (ck Integration)
**Estimated Time**: 5-10 minutes

---

## Overview

This guide covers migrating existing Loa projects to v0.8.0 with the optional `ck` semantic search integration. The migration is **non-breaking** - your existing workflow will continue to work unchanged.

---

## Pre-Migration Checklist

- [ ] Git working tree is clean (`git status`)
- [ ] Existing grimoire backed up (or committed to git)
- [ ] Rust toolchain installed (if you want semantic search)

---

## Migration Steps

### Step 1: Backup Your Grimoire

```bash
# Option A: Copy to backup directory
cp -r loa-grimoire loa-grimoire.backup.$(date +%Y%m%d)

# Option B: Commit current state (recommended)
git add loa-grimoire/
git commit -m "backup: pre-ck-integration grimoire state"
```

### Step 2: Update the Framework

```bash
# If using git subtree
git pull origin main

# If using npm/pnpm
pnpm update loa-framework

# If using the update script
.claude/scripts/update.sh
```

### Step 3: Install ck (Optional)

**Prerequisites**: Rust toolchain (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)

```bash
# Install ck
cargo install ck-search

# Verify installation
ck --version
# Expected: ck 0.x.x

# Optional: Install bd for issue tracking
npm install -g beads-cli
bd --version
```

**Note**: If you skip this step, Loa will continue working with grep-based search.

### Step 4: Run /setup

```bash
# In your Claude Code session
/setup
```

Expected output (with ck installed):
```
✓ ck installed: 0.5.2
✓ bd installed: 1.0.0
Setup complete with full enhancement suite.
```

Expected output (without ck):
```
○ ck not installed (optional)
  For semantic search: cargo install ck-search
Setup complete. For enhanced capabilities, see INSTALLATION.md
```

### Step 5: Re-run /ride

```bash
# Generate updated drift report with semantic analysis
/ride
```

This will:
1. Index your codebase (if ck installed)
2. Extract code reality
3. Detect Ghost Features (documented but not implemented)
4. Classify Shadow Systems (implemented but not documented)
5. Generate drift report

### Step 6: Review Changes

Check the following files for updates:
- `loa-grimoire/reality/drift-report.md` - Code vs documentation drift
- `loa-grimoire/NOTES.md` - Agent working memory
- `.beads/` - Ghost/Shadow issues (if bd installed)

---

## What Changes

### New Files Created
| File | Purpose |
|------|---------|
| `.ck/` | Semantic search index (gitignored) |
| `loa-grimoire/a2a/trajectory/*.jsonl` | Agent reasoning logs (gitignored) |

### Files Modified
| File | Change |
|------|--------|
| `loa-grimoire/reality/drift-report.md` | Enhanced with Ghost/Shadow analysis |
| `loa-grimoire/NOTES.md` | Updated session continuity |
| `.gitignore` | Added `.ck/` and trajectory entries |

### New Capabilities
1. **Semantic search** - Find code by meaning, not just keywords
2. **Ghost detection** - Identify promised but missing features
3. **Shadow classification** - Categorize undocumented code
4. **Trajectory logging** - Audit trail for agent decisions

---

## Rollback Instructions

If you encounter issues after migration:

### Option A: Restore from Backup
```bash
# Remove new files
rm -rf .ck/
rm -rf loa-grimoire/a2a/trajectory/

# Restore backup
rm -rf loa-grimoire
mv loa-grimoire.backup.YYYYMMDD loa-grimoire
```

### Option B: Git Reset
```bash
# Reset to pre-migration commit
git log --oneline  # Find backup commit
git reset --hard <backup-commit-hash>
```

### Option C: Uninstall ck
```bash
# Remove ck (Loa will fall back to grep)
cargo uninstall ck-search

# Remove index
rm -rf .ck/
```

---

## FAQ

### Q: Do I need to install ck?
**A**: No. ck is optional. Loa works perfectly with grep-based search. ck provides enhanced semantic understanding for large codebases.

### Q: Will my existing commands change?
**A**: No. All commands work identically. The only difference is improved precision with ck installed.

### Q: How much disk space does the index use?
**A**: Approximately 10-50MB per repository, depending on codebase size. The index is stored in `.ck/` and is gitignored.

### Q: How long does indexing take?
**A**:
- Small codebase (<10K LOC): ~10 seconds
- Medium codebase (10K-100K LOC): ~30-60 seconds
- Large codebase (>100K LOC): 1-5 minutes

Delta reindexing after changes is much faster.

### Q: Can I use ck with other tools?
**A**: Yes. ck is a standalone CLI tool. You can use it directly for ad-hoc searches outside of Loa.

### Q: What if ck crashes or becomes unavailable?
**A**: Loa automatically falls back to grep. You won't notice any difference in functionality, just slightly reduced precision on semantic queries.

### Q: Do I need to reindex manually?
**A**: No. Loa handles indexing automatically. Delta reindexing happens when the index is stale.

### Q: Where are the trajectory logs?
**A**: `loa-grimoire/a2a/trajectory/YYYY-MM-DD.jsonl`. These are gitignored and auto-archived after 7 days.

### Q: What is a "Ghost Feature"?
**A**: A feature documented in your PRD/SDD but not found in the codebase. The Negative Grounding protocol verifies this with 2+ diverse searches returning 0 results.

### Q: What is a "Shadow System"?
**A**: Code that exists in your codebase but isn't documented. Classified as:
- **Orphaned**: No references in any documentation
- **Drifted**: References exist but descriptions don't match
- **Partial**: Partially documented

---

## Troubleshooting

### "ck: command not found"
```bash
# Ensure Rust/Cargo bin is in PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Or reinstall
cargo install ck-search
```

### ".ck/ permission denied"
```bash
# Remove corrupted index
rm -rf .ck/

# Run /ride to regenerate
/ride
```

### "Index corrupt or outdated"
```bash
# Force full reindex
rm -rf .ck/
ck --index . --quiet
```

### Slow indexing on large codebase
```bash
# Index in background
nohup ck --index . --quiet &

# Check progress
ls -la .ck/
```

---

## Support

For issues specific to ck integration:
1. Check this migration guide
2. Review `RELEASE_NOTES_CK_INTEGRATION.md`
3. Open an issue on GitHub

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
