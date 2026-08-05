#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=runtime/config/versions.env
source "$RUNTIME_ROOT/config/versions.env"
JOBS="${PX4_DEMO_SETUP_JOBS:-4}"
export GIT_TERMINAL_PROMPT=0

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || {
  echo "PX4_DEMO_SETUP_JOBS must be a positive integer" >&2
  exit 64
}
mkdir -p "$RUNTIME_ROOT/vendor" "$RUNTIME_ROOT/third_party"
SEED_SOURCE="${PX4_DEMO_SEED_SOURCE:-}"
if [[ -n "$SEED_SOURCE" ]]; then
  SEED_SOURCE="$(realpath -e "$SEED_SOURCE")"
fi

checkout_exact() {
  local repository="$1" ref="$2" commit="$3" destination="$4"
  local local_source="${5:-}"
  if [[ ! -d "$destination/.git" ]]; then
    [[ ! -e "$destination" ]] || {
      echo "Refusing to overwrite non-Git source directory: $destination" >&2
      return 1
    }
    if [[ -n "$local_source" && -e "$local_source/.git" ]]; then
      git clone --local --no-checkout "$local_source" "$destination"
      git -C "$destination" remote set-url origin "$repository"
    else
      mkdir -p "$destination"
      git -C "$destination" init
      git -C "$destination" remote add origin "$repository"
    fi
  fi
  [[ "$(git -C "$destination" remote get-url origin)" == "$repository" ]] || {
    echo "Unexpected origin for $destination" >&2
    return 1
  }
  if ! git -C "$destination" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$destination" fetch --force --filter=blob:none --depth 1 origin "$ref"
  fi
  git -C "$destination" checkout --detach "$commit"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$commit" ]]
}

clone_local_recursive() {
  local source="$1" destination="$2" commit="$3" origin path subcommit
  git clone --local --no-checkout "$source" "$destination"
  origin="$(git -C "$source" remote get-url origin)"
  git -C "$destination" remote set-url origin "$origin"
  git -C "$destination" checkout --detach "$commit"
  [[ -f "$destination/.gitmodules" ]] || return 0
  while read -r _ path; do
    [[ -n "$path" && -e "$source/$path/.git" ]] || {
      echo "Local seed is missing initialized submodule: $source/$path" >&2
      return 1
    }
    subcommit="$(git -C "$destination" ls-tree HEAD -- "$path" | awk '{print $3}')"
    [[ "$subcommit" =~ ^[0-9a-f]{40}$ ]] || return 1
    mkdir -p "$(dirname "$destination/$path")"
    clone_local_recursive "$source/$path" "$destination/$path" "$subcommit"
  done < <(git -C "$destination" config --file .gitmodules --get-regexp '^submodule\..*\.path$')
}

PX4_DIR="$RUNTIME_ROOT/vendor/PX4-Autopilot"
if [[ -n "$SEED_SOURCE" && ! -e "$PX4_DIR" ]]; then
  clone_local_recursive "$SEED_SOURCE/vendor/PX4-Autopilot" "$PX4_DIR" "$PX4_COMMIT"
else
  checkout_exact "$PX4_REPOSITORY" "refs/tags/$PX4_TAG" "$PX4_COMMIT" "$PX4_DIR"
  git -C "$PX4_DIR" submodule sync --recursive
  git -C "$PX4_DIR" -c submodule.fetchJobs="$JOBS" submodule update \
    --init --recursive --depth 1 --jobs "$JOBS"
fi
[[ -z "$(git -C "$PX4_DIR" status --short --untracked-files=no)" ]] || {
  echo "PX4 source has unexpected tracked changes" >&2
  exit 1
}

DLIO_DIR="$RUNTIME_ROOT/third_party/direct_lidar_inertial_odometry"
DLIO_PATCH="$RUNTIME_ROOT/patches/dlio-ros2-upstream-fixes.patch"
checkout_exact "$DLIO_REPOSITORY" "refs/heads/$DLIO_BRANCH" "$DLIO_COMMIT" "$DLIO_DIR" \
  "${SEED_SOURCE:+$SEED_SOURCE/third_party/direct_lidar_inertial_odometry}"
[[ "$(sha256sum "$DLIO_PATCH" | awk '{print $1}')" == "$DLIO_PATCH_SHA256" ]]
if git -C "$DLIO_DIR" apply --reverse --check "$DLIO_PATCH" >/dev/null 2>&1; then
  :
elif git -C "$DLIO_DIR" apply --check "$DLIO_PATCH"; then
  git -C "$DLIO_DIR" apply "$DLIO_PATCH"
else
  echo "DLIO patch cannot be applied or verified" >&2
  exit 1
fi
[[ "$(sha256sum "$DLIO_DIR/include/dlio/odom.h" | awk '{print $1}')" == "$DLIO_HEADER_PATCHED_SHA256" ]]
[[ "$(sha256sum "$DLIO_DIR/src/dlio/odom.cc" | awk '{print $1}')" == "$DLIO_ODOM_PATCHED_SHA256" ]]

MAVROS_DIR="$RUNTIME_ROOT/mavros-src"
MAVROS_PATCH="$RUNTIME_ROOT/patches/mavros-2.14.0-vehicles-lock.patch"
MAVROS_ROUTER_PATCH="$RUNTIME_ROOT/patches/mavros-2.14.0-router-lock.patch"
checkout_exact "$MAVROS_REPOSITORY" "refs/tags/$MAVROS_TAG" "$MAVROS_COMMIT" "$MAVROS_DIR" \
  "${SEED_SOURCE:+$SEED_SOURCE/runtime/mavros-overlay-src}"
[[ "$(sha256sum "$MAVROS_PATCH" | awk '{print $1}')" == "$MAVROS_PATCH_SHA256" ]]
[[ "$(sha256sum "$MAVROS_ROUTER_PATCH" | awk '{print $1}')" == \
    "$MAVROS_ROUTER_PATCH_SHA256" ]]
for patch in "$MAVROS_PATCH" "$MAVROS_ROUTER_PATCH"; do
  if git -C "$MAVROS_DIR" apply --reverse --check "$patch" >/dev/null 2>&1; then
    :
  elif git -C "$MAVROS_DIR" apply --check "$patch"; then
    git -C "$MAVROS_DIR" apply "$patch"
  else
    echo "MAVROS patch cannot be applied or verified: $patch" >&2
    exit 1
  fi
done

printf 'px4=%s\ndlio=%s\nmavros=%s\n' \
  "$(git -C "$PX4_DIR" rev-parse HEAD)" \
  "$(git -C "$DLIO_DIR" rev-parse HEAD)" \
  "$(git -C "$MAVROS_DIR" rev-parse HEAD)"
