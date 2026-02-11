#!/usr/bin/env bash
# sandbox.sh — Sandbox provisioning for Loa Eval tasks
# Provides isolated temp-directory environments for eval task execution.
# Exit codes: 0 = success, 1 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
SANDBOX_PREFIX="/tmp/loa-eval"

# --- Preflight ---
for tool in mktemp git sha256sum; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: Missing required tool: $tool" >&2
    exit 1
  fi
done

usage() {
  cat <<'USAGE'
Usage: sandbox.sh <command> [options]

Commands:
  create       Create a sandbox from a fixture
  destroy      Destroy a specific sandbox
  destroy-all  Destroy all sandboxes for a run

Options (create):
  --fixture <path>       Fixture directory (relative to evals/fixtures/)
  --run-id <id>          Run identifier
  --trial-id <id>        Trial identifier
  --sandbox-mode <mode>  Sandbox mode: local (default), container

Options (destroy):
  --trial-id <id>      Trial identifier to destroy

Options (destroy-all):
  --run-id <id>        Run identifier

Exit codes:
  0  Success
  1  Error
USAGE
  exit 1
}

# --- PATH_SAFETY: Validate fixture path ---
validate_fixture_path() {
  local fixture_path="$1"

  # Reject path traversal
  if [[ "$fixture_path" == *".."* ]]; then
    echo "ERROR: Path traversal detected in fixture path: $fixture_path" >&2
    return 1
  fi

  local full_path="$EVALS_DIR/fixtures/$fixture_path"

  # Must be within evals/fixtures/
  local real_path
  real_path="$(realpath -m "$full_path" 2>/dev/null || echo "$full_path")"
  local fixtures_real
  fixtures_real="$(realpath -m "$EVALS_DIR/fixtures" 2>/dev/null || echo "$EVALS_DIR/fixtures")"

  if [[ "$real_path" != "$fixtures_real"* ]]; then
    echo "ERROR: Fixture path escapes fixtures directory: $fixture_path" >&2
    return 1
  fi

  if [[ ! -d "$full_path" ]]; then
    echo "ERROR: Fixture directory not found: $full_path" >&2
    return 1
  fi

  # Reject symlinks pointing outside fixture
  while IFS= read -r -d '' link; do
    local target
    target="$(readlink -f "$link" 2>/dev/null || echo "")"
    if [[ -n "$target" && "$target" != "$full_path"* && "$target" != "$EVALS_DIR"* ]]; then
      echo "ERROR: Symlink points outside fixture: $link -> $target" >&2
      return 1
    fi
  done < <(find "$full_path" -type l -print0 2>/dev/null)

  return 0
}

# --- Sanitize environment ---
sanitize_env() {
  local sandbox_path="$1"

  # Clear sensitive env vars
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN 2>/dev/null || true
  unset ANTHROPIC_API_KEY OPENAI_API_KEY 2>/dev/null || true
  unset GITHUB_TOKEN GH_TOKEN 2>/dev/null || true

  # Set controlled env
  export TZ=UTC
  export LC_ALL=C
  export HOME="$sandbox_path/home"
  export TMPDIR="$sandbox_path/tmp"

  # Restrictive umask
  umask 077

  # Clean PATH — only essential directories
  export PATH="/usr/local/bin:/usr/bin:/bin"
}

# --- Create sandbox ---
cmd_create() {
  local fixture=""
  local run_id=""
  local trial_id=""
  local sandbox_mode="local"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fixture) fixture="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --trial-id) trial_id="$2"; shift 2 ;;
      --sandbox-mode) sandbox_mode="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$fixture" || -z "$run_id" ]]; then
    echo "ERROR: --fixture and --run-id are required" >&2
    exit 1
  fi

  # Default trial-id
  [[ -z "$trial_id" ]] && trial_id="${run_id}-trial-1"

  # Validate fixture path (PATH_SAFETY)
  validate_fixture_path "$fixture" || exit 1

  local fixture_dir="$EVALS_DIR/fixtures/$fixture"

  # Container mode: use docker for isolation
  if [[ "$sandbox_mode" == "container" ]]; then
    cmd_create_container "$fixture" "$fixture_dir" "$run_id" "$trial_id"
    return
  fi

  # Create sandbox directory
  local sandbox_dir
  sandbox_dir="$(mktemp -d "${SANDBOX_PREFIX}-${trial_id}-XXXXXX")"

  # Create subdirectories
  mkdir -p "$sandbox_dir/home" "$sandbox_dir/tmp" "$sandbox_dir/workspace"

  # Copy fixture contents (not symlink — isolation)
  cp -a "$fixture_dir/." "$sandbox_dir/workspace/"

  # Initialize git repo in sandbox (some skills use git)
  (
    cd "$sandbox_dir/workspace"
    git init -q 2>/dev/null || true
    git add -A 2>/dev/null || true
    git commit -q -m "Initial fixture state" --allow-empty 2>/dev/null || true
  )

  # Handle dependency strategy
  local dep_strategy="none"
  if [[ -f "$fixture_dir/fixture.yaml" ]]; then
    dep_strategy="$(yq -r '.dependency_strategy // "none"' "$fixture_dir/fixture.yaml")"
  fi

  case "$dep_strategy" in
    prebaked)
      # Dependencies already in fixture, nothing to do
      ;;
    offline-cache)
      if [[ -f "$sandbox_dir/workspace/package-lock.json" ]]; then
        (cd "$sandbox_dir/workspace" && npm ci --offline --ignore-scripts 2>/dev/null || true)
      fi
      ;;
    none)
      # No dependencies to install
      ;;
    *)
      echo "WARNING: Unknown dependency_strategy: $dep_strategy" >&2
      ;;
  esac

  # Record environment fingerprint
  local fingerprint_file="$sandbox_dir/env-fingerprint.json"
  jq -n \
    --arg run_id "$run_id" \
    --arg trial_id "$trial_id" \
    --arg fixture "$fixture" \
    --arg sandbox_path "$sandbox_dir" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg bash_version "${BASH_VERSION:-unknown}" \
    --arg node_version "$(node --version 2>/dev/null || echo 'not-installed')" \
    --arg python_version "$(python3 --version 2>/dev/null | awk '{print $2}' || echo 'not-installed')" \
    --arg os "$(uname -s)" \
    --arg arch "$(uname -m)" \
    --arg dep_strategy "$dep_strategy" \
    '{
      run_id: $run_id,
      trial_id: $trial_id,
      fixture: $fixture,
      sandbox_path: $sandbox_path,
      created_at: $created_at,
      environment: {
        bash: $bash_version,
        node: $node_version,
        python: $python_version,
        os: $os,
        arch: $arch
      },
      dependency_strategy: $dep_strategy
    }' > "$fingerprint_file"

  # Output sandbox path (workspace directory is the working dir)
  echo "$sandbox_dir/workspace"
}

# --- Destroy sandbox ---
cmd_destroy() {
  local trial_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --trial-id) trial_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$trial_id" ]]; then
    echo "ERROR: --trial-id is required" >&2
    exit 1
  fi

  # Find and remove matching sandbox directories
  local found=false
  for dir in "${SANDBOX_PREFIX}-${trial_id}"-*; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      found=true
    fi
  done

  if [[ "$found" == "false" ]]; then
    echo "WARNING: No sandbox found for trial-id: $trial_id" >&2
  fi
}

# --- Destroy all sandboxes for a run ---
cmd_destroy_all() {
  local run_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$run_id" ]]; then
    echo "ERROR: --run-id is required" >&2
    exit 1
  fi

  # Find and remove all sandboxes matching run-id
  for dir in "${SANDBOX_PREFIX}-${run_id}"-*; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
    fi
  done
}

# --- Container sandbox create ---
cmd_create_container() {
  local fixture="$1"
  local fixture_dir="$2"
  local run_id="$3"
  local trial_id="$4"

  # Verify docker is available
  if ! command -v docker &>/dev/null; then
    echo "ERROR: docker required for container sandbox mode" >&2
    exit 1
  fi

  # Verify image exists
  local image="loa-eval-sandbox:latest"
  if ! docker image inspect "$image" &>/dev/null; then
    echo "ERROR: Container image not found: $image" >&2
    echo "Build with: docker build -t $image -f evals/harness/Dockerfile.sandbox ." >&2
    exit 1
  fi

  # Create host-side directory for results
  local sandbox_dir
  sandbox_dir="$(mktemp -d "${SANDBOX_PREFIX}-${trial_id}-XXXXXX")"
  mkdir -p "$sandbox_dir/workspace" "$sandbox_dir/results"

  # Copy fixture to workspace
  cp -a "$fixture_dir/." "$sandbox_dir/workspace/"

  # Initialize git in workspace
  (
    cd "$sandbox_dir/workspace"
    git init -q 2>/dev/null || true
    git add -A 2>/dev/null || true
    git commit -q -m "Initial fixture state" --allow-empty 2>/dev/null || true
  )

  # Run container with security constraints
  local container_name="loa-eval-${trial_id}"
  docker run -d \
    --name "$container_name" \
    --network none \
    --memory 2g \
    --cpus 2 \
    --read-only \
    --tmpfs /tmp:rw,noexec,size=512m \
    --tmpfs /home/evaluser:rw,size=64m \
    -v "$sandbox_dir/workspace:/workspace:ro" \
    -v "$sandbox_dir/results:/results:rw" \
    -e "RUN_ID=$run_id" \
    -e "TRIAL_ID=$trial_id" \
    "$image" \
    sleep infinity &>/dev/null

  # Record container info in fingerprint
  jq -n \
    --arg run_id "$run_id" \
    --arg trial_id "$trial_id" \
    --arg fixture "$fixture" \
    --arg sandbox_path "$sandbox_dir" \
    --arg container_name "$container_name" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sandbox_mode "container" \
    '{
      run_id: $run_id,
      trial_id: $trial_id,
      fixture: $fixture,
      sandbox_path: $sandbox_path,
      container_name: $container_name,
      created_at: $created_at,
      sandbox_mode: $sandbox_mode
    }' > "$sandbox_dir/env-fingerprint.json"

  # Output workspace path (inside the host mount)
  echo "$sandbox_dir/workspace"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
  usage
fi

command="$1"
shift

case "$command" in
  create) cmd_create "$@" ;;
  destroy) cmd_destroy "$@" ;;
  destroy-all) cmd_destroy_all "$@" ;;
  *) echo "ERROR: Unknown command: $command" >&2; usage ;;
esac
