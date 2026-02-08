# Sprint 4 (Global: sprint-67) — Engineer Feedback (Round 2)

## Verdict: All good

All acceptance criteria verified against actual code:

### Task 4.1: Endpoint allowlist hardening — PASS
- `args[1]` position enforced (line 46)
- `FORBIDDEN_FLAGS` blocks all 7 dangerous flags (lines 31-39)
- `-X` restricted to POST only (lines 69-74)
- `auth status` requires exactly 2 args (line 80)
- All 7 call sites verified compatible with new allowlist

### Task 4.2: Information leakage elimination — PASS
- `gh()` error: exit code only (line 113-114)
- `parseJson()`: no raw content (line 123)
- Anthropic constructor: no `sk-ant-...` (line 21)
- Anthropic retry/non-OK: no response body (lines 72, 78)
- Reviewer sanitizer logs: count only (lines 181, 200)
- Reviewer error logs: code/category/source only (lines 270-272)

### Task 4.3: Double marker fix + reviewed count — PASS
- Marker only in `postReview()` adapter (line 254-255)
- `reviewed` counts `r.posted` only (line 312)

### Task 4.4: Repo filtering + network retry — PASS
- `accessibleRepos` Set built in preflight (lines 76-87)
- Early exit on zero accessible (lines 89-92)
- Items filtered by `repo_inaccessible` (lines 108-113)
- Network retry on TypeError/ECONNRESET/ENOTFOUND/EAI_AGAIN/ETIMEDOUT (lines 106-110)
- Model validation in constructor (lines 23-25)

### Previous Feedback — RESOLVED
- `postReview()` args reordered: endpoint at `args[1]`, flags follow (line 257-268)

### Note (non-blocking)
`adapters/index.ts:33` still has the old `sk-ant-...` error message in `createLocalAdapters()`. This is dead code since `AnthropicAdapter` constructor validates first. Not a Sprint 4 acceptance criterion — can be cleaned up later.
