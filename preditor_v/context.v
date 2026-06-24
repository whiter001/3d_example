// =============================================================================
//  context.v - 全局编辑器状态
// =============================================================================
//
//  Context 是整个编辑器的根数据, 集中持有:
//    - cfg (配置 + 主题)
//    - buffer (当前编辑的文件)
//    - view (BufferView, 渲染层)
//    - 三个 Keymap (global / buffer / command)
//    - 状态栏消息 (临时显示, 有到期时间)
//    - 命令模式输入缓冲
//    - 退出标志
//
//  全局实例 __global (mut context Context), 所有 module main 文件共享.
// =============================================================================

module main

import raylib as r

pub const font_path = 'assets/fonts/liberationmono-regular.ttf'

pub const status_bar_h    = 24
pub const bottom_hint_h   = 22
pub const command_line_h  = 24
pub const gutter_pad      = 6
pub const gutter_min_w    = 36

pub struct Context {
pub mut:
	cfg             Config
	buffer          Buffer
	view            BufferView
	font            r.Font
	font_loaded     bool
	global_keymap   Keymap
	buffer_keymap   Keymap
	command_keymap  Keymap
	status_message  string
	status_until    i64
	in_command      bool
	command_buf     string
	should_quit     bool
}

// 全局编辑器实例
__global (
	context Context
)

// ===== 初始化 =====
pub fn context_init() {
	context.cfg = config_default()
	context.buffer = new_buffer('', []u8{})
	context.view = new_buffer_view(context.buffer, context.cfg.tab_size, context.cfg.show_line_numbers)
	context.global_keymap = new_keymap()
	context.buffer_keymap = new_keymap()
	context.command_keymap = new_keymap()
	register_default_keymaps(mut context.global_keymap, mut context.buffer_keymap, mut context.command_keymap)
	context.font_loaded = false
	context.status_message = 'preditor_v ready. ctrl+s save, ctrl+o open, ctrl+t theme, ctrl+q quit'
	context.status_until = get_time_ms() + 3000
}

// 加载字体 (在 raylib init 之后调用)
pub fn context_load_font() {
	if !context.font_loaded {
		mut codepoints := []int{}
		for cp in 32 .. 127 {
			codepoints << cp
		}
		context.font = r.load_font_ex(font_path, context.cfg.font_size, codepoints.data, codepoints.len)
		context.font_loaded = true
	}
}

// 卸载资源
pub fn context_shutdown() {
	if context.font_loaded {
		r.unload_font(context.font)
		context.font_loaded = false
	}
}

// ===== 视图同步 =====
//
// 每次主循环检查: 光标是否滚出可见范围, 如果是则调整 visible_start

pub fn (mut c Context) sync_viewport() {
	screen_h := r.get_screen_height()
	mut text_h := f32(screen_h) - f32(status_bar_h + bottom_hint_h)
	if c.in_command {
		text_h -= f32(command_line_h)
	}
	font_size := f32(c.cfg.font_size)
	max_visible := int(text_h / font_size)
	if max_visible < 1 {
		return
	}
	line, _ := byte_to_line_col(c.buffer.content, c.view.cursor.point)
	if line < c.view.visible_start {
		c.view.visible_start = line
	}
	if line >= c.view.visible_start + max_visible {
		c.view.visible_start = line - max_visible + 1
	}
}

// 状态栏消息是否还有效
pub fn (c &Context) status_active() bool {
	return c.status_message != '' && get_time_ms() < c.status_until
}