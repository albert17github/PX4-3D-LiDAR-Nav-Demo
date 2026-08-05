#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/scripts/lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"
REQUESTED=""
FORCE=0
RESULT=0
declare -A STOPPED=()

while (($#)); do
  case "$1" in
    --run-dir)
      shift
      REQUESTED="${1:-}"
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      echo "Usage: $0 [--run-dir PATH] [--force]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
  shift
done

ensure_runtime_dirs
exec 9> "$STATE_DIR/lifecycle.lock"
flock -w 5 9 || {
  echo "Another runtime start/stop operation is active" >&2
  exit 40
}
if [[ -n "$REQUESTED" ]]; then
  RUN_DIR="$(realpath -e "$REQUESTED" 2>/dev/null || true)"
  runs_real="$(realpath -e "$RUNS_DIR")"
  [[ "$RUN_DIR" == "$runs_real/"* ]] || {
    echo "Refusing unsafe run path: $REQUESTED" >&2
    exit 40
  }
else
  RUN_DIR="$(safe_active_run 2>/dev/null || true)"
fi
if [[ -z "$RUN_DIR" || ! -d "$RUN_DIR" ]]; then
  echo "No active project-owned runtime."
  exit 0
fi
append_status "$RUN_DIR" stopping "force=$FORCE"

group_alive() {
  local pgid="$1"
  ps -eo pgid=,stat= | awk -v wanted="$pgid" \
    '$1 == wanted && $2 !~ /^Z/ {found=1} END {exit !found}'
}

wait_group() {
  local pgid="$1" seconds="$2"
  local deadline=$((SECONDS + seconds))
  while ((SECONDS < deadline)); do
    group_alive "$pgid" || return 0
    sleep 0.25
  done
  ! group_alive "$pgid"
}

stop_one() {
  local name="$1" file pgid
  [[ -z "${STOPPED[$name]:-}" ]] || return 0
  file="$RUN_DIR/pids/$name.pid"
  [[ -f "$file" ]] || return 0
  pgid="$(record_value "$file" pgid)"
  if ! component_alive "$RUN_DIR" "$name"; then
    if group_alive "$pgid"; then
      echo "Refusing to signal an unverifiable process group: $name PGID=$pgid" >&2
      append_status "$RUN_DIR" component_identity_mismatch "$name pgid=$pgid"
      RESULT=40
      return 1
    fi
    STOPPED["$name"]=1
    return 0
  fi
  echo "Stopping $name (PGID $pgid)"
  kill -INT -- "-$pgid" 2>/dev/null || true
  if wait_group "$pgid" 15; then
    STOPPED["$name"]=1
    append_status "$RUN_DIR" component_stopped "$name signal=SIGINT"
    return 0
  fi
  component_alive "$RUN_DIR" "$name" || {
    echo "Identity changed after SIGINT; refusing escalation: $name" >&2
    RESULT=40
    return 1
  }
  kill -TERM -- "-$pgid" 2>/dev/null || true
  if wait_group "$pgid" 5; then
    STOPPED["$name"]=1
    append_status "$RUN_DIR" component_stopped "$name signal=SIGTERM"
    return 0
  fi
  if ((FORCE)) && component_alive "$RUN_DIR" "$name"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    if wait_group "$pgid" 3; then
      STOPPED["$name"]=1
      append_status "$RUN_DIR" component_stopped "$name signal=SIGKILL"
      return 0
    fi
  fi
  echo "Process group remains alive: $name PGID=$pgid" >&2
  RESULT=40
  return 1
}

# Stop producers before the PCL/OctoMap consumers, and drain callbacks before
# tearing down DLIO and its MAVROS relay.
stop_one pointcloud_bridge || true
sleep 3
stop_one octomap || true
stop_one dlio || true
sleep 3
stop_one dlio_px4_relay || true

if [[ -s "$RUN_DIR/component-order" ]]; then
  while IFS= read -r name; do
    valid_component "$name" || {
      RESULT=40
      continue
    }
    stop_one "$name" || true
  done < <(tac "$RUN_DIR/component-order")
fi

scan="$RUN_DIR/evidence/shutdown-crash-scan.txt"
: > "$scan"
for log in "$RUN_DIR"/logs/*.log; do
  [[ -f "$log" ]] || continue
  grep -HnEi \
    'segmentation fault|sigsegv|double free|corrupted|core dumped|terminate called' \
    "$log" >> "$scan" 2>/dev/null || true
done
if [[ -s "$scan" ]]; then
  append_status "$RUN_DIR" shutdown_crash_evidence "file=$scan"
  RESULT=40
else
  printf '%s\n' 'PASS: no owned-component crash signature found.' > "$scan"
fi

if ((RESULT == 0)); then
  append_status "$RUN_DIR" stopped 'all_owned_groups_stopped'
  if [[ -f "$ACTIVE_RUN_FILE" ]] && \
     [[ "$(< "$ACTIVE_RUN_FILE")" == "$RUN_DIR" ]]; then
    mv "$ACTIVE_RUN_FILE" "$RUN_DIR/active-run.closed"
  fi
  echo "Stopped run: $RUN_DIR"
else
  append_status "$RUN_DIR" stop_failed 'residual_or_identity_mismatch'
  echo "Stop incomplete; inspect: $RUN_DIR" >&2
fi
exit "$RESULT"
