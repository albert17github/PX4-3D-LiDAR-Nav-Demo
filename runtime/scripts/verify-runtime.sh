#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_ROOT="$(dirname "$RUNTIME_ROOT")"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"
ROS_ROOTFS="$RUNTIME_ROOT/env/rootfs"
ROS_PREFIX="$ROS_ROOTFS/opt/ros/jazzy"
LD_PATH="$RUNTIME_ROOT/mavros-overlay/lib:$ROS_PREFIX/lib:$ROS_PREFIX/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib/x86_64-linux-gnu:$ROS_ROOTFS/lib/x86_64-linux-gnu:$ROS_ROOTFS/usr/lib:$ROS_ROOTFS/lib"
DLIO_DIR="$RUNTIME_ROOT/third_party/direct_lidar_inertial_odometry"
DLIO_BINARY="$RUNTIME_ROOT/ros2_ws/build/direct_lidar_inertial_odometry/dlio_odom_node"
MAVROS_DIR="$RUNTIME_ROOT/mavros-src"
MAVROS_LIBRARY="$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so"
PX4_DIR="$RUNTIME_ROOT/vendor/PX4-Autopilot"
LOCK_DIR="$RUNTIME_ROOT/.setup"
LOCK_FILE="$LOCK_DIR/runtime.lock"

required=(
  "$RUNTIME_ROOT/env/proot"
  "$ROS_ROOTFS/.packages-complete"
  "$ROS_PREFIX/lib/ros_gz_bridge/parameter_bridge"
  "$ROS_PREFIX/lib/octomap_server/octomap_server_node"
  "$ROS_PREFIX/lib/rviz2/rviz2"
  "$ROS_PREFIX/lib/libMrsOctomapPlanner_MinimalOctomapPlanner.so"
  "$ROS_ROOTFS/usr/bin/ffmpeg"
  "$PX4_DIR/build/px4_sitl_default/bin/px4"
  "$DLIO_BINARY"
  "$RUNTIME_ROOT/mavros-overlay/lib/libmavros.so"
  "$MAVROS_LIBRARY"
  "$LOCK_DIR/px4-build.inputs"
  "$LOCK_DIR/dlio-build.inputs"
  "$LOCK_DIR/mavros-build.inputs"
  "$DEMO_ROOT/config/demo.yaml"
  "$DEMO_ROOT/src/ab_mission.py"
  "$DEMO_ROOT/scripts/check_simulation_contract.py"
)
for path in "${required[@]}"; do
  [[ -e "$path" ]] || {
    echo "Missing runtime prerequisite: $path" >&2
    exit 10
  }
done
[[ "$(git -C "$PX4_DIR" rev-parse HEAD)" == "$PX4_COMMIT" ]]
[[ "$(git -C "$DLIO_DIR" rev-parse HEAD)" == "$DLIO_COMMIT" ]]
[[ "$(git -C "$MAVROS_DIR" rev-parse HEAD)" == "$MAVROS_COMMIT" ]]
git -C "$DLIO_DIR" apply --reverse --check "$RUNTIME_ROOT/patches/dlio-ros2-upstream-fixes.patch"
git -C "$MAVROS_DIR" apply --reverse --check "$RUNTIME_ROOT/patches/mavros-2.14.0-vehicles-lock.patch"
git -C "$MAVROS_DIR" apply --reverse --check "$RUNTIME_ROOT/patches/mavros-2.14.0-router-lock.patch"
[[ "$(sha256sum "$DLIO_DIR/include/dlio/odom.h" | awk '{print $1}')" == "$DLIO_HEADER_PATCHED_SHA256" ]]
[[ "$(sha256sum "$DLIO_DIR/src/dlio/odom.cc" | awk '{print $1}')" == "$DLIO_ODOM_PATCHED_SHA256" ]]

for binary in "$DLIO_BINARY" "$MAVROS_LIBRARY" \
  "$ROS_PREFIX/lib/ros_gz_bridge/parameter_bridge" \
  "$ROS_PREFIX/lib/octomap_server/octomap_server_node"; do
  if env LD_LIBRARY_PATH="$LD_PATH:$RUNTIME_ROOT/ros2_ws/install/direct_lidar_inertial_odometry/lib" \
      ldd "$binary" | grep -Fq 'not found'; then
    echo "Unresolved runtime library: $binary" >&2
    exit 10
  fi
done
"$RUNTIME_ROOT/scripts/proot-run.sh" bash -lc \
  'source /opt/ros/jazzy/setup.bash; ros2 --help >/dev/null; gz sim --versions >/dev/null'
"$RUNTIME_ROOT/scripts/proot-run.sh" bash -lc \
  'source /opt/ros/jazzy/setup.bash; python3 /project/scripts/capture_px4_fusion_live.py --self-test >/dev/null'
"$RUNTIME_ROOT/scripts/proot-run.sh" bash -lc \
  'source /opt/ros/jazzy/setup.bash; python3 /project/scripts/check_ground_state.py --self-test >/dev/null; python3 /project/scripts/check_odom_stream.py --self-test >/dev/null'
python3 -m py_compile \
  "$DEMO_ROOT/src/ab_mission.py" \
  "$DEMO_ROOT/scripts/check_simulation_contract.py"
env PATH="$ROS_PREFIX/bin:$PATH" \
  LD_LIBRARY_PATH="$LD_PATH" \
  PYTHONPATH="$ROS_PREFIX/lib/python3.12/site-packages:$ROS_ROOTFS/usr/lib/python3/dist-packages" \
  PYTHONNOUSERSITE=1 \
  AMENT_PREFIX_PATH="$ROS_PREFIX" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  python3 "$DEMO_ROOT/src/ab_mission.py" --self-test >/dev/null
env PYTHONPATH="$ROS_ROOTFS/usr/lib/python3/dist-packages" PYTHONNOUSERSITE=1 \
  python3 "$DEMO_ROOT/scripts/check_simulation_contract.py" \
    --config "$DEMO_ROOT/config/demo.yaml" \
    --world "$RUNTIME_ROOT/worlds/lidar_slam_course.sdf" >/dev/null

mkdir -p "$LOCK_DIR" "$RUNTIME_ROOT/logs"
# dpkg-query expands its own format variables.
# shellcheck disable=SC2016
"$RUNTIME_ROOT/scripts/proot-run.sh" \
  dpkg-query -W -f='${Package}\t${Version}\n' \
  > "$RUNTIME_ROOT/logs/environment-packages.txt"
package_sha="$(sha256sum "$RUNTIME_ROOT/logs/environment-packages.txt" | awk '{print $1}')"
{
  printf 'runtime_schema=%s\n' "$RUNTIME_SCHEMA"
  printf 'verified_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'px4_commit=%s\n' "$PX4_COMMIT"
  printf 'dlio_commit=%s\n' "$DLIO_COMMIT"
  printf 'mavros_commit=%s\n' "$MAVROS_COMMIT"
  printf 'px4_binary_sha256=%s\n' "$(sha256sum "$PX4_DIR/build/px4_sitl_default/bin/px4" | awk '{print $1}')"
  printf 'dlio_binary_sha256=%s\n' "$(sha256sum "$DLIO_BINARY" | awk '{print $1}')"
  printf 'mavros_core_sha256=%s\n' "$(sha256sum "$RUNTIME_ROOT/mavros-overlay/lib/libmavros.so" | awk '{print $1}')"
  printf 'mavros_plugins_sha256=%s\n' "$(sha256sum "$MAVROS_LIBRARY" | awk '{print $1}')"
  printf 'environment_packages_sha256=%s\n' "$package_sha"
} > "$LOCK_FILE"
echo "runtime_verification=PASS"
echo "runtime_lock=$LOCK_FILE"
