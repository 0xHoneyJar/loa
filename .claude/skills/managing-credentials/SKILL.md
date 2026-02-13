---
parallel_threshold: 1000
timeout_minutes: 10
zones:
  system:
    path: .claude
    permission: none
  state:
    paths: [grimoires/loa]
    permission: read
  app:
    paths: [src, lib, app]
    permission: none
---

# /loa-credentials — Credential Management

## Overview

Manage API credentials for Loa's multi-model provider system. Three storage tiers:

1. **Environment variables** — highest priority, standard approach
2. **Encrypted store** — `~/.loa/credentials/store.json.enc` (Fernet/AES-128)
3. **.env.local** — project-level dotenv file (gitignored)

## Subcommands

### status (default)

Show credential status for all known providers.

**Workflow**:
1. Run: `python3 -c "from loa_cheval.credentials import get_credential_provider; from loa_cheval.credentials.health import HEALTH_CHECKS; p = get_credential_provider('.'); [print(f'{k}: {\"configured\" if p.get(k) else \"missing\"}') for k in HEALTH_CHECKS]"`
2. Format results as a table:
   ```
   Credential Status
   ─────────────────────────────────
   OPENAI_API_KEY      configured  (env)
   ANTHROPIC_API_KEY   missing
   MOONSHOT_API_KEY    configured  (.env.local)
   ```
3. If any credentials are missing, suggest: `Run /loa-credentials set <NAME> to configure`

### set <CREDENTIAL_ID>

Store a credential in the encrypted store.

**Workflow**:
1. Validate the credential ID is in the known list or matches the allowlist pattern
2. **CRITICAL**: Use `AskUserQuestion` to prompt for the value — NEVER accept credentials as command arguments
3. Run: `python3 -c "from loa_cheval.credentials.store import EncryptedStore; s = EncryptedStore(); s.set('CREDENTIAL_ID', 'VALUE')"`
4. Confirm: "Stored CREDENTIAL_ID in encrypted store (~/.loa/credentials/)"
5. Optionally offer to test the credential

**Security Rules**:
- NEVER echo, print, or log the credential value
- NEVER include the credential value in tool call descriptions
- NEVER store credentials in .claude/ or grimoires/
- The value MUST come from user input via AskUserQuestion, never from command args

### test

Test all configured credentials against provider endpoints.

**Workflow**:
1. Run: `python3 -c "from loa_cheval.credentials import get_credential_provider; from loa_cheval.credentials.health import check_all; results = check_all(get_credential_provider('.')); [print(f'{r.credential_id}: {r.status} — {r.message}') for r in results]"`
2. Format results:
   ```
   Credential Health
   ─────────────────────────────────
   OPENAI_API_KEY      ok     — OpenAI API: valid (HTTP 200)
   ANTHROPIC_API_KEY   error  — Anthropic API: invalid key (HTTP 401)
   MOONSHOT_API_KEY    missing — MOONSHOT_API_KEY not configured
   ```

### delete <CREDENTIAL_ID>

Remove a credential from the encrypted store.

**Workflow**:
1. Confirm with user before deletion
2. Run: `python3 -c "from loa_cheval.credentials.store import EncryptedStore; s = EncryptedStore(); print('deleted' if s.delete('CREDENTIAL_ID') else 'not found')"`

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "cryptography package required" | Missing dependency | `pip install cryptography` |
| "No credentials configured" | Empty store + no env vars | Run `/loa-credentials set` |
| "Health check timeout" | Network issue | Check connectivity |

## Integration

Credentials stored via this command are automatically discovered by:
- Config interpolation (`{env:VAR}` tokens in `.loa.config.yaml`)
- LazyValue resolution (provider auth fields)
- All skills that use model-invoke

The credential chain is: env var → encrypted store → .env.local
Environment variables always take priority.
