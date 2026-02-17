# PRD: Cross-Codebase Feedback Routing

> Cycle: cycle-025 | Author: janitooor + Claude
> Source: [#355](https://github.com/0xHoneyJar/loa/issues/355)
> Priority: P2 (feature request — enhances constructs ecosystem feedback loop)
> Flatline: Reviewed (4 HIGH_CONSENSUS integrated, 9 BLOCKERS addressed)

## 1. Problem Statement

Loa generates rich, structured feedback at every stage of the development lifecycle — Bridgebuilder reviews, audit findings, review feedback, and user-initiated `/feedback` reports. Today, this feedback routes to only 4 hardcoded repos (loa, loa-constructs, forge, current project) via keyword matching in `feedback-classifier.sh`.

When an issue originates from **construct code** (installed packs/skills from the constructs network), the feedback has nowhere to go. It stays local or gets filed on the wrong repo. The construct vendor — the person who can actually fix the problem — never sees it.

**Example scenario**: A user installs the "observer" pack from the constructs registry. During a Bridgebuilder review, an audit finding traces to a vulnerability in `observer/deep-interview/SKILL.md`. Today, that finding gets filed on `0xHoneyJar/loa` or the user's project repo. The observer pack vendor never learns about it.

**Impact**: The constructs ecosystem has no feedback loop. Vendors ship packs blind — no bug reports, no usage patterns, no quality signals from the field. Users who discover construct issues have no standard way to report upstream.

> Sources: #355 (field observation from janitooor/zerker applying constructs to builds)

## 2. Goals & Success Metrics

### Goals

1. **Route feedback to construct source repos**: When Loa detects that an issue originates from construct code, route the feedback to the construct's declared source repository.
2. **Always prompt before external filing**: Never auto-file issues on repos the user doesn't control. Show what will be filed and where, require explicit confirmation.
3. **Constructs declare their source repo**: Use `source_repo` field in construct `manifest.yaml` — simple, explicit, reliable.
4. **Secure by default**: Redact sensitive content before filing on external repos. Validate `source_repo` against vendor organization.

### Success Metrics

| Metric | Target |
|--------|--------|
| Feedback correctly attributed to construct origin | >90% when construct code is involved |
| User confirmation before external filing | 100% (hard requirement) |
| Construct repos without `source_repo` gracefully degrade | Falls back to existing routing |
| No regressions in existing 4-repo routing | All existing classifier tests pass |
| Zero sensitive data leakage in external issues | 100% (redaction applied) |

## 3. User & Stakeholder Context

### Primary Persona: Construct Consumer

A developer using Loa with installed constructs packs. They encounter issues during builds that trace back to construct code. They want to report upstream without manually identifying the construct's source repo and crafting an issue.

### Secondary Persona: Construct Vendor

A developer who publishes packs to the constructs network. They want to receive structured, actionable feedback from the field — bug reports with context, audit findings with severity levels.

### Stakeholder: Network Operator (THJ)

Wants the constructs ecosystem to have a healthy feedback loop. Feedback routing creates network effects — better construct quality attracts more users, more users generate more feedback.

## 4. Functional Requirements

### Phase 1 (MVP — this cycle)

#### FR-1: Construct Attribution Engine

When `/feedback` generates findings, determine whether the finding traces to construct code.

**Attribution algorithm** (Flatline IMP-001: define the scoring formula):

| Signal | Weight | Description |
|--------|--------|-------------|
| File path match | 1.0 | Path starts with `.claude/constructs/skills/{vendor}/` or `.claude/constructs/packs/{pack}/` |
| Skill name match | 0.6 | Finding mentions a skill name that exists in installed constructs |
| Vendor name match | 0.4 | Finding mentions a known vendor name |
| User explicit mention | 1.0 | User types the construct/pack name in feedback text |

**Scoring**: Sum matched signal weights. Normalize to 0.0-1.0 by dividing by max possible (3.0). Threshold for construct routing: 0.33 (i.e., at least one path match or user mention).

**Output**: `{construct: "vendor/pack", source_repo: "org/repo", confidence: 0.0-1.0, signals: [...]}`.

**Edge case — multiple constructs** (Flatline IMP-002 overlap): If multiple constructs match, pick the one with highest confidence. If tied, present all matches to user for disambiguation.

#### FR-2: Source Repo Resolution

Resolve a construct to its upstream source repository.

**Primary source**: `source_repo` field in construct's `manifest.yaml`:
```yaml
# .claude/constructs/packs/observer/manifest.yaml
name: observer
vendor: artisan
version: 1.2.0
source_repo: "0xHoneyJar/observer-pack"  # NEW FIELD
```

**Validation** (Flatline IMP-003 / SKP-002 supply-chain trust):
- `source_repo` MUST match the pattern `{org}/{repo}` (GitHub owner/repo format)
- `source_repo` org SHOULD match the vendor's known GitHub organization
- If org doesn't match vendor name: display prominent warning in confirmation prompt: "The declared repo **{source_repo}** does not match the vendor organization **{vendor}**. This may indicate a tampered manifest."
- User must explicitly confirm after seeing the warning

**Fallback**: If `source_repo` is not declared, fall back to existing 4-repo routing. Log a warning suggesting the vendor add the field.

#### FR-3: Feedback Routing Extension

Extend `feedback-classifier.sh` to support construct routing as a 5th category:

| Category | Target | Signals |
|----------|--------|---------|
| `loa_framework` | `0xHoneyJar/loa` | .claude/, grimoires/, skill, protocol |
| `loa_constructs` | `0xHoneyJar/loa-constructs` | registry, API, pack, license |
| `forge` | `0xHoneyJar/forge` | experimental, sandbox, WIP |
| `project` | Current project repo | application, deployment, infra |
| **`construct`** | **Resolved from manifest** | **Construct paths, skill names, vendor refs** |

The `construct` category takes priority when attribution confidence >= 0.33.

#### FR-4: User-Initiated Feedback Routing (`/feedback`)

When `/feedback` detects construct-related context:

1. Run attribution (FR-1)
2. If construct detected with `source_repo`:
   - Show full target repo URL prominently
   - Show redacted preview of what will be filed
   - If vendor org mismatch: show trust warning (FR-2)
   - Options: [Route to construct repo] / [Route to loa instead] / [Route to current project]
3. On confirmation, apply redaction (FR-5), create GitHub issue via `gh issue create`
4. Record in dedup ledger (FR-6)

#### FR-5: Content Redaction for External Issues

Before filing on any external construct repo, apply content redaction (Flatline IMP-005 / SKP-006):

**Always redact**:
- Absolute file paths (replace with relative paths from project root)
- Environment variables and their values
- API keys, tokens, secrets (use gitleaks-style patterns)
- `~/.claude/`, `~/.ssh/`, `~/.aws/` references
- Git remote URLs containing credentials

**Always include**:
- Construct name and version
- Loa framework version
- Finding description (redacted)
- Severity level

**User controls** (shown in confirmation preview):
- Toggle: include code snippets (default: OFF for external repos)
- Toggle: include file:line references (default: ON, paths redacted)
- Toggle: include environment info (default: OFF)

#### FR-6: Dedup and Rate Limiting

Prevent spam/abuse of external repos (Flatline IMP-002 / SKP-002):

**Local dedup ledger**: `.run/feedback-ledger.json`
```json
{
  "submissions": [
    {
      "repo": "org/repo",
      "fingerprint": "sha256 of redacted issue body",
      "timestamp": "2026-02-17T12:00:00Z",
      "issue_url": "https://github.com/org/repo/issues/1"
    }
  ]
}
```

**Rules**:
- Same fingerprint to same repo within 24h: block with "Already filed" message
- More than 5 issues to same repo within 24h: warn and require extra confirmation
- More than 20 issues to same repo within 7 days: block with "Rate limit exceeded" message

#### FR-7: Issue Format for Construct Repos

Issues filed on construct repos follow a structured, redacted format:

```markdown
## [Loa Feedback] {summary}

**Source**: {feedback_type} (user feedback / audit / review)
**Loa Version**: {version}
**Pack**: {vendor}/{pack} v{version}
**Severity**: {severity_if_applicable}

### Description

{redacted description of the finding}

### Details

{redacted file references, NO code snippets by default}

---
Filed by [Loa Framework](https://github.com/0xHoneyJar/loa) with user confirmation
```

#### FR-8: Configuration

```yaml
# .loa.config.yaml
feedback:
  routing:
    enabled: true
    auto_classify: true
    require_confirmation: true  # MUST remain true for construct routing
    construct_routing:
      enabled: true             # Master toggle for construct feedback
      attribution_threshold: 0.33 # Minimum confidence to suggest construct routing
      redaction:
        strip_absolute_paths: true
        strip_secrets: true
        strip_env_vars: true
        include_snippets: false   # Default OFF for external repos
        include_file_refs: true   # Paths redacted to relative
        include_environment: false # Default OFF
      rate_limits:
        per_repo_daily: 5        # Warn threshold
        per_repo_daily_hard: 20  # Block threshold
        dedup_window_hours: 24
```

### Phase 2 (future cycle — deferred)

| Deferred FR | Description |
|-------------|-------------|
| FR-5-future | Automated pipeline routing (Bridgebuilder, audit, review, bug) |
| FR-9-future | Bidirectional feedback (vendor responses) |
| FR-10-future | Feedback analytics for vendors |

Automated pipeline integration (Bridgebuilder, audit-sprint, review-sprint, bug triage) is deferred until Phase 1 validates the core attribution and routing logic with `/feedback`.

## 5. Technical & Non-Functional Requirements

### NFR-1: Permission Safety

Filing issues on external repos requires the user's `gh` CLI to have write access to that repo. If `gh` auth doesn't cover the target repo:
- Show clear error: "Cannot file on {repo} — gh CLI lacks write access"
- Offer fallback: copy redacted issue to clipboard
- Never attempt to authenticate on behalf of the user

### NFR-2: Graceful Degradation

| Scenario | Behavior |
|----------|----------|
| Construct has no `source_repo` | Fall back to existing 4-repo routing, warn user |
| `gh` lacks access to construct repo | Offer clipboard fallback |
| Attribution confidence < threshold | Don't suggest construct routing |
| Constructs not installed | Existing routing unchanged |
| Manifest appears tampered (org mismatch) | Show trust warning, require explicit confirmation |
| Dedup ledger missing/corrupt | Create new ledger, proceed |

### NFR-3: No Registry API Dependency

Attribution and routing use LOCAL manifest data only (`.claude/constructs/` directory). No network calls to the constructs registry API. This keeps the feature working offline and avoids coupling to API availability.

### NFR-4: Backward Compatibility

- All existing `/feedback` behavior unchanged when no constructs are installed
- All existing `feedback-classifier.sh` tests continue to pass
- The 4 hardcoded repo categories remain as-is
- New `construct` category is additive only

### NFR-5: Security Boundary

External construct repos are an **untrusted trust boundary**. All content crossing this boundary must be:
1. Redacted (FR-5)
2. User-confirmed (FR-4)
3. Rate-limited (FR-6)
4. Source-validated (FR-2)

## 6. Scope & Prioritization

### In Scope (Phase 1 MVP)

1. Construct attribution engine with defined scoring algorithm (FR-1)
2. Source repo resolution with trust validation (FR-2)
3. Extended feedback classifier with construct category (FR-3)
4. `/feedback` command routing with redaction preview (FR-4)
5. Content redaction engine for external issues (FR-5)
6. Dedup ledger and rate limiting (FR-6)
7. Structured issue format (FR-7)
8. Configuration (FR-8)

### Out of Scope

- Automated pipeline routing (Bridgebuilder, audit, review, bug) — Phase 2
- Constructs network API relay (server-side routing) — direct `gh` only
- Auto-filing without user confirmation — always prompt
- Construct vendor notification system (email, webhook)
- Feedback analytics dashboard for vendors
- Bidirectional feedback (vendor responding back through Loa)
- Registry manifest schema enforcement (vendors opt in to `source_repo`)

## 7. Risks & Dependencies

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| User's `gh` auth lacks write to construct repo | High | Medium | Clipboard fallback, clear error |
| Vendors don't declare `source_repo` | Medium | High | Graceful degradation, warning; THJ can seed field in first-party packs |
| Supply-chain: tampered manifest redirects feedback | Low | High | Org mismatch warning, user confirmation, redaction |
| False attribution (feedback routed to wrong construct) | Low | Medium | Confidence threshold, user confirmation, disambiguation |
| Spam/abuse of vendor repos | Low | High | Dedup ledger, rate limits, confirmation |

### Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| `gh` CLI installed and authenticated | Existing requirement for `/feedback` | Low |
| Constructs installed locally | Required for attribution | Low |
| `manifest.yaml` with `source_repo` field | New field, vendor opt-in | Medium |

### Flatline Review Findings Addressed

| Finding | Resolution |
|---------|------------|
| IMP-001: Confidence scoring undefined | FR-1 now defines weighted signal algorithm |
| IMP-002: No dedup/rate limiting | FR-6 adds local ledger with dedup + throttling |
| IMP-003: Untrusted manifest routing | FR-2 adds org validation + trust warnings |
| IMP-005: No content redaction | FR-5 adds redaction engine with user toggles |
| SKP-002: Supply-chain exfiltration | FR-2 validation + FR-5 redaction + always-prompt |
| SKP-005: Scope too large | Phased: core routing now, pipeline integration deferred |
