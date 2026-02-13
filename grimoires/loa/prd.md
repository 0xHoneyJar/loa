# PRD: Post-Merge Automation Pipeline

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Source Issue**: https://github.com/0xHoneyJar/loa/issues/298
**Cycle**: cycle-007

---

## 1. Problem Statement

After a PR merges to `main`, the maintainer must manually execute 6 sequential steps:

1. Update documentation if relevant changes landed
2. Regenerate Grounded Truth (checksums, scaffolding)
3. Run RTFM validation (zero-context doc testing)
4. Bump semver version in CHANGELOG, README, and package files
5. Create a git tag
6. Create a GitHub Release with release notes (for cycle completions)

This is tedious, error-prone, and blocks the next development cycle. The individual tools exist (`ground-truth-gen.sh`, RTFM skill, version consistency checks in CI) but nothing orchestrates them automatically on merge.

> Sources: Issue #298 body, Phase 1 interview Q1 ("atm am needing to do this manually but would rather it be a thing which happens automatically upon merge")

## 2. Vision & Goals

### Vision

Every merge to `main` triggers an automated pipeline that handles the mechanical post-merge lifecycle — documentation, truth generation, validation, versioning, and release — so the maintainer can focus on the next cycle.

### Goals

| Goal | Success Metric | Priority |
|------|----------------|----------|
| G1: Zero manual post-merge steps for routine merges | 0 manual commands after PR merge | P0 |
| G2: Automated semver from conventional commits | Correct version bump in 100% of merges | P0 |
| G3: Grounded Truth always current after merge | GT checksums updated within 5 min of merge | P0 |
| G4: RTFM validation catches doc regressions | Zero false-negative doc gaps post-merge | P1 |
| G5: GitHub Releases for cycle completions | Release created with notes for every cycle PR | P1 |
| G6: Non-cycle PRs get patch bump + tag | Consistent version progression across all merges | P2 |

### Non-Goals

- Automating pre-merge review (already handled by Bridgebuilder, Flatline, post-PR validation)
- Replacing the `/ship` command for manual deploys
- Auto-merging PRs (merge remains a human decision)
- Automating infrastructure deployment (that's `/deploy-production`)

## 3. Users & Stakeholders

### Primary User: Maintainer (@janitooor)

- **Context**: Solo maintainer of Loa framework
- **Pain point**: 6-step manual post-merge ritual after every PR
- **Desired outcome**: Merge PR → walk away → everything happens

### Secondary User: AI Operators (Clawdbot, future agents)

- **Context**: Autonomous agents that complete cycles and create PRs
- **Pain point**: Cannot trigger post-merge steps; must leave instructions for human
- **Desired outcome**: Cycle completion triggers full pipeline without human involvement

## 4. Functional Requirements

### FR-1: GitHub Action Trigger (P0)

**What**: A GitHub Actions workflow that fires on push to `main` (merge event).

**Behavior**:
- Triggers on `push` to `main` branch only
- Detects merge commit vs direct push (only processes merge commits)
- Extracts source PR number from merge commit message
- Classifies PR type: `cycle-completion` vs `bugfix` vs `other`
- Routes to appropriate pipeline tier

**Classification Logic**:
- `cycle-completion`: PR title matches `/^(Run Mode|Sprint Plan|feat\(sprint)/` OR PR has `cycle` label OR CHANGELOG contains `[Unreleased]` section with `### Added` entries
- `bugfix`: PR title matches `/^fix/` OR has `bugfix` label
- `other`: Everything else (docs, chore, refactor)

**Acceptance Criteria**:
- [ ] Workflow triggers on push to main
- [ ] Correctly classifies PR type in >95% of cases
- [ ] Skips non-merge pushes (direct commits, force-pushes)
- [ ] Logs classification decision for debugging

### FR-2: Claude Code Action Integration (P0)

**What**: Set up `anthropics/claude-code-action` as the execution bridge between GH Actions and Loa.

**Behavior**:
- GH Action step invokes claude-code-action with appropriate prompt
- Prompt includes: PR type, PR number, merge commit SHA, files changed
- Claude Code runs the `/ship` skill (FR-5) with context
- Output captured and posted as PR comment or GH Actions summary

**Acceptance Criteria**:
- [ ] claude-code-action configured in `.github/workflows/`
- [ ] API key stored as repository secret (`ANTHROPIC_API_KEY`)
- [ ] Prompt template tested with mock merge events
- [ ] Timeout configured (30 min max)
- [ ] Cost guard: single invocation per merge (no retry loops)

### FR-3: Conventional Commit Semver Parser (P0)

**What**: Parse commit messages between the last tag and HEAD to determine semver bump.

**Behavior**:
- Scans all commits in the merge (between previous tag and HEAD)
- Applies conventional commit rules:
  - `feat(...)` or `feat:` → **minor** bump
  - `fix(...)` or `fix:` → **patch** bump
  - `BREAKING CHANGE:` in body or `!` after type → **major** bump
  - `chore`, `docs`, `refactor`, `test`, `ci` → **patch** bump (still bumps, keeps versions ticking)
- Highest-priority bump wins (major > minor > patch)
- Generates next version string from current tag

**Acceptance Criteria**:
- [ ] Shell script: `.claude/scripts/semver-bump.sh`
- [ ] Reads current version from latest git tag (`v*.*.*`)
- [ ] Falls back to CHANGELOG version if no tags exist
- [ ] Outputs: `{"current": "1.35.1", "next": "1.36.0", "bump": "minor", "commits": [...]}`
- [ ] Unit tests in `tests/unit/semver-bump.bats`

### FR-4: Post-Merge Pipeline Orchestrator (P0)

**What**: Shell script that orchestrates the post-merge phases in sequence.

**Pipeline Phases**:

```
CLASSIFY → SEMVER → CHANGELOG → GT_REGEN → RTFM → TAG → RELEASE → NOTIFY
```

| Phase | Description | Cycle PR | Bugfix PR | Other PR |
|-------|-------------|----------|-----------|----------|
| CLASSIFY | Determine PR type | Yes | Yes | Yes |
| SEMVER | Compute next version | Yes | Yes | Yes |
| CHANGELOG | Finalize `[Unreleased]` → version header | Yes | Yes | Skip |
| GT_REGEN | Run `ground-truth-gen.sh --mode all` | Yes | Skip | Skip |
| RTFM | Run RTFM validation on updated docs | Yes | Skip | Skip |
| TAG | Create + push `v{version}` tag | Yes | Yes | Yes |
| RELEASE | Create GitHub Release with notes | Yes | Skip | Skip |
| NOTIFY | Post summary to PR / Discord | Yes | Yes | Yes |

**Acceptance Criteria**:
- [ ] Script: `.claude/scripts/post-merge-orchestrator.sh`
- [ ] State file: `.run/post-merge-state.json`
- [ ] Each phase is idempotent (safe to re-run)
- [ ] Failed phase halts pipeline with clear error
- [ ] Dry-run mode for testing (`--dry-run`)
- [ ] Emits structured JSON summary on completion

### FR-5: Enhanced `/ship` Skill (P1)

**What**: Extend the existing `/ship` golden path command to serve as both manual and automated entry point.

**Behavior**:
- Manual mode: User runs `/ship` interactively after merge
- Automated mode: claude-code-action invokes `/ship --automated --pr <number> --sha <commit>`
- Both modes invoke `post-merge-orchestrator.sh`
- Automated mode skips confirmations, posts results as PR comment

**Acceptance Criteria**:
- [ ] `/ship` detects whether invoked manually or via CI
- [ ] `--automated` flag suppresses interactive prompts
- [ ] Posts summary to merged PR as comment
- [ ] Archives cycle if PR was cycle-completion type

### FR-6: RTFM Post-Merge Gate (P1)

**What**: Run RTFM validation after GT regeneration to catch documentation regressions.

**Behavior**:
- Invokes RTFM testing on: `README.md`, `INSTALLATION.md`, GT `index.md`
- If critical gaps found: logs warning, continues (does not block tag/release)
- Gap report saved to `.run/post-merge-rtfm-report.json`
- Summary included in release notes

**Acceptance Criteria**:
- [ ] RTFM runs in headless mode (no user prompts)
- [ ] Critical gaps logged but don't block release
- [ ] Gap count included in post-merge summary

### FR-7: Release Notes Generation (P1)

**What**: Auto-generate release notes from CHANGELOG and commit history.

**Behavior**:
- For cycle completions: extract CHANGELOG section for this version
- Append: sprint summary table, files changed, test results
- For bugfixes: minimal "Bug fix release" template
- Include link to source PR

**Acceptance Criteria**:
- [ ] Script: `.claude/scripts/release-notes-gen.sh`
- [ ] Extracts correct CHANGELOG section
- [ ] Handles missing CHANGELOG gracefully
- [ ] Output format matches existing release style

### FR-8: CHANGELOG Finalization (P2)

**What**: Automatically convert `[Unreleased]` section to versioned entry on merge.

**Behavior**:
- Detects `## [Unreleased]` section in CHANGELOG.md
- Replaces with `## [version] - date — PR Title`
- Adds empty `## [Unreleased]` section above
- Commits the CHANGELOG update

**Acceptance Criteria**:
- [ ] Only modifies CHANGELOG if `[Unreleased]` section exists
- [ ] Date format: YYYY-MM-DD
- [ ] Version comes from FR-3 semver calculation
- [ ] Committed with conventional prefix: `chore(release): v{version}`

## 5. Technical & Non-Functional Requirements

### NFR-1: Idempotency

Every pipeline phase must be safe to re-run. If the workflow fails mid-pipeline, re-running from the beginning must not create duplicate tags, releases, or commits.

### NFR-2: Cost Control

Claude Code invocation via claude-code-action must be bounded:
- Max 1 invocation per merge event
- 30-minute timeout
- No retry loops (fail once → notify, let human investigate)
- Estimated cost per invocation: <$5 (Haiku for simple tasks, Sonnet for GT/RTFM)

### NFR-3: Security

- `ANTHROPIC_API_KEY` stored as GitHub repository secret
- Pipeline runs with minimal permissions (contents: write, pull-requests: write)
- No secrets logged to workflow output
- Tag signing optional (not in MVP scope)

### NFR-4: Observability

- Each phase logs structured JSON to workflow output
- Final summary posted as PR comment
- Discord notification on failure (uses existing `DISCORD_WEBHOOK_URL` secret)

### NFR-5: Graceful Degradation

If claude-code-action is unavailable or times out:
- Semver + tag still happen (pure shell, no AI needed)
- GT + RTFM + release notes are skipped (require AI)
- Manual `/ship` remains available as fallback

## 6. Scope & Prioritization

### MVP (Sprint 1-2)

| Feature | Priority | Description |
|---------|----------|-------------|
| GH Action trigger | P0 | Workflow file with merge detection + PR classification |
| Semver parser | P0 | Conventional commit → version bump script |
| Pipeline orchestrator | P0 | Shell script coordinating phases |
| Git tag creation | P0 | Automated tagging from computed version |
| claude-code-action setup | P0 | CI integration with Claude Code |

### Phase 2 (Sprint 3)

| Feature | Priority | Description |
|---------|----------|-------------|
| `/ship` enhancement | P1 | Dual-mode manual/automated skill |
| GT regeneration | P1 | Post-merge ground truth update |
| RTFM validation | P1 | Post-merge doc regression check |
| Release notes gen | P1 | Auto-generated from CHANGELOG + commits |
| GitHub Release creation | P1 | Automated release for cycle PRs |

### Future (Out of Scope)

- Tag signing with GPG
- Automated deployment triggers
- Cross-repo release coordination
- Release approval gates
- Automated rollback on RTFM failure

## 7. Risks & Dependencies

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| claude-code-action reliability | Pipeline stalls if Claude unavailable | Graceful degradation: shell-only phases still work |
| Cost runaway | Unexpected API costs | Hard timeout + single invocation + Haiku default |
| CHANGELOG format drift | Semver parser breaks | Strict format validation in CI |
| Race conditions | Two PRs merge simultaneously | GH Actions concurrency group on main |
| Tag conflicts | Version already exists | Check before creating, append `.1` suffix if needed |

### Dependencies

| Dependency | Status | Owner |
|------------|--------|-------|
| `anthropics/claude-code-action` | Available on GH Marketplace | Anthropic |
| `ANTHROPIC_API_KEY` secret | Needs setup | @janitooor |
| Existing `ground-truth-gen.sh` | Working | Loa framework |
| Existing RTFM skill | Working | Loa framework |
| Conventional commit discipline | In use (commit prefixes) | Team convention |

## 8. Success Criteria

**Cycle-007 is complete when:**

1. Merging a cycle-completion PR to main triggers the full pipeline automatically
2. Merging a bugfix PR creates a patch bump + tag with no manual steps
3. The semver parser correctly handles feat/fix/breaking commit prefixes
4. GT is regenerated and RTFM runs on cycle-completion merges
5. A GitHub Release is created with auto-generated notes for cycle PRs
6. The entire pipeline completes in <10 minutes for typical merges
7. Failures are clearly reported via PR comment and Discord notification
