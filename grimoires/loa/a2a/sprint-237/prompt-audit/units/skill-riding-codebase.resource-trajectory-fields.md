# Trajectory Log Fields — riding-codebase

Read when logging a phase to `grimoires/loa/a2a/trajectory/riding-{date}.jsonl`, for the exact `action` name and `details` fields that phase uses.

| Phase | Action | Key Details Fields |
|-------|--------|--------------------|
| 0 | `preflight` | `loa_version` |
| 0.5 | `codebase_probe` | `strategy`, `total_files`, `total_lines`, `estimated_tokens` |
| 0.6 | `staleness_check` | `status`, `artifact_age_days` |
| 1 | `claims_generated` | `claim_count`, `output` |
| 2 | `code_extraction` | `routes`, `entities`, `env_vars` |
| 2b | `hygiene_audit` | `items_flagged` |
| 3 | `legacy_inventory` | `docs_found` |
| 4 | `drift_analysis` | `drift_score`, `ghosts`, `shadows`, `stale` |
| 5 | `consistency_analysis` | `score`, `output` |
| 6 | `artifact_generation` | `prd_claims`, `sdd_claims`, `grounded_pct` |
| 6.5 | `reality_generation` | `files`, `total_tokens`, `within_budget` |
| 7 | `governance_audit` | `gaps` |
| 8 | `legacy_deprecation` | `files_marked` |
| 9 | `self_audit` | `quality_score`, `assumptions`, `output` |
| 10 | `handoff` | `total_duration_minutes` |
| 11 | `ground_truth_generation` | `files`, `total_tokens`, `checksums_count`, `within_budget` |
| 12 | `gap_tracker` | `new_gaps`, `total_open`, `highest_id`, `threshold_status` |
| 13 | `decision_archaeology` | `adr_dirs_found`, `adrs_parsed`, `active`, `stale`, `output` |
| 14 | `terminology_extraction` | `terms_extracted`, `domains`, `output` |
