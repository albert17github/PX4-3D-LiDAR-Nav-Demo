#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"
CACHE_DIR="$RUNTIME_ROOT/env/cache"
ARCHIVE="$CACHE_DIR/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz"
PROOT_BIN="$RUNTIME_ROOT/env/proot"
ROOTFS_DIR="$RUNTIME_ROOT/env/rootfs"
ROOTFS_TMP="$RUNTIME_ROOT/env/rootfs.extracting"

verify_hash() {
  local expected="$1" file="$2" actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    printf 'SHA256 mismatch: %s\nexpected=%s\nactual=%s\n' "$file" "$expected" "$actual" >&2
    return 1
  }
}

download() {
  local url="$1" output="$2" expected="$3" temporary
  if [[ -f "$output" ]] && verify_hash "$expected" "$output"; then
    return 0
  fi
  temporary="$(mktemp "${output}.partial.XXXXXX")"
  curl -fL --retry 5 --retry-all-errors --connect-timeout 20 "$url" -o "$temporary"
  verify_hash "$expected" "$temporary"
  mv "$temporary" "$output"
}

mkdir -p "$CACHE_DIR"
download "$ROOTFS_ARCHIVE_URL" "$ARCHIVE" "$ROOTFS_ARCHIVE_SHA256"
download "$PROOT_URL" "$PROOT_BIN" "$PROOT_SHA256"
chmod 0755 "$PROOT_BIN"

if [[ ! -f "$ROOTFS_DIR/.bootstrap-complete" ]]; then
  [[ ! -e "$ROOTFS_DIR" && ! -e "$ROOTFS_TMP" ]] || {
    echo "Refusing to overwrite an incomplete rootfs. Inspect: $ROOTFS_DIR $ROOTFS_TMP" >&2
    exit 1
  }
  mkdir -p "$ROOTFS_TMP"
  tar --extract --gzip --file "$ARCHIVE" --directory "$ROOTFS_TMP" \
    --no-same-owner --exclude='dev/*'
  mkdir -p "$ROOTFS_TMP/dev" "$ROOTFS_TMP/tmp"
  touch "$ROOTFS_TMP/.bootstrap-complete"
  mv "$ROOTFS_TMP" "$ROOTFS_DIR"
fi

[[ -x "$ROOTFS_DIR/bin/bash" ]] || {
  echo "Rootfs marker exists but /bin/bash is unavailable: $ROOTFS_DIR" >&2
  exit 1
}
printf 'rootfs_ready=%s\nproot_ready=%s\n' "$ROOTFS_DIR" "$PROOT_BIN"
