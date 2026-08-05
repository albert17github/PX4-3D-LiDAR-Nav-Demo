#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$ROOT/runtime"
SEED_FROM=""
VERIFY_ONLY=0
INSTALL_HOST_DEPS=0
JOBS="${PX4_DEMO_SETUP_JOBS:-}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [OPTIONS]

Builds the complete project-owned PX4/ROS/Gazebo runtime without modifying or
depending on another project directory.

Options:
  --jobs N              Parallel build jobs (default: min(nproc, 4)).
  --install-host-deps   Install the small Ubuntu desktop prerequisites via sudo.
  --seed-from PATH      Copy validated local caches/builds, then verify them.
  --verify-only         Do not download or build; verify the current runtime.
  -h, --help            Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --jobs)
      shift
      JOBS="${1:-}"
      ;;
    --install-host-deps)
      INSTALL_HOST_DEPS=1
      ;;
    --seed-from)
      shift
      SEED_FROM="${1:-}"
      ;;
    --verify-only)
      VERIFY_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "This reproducible runtime currently supports Linux x86_64 only." >&2
  exit 10
}
if [[ -z "$JOBS" ]]; then
  JOBS="$(nproc)"
  ((JOBS <= 4)) || JOBS=4
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || {
  echo "--jobs must be a positive integer" >&2
  exit 64
}
export PX4_DEMO_SETUP_JOBS="$JOBS"

host_commands=(bash curl flock git gzip ldd nproc python3 realpath setsid sha256sum ss tar taskset timeout)
desktop_commands=(Xephyr gnome-screenshot xdpyinfo xdotool)
missing=()
for command in "${host_commands[@]}" "${desktop_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
if (("${#missing[@]}" > 0)) && ((INSTALL_HOST_DEPS)); then
  command -v sudo >/dev/null || {
    echo "sudo is required to install host prerequisites" >&2
    exit 10
  }
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates curl git gzip iproute2 procps python3 rsync tar \
    util-linux x11-utils xdotool xserver-xephyr gnome-screenshot
  missing=()
  for command in "${host_commands[@]}" "${desktop_commands[@]}"; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
fi
if (("${#missing[@]}" > 0)); then
  printf 'Missing host commands: %s\n' "${missing[*]}" >&2
  echo "Run ./setup.sh --install-host-deps (or install the listed Ubuntu packages)." >&2
  exit 10
fi
if [[ -n "$SEED_FROM" ]] && ! command -v rsync >/dev/null; then
  echo "--seed-from requires rsync; use --install-host-deps or install rsync." >&2
  exit 10
fi

if ((VERIFY_ONLY)); then
  exec "$RUNTIME_ROOT/scripts/verify-runtime.sh"
fi

mkdir -p "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/.setup"
free_kib="$(df -Pk "$ROOT" | awk 'NR == 2 {print $4}')"
if [[ ! -f "$RUNTIME_ROOT/env/rootfs/.packages-complete" ]] && ((free_kib < 20971520)); then
  echo "At least 20 GiB free space is required for a fresh runtime." >&2
  exit 10
fi

echo "[setup 1/5] Fetching pinned upstream source trees..."
PX4_DEMO_SEED_SOURCE="$SEED_FROM" "$RUNTIME_ROOT/scripts/fetch-sources.sh" \
  2>&1 | tee "$RUNTIME_ROOT/logs/fetch-sources.log"
if [[ -n "$SEED_FROM" ]]; then
  echo "[setup 2/5] Importing validated local cache (no links are retained)..."
  "$RUNTIME_ROOT/scripts/seed-runtime.sh" "$SEED_FROM" \
    2>&1 | tee "$RUNTIME_ROOT/logs/seed-runtime.log"
else
  echo "[setup 2/5] Downloading and verifying Ubuntu rootfs..."
  "$RUNTIME_ROOT/scripts/bootstrap-rootfs.sh" \
    2>&1 | tee "$RUNTIME_ROOT/logs/bootstrap-rootfs.log"
fi

if [[ ! -f "$RUNTIME_ROOT/env/rootfs/.packages-complete" ]]; then
  echo "[setup 3/5] Installing PX4, ROS 2 Jazzy, Gazebo, MAVROS, OctoMap and MRS packages..."
  PROOT_DPKG_COMPAT=1 "$RUNTIME_ROOT/scripts/proot-run.sh" \
    bash /project/env/install-packages.sh \
    2>&1 | tee "$RUNTIME_ROOT/logs/install-packages.log"
else
  echo "[setup 3/5] Package environment already present"
fi

echo "[setup 4/5] Building missing pinned source components..."
"$RUNTIME_ROOT/scripts/build-runtime.sh" 2>&1 | tee "$RUNTIME_ROOT/logs/build-runtime.log"
echo "[setup 5/5] Verifying source, patches, binaries and package manifest..."
"$RUNTIME_ROOT/scripts/verify-runtime.sh" 2>&1 | tee "$RUNTIME_ROOT/logs/verify-runtime.log"

echo "Setup complete."
echo "Next: ./demo.sh --interactive"
