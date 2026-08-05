#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=runtime/config/versions.env
source /project/config/versions.env

[[ "$MRS_CHANNEL" == stable ]] || {
  echo "Only the reviewed CTU MRS stable channel is supported." >&2
  exit 1
}
KEY_ASC=/tmp/ctu-mrs.gpg.asc
KEY_RING=/etc/apt/keyrings/ctu-mrs.gpg
INRELEASE=/tmp/ctu-mrs-InRelease
curl -fsSL --retry 5 --retry-all-errors https://ctu-mrs.github.io/ppa2-stable/ctu-mrs.gpg -o "$KEY_ASC"
actual_fingerprint="$(gpg --show-keys --with-colons --fingerprint "$KEY_ASC" | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "$actual_fingerprint" == "$MRS_APT_KEY_FINGERPRINT" ]] || {
  printf 'CTU MRS signing key mismatch.\nexpected=%s\nactual=%s\n' \
    "$MRS_APT_KEY_FINGERPRINT" "$actual_fingerprint" >&2
  exit 1
}
install -d /etc/apt/keyrings /etc/apt/preferences.d /etc/ros/rosdep/sources.list.d
gpg --batch --yes --dearmor --output "$KEY_RING" "$KEY_ASC"
curl -fsSL --retry 5 --retry-all-errors https://ctu-mrs.github.io/ppa2-stable/InRelease -o "$INRELEASE"
gpgv --keyring "$KEY_RING" "$INRELEASE"
install -m 0644 /project/env/apt/ctu-mrs-stable.list /etc/apt/sources.list.d/ctu-mrs-stable.list
install -m 0644 /project/env/apt/ctu-mrs-stable-preferences /etc/apt/preferences.d/ctu-mrs-stable-preferences
install -m 0644 /project/env/apt/ctu-mrs-stable-rosdep.list /etc/ros/rosdep/sources.list.d/ctu-mrs-stable.list
apt-get -o Acquire::Retries=5 update
apt-get install -y --no-install-recommends \
  ros-jazzy-mrs-octomap-mapping-planning \
  ros-jazzy-mrs-uav-px4-api
dpkg-query -W -f='${Package}\t${Version}\n' 'ros-jazzy-mrs-*' > /project/logs/mrs-packages.txt
