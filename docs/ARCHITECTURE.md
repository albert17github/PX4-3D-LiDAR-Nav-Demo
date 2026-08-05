# Minimal architecture

## Data path

1. Gazebo 以实时因子 1.0 运行 PX4 x500 和 360×16 三维 LiDAR。
2. `ros_gz_bridge` 发布 `/lidar_3d/points`，MAVROS 发布 PX4 IMU。
3. DLIO 使用点云和 IMU 发布 `/dlio/odom`。
4. 上游 MAVROS odometry plugin 将 DLIO 里程计送入 PX4 EKF2。
5. 标准 `octomap_server_node` 使用点云与 PX4 位姿生成 `/octomap_binary`。
6. 上游 `MinimalOctomapPlanner` 从 OctoMap 请求 A→B 三维 A* 路径。
7. 一个薄的 Python 执行器以限速插值后的 `PoseStamped` 向 MAVROS 发送路径。
8. Gazebo 显示真实运动；RViz 显示点云、地图、路径和位姿。

## Deliberate limits

- 环境为静态障碍，不做动态目标跟踪。
- 规划器允许未知空间通行，适合可控仿真演示，不代表实机安全策略。
- 不复用旧工程的正式审计器、封存器或 97 项 Gate 作为本项目主流程。

