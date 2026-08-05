#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=runtime/config/versions.env
source /project/config/versions.env
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

install -d /usr/share/update-notifier /project/logs
install -m 0755 /project/env/stubs/notify-reboot-required /usr/share/update-notifier/notify-reboot-required
dpkg --configure -a
apt-get -o Acquire::Retries=5 update
apt-get install -y --no-install-recommends ca-certificates curl gnupg locales lsb-release software-properties-common sudo wget
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
add-apt-repository universe -y

ROS_APT_DEB="/tmp/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.noble_all.deb"
curl -fL --retry 5 --retry-all-errors \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.noble_all.deb" \
  -o "$ROS_APT_DEB"
actual_ros_apt_sha="$(sha256sum "$ROS_APT_DEB" | awk '{print $1}')"
[[ "$actual_ros_apt_sha" == "$ROS_APT_SOURCE_SHA256" ]] || {
  echo "ROS apt source package SHA256 mismatch" >&2
  exit 1
}
dpkg -i "$ROS_APT_DEB"
# PRoot reports an incorrect result for the shell builtin `[ -r FILE ]` on
# files created after extraction.  Noble apt-key uses that check in its
# --readonly path and otherwise silently substitutes /dev/null for Signed-By.
# shellcheck disable=SC2016 # These are literal apt-key source fragments.
apt_key_readability_old='create_new_keyring() { if [ ! -r "$FORCED_KEYRING" ]; then'
# shellcheck disable=SC2016 # These are literal apt-key source fragments.
apt_key_readability_new='create_new_keyring() { if ! /usr/bin/test -r "$FORCED_KEYRING"; then'
if grep -Fq "$apt_key_readability_old" /usr/bin/apt-key; then
  # shellcheck disable=SC2016 # Keep the apt-key variable literal.
  sed -i 's#if \[ ! -r "$FORCED_KEYRING" \]; then#if ! /usr/bin/test -r "$FORCED_KEYRING"; then#' \
    /usr/bin/apt-key
fi
grep -Fq "$apt_key_readability_new" /usr/bin/apt-key || {
  echo "Unsupported apt-key readability implementation" >&2
  exit 1
}
ROS_APT_KEY=/project/env/apt/ros2-archive-keyring.asc
actual_ros_key_fingerprint="$(gpg --show-keys --with-colons --fingerprint "$ROS_APT_KEY" | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "$actual_ros_key_fingerprint" == "$ROS_APT_KEY_FINGERPRINT" ]] || {
  echo "ROS apt signing key fingerprint mismatch" >&2
  exit 1
}
# The official ros2-apt-source package uses HTTP for this repository.  Package
# authenticity is provided by the signed InRelease metadata, which is checked
# here and again by apt through Signed-By.  Do not bypass TLS verification.
curl -fsSL --retry 5 --retry-all-errors \
  http://packages.ros.org/ros2/ubuntu/dists/noble/InRelease \
  -o /tmp/ros2-InRelease
gpgv --keyring /usr/share/keyrings/ros2-archive-keyring.gpg /tmp/ros2-InRelease
install -m 0644 /project/env/apt/ros2-proot.sources /usr/share/ros-apt-source/ros2.sources

RUNS_IN_DOCKER=true /project/vendor/PX4-Autopilot/Tools/setup/ubuntu.sh --no-nuttx
apt-get -o Acquire::Retries=5 update
apt-get install -y --no-install-recommends \
  ffmpeg \
  libomp-dev libtbb-dev libyaml-cpp-dev \
  python3-colcon-common-extensions python3-rosdep python3-yaml \
  ros-dev-tools \
  ros-jazzy-mavros ros-jazzy-mavros-extras \
  ros-jazzy-octomap-rviz-plugins ros-jazzy-octomap-server \
  ros-jazzy-pcl-ros \
  ros-jazzy-rclcpp-components \
  ros-jazzy-ros-base \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-rviz-default-plugins ros-jazzy-rviz2 \
  ros-jazzy-tf2-ros ros-jazzy-topic-tools
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then rosdep init; fi
rosdep update
/project/env/install-mrs.sh
dpkg-query -W -f='${Package}\t${Version}\n' | sort > /project/logs/environment-packages.txt
touch /project/env/rootfs/.packages-complete
