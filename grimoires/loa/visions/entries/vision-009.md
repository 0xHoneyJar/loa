# Vision: Audit-Mode Context Filtering

**ID**: vision-009
**Source**: Bridge review of bridge-20260219-16e623
**PR**: #368
**Date**: 2026-02-19T00:00:00Z
**Status**: Captured
**Tags**: [epistemic-enforcement, security, cheval]

## Insight

Before enabling full epistemic filtering in cheval.py, implement an audit-only mode: `filter_context` runs on every invocation but only logs what would be filtered (to `.run/epistemic-audit.jsonl`) without actually modifying messages. This provides visibility into filtering behavior before enforcement, data for tuning regex patterns, and evidence for which models receive what content.

## Potential

Bridges the enforcement gap between the current "no filtering" state and full epistemic context access control. Audit-mode filtering would validate that `context_access` declarations are correct before Jam reviewers depend on them. Enable via feature flag: `context_filtering: audit`.

## Connection Points

- Bridgebuilder finding: BB-512 from bridge-20260219-16e623
- Bridge: bridge-20260219-16e623, PR #368
- Connects epistemic enforcement gap with Jam geometry roadmap
