# protocol-checklist.jq
# Renders checklist table for implementation-compliance.md
#
# Input: array of constraint objects filtered for protocol target,
#        pre-sorted by the generation script in checklist order
# Output: markdown table rows with #, Check, Required?, How to Verify columns
#
# Rendering contract:
#   text_variants["protocol"] contains: "Check ||| Required ||| How to Verify"
#   Fallback: rule_type + " " + text for Check, "ALWAYS" for Required, "" for Verify

[
  .[]
  | (
      if .text_variants and .text_variants["protocol"] then
        .text_variants["protocol"] | split(" ||| ") |
        { check: .[0], required: .[1], verify: .[2] }
      else
        { check: (.rule_type + " " + .text), required: "ALWAYS", verify: "" }
      end
    )
] | to_entries[]
| "| \(.key + 1) | \(.value.check) | \(.value.required) | \(.value.verify) |"
