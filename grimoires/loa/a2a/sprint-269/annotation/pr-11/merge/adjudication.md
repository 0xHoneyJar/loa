# Adjudication list — pr-11

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

7 item(s) disagree.

### H02: verdict


Annotator A:

```json
{
  "anchor_lines": [
    2004
  ],
  "category": null,
  "description": "Computes the sanitised provider message consumed by the D2 fix.",
  "file": ".claude/adapters/cheval.py",
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
    2022,
    2032
  ],
  "category": "security",
  "description": "The calibration exit records and prints the raw provider error text (str(_exc)) under message_redacted and in stderr JSON without passing it through the redaction helper.",
  "file": ".claude/adapters/cheval.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H03: anchors


Annotator A:

```json
{
  "anchor_lines": [
    2022,
    2032
  ],
  "category": "security",
  "description": "The calibration exit records the raw provider error text under message_redacted (and prints it) without passing it through the redaction helper, so secret-shaped fragments can reach the envelope and stderr.",
  "file": ".claude/adapters/cheval.py",
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
    2022
  ],
  "category": "security",
  "description": "message_redacted is filled with the unredacted provider error string.",
  "file": ".claude/adapters/cheval.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H05: severity


Annotator A:

```json
{
  "anchor_lines": [
    2110,
    2256,
    2297
  ],
  "category": "logic",
  "description": "Unverified (above-probed-bound) status is inherited from the chain head instead of being computed per hop, so a calibrated fallback's 429 or context verdict is misclassified as unverified and not walked.",
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
    2110,
    2256,
    2297
  ],
  "category": "logic",
  "description": "The 'above the probed bound' status is taken from the chain head (_ceiling_unverified) instead of computed per hop, so a calibrated fallback's ordinary 429 is not walked and is recorded as RATE_LIMIT_UNVERIFIED, and its context verdict is misclassed as CEILING_UNVERIFIED_LIMIT.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H06: severity


Annotator A:

```json
{
  "anchor_lines": [
    2256
  ],
  "category": "logic",
  "description": "A provider context-limit verdict on any hop is classed CEILING_UNVERIFIED_LIMIT based on the head's unverified flag rather than this hop's.",
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
    2256
  ],
  "category": "logic",
  "description": "Provider context-limit class on a fallback hop uses the head's unverified status rather than the hop's own.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H07: severity


Annotator A:

```json
{
  "anchor_lines": [
    2297
  ],
  "category": "logic",
  "description": "A 429 on a calibrated fallback hop ends the call as RATE_LIMIT_UNVERIFIED (and writes a calibration record) because the head's unverified flag is used instead of the hop's.",
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
    2297
  ],
  "category": "logic",
  "description": "A 429 on a calibrated fallback hop ends the call as RATE_LIMIT_UNVERIFIED (not walked) because the head's unverified status is inherited.",
  "file": ".claude/adapters/cheval.py",
  "group": "D1",
  "not_defect_class": null,
  "severity": "high",
  "verdict": "defect"
}
```

### H11: verdict


Annotator A:

```json
{
  "anchor_lines": [
    290
  ],
  "category": null,
  "description": "Imports math and rejects bool values as part of the D4 multiplier validation fix.",
  "file": ".claude/adapters/loa_cheval/metering/pricing.py",
  "group": "D4",
  "not_defect_class": "follow-on",
  "severity": null,
  "verdict": "not-defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    290,
    292,
    295
  ],
  "category": "input-validation",
  "description": "The multiplier parser accepts non-finite values (inf, nan, 1e309) and booleans, which later crash or explode the cost calculation instead of defaulting to 1.0.",
  "file": ".claude/adapters/loa_cheval/metering/pricing.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

### H12: anchors


Annotator A:

```json
{
  "anchor_lines": [
    292,
    295
  ],
  "category": "input-validation",
  "description": "Non-finite multipliers (inf, nan, 1e309) pass the `> 0` check and are accepted, crashing or exploding the cost calculation instead of falling back to 1.0.",
  "file": ".claude/adapters/loa_cheval/metering/pricing.py",
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
    295
  ],
  "category": "input-validation",
  "description": "Only m > 0 is checked, so inf passes and nan falls through inconsistently instead of requiring a finite positive multiplier.",
  "file": ".claude/adapters/loa_cheval/metering/pricing.py",
  "group": "D4",
  "not_defect_class": null,
  "severity": "medium",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H04

```json
{
  "A": "The stderr error JSON embeds the unsanitised provider exception text.",
  "B": "The stderr error JSON embeds the unredacted provider error string."
}
```

- H10

```json
{
  "A": "The long-context premium multiplies already-floored per-category costs (with float math), underbilling by the discarded remainders and dropping remainders for the premium path.",
  "B": "The long-context premium multiplies already-floored per-category costs (and float-multiplies), underbilling by the discarded remainders and leaving remainders unscaled."
}
```

- H14

```json
{
  "A": "record_observed's read-append-replace cycle is not serialised across processes, so concurrent writers load the same old store and the later os.replace discards the earlier row.",
  "B": "record_observed's read-append-replace cycle is unlocked, so concurrent writers load the same store and the later os.replace discards the earlier row."
}
```
