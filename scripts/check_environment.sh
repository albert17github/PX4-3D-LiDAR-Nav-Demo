#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="$ROOT/runtime"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"

mode=setup
case "${1:-}" in
  "") ;;
  --setup) mode=setup ;;
  --run) mode=run ;;
  -h|--help)
    cat <<'EOF'
Usage: ./scripts/check_environment.sh [--setup|--run]

Checks the documented Ubuntu 24.04 x86_64 environment.  --run also verifies
the project-owned runtime files and pinned source revisions.
EOF
    exit 0
    ;;
  *)
    echo "Unknown option: ${1:-}" >&2
    exit 64
    ;;
esac
[[ $# -le 1 ]] || {
  echo "Only one mode may be specified." >&2
  exit 64
}

failures=0
warnings=0

pass() {
  printf '  PASS  %-20s %s\n' "$1" "$2"
}

warn() {
  printf '  WARN  %-20s %s\n' "$1" "$2"
  warnings=$((warnings + 1))
}

fail() {
  printf '  FAIL  %-20s %s\n' "$1" "$2" >&2
  failures=$((failures + 1))
}

version_at_least() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

os_id="unknown"
os_version="unknown"
os_name="unknown"
if [[ -r /etc/os-release ]]; then
  # /etc/os-release is the operating system's own machine-readable contract.
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id="${ID:-unknown}"
  os_version="${VERSION_ID:-unknown}"
  os_name="${PRETTY_NAME:-unknown}"
fi

echo "Recommended environment check (mode=$mode)"
if [[ "$os_id" == ubuntu && "$os_version" == 24.04 ]]; then
  pass "operating system" "$os_name"
else
  fail "operating system" "Ubuntu 24.04 LTS required; found $os_name"
fi

architecture="$(uname -m)"
if [[ "$architecture" == x86_64 ]]; then
  pass "architecture" "$architecture"
else
  fail "architecture" "x86_64 required; found $architecture"
fi

required_commands=(bash curl flock git gzip ldd nproc python3 realpath setsid sha256sum ss tar taskset tee timeout)
if [[ "$mode" == run ]]; then
  required_commands+=(Xephyr gnome-screenshot xdpyinfo xdotool)
fi
missing_commands=()
for command_name in "${required_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || missing_commands+=("$command_name")
done
if ((${#missing_commands[@]} == 0)); then
  pass "host commands" "all required commands are available"
else
  fail "host commands" "missing: ${missing_commands[*]}"
  printf '        Install the Ubuntu packages listed in docs/REPRODUCE.md, then rerun this check.\n' >&2
fi

bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
if version_at_least "$bash_version" 5.2; then
  pass "Bash" "$bash_version (minimum 5.2)"
else
  fail "Bash" "$bash_version found; minimum 5.2"
fi
if command -v git >/dev/null 2>&1; then
  git_version="$(git --version | awk '{print $3}')"
  if version_at_least "$git_version" 2.43; then
    pass "Git" "$git_version (minimum 2.43)"
  else
    fail "Git" "$git_version found; minimum 2.43"
  fi
fi
if command -v python3 >/dev/null 2>&1; then
  python_version="$(python3 -c 'import platform; print(platform.python_version())')"
  python_major_minor="${python_version%.*}"
  if [[ "$python_major_minor" == 3.12 ]]; then
    pass "Python" "$python_version (required series 3.12.x)"
  else
    fail "Python" "$python_version found; required series 3.12.x"
  fi
fi

cpu_count="$(nproc 2>/dev/null || echo 0)"
memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
swap_kib="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
if ((cpu_count >= 4)); then
  pass "CPU" "$cpu_count logical CPUs (minimum 4; 8+ recommended)"
else
  fail "CPU" "$cpu_count logical CPUs found; minimum 4"
fi
if ((memory_kib >= 10 * 1024 * 1024)); then
  pass "memory" "$((memory_kib / 1024 / 1024)) GiB RAM, $((swap_kib / 1024 / 1024)) GiB swap"
else
  fail "memory" "$((memory_kib / 1024 / 1024)) GiB RAM found; allocate at least 12 GiB to the VM"
fi

free_kib="$(df -Pk "$ROOT" | awk 'NR == 2 {print $4}')"
minimum_free_kib=$((5 * 1024 * 1024))
if [[ "$mode" == setup && ! -f "$RUNTIME_ROOT/env/rootfs/.packages-complete" ]]; then
  minimum_free_kib=$((20 * 1024 * 1024))
fi
if ((free_kib >= minimum_free_kib)); then
  pass "free disk" "$((free_kib / 1024 / 1024)) GiB available"
else
  fail "free disk" "$((free_kib / 1024 / 1024)) GiB available; $((minimum_free_kib / 1024 / 1024)) GiB required for this mode"
fi

if [[ -n "${DISPLAY:-}" ]]; then
  if command -v xdpyinfo >/dev/null 2>&1 && timeout 5s xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    pass "desktop display" "DISPLAY=$DISPLAY is reachable"
  elif [[ "$mode" == run ]]; then
    fail "desktop display" "DISPLAY=$DISPLAY is not reachable through X11/XWayland"
  else
    warn "desktop display" "DISPLAY=$DISPLAY could not be queried; setup may continue, but the demo cannot start"
  fi
elif [[ "$mode" == run ]]; then
  fail "desktop display" "DISPLAY is empty; start from the Ubuntu desktop session"
else
  warn "desktop display" "DISPLAY is empty; setup may continue, but the demo cannot start"
fi

if [[ "$mode" == run ]]; then
  runtime_files=(
    "$RUNTIME_ROOT/env/rootfs/.packages-complete"
    "$RUNTIME_ROOT/.setup/runtime.lock"
    "$RUNTIME_ROOT/env/rootfs/opt/ros/$ROS_DISTRO/lib/rviz2/rviz2"
    "$RUNTIME_ROOT/env/rootfs/usr/bin/gz"
    "$RUNTIME_ROOT/vendor/PX4-Autopilot/build/px4_sitl_default/bin/px4"
    "$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so"
    "$RUNTIME_ROOT/env/rootfs/opt/ros/$ROS_DISTRO/lib/libMrsOctomapPlanner_MinimalOctomapPlanner.so"
  )
  missing_runtime=()
  for runtime_file in "${runtime_files[@]}"; do
    [[ -e "$runtime_file" ]] || missing_runtime+=("${runtime_file#"$ROOT/"}")
  done
  if ((${#missing_runtime[@]} == 0)); then
    pass "runtime files" "ROS $ROS_DISTRO, Gazebo $GAZEBO_RELEASE and required binaries are present"
  else
    fail "runtime files" "missing: ${missing_runtime[*]}"
  fi

  revision_failures=()
  revision_specs=(
    "PX4:$RUNTIME_ROOT/vendor/PX4-Autopilot:$PX4_COMMIT"
    "DLIO:$RUNTIME_ROOT/third_party/direct_lidar_inertial_odometry:$DLIO_COMMIT"
    "MAVROS:$RUNTIME_ROOT/mavros-src:$MAVROS_COMMIT"
  )
  for revision_spec in "${revision_specs[@]}"; do
    IFS=: read -r component repository expected_revision <<<"$revision_spec"
    actual_revision="$(git -C "$repository" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$actual_revision" != "$expected_revision" ]]; then
      revision_failures+=("$component=${actual_revision:-missing}, expected=$expected_revision")
    fi
  done
  if ((${#revision_failures[@]} == 0)); then
    pass "source versions" "PX4 $PX4_TAG, DLIO $DLIO_BRANCH and MAVROS $MAVROS_TAG match the lock file"
  else
    fail "source versions" "${revision_failures[*]}"
  fi
fi

if ((failures > 0)); then
  printf '\nEnvironment check: FAIL (%d failure(s), %d warning(s))\n' "$failures" "$warnings" >&2
  printf 'Recommended configuration: %s/docs/REPRODUCE.md\n' "$ROOT" >&2
  exit 10
fi

printf '\nEnvironment check: PASS (%d warning(s))\n' "$warnings"
