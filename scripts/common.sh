#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "common.sh must be sourced" >&2
  exit 64
fi

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_ROOT="${PX4_DEMO_STACK_ROOT:-/home/albert/PX4-LiDAR-SLAM-Sim}"
ROS_ROOTFS="$STACK_ROOT/env/rootfs"
ROS_PREFIX="$ROS_ROOTFS/opt/ros/jazzy"
ROS_DOMAIN_ID_VALUE="${ROS_DOMAIN_ID:-0}"
RMW_IMPLEMENTATION_VALUE="${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
ROS_LD_LIBRARY_PATH="$ROS_PREFIX/lib:$ROS_PREFIX/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib/x86_64-linux-gnu:$ROS_ROOTFS/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib:$ROS_ROOTFS/lib"
ROS_PYTHONPATH="$ROS_PREFIX/lib/python3.12/site-packages:$ROS_ROOTFS/usr/lib/python3/dist-packages:$ROS_ROOTFS/usr/lib/python3.12/dist-packages:$ROS_ROOTFS/usr/local/lib/python3.12/dist-packages"
FFMPEG="$ROS_ROOTFS/usr/bin/ffmpeg"
FFPROBE="$ROS_ROOTFS/usr/bin/ffprobe"
MAVROS_OVERLAY_HOST_LIB_DIR="${PX4_DEMO_MAVROS_OVERLAY_HOST_LIB_DIR:-$STACK_ROOT/runtime/mavros-overlay/lib}"
# shellcheck disable=SC2034 # Public value consumed by start.sh after sourcing.
MAVROS_OVERLAY_GUEST_LIB_DIR="${PX4_DEMO_MAVROS_OVERLAY_GUEST_LIB_DIR:-/project/runtime/mavros-overlay/lib}"
# shellcheck disable=SC2034  # Public value consumed by scripts that source this file.
RVIZ_DISPLAY="${PX4_DEMO_RVIZ_DISPLAY:-:98}"
CURRENT_RUN_FILE="$DEMO_ROOT/.runtime/current-run"

now_iso() {
  date --iso-8601=seconds
}

native_ros() {
  env \
    PATH="$ROS_PREFIX/bin:$PATH" \
    LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
    PYTHONPATH="$ROS_PYTHONPATH" \
    PYTHONNOUSERSITE=1 \
    AMENT_PREFIX_PATH="$ROS_PREFIX" \
    COLCON_PREFIX_PATH="$ROS_PREFIX" \
    ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
    ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
    RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
    "$@"
}

require_runtime() {
  local path
  for path in \
    "$STACK_ROOT/scripts/start_sim.sh" \
    "$STACK_ROOT/scripts/stop_sim.sh" \
    "$ROS_PREFIX/lib/rclcpp_components/component_container_mt" \
    "$ROS_PREFIX/lib/rviz2/rviz2" \
    "$ROS_PREFIX/lib/libMrsOctomapPlanner_MinimalOctomapPlanner.so" \
    "$MAVROS_OVERLAY_HOST_LIB_DIR/libmavros_plugins.so" \
    "$FFMPEG" \
    "$FFPROBE"; do
    [[ -e "$path" ]] || {
      echo "Missing shared runtime file: $path" >&2
      return 10
    }
  done
}

current_run() {
  [[ -f "$CURRENT_RUN_FILE" ]] || return 1
  local value
  IFS= read -r value <"$CURRENT_RUN_FILE"
  [[ -n "$value" && -d "$value" ]] || return 1
  printf '%s\n' "$value"
}

record_pid() {
  local run_dir="$1"
  local name="$2"
  local pid="$3"
  local pgid
  pgid="$(ps -o pgid= -p "$pid" | tr -d ' ')" || return 1
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 1
  printf 'pid=%s\npgid=%s\nstarted_at=%s\n' "$pid" "$pgid" "$(now_iso)" \
    >"$run_dir/pids/$name.pid"
}

read_pid_field() {
  local run_dir="$1"
  local name="$2"
  local key="$3"
  local file="$run_dir/pids/$name.pid"
  [[ -f "$file" ]] || return 1
  awk -F= -v key="$key" '$1 == key {print $2; found=1} END {exit !found}' "$file"
}

stop_group() {
  local run_dir="$1"
  local name="$2"
  local pgid
  pgid="$(read_pid_field "$run_dir" "$name" pgid 2>/dev/null)" || return 0
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || return 0
  if ps -eo pgid= | awk -v target="$pgid" '$1 == target {found=1} END {exit !found}'; then
    kill -INT -- "-$pgid" 2>/dev/null || true
    for _ in {1..20}; do
      if ! ps -eo pgid= | awk -v target="$pgid" '$1 == target {found=1} END {exit !found}'; then
        return 0
      fi
      sleep 0.25
    done
    kill -TERM -- "-$pgid" 2>/dev/null || true
  fi
}
