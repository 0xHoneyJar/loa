# Adjudication list — pr-77

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H08: anchors


Annotator A:

```json
{
  "anchor_lines": [
    569,
    570,
    571,
    572,
    575,
    576,
    621,
    622,
    623
  ],
  "category": "logic",
  "description": "@types/node is downloaded at the registry's floating `latest` tag rather than a pinned version, and any copy already materialized is reused whatever its version, so type-check diagnostics can change silently or stay stuck on a stale version.",
  "file": "cli/tools/installer/npm_compat.rs",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    569,
    572,
    575,
    576
  ],
  "category": "logic",
  "description": "ensure_types_node downloads whatever @types/node is the registry's latest and reuses any previously materialized copy regardless of version, so type-check results drift with registry releases and stale copies are never refreshed.",
  "file": "cli/tools/installer/npm_compat.rs",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H11

```json
{
  "A": "download_npm_package hardcodes registry.npmjs.org and ignores the project's configured registry (.npmrc / NPM_CONFIG_REGISTRY), so private registries, mirrors and offline setups are bypassed.",
  "B": "download_npm_package hardcodes registry.npmjs.org, ignoring the project's configured registry (.npmrc / NPM_CONFIG_REGISTRY), so private registries, mirrors and offline setups are bypassed."
}
```
