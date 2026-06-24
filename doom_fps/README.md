# raylib_doom

> DOOM 风格的第一人称射击游戏, 基于 [`raylib_fps_in_v`](../raylib_fps_in_v) 的迷宫脚手架扩展而来.

## 来源

`raylib_fps_in_v` 提供了第一称相机 + 灰度 PNG 自动生成 3D 迷宫 + 圆-矩形墙体碰撞.
本项目在此基础上加入:

- 武器视图模型 + 后坐力动画 + 枪口火光
- 射线射击 (`GetScreenToWorldRay` + `GetRayCollisionBox`) 命中敌人
- 立方体敌人 FSM (idle / chase / attack / dying / dead)
- 玩家 HP + 弹药 + 装弹 + 受击红屏
- 程序生成关卡 (第 2、3 关随机隔墙)
- HUD (HP 条 / 弹药 / 击杀数 / 准星 / 关卡名)
- 关卡过渡 + 死亡 + 胜利 状态机

## 运行环境

- [V](https://vlang.zikesong.cn/) 0.5.x
- Raylib 模块 (通过 `v.mod` 自动声明)

## 构建与运行

```bash
v .
./3d_example           # 或 ./raylib_doom (取决于 v.mod 中的模块名)
```

也可显式指定输出文件名:

```bash
v . -o raylib_doom
./raylib_doom
```

## 操作说明

| 键位 | 作用 |
|---|---|
| `W` `A` `S` `D` | 前后左右移动 |
| `Shift` | 加速 (raylib 内建) |
| 鼠标 | 转向 |
| `Space` | 跳跃 (raylib 内建) |
| `鼠标左键` | 开火 |
| `R` | 装弹 |
| `ESC` | 退出 |

## 关卡设计

| 关卡 | 来源 | 敌人数量 |
|---|---|---|
| E1M1: Hangar | 复用 `cubicmap.png` (来自 `raylib_fps_in_v`) | 5 |
| E1M2: Arena  | 程序生成 24x24, 中心广场 + 散点隔墙 | 8 |
| E1M3: Catacombs | 程序生成 32x32, 大量纵横隔墙 | 10 |

完成一关所有敌人 → 1.6 秒后自动切下一关 → 第 3 关完成后显示 VICTORY.
HP 归零 → 显示 YOU DIED → 按 `R` 重启当前关.

## 源码结构

```
3d_example/
├── main.v        主循环 + 相机 + 开火 + 敌人绘制
├── game.v        Game 状态机与生命周期
├── player.v      Player + 武器 + 装弹
├── enemy.v       Enemy + FSM AI + 移动碰撞
├── level.v       Level 加载 / 程序生成 / 墙体碰撞
├── ui.v          HUD / 状态覆盖 / 武器视图模型
├── assets/
│   ├── level1.png       关卡 1 灰度图
│   └── wall_atlas.png   立方体材质图集
└── v.mod
```

## 与原版 `raylib_fps_in_v` 的关键差异

| 维度 | 原版 | 本项目 |
|---|---|---|
| 用途 | 教学示例 | 可玩游戏 |
| 渲染 | 单迷宫 | 多关卡 |
| 交互 | 只移动 | 移动 + 射击 + 装弹 |
| 实体 | 无 | 立方体敌人 |
| 视觉 | 仅 FPS | FPS + HUD + 武器模型 |
| 关卡来源 | 静态 PNG | 静态 + 程序生成 |

## 已知 TODO

- 武器音效 (raylib 音频已可用, 缺 .wav 资源)
- 命中粒子 (命中时在 3D 世界中弹出血雾)
- 多种武器 (散弹枪 / 火箭筒 / 能量枪)
- Boss 战
- 实体地图物件 (弹药包 / 医疗包)

## License

MIT.