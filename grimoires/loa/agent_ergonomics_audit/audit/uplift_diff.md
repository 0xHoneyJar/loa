# Pass 1 uplift — pre vs post (Fable re-score, evidence = live probe transcripts)

Scoring basis: pre = dual-Sonnet median (agent_surfaces.jsonl, target_sha
3a5c4b90); post = Fable lead re-score against the same rubric anchors, from
post-fix probes run in this session (every probe quoted in the commit
messages / session transcript). Only dimensions materially touched by a rec
are re-scored; untouched dims carry over.

| Surface | Dim | Pre | Post | Evidence (post) |
|---|---|---|---|---|
| block-destructive FR-2-AMBIGUOUS msg | error_pedagogy | 90 | 800 | message names accepted forms + protected set + 2 working alternatives; probe sweep: ./.loa/qmd/ allowed, ./.git//./.aws/./.env* still blocked |
| block-destructive FR-2 (rm gate) | intent_inference | 310 | 650 | bounded hidden-dir intent honored; catastrophic set unchanged (16-case matrix) |
| golden-path.sh::script | self_documentation | 110 | 700 | direct exec: usage + function menu + machine-readable alternatives on stderr, exit 2 (was: silent exit 0) |
| golden-path.sh::script | agent_intuitiveness | 125 | 700 | probing agent can no longer mistake no-op for success |
| loa-status.sh::script | intent_inference | ~150 | 750 | --jsno → exit 2 + "Did you mean: --json?" + usage (was: full human output, exit 0) |
| loa-status.sh::script | composability | ~200 | 800 | piped + NO_COLOR probes: 0 escape bytes (was 8 escape lines) |
| loa-status.sh (--triage) | agent_ergonomics | — | +450 | 3 round-trips → 1 call; single-doc envelope pinned by test |
| beads-health.sh::script | error_pedagogy | 375 | 750 | --help now answers (was "Unknown option: --help"); verified exit dictionary; staleness recommendation actually clears the condition |
| beads-health.sh (jsonl_stale) | determinism/composability | 675 | 750 | permanent DEGRADED loop broken: content probe + verified-current marker; live HEALTHY after following its own recommendation |
| semver-bump.sh::script | self_documentation | 625 | 775 | exit dictionary in --help; 'help' word accepted |
| semver-bump.sh::script | intent_inference | 450 | 700 | --from-tga → did-you-mean --from-tag + usage |
| validate-skill-capabilities.sh | error_pedagogy | 560 | 775 | raw '$2: unbound variable' → 'Error: --skill requires a skill name' + usage |
| validate-skill-capabilities.sh | composability | 605 | 750 | color block NO_COLOR+TTY gated |
| memory-query.sh | error_pedagogy | 625 | 800 | zero-output shift-crash → 'Error: --type requires a value' + usage, exit 2 |
| memory-query.sh | intent_inference | 250 | 700 | did-you-mean wired |
| construct-resolve.sh | error_pedagogy | 675 | 750 | --index value guard (fresh-eyes r1); did-you-mean |
| workflow-state.sh (JSON counters) | output_parseability | ~475 | 750 | completed=1/total=1 live (was 100/1, 95%); completed ≤ total invariant tested |
| classify-merge-pr.sh | intent_inference | 450 | 800 | the #1201 incident subject now → cycle; released-* negative pinned |
| (new) loa-capabilities.sh | self_documentation (family) | 0 (absent) | 800 | 21-script contract, drift-gated (gate demonstrably bit during development) |

**Median uplift across touched dimension-surface pairs: ≈ +330 points.**
**Regressions: none** (all changes additive; full unit+script suites green;
9 pre-existing suites for touched files re-run green).

Intent-corpus recheck (the 17 useless_error entries): the 5 probed classes
(bh-*, sb-*, vsc-*, cr-5, mq-4) now produce useful_hint-grade output —
verified by the agent-ergonomics-unknown-flag.bats fixtures which encode one
representative per script.

---

## FIX-FORWARD 2026-07-12 — R-002 security regression reversed (independent audit)

The independent security audit (dispatched after operator asked "reviewed &
audited?") **found R-002 shipped a security regression**: the "allow bounded
hidden subdirs" behavior used a *denylist* of sensitive names, which leaked —
`rm -rf ./.netrc / ./.npmrc / ./.pypirc / ./.git-credentials / ./.authinfo /
./.password-store / ./.aws-old / ./.ssh-backup` were all NEWLY ALLOWED vs the
pre-R-002 hook (verified by a 22-case pre-vs-post matrix). Classic
denylist-whack-a-mole (bug #898); my own R-002 regression tests green-lit the
vulnerability because they encoded my flawed intent, not an adversarial model.

**Reversal**: `_re_allow_exclude` / `_re_allow_list` restored to pre-R-002
bytes (block ALL `./.hidden` paths — an allowlist that fails SAFE). The S-1
defect (message recommended a non-working form) is fixed in the FR-2 MESSAGES
alone: they now name `trash` + `find <path> -mindepth 1 -delete` (works on
hidden dirs), never a bogus accepted form. Net R-002 effect on the rm-gate:
**message-only**, zero new deletion surface — verified byte-identical to the
safe pre-R-002 baseline across the 22-case matrix. error_pedagogy uplift
(90→~700) STANDS; the intent_inference "allow hidden dirs" uplift is
WITHDRAWN. Fixtures flipped to pin the safe behavior + 7 adversarial
credential-dir cases added.

**Lesson (durable)**: an independent adversarial audit caught what 5 author
fresh-eyes rounds + author-written tests did not — the author's tests can only
be as adversarial as the author's threat model. This is why the review/audit
gate must be independent.
