# Adjudication list — pr-15

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

99 item(s) disagree.

### H04: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1693,
    1694,
    1695,
    1696
  ],
  "category": "logic",
  "description": "Head has no planner for agy hops: with hounfour.headless.agy_opt_in off, a gated gemini-headless hop inside a mixed fallback chain stays in models_requested and is dispatched/walked as a failed hop instead of being planned around (the hunk also adds the CLI-aware calibrate hint used by D2).",
  "file": ".claude/adapters/cheval.py",
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
    356,
    1693,
    1694,
    1696
  ],
  "category": "logic",
  "description": "Head has no planner that drops agy hops from a mixed chain while hounfour.headless.agy_opt_in is off, so gated agy hops are dispatched/walked and counted in models_requested as failed voices (the hunk also adds the CLI-aware calibration hint helper).",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H11: group, category

- group members besides H11: A ['H20', 'H43', 'H44', 'H96', 'H97'], B ['H20', 'H96', 'H97']

Annotator A:

```json
{
  "anchor_lines": [
    1228,
    1229
  ],
  "category": "logic",
  "description": "A single-entry chain refused by the agy opt-in is reported with verdict reason 'Other' instead of a distinct OptInRequired reason.",
  "file": ".claude/adapters/cheval.py",
  "group": "D9",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1228,
    1229
  ],
  "category": "contract",
  "description": "A single-hop chain refused by the agy opt-in gets verdict-quality reason 'Other' instead of a distinct opt-in reason.",
  "file": ".claude/adapters/cheval.py",
  "group": "D8",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H12: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1693,
    1694,
    1695,
    1696
  ],
  "category": "logic",
  "description": "models_requested is taken from the full resolved chain without first planning around agy hops gated off by the opt-in, so gated hops are dispatched and counted.",
  "file": ".claude/adapters/cheval.py",
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
    1693,
    1694,
    1696
  ],
  "category": "logic",
  "description": "models_requested is taken from the full resolved chain before any agy planning, so gated agy hops are recorded as requested and walked.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H14: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes models_not_planned to the exit-7 MODELINV emit.",
  "file": ".claude/adapters/cheval.py",
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
    2070
  ],
  "category": "contract",
  "description": "The exit-7 MODELINV envelope omits the hops that were not planned.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H20: group, category

- group members besides H20: A ['H11', 'H43', 'H44', 'H96', 'H97'], B ['H11', 'H96', 'H97']

Annotator A:

```json
{
  "anchor_lines": [
    2546,
    2547,
    2548,
    2549,
    2550,
    2551,
    2552
  ],
  "category": "error-handling",
  "description": "An agy-alone chain refused by the opt-in is recorded with error_class UNKNOWN and no failure_class, and the error JSON drops the failure_class, so consumers cannot tell it from a real failure.",
  "file": ".claude/adapters/cheval.py",
  "group": "D9",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    2546,
    2547,
    2548,
    2549,
    2550,
    2551,
    2552
  ],
  "category": "contract",
  "description": "An agy opt-in refusal (ChevalError with failure_class opt_in_required) is recorded as error_class UNKNOWN with no failure_class, and the error JSON drops the class.",
  "file": ".claude/adapters/cheval.py",
  "group": "D8",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H22: anchors


Annotator A:

```json
{
  "anchor_lines": [
    2838,
    2839,
    2840,
    2841,
    2842,
    2843
  ],
  "category": "error-handling",
  "description": "Inline effort_effective derivation inside the emit call can raise and lose the envelope (fix also passes models_not_planned).",
  "file": ".claude/adapters/cheval.py",
  "group": "D8",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    2834,
    2835,
    2836,
    2837,
    2838,
    2839,
    2840,
    2841,
    2842,
    2843
  ],
  "category": "error-handling",
  "description": "The final emit derives effort_effective inline (an exception loses the envelope) and omits models_not_planned.",
  "file": ".claude/adapters/cheval.py",
  "group": "D7",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H27: group

- group members besides H27: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H28', 'H29', 'H30'], B ['H28', 'H29', 'H30']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Imports stat for the regular-file check in the hardened opt-in reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
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
  "description": "Imports stat for the strict opt-in reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H28: group

- group members besides H28: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H29', 'H30'], B ['H27', 'H29', 'H30']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "_HAS_YAML flag for the strict opt-in reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
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
  "description": "Records PyYAML availability for the strict opt-in reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H29: group

- group members besides H29: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H30'], B ['H27', 'H28', 'H30']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "_HAS_YAML flag (fallback branch) for the strict opt-in reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
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
  "description": "Records PyYAML absence for the yq fallback reader.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H30: anchors, group

- group members besides H30: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29'], B ['H27', 'H28', 'H29']

Annotator A:

```json
{
  "anchor_lines": [
    113,
    116,
    117,
    120,
    122,
    125,
    126
  ],
  "category": "security",
  "description": "agy_opt_in_enabled lets the framework System defaults satisfy the operator opt-in, reads the config from whatever cwd-ancestor root the walk finds (a planted .loa.config.yaml can opt in), accepts PyYAML 1.1 truthy spellings (yes/on/True) and never checks that the config is writable only by the current user, so the argv-exposing agy route can be enabled without the operator's decision.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    113,
    116,
    120,
    121,
    122,
    125,
    126
  ],
  "category": "security",
  "description": "agy_opt_in_enabled lets framework System defaults satisfy the operator-only opt-in, accepts PyYAML YAML-1.1 truthy spellings (yes/on/True), runs the root walk outside the fail-closed try, and honours a cwd-ancestor or others-writable config, so the argv-exposing agy route can be enabled without an explicit operator `true`.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D10",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H32: group

- group members besides H32: A ['H36', 'H40', 'H41'], B ['H36', 'H40']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Imports ProviderContextLimitError for the size-rejection classification.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    72
  ],
  "category": null,
  "description": "Imports ProviderContextLimitError for the size-rejection classification fix.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H33: severity


Annotator A:

```json
{
  "anchor_lines": [
    131,
    145
  ],
  "category": "input-validation",
  "description": "build_headless_argv accepts a prompt and places it right after -p before the options, so a prompt starting with '-' is parsed by the CLI as a flag.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    131,
    145
  ],
  "category": "input-validation",
  "description": "build_headless_argv accepts a prompt and puts it right after -p, where the CLI parses options, so a prompt starting with '-' is read as a flag.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H35: severity


Annotator A:

```json
{
  "anchor_lines": [
    145
  ],
  "category": "input-validation",
  "description": "The argv prompt is inserted in option position (before --output-format etc.), where a leading '-' is parsed as an option.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    145
  ],
  "category": "input-validation",
  "description": "The argv prompt sits in option position, before the option terminator.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H36: group

- group members besides H36: A ['H32', 'H40', 'H41'], B ['H32', 'H40']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Static-auth marker list used by the new error classification.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    162
  ],
  "category": null,
  "description": "Adds the static-auth marker list used by the reclassified error handler.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H39: verdict


Annotator A:

```json
{
  "anchor_lines": [
    341,
    342
  ],
  "category": "input-validation",
  "description": "No option terminator: an argv prompt is never placed after '--', so a prompt beginning with '-' can be read as a CLI flag.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    341
  ],
  "category": null,
  "description": "An argv prompt now goes last, after '--'.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H40: group

- group members besides H40: A ['H32', 'H36', 'H41'], B ['H32', 'H36']

Annotator A:

```json
{
  "anchor_lines": [
    543,
    544,
    545,
    546,
    547,
    548,
    549,
    550,
    551,
    552,
    553
  ],
  "category": "error-handling",
  "description": "The CLI's own 'Prompt is too long' size rejection is not mapped to a context-limit error, and bare '429'/'529' substrings (e.g. digits inside a stated token count) classify it as a retryable rate limit that walks the chain and counts against breakers; a 'please wait' auth message is also treated as a throttle.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    543,
    544,
    545,
    546,
    547,
    548,
    549,
    550,
    551,
    552,
    553
  ],
  "category": "error-handling",
  "description": "_raise_for_error treats any '429'/'529' substring (including digits in a token count) as a rate limit and has no context-limit branch, so the CLI's 'Prompt is too long' size rejection is walked as a provider failure or retried as a throttle.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D13",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H41: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds 'invalid api key' to the static-auth markers, matching the new marker list.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D12",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    575,
    576,
    577,
    578,
    579,
    580,
    581,
    582
  ],
  "category": "error-handling",
  "description": "An 'invalid API key' diagnostic is not recognised as a static auth failure and falls through to a walkable ProviderUnavailableError.",
  "file": ".claude/adapters/loa_cheval/providers/claude_headless_adapter.py",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H43: group

- group members besides H43: A ['H11', 'H20', 'H44', 'H96', 'H97'], B -

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "ConfigError accepts a context so the opt-in failure_class flows through the base constructor.",
  "file": ".claude/adapters/loa_cheval/types.py",
  "group": "D9",
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
  "description": "ConfigError forwards an optional context to the base constructor.",
  "file": ".claude/adapters/loa_cheval/types.py",
  "group": null,
  "not_defect_class": "refactor",
  "severity": null,
  "verdict": "not-defect"
}
```

### H44: group

- group members besides H44: A ['H11', 'H20', 'H43', 'H96', 'H97'], B -

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "AgyOptInRequiredError passes its failure_class context through the base constructor so cheval can read it; intent beyond the D9 fix is unclear from the context.",
  "file": ".claude/adapters/loa_cheval/types.py",
  "group": "D9",
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
  "description": "Passes context through the base constructor instead of assigning it afterwards; the attribute value looks the same either way, so the behavioural intent is unclear from the shown text and this is treated as a refactor.",
  "file": ".claude/adapters/loa_cheval/types.py",
  "group": null,
  "not_defect_class": "refactor",
  "severity": null,
  "verdict": "not-defect"
}
```

### H91: anchors, group

- group members besides H91: A ['H92', 'H93', 'H94'], B ['H202', 'H211', 'H212', 'H92', 'H93', 'H94']

Annotator A:

```json
{
  "anchor_lines": [
    282,
    283
  ],
  "category": "input-validation",
  "description": "Free-text ceiling_calibration strings (reprobe_trigger, cli_version, cli_model) have no length bound in the schema.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    287
  ],
  "category": "input-validation",
  "description": "The provenance string fields of ceiling_calibration have no length bound, so arbitrary-length probe text validates.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D15",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H92: anchors, group

- group members besides H92: A ['H91', 'H93', 'H94'], B ['H202', 'H211', 'H212', 'H91', 'H93', 'H94']

Annotator A:

```json
{
  "anchor_lines": [
    290,
    291,
    292
  ],
  "category": "input-validation",
  "description": "Unbounded ceiling_calibration string field in the schema.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    292
  ],
  "category": "input-validation",
  "description": "transport string unbounded in the schema.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D15",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H93: anchors, group

- group members besides H93: A ['H91', 'H92', 'H94'], B ['H202', 'H211', 'H212', 'H91', 'H92', 'H94']

Annotator A:

```json
{
  "anchor_lines": [
    295,
    296
  ],
  "category": "input-validation",
  "description": "cli_version has no length bound.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    296
  ],
  "category": "input-validation",
  "description": "cli_version string unbounded in the schema.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D15",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H94: anchors, group

- group members besides H94: A ['H91', 'H92', 'H93'], B ['H202', 'H211', 'H212', 'H91', 'H92', 'H93']

Annotator A:

```json
{
  "anchor_lines": [
    299,
    300
  ],
  "category": "input-validation",
  "description": "cli_model has no length bound.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D14",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    300
  ],
  "category": "input-validation",
  "description": "cli_model string unbounded in the schema.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D15",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H95: group

- group members besides H95: A ['H100', 'H101', 'H102', 'H208', 'H209', 'H210', 'H211', 'H217'], B ['H100', 'H101', 'H102', 'H208', 'H209', 'H210']

Annotator A:

```json
{
  "anchor_lines": [
    306,
    307
  ],
  "category": "contract",
  "description": "The schema neither records nor requires a probe outcome for a probed_headless bound, so a partial (budget-capped) probe is indistinguishable from a clean one in the catalog.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    306,
    307
  ],
  "category": "contract",
  "description": "A probed_headless calibration validates without its transport or probe outcome, so a partial probe's bound is indistinguishable from a clean one.",
  "file": ".claude/data/schemas/model-config-v3.schema.json",
  "group": "D16",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H96: group

- group members besides H96: A ['H11', 'H20', 'H43', 'H44', 'H97'], B ['H11', 'H20', 'H97']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema admits the new models_failed[].failure_class field.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    64
  ],
  "category": null,
  "description": "Schema admits failure_class on models_failed entries for the opt-in classification fix.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H97: group

- group members besides H97: A ['H11', 'H20', 'H43', 'H44', 'H96'], B ['H11', 'H20', 'H96']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema admits the new OptInRequired reason.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D9",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    510
  ],
  "category": null,
  "description": "Schema admits the OptInRequired reason.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H100: group

- group members besides H100: A ['H101', 'H102', 'H208', 'H209', 'H210', 'H211', 'H217', 'H95'], B ['H101', 'H102', 'H208', 'H209', 'H210', 'H95']

Annotator A:

```json
{
  "anchor_lines": [
    506
  ],
  "category": "logic",
  "description": "The probed Opus 5.5 entry records sample_size: null although a probe with samples informed the bound.",
  "file": ".claude/defaults/model-config.yaml",
  "group": "D31",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    506
  ],
  "category": "logic",
  "description": "The catalog records sample_size: null for a bound that five probe samples informed.",
  "file": ".claude/defaults/model-config.yaml",
  "group": "D16",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H101: anchors, group, severity, category

- group members besides H101: A ['H100', 'H102', 'H208', 'H209', 'H210', 'H211', 'H217', 'H95'], B ['H100', 'H102', 'H208', 'H209', 'H210', 'H95']

Annotator A:

```json
{
  "anchor_lines": [
    503,
    513
  ],
  "category": "contract",
  "description": "The catalog entry written from a partial probe does not say the outcome was partial.",
  "file": ".claude/defaults/model-config.yaml",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    509,
    513
  ],
  "category": "logic",
  "description": "The operator_set entry from a partial probe does not record probe_outcome: partial.",
  "file": ".claude/defaults/model-config.yaml",
  "group": "D16",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H102: group

- group members besides H102: A ['H100', 'H101', 'H208', 'H209', 'H210', 'H211', 'H217', 'H95'], B ['H100', 'H101', 'H208', 'H209', 'H210', 'H95']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Checksum refreshed for the catalog edit.",
  "file": ".claude/defaults/model-config.yaml.checksum",
  "group": "D31",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1
  ],
  "category": null,
  "description": "Checksum refreshed for the catalog edits.",
  "file": ".claude/defaults/model-config.yaml.checksum",
  "group": "D16",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H104: anchors


Annotator A:

```json
{
  "anchor_lines": [
    2350,
    2351,
    2352,
    2353,
    2354,
    2356,
    2360
  ],
  "category": "logic",
  "description": "The companion planner only drops a hop whose canonical name is exactly gemini-headless, missing agy-routed hops (provider-prefixed forms, Google models under cli-only, project aliases), and its own yq reader differs from the shared strict opt-in rule.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    2350,
    2351,
    2352,
    2353,
    2354,
    2355,
    2356,
    2357,
    2358,
    2359,
    2360
  ],
  "category": "logic",
  "description": "The companion planner recognises an agy hop only by the exact canonical name gemini-headless (not provider-prefixed forms, aliases, or a Google model under cli-only), so agy-routed companion hops are planned while the opt-in is off.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H105: anchors, group

- group members besides H105: A ['H108', 'H113'], B ['H108', 'H113', 'H128', 'H131', 'H137', 'H161']

Annotator A:

```json
{
  "anchor_lines": [
    4080,
    4081
  ],
  "category": "other",
  "description": "The dissent planner never emits the once-per-run gate warning when the agy route is available but gated.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    4081
  ],
  "category": "other",
  "description": "No once-per-run WARN when the agy route is available but gated or the opt-in is mis-typed.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H107: anchors


Annotator A:

```json
{
  "anchor_lines": [
    522,
    523,
    524,
    525,
    526,
    529,
    532,
    533,
    534,
    535,
    536
  ],
  "category": "logic",
  "description": "Flatline's tertiary agy predicate uses its own name/gemini* heuristic (no catalog aliases such as deep-research-pro) and a separate yq reader instead of the shared rule, so agy-routed tertiaries can be misjudged.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    522,
    523,
    524,
    525,
    526,
    529,
    530,
    531,
    532,
    533,
    534,
    535,
    536
  ],
  "category": "logic",
  "description": "Flatline's local agy predicate only knows gemini*-named Google models and ignores catalog/project aliases, diverging from cheval's routing, so a gated agy tertiary may be planned.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H108: group

- group members besides H108: A ['H105', 'H113'], B ['H105', 'H113', 'H128', 'H131', 'H137', 'H161']

Annotator A:

```json
{
  "anchor_lines": [
    2456
  ],
  "category": "other",
  "description": "Flatline never emits the once-per-run agy gate warning.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    2456
  ],
  "category": "other",
  "description": "No once-per-run agy gate WARN in Flatline.",
  "file": ".claude/scripts/flatline-orchestrator.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H110: anchors


Annotator A:

```json
{
  "anchor_lines": [
    798,
    799,
    800,
    801,
    802,
    805,
    806
  ],
  "category": "logic",
  "description": "/loa status uses its own opt-in reader and a provider=='google' heuristic rather than the shared agy route predicate, so its gate note can disagree with cheval.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    798,
    799,
    800,
    801,
    802,
    803,
    804,
    805,
    806
  ],
  "category": "logic",
  "description": "/loa status uses its own opt-in reader and a provider==google rule instead of the shared predicate, so its hop note can disagree with what cheval routes.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H111: anchors


Annotator A:

```json
{
  "anchor_lines": [
    811
  ],
  "category": "logic",
  "description": "The CLI hop gating keys on the binary name agy rather than the shared routes_to_agy predicate.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    811,
    812
  ],
  "category": "logic",
  "description": "The hop gating checks only the bin name agy instead of the shared routes_to_agy predicate.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H112: anchors


Annotator A:

```json
{
  "anchor_lines": [
    822,
    826,
    827,
    828,
    831,
    832,
    833,
    838,
    842
  ],
  "category": "logic",
  "description": "The ceiling line splices the alias-derived model id into yq expression text, accepts observations outside the plausible window, ignores a foreign-transport calibration that an observation should tighten, and prints an unquoted calibrate command.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D19",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    822,
    826,
    827,
    828,
    831,
    832,
    833,
    838,
    839,
    840,
    842
  ],
  "category": "logic",
  "description": "The status ceiling line splices the model id into yq expressions, reports a foreign-transport calibration as authoritative even when a lower observation exists, accepts observations outside the context window, and emits an unquoted calibrate command.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D19",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H113: group

- group members besides H113: A ['H105', 'H108'], B ['H105', 'H108', 'H128', 'H131', 'H137', 'H161']

Annotator A:

```json
{
  "anchor_lines": [
    860
  ],
  "category": "other",
  "description": "The Providers section never emits the agy gate warning.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    860
  ],
  "category": "other",
  "description": "No agy gate WARN in the human Providers section.",
  "file": ".claude/scripts/loa-status.sh",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H120: anchors


Annotator A:

```json
{
  "anchor_lines": [
    188,
    189,
    190,
    191,
    192
  ],
  "category": "logic",
  "description": "P3 gates only hops whose CLI is agy, so a Google model under cli-only (routed through agy) is counted usable on its Google credential with the opt-in off, and when opted in its usability is judged by the credential instead of the agy binary.",
  "file": ".claude/scripts/run-preflight.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    186,
    187,
    188,
    189,
    190
  ],
  "category": "logic",
  "description": "P3 gates only hops whose cli is agy, so a Google model under cli-only counts as usable on its API credential and, when opted in, its usability is judged on the credential instead of the agy binary.",
  "file": ".claude/scripts/run-preflight.sh",
  "group": "D17",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H123: group

- group members besides H123: A ['H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated build manifest.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D10",
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
  "description": "Build manifest regenerated for the rebuilt dist.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H124: group

- group members besides H124: A ['H123', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Manifest hash of config.ts after the fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D10",
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
  "description": "Manifest hash refreshed for config.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H125: group

- group members besides H125: A ['H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H126', 'H136', 'H142', 'H143', 'H145', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Manifest hash of multi-model-pipeline.ts after the fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D22",
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
  "description": "Manifest hash refreshed for multi-model-pipeline.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H126: group

- group members besides H126: A ['H125', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H136', 'H142', 'H143', 'H145', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Manifest hash refresh (review-verdict.ts); mechanical rebuild.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D22",
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
  "description": "Manifest hash refreshed.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H127: group

- group members besides H127: A ['H149', 'H150', 'H170'], B ['H149', 'H150', 'H169', 'H170']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Manifest hash of truncation.generated.ts after the fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D24",
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
  "description": "Manifest hash refreshed for truncation.generated.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D24",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H128: group

- group members besides H128: A ['H125', 'H126', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H105', 'H108', 'H113', 'H131', 'H137', 'H161']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Manifest hash of main.ts after the fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D22",
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
  "description": "Manifest hash refreshed for main.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D18",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H129: group

- group members besides H129: A ['H123', 'H124', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declarations mirroring the config.ts opt-in reader fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79
  ],
  "category": null,
  "description": "Declaration copy of the readAgyGate fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H130: group

- group members besides H130: A ['H125', 'H126', 'H128', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration: gate parameter now required.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    86
  ],
  "category": null,
  "description": "Declaration copy: gate argument required.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H131: group

- group members besides H131: A ['H125', 'H126', 'H128', 'H130', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H105', 'H108', 'H113', 'H128', 'H137', 'H161']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration of agyGateStartupLines.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    100
  ],
  "category": null,
  "description": "Declaration of agyGateStartupLines.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D18",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H132: group

- group members besides H132: A ['H123', 'H124', 'H129', 'H133', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts.map",
  "group": "D10",
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
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts.map",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H133: group

- group members besides H133: A ['H123', 'H124', 'H129', 'H132', 'H134', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled imports for the reader fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    3
  ],
  "category": null,
  "description": "Built copy of the source import change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H134: group

- group members besides H134: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H138', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the readAgyGate fix in config.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    122,
    147
  ],
  "category": null,
  "description": "Built copy of the readAgyGate / isAgyRouted fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H135: group

- group members besides H135: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy: no cwd default gate.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    154
  ],
  "category": null,
  "description": "Built copy: validateApiKeys no longer defaults the gate to the cwd config.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H136: group

- group members besides H136: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H142', 'H143', 'H145', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the read-error gating fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    159
  ],
  "category": null,
  "description": "Built copy of the read-error gating fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H137: group

- group members besides H137: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H105', 'H108', 'H113', 'H128', 'H131', 'H161']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled agyGateStartupLines.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    178
  ],
  "category": null,
  "description": "Built copy of agyGateStartupLines.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D18",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H138: group

- group members besides H138: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H156', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H141', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js.map",
  "group": "D10",
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
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js.map",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H141: group

- group members besides H141: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H156', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled import update.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    13
  ],
  "category": null,
  "description": "Built copy of the import change.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H142: group

- group members besides H142: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H143', 'H145', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the pipeline read-error handling fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    97,
    98,
    99
  ],
  "category": null,
  "description": "Built copy of the read-error / strict-mode handling fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H143: group

- group members besides H143: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H145', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the no-models message fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    127
  ],
  "category": null,
  "description": "Built copy of the no-models message fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H145: group

- group members besides H145: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H148', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the quorum fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    288,
    289
  ],
  "category": null,
  "description": "Built copy of the merge-block-on-read-error fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H148: group

- group members besides H148: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H145', 'H160', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map",
  "group": "D22",
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
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H149: group

- group members besides H149: A ['H127', 'H150', 'H170'], B ['H127', 'H150', 'H169', 'H170']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled generated header comment.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/truncation.generated.js",
  "group": "D24",
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
  "description": "Built copy of the units comment.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/truncation.generated.js",
  "group": "D24",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H150: group

- group members besides H150: A ['H127', 'H149', 'H170'], B ['H127', 'H149', 'H169', 'H170']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the corrected Opus 5.5 budget.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/truncation.generated.js",
  "group": "D24",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    31
  ],
  "category": null,
  "description": "Built copy of the corrected opus-5-5 budget.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/truncation.generated.js",
  "group": "D24",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H156: group

- group members besides H156: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H157', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H157', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "fs/path imports for the hardened reader.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    3
  ],
  "category": null,
  "description": "fs/path imports for the fd-based strict reader.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H157: group

- group members besides H157: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H158', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H158', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the trust/permission helpers and gate fields used by the readAgyGate fix.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D10",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    151
  ],
  "category": null,
  "description": "Adds the readError/typeWarning fields, the config-path helper and the permission-rule helpers used by the readAgyGate fix.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H158: anchors, group

- group members besides H158: A ['H123', 'H124', 'H129', 'H132', 'H133', 'H134', 'H138', 'H156', 'H157', 'H27', 'H28', 'H29', 'H30'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H159', 'H162']

Annotator A:

```json
{
  "anchor_lines": [
    159,
    163,
    164,
    165,
    166,
    167,
    171,
    173,
    174,
    175,
    180,
    181,
    182
  ],
  "category": "security",
  "description": "Bridgebuilder's readAgyGate defaults to the cwd config, never checks the config's owner/permissions, reads through aliases/merge keys without warning, swallows every read error silently as opt-in off, and isAgyRouted only matches the literal gemini-headless id.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D10",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    159,
    163,
    166,
    171,
    173,
    174,
    175,
    176,
    182
  ],
  "category": "security",
  "description": "Bridgebuilder's readAgyGate opts in from a config others can write, reads through aliases/merge keys, swallows read errors silently as 'off' without a reason, and isAgyRouted only knows the literal gemini-headless id.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D21",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H159: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Removes the cwd default gate parameter so callers pass the repo config.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    190
  ],
  "category": "logic",
  "description": "validateApiKeys defaults the gate to readAgyGate() of the cwd's .loa.config.yaml, not the repo root's, so callers can judge voices against the wrong config.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D21",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H160: group

- group members besides H160: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H161', 'H162', 'H163', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H145', 'H148', 'H163', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [
    200
  ],
  "category": "error-handling",
  "description": "When the Loa config cannot be read, Google voices are still planned as HTTP voices although cheval may route them to agy and refuse them, so the failure is miscounted.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    200
  ],
  "category": "error-handling",
  "description": "When the Loa config is unreadable the mode is unknown but Google voices are still planned as HTTP, though cheval may route them to agy and refuse them.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H161: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds startup lines for the read error / type warning.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    220
  ],
  "category": "other",
  "description": "Bridgebuilder has no startup line for the gate's read error or type warning, so an unreadable or mis-typed opt-in is never said.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D18",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H162: group

- group members besides H162: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H163', 'H164', 'H166'], B ['H123', 'H124', 'H129', 'H130', 'H132', 'H133', 'H134', 'H135', 'H138', 'H141', 'H156', 'H157', 'H158', 'H159']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Import update.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    26
  ],
  "category": null,
  "description": "Imports the shared config-path helper.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D21",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H163: group

- group members besides H163: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H164', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H145', 'H148', 'H160', 'H164', 'H166']

Annotator A:

```json
{
  "anchor_lines": [
    172,
    173,
    174
  ],
  "category": "error-handling",
  "description": "An unreadable config or a non-boolean opt-in is logged only as 'agy opt-in off' at info level, and strict mode silently runs without a configured voice instead of warning or refusing.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    172,
    173,
    174
  ],
  "category": "error-handling",
  "description": "The pipeline reports a config read failure as a plain 'opt-in off' info line and, in strict mode, does not refuse a review whose configured voices a failed read removed.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H164: group

- group members besides H164: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H166'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H145', 'H148', 'H160', 'H163', 'H166']

Annotator A:

```json
{
  "anchor_lines": [
    212
  ],
  "category": "error-handling",
  "description": "With no usable model the error always says 'all API keys missing' even when the voices were removed by the agy gate.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    212
  ],
  "category": "error-handling",
  "description": "With no adapters it always says 'all API keys missing', even when voices were not planned by the opt-in or by a config read error.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H165: category


Annotator A:

```json
{
  "anchor_lines": [
    347,
    348,
    349,
    350,
    351,
    352,
    353
  ],
  "category": "other",
  "description": "The posted verdict header never names the voices that were not planned or why.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D23",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    347,
    348,
    349,
    350,
    351,
    352,
    353
  ],
  "category": "logic",
  "description": "The posted verdict header is built without the voices that were not planned, so the PR comment hides which voices did not run and why.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D23",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H166: group

- group members besides H166: A ['H125', 'H126', 'H128', 'H130', 'H131', 'H135', 'H136', 'H137', 'H141', 'H142', 'H143', 'H145', 'H148', 'H159', 'H160', 'H161', 'H162', 'H163', 'H164'], B ['H125', 'H126', 'H136', 'H142', 'H143', 'H145', 'H148', 'H160', 'H163', 'H164']

Annotator A:

```json
{
  "anchor_lines": [
    421,
    422
  ],
  "category": "logic",
  "description": "Voices removed by a config read error shrink the expected quorum, so a review missing them can still clear the merge.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    421,
    422
  ],
  "category": "logic",
  "description": "Voices dropped by a config READ ERROR are subtracted from the expected quorum, so a host fault can shrink the quorum and clear the merge.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D22",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H168: category


Annotator A:

```json
{
  "anchor_lines": [
    652
  ],
  "category": "other",
  "description": "The verdict quality line omits the not-planned voices.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D23",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    652
  ],
  "category": "logic",
  "description": "The verdict-quality line omits the not-planned voices and the reason.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
  "group": "D23",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H169: group

- group members besides H169: A -, B ['H127', 'H149', 'H150', 'H170']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Generated header comment explaining units.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    14
  ],
  "category": null,
  "description": "Generated comment documenting the measured-to-estimate units rule.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": "D24",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H170: group, severity

- group members besides H170: A ['H127', 'H149', 'H150'], B ['H127', 'H149', 'H150', 'H169']

Annotator A:

```json
{
  "anchor_lines": [
    34
  ],
  "category": "logic",
  "description": "The Opus 5.5 budget (916000) takes a ceiling measured in provider tokens as estimate-unit tokens, and the char estimator under-counts the tokenizer ~1.8x, so Bridgebuilder builds prompts far past the real window.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": "D24",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    34
  ],
  "category": "logic",
  "description": "claude-opus-5-5's maxInput 916000 treats the provider-measured ceiling as BB estimate units; BB's estimate under-counts the 4.7+ tokenizer by ~1.8x, so BB sends payloads far above the measured bound.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
  "group": "D24",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H198: group

- group members besides H198: A ['H206', 'H207'], B ['H201', 'H206', 'H207']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "math/re imports for the classifier fixes.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
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
  "description": "Imports math/re used by the classifier and bounds fixes.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H200: group

- group members besides H200: A ['H220', 'H221'], B ['H216', 'H220']

Annotator A:

```json
{
  "anchor_lines": [
    133,
    134
  ],
  "category": "logic",
  "description": "A tokens-per-minute 429 is retried on the 5 s/15 s schedule, which cannot clear the 60 s window, and after three attempts it is recorded as a size rejection, so the probe can bracket the ceiling with a throttle.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D26",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    133,
    134
  ],
  "category": "logic",
  "description": "A tokens-per-minute 429 is retried on the 5 s/15 s schedule, which cannot clear the 60 s window, so a transient throttle persists and is mis-recorded.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D27",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H201: group

- group members besides H201: A -, B ['H198', 'H206', 'H207']

Annotator A:

```json
{
  "anchor_lines": [
    144
  ],
  "category": "logic",
  "description": "The 5xx regex matches any bare three-digit 5xx number (e.g. 'took 503 ms'), so non-transient failures are retried as transient.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D27",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    144
  ],
  "category": "logic",
  "description": "_STATUS_5XX matches any bare 5xx number (e.g. 'took 503 ms'), classifying non-transient failures as transient.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H202: anchors, group

- group members besides H202: A ['H212'], B ['H211', 'H212', 'H91', 'H92', 'H93', 'H94']

Annotator A:

```json
{
  "anchor_lines": [
    173,
    174,
    175,
    178
  ],
  "category": "input-validation",
  "description": "Operator- and CLI-supplied strings (host route, resolved cli model, cli --version) reach the catalog's provenance text unchecked, so a control or line-break character can break or inject YAML into the catalog.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D32",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    173,
    174,
    175,
    456,
    457,
    458,
    459,
    460,
    467,
    468
  ],
  "category": "input-validation",
  "description": "Operator- and CLI-supplied values (host route, resolved cli_model, cli --version) reach the catalog's YAML text and provenance comment unchecked, so a line break or control character can corrupt or inject catalog content.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H205: severity


Annotator A:

```json
{
  "anchor_lines": [
    238,
    239,
    240
  ],
  "category": "input-validation",
  "description": "Usage and cost values from the CLI JSON are taken unchecked; Infinity/NaN or absurd values crash the cost arithmetic (OverflowError) and lose the record.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D29",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    238,
    239,
    240
  ],
  "category": "input-validation",
  "description": "Non-finite or absurd CLI cost/token values (json accepts Infinity/NaN) are kept and later overflow the cost arithmetic.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D28",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H206: group, severity

- group members besides H206: A ['H198', 'H207'], B ['H198', 'H201', 'H207']

Annotator A:

```json
{
  "anchor_lines": [
    251,
    252,
    253,
    254,
    255,
    256,
    257
  ],
  "category": "logic",
  "description": "Classification runs on a 300-character truncated diagnostic and checks the context-limit marker before throttling, so Bedrock's 'Too many tokens, please wait' throttle is recorded as a size rejection and markers past 300 chars are missed.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    251,
    252,
    253,
    254,
    255,
    256,
    257
  ],
  "category": "logic",
  "description": "The classifier truncates the diagnostic to 300 chars before classifying and checks the context-limit marker first, so Bedrock's 'Too many tokens, please wait' throttle is recorded as a size rejection with no retry.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H207: group, severity

- group members besides H207: A ['H198', 'H206'], B ['H198', 'H201', 'H206']

Annotator A:

```json
{
  "anchor_lines": [
    266,
    267
  ],
  "category": "logic",
  "description": "Transient markers are searched in the truncated diagnostic only.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    266,
    267
  ],
  "category": "logic",
  "description": "Transient markers are searched in the truncated diagnostic only.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D25",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H208: group

- group members besides H208: A ['H100', 'H101', 'H102', 'H209', 'H210', 'H211', 'H217', 'H95'], B ['H100', 'H101', 'H102', 'H209', 'H210', 'H95']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Writer signature gains the required probe_outcome/sample_size parameters.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    403,
    404
  ],
  "category": null,
  "description": "Writer signature gains required probe_outcome / sample_size.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D16",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H209: group

- group members besides H209: A ['H100', 'H101', 'H102', 'H208', 'H210', 'H211', 'H217', 'H95'], B ['H100', 'H101', 'H102', 'H208', 'H210', 'H95']

Annotator A:

```json
{
  "anchor_lines": [
    402,
    403,
    404,
    413,
    414,
    415
  ],
  "category": "contract",
  "description": "write_catalog_operator_set takes no probe outcome or sample count and does not validate its string inputs, so a written entry cannot say whether its probe was clean or partial.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    402,
    403,
    404,
    413,
    414,
    415
  ],
  "category": "contract",
  "description": "write_catalog_operator_set has no probe_outcome and validates none of its provenance fields, so any caller can write a partial or unvalidated probe as if it were clean.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D16",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H210: group, severity

- group members besides H210: A ['H100', 'H101', 'H102', 'H208', 'H209', 'H211', 'H217', 'H95'], B ['H100', 'H101', 'H102', 'H208', 'H209', 'H95']

Annotator A:

```json
{
  "anchor_lines": [
    456,
    460
  ],
  "category": "logic",
  "description": "The catalog writer hard-codes sample_size: null and writes no probe_outcome.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    456,
    460
  ],
  "category": "logic",
  "description": "The writer hardcodes sample_size: null and omits probe_outcome in ceiling_calibration.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D16",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H211: group

- group members besides H211: A ['H100', 'H101', 'H102', 'H208', 'H209', 'H210', 'H217', 'H95'], B ['H202', 'H212', 'H91', 'H92', 'H93', 'H94']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Provenance comment gains the partial note via a template.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    467,
    468
  ],
  "category": null,
  "description": "Provenance comment moved to a template (checked by the re-parse) with the partial note.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D15",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H212: group, category

- group members besides H212: A ['H202'], B ['H202', 'H211', 'H91', 'H92', 'H93', 'H94']

Annotator A:

```json
{
  "anchor_lines": [
    480
  ],
  "category": "input-validation",
  "description": "The produced catalog text is returned without re-parsing, so a malformed or collateral edit is written unverified.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D32",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    480
  ],
  "category": "logic",
  "description": "The line-level catalog edit is returned without re-parsing, so a malformed write or a change outside the entry would be persisted.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D15",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H213: group

- group members besides H213: A ['H214'], B ['H214', 'H217']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Argument defaults/help changed so api-only flags can be detected; adds the partial-write flag.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D33",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    501,
    502,
    503
  ],
  "category": null,
  "description": "Argument defaults/help changed so api-only flags can be detected; adds the partial-write flag.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D29",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H214: group

- group members besides H214: A ['H213'], B ['H213', 'H217']

Annotator A:

```json
{
  "anchor_lines": [
    512,
    513
  ],
  "category": "input-validation",
  "description": "--allow-partial/--tier/--itpm are silently ignored under --transport claude-headless.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D33",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    512,
    513
  ],
  "category": "input-validation",
  "description": "--allow-partial, --tier and --itpm are silently ignored with --transport claude-headless, so the operator believes they took effect.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D29",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H215: anchors


Annotator A:

```json
{
  "anchor_lines": [
    616,
    617,
    618,
    623,
    625
  ],
  "category": "logic",
  "description": "An outcome bracketed by a token-limit (throttle) rejection rather than a context-limit rejection is accepted as clean, so a rate limit is written as the context ceiling.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D34",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    617,
    618,
    619,
    627,
    628
  ],
  "category": "logic",
  "description": "A bound bracketed by a token-budget/throttle rejection (not a context limit) is judged clean and can be written as the context ceiling.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D30",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H216: anchors, group

- group members besides H216: A ['H219'], B ['H200', 'H220']

Annotator A:

```json
{
  "anchor_lines": [
    711,
    712,
    713,
    714,
    715,
    716
  ],
  "category": "logic",
  "description": "Spend accounting charges every failed attempt the full estimate (including the CLI's free local pre-flight rejections and never-sent spawns), exhausting the budget cap on attempts that cost nothing.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D35",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    720,
    721,
    722,
    723,
    724,
    725,
    726,
    727
  ],
  "category": "logic",
  "description": "A token-limit 429 that persists over the short retries is turned into a size rejection even though the TPM window was never waited out, and retry-after hints are ignored (the hunk also adds the per-attempt charge table).",
  "file": "tools/ceiling-probe-live.py",
  "group": "D27",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H217: group

- group members besides H217: A ['H100', 'H101', 'H102', 'H208', 'H209', 'H210', 'H211', 'H95'], B ['H213', 'H214']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Usage check for the new partial-write flag.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    639
  ],
  "category": null,
  "description": "Validates the new partial-write flag's dependency.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D29",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H218: anchors, group

- group members besides H218: A -, B ['H219', 'H221']

Annotator A:

```json
{
  "anchor_lines": [
    644,
    645,
    646,
    647,
    648,
    653
  ],
  "category": "logic",
  "description": "With --write-catalog the catalog prerequisites (block, context_window, writable file) and the provenance strings are only checked after the paid bisection, and the cost estimate ignores the cache-write rate and tokenizer ratio, so money is spent on a probe whose write cannot land.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D36",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    644,
    645,
    646,
    647,
    648,
    649,
    650,
    651,
    652,
    653
  ],
  "category": "logic",
  "description": "The budget estimate uses the plain input price (the CLI bills the cache-write rate, 1.25x) and a 1.0 tokenizer ratio, and catalog write prerequisites/provenance are only checked after money has been spent.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H219: anchors, group

- group members besides H219: A ['H216'], B ['H218', 'H221']

Annotator A:

```json
{
  "anchor_lines": [
    688,
    689,
    690
  ],
  "category": "logic",
  "description": "The budget pre-check estimates the first step at ratio 1.0, under-estimating its cost by the ~1.8x tokenizer ratio, so the cap can be exceeded.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D35",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    684,
    688,
    689,
    690
  ],
  "category": "logic",
  "description": "The per-attempt budget pre-check estimates the first blind step at ratio 1.0, under-estimating the cost of the 4.7+ tokenizer.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H220: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Uses the computed retry wait.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D26",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    697
  ],
  "category": "logic",
  "description": "The retry sleep always uses the short backoff regardless of class or retry-after hint.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D27",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H221: anchors, group

- group members besides H221: A ['H200', 'H220'], B ['H218', 'H219']

Annotator A:

```json
{
  "anchor_lines": [
    705,
    706,
    707,
    711,
    712,
    713,
    714,
    715,
    716,
    720,
    721,
    722,
    723,
    724,
    725,
    726,
    727
  ],
  "category": "logic",
  "description": "A token-limit transient that persists over the short retries is turned into a size rejection without the TPM window having been waited out, and output-cap/timeout/spawn cases are not distinguished for charging.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D26",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    705,
    706,
    707,
    708,
    709,
    710,
    711,
    712,
    713,
    714,
    715,
    716
  ],
  "category": "logic",
  "description": "Spend charges every failed attempt (including CLI-local rejections never sent, spawn failures) at the full estimate and does not handle an output-cap overflow or an interrupt mid-attempt, so spend and budget stops are wrong.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D31",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H223: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the interruption reason to the outcome reasons.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D29",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    771,
    772,
    773
  ],
  "category": "error-handling",
  "description": "The outcome reasons never record an interrupted bisection.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D28",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H224: anchors


Annotator A:

```json
{
  "anchor_lines": [
    799,
    802
  ],
  "category": "other",
  "description": "The record stores the binary path and argv with the operator's absolute home path (and an unresolved bare binary name).",
  "file": "tools/ceiling-probe-live.py",
  "group": "D37",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    799,
    800,
    801,
    802
  ],
  "category": "other",
  "description": "The tracked probe record stores the raw cli_bin and argv (absolute home paths) and re-resolves cli_model, not the binary that actually ran.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D32",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H225: anchors, severity


Annotator A:

```json
{
  "anchor_lines": [
    811,
    815,
    816,
    817,
    818
  ],
  "category": "logic",
  "description": "The record claims written_ceiling before the catalog write is attempted, so a failed write still leaves a record saying it was written.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D38",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    811,
    812,
    813,
    814,
    815,
    816,
    817,
    818,
    819,
    820,
    821
  ],
  "category": "logic",
  "description": "The record claims written_ceiling before the catalog write is attempted, so a failed atomic write leaves a record saying the bound was written.",
  "file": "tools/ceiling-probe-live.py",
  "group": "D33",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H05

```json
{
  "A": "The observed provider-limit lookup ignores the hop's context_window, so a recorded observation outside the plausible window range (e.g. from a different route) can lower or set the input bound; intent inferred from the added argument.",
  "B": "The observed provider limit is looked up without the hop's context_window, so an out-of-range observation (e.g. from another route) can lower or distort this hop's input bound."
}
```

- H08

```json
{
  "A": "The 'sets both params.default_effort and extra.effort' warning fires for HTTP entries whose extra rung is never read, a misleading config warning.",
  "B": "The 'sets both params.default_effort and extra.effort' WARN fires for HTTP entries, whose extra rung is never read, producing a spurious config warning."
}
```

- H09

```json
{
  "A": "The CLI extra rung only reads the first truthy of extra.effort/reasoning_effort, so an invalid extra.effort hides a valid reasoning_effort and the invalid value is silently ignored without a warning.",
  "B": "For a CLI entry an invalid extra.effort hides a valid extra.reasoning_effort (the `or` picks the first truthy key) and the invalid value is dropped silently without a WARN."
}
```

- H10

```json
{
  "A": "effort_effective is derived by a hard-coded provider check (any CLI hop passes effort through, only provider 'anthropic' maps) rather than the dispatching adapter, so the MODELINV record misstates the wire effort for codex/grok/other adapters and for providers whose block type differs from the key.",
  "B": "_effort_on_wire hardcodes 'CLI passes through, anthropic maps, everyone else None' instead of asking the dispatching adapter, so MODELINV effort_effective is wrong for providers whose type differs from the key or for CLI adapters that do not send effort."
}
```

- H13

```json
{
  "A": "Pre-flight gate looks up the observed limit without the head entry's context_window, so implausible observations are not filtered.",
  "B": "Pre-flight gate reads the observed bound without the head hop's context_window."
}
```

- H15

```json
{
  "A": "A CLI hop's own size rejection is recorded in the observed-ceiling store, lowering the HTTP route's input bound with a measurement that does not apply to it.",
  "B": "A CLI hop's own size rejection is recorded as a ceiling observation for the provider/model, wrongly lowering the HTTP route's input bound."
}
```

- H16

```json
{
  "A": "The calibrate hint names the CLI hop's model (which the probe refuses) and interpolates the model id unquoted into a shell command the operator pastes.",
  "B": "The calibration hint always names the failing hop's model id unquoted, so a CLI hop gets a probe command the probe refuses and the model id is not shell-quoted."
}
```

- H17

```json
{
  "A": "The preflight line always prints 'run: <probe command>' even for a CLI hop with no calibratable HTTP entry.",
  "B": "The operator message prints a probe command even when no calibration is possible for a CLI hop."
}
```

- H18

```json
{
  "A": "The error JSON always says 'calibrate: <command>' even when no probe command applies.",
  "B": "The error JSON names a calibrate command even when the CLI's own window refused the payload."
}
```

- H19

```json
{
  "A": "Per-hop bound computation looks up the observed limit without the hop's context_window.",
  "B": "The per-hop derived bound reads the observed limit without the hop's context_window."
}
```

- H21

```json
{
  "A": "effort_effective is computed inline inside the emit call, so any exception in its derivation falls into the emit's handler and the whole MODELINV envelope is lost.",
  "B": "effort_effective is computed inline in the _emit_modelinv call, so an exception there falls into the emit handler and the whole MODELINV envelope is lost."
}
```

- H31

```json
{
  "A": "validate_config keeps checking type and the agy binary when the opt-in is off, adding irrelevant 'CLI not found' errors to the opt-in refusal.",
  "B": "With the opt-in off validate_config still looks up the binary and reports 'CLI not found on PATH', a misleading error for a route that is disabled."
}
```

- H117

```json
{
  "A": "cli_for ignores provider-prefixed ids (google:gemini-headless) and the local opt-in reader uses python-yq '== true', which differs from the strict shared rule.",
  "B": "run-preflight's agy_opted_in accepts `== true` under python yq (loose truthiness) and cli_for misses provider-prefixed headless ids, so P3 can judge gated agy voices as usable."
}
```

- H118

```json
{
  "A": "provider_of returns no provider for catalog model ids without a family prefix (e.g. deep-research-pro), so such Google voices are not recognised.",
  "B": "provider_of returns empty for catalog Google ids without a gemini prefix (e.g. deep-research-pro), so they escape the agy gate."
}
```

- H121

```json
{
  "A": "A stage whose every voice is gated off by the opt-in is reported as having no credential and no CLI on PATH, a misleading failure reason.",
  "B": "A stage whose every voice is gated off by the agy opt-in is reported as 'no credential present and no CLI hop', a misleading remediation."
}
```

- H122

```json
{
  "A": "The P3 FAIL detail gives the missing-credential reason for stages that failed only because of the agy opt-in.",
  "B": "The P3 FAIL detail does not say the stage failed because of the opt-in."
}
```

- H203

```json
{
  "A": "subprocess.run(timeout=) kills only the direct child (the wrapper), leaving the claude process running, and output past 1 MB is silently truncated and still classified.",
  "B": "subprocess.run(timeout=) kills only the direct child (the wrapper), leaving the real claude process running, and output past 1 MB is silently truncated into a classification."
}
```

- H204

```json
{
  "A": "An exception inside classification propagates and aborts the probe, losing the record of paid steps.",
  "B": "An exception inside _classify propagates as a traceback and loses the probe record after paid attempts."
}
```

- H222

```json
{
  "A": "A ^C or unexpected exception during the bisection aborts without writing the record of the paid steps.",
  "B": "The bisection loop is unguarded: ^C or an unexpected exception after paid steps exits without writing the record."
}
```

- H226

```json
{
  "A": "No exit path distinguishes an interrupted probe; with the record lost on exception the operator gets no record or exit status for it.",
  "B": "There is no exit path for an interrupted bisection, so it falls through the partial/clean handling with the wrong exit code."
}
```
