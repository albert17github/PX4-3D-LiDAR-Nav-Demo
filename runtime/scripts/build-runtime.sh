#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"
[[ -f "$RUNTIME_ROOT/env/rootfs/.packages-complete" ]] || {
  echo "ROS/PX4 build dependencies are not installed" >&2
  exit 10
}
have_px4=0
have_dlio=0
have_mavros=0
px4_inputs="$(printf 'px4_commit=%s' "$PX4_COMMIT")"
dlio_inputs="$(printf 'dlio_commit=%s\ndlio_patch_sha256=%s' \
  "$DLIO_COMMIT" "$DLIO_PATCH_SHA256")"
mavros_inputs="$(printf 'mavros_commit=%s\nmavros_patch_sha256=%s\nmavros_router_patch_sha256=%s' \
  "$MAVROS_COMMIT" "$MAVROS_PATCH_SHA256" "$MAVROS_ROUTER_PATCH_SHA256")"
marker_matches() {
  [[ -f "$1" && "$(< "$1")" == "$2" ]]
}
[[ -x "$RUNTIME_ROOT/vendor/PX4-Autopilot/build/px4_sitl_default/bin/px4" ]] && \
  marker_matches "$RUNTIME_ROOT/.setup/px4-build.inputs" "$px4_inputs" && have_px4=1
[[ -x "$RUNTIME_ROOT/ros2_ws/build/direct_lidar_inertial_odometry/dlio_odom_node" ]] && \
  marker_matches "$RUNTIME_ROOT/.setup/dlio-build.inputs" "$dlio_inputs" && have_dlio=1
[[ -f "$RUNTIME_ROOT/mavros-overlay/lib/libmavros.so" && \
   -f "$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so" ]] && \
  marker_matches "$RUNTIME_ROOT/.setup/mavros-build.inputs" "$mavros_inputs" && have_mavros=1

"$RUNTIME_ROOT/scripts/proot-run.sh" \
  env PX4_DEMO_SETUP_JOBS="${PX4_DEMO_SETUP_JOBS:-4}" \
  PX4_DEMO_HAVE_PX4="$have_px4" PX4_DEMO_HAVE_DLIO="$have_dlio" \
  PX4_DEMO_HAVE_MAVROS="$have_mavros" \
  bash /project/env/build-runtime.sh
printf '%s\n' "$px4_inputs" > "$RUNTIME_ROOT/.setup/px4-build.inputs"
printf '%s\n' "$dlio_inputs" > "$RUNTIME_ROOT/.setup/dlio-build.inputs"
printf '%s\n' "$mavros_inputs" > "$RUNTIME_ROOT/.setup/mavros-build.inputs"
