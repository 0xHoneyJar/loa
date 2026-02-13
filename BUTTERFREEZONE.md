<!-- AGENT-CONTEXT
name: loa
type: framework
purpose: No description available
key_files: [.claude/loa/CLAUDE.loa.md, .loa.config.yaml, .claude/scripts/]
version: v1.33.1
trust_level: grounded
-->

# loa

<!-- provenance: DERIVED -->
No description available

## Key Capabilities
<!-- provenance: DERIVED -->
- `.claude/adapters/cheval.py:_build_provider_config`
- `.claude/adapters/cheval.py:_error_json`
- `.claude/adapters/cheval.py:_load_persona`
- `.claude/adapters/cheval.py:cmd_invoke`
- `.claude/adapters/cheval.py:cmd_print_config`
- `.claude/adapters/cheval.py:cmd_validate_bindings`
- `.claude/adapters/cheval.py:main`
- `.claude/adapters/loa_cheval/config/interpolation.py:LazyValue`
- `.claude/adapters/loa_cheval/config/interpolation.py:_check_env_allowed`
- `.claude/adapters/loa_cheval/config/interpolation.py:_check_file_allowed`
- `.claude/adapters/loa_cheval/config/interpolation.py:_get_credential_provider`
- `.claude/adapters/loa_cheval/config/interpolation.py:_matches_lazy_path`
- `.claude/adapters/loa_cheval/config/interpolation.py:_reset_credential_provider`
- `.claude/adapters/loa_cheval/config/interpolation.py:_resolve_env`
- `.claude/adapters/loa_cheval/config/interpolation.py:interpolate_config`
- `.claude/adapters/loa_cheval/config/interpolation.py:interpolate_value`
- `.claude/adapters/loa_cheval/config/interpolation.py:redact_config`
- `.claude/adapters/loa_cheval/config/loader.py:_deep_merge`
- `.claude/adapters/loa_cheval/config/loader.py:_find_project_root`
- `.claude/adapters/loa_cheval/config/loader.py:load_system_defaults`
- `.claude/commands/scripts/common.sh:check_audit_prerequisites`
- `.claude/commands/scripts/common.sh:check_dir_exists`
- `.claude/commands/scripts/common.sh:check_file_exists`
- `.claude/commands/scripts/common.sh:check_implement_prerequisites`
- `.claude/commands/scripts/common.sh:check_review_prerequisites`
- `.claude/commands/scripts/common.sh:check_reviewer_report`
- `.claude/commands/scripts/common.sh:check_senior_approval`
- `.claude/commands/scripts/common.sh:check_setup_complete`
- `.claude/commands/scripts/common.sh:check_sprint_dir`
- `.claude/commands/scripts/common.sh:check_sprint_in_plan`

## Architecture
<!-- provenance: DERIVED -->
Directory structure:
```
./docs
./docs/architecture
./docs/integration
./evals
./evals/baselines
./evals/fixtures
./evals/graders
./evals/harness
./evals/results
./evals/suites
./evals/tasks
./evals/tests
./grimoires
./grimoires/loa
./grimoires/pub
./skills
./skills/legba
./tests
./tests/e2e
./tests/edge-cases
./tests/fixtures
./tests/helpers
./tests/integration
./tests/performance
./tests/unit
```

## Interfaces
<!-- provenance: DERIVED -->
### Skill Commands
- `/auditing-security`
- `/autonomous-agent`
- `/bridgebuilder-review`
- `/browsing-constructs`
- `/bug-triaging`
- `/butterfreezone-gen`
- `/continuous-learning`
- `/deploying-infrastructure`
- `/designing-architecture`
- `/discovering-requirements`
- `/enhancing-prompts`
- `/eval-running`
- `/flatline-knowledge`
- `/implementing-tasks`
- `/managing-credentials`
- `/mounting-framework`
- `/planning-sprints`
- `/reviewing-code`
- `/riding-codebase`
- `/rtfm-testing`
- `/run-bridge`
- `/run-mode`
- `/simstim-workflow`
- `/translating-for-executives`

## Module Map
<!-- provenance: DERIVED -->
| Module | Files | Purpose |
|--------|-------|---------|
| `docs/` | 4 | Documentation |
| `evals/` | 998 |  |
| `grimoires/` | 489 | Loa state files |
| `skills/` | 5112 |  |
| `tests/` | 142 | Test suites |

## Quick Start
<!-- provenance: OPERATIONAL -->
## Quick Start (~2 minutes)

**Prerequisites**: [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (Anthropic's CLI for Claude), Git, jq, [yq v4+](https://github.com/mikefarah/yq). See **[INSTALLATION.md](INSTALLATION.md)** for full details.

```bash
# Install (one command, any existing repo)
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Start Claude Code
claude

# These are slash commands typed inside Claude Code, not your terminal.
# 5 commands. Full development cycle.
/plan      # Requirements -> Architecture -> Sprints
/build     # Implement the current sprint
/review    # Code review + security audit
/ship      # Deploy and archive
```
<!-- ground-truth-meta
head_sha: 4ac1d63aa167366fe7f70e9319d50c25e83d48f3
generated_at: 2026-02-13T07:22:54Z
generator: butterfreezone-gen v1.0.0
sections:
  agent_context: b09a6c0215127e4e9e31487cadb96d5d1c659ce8257abbae9662592779dde922
  capabilities: fb6ef381fb7c2032e949e99a675dae0b4d58aabe935aec3c9c48c362594e9ca7
  architecture: a5ffce49636c71a93df41e9cb65f1bf394cce17d65413c45607d64e248f908f7
  interfaces: 23e92915acfd2a5fa593f1d7053d04ef25df2a6ed03b76aa70588791003fb6b1
  module_map: f60fed6f0ce0317f86e7143e97ae9f27fe9ed6e2dd104fa433afa969e5d78691
  quick_start: a6405f431b837c85a4beb869478df1e6a43f256f4d76b31927744707468cf68f
-->
