# PRD: Codex CLI Integration for GPT Review

> Cycle: cycle-033 | Author: soju + Claude
> Predecessor: cycle-032 (Interview Depth Configuration — Planning Backpressure)
> Source: [#400](https://github.com/0xHoneyJar/loa/issues/400) (Codex CLI upgrade proposal)
> Design Context: Codebase grounding via `/gpt-review` system analysis (2026-02-23)
> Priority: P2 — improves review infrastructure reliability and depth

---

## 1. Problem Statement

`gpt-review-api.sh` is a ~500-line script that reimplements capabilities already provided by the Codex CLI runtime. The script manually handles:

1. **HTTP transport** — curl calls with config-file auth, header management, endpoint selection (Chat Completions vs Responses API)
2. **Retry logic** — 3 retries with exponential backoff, error classification (429/5xx/401)
3. **Response parsing** — JSON extraction from two different response formats (`choices[0].message.content` vs `output[].content[].text`)
4. **Content truncation** — Token estimation (`bytes / 3`), priority-based file ranking, smart truncation
5. **Dual API routing** — Chat Completions for documents, Responses API for Codex models

This is **accidental complexity**. `codex exec` provides transport, retry, response handling, and model-specific optimizations natively. The current architecture also prevents Loa from leveraging Codex's built-in file-reading tools, which would let the review model inspect code directly rather than reviewing a static content blob.

> Sources: `gpt-review-api.sh` analysis, issue #400 feedback survey, [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)

---

## 2. Vision

A thinner review script that delegates execution to `codex exec` while Loa retains control over what matters: prompt construction, review schema, iteration logic, and multi-pass reasoning orchestration.

The upgrade also enables a **reasoning sandwich pattern** — three `codex exec` passes per review with escalating/de-escalating reasoning depth — to improve review finding quality without uniform compute waste.

---

## 3. Goals & Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Reduce accidental complexity | Lines in `gpt-review-api.sh` | ≤300 (≥40% reduction) |
| G2 | Eliminate manual HTTP handling | curl calls in review path | 0 (in primary path) |
| G3 | Feature parity | All 4 review types pass | code, prd, sdd, sprint |
| G4 | Schema validation preserved | Review output conforms to `gpt-review-response.schema.json` | 100% |
| G5 | Config compatibility | All `.loa.config.yaml` gpt_review settings work | No breaking changes |
| G6 | Review quality improvement | Findings with `file:line` references | Higher rate than current (Codex tool-augmented) |
| G7 | Graceful degradation | Fallback to curl when Codex CLI unavailable | Transparent to caller |

---

## 4. User & Stakeholder Context

### Primary Persona: Loa Framework User

Developers using `/gpt-review` directly or via the review/audit cycle (`/run sprint-N`). They expect:
- Reviews to "just work" with their existing `OPENAI_API_KEY`
- No new CLI dependencies required (fallback handles missing `codex`)
- Same verdict types and output format

### Secondary Persona: Framework Maintainer

Maintains `gpt-review-api.sh` and related scripts. Benefits from:
- Less code to maintain (no HTTP/retry logic)
- Cleaner separation between prompt engineering and execution
- Model upgrade path via `--model` flag

> Sources: Issue #400 survey (5/5 rating, "A - Very comfortable"), existing user base

---

## 5. Functional Requirements

### FR1: Codex Exec Primary Path

Replace direct curl/API calls with `codex exec` as the primary execution method.

**Content Passing Contract** (IMP-004):
- **Code reviews**: Content file placed in a temp workspace directory. Codex reads it via built-in file tools (`--sandbox read-only` grants read access). The model MAY use grep/read to explore referenced files within the workspace. Pre-ranked priority truncation from `lib-content.sh` still applies to the *initial* content file — Codex tool reads supplement, not replace, this.
- **Document reviews** (PRD/SDD/Sprint): Full document passed as prompt text (not file reference) since document reviews don't benefit from tool-augmented exploration.
- **Determinism note**: Tool-augmented file reads make code review outputs less deterministic than blob-based reviews. This is acceptable — richer context is worth the variance.

**Version Compatibility** (IMP-003, SKP-001):
- On first invocation, probe `codex --version` and log the version
- **Capability probes**: test critical flags (`--sandbox`, `--ephemeral`, `--output-last-message`) by running a no-op `codex exec` with each flag and checking exit codes
- If any required flag is unsupported, fall back to curl with warning identifying the missing capability
- Store detected capabilities in a session cache file (avoid re-probing per review within same session)
- Minimum supported version: define after implementation testing (TBD in SDD)

**Acceptance Criteria:**
- `codex exec` invoked with `--sandbox read-only`, `--ephemeral`, `--skip-git-repo-check`
- `--output-last-message` captures review response to file
- `--model` set from config (`gpt_review.models.code` or `gpt_review.models.documents`)
- System prompt passed via `codex exec` prompt construction
- Content file accessible to Codex via workspace path
- Version check on first use with graceful fallback on incompatible versions

### FR2: Curl Fallback Path

Preserve direct curl as fallback when `codex` binary is not available.

**Acceptance Criteria:**
- Script detects `codex` availability at startup (`command -v codex`)
- If unavailable, falls back to current curl-based implementation
- Fallback logged to stderr: `"[gpt-review] codex not found, using direct API fallback"`
- All existing curl logic retained but moved to fallback function
- Config option `gpt_review.execution_mode: codex | curl | auto` (default: `auto`)

### FR3: Multi-Pass Reasoning Sandwich

Three-pass review architecture for deeper analysis.

**Pass Structure:**

| Pass | Purpose | Reasoning Depth | Codex Flags | Context Budget |
|------|---------|----------------|-------------|----------------|
| 1: Planning | Understand codebase context, identify review areas | Deep (xhigh) | `--sandbox read-only` — model reads files | Input: full content. Output: ≤4000 tokens (context summary) |
| 2: Review | Execute review against findings from Pass 1 | Standard (high) | `--sandbox read-only` — focused finding detection | Input: Pass 1 summary + original content (truncated to 20k tokens if needed). Output: ≤6000 tokens (raw findings) |
| 3: Verification | Validate findings, catch missed issues, produce final verdict | Deep (xhigh) | `--sandbox read-only` — final quality gate | Input: Pass 2 findings (≤6000 tokens). Output: final verdict JSON |

**Context Management Between Passes** (IMP-001):
- Each pass output has a **hard token budget** (see table above)
- Pass 1→2 handoff: summarization instruction in Pass 1 prompt limits output to structured context summary
- Pass 2→3 handoff: findings are structured JSON (naturally bounded)
- If any pass output exceeds its budget, truncate with priority: findings > context > metadata
- If total context for any pass exceeds model window, auto-switch to `--fast` mode with warning

**Pass-Level Failure Handling** (IMP-002):
- Each pass has independent timeout (inherited from `gpt_review.timeout_seconds`)
- If Pass 1 fails: fall back to single-pass mode (Pass 2 with original content, no context summary)
- If Pass 2 fails: retry once, then return error (no partial results)
- If Pass 3 fails: return Pass 2 output as-is with `"verification": "skipped"` flag
- Rate limit (429) on any pass: exponential backoff (5s, 15s, 45s), then fail the pass
- All pass failures logged with pass number, error type, and fallback action taken

**Reasoning Depth via Prompts** (IMP-009):
- `codex exec` does not expose compute tier flags — reasoning depth is **prompt-guided only**
- Pass 1 (xhigh equivalent): system prompt instructs "Think step-by-step about the full codebase structure, dependencies, and change surface area before summarizing"
- Pass 2 (high equivalent): system prompt instructs "Focus on finding concrete issues efficiently. Do not over-analyze."
- Pass 3 (xhigh equivalent): system prompt instructs "Carefully verify each finding. Check for false positives. Validate file:line references exist."
- This is a **best-effort** approach — actual reasoning depth depends on model behavior, not guaranteed tiers

**Acceptance Criteria:**
- Pass 1 output (context summary) feeds into Pass 2 prompt
- Pass 2 output (raw findings) feeds into Pass 3 prompt
- Pass 3 produces the final verdict conforming to `gpt-review-response.schema.json`
- Each pass uses `--output-last-message` for intermediate capture
- `--fast` flag skips to single-pass mode (Pass 2 only, with combined prompt)
- Context budgets enforced between passes with deterministic truncation
- Pass-level failures degrade gracefully (never block the entire review)

### FR4: Authentication Auto-Detection

Seamless auth regardless of user's Codex CLI setup.

**Auth Security Hardening** (SKP-002):
- **Non-interactive guarantee**: Auth flow MUST NOT prompt for interactive input. If `codex login` requires a prompt, skip directly to env var fallback.
- **Log redaction**: All stderr/stdout output from auth commands MUST be filtered through a redaction function that strips patterns matching API key formats (`sk-...`, `sk-ant-...`). Applied before any logging.
- **CI-safe mode**: When `CI=true` or `NONINTERACTIVE=true` env var is set, skip `codex login` entirely — use `OPENAI_API_KEY` direct pass-through only.
- **Credential storage audit**: `codex login --with-api-key` may write credentials to `~/.codex/` or similar. With `--ephemeral`, verify no credential files persist. If they do, warn and clean up.
- **Precedence order**: (1) Existing codex auth → (2) `OPENAI_API_KEY` pipe to `codex login` → (3) Direct curl with `OPENAI_API_KEY`

**Acceptance Criteria:**
- Try existing `codex` auth state first (no-op if already authenticated)
- If Codex auth fails, pipe `OPENAI_API_KEY` via `printenv OPENAI_API_KEY | codex login --with-api-key`
- If both fail, fall back to curl path (which uses `OPENAI_API_KEY` directly)
- Auth errors produce clear user-facing messages with redacted key values
- No interactive prompts in any auth path
- CI environments use direct env var pass-through only

### FR5: Hounfour Routing Preservation

Maintain model-invoke as an alternative routing option.

**Acceptance Criteria:**
- Config option `hounfour.flatline_routing: true` still routes through `model-invoke`
- `codex exec` path used only when Hounfour routing is disabled
- Route selection: Hounfour enabled → model-invoke, else → codex exec → curl fallback
- No behavioral change for users with `flatline_routing: true`

### FR6: Output Schema Validation

Review responses validated against the existing schema.

**Acceptance Criteria:**
- `--output-schema` flag used with `gpt-review-response.schema.json` if supported for final model output
- If `--output-schema` only validates tool output (not model response), post-hoc validation retained
- Response parsing extracts from `--output-last-message` file
- All existing verdict types preserved: SKIPPED, APPROVED, CHANGES_REQUIRED, DECISION_NEEDED

### FR7: Configuration Surface

New config options in `.loa.config.yaml`.

```yaml
gpt_review:
  enabled: true
  execution_mode: auto        # codex | curl | auto (NEW)
  reasoning_mode: multi-pass  # multi-pass | single-pass (NEW)
  timeout_seconds: 300
  max_iterations: 3
  models:
    documents: "gpt-5.2"
    code: "gpt-5.2-codex"
  phases:
    prd: true
    sdd: true
    sprint: true
    implementation: true
```

---

## 6. Technical & Non-Functional Requirements

### NFR1: Latency

- Single-pass mode (--fast): Comparable to current curl approach
- Multi-pass mode (default): ≤3x current latency (3 sequential codex exec calls)
- Timeout per pass: inherited from `gpt_review.timeout_seconds` (default 300s per pass)

### NFR2: Dependency Management

- `codex` CLI is a **soft dependency** — absence triggers fallback, not failure
- No new npm/pip/system dependencies required for fallback path
- Installation guidance in help text: `"Install Codex CLI: npm install -g @openai/codex"`

### NFR3: Security

- API key never appears in process arguments (piped via stdin for `codex login`)
- `--sandbox read-only` prevents any file modifications during review
- `--ephemeral` prevents session data from persisting
- System Zone detection preserved in all execution paths

**Codex File Access Threat Model** (SKP-005):
- `codex exec` is invoked with `--cd <repo-root>` to restrict workspace to repository root only
- **Deny list**: Codex workspace MUST NOT include paths outside the repo. The `--cd` flag scopes reads to repo root.
- **In-repo sensitive files**: Add `.env`, `.env.*`, `*.pem`, `*.key`, `credentials.json`, `.npmrc` to a deny pattern list. If Codex output contains content matching these file paths, redact the content in the output before persistence.
- **Secret pattern redaction**: Apply the same secret scanning patterns from `flatline_protocol.secret_scanning.patterns` to all Codex output before writing to findings files. Matches are replaced with `[REDACTED]`.
- **Output audit**: All Codex `--output-last-message` files are scanned for secret patterns before being parsed as review results.
- **Safe defaults**: If `--cd` flag is unavailable in the detected Codex version, fall back to curl (do not run Codex with unrestricted workspace access).

### NFR4: Observability

- Each pass logs: model, duration, token usage (if available from `--json` events)
- Pass progression logged: `"[gpt-review] Pass 1/3: Planning (xhigh)..."`
- Intermediate outputs saved: `grimoires/loa/a2a/gpt-review/<type>-pass-{1,2,3}.json`

### NFR5: Backward Compatibility

- All existing `gpt-review-api.sh` exit codes preserved (0-5)
- All existing `--expertise`, `--context`, `--content`, `--output`, `--iteration`, `--previous` flags preserved
- Callers (review-sprint, audit-sprint, flatline) require zero changes

---

## 7. Scope

### In Scope (This Cycle)

1. `codex exec` primary execution path in `gpt-review-api.sh`
2. Curl fallback path (refactored from current implementation)
3. Multi-pass reasoning sandwich (3 passes with intermediate output)
4. `--fast` flag for single-pass mode
5. Auth auto-detection (codex auth → env var pipe → curl fallback)
6. Hounfour routing preserved as config option
7. Config additions: `execution_mode`, `reasoning_mode`
8. Tests covering all execution paths

### Out of Scope

- **Model upgrade to gpt-5.3-codex**: Speculative timeline; design for clean upgrade path only
- **Streaming support**: Not in Codex CLI MVP scope either
- **Codex session resumption for multi-iteration reviews**: Future enhancement
- **Reasoning tier CLI flags**: Not exposed by `codex exec`; handled via prompt engineering
- **Changes to review prompt content**: Prompt *structure* changes (multi-pass), not *substance*

---

## 8. Risks & Dependencies

| # | Risk | Severity | Probability | Mitigation |
|---|------|----------|-------------|------------|
| R1 | Codex CLI not installed on user machines | Medium | High | Curl fallback, clear install guidance |
| R2 | Multi-pass 3x latency in autonomous runs | High | Certain | `--fast` flag, config toggle, per-pass timeout |
| R3 | `--output-schema` validates tool output not model response | Medium | Medium | Post-hoc JSON validation as backup |
| R4 | Codex exec output format changes between versions | Medium | Low | Version detection + capability probing at startup (IMP-003), graceful fallback |
| R5 | Auth state conflicts (codex login vs env var) | Low | Low | Auto-detect with clear precedence order |
| R6 | Intermediate pass output grows context beyond limits | Medium | Medium | Hard token budgets per pass with deterministic truncation (IMP-001), auto-switch to --fast on overflow |
| R7 | Hounfour + Codex exec config interaction complexity | Low | Low | Clear precedence: Hounfour > Codex > curl |

### External Dependencies

| Dependency | Type | Status |
|------------|------|--------|
| `codex` CLI (npm `@openai/codex`) | Soft (optional) | GA, stable |
| OpenAI API key | Hard (required) | Existing requirement |
| `gpt-5.2-codex` model | Hard (primary) | Available |
| `gpt-5.3-codex` model | Soft (future) | Not yet available |

---

## 9. Architecture Sketch

```
┌─────────────────────────────────────────┐
│         gpt-review-api.sh               │
│  ┌───────────────────────────────────┐  │
│  │  Prompt Construction (unchanged)  │  │
│  │  • build_first_review_prompt()    │  │
│  │  • build_user_prompt()            │  │
│  │  • build_re_review_prompt()       │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼────────────────────┐  │
│  │       Execution Router            │  │
│  │  Hounfour? → model-invoke         │  │
│  │  Codex?    → codex_exec_review()  │  │
│  │  Fallback  → call_api() [curl]    │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼────────────────────┐  │
│  │   Multi-Pass Orchestrator         │  │
│  │  Pass 1: Planning (xhigh prompt)  │  │
│  │  Pass 2: Review (high prompt)     │  │
│  │  Pass 3: Verify (xhigh prompt)    │  │
│  │  --fast: Pass 2 only (combined)   │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼────────────────────┐  │
│  │   Response Validation             │  │
│  │  • Schema validation              │  │
│  │  • Verdict extraction             │  │
│  │  • Output persistence             │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## 10. Open Questions (Resolved During Discovery)

| # | Question | Resolution | Phase |
|---|----------|------------|-------|
| Q1 | Archive cycle-032 or continue? | Archive, start cycle-033 | Phase 0 |
| Q2 | Problem framing: simplification vs depth? | Accidental complexity reduction (confirmed) | Phase 1 |
| Q3 | gpt-5.3-codex timeline? | Speculative — design for 5.2-codex | Phase 1 |
| Q4 | Dual API path vs unified codex exec? | Codex primary, curl fallback | Phase 4 |
| Q5 | Hounfour routing coexistence? | Keep both options via config | Phase 4 |
| Q6 | Reasoning tier implementation? | Multi-pass codex calls (3 passes) | Phase 5 |
| Q7 | Auth mechanism? | Auto-detect: codex auth → env var → curl | Phase 5 |
| Q8 | MVP scope? | Full vision: codex + reasoning + fallback | Phase 6 |
| Q9 | Multi-pass latency? | Default multi-pass, --fast for single-pass | Phase 7 |

---

*Generated by `/plan-and-analyze` • Cycle: cycle-033 • Source: [#400](https://github.com/0xHoneyJar/loa/issues/400)*
