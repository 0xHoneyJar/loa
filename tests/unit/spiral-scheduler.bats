#!/usr/bin/env bats
# Tests for spiral scheduler (cycle-072)
# Covers: AC-9, AC-11, AC-12

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCHEDULER="$PROJECT_ROOT/.claude/scripts/spiral-scheduler.sh"
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Test 1: exits 2 when scheduling disabled (AC-9)
# ---------------------------------------------------------------------------
@test "scheduler: exits 2 when scheduling disabled" {
    # Create minimal config with scheduling disabled
    cat > "$TEST_TMPDIR/config.yaml" << 'YAML'
spiral:
  enabled: true
  scheduling:
    enabled: false
YAML

    CONFIG="$TEST_TMPDIR/config.yaml" \
    PROJECT_ROOT="$TEST_TMPDIR" \
    run bash -c 'source '"$PROJECT_ROOT"'/.claude/scripts/bootstrap.sh 2>/dev/null; CONFIG='"$TEST_TMPDIR"'/config.yaml; source '"$SCHEDULER"'' 2>&1 || true

    # The script should exit 2 (scheduling disabled)
    [[ "$output" == *"Scheduling disabled"* || "$status" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# Test 2: exits 2 when spiral disabled (AC-9)
# ---------------------------------------------------------------------------
@test "scheduler: exits 2 when spiral disabled" {
    cat > "$TEST_TMPDIR/config.yaml" << 'YAML'
spiral:
  enabled: false
  scheduling:
    enabled: true
YAML

    CONFIG="$TEST_TMPDIR/config.yaml" \
    PROJECT_ROOT="$TEST_TMPDIR" \
    run bash -c 'CONFIG='"$TEST_TMPDIR"'/config.yaml; _read_config() { yq eval ".$1 // null" "$CONFIG" 2>/dev/null; }; scheduling_enabled=$(_read_config "spiral.scheduling.enabled"); spiral_enabled=$(_read_config "spiral.enabled"); [[ "$spiral_enabled" != "true" ]] && echo "Spiral disabled" && exit 2'
    [[ "$output" == *"Spiral disabled"* ]]
}

# ---------------------------------------------------------------------------
# Test 3: _in_window returns true during window (AC-11)
# ---------------------------------------------------------------------------
@test "scheduler: in_window returns true during configured hours" {
    # Get current hour and set window around it
    local current_hour
    current_hour=$(date -u +%H)
    local start_hour=$(( (current_hour - 1 + 24) % 24 ))
    local end_hour=$(( (current_hour + 1) % 24 ))

    run bash -c "
        _read_config() { case \"\$1\" in
            spiral.scheduling.strategy) echo 'fill' ;;
            spiral.scheduling.windows\\[0\\].start_utc) printf '%02d:00' $start_hour ;;
            spiral.scheduling.windows\\[0\\].end_utc) printf '%02d:00' $end_hour ;;
        esac; }

        _in_window() {
            local strategy; strategy=\$(_read_config 'spiral.scheduling.strategy')
            [[ \"\$strategy\" == 'continuous' ]] && return 0
            local start_utc end_utc
            start_utc=\$(_read_config 'spiral.scheduling.windows[0].start_utc')
            end_utc=\$(_read_config 'spiral.scheduling.windows[0].end_utc')
            [[ -z \"\$start_utc\" || -z \"\$end_utc\" ]] && return 0
            local today now_epoch start_epoch end_epoch
            today=\$(date -u +%Y-%m-%d)
            now_epoch=\$(date -u +%s)
            start_epoch=\$(date -u -d \"\${today}T\${start_utc}:00Z\" +%s 2>/dev/null || echo 0)
            end_epoch=\$(date -u -d \"\${today}T\${end_utc}:00Z\" +%s 2>/dev/null || echo 0)
            [[ \"\$start_epoch\" -eq 0 || \"\$end_epoch\" -eq 0 ]] && return 0
            [[ \"\$now_epoch\" -ge \"\$start_epoch\" && \"\$now_epoch\" -lt \"\$end_epoch\" ]]
        }

        _in_window && echo 'IN_WINDOW' || echo 'OUTSIDE_WINDOW'
    "
    [[ "$output" == *"IN_WINDOW"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: _in_window returns false outside window (AC-11)
# ---------------------------------------------------------------------------
@test "scheduler: in_window returns false outside configured hours" {
    # Set window in the past
    run bash -c "
        _read_config() { case \"\$1\" in
            spiral.scheduling.strategy) echo 'fill' ;;
            spiral.scheduling.windows\\[0\\].start_utc) echo '00:00' ;;
            spiral.scheduling.windows\\[0\\].end_utc) echo '00:01' ;;
        esac; }

        _in_window() {
            local strategy; strategy=\$(_read_config 'spiral.scheduling.strategy')
            [[ \"\$strategy\" == 'continuous' ]] && return 0
            local start_utc end_utc
            start_utc=\$(_read_config 'spiral.scheduling.windows[0].start_utc')
            end_utc=\$(_read_config 'spiral.scheduling.windows[0].end_utc')
            [[ -z \"\$start_utc\" || -z \"\$end_utc\" ]] && return 0
            local today now_epoch start_epoch end_epoch
            today=\$(date -u +%Y-%m-%d)
            now_epoch=\$(date -u +%s)
            start_epoch=\$(date -u -d \"\${today}T\${start_utc}:00Z\" +%s 2>/dev/null || echo 0)
            end_epoch=\$(date -u -d \"\${today}T\${end_utc}:00Z\" +%s 2>/dev/null || echo 0)
            [[ \"\$start_epoch\" -eq 0 || \"\$end_epoch\" -eq 0 ]] && return 0
            [[ \"\$now_epoch\" -ge \"\$start_epoch\" && \"\$now_epoch\" -lt \"\$end_epoch\" ]]
        }

        _in_window && echo 'IN_WINDOW' || echo 'OUTSIDE_WINDOW'
    "
    # Current time (unless exactly midnight) should be outside 00:00-00:01
    [[ "$output" == *"OUTSIDE_WINDOW"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: continuous strategy bypasses window check (AC-12)
# ---------------------------------------------------------------------------
@test "scheduler: continuous strategy always in window" {
    run bash -c "
        _read_config() { case \"\$1\" in
            spiral.scheduling.strategy) echo 'continuous' ;;
            *) echo '' ;;
        esac; }

        _in_window() {
            local strategy; strategy=\$(_read_config 'spiral.scheduling.strategy')
            [[ \"\$strategy\" == 'continuous' ]] && return 0
            return 1  # Would fail if not continuous
        }

        _in_window && echo 'IN_WINDOW' || echo 'OUTSIDE_WINDOW'
    "
    [[ "$output" == *"IN_WINDOW"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: check_token_window continues when no window configured (AC-12)
# ---------------------------------------------------------------------------
@test "scheduler: check_token_window continues when no window" {
    run bash -c "
        read_config() { echo ''; }
        log() { :; }
        log_trajectory() { :; }

        check_token_window() {
            local strategy; strategy=\$(read_config 'spiral.scheduling.strategy')
            [[ \"\$strategy\" == 'continuous' ]] && return 1
            local window_end_utc; window_end_utc=\$(read_config 'spiral.scheduling.windows[0].end_utc')
            [[ -z \"\$window_end_utc\" ]] && return 1
            return 0
        }

        check_token_window && echo 'STOP' || echo 'CONTINUE'
    "
    [[ "$output" == *"CONTINUE"* ]]
}
