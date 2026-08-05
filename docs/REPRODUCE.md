# 从 GitHub 复刻完整环境

## 结论

这个仓库现在是唯一入口。它不提交大型二进制环境，也不要求计算机上预先
存在 `PX4-LiDAR-SLAM-Sim`、`RVPX4` 或其他本地项目。

普通用户的流程是：

```bash
git clone https://github.com/albert17github/PX4-3D-LiDAR-Nav-Demo.git
cd PX4-3D-LiDAR-Nav-Demo
./setup.sh --install-host-deps
./demo.sh --interactive
```

第一条运行命令会在需要时通过 `sudo apt` 安装少量宿主桌面工具，并在仓库
自己的 `runtime/` 中下载、安装和构建完整仿真栈。以后只运行
`./demo.sh`，不会再次下载。

## 支持范围

- Ubuntu 24.04 Desktop，Linux `x86_64`；
- 至少 4 个逻辑 CPU；建议 8 个或更多；
- 建议 12 GiB RAM（当前验证机为约 11 GiB RAM + 4 GiB swap）；
- 首次安装前至少 20 GiB 可用磁盘；当前完整生成目录约 14 GiB，额外空间用于
  下载、解包和编译峰值；
- 可访问 GitHub、Ubuntu Cloud Images、ROS 2 和 CTU MRS 软件源；
- 当前阶段使用 X11/XWayland 桌面显示 Gazebo 与 RViz。

## 仓库保存什么

| 内容 | 保存方式 |
|---|---|
| PX4 | 官方仓库 tag `v1.17.0`，锁定 commit |
| DLIO | 官方 `feature/ros2` commit + 本仓库审核补丁 |
| MAVROS | 官方 `2.14.0` commit + vehicles map 与 router address 并发补丁 |
| Ubuntu | 官方 Noble WSL rootfs URL + SHA-256 |
| ROS 2 / Gazebo | Ubuntu rootfs 内安装 Jazzy / Harmonic 包 |
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

## `setup.sh` 做了什么

1. 检查宿主架构、桌面命令、CPU 和磁盘条件；
2. 对固定 commit 做浅检出，并递归初始化 PX4 submodule；
3. 下载 Ubuntu Noble rootfs 与 PRoot，逐个验证 SHA-256；
4. 在项目内 rootfs 安装 PX4、ROS 2、Gazebo、OctoMap、MAVROS 和 MRS；
5. 应用并核验 DLIO、MAVROS 补丁；
6. 构建缺失的 PX4 SITL、DLIO 与 MAVROS overlay；
7. 检查 source commit、反向补丁、动态库闭包、Python self-test，以及
   `demo.yaml` 与 Gazebo 世界的位姿/障碍物坐标契约；
8. 生成本机 runtime lock。

每一步都可重复运行。已有且通过核验的下载、源码和二进制会被复用。

## 常用命令

```bash
# 只核验，不下载、不编译
./setup.sh --verify-only

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

这是可选的加速路径。它只接受固定哈希的已验证二进制，把文件复制到当前
项目，并为源码建立独立 Git 元数据；不会建立指向旧项目的 symlink，也不会
复制旧 run、报告或 ULog。普通用户不需要这个选项。

## 如何证明没有隐藏的兄弟项目依赖

```bash
source scripts/common.sh
printf '%s\n' "$STACK_ROOT"
./setup.sh --verify-only
git grep -n '/home/albert/PX4-LiDAR-SLAM-Sim' -- \
  demo.sh setup.sh scripts runtime ':!runtime/scripts/seed-runtime.sh'
```

第一条结果应位于当前 checkout 的 `runtime`；最后一条应无输出。可选
`seed-runtime.sh` 中出现旧路径字样只属于明确的迁移排除规则，不参与默认
安装或启动。

## 发布前仍需仓库所有者决定

当前 GitHub 仓库是 private，且仓库顶层没有选定项目许可证。脚本和环境已经
可以复刻，但要让任何陌生用户直接 clone、修改和再分发，还需要仓库所有者
明确决定：

1. 是否把 repository visibility 改为 public；
2. 自写薄连接层采用哪一种许可证。

这两项涉及访问权限和法律授权，自动化脚本不会自行修改。
