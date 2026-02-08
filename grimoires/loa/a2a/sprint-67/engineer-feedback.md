# Sprint 4 (Global: sprint-67) — Engineer Feedback

## Verdict: CHANGES_REQUIRED

## Issue 1: postReview() broken by allowlist hardening (CRITICAL)

**File**: `.claude/skills/bridgebuilder-review/resources/adapters/github-cli.ts`
**Lines**: 257-268 (call site) vs 44-47 (validation)

### Problem

The hardened `assertAllowedArgs()` requires `args[1]` to be the endpoint (must start with `/`). However, `postReview()` places `-X` at `args[1]`:

```typescript
// Line 257-261 — args[1] is "-X", not the endpoint
await gh([
  "api",        // args[0] = "api"
  "-X",         // args[1] = "-X" ← FAILS: doesn't start with "/"
  "POST",       // args[2]
  `/repos/...`, // args[3] = actual endpoint
  ...
]);
```

The `assertAllowedArgs()` check at line 46-48 will throw:
```
Error: gh api endpoint missing or invalid
```

This means **every call to `postReview()` will throw at runtime**. The review pipeline will never be able to post reviews.

### Fix

Reorder `postReview()` args to match the canonical `gh api <endpoint> [flags]` pattern:

```typescript
await gh([
  "api",
  `/repos/${input.owner}/${input.repo}/pulls/${input.prNumber}/reviews`,
  "-X",
  "POST",
  "--raw-field",
  `body=${body}`,
  "-f",
  `event=${input.event}`,
  "-f",
  `commit_id=${input.headSha}`,
]);
```

This puts the endpoint at `args[1]` where the allowlist expects it, with `-X POST` as subsequent flags.

## Summary

All other acceptance criteria PASS. This is the only issue — but it's a runtime crash on every review post, so it must be fixed before approval.
