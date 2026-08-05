#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=runtime/config/versions.env
source /project/config/versions.env
JOBS="${PX4_DEMO_SETUP_JOBS:-4}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || exit 64
mkdir -p /project/logs /project/ros2_ws /project/mavros-build /project/mavros-overlay

if [[ "${PX4_DEMO_HAVE_PX4:-0}" != 1 ]]; then
  echo "[build 1/3] PX4 SITL"
  make -C /project/vendor/PX4-Autopilot -j"$JOBS" px4_sitl_default
else
  echo "[build 1/3] PX4 SITL already present"
fi

# ROS environment hooks are not nounset-clean.
set +u
# This path exists inside the generated rootfs.
# shellcheck disable=SC1091
source /opt/ros/jazzy/setup.bash
set -u

if [[ "${PX4_DEMO_HAVE_DLIO:-0}" != 1 ]]; then
  echo "[build 2/3] DLIO"
  colcon --log-base /project/logs/dlio-colcon build \
    --base-paths /project/third_party/direct_lidar_inertial_odometry \
    --build-base /project/ros2_ws/build \
    --install-base /project/ros2_ws/install \
    --packages-select direct_lidar_inertial_odometry \
    --symlink-install \
    --parallel-workers "$JOBS" \
    --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo
else
  echo "[build 2/3] DLIO already present"
fi

if [[ "${PX4_DEMO_HAVE_MAVROS:-0}" != 1 ]]; then
  echo "[build 3/3] MAVROS race-fix overlay"
  colcon --log-base /project/logs/mavros-colcon build \
    --base-paths /project/mavros-src \
    --build-base /project/mavros-build \
    --install-base /project/mavros-overlay \
    --merge-install \
    --packages-select mavros \
    --parallel-workers "$JOBS" \
    --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo
else
  echo "[build 3/3] MAVROS overlay already present"
fi
