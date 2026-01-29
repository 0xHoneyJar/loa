#!/usr/bin/env bash
# .claude/scripts/memory-admin.sh
#
# Memory Administration CLI for Loa Memory Stack
# Manages vector database, memories, and embeddings
#
# Usage:
#   memory-admin.sh init              Initialize database
#   memory-admin.sh add <content> --type TYPE [--source SOURCE]
#   memory-admin.sh list [--type TYPE] [--limit N]
#   memory-admin.sh search <query> [--top-k N] [--threshold T]
#   memory-admin.sh delete <id>
#   memory-admin.sh stats
#   memory-admin.sh export [--format json|csv]
#   memory-admin.sh import <file.json>
#   memory-admin.sh prune [--older-than DAYS] [--min-matches N] [--dry-run]

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOA_DIR="${PROJECT_ROOT}/.loa"
DB_FILE="${LOA_DIR}/memory.db"
EMBED_SCRIPT="${PROJECT_ROOT}/.claude/hooks/memory-utils/embed.py"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Python interpreter - prefer venv if available
if [[ -x "${LOA_DIR}/venv/bin/python3" ]]; then
    PYTHON="${LOA_DIR}/venv/bin/python3"
else
    PYTHON="python3"
fi

# Memory types
VALID_TYPES=("gotcha" "pattern" "decision" "learning")

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

ensure_db_exists() {
    if [[ ! -f "$DB_FILE" ]]; then
        log_error "Database not initialized. Run: memory-admin.sh init"
        exit 1
    fi
}

validate_type() {
    local type="$1"
    for valid in "${VALID_TYPES[@]}"; do
        if [[ "$type" == "$valid" ]]; then
            return 0
        fi
    done
    log_error "Invalid memory type: $type"
    log_error "Valid types: ${VALID_TYPES[*]}"
    exit 1
}

sanitize_content() {
    local content="$1"
    local max_length=2000

    # Truncate if too long
    if [[ ${#content} -gt $max_length ]]; then
        content="${content:0:$max_length}"
        log_warn "Content truncated to $max_length characters"
    fi

    # MED-001 fix: Comprehensive input sanitization
    # Remove null bytes
    content=$(printf '%s' "$content" | tr -d '\0')

    # Normalize line endings (CRLF -> LF)
    content=$(printf '%s' "$content" | tr '\r' '\n')

    # Remove control characters except newline, tab (ASCII 0-8, 11-12, 14-31)
    content=$(printf '%s' "$content" | tr -d '\001-\010\013\014\016-\037')

    # Remove ANSI escape sequences
    content=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

    echo "$content"
}

# Sanitize source field (file path or URL)
sanitize_source() {
    local source="$1"

    # Empty source is valid
    if [[ -z "$source" ]]; then
        echo ""
        return
    fi

    # Remove control characters
    source=$(printf '%s' "$source" | tr -d '\0-\037')

    # Limit length
    if [[ ${#source} -gt 500 ]]; then
        source="${source:0:500}"
    fi

    echo "$source"
}

generate_embedding() {
    local text="$1"

    if [[ ! -f "$EMBED_SCRIPT" ]]; then
        log_error "Embedding script not found: $EMBED_SCRIPT"
        exit 1
    fi

    # Check if Python and sentence-transformers are available
    local check_result
    check_result=$("$PYTHON" "$EMBED_SCRIPT" --check 2>/dev/null || echo '{"available": false}')

    if ! echo "$check_result" | jq -e '.available' >/dev/null 2>&1; then
        log_error "Embedding service not available"
        log_error "Install: pip install sentence-transformers"
        exit 1
    fi

    # Generate embedding
    echo "$text" | "$PYTHON" "$EMBED_SCRIPT"
}

# =============================================================================
# Database Schema
# =============================================================================

create_schema() {
    sqlite3 "$DB_FILE" <<'EOF'
-- Core memory storage
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    memory_type TEXT NOT NULL CHECK (memory_type IN ('gotcha', 'pattern', 'decision', 'learning')),
    source TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_matched_at TEXT,
    match_count INTEGER DEFAULT 0
);

-- Embeddings storage (JSON array of floats)
-- Using JSON instead of sqlite-vss for portability
CREATE TABLE IF NOT EXISTS memory_embeddings (
    memory_id INTEGER PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
    embedding TEXT NOT NULL,
    dimension INTEGER NOT NULL DEFAULT 384
);

-- Query hash cache for deduplication
CREATE TABLE IF NOT EXISTS query_cache (
    hash TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session_id TEXT
);

-- Search history for analytics
CREATE TABLE IF NOT EXISTS search_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query_hash TEXT NOT NULL,
    query_preview TEXT,
    result_count INTEGER,
    top_score REAL,
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source);
CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at);
CREATE INDEX IF NOT EXISTS idx_query_cache_timestamp ON query_cache(timestamp);

-- Enable foreign keys
PRAGMA foreign_keys = ON;
EOF
}

# =============================================================================
# Commands
# =============================================================================

cmd_init() {
    log_info "Initializing Loa Memory Stack database..."

    # Create directory if needed
    mkdir -p "$LOA_DIR"

    # Create or update schema
    create_schema

    # Verify
    if [[ -f "$DB_FILE" ]]; then
        local table_count
        table_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
        log_success "Database initialized at $DB_FILE"
        log_info "Tables created: $table_count"
    else
        log_error "Failed to create database"
        exit 1
    fi
}

cmd_add() {
    local content=""
    local memory_type=""
    local source=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t)
                memory_type="$2"
                shift 2
                ;;
            --source|-s)
                source="$2"
                shift 2
                ;;
            *)
                if [[ -z "$content" ]]; then
                    content="$1"
                else
                    content="$content $1"
                fi
                shift
                ;;
        esac
    done

    # Validate
    if [[ -z "$content" ]]; then
        log_error "Content is required"
        echo "Usage: memory-admin.sh add <content> --type TYPE [--source SOURCE]"
        exit 1
    fi

    if [[ -z "$memory_type" ]]; then
        log_error "Memory type is required (--type)"
        exit 1
    fi

    validate_type "$memory_type"
    ensure_db_exists

    # Sanitize content and source (MED-001 fix)
    content=$(sanitize_content "$content")
    source=$(sanitize_source "$source")

    # Generate embedding
    log_info "Generating embedding..."
    local embed_result
    embed_result=$(generate_embedding "$content")

    if ! echo "$embed_result" | jq -e '.embedding' >/dev/null 2>&1; then
        log_error "Failed to generate embedding"
        echo "$embed_result" >&2
        exit 1
    fi

    local embedding
    local content_hash
    embedding=$(echo "$embed_result" | jq -c '.embedding')
    content_hash=$(echo "$embed_result" | jq -r '.content_hash')

    # Insert memory using Python for safe parameterized queries (HIGH-001 fix)
    log_info "Storing memory..."
    local memory_id
    memory_id=$("$PYTHON" - "$DB_FILE" "$content" "$content_hash" "$memory_type" "$source" "$embedding" <<'PYTHON_SAFE_INSERT'
import sys
import sqlite3
import json

db_file = sys.argv[1]
content = sys.argv[2]
content_hash = sys.argv[3]
memory_type = sys.argv[4]
source = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
embedding = sys.argv[6] if len(sys.argv) > 6 else "[]"

try:
    conn = sqlite3.connect(db_file)
    cur = conn.cursor()

    # Use parameterized query to prevent SQL injection
    cur.execute("""
        INSERT OR REPLACE INTO memories (content, content_hash, memory_type, source)
        VALUES (?, ?, ?, ?)
    """, (content, content_hash, memory_type, source))

    memory_id = cur.lastrowid

    # Insert embedding with parameterized query
    cur.execute("""
        INSERT OR REPLACE INTO memory_embeddings (memory_id, embedding, dimension)
        VALUES (?, ?, 384)
    """, (memory_id, embedding))

    conn.commit()
    conn.close()

    print(memory_id)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SAFE_INSERT
)

    log_success "Memory added with ID: $memory_id"
    echo "{\"id\": $memory_id, \"content_hash\": \"$content_hash\", \"type\": \"$memory_type\"}"
}

cmd_list() {
    local memory_type=""
    local limit=20

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t)
                memory_type="$2"
                shift 2
                ;;
            --limit|-l)
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    ensure_db_exists

    # Use Python for safe parameterized queries (HIGH-001 fix)
    "$PYTHON" - "$DB_FILE" "$memory_type" "$limit" <<'PYTHON_SAFE_LIST'
import sys
import sqlite3
import json

db_file = sys.argv[1]
memory_type = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20

conn = sqlite3.connect(db_file)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

if memory_type:
    cur.execute("""
        SELECT
            id,
            memory_type as type,
            substr(content, 1, 80) || CASE WHEN length(content) > 80 THEN '...' ELSE '' END as preview,
            source,
            match_count,
            created_at
        FROM memories
        WHERE memory_type = ?
        ORDER BY created_at DESC
        LIMIT ?
    """, (memory_type, limit))
else:
    cur.execute("""
        SELECT
            id,
            memory_type as type,
            substr(content, 1, 80) || CASE WHEN length(content) > 80 THEN '...' ELSE '' END as preview,
            source,
            match_count,
            created_at
        FROM memories
        ORDER BY created_at DESC
        LIMIT ?
    """, (limit,))

rows = [dict(row) for row in cur.fetchall()]
conn.close()
print(json.dumps(rows))
PYTHON_SAFE_LIST
}

cmd_search() {
    local query=""
    local top_k=3
    local threshold=0.35

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --top-k|-k)
                top_k="$2"
                shift 2
                ;;
            --threshold|-t)
                threshold="$2"
                shift 2
                ;;
            *)
                if [[ -z "$query" ]]; then
                    query="$1"
                else
                    query="$query $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$query" ]]; then
        log_error "Query is required"
        echo "Usage: memory-admin.sh search <query> [--top-k N] [--threshold T]"
        exit 1
    fi

    ensure_db_exists

    # Generate query embedding
    log_info "Generating query embedding..." >&2
    local embed_result
    embed_result=$(generate_embedding "$query")

    if ! echo "$embed_result" | jq -e '.embedding' >/dev/null 2>&1; then
        log_error "Failed to generate embedding"
        exit 1
    fi

    local query_embedding
    local query_hash
    query_embedding=$(echo "$embed_result" | jq -c '.embedding')
    query_hash=$(echo "$embed_result" | jq -r '.content_hash')

    # Perform similarity search using Python for cosine similarity
    # (Since we're not using sqlite-vss, we compute similarity in Python)
    "$PYTHON" - "$DB_FILE" "$query_embedding" "$top_k" "$threshold" <<'PYTHON_SCRIPT'
import sys
import sqlite3
import json
import math

def cosine_similarity(vec1, vec2):
    dot_product = sum(a * b for a, b in zip(vec1, vec2))
    magnitude1 = math.sqrt(sum(a * a for a in vec1))
    magnitude2 = math.sqrt(sum(b * b for b in vec2))
    if magnitude1 == 0 or magnitude2 == 0:
        return 0.0
    return dot_product / (magnitude1 * magnitude2)

db_file = sys.argv[1]
query_embedding = json.loads(sys.argv[2])
top_k = int(sys.argv[3])
threshold = float(sys.argv[4])

conn = sqlite3.connect(db_file)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# Get all memories with embeddings
cursor.execute("""
    SELECT m.id, m.content, m.memory_type, m.source, m.match_count, me.embedding
    FROM memories m
    JOIN memory_embeddings me ON m.id = me.memory_id
""")

results = []
for row in cursor.fetchall():
    embedding = json.loads(row['embedding'])
    similarity = cosine_similarity(query_embedding, embedding)

    if similarity >= threshold:
        results.append({
            'id': row['id'],
            'content': row['content'],
            'memory_type': row['memory_type'],
            'source': row['source'],
            'match_count': row['match_count'],
            'score': round(similarity, 4)
        })

# Sort by similarity and limit
results.sort(key=lambda x: x['score'], reverse=True)
results = results[:top_k]

# Update match counts
for r in results:
    cursor.execute("""
        UPDATE memories
        SET match_count = match_count + 1, last_matched_at = datetime('now')
        WHERE id = ?
    """, (r['id'],))

conn.commit()
conn.close()

print(json.dumps(results, indent=2))
PYTHON_SCRIPT

    # Log search to history using safe parameterized query (HIGH-001 fix)
    local query_preview
    query_preview=$(echo "$query" | head -c 50)
    "$PYTHON" - "$DB_FILE" "$query_hash" "$query_preview" <<'PYTHON_LOG_SEARCH'
import sys
import sqlite3

db_file = sys.argv[1]
query_hash = sys.argv[2]
query_preview = sys.argv[3] if len(sys.argv) > 3 else ""

conn = sqlite3.connect(db_file)
cur = conn.cursor()
cur.execute("""
    INSERT INTO search_history (query_hash, query_preview, result_count, top_score)
    VALUES (?, ?, 0, 0)
""", (query_hash, query_preview))
conn.commit()
conn.close()
PYTHON_LOG_SEARCH
}

cmd_delete() {
    local id="$1"

    if [[ -z "$id" ]]; then
        log_error "Memory ID is required"
        echo "Usage: memory-admin.sh delete <id>"
        exit 1
    fi

    # Validate id is numeric (HIGH-001 fix)
    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid memory ID: must be a positive integer"
        exit 1
    fi

    ensure_db_exists

    # Check if exists and delete using safe parameterized query (HIGH-001 fix)
    local result
    result=$("$PYTHON" - "$DB_FILE" "$id" <<'PYTHON_SAFE_DELETE'
import sys
import sqlite3

db_file = sys.argv[1]
memory_id = int(sys.argv[2])

conn = sqlite3.connect(db_file)
cur = conn.cursor()

# Check if exists
cur.execute("SELECT COUNT(*) FROM memories WHERE id = ?", (memory_id,))
exists = cur.fetchone()[0]

if exists == 0:
    print("NOT_FOUND")
else:
    cur.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
    conn.commit()
    print("DELETED")

conn.close()
PYTHON_SAFE_DELETE
)

    if [[ "$result" == "NOT_FOUND" ]]; then
        log_error "Memory with ID $id not found"
        exit 1
    fi

    log_success "Memory $id deleted"
}

cmd_stats() {
    ensure_db_exists

    sqlite3 -json "$DB_FILE" <<'EOF'
SELECT
    (SELECT COUNT(*) FROM memories) as total_memories,
    (SELECT COUNT(*) FROM memories WHERE memory_type = 'gotcha') as gotchas,
    (SELECT COUNT(*) FROM memories WHERE memory_type = 'pattern') as patterns,
    (SELECT COUNT(*) FROM memories WHERE memory_type = 'decision') as decisions,
    (SELECT COUNT(*) FROM memories WHERE memory_type = 'learning') as learnings,
    (SELECT COUNT(*) FROM search_history) as total_searches,
    (SELECT COALESCE(AVG(match_count), 0) FROM memories) as avg_match_count,
    (SELECT COALESCE(SUM(match_count), 0) FROM memories) as total_matches;
EOF
}

cmd_export() {
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format|-f)
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    ensure_db_exists

    case "$format" in
        json)
            sqlite3 -json "$DB_FILE" <<'EOF'
SELECT m.id, m.content, m.content_hash, m.memory_type, m.source,
       m.created_at, m.last_matched_at, m.match_count,
       me.embedding
FROM memories m
LEFT JOIN memory_embeddings me ON m.id = me.memory_id
ORDER BY m.id;
EOF
            ;;
        csv)
            sqlite3 -header -csv "$DB_FILE" <<'EOF'
SELECT id, content, memory_type, source, created_at, match_count
FROM memories
ORDER BY id;
EOF
            ;;
        *)
            log_error "Unknown format: $format (use json or csv)"
            exit 1
            ;;
    esac
}

cmd_import() {
    local file="$1"

    if [[ -z "$file" || ! -f "$file" ]]; then
        log_error "Import file not found: $file"
        echo "Usage: memory-admin.sh import <file.json>"
        exit 1
    fi

    ensure_db_exists

    log_info "Importing memories from $file..."

    local count=0
    while IFS= read -r memory; do
        local content type source
        content=$(echo "$memory" | jq -r '.content // empty')
        type=$(echo "$memory" | jq -r '.memory_type // .type // "learning"')
        source=$(echo "$memory" | jq -r '.source // "import"')

        if [[ -n "$content" ]]; then
            cmd_add "$content" --type "$type" --source "$source" >/dev/null
            ((count++)) || true
        fi
    done < <(jq -c '.[]' "$file")

    log_success "Imported $count memories"
}

cmd_prune() {
    local older_than=""
    local min_matches=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --older-than|-o)
                older_than="$2"
                shift 2
                ;;
            --min-matches|-m)
                min_matches="$2"
                shift 2
                ;;
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    ensure_db_exists

    # Validate numeric inputs (HIGH-001 fix)
    if [[ -n "$older_than" ]] && ! [[ "$older_than" =~ ^[0-9]+$ ]]; then
        log_error "Invalid --older-than value: must be a positive integer"
        exit 1
    fi

    if [[ -n "$min_matches" ]] && ! [[ "$min_matches" =~ ^[0-9]+$ ]]; then
        log_error "Invalid --min-matches value: must be a positive integer"
        exit 1
    fi

    if [[ -z "$older_than" && -z "$min_matches" ]]; then
        log_error "At least one condition required: --older-than DAYS or --min-matches N"
        exit 1
    fi

    # Use Python for safe parameterized prune (HIGH-001 fix)
    local result
    result=$("$PYTHON" - "$DB_FILE" "${older_than:-0}" "${min_matches:--1}" "$dry_run" <<'PYTHON_SAFE_PRUNE'
import sys
import sqlite3
import json

db_file = sys.argv[1]
older_than = int(sys.argv[2]) if sys.argv[2] != "0" else None
min_matches = int(sys.argv[3]) if sys.argv[3] != "-1" else None
dry_run = sys.argv[4] == "true"

conn = sqlite3.connect(db_file)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

# Build conditions dynamically but safely
conditions = []
params = []

if older_than is not None:
    conditions.append("created_at < datetime('now', ? || ' days')")
    params.append(f"-{older_than}")

if min_matches is not None:
    conditions.append("match_count < ?")
    params.append(min_matches)

where_clause = " AND ".join(conditions)

# Count candidates
cur.execute(f"SELECT COUNT(*) FROM memories WHERE {where_clause}", params)
count = cur.fetchone()[0]

if count == 0:
    print(json.dumps({"action": "none", "count": 0}))
elif dry_run:
    cur.execute(f"""
        SELECT id, memory_type, substr(content, 1, 50) as preview, match_count, created_at
        FROM memories
        WHERE {where_clause}
        ORDER BY created_at
    """, params)
    rows = [dict(row) for row in cur.fetchall()]
    print(json.dumps({"action": "dry_run", "count": count, "memories": rows}))
else:
    cur.execute(f"DELETE FROM memories WHERE {where_clause}", params)
    conn.commit()
    print(json.dumps({"action": "deleted", "count": count}))

conn.close()
PYTHON_SAFE_PRUNE
)

    local action count
    action=$(echo "$result" | jq -r '.action')
    count=$(echo "$result" | jq -r '.count')

    case "$action" in
        none)
            log_info "No memories match prune criteria"
            ;;
        dry_run)
            log_info "[DRY RUN] Would prune $count memories:"
            echo "$result" | jq '.memories'
            ;;
        deleted)
            log_success "Pruned $count memories"
            ;;
    esac
}

cmd_help() {
    cat <<'EOF'
Loa Memory Stack - Memory Administration CLI

Usage:
  memory-admin.sh <command> [options]

Commands:
  init                          Initialize database
  add <content> --type TYPE     Add a memory (types: gotcha, pattern, decision, learning)
  list [--type TYPE]            List memories
  search <query>                Search memories by similarity
  delete <id>                   Delete a memory
  stats                         Show statistics
  export [--format json|csv]    Export memories
  import <file.json>            Import memories from JSON
  prune [options]               Remove stale memories

Options for 'add':
  --type, -t TYPE               Memory type (required)
  --source, -s SOURCE           Source attribution

Options for 'list':
  --type, -t TYPE               Filter by type
  --limit, -l N                 Limit results (default: 20)

Options for 'search':
  --top-k, -k N                 Number of results (default: 3)
  --threshold, -t T             Similarity threshold (default: 0.35)

Options for 'prune':
  --older-than, -o DAYS         Prune memories older than N days
  --min-matches, -m N           Prune memories with fewer than N matches
  --dry-run, -n                 Show what would be pruned

Examples:
  memory-admin.sh init
  memory-admin.sh add "Use absolute paths in settings.json" --type gotcha --source "debugging"
  memory-admin.sh search "settings path expansion"
  memory-admin.sh prune --older-than 90 --min-matches 2 --dry-run
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            cmd_init "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        stats)
            cmd_stats "$@"
            ;;
        export)
            cmd_export "$@"
            ;;
        import)
            cmd_import "$@"
            ;;
        prune)
            cmd_prune "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
