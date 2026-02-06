# skill-md-constraints.jq
# Renders numbered constraint rules for SKILL.md <constraints> blocks
#
# Input: array of constraint objects filtered by skill name
# Output: numbered markdown list
#
# Rendering contract:
#   text_variants["skill-md"] preferred
#   rule_type + " " + text fallback

[
  .[]
  | (
      if .text_variants and .text_variants["skill-md"] then
        .text_variants["skill-md"]
      else
        .rule_type + " " + .text
      end
    )
] | to_entries[] | "\(.key + 1). \(.value)"
