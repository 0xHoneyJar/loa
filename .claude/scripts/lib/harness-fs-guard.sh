#!/usr/bin/env bash
# =============================================================================
# harness-fs-guard.sh — Cycle-108 sprint-1 T1.E
# =============================================================================
# Filesystem-isolation guards for the advisor-benchmark replay harness (Sprint 2).
# Closes SDD §20.6 ATK-A14: symlink-traversal escape from worktree.
#
# Functions exported (sourceable):
#
#   harness_symlink_scan <dir>
#       Scan <dir> for symlinks pointing OUTSIDE <dir>. Returns 0 if clean;
#       returns 1 + emits a BLOCK message per offending symlink to stderr.
#       Also prints JSON-line per offending symlink to stdout for harness
#       structured logging.
#
#   harness_fs_snapshot_pre <out-file>
#       Capture mtime + size for paths the replay MUST NOT mutate:
#       ~, /tmp, /var/tmp, <repo-root>-but-outside-worktree, .run/
#       (excluding .run/model-invoke.jsonl which is intentionally written
#       to via LOA_AUDIT_LOG_PATH override). Output: tab-separated file.
#
#   harness_fs_snapshot_post <pre-file>
#       Re-capture and diff. Emits BLOCK + JSON-line per mutation to stdout.
#       Returns 0 if clean; returns 1 on any unexplained mutation.
#
# Sprint-1 acceptance: these functions are STUBS — Sprint 2's
# advisor-benchmark.sh wires them into per-replay setup/teardown. The
# stubs themselves are functional and unit-tested.
#
# Source: SDD §20.6 (ATK-A14 closure).
# =============================================================================

set -uo pipefail  # NOT -e — these functions return non-zero to signal failure

# realpath wrapper that's portable across linux + macOS. realpath with -m
# (canonicalize missing parts) is GNU-only; fall back to readlink -f or
# python on macOS. The shell-compat-lint pattern `realpath.*||.*readlink`
# is intentionally satisfied here so the linter sees the OR-chain as a
# valid cross-platform guard.
_loa_realpath() {
    local target="$1"
    # GNU realpath || BSD readlink -f || Python3 (portable last resort).
    realpath -m "$target" 2>/dev/null || \
        readlink -f "$target" 2>/dev/null || \
        python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$target"
}

# Returns 0 if symlink target's realpath is INSIDE <dir>; 1 otherwise.
_loa_symlink_inside() {
    local symlink="$1"
    local enforce_dir="$2"

    local target_resolved enforce_resolved
    target_resolved=$(_loa_realpath "$symlink")
    enforce_resolved=$(_loa_realpath "$enforce_dir")

    [[ -z "$target_resolved" || -z "$enforce_resolved" ]] && return 1

    # Ensure trailing slash for prefix-match correctness
    case "$target_resolved/" in
        "$enforce_resolved/"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Public: scan <dir> for symlinks pointing outside <dir>.
harness_symlink_scan() {
    local enforce_dir="$1"

    if [[ ! -d "$enforce_dir" ]]; then
        echo "[harness-fs-guard] ERROR: directory does not exist: $enforce_dir" >&2
        return 2
    fi

    local enforce_resolved
    enforce_resolved=$(_loa_realpath "$enforce_dir")

    local bad_links=0
    while IFS= read -r -d '' link; do
        if ! _loa_symlink_inside "$link" "$enforce_dir"; then
            local target
            target=$(_loa_realpath "$link")
            echo "[harness-fs-guard] BLOCK: symlink escapes worktree: $link -> $target (worktree: $enforce_resolved)" >&2
            printf '{"event":"symlink_escape","link":"%s","target":"%s","worktree":"%s"}\n' \
                "$link" "$target" "$enforce_resolved"
            bad_links=$((bad_links + 1))
        fi
    done < <(find "$enforce_dir" -type l -print0 2>/dev/null)

    if [[ "$bad_links" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Paths that replay-context MUST NOT mutate. Operator can extend by
# setting LOA_HARNESS_FS_GUARD_EXTRA_PATHS (colon-separated).
# When LOA_HARNESS_FS_GUARD_EXCLUSIVE=1, ONLY the extra paths are
# monitored — useful for tests where the default $HOME / /tmp paths
# would mutate due to unrelated activity.
_loa_default_protected_paths() {
    if [[ "${LOA_HARNESS_FS_GUARD_EXCLUSIVE:-0}" == "1" ]]; then
        # Exclusive mode: only operator-supplied paths
        if [[ -n "${LOA_HARNESS_FS_GUARD_EXTRA_PATHS:-}" ]]; then
            echo "$LOA_HARNESS_FS_GUARD_EXTRA_PATHS" | tr ':' '\n'
        fi
        return 0
    fi

    cat <<EOF
$HOME
/tmp
/var/tmp
EOF
    # Also include repo root excluding worktree (worktree is inside repo
    # root but the OUTER repo's tree should not be mutated).
    if [[ -n "${LOA_HARNESS_WORKTREE_ROOT:-}" && -n "${PROJECT_ROOT:-}" ]]; then
        find "$PROJECT_ROOT" -maxdepth 1 -mindepth 1 -not -path "$LOA_HARNESS_WORKTREE_ROOT" 2>/dev/null
    fi
    # Operator extension
    if [[ -n "${LOA_HARNESS_FS_GUARD_EXTRA_PATHS:-}" ]]; then
        echo "$LOA_HARNESS_FS_GUARD_EXTRA_PATHS" | tr ':' '\n'
    fi
}

# Capture mtime + size for each protected path (one entry per immediate
# child, recursive scan is too expensive for /tmp).
harness_fs_snapshot_pre() {
    local out_file="$1"

    : > "$out_file"
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        [[ ! -e "$path" ]] && continue
        # mtime + size, tab-separated; one line per immediate child.
        # The audit log (`.run/model-invoke.jsonl`) is intentionally written
        # via LOA_AUDIT_LOG_PATH override; exclude it from the snapshot.
        find "$path" -maxdepth 1 \
            -not -path "$path/model-invoke.jsonl" \
            -printf '%T@\t%s\t%p\n' 2>/dev/null
    done < <(_loa_default_protected_paths) | sort > "$out_file"
}

# Compare current state to pre-snapshot; emit BLOCK + JSON-line per mutation.
harness_fs_snapshot_post() {
    local pre_file="$1"

    if [[ ! -f "$pre_file" ]]; then
        echo "[harness-fs-guard] ERROR: pre-snapshot file not found: $pre_file" >&2
        return 2
    fi

    local post_tmp
    post_tmp=$(mktemp)
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        [[ ! -e "$path" ]] && continue
        find "$path" -maxdepth 1 \
            -not -path "$path/model-invoke.jsonl" \
            -printf '%T@\t%s\t%p\n' 2>/dev/null
    done < <(_loa_default_protected_paths) | sort > "$post_tmp"

    # Compute diff: lines in post not in pre = added or modified;
    # lines in pre not in post = deleted. Both are mutations.
    local mutations=0
    while IFS=$'\t' read -r mtime size path; do
        echo "[harness-fs-guard] BLOCK: mutation detected: $path (mtime=$mtime size=$size)" >&2
        printf '{"event":"fs_mutation","path":"%s","mtime":%s,"size":%s,"direction":"appeared_or_modified"}\n' \
            "$path" "$mtime" "$size"
        mutations=$((mutations + 1))
    done < <(comm -13 "$pre_file" "$post_tmp")

    while IFS=$'\t' read -r mtime size path; do
        echo "[harness-fs-guard] BLOCK: file disappeared: $path (was mtime=$mtime size=$size)" >&2
        printf '{"event":"fs_mutation","path":"%s","mtime":%s,"size":%s,"direction":"disappeared"}\n' \
            "$path" "$mtime" "$size"
        mutations=$((mutations + 1))
    done < <(comm -23 "$pre_file" "$post_tmp")

    rm -f "$post_tmp"

    if [[ "$mutations" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Export functions when sourced
if (return 0 2>/dev/null); then
    # Being sourced; functions are now available
    :
else
    # Being executed directly — print usage
    cat <<EOF
harness-fs-guard.sh — Cycle-108 sprint-1 T1.E FS guards (source me, do not run)

Source via:
    source .claude/scripts/lib/harness-fs-guard.sh

Then call:
    harness_symlink_scan <dir>
    harness_fs_snapshot_pre <out-file>
    harness_fs_snapshot_post <pre-file>

See SDD §20.6 (ATK-A14 closure) for usage in Sprint 2's harness.
EOF
    exit 0
fi
