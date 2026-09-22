# Enrichment Config Defaults & Optional Integrations — riding-codebase

Read when any `--with-*` enrichment flag is set (Phases 12-15 in `SKILL.md`), or when checking the optional QMD reality-context integration during Phase 4 drift analysis.

## Config Defaults

Read enrichment thresholds from `.loa.config.yaml` (used by Phases 12-14):

```bash
# Gap tracker thresholds
GAP_MAX_OPEN=$(yq eval '.ride.enrichment.gaps.max_open // 200' .loa.config.yaml 2>/dev/null || echo "200")
GAP_WARN_AT=$(yq eval '.ride.enrichment.gaps.warn_at // 150' .loa.config.yaml 2>/dev/null || echo "150")

# Decision archaeology thresholds
DECISION_STALE_MONTHS=$(yq eval '.ride.enrichment.decisions.stale_months // 12' .loa.config.yaml 2>/dev/null || echo "12")
DECISION_EXTRA_PATHS=$(yq eval '.ride.enrichment.decisions.extra_paths // []' .loa.config.yaml 2>/dev/null || echo "[]")

# Terminology thresholds
TERM_MAX_TERMS=$(yq eval '.ride.enrichment.terminology.max_terms // 50' .loa.config.yaml 2>/dev/null || echo "50")
```

## QMD Reality Context (Optional)

During drift analysis, if `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false`:

1. Build query from module names being analyzed
2. Run: `.claude/scripts/qmd-context-query.sh --query "<module_names>" --scope reality --budget 2000 --format text`
3. Include output as additional context during drift comparison
4. If script missing, disabled, or returns empty: proceed normally (graceful no-op)
