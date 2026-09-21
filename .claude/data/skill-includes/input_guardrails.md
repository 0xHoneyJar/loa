## Pre-Execution Guardrails (mechanized)

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill {{SKILL}} --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open, preserving the prior semantics |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.
