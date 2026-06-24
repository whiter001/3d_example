// =============================================================================
//  stage.v - title / view / game 三个阶段的渲染与状态切换
// =============================================================================
//
//  每个阶段各自有:
//    init_xxx()      - 一次性, 把对应 sprite 的 x/y 摆好
//    draw_xxx()      - 渲染到 RenderTexture (背景 + 玩家 + 对手 + HUD)
//    handle_keys_xxx() - 读键盘
//    update_xxx()    - 每帧推进时间相关计数
//
//  main.v 主循环在 game.update() / game.render() 中按 state 派发到对应函数.
// =============================================================================

module main

import raylib as r

// ===== title 屏 (按 Enter 进入 view) =====
pub fn title_handle_keys() {
	if r.is_key_pressed(int(r.KeyboardKey.key_enter)) || r.is_key_pressed(int(r.KeyboardKey.key_space)) {
		if !game.blink_enter && game.can_enter {
			game.blink_enter = true
			r.play_music_stream(game.music)
		}
	}
	if r.is_key_released(int(r.KeyboardKey.key_enter)) || r.is_key_released(int(r.KeyboardKey.key_space)) {
		game.can_enter = true
	}
}

pub fn title_update() {
	if game.blink_enter {
		game.blink_frames_counter += 1
		if game.blink_frames_counter >= 30 {
			game.blink_frames_counter = 0
			game.blink_count += 1
			if game.blink_count >= 4 {
				game.state = .view
				game.blink_enter = false
				game.blink_count = 0
			}
		}
	}
}

pub fn title_draw() {
	r.clear_background(r.black)
	if 'konami_logo' in game.sprites {
		game.sprites['konami_logo'].draw()
	}
	if 'title' in game.sprites {
		game.sprites['title'].draw()
	}
	// 版权文字 (用 raylib DrawText 简化)
	ui_draw_centered_text('* 1985 konami', 110, 8, r.Color{200, 200, 200, 255})
	ui_draw_centered_text('* 2024 silva (v port)', 120, 8, r.Color{200, 200, 200, 255})
	if game.blink_enter {
		// 闪烁: 每 30 帧切换 alpha
		if (game.blink_frames_counter / 4) % 2 == 0 {
			ui_draw_centered_text('press enter to start', 165, 8, r.white)
		}
	} else {
		ui_draw_centered_text('press enter to start', 165, 8, r.white)
	}
}

// ===== view 屏 (显示 STAGE N 1 秒) =====
pub fn view_handle_keys() {
	// view 阶段不接受任何按键
}

pub fn view_update() {
	game.time_seconds += 1
	if game.time_seconds >= 60 {
		game.time_seconds = 0
		game.time_counter = 0
		game.state = .game
		game_init_layout()
	}
}

pub fn view_draw() {
	r.clear_background(r.black)
	stage_text := 'stage ${game.stage}'
	ui_draw_centered_text(stage_text, game_height / 2 - 4, 16, r.white)
}

// ===== game 屏 =====
pub fn game_handle_keys() {
	if game.player.health > 0 && game.villain_health > 0 {
		game.player.handle_keys()
	}
	// game over: Enter 重启
	if (game.end_state == end_state_game_over || game.villain_end_state == end_state_villain_game_over)
		&& (r.is_key_pressed(int(r.KeyboardKey.key_enter)) || r.is_key_pressed(int(r.KeyboardKey.key_space))) {
		game_init()
		game_load_assets()
		title_init()
	}
}

pub fn game_update() {
	// 受击红屏恢复
	if game.show_villain_hit {
		game_update_active()
		return
	}
	game_update_active()
	game.player.face_villain()
}

pub fn game_draw() {
	r.update_music_stream(game.music)

	// 背景
	if 'game_bg' in game.sprites {
		game.sprites['game_bg'].draw()
	}

	// 顶部 HUD
	ui_draw_game_hud()

	// 双方血条
	ui_draw_health_bars()

	// 对手
	draw_villain()

	// 玩家
	game.player.shake_apply()
	game.player.draw()

	// 显示对手 hit 精灵
	if game.show_villain_hit {
		name := villain_names[game.stage - 1]
		hit_id := '${name}_hit'
		if hit_id in game.sprites {
			game.sprites[hit_id].draw()
		}
	}

	// game over 文字
	if game.end_state == end_state_game_over || game.villain_end_state == end_state_villain_game_over {
		ui_draw_centered_text('game over', game_height / 2 - 4, 10, r.white)
		end_text := if game.end_state == end_state_game_over { 'you win' } else { 'you lose' }
		ui_draw_centered_text(end_text, game_height / 2 + 6, 10, r.white)
	}
}

// ===== RenderTexture 拉伸到屏幕 =====
pub fn blit_target_to_screen() {
	src := r.Rectangle{
		x:      0
		y:      0
		width:  f32(game_width)
		height: f32(-game_height)  // 翻转
	}
	// 保持比例 (256:240 == 16:15) 居中填满屏幕高度
	dst_h := f32(screen_height)
	dst_w := dst_h * f32(game_width) / f32(game_height)
	dst_x := (f32(screen_width) - dst_w) / 2.0
	dst := r.Rectangle{
		x:      dst_x
		y:      0
		width:  dst_w
		height: dst_h
	}
	origin := r.Vector2{0, 0}
	r.draw_texture_pro(game.target.texture, src, dst, origin, 0, r.white)
}

// ===== 主循环派发 =====
pub fn stage_update() {
	match game.state {
		.title { title_update() }
		.view { view_update() }
		.game { game_update() }
	}
}

pub fn stage_handle_keys() {
	match game.state {
		.title { title_handle_keys() }
		.view { view_handle_keys() }
		.game { game_handle_keys() }
	}
}

pub fn stage_draw() {
	r.begin_texture_mode(game.target)
	match game.state {
		.title { title_draw() }
		.view { view_draw() }
		.game { game_draw() }
	}
	r.end_texture_mode()
}