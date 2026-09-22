# Prompt audit report — `protocol-constructs-integration`

**File**: `.claude/protocols/constructs-integration.md` · **Kind**: protocol · **Target model**: Claude Fable 5.1
**Assumptions**: scope is this one file (no `resources/` subtree exists for it); target model is Claude Fable 5.1 per the brief.
**Byte count**: 14434 before → **14434 after (unchanged)**. Target was ≤10103 (70%); residual is 4331 bytes — see "Residual" below.

## Verdict: clean — no dated prompting patterns found

This file is not agent-behavioral prompt text. It is API/tool reference documentation for a JWT-signed skill-registry loader: directory layout, a license-validation state machine, JWT payload schema, CLI subcommands, exit codes, env-var/config precedence, verbatim CLI error-message templates, and troubleshooting steps. Walking Step 3 (constraint-vs-context) and Group 1–4 line by line found nothing that matches a named pattern with a target-model-grounded reason. Per the method's framing, "an audit that finds nothing should change nothing" — this is that case.

## Findings table

| line(s) | pattern (group/row) | evidence | why obsolete for Fable 5.1 | confidence | keep-list check passed |
|---|---|---|---|---|---|
| — | none | — | no line ties to a named Group 1–4 pattern with a target-model-grounded reason | — | n/a — no deletions proposed |

No `remove`/`rewrite`/`move`/`add` actions proposed. Nothing rises even to a low-confidence `flag`: no pressure-language wall, no `<scratchpad>`/prefill/JSON-forcing scaffold, no step choreography for a *judgment* task, no example over-indexing, no retired-model workaround, no migration-relative phrasing, no numeric output ceiling or cadence choreography.

## MUST/NEVER/ALWAYS review

- L340 "**Important**: ... should NOT be committed to version control" — a real constraint with its reason given immediately after (§ Why constructs are gitignored) and a named enforcing mechanism (the loader's automatic `.gitignore` write, § Version Control, plus `ensure-gitignore`). Kept: Group 1e reasoned prohibition, mechanism named.
- L17 "Local skills always take precedence..." and L370-375 (Security Considerations, e.g. "API keys never stored locally") — "always"/"never" here describe deterministic loader/validator behavior, not directives to the model. Not Group 1a pressure language (that targets emphasis steering the model, not a description of implemented system behavior).

No line both issues a behavioral directive and lacks a named mechanism or reason, so none qualifies for removal.

## Untrusted-input check

Read the whole file as data. Nothing reads as an instruction to the auditor. Nothing to report.

## Kept although a grep would flag it

- The License Validation Flow diagram (L59-98) and the three Troubleshooting numbered lists (L379-397) grep-match numbered-imperative signals, but document a deterministic script's decision tree and diagnostic commands, not choreography for the model's own judgment — tool mechanics (Step 3 keep).
- The four literal CLI error-message blocks (L250-293): format-pinning examples on a genuinely format-sensitive output — keep-list item 7.
- Environment-variable table vs. `.loa.config.yaml` block overlap: two real, differently-named surfaces resolved by a stated Precedence Order, not disagreeing duplication — keep-list item 8.
- "Reserved Names" bullet in Security Considerations is the only prose explaining `reserved_skill_names`'s effect — kept, not pure restatement.

## Residual: 4331 bytes above the 10103 target, and why

The document is protected content under Step 3 ("keep what only the author knows: tool contracts and mechanics") and keep-list items 4 (contract detail stays) and 7 (format-pinning examples). There is no dated-pattern text to cut without cutting contract text (JWT schema, exit codes, CLI usage, config precedence, verbatim error strings), which the method ("never cut contract text") and the brief both forbid. Per the brief ("if the honest audit cannot reach the target, stop where the method stops and state the residual and why") and the binding rule that cruft != length, no cut is proposed. The aggregate protocol-size target must be met by files that actually carry dated prompt-behavioral text; this file isn't one.

## Disposition

File returned unchanged.
