#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$ROOT/runtime"
SEED_FROM=""
VERIFY_ONLY=0
JOBS="${PX4_DEMO_SETUP_JOBS:-}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS]

Builds the complete project-owned PX4/ROS/Gazebo runtime without modifying or
depending on another project directory.

Options:
  --jobs N              Parallel build jobs (default: min(nproc, 4)).
  --seed-from PATH      Copy validated local caches/builds, then verify them.
  --verify-only         Do not download or build; verify the current runtime.
  -h, --help            Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --jobs)
      shift
      JOBS="${1:-}"
      ;;
    --seed-from)
      shift
      SEED_FROM="${1:-}"
      ;;
    --verify-only)
      VERIFY_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if [[ -z "$JOBS" ]]; then
  JOBS="$(nproc)"
  ((JOBS <= 4)) || JOBS=4
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || {
  echo "--jobs must be a positive integer" >&2
  exit 64
}
export PX4_DEMO_SETUP_JOBS="$JOBS"

if [[ -n "$SEED_FROM" ]] && ! command -v rsync >/dev/null; then
  echo "--seed-from requires rsync; install it before continuing." >&2
  exit 10
fi

mkdir -p "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/.setup"

run_stage() {
  local position="$1"
  local description="$2"
  local log_file="$3"
  shift 3
  echo "[setup $position] $description"
  set +e
  "$@" 2>&1 | tee "$log_file"
  local command_rc="${PIPESTATUS[0]}"
  set -e
  if ((command_rc != 0)); then
    printf '\nERROR: setup stage %s failed: %s\n' "$position" "$description" >&2
    printf 'Exit code: %d\n' "$command_rc" >&2
    printf 'Log: %s\n' "$log_file" >&2
    printf 'Resolve the reported problem, then rerun: ./setup.sh\n' >&2
    exit "$command_rc"
  fi
  echo "[setup $position] PASS"
}

first_stage="1/6"
((VERIFY_ONLY)) && first_stage="1/2"
run_stage "$first_stage" "Checking the documented host environment..." \
  "$RUNTIME_ROOT/logs/environment-check.log" \
  "$ROOT/scripts/check_environment.sh" --setup

if ((VERIFY_ONLY)); then
  run_stage "2/2" "Verifying source versions, binaries and package manifest..." \
    "$RUNTIME_ROOT/logs/verify-runtime.log" \
    "$RUNTIME_ROOT/scripts/verify-runtime.sh"
  echo "Verification complete."
  exit 0
fi

run_stage "2/6" "Downloading the pinned upstream source trees..." \
  "$RUNTIME_ROOT/logs/fetch-sources.log" \
  env PX4_DEMO_SEED_SOURCE="$SEED_FROM" "$RUNTIME_ROOT/scripts/fetch-sources.sh"
if [[ -n "$SEED_FROM" ]]; then
  run_stage "3/6" "Importing the selected validated local cache..." \
    "$RUNTIME_ROOT/logs/seed-runtime.log" \
    "$RUNTIME_ROOT/scripts/seed-runtime.sh" "$SEED_FROM"
else
  run_stage "3/6" "Downloading and checking the Ubuntu 24.04 rootfs..." \
    "$RUNTIME_ROOT/logs/bootstrap-rootfs.log" \
    "$RUNTIME_ROOT/scripts/bootstrap-rootfs.sh"
fi

if [[ ! -f "$RUNTIME_ROOT/env/rootfs/.packages-complete" ]]; then
  run_stage "4/6" "Installing the locked ROS 2, Gazebo, MAVROS, OctoMap and MRS packages..." \
    "$RUNTIME_ROOT/logs/install-packages.log" \
    env PROOT_DPKG_COMPAT=1 "$RUNTIME_ROOT/scripts/proot-run.sh" \
      bash /project/env/install-packages.sh
else
  echo "[setup 4/6] Package environment already present: PASS"
fi

run_stage "5/6" "Building missing pinned source components..." \
  "$RUNTIME_ROOT/logs/build-runtime.log" \
  "$RUNTIME_ROOT/scripts/build-runtime.sh"
run_stage "6/6" "Verifying source versions, binaries and package manifest..." \
  "$RUNTIME_ROOT/logs/verify-runtime.log" \
  "$RUNTIME_ROOT/scripts/verify-runtime.sh"

echo "Setup complete."
echo "Next: ./demo.sh --interactive"
