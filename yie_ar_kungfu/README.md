# yie_ar_kungfu

> 1985 Konami 街机格斗游戏 *Yie Ar Kung-Fu* 的 V + raylib 实现.
> 原始参考: [six519/YieArKUNGFUZig](https://github.com/six519/YieArKUNGFUZig) (Zig + raylib).

## 玩法

单屏格斗游戏. 玩家扮演 **FERDIE**, 一路过关斩将击败 5 个对手:

| 关卡 | 对手 | 备注 |
|---|---|---|
| 1 | Wang  | 入门级 |
| 2 | Tao   | |
| 3 | Chen  | 持旋转链球 (spinning chain) |
| 4 | Lang  | |
| 5 | Mu    | Boss |

每关开始时双方 9 点血. 玩家先清空对手血量进入下一关; 若血量归零, 失去一条命 (共 3 条),
回到 view 屏; 全部用完则 GAME OVER.

击败对手后会播放一段连招演出, 然后进入下一关. 通关第 5 关显示 `YOU WIN`,
玩家阵亡后显示 `YOU LOSE`, 按 Enter 重新开始.

## 运行环境

- [V](https://vlang.zikesong.cn/) 0.5.x
- [Nushell](https://www.nushell.sh/) (推荐 0.113+, 用 `nu build.nu ...`)
- Raylib 模块 (通过 `v.mod` 自动声明)
- macOS / Linux, raylib 系统库 (`brew install raylib` 或 `apt install libraylib-dev`)

## 构建与运行

### 用 build.nu (推荐)

```bash
nu build.nu stats          # 查看代码行数 / 资源数量
nu build.nu debug          # debug 构建 -> yie_ar_kungfu_debug
nu build.nu prod           # prod 构建  -> yie_ar_kungfu (默认)
nu build.nu build debug    # 等价于 nu build.nu debug
nu build.nu run            # 构建并启动 (默认 prod)
nu build.nu run debug      # 构建 debug 版并启动
nu build.nu clean          # 删除所有编译产物
```

| 模式 | 命令参数 | 产物 | 大小 (典型) |
|---|---|---|---|
| prod  | `v -enable-globals . -o yie_ar_kungfu`           | `yie_ar_kungfu`        | ~426 KB |
| debug | `v -enable-globals -g . -o yie_ar_kungfu_debug`  | `yie_ar_kungfu_debug`  | ~578 KB (含调试符号) |

### 直接用 v

如果不想用 build.nu:

```bash
v -enable-globals . -o yie_ar_kungfu
./yie_ar_kungfu
```

> **⚠️ 为什么不用 `v -prod`?**
> V 0.5.x 的 raylib 绑定与本地 raylib 5.x 头文件存在 `ctx_data` vs `ctxData` 字段名
> 不匹配, 启用 `-prod` 会触发 C 编译错误. 本脚本的 prod 模式用 V 默认的 Release-fast
> 优化级别 (性能与 `-prod` 接近).

## 操作说明

| 键位 | 作用 |
|---|---|
| `←` `→` | 前后移动 |
| `↑` | 跳跃 |
| `↓` | 蹲 |
| `A` 或 `J` | 出拳 (stand_punch / sit_punch) |
| `S` 或 `K` | 踢腿 (带左右方向键时为高位踢) |
| `Space` / `Enter` | 开始 / 重玩 |
| `ESC` | 退出 |

### 飞行踢

跳跃中按 `S` (或 `K`) 触发. 飞行踢击中对手得 300 分 (普通出拳 100, 高位踢 200).

### 调试键

游戏内无调试键. 需要调整常量请改 `game.v` (血量 / 边界) 或 `player.v` (跳跃 / 速度).

## 渲染

游戏以 256×240 渲染到 RenderTexture, 然后按 16:15 等比拉伸到 1024×768 屏幕中心,
保持 NES 风格像素艺术. 纹理过滤为 raylib 默认 (Texture2D 默认 NEAREST, 缩放后呈块状像素).

## 源码结构

```
yie_ar_kungfu/
├── main.v            54 行  入口 + 主循环
├── game.v           446 行  全局常量 / Game 结构体 / 资源加载
├── sprite.v         194 行  帧动画 + 翻转 + 资源 ID 表
├── player.v         583 行  FSM + 攻击判定 + 跳跃物理 + 飞行踢
├── enemy.v          455 行  5 个对手 AI + 胜负状态机
├── stage.v          197 行  title / view / game 三阶段渲染钩子
├── ui.v              92 行  HUD 文字与血条
├── build.nu                Nushell 构建脚本 (debug/prod/run/clean/stats)
├── v.mod                   Module 声明 (依赖 raylib)
└── assets/
    ├── images/   45 张 PNG (从 six519/YieArKUNGFUZig 抽取)
    └── sounds/   9 个 WAV
```

总计 **~2020 行 V 代码**, 7 个 .v 文件.

## 关键算法

### 命中判定

玩家攻击框相对位置查 `CollisionInfo` 静态表 (`ci_stand_punch` / `ci_sit_punch` /
`ci_stand_kick` / `ci_sit_kick` / `ci_high_kick` / `ci_air`), 对手受击框按当前关卡
查 `villain_collisions[stage-1].body`. 标准 AABB 重叠判定.

### 跳跃物理

加速度递减抛物线 (原版 zigzag 观感), `acceleration_speed` 控制上升/下降速度,
峰高 115 像素. 跳跃中可按左右方向键横向摆动.

### AI

每 `VILLAIN_FRAME_SPEED` tick (约 5 fps) 决策一次:
- `follow_player`: 向玩家方向走 1 像素/帧
- `running_left/right`: 受击后退 5 像素/帧, 跑 10 帧回 follow
- `forward_with_attack`: 攻击动画期间
- 距离玩家 < 判定范围时随机选 `kick` (踢) 或 `other` (拳) 进入攻击

### 5 关流程

```
title (按 Enter 进入 view)
  ↓
view (显示 STAGE N 1 秒, 切到 game)
  ↓
game (与当前对手对战)
  ├ villain_health = 0 → END_STATE 演出 → 下一关 view 或 GAME OVER
  └ player_health  = 0 → VILLAIN_END_STATE 演出 → 复活 (lives-1) 或 GAME OVER
```

## 已知限制

- **V 0.5.x + raylib 5.x**: `-prod` 标志触发 C 编译错误 (字段名不匹配), 已通过
  使用 V 默认 Release-fast 优化绕开
- **`-enable-globals` 必须**: V 0.5.x 不允许 module 顶层用 `pub mut`, 必须用
  `__global` 块 + `-enable-globals` 标志
- **HUD 文字**: 用 raylib `DrawText` (非像素字体), 与原版字母图集拼字符串观感略不同
- **无 gamepad 支持**: 仅键盘, 原版的 gamepad 映射未移植
- **音频**: 原版 9 个 WAV 全部加载 (bg.mp3 / attack / collided / collided2 /
  counting / dead / feet_sound / game_over / low_health / win)

## License

MIT.