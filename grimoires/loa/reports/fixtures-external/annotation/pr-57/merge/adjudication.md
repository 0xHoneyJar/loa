# Adjudication list — pr-57

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

12 item(s) disagree.

### H01: group

- group members besides H01: A -, B ['H02', 'H03', 'H05', 'H06', 'H07', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Crate version bump only; no behaviour change.",
  "file": "libs/npm_cache/Cargo.toml",
  "group": null,
  "not_defect_class": "refactor",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    5
  ],
  "category": null,
  "description": "Crate version bump that goes with the public API change to NpmPackumentFormat.",
  "file": "libs/npm_cache/Cargo.toml",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H02: group

- group members besides H02: A ['H03', 'H05', 'H06', 'H07', 'H08', 'H09', 'H12'], B ['H01', 'H03', 'H05', 'H06', 'H07', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds chrono dependency needed by the new modified-date based packument format selection.",
  "file": "libs/npm_cache/Cargo.toml",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the chrono dependency that the new modified-date-based packument format selection needs.",
  "file": "libs/npm_cache/Cargo.toml",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H03: anchors, group

- group members besides H03: A ['H02', 'H05', 'H06', 'H07', 'H08', 'H09', 'H12'], B ['H01', 'H02', 'H05', 'H06', 'H07', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [
    78,
    79,
    80,
    81,
    82
  ],
  "category": "logic",
  "description": "Head always fetches the full packument when minimumDependencyAge is set, even for packages whose abbreviated manifest's modified date shows the full packument isn't needed, and does not tie Full to the no-downgrade trust policy (intent partly unclear from the context; reads as a correctness/efficiency fix to format selection).",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    77,
    78,
    79,
    80,
    81,
    82,
    83
  ],
  "category": "logic",
  "description": "Head's packument format model ties the full packument to minimumDependencyAge alone. It always fetches full packuments for every package when minimumDependencyAge is set, even for packages last modified before the cutoff, and does not model the no-downgrade trust policy's need for the full packument. The fix's intent is partly an optimisation, so this reading is somewhat uncertain.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H05: group

- group members besides H05: A ['H02', 'H03', 'H06', 'H07', 'H08', 'H09', 'H12'], B ['H01', 'H02', 'H03', 'H06', 'H07', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the requested packument format to the HTTP client as part of the format-selection fix.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    103
  ],
  "category": null,
  "description": "Adds a packument request format parameter to the HTTP client trait for the new format selection.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H06: group

- group members besides H06: A ['H02', 'H03', 'H05', 'H07', 'H08', 'H09', 'H12'], B ['H01', 'H02', 'H03', 'H05', 'H07', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the unused packument format parameter as part of the format-selection fix.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    330
  ],
  "category": null,
  "description": "Removes the unused packument format parameter from load_package_info as part of the format rework.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H07: group

- group members besides H07: A ['H02', 'H03', 'H05', 'H06', 'H08', 'H09', 'H12'], B ['H01', 'H02', 'H03', 'H05', 'H06', 'H08', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Carries the cached modified date through for the format-selection fix.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    348
  ],
  "category": null,
  "description": "Carries the cached modified date into SerializedCachedPackageInfo so the new format selection can use it.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H08: group

- group members besides H08: A ['H02', 'H03', 'H05', 'H06', 'H07', 'H09', 'H12'], B ['H01', 'H02', 'H03', 'H05', 'H06', 'H07', 'H09', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Signature updated to the new request-format type.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    378
  ],
  "category": null,
  "description": "Updates the parameter type to the new NpmPackumentRequestFormat.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H09: group

- group members besides H09: A ['H02', 'H03', 'H05', 'H06', 'H07', 'H08', 'H12'], B ['H01', 'H02', 'H03', 'H05', 'H06', 'H07', 'H08', 'H12']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Comparison updated to the new request-format type.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    383
  ],
  "category": null,
  "description": "Updates the comparison to the new NpmPackumentRequestFormat type.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H12: group

- group members besides H12: A ['H02', 'H03', 'H05', 'H06', 'H07', 'H08', 'H09'], B ['H01', 'H02', 'H03', 'H05', 'H06', 'H07', 'H08', 'H09']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Keeps the manifest's modified date in the slim cache, needed for the format-selection fix.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    458
  ],
  "category": null,
  "description": "Keeps the manifest's modified date in the slimmed cache so the new format selection can decide when the full packument is needed.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H13: severity


Annotator A:

```json
{
  "anchor_lines": [
    571,
    572,
    573
  ],
  "category": "error-handling",
  "description": "A malformed non-object `scripts` field in any version makes slimming fail with an error, so the entire packument fails to load.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D3",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    571,
    572,
    573
  ],
  "category": "error-handling",
  "description": "A malformed non-object `scripts` field in any version (e.g. an empty string) makes has_install_script return an error, so loading the entire packument fails.",
  "file": "libs/npm_cache/lib.rs",
  "group": "D3",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H25: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1688,
    1689,
    1692,
    1695,
    1699,
    688,
    764,
    959,
    1058
  ],
  "category": "security",
  "description": "Symlink destinations are built from unvalidated package names/aliases, so names like `../x`, absolute paths or `.deno` let an install delete and replace entries outside or inside reserved parts of node_modules.",
  "file": "libs/npm_installer/local.rs",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1688,
    1689,
    1692,
    1693,
    1695,
    1699
  ],
  "category": "security",
  "description": "symlink_package_dir accepts arbitrary destination paths built from untrusted package names or aliases (e.g. `../outside`, absolute paths, `.deno`), so it can delete entries and create symlinks outside node_modules or over reserved directories.",
  "file": "libs/npm_installer/local.rs",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H26: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1689,
    1690,
    1692,
    1695,
    1699
  ],
  "category": "security",
  "description": "symlink_package_dir accepts an arbitrary destination path without validating the package name, enabling path traversal on removal and link creation.",
  "file": "libs/npm_installer/local.rs",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1689,
    1690,
    1692,
    1699
  ],
  "category": "security",
  "description": "symlink_package_dir takes an unvalidated new_path and removes and replaces whatever is there, allowing path traversal through crafted package names or aliases.",
  "file": "libs/npm_installer/local.rs",
  "group": "D4",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H11

```json
{
  "A": "When a registry ignores the Accept header and returns a full packument for an abbreviated request, head does not record the full-packument marker, so the cache entry is misclassified as abbreviated.",
  "B": "Some registries ignore the Accept header and always return the full packument; head does not detect this, so it fails to record the full-packument marker and treats the cache entry as abbreviated."
}
```
