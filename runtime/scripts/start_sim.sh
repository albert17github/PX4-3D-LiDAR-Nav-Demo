#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/scripts/lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

PROFILE=""
PX4_FEED=0
WITH_OCTOMAP=0
STARTUP_HEALTH=""
RUN_DIR=""
LOCK_HELD=0
DLIO_OUTPUT=/dlio/odom
PX4_BINARY="$RUNTIME_ROOT/vendor/PX4-Autopilot/build/px4_sitl_default/bin/px4"
DLIO_SOURCE="$RUNTIME_ROOT/third_party/direct_lidar_inertial_odometry"
DLIO_BINARY="$RUNTIME_ROOT/ros2_ws/build/direct_lidar_inertial_odometry/dlio_odom_node"
DLIO_INSTALL="$RUNTIME_ROOT/ros2_ws/install/direct_lidar_inertial_odometry"
DLIO_LD_LIBRARY_PATH="$DLIO_INSTALL/lib:$ROS_LD_LIBRARY_PATH"
ROS_GZ_BRIDGE="$ROS_PREFIX/lib/ros_gz_bridge/parameter_bridge"
TOPIC_TOOLS_RELAY="$ROS_PREFIX/lib/topic_tools/relay"
OCTOMAP_BINARY="$ROS_PREFIX/lib/octomap_server/octomap_server_node"
GROUND_EVIDENCE=""

usage() {
  cat <<'EOF'
Usage: ./runtime/scripts/start_sim.sh --profile dlio --enable-px4-feed \
  --with-octomap --startup-health readiness

This project-owned runtime intentionally exposes only the validated mainline.
EOF
}

while (($#)); do
  case "$1" in
    --profile)
      shift
      PROFILE="${1:-}"
      ;;
    --enable-px4-feed)
      PX4_FEED=1
      ;;
    --with-octomap)
      WITH_OCTOMAP=1
      ;;
    --startup-health)
      shift
      STARTUP_HEALTH="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unsupported argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done
[[ "$PROFILE" == dlio && "$PX4_FEED" == 1 && "$WITH_OCTOMAP" == 1 && \
   "$STARTUP_HEALTH" == readiness ]] || {
  echo "Only the validated DLIO + PX4 feed + OctoMap readiness mainline is supported." >&2
  usage >&2
  exit 64
}

cleanup_failed_start() {
  local rc=$?
  trap - EXIT
  if ((rc != 0)) && [[ -n "$RUN_DIR" && -d "$RUN_DIR" ]]; then
    ((LOCK_HELD == 0)) || {
      flock -u 9 || true
      LOCK_HELD=0
    }
    "$SCRIPT_DIR/stop_sim.sh" --run-dir "$RUN_DIR" --force >/dev/null 2>&1 || true
    append_status "$RUN_DIR" failed "start_exit=$rc"
    echo "Startup failed; evidence retained: $RUN_DIR" >&2
  fi
  exit "$rc"
}
trap cleanup_failed_start EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

locked_hash_matches() {
  local key="$1" file="$2" expected
  expected="$(record_value "$RUNTIME_ROOT/.setup/runtime.lock" "$key")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] && \
    [[ "$(sha256sum "$file" | awk '{print $1}')" == "$expected" ]]
}

preflight() {
  local path cpu_count
  for path in \
    "$RUNTIME_ROOT/.setup/runtime.lock" \
    "$PROOT_RUN" "$PX4_BINARY" "$DLIO_BINARY" \
    "$ROS_GZ_BRIDGE" "$TOPIC_TOOLS_RELAY" "$OCTOMAP_BINARY" \
    "$RUNTIME_ROOT/mavros-overlay/lib/libmavros.so" \
    "$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so" \
    "$ROS_PREFIX/lib/libMrsOctomapPlanner_MinimalOctomapPlanner.so" \
    "$RUNTIME_ROOT/config/dlio_sim.yaml" \
    "$RUNTIME_ROOT/config/mavros_px4_sitl.yaml" \
    "$RUNTIME_ROOT/config/octomap_server.yaml" \
    "$RUNTIME_ROOT/models/x500_lidar_3d/model.sdf" \
    "$RUNTIME_ROOT/worlds/lidar_slam_course.sdf"; do
    [[ -e "$path" ]] || {
      echo "Missing project-owned runtime file: $path" >&2
      return 10
    }
  done
  for path in flock ldd python3 realpath setsid ss taskset timeout; do
    command -v "$path" >/dev/null || {
      echo "Missing host command: $path" >&2
      return 10
    }
  done
  locked_hash_matches px4_binary_sha256 "$PX4_BINARY" || return 10
  locked_hash_matches dlio_binary_sha256 "$DLIO_BINARY" || return 10
  locked_hash_matches mavros_core_sha256 \
    "$RUNTIME_ROOT/mavros-overlay/lib/libmavros.so" || return 10
  locked_hash_matches mavros_plugins_sha256 \
    "$RUNTIME_ROOT/mavros-overlay/lib/libmavros_plugins.so" || return 10
  [[ "$(git -C "$DLIO_SOURCE" rev-parse HEAD)" == \
      "$(record_value "$RUNTIME_ROOT/.setup/runtime.lock" dlio_commit)" ]] || return 10
  env LD_LIBRARY_PATH="$DLIO_LD_LIBRARY_PATH" ldd "$DLIO_BINARY" | \
    grep -Fq 'not found' && return 10
  cpu_count="$(nproc)"
  ((cpu_count >= 4)) || {
    echo "At least four logical CPUs are required for realtime DLIO simulation." >&2
    return 10
  }
}

topic_once() {
  native_ros timeout --signal=INT --kill-after=2s 15s \
    ros2 topic echo --no-daemon --spin-time 5 "$1" --once --timeout 10 \
    >/dev/null 2>&1
}

topic_field_equals() {
  local output
  output="$(native_ros timeout --signal=INT --kill-after=2s 15s \
    ros2 topic echo --no-daemon --spin-time 5 "$1" --once --timeout 10 \
    --field "$2" 2>/dev/null)" || return 1
  output="$(awk 'NF && $0 != "---" {print; exit}' <<< "$output")"
  [[ "$output" == "$3" ]]
}

gazebo_ready() {
  local models topics
  models="$("$PROOT_RUN" bash -lc \
    'timeout --signal=INT --kill-after=2s 6s gz model --list' 2>/dev/null)" || return 1
  topics="$("$PROOT_RUN" bash -lc \
    'timeout --signal=INT --kill-after=2s 6s gz topic -l' 2>/dev/null)" || return 1
  grep -Fqx '    - x500_lidar_3d' <<< "$models" && \
    grep -Fxq '/lidar_3d/points' <<< "$topics"
}

px4_ready() {
  ss -H -lun | awk '$4 ~ /:14580$/ {found=1} END {exit !found}'
}

bridges_ready() {
  local type
  topic_once /clock && topic_once /lidar_3d/points || return 1
  type="$(native_ros timeout 15s ros2 topic type --no-daemon --spin-time 5 \
    /lidar_3d/points 2>/dev/null)" || return 1
  [[ "$type" == sensor_msgs/msg/PointCloud2 ]]
}

mavros_ready() {
  topic_field_equals /mavros/state connected True && topic_once /mavros/imu/data_raw
}

ground_state_ready() {
  native_ros python3 "$RUNTIME_ROOT/scripts/check_ground_state.py" \
    --output "$GROUND_EVIDENCE" --deadline 7 >/dev/null
}

px4_parameter() {
  "$PROOT_RUN" bash -lc \
    "cd /project/vendor/PX4-Autopilot && timeout 8s ./build/px4_sitl_default/bin/px4-param show -q '$1'" \
    2>/dev/null
}

px4_value_equals() {
  local actual
  actual="$(px4_parameter "$1")" || return 1
  awk -v actual="$actual" -v expected="$2" \
    'BEGIN {d=actual-expected; if (d<0)d=-d; exit !(d<0.00001)}'
}

px4_boot_profile_ready() {
  px4_value_equals EKF2_EV_CTRL 1 &&
    px4_value_equals EKF2_MAG_TYPE 6 &&
    px4_value_equals EKF2_GPS_CTRL 0 &&
    px4_value_equals EKF2_BARO_CTRL 1 &&
    px4_value_equals EKF2_HGT_REF 0
}

mavros_aliases_ready() {
  local odom_ned base_frd
  odom_ned="$(native_ros timeout 8s ros2 run tf2_ros tf2_echo \
    odom odom_ned -r 2 2>/dev/null || true)"
  base_frd="$(native_ros timeout 8s ros2 run tf2_ros tf2_echo \
    base_link base_link_frd -r 2 2>/dev/null || true)"
  grep -Fq 'Translation:' <<< "$odom_ned" && grep -Fq 'Translation:' <<< "$base_frd"
}

configure_mavros_tf() {
  native_ros timeout 12s ros2 param set --no-daemon --spin-time 3 --timeout 8 \
    /mavros/local_position tf.send true >/dev/null &&
  native_ros timeout 12s ros2 param set --no-daemon --spin-time 3 --timeout 8 \
    /mavros/local_position tf.frame_id map >/dev/null &&
  native_ros timeout 12s ros2 param set --no-daemon --spin-time 3 --timeout 8 \
    /mavros/local_position tf.child_frame_id base_link >/dev/null
}

mavros_map_tf_ready() {
  local output
  output="$(native_ros timeout 8s ros2 run tf2_ros tf2_echo \
    map base_link -r 2 2>/dev/null || true)"
  grep -Fq 'Translation:' <<< "$output"
}

static_tf_ready() {
  local output
  output="$(native_ros timeout 8s ros2 run tf2_ros tf2_echo \
    base_link lidar_link -r 2 2>/dev/null || true)"
  grep -Eq 'Translation:.*0\.000.*0\.000.*0\.135' <<< "$output"
}

dlio_topic_ready() {
  topic_field_equals "$DLIO_OUTPUT" header.frame_id odom &&
    topic_field_equals "$DLIO_OUTPUT" child_frame_id base_link
}

dlio_stream_ready() {
  native_ros python3 "$RUNTIME_ROOT/scripts/check_odom_stream.py" \
    --topic "$DLIO_OUTPUT" --duration 5 --min-unique-rate 25 --max-gap 0.15 \
    > "$RUN_DIR/evidence/dlio-stream.json"
}

dlio_map_ready() {
  local dlio_tf canonical_tf map_lidar
  dlio_topic_ready || return 1
  dlio_tf="$(native_ros timeout 15s ros2 topic info --no-daemon --spin-time 5 \
    /dlio/tf_unused --verbose 2>/dev/null)" || return 1
  canonical_tf="$(native_ros timeout 15s ros2 topic info --no-daemon --spin-time 5 \
    /tf --verbose 2>/dev/null)" || return 1
  map_lidar="$(native_ros timeout 10s ros2 run tf2_ros tf2_echo \
    map lidar_link -r 2 2>/dev/null || true)"
  grep -Eq '^Publisher count: 1$' <<< "$dlio_tf" &&
    grep -Eq 'Node name: dlio_odom_node$' <<< "$dlio_tf" &&
    grep -Eq 'Node name: mavros$' <<< "$canonical_tf" &&
    grep -Fq 'Translation:' <<< "$map_lidar" &&
    ! grep -Fq 'The tf tree is invalid because it contains a loop' \
      "$RUN_DIR/logs/mavros.log" "$RUN_DIR/logs/dlio.log"
}

route_publisher_free() {
  local info
  info="$(native_ros timeout 15s ros2 topic info --no-daemon --spin-time 5 \
    /mavros/odometry/out --verbose 2>/dev/null)" || return 1
  grep -Eq '^Publisher count: 0$' <<< "$info" &&
    grep -Eq '^Subscription count: [1-9][0-9]*$' <<< "$info"
}

route_ready() {
  local info
  topic_field_equals /mavros/odometry/out header.frame_id odom &&
    topic_field_equals /mavros/odometry/out child_frame_id base_link || return 1
  info="$(native_ros timeout 15s ros2 topic info --no-daemon --spin-time 5 \
    /mavros/odometry/out --verbose 2>/dev/null)" || return 1
  grep -Eq '^Publisher count: 1$' <<< "$info" &&
    grep -Eq '^Subscription count: [1-9][0-9]*$' <<< "$info" &&
    grep -Eq 'Node name: dlio_px4_relay$' <<< "$info"
}

px4_ev_position_fusion_ready() {
  local output="$RUN_DIR/evidence/px4-boot-fusion-flags.txt"
  "$PROOT_RUN" bash -lc \
    'cd /project/vendor/PX4-Autopilot && timeout 12s ./build/px4_sitl_default/bin/px4-listener --instance 0 estimator_status_flags -n 1' \
    > "$output" 2>&1 &&
    grep -Fq 'cs_ev_pos: True' "$output" &&
    grep -Fq 'cs_ev_yaw_fault: False' "$output"
}

octomap_ready() {
  local output frame
  frame="$(native_ros timeout 15s ros2 param get --no-daemon --spin-time 5 \
    --timeout 10 --hide-type /octomap_server frame_id 2>/dev/null)" || return 1
  [[ "$frame" == map ]] || return 1
  output="$(native_ros timeout 15s ros2 topic echo --no-daemon --spin-time 5 \
    /octomap_binary --once --timeout 10 --truncate-length 16 2>/dev/null)" || return 1
  grep -Eq '^[[:space:]]+frame_id: map$' <<< "$output" &&
    grep -Fqx 'binary: true' <<< "$output" &&
    grep -Fqx 'id: OcTree' <<< "$output" &&
    grep -Eq '^resolution: 0\.4(0*)?$' <<< "$output"
}

preflight
ensure_runtime_dirs
exec 9> "$STATE_DIR/lifecycle.lock"
flock -w 5 9 || {
  echo "Another runtime start/stop operation is active" >&2
  exit 11
}
LOCK_HELD=1

if active="$(safe_active_run 2>/dev/null)"; then
  live=0
  for record in "$active"/pids/*.pid; do
    [[ -f "$record" ]] || continue
    name="${record##*/}"
    name="${name%.pid}"
    component_alive "$active" "$name" && live=1
  done
  ((live == 0)) || {
    echo "A project-owned runtime is already active: $active" >&2
    exit 11
  }
  mv "$ACTIVE_RUN_FILE" "$active/active-run.stale"
elif [[ -f "$ACTIVE_RUN_FILE" ]]; then
  mv "$ACTIVE_RUN_FILE" "$STATE_DIR/active-run.invalid-$(date +%Y%m%d-%H%M%S)"
fi

conflicts="$(pgrep -af \
  '[g]z sim|[p]x4_sitl_default/bin/px4 -d|[d]lio_odom_node|[o]ctomap_server_node|[m]avros_node' \
  || true)"
[[ -z "$conflicts" ]] || {
  echo "Conflicting simulation processes exist; refusing to adopt them:" >&2
  printf '%s\n' "$conflicts" >&2
  exit 11
}

umask 077
RUN_DIR="$(mktemp -d "$RUNS_DIR/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
mkdir -p "$RUN_DIR"/{commands,pids,logs,evidence}
: > "$RUN_DIR/status"
: > "$RUN_DIR/component-order"
GROUND_EVIDENCE="$RUN_DIR/evidence/mavros-ground-state-before-relay.json"
{
  printf 'run_id=%s\n' "${RUN_DIR##*/}"
  printf 'project=%s\nstarted_at=%s\n' "$RUNTIME_ROOT" "$(now_iso)"
  printf 'profile=dlio\npx4_feed_enabled=1\noctomap_enabled=1\n'
  printf 'octomap_frame=map\noctomap_pose_source=px4_ekf2_local_position\n'
  printf 'startup_health_mode=readiness\n'
  printf 'px4_commit=%s\ndlio_commit=%s\nmavros_commit=%s\n' \
    "$(record_value "$RUNTIME_ROOT/.setup/runtime.lock" px4_commit)" \
    "$(record_value "$RUNTIME_ROOT/.setup/runtime.lock" dlio_commit)" \
    "$(record_value "$RUNTIME_ROOT/.setup/runtime.lock" mavros_commit)"
} > "$RUN_DIR/manifest.txt"
write_active_run "$RUN_DIR"
append_status "$RUN_DIR" starting 'profile=dlio px4_feed=1 octomap=1'

cpu_count="$(nproc)"
if ((cpu_count >= 8)); then
  DLIO_CPU=6
else
  DLIO_CPU=$((cpu_count - 1))
fi
GZ_RESOURCES=/project/models:/project/worlds:/project/vendor/PX4-Autopilot/Tools/simulation/gz/models:/project/vendor/PX4-Autopilot/Tools/simulation/gz/worlds

spawn_component "$RUN_DIR" gazebo "$RUNTIME_ROOT" \
  "$PROOT_RUN" env GZ_SIM_RESOURCE_PATH="$GZ_RESOURCES" \
  GZ_SIM_SERVER_CONFIG_PATH=/project/config/gazebo-server.config \
  LIBGL_ALWAYS_SOFTWARE=1 SVGA_VGPU10=0 \
  gz sim -r -v 2 /project/worlds/lidar_slam_course.sdf
component_gate "$RUN_DIR" gazebo 'Gazebo model and native LiDAR topic' 90 gazebo_ready

spawn_component "$RUN_DIR" px4 "$RUNTIME_ROOT" \
  "$PROOT_RUN" env PX4_SYS_AUTOSTART=4001 PX4_GZ_STANDALONE=1 \
  PX4_GZ_WORLD=lidar_slam_course PX4_GZ_MODEL_NAME=x500_lidar_3d \
  bash -lc 'cd /project/vendor/PX4-Autopilot && exec ./build/px4_sitl_default/bin/px4 -d'
component_gate "$RUN_DIR" px4 'PX4 MAVLink UDP 14580' 45 px4_ready

spawn_component "$RUN_DIR" clock_bridge "$ROS_GZ_BRIDGE" \
  env USER=root LOGNAME=root LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  "$ROS_GZ_BRIDGE" \
  '/world/lidar_slam_course/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock' \
  --ros-args -r /world/lidar_slam_course/clock:=/clock
spawn_component "$RUN_DIR" pointcloud_bridge "$RUNTIME_ROOT" \
  "$PROOT_RUN" env ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" bash -lc \
  'source /opt/ros/jazzy/setup.bash && exec ros2 run ros_gz_bridge parameter_bridge "/lidar_3d/points@sensor_msgs/msg/PointCloud2[gz.msgs.PointCloudPacked"'
component_gate "$RUN_DIR" pointcloud_bridge 'ROS clock and PointCloud2 bridge' 60 bridges_ready

# LD_LIBRARY_PATH expands in the guest shell.
# shellcheck disable=SC2016
spawn_component "$RUN_DIR" mavros "$RUNTIME_ROOT" \
  "$PROOT_RUN" env ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" bash -lc \
  'source /opt/ros/jazzy/setup.bash; export LD_LIBRARY_PATH=/project/mavros-overlay/lib:${LD_LIBRARY_PATH:-}; exec ros2 launch mrs_uav_px4_api mavros.launch fcu_url:=udp://0.0.0.0:14540@127.0.0.1:14580 gcs_url:=udp://127.0.0.1:14555@ tgt_system:=1 tgt_component:=1 pluginlists_yaml:=/opt/ros/jazzy/share/mrs_uav_px4_api/config/mavros_plugins.yaml config_yaml:=/project/config/mavros_px4_sitl.yaml namespace:=mavros use_sim_time:=true base_link_frame_id:=base_link odom_frame_id:=odom map_frame_id:=map'
component_gate "$RUN_DIR" mavros 'MAVROS heartbeat and PX4 IMU' 75 mavros_ready
component_gate "$RUN_DIR" mavros 'PX4 landed/disarmed before estimator routing' \
  20 ground_state_ready
component_gate "$RUN_DIR" mavros 'pre-applied PX4 external-position boot profile' \
  30 px4_boot_profile_ready
component_gate "$RUN_DIR" mavros 'MAVROS ENU/NED and FLU/FRD aliases' \
  30 mavros_aliases_ready
configure_mavros_tf
component_gate "$RUN_DIR" mavros 'MAVROS map to base_link TF' 30 mavros_map_tf_ready

spawn_component "$RUN_DIR" px4_map_imu_tf "$RUNTIME_ROOT" \
  "$PROOT_RUN" env ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" bash -lc \
  'source /opt/ros/jazzy/setup.bash && exec ros2 run tf2_ros static_transform_publisher --x 0 --y 0 --z 0 --roll 0 --pitch 0 --yaw 0 --frame-id base_link --child-frame-id imu_link --ros-args -r __node:=px4_map_imu_tf'
spawn_component "$RUN_DIR" px4_map_lidar_tf "$RUNTIME_ROOT" \
  "$PROOT_RUN" env ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" \
  RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" bash -lc \
  'source /opt/ros/jazzy/setup.bash && exec ros2 run tf2_ros static_transform_publisher --x 0 --y 0 --z 0.135 --roll 0 --pitch 0 --yaw 0 --frame-id base_link --child-frame-id lidar_link --ros-args -r __node:=px4_map_lidar_tf'
component_gate "$RUN_DIR" px4_map_lidar_tf 'sensor extrinsic TF' 30 static_tf_ready

spawn_component "$RUN_DIR" dlio "$DLIO_BINARY" \
  taskset -c "$DLIO_CPU" env LD_LIBRARY_PATH="$DLIO_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$DLIO_INSTALL:$ROS_PREFIX" \
  COLCON_PREFIX_PATH="$DLIO_INSTALL:$ROS_PREFIX" \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  OMP_NUM_THREADS=1 MALLOC_CHECK_=3 MALLOC_PERTURB_=165 \
  "$DLIO_BINARY" --ros-args --params-file "$RUNTIME_ROOT/config/dlio_sim.yaml" \
  -r pointcloud:=/lidar_3d/points -r imu:=/mavros/imu/data_raw \
  -r odom:=/dlio/odom -r pose:=/dlio/pose -r path:=/dlio/path \
  -r kf_pose:=/dlio/keyframes -r kf_cloud:=/dlio/pointcloud/keyframe \
  -r deskewed:=/dlio/pointcloud/deskewed -r /tf:=/dlio/tf_unused
component_gate "$RUN_DIR" dlio 'DLIO odometry with isolated TF authority' 180 dlio_map_ready
component_gate "$RUN_DIR" dlio 'finite DLIO odometry cadence' 45 dlio_stream_ready
component_gate "$RUN_DIR" dlio 'MAVROS odometry input has no prior publisher' \
  30 route_publisher_free
component_gate "$RUN_DIR" mavros 'PX4 still landed/disarmed before relay' \
  20 ground_state_ready

spawn_component "$RUN_DIR" dlio_px4_relay "$TOPIC_TOOLS_RELAY" \
  env LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  MALLOC_CHECK_=3 MALLOC_PERTURB_=165 "$TOPIC_TOOLS_RELAY" \
  --ros-args -r __node:=dlio_px4_relay \
  -p input_topic:=/dlio/odom -p output_topic:=/mavros/odometry/out -p lazy:=false
component_gate "$RUN_DIR" dlio_px4_relay 'DLIO odometry routed to MAVROS' 120 route_ready
component_gate "$RUN_DIR" dlio_px4_relay 'PX4 fuses fresh external position' \
  90 px4_ev_position_fusion_ready

spawn_component "$RUN_DIR" octomap "$OCTOMAP_BINARY" \
  env LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy OMP_NUM_THREADS=1 \
  MALLOC_CHECK_=3 MALLOC_PERTURB_=165 "$OCTOMAP_BINARY" \
  --ros-args -r __node:=octomap_server -r cloud_in:=/lidar_3d/points \
  --params-file "$RUNTIME_ROOT/config/octomap_server.yaml" \
  -p use_sim_time:=true -p frame_id:=map
component_gate "$RUN_DIR" octomap 'non-empty 0.4 m map-frame OctoMap' 75 octomap_ready

{
  printf 'mode=readiness\n'
  awk -F '\t' '$2 == "gate_passed" {print}' "$RUN_DIR/status"
} > "$RUN_DIR/evidence/startup-readiness-summary.txt"
append_status "$RUN_DIR" running 'startup_readiness_passed mode=readiness'
touch "$RUN_DIR/ready.marker"
flock -u 9
LOCK_HELD=0
trap - EXIT INT TERM
echo "Simulation stack ready."
echo "run_dir=$RUN_DIR"
echo "health=readiness-gates"
echo "stop=$SCRIPT_DIR/stop_sim.sh --run-dir $RUN_DIR"
