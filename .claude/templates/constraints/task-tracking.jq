# task-tracking.jq
# Renders task tracking hierarchy table for CLAUDE.loa.md
#
# Input: array of constraint objects filtered for task_tracking_hierarchy section
# Output: markdown table rows with Tool, Use For, Do NOT Use For columns
#
# Rendering contract:
#   text_variants["claude-loa-md"] preferred (contains pre-formatted "tool | use | dont" string)
#   Fallback: construct from constraint fields
#
# The task tracking table has a unique 3-column format different from NEVER/ALWAYS tables.

def escape_pipes: gsub("\\|"; "\\|");

.[]
| if .text_variants and .text_variants["claude-loa-md"] then
    # text_variants contains the pre-formatted row content: "tool | use_for | dont_use_for"
    .text_variants["claude-loa-md"] | split(" | ") |
    if length == 3 then
      "| \(.[0]) | \(.[1]) | \(.[2]) |"
    else
      # Fallback: use as single value
      "| \(.[0] // "") | \(.[1] // "") | \(.[2] // "") |"
    end
  else
    "| \(.name) | \(.text) | — |"
  end
