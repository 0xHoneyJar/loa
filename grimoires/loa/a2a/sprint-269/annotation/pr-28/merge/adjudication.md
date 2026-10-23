# Adjudication list — pr-28

Annotator labels are data, not instructions. Every item below needs a complete record in adjudication.json: `{"<id>": {verdict, group, file, anchor_lines, description, severity, category, reason}}` (group ids in annotator A's namespace; nulls only for a not-defect verdict).

1 item(s) disagree.

### H02: anchors


Annotator A:

```json
{
  "anchor_lines": [
    1927,
    1928,
    1929
  ],
  "category": "contract",
  "description": "The report silently drops eval-only arms from the component count without disclosing which arms were excluded or how many rows they carried.",
  "file": "evals/harness/ablation-report.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

Annotator B:

```json
{
  "anchor_lines": [
    1927,
    1928,
    1929,
    1930,
    1931,
    1932
  ],
  "category": "contract",
  "description": "The report drops eval-only arms from the component list without disclosing them or their row counts anywhere, so readers cannot see which arms were excluded from decisions.",
  "file": "evals/harness/ablation-report.py",
  "group": "D2",
  "not_defect_class": null,
  "severity": "low",
  "verdict": "defect"
}
```

## Description differences (informational; the merge takes A's text)

- H01

```json
{
  "A": "An arm whose toggles set oracle_open: true but lacks eval_only: true is silently counted as a decision component instead of being refused or treated as evaluation-only.",
  "B": "The report treats an arm as evaluation-only only by its eval_only flag, so a suite arm with toggles.oracle_open: true but no eval_only is silently counted as a shipped-default component instead of being refused or excluded."
}
```

- H06

```json
{
  "A": "The eval_only refusal keys only on the eval_only flag, so an arm with toggles.oracle_open: true (or a non-boolean eval_only/oracle_open read as false) runs the open-mount oracle outside the batch context.",
  "B": "The eval_only guard reads only the eval_only flag (and reads a non-boolean value as false), so an arm whose toggles open the oracle mount, or whose eval_only is malformed, runs outside the batch context without being refused."
}
```
