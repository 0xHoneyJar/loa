# Pre-Flight Integrity Protocol

**Version**: 1.0.0
**Status**: Active
**PRD Reference**: FR-2.1
**SDD Reference**: §3.1

## Purpose

Verify System Zone integrity and ck binary availability before any semantic search operation. This protocol implements AWS Projen-level integrity enforcement to prevent operations on compromised framework files.

## Invariants

1. **System Zone Immutability**: `.claude/` files must match checksums in `.claude/checksums.json`
2. **Version Pinning**: ck binary version must meet `.loa-version.json` requirement
3. **Self-Healing State Zone**: `.ck/` directory missing triggers silent reindex
4. **Binary Integrity**: ck SHA-256 fingerprint verified (if configured)

## Protocol Specification

### Pre-Flight Check Sequence

```
1. Establish PROJECT_ROOT via git
2. Load integrity_enforcement from .loa.config.yaml
3. Verify System Zone checksums
4. Check ck availability and version
5. Verify ck binary fingerprint (optional)
6. Self-heal State Zone if missing
7. Trigger delta reindex if needed
```

### Integrity Enforcement Levels

| Level | Behavior on Drift | Use Case |
|-------|-------------------|----------|
| `strict` | **HALT** execution, exit 1 | CI/CD, production |
| `warn` | **LOG** warning, proceed | Development |
| `disabled` | No integrity checks | Rapid prototyping |

### Configuration

**`.loa.config.yaml`**:
```yaml
integrity_enforcement: strict  # or "warn", "disabled"
```

**`.loa-version.json`**:
```json
{
  "dependencies": {
    "ck": {
      "version": ">=0.7.0",
      "optional": true,
      "install": "cargo install ck-search"
    }
  },
  "binary_fingerprints": {
    "ck": "sha256-hash-here-if-known"
  }
}
```

## Implementation

### Script Location

`.claude/scripts/preflight.sh`

### Execution Context

**When to Run**:
- Before ANY ck search operation
- During `/setup` and `/update-loa` commands
- At the start of agent skills that use search

**When NOT to Run**:
- Pure grep fallback (no ck involvement)
- Read-only operations (file reads, status checks)
- Documentation commands

### Exit Codes

| Code | Meaning | Agent Action |
|------|---------|--------------|
| 0 | Checks passed | Proceed with operation |
| 1 | Checks failed (strict mode) | HALT, display error, suggest `/update-loa` |

### Error Messages

**Checksum Violation (strict)**:
```
SYSTEM ZONE INTEGRITY VIOLATION

Modified files detected in .claude/:
  - .claude/skills/implementing-tasks/SKILL.md
  - .claude/protocols/trajectory-evaluation.md

HALTING: Cannot proceed with compromised System Zone

Resolution:
  1. Move customizations to .claude/overrides/
  2. Restore System Zone: .claude/scripts/update.sh --force-restore
  3. Re-run operation
```

**Version Mismatch (warn)**:
```
⚠️  ck version mismatch
   Required: >=0.7.0
   Installed: 0.6.5

Recommendation: cargo install ck-search --force
Operations may work but feature compatibility not guaranteed.
```

**Binary Fingerprint Mismatch (strict)**:
```
⚠️  ck binary fingerprint mismatch
   Expected: a3f2...d4c1
   Actual:   b8e7...f2a9

HALTING: Binary integrity check failed
Reinstall ck: cargo install ck-search --force
```

## Self-Healing State Zone

### Trigger Conditions

- `.ck/` directory missing
- `.ck/.last_commit` file missing or corrupted
- First run after framework installation

### Healing Process

```bash
# Background reindex (non-blocking)
nohup ck --index "${PROJECT_ROOT}" --quiet </dev/null >/dev/null 2>&1 &
```

### Delta Reindex Strategy

**Threshold**: <100 changed files → delta reindex (fast)
**Threshold**: ≥100 changed files → full reindex (slow)

```bash
CHANGED_FILES=$(git diff --name-only "${LAST_INDEXED}" "HEAD" | wc -l)

if [[ "${CHANGED_FILES}" -lt 100 ]]; then
    # Delta: Update only changed files (80-90% cache hit)
    ck --index "${PROJECT_ROOT}" --delta --quiet &
else
    # Full: Rebuild entire index
    ck --index "${PROJECT_ROOT}" --quiet &
fi
```

## Integration Points

### Agent Skills

All skills that use semantic search must call pre-flight:

```bash
# At start of skill
"${PROJECT_ROOT}/.claude/scripts/preflight.sh" || exit 1
```

### Command Routing

Commands with `integrations: [ck]` automatically run pre-flight via command framework.

### Trajectory Logging

Pre-flight results logged to trajectory:

```jsonl
{"ts": "2024-01-15T10:30:00Z", "phase": "preflight", "enforcement": "strict", "checksums_valid": true, "ck_available": true, "ck_version": "0.7.0", "state_zone_healed": false}
```

## Testing

### Test Scenarios

1. **Clean State**: All checks pass → exit 0
2. **Modified .claude/ + strict**: Checksum fails → exit 1
3. **Modified .claude/ + warn**: Log warning → exit 0
4. **ck missing**: Graceful message → exit 0
5. **ck version too old**: Version warning → exit 0 (warn mode)
6. **ck fingerprint mismatch + strict**: Fingerprint fails → exit 1
7. **.ck/ missing**: Trigger reindex → exit 0
8. **Delta needed**: Trigger delta → exit 0

### Manual Testing

```bash
# Test clean state
.claude/scripts/preflight.sh
echo $?  # Should be 0

# Test modified System Zone (strict)
echo "# test" >> .claude/skills/implementing-tasks/SKILL.md
.claude/scripts/preflight.sh
echo $?  # Should be 1

# Restore
git checkout .claude/skills/implementing-tasks/SKILL.md

# Test with ck missing
mv /usr/local/bin/ck /usr/local/bin/ck.bak
.claude/scripts/preflight.sh
echo $?  # Should be 0 (optional tool)
mv /usr/local/bin/ck.bak /usr/local/bin/ck
```

## Performance

**Target**: <100ms for all checks combined
**Bottleneck**: SHA-256 checksums on large `.claude/` directory
**Optimization**: Cache checksums in-memory for session duration

## Security Considerations

1. **Tamper Detection**: Checksums prevent malicious System Zone modifications
2. **Binary Integrity**: Fingerprints prevent compromised ck binary execution
3. **Graceful Degradation**: Missing ck never blocks operations (grep fallback)
4. **User Override**: `disabled` mode for development (not recommended for prod)

## Maintenance

### Updating Checksums

After legitimate System Zone updates via `/update-loa`:

```bash
.claude/scripts/update.sh  # Automatically regenerates checksums.json
```

### Updating Binary Fingerprints

After ck version upgrade:

```bash
CK_PATH=$(command -v ck)
NEW_FINGERPRINT=$(sha256sum "${CK_PATH}" | awk '{print $1}')

# Update .loa-version.json
jq ".binary_fingerprints.ck = \"${NEW_FINGERPRINT}\"" .loa-version.json > .loa-version.json.tmp
mv .loa-version.json.tmp .loa-version.json
```

## References

- **PRD FR-2.1**: Pre-Flight Integrity Checks
- **PRD NFR-2.1**: Security & Integrity
- **PRD NFR-3.1**: Self-Healing State Zone
- **SDD §3.1**: Pre-Flight Integrity Checker
- **AWS Projen**: Infrastructure integrity patterns
