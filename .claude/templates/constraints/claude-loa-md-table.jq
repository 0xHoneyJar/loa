# claude-loa-md-table.jq
# Renders constraint rows for NEVER/ALWAYS tables in CLAUDE.loa.md
#
# Input: array of constraint objects filtered by section
# Output: markdown table rows (no header — header is in the target file)
#
# Rendering contract:
#   text_variants["claude-loa-md"] preferred
#   rule_type + " " + text fallback
#
# Pipe characters in field values are escaped to prevent table breakage.

def escape_pipes: gsub("\\|"; "\\|");

.[]
| (
    if .text_variants and .text_variants["claude-loa-md"] then
      .text_variants["claude-loa-md"]
    else
      .rule_type + " " + .text
    end
  ) as $base_rule
| (
    if .construct_yield and .construct_yield.enabled then
      $base_rule + " (" + .construct_yield.yield_text + ")"
    else
      $base_rule
    end
  ) as $rule
| .why as $why
| "| \($rule | escape_pipes) | \($why | escape_pipes) |"
