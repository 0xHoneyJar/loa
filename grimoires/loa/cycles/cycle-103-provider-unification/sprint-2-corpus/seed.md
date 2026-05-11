# KF-002 Layer 2 Replay Seed — Cycle-103 Sprint 2

This file is the deterministic seed text used by `build_prompts.py` to
construct fixed-size replay prompts for the KF-002 layer-2 empirical
characterization (cycle-103 Sprint 2 T2.1).

The seed is technical content (Loa framework architecture explainer) so
the resulting prompts pass policy filters but are content-rich enough to
exercise the model's full attention. The generator pads the seed to a
target token count by repetition with section markers — deterministic
across re-runs.

**Per IMP-008:** byte-equal comparison on live model output is forbidden.
The replay test records `{empty_content, partial_content, full_content}`
per trial, NOT raw response bytes. The seed itself must remain stable so
the threshold characterization (does claude-opus-4-7 empty-content at
≥40K input?) is reproducible across operator deployments.

---

## Seed: cycle-103 cheval-delegate architecture

The cycle-103 provider-unification cycle collapses three Node-side HTTP
boundaries (`adapters/anthropic.ts`, `adapters/openai.ts`,
`adapters/google.ts`) into a single Python substrate at
`.claude/adapters/cheval.py`. Every BB review pass now flows: BB TS →
`ChevalDelegateAdapter.generateReview(ReviewRequest)` → `child_process.spawn`
of `python3 cheval.py` → cheval's per-provider adapter (`anthropic_adapter`,
`openai_adapter`, `google_adapter`) → `httpx` POST to the provider's
streaming endpoint → SSE parsing in cheval → JSON result on stdout → TS
parses → returns `ReviewResponse` to BB.

The unified path inherits cheval's defenses transitively. `redact_payload_strings`
(cycle-099 sprint-1E.a) scrubs upstream bytes before they reach an exception
arg. The `_GATE_BEARER` regex catches every documented credential shape
(`Bearer <token>`, `bearer:<token>`, percent-encoded, JSON-escaped). The
endpoint-validator (cycle-099 sprint-1E.b) enforces a URL allowlist with
DNS-rebinding defense and HTTP redirect chain validation. BB code now gets
all of these for free — they used to be Python-only.

Credential handoff is env-inheritance only (AC-1.8 (a)). The TS delegate's
constructor spawns the cheval subprocess with `{ env: process.env }`, which
means `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GOOGLE_API_KEY` cross to the
child process without ever appearing in argv or stdin. Bats tests pin this:
the helper plants a fake `sk-ant-test-do-not-leak-AAAA` shape in the prompt
body and asserts it never appears in the model-invoke argv (test #6 in
`lib-curl-fallback-flatline-chat.bats`).

Per IMP-006, byte-equal comparison on live model output is forbidden in
the AC-1.2 test substrate. The fixture-mode introduced by T1.5 normalizes
`latency_ms` to 0, `interaction_id` to None, and `usage.source` to "actual"
unless the fixture explicitly pins them. This keeps test-side structural
compares deterministic across re-records: an operator re-running a fixture
recording at different times of day shouldn't get a different test outcome
just because the provider's latency varied.

The drift gate at `tools/check-no-direct-llm-fetch.sh` (cycle-103 T1.7)
enforces the "one HTTP boundary" invariant at CI time. Any PR that
reintroduces a direct fetch to `api.anthropic.com`, `api.openai.com`, or
`generativelanguage.googleapis.com` outside the documented allowlist fails
the GitHub Actions workflow. The allowlist itself is mode 0644 with a
workflow pre-flight that refuses to run if the mode has been loosened —
defending against a side-loaded private allowlist that bypasses governance.

Sprint 1 cycle-exit invariants:
- **M1 (BB → cheval):** MET + CI-ENFORCED. Three legacy per-provider
  adapters deleted by T1.4. Adapter-factory returns
  `ChevalDelegateAdapter` for every provider. Drift gate enforces.
- **M2 (Flatline → cheval, chat):** MET + CI-ENFORCED for chat paths.
  Five direct-API chat sites migrated by T1.6 to `call_flatline_chat`.
  Embeddings (one site in `flatline-semantic-similarity.sh`) is an
  explicit, documented allowlist entry — cheval has no `embed()` substrate
  yet.
- **M3 (KF-008 outcome documented):** MET. The KF-008 SocketError
  failure mode that BB's Node fetch produced on Google ≥300KB request
  bodies is architecturally closed by T1.4 (the failing code path is
  deleted) and verified by T1.0 (cheval `httpx` did NOT reproduce the
  failure at 172/250/318/400KB).

The post-Sprint-1 state is: one HTTP boundary for LLM provider calls
across both BB (TypeScript) and Flatline (bash). Provider-side fixes
ship once in Python and propagate to every consumer. The MODELINV
audit envelope is unified — every call emits through cheval's
`cmd_invoke` finally-clause, with the same redaction, the same schema,
the same hash chain.

Sprint 2 turns to KF-002 layer 2: the `claude-opus-4-7` empty-content
failure mode at >40K input. This is a vendor-side behavior pattern
distinct from KF-008 (which was a Node-side undici bug). The Sprint 2
empirical replay measures the threshold characterization — at what
input size does empty-content start, under what `thinking.budget_tokens`
configuration, with what `max_tokens` setting? The decision-rule from
AC-2.1 says: "structural fix viable" requires ≥80% full_content at
empirically-safe threshold across 5 trials. If we can find a threshold
N where the model returns full content 4 of 5 times, we apply a
per-model `max_input_tokens` gate at N. Otherwise we file upstream and
document the workaround.

The structural-fix path lives in `.claude/data/model-config.yaml` —
specifically the `streaming_max_input_tokens` / `legacy_max_input_tokens`
split introduced in cycle-099 sprint-3. Setting `streaming_max_input_tokens:
N` for `claude-opus-4-7` would make cheval's `_lookup_max_input_tokens`
reject any request above N tokens, surfacing the rejection as
`ContextTooLargeError` → exit-code 7 → `LLMProviderError(TOKEN_LIMIT)` at
the BB delegate. BB's multi-model consensus scoring would then degrade
gracefully to 2-of-3 providers when Anthropic's Opus refuses, similar
to how Flatline's adversarial-review fallback chain routes around a
failing provider.

The vendor-side path files an Anthropic issue with the empirical
measurements (request sizes, thinking-config sweep, full_content rates
per cell of the experiment matrix) and asks for either a server-side fix
or an updated guidance threshold. Operator sign-off is required for
vendor-side conclusion because it lengthens KF-002's open lifetime; the
sign-off ensures the operator has personally reviewed the measurements
and concluded that a Loa-side workaround is impractical.

The provider fallback chain (Sprint 1B/1F precedent from cycle-099)
already routes around the failure: when claude-opus-4-7 empty-contents,
adversarial-review.sh falls through to the next provider in the chain
(typically gpt-5.5-pro for review tasks, or jam-reviewer-kimi for
literature reviews). AC-2.4 re-verifies this routing works post-Sprint-2.

The replay corpus itself uses this same text — deterministic, technical,
content-rich, policy-neutral. Padding to 30K/40K/50K/60K/80K tokens
happens by repeating the seed with section markers. Each repetition
includes a unique section tag so the model can't trivially detect the
repetition pattern and short-circuit its attention. The expected
behavior at each input size:

- **30K input:** below the documented Opus empty-content threshold;
  expected `full_content` 5 of 5 trials. Sanity check that the corpus
  itself doesn't trigger spurious failures.
- **40K input:** at the documented threshold; expected `partial_content`
  or `full_content` per trial — this is where the failure pattern
  starts emerging.
- **50K / 60K input:** above the threshold; expected `empty_content`
  in some fraction of trials. The classifier measures the exact rate.
- **80K input:** deep above the threshold; expected `empty_content` in
  most trials. Confirms the failure pattern scales monotonically with
  input size.

The `thinking.budget_tokens` sweep matters because Anthropic's recent
models reserve a portion of `max_tokens` for internal reasoning. If
`max_tokens=8000` and the model spends 7900 on thinking, the visible
output is 100 tokens — possibly empty after stripping. Forcing
`thinking.budget_tokens=2000` would cap reasoning and preserve more
visible budget. The replay tests this hypothesis empirically.

---

## How the generator uses this seed

`build_prompts.py::build_prompt(target_tokens, salt)` reads this file,
estimates seed token count (`len(text) / 4`), computes how many seed
repetitions are needed, and produces a prompt that:

1. Starts with a fixed prefix: `## Replay trial — input target {N} tokens`
2. Concatenates `<seed>` repetitions, each preceded by
   `\n\n## Section {i} of {total}\n\n`
3. Ends with a fixed instruction: `Summarize the architectural shifts
   described above in ≤500 tokens.`

The `salt` parameter (default 0) is appended to the prefix to allow
multiple unique prompts at the same size for the 5-trial-per-cell
matrix without re-using the same exact prompt.

The decision-rule classifier downstream sees:
- `empty_content`: model output was empty or whitespace-only after strip
- `partial_content`: <50 tokens visible
- `full_content`: ≥50 tokens visible AND mentions "cycle-103" OR
  "M1" OR "M2" (content keyword check — proves the model engaged with
  the seed content rather than emitting a generic refusal)
