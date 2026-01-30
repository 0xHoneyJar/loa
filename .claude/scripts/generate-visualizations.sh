#!/bin/bash
# =============================================================================
# generate-visualizations.sh - Mermaid Visualization Generator
# =============================================================================
# Sprint 16: Generate visual diagrams for compound learning outputs
# Goal Contribution: PRD FR-10 (Visualization)
#
# Integrates with visual_communication protocol (see .claude/protocols/visual-communication.md)
# Uses mermaid-url.sh for secure preview URL generation
#
# Usage:
#   ./generate-visualizations.sh [type] [options]
#
# Types:
#   pattern-flowchart   Pattern detection flow
#   sprint-sequence     Sprint session timeline
#   learning-map        Task to learnings relationships
#   skill-er            Skill relationships (ER diagram)
#
# Options:
#   --output DIR        Output directory (default: grimoires/loa/diagrams)
#   --format FORMAT     Output format: mermaid|ascii
#   --with-url          Generate Beautiful Mermaid preview URLs
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/grimoires/loa/diagrams"
PATTERNS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/patterns.json"
LEARNINGS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json"
MERMAID_URL_SCRIPT="${SCRIPT_DIR}/mermaid-url.sh"

DIAGRAM_TYPE="pattern-flowchart"
FORMAT="mermaid"
WITH_URL=false

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  [[ $# -gt 0 && ! "$1" =~ ^-- ]] && { DIAGRAM_TYPE="$1"; shift; }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output) OUTPUT_DIR="$2"; shift 2 ;;
      --format) FORMAT="$2"; shift 2 ;;
      --with-url) WITH_URL=true; shift ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

# Generate preview URL using mermaid-url.sh (visual_communication protocol)
generate_preview_url() {
  local mermaid_content="$1"

  if [[ ! -x "$MERMAID_URL_SCRIPT" ]]; then
    echo "[WARN] mermaid-url.sh not found, skipping URL generation" >&2
    return 1
  fi

  # Use our security-hardened URL generator
  echo "$mermaid_content" | "$MERMAID_URL_SCRIPT" --stdin 2>/dev/null || {
    echo "[WARN] URL generation failed (diagram may exceed size limit)" >&2
    return 1
  }
}

# Generate pattern flowchart
generate_pattern_flowchart() {
  if [[ ! -f "$PATTERNS_FILE" ]]; then
    echo "graph TD"
    echo "    NoData[No patterns detected yet]"
    return
  fi
  
  echo "graph TD"
  echo "    subgraph \"Pattern Detection Flow\""
  
  local patterns
  patterns=$(jq '.patterns // []' "$PATTERNS_FILE")
  
  local count
  count=$(echo "$patterns" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "        NoPatterns[No patterns detected]"
  else
    echo "$patterns" | jq -r '
      to_entries | .[] |
      "        P\(.key)[\"" + .value.signature[0:30] + "\"]"
    '
    
    # Add confidence styling
    echo ""
    echo "$patterns" | jq -r '
      to_entries | .[] |
      if .value.confidence >= 0.8 then
        "    style P\(.key) fill:#10b981,stroke:#059669"
      elif .value.confidence >= 0.5 then
        "    style P\(.key) fill:#fbbf24,stroke:#d97706"
      else
        "    style P\(.key) fill:#f4f4f5,stroke:#a1a1aa"
      end
    '
  fi
  
  echo "    end"
}

# Generate sprint sequence diagram
generate_sprint_sequence() {
  echo "sequenceDiagram"
  echo "    participant D as Developer"
  echo "    participant A as Agent"
  echo "    participant S as Skills"
  echo "    participant L as Learnings"
  echo ""
  echo "    Note over D,L: Compound Learning Flow"
  echo ""
  echo "    D->>A: Start Development Cycle"
  echo "    A->>A: Implement Tasks"
  echo "    A-->>S: Extract Skills"
  echo "    S->>L: Update Registry"
  echo "    A->>D: Cycle Complete"
  echo ""
  echo "    Note over D,L: /compound Review"
  echo "    A->>L: Batch Retrospective"
  echo "    L->>S: Quality Gates"
  echo "    S-->>D: Extracted Learnings"
}

# Generate learning map
generate_learning_map() {
  echo "graph LR"
  echo "    subgraph \"Current Task\""
  echo "        T[Task Context]"
  echo "    end"
  echo "    subgraph \"Relevant Learnings\""
  
  if [[ -f "$LEARNINGS_FILE" ]]; then
    local learnings
    learnings=$(jq '.learnings[0:5]' "$LEARNINGS_FILE" 2>/dev/null || echo "[]")
    
    echo "$learnings" | jq -r '
      to_entries | .[] |
      "        L\(.key)[\"" + .value.id[0:25] + "\"]"
    '
    
    echo "    end"
    echo ""
    
    # Add connections and styling
    echo "$learnings" | jq -r '
      to_entries | .[] |
      "    T -.->|applies| L\(.key)"
    '
    
    echo ""
    echo "$learnings" | jq -r '
      to_entries | .[] |
      if .value.effectiveness_score >= 80 then
        "    style L\(.key) fill:#10b981,stroke:#059669"
      elif .value.effectiveness_score >= 50 then
        "    style L\(.key) fill:#fbbf24,stroke:#d97706"
      else
        "    style L\(.key) fill:#f4f4f5,stroke:#a1a1aa"
      end
    '
  else
    echo "        NoLearnings[No learnings yet]"
    echo "    end"
  fi
  
  echo "    style T fill:#3b82f6,stroke:#1d4ed8,color:#fff"
}

# Generate skill ER diagram
generate_skill_er() {
  cat << 'EOF'
erDiagram
    SKILL {
        string id PK
        string name
        int effectiveness
        date created
    }
    PATTERN {
        string id PK
        string signature
        int occurrences
        float confidence
    }
    SESSION {
        string id PK
        date timestamp
        string agent
    }
    APPLICATION {
        string id PK
        string skill_id FK
        string task_id
        string type
    }
    
    SKILL ||--o{ PATTERN : extracted-from
    PATTERN }|--o{ SESSION : detected-in
    SKILL ||--o{ APPLICATION : applied-in
EOF
}

# Generate ASCII fallback
generate_ascii() {
  cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPOUND LEARNING SYSTEM                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│  │  Trajectory │────▶│   Pattern   │────▶│   Skills    │           │
│  │    Logs     │     │  Detector   │     │  Generated  │           │
│  └─────────────┘     └─────────────┘     └─────────────┘           │
│                             │                   │                   │
│                             ▼                   ▼                   │
│                      ┌─────────────┐     ┌─────────────┐           │
│                      │  Clusters   │     │  Learnings  │           │
│                      │  (Similar)  │     │  Registry   │           │
│                      └─────────────┘     └─────────────┘           │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  FEEDBACK LOOP: Apply → Track → Verify → Reinforce/Demote      ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
EOF
}

main() {
  parse_args "$@"

  mkdir -p "$OUTPUT_DIR"

  local output=""
  local filename=""

  case "$DIAGRAM_TYPE" in
    pattern-flowchart)
      output=$(generate_pattern_flowchart)
      filename="pattern-flowchart.mmd"
      ;;
    sprint-sequence)
      output=$(generate_sprint_sequence)
      filename="sprint-sequence.mmd"
      ;;
    learning-map)
      output=$(generate_learning_map)
      filename="learning-map.mmd"
      ;;
    skill-er)
      output=$(generate_skill_er)
      filename="skill-er.mmd"
      ;;
    ascii)
      output=$(generate_ascii)
      filename="overview.txt"
      ;;
    *)
      echo "[ERROR] Unknown diagram type: $DIAGRAM_TYPE" >&2
      usage
      ;;
  esac

  if [[ "$FORMAT" == "ascii" ]]; then
    generate_ascii
  else
    echo "$output" | tee "${OUTPUT_DIR}/${filename}"
    echo ""
    echo "[INFO] Written to ${OUTPUT_DIR}/${filename}"

    # Generate preview URL if requested (uses visual_communication protocol)
    if [[ "$WITH_URL" == "true" ]]; then
      local preview_url
      if preview_url=$(generate_preview_url "$output"); then
        echo ""
        echo "**Preview**: $preview_url"
      fi
    fi
  fi
}

main "$@"
