# Minimal architecture

## Data path

1. Gazebo 以实时因子 1.0 运行 PX4 x500 和 360×16 三维 LiDAR。
2. `ros_gz_bridge` 发布 `/lidar_3d/points`，MAVROS 发布 PX4 IMU。
3. DLIO 使用点云和 IMU 发布 `/dlio/odom`。
4. 上游 MAVROS odometry plugin 以 `LOCAL_FRD/BODY_FRD` 将 DLIO 位置、body velocity 和 yaw 送入 PX4 EKF2；飞行合同为 `EKF2_EV_CTRL=13`。
5. 标准 `octomap_server_node` 使用点云与 PX4 位姿生成 `/octomap_binary`。
6. 上游 `MinimalOctomapPlanner` 从 OctoMap 请求 A→B 三维 A* 路径。
7. 一个薄的 Python 执行器以限速插值后的 `PoseStamped` 向 MAVROS 发送路径。
8. Gazebo 显示真实运动；RViz 显示点云、地图、路径和位姿。

## Heading authority

- 启动时 `EKF2_MAG_TYPE=6`，磁航向只用于初始化；DLIO feed 稳定后由 external odometry 持续约束 horizontal position、velocity 和 yaw，飞行中不切换航向源。
- `odom` 是连续局部定位层；`map→odom` 的初始 yaw 在有磁航向时可由磁航向给出，无磁航向时由 LIO/人工初始对齐给出。二者都不得在飞行中重新定义 `odom`。
- `LOCAL_FRD` 是任意本地外部里程计的正确 MAVLink 语义；PX4 在该模式下允许 `cs_yaw_align=False`，因此健康判断使用 EV fusion、innovation、reset counter 和实际控制结果，而不伪造 north-aligned `LOCAL_NED`。
- 任务执行器保持当前 yaw 垂直起飞，到达安全高度后再原地转向，并在整条规划路径上保持同一 yaw。

## Deliberate limits

- 环境为静态障碍，不做动态目标跟踪。
- 规划器允许未知空间通行，适合可控仿真演示，不代表实机安全策略。
- 不复用旧工程的正式审计器、封存器或 97 项 Gate 作为本项目主流程。
