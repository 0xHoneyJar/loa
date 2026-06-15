# Bedrock forward-routing (`compliance_profile`)

## TL;DR

Set **one** flag and every Anthropic-family voice (opus, sonnet, haiku, …) dispatches
through Amazon Bedrock instead of the direct Anthropic API — on the *initial* call, not
just on fallback:

```yaml
# .loa.config.yaml
hounfour:
  providers:
    bedrock:
      compliance_profile: prefer_bedrock   # or bedrock_only
```

No per-alias editing. No regenerating maps by hand. The equivalence is read from each
Bedrock model's existing `fallback_to` field, so there is **no heuristic name matching**
(SKP-003 compatible).

## The problem this fixes

Before this change, `compliance_profile` only governed **fallback direction** — what
happens *after* a call has already been dispatched to the Bedrock adapter and Bedrock
fails. It did **not** influence the *initial* routing decision.

That left a gap. An alias like `opus → anthropic:claude-opus-4-8` (the shipped default)
resolves to the **direct Anthropic API** at dispatch time. If an operator runs
Bedrock-only (no `ANTHROPIC_API_KEY`, only `AWS_BEARER_TOKEN_BEDROCK`), that call hits
the Anthropic provider with no credentials → `FALLBACK_EXHAUSTED` → an empty
`claude-headless` voice. In a multi-voice Flatline run this silently degrades a 3-voice
consensus to 2 voices with a 2-token stub standing in for the third — and the consensus
envelope can still label it "succeeded" because it lists the *requested* id, not the
*actual* `final_model_id`.

There were two compounding layers:

1. **Python (cheval/loader):** aliases targeting `anthropic:` were dispatched to the
   Anthropic provider regardless of Bedrock posture.
2. **Bash (flatline):** `resolve_provider_id` reads only the codegen'd
   `generated-model-maps.sh` (from `model-config.yaml`), never `.loa.config.yaml`. Even
   an operator who hand-set a `bedrock:` alias override in their config saw flatline's
   bash layer pre-qualify the name to `anthropic:` and hand *that* to cheval — which then
   skipped the bedrock alias (aliases key on bare names, not `provider:`-qualified ones).

## How forward-routing works

When the resolved `providers.bedrock.compliance_profile` is `bedrock_only` or
`prefer_bedrock`, the loader builds an **inverse `fallback_to` table**:

```
us.anthropic.claude-opus-4-8 : fallback_to = anthropic:claude-opus-4-8
                              ⇒  anthropic:claude-opus-4-8  →  bedrock:us.anthropic.claude-opus-4-8
```

Every alias whose target appears on the left is rewritten to the Bedrock model on the
right. Because `prefer_bedrock` already *requires* every Bedrock model to declare
`fallback_to` (enforced by `_enforce_prefer_bedrock_fallback_to`, SKP-003), the
equivalence is operator-asserted, not guessed.

- Under **`prefer_bedrock`**: initial dispatch goes to Bedrock; the original
  `anthropic:<model>` remains the safety net via the Bedrock model's own `fallback_to`.
- Under **`bedrock_only`**: initial dispatch goes to Bedrock; the adapter fails closed on
  Bedrock error (no Anthropic fallback) — unchanged compliance posture.
- Aliases targeting other providers (`openai:`, `google:`) are untouched.
- Aliases already pointing at `bedrock:` are left as-is (idempotent).

The same transform is applied in **both** layers so they agree:

- `loader.py::_apply_bedrock_forward_routing` — the Python/cheval path.
- `gen-adapter-maps.sh::_maybe_apply_bedrock_forward_routing` — the bash codegen path that
  feeds flatline's `resolve_provider_id`.

## Misconfiguration guard

A common field mistake is setting the flag one level too high:

```yaml
hounfour:
  compliance_profile: prefer_bedrock   # ← WRONG: silently ignored
```

The loader reads it at `hounfour.providers.bedrock.compliance_profile`. When the flag is
found at the top level while the correct location is unset, the loader now emits a loud
one-shot WARNING instead of silently ignoring it.

## Operator interim recipe (pre-merge)

Until this ships, a Bedrock operator can get the same effect locally without editing
tracked source, by generating the resolver map from an operator-owned config copy whose
`opus`/`cheap` aliases point at `bedrock:`:

```bash
# 1. operator config = SSOT copy with bedrock-targeted aliases (kept OUTSIDE the repo)
cp .claude/defaults/model-config.yaml ~/operator-model-config.yaml
#    edit aliases: opus: "bedrock:us.anthropic.claude-opus-4-8"  (etc.)

# 2. regenerate the resolver map from it
bash .claude/scripts/gen-adapter-maps.sh --config ~/operator-model-config.yaml

# 3. hide the regenerated artifact from git so it never dirties status or pushes
git update-index --skip-worktree .claude/scripts/generated-model-maps.sh

# verify
bash -c 'source .claude/scripts/lib/model-resolver.sh; echo opus=$(resolve_provider_id opus)'
# expect: opus=bedrock:us.anthropic.claude-opus-4-8
```

This PR makes that recipe unnecessary: with `compliance_profile: prefer_bedrock`, both the
codegen and the loader perform the rewrite automatically.
