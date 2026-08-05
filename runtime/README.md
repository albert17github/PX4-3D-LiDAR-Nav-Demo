# Project-owned runtime

这个目录同时包含“可提交配方”和“本机生成物”。

提交到 Git 的内容：

- `config/`：上游版本锁和运行参数；
- `env/`：rootfs 内的软件安装配方；
- `models/`、`worlds/`：本演示场景；
- `patches/`：DLIO 与 MAVROS 的已审核修复；
- `scripts/`：安装、启动、停止与最小 readiness gate。

由 `./setup.sh` 生成且被 `.gitignore` 排除的内容：

- `env/rootfs`、`env/cache`、`env/proot`；
- `vendor/PX4-Autopilot`、`third_party/`、`mavros-src/`；
- `ros2_ws/`、`mavros-build/`、`mavros-overlay/`；
- `.setup/`、`logs/`、`runs/`。

因此 GitHub 保持轻量，但 checkout 完成安装后仍是完全项目内、自包含的
运行时。不要把上述生成目录手工提交到 Git。`./setup.sh --verify-only` 会核对
上游 commit、补丁、二进制动态库闭包、包 manifest，以及顶层任务配置与本目录
Gazebo world 的坐标合同。

`./setup.sh --seed-from PATH` 只是一条显式的本机迁移加速路径；复制后仍必须
通过同一验证，且不得留下指向 PATH 的 symlink 或 Git alternates。普通 GitHub
用户应直接运行 `./setup.sh --install-host-deps`，不需要任何旧项目。
