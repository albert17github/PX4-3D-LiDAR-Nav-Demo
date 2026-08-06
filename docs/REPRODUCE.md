# 从 GitHub 复刻推荐环境

## 结论

仓库保存版本锁、补丁、场景和安装配方，不提交大型二进制运行时，也不要求
计算机上预先存在其他 PX4、ROS 或 Gazebo 工程。

当前支持范围是下表中的 Ubuntu 24.04 桌面环境。脚本负责检查环境、下载固定
上游版本、构建和核验；失败时保留上游原始错误，并明确指出失败阶段和日志位置。

推荐流程是：

```bash
git clone https://github.com/albert17github/PX4-3D-LiDAR-Nav-Demo.git
cd PX4-3D-LiDAR-Nav-Demo
./scripts/check_environment.sh --setup
./setup.sh
./demo.sh --interactive
```

`check_environment.sh` 和 `setup.sh` 不会修改宿主机软件源，也不会自动执行
`sudo apt`。宿主命令缺失时，请先按下面的命令安装；网络、代理、DNS、软件源
或虚拟机图形配置问题需要根据脚本显示的原始错误处理。

## 推荐环境

| 项目 | 正式支持 / 推荐值 | 启动检查 |
|---|---|---|
| 操作系统 | Ubuntu 24.04 LTS Desktop；当前实测 24.04.4 | 必须为 `ID=ubuntu`、`VERSION_ID=24.04` |
| 架构 | Linux `x86_64` | 必须匹配 |
| 虚拟机 | VMware，启用 3D acceleration；也可使用满足条件的物理机 | 脚本只检查图形显示是否可连接 |
| CPU | 推荐 8 个逻辑 CPU，最低 4 个 | 低于 4 个停止 |
| 内存 | 推荐分配 12 GiB RAM + 4 GiB swap | guest 内可用 RAM 低于 10 GiB 停止 |
| 磁盘 | 首次安装推荐 30 GiB 可用，最低 20 GiB；完整 `runtime/` 约 14 GiB | 首装低于 20 GiB 停止；运行低于 5 GiB 停止 |
| 桌面 | GNOME 桌面，X11 或 Wayland + XWayland，建议至少 1280×800 | 运行前验证 `DISPLAY` 可连接 |
| Bash | 5.2.x 或更高 | 最低 5.2 |
| Git | 2.43 或更高 | 最低 2.43 |
| Python | 3.12.x | 必须为 3.12 系列 |
| ROS / Gazebo | 项目内 Ubuntu Noble rootfs、ROS 2 Jazzy、Gazebo Harmonic | 运行前检查目录和可执行文件 |
| 上游源码 | PX4 `v1.17.0`、MAVROS `2.14.0`、锁定 DLIO commit | 运行前比对 commit |

参考验证环境为 VMware guest、Ubuntu 24.04.4、16 个逻辑 CPU、约 12 GiB RAM、
4 GiB swap，并通过 XWayland 显示 Gazebo 和 RViz。Ubuntu 补丁版本可以随安全
更新变化；脚本锁定上述主版本边界。

### 安装宿主机命令

在一台新的 Ubuntu 24.04 Desktop 中先执行：

```bash
sudo apt update
sudo apt install -y \
  ca-certificates curl git gzip iproute2 procps python3 rsync tar \
  util-linux x11-utils xdotool xserver-xephyr gnome-screenshot
```

这些包只提供下载、进程管理和桌面显示命令。ROS、Gazebo、PX4、MAVROS、
OctoMap 与 MRS 不安装进宿主系统，而是生成在本仓库的 `runtime/` 中。

### 网络需要访问的位置

- `github.com` 与 `objects.githubusercontent.com`：项目及固定上游源码；
- `cloud-images.ubuntu.com`：固定 Ubuntu Noble rootfs；
- `proot.gitlab.io`：固定 PRoot 可执行文件；
- `packages.ros.org`、`packages.osrfoundation.org`：ROS 2 Jazzy 与 Gazebo Harmonic；
- `ctu-mrs.github.io`：MRS OctoMap planner 软件包。

脚本不会自动更换镜像、代理或 DNS。某个地址在当前网络中不可达时，错误会停在
相应阶段；处理好网络后重新运行同一个 `./setup.sh` 即可复用已完成内容。

## 仓库保存什么

| 内容 | 保存方式 |
|---|---|
| PX4 | 官方仓库 tag `v1.17.0`，锁定 commit |
| DLIO | 官方 `feature/ros2` commit + 本仓库审核补丁 |
| MAVROS | 官方 `2.14.0` commit + vehicles map 与 router address 并发补丁 |
| Ubuntu | 官方 Noble WSL rootfs URL + SHA-256 |
| ROS 2 / Gazebo | 固定 ROS 官方签名 key fingerprint，在 Ubuntu rootfs 内安装 Jazzy / Harmonic 包 |
| MRS A* | CTU MRS stable 软件源，先验证签名 key 与 InRelease |
| 场景 | 本仓库跟踪 LiDAR 模型、Gazebo 世界与 ROS 参数 |

机器可读的全部版本与下载哈希位于
[`runtime/config/versions.env`](../runtime/config/versions.env)。安装完成后，
`runtime/.setup/runtime.lock` 会记录本机实际生成的 PX4、DLIO、MAVROS
二进制 SHA-256；`runtime/logs/environment-packages.txt` 会记录实际 apt
包版本。

Ubuntu rootfs、PRoot、源码 commit 和本仓库补丁是固定输入；ROS/Ubuntu/MRS
的 apt 包由签名软件源在安装时解析，并把实际版本写入 manifest。因此它是
“可一键重建并可审计”的环境，不宣称跨日期 bit-for-bit 相同。长期归档时应连同
`runtime/logs/environment-packages.txt` 和本机生成的 `runtime.lock` 保存。

ROS 软件源没有使用 `Trusted: yes`。安装脚本固定并验证仓库中的 ROS 官方公钥
fingerprint，先以 `gpgv` 核验 `InRelease`，随后由 apt 通过 `Signed-By` 再次
验证。脚本中针对 `/usr/bin/apt-key` 的单行修改只修复 PRoot 对新 keyring
执行 shell builtin `test -r` 时的误判，并对修改前、修改后的精确文本都做检查；
若 Ubuntu 实现发生变化，安装会明确失败而不是绕过签名验证。

## `setup.sh` 的六个阶段

1. 检查推荐的 Ubuntu、架构、主机命令、版本、资源和桌面显示；
2. 下载 PX4、DLIO、MAVROS 及限定的 PX4 submodule，并比对固定 commit；
3. 下载 Ubuntu Noble rootfs 与 PRoot，逐个验证 SHA-256；
4. 在项目内 rootfs 安装 PX4、ROS 2、Gazebo、OctoMap、MAVROS 和 MRS；
5. 应用已审核补丁并构建缺失的 PX4 SITL、DLIO 与 MAVROS overlay；
6. 检查 source commit、反向补丁、动态库闭包、Python self-test，以及
   `demo.yaml` 与 Gazebo 世界的位姿/障碍物坐标契约；
   最后生成本机 runtime lock。

每一步都可重复运行。已有且通过核验的下载、源码和二进制会被复用。失败格式为：

```text
ERROR: setup stage 4/6 failed: Installing the locked ROS 2, Gazebo, ... packages...
Exit code: 100
Log: /absolute/path/runtime/logs/install-packages.log
Resolve the reported problem, then rerun: ./setup.sh
```

这表示脚本已经完成定位和留档，不会继续猜测故障原因或修改宿主环境。先查看
日志末尾的原始 `apt`、`curl`、`git` 或编译器错误，处理后重新执行。

## 常用命令

```bash
# 只核验，不下载、不编译
./setup.sh --verify-only

# 启动前再次检查宿主环境、显示、runtime 文件和固定源码版本
./scripts/check_environment.sh --run

# 使用四个编译任务全新安装
./setup.sh --jobs 4

# 启动、交互飞行、停止
./scripts/start.sh
./scripts/fly_ab.sh --interactive
./scripts/stop.sh
```

维护者在同一台机器迁移旧的已验证缓存时，可使用：

```bash
./setup.sh --seed-from /absolute/path/to/validated-stack
```

这是面向维护者的可选加速路径。它只接受固定哈希的已验证二进制，把文件复制到当前
项目，并为源码建立独立 Git 元数据；不会建立指向旧项目的 symlink，也不会
复制旧 run、报告或 ULog。首次安装不需要这个选项。

## 运行时边界

```bash
source scripts/common.sh
printf '%s\n' "$STACK_ROOT"
./setup.sh --verify-only
```

`STACK_ROOT` 应位于当前 checkout 的 `runtime`。默认安装和启动路径都从仓库
根目录计算；只有明确传入 `--seed-from` 时，安装器才读取指定的缓存目录，且
复制完成后不保留 symlink 或 Git alternates。

## 开源发布与许可证

GitHub repository visibility 为 `public`，无需 collaborator 权限即可 clone。
项目自写的薄连接层、启动脚本、配置和文档使用 `Apache-2.0`；完整条款位于
仓库顶层 [`LICENSE`](../LICENSE)。安装脚本下载的上游组件及
`runtime/patches/` 中源自上游代码的内容继续遵守各自许可证，不能因为本项目
采用 `Apache-2.0` 而覆盖；具体边界见
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。
