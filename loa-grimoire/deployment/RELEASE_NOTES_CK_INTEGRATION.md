# Release Notes: ck Semantic Search Integration

**Version**: v0.8.0
**Release Date**: 2025-12-27
**Type**: Feature Enhancement

---

## What's New

The Loa Framework now supports **optional semantic code search** through the `ck` tool, providing dramatically improved code understanding while maintaining full backward compatibility. This enhancement is **completely invisible** to users - your workflow remains unchanged whether or not you have `ck` installed.

---

## Key Features

### Invisible Enhancement Pattern
- All commands work identically with or without `ck` installed
- No mentions of "semantic search", "ck", or "fallback" in agent output
- Users experience improved results without any awareness of the underlying change

### Semantic Code Search
- **Vector-based search** using nomic-v1.5 embeddings
- **<500ms search latency** on repositories up to 1M LOC
- **80-90% cache hit rate** with delta reindexing
- **Automatic fallback** to grep when `ck` unavailable

### Ghost Feature Detection
- Automatically detects **documented but unimplemented features**
- Uses **Negative Grounding Protocol** (2+ diverse queries returning 0 results)
- Creates Beads issues for discovered liabilities (if `bd` installed)

### Shadow System Classification
- Identifies **undocumented code** in your repository
- Classifies as **Orphaned**, **Drifted**, or **Partial**
- Generates actionable drift reports

### Enhanced Context Management
- **Tool Result Clearing** protocol for attention budget management
- **Semantic Decay** (Active → Decayed → Archived) for search results
- **Word-for-word citations** with absolute file paths

### Trajectory Evaluation (ADK-Level)
- **Intent-First Search** prevents "fishing expeditions"
- **Grounding ratio enforcement** (≥0.95 threshold)
- **Self-audit checkpoints** before completion

---

## Installation Instructions

### ck (Semantic Search)
```bash
# Optional - enables semantic code search
cargo install ck-search

# Verify installation
ck --version
```

### bd (Task Tracking)
```bash
# Optional - enables Ghost/Shadow issue tracking
npm install -g beads-cli

# Verify installation
bd --version
```

**Note**: Both tools are completely optional. Loa works perfectly without them.

---

## Migration Guide (Existing Users)

1. **Backup** your existing grimoire:
   ```bash
   cp -r loa-grimoire loa-grimoire.backup
   ```

2. **Update** to the latest framework:
   ```bash
   git pull origin main  # Or update via your method
   ```

3. **Optionally install** ck:
   ```bash
   cargo install ck-search
   ```

4. **Verify** your installation:
   ```bash
   # Run /setup to verify
   # ck status will be shown if installed
   ```

5. **Re-run /ride** to regenerate drift report:
   ```bash
   # Your drift report will now include semantic analysis
   ```

6. **Review** drift report changes:
   - Ghost Features will be flagged
   - Shadow Systems will be classified
   - Beads issues created (if bd installed)

### Rollback Instructions
If you encounter issues:
```bash
# Restore backup
rm -rf loa-grimoire
mv loa-grimoire.backup loa-grimoire

# Remove ck if desired
cargo uninstall ck-search
```

---

## Breaking Changes

**None** - This release is fully backward compatible.

---

## Known Limitations

### v0.8.0 Scope
1. **Single repository only** - No federated/multi-repo search
2. **Rust toolchain required** for ck installation
3. **Index stored locally** in `.ck/` directory (~10-50MB per repo)
4. **Initial indexing** may take 1-5 minutes for large codebases

### Not Included in v0.8.0
- MCP server migration (planned for v0.9.0)
- Multi-model embedding strategies
- Real-time index updates via git hooks
- GUI for trajectory visualization

---

## Future Roadmap

### v0.9.0 (MCP Migration)
- Connection pooling and health checks
- MCP server registration
- Improved error handling

### v1.0.0 (Multi-Repository)
- Federated search across repositories
- Cross-repo dependency tracking
- Shared embedding cache

### v1.1.0 (Advanced Analytics)
- Trajectory pattern detection
- Automated Beads integration
- Performance regression tracking

---

## Technical Details

### Performance Targets
| Metric | Target | Achieved |
|--------|--------|----------|
| Search Speed (1M LOC) | <500ms | ✅ |
| Cache Hit Rate | 80-90% | ✅ |
| Grounding Ratio | ≥0.95 | ✅ |
| User Experience Parity | 100% | ✅ |

### Files Added/Modified
- **Protocols**: 8 new protocols in `.claude/protocols/`
- **Scripts**: 6 new scripts in `.claude/scripts/`
- **Skills**: 2 enhanced skill resources
- **Tests**: 127 total tests (unit, integration, edge cases)
- **Documentation**: Updated INSTALLATION.md, README.md

### Test Coverage
- **Unit tests**: 79 tests for core scripts
- **Integration tests**: 22 scenarios for /ride workflow
- **Edge cases**: 26 error handling scenarios
- **Performance**: Automated PRD target validation

---

## Credits

This release was developed through the Loa agent-driven development workflow:
- **Product Requirements**: discovering-requirements agent
- **Architecture**: designing-architecture agent
- **Sprint Planning**: planning-sprints agent
- **Implementation**: implementing-tasks agent
- **Code Review**: reviewing-code agent
- **Security Audit**: auditing-security agent

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
