// =============================================================================
//  config.v - 编辑器配置 + 主题
// =============================================================================
//
//  Config 持有运行时配置 (tab size / 字号 / 当前主题索引).
//  Theme 是一组 Color: 背景 / 前景 / 光标 / 状态栏 / 行号 等.
//
//  内置 3 个主题 (对齐 Preditor 原版):
//    - Default_Dark      黑色背景, 绿色前景 (类似 Doom 终端)
//    - 4Coder_Fleury     中性灰背景 (Preditor 默认)
//    - VisualStudio_Light 白色背景, 蓝色光标
// =============================================================================

module main

import raylib as r

pub struct Config {
pub mut:
	tab_size          int = 4
	show_line_numbers bool = true
	font_size         int = 17
	cursor_blink_ms   int = 500
	themes            []Theme
	current_theme_idx int
}

pub struct Theme {
pub:
	name   string
	colors Colors
}

pub struct Colors {
pub:
	background        r.Color
	foreground        r.Color
	cursor            r.Color
	cursor_line_bg    r.Color
	selection_bg      r.Color
	selection_fg      r.Color
	line_number_fg    r.Color
	status_bar_bg     r.Color
	status_bar_fg     r.Color
	active_border     r.Color
}

// ===== 默认主题 =====

fn theme_default_dark() Theme {
	return Theme{
		name: 'Default_Dark'
		colors: Colors{
			background:     r.Color{12, 12, 12, 255}      // #0c0c0c
			foreground:     r.Color{144, 176, 144, 255}   // #90B090
			cursor:         r.Color{0, 255, 0, 255}       // #00ff00
			cursor_line_bg: r.Color{82, 83, 78, 255}      // #52534E
			selection_bg:   r.Color{255, 68, 221, 255}    // #FF44DD
			selection_fg:   r.Color{255, 255, 255, 255}
			line_number_fg: r.Color{242, 242, 242, 255}   // #F2F2F2
			status_bar_bg:  r.Color{136, 136, 136, 255}   // #888888
			status_bar_fg:  r.Color{0, 0, 0, 255}
			active_border:  r.Color{41, 41, 41, 255}      // #292929
		}
	}
}

fn theme_4coder_fleury() Theme {
	return Theme{
		name: '4Coder_Fleury'
		colors: Colors{
			background:     r.Color{40, 42, 54, 255}      // Dracula-ish dark
			foreground:     r.Color{248, 248, 242, 255}   // 接近白
			cursor:         r.Color{255, 200, 87, 255}    // 琥珀色
			cursor_line_bg: r.Color{68, 71, 90, 255}      // #4457A...
			selection_bg:   r.Color{80, 90, 140, 255}
			selection_fg:   r.Color{248, 248, 242, 255}
			line_number_fg: r.Color{98, 114, 164, 255}
			status_bar_bg:  r.Color{40, 42, 54, 255}
			status_bar_fg:   r.Color{189, 147, 249, 255}  // 紫色
			active_border:   r.Color{255, 200, 87, 255}
		}
	}
}

fn theme_vs_light() Theme {
	return Theme{
		name: 'VisualStudio_Light'
		colors: Colors{
			background:     r.Color{255, 255, 255, 255}   // #ffffff
			foreground:     r.Color{0, 0, 0, 255}         // #000000
			cursor:         r.Color{23, 23, 23, 255}      // #171717
			cursor_line_bg: r.Color{245, 245, 245, 255}   // #F5F5F5
			selection_bg:   r.Color{173, 214, 255, 255}   // #ADD6FF
			selection_fg:   r.Color{0, 0, 0, 255}
			line_number_fg: r.Color{1, 1, 1, 255}         // #010101
			status_bar_bg:  r.Color{105, 105, 105, 255}   // #696969
			status_bar_fg:  r.Color{0, 0, 0, 255}
			active_border:  r.Color{140, 222, 148, 255}   // #8cde94
		}
	}
}

// 初始化默认配置 + 主题
pub fn config_default() Config {
	mut cfg := Config{}
	cfg.themes = [theme_default_dark(), theme_4coder_fleury(), theme_vs_light()]
	cfg.current_theme_idx = 1  // 4Coder_Fleury 为默认
	return cfg
}

// 取当前主题
pub fn (c Config) current_theme() Theme {
	if c.themes.len == 0 {
		return theme_default_dark()
	}
	if c.current_theme_idx < 0 || c.current_theme_idx >= c.themes.len {
		return c.themes[0]
	}
	return c.themes[c.current_theme_idx]
}

// 循环切换到下一个主题, 返回主题名
pub fn (mut c Config) cycle_theme() string {
	if c.themes.len == 0 {
		return ''
	}
	c.current_theme_idx = (c.current_theme_idx + 1) % c.themes.len
	return c.themes[c.current_theme_idx].name
}