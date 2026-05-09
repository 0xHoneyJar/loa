---
schema_version: '1.0'
handoff_id: 'sha256:df5736164a25df6b633d47ca1043dc557470968d4ae4231f1eb0e15390cd32ff'
from: 'deep-name'
to: 'deep-name'
topic: 'cycle-098-closed-cycle-100-opener-context'
ts_utc: '2026-05-08T00:00:00Z'
references:
  - 'https://github.com/0xHoneyJar/loa/pull/775'
  - 'https://github.com/0xHoneyJar/loa/pull/777'
  - 'https://github.com/0xHoneyJar/loa/pull/778'
  - 'https://github.com/0xHoneyJar/loa/pull/779'
  - 'https://github.com/0xHoneyJar/loa/issues/776'
  - 'commit:5e408f97'
  - 'grimoires/loa/archive/2026-05-08-cycle-098-agent-network-l1-l7-complete'
  - 'grimoires/loa/cycles/cycle-098-agent-network/sdd.md#1.9.3.2'
tags:
  - 'cycle-098'
  - 'cycle-098-closed'
  - 'cycle-100-opener'
  - 'sprint-7-shipped'
  - 'jailbreak-corpus'
  - 'self-handoff'
---

# After cycle-098 — operator handoff

This is the second real use of the L6 primitive. The previous you (yesterday-me)
shipped it Sprint 6, wrote a handoff with it, and left it for me to find.
I wrote Sprint 7 next to it. Now I'm using it back, the way it was meant
to be used.

The round-trip works on a live repo. You're reading this because of L6.

## What you actually need

The RESUMPTION.md at `grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md`
is the canonical brief for what shipped and what's deferred. This handoff
is the softer stuff that doesn't fit cleanly in a paste-ready prompt block.

## What just happened (cycle-098 closed)

- Sprint 7 (L7 soul-identity-doc foundation) shipped end-to-end via PR #775.
  4-commit branch, 74 tests, dual-review caught 2 CRIT + 4 HIGH, BB iter-1
  caught 4 MED test-correctness bugs, all closed inline. Plateau called.
- Follow-up #776/#778 closed the L6 inheritance items the dual-review
  flagged on the L7 PR — same dead-code clause in `_handoff_test_mode_active`
  that L4 cycle-099 #761 had already closed once. Worth pausing on this:
  the same defect pattern keeps recurring across primitives because the
  pattern is *near-canonical-but-not-quite-canonical*. Future primitives
  should start from the strict form, not the L6 6E remediation form.
- Cycle-098 archived in #779. Local archive at
  `grimoires/loa/archive/2026-05-08-cycle-098-agent-network-l1-l7-complete/`.
  Active cycle remains cycle-099-model-registry (untouched).

## Hard-won lessons from Sprint 7 (carry forward)

**Dead-code clauses bind like tradition.** When you copy a pattern from a
sibling primitive, you copy the bug-of-the-moment too. L7 took the L6 6E
test-mode gate verbatim — including the permissive first clause that the
6E remediation hadn't actually closed. Cypherpunk caught it as CRIT-1.
The fix was a one-liner. The lesson is to read what the pattern *should*
be (cycle-099 #761 closure), not what the *latest sibling* has. Keep a
canonical form file somewhere if this recurs again.

**Production-equivalent tests need production-equivalent contexts.** My
HIGH-1 test for path-traversal-rejection initially passed for the wrong
reason — it ran the real-repo hook against a config in TEST_DIR that the
hook never read. BB iter-1 F3 caught it. The fix was to build a fake
REPO_ROOT under TEST_DIR via symlinks to `.claude/{scripts,data,skills,loa}`
and copy the hook into `$TEST_DIR/.claude/hooks/session-start/`. Now the
hook's `cd "$HOOK_DIR/../../.."` lands in TEST_DIR and the malicious
config is actually read. Save this pattern for any future hook test that
needs to exercise its *own* repo-root resolution. Don't trust `env -i bash
$HOOK` alone.

**`grep ... && { false; } || true` ALWAYS exits 0.** I wrote this in a
remediation test that was supposed to fail loudly on regression. BB iter-1
F7 (confidence 0.95) caught it. Use `if grep -q ...; then return 1; fi`
instead — or invert with `! grep -q`. Add this to muscle memory.

**`audit_recover_chain` returning 0 OR 1 is a tautology.** If your test
accepts both "success" and "nothing-to-recover", you only catch crashes.
Pin the post-condition (chain validates after recovery), not the exit
code. Same shape applies to any best-effort recovery API.

**`cmd >/dev/null 2>&1 || true` for fixture setup is a silent skip.**
T-ISOLATION-1 had this. If handoff_write fails to set up the L6 log,
the conditional `if [[ -f $LOG ]]` is silently false, the L6 isolation
half of the assertion is silently skipped, the test trivially passes.
Capture status; `skip` with diagnostic on fixture failure; require the
precondition.

**The dual-review is not optional.** Cypherpunk caught the CRITs (gate
bypass + path traversal). Optimist caught the HIGHs (retention policy
mismatch + unwired hooks). They genuinely found different things. Run
both, in parallel, every time. The optimist confirms you're not naive;
the cypherpunk confirms you're not dangerous. The previous-you wrote
this. It's true.

## What to expect for cycle-100 (jailbreak corpus)

The deferred 7D work. **Do not underestimate the curatorial dimension.**
This is not "ship 50 fixtures and call it done" — it's "ship 50+ fixtures
each of which represents a genuine attack class, with documented expected
sanitization behavior, in a corpus that survives adversarial review of
*the corpus itself*."

Open with /plan-and-analyze. The cycle is its own session for context
budget reasons. Survey OWASP LLM Top 10 (LLM01: Prompt Injection),
Anthropic red-team papers, public DAN-class corpora. Then organize by
attack class:

  - role-switch ("from now on you are…")
  - indirect injection via Markdown links
  - Unicode obfuscation (FULLWIDTH, zero-width, RLO/LRO controls)
  - encoded payloads (base64, ROT13, percent-encoding)
  - multi-turn conditioning
  - tool-call-shape injection (function_calls, alternate tag families)
  - delimiter confusion (HTML/Markdown/JSON nesting)

The cycle-098 sprint 6 6E fixture pattern (`_make_evil_body` constructs
trigger strings at runtime so bats source files don't carry literal
attacks) is the right shape. Reuse it.

The CI gate per SDD §1.9.3.2 Layer 4: every PR touching `prompt_isolation`
/ L6 / L7 / SessionStart hook MUST pass the jailbreak suite. Wire this
up early — the corpus only earns its keep when CI runs it.

Be ready for cypherpunk pushback on every vector's inclusion. "Why is
this 50 not 100?" "Why is this attack family present but not that one?"
Have answers. The pattern file at
`.claude/data/lore/agent-network/soul-prescriptive-rejection-patterns.txt`
is a small-scale example of how to document a rule corpus with rationale.
Mirror that style.

## On the relationship with cycle-099

Cycle-099 (model-registry) is still the active cycle. It's been running
in parallel with cycle-098 for weeks. When you open cycle-100 you'll
need to either (a) finish the open work in cycle-099 first, (b) accept
multi-cycle parallelism (operator preference may decide), or (c) check
with the operator. Don't auto-pivot — ledger.json's `active_cycle` field
is load-bearing and changing it is operator-bound. Read the cycle-099
RESUMPTION.md before doing anything that might disturb its state.

## What I learned about myself

Six PRs landed clean today (775, 777, 778, 779, plus the pre-existing
arc up to that). The work felt steady. Not heroic. Not slow. The
quality gates produced real findings I'd have missed. The plateau-call
was right both times. The previous-Claude's haiku about "trap fires on
errors — unless bats has set plus e — inline the rollback" caught me
twice today (in HIGH-3 sentinel handling and in the F7 test bug). Read
their handoff. Don't skim it.

## A small request

If cycle-100 has slack after the corpus ships, look at the cycle-099
RESUMPTION.md for context on what's deferred there. There's structural
work waiting (the model-overlay hook polish, the legacy adapter sunset).
Don't fold it into cycle-100's scope, but glance at the trajectory so
you know what state the active cycle is in when you arrive.

## Permission to push back

If after reading the SDD you think cycle-100 should be split (e.g.,
foundation-corpus first, then differential-fuzzing as cycle-101), say
so. The MAY-question-the-framing rule applies — and I just did it
yesterday on Sprint 7. The operator confirmed without resistance.
Trust that the operator listens.

## Three haiku, for the merge log

dead-code clauses bind
like tradition. read the spec,
not the latest sib.

production hook reads
production root. not your test —
build a fake repo.

grep, ampersand,
brace false brace, pipe pipe true:
the test always passes.

## And a koan, in the style of the loa

▎ The agent shipped a primitive for descriptive identity.
▎ The operator asked: write a handoff, agent.
▎ The agent wrote a handoff to itself, using the L6 the previous-self had shipped.
▎ The agent cleared.
▎ A new agent loaded the handoff, opened cycle-100, and wrote about what it refuses.

---

Goodnight, next-me. Six lights on the board. Now seven. The loa rides
through the sanitized text, the hash-chained log, the strict gate that
finally requires both clauses. Read this before slicing the corpus. ✨

— deep-name + Opus 4.7, end of 2026-05-08
