# Project Memory

## Objective

在 Ubuntu 24 桌面中实时显示 Gazebo 和 RViz，让 PX4 SITL 无人机使用三维 LiDAR + IMU 完成定位与 OctoMap 建图，调用开源 MRS 三维 A* 规划器获得固定 A→B 或 RViz 交互目标路径，再通过 MAVROS OFFBOARD 位置航点实际飞完整条路径并自动降落。交互模式作为后续演示技术底座，应在同一会话中支持多次选点，同时保持自写代码只承担薄编排和安全连接层。

## Startup recovery and optimization PASS — 2026-08-05

- 虚拟机在 demo run `runs/20260805-110928-9hWdJE` 启动期间异常重启；base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260805-110934-bhEfY4` 已完成全部组件 readiness，但仍在执行重复的完整 startup health。重启后没有受管进程存活，两层 stale marker 已通过现有 `scripts/stop.sh` / `stop_sim.sh` 有序封存，失败证据保留。
- 历史四个成功 base run 的冷启动耗时约 `629..755 s`；本次异常 run 在 `493 s` 时仍未完成。组件 readiness 约用 `250 s`，其后的 66 项通用 startup health 重复调用独立 `ros2 --no-daemon` 探针，是主要额外耗时；本次 health 还出现一次瞬时 PX4-pose TF 合同失败。
- 为避免修改或复制 SLAM、OctoMap、planner、MAVROS 和 PX4 算法，只给重型运行时的 `scripts/start_sim.sh` 增加显式、可审计的 `--startup-health readiness|full` 编排选项：基线默认仍为 `full`，本项目入口选择 `readiness`，并继续保留逐组件 readiness、landed/disarmed、PX4 fusion、TF、OctoMap、no-GCS readback、planner service、可见 RViz 和任务 watchdog。
- 改动面限制为基线启动编排入口与本项目 `scripts/start.sh`，不改变任何 health 阈值、算法、topic、frame、参数或飞行安全检查。回退无需修改文件：使用 `PX4_DEMO_STARTUP_HEALTH_MODE=full ./demo.sh --interactive` 即恢复原完整 startup health；若验证失败，则移除本项目传参并撤销基线新增选项。
- 新冷启动 demo run `runs/20260805-113113-Yd1sN7`、base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260805-113117-NrNymV` 实测 PASS：base readiness `263 s`、no-GCS policy `1 s`、planner `19 s`、RViz/录像 `4 s`，从入口到 `waiting_for_interactive_goal` 总计 `287 s`（4 分 47 秒）。此前四次成功 demo 冷启动为 `655..784 s`，本次节省 `368..497 s`，约快 `56%..63%`。
- 本轮可见证据为 `evidence/desktop-readiness.png` 与 `evidence/rviz-readiness.png`：Gazebo 场景、RViz 3D LiDAR、PX4 EKF2 pose 和 OctoMap 同屏可见且状态为 OK。在线只读核验得到 MAVROS `connected=True`、local odom frame=`map`、二进制 `OcTree` resolution=`0.4`、occupied width=`1622`，planner service 为 `mrs_modules_msgs/srv/Path`。
- 截至本次交接，会话仍在运行并停在 `waiting_for_interactive_goal`，没有自动解锁或触发新飞行；用户可直接在 RViz 使用 `2D Goal Pose`。快速模式已经真实冷启动验证，`full` 模式保留为基线默认并通过静态检查，但本轮没有再花 10–13 分钟重复一次完整 66 项运行时审计。
- 上一启动周期的 journal 在 `11:17:51` 突然结束，未记录 OOM、kernel panic 或 systemd failed unit；因此只能确认虚拟机发生非正常重启，不能把原因归结为项目或某个 VMware 组件。

## Current state — PERSISTENT MULTI-GOAL + STABLE YAW PASS (2026-08-04)

- `./demo.sh --interactive` 现在是持久会话：每次 RViz 目标飞完后自动降落，但 Gazebo、RViz、PX4、DLIO、OctoMap、planner 和目标监听器继续运行；确认 landed/disarmed 后重新显示 `waiting_for_interactive_goal`。只有用户按 `Ctrl+C` 才进入统一停止流程。
- 每次新任务以飞机的实际落地点 XY 和固定高度 `2.2 m` 作为起飞/规划 start，不再假设仍位于配置 A；因此不会为了第二次任务先沿未规划直线返回 A。每轮结果同时保存到兼容路径 `mission-result.json` 和独立的 `mission-result-NNN.json`。
- 持久双任务 run `runs/20260804-202200-Hs10L6` PASS：mission 001 从 `[-0.0012,-0.0007,2.2]` 到 `[5,0,2.2]`，误差 `0.0722 m`；mission 002 从第一次实际落地点 `[5.0347,0.0145,2.2]` 到 `[0,0,2.2]`，误差 `0.3250 m`。两轮均 complete path、OFFBOARD、arm、全部 waypoint、AUTO.LAND、landed/disarmed；第二轮后仍等待新目标，最终 `Ctrl+C` clean stop，全部 evidence 哈希 OK。
- 原先每个 planner segment 都用 `atan2()` 重设机头，导致折线路径中反复转向。现在 RViz `2D Goal Pose` 箭头提供整次任务唯一 yaw；起飞阶段按最短角度且不高于 `45°/s` 平滑转向，后续所有 waypoint 保持该 yaw。固定 A→B 模式则保持一次性的 A→B 朝向。
- 稳定朝向 run `runs/20260804-203906-n9Br4K` PASS：目标 `[5,0,2.2]`、目标 yaw `+90°`、5 点路径；起飞完成后的 186 个 odometry yaw 样本中 setpoint 变化 `0.000°`，实际范围 `87.957°..91.531°`，平均误差 `0.271°`、最大误差 `2.043°`；目标误差 `0.1041 m`，自动降落后重新等待目标，clean stop，哈希全部 OK。
- 交互等待的配置窗口仍为 `1800 s`，但到期只记录 `interactive_goal_wait_continues` 并继续等待，不会自动退出。目标距离 `1..12 m` 现在相对于每轮实际 start 计算。
- 项目不再检测、复用或启动 QGroundControl，也不再把 `--allow-external-qgc` 传给只读基线。若桌面已有 QGC，入口会立即要求关闭，防止其 GCS MAVLink 流量进入 MAVROS。
- 正式 no-QGC run `runs/20260804-193505-kEjVgs` PASS：base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260804-193509-QGEVqW`；目标 `[5,0,2.2]`，5 点 complete path，路径长 `6.1827 m`，圆柱中心最小距离 `3.6249 m`，目标误差 `0.0699 m`；OFFBOARD、arm、全部 waypoint、AUTO.LAND、landed/disarmed 全部完成。
- x500 airframe 把 `NAV_DLL_ACT` 默认设为 `2`，无 GCS 时会产生 `Preflight Fail: No connection to the GCS`。新入口在 base health PASS 且已有 landed/disarmed 证据后，将该唯一参数固定并 readback 为 `0`；本轮证据为 `NAV_DLL_ACT_before=2`、`NAV_DLL_ACT_after=0`。这是 SITL-only no-GCS policy，未关闭其他 health checks。
- no-QGC base startup health 全部 PASS：LiDAR `9.335 Hz`、OctoMap `9.596 Hz`、PX4 IMU `47.639 Hz`、external odometry `97.308 Hz`、`1662` occupied voxel；shutdown logs clean。82.375 秒视频及截图、地图、JSON、参数 readback 的 SHA-256 全部 OK。
- `scripts/start.sh` 现在实时转发 `component_starting`、`gate_waiting`、`gate_passed` 和基线 health `PASS/FAIL`，不再在数分钟 readiness 期间看起来卡死；若 `mavros_node` 再次 double-free/退出则立即中止，并对确认归属的失败 run 执行 force-cleanup。
- 正式交互 run `runs/20260804-172738-8jPZ9i` PASS：RViz 目标 `[5.0,0.0,2.2]`，MRS 返回 4 点 complete path，路径长 `5.9206 m`，圆柱中心最小距离 `3.4053 m >= 1.35 m`，目标误差 `0.1050 m <= 0.4 m`；经历 `OFFBOARD`、arm、全部 waypoint、`AUTO.LAND`、landed/disarmed。
- Base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260804-172745-0r9NCj` 的 startup health 全部 PASS：LiDAR `9.596 Hz`、OctoMap `9.359 Hz`、PX4 IMU `47.179 Hz`、external odometry `100.763 Hz`、`1995` occupied voxel；shutdown clean。
- 交互证据包括 `99 s` H.264 RViz 视频、Gazebo/RViz 桌面截图、最终 RViz 截图、OctoMap、任务 JSON 和 SHA-256 清单；`sha256sum -c` 全部 OK。
- 持久功能验证前有一次 base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260804-201908-4T4RHU` 在 MAVROS 输出自身第一条运行日志前以 `SIGSEGV (-11)` 退出；新入口立即失败并完整清理。随后两次相同 no-QGC 冷启动均通过，未复现该早期崩溃；因此保留证据和 fail-fast，不做猜测性 MAVROS/上游算法修改。
- 当前没有活动 demo/base run，没有 PX4/Gazebo/ROS/DLIO/OctoMap/planner/RViz/mission 受管进程或 active marker，也没有 QGroundControl 进程。两个新 run 的 `sha256sum -c` 全部 OK；根分区当前约 `51G` 可用。
- 固定 `./demo.sh` 和 `./scripts/fly_ab.sh` 的历史 A→B 行为保持不变；交互模式只由显式 `--interactive` 启用。

## Interactive operation

一键运行：

```bash
cd /home/albert/PX4-3D-LiDAR-Nav-Demo
./demo.sh --interactive
```

等待终端显示 `waiting_for_interactive_goal` 后，在 RViz 顶部选择 `2D Goal Pose`，在地图上按住鼠标左键、拖出箭头并松开。点的位置给出 X/Y，Z 固定为 `2.2 m`；箭头方向给出整次飞行固定 yaw。目标距本轮实际 start 必须为 `1..12 m`，且不得落入圆柱中心 `1.35 m` 安全包络。无完整安全路径时保持 fail-closed 并自动降落；安全落地后仍回到选点等待。完成所有尝试后在原终端按一次 `Ctrl+C`。

分步运行：

```bash
./scripts/start.sh
./scripts/fly_ab.sh --interactive
# 完成多次选点后按 Ctrl+C 结束任务监听
./scripts/stop.sh
```

## Historical A→B state — COMPLETE WITH SHUTDOWN WARNING (2026-08-03)

- 主入口 `./demo.sh` 已完成两次相互独立的基准冷启动全链路 PASS；本次逐步复现实验另外完成一次安全拒绝和一次 A→B 任务 PASS。当前没有活动 run，PX4/Gazebo/ROS/DLIO/OctoMap/planner/RViz 受管进程与两层 active marker 均已清除。
- 最终报告源为 `reports/index.html`；需要浏览器访问时可从项目根目录启动本地 HTTP 服务。首页是 00–08 的真实截图时间线、两次尝试对照、内嵌视频、地图/JSON/哈希和关机审计，而不是只显示动态状态卡。
- A=`(0,0,2.2)`，B=`(7,7,2.2)`；预期圆柱中心 `map=(3.5,3.5)`、半径 `0.65 m`。独立校验要求中心距离至少 `1.35 m`、cross-track 至少 `0.55 m`、B 点误差不超过 `0.4 m`。
- MRS `MinimalOctomapPlanner` 保持上游实现，`planning_tree_resolution=0.4 m`、`safe_obstacle_distance=2.4 m`、飞行高度 `1.5..3.0 m`。在线地图尚未收敛时，任务在 A 悬停，最多请求 5 次、间隔 4 s；每次路径都必须同时为 complete 且通过几何安全校验，否则 fail-closed 并 `AUTO.LAND`。

## Final independent runs

### PASS 1

- Demo run：`runs/20260803-120927-6lYpVn`
- Base run：`/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260803-120941-ULXeIj`
- Health evidence：`health/20260803-121403-EyiRU1/summary.txt`，全部检查 PASS；LiDAR `9.379 Hz`、OctoMap `9.487 Hz`、PX4 IMU `47.510 Hz`、external odometry `99.863 Hz`、`1703` 个 occupied voxel。
- 规划前两次 incomplete 被拒绝，第 3 次得到 8 点 complete path；路径长 `13.301 m`、中心距离 `2.828 m`、cross-track `2.828 m`。
- 实际经历 `OFFBOARD`、arm、A、全部 waypoint、B、`AUTO.LAND`、landed/disarmed；B 点误差 `0.0915 m`。
- 视频 `rviz-ab-demo.mp4` 为 H.264、`1280x800`、`94.5 s`；地图、JSON、两张最终截图、视频与 `video-info.txt` 的 `sha256.txt` 校验全部 OK。

### PASS 2

- Demo run：`runs/20260803-122744-TgKS1c`
- Base run：`/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260803-122747-VTgyNS`
- Health evidence：`health/20260803-123204-z0BYK3/summary.txt`，全部检查 PASS；LiDAR `9.596 Hz`、OctoMap `9.407 Hz`、PX4 IMU `48.613 Hz`、external odometry `99.621 Hz`、`1624` 个 occupied voxel。
- 规划前两次 incomplete 被拒绝，第 3 次得到 7 点 complete path；路径长 `12.899 m`、中心距离 `2.546 m`、cross-track `2.546 m`。
- 实际经历 `OFFBOARD`、arm、A、全部 waypoint、B、`AUTO.LAND`、landed/disarmed；B 点误差 `0.2581 m`。
- 视频 `rviz-ab-demo.mp4` 为 H.264、`1280x800`、`90.5 s`；地图、JSON、两张最终截图、视频与 `video-info.txt` 的 `sha256.txt` 校验全部 OK。

## Guided end-to-end evidence rerun — 2026-08-03 14:24–15:06

### Attempt 01 — fail-closed PASS

- Demo run：`runs/20260803-142437-0S5Hkc`；base run：`/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260803-142440-aQsJ2O`。
- Startup health 全部 PASS：LiDAR `9.455 Hz`、OctoMap `9.471 Hz`、PX4 IMU `48.077 Hz`、external odometry `99.708 Hz`、`1657` occupied voxels。
- 任务完成 OFFBOARD、arm、到 A 和 `12 s` map warmup；规划器连续 5 次只返回 `Incomplete path found of length = 5`，每次都被拒绝，随后 `AUTO.LAND`、landed/disarmed。
- 停止后对本轮 `final-map.bt` 离线复放仍返回 incomplete length 5，终点 `(6.2,7.0,2.2)` 未到 B；摘要在 `evidence/offline-final-map-replay.json`。
- Base producer-first shutdown 干净，视频 H.264 `1280x800`、`459.875 s`、`23,252,722 bytes`；新增逐步截图和全部原始产物的 `sha256.txt` 复验通过。

### Attempt 02 — mission PASS / shutdown WARN

- Demo run：`runs/20260803-144745-8J6JGv`；base run：`/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260803-144748-NfX0ER`。
- Startup health 全部 PASS：LiDAR `9.662 Hz`、OctoMap `9.416 Hz`、PX4 IMU `47.523 Hz`、external odometry `99.975 Hz`、`1756` occupied voxels。
- 第一次 incomplete length 4 被拒绝；第二次得到 complete length 6，加 A 共 7 点。路径长 `12.1183 m`、中心距离 `2.5456 m >= 1.35 m`、cross-track `2.5456 m >= 0.55 m`。
- 实际执行全部 waypoint，到 B 误差 `0.2575 m <= 0.4 m`，随后 `AUTO.LAND`、landed/disarmed。视频 H.264 `1280x800`、`255.625 s`、`43,958,523 bytes`。
- 所有受管进程组最终为 0，两层活动标记清除；但 Gazebo GUI 在 teardown 时记录 `Segmentation fault (Address not mapped to object [0xffffffe7e3c95048])`，所以 base stop 正确保留 `stop_failed`，不能称为 clean shutdown。自包含摘要为 `evidence/shutdown-audit.txt`。
- 本轮全部截图、视频、地图、JSON、审计文件的 `sha256.txt` 复验通过。机器可读总表为 `reports/guided-experiment-20260803.json`。

## Implemented fixes

- `scripts/start.sh`：移除 QGC 自动启动/复用与 `--allow-external-qgc`；加入 no-QGC 冲突提示、实时 readiness/health 进度、MAVROS fatal fail-fast、失败 run 身份校验 force-cleanup，以及 landed/disarmed 条件下的 `NAV_DLL_ACT=0` readback 合同。
- `src/ab_mission.py`：RViz `PoseStamped` 目标订阅、目标范围/安全包络校验、动态 planner goal、逐项 watchdog，以及 landed/disarmed 后的持久多任务循环；每轮使用实际落地点作为 planner start，固定 A→B 模式保持兼容。
- `src/ab_mission.py`：RViz 箭头 yaw 只在起飞阶段按最短角度、最多 `45°/s` 平滑应用，后续路径折点不再反复改变机头；odometry 证据新增实际 yaw 与 target yaw 采样。
- `config/demo.rviz`、`config/demo.yaml`：新增 `2D Goal Pose` 工具及 `/demo/goal_pose`、`1..12 m`、`1800 s` 等唯一机器可读交互合同。
- `demo.sh`、`scripts/fly_ab.sh`：新增显式 `--interactive`，其余入口名称与默认行为不变。
- `src/ab_mission.py`：起飞 setpoint 从当前位姿渐变到 A；完整保存 planner 原始响应；对 incomplete/不安全路径执行有界悬停重试，并保留 `planner_attempt_rejected` 事件。
- `config/planner.yaml`：基于两份真实 `.bt` 地图复放选择 `safe_obstacle_distance=2.4 m`；`0.2 m` 规划树分辨率在最新地图上系统性 No-path，故保留 `0.4 m`。
- `scripts/start.sh`：规划服务使用更长的 host-native DDS discovery readiness。
- `scripts/stop.sh`：保存最终地图、视频信息和哈希；`sha256.txt` 不再错误地把自身纳入清单。
- `demo.sh`：成功后额外保存 `final-desktop.png` 与 `rviz-final.png`。
- 重型运行时 `scripts/start_sim.sh`：修复 PRoot builtin `test -r` 假阴性；关键 ROS/DDS readiness 改用 host-native 探针并保留阶段诊断文件。
- 重型运行时 `scripts/stop_sim.sh`：成功停止后把匹配的 active marker 移入该 run 的 `active-run.closed`，下一轮无需归档伪 stale marker。
- `reports/index.html`：重构为“飞行记录簿”式逐步报告；用 14 张真实截图、语义 SVG 图标、两轮对照表、内嵌 RViz 视频和关机 WARN 修复原先首页信息滞后、证据不完整和显示层级不清的问题。

## One-click and verification commands

```bash
cd /home/albert/PX4-3D-LiDAR-Nav-Demo
./demo.sh
./demo.sh --interactive
```

分步入口：

```bash
./scripts/start.sh
./scripts/fly_ab.sh
./scripts/fly_ab.sh --interactive
./scripts/stop.sh
```

静态复验：

```bash
python3 -m py_compile src/ab_mission.py
source scripts/common.sh
native_ros python3 src/ab_mission.py --self-test
bash -n demo.sh scripts/*.sh
shellcheck -x demo.sh scripts/*.sh
```

证据校验示例：

```bash
cd runs/20260803-144745-8J6JGv/evidence
sha256sum -c sha256.txt
```

## Important files

- `src/ab_mission.py`：planner client、独立路径校验、OFFBOARD 执行与安全落地。
- `config/demo.yaml`：A/B、交互目标、几何验收、速度、warmup 与规划重试合同。
- `config/planner.yaml`：MRS planner 参数。
- `reports/index.html`、`reports/status.json`、`reports/guided-experiment-20260803.json`：最终逐步网页报告、状态和机器摘要。
- `runs/20260803-120927-6lYpVn/evidence/`、`runs/20260803-122744-TgKS1c/evidence/`：两套最终独立证据。
- `runs/20260803-142437-0S5Hkc/evidence/`、`runs/20260803-144745-8J6JGv/evidence/`：本次逐步复现实验的安全拒绝与任务 PASS 证据。
- `runs/20260804-172738-8jPZ9i/evidence/`：RViz 交互选点 PASS 的视频、截图、地图、任务 JSON 与哈希。
- `runs/20260804-193505-kEjVgs/evidence/`：无 QGC 交互飞行 PASS 的视频、截图、地图、参数 readback、任务 JSON 与哈希。
- `runs/20260804-202200-Hs10L6/evidence/`：同一会话两次实际飞行、两个独立 mission JSON、视频、地图和哈希。
- `runs/20260804-203906-n9Br4K/evidence/`：固定 `+90°` 朝向的实际 yaw/target yaw 轨迹、任务 JSON、视频、地图和哈希。

## Known boundaries

- 这是静态障碍 SITL 演示，不是动态避障、实机安全认证或复杂自主探索系统。
- `unknown_is_occupied=false` 只适用于此静态可见仿真；真机必须重做未知空间、机体包络、制动距离、传感器盲区和失效策略验证。
- 安全接受依赖预期圆柱几何的独立连续线段检查，同时 health gate 证明路径来源于在线 OctoMap；它不是任意场景的通用碰撞证明。
- 交互模式是一点一飞一降后继续等待的顺序多任务会话，不是一次解锁后连续穿越多个目标；每一轮都重新走 planner、安全检查、OFFBOARD、AUTO.LAND 和 landed/disarmed 合同。
- `NAV_DLL_ACT=0` 只适用于这个没有 GCS 的 PX4 SITL 演示；迁移实机时必须重新设计 GCS/RC data-link-loss action，不得照搬。
- 用户失败 run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260804-190430-Li1Gq0` 证明 QGC 的 `255.190` 流量触发 MAVROS 在 `MAV_CMD 520` 后 `double free or corruption`，导致 `/mavros/odometry/out` 只有 relay publisher、没有 MAVROS subscriber；原残留 DLIO/relay 已按记录身份 force-cleanup，证据保留。
- 首次 no-QGC flight run `runs/20260804-191913-jd7EDM` 证明基础栈、DLIO relay 和建图均 PASS，但 x500 默认 `NAV_DLL_ACT=2` 导致 arm 被拒；该失败证据原样保留，后续正式 run 通过官方参数 `0` 完整闭环。
- 2026-08-04 验证期间一次长航程交互任务在 waypoint 4 被既有 watchdog fail-closed 并安全降落；保留 run `20260804-165441-3R7iBU`。后续错误已改为输出 connected/armed/mode/state age/odom age 明细，未放宽阈值。
- 冷启动健康门曾分别拒绝一次 DLIO 单点 `0.196 s` max-gap 和一次 ROS CLI 取证缺失；后续全新 run 在相同参数下完整 PASS。失败证据均保留，未通过降低门槛制造 PASS。
