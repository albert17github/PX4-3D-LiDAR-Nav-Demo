# Project Memory

## Objective

在 Ubuntu 24 桌面中实时显示 Gazebo 和 RViz，让 PX4 SITL 无人机使用三维 LiDAR + IMU 完成定位与 OctoMap 建图，调用开源 MRS 三维 A* 规划器获得固定 A→B 或 RViz 交互目标路径，再通过 MAVROS OFFBOARD 位置航点实际飞完整条路径并自动降落。交互模式作为后续演示技术底座，应在同一会话中支持多次选点，同时保持自写代码只承担薄编排和安全连接层。

## GitHub README 16:10 image crops — PASS (2026-08-06)

- GitHub 主页 `README.md` 的“运行画面”不能依赖报告页 CSS 裁切，因此新增 4 张独立展示图并改为直接引用；四张文件均为 RGB `960×600`（16:10）。运行画面使用 GitHub 会保留的 `width="100%"` 表格、两个 `width="50%"` 列和只指定宽度的图片，锁定双栏尺寸且让高度按原比例计算。
- `gazebo-world-ready-16x10.png`、`rviz-map-ready-16x10.png` 与 `rviz-flight-path-16x10.png` 保留各自主场景；`gazebo-landed-b-16x10.png` 使用更近的 16:10 裁剪框，让落地后的 x500 在主页双栏缩略图中清晰可见。准确来源与裁剪框记录在 `reports/assets/README.md`。
- 展示图只做确定性裁剪与等比例缩放，没有拉伸或生成式重绘。4 张原始证据图未覆盖，原始 SHA-256 保持不变；`reports/assets/SHA256SUMS` 现在同时核验 4 张原图和 4 张展示图，8 项全部 PASS。
- Firefox 直接打开 GitHub 分支主页验证：4 个 cell 均为 `418.5 px`，4 张展示图均为 `391.5×244.68 px`、计算比例 `1.6`、自然尺寸 `960×600`，全部加载成功且页面横向溢出为 0。交付分支为 `docs/readme-gallery-16x10`，对应 PR #4。
- 本阶段只修改 README、图片来源说明、哈希清单和新增展示资产，不修改报告页、SLAM、OctoMap、规划、飞行脚本或 PX4 参数。

## Public copy and 16:10 gallery — PASS (2026-08-06)

- `README.md`、`reports/index.html` 与 `reports/assets/README.md` 的公开文案已收敛为项目能力、组件、运行画面和参考结果；移除了“补拍、调整视角、另一轮任务”等调试过程表述。报告截图标签现在描述 Gazebo、RViz、OctoMap 与 MRS 3D A* 本身，不再把图片获取过程当作页面主内容。
- 公开参考结果统一到主路径图对应的 `runs/20260806-101021-Gv9JVf`：8 个 `planned_path` 点、路径长 `12.75285 m`、cross-track `3.11127 m`、障碍中心距 `2.85576 m`、B 误差 `0.04039 m`，随后 `AUTO.LAND`、`landed_disarmed`，mission verdict 为 PASS。README、HTML 和 `reports/status.json` 使用一致的三位小数展示值。
- 报告截图区由交错时间线改为桌面端规整 2×2、移动端单列；每个图片区使用固定 16:10 容器、`object-fit: cover` 和逐图 `object-position`，通过裁切统一比例，没有拉伸或改写原始 PNG。`reports/assets/SHA256SUMS` 的 4 张原图全部复核通过。
- Firefox headless 实测桌面 `1440×1414` 与移动端 `500×1614`：4 个图片区计算比例均为 `1.6`、`object-fit=cover`，页面横向溢出均为 0；人工检查确认物理世界、在线地图、A→B 路径和落地无人机仍位于裁切后的可视区域。HTML 相对链接/锚点、JSON、公开指标一致性、禁用调试措辞扫描与 `git diff --check` 均 PASS。
- GitHub 交付分支为 `docs/refine-public-copy-gallery`，对应 PR #3；公开报告入口仍为 `https://albert17github.github.io/PX4-3D-LiDAR-Nav-Demo/`。
- 本阶段只修改公开文档、报告 CSS/HTML 与机器可读参考结果，没有修改 SLAM、OctoMap、规划、飞行脚本、PX4 参数或任何原始图片。

## RViz path image camera retake — PASS (2026-08-06)

- 为避免首页路径图中 LiDAR 扫描与中央障碍在观察方向上重合，重新运行固定 A→B 任务，并只使用 RViz `Move Camera` 调整观察角度；没有修改地图、规划、飞行代码或参数。
- Demo run `runs/20260806-101021-Gv9JVf` 在 `248 s` ready，得到 8 点完整路径：路径长 `12.75285 m`、cross-track `3.11127 m`、障碍中心距 `2.85576 m`、B 误差 `0.04039 m`，随后 `AUTO.LAND`、`landed_disarmed`，mission verdict 为 PASS。
- 新图由 RViz `File → Save Image` 直接导出为 `900×708`，替换 `reports/assets/rviz-flight-path.png`；SHA-256 为 `c9a106450328d1f8519f5f1c1a737e09127e470a953ef0fa85cd2ba1d62defcf`。原始分辨率检查确认无对话框、桌面或黑块，扫描面、位姿轴和中央障碍已在画面上分开。
- 停止后 demo/base active marker 与受管进程为 0。停止脚本因 `/mavros/extended_state` 未发布而记录 `px4_lio_restore=SKIPPED_NOT_PROVEN_LANDED`；下一次启动仍会按现有 boot profile 先修复参数，不能把本轮记录为参数 restore PASS。

## Public GitHub landing and report — PASS (2026-08-06)

- GitHub 首页 `README.md` 已改为面向首次访问者的项目说明，只保留功能、真实 Gazebo/RViz 图片、架构、安装、使用、参考结果、运行边界和贡献入口；移除了内部 run 编号、旧版本流水账、作者目录、工作记忆入口和本机 `127.0.0.1` 报告地址。
- `reports/index.html` 保留 4 张 Gazebo/RViz 应用内导出图片和 HTML/CSS 标注，但文案改为具体的组件、动作与测量结果，去掉口号式标题、客户/用户归责语气和内部验收措辞。公开链接统一使用仓库相对路径、GitHub 源码地址或 GitHub Pages 地址。
- 根目录 `index.html` 将 GitHub Pages 入口转到 `reports/`；公开目标 URL 为 `https://albert17github.github.io/PX4-3D-LiDAR-Nav-Demo/`。Open Graph、canonical 与页面图片 URL 均使用该公开地址，不再引用临时预览服务。
- 新增 `CONTRIBUTING.md`、结构化 bug issue 表单和图片 `SHA256SUMS`；本地检查增加公开文档链接与本机地址扫描。`.gitattributes` 将根入口与报告 HTML 标为 `linguist-documentation`，使 GitHub 语言统计反映 Python/Shell 主实现而不是介绍页篇幅。曾准备的 GitHub Actions 文件因当前 OAuth token 没有 `workflow` scope 而未推送，未扩大账号权限。
- 本地复验通过：全部 Shell `bash -n`/`shellcheck -x`、Python `py_compile`、`./setup.sh --verify-only`、HTML/JSON 解析、README/报告相对链接、公开文档本机地址扫描和 4 张 PNG 哈希。四张原图已再次以原始分辨率检查；Firefox 实际打开并检查了报告首页、场景区和参考结果区。
- 本阶段未改 SLAM、OctoMap、规划、任务执行或 PX4 参数。唯一运行时脚本改动是把可选 seed copy 中的个人 home 排除路径泛化为 `/home/***`，默认安装和启动路径不受影响。

## Recommended environment + software-native report — PASS (2026-08-06)

- 复刻策略已从“自动兼容尽可能多的网络和 PRoot 边角情况”收敛为“只支持明确的推荐环境”。正式边界为 Ubuntu 24.04 LTS Desktop、Linux `x86_64`、Bash ≥ 5.2、Git ≥ 2.43、Python 3.12.x、至少 4 线程、guest 内至少 10 GiB RAM、首次安装至少 20 GiB 可用空间，以及可连接的 X11/XWayland `DISPLAY`；详细推荐值在 `docs/REPRODUCE.md`。
- 新入口 `./scripts/check_environment.sh --setup|--run` 只做检查，不安装软件、不修改软件源、代理、DNS 或虚拟机设置。`--run` 额外核验 ROS 2 Jazzy、Gazebo Harmonic、关键 runtime 文件，以及 PX4 `v1.17.0`、DLIO、MAVROS `2.14.0` 的固定 commit。`scripts/start.sh` 在任何仿真进程启动前执行 `--run`。
- `setup.sh` 不再提供 `--install-host-deps`。它按 6 个阶段输出环境检查、源码下载、rootfs、包安装、构建和最终核验；失败时固定显示阶段、日志绝对路径和重试命令，不再为不同客户网络自动切镜像或堆叠专项修复。上一轮尚未提交的 OSRF key/hash/index retry gate 已撤掉；已提交的 6 个 PX4 依赖、串行下载、超时重试和简单 HTTPS 修正保留。
- 静态与负向检查已通过：`bash -n`、`shellcheck -x`、`git diff --check` 均为 PASS；`DISPLAY=` 的 `--run` 检查以 exit 10 在 desktop display 项明确失败；当前机 `./scripts/check_environment.sh --run` 与 `./setup.sh --verify-only` 均 PASS。
- 重新冷启动 run `runs/20260806-001212-uVRmSE`，base run `runtime/runs/20260806-001217-nlQ1VC`。新增环境检查先 PASS，完整栈 `247 s` ready；固定 A→B 获得 9 点完整路径，路径长 `13.507 m`、cross-track `3.394 m`、障碍中心距 `3.129 m`、B 误差 `0.037 m`，随后 `AUTO.LAND`、`landed_disarmed`，mission verdict 为 PASS。
- 该 run 停止后 demo/base active marker 和 PX4/Gazebo/RViz/DLIO/OctoMap/MAVROS 进程均为 0；但停止状态记录 `px4_lio_restore=SKIPPED_NOT_PROVEN_LANDED`，表示停止脚本当时未能再次证明 landed/disarmed，因而正确跳过恢复写参。下一次启动仍会先执行 boot profile 修复；不能把本轮描述为参数 restore evidence PASS。
- `reports/index.html` 已重写为项目介绍页。4 张跟踪图片来自同一 run 的 Gazebo `Screenshot` plugin 或 RViz `File → Save Image` render panel，不含桌面、终端或浏览器；原图尺寸、语义、人工多模态检查和 SHA-256 在 `reports/assets/README.md`。Firefox 实际页面已打开检查，桌面版 hero、字体层级、图片、导航和注释正常；页面资源 HTTP 检查均为 200。

## Self-contained runtime + corrected geometry — 2-RUN PASS (2026-08-05)

- 项目默认运行时已从兄弟项目迁入本 checkout 的 `runtime/`。当前首次入口是 `./scripts/check_environment.sh --setup` 后执行 `./setup.sh`；`./setup.sh --verify-only` 核验 source commit、补丁、动态库闭包、Python 自测、apt manifest 与仿真几何合同；默认启动链不读取 `/home/albert/PX4-LiDAR-SLAM-Sim`、`RVPX4` 或其他兄弟目录。
- 私有 GitHub feature branch 的全新 clone 已从零执行到 Gazebo/Harmonic 依赖解析阶段，期间真实发现并修复 PRoot 下 `apt-key` 对新 keyring 的可读性误判。仓库现在跟踪 ROS 官方公钥并固定 fingerprint `C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654`；安装时先用 `gpgv` 验证签名 `InRelease`，apt 再通过 `Signed-By` 复验，不使用 `Trusted: yes` 或跳过证书检查。为避免再生成一套约 `14 GiB` 的重复环境，该干净副本在越过故障点、进入 730 个 Gazebo 包下载后按用户要求停止并移入回收站；不能把它记作完整 clean-install PASS。当前主 checkout 的完整 runtime 核验与下面两轮端到端飞行 PASS 不受影响。
- Git 只跟踪安装配方、版本锁、补丁、模型、world 与脚本；约 `14 GiB` 的 rootfs、源码 checkout、build、overlay、日志和 run 都由 setup 生成并在 `.gitignore` 排除。`runtime/config/versions.env` 固定 Ubuntu Noble WSL rootfs URL/SHA、PRoot SHA、PX4 `v1.17.0` commit `d6f12ad1`、DLIO commit `c8acc371`、MAVROS `2.14.0` commit `c655e634` 与所有补丁 SHA。
- 迁移不复制旧 run、报告或 ULog；当前 runtime 中三套源码 checkout 都有官方 origin、无 Git alternates，也没有指向兄弟项目的 symlink。`--seed-from` 只保留为显式的本机迁移加速选项，普通用户不需要。
- MAVROS 早期偶发 `double free or corruption` 的根因位于固定 `2.14.0` 中两个上游已修复的并发区：原 vehicles map 锁补丁之外，新增按上游 `bf464a2b`、`65cec447`、`07944251`、`d07483ee` 提取的 router `remote_addrs/stale_addrs` 锁补丁。修补后的 `libmavros.so`/`libmavros_plugins.so` 哈希进入 runtime lock，连续正式 run 未再出现崩溃。
- 原任务还存在一个独立坐标契约错误：world 中车辆初始 yaw=`0.55 rad`，历史配置却把未旋转 world 差值 `(3.5,3.5)` 直接冒充 DLIO `map` 坐标。两轮当前 ULog 用 Gazebo ground truth 拟合得到 `map→world` 旋转 `31.51°`，与初始 yaw 一致。只改校验坐标会让圆柱离开 A→B 中线，因此最终保留非零初始航向，并把 `cyan_pillar` world 位姿移到 `(-6.845569,-1.186759)`，使其经 SE(2) 变换后严格为 `map=(3.5,3.5)`、真正位于 A→B 中点。
- `scripts/check_simulation_contract.py` 会读取 `config/demo.yaml` 与 `runtime/worlds/lidar_slam_course.sdf`，自动核对车辆/圆柱名称、world 位姿、半径和换算后的 map 坐标；它已进入 `verify-runtime.sh`。安全阈值仍是半径 `0.65 m` + 净距 `0.70 m` = 中心距 `1.35 m`，没有调低。
- 修正场景后的两个独立正式 run 均完整 PASS：`runs/20260805-182916-btMc4A` 路径 `12.88595 m`、cross-track `3.11127 m`、中心距 `2.96055 m`、B 误差 `0.02440 m`；`runs/20260805-183516-xIDcJr` 路径 `12.72449 m`、cross-track `3.11127 m`、中心距 `2.92710 m`、B 误差 `0.03733 m`。两轮均 visible Gazebo + RViz、在线 OctoMap、完整 MRS path、OFFBOARD、arm、全部 waypoint、AUTO.LAND、landed/disarmed、截图/视频/地图 SHA-256 全通过，clean stop 后受管进程与两层 active marker 均为 0。
- 两轮冷启动总计 `235/237 s`，底层 readiness `194/198 s`；相对此前已优化的 `287 s` 再缩短约 `17%..18%`。另修复 MRS component discovery 的瞬时竞态：容器必须显式 ready，load 使用 `10 s` discovery 并最多重试 3 次；一次未解锁失败 run `20260805-182343-iauTdk` 原样保留，随后两轮均首次加载成功。
- `src/ab_mission.py` 的 waypoint settle timeout 现在至少 `10 s`，并按航段飞行时间加 `8 s` 余量；整个 settle 期间仍执行 `0.5 s` odometry 与 OFFBOARD watchdog。这修复了到达容差边缘时刚进入稳定窗口便超时的问题，不是放松飞行状态门。
- 版本路线：`v0.1.0-initial` → `v0.2.0-lio-yaw` → `v0.3.0-self-contained` → `v0.3.1`（公开开源发布）。用户已明确授权将 GitHub repository visibility 改为 `public`；项目自写的启动编排、薄任务连接层、配置和文档采用 `Apache-2.0`，上游组件与源自上游代码的补丁继续受各自许可证约束。公开前对全部 Git 历史做了已知 token/private-key 模式扫描，唯一命中是进程归属校验使用的非敏感运行时 `token` 字段；仓库无 Actions run、release 或超过 5 MB 的历史 blob。
- 未删除任何旧项目或历史证据。被忽略的失败复制目录 `runtime/.setup/rootfs.partial-20260805-1655` 约 `1.4 GiB` 也仍保留，只有用户确认准确路径后才能删除。

以下章节为本轮自包含改造之前的历史记录；涉及“共享基线”或旧 `(3.5,3.5)` 计算的描述用于追溯，不再代表当前启动链与几何口径。

## LIO position/velocity/yaw authority — 4-FLIGHT PASS (2026-08-05)

- 长距离、多次飞行后“箭头乱、飞机乱飞”的主因不是 A*：旧配置 `EKF2_EV_CTRL=1` 只融合 DLIO 水平位置，PX4 yaw 仍由磁航向/IMU 独立维护；PX4 heading reset 会把 `LOCAL_FRD` 外部位置重新旋转。历史异常中位置跳变量与 `2 r sin(Δyaw/2)` 一致，且 A* 在发散前未被调用。
- 当前修复不更换 SLAM、规划器或飞控算法。`config/px4-lio-yaw.params` 定义三个生命周期：启动兼容态 `EKF2_EV_CTRL=1, EKF2_MAG_TYPE=6`；DLIO 就绪后的飞行态 `EKF2_EV_CTRL=13`（horizontal position + body velocity + yaw）；安全停机恢复态 `EKF2_EV_CTRL=1, EKF2_MAG_TYPE=0`。`MAG_TYPE=6` 只用于上电初始化，飞行中磁航向不再与 LIO yaw 竞争。
- `scripts/start.sh` 会先用 PX4 `PX4_SIM_MODEL=shell` 最小启动修复持久参数，即使虚拟机异常退出、上次来不及恢复，也能重新进入启动合同。运行时 READY 且已证明 landed/disarmed 后才切换到 flight profile；只有实时读到 `cs_ev_pos/cs_ev_vel/cs_ev_yaw=True`、`cs_mag_hdg/cs_mag_3d=False`、`cs_ev_yaw_fault=False` 才继续启动 planner/RViz。
- `scripts/stop.sh` 只在 MAVROS 同时证明 `armed=false`、`landed_state=1` 时恢复下一次启动参数；本轮 readback 为 `EV_CTRL 13→1`、`MAG_TYPE 6→0`。若落地条件不能证明则跳过写参，由下一次项目启动的最小 shell 修复，绝不在飞行中切换估计器。
- MAVROS `ODOMETRY` 的 `MAV_FRAME_LOCAL_FRD` 是 PX4 对本地外部里程计的官方帧语义；此时 `cs_yaw_align=False` 是 EKF2 源码的预期状态，不能为了让标志变 True 而伪装成 `LOCAL_NED`。真实系统无磁航向时，应在实际启动编排中让 LIO yaw 在飞行前可用；有磁航向时可像本仿真一样只用于初始 `map→odom` 对齐，飞行中仍保持单一 LIO yaw 权限。
- `src/ab_mission.py` 现在保持当前航向垂直起飞，到 `2.2 m` 后才以不超过 `45°/s` 原地转到任务 yaw；每个 waypoint 同时检查位置和 `10°` yaw 误差。满负载实测 `/mavros/state` 仅 `0.55..1 Hz`，低频状态门改为 `5 s` 以容忍一次漏报；真正的控制反馈 `/mavros/local_position/odom` watchdog 仍保持 `0.5 s`。
- 正式验证 demo run `runs/20260805-151557-Otlbug`、base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260805-151611-RZ9WfJ` 已 clean stop。启动总计 `303 s`：参数准备 `8 s`、base readiness `262 s`、估计器/no-GCS `8 s`、planner `17 s`、RViz/recording `8 s`。
- 同一个 PX4/EKF2/DLIO/OctoMap 实例连续四次 PASS：`(7,0)→(7,7)`、`(7,7)→(7,3)`、`(7,3)→(9,3)`、`(9,3)→(9,5)`；目标 yaw 依次为 `+135°/-135°/0°/180°`，路径长 `7.730/4.045/2.183/2.228 m`，目标误差 `0.051/0.045/0.028/0.045 m`，最远目标半径 `10.296 m`，每轮均 AUTO.LAND、landed/disarmed。
- 四份闭合 ULog `07_35_07.ulg`、`07_37_17.ulg`、`07_39_30.ulg`、`07_41_12.ulg` 独立证明：飞行中 EV position/velocity/yaw 始终启用，磁航向始终关闭，horizontal position/velocity/yaw innovation 全部未拒绝，failsafe/failure detector 为零，ULog dropout 为零；`heading_reset_counter` 和 `quat_reset_counter` 各自全程固定为 `2`，飞行中增量均为 `0`。
- 使用一套固定 SE(2)（禁止逐航次重新对齐）比较任意 DLIO 局部系与 Gazebo ground truth，四次飞行合计位置残差 mean/p95/max=`0.053/0.110/0.128 m`，yaw 残差 mean/p95/max=`0.60°/1.78°/3.04°`。机器摘要为 `runs/20260805-151557-Otlbug/evidence/lio-yaw-ulog-summary.json`，最终截图、`112 MB` RViz 视频、4 个 mission JSON、参数 readback、地图与 SHA-256 同目录保存。
- 验证途中另发现两个独立边界：部分目标会被上游 MRS 返回 `Incomplete path`，控制器会悬停重试后自动降落；一次 SITL `battery_simulator` 工作项虽显示 running 但停止发布，PX4 以 `Battery unhealthy` 拒绝再次解锁，落地后重启模拟电池模块才恢复。两者均 fail-closed，没有引发乱飞；电池模块现象属于仿真运行时问题，不能用关闭实机电池健康门来规避。
- 版本基线已推送到私有 GitHub 仓库 `albert17github/PX4-3D-LiDAR-Nav-Demo`：初始提交 `1f535b2`、标签 `v0.1.0-initial`。本修复在 `fix/lio-yaw-authority` 分支叠加；完成提交后以 `v0.2.0-lio-yaw` 标记，后续工作从该版本继续。

## Startup recovery and optimization PASS — 2026-08-05

- 虚拟机在 demo run `runs/20260805-110928-9hWdJE` 启动期间异常重启；base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260805-110934-bhEfY4` 已完成全部组件 readiness，但仍在执行重复的完整 startup health。重启后没有受管进程存活，两层 stale marker 已通过现有 `scripts/stop.sh` / `stop_sim.sh` 有序封存，失败证据保留。
- 历史四个成功 base run 的冷启动耗时约 `629..755 s`；本次异常 run 在 `493 s` 时仍未完成。组件 readiness 约用 `250 s`，其后的 66 项通用 startup health 重复调用独立 `ros2 --no-daemon` 探针，是主要额外耗时；本次 health 还出现一次瞬时 PX4-pose TF 合同失败。
- 为避免修改或复制 SLAM、OctoMap、planner、MAVROS 和 PX4 算法，只给重型运行时的 `scripts/start_sim.sh` 增加显式、可审计的 `--startup-health readiness|full` 编排选项：基线默认仍为 `full`，本项目入口选择 `readiness`，并继续保留逐组件 readiness、landed/disarmed、PX4 fusion、TF、OctoMap、no-GCS readback、planner service、可见 RViz 和任务 watchdog。
- 改动面限制为基线启动编排入口与本项目 `scripts/start.sh`，不改变任何 health 阈值、算法、topic、frame、参数或飞行安全检查。回退无需修改文件：使用 `PX4_DEMO_STARTUP_HEALTH_MODE=full ./demo.sh --interactive` 即恢复原完整 startup health；若验证失败，则移除本项目传参并撤销基线新增选项。
- 新冷启动 demo run `runs/20260805-113113-Yd1sN7`、base run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260805-113117-NrNymV` 实测 PASS：base readiness `263 s`、no-GCS policy `1 s`、planner `19 s`、RViz/录像 `4 s`，从入口到 `waiting_for_interactive_goal` 总计 `287 s`（4 分 47 秒）。此前四次成功 demo 冷启动为 `655..784 s`，本次节省 `368..497 s`，约快 `56%..63%`。
- 本轮可见证据为 `evidence/desktop-readiness.png` 与 `evidence/rviz-readiness.png`：Gazebo 场景、RViz 3D LiDAR、PX4 EKF2 pose 和 OctoMap 同屏可见且状态为 OK。在线只读核验得到 MAVROS `connected=True`、local odom frame=`map`、二进制 `OcTree` resolution=`0.4`、occupied width=`1622`，planner service 为 `mrs_modules_msgs/srv/Path`。
- 该优化验证会话后来已通过统一停止入口关闭；它只验证冷启动和等待状态，没有自动解锁或触发飞行。快速模式已经真实冷启动验证，`full` 模式保留为基线默认并通过静态检查，但本轮没有再花 10–13 分钟重复一次完整 66 项运行时审计。
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
./scripts/check_environment.sh --setup
./scripts/check_environment.sh --run
./setup.sh --verify-only
python3 -m py_compile src/ab_mission.py
source scripts/common.sh
native_ros python3 src/ab_mission.py --self-test
bash -n demo.sh scripts/*.sh
shellcheck -x demo.sh scripts/*.sh
```

证据校验示例：

```bash
cd runs/20260805-151557-Otlbug/evidence
sha256sum -c sha256.txt
```

## Important files

- `src/ab_mission.py`：planner client、独立路径校验、OFFBOARD 执行与安全落地。
- `config/px4-lio-yaw.params`：PX4 boot/runtime/restore 三阶段 external odometry 与 yaw 权限合同。
- `config/demo.yaml`：A/B、交互目标、几何验收、速度、warmup 与规划重试合同。
- `config/planner.yaml`：MRS planner 参数。
- `reports/index.html`、`reports/status.json`、`reports/guided-experiment-20260803.json`：最终逐步网页报告、状态和机器摘要。
- `reports/assets/`：Gazebo/RViz 软件内部导出的介绍页原图、来源说明与 SHA-256。
- `runs/20260803-120927-6lYpVn/evidence/`、`runs/20260803-122744-TgKS1c/evidence/`：两套最终独立证据。
- `runs/20260803-142437-0S5Hkc/evidence/`、`runs/20260803-144745-8J6JGv/evidence/`：本次逐步复现实验的安全拒绝与任务 PASS 证据。
- `runs/20260804-172738-8jPZ9i/evidence/`：RViz 交互选点 PASS 的视频、截图、地图、任务 JSON 与哈希。
- `runs/20260804-193505-kEjVgs/evidence/`：无 QGC 交互飞行 PASS 的视频、截图、地图、参数 readback、任务 JSON 与哈希。
- `runs/20260804-202200-Hs10L6/evidence/`：同一会话两次实际飞行、两个独立 mission JSON、视频、地图和哈希。
- `runs/20260804-203906-n9Br4K/evidence/`：固定 `+90°` 朝向的实际 yaw/target yaw 轨迹、任务 JSON、视频、地图和哈希。
- `runs/20260805-151557-Otlbug/evidence/`：LIO position/velocity/yaw 修复后的四次连续任务、四份 ULog 汇总、Gazebo 真值对照、视频、参数生命周期 readback 与哈希。

## Known boundaries

- 这是静态障碍 SITL 演示，不是动态避障、实机安全认证或复杂自主探索系统。
- `unknown_is_occupied=false` 只适用于此静态可见仿真；真机必须重做未知空间、机体包络、制动距离、传感器盲区和失效策略验证。
- 安全接受依赖预期圆柱几何的独立连续线段检查，同时 health gate 证明路径来源于在线 OctoMap；它不是任意场景的通用碰撞证明。
- 交互模式是一点一飞一降后继续等待的顺序多任务会话，不是一次解锁后连续穿越多个目标；每一轮都重新走 planner、安全检查、OFFBOARD、AUTO.LAND 和 landed/disarmed 合同。
- `NAV_DLL_ACT=0` 只适用于这个没有 GCS 的 PX4 SITL 演示；迁移实机时必须重新设计 GCS/RC data-link-loss action，不得照搬。
- 真机必须在解锁前建立唯一且连续的 yaw 权限：有可用磁航向时只允许它完成初始化，无磁航向时必须等待 LIO yaw 就绪；本项目不允许在飞行中切换磁航向与 LIO yaw。
- 本轮一次 `battery_simulator` work item 停止发布、但仍显示 running，PX4 正确以 `Battery unhealthy` 拒绝再次解锁；这是待单独定位的 SITL 生命周期问题，不能通过关闭真机电池健康门规避。
- 2026-08-06 页面取图验证 run 的任务已 landed/disarmed、停止后无残留进程，但 stop 状态为 `px4_lio_restore=SKIPPED_NOT_PROVEN_LANDED`；停止脚本按 fail-closed 规则没有恢复写参，下一次启动由既有 boot profile 修复。本轮不把参数 restore 记为 PASS。
- 用户失败 run `/home/albert/PX4-LiDAR-SLAM-Sim/runtime/runs/20260804-190430-Li1Gq0` 证明 QGC 的 `255.190` 流量触发 MAVROS 在 `MAV_CMD 520` 后 `double free or corruption`，导致 `/mavros/odometry/out` 只有 relay publisher、没有 MAVROS subscriber；原残留 DLIO/relay 已按记录身份 force-cleanup，证据保留。
- 首次 no-QGC flight run `runs/20260804-191913-jd7EDM` 证明基础栈、DLIO relay 和建图均 PASS，但 x500 默认 `NAV_DLL_ACT=2` 导致 arm 被拒；该失败证据原样保留，后续正式 run 通过官方参数 `0` 完整闭环。
- 2026-08-04 验证期间一次长航程交互任务在 waypoint 4 被既有 watchdog fail-closed 并安全降落；保留 run `20260804-165441-3R7iBU`。后续错误已改为输出 connected/armed/mode/state age/odom age 明细，未放宽阈值。
- 冷启动健康门曾分别拒绝一次 DLIO 单点 `0.196 s` max-gap 和一次 ROS CLI 取证缺失；后续全新 run 在相同参数下完整 PASS。失败证据均保留，未通过降低门槛制造 PASS。
