# /toggle-gpt-review Command

Toggle GPT cross-model review on or off.

## Usage

```bash
/toggle-gpt-review
```

## Execution

Run the toggle script:

```bash
.claude/scripts/gpt-review-toggle.sh
```

The script handles everything:
- Flips `gpt_review.enabled`: `true` → `false` or `false` → `true`
- Injects/removes GPT review instructions from CLAUDE.md
- Injects/removes review gates from skill files
- Injects/removes review gates from command files
- Reports: `GPT Review: ENABLED` or `GPT Review: DISABLED`

## After Toggling

Restart your Claude session for the injected changes to take effect.
