#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="$RUNTIME_ROOT/env/rootfs"
PROOT_BIN="$RUNTIME_ROOT/env/proot"

[[ -x "$PROOT_BIN" && -x "$ROOTFS_DIR/bin/bash" ]] || {
  echo "Runtime rootfs is missing. Run: $(dirname "$RUNTIME_ROOT")/setup.sh" >&2
  exit 10
}

mkdir -p "$ROOTFS_DIR/project" "$ROOTFS_DIR/tmp" "$ROOTFS_DIR/run/user/$(id -u)"
bindings=(
  -b /dev
  -b /proc
  -b /sys
  -b /etc/resolv.conf
  -b /etc/hosts
  -b "$RUNTIME_ROOT:/project"
)
if [[ "${PROOT_DPKG_COMPAT:-0}" == 1 ]]; then
  bindings+=(
    -b "$RUNTIME_ROOT/env/stubs/systemd-tmpfiles:/usr/bin/systemd-tmpfiles"
    -b "$RUNTIME_ROOT/env/stubs/ucf-proot:/usr/bin/ucf"
    -b "$RUNTIME_ROOT/env/stubs/ucf-proot:/usr/bin/ucfr"
  )
fi
[[ ! -d /tmp/.X11-unix ]] || bindings+=(-b /tmp/.X11-unix)
if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
  bindings+=(-b "$XDG_RUNTIME_DIR")
fi
if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
  bindings+=(-b "$XAUTHORITY:/root/.Xauthority")
elif [[ -f "${HOME:-/nonexistent}/.Xauthority" ]]; then
  bindings+=(-b "$HOME/.Xauthority:/root/.Xauthority")
fi

exec "$PROOT_BIN" -0 -r "$ROOTFS_DIR" -w /project "${bindings[@]}" \
  /usr/bin/env HOME=/root USER=root LOGNAME=root \
  DISPLAY="${DISPLAY:-:0}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
  QT_X11_NO_MITSHM=1 SVGA_VGPU10="${SVGA_VGPU10:-0}" \
  DEBIAN_FRONTEND=noninteractive "$@"
