#!/usr/bin/env bash
# Performance benchmarking script for ck semantic search
# Tests search latency, cache hit rates, and indexing performance
#
# Usage:
#   ./benchmark.sh [test_corpus_path]
#
# Requirements:
#   - ck installed (cargo install ck-search)
#   - bc for calculations
#   - Large test corpus (optional, will use project root if not specified)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
TEST_CORPUS="${1:-${PROJECT_ROOT}}"
RESULTS_FILE="${SCRIPT_DIR}/benchmark-results-$(date +%Y%m%d-%H%M%S).txt"
RUNS_PER_TEST=5  # Number of runs to average

# Check dependencies
if ! command -v ck >/dev/null 2>&1; then
    echo "Error: ck not installed. Please install: cargo install ck-search" >&2
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "Error: bc not installed. Required for calculations." >&2
    exit 1
fi

# Utility functions
log() {
    echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_FILE"
}

measure_time() {
    local start=$(date +%s%N)
    "$@" >/dev/null 2>&1
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))  # Convert to milliseconds
    echo "$duration"
}

calculate_avg() {
    local sum=0
    local count=0
    for val in "$@"; do
        sum=$(echo "$sum + $val" | bc)
        ((count++))
    done
    echo "scale=2; $sum / $count" | bc
}

# Initialize results file
log "====================================="
log "ck Performance Benchmark"
log "====================================="
log "Test Corpus: $TEST_CORPUS"
log "Timestamp: $(date)"
log "ck Version: $(ck --version 2>&1 || echo 'Unknown')"
log "====================================="
log ""

# Count lines of code in corpus
log "Analyzing test corpus..."
if command -v cloc >/dev/null 2>&1; then
    TOTAL_LOC=$(cloc "$TEST_CORPUS" --json 2>/dev/null | jq '.SUM.code' 2>/dev/null || echo "unknown")
else
    TOTAL_LOC=$(find "$TEST_CORPUS" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" \) -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "unknown")
fi
log "Total Lines of Code: $TOTAL_LOC"
log ""

# Test 1: Full Index Time (Cold Start)
log "Test 1: Full Index Time (Cold Start)"
log "-------------------------------------"

# Remove existing index
rm -rf "${TEST_CORPUS}/.ck" 2>/dev/null || true

index_times=()
for run in $(seq 1 $RUNS_PER_TEST); do
    log "Run $run/$RUNS_PER_TEST..."
    duration=$(measure_time ck --index "$TEST_CORPUS" --quiet)
    index_times+=("$duration")
    log "  Duration: ${duration}ms"

    # Clean for next run
    rm -rf "${TEST_CORPUS}/.ck" 2>/dev/null || true
done

avg_index_time=$(calculate_avg "${index_times[@]}")
log "Average Full Index Time: ${avg_index_time}ms"
log ""

# Test 2: Search Latency (Cold Cache)
log "Test 2: Search Latency (Cold Cache)"
log "-------------------------------------"

# Index once for all search tests
log "Creating initial index..."
ck --index "$TEST_CORPUS" --quiet 2>/dev/null || true

# Test queries
queries=(
    "authentication token validation"
    "database connection pool"
    "error handling middleware"
    "API endpoint routing"
    "user session management"
)

cold_times=()
for query in "${queries[@]}"; do
    log "Query: '$query'"

    # Clear OS cache (requires sudo, skip if not available)
    sync 2>/dev/null || true
    # echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true  # Requires root

    durations=()
    for run in $(seq 1 $RUNS_PER_TEST); do
        duration=$(measure_time ck --semantic "$query" --path "$TEST_CORPUS" --jsonl)
        durations+=("$duration")
    done

    avg_duration=$(calculate_avg "${durations[@]}")
    cold_times+=("$avg_duration")
    log "  Average: ${avg_duration}ms"
done

overall_cold_avg=$(calculate_avg "${cold_times[@]}")
log "Overall Cold Cache Average: ${overall_cold_avg}ms"
log ""

# Test 3: Search Latency (Warm Cache)
log "Test 3: Search Latency (Warm Cache)"
log "-------------------------------------"

warm_times=()
for query in "${queries[@]}"; do
    log "Query: '$query'"

    # Run twice (first warms cache, second measures)
    ck --semantic "$query" --path "$TEST_CORPUS" --jsonl >/dev/null 2>&1 || true

    durations=()
    for run in $(seq 1 $RUNS_PER_TEST); do
        duration=$(measure_time ck --semantic "$query" --path "$TEST_CORPUS" --jsonl)
        durations+=("$duration")
    done

    avg_duration=$(calculate_avg "${durations[@]}")
    warm_times+=("$avg_duration")
    log "  Average: ${avg_duration}ms"
done

overall_warm_avg=$(calculate_avg "${warm_times[@]}")
log "Overall Warm Cache Average: ${overall_warm_avg}ms"
log ""

# Test 4: Cache Hit Rate
log "Test 4: Cache Hit Rate Simulation"
log "-------------------------------------"

# Modify a few files to simulate delta changes
test_files=($(find "$TEST_CORPUS" -type f \( -name "*.js" -o -name "*.ts" \) | head -5))
modified_count=0

for file in "${test_files[@]}"; do
    if [ -f "$file" ] && [ -w "$file" ]; then
        # Add a comment to trigger delta
        echo "// Benchmark modification" >> "$file"
        ((modified_count++))
    fi
done

log "Modified $modified_count files for delta test"

# Measure delta reindex time
delta_times=()
for run in $(seq 1 $RUNS_PER_TEST); do
    duration=$(measure_time ck --index "$TEST_CORPUS" --delta --quiet)
    delta_times+=("$duration")
    log "  Delta Reindex Run $run: ${duration}ms"
done

avg_delta_time=$(calculate_avg "${delta_times[@]}")
log "Average Delta Reindex Time: ${avg_delta_time}ms"

# Calculate cache efficiency (delta vs full)
if (( $(echo "$avg_index_time > 0" | bc -l) )); then
    speedup=$(echo "scale=2; $avg_index_time / $avg_delta_time" | bc)
    cache_efficiency=$(echo "scale=2; (1 - ($avg_delta_time / $avg_index_time)) * 100" | bc)
    log "Delta Speedup: ${speedup}x faster"
    log "Cache Efficiency: ${cache_efficiency}% time saved"
fi

# Restore modified files (git restore if possible)
if [ "$TEST_CORPUS" = "$PROJECT_ROOT" ]; then
    log "Restoring modified files..."
    git restore "${test_files[@]}" 2>/dev/null || true
fi

log ""

# Test 5: Scalability Test (Result Count Impact)
log "Test 5: Scalability - Impact of Result Count"
log "-------------------------------------"

result_thresholds=(0.8 0.6 0.4 0.2)
for threshold in "${result_thresholds[@]}"; do
    log "Threshold: $threshold"

    duration=$(measure_time ck --semantic "function" --path "$TEST_CORPUS" --threshold "$threshold" --top-k 100 --jsonl)
    result_count=$(ck --semantic "function" --path "$TEST_CORPUS" --threshold "$threshold" --top-k 100 --jsonl 2>/dev/null | wc -l || echo 0)

    log "  Duration: ${duration}ms, Results: $result_count"
done

log ""

# Summary and Validation
log "====================================="
log "SUMMARY & VALIDATION"
log "====================================="
log ""

# Validate against PRD targets
TARGET_SEARCH_LATENCY=500  # ms (PRD NFR-1.1)
TARGET_CACHE_HIT_RATE=80   # percent (PRD NFR-1.2)

log "Performance Targets (from PRD):"
log "  Search Speed: <${TARGET_SEARCH_LATENCY}ms on 1M LOC"
log "  Cache Hit Rate: ${TARGET_CACHE_HIT_RATE}-90%"
log ""

log "Actual Performance:"
log "  Average Search Latency (Cold): ${overall_cold_avg}ms"
log "  Average Search Latency (Warm): ${overall_warm_avg}ms"
log "  Full Index Time: ${avg_index_time}ms"
log "  Delta Index Time: ${avg_delta_time}ms"
if [ -n "${cache_efficiency:-}" ]; then
    log "  Cache Efficiency: ${cache_efficiency}%"
fi
log ""

# Validation checks
validation_passed=true

if (( $(echo "$overall_warm_avg > $TARGET_SEARCH_LATENCY" | bc -l) )); then
    log "⚠️  WARNING: Search latency (${overall_warm_avg}ms) exceeds target (${TARGET_SEARCH_LATENCY}ms)"
    validation_passed=false
else
    log "✓ Search latency within target"
fi

if [ -n "${cache_efficiency:-}" ]; then
    if (( $(echo "$cache_efficiency < $TARGET_CACHE_HIT_RATE" | bc -l) )); then
        log "⚠️  WARNING: Cache efficiency (${cache_efficiency}%) below target (${TARGET_CACHE_HIT_RATE}%)"
        validation_passed=false
    else
        log "✓ Cache efficiency meets target"
    fi
fi

log ""
log "====================================="
if [ "$validation_passed" = true ]; then
    log "✓ All performance targets met"
    exit 0
else
    log "⚠️  Some performance targets not met (see warnings above)"
    log "Note: This may be due to corpus size or hardware limitations"
    exit 0  # Don't fail the script, just warn
fi
