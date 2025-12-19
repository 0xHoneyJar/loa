# Contributing to Loa

Thank you for your interest in contributing to Loa! This document provides guidelines and information for contributors.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Submitting Changes](#submitting-changes)
- [Style Guidelines](#style-guidelines)
- [Testing](#testing)
- [Documentation](#documentation)
- [Community](#community)

## Getting Started

### Prerequisites

- [Claude Code](https://claude.ai/code) installed and configured
- Git 2.x or later
- Node.js 18+ (for running tests and linting)

### Setting Up Your Development Environment

1. **Fork the repository** on GitHub

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/loa.git
   cd loa
   ```

3. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/0xHoneyJar/loa.git
   ```

4. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

5. **Start Claude Code and run setup**
   ```bash
   claude
   /setup
   ```

## Development Workflow

### Branch Naming Convention

Use descriptive branch names following these patterns:

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/description` | `feature/add-typescript-agent` |
| Bug fix | `fix/description` | `fix/analytics-json-parsing` |
| Documentation | `docs/description` | `docs/update-contribution-guide` |
| Refactor | `refactor/description` | `refactor/agent-prompt-structure` |
| CI/Infra | `ci/description` | `ci/add-lint-workflow` |

### Keeping Your Fork Updated

```bash
# Fetch upstream changes
git fetch upstream

# Merge upstream main into your branch
git merge upstream/main

# Or rebase (for cleaner history)
git rebase upstream/main
```

### Making Changes

1. **Sync with upstream** before starting work
2. **Create a feature branch** from `main`
3. **Make focused commits** with clear messages
4. **Test your changes** locally
5. **Push to your fork** and create a PR

## Submitting Changes

### Pull Request Process

1. **Ensure your PR addresses a single concern**
   - One feature, one bug fix, or one documentation update per PR
   - Large changes should be broken into smaller PRs

2. **Write a clear PR description**
   - What does this PR do?
   - Why is this change needed?
   - How was it tested?

3. **Link related issues**
   - Use keywords like `Closes #123` or `Fixes #456`

4. **Wait for CI to pass**
   - All automated checks must pass
   - Secret scanning and security audits must pass

5. **Request review**
   - At least one maintainer approval required
   - Address review feedback promptly

### Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

Longer description if needed.

Closes #123
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `ci`: CI/CD changes
- `chore`: Maintenance tasks

**Examples:**
```
feat(agents): add code-reviewer agent for automated PR reviews

fix(analytics): handle missing usage.json gracefully

docs(readme): add troubleshooting section for MCP setup
```

## Style Guidelines

### Agent Prompts

When modifying agent prompts in `.claude/agents/`:

- Maintain consistent persona and expertise level
- Include clear phase transitions
- Provide structured output formats
- Document expected inputs and outputs

### Command Definitions

When creating or modifying commands in `.claude/commands/`:

- Use clear, descriptive command names
- Include help text and examples
- Handle error cases gracefully
- Update CLAUDE.md with new commands

### Documentation

- Use clear, concise language
- Include code examples where helpful
- Keep line lengths reasonable (< 100 chars)
- Update related docs when making changes

## Testing

### Running Tests

```bash
# Run linting
npm run lint

# Run all tests
npm test

# Run specific test suite
npm test -- --grep "agent"
```

### What to Test

- New agent prompts should include example interactions
- Command changes should be tested with `/command help`
- Documentation changes should be previewed locally

### CI Checks

All PRs must pass:

1. **Secret Scanning** - No secrets in code
2. **Security Audit** - No critical vulnerabilities
3. **Linting** - Code style compliance
4. **Tests** - All tests passing

## Documentation

### Updating Documentation

When your changes affect documentation:

1. **README.md** - User-facing feature descriptions
2. **PROCESS.md** - Workflow documentation
3. **CLAUDE.md** - Agent and command reference
4. **CHANGELOG.md** - Version history (maintainers will update)

### Documentation Standards

- Keep explanations beginner-friendly
- Include command examples
- Update table of contents if adding sections
- Check for broken links

## Community

### Getting Help

- **Issues**: Use GitHub Issues for bugs and feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Discord**: Join our Discord for real-time chat

### Recognition

Contributors are recognized in:
- GitHub contributor graphs
- Release notes (for significant contributions)
- Special thanks in documentation

## Types of Contributions

### We Welcome

- Bug fixes and issue reports
- Documentation improvements
- New agent definitions
- Command enhancements
- Security improvements
- Performance optimizations
- Test coverage improvements

### Before Starting Large Changes

For significant changes (new agents, workflow modifications, architecture changes):

1. **Open an issue first** to discuss the proposal
2. **Get maintainer feedback** before implementing
3. **Consider breaking into smaller PRs** for easier review

## License

By contributing to Loa, you agree that your contributions will be licensed under the [AGPL-3.0 License](LICENSE.md).

---

Thank you for contributing to Loa! Your efforts help make AI-assisted development better for everyone.
