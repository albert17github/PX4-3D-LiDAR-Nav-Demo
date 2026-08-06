# 报告图片来源

以下图片来自相同配置下完成闭环的在线建图、规划、飞行和落地验证。它们由
Gazebo 或 RViz 自身的保存功能生成，不是桌面全屏截图：

| 文件 | 应用导出方式 | 原始尺寸 | 内容 |
|---|---|---:|---|
| `gazebo-world-ready.png` | Gazebo GUI `Screenshot` plugin / `/gui/screenshot` | 1700×1173 | 障碍世界 ready |
| `rviz-map-ready.png` | RViz `File → Save Image`，未勾选整窗 | 900×708 | 实时 3D LiDAR 与 OctoMap |
| `rviz-flight-path.png` | RViz `File → Save Image`，未勾选整窗 | 900×708 | 调整视角后补拍的 8 点完整路径与任务标记 |
| `gazebo-landed-b.png` | Gazebo GUI `Screenshot` plugin / `/gui/screenshot` | 1700×1173 | B 点落地后的 x500 与 3D LiDAR |

`rviz-flight-path.png` 于 2026-08-06 在另一轮固定 A→B 任务 PASS 后补拍：路径长
`12.753 m`、横向绕行 `3.111 m`、目标误差 `0.040 m`，最终事件为
`landed_disarmed`。只调整了 RViz 观察角度，没有修改地图、路径或算法。

所有图片在加入页面前均已逐张以原始分辨率检查。页面上的文字标注使用 HTML/CSS
叠加，未覆盖或改写原始 PNG 像素。

## SHA-256

```text
a21db190c1f947322b88c3289ce1e3343b8037ebf1024b9e2109db2da50091ec  gazebo-landed-b.png
ef356271cc86c466ca9bbfff25ec2f4751031f5b76368c8b730e86e6a7e1872c  gazebo-world-ready.png
c9a106450328d1f8519f5f1c1a737e09127e470a953ef0fa85cd2ba1d62defcf  rviz-flight-path.png
b9d47e1b355115ed409ca83304021fe1b4dbcfd87e19002bf13f09403ba2283c  rviz-map-ready.png
```

可以在本目录运行 `sha256sum -c SHA256SUMS` 复核原图。
