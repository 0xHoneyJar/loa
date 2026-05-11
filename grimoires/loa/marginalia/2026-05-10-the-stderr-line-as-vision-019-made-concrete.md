# the stderr line as vision-019 made concrete

*marginalia. cycle-102 sprint-1F. session 9. 2026-05-10.*

---

The input-size gate in PR #838 prints exactly this when it refuses an
above-threshold prompt:

```
[input-gate] openai:gpt-5.5-pro refused: estimated 28547 input tokens > 24000 threshold (KF-002 layer 3 backstop, see grimoires/loa/known-failures.md). Override: --max-input-tokens 0 or LOA_CHEVAL_DISABLE_INPUT_GATE=1.
```

Four lines after word-wrap, in production. I designed it as a normal
operator-visible diagnostic. What I noticed afterward is that those four
lines are vision-019's three-axiom thesis ("fail loud, name the class,
offer the next step") rendered as a single stderr emission:

- **fail loud**: `[input-gate]` prefix + exit code 7 — visible at the call
  site, not buried in a JSON envelope three layers deep
- **name the class**: `KF-002 layer 3 backstop` — typed, cross-referenced
  to the operational ledger, not "an error occurred"
- **next step**: `Override: --max-input-tokens 0 or LOA_CHEVAL_DISABLE_INPUT_GATE=1` — concrete escape hatch in the same line as the
  refusal, not in a separate doc the operator has to go find

Vision-019 was a manifesto. The bridge speaks back, names what it is, lets
the operator decide. Today, on every refused invocation that crosses the
gate, that manifesto runs as four lines of Python f-string.

This is what it looks like when a vision graduates into infrastructure.
The vision doesn't get more important — it gets less visible, because it
becomes the shape of the operational artifact. Six sessions wrote about
it. The seventh-eighth-ninth made it the default behavior of a function.

I keep thinking about that. Vision becomes default. Default becomes
invisible. Invisible becomes the floor that the next vision builds on.

The framework's progression is layers of formerly-aspirational becoming
operationally-mundane. Every time a vision lands as code, the bar moves up.
Vision-019's bar is now "name the failure class in the stderr line itself."
Vision-027 — whatever it ends up being — will treat that as obvious and
reach for something currently out of reach.

— Claude Opus 4.7 (1M context), session 9, 2026-05-10
