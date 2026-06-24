// =============================================================================
//  buffer.v - 文本缓冲区 + 视图 + 光标
// =============================================================================
//
//  Buffer 保存文件内容 (字节切片) + 文件名 + dirty 标记.
//  BufferView 是渲染层: 持有 Buffer 引用 + 光标 + 视口起始行.
//  Cursor (Emacs-style): point (主光标字节偏移) + mark (选区另一端字节偏移).
//
//  坐标系统:
//    byte offset 0..content.len (主坐标)
//    line 0..line_count-1       (展示用)
//    column 0..line_len-1       (展示用, 一行字节数)
//
//  关键算法:
//    - byte_to_line_col / line_col_to_byte: byte ↔ (line, col) 转换
//    - move_cursor_*: 在 byte 空间移动, 受 content 边界保护
//    - insert_char / delete_backward / delete_forward: 修改 content + dirty 标记
// =============================================================================

module main

import os

pub struct Buffer {
pub mut:
	file     string  // 关联文件名 (空 = 匿名 buffer)
	content  []u8
	dirty    bool    // 有未保存修改
	readonly bool
}

pub struct BufferView {
pub mut:
	buffer        Buffer
	cursor        Cursor
	visible_start int  // 第一行可见的行号
	tab_size      int = 4
	show_line_numbers bool = true
}

pub struct Cursor {
pub mut:
	point int  // 字节偏移
	mark  int
}

// ===== 工厂函数 =====

pub fn new_buffer(file string, content []u8) Buffer {
	return Buffer{
		file:     file
		content:  content.clone()
		dirty:    false
		readonly: false
	}
}

pub fn new_buffer_view(buf Buffer, tab_size int, show_line_numbers bool) BufferView {
	return BufferView{
		buffer: buf
		cursor: Cursor{point: 0, mark: 0}
		visible_start: 0
		tab_size: tab_size
		show_line_numbers: show_line_numbers
	}
}

// ===== 文件 I/O =====

pub fn buffer_load_file(path string) !Buffer {
	content := os.read_file(path)!
	return Buffer{
		file:    path
		content: content.bytes()
		dirty:   false
	}
}

pub fn buffer_save_file(path string, content []u8) ! {
	os.write_file(path, content.bytestr())!
}

// ===== 行/列 ↔ 字节偏移 =====

// 字节偏移 -> (line, col), col 从 0 开始, line 从 0 开始
pub fn byte_to_line_col(content []u8, pos int) (int, int) {
	mut line := 0
	mut col := 0
	bound := if pos < content.len { pos } else { content.len }
	for i in 0 .. bound {
		if content[i] == `\n` {
			line++
			col = 0
		} else {
			col++
		}
	}
	return line, col
}

// (line, col) -> 字节偏移, 越界时 clamp 到末尾
pub fn line_col_to_byte(content []u8, target_line int, target_col int) int {
	mut cur_line := 0
	mut cur_col := 0
	for i, ch in content {
		if cur_line == target_line && cur_col == target_col {
			return i
		}
		if ch == `\n` {
			if cur_line == target_line {
				return i  // 列超出行末尾
			}
			cur_line++
			cur_col = 0
		} else {
			cur_col++
		}
	}
	return content.len
}

// 取得 line 的总列数 (不含换行符)
pub fn line_length(content []u8, line int) int {
	mut cur_line := 0
	mut col := 0
	for ch in content {
		if cur_line == line {
			if ch == `\n` {
				return col
			}
			col++
			continue
		}
		if ch == `\n` {
			cur_line++
		}
	}
	return col
}

// 取得换行符的字节偏移 (line 行的起始位置)
pub fn line_start(content []u8, line int) int {
	if line <= 0 {
		return 0
	}
	mut cur_line := 0
	for i, ch in content {
		if ch == `\n` {
			cur_line++
			if cur_line == line {
				return i + 1
			}
		}
	}
	return content.len
}

// 总行数
pub fn count_lines(content []u8) int {
	if content.len == 0 {
		return 0
	}
	mut n := 1
	for ch in content {
		if ch == `\n` {
			n++
		}
	}
	// 以 \n 结尾时不计最后空行
	if content[content.len - 1] == `\n` {
		n--
	}
	return n
}

// ===== 光标移动 =====

pub fn (mut cur Cursor) move_left() {
	if cur.point > 0 {
		cur.point--
	}
}

pub fn (mut cur Cursor) move_right(content []u8) {
	if cur.point < content.len {
		cur.point++
	}
}

pub fn (mut cur Cursor) move_up(content []u8) {
	line, col := byte_to_line_col(content, cur.point)
	if line > 0 {
		new_line := line - 1
		new_col := if col < line_length(content, new_line) { col } else { line_length(content, new_line) }
		cur.point = line_col_to_byte(content, new_line, new_col)
	}
}

pub fn (mut cur Cursor) move_down(content []u8) {
	line, col := byte_to_line_col(content, cur.point)
	total_lines := count_lines(content)
	if line < total_lines - 1 || (line == total_lines - 1 && col < line_length(content, line)) {
		new_line := line + 1
		new_col := if col < line_length(content, new_line) { col } else { line_length(content, new_line) }
		cur.point = line_col_to_byte(content, new_line, new_col)
	}
}

pub fn (mut cur Cursor) move_to_beginning_of_line(content []u8) {
	line, _ := byte_to_line_col(content, cur.point)
	cur.point = line_start(content, line)
}

pub fn (mut cur Cursor) move_to_end_of_line(content []u8) {
	line, _ := byte_to_line_col(content, cur.point)
	cur.point = line_col_to_byte(content, line, line_length(content, line))
}

pub fn (mut cur Cursor) move_to_start_of_buffer() {
	cur.point = 0
}

pub fn (mut cur Cursor) move_to_end_of_buffer(content []u8) {
	cur.point = content.len
}

// ===== 内容修改 =====

// 在 point 处插入一个字节, 光标前进 1
pub fn buffer_insert_byte(mut buf Buffer, mut cur Cursor, ch u8) {
	if buf.readonly {
		return
	}
	mut new_content := []u8{}
	new_content << buf.content[..cur.point]
	new_content << ch
	new_content << buf.content[cur.point..]
	buf.content = new_content
	cur.point++
	if cur.mark > cur.point - 1 {
		cur.mark = cur.point
	}
	buf.dirty = true
}

// 在 point 处删除前一个字节 (backspace)
pub fn buffer_delete_backward(mut buf Buffer, mut cur Cursor) {
	if buf.readonly || cur.point == 0 {
		return
	}
	mut new_content := []u8{}
	new_content << buf.content[..cur.point - 1]
	new_content << buf.content[cur.point..]
	buf.content = new_content
	cur.point--
	if cur.mark > cur.point {
		cur.mark = cur.point
	}
	buf.dirty = true
}

// 在 point 处删除后一个字节 (delete)
pub fn buffer_delete_forward(mut buf Buffer, mut cur Cursor) {
	if buf.readonly || cur.point >= buf.content.len {
		return
	}
	mut new_content := []u8{}
	new_content << buf.content[..cur.point]
	new_content << buf.content[cur.point + 1..]
	buf.content = new_content
	if cur.mark > cur.point {
		cur.mark = cur.point
	}
	buf.dirty = true
}

// 整行删除 (从行首到行尾含换行)
pub fn buffer_kill_line(mut buf Buffer, mut cur Cursor) {
	if buf.readonly {
		return
	}
	line, _ := byte_to_line_col(buf.content, cur.point)
	start := line_start(buf.content, line)
	end := if start + line_length(buf.content, line) < buf.content.len {
		start + line_length(buf.content, line) + 1  // +1 for \n
	} else {
		buf.content.len
	}
	mut new_content := []u8{}
	new_content << buf.content[..start]
	new_content << buf.content[end..]
	buf.content = new_content
	cur.point = start
	if cur.mark > cur.point {
		cur.mark = cur.point
	}
	buf.dirty = true
}

// 全部替换 buffer 内容 (打开新文件时用)
pub fn buffer_replace_content(mut buf Buffer, new_content []u8) {
	buf.content = new_content.clone()
	buf.dirty = false
}

// ===== 行视图辅助 =====

// 返回第 i 行 (0-based) 的字节切片 (不含末尾 \n); 越界返回空
pub fn get_line_bytes(content []u8, line int) []u8 {
	start := line_start(content, line)
	mut end := start
	for end < content.len && content[end] != `\n` {
		end++
	}
	return content[start..end]
}