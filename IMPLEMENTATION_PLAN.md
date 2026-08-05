# PX4 三维 LiDAR 建图与 A→B 避障仿真实施计划

- 项目目录：`/home/albert/PX4-3D-LiDAR-Nav-Demo`
- 计划版本：`v1.0`
- 冻结日期：`2026-08-01`
- 主入口目标：`./demo.sh`
- 执行原则：一次只推进一个 Gate；先取得可见证据，再进入下一 Gate。

## 1. 最终结论和范围

本项目只完成一条简洁、实时、可重复的闭环：

```text
PX4 SITL + Gazebo 3D LiDAR
            ↓ point cloud + IMU
           DLIO
            ├─ odometry → MAVROS → PX4 EKF2
            └─ pose + cloud → OctoMap
                                 ↓
                    MRS MinimalOctomapPlanner
                                 ↓ 3D A* path
                    MAVROS OFFBOARD setpoints
                                 ↓
                     PX4 实际绕障飞到 B 并降落
```

最终必须同时看到 Gazebo 和 RViz 的实时图形界面。纯后台 topic、离线
rosbag 回放、静态路径图片都不能替代最终演示。

本阶段明确不做：

- 动态障碍预测、复杂自主探索、群机协同；
- 实机飞行、实机安全认证和飞控硬件适配；
- 自研 SLAM、OctoMap、A* 或飞控算法；
- 旧工程中的多层审计器、97 项 Gate、seal schema 或复杂 mission coordinator；
- 为了绕开单个错误而更换整套 ROS、PX4、SLAM 或规划框架。

## 2. 冻结的开源技术栈

| 环节 | 冻结方案 | 本项目只做什么 |
|---|---|---|
| 飞控 | PX4 v1.17 SITL / EKF2 | 复用现成运行时与参数 |
| 物理和传感器 | Gazebo Sim / 3D LiDAR | 复用现成世界、机体和传感器 |
| 激光惯性里程计 | Direct LiDAR-Inertial Odometry (DLIO) | 只检查输入、输出和坐标系 |
| ROS/PX4 接口 | MAVROS | 外部里程计回灌、状态读取、OFFBOARD 航点 |
| 三维地图 | ROS 2 `octomap_server` | 订阅点云和位姿，发布占据地图 |
| 三维规划 | MRS `MinimalOctomapPlanner` | 调用上游 OctoMap A* 服务 |
| 可视化 | RViz | 显示 LiDAR、OctoMap、位姿、A/B 和路径 |
| 薄连接层 | `src/ab_mission.py` 与 shell 脚本 | 启停、请求路径、限速发送航点、保存证据 |

除非已有组件被当前证据证明无法满足验收，不新增同类框架。

## 3. 冻结的演示场景和数据口径

- 坐标系：`map`
- A：`(0.0, 0.0, 2.2)`
- B：`(7.0, 7.0, 2.2)`
- 预期圆柱中心（局部 `map`）：`(3.5, 3.5)`
- 圆柱半径：`0.65 m`
- 最低演示净距：`0.70 m`
- 规划中心距下限：`1.35 m`
- 最低可见横向绕行：`0.55 m`
- 巡航速度：`0.65 m/s`
- 航点发送频率：`20 Hz`
- B 点误差目标：`≤ 0.40 m`，执行器内部航点容差为 `0.30 m`
- 到达 B 后保持：`3 s`，随后自动降落和解锁。

这些值以 `config/demo.yaml` 为唯一机器可读来源；计划和报告不得另建一套
不一致参数。

## 4. 最终验收合同

| 编号 | 必须满足的结果 | 主要证据 |
|---|---|---|
| AC-01 | Ubuntu 桌面实时显示 Gazebo，能看到无人机、圆柱障碍和实际运动 | Gazebo 截图/录屏 |
| AC-02 | RViz 实时显示 3D 点云、OctoMap、PX4 位姿、A/B 和规划路径 | RViz 截图/录屏 |
| AC-03 | MAVROS 已连接，PX4 本地里程计持续更新；飞行期间无 odometry/OFFBOARD watchdog 失败 | topic 采样、mission log、JSON events |
| AC-04 | 规划器返回完整非直线路径，路径长度大于直线至少 `0.10 m`，横向绕行至少 `0.55 m`，障碍中心距至少 `1.35 m` | `mission-result.json` metrics 和 RViz 路径 |
| AC-05 | PX4 实际进入 OFFBOARD、解锁、飞到 B、保持、自动降落并解除解锁 | Gazebo 视频、状态事件、最终 B 误差 |
| AC-06 | 每次正式运行至少保存视频、关键截图、最终 OctoMap、日志、JSON 和 SHA-256 清单 | 独立 `runs/<timestamp>/evidence/` |
| AC-07 | 从干净停止状态连续完成两次全新运行，不复用第一次进程和结果文件 | 两个不同 run 目录及各自 PASS 证据 |

只有 AC-01 至 AC-07 全部有本轮证据，项目才可以标记为“完成”。

## 5. 文件与边界策略

### 5.1 唯一交付目录

新项目 `/home/albert/PX4-3D-LiDAR-Nav-Demo` 是唯一交付入口。旧项目
`/home/albert/PX4-LiDAR-SLAM-Sim` 只作为只读重型运行时和历史经验档案：

- 可以调用其已安装的 PX4、Gazebo、ROS 2、DLIO、MAVROS 和 OctoMap；
- 不复制旧 `runs/`、旧报告或旧审计框架到新项目；
- 不删除旧项目；
- 如果确实要改旧运行时，必须先在 `PROJECT_MEMORY.md` 说明原因、改动面和回退方法。

### 5.2 新项目必须保持的入口

```text
demo.sh                 一键完整演示
scripts/start.sh        只启动可见栈，不解锁
scripts/fly_ab.sh       满足前置 Gate 后执行 A→B
scripts/stop.sh         保存地图和媒体并有序停止
config/demo.yaml        唯一任务参数
config/planner.yaml     上游规划器参数
config/demo.rviz        RViz 显示配置
src/ab_mission.py       薄任务执行器
PROJECT_MEMORY.md       当前真实进度和下一步
reports/index.html      人可浏览的状态与证据入口
```

### 5.3 修改纪律

- 一次尝试最多修改一到两个直接相关文件；
- 修改前记录当前失败命令、首个根因错误和对应日志路径；
- 修复后只重跑当前 Gate，不同时重构下一 Gate；
- 不允许把错误简单隐藏为 `|| true` 后宣称通过；
- 同一 Gate 连续两次遇到同一根因时，才升级到更强模型复核；
- 并行 Agent 只适合只读日志分析或独立测试，不允许多个 Agent 同时改启动链。

## 6. 当前基线（2026-08-01）

已经完成并有本地检查记录：

- 新目录、最小架构、配置、启动/飞行/停止入口已经建立；
- `bash -n` 和 `shellcheck -x` 已通过；
- `src/ab_mission.py` 已通过 `py_compile` 和 `--self-test`；
- MRS `MinimalOctomapPlanner` 已在隔离 ROS domain 中成功加载，服务类型为
  `mrs_modules_msgs/srv/Path`；
- 宿主缺少 `ffmpeg` 的首次启动前置错误已经定位，当前脚本改为复用旧运行时
  rootfs 内的 `ffmpeg`/`ffprobe`；
- 当前没有活动仿真 run，也没有把任何后台结果冒充实时 GUI 结果。

尚未完成：

- 修复 `ffmpeg` 路径后尚未重新启动完整 Gazebo + RViz；
- 新项目尚无在线建图截图；
- 尚无本项目 A→B 规划结果、实际飞行、降落视频；
- 尚无两次独立 PASS 运行。

## 7. 分阶段执行计划

### Gate 0：范围冻结和交接文件

状态：`DONE`

目标：保证后续模型从同一份边界开始，不重新扩展研究方向。

操作：

1. 阅读 `AGENTS.md`、本计划、`PROJECT_MEMORY.md`、`README.md` 和
   `docs/ARCHITECTURE.md`。
2. 确认旧项目已标为 archive，新项目为唯一交付入口。
3. 确认没有活动 demo run；保留报告服务不影响本 Gate。

通过条件：上述文件互不冲突，且本计划主文件与备份哈希一致。

推荐模型：`gpt-5.6-luna` Medium（若可用）或 `gpt-5.6-terra` Medium。

### Gate 1：静态检查和运行时边界

状态：`NEXT`

目标：不打开 GUI、不解锁，确认薄连接层和复用运行时可以被找到。

执行命令：

```bash
cd /home/albert/PX4-3D-LiDAR-Nav-Demo
git status --short --branch
bash -n demo.sh scripts/*.sh
shellcheck -x demo.sh scripts/*.sh
python3 -m py_compile src/ab_mission.py
bash -lc 'source scripts/common.sh; require_runtime'
bash -lc 'source scripts/common.sh; native_ros python3 src/ab_mission.py --self-test'
```

通过条件：所有命令退出码为 0；没有安装新依赖；没有启动残留 ROS/PX4 进程。

失败处理：只修首个确定错误。若是路径问题，优先修 `scripts/common.sh`；若是
接口/语法问题，才修改对应脚本。不得在此 Gate 启动完整仿真来掩盖静态错误。

产物：将命令、退出码和实际时间补充到 `PROJECT_MEMORY.md`。

推荐模型：`gpt-5.6-terra` Medium；纯日志整理可以用 `gpt-5.6-luna` Medium。

### Gate 2：只启动实时可见 GUI 栈

状态：`PENDING`

目标：打开真实 Gazebo 和 RViz，验证启动编排；本 Gate 禁止解锁和飞行。

前置条件：Gate 1 PASS，桌面会话可见且没有旧 demo run。

执行：

```bash
cd /home/albert/PX4-3D-LiDAR-Nav-Demo
./scripts/start.sh
```

必须人工或多模态观察：

1. Ubuntu 桌面出现可交互 Gazebo 窗口；
2. 场景内能看见 PX4 无人机与圆柱障碍；
3. 桌面出现 RViz 窗口，且不是静态截图；
4. RViz 固定坐标系为 `map`，界面没有持续红色 Global Status；
5. 窗口至少稳定保持 30 秒，进程没有自行退出。

只读接口检查：

- `/mavros/state` 有连接状态；
- `/mavros/local_position/odom` 持续更新；
- `/lidar_3d/points` 或当前冻结的 LiDAR topic 有消息；
- `/octomap_binary` 存在；
- `/demo/minimal_planner/get_path` 类型正确；
- `/tf` 中存在完成 `map` 到传感器/机体显示所需的变换。

通过证据：保存一张 Gazebo 全景和一张 RViz 全景，记录 node/topic/service
摘要。此时只写“GUI stack PASS”，不能写“A→B PASS”。

安全停止：

```bash
./scripts/stop.sh
```

推荐模型：`gpt-5.6-terra` High。出现窗口、X11、DDS 或多进程顺序问题时，
不要交给 `luna` 自由改动启动链。

### Gate 3：定位与三维建图

状态：`PENDING`

目标：证明三维 LiDAR + IMU 的估计和 OctoMap 是在线数据流，而不是仅有节点名。

前置条件：重新运行 `./scripts/start.sh`，Gate 2 的两个窗口都可见。

检查顺序：

1. 观察 RViz 点云随仿真时间刷新；
2. 确认 DLIO odometry 时间戳、频率和有限数值持续更新；
3. 确认 MAVROS/PX4 本地 odometry 新鲜，无明显坐标跳变；
4. 确认 OctoMap 随点云生成，占据体与 Gazebo 圆柱位置相符；
5. 截取同一时刻的 Gazebo 与 RViz，便于对比障碍物。

通过条件：点云、odometry、OctoMap 三者都实时更新；圆柱在地图中可辨识；
没有 TF extrapolation 风暴；数据停止时能被检测出来而不是继续用陈旧值。

失败优先级：先查 topic 名和时间戳，再查 TF/frame，最后才查算法参数。禁止
第一反应更换 SLAM 算法。

产物：topic 频率/时间戳摘要、Gazebo/RViz 对照截图、相关日志路径。

推荐模型：`gpt-5.6-terra` High。

### Gate 4：只验证 A→B 三维路径

状态：`PENDING`

目标：在不解锁无人机的情况下，先确认上游规划器能基于当前 OctoMap 返回
穿不过圆柱、具有可见绕行的路径。

执行策略：优先直接用 ROS 2 service CLI 调用
`/demo/minimal_planner/get_path`，请求 A `(0,0,2.2)` 到 B `(7,7,2.2)`；不要
为了这一步新增另一个规划程序。若 CLI 响应字段难以核验，可给现有
`ab_mission.py` 增加一个最小 `--plan-only` 参数，但必须单独测试且不得解锁。

通过条件：

- service 返回 `success=true` 和 complete path；
- 路径端点是 A/B，所有高度位于 `1.5..3.0 m`；
- `path_length > direct_distance + 0.10 m`；
- `max_cross_track ≥ 0.55 m`；
- `minimum_obstacle_center_distance ≥ 1.35 m`；
- RViz 中能看见路径从圆柱旁绕过，而不是穿模。

若失败：先核对 OctoMap 中障碍位置和 `map` 坐标，再核对 planner remap 和
膨胀距离；一次只改一个参数，不调低安全距离来制造 PASS。

产物：原始 service 响应、计算后的路径 metrics、RViz 路径截图。

推荐模型：`gpt-5.6-terra` High。

### Gate 5：PX4 实际 A→B 闭环飞行

状态：`PENDING`

目标：只在 Gate 2–4 均 PASS 后，让 PX4 实际沿已验证路径飞行。

执行：

```bash
./scripts/fly_ab.sh
```

观察顺序：

1. 飞行前无人机在 A 的 XY 附近，处于落地、未解锁状态；
2. 连续位置 setpoint 预热后进入 `OFFBOARD`；
3. 解锁并上升到 `2.2 m`；
4. 地图预热完成后取得已验证的规划路径；
5. Gazebo 中无人机实际绕开圆柱，RViz 位姿沿路径移动；
6. 到达 B，误差 `≤0.40 m`，保持 3 秒；
7. 切换 `AUTO.LAND`，最终 landed 且 disarmed。

执行器的 watchdog 失败、OFFBOARD 丢失、odometry 陈旧或路径指标不合格，
任一情况都必须判定该 run FAIL，并优先尝试自动降落。

通过证据：`mission-result.json` 为 PASS，包含完整事件、路径 metrics、执行轨迹
和 B 点误差；Gazebo/RViz 录像可看见真实运动和绕障；最终状态为降落且解锁。

失败后先保存 run，再运行：

```bash
./scripts/stop.sh
```

不得直接删除失败 run，也不要用失败 run 的部分产物拼接 PASS。

推荐模型：`gpt-5.6-terra` High。若同一个根因已在两个干净 run 中复现，携带
最短复现命令和对应日志，临时升级 `gpt-5.6-sol` High 诊断；修复后仍回到
Terra 执行验证。

### Gate 6：一键复现、证据和最终交付

状态：`PENDING`

目标：证明闭环不是一次偶然成功，并形成简洁可读的交付。

执行：

1. 有序停止并确认没有旧 demo/PX4/ROS/Gazebo 残留；
2. 从项目根目录运行一次 `./demo.sh`；
3. 完整 PASS 并停止后，再从干净状态运行第二次 `./demo.sh`；
4. 核对两个独立 run 的视频、截图、`.bt` 地图、JSON、日志和 SHA-256；
5. 更新 `PROJECT_MEMORY.md`、`README.md` 和 `reports/index.html`；
6. 报告只保留架构、运行命令、两次结果、截图/视频、已知边界，不恢复旧审计体系。

最终交付清单：

- 一条命令：`./demo.sh`；
- 一张闭环架构图；
- 两次新鲜 PASS 的 run 目录；
- Gazebo 与 RViz 关键截图；
- 一段能看见建图、规划、绕障和降落的完整视频；
- 最终 OctoMap；
- A/B、路径净距、B 点误差等机器可读结果；
- 实机迁移时需要重新处理的坐标系、标定、时延和安全边界说明。

推荐模型：`gpt-5.6-terra` Medium 负责机械复现和整理；最终跨组件真实性复核
可使用 `gpt-5.6-sol` Medium/High。

## 8. 小模型执行协议

每次只给模型一个 Gate，不要直接说“把整个项目全部做完”。建议提示词：

```text
你现在只执行 IMPLEMENTATION_PLAN.md 的 Gate N。
先读 AGENTS.md、IMPLEMENTATION_PLAN.md、PROJECT_MEMORY.md、README.md 和
docs/ARCHITECTURE.md，再运行 git status。不得提前执行下一 Gate，不得新增同类
SLAM/规划框架，不得删除旧 run。先复现并记录首个根因；最多修改两个直接相关
文件。完成后运行本 Gate 的验证命令，更新 PROJECT_MEMORY.md 和 reports/status.json，
明确列出 PASS 证据、尚未验证内容和下一 Gate，但不要自动进入下一 Gate。
涉及 Gate 5 解锁飞行前，必须重新确认 Gate 2、3、4 本次运行均已 PASS。
```

建议模型分配：

| 工作 | 首选模型 | Reasoning |
|---|---|---|
| 文档读取、状态整理、哈希/文件检查 | `gpt-5.6-luna`（若模型列表可用） | Medium |
| 静态检查、小范围 shell/Python 修复 | `gpt-5.6-terra` | Medium |
| Gazebo/RViz/DDS/TF/SLAM/规划在线联调 | `gpt-5.6-terra` | High |
| 实际 OFFBOARD 飞行与故障保护验证 | `gpt-5.6-terra` | High |
| 两次同根因失败后的深度诊断、最终真实性复核 | `gpt-5.6-sol` | High |

不建议默认使用 Max 或 Ultra。这个项目当前的主要风险是共享进程、坐标系和实时
状态，不是可无限并行的代码量；多个写入型 Agent 容易互相停止进程、覆盖状态或
误用另一 run 的证据。只有日志分析、静态测试和报告整理可在明确分工后并行。

## 9. 升级和停止条件

满足任一条件，当前小模型应停止改动并把证据交给更强模型：

- 同一首个根因在两个干净尝试中重复出现；
- 需要同时修改旧运行时和新项目三个以上文件；
- 需要改变冻结的 SLAM、规划器或坐标系架构；
- PX4 解锁后出现无法确认的状态、位置跳变或无法自动降落；
- GUI 观察与后台 topic/JSON 相互矛盾；
- 为获得 PASS 必须降低净距、关闭 watchdog 或复用旧证据。

发生上述情况时，不标记 blocked 也不伪造进度；保留失败 run，写清：最短复现
命令、首个错误、日志路径、已经排除的原因和建议复核范围。

## 10. 进度更新规则

每个 Gate 结束后同时更新：

1. `PROJECT_MEMORY.md`：事实、命令、结果、问题、下一步；
2. `reports/status.json`：当前 Gate、状态和证据链接；
3. `reports/index.html`：只有结构或最终证据展示需要变化时才修改页面；
4. 当前 run 内的日志和 evidence：不可手工美化或跨 run 拼接。

进度百分比只能表示 Gate 完成比例，不能用“代码大致写完”代替实时闭环证据。

## 11. 当前下一步

由新的执行模型从 Gate 1 开始，先重跑静态检查和运行时边界。Gate 1 PASS 后，
停止并汇报；得到继续指令后再进入 Gate 2，重新运行修正了 `ffmpeg` 路径的
`./scripts/start.sh`，由真实 Gazebo/RViz 窗口决定是否通过。

