# preditor_v

> [amirrezaask/Preditor](https://github.com/amirrezaask/Preditor) 的 V + raylib 实现.
> 原始版本是 Go + raylib 的 Emacs 风格可编程文本编辑器. 本项目实现 **核心子集**:
> Buffer + BufferView + Cursor + 文件 I/O + 主题切换 + 基本键位.

## 特性

- **Buffer**: 字节切片文本缓冲区, 支持插入 / 删除 / 行操作
- **Cursor**: Emacs-style (Point / Mark)
- **BufferView**: 视口渲染 + 行号 gutter + 自动滚动跟随光标
- **Theme**: 内置 3 个主题 (Default_Dark / 4Coder_Fleury / VisualStudio_Light), 运行时切换
- **Keymap**: 三层栈式覆盖 (global / buffer / command)
- **命令模式**: `:w` / `:q` / `:o <file>` / `:t`
- **TTF 字体**: 等宽 Liberation Mono / JetBrains Mono (从 Preditor 原版抽取)

## 不实现

- ❌ 多窗口 / 分屏
- ❌ ripgrep 搜索
- ❌ tree-sitter 语法高亮
- ❌ 编译命令
- ❌ prompt 补全 / fuzzy search

> 上述项保留可扩展接口 (Buffer / Keymap / Theme), 后续可增量补全.

## 运行环境

- [V](https://vlang.zikesong.cn/) 0.5.x
- [Nushell](https://www.nushell.sh/) 0.113+ (推荐用 `nu build.nu`)
- Raylib 系统库 (`brew install raylib` 或 `apt install libraylib-dev`)

## 构建与运行

### 用 build.nu

```bash
nu build.nu stats          # 代码统计
nu build.nu prod           # prod 构建 -> preditor_v (~??)
nu build.nu debug          # debug 构建 -> preditor_v_debug
nu build.nu run            # 构建并启动
nu build.nu clean          # 清理产物
```

### 直接用 v

```bash
v -enable-globals . -o preditor_v
./preditor_v
```

## 操作说明

| 键 | 动作 |
|---|---|
| 任意字符键 | 插入字符 |
| `Backspace` | 删除前一个字符 |
| `Delete` | 删除后一个字符 |
| `←` `→` `↑` `↓` | 移动光标 |
| `Home` / `End` | 行首 / 行尾 |
| `Ctrl+S` | 保存当前 buffer |
| `Ctrl+O` | 提示输入文件名打开 |
| `Ctrl+T` | 循环切换主题 |
| `Ctrl+Q` | 退出 (有未保存修改时按两次) |
| `:` | 进入命令模式 |

### 命令模式

| 命令 | 作用 |
|---|---|
| `:w` | 保存 (用 buffer.file) |
| `:w <filename>` | 另存为 |
| `:q` | 退出 (无未保存修改时) |
| `:o <filename>` | 打开文件 |
| `:t` | 循环切换主题 |

`Esc` 退出命令模式.

## 源码结构

```
preditor_v/
├── main.v        入口 + 主循环
├── context.v     Context 全局状态
├── buffer.v      Buffer / BufferView / Cursor + 移动 + I/O
├── config.v      Config + Theme + Colors (3 个默认主题)
├── keymap.v      Action 枚举 + Keymap + dispatch
├── input.v       raylib 按键 -> Key 字符串
├── render.v      status bar / 文本 / 光标 / 主题色
├── build.nu      Nushell 构建脚本
└── assets/fonts/
    ├── liberationmono-regular.ttf   (从 Preditor 抽取)
    └── jetbrainsmono.ttf
```

## 关键算法

### 行/列 ↔ 字节偏移

```v
fn byte_to_line_col(content []byte, pos int) (int, int) {
    // 扫描到 pos, 累计 \n 数得到 line, 同行的字节数得到 col
}
```

### 视口跟随

每帧 `sync_viewport()` 检查光标所在行是否在 `[visible_start, visible_start + max_visible)` 范围内, 否则调整 visible_start.

### 等宽字体字符宽度

用 `r.measure_text_ex(font, 'M', size, 0).x` 测一次缓存到 `Context`.

## 已知限制

- **V 0.5.x raylib 绑定**: 不支持 `v -prod`, build.nu 用 V 默认 Release-fast
- **`-enable-globals` 必须**: V 0.5.x 不允许 module 顶层 `pub mut`, 必须 `__global` 块
- **树语法高亮**: 跳过, 但 `Theme.colors` 已预留扩展字段
- **窗口大小写**: 启动时固定 1024x720, 不支持运行时缩放
- **撤销**: 未实现 `ActionStack` (Preditor 的 undo 机制)

## License

MIT.