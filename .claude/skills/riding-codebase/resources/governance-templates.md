# Governance Templates

Templates for governance artifacts identified during `/ride` governance audit.

---

## CHANGELOG.md Template

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features added in this version

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security vulnerability fixes

## [1.0.0] - YYYY-MM-DD

### Added
- Initial release
```

---

## CONTRIBUTING.md Template

```markdown
# Contributing to [Project Name]

Thank you for your interest in contributing! This document provides guidelines
and instructions for contributing to this project.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template
3. Include:
   - Clear description of the issue
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details

### Suggesting Features

1. Check existing feature requests
2. Use the feature request template
3. Explain the use case and benefits

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Write/update tests
5. Ensure all tests pass
6. Submit a pull request

## Development Setup

```bash
# Clone the repository
git clone [repo-url]
cd [project-name]

# Install dependencies
[installation commands]

# Run tests
[test commands]

# Start development server
[dev commands]
```

## Code Style

- Follow existing code patterns
- Run linter before committing: `[lint command]`
- Write meaningful commit messages

## Review Process

1. All PRs require at least one approval
2. CI checks must pass
3. No merge conflicts with main branch

## Questions?

Open an issue or reach out to [contact method].
```

---

## SECURITY.md Template

```markdown
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| x.x.x   | :white_check_mark: |
| < x.x   | :x:                |

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via:

- Email: security@[domain].com
- Security advisory: [link if available]

### What to Include

1. Type of vulnerability
2. Full path to the affected source file(s)
3. Location of affected source code (tag/branch/commit or direct URL)
4. Step-by-step reproduction instructions
5. Proof-of-concept or exploit code (if possible)
6. Impact assessment

### Response Timeline

- **Initial response**: Within 48 hours
- **Status update**: Within 5 business days
- **Resolution target**: Depends on severity

### After Reporting

1. We will acknowledge receipt
2. We will investigate and determine impact
3. We will develop and test a fix
4. We will release the fix and credit you (if desired)

## Security Best Practices

When contributing, please:

- Never commit secrets or credentials
- Use environment variables for sensitive config
- Follow secure coding guidelines
- Report potential vulnerabilities responsibly

## Scope

This security policy applies to:

- The main repository
- Official releases
- Official Docker images (if applicable)
```

---

## CODEOWNERS Template

```
# CODEOWNERS file
# These owners will be requested for review when someone opens a pull request.

# Default owners for everything in the repo
*       @team-lead @senior-dev

# Specific paths
/src/api/           @api-team
/src/handlers/      @indexer-team
/src/auth/          @security-team
/infrastructure/    @devops-team
/docs/              @docs-team

# Critical files
.github/            @team-lead
package.json        @team-lead
*.lock              @team-lead

# Security-sensitive
/src/auth/          @security-team @team-lead
/src/crypto/        @security-team @team-lead
.env.example        @security-team
```

---

## .github/ISSUE_TEMPLATE/bug_report.md

```markdown
---
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Description
A clear and concise description of the bug.

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. Scroll down to '...'
4. See error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Screenshots
If applicable, add screenshots.

## Environment
- OS: [e.g., macOS 14.0]
- Browser: [e.g., Chrome 120]
- Version: [e.g., v1.2.3]

## Additional Context
Any other context about the problem.
```

---

## .github/ISSUE_TEMPLATE/feature_request.md

```markdown
---
name: Feature Request
about: Suggest an idea for this project
title: '[FEATURE] '
labels: enhancement
assignees: ''
---

## Problem Statement
A clear description of the problem you're trying to solve.

## Proposed Solution
Describe the solution you'd like.

## Alternatives Considered
Describe alternatives you've considered.

## Additional Context
Any other context, mockups, or examples.
```

---

## .github/pull_request_template.md

```markdown
## Description
Brief description of changes.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Related Issues
Fixes #(issue number)

## Testing
- [ ] Tests added/updated
- [ ] All tests passing
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (if needed)
- [ ] No new warnings introduced

## Screenshots (if applicable)

## Additional Notes
```

---

## Usage During Governance Audit

When the governance audit (Phase 7) identifies missing artifacts, create tasks:

```bash
# Example: Create governance setup tasks
if [[ ! -f "CHANGELOG.md" ]]; then
  echo "- [ ] Create CHANGELOG.md using governance-templates.md" >> tasks.md
fi

if [[ ! -f "CONTRIBUTING.md" ]]; then
  echo "- [ ] Create CONTRIBUTING.md using governance-templates.md" >> tasks.md
fi

if [[ ! -f "SECURITY.md" ]]; then
  echo "- [ ] Create SECURITY.md (PRIORITY: security disclosure)" >> tasks.md
fi
```
