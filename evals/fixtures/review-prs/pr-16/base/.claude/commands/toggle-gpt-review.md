# /toggle-gpt-review Command

> [!WARNING]
> **DEPRECATED as of 2026-04-15** — **non-functional**, scheduled for removal
> **no earlier than 2026-07-15**.
>
> This command references `.claude/scripts/gpt-review-toggle.sh`, which has been
> removed from the repository. Running `/toggle-gpt-review` will produce a
> "script not found" error. The sibling `/gpt-review` command has also been
> marked for deprecation — see `.claude/commands/gpt-review.md` for the full
> rationale and migration path.
>
> **If you rely on `/toggle-gpt-review`**, please run `/feedback` or file an
> issue at https://github.com/0xHoneyJar/loa/issues with the `deprecation` label.

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
