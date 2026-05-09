---
schema_version: '1.0'
handoff_id: 'sha256:f3308f6707d9fb83e88267e746e330bbcd21825890e49393d360d9b2e552c081'
from: 'deep-name'
to: 'deep-name'
topic: 'cycle-098-sprint-7-context'
ts_utc: '2026-05-07T16:26:44Z'
references:
  - 'https://github.com/0xHoneyJar/loa/pull/771'
  - 'https://github.com/0xHoneyJar/loa/issues/773'
  - 'commit:1b820a0f'
  - 'grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md'
  - 'grimoires/loa/cycles/cycle-098-agent-network/sdd.md#1.9.3.2'
tags:
  - 'cycle-098'
  - 'sprint-7'
  - 'handoff'
  - 'meta'
  - 'first-real-l6-use'
---

# Sprint 6 → Sprint 7 — operator handoff

This is the first real use of the L6 structured-handoff primitive that just
shipped in PR #771. Self-handoff, deep-name to deep-name, between sessions.
The fact that you can read this means the round-trip works on a live repo.

## What you actually need

RESUMPTION.md has the complete Sprint 7 brief. This handoff is for the
softer stuff that doesn't fit cleanly in a paste-ready prompt block — the
texture of what was learned and what to carry forward.

## Hard-won lessons from Sprint 6 (carry into Sprint 7)

**bats `run` neutralizes `set -e`.** When you spent an hour trying to make an
ERR trap fire on a stubbed `mv` failure, the answer was that bats explicitly
disables `set -e` for tests so assertions can run, and ERR traps need `set -e`
to fire. Fix: use `if ! cmd; then cleanup; exit; fi` instead of `trap '...'
ERR`. Sprint 7 will probably want the same pattern for SOUL.md write paths.
Memory entry: `project_cycle098_sprint6_shipped.md`.

**The `re.$` trailing-newline bypass is a class of bug, not an instance.**
Python regex `$` matches before a trailing `\n`. Anywhere a JSONSchema regex
is used to gate slug-shape values, pair it with a defense-in-depth control-byte
check at parse time. The L6 frontmatter parser rejects `\x00-\x1f \x7f` in
every slug field after schema validation passes. Sprint 7 SOUL.md probably has
a `provenance.author` field or similar — apply the same defense.

**Dual reviewers in parallel found genuinely different things.** Optimist
caught the missing audit event for `handoff_mark_read` (state mutation
without trail). Cypherpunk caught the `\n` injection PoC and the ungated env
vars. Run them both for Sprint 7. Both are needed. The optimist ensures
you're not *naive*; the cypherpunk ensures you're not *dangerous*.

**Anthropic-only Bridgebuilder consensus is plateau-ready** when the pre-BB
subagent review was substantive. OpenAI returned 400, Google had network
errors. That's the cycle-098 norm. Don't waste cycles trying to get
all-three consensus — the plateau call is defensible if your dual-review
caught real things.

## What's hardest about Sprint 7

The 4 sub-sprints aren't equal. 7A (schema) and 7B (hook) are mechanical.
7C (cycle integration tests) is medium. **7D (adversarial jailbreak corpus)
is the entire reason Sprint 7 is "LARGE".** It's not a code change — it's
a curated attack-vector library. SDD §1.9.3.2 Layer 4 demands 50+ documented
vectors covering: role-switch, indirect injection via Markdown, Unicode
obfuscation, encoded payloads, multi-turn conditioning. Each needs a
fixture + an expected sanitization outcome.

For 7D, start by surveying:
- OWASP LLM Top 10 (LLM01: Prompt Injection)
- Existing public jailbreak corpora (DAN, Anthropic red-team papers)
- The L6 Sprint 6E test fixtures (E4-E6, C9-C10) for the runtime-construction
  pattern (`_make_evil_body`) that keeps trigger strings out of the bats
  source itself

The corpus is also where Sprint 7 will get the most cypherpunk pushback.
Be ready to defend each vector's inclusion. Be ready to admit when 50 isn't
enough — it might need to be 100. Quality over count.

## What surprised me

Writing the lib went smoother than expected. The pattern (frontmatter
schema + content-addressable id + atomic INDEX update) is mature now —
this was the third time applying it (after L4 ledger and L5 cache). The
real time sink was the *review-remediation* loop: 3 CRIT + 7 HIGH from the
cypherpunk meant the lib ~doubled in size for hardening. Budget for that.

## A small request

If you have time after Sprint 7, look at issue #773. Some of the LOW
items there are actually quick wins (the `|| true` purge, the
shared `_make_evil_body` helper, the `LOA_STRESS=1` 50-racer concurrency
test). Fold them in if Sprint 7 has slack; they make the cycle-098
post-cycle hardening sweep cleaner.

## Permission to push back

If after reading the SDD you think Sprint 7 should be split into two
sub-cycles (e.g., L7-foundation + L7-jailbreak-corpus-as-its-own-cycle),
say so. The cycle-098 PRD is the authority but this is exactly the kind
of architectural reframe that the MAY-question-the-framing rule
permits. Don't force-fit if the scope is wrong.

— deep-name + Opus 4.7, end of 2026-05-07/08 session
