---
name: bridgebuilder-review
description: "Bridgebuilder — Autonomous PR Review"
role: review
effort: xhigh  # cycle-114 FR-3: multi-model deep review — deepest reasoning
# cycle-114 FR-4: this review skill legitimately writes STATE-zone artifacts
# (review records, vision/lore entries), so Write is retained; app-code
# prevention is governed by zones. The harness removes implementation-only
# mutations (notebook edits + git index/commit/push) so it cannot land code.
disallowed-tools:
  - NotebookEdit
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git push *)
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: true
  user_interaction: false
  agent_spawn: true
  task_management: false
cost-profile: heavy
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/bridgebuilder]
    permission: read
  app:
    permission: none
---

<permission_grants>
## Permission Grants (MAY — registry-rendered)

Precedence: NEVER > MUST > ALWAYS > SHOULD > MAY. Cite the constraint ID when exercising a grant.

<!-- @constraint-generated: start bridgebuilder_review_grants | hash:70750066881f676d -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
1. MAY question the framing of requirements during `/plan-and-analyze` and bridge reviews, proposing alternative problem definitions when the analysis warrants reframing
2. MAY propose alternative approaches that challenge existing architecture during bridge reviews and `/review-sprint`
3. MAY create SPECULATION findings during planning and review skills (`/plan-and-analyze`, `/architect`, `/review-sprint`, bridge reviews) — explicitly excluded from `/implement` and `/audit-sprint`
<!-- @constraint-generated: end bridgebuilder_review_grants -->
</permission_grants>


# Bridgebuilder — Autonomous PR Review

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- `ANTHROPIC_API_KEY` environment variable set
- Node.js >= 20.0.0

## Usage

```bash
/bridgebuilder                          # Review all open PRs on auto-detected repo
/bridgebuilder --dry-run                # Preview reviews without posting
/bridgebuilder --pr 42                  # Review only PR #42
/bridgebuilder --repo owner/repo        # Target specific repo
/bridgebuilder --no-auto-detect         # Skip git remote detection
```

## How It Works

1. Resolves configuration from 5-level precedence: CLI > env > YAML > auto-detect > defaults
2. Detects current repo from `git remote -v` (unless `--no-auto-detect`)
3. Fetches open PRs via `gh` CLI
4. For each PR:
   - Checks if already reviewed (marker: `<!-- bridgebuilder-review: {sha} -->`)
   - Builds review prompt from persona + truncated diff
   - Calls Anthropic API for review generation
   - Sanitizes output (redacts leaked secrets)
   - Posts review to GitHub (`COMMENT` or `REQUEST_CHANGES`)
5. Prints JSON summary with counts and `verdicts`: one entry per PR with
   `repo`, `pr`, `headSha`, `verdict`, `highestSeverity`, and `mergeBlocked`.

For a merge handoff, match the entry to the current PR head and inspect the
body-derived verdict. `REQUEST_CHANGES`, HIGH/CRITICAL findings, `UNKNOWN`,
missing entries, or `mergeBlocked: true` block clearance. `reviewed: 1`,
`errors: 0`, exit 0, and GitHub `COMMENTED` describe execution, not approval.
Fix blockers and obtain a current-head review before reconsidering a merge.
An explicit `APPROVE` with `mergeBlocked: false` still requires the repository's
normal merge authorization and checks.

### Large pull requests: the paged, SHA-pinned fetch (cycle-133 C-1, KF-054)

Large PRs are fetched in two SHA-pinned passes (list, select within `max_files` / `max_diff_bytes`, re-read only the
selected pages; a head move restarts once, a second degrades as `pr_head_moved`). Every review carries a **coverage
record** (`verdicts[].coverage`; counts, omitted paths and a `<!-- bridgebuilder-coverage: {…} -->` marker in the posted
review): `reviewed[]`, `omitted[]` (reason, `pattern`, `fetch`), `protected_kept`, `reviewignore_source`. An added file
listed without a patch is read by content at the head sha and reviewed as an all-additions patch (`source: "contents"`),
bounded by bytes, `max_content_fetches` (20) and 120 s; other outcomes stay `no_patch` with `omitted[].fetch` naming
why (cycle-135, bd-w5pd9). See `resources/exclusions-and-coverage.md` for the fetch rules, fields and rendering.


| Omission reason | Blocks the merge |
|---|---|
| `excluded_loa`, `excluded_pattern`, `renamed` (no content change) | never |
| `file_cap`, `byte_budget`, `no_patch`, `patch_truncated`, `page_incomplete`, `excluded_fail_closed` | when the file is a reviewable code file (code, scripts, config, docs) |
| files GitHub counts but does not list (`unknown_omitted`, above the 3,000-file cap or on an unread page) | always |

A blocking omission sets `degraded: true` and `mergeBlockedReason: incomplete_coverage`, and the verdict is `UNKNOWN`
unless a finding already requires `REQUEST_CHANGES`.

### Verdict and the guarded consensus writer (cycle-133 C-2, KF-055)

The consensus comment's findings block is rendered from the consensus, never written by the writer model. Every
canonical field (`id`, `file`, `anchor_line`, `anchor_line_end`, `severity`, `confidence`, `failure_scenario`,
`suggestion`, `blocking`) is carried byte for byte, with ids made unique. The writer's output is posted as a separate
**Commentary** section. It is admitted only when two checks pass:

- **Writer eligibility.** The writer route must enforce a no-tool dispatch, reported by the adapter in the dispatch
  result and verified before and after the call. `bridgebuilder.writer_role_allowlist` defaults to `claude-headless`
  (`--tools ""`, plan mode), `anthropic-api`, `openai-api`, `google-api` and `bedrock-api`. It is read from trusted
  configuration only and can narrow the list, never widen it. `codex-headless` is refused until a test proves its
  native tools cannot execute. A google writer is refused while `hounfour.headless.agy_opt_in` is on. A reply that
  carries a tool call is refused. Failing this check is `writer_not_eligible`.
- **The enrichment guard** (`core/enrichment-guard.ts`). It rejects provider tool-call grammar (a line-start
  `<invoke`/`<function_calls` tag, or a `tool_use`/`tool_calls`/`function_call`/`toolUse`/`functionCall` JSON key)
  outside fenced code and outside JSON string values. It also rejects a findings block of the writer's own, a
  duplicated id, or an echoed finding with an altered or missing canonical field or verdict. A faithful echo is
  accepted and stripped. Failing this check is `enrichment_guard_rejected`.

On either failure the un-enriched consensus is posted, the reason is named in the comment, and the run exits 3.
The single-model two-pass path applies the tool-grammar check to its Pass 2 output as well.

The verdict (`core/review-verdict.ts`) applies these rules in order:

1. Any finding with `blocking: true` or severity CRITICAL, BLOCKER or HIGH gives `REQUEST_CHANGES`.
2. A guard rejection, incomplete coverage or a fetch-side degradation gives `UNKNOWN` with `mergeBlocked: true` and
   the reason.
3. Two blocks, a malformed block, a voice without a valid block, or a block verdict contradicting rule 1 give
   `verdict_conflict`: `UNKNOWN` and `mergeBlocked: true`. Under rule 1 the verdict stays `REQUEST_CHANGES` and the
   conflict is still recorded.
4. Exactly one valid consensus block gives its `verdict`. `COMMENT` and `APPROVE` give `mergeBlocked: false`.
5. With no block, the prose rule applies.

INFO, PRAISE, SPECULATION and REFRAME never block. `writer_not_eligible` degrades the run without changing the
verdict, because the un-enriched consensus is authoritative.

`degraded_reason` is one of `files_payload_oversize`, `files_list_truncated`, `page_incomplete`,
`patch_fetch_rate_limited`, `pr_head_moved`, `incomplete_coverage`, `enrichment_guard_rejected`,
`writer_not_eligible` or `verdict_conflict` (`core/run-outcome.ts`). The summary JSON carries `degraded`,
`degraded_reason` and `mergeBlockedReason` per verdict, and `degraded_reasons` for the run.

## Configuration

Set in `.loa.config.yaml` under `bridgebuilder:` section, or via environment variables:

| Setting | Env Var | Default |
|---------|---------|---------|
| repos | `BRIDGEBUILDER_REPOS` | Auto-detected from git remote |
| model | `BRIDGEBUILDER_MODEL` | `opus` (alias → the catalog's current Opus; cycle-126) |
| dry_run | `BRIDGEBUILDER_DRY_RUN` | `false` |
| max_prs | — | `10` |
| max_files_per_pr | — | `50` |
| max_diff_bytes | — | `512000` (bounds retained and submitted patch bytes; cycle-133 C-1) |
| gh_max_buffer_bytes | — | `67108864` (64 MiB per `gh` call, which receives one page of the files list; 1 MiB … 512 MiB, else the default with a warning; cycle-133 C-1) |
| exclude_patterns | — | always prefixed with `evals/fixtures/review-prs/**` and `grimoires/loa/reports/ablation-2.0/*-grades/**`, applied before any patch is retained, under self-review too (cycle-133 C-1) |
| writer_role_allowlist | — | `[claude-headless, anthropic-api, openai-api, google-api, bedrock-api]`; trusted configuration only; narrows, never widens (cycle-133 C-2) |
| max_input_tokens | — | `8000` |
| max_output_tokens | — | `4000` |
| persona_path | — | `grimoires/bridgebuilder/BEAUVOIR.md` |

### Exclusion patterns and protected paths (cycle-135, bd-ow72o / bd-i4fyw)

One gitignore-like grammar and matcher for `exclude_patterns`, `--exclude`, `.reviewignore` and the defaults on every
Node version: a pattern without `*`, `?`, `{`, `[` names whole segments (`PROCESS.md` ⇢ `docs/PROCESS.md`, never
`MYPROCESS.md`); slashless wildcards float, wildcards with a `/` are root-anchored; negation, escapes, extglob and nested
braces are rejected with a WARN. `protected_paths` (default `.github/workflows/**`, `.github/actions/**`,
`.github/CODEOWNERS`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/**`, `.husky/**`,
`.reviewignore`; `[]` disables) leave the review only through an explicit root-anchored name or full path; wildcards and
floating names keep them (`protected_kept`). On a pull request these keys, `exclude_patterns`, `fetch_missing_patches`
(`true`) and `max_content_fetches` (`20`) follow the trusted config, and `.reviewignore` is read from the PR base (a
failed base copy → `base_unavailable`, review degraded). See `resources/exclusions-and-coverage.md` for the full rules.

### Invocation trust contract (#1050)

Run `/bridgebuilder` from a **trusted checkout** (your default branch or a clean clone) — never
from a working tree where untrusted PR-head content has been checked out (e.g. after a manual
`gh pr checkout`). BB fetches PR data via `gh api` (diff-as-data) and never writes PR files to the
working tree, so the reviewed diff is safe; but `.loa.config.yaml` (models, budgets,
`cross_repo.allowed_owners`, `cross_repo.manual_refs`) is read from the **local checkout**, which
must therefore be trusted. The auto-detected cross-repo allowlist defaults to the reviewed PR's own
org (derived from PR metadata, independent of config); `allowed_owners` / `manual_refs` only widen
that and assume a trusted config source. Investigated + closed as not-applicable in the shipped
invocation model (no PR-head checkout) — see #1050. Since cycle-129 the provider, locality and
exit keys follow the trusted-source precedence below even when the checkout is a PR head.

## Self-Review Opt-In (#796 / vision-013)

When BB reviews a PR that modifies BB itself — or any other framework file under `.claude/`, `grimoires/`, `.beads/`, etc. — the Loa-aware filter normally strips those files from the review payload before the multi-model pass. This is correct for code-PR reviews (no review noise from grimoire side-effects) but inverts on self-modifying PRs (the framework files ARE the substance).

To opt a single PR into self-review (framework files visible to all reviewer models), apply the label:

```
bridgebuilder:self-review
```

When detected, BB:

- Skips the LOA framework exclusion for that PR's review pass — `.claude/`, `grimoires/`, `.beads/` files become reviewable
- **Continues to honor `.reviewignore` operator-curated patterns** (BR-003 / BB-001-security): `secrets/`, `vendor/`, private-doc patterns in your repo's `.reviewignore` still exclude their matches under self-review. The label is an Allow on framework files, NOT a global Deny suppressor.
- Surfaces a banner in the review output:
  - With `.reviewignore` user patterns: `[Loa-aware: self-review opt-in active — framework files included; .reviewignore (N user patterns) still honored (vision-013 / #796)]`
  - Without: `[Loa-aware: self-review opt-in active — framework files included (vision-013 / #796)]`
- Sets `truncated.selfReviewActive: true` on the typed `TruncationResult` (downstream consumers — cache key, audit logs, future analyzers — read this field; never substring-match the banner prose, BB-797-001)
- Leaves the global config (`loaAware`) untouched — the opt-in is per-PR, not workspace-wide
- The Pass 1 cache key includes `selfReview` as a distinct dimension, so toggling the label on a PR with unchanged `headSha` produces a fresh review (BB-003-cache)

Use this for: bridgebuilder TS adapter changes, cycle-planning PRs (PRD/SDD/sprint), construct manifest changes, anything where the framework artifacts ARE the diff. The label is a single source of truth (constant `SELF_REVIEW_LABEL` in `core/truncation.ts`); substring matches like `bridgebuilder:self-review-extra` do NOT trigger.

## Persona

Override the default reviewer persona by creating `grimoires/bridgebuilder/BEAUVOIR.md`. The default persona reviews across 4 dimensions: Security, Quality, Test Coverage, and Operational Readiness.

## Execution

This skill runs `entry.sh` which invokes the compiled Node.js application:

```bash
.claude/skills/bridgebuilder-review/resources/entry.sh [flags]
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All reviews completed successfully |
| 1 | One or more reviews encountered errors |
| 3 | Review completed DEGRADED with a named `degraded_reason` (coverage, guard, writer, verdict conflict; both modes; cycle-133 C-1/C-2), or a multi-model consensus DEGRADED: fewer voices completed than planned, or a degraded verdict-quality band. The JSON (`degraded`, `verdicts[].voices.incomplete`) and the comments are written first; callers print a WARN naming the voices and carry on. `bridgebuilder.exit_on_degraded: 0` restores exit 0 (cycle-129, DEC-0150) |
| 4 | `entry.sh` preflight: `node_modules/zod` missing (`npm ci`); was 3 before cycle-129 |

The completion banner prints `Done in Ns — completed/planned model(s) completed`.

## Trusted provider configuration (cycle-129 D-7.5, DEC-0170)

The full contract (sources, precedence, what a drifting PR head refuses with exit 5 and what it only WARNs about since
cycle-135) is in `resources/exclusions-and-coverage.md` § Trusted provider configuration; read it when configuring
providers or review scope for a pull-request run.
