// =============================================================================
//  render.v - 编辑器渲染
// =============================================================================
//
//  布局 (从上到下):
//    y=0        status bar (24px)         - 文件名 + dirty + 主题
//    y=24..H-hint 文本区域 (剩余高度)
//       x=0     gutter (4 字符宽, 行号)
//       x=gw    文本
//    y=H-22    bottom hint (22px)        - 快捷键提示
//    y=H       [若 in_command] command line (24px)
//
//  主题色板从 context.cfg.current_theme().colors 取.
// =============================================================================

module main

import raylib as r

// 取当前主题颜色
fn theme_bg(c &Context) r.Color { return c.cfg.current_theme().colors.background }
fn theme_fg(c &Context) r.Color { return c.cfg.current_theme().colors.foreground }
fn theme_cursor(c &Context) r.Color { return c.cfg.current_theme().colors.cursor }
fn theme_cursor_line(c &Context) r.Color { return c.cfg.current_theme().colors.cursor_line_bg }
fn theme_selection_bg(c &Context) r.Color { return c.cfg.current_theme().colors.selection_bg }
fn theme_selection_fg(c &Context) r.Color { return c.cfg.current_theme().colors.selection_fg }
fn theme_gutter_fg(c &Context) r.Color { return c.cfg.current_theme().colors.line_number_fg }
fn theme_status_bg(c &Context) r.Color { return c.cfg.current_theme().colors.status_bar_bg }
fn theme_status_fg(c &Context) r.Color { return c.cfg.current_theme().colors.status_bar_fg }

// 字符宽度 (等宽字体, 'M' 的宽度)
fn char_width(c &Context) f32 {
	return r.measure_text_ex(c.font, 'M', f32(c.cfg.font_size), 0).x
}

// 行高 (用 fontSize 近似)
fn line_height(c &Context) f32 {
	return f32(c.cfg.font_size)
}

// 主渲染入口
pub fn render(c &Context) {
	r.clear_background(theme_bg(c))
	draw_text_area(c)
	draw_status_bar(c)
	draw_bottom_hint(c)
	if c.in_command {
		draw_command_line(c)
	}
}

// ===== 状态栏 (顶部 24px) =====
fn draw_status_bar(c &Context) {
	r.draw_rectangle(0, 0, r.get_screen_width(), status_bar_h, theme_status_bg(c))
	mut info := ''
	if c.buffer.file != '' {
		info = c.buffer.file
	} else {
		info = '<untitled>'
	}
	if c.buffer.dirty {
		info += ' *'
	}
	info += '   |   '
	info += 'theme: ${c.cfg.current_theme().name}'
	r.draw_text(info, 8, 4, 14, theme_status_fg(c))

	// 右侧: 列/行 (用 raylib default font, 这里用 context.font)
	line, col := byte_to_line_col(c.buffer.content, c.view.cursor.point)
	loc := 'line ${line + 1}  col ${col}'
	tw := r.measure_text(loc, 14)
	r.draw_text(loc, r.get_screen_width() - tw - 8, 4, 14, theme_status_fg(c))
}

// ===== 底部 hint =====
fn draw_bottom_hint(c &Context) {
	sh := r.get_screen_height()
	r.draw_rectangle(0, sh - bottom_hint_h, r.get_screen_width(), bottom_hint_h, theme_status_bg(c))
	hint := 'Ctrl+S save   Ctrl+O open   Ctrl+T theme   Ctrl+Q quit   : command'
	r.draw_text(hint, 8, sh - bottom_hint_h + 4, 12, theme_status_fg(c))
}

// ===== 文本区域 =====
fn draw_text_area(c &Context) {
	font_size := f32(c.cfg.font_size)
	sh := r.get_screen_height()
	lh := line_height(c)
	cw := char_width(c)
	gw := gutter_min_w
	text_y0 := f32(status_bar_h)
	mut text_h := f32(sh) - f32(status_bar_h + bottom_hint_h)
	if c.in_command {
		text_h -= f32(command_line_h)
	}
	max_visible := int(text_h / lh)

	// 光标所在行的背景高亮
	line, _ := byte_to_line_col(c.buffer.content, c.view.cursor.point)
	if line >= c.view.visible_start && line < c.view.visible_start + max_visible {
		cy := text_y0 + f32(line - c.view.visible_start) * lh
		r.draw_rectangle(int(gw), int(cy), int(f32(r.get_screen_width()) - gw), int(lh),
			theme_cursor_line(c))
	}

	// 行号 + 文本行
	for i in 0 .. max_visible {
		actual_line := c.view.visible_start + i
		y := text_y0 + f32(i) * lh

		// 行号
		if c.view.show_line_numbers {
			line_num := '${actual_line + 1}'
			nw := r.measure_text(line_num, int(font_size))
			r.draw_text(line_num, int(gw) - nw - gutter_pad, int(y), int(font_size), theme_gutter_fg(c))
		}

		// 文本
		line_bytes := get_line_bytes(c.buffer.content, actual_line)
		if line_bytes.len > 0 {
			text := line_bytes.bytestr()
			pos := r.Vector2{gw + gutter_pad, y}
			r.draw_text_ex(c.font, text, pos, font_size, 0, theme_fg(c))
		}
	}

	// 光标
	mut col := 0
	_, col = byte_to_line_col(c.buffer.content, c.view.cursor.point)
	cx := gw + gutter_pad + f32(col) * cw
	cy := text_y0 + f32(line - c.view.visible_start) * lh
	r.draw_rectangle(int(cx), int(cy), int(cw) + 1, int(lh) + 1, theme_cursor(c))

	// 临时状态消息覆盖在屏幕中央
	if c.status_active() {
		msg := c.status_message
		tw := r.measure_text(msg, 18)
		th := 24
		bx := (r.get_screen_width() - tw) / 2 - 8
		by := (r.get_screen_height() - th) / 2 - 8
		r.draw_rectangle(bx, by, tw + 16, th, theme_status_bg(c))
		r.draw_text(msg, bx + 8, by + 4, 18, theme_status_fg(c))
	}
}

// ===== 命令行 (底部) =====
fn draw_command_line(c &Context) {
	sh := r.get_screen_height()
	y := sh - bottom_hint_h - command_line_h
	r.draw_rectangle(0, y, r.get_screen_width(), command_line_h, theme_status_bg(c))
	prompt := ': ${c.command_buf}'
	r.draw_text(prompt, 8, y + 4, 16, theme_status_fg(c))
	// 光标 (用小竖线)
	cx := 8 + r.measure_text(prompt, 16)
	r.draw_rectangle(cx, y + 4, 2, 16, theme_cursor(c))
}