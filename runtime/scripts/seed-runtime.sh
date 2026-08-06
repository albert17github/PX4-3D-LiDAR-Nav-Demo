#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"
SOURCE="${1:-}"
[[ -n "$SOURCE" && -d "$SOURCE" ]] || {
  echo "Usage: $0 /absolute/path/to/validated-old-stack" >&2
  exit 64
}
SOURCE="$(realpath -e "$SOURCE")"
[[ "$SOURCE" != "$RUNTIME_ROOT" ]] || {
  echo "Seed source and destination must differ" >&2
  exit 64
}

for required in \
  "$SOURCE/env/rootfs/.bootstrap-complete" \
  "$SOURCE/env/proot" \
  "$SOURCE/vendor/PX4-Autopilot/build/px4_sitl_default/bin/px4" \
  "$SOURCE/ros2_ws/build/direct_lidar_inertial_odometry/dlio_odom_node" \
  "$SOURCE/runtime/mavros-overlay/lib/libmavros.so" \
  "$SOURCE/runtime/mavros-overlay/lib/libmavros_plugins.so"; do
  [[ -e "$required" ]] || {
    echo "Seed source is incomplete: $required" >&2
    exit 10
  }
done
[[ "$(sha256sum "$SOURCE/env/proot" | awk '{print $1}')" == "$PROOT_SHA256" ]]
[[ "$(sha256sum "$SOURCE/vendor/PX4-Autopilot/build/px4_sitl_default/bin/px4" | awk '{print $1}')" == "$LOCAL_SEED_PX4_BINARY_SHA256" ]]
[[ "$(sha256sum "$SOURCE/ros2_ws/build/direct_lidar_inertial_odometry/dlio_odom_node" | awk '{print $1}')" == "$LOCAL_SEED_DLIO_BINARY_SHA256" ]]
[[ "$(sha256sum "$SOURCE/runtime/mavros-overlay/lib/libmavros.so" | awk '{print $1}')" == "$LOCAL_SEED_MAVROS_CORE_SHA256" ]]
[[ "$(sha256sum "$SOURCE/runtime/mavros-overlay/lib/libmavros_plugins.so" | awk '{print $1}')" == "$LOCAL_SEED_MAVROS_BINARY_SHA256" ]]
command -v rsync >/dev/null || {
  echo "rsync is required for --seed-from" >&2
  exit 10
}

mkdir -p "$RUNTIME_ROOT/env" "$RUNTIME_ROOT/vendor/PX4-Autopilot" \
  "$RUNTIME_ROOT/ros2_ws" "$RUNTIME_ROOT/mavros-overlay" "$RUNTIME_ROOT/.setup"
if [[ ! -f "$RUNTIME_ROOT/env/rootfs/.seed-copy-complete" ]]; then
  mkdir -p "$RUNTIME_ROOT/env/rootfs"
  rsync -aH \
    --exclude='/PX4-LiDAR-SLAM-Sim/***' \
    --exclude='/RVPX4/***' \
    --exclude='/home/***' \
    --exclude='/project/***' \
    --exclude='/root/.Xauthority' \
    --exclude='/tmp/.X11-unix/***' \
    --exclude='/run/user/***' \
    --exclude='/var/lib/snapd/void/***' \
    "$SOURCE/env/rootfs/" "$RUNTIME_ROOT/env/rootfs/"
  touch "$RUNTIME_ROOT/env/rootfs/.seed-copy-complete"
fi
if [[ ! -e "$RUNTIME_ROOT/env/proot" ]]; then
  install -m 0755 "$SOURCE/env/proot" "$RUNTIME_ROOT/env/proot"
fi
if [[ -f "$SOURCE/env/cache/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz" && \
      ! -f "$RUNTIME_ROOT/env/cache/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz" ]]; then
  mkdir -p "$RUNTIME_ROOT/env/cache"
  cp --reflink=auto "$SOURCE/env/cache/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz" \
    "$RUNTIME_ROOT/env/cache/"
fi

# Copy only reusable PX4 build products.  Historical ULogs account for most of
# the old 14 GB build tree and intentionally stay in the archive project.
rsync -a --exclude='/px4_sitl_default/rootfs/log/***' \
  "$SOURCE/vendor/PX4-Autopilot/build/" "$RUNTIME_ROOT/vendor/PX4-Autopilot/build/"
for tree in build install; do
  if [[ -d "$SOURCE/ros2_ws/$tree/direct_lidar_inertial_odometry" ]]; then
    mkdir -p "$RUNTIME_ROOT/ros2_ws/$tree"
    cp -a --reflink=auto "$SOURCE/ros2_ws/$tree/direct_lidar_inertial_odometry" \
      "$RUNTIME_ROOT/ros2_ws/$tree/"
  fi
done
if [[ ! -f "$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so" ]]; then
  cp -a --reflink=auto "$SOURCE/runtime/mavros-overlay/." "$RUNTIME_ROOT/mavros-overlay/"
fi
touch "$RUNTIME_ROOT/env/rootfs/.packages-complete"
printf 'px4_commit=%s\n' "$PX4_COMMIT" > "$RUNTIME_ROOT/.setup/px4-build.inputs"
printf 'dlio_commit=%s\ndlio_patch_sha256=%s\n' \
  "$DLIO_COMMIT" "$DLIO_PATCH_SHA256" > "$RUNTIME_ROOT/.setup/dlio-build.inputs"
printf 'seed_source=%s\nseeded_at=%s\n' "$SOURCE" "$(date --iso-8601=seconds)" \
  > "$RUNTIME_ROOT/.setup/local-seed.txt"
echo "Local cache copied; runtime files no longer resolve through the source path."
