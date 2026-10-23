## Pre-Execution Guardrails (mechanized)

Run only if `.claude/scripts/lib/profile-lib.sh knob guardrails.input.enabled false` prints `true`
and env `LOA_GUARDRAILS_ENABLED` is not `false`: write the prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill {{SKILL}} --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (the script logs) |
| Script missing, non-zero exit, or unparseable output | Continue (fail-open) |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.
