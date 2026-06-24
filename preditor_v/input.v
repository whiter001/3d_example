// =============================================================================
//  input.v - 把 raylib 键盘事件转换为 Key 字符串
// =============================================================================
//
//  get_key() 返回 ?string:
//    - none: 本帧没有按键
//    - Some(key): 按下的键, 字符串格式见 keymap.v
//
//  修饰键组合: 'ctrl+x' / 'alt+x' / 'shift+x'
//  特殊键: '<enter>' / '<esc>' / '<tab>' / '<backspace>' / '<up>' / '<down>' / ...
//  普通字符: 'a' .. 'z' / 'A' .. 'Z' / '0' .. '9' / 标点
//
//  注意: raylib 的 IsKeyPressed 只在该帧返回 true 一次, 适合单次触发命令.
// =============================================================================

module main

import raylib as r

// 修饰键状态 (主侧 + 副侧任一即可)
fn ctrl_down() bool {
	return r.is_key_down(int(r.KeyboardKey.key_left_control))
		|| r.is_key_down(int(r.KeyboardKey.key_right_control))
}

fn alt_down() bool {
	return r.is_key_down(int(r.KeyboardKey.key_left_alt))
		|| r.is_key_down(int(r.KeyboardKey.key_right_alt))
}

fn shift_down() bool {
	return r.is_key_down(int(r.KeyboardKey.key_left_shift))
		|| r.is_key_down(int(r.KeyboardKey.key_right_shift))
}

// 把修饰键拼到 key 字符串前面 (例 'ctrl+s')
fn with_mod(key string, ctrl bool, alt bool, shift bool) string {
	if ctrl {
		return 'ctrl+${key}'
	}
	if alt {
		return 'alt+${key}'
	}
	if shift {
		return 'shift+${key}'
	}
	return key
}

// 读本帧按键, 返回 ?string
pub fn get_key() ?string {
	ctrl  := ctrl_down()
	alt   := alt_down()
	shift := shift_down()

	// ---- 特殊键 (优先于字符键) ----
	if r.is_key_pressed(int(r.KeyboardKey.key_enter)) {
		return with_mod('<enter>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_escape)) {
		return with_mod('<esc>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_tab)) {
		return with_mod('<tab>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_backspace)) {
		return with_mod('<backspace>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_delete)) {
		return with_mod('<delete>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_up)) {
		return with_mod('<up>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_down)) {
		return with_mod('<down>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_left)) {
		return with_mod('<left>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_right)) {
		return with_mod('<right>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_home)) {
		return with_mod('<home>', ctrl, alt, shift)
	}
	if r.is_key_pressed(int(r.KeyboardKey.key_end)) {
		return with_mod('<end>', ctrl, alt, shift)
	}

	// ---- 字母键 a-z ----
	letter_keys := {
		'a': int(r.KeyboardKey.key_a)
		'b': int(r.KeyboardKey.key_b)
		'c': int(r.KeyboardKey.key_c)
		'd': int(r.KeyboardKey.key_d)
		'e': int(r.KeyboardKey.key_e)
		'f': int(r.KeyboardKey.key_f)
		'g': int(r.KeyboardKey.key_g)
		'h': int(r.KeyboardKey.key_h)
		'i': int(r.KeyboardKey.key_i)
		'j': int(r.KeyboardKey.key_j)
		'k': int(r.KeyboardKey.key_k)
		'l': int(r.KeyboardKey.key_l)
		'm': int(r.KeyboardKey.key_m)
		'n': int(r.KeyboardKey.key_n)
		'o': int(r.KeyboardKey.key_o)
		'p': int(r.KeyboardKey.key_p)
		'q': int(r.KeyboardKey.key_q)
		'r': int(r.KeyboardKey.key_r)
		's': int(r.KeyboardKey.key_s)
		't': int(r.KeyboardKey.key_t)
		'u': int(r.KeyboardKey.key_u)
		'v': int(r.KeyboardKey.key_v)
		'w': int(r.KeyboardKey.key_w)
		'x': int(r.KeyboardKey.key_x)
		'y': int(r.KeyboardKey.key_y)
		'z': int(r.KeyboardKey.key_z)
	}
	for ch, keycode in letter_keys {
		if r.is_key_pressed(keycode) {
			if ctrl || alt {
				return with_mod(ch, ctrl, alt, false)
			}
			// shift: 输出大写 (V 的 byte 转 char 直接用 ch.str())
			if shift {
				return ch.to_upper().str()
			}
			return ch.str()
		}
	}

	// ---- 数字键 0-9 ----
	digit_keys := {
		'0': int(r.KeyboardKey.key_zero)
		'1': int(r.KeyboardKey.key_one)
		'2': int(r.KeyboardKey.key_two)
		'3': int(r.KeyboardKey.key_three)
		'4': int(r.KeyboardKey.key_four)
		'5': int(r.KeyboardKey.key_five)
		'6': int(r.KeyboardKey.key_six)
		'7': int(r.KeyboardKey.key_seven)
		'8': int(r.KeyboardKey.key_eight)
		'9': int(r.KeyboardKey.key_nine)
	}
	for ch, keycode in digit_keys {
		if r.is_key_pressed(keycode) {
			if ctrl || alt {
				return with_mod(ch, ctrl, alt, false)
			}
			return ch.str()
		}
	}

	// ---- 标点键 ----
	punct_keys := {
		' ':    int(r.KeyboardKey.key_space)
		',':    int(r.KeyboardKey.key_comma)
		'.':    int(r.KeyboardKey.key_period)
		'/':    int(r.KeyboardKey.key_slash)
		';':    int(r.KeyboardKey.key_semicolon)
		'\'':   int(r.KeyboardKey.key_apostrophe)
		'\\':   int(r.KeyboardKey.key_backslash)
		'[':    int(r.KeyboardKey.key_left_bracket)
		']':    int(r.KeyboardKey.key_right_bracket)
		'-':    int(r.KeyboardKey.key_minus)
		'=':    int(r.KeyboardKey.key_equal)
		'`':    int(r.KeyboardKey.key_grave)
	}
	for ch, keycode in punct_keys {
		if r.is_key_pressed(keycode) {
			if ctrl || alt {
				return with_mod(ch, ctrl, alt, false)
			}
			return ch.str()
		}
	}

	// ':' 单独 (V 中 map key 用 rune 即可, 但 raylib 没有 key_colon, 用 shift+semicolon 模拟)
	if r.is_key_pressed(int(r.KeyboardKey.key_semicolon)) && shift {
		return ':'
	}

	return none
}

// 处理本帧按键: 先 global_keymap, 再 buffer_keymap 或 command_keymap
pub fn handle_key_events(mut c Context) {
	key := get_key() or { return }
	mut binding := c.global_keymap.lookup(key) or { Binding{} }
	if binding.action == .none {
		// 命令模式用 command_keymap; 普通模式用 buffer_keymap
		mut km := if c.in_command { c.command_keymap } else { c.buffer_keymap }
		binding = km.lookup(key) or { return }
	}
	c.dispatch(binding)
}