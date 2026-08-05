# Third-party components

本项目只编排上游组件，不重新实现它们。各组件仍受各自许可证约束：

- PX4-Autopilot: <https://github.com/PX4/PX4-Autopilot>
- Gazebo: <https://gazebosim.org/>
- ROS 2 Jazzy: <https://docs.ros.org/en/jazzy/>
- DLIO: <https://github.com/vectr-ucla/direct_lidar_inertial_odometry>
- MAVROS: <https://github.com/mavlink/mavros>
- OctoMap: <https://octomap.github.io/>
- CTU MRS: <https://github.com/ctu-mrs>
- PRoot: <https://gitlab.com/proot/proot>
- Ubuntu cloud images: <https://cloud-images.ubuntu.com/>

`runtime/patches/` 是针对锁定上游版本保存的补丁；安装后完整上游源码及
许可证位于被忽略的 `runtime/vendor`、`runtime/third_party` 和
`runtime/mavros-src` 中。

MAVROS router address 锁补丁只回移上游 ros2 分支随后发布的并发修复
`bf464a2b`、`65cec447`、`07944251`、`d07483ee`；vehicles map 补丁同样保留
上游文件的原许可证。补丁 SHA-256 位于 `runtime/config/versions.env`。

除上述第三方内容及源自上游代码的补丁外，本项目自写的启动编排、任务连接层、
配置和文档由仓库所有者按 [`Apache License 2.0`](LICENSE) 授权。顶层
`LICENSE` 不替换或削弱任何第三方组件原有的许可证、版权声明或署名要求。
