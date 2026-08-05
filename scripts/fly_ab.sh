#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

mission_args=()
mission_mode="fixed_ab"
if [[ "${1:-}" == "--interactive" ]]; then
  mission_args+=(--interactive)
  mission_mode="interactive_rviz_goal"
  shift
fi
if (($# != 0)); then
  echo "Usage: $0 [--interactive]" >&2
  exit 64
fi

run_dir="$(current_run)" || {
  echo "No active demo. Run ./scripts/start.sh first." >&2
  exit 20
}
[[ -f "$run_dir/base-run.txt" ]] || {
  echo "Active demo has no base run" >&2
  exit 20
}

printf 'mission_started_at=%s\nstate=flying\nmission_mode=%s\n' \
  "$(now_iso)" "$mission_mode" >>"$run_dir/status"
if [[ "$mission_mode" == "interactive_rviz_goal" ]]; then
  echo "RViz interactive mode: choose '2D Goal Pose', then click and drag on the map."
  echo "The selected XY flies at 2.2 m; the arrow is held as the mission heading."
  echo "After each safe landing, choose another goal. Press Ctrl+C when finished."
fi
set +e
native_ros taskset -c 0-5,7 python3 "$DEMO_ROOT/src/ab_mission.py" \
  --config "$DEMO_ROOT/config/demo.yaml" \
  --result "$run_dir/evidence/mission-result.json" \
  "${mission_args[@]}" \
  2>&1 | tee "$run_dir/logs/mission.log"
mission_rc=${PIPESTATUS[0]}
set -e

if ((mission_rc == 0)); then
  printf 'mission_finished_at=%s\nstate=landed\n' "$(now_iso)" >>"$run_dir/status"
else
  printf 'mission_failed_at=%s\nstate=mission_failed\nexit_code=%s\n' \
    "$(now_iso)" "$mission_rc" >>"$run_dir/status"
fi
exit "$mission_rc"
