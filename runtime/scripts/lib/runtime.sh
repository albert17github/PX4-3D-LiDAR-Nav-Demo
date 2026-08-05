#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "runtime.sh must be sourced" >&2
  exit 64
fi

RUNTIME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$RUNTIME_LIB_DIR/../.." && pwd)"
STATE_DIR="$RUNTIME_ROOT/.runtime"
RUNS_DIR="$RUNTIME_ROOT/runs"
ACTIVE_RUN_FILE="$STATE_DIR/active-run"
# Public value used by scripts sourcing this library.
# shellcheck disable=SC2034
PROOT_RUN="$RUNTIME_ROOT/scripts/proot-run.sh"
ROS_ROOTFS="$RUNTIME_ROOT/env/rootfs"
ROS_PREFIX="$ROS_ROOTFS/opt/ros/jazzy"
ROS_DOMAIN_ID_VALUE="${ROS_DOMAIN_ID:-0}"
RMW_IMPLEMENTATION_VALUE="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
ROS_LD_LIBRARY_PATH="$ROS_PREFIX/lib:$ROS_PREFIX/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib/x86_64-linux-gnu:$ROS_ROOTFS/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib:$ROS_ROOTFS/lib"
ROS_PYTHONPATH="$ROS_PREFIX/lib/python3.12/site-packages:$ROS_ROOTFS/usr/lib/python3/dist-packages:$ROS_ROOTFS/usr/lib/python3.12/dist-packages:$ROS_ROOTFS/usr/local/lib/python3.12/dist-packages"

now_iso() {
  date --iso-8601=seconds
}

append_status() {
  local run_dir="$1" event="$2" detail="${3:-}"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\t'/ }"
  printf '%s\t%s\t%s\n' "$(now_iso)" "$event" "$detail" >> "$run_dir/status"
}

ensure_runtime_dirs() {
  mkdir -p "$STATE_DIR" "$RUNS_DIR"
}

native_ros() {
  timeout --signal=TERM --kill-after=3s "${PX4_DEMO_ROS_TIMEOUT_S:-40}s" \
    env PATH="$ROS_PREFIX/bin:$PATH" \
    LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
    PYTHONPATH="$ROS_PYTHONPATH" PYTHONNOUSERSITE=1 \
    AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
    ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
    ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
    RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" "$@"
}

record_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$file"
}

valid_component() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

proc_starttime() {
  local pid="$1" tail
  [[ -r "/proc/$pid/stat" ]] || return 1
  IFS= read -r tail < "/proc/$pid/stat"
  tail="${tail##*) }"
  read -r -a fields <<< "$tail"
  (("${#fields[@]}" >= 20)) || return 1
  printf '%s\n' "${fields[19]}"
}

proc_cmdline() {
  tr '\0' ' ' < "/proc/$1/cmdline"
}

spawn_component() {
  local run_dir="$1" name="$2" token="$3"
  shift 3
  local pid pgid starttime cmdline
  valid_component "$name" || return 64
  printf -v cmdline '%q ' "$@"
  printf '%s\n' "${cmdline% }" > "$run_dir/commands/$name.command"
  append_status "$run_dir" component_starting "$name"
  setsid "$@" > "$run_dir/logs/$name.log" 2>&1 </dev/null &
  pid=$!
  sleep 0.1
  kill -0 "$pid" 2>/dev/null || {
    wait "$pid" || true
    echo "Component exited during startup: $name" >&2
    return 12
  }
  pgid="$(ps -o pgid= -p "$pid" | tr -d ' ')"
  starttime="$(proc_starttime "$pid")"
  [[ "$pgid" == "$pid" && -n "$starttime" ]] || return 12
  {
    printf 'pid=%s\npgid=%s\nstarttime=%s\n' "$pid" "$pgid" "$starttime"
    printf 'boot_id=%s\ntoken=%s\n' "$(< /proc/sys/kernel/random/boot_id)" "$token"
  } > "$run_dir/pids/$name.pid"
  printf '%s\n' "$name" >> "$run_dir/component-order"
  append_status "$run_dir" component_started "$name pid=$pid pgid=$pgid"
}

component_alive() {
  local run_dir="$1" name="$2" file pid pgid starttime token
  file="$run_dir/pids/$name.pid"
  [[ -f "$file" ]] || return 1
  pid="$(record_value "$file" pid)"
  pgid="$(record_value "$file" pgid)"
  starttime="$(record_value "$file" starttime)"
  token="$(record_value "$file" token)"
  [[ "$(< /proc/sys/kernel/random/boot_id)" == "$(record_value "$file" boot_id)" ]]
  kill -0 "$pid" 2>/dev/null
  [[ "$(ps -o pgid= -p "$pid" | tr -d ' ')" == "$pgid" ]]
  [[ "$(proc_starttime "$pid")" == "$starttime" ]]
  [[ "$(proc_cmdline "$pid")" == *"$token"* ]]
}

wait_until() {
  local seconds="$1"
  shift
  local deadline=$((SECONDS + seconds))
  while ((SECONDS < deadline)); do
    "$@" && return 0
    sleep 0.5
  done
  "$@"
}

component_gate() {
  local run_dir="$1" name="$2" description="$3" seconds="$4"
  shift 4
  append_status "$run_dir" gate_waiting "$name $description"
  if ! wait_until "$seconds" component_probe "$run_dir" "$name" "$@"; then
    append_status "$run_dir" gate_timeout "$name $description"
    echo "Readiness timeout: $description" >&2
    return 12
  fi
  append_status "$run_dir" gate_passed "$name $description"
}

component_probe() {
  local run_dir="$1" name="$2"
  shift 2
  component_alive "$run_dir" "$name" && "$@"
}

write_active_run() {
  local run_dir="$1" temporary
  temporary="$(mktemp "$STATE_DIR/.active-run.XXXXXX")"
  printf '%s\n' "$run_dir" > "$temporary"
  mv "$temporary" "$ACTIVE_RUN_FILE"
}

safe_active_run() {
  local candidate real_runs real_candidate
  [[ -f "$ACTIVE_RUN_FILE" ]] || return 1
  IFS= read -r candidate < "$ACTIVE_RUN_FILE"
  [[ -d "$candidate" ]] || return 1
  real_runs="$(realpath -e "$RUNS_DIR")"
  real_candidate="$(realpath -e "$candidate")"
  [[ "$real_candidate" == "$real_runs/"* ]] || return 1
  printf '%s\n' "$real_candidate"
}
