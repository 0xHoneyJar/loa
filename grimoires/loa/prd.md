# PRD: Bridgebuilder Large PR Support — Token Budget & Progressive Review

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Date**: 2026-02-09
**Issue**: #260

---

## 1. Problem Statement

The Bridgebuilder autonomous PR review skill cannot review large PRs. When invoked against PR #259 (10 files, 1787 additions, ~65KB diff), the skill fails at every configuration level:

1. **Default config** (`maxInputTokens: 8000`): Skipped as `prompt_too_large` — the 65KB diff alone estimates to ~16K tokens, double the budget
2. **CLI override attempt** (`--max-input-tokens 32000`): CLI parser doesn't accept token flags — only `--dry-run`, `--repo`, `--pr`, `--no-auto-detect` are parsed
3. **YAML config override** (`max_input_tokens: 64000`): Even when the token check passes, the API call fails with `E_LLM` (connection reset/timeout on large payloads)

The user reports: *"each of the times i have called the skill directly it has not actually been able to run due to these limits"*

This renders Bridgebuilder unable to review its own PRs — a critical gap for a review tool.

---

## 2. Root Cause Analysis

### 2.1 Token Budget Mismatch

The default `maxInputTokens: 8000` was tuned for small PRs (~10-15 files, <20KB diff). The token estimation formula `(systemPrompt.length + userPrompt.length) / 4` is deliberately conservative (over-estimates). For PR #259:

- Persona (BEAUVOIR.md): ~5-10KB
- PR metadata + format instructions: ~1KB
- Diff content: ~65KB (after truncation to `maxDiffBytes: 100000`)
- Total prompt chars: ~75KB → estimated ~18,750 tokens → exceeds 8,000 limit

### 2.2 CLI Configuration Gap

The `parseCLIArgs()` function only handles 4 flags: `--dry-run`, `--repo`, `--pr`, `--no-auto-detect`. Token/size limits are only configurable via YAML config. The user's attempt to pass `--max-input-tokens 32000` was silently ignored.

### 2.3 API Payload Limits

Even when YAML config raises `maxInputTokens` to 64000, the raw HTTP request body becomes very large. The Anthropic adapter uses a 120s timeout and 2 retries, but connection resets on large payloads suggest:
- Network/proxy intermediary dropping large requests
- API rate limiting on payload size (separate from token count)
- The request body includes the full prompt text as a JSON string

### 2.4 Truncation vs Token Check Ordering

The diff truncation (`maxDiffBytes: 100000`) runs BEFORE the token check, but the token check also includes the system prompt (persona). The truncation only budgets diff bytes, not total prompt bytes. This means:
- Diff is truncated to 100KB
- Persona adds 5-10KB
- Metadata/format adds ~1KB
- Total: 106-111KB → ~27K estimated tokens
- Even a generous `maxInputTokens` may not help if the actual API payload is too large

---

## 3. Goals

### Primary Goal
Make Bridgebuilder reliably review PRs of any reasonable size (up to ~200 files / 200KB diff).

### Secondary Goals
1. Make token/size configuration accessible from CLI (not just YAML)
2. Provide clear feedback when a PR is too large, with actionable guidance
3. Enable progressive review strategies for oversized PRs
4. Maintain zero external runtime dependencies (PRD NFR-1 from original Bridgebuilder)

### Non-Goals
- Adding a proper tokenizer (tiktoken) — would violate zero-dependency constraint
- Changing the Anthropic API adapter to use streaming — separate concern
- Supporting non-Anthropic LLM providers — out of scope

---

## 4. Users

| User | Need |
|------|------|
| Loa developer (primary) | Review own Loa PRs which include full PRD/SDD/sprint plan diffs |
| Autonomous `/run` pipeline | Automated review as part of sprint plan execution |
| OSS project maintainer | Review community PRs across repos |

---

## 5. Functional Requirements

### FR-1: Raised Default Token Budget

Raise `maxInputTokens` default from 8,000 to 128,000 (Sonnet 4.5 supports 200K context).

### FR-2: Raised Default Diff Byte Budget

Raise `maxDiffBytes` default from 100,000 to 512,000 (512KB).

### FR-3: CLI Flags for Token/Size Configuration

Add CLI flags: `--max-input-tokens`, `--max-output-tokens`, `--max-diff-bytes`, `--model`.

### FR-4: Increased API Timeout for Large Payloads

Scale timeout based on estimated prompt size: 120s default, 300s for large prompts.

### FR-5: Pre-flight Prompt Size Report

Log prompt size estimates before LLM call.

### FR-6: Graceful Oversized PR Handling

Actionable error messages instead of silent skips.

### FR-7: Raised Default Output Token Budget

Raise `maxOutputTokens` default from 4,000 to 16,000.

---

## 6. Non-Functional Requirements

- NFR-1: Zero external dependencies
- NFR-2: Backward compatibility with existing YAML configs
- NFR-3: No breaking CLI changes
- NFR-4: TypeScript compilation to dist/

---

## 7. Success Criteria

1. `/bridgebuilder-review --pr 259` succeeds on PR #259
2. CLI accepts new flags
3. Pre-flight prompt estimate logged
4. Oversized PRs produce actionable errors
5. Existing behavior unchanged
6. No new dependencies

---

## 8. References

- Issue: [#260](https://github.com/0xHoneyJar/loa/issues/260)
- Affected PR: [#259](https://github.com/0xHoneyJar/loa/pull/259)
- Bridgebuilder skill: `.claude/skills/bridgebuilder-review/`
