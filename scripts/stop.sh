#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

run_dir=""
if [[ "${1:-}" == "--run-dir" ]]; then
  run_dir="${2:-}"
else
  run_dir="$(current_run 2>/dev/null || true)"
fi
[[ -n "$run_dir" && -d "$run_dir" ]] || exit 0

printf 'stopping_at=%s\nstate=stopping\n' "$(now_iso)" >>"$run_dir/status"

if [[ -f "$run_dir/base-run.txt" ]]; then
  base_run="$(<"$run_dir/base-run.txt")"
  if [[ -d "$base_run" ]]; then
    native_ros timeout --signal=INT --kill-after=2s 15s \
      ros2 run octomap_server octomap_saver_node --ros-args \
      -p octomap_path:="$run_dir/evidence/final-map.bt" \
      >"$run_dir/logs/map-save.log" 2>&1 || true
  fi
fi

stop_group "$run_dir" video
stop_group "$run_dir" rviz
stop_group "$run_dir" xephyr
stop_group "$run_dir" planner

if [[ -f "$run_dir/base-run.txt" ]]; then
  base_run="$(<"$run_dir/base-run.txt")"
  if [[ -d "$base_run" ]]; then
    "$STACK_ROOT/scripts/stop_sim.sh" --run-dir "$base_run" \
      >"$run_dir/logs/base-stack-stop.log" 2>&1 || true
  fi
fi

if [[ -f "$run_dir/evidence/rviz-ab-demo.mp4" ]]; then
  env LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
    "$FFPROBE" -v error -show_entries format=duration,size \
    -of default=noprint_wrappers=1 "$run_dir/evidence/rviz-ab-demo.mp4" \
    >"$run_dir/evidence/video-info.txt" 2>&1 || true
fi
find "$run_dir/evidence" -maxdepth 1 -type f ! -name sha256.txt -print0 | sort -z | \
  xargs -0 -r sha256sum >"$run_dir/evidence/sha256.txt"

printf 'stopped_at=%s\nstate=stopped\n' "$(now_iso)" >>"$run_dir/status"
if [[ -f "$CURRENT_RUN_FILE" ]] && [[ "$(<"$CURRENT_RUN_FILE")" == "$run_dir" ]]; then
  mv "$CURRENT_RUN_FILE" "$run_dir/current-run.closed"
fi
echo "Demo stopped: $run_dir"
