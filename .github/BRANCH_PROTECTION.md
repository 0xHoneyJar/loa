# Branch Protection Configuration

This document describes the required GitHub branch protection rules for the `loa` template repository.

## Required Settings for `main` Branch

Navigate to: **Settings > Branches > Branch protection rules > Add rule**

### Basic Settings

- **Branch name pattern**: `main`
- **Require a pull request before merging**: ✅ Enabled
  - **Required approving reviews**: 1
  - **Dismiss stale pull request approvals when new commits are pushed**: ✅
  - **Require review from Code Owners**: ✅ Enabled (CODEOWNERS file exists)

### Status Checks

- **Require status checks to pass before merging**: ✅ Enabled
- **Require branches to be up to date before merging**: ✅ Enabled

**Required status checks** (must all pass):

| Check Name | Purpose |
|------------|---------|
| `Template Protection` | Blocks forbidden files (prd.md, sdd.md, sprint.md, a2a/*, etc.) |
| `Validate Framework Files` | Ensures required skills/commands/docs exist |

### Additional Protection

- **Require conversation resolution before merging**: ✅ Recommended
- **Do not allow bypassing the above settings**: ✅ **CRITICAL** - Prevents admins from bypassing

### Restrictions

- **Restrict who can push to matching branches**: Optional
  - If enabled, add maintainers who can push directly

## Template Guard Override

The CI workflow includes a `[skip-template-guard]` escape hatch for exceptional circumstances:

1. Add `[skip-template-guard]` to your commit message
2. The template guard step will still fail, but subsequent jobs will show a warning
3. **This should be used sparingly** and only for legitimate template updates

**Note**: Even with the override, branch protection rules will still require PR approval, so forbidden files cannot be merged without explicit human review.

## Ruleset Alternative (Recommended)

GitHub Rulesets provide more granular control. Navigate to: **Settings > Rules > Rulesets**

### Create Ruleset: "Template Protection"

```yaml
name: Template Protection
enforcement: active
target: branch
conditions:
  ref_name:
    include: ["refs/heads/main"]

rules:
  - type: pull_request
    parameters:
      required_approving_review_count: 1
      dismiss_stale_reviews_on_push: true
      require_last_push_approval: false

  - type: required_status_checks
    parameters:
      strict_required_status_checks_policy: true
      required_status_checks:
        - context: "Template Protection"
          integration_id: 15368  # GitHub Actions
        - context: "Validate Framework Files"
          integration_id: 15368

  - type: non_fast_forward
    # Prevents force pushes
```

## Verification

After configuring protection:

1. Create a test branch
2. Add a forbidden file (e.g., `grimoires/loa/prd.md`)
3. Open a PR to `main`
4. Verify the `Template Protection` check fails
5. Delete the test branch

## Files Protected

The following patterns are blocked by the `Template Protection` check:

### Individual Files
- `grimoires/loa/prd.md`
- `grimoires/loa/sdd.md`
- `grimoires/loa/sprint.md`
- `grimoires/loa/NOTES.md`

### Directory Patterns
- `grimoires/loa/a2a/sprint-*/**`
- `grimoires/loa/a2a/index.md`
- `grimoires/loa/a2a/deployment-feedback.md`
- `grimoires/loa/a2a/trajectory/**`
- `grimoires/loa/deployment/**` (except README.md)
- `grimoires/loa/reality/**` (except README.md)
- `grimoires/loa/analytics/**` (except README.md)
- `grimoires/loa/research/**` (except README.md)

README.md files in each directory are explicitly allowed to document the directory's purpose.
