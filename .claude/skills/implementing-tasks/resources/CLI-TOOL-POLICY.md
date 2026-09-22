# CLI Tool Policy

## Approved Read-Only Allowlist

| Tool | Allowed Commands | Notes |
|------|-----------------|-------|
| `git` | `status`, `log`, `diff`, `branch`, `show` | Local only, no network |
| `gh` | `issue list`, `issue view`, `pr list`, `pr view`, `pr checks` | Use `--json` + field filtering to avoid leaking secrets from PR bodies |
| `npm`/`bun` | `test`, `run lint`, `run typecheck`, `run format` | Build/check + format-check commands |
| `cargo` | `check`, `test`, `clippy` | Build/check commands |

## Require Confirmation

| Operation Type | Examples |
|---------------|----------|
| Network writes | `git push`, `gh pr create`, `gh issue create` |
| Deployments | `railway deploy`, `vercel deploy` |
| Package mutations | `npm install`, `cargo add` |
| Cloud CLIs | `aws`, `gcloud`, `az` (any operation) |
| Destructive | `rm`, `git reset`, `git checkout -- .` |
