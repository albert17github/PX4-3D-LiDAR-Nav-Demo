# 报告图片来源

以下图片来自相同配置下完成闭环的在线建图、规划、飞行和落地验证。它们由
Gazebo 或 RViz 自身的保存功能生成，不是桌面全屏截图：

| 文件 | 应用导出方式 | 原始尺寸 | 内容 |
|---|---|---:|---|
| `gazebo-world-ready.png` | Gazebo GUI `Screenshot` plugin / `/gui/screenshot` | 1700×1173 | 障碍世界 ready |
| `rviz-map-ready.png` | RViz `File → Save Image`，未勾选整窗 | 900×708 | 实时 3D LiDAR 与 OctoMap |
| `rviz-flight-path.png` | RViz `File → Save Image`，未勾选整窗 | 900×708 | 固定 A→B 的 8 点路径、任务标记与 PX4 位姿 |
| `gazebo-landed-b.png` | Gazebo GUI `Screenshot` plugin / `/gui/screenshot` | 1700×1173 | B 点落地后的 x500 与 3D LiDAR |

`rviz-flight-path.png` 记录固定 A→B 参考任务：路径长 `12.753 m`、横向绕行
`3.111 m`、目标误差 `0.040 m`；任务最终进入 `AUTO.LAND` 并解除解锁。
图片由 RViz render panel 直接导出。

所有图片在加入页面前均已逐张以原始分辨率检查。报告页使用固定 16:10 容器和
`object-fit: cover` 裁切显示；文字标注由 HTML/CSS 叠加，原始 PNG 像素保持不变。

## README 16:10 展示裁剪

GitHub 主页的“运行画面”引用以下 960×600 展示图。它们只从对应原图中裁切，
再按相同比例统一缩放；没有拉伸、重绘或覆盖原始证据图。

| 展示图 | 来源 | 原图裁剪框 `[left, top, right, bottom]` |
|---|---|---|
| `gazebo-world-ready-16x10.png` | `gazebo-world-ready.png` | `[2, 56, 1698, 1116]` |
| `rviz-map-ready-16x10.png` | `rviz-map-ready.png` | `[2, 70, 898, 630]` |
| `rviz-flight-path-16x10.png` | `rviz-flight-path.png` | `[2, 70, 898, 630]` |
| `gazebo-landed-b-16x10.png` | `gazebo-landed-b.png` | `[430, 220, 1390, 820]` |

## SHA-256

```text
3d82c1562cca967c535f5e039523c14d6189b44006228ab1c24d54403bd71166  gazebo-landed-b-16x10.png
a21db190c1f947322b88c3289ce1e3343b8037ebf1024b9e2109db2da50091ec  gazebo-landed-b.png
e3c9e67e18ab845915f99fc7047e36f485d162e235a17d5039dc4ccd1ae48ace  gazebo-world-ready-16x10.png
ef356271cc86c466ca9bbfff25ec2f4751031f5b76368c8b730e86e6a7e1872c  gazebo-world-ready.png
c2d4de8ec2743a540ab82645ecaab8654ce4b15cfe07140b89ba5f45603a089e  rviz-flight-path-16x10.png
c9a106450328d1f8519f5f1c1a737e09127e470a953ef0fa85cd2ba1d62defcf  rviz-flight-path.png
81c469fa0579666bafaf8bcc2e7869340a28446d4dd4ffc640fcc8c6d837b944  rviz-map-ready-16x10.png
b9d47e1b355115ed409ca83304021fe1b4dbcfd87e19002bf13f09403ba2283c  rviz-map-ready.png
```

可以在本目录运行 `sha256sum -c SHA256SUMS` 复核原图和展示裁剪图。
