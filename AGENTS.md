# PX4 3D LiDAR Navigation Demo

## Scope

- 每个新执行模型必须先完整阅读 `IMPLEMENTATION_PLAN.md`，一次只执行用户指定的一个 Gate；完成并汇报后不得自动跳到下一 Gate。
- 只交付一条可实时观察、可重复运行的主线：PX4 SITL + Gazebo → 3D LiDAR → DLIO → OctoMap → 开源三维 A* 规划 → MAVROS OFFBOARD 航点执行。
- Gazebo 和 RViz 必须显示在 Ubuntu 桌面；后台 topic 回放不能作为最终演示。
- 不在本项目重写 SLAM、OctoMap、路径规划或飞控算法。
- 自写代码只允许承担启动编排、A/B 参数、规划服务调用、平滑航点执行、截图/视频保存。
- 静态障碍绕行是本阶段目标；动态障碍与认证级安全证明不属于当前范围。

## Simplicity rules

- 主入口保持为 `./demo.sh`，分步入口保持为 `./scripts/start.sh`、`./scripts/fly_ab.sh`、`./scripts/stop.sh`。
- 不引入新的审计框架、seal schema、策略哈希矩阵或多层 mission coordinator。
- 重型 PX4/ROS 运行时暂时复用只读基线 `/home/albert/PX4-LiDAR-SLAM-Sim`，不要复制其历史 run、报告或审计脚本。
- 新增依赖前先说明用途；优先使用基线中已安装并验证的开源包。
- 不删除或修改基线项目的历史证据。

## Verification

- Python 修改后运行 `python3 -m py_compile` 和脚本自带 `--self-test`。
- Shell 修改后运行 `bash -n` 和 `shellcheck -x`。
- 最终 PASS 必须同时有：可见 Gazebo、可见 RViz、在线 OctoMap、非直线路径、PX4 实际到达 B、自动降落、截图和视频。
- 阶段性完成后更新 `PROJECT_MEMORY.md` 和 `reports/index.html`。
