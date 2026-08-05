# PX4 3D LiDAR A→B Navigation Demo

[Apache-2.0](LICENSE) · [GitHub](https://github.com/albert17github/PX4-3D-LiDAR-Nav-Demo)

这是一个刻意保持简洁的实时图形化仿真项目。它不实现新的 SLAM 或规划算法，只把成熟开源组件连接成闭环：

```text
PX4 SITL + Gazebo 3D LiDAR
              ↓ point cloud + IMU
             DLIO
              ├── position + body velocity + yaw → MAVROS → PX4 EKF2
              └── pose + cloud → OctoMap
                                   ↓
                         MRS 3D A* planner
                                   ↓ waypoints
                         MAVROS OFFBOARD → PX4
```

## 最终演示

- Ubuntu 桌面实时显示 Gazebo 仿真世界。
- RViz 实时显示 3D LiDAR、OctoMap、PX4 位姿、A/B 与规划路径。
- 默认从 A `(0,0,2.2)` 飞到 B `(7,7,2.2)`。
- A-B 直线穿过 `map=(3.5,3.5)` 的圆柱障碍，规划器必须给出非直线绕行路径。
- 无人机实际沿路径飞行，到达 B 后自动降落。
- 交互模式每次落地后继续等待下一次 RViz 选点，不重启整套仿真。
- 每次运行保存截图、视频、地图和简短 JSON 结果。

## 复用而非重写

| 功能 | 开源组件 |
|---|---|
| 飞控与状态估计 | PX4 v1.17 SITL / EKF2 |
| 物理与传感器 | Gazebo Sim / 3D LiDAR |
| 激光惯性里程计 | DLIO |
| 飞控通信 | MAVROS |
| 三维地图 | ROS 2 OctoMap server |
| 三维路径规划 | MRS MinimalOctomapPlanner / A* |
| 可视化 | RViz |

项目自写部分只负责启动编排、目标接收、安全校验、平滑发送位置航点和保存证据。

## 首次安装与复刻

仓库不提交数 GB 的 Ubuntu、ROS、PX4 和编译产物，而是提交版本锁、补丁、
模型、世界和安装配方。项目只正式支持文档列出的 Ubuntu 24.04 桌面环境；
请先按 [复刻说明](docs/REPRODUCE.md) 安装宿主机命令，再执行：

```bash
git clone https://github.com/albert17github/PX4-3D-LiDAR-Nav-Demo.git
cd PX4-3D-LiDAR-Nav-Demo
./scripts/check_environment.sh --setup
./setup.sh
./demo.sh --interactive
```

检查脚本不会安装软件或修改系统。所有下载源码、rootfs 和构建产物都生成在
当前仓库的 `runtime/` 下；默认启动不读取 `/home/albert` 下的任何兄弟项目。
安装可重复执行，完成后也可用 `./setup.sh --verify-only` 只做完整性核验。
每个阶段失败时会显示阶段名称、退出码和日志路径；网络、软件源及宿主机配置
问题由用户按原始错误自行处理。推荐环境、确切版本和阶段说明见
[docs/REPRODUCE.md](docs/REPRODUCE.md)。

本仓库为 public，任何用户都可以直接 clone。首次安装会下载固定版本的上游源码和
签名软件包，不需要本机存在作者的其他项目。

## 运行

主入口固定为：

```bash
cd PX4-3D-LiDAR-Nav-Demo
./demo.sh
```

脚本会重新冷启动完整栈，通过健康门后才允许 `OFFBOARD` 与 arm；规划路径不完整或净距不足时会在 A 悬停有界重试，全部失败则自动安全降落。成功运行会在新的 `runs/<timestamp>/evidence/` 中保存 JSON、截图、H.264 视频、`.bt` 地图和 SHA-256 清单。

默认冷启动使用主线 `readiness` 模式，逐项验证 Gazebo/LiDAR、MAVROS、
landed/disarmed、DLIO、PX4 EKF2 external position 融合、TF 与非空
OctoMap；随后主入口再切换并核验 external position/velocity/yaw 三项持续融合。
旧基线的多层审计框架不再进入本项目启动链。

本项目不需要 QGroundControl。启动期间由 MAVROS 连接 PX4，终端会持续显示每个组件和 readiness gate 的进度；如果桌面上已有 QGroundControl，入口会直接提示关闭，避免其 MAVLink GCS 流量进入本演示。PX4 的 SITL-only 合同在 landed/disarmed 状态下验证并固定 `NAV_DLL_ACT=0`，不会因此关闭其他定位、OFFBOARD 或 arming health checks。

RViz 交互选点模式：

```bash
./demo.sh --interactive
```

等待终端显示 `waiting_for_interactive_goal`，然后在 RViz 顶部选择 `2D Goal Pose`，在地图上按住鼠标并拖出箭头。点击位置提供目标 X/Y，飞行高度固定为 `2.2 m`，箭头方向作为整次任务的固定机头朝向。机体先保持当前航向垂直起飞，到达高度后再按最短角度、最多 `45°/s` 原地转向，不再跟随每个规划折点反复旋转。

路径通过在线 OctoMap 规划和安全校验后才会进入 OFFBOARD。到达后自动降落，但程序、Gazebo、RViz、DLIO 和地图都不会退出；终端重新显示 `waiting_for_interactive_goal` 后可以继续选下一个点。下一次规划从飞机的实际落地点开始。等待会持续到用户停止，配置中的 30 分钟只作为周期性等待提示，不会关闭窗口。完成全部尝试后在原终端按一次 `Ctrl+C`。

分步入口同样支持交互：

```bash
./scripts/start.sh
./scripts/fly_ab.sh --interactive
# 完成多次尝试后按 Ctrl+C 结束 fly_ab.sh
./scripts/stop.sh
```

## 已验证结果

2026-08-05 自包含运行时与几何合同完成两次独立 PASS：默认入口只使用当前
checkout 的 `runtime/`，不再读取兄弟项目；PX4 `v1.17.0`、DLIO、MAVROS
`2.14.0`、Ubuntu rootfs、补丁与下载哈希均有机器版本锁。仿真保留非零初始
航向 `0.55 rad`，并把圆柱 world 位姿严格变换为 DLIO `map=(3.5,3.5)`，使其
真正位于 A→B 中线。正式 run `20260805-182916-btMc4A` 与
`20260805-183516-xIDcJr` 分别获得 9/7 点完整路径，路径长
`12.886/12.724 m`、横向绕行均为 `3.111 m`、圆柱中心距离
`2.961/2.927 m`，B 点误差 `0.024/0.037 m`；两轮均自动降落、哈希全通过、
clean stop 且残留进程为零。冷启动总计 `235/237 s`，比此前已优化的
`287 s` 再缩短约 `17%..18%`。

上述新版本也修复了两个启动/运行时边界：航点到达临界时保留 odometry
watchdog 并增加合理 settle 余量；MAVROS 使用固定上游版本加官方后续
vehicles/router 锁补丁，MRS component discovery 则采用有界重试。没有更换
DLIO、OctoMap、A* 或 PX4 算法，也没有降低安全阈值。

> 坐标口径说明：2026-08-03/04 的历史报告曾把未旋转的 world 差值
> `(3.5,3.5)` 直接写成 DLIO `map` 坐标；那些旧中心距数字只保留为历史记录，
> 不再作为当前几何验收依据。当前版本由
> `scripts/check_simulation_contract.py` 自动核对 SDF、初始航向与任务配置。

2026-08-05 LIO yaw authority run `20260805-151557-Otlbug` PASS：PX4 在飞行阶段实测 `EKF2_EV_CTRL=13`，DLIO 同时约束 horizontal position、body velocity 和 yaw；磁航向仅用于启动初始化，飞行中 `cs_mag_hdg/cs_mag_3d=False`。同一个 PX4/EKF2/DLIO 实例连续完成 4 次飞行和自动降落，最远目标半径 `10.296 m`，目标误差均为 `0.028..0.051 m`。4 份 ULog 中 EV 三项 fusion 全程有效、三类 innovation 零拒绝、飞行中 heading/quaternion reset 增量为 0、dropout 为 0；以一套固定 SE(2) 对齐 Gazebo 真值后的最大位置/yaw 残差为 `0.128 m / 3.04°`。完整摘要见 `runs/20260805-151557-Otlbug/evidence/lio-yaw-ulog-summary.json`。

2026-08-05 冷启动优化 run `20260805-113113-Yd1sN7` PASS：虚拟机异常重启后的 stale marker 已由现有停止脚本封存；新的 base readiness 用时 `263 s`，完整入口到 RViz `waiting_for_interactive_goal` 用时 `287 s`，此前四次成功启动为 `655..784 s`，约快 `56%..63%`。Gazebo/RViz 同屏截图、在线 `0.4 m` OctoMap（`1622` occupied centers）、MAVROS connected、`map` odom 和 MRS planner service 均已现场核验；本轮只启动并等待选点，没有自动触发飞行。

2026-08-04 持久多目标 run `20260804-202200-Hs10L6` PASS：同一次 Gazebo/RViz/PX4/DLIO/OctoMap 会话先从实际起点 `(-0.001,-0.001)` 飞到 `(5,0)`，落地后没有退出；随后从第一次实际落地点 `(5.035,0.015)` 重新规划飞回 `(0,0)`。两次目标误差分别为 `0.072 m`、`0.325 m`，均经历完整路径、`AUTO.LAND`、landed/disarmed，并分别保存为 `mission-result-001.json`、`mission-result-002.json`。第二次落地后仍重新进入选点等待，最终由 `Ctrl+C` 干净停止。

2026-08-04 稳定朝向 run `20260804-203906-n9Br4K` PASS：RViz 目标 `(5,0,2.2)` 的箭头设为 `+90°`，规划路径含 5 点和多个折点。起飞完成后的 186 个实际 yaw 样本中，setpoint 全程变化 `0.000°`，实际机头范围 `87.96°..91.53°`，平均误差 `0.27°`、最大误差 `2.04°`；目标误差 `0.104 m`，随后自动降落并继续等待下一目标。完整 evidence 的 SHA-256 已复验通过。

2026-08-04 无 QGC 冷启动和完整交互飞行已 PASS：run `20260804-193505-kEjVgs`、base run `20260804-193509-QGEVqW`。启动时 `NAV_DLL_ACT` 从 x500 默认值 `2` 读回并固定为 `0`；RViz 目标 `(5,0,2.2)` 得到 5 点 complete path，路径长 `6.183 m`、圆柱中心最小距离 `3.625 m`，实际到达误差 `0.070 m`，随后 `AUTO.LAND`、landed/disarmed。82.375 秒视频、截图、地图、JSON、参数 readback 和 SHA-256 全部通过；底层 shutdown clean，QGC/受管进程/active marker 均为零。

2026-08-04 已完成一次 `./demo.sh --interactive`：RViz 选择目标 `(5,0,2.2)`，MRS 返回 4 点 complete path，路径长 `5.921 m`、圆柱中心最小距离 `3.405 m`，PX4 实际到达目标，误差 `0.105 m`，随后 `AUTO.LAND`、landed/disarmed。run 为 `20260804-172738-8jPZ9i`，视频、截图、地图、JSON 和 SHA-256 全部通过，底层 shutdown clean。

2026-08-03 已连续完成两次独立 `./demo.sh`：

| run | 障碍中心最小距离 | B 点误差 | 结束状态 |
|---|---:|---:|---|
| `20260803-120927-6lYpVn` | `2.828 m` | `0.0915 m` | `AUTO.LAND`，landed/disarmed |
| `20260803-122744-TgKS1c` | `2.546 m` | `0.2581 m` | `AUTO.LAND`，landed/disarmed |

合同要求分别为 `≥1.35 m` 与 `≤0.4 m`。两次 run 的底层 health、Gazebo/RViz 可见性、PointCloud2、在线 OctoMap、PX4 uORB 外部水平位置融合、视频、地图和哈希均已复核。

同日又按报告步骤完整复现：`20260803-142437-0S5Hkc` 连续拒绝 5 条 incomplete path 后安全降落；新的独立 run `20260803-144745-8J6JGv` 获得 7 点完整路径，中心距离 `2.546 m`，实际到 B 误差 `0.2575 m`，随后 landed/disarmed。第二轮任务与证据哈希 PASS，但 Gazebo GUI teardown 记录 Segmentation fault，所以报告单独保留 shutdown WARN，不能称为 clean shutdown。

浏览器报告：<http://127.0.0.1:8770/reports/index.html>

## 版本切换

- 初始基线：commit `1f535b2`，tag `v0.1.0-initial`。
- LIO yaw 修复：tag `v0.2.0-lio-yaw`，后续修改从此版本继续叠加。
- 自包含运行时、正确几何合同与两次独立 PASS：tag `v0.3.0-self-contained`。
- 公开开源发布与 Apache-2.0：tag `v0.3.1`。
- 公开仓库：<https://github.com/albert17github/PX4-3D-LiDAR-Nav-Demo>。

## 许可证

本项目自写的启动编排、任务连接层、配置和文档使用
[Apache License 2.0](LICENSE)。由安装脚本取得的 PX4、Gazebo、ROS 2、DLIO、
MAVROS、OctoMap、MRS、PRoot 和 Ubuntu 内容，以及 `runtime/patches/` 中源自
上游代码的补丁，继续遵守各自原许可证；详见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

详细当前状态和一键复核命令见 [PROJECT_MEMORY.md](PROJECT_MEMORY.md)，静态报告源文件见 [reports/index.html](reports/index.html)。

详细的逐阶段实施、验收条件和小模型分工见 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)。
日期备份位于 [docs/backups/IMPLEMENTATION_PLAN-20260801.md](docs/backups/IMPLEMENTATION_PLAN-20260801.md)。
