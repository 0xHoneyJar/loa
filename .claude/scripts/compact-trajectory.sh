#!/usr/bin/env bash
# .claude/scripts/compact-trajectory.sh
#
# Trajectory Log Compaction - Compress old logs to save disk space
#
# Usage:
#   ./compact-trajectory.sh [--dry-run]
#
# Compression Policy:
#   - Compress trajectories older than 30 days to .jsonl.gz
#   - Purge archives older than 365 days
#   - Retention configurable via .loa.config.yaml

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TRAJECTORY_DIR="${PROJECT_ROOT}/loa-grimoire/a2a/trajectory"
ARCHIVE_DIR="${TRAJECTORY_DIR}/archive"

# Default retention policy (days)
RETENTION_DAYS=30
ARCHIVE_DAYS=365
COMPRESSION_LEVEL=6

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE - No files will be modified"
fi

# Load config if available
if [[ -f "${PROJECT_ROOT}/.loa.config.yaml" ]]; then
    if command -v yq >/dev/null 2>/dev/null; then
        RETENTION_DAYS=$(yq eval '.trajectory.retention_days // 30' "${PROJECT_ROOT}/.loa.config.yaml")
        ARCHIVE_DAYS=$(yq eval '.trajectory.archive_days // 365' "${PROJECT_ROOT}/.loa.config.yaml")
        COMPRESSION_LEVEL=$(yq eval '.trajectory.compression_level // 6' "${PROJECT_ROOT}/.loa.config.yaml")
    fi
fi

echo "Trajectory Compaction Policy:"
echo "  Retention: ${RETENTION_DAYS} days"
echo "  Archive: ${ARCHIVE_DAYS} days"
echo "  Compression: level ${COMPRESSION_LEVEL}"
echo ""

# Create archive directory if needed
mkdir -p "${ARCHIVE_DIR}"

# Find files to compress (older than RETENTION_DAYS)
COMPRESS_COUNT=0
PURGE_COUNT=0
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0

echo "=== Phase 1: Compress Old Trajectories ==="
echo ""

while IFS= read -r -d '' file; do
    # Get file modification time
    file_age_days=$(( ($(date +%s) - $(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null)) / 86400 ))
    
    if [[ ${file_age_days} -gt ${RETENTION_DAYS} ]]; then
        file_size=$(stat -c %s "${file}" 2>/dev/null || stat -f %z "${file}" 2>/dev/null)
        TOTAL_SIZE_BEFORE=$((TOTAL_SIZE_BEFORE + file_size))
        
        echo "Compressing: $(basename "${file}") (${file_age_days} days old, $(( file_size / 1024 )) KB)"
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            # Compress with gzip
            gzip -${COMPRESSION_LEVEL} -c "${file}" > "${file}.gz"
            
            # Verify compression successful
            if [[ -f "${file}.gz" ]]; then
                compressed_size=$(stat -c %s "${file}.gz" 2>/dev/null || stat -f %z "${file}.gz" 2>/dev/null)
                TOTAL_SIZE_AFTER=$((TOTAL_SIZE_AFTER + compressed_size))
                
                # Remove original
                rm "${file}"
                
                echo "  → Compressed to $(( compressed_size / 1024 )) KB ($(( (file_size - compressed_size) * 100 / file_size ))% reduction)"
            else
                echo "  ERROR: Compression failed"
            fi
        else
            echo "  [DRY RUN] Would compress to ${file}.gz"
        fi
        
        ((COMPRESS_COUNT++))
    fi
done < <(find "${TRAJECTORY_DIR}" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null || true)

echo ""
echo "Compressed: ${COMPRESS_COUNT} files"
if [[ "${DRY_RUN}" == "false" ]] && [[ ${COMPRESS_COUNT} -gt 0 ]]; then
    echo "Space saved: $(( (TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER) / 1024 )) KB"
fi

echo ""
echo "=== Phase 2: Purge Old Archives ==="
echo ""

# Find compressed archives to purge (older than ARCHIVE_DAYS)
while IFS= read -r -d '' file; do
    file_age_days=$(( ($(date +%s) - $(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null)) / 86400 ))
    
    if [[ ${file_age_days} -gt ${ARCHIVE_DAYS} ]]; then
        file_size=$(stat -c %s "${file}" 2>/dev/null || stat -f %z "${file}" 2>/dev/null)
        
        echo "Purging: $(basename "${file}") (${file_age_days} days old)"
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            rm "${file}"
            echo "  → Deleted (freed $(( file_size / 1024 )) KB)"
        else
            echo "  [DRY RUN] Would delete"
        fi
        
        ((PURGE_COUNT++))
    fi
done < <(find "${TRAJECTORY_DIR}" -name "*.jsonl.gz" -type f -print0 2>/dev/null || true)

echo ""
echo "Purged: ${PURGE_COUNT} archives"

echo ""
echo "=== Summary ==="
echo "  Compressed: ${COMPRESS_COUNT} files"
echo "  Purged: ${PURGE_COUNT} files"

if [[ "${DRY_RUN}" == "false" ]] && [[ ${COMPRESS_COUNT} -gt 0 ]]; then
    echo "  Space saved: $(( (TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER) / 1024 )) KB"
fi

echo ""
echo "Compaction complete."

# To run this script automatically via cron:
# Add to crontab: 0 2 * * * /path/to/.claude/scripts/compact-trajectory.sh
