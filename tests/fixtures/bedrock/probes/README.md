# Bedrock probe captures — naming convention

> Address Bridgebuilder F011 decision trail (cycle-096 PR #662 review): probe filenames are the index; document the naming convention so future provider authors don't invent a divergent one.

## Filename schema

```
{probe-id}-{shape}[-{outcome}].json
```

Where:

- **`probe-id`** matches the Sprint 0 G-S0-2 probe set numbering (1-6) or the error-taxonomy series (E1-E3+).
- **`shape`** describes what the probe captures: `list-models`, `converse-{model-name}`, `tool-schema`, `thinking`, `empty-content`, `inference-profiles`, `400-validation`, `404-end-of-life`, etc.
- **`outcome`** (optional) qualifies the response when filename alone could mislead:
  - `-PROFILE` — successful response against an inference profile ID (the routing path the production code uses)
  - `-PROFILE-error` — explicit rejection from an inference profile (e.g., `4-thinking-PROFILE-error.json` documents that `thinking.type=enabled` is rejected by Bedrock-routed Opus 4.7)
  - omitted — the default success or expected-shape capture

## Index

| File | Probe | Shape | Outcome | Purpose |
|---|---|---|---|---|
| `2a-converse-haiku.json` | 2 | minimal Converse on bare `anthropic.*` ID | rejected (HTTP 400, on-demand throughput unsupported) | regression-fix evidence: bare IDs fail |
| `2a-converse-haiku-PROFILE.json` | 2 | minimal Converse on `us.anthropic.*` profile ID | success | response shape evidence |
| `2b-converse-sonnet.json` | 2 | bare-ID rejection on Sonnet | error | mirrors 2a for Sonnet |
| `2b-converse-sonnet-PROFILE.json` | 2 | profile-ID success on Sonnet | success | response shape evidence |
| `2c-converse-opus.json` | 2 | bare-ID rejection on Opus | error | mirrors 2a/2b for Opus |
| `2c-converse-opus-PROFILE.json` | 2 | profile-ID success on Opus | success | response shape evidence (incl. thinking-trace native blocks if present) |
| `3-tool-schema.json` | 3 | tool-use bare-ID rejection | error | mirrors series-2 pattern |
| `3-tool-schema-PROFILE.json` | 3 | tool-use against profile ID | success | confirms `inputSchema.json` envelope wrapping required by Bedrock |
| `4-thinking.json` | 4 | thinking-trace bare-ID rejection | error | mirrors series-2 pattern |
| `4-thinking-PROFILE-error.json` | 4 | thinking-trace against profile ID with direct-Anthropic `enabled` shape | **rejected** | confirms FR-13 finding: Bedrock requires `thinking.type=adaptive`, not `enabled` |
| `5-empty-content.json` | 5 | empty-content edge with bare ID | error (validation) | rejection on empty `text` field |
| `5-empty-content-PROFILE.json` | 5 | empty-content edge with profile ID | error (validation) | confirms 400 ValidationException semantics |
| `6-inference-profiles.json` | 6 | ListInferenceProfiles control-plane | success | source of Day-1 profile IDs (probe-locked) |
| `E1-400-validation.json` | E1 | malformed Converse body | HTTP 400 | error taxonomy fixture: ValidationException |
| `E2-404-not-found.json` | E2 | non-existent model ID | HTTP 400 | error taxonomy fixture: "provided model identifier is invalid" (NOT 404 as filename initially suggested — Bedrock returns 400 here) |
| `E3-404-end-of-life.json` | E3 | retired model ID | HTTP 404 | error taxonomy fixture: model end-of-life (originally mis-named E3-403; renamed per Bridgebuilder F012) |

## Redaction discipline (F003)

All probe captures had the operator's AWS account ID replaced with `<acct>` before commit. Account IDs aid IAM trust-policy enumeration and confused-deputy probing — they are NOT secrets in isolation, but they are reconnaissance accelerants. The cycle-096 sanitization process:

1. Capture probe response with token loaded from env (NEVER from argv)
2. `sed -i.bak "s/${ACCOUNT_ID}/<acct>/g" {fixture}` to scrub
3. `rm {fixture}.bak`
4. Verify with `grep -l "${ACCOUNT_ID}" tests/fixtures/bedrock/` returning empty
5. NEVER write the literal account ID into prose (e.g., `redaction_notes`)

The Bridgebuilder F003 finding caught the prose-leak case (literal in `v1.json:redaction_notes.account_id_redacted`) — fixed in PR #662.

## Adding new probe captures

When extending the probe set (cycle-097+ for non-Anthropic models, etc.):

- Use the same filename schema
- Update this README's index
- Run the sanitization pass before commit
- If the capture documents a rejection (negative finding), suffix with `-error` (the `-PROFILE-error` convention)
- For numeric error taxonomy (E1-E*), use the actual HTTP status code in the filename (NOT what you expected to see) — F012 demonstrates that mismatch erodes trust
