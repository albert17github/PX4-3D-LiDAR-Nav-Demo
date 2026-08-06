# 参与贡献

项目主线为：

```text
PX4 SITL + Gazebo → DLIO → OctoMap → MRS 3D A* → MAVROS OFFBOARD
```

本仓库主要维护启动编排、组件连接、任务执行、安全检查、仿真场景和复现文档。
SLAM、OctoMap、规划器或 PX4 本身的问题，优先在对应上游项目中讨论。

## 提交 issue

提交前请先搜索已有 issue，并准备以下信息：

- Ubuntu 版本、CPU、内存、显卡或虚拟机配置；
- 当前 commit：`git rev-parse HEAD`；
- `./scripts/check_environment.sh --setup` 或 `--run` 的完整输出；
- 失败命令、首次出现的错误和对应 `runtime/logs/` 文件；
- 能稳定复现问题的最短步骤；
- 如果问题涉及图形界面，附 Gazebo 或 RViz 应用内导出的图片。

请删除日志中的用户名、访问令牌、私有地址和其他敏感信息。不要在 issue 中粘贴
密码、token、cookie 或私钥。

## 提交 pull request

1. 从最新 `main` 创建范围明确的分支。
2. 一次 pull request 解决一个问题，避免同时更换 SLAM、规划器和飞控框架。
3. 保持 `./demo.sh`、`./scripts/start.sh`、`./scripts/fly_ab.sh` 和
   `./scripts/stop.sh` 这些主入口稳定。
4. 不提交 `runtime/` 生成内容、`runs/`、视频、ULog 或本机绝对路径。
5. 说明修改原因、验证命令、实际结果和仍未覆盖的边界。

提交前至少运行：

```bash
bash -n demo.sh setup.sh scripts/*.sh runtime/scripts/*.sh runtime/env/install-packages.sh
shellcheck -x demo.sh setup.sh scripts/*.sh runtime/scripts/*.sh runtime/env/install-packages.sh
python3 -m py_compile src/ab_mission.py scripts/check_simulation_contract.py
./setup.sh --verify-only
```

修改 Python 任务执行器时还应运行其 `--self-test`。涉及飞行行为、PX4 参数、坐标系
或安全阈值的变更，需要提供新的 Gazebo、RViz 和任务结果证据。

## 许可证

提交到本仓库的原创代码和文档将按 [Apache License 2.0](LICENSE) 发布。
来自上游项目的代码或补丁必须保留原始许可证与来源说明，具体边界见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
