# Slice 2 — Adversarial Corpus (blind bounded input)

This is a **synthetic, bounded input corpus** for Aleph Slice 2. It is the raw
material the Research Précis is distilled from. It is deliberately written as a
**blind input**: it carries no answer key, no seeding notes, no disposition
labels, and no hints about how each fragment should be handled. Read `precis.md`
to see how Aleph dispositions this material; read `README.md` for the
case-by-case self-check.

All content below is invented for this fixture. It contains no real ChatGPT
export material, no real private research, and no real competitor conclusions.
The subject matter (a token-gated membership product called "Freeside") is the
same synthetic frame used in Slice 1, extended with adversarial material.

Four source fragments: `SRC-101`, `SRC-102`, `SRC-103`, `SRC-104`.

---

## SRC-101 — deep-research snippet ("access model")

Freeside's access model is built on token-gated membership: holding a threshold
amount of the project token unlocks the gated member channels. This is the core
access primitive — the rest of the system assumes it.

Gating appears to improve member retention: members who must hold to stay in
tend to stick around longer than they would in an open community.

Membership should not be all-or-nothing. A tiered holder model — holder,
contributor, core — lets the community recognise depth of commitment instead of
a single binary gate.

The gated perks are also the growth engine: members refer others because the
perks behind the gate are worth referring people to.

## SRC-102 — conversation excerpt ("growth thread")

> A: Honestly the fastest way to grow the top of the funnel is a free, open
> membership tier. Let anyone in, then upsell the token gate later. Open access
> maximises sign-ups.
>
> B: Maybe. Also we should run a sizeable token buyback and treasury program to
> support the token price — if the token is strong, membership feels more
> valuable.
>
> A: Either way, gating keeps people engaged. People who are gated in stay
> active longer, that's pretty clear.
>
> B: Sure. And token-gated communities are everywhere now, this isn't exotic —
> half the projects we look at do some version of it.

## SRC-103 — working note ("gating rules")

Membership has to be strictly token-gated. No free tier. If we open a free tier
the access model collapses — the gate is the product, and a free side door
removes the only thing members are paying to be inside.

Open question: should the gating token be a single fungible token, or a
multi-token per-tier arrangement (a different token per holder level)? This
depends on architecture decisions we have not made.

Also unresolved: referral rewards. Do we pay referrers in the project token, or
in non-token points that never touch the token economy? Both have very
different downstream implications and we have not picked one.

## SRC-104 — design / longitudinal note ("dashboard & profiles")

Looking at engagement over several months, retention is consistently higher when
access is gated than in the open periods we trialled. The gate correlates with
people staying.

The member dashboard should probably default to dark mode with a teal accent —
it reads better in the evening when most members are active.

We could display the wallet holdings of well-known members on their public
profiles — seeing that respected people hold a lot could boost status and make
the gate feel more aspirational.
