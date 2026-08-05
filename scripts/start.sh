#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_runtime
startup_health_mode=readiness
if [[ -n "${PX4_DEMO_STARTUP_HEALTH_MODE:-}" &&
      "${PX4_DEMO_STARTUP_HEALTH_MODE}" != readiness ]]; then
  echo "Only PX4_DEMO_STARTUP_HEALTH_MODE=readiness is supported by the self-contained mainline." >&2
  exit 64
fi
for command in setsid Xephyr xdpyinfo xdotool python3 gnome-screenshot; do
  command -v "$command" >/dev/null || {
    echo "Missing command: $command" >&2
    exit 10
  }
done

if existing="$(current_run 2>/dev/null)"; then
  echo "A demo run is already active: $existing" >&2
  exit 11
fi

mkdir -p "$DEMO_ROOT/.runtime" "$DEMO_ROOT/runs"
run_dir="$(mktemp -d "$DEMO_ROOT/runs/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
mkdir -p "$run_dir"/{logs,pids,evidence}
printf '%s\n' "$run_dir" >"$CURRENT_RUN_FILE"
startup_started_epoch="$(date +%s)"
printf 'started_at=%s\nstate=starting\nstartup_health_mode=%s\n' \
  "$(now_iso)" "$startup_health_mode" >"$run_dir/status"
base_start_pid=""
px4_prepare_pid=""

cleanup_failed_start() {
  local rc=$?
  trap - EXIT
  if [[ -n "$px4_prepare_pid" ]] && kill -0 "$px4_prepare_pid" 2>/dev/null; then
    kill -TERM -- "-$px4_prepare_pid" 2>/dev/null || true
    wait "$px4_prepare_pid" 2>/dev/null || true
  fi
  if [[ -n "$base_start_pid" ]] && kill -0 "$base_start_pid" 2>/dev/null; then
    kill -TERM "$base_start_pid" 2>/dev/null || true
    wait "$base_start_pid" 2>/dev/null || true
  fi
  if ((rc != 0)); then
    printf 'failed_at=%s\nstate=failed\nexit_code=%s\n' "$(now_iso)" "$rc" >>"$run_dir/status"
    "$SCRIPT_DIR/stop.sh" --run-dir "$run_dir" >/dev/null 2>&1 || true
    if [[ -f "$run_dir/base-run.txt" ]]; then
      base_run="$(<"$run_dir/base-run.txt")"
      if [[ -d "$base_run" ]]; then
        "$STACK_ROOT/scripts/stop_sim.sh" --run-dir "$base_run" --force \
          >"$run_dir/logs/base-stack-force-stop.log" 2>&1 || true
      fi
    fi
  fi
  exit "$rc"
}
trap cleanup_failed_start EXIT

if pgrep -f '[Q]GroundControl' >/dev/null 2>&1; then
  echo "QGroundControl is not used by this demo. Close it before starting." >&2
  exit 11
fi
printf 'qgc=disabled\n' >>"$run_dir/status"

echo "[1/6] Preparing the reboot-safe PX4 LIO heading profile..."
boot_profile_started_epoch="$(date +%s)"
if pgrep -f '[b]uild/px4_sitl_default/bin/px4 -d' >/dev/null 2>&1; then
  echo "A PX4 daemon is already running; refusing to alter its parameters." >&2
  exit 11
fi
setsid "$STACK_ROOT/scripts/proot-run.sh" env PX4_SIM_MODEL=shell bash -lc \
  'cd /project/vendor/PX4-Autopilot && exec ./build/px4_sitl_default/bin/px4 -d' \
  >"$run_dir/logs/px4-parameter-prepare.log" 2>&1 &
px4_prepare_pid=$!
px4_parameter_daemon_ready=0
for _ in {1..50}; do
  if px4_parameter_value EKF2_EV_CTRL >/dev/null 2>&1; then
    px4_parameter_daemon_ready=1
    break
  fi
  kill -0 "$px4_prepare_pid" 2>/dev/null || break
  sleep 0.2
done
((px4_parameter_daemon_ready == 1)) || {
  echo "PX4 parameter preparation daemon did not become ready" >&2
  exit 12
}
px4_apply_parameter_profile boot "$run_dir/evidence/px4-lio-yaw-boot-readback.txt"
# PX4's POSIX shutdown client intentionally exits with 255 after asking the
# server to terminate.  The process-exit check below is the real success gate.
px4_client shutdown >/dev/null || true
for _ in {1..50}; do
  kill -0 "$px4_prepare_pid" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "$px4_prepare_pid" 2>/dev/null; then
  echo "PX4 parameter preparation daemon did not stop" >&2
  exit 12
fi
wait "$px4_prepare_pid" || true
px4_prepare_pid=""
boot_profile_ready_epoch="$(date +%s)"
boot_profile_seconds=$((boot_profile_ready_epoch - boot_profile_started_epoch))
printf 'px4_lio_boot_profile=PASS\nstartup_px4_profile_seconds=%s\n' \
  "$boot_profile_seconds" >>"$run_dir/status"
echo "      EKF2_MAG_TYPE=6 (initialization only); project boot contract restored"
echo "      [timing] px4_profile=${boot_profile_seconds}s"

echo "[2/6] Starting visible PX4 + Gazebo + LiDAR + DLIO + OctoMap stack..."
echo "      Project-owned mainline readiness gates are enabled."
base_started_epoch="$(date +%s)"
base_active_before="$(cat "$STACK_ROOT/.runtime/active-run" 2>/dev/null || true)"
set +e
PX4_SIM_MAVROS_OVERLAY_GUEST_LIB_DIR="$MAVROS_OVERLAY_GUEST_LIB_DIR" \
  "$STACK_ROOT/scripts/start_sim.sh" \
  --profile dlio \
  --enable-px4-feed \
  --with-octomap \
  --startup-health "$startup_health_mode" \
  >"$run_dir/logs/base-stack-start.log" 2>&1 &
base_start_pid=$!

base_run=""
base_status_lines=0
base_log_lines=0
mavros_failure_reported=0
while kill -0 "$base_start_pid" 2>/dev/null; do
  candidate="$(cat "$STACK_ROOT/.runtime/active-run" 2>/dev/null || true)"
  if [[ -n "$candidate" && "$candidate" != "$base_active_before" && -d "$candidate" ]]; then
    if [[ "$candidate" != "$base_run" ]]; then
      base_run="$candidate"
      base_status_lines=0
      printf '%s\n' "$base_run" >"$run_dir/base-run.txt"
      echo "      base_run=$base_run"
    fi
    if [[ -f "$base_run/status" ]]; then
      status_lines="$(wc -l <"$base_run/status")"
      if ((status_lines > base_status_lines)); then
        while IFS=$'\t' read -r _ event detail; do
          case "$event" in
            component_starting|gate_waiting|gate_passed|gate_timeout)
              printf '      %-18s %s\n' "[$event]" "$detail"
              ;;
          esac
        done < <(sed -n "$((base_status_lines + 1)),${status_lines}p" "$base_run/status")
        base_status_lines="$status_lines"
      fi
    fi
    if ((mavros_failure_reported == 0)) && [[ -f "$base_run/logs/mavros.log" ]] && \
       grep -Eq 'double free or corruption|\[mavros_node-[0-9]+\]: process has died' \
         "$base_run/logs/mavros.log"; then
      echo "MAVROS exited during startup; aborting immediately. See $base_run/logs/mavros.log" >&2
      mavros_failure_reported=1
      kill -TERM "$base_start_pid" 2>/dev/null || true
    fi
  fi
  if [[ -f "$run_dir/logs/base-stack-start.log" ]]; then
    log_lines="$(wc -l <"$run_dir/logs/base-stack-start.log")"
    if ((log_lines > base_log_lines)); then
      while IFS= read -r line; do
        case "$line" in
          PASS\ *|FAIL\ *|health_evidence=*|Simulation\ stack\ ready.*)
            printf '      %s\n' "$line"
            ;;
        esac
      done < <(sed -n "$((base_log_lines + 1)),${log_lines}p" \
        "$run_dir/logs/base-stack-start.log")
      base_log_lines="$log_lines"
    fi
  fi
  sleep 1
done
wait "$base_start_pid"
base_rc=$?
base_start_pid=""
if [[ -f "$run_dir/logs/base-stack-start.log" ]]; then
  log_lines="$(wc -l <"$run_dir/logs/base-stack-start.log")"
  if ((log_lines > base_log_lines)); then
    while IFS= read -r line; do
      case "$line" in
        PASS\ *|FAIL\ *|health_evidence=*|Simulation\ stack\ ready.*)
          printf '      %s\n' "$line"
          ;;
      esac
    done < <(sed -n "$((base_log_lines + 1)),${log_lines}p" \
      "$run_dir/logs/base-stack-start.log")
  fi
fi
set -e
if ((base_rc != 0)); then
  tail -n 12 "$run_dir/logs/base-stack-start.log" >&2 || true
  exit "$base_rc"
fi

base_run="$(awk -F= '$1 == "run_dir" {value=$2} END {print value}' "$run_dir/logs/base-stack-start.log")"
[[ -n "$base_run" && -d "$base_run" && -f "$base_run/ready.marker" ]] || {
  echo "Base stack did not return a ready run directory" >&2
  exit 12
}
printf '%s\n' "$base_run" >"$run_dir/base-run.txt"
grep -Fxq "startup_health_mode=$startup_health_mode" "$base_run/manifest.txt" || {
  echo "Base stack startup health mode does not match the requested mode" >&2
  exit 12
}
if [[ ! -s "$base_run/evidence/startup-readiness-summary.txt" ]]; then
  echo "Base stack readiness summary is missing" >&2
  exit 12
fi
base_ready_epoch="$(date +%s)"
base_start_seconds=$((base_ready_epoch - base_started_epoch))
printf 'base_stack_ready_at=%s\nstartup_base_seconds=%s\n' \
  "$(now_iso)" "$base_start_seconds" >>"$run_dir/status"
echo "      [timing] base_stack=${base_start_seconds}s"

echo "[3/6] Enabling continuous DLIO position/velocity/yaw authority while landed..."
stage_started_epoch="$base_ready_epoch"
ground_state="$base_run/evidence/mavros-ground-state-before-relay.json"
python3 - "$ground_state" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    state = json.load(stream)
if state.get("result") != "PASS" or state.get("armed") is not False or state.get("landed_state") != 1:
    raise SystemExit("PX4 ground-state evidence does not prove landed/disarmed")
PY
px4_apply_parameter_profile runtime \
  "$run_dir/evidence/px4-lio-yaw-runtime-readback.txt"
fusion_flags="$run_dir/evidence/px4-lio-yaw-estimator-status-flags.txt"
fusion_ready=0
for _ in {1..40}; do
  if px4_client listener --instance 0 estimator_status_flags -n 1 \
      >"$fusion_flags" 2>&1 &&
     grep -Fq 'cs_ev_pos: True' "$fusion_flags" &&
     grep -Fq 'cs_ev_vel: True' "$fusion_flags" &&
     grep -Fq 'cs_ev_yaw: True' "$fusion_flags" &&
     grep -Fq 'cs_mag_hdg: False' "$fusion_flags" &&
     grep -Fq 'cs_mag_3d: False' "$fusion_flags" &&
     grep -Fq 'cs_ev_yaw_fault: False' "$fusion_flags"; then
    fusion_ready=1
    break
  fi
  sleep 0.5
done
((fusion_ready == 1)) || {
  echo "PX4 did not confirm continuous DLIO position/velocity/yaw fusion" >&2
  exit 12
}
px4_param_before="$("$STACK_ROOT/scripts/proot-run.sh" bash -lc \
  'cd /project/vendor/PX4-Autopilot && ./build/px4_sitl_default/bin/px4-param show -q NAV_DLL_ACT')"
if [[ "$px4_param_before" != 0 ]]; then
  "$STACK_ROOT/scripts/proot-run.sh" bash -lc \
    'cd /project/vendor/PX4-Autopilot && ./build/px4_sitl_default/bin/px4-param set NAV_DLL_ACT 0' \
    >"$run_dir/logs/px4-no-gcs-param-set.log" 2>&1
  sleep 1
fi
px4_param_after="$("$STACK_ROOT/scripts/proot-run.sh" bash -lc \
  'cd /project/vendor/PX4-Autopilot && ./build/px4_sitl_default/bin/px4-param show -q NAV_DLL_ACT')"
[[ "$px4_param_after" == 0 ]] || {
  echo "PX4 NAV_DLL_ACT readback failed: $px4_param_after" >&2
  exit 12
}
printf 'NAV_DLL_ACT_before=%s\nNAV_DLL_ACT_after=%s\n' \
  "$px4_param_before" "$px4_param_after" >"$run_dir/evidence/px4-no-gcs-readback.txt"
printf 'px4_nav_dll_act=%s\nqgc=disabled\n' "$px4_param_after" >>"$run_dir/status"
echo "      NAV_DLL_ACT=$px4_param_after (GCS link-loss action disabled for SITL)"
policy_ready_epoch="$(date +%s)"
no_gcs_seconds=$((policy_ready_epoch - stage_started_epoch))
printf 'px4_lio_runtime_profile=PASS\npx4_ev_ctrl=13\npx4_mag_type=6\n' \
  >>"$run_dir/status"
echo "      EKF2_EV_CTRL=13; cs_ev_pos/cs_ev_vel/cs_ev_yaw=True; in-flight mag yaw=False"
echo "      [timing] estimator_and_no_gcs_policy=${no_gcs_seconds}s"

echo "[4/6] Starting upstream MRS MinimalOctomapPlanner..."
stage_started_epoch="$policy_ready_epoch"
setsid env \
  LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  MALLOC_CHECK_=3 MALLOC_PERTURB_=165 \
  "$ROS_PREFIX/lib/rclcpp_components/component_container_mt" \
  --ros-args -r __node:=planner_container -r __ns:=/demo \
  >"$run_dir/logs/planner-container.log" 2>&1 &
planner_pid=$!
record_pid "$run_dir" planner "$planner_pid"

planner_container_ready=0
for _ in {1..30}; do
  if native_ros timeout 3s ros2 node list --no-daemon --spin-time 1 2>/dev/null | \
      grep -Fxq '/demo/planner_container'; then
    planner_container_ready=1
    break
  fi
  sleep 0.5
done
kill -0 "$planner_pid" 2>/dev/null || {
  echo "Planner component container exited" >&2
  exit 12
}
((planner_container_ready == 1)) || {
  echo "Planner component container was not discovered" >&2
  exit 12
}

planner_load_log="$run_dir/logs/planner-load.log"
planner_loaded=0
for attempt in {1..3}; do
  printf 'attempt=%s\n' "$attempt" >>"$planner_load_log"
  # shellcheck disable=SC2088  # '~/' is an intentional ROS private-name remap.
  if native_ros timeout --signal=INT --kill-after=2s 30s \
      ros2 component load --no-daemon --spin-time 10 \
      /demo/planner_container \
      mrs_octomap_planner mrs_octomap_planner::MinimalOctomapPlanner \
      -n minimal_planner --node-namespace /demo \
      -p config:="$DEMO_ROOT/config/planner.yaml" \
      -p use_sim_time:=true \
      -r '~/octomap_in:=/octomap_binary' \
      -r 'get_path_in:=/demo/minimal_planner/get_path' \
      >>"$planner_load_log" 2>&1; then
    planner_loaded=1
    break
  fi
  sleep 1
done
((planner_loaded == 1)) || {
  echo "Planner component could not be loaded after 3 attempts" >&2
  exit 12
}

planner_service_ready=0
planner_services_log="$run_dir/logs/planner-services.log"
for attempt in {1..3}; do
  printf 'attempt=%s\n' "$attempt" >>"$planner_services_log"
  if native_ros timeout 15s ros2 service list --no-daemon --spin-time 10 --show-types \
      >>"$planner_services_log" 2>&1 &&
      grep -Fxq '/demo/minimal_planner/get_path [mrs_modules_msgs/srv/Path]' \
        "$planner_services_log"; then
    planner_service_ready=1
    break
  fi
  sleep 1
done
((planner_service_ready == 1)) || {
  echo "Planner service is not ready" >&2
  exit 12
}
planner_ready_epoch="$(date +%s)"
planner_seconds=$((planner_ready_epoch - stage_started_epoch))
echo "      [timing] planner=${planner_seconds}s"

echo "[5/6] Opening visible RViz window on desktop..."
stage_started_epoch="$planner_ready_epoch"
display_number="${RVIZ_DISPLAY#:}"
[[ ! -e "/tmp/.X11-unix/X$display_number" && ! -e "/tmp/.X${display_number}-lock" ]] || {
  echo "RViz display $RVIZ_DISPLAY is already in use" >&2
  exit 11
}
setsid env DISPLAY="${DISPLAY:-:0}" \
  Xephyr "$RVIZ_DISPLAY" -screen 1280x800 -nolisten tcp -noreset -ac -br \
  >"$run_dir/logs/xephyr.log" 2>&1 &
xephyr_pid=$!
record_pid "$run_dir" xephyr "$xephyr_pid"
for _ in {1..30}; do
  env DISPLAY="$RVIZ_DISPLAY" xdpyinfo >/dev/null 2>&1 && break
  sleep 0.25
done
env DISPLAY="$RVIZ_DISPLAY" xdpyinfo >/dev/null 2>&1 || {
  echo "RViz display failed to open" >&2
  exit 12
}

RVIZ_QT_PLUGIN_PATH="$ROS_ROOTFS/usr/lib/x86_64-linux-gnu/qt5/plugins"
RVIZ_OGRE_PLUGIN_DIR="$ROS_PREFIX/opt/rviz_ogre_vendor/lib/OGRE"
RVIZ_LD_LIBRARY_PATH="$ROS_PREFIX/opt/rviz_ogre_vendor/lib:$ROS_LD_LIBRARY_PATH"
setsid env \
  DISPLAY="$RVIZ_DISPLAY" QT_QPA_PLATFORM=xcb \
  QT_PLUGIN_PATH="$RVIZ_QT_PLUGIN_PATH" \
  QT_QPA_PLATFORM_PLUGIN_PATH="$RVIZ_QT_PLUGIN_PATH/platforms" \
  OGRE_PLUGIN_DIR="$RVIZ_OGRE_PLUGIN_DIR" \
  LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=true SVGA_VGPU10=0 \
  LD_LIBRARY_PATH="$RVIZ_LD_LIBRARY_PATH" \
  AMENT_PREFIX_PATH="$ROS_PREFIX" COLCON_PREFIX_PATH="$ROS_PREFIX" \
  ROS_VERSION=2 ROS_PYTHON_VERSION=3 ROS_DISTRO=jazzy \
  ROS_DOMAIN_ID="$ROS_DOMAIN_ID_VALUE" RMW_IMPLEMENTATION="$RMW_IMPLEMENTATION_VALUE" \
  "$ROS_PREFIX/lib/rviz2/rviz2" -d "$DEMO_ROOT/config/demo.rviz" \
  --ros-args -r __node:=demo_rviz -p use_sim_time:=true \
  >"$run_dir/logs/rviz.log" 2>&1 &
rviz_pid=$!
record_pid "$run_dir" rviz "$rviz_pid"

for _ in {1..60}; do
  if env DISPLAY="$RVIZ_DISPLAY" xdotool search --onlyvisible --class rviz2 >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
env DISPLAY="$RVIZ_DISPLAY" xdotool search --onlyvisible --class rviz2 >/dev/null 2>&1 || {
  echo "Visible RViz window did not appear" >&2
  exit 12
}

echo "[6/6] Starting RViz video recording..."
setsid env LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  "$FFMPEG" -hide_banner -loglevel warning -y \
  -f x11grab -video_size 1280x800 -framerate 8 -i "$RVIZ_DISPLAY.0+0,0" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  "$run_dir/evidence/rviz-ab-demo.mp4" \
  >"$run_dir/logs/video.log" 2>&1 &
video_pid=$!
record_pid "$run_dir" video "$video_pid"

# The RViz recording is confined to Xephyr.  Preserve one host-compositor
# screenshot as well, so the final evidence visibly includes the Gazebo GUI.
sleep 1
gnome-screenshot -f "$run_dir/evidence/gazebo-rviz-desktop.png" \
  >"$run_dir/logs/desktop-screenshot.log" 2>&1
[[ -s "$run_dir/evidence/gazebo-rviz-desktop.png" ]] || {
  echo "Gazebo/RViz desktop screenshot was not saved" >&2
  exit 12
}

ready_epoch="$(date +%s)"
rviz_recording_seconds=$((ready_epoch - stage_started_epoch))
startup_total_seconds=$((ready_epoch - startup_started_epoch))
printf 'ready_at=%s\nstate=ready\nbase_run=%s\nstartup_no_gcs_seconds=%s\nstartup_planner_seconds=%s\nstartup_rviz_recording_seconds=%s\nstartup_total_seconds=%s\n' \
  "$(now_iso)" "$base_run" "$no_gcs_seconds" "$planner_seconds" \
  "$rviz_recording_seconds" "$startup_total_seconds" >>"$run_dir/status"
echo "      [timing] rviz_and_recording=${rviz_recording_seconds}s total=${startup_total_seconds}s"
trap - EXIT
echo "Demo stack ready."
echo "demo_run=$run_dir"
echo "base_run=$base_run"
echo "next=$SCRIPT_DIR/fly_ab.sh"
