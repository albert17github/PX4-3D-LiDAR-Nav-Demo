#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
run_dir=""
mission_args=()
interactive_mode=0

if [[ "${1:-}" == "--interactive" ]]; then
  mission_args+=(--interactive)
  interactive_mode=1
  shift
fi
if (($# != 0)); then
  echo "Usage: $0 [--interactive]" >&2
  exit 64
fi

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n "$run_dir" ]]; then
    "$ROOT/scripts/stop.sh" --run-dir "$run_dir" || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

"$ROOT/scripts/start.sh"
run_dir="$(<"$ROOT/.runtime/current-run")"
if ((interactive_mode == 1)); then
  echo "Persistent interactive session ready: every safe landing returns to RViz goal selection."
  echo "Choose '2D Goal Pose' again for each flight; press Ctrl+C once to stop the session."
fi
"$ROOT/scripts/fly_ab.sh" "${mission_args[@]}"
sleep "${DEMO_FINAL_HOLD_S:-5}"
gnome-screenshot -f "$run_dir/evidence/final-desktop.png"
env LD_LIBRARY_PATH="$ROS_LD_LIBRARY_PATH" \
  "$FFMPEG" -hide_banner -loglevel error -y \
  -f x11grab -video_size 1280x800 -i "$RVIZ_DISPLAY.0+0,0" \
  -frames:v 1 "$run_dir/evidence/rviz-final.png"
trap - EXIT INT TERM
"$ROOT/scripts/stop.sh" --run-dir "$run_dir"
if ((interactive_mode == 1)); then
  echo "Persistent RViz interactive session stopped: $run_dir"
else
  echo "A→B realtime GUI demo complete: $run_dir"
fi
