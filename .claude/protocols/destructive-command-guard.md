# Destructive Command Guard Protocol

## Overview

The Destructive Command Guard (DCG) is a runtime safety layer that validates shell commands before execution. It intercepts potentially dangerous operations and applies configurable policies to BLOCK, WARN, or ALLOW based on pattern matching and context analysis.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Command Execution                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐│
│   │ dcg-exec │───>│ parser   │───>│ matcher  │───>│ result ││
│   └──────────┘    └──────────┘    └──────────┘    └────────┘│
│        │               │               │               │     │
│        │         ┌─────┴─────┐   ┌─────┴─────┐        │     │
│        │         │ fast path │   │ patterns  │        │     │
│        │         │ AST path  │   │ safe ctx  │        │     │
│        │         └───────────┘   │ safe path │        │     │
│        │                         └───────────┘        │     │
│        │                                              │     │
│        ▼                                              ▼     │
│   ┌─────────────────────────────────────────────────────────┤
│   │                     packs-loader                        │
│   │  ┌────────┐  ┌──────────┐  ┌────────┐  ┌────────────┐  │
│   │  │  core  │  │ database │  │ docker │  │ kubernetes │  │
│   │  └────────┘  └──────────┘  └────────┘  └────────────┘  │
│   └─────────────────────────────────────────────────────────┘
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Actions

| Action | Behavior | Use Case |
|--------|----------|----------|
| `BLOCK` | Prevents execution, returns error | Critical operations (rm -rf /, DROP TABLE) |
| `WARN` | Logs warning, allows execution | Risky but valid operations (git reset --hard) |
| `ALLOW` | Permits execution silently | Safe operations or safe contexts |

## Configuration

```yaml
# .loa.config.yaml
destructive_command_guard:
  enabled: true
  timeout_ms: 100

  # Security packs to load (core always loaded)
  packs:
    database: true
    docker: true
    kubernetes: false
    cloud-aws: false
    cloud-gcp: false
    terraform: false

  # Additional safe paths beyond defaults
  safe_paths:
    - /app/cache
    - /var/cache/app

  # Override actions for specific patterns
  overrides:
    git_push_force:
      action: WARN  # Allow with warning instead of block
```

## Safe Paths

The following paths are considered safe for deletion operations:

**Default safe paths**:
- `/tmp`, `/var/tmp`, `$TMPDIR`
- `$PROJECT_ROOT/node_modules`
- `$PROJECT_ROOT/dist`, `$PROJECT_ROOT/build`
- `$PROJECT_ROOT/.venv`, `$PROJECT_ROOT/venv`
- `$PROJECT_ROOT/__pycache__`, `$PROJECT_ROOT/.pytest_cache`

**Path handling** (per Flatline SKP-004):
- All paths must be absolute (relative paths rejected)
- Environment variables expanded at init time
- Symlinks resolved via `realpath -m`
- Path canonicalization before matching

## Safe Contexts

Commands are allowed in these contexts:

| Context | Example | Reason |
|---------|---------|--------|
| grep/search | `grep 'rm -rf' file.txt` | Reading, not executing |
| echo/print | `echo "DROP TABLE"` | Outputting, not executing |
| cat/read | `cat /etc/passwd` | Read-only operation |
| --help | `rm --help` | Documentation request |
| --dry-run | `terraform destroy --dry-run` | Simulation only |
| --version | `git --version` | Version info request |

## Security Packs

### Core Pack (always loaded)
- Filesystem: `rm -rf /`, `rm -rf ~`, `rm -rf /etc`, etc.
- Git: `git push --force`, `git reset --hard`, `git clean -fdx`
- Shell: `eval "$var"`

### Database Pack
- SQL: `DROP TABLE`, `TRUNCATE`, `DELETE` without WHERE
- MongoDB: `dropDatabase()`, `drop()`, `deleteMany({})`
- Redis: `FLUSHALL`, `FLUSHDB`

### Docker Pack
- Containers: `docker rm -f $(docker ps -aq)`
- Images: `docker rmi $(docker images -q)`
- Volumes: `docker volume rm $(docker volume ls -q)`
- System: `docker system prune -a -f`

### Kubernetes Pack (Sprint 3)
- Namespace: `kubectl delete ns`
- Cluster-wide: `kubectl delete --all`
- Context: dangerous context switches

### Cloud Packs (Sprint 3)
- AWS: S3 bucket deletion, CloudFormation destroy
- GCP: Project deletion, dataset deletion
- Terraform: `terraform destroy` without approval

## Run Mode Integration

During autonomous execution (`/run sprint-N`), DCG provides additional protection:

1. **Pre-execution validation**: All bash commands checked before execution
2. **Audit logging**: Blocked commands logged to trajectory
3. **Circuit breaker**: Multiple blocks may trigger workflow halt

```yaml
# Run mode DCG behavior
run_mode:
  dcg:
    enabled: true
    audit_log: true
    halt_on_block_count: 3  # Halt after 3 blocked commands
```

## Bypass

DCG can be bypassed when necessary:

```bash
# Environment variable bypass
DCG_SKIP=1 rm -rf /tmp/sensitive-cache

# Config-based bypass for specific patterns
destructive_command_guard:
  bypass:
    - pattern: "rm -rf /specific/path"
      reason: "Required for deployment cleanup"
```

**Note**: Bypasses are logged and should be used sparingly.

## Fail-Open Design

DCG follows fail-open principles to avoid blocking legitimate workflows:

- Parser errors → ALLOW (log warning)
- Pack load errors → Use embedded patterns (log warning)
- Pattern syntax errors → Skip pattern (log warning)
- Timeout → ALLOW (log warning)

## Adding Custom Patterns

Create a custom pack in `.claude/security-packs/`:

```yaml
# custom.yaml
version: 1.0.0
name: custom
description: Project-specific patterns

patterns:
  - id: custom_dangerous_op
    pattern: "\\bdangerous-command\\b"
    action: BLOCK
    severity: high
    message: "Custom dangerous operation blocked"
```

Enable in config:
```yaml
destructive_command_guard:
  packs:
    custom: true
```

## Testing

Run DCG tests:
```bash
# Unit tests (always work)
bash .claude/scripts/tests/test_dcg.sh

# Golden tests (requires yq v4+)
bash .claude/scripts/tests/dcg-golden-test-runner.sh
```

Validate a command manually:
```bash
source .claude/scripts/destructive-command-guard.sh
dcg_init
dcg_validate "rm -rf /tmp/test" | jq .
```

## Related

- [Run Mode Protocol](.claude/protocols/run-mode.md)
- [Git Safety Protocol](.claude/protocols/git-safety.md)
- [Input Guardrails](.claude/protocols/input-guardrails.md)
