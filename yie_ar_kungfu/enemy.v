// =============================================================================
//  enemy.v - 对手 AI + 渲染 + 胜负状态机
// =============================================================================
//
//  对手状态机:
//    VillainMoveState (AI 移动策略):
//      follow_player        - 默认: 向玩家方向走 1 像素, 近距离随机选攻击
//      forward_with_attack  - 攻击动画期间
//      running_left/right   - 受击后退 5 像素/帧, 跑 10 帧回 follow
//
//    VillainAction (动画状态):
//      idle / kick / other / dead / pause
//
//  主循环 game.v 调用顺序:
//    1. game_update()       推进时间/AI/碰撞
//    2. game_render()       画背景 + 对手 + 玩家 + HUD
//
//  关键算法:
//    - AI 在每个 VILLAIN_FRAME_SPEED tick (5 fps) 决策一次移动方向
//    - 攻击动画到最后一帧时, 若攻击框与玩家受击框重叠 -> 扣血 + 触发 shake
//    - 玩家胜负: villain_health=0 -> END_STATE_SHOWTIME 连招演出
//    - player_health=0     -> villain_end_state 演出
// =============================================================================

module main

import raylib as r

// Villain 配置常量
pub const villain_sprite_frame_speed    = 3
pub const spinning_chain_speed          = 6
pub const villain_default_x             = i16(147)
pub const villain_default_y             = i16(152)
pub const villain_frame_speed           = 21
pub const villain_fb_speed              = i16(1)
pub const villain_sprite_frame_speed_run = 7
pub const villain_fb_speed_run          = i16(5)
pub const villain_run_boundary          = 30
pub const villain_back_distance         = u8(10)

// 攻击类型列表 (0=kick, 1=other)
pub const attack_list = [VillainAction.kick, .other]

// ===== AI 主循环 =====
pub fn villain_movement_tick() {
	game.villain_movement_counter += 1
	if game.villain_movement_counter >= (target_fps / villain_frame_speed) {
		game.villain_movement_counter = 0
		handle_villain_movement()
	}
}

// AI 状态机决策
fn handle_villain_movement() {
	match game.villain_move_state {
		.forward_with_attack {
			// 攻击动画中, 什么都不做
		}
		.running_left {
			game.villain_current_move = .idle
			villain_run_left()
		}
		.running_right {
			game.villain_current_move = .idle
			villain_run_right()
		}
		.follow_player {
			villain_follow_player()
			if villain_near_player() {
				villain_simple_attack()
			}
		}
	}
}

// 对手靠近玩家: 按玩家方向走 1 像素
fn villain_follow_player() {
	if game.villain_x > game.player.x {
		villain_modify_x(villain_fb_speed, false)
	}
	if game.villain_x < game.player.x {
		villain_modify_x(villain_fb_speed, true)
	}
}

// 对手离玩家足够近: 随机选 kick / other 进入攻击
fn villain_simple_attack() {
	game.villain_move_state = .forward_with_attack
	game.villain_random_attack = rand_int(2)
	game.villain_current_move = attack_list[game.villain_random_attack]
}

// 是否在攻击范围内 (玩家 sprite 宽度 / 切分数 + 10 像素)
fn villain_near_player() bool {
	if !('player_normal' in game.sprites) {
		return false
	}
	pn := game.sprites['player_normal']
	w := pn.texture.width
	tc := if pn.tile_count > 0 { pn.tile_count } else { 1 }
	boundary := (w / tc) + 10
	if game.is_villain_flipped {
		return game.villain_x >= game.player.x - i16(boundary)
	}
	return game.villain_x <= game.player.x + i16(boundary)
}

// 对手受击后退左
fn villain_run_left() {
	villain_go_direction(game.villain_x > (stage_boundary + villain_run_boundary), false)
}

// 对手受击后退右
fn villain_run_right() {
	w_half := game_width / 2
	villain_go_direction(game.villain_x < (game_width - (stage_boundary + villain_run_boundary) - w_half), true)
}

// 通用后退逻辑
fn villain_go_direction(condition bool, is_right bool) {
	if game.run_counter > villain_back_distance {
		game.villain_move_state = .follow_player
		name := villain_names[game.stage - 1]
		id := '${name}_normal'
		if id in game.sprites {
			game.sprites[id].frame_speed = villain_sprite_frame_speed
		}
		return
	}
	if condition {
		villain_modify_x(villain_fb_speed_run, is_right)
		game.run_counter += 1
		return
	}
	game.villain_move_state = if is_right { .running_left } else { .running_right }
}

// ===== 渲染对手 =====
pub fn draw_villain() {
	set_villain_sprite_positions()
	match game.villain_current_move {
		.kick, .other {
			name := villain_names[game.stage - 1]
			suffix := if game.villain_random_attack == 0 { 'kick' } else { 'other' }
			id := '${name}_${suffix}'
			if id in game.sprites {
				unsafe {
					mut s := &game.sprites[id]
					s.y = int(game.villain_y)
					s.x = int(game.villain_x) - int(villain_collisions[game.stage - 1].body.minus_x_kick)
					s.paused = game.player.show_hit
					if s.play() {
						if !check_villain_attack_on_player() {
							villain_reset_move()
						} else if game.player.health > 0 {
							// 击中已在 check_villain_attack_on_player 中处理
						}
					}
				}
			}
		}
		.dead {
			name := villain_names[game.stage - 1]
			id := '${name}_dead'
			if id in game.sprites {
				game.sprites[id].draw()
			}
		}
		.pause {
			name := villain_names[game.stage - 1]
			suffix := if game.villain_random_attack == 0 { 'kick' } else { 'other' }
			id := '${name}_${suffix}'
			if id in game.sprites {
				game.sprites[id].draw_by_index(1)
			}
		}
		else {
			// idle: 画 spinning_chain (如果是 Chen) + normal
			if game.stage == 3 && 'spinning_chain' in game.sprites {
				unsafe {
					mut sc := &game.sprites['spinning_chain']
					sc.x = int(game.spinning_chain_x)
					sc.y = int(game.spinning_chain_y)
					sc.paused = game.player.show_hit
					sc.play()
				}
			}
			name := villain_names[game.stage - 1]
			id := '${name}_normal'
			if id in game.sprites {
				unsafe {
					mut s := &game.sprites[id]
					s.paused = game.player.show_hit
					s.play()
				}
			}
		}
	}

	// flip checker
	if !game.show_villain_hit && game.villain_current_move != .kick && game.villain_current_move != .other {
		if game.player.x > game.villain_x && !game.is_villain_flipped {
			flip_villain_sprites()
		}
		if game.villain_x > game.player.x && game.is_villain_flipped {
			flip_villain_sprites()
		}
	}
}

// 同步对手各 sprite 的 x/y
fn set_villain_sprite_positions() {
	name := villain_names[game.stage - 1]
	for suffix in ['normal', 'kick', 'other', 'dead', 'hit'] {
		id := '${name}_${suffix}'
		if id in game.sprites {
			game.sprites[id].x = int(game.villain_x)
			game.sprites[id].y = int(game.villain_y)
		}
	}
}

// ===== 玩家胜利: villain_end_state 推进 (被打倒) =====
pub fn handle_villain_end_state() {
	match game.villain_end_state {
		end_state_villain_start {
			game.villain_end_state = end_state_villain_lie_down
			game.villain_current_move = .pause
			r.stop_music_stream(game.music)
			game.player.kuyakoy = 0
		}
		end_state_villain_lie_down {
			game.player.set_movement(.dead)
			game.player.y = player_default_y
			if 'player_dead' in game.sprites {
				game.sprites['player_dead'].reset_current_frame()
			}
			if 'dead' in game.sounds {
				r.play_sound(game.sounds['dead'])
			}
			game.villain_end_state = end_state_villain_move_feet
		}
		end_state_villain_move_feet {
			// 等待 player_dead.play() 推进到第 3 次 (在 player.draw 内处理)
		}
		end_state_villain_end {
			if game.player.lives > 0 {
				game.player.lives -= 1
				game.state = .view
				r.play_music_stream(game.music)
				reset_game_stage()
			} else {
				if 'game_over' in game.sounds {
					r.play_sound(game.sounds['game_over'])
				}
				game.villain_end_state = end_state_villain_game_over
			}
		}
		else {
			// end_state_villain_game_over: 等待 Enter 重启
		}
	}
}

// ===== 玩家胜利: end_state 推进 (连招演出) =====
pub fn handle_end_state() {
	match game.end_state {
		end_state_start {
			game.villain_current_move = .dead
			if 'dead' in game.sounds {
				r.play_sound(game.sounds['dead'])
			}
			game.end_state = end_state_play_sound
		}
		end_state_play_sound {
			if 'win' in game.sounds {
				r.play_sound(game.sounds['win'])
			}
			game.end_state = end_state_showtime
		}
		end_state_showtime {
			end_set(.stand_punch, false, true)
		}
		end_state_showtime_hk1 {
			end_set(.high_kick, true, true)
		}
		end_state_showtime_lk1 {
			end_set(.sit_kick, true, true)
		}
		end_state_showtime_lk2 {
			end_set(.sit_kick, true, true)
		}
		end_state_showtime_hk2 {
			end_set(.high_kick, true, true)
		}
		end_state_showtime_p {
			end_set(.stand_punch, true, true)
		}
		end_state_smile {
			end_set(.smile, true, false)
		}
		end_state_count_life {
			game.max_halt_time = 1
			if game.player.health > 0 {
				game.player.health -= 1
				if 'counting' in game.sounds {
					r.play_sound(game.sounds['counting'])
				}
				game.score += 100
			} else {
				game.end_state = end_state_end
			}
		}
		end_state_end {
			game.max_halt_time = 2
			if game.stage == max_stages {
				if 'game_over' in game.sounds {
					r.play_sound(game.sounds['game_over'])
				}
				game.end_state = end_state_game_over
			} else {
				game.stage += 1
				game.state = .view
				r.play_music_stream(game.music)
				reset_game_stage()
			}
		}
		else {
			// end_state_game_over: 等待 Enter
		}
	}
}

// 设置玩家动作 + 推进 end_state (用于连招演出)
fn end_set(move PlayerMove, flip bool, play_sound bool) {
	if flip {
		game.player.flip_all_sprites()
	}
	game.player.set_movement(move)
	if play_sound {
		if 'attack' in game.sounds {
			r.play_sound(game.sounds['attack'])
		}
	}
	game.end_state += 1
}

// ===== 公共时间 tick (60 Hz) =====
pub fn game_tick() {
	game.time_counter += 1
	if game.time_counter >= (target_fps / frame_speed) {
		game.time_counter = 0
		if game.time_seconds == 59 {
			game.time_seconds = 0
			game_on_time_tick()
			return
		}
		game.time_seconds += 1
		game_on_time_tick()
	}
}

fn game_on_time_tick() {
	if game.state != .game {
		return
	}
	// 受击暂停 (player hit villain)
	if game.pause_movement {
		game.halt_time += 1
		if game.halt_time == 2 {
			game.pause_movement = false
			game.halt_time = 0
			if game.player.current_movement == .up || game.player.current_movement == .coming_down {
				game.player.activate_attack = true
				game.player.activate_time = 0
				game.player.show_hit = false
			}
			game.villain_health -= 1
			if game.villain_health == 0 {
				r.stop_music_stream(game.music)
				game.halt_time = 0
			} else {
				if game.villain_move_state != .running_left && game.villain_move_state != .running_right {
					game.run_counter = 0
					game.villain_move_state = if !game.is_villain_flipped { .running_right } else { .running_left }
					name := villain_names[game.stage - 1]
					id := '${name}_normal'
					if id in game.sprites {
						game.sprites[id].frame_speed = villain_sprite_frame_speed_run
					}
				}
			}
		}
	}

	// 玩家击败对手 -> 连招演出
	if game.villain_health == 0 {
		game.halt_time += 1
		if game.halt_time == game.max_halt_time {
			handle_end_state()
			game.halt_time = 0
		}
	}

	// 玩家血量归零 -> 死亡演出
	if game.player.health == 0 && game.villain_health != 0 {
		game.halt_time += 1
		if game.halt_time == game.max_halt_time {
			handle_villain_end_state()
			game.halt_time = 0
		}
	}

	// villain hit player 后恢复
	if game.show_villain_hit {
		game.halt_time_hit += 1
		if game.halt_time_hit == 4 {
			game.halt_time_hit = 0
			game.show_villain_hit = false
			villain_reset_move()
			game.player.x = game.player.old_x
			game.player.shake = false
			// 还原玩家动作
			if (game.player.current_movement == .right && !r.is_key_down(int(r.KeyboardKey.key_right)))
				|| (game.player.current_movement == .left && !r.is_key_down(int(r.KeyboardKey.key_left)))
				|| (game.player.current_movement == .down && !r.is_key_down(int(r.KeyboardKey.key_down))) {
				game.player.set_movement(.idle)
			}
			if game.player.health == 0 {
				game.villain_current_move = .pause
			}
		}
	}
}

// 每帧总更新 (非暂停时)
pub fn game_update_active() {
	if !game.pause_movement {
		game.player.tick_halts()
		game.player.handle_jump()
	}
	if !game.player.show_hit && game.villain_health > 0 && game.player.health > 0 {
		villain_movement_tick()
	}
}

// game_over 屏: 按 Enter 重启
pub fn game_over_handle_keys() {
	if r.is_key_pressed(int(r.KeyboardKey.key_enter))
		|| r.is_key_pressed(int(r.KeyboardKey.key_space)) {
		game_init()
		game_load_assets()
		title_init()
	}
}