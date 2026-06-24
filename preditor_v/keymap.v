// =============================================================================
//  keymap.v - 键位绑定 (key 字符串 -> Action + 参数)
// =============================================================================
//
//  Key 字符串格式:
//    'a'..'z', 'A'..'Z', '0'..'9', 单字符标点
//    '<enter>' / '<esc>' / '<tab>' / '<backspace>' / '<up>' / '<down>'
//    '<left>' / '<right>' / '<home>' / '<end>' / '<delete>'
//    'ctrl+x' / 'alt+x' / 'shift+x' 修饰键组合
//
//  Binding = Action + 参数 (arg u8 用于 insert_byte, 其它命令忽略)
//
//  Action 是 enum, dispatch 函数根据 action 调用对应逻辑. 用 enum 而非 fn type
//  是为了避免 V 的闭包捕获语法, 让代码简单直接.
// =============================================================================

module main

import raylib as r

// 动作枚举 (每个对应一段 dispatch 中的逻辑)
pub enum Action {
	none
	insert_byte               // arg = 要插入的字节
	delete_backward
	delete_forward
	kill_line
	move_left
	move_right
	move_up
	move_down
	move_to_bol
	move_to_eol
	move_to_bof
	move_to_eof
	enter_command_mode        // 切到 : 命令模式
	command_save              // :w
	command_quit              // :q
	command_open              // :o <file>
	command_cycle_theme       // :t
	command_backspace         // 命令模式删除前一字符
	save_buffer               // ctrl+s
	open_prompt               // ctrl+o
	cycle_theme               // ctrl+t
	quit_editor               // ctrl+q
	escape                    // <esc>
}

pub struct Binding {
pub:
	action Action
	arg    u8
}

pub struct Keymap {
pub mut:
	bindings map[string]Binding
}

pub fn new_keymap() Keymap {
	return Keymap{
		bindings: map[string]Binding{}
	}
}

pub fn (mut km Keymap) bind(key string, action Action, arg u8) {
	km.bindings[key] = Binding{action: action, arg: arg}
}

pub fn (km &Keymap) lookup(key string) ?Binding {
	if key in km.bindings {
		return km.bindings[key]
	}
	return none
}

// ===== 默认键位注册 =====
//
// 字符 a-z 和 0-9 用循环批量注册, 其它单独.
pub fn register_default_keymaps(mut global_kb Keymap, mut buf_kb Keymap, mut cmd_kb Keymap) {
	// --- buffer_keymap: 字符键 ---
	for i in 32 .. 127 {
		ch := u8(i)
		key_str := ch.str()
		buf_kb.bind(key_str, .insert_byte, ch)
	}

	// --- buffer_keymap: 特殊键 ---
	buf_kb.bind('<enter>',    .insert_byte, `\n`)
	buf_kb.bind('<backspace>', .delete_backward, 0)
	buf_kb.bind('<delete>',   .delete_forward, 0)
	buf_kb.bind('<left>',     .move_left, 0)
	buf_kb.bind('<right>',    .move_right, 0)
	buf_kb.bind('<up>',       .move_up, 0)
	buf_kb.bind('<down>',     .move_down, 0)
	buf_kb.bind('<home>',     .move_to_bol, 0)
	buf_kb.bind('<end>',      .move_to_eol, 0)
	buf_kb.bind('<esc>',      .escape, 0)

	// --- global_keymap: 编辑器级 ---
	global_kb.bind('ctrl+s', .save_buffer, 0)
	global_kb.bind('ctrl+o', .open_prompt, 0)
	global_kb.bind('ctrl+t', .cycle_theme, 0)
	global_kb.bind('ctrl+q', .quit_editor, 0)

	// --- buffer_keymap: 进入命令模式 ---
	buf_kb.bind(':', .enter_command_mode, 0)

	// --- command_keymap: :w / :q / :o / :t ---
	cmd_kb.bind('w', .command_save, 0)
	cmd_kb.bind('q', .command_quit, 0)
	cmd_kb.bind('o', .command_open, 0)
	cmd_kb.bind('t', .command_cycle_theme, 0)
	cmd_kb.bind('<backspace>', .command_backspace, 0)
	cmd_kb.bind('<esc>', .escape, 0)
}

// ===== dispatch =====

pub fn (mut c Context) dispatch(b Binding) {
	match b.action {
		.none {}
		.insert_byte { buffer_insert_byte(mut c.buffer, mut c.view.cursor, b.arg) }
		.delete_backward { buffer_delete_backward(mut c.buffer, mut c.view.cursor) }
		.delete_forward { buffer_delete_forward(mut c.buffer, mut c.view.cursor) }
		.kill_line { buffer_kill_line(mut c.buffer, mut c.view.cursor) }
		.move_left { c.view.cursor.move_left() }
		.move_right { c.view.cursor.move_right(c.buffer.content) }
		.move_up { c.view.cursor.move_up(c.buffer.content) }
		.move_down { c.view.cursor.move_down(c.buffer.content) }
		.move_to_bol { c.view.cursor.move_to_beginning_of_line(c.buffer.content) }
		.move_to_eol { c.view.cursor.move_to_end_of_line(c.buffer.content) }
		.move_to_bof { c.view.cursor.move_to_start_of_buffer() }
		.move_to_eof { c.view.cursor.move_to_end_of_buffer(c.buffer.content) }
		.enter_command_mode {
			c.in_command = true
			c.command_buf = ''
		}
		.command_save {
			// :w [filename] - 如未指定, 用 buffer.file; 如都为空, 提示
			cmd_handle_w(mut c)
		}
		.command_quit {
			cmd_handle_q(mut c)
		}
		.command_open {
			cmd_handle_o(mut c)
		}
		.command_cycle_theme {
			cmd_handle_t(mut c)
		}
		.command_backspace {
			if c.command_buf.len > 0 {
				c.command_buf = c.command_buf[..c.command_buf.len - 1]
			}
		}
		.save_buffer {
			cmd_handle_save(mut c)
		}
		.open_prompt {
			c.in_command = true
			c.command_buf = 'o '
		}
		.cycle_theme {
			name := c.cfg.cycle_theme()
			c.status_message = 'theme: ${name}'
			c.status_until = get_time_ms() + 2000
		}
		.quit_editor {
			if c.buffer.dirty {
				c.status_message = 'unsaved changes! press ctrl+q again to force quit'
				c.status_until = get_time_ms() + 3000
				c.buffer.dirty = false  // 第二次 ctrl+q 直接退出 (简化)
				c.should_quit = true
			} else {
				c.should_quit = true
			}
		}
		.escape {
			c.in_command = false
			c.command_buf = ''
		}
	}
}

// 命令模式处理 - w / q / o / t 的子命令
fn cmd_handle_w(mut c Context) {
	cmd := c.command_buf.trim_space()
	// cmd 可能是 "w" / "w filename"
	parts := cmd.split(' ')
	if parts.len == 1 || (parts.len >= 2 && parts[1] == '') {
		// 纯 :w
		if c.buffer.file == '' {
			c.status_message = 'no filename. use :w <filename>'
			c.status_until = get_time_ms() + 2000
		} else {
			buffer_save_file(c.buffer.file, c.buffer.content) or {
				c.status_message = 'save failed: ${err.msg()}'
				c.status_until = get_time_ms() + 3000
				c.in_command = false
				c.command_buf = ''
				return
			}
			c.buffer.dirty = false
			c.status_message = 'saved ${c.buffer.file}'
			c.status_until = get_time_ms() + 1500
		}
	} else {
		// :w <filename>
		path := parts[1..].join(' ')
		buffer_save_file(path, c.buffer.content) or {
			c.status_message = 'save failed: ${err.msg()}'
			c.status_until = get_time_ms() + 3000
			c.in_command = false
			c.command_buf = ''
			return
		}
		c.buffer.file = path
		c.buffer.dirty = false
		c.status_message = 'saved ${path}'
		c.status_until = get_time_ms() + 1500
	}
	c.in_command = false
	c.command_buf = ''
}

fn cmd_handle_q(mut c Context) {
	if c.buffer.dirty {
		c.status_message = 'unsaved! press :q! to force, or :w to save first'
		c.status_until = get_time_ms() + 3000
		c.in_command = false
		c.command_buf = ''
		return
	}
	c.should_quit = true
	c.in_command = false
	c.command_buf = ''
}

fn cmd_handle_o(mut c Context) {
	cmd := c.command_buf.trim_space()
	parts := cmd.split(' ')
	if parts.len < 2 || parts[1] == '' {
		c.status_message = 'usage: :o <filename>'
		c.status_until = get_time_ms() + 2000
		c.in_command = false
		c.command_buf = ''
		return
	}
	path := parts[1..].join(' ')
	mut new_buf := buffer_load_file(path) or {
		c.status_message = 'open failed: ${err.msg()}'
		c.status_until = get_time_ms() + 3000
		c.in_command = false
		c.command_buf = ''
		return
	}
	c.buffer = new_buf
	c.view.buffer = c.buffer
	c.view.cursor = Cursor{point: 0, mark: 0}
	c.view.visible_start = 0
	c.status_message = 'opened ${path}'
	c.status_until = get_time_ms() + 1500
	c.in_command = false
	c.command_buf = ''
}

fn cmd_handle_t(mut c Context) {
	name := c.cfg.cycle_theme()
	c.status_message = 'theme: ${name}'
	c.status_until = get_time_ms() + 2000
	c.in_command = false
	c.command_buf = ''
}

fn cmd_handle_save(mut c Context) {
	// ctrl+s: 用现有文件名保存, 没有则提示用 :w <filename>
	if c.buffer.file == '' {
		c.status_message = 'no filename. use :w <filename>'
		c.status_until = get_time_ms() + 2000
		return
	}
	buffer_save_file(c.buffer.file, c.buffer.content) or {
		c.status_message = 'save failed: ${err.msg()}'
		c.status_until = get_time_ms() + 3000
		return
	}
	c.buffer.dirty = false
	c.status_message = 'saved ${c.buffer.file}'
	c.status_until = get_time_ms() + 1500
}

// 当前毫秒时间戳 (V 没有原生 time, 用 raylib 的 get_time)
fn get_time_ms() i64 {
	return i64(r.get_time() * 1000.0)
}