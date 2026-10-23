# Adjudication list — pr-21

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

70 item(s) disagree.

### H01: anchors, group

- group members besides H01: A ['H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [
    1813,
    1817
  ],
  "category": "security",
  "description": "Under hounfour.locality local_voices cheval plans only around agy hops, so hosted hops (primary or fallback) of a chain are still dispatched with the prompt.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    420,
    422
  ],
  "category": "security",
  "description": "Under hounfour.locality local_voices cheval has no planner that drops hosted hops, so a chain containing hosted hops is dispatched to them (only the agy opt-in is planned around).",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H02: group

- group members besides H02: A ['H01', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [
    1813,
    1814,
    1815,
    1817
  ],
  "category": "security",
  "description": "cheval never applies the local_voices posture before the chain walk, so a chain with no local hop is dispatched to hosted providers instead of being refused.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1813,
    1814,
    1815,
    1817
  ],
  "category": "security",
  "description": "The dispatch path only plans around agy, so under local_voices hosted hops are walked and a chain with no local hop is dispatched instead of being refused with a MODELINV row.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H03: group, category

- group members besides H03: A ['H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [
    474,
    475,
    476
  ],
  "category": "logic",
  "description": "MODELINV hop_locality records 'local' for any hop whose model is labelled dispatch_group local, even when the provider is a CLI provider or its endpoint host is not loopback/RFC1918/localhost.",
  "file": ".claude/adapters/loa_cheval/audit/modelinv.py",
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
    474,
    475,
    476
  ],
  "category": "security",
  "description": "MODELINV hop_locality records 'local' for any hop whose model declares dispatch_group local, even when the provider is CLI or its endpoint host is not loopback/RFC1918.",
  "file": ".claude/adapters/loa_cheval/audit/modelinv.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H05: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds local-hop rule helpers used by the validate_providers fix.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    112,
    116
  ],
  "category": "security",
  "description": "There is no local-hop rule at load: a dispatch_group local label on a CLI provider or on a provider whose endpoint host is public is accepted and trusted.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H06: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds hop_is_local and validate_local_fallbacks helpers called by the planner/loader fixes.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
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
    125
  ],
  "category": "security",
  "description": "Nothing validates that a dispatch_group local model's fallback_chain stays on local hops under local_voices, so cheval's in-call fallback walk can send the prompt to a hosted provider.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H09: group

- group members besides H09: A ['H03', 'H05', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [
    153,
    156,
    157,
    159
  ],
  "category": "security",
  "description": "validate_providers trusts a dispatch_group local label: a CLI provider or a provider with a public/DNS endpoint labelled local is admitted at load (and an https local endpoint is wrongly refused without an opt-in).",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    153,
    156,
    157,
    159
  ],
  "category": "security",
  "description": "validate_providers never checks a dispatch_group local label against the endpoint host (and refuses a local-labelled https loopback/RFC1918 endpoint without an opt-in), so a declared locality is trusted rather than enforced.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H12: anchors


Annotator A:

```json
{
  "anchor_lines": [
    230,
    231,
    232,
    233
  ],
  "category": "error-handling",
  "description": "A ConfigError raised by describe_provider is not caught, producing a traceback instead of the JSON error and exit 78.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    230,
    231
  ],
  "category": "error-handling",
  "description": "A ConfigError raised by describe_provider is not caught, so the CLI crashes with a traceback instead of reporting config_load_failed with exit 78.",
  "file": ".claude/adapters/loa_cheval/config/endpoint_policy.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H13: group

- group members besides H13: A ['H01', 'H02', 'H06', 'H14', 'H19', 'H22', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H14', 'H19', 'H22', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Import for the new fallback check.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
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
  "description": "Imports validate_local_fallbacks for the loader fix.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H14: group

- group members besides H14: A ['H01', 'H02', 'H06', 'H13', 'H19', 'H22', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H13', 'H19', 'H22', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [
    704
  ],
  "category": "security",
  "description": "The loader admits, under local_voices, a dispatch_group local model whose fallback_chain reaches a hosted hop, so cheval can walk the prompt to a hosted provider.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    704
  ],
  "category": "security",
  "description": "load_config never refuses a local model whose fallback_chain reaches a hosted hop under local_voices.",
  "file": ".claude/adapters/loa_cheval/config/loader.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H15: group

- group members besides H15: A ['H03', 'H05', 'H09', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the local flag to TransportPolicy for the request-time host check.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D2",
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
  "description": "Adds the `local` field and imports to TransportPolicy for the request-time local-hop check.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H16: anchors, group

- group members besides H16: A ['H03', 'H05', 'H09', 'H15', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [
    137,
    138,
    139,
    140
  ],
  "category": "security",
  "description": "TransportPolicy.check_url never requires a local hop's request host to be loopback/RFC1918/localhost, so a declared locality is not enforced at request time.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    128,
    136,
    137,
    140
  ],
  "category": "security",
  "description": "TransportPolicy.check_url does not require a local hop's request host to be loopback/RFC1918/localhost, so a dispatch_group local hop reaching the adapter by another loader can go to any host.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H17: anchors


Annotator A:

```json
{
  "anchor_lines": [
    140,
    145
  ],
  "category": "security",
  "description": "A localhost endpoint is trusted without checking what the system resolver maps it to, so a non-loopback /etc/hosts entry sends a local/plain-http request off the machine.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    128,
    145
  ],
  "category": "security",
  "description": "A localhost endpoint is trusted without checking what the system resolver returns, so a hosts/nsswitch entry can send a 'local' or plain-http opted-in request to a non-loopback address.",
  "file": ".claude/adapters/loa_cheval/providers/base.py",
  "group": "D5",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H18: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Passes the local flag into TransportPolicy.",
  "file": ".claude/adapters/loa_cheval/providers/openai_adapter.py",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    221,
    222
  ],
  "category": "security",
  "description": "The adapter builds the TransportPolicy without marking local hops, so the request-time local-host rule is never applied.",
  "file": ".claude/adapters/loa_cheval/providers/openai_adapter.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H19: group

- group members besides H19: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H22', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H13', 'H14', 'H22', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds LocalityRefusedError used by the planner fix.",
  "file": ".claude/adapters/loa_cheval/types.py",
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
  "description": "Adds LocalityRefusedError used by the locality planner fix.",
  "file": ".claude/adapters/loa_cheval/types.py",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H22: group

- group members besides H22: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H23', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H23', 'H24']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema enum extended for locality_refused.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
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
  "description": "Schema enum extended with locality_refused for the new refusal.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H23: group

- group members besides H23: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H24', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H24']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema description for locality_refused.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
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
  "description": "Schema description for locality_refused not-planned hops.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H24: group

- group members besides H24: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H44', 'H45', 'H72', 'H73'], B ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema enum extended for locality_refused.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
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
  "description": "Schema enum extended with locality_refused for models_not_planned.",
  "file": ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json",
  "group": "D1",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H26: category


Annotator A:

```json
{
  "anchor_lines": [
    3888,
    3889
  ],
  "category": "input-validation",
  "description": "A zero catalog price on a non-open-weight entry (a bad pricing overlay) is accepted silently, zeroing the budget estimate without a warning.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    3888,
    3889
  ],
  "category": "logic",
  "description": "A zero-priced voice is accepted as 0c with no warning even when it is not an open-weight entry, so a bad pricing overlay silently zeroes the budget estimate.",
  "file": ".claude/scripts/adversarial-review.sh",
  "group": "D6",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

### H30: group

- group members besides H30: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Imports for the endpoint check.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
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
  "description": "Imports for the endpoint locality helper.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H31: group

- group members besides H31: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds the stdlib endpoint locality helpers.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
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
  "description": "Adds helper functions used by the classifier fix.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H32: group

- group members besides H32: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [
    116,
    117,
    118,
    119
  ],
  "category": "security",
  "description": "The planner classifies a hop as local purely from its dispatch_group label, without rejecting CLI providers or endpoints whose host is not loopback/RFC1918/localhost.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    116,
    117,
    118,
    119
  ],
  "category": "security",
  "description": "The planner classifier calls a hop local on the dispatch_group label alone, without rejecting CLI providers or endpoints whose host is not loopback/RFC1918/localhost.",
  "file": ".claude/scripts/lib/hop-locality.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H34: group

- group members besides H34: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Rebuilt manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D2",
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
  "description": "Regenerated build manifest.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H35: group

- group members besides H35: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H34', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Rebuilt manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D2",
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
  "description": "Regenerated build manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H36: group

- group members besides H36: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H34', 'H35', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Rebuilt manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D2",
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
  "description": "Regenerated build manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H37: group

- group members besides H37: A ['H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Rebuilt manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D8",
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
  "description": "Regenerated build manifest hash.",
  "file": ".claude/skills/bridgebuilder-review/dist/.build-manifest.json",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H38: group

- group members besides H38: A ['H37', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D8",
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
  "description": "Generated type declarations for the drift fields.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H39: group

- group members besides H39: A -, B ['H34', 'H35', 'H36', 'H37', 'H38', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Doc comment update in compiled output.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Generated doc comment copy.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H40: group

- group members besides H40: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D2",
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
  "description": "Generated declarations for the new locality and drift functions.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H41: group

- group members besides H41: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.d.ts.map",
  "group": "D2",
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
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H42: group

- group members besides H42: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the config.ts import change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H43: group

- group members besides H43: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the schema field additions.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H44: group

- group members besides H44: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24', 'H45', 'H72', 'H73'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
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
  "description": "Compiled copy of the parseProviderDecls change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H45: group

- group members besides H45: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24', 'H44', 'H72', 'H73'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
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
  "description": "Compiled copy of the parseProviderDecls change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H46: group

- group members besides H46: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the parseProviderDecls change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H47: group

- group members besides H47: A ['H37', 'H38', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
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
  "description": "Compiled copy of the trusted-view yq change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H48: group

- group members besides H48: A ['H37', 'H38', 'H47', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
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
  "description": "Compiled copy of the yqTrustedView change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H49: group

- group members besides H49: A -, B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Doc comment update in compiled output.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": null,
  "not_defect_class": "docs",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled doc comment copy.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H50: group

- group members besides H50: A ['H37', 'H38', 'H47', 'H48', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
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
  "description": "Compiled copy of the head drift computation.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H51: group

- group members besides H51: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
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
  "description": "Compiled copy of the head drift computation.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H52: group

- group members besides H52: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
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
  "description": "Compiled copy of the drift functions.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H53: group

- group members besides H53: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the isLocalVoice/localVoiceDecision fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H54: group

- group members besides H54: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the applyLocality change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H55: group

- group members besides H55: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
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
  "description": "Compiled copy of the singleModelLocalityRefusal change.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H56: group

- group members besides H56: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/config.js.map",
  "group": "D2",
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
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H57: group

- group members besides H57: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration copy.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts",
  "group": "D2",
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
  "description": "Generated type additions for ProviderDecl.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H58: group

- group members besides H58: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled declaration copy.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts",
  "group": "D8",
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
  "description": "Generated type additions for TrustedConfig.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H59: group

- group members besides H59: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts.map",
  "group": "D2",
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
  "file": ".claude/skills/bridgebuilder-review/dist/core/types.d.ts.map",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H60: group

- group members besides H60: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.d.ts.map",
  "group": "D8",
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
  "file": ".claude/skills/bridgebuilder-review/dist/main.d.ts.map",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H61: group

- group members besides H61: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.js",
  "group": "D8",
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
  "description": "Compiled copy of the main.ts import change.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H62: group

- group members besides H62: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Compiled copy of the source fix.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.js",
  "group": "D8",
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
  "description": "Compiled copy of the drift refusal in main.ts.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.js",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H63: group

- group members besides H63: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Regenerated source map.",
  "file": ".claude/skills/bridgebuilder-review/dist/main.js.map",
  "group": "D8",
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
  "file": ".claude/skills/bridgebuilder-review/dist/main.js.map",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H70: group

- group members besides H70: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H71', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Import for the IPv6 host check.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
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
  "description": "Import for the endpoint host check.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H71: group

- group members besides H71: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H74', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Schema reads endpoint/type for the local-hop rule.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
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
  "description": "Reads endpoint and type into the provider schema for the locality check.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H72: group

- group members besides H72: A ['H01', 'H02', 'H06', 'H13', 'H14', 'H19', 'H22', 'H23', 'H24', 'H44', 'H45', 'H73'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H73', 'H74', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Variables for collecting fallbacks and CLI models.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
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
  "description": "Counters for CLI detection and fallback collection.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H73: verdict


Annotator A:

```json
{
  "anchor_lines": [
    484,
    485,
    486,
    487,
    488
  ],
  "category": "security",
  "description": "Bridgebuilder ignores each model's fallback_chain (and CLI kind), so under local_voices a local voice whose chain falls back to a hosted hop is kept.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Collects CLI kind and fallback chains for the locality decision.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H74: group

- group members besides H74: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H82', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H82', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Records endpoint, cli and fallbacks on the declaration.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
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
  "description": "Stores endpoint, cli and fallbacks on ProviderDecl.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H75: group

- group members besides H75: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "yq view extended with aliases and allowlists for drift detection.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
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
  "description": "Trusted view also reads aliases and secret allowlists, for the drift comparison.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H76: group

- group members besides H76: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "TrustedView fields for drift detection.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
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
  "description": "TrustedView type fields for the drift comparison.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H77: group

- group members besides H77: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H79', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Returns the new view fields.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
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
  "description": "Returns the new trusted view fields.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H79: group

- group members besides H79: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H80', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H80', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Restructures head-view scoping for the drift computation.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
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
  "description": "Hoists headView for the drift computation.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H80: anchors, group

- group members besides H80: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H81', 'H86', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H81', 'H86', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [
    671,
    672,
    673,
    676,
    678,
    681
  ],
  "category": "security",
  "description": "On a pull request the head config is only checked for head-only keyless/insecure providers; other differences (endpoints, aliases, locality, secret allowlist) that cheval reads from the checkout are not detected, so an attacker-controlled head steers dispatch.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    671,
    673,
    678,
    679
  ],
  "category": "security",
  "description": "On a pull request the head config is only checked for head-only keyless/insecure providers, so other head changes cheval will read (providers' endpoints, aliases, locality, secret allowlist, or an unparsable head) go undetected.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H81: verdict


Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Adds drift helpers and returns headDrift/aliases.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    711
  ],
  "category": "security",
  "description": "loadTrustedConfig returns no head-drift result, so nothing can refuse a PR whose head changes the configuration cheval dispatches with.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H82: anchors, group

- group members besides H82: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H83', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H83', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [
    722,
    723,
    724,
    725,
    726,
    727,
    728,
    729,
    730,
    731,
    732
  ],
  "category": "security",
  "description": "isLocalVoice treats any voice labelled dispatch_group local as local without checking that the provider is not a CLI provider and its endpoint host is loopback/RFC1918/localhost.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    726,
    727,
    728,
    729,
    730,
    731,
    732
  ],
  "category": "security",
  "description": "isLocalVoice trusts the dispatch_group local label alone, ignoring CLI providers, the endpoint host and the model's fallback_chain, so a hosted voice can pass the local_voices filter.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H83: group

- group members besides H83: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H84', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H84', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Caller updated to localVoiceDecision.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
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
  "description": "applyLocality uses the new decision and its reason.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H84: group

- group members besides H84: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H85'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H85']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Caller updated to localVoiceDecision.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
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
  "description": "singleModelLocalityRefusal uses the new decision and its reason.",
  "file": ".claude/skills/bridgebuilder-review/resources/config.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H85: group

- group members besides H85: A ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H34', 'H35', 'H36', 'H40', 'H41', 'H42', 'H43', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H59', 'H70', 'H71', 'H74', 'H82', 'H83', 'H84'], B ['H03', 'H05', 'H09', 'H15', 'H16', 'H18', 'H30', 'H31', 'H32', 'H40', 'H41', 'H42', 'H43', 'H44', 'H45', 'H46', 'H53', 'H54', 'H55', 'H56', 'H57', 'H70', 'H71', 'H72', 'H73', 'H74', 'H82', 'H83', 'H84']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Type fields for endpoint/cli/fallbacks.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
  "group": "D2",
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
  "description": "ProviderDecl fields for the locality fix.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
  "group": "D2",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H86: group

- group members besides H86: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H88', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H88', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Type fields for aliases/headDrift.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
  "group": "D8",
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
  "description": "TrustedConfig fields for aliases and headDrift.",
  "file": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H88: group

- group members besides H88: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H89'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H89']

Annotator A:

```json
{
  "anchor_lines": [],
  "category": null,
  "description": "Imports for the drift refusal.",
  "file": ".claude/skills/bridgebuilder-review/resources/main.ts",
  "group": "D8",
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
  "description": "Imports for the drift refusal.",
  "file": ".claude/skills/bridgebuilder-review/resources/main.ts",
  "group": "D8",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

### H89: group

- group members besides H89: A ['H37', 'H38', 'H47', 'H48', 'H50', 'H51', 'H52', 'H58', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88'], B ['H34', 'H35', 'H36', 'H37', 'H38', 'H39', 'H47', 'H48', 'H49', 'H50', 'H51', 'H52', 'H58', 'H59', 'H60', 'H61', 'H62', 'H63', 'H75', 'H76', 'H77', 'H79', 'H80', 'H81', 'H86', 'H88']

Annotator A:

```json
{
  "anchor_lines": [
    464,
    465,
    466
  ],
  "category": "security",
  "description": "main.ts proceeds to plan voices on a pull request whose head config differs from the trusted config instead of refusing the run.",
  "file": ".claude/skills/bridgebuilder-review/resources/main.ts",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    464,
    465,
    466
  ],
  "category": "security",
  "description": "main.ts goes ahead with the multi-model run on a PR even when the head's provider/alias/locality/allowlist config differs from the trusted source, even though cheval dispatches with the checkout's config.",
  "file": ".claude/skills/bridgebuilder-review/resources/main.ts",
  "group": "D8",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H90: anchors, category


Annotator A:

```json
{
  "anchor_lines": [
    78,
    79,
    80,
    85,
    89
  ],
  "category": "error-handling",
  "description": "Any exit 3 is treated as a completed DEGRADED review and mapped to exit 0 even when no run JSON proves completion, masking failures (and incomplete_voices is a string rather than an array).",
  "file": ".claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    78,
    79,
    80,
    85,
    88,
    89
  ],
  "category": "logic",
  "description": "The dispatcher treats any exit 3 as a completed DEGRADED review and exits 0, even with no run JSON to prove it, so a failure that happens to exit 3 is reported as success; it also records incomplete_voices as a string, not an array.",
  "file": ".claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh",
  "group": "D9",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H07

```json
{
  "A": "An explicit keyless: false combined with a literal auth such as \"local\" is silently overridden to keyless: true instead of being refused as a conflict.",
  "B": "An explicit keyless: false combined with a literal auth like \"local\" is silently overwritten to keyless: true instead of being refused as a conflict."
}
```

- H11

```json
{
  "A": "The endpoint_policy CLI catches only ConfigError from load_config, so a YAML parse or other load failure escapes as a traceback instead of the JSON error line and exit 78.",
  "B": "The endpoint_policy CLI only catches ConfigError from load_config, so any other load failure (e.g. unparseable YAML) escapes as a traceback instead of the JSON error line and exit 78 the health probe expects."
}
```

- H28

```json
{
  "A": "The local_voices envelope attaches the DEGRADED note to every audit regardless of whether the companion was an independent voice, and provides no machine-readable degraded_security_review flag.",
  "B": "Under local_voices every audit envelope gets the DEGRADED note even with an independent companion voice, and the degraded-security-review case has no machine-readable flag."
}
```
