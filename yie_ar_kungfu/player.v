// =============================================================================
//  player.v - 玩家 FSM + 攻击判定 + 跳跃物理
// =============================================================================
//
//  PlayerMove 枚举对齐 Zig 原版常量:
//    none / idle / idle_2 / left / right / down / stand_punch / sit_punch
//    stand_kick / sit_kick / high_kick / up / coming_down / smile / dead / very_dead
//
//  所有跨文件访问的全局状态走 module main 的 pub mut game 变量 (见 game.v).
//  玩家逻辑只读 villain_x/y 等少量字段, 不直接持有 game.
//
//  方法:
//    handle_keys  - 读 raylib 键盘, 切换 current_movement / 触发跳跃 / 触发攻击
//    handle_jump  - 推进 y 坐标, 到达顶点后切到 coming_down
//    attack       - 走完整攻击流程: 判定命中 + 扣血 + 加分 + 音效
//    draw         - 根据 current_movement 渲染对应 sprite
// =============================================================================

module main

import raylib as r

pub enum PlayerMove {
	none        = -1
	idle        = 0
	idle_2      = 1
	left        = 2
	right       = 3
	down        = 4
	stand_punch = 5
	sit_punch   = 6
	stand_kick  = 7
	sit_kick    = 8
	high_kick   = 9
	up          = 10
	coming_down = 11
	smile       = 12
	dead        = 13
	very_dead   = 14
}

pub const player_speed              = i16(1)
pub const player_frame_speed        = 15
pub const player_default_x          = i16(40)
pub const player_default_y          = i16(159)
pub const player_default_lives      = u8(2)
pub const player_jump_height        = i16(115)
pub const player_jump_speed         = i16(2)
pub const player_jump_accel         = u16(55)
pub const player_jump_towards_none  = u8(0)
pub const player_jump_towards_left  = u8(1)
pub const player_jump_towards_right = u8(2)
pub const player_shake_force        = i16(2)
pub const player_can_attack_time    = 2

pub const player_sprite_ids = [
	'player_normal',
	'player_down',
	'player_stand_punch',
	'player_sit_punch',
	'player_stand_kick',
	'player_sit_kick',
	'player_high_kick',
	'player_flying_kick',
	'player_smile',
	'player_dead',
]

pub struct CollisionInfo {
pub:
	x1           i16
	x2           i16
	y            i16
	width        u16
	height       u16
	minus_x_kick i16
}

// 6 个攻击类型的判定框 (相对玩家 x/y 偏移)
pub const ci_sit_punch   = CollisionInfo{ x1: 28, x2: 0, y: 19, width: 3, height: 3, minus_x_kick: 0 }
pub const ci_stand_kick  = CollisionInfo{ x1: 25, x2: 0, y: 24, width: 6, height: 5, minus_x_kick: 0 }
pub const ci_sit_kick    = CollisionInfo{ x1: 30, x2: 0, y: 27, width: 6, height: 5, minus_x_kick: 0 }
pub const ci_high_kick   = CollisionInfo{ x1: 27, x2: 0, y: 3,  width: 5, height: 4, minus_x_kick: 0 }
pub const ci_air         = CollisionInfo{ x1: 31, x2: 0, y: 24, width: 4, height: 5, minus_x_kick: 0 }
pub const ci_stand_punch = CollisionInfo{ x1: 25, x2: 0, y: 14, width: 3, height: 3, minus_x_kick: 0 }

// 玩家本体受击框 (用于被 villain 攻击)
pub const player_collision_info = CollisionInfo{ x1: 8, x2: 10, y: 1, width: 10, height: 32, minus_x_kick: 0 }

pub struct Player {
pub mut:
	time_counter        u16
	time_seconds        u16
	halt_time           u16
	halt_time_jump      u16
	last_movement       PlayerMove = .none
	jump_frames_counter u16
	acceleration_speed  u16 = player_jump_accel
	jump_towards        u8  = player_jump_towards_none
	is_flying_kick      bool
	can_flying_kick     bool = true
	is_flipped          bool
	x                   i16 = player_default_x
	y                   i16 = player_default_y
	lives               u8  = player_default_lives
	health              u8  = default_health
	current_movement    PlayerMove = .none
	input_disabled      bool
	can_attack          bool = true
	activate_attack     bool
	activate_time       u8
	old_x               i16
	shake               bool
	add_x               bool = true
	kuyakoy             u8
	show_hit            bool
}

pub fn new_player() Player {
	return Player{
		health:    default_health
		lives:     player_default_lives
		is_flipped: false
	}
}

// 复位 (进入新关卡)
pub fn (mut p Player) clear() {
	p.set_movement(.idle)
	p.x = player_default_x
	p.y = player_default_y
	p.input_disabled = false
	p.halt_time = 0
	p.halt_time_jump = 0
	p.can_attack = true
	p.activate_attack = false
	p.last_movement = .none
	p.health = default_health
	p.is_flying_kick = false
	p.can_flying_kick = true
	p.show_hit = false
	p.shake = false
	p.kuyakoy = 0
	p.old_x = 0
	if p.is_flipped {
		p.flip_all_sprites()
	}
}

// 设置当前动作
pub fn (mut p Player) set_movement(m PlayerMove) {
	if p.current_movement == .dead && m == .idle {
		return
	}
	p.last_movement = p.current_movement
	p.current_movement = m
}

// 同步所有玩家 sprite 的 x/y 到 p.x / p.y
pub fn (mut p Player) sync_sprite_positions() {
	for id in player_sprite_ids {
		if id in game.sprites {
			game.sprites[id].x = int(p.x)
			game.sprites[id].y = int(p.y)
		}
	}
}

// 翻转所有玩家 sprite (同步 hit 精灵)
pub fn (mut p Player) flip_all_sprites() {
	for id in player_sprite_ids {
		if id in game.sprites {
			game.sprites[id].flip_horizontal()
		}
	}
	if 'hit' in game.sprites {
		game.sprites['hit'].flip_horizontal()
	}
	p.is_flipped = !p.is_flipped
}

// 屏幕摇晃 (受击时由 game.v 推进)
pub fn (mut p Player) shake_apply() {
	if p.shake {
		if p.add_x {
			p.x += player_shake_force
		} else {
			p.x -= player_shake_force
		}
		p.add_x = !p.add_x
	}
}

// 在 256x240 渲染坐标系下根据 current_movement 绘制当前帧
pub fn (mut p Player) draw() {
	p.sync_sprite_positions()

	match p.current_movement {
		.left, .right {
			if 'player_normal' in game.sprites {
				unsafe {
					mut s := &game.sprites['player_normal']
					s.paused = game.show_villain_hit
					s.play()
				}
			}
		}
		.down, .up, .coming_down {
			if p.is_flying_kick {
				if 'player_flying_kick' in game.sprites {
					game.sprites['player_flying_kick'].draw()
				}
			} else if 'player_down' in game.sprites {
				game.sprites['player_down'].draw()
			}
		}
		.idle_2 {
			if 'player_normal' in game.sprites {
				game.sprites['player_normal'].draw_by_index(1)
			}
		}
		.stand_punch {
			if 'player_stand_punch' in game.sprites {
				game.sprites['player_stand_punch'].draw()
			}
		}
		.sit_punch {
			if 'player_sit_punch' in game.sprites {
				game.sprites['player_sit_punch'].draw()
			}
		}
		.stand_kick {
			if 'player_stand_kick' in game.sprites {
				game.sprites['player_stand_kick'].draw()
			}
		}
		.sit_kick {
			if 'player_sit_kick' in game.sprites {
				game.sprites['player_sit_kick'].draw()
			}
		}
		.high_kick {
			if 'player_high_kick' in game.sprites {
				game.sprites['player_high_kick'].draw()
			}
		}
		.smile {
			if 'player_smile' in game.sprites {
				game.sprites['player_smile'].draw()
			}
		}
		.very_dead {
			if 'player_dead' in game.sprites {
				game.sprites['player_dead'].draw()
			}
		}
		.dead {
			if 'player_dead' in game.sprites {
				if game.sprites['player_dead'].play() {
					if 'feet_sound' in game.sounds {
						r.play_sound(game.sounds['feet_sound'])
					}
					p.kuyakoy += 1
					if p.kuyakoy == 3 {
						p.set_movement(.very_dead)
						game.villain_end_state = end_state_villain_end
					}
				}
			}
		}
		else {
			if 'player_normal' in game.sprites {
				game.sprites['player_normal'].draw_by_index(0)
			}
		}
	}

	if p.show_hit && 'hit' in game.sprites {
		game.sprites['hit'].draw()
	}
}

// 计算玩家攻击框 (按当前动作选用对应 CollisionInfo)
fn player_attack_box(p Player, ci CollisionInfo) (i16, i16, i16, i16) {
	mut px := p.x
	if !p.is_flipped {
		px += ci.x1
	}
	py := p.y + ci.y
	return px, py, i16(ci.width), i16(ci.height)
}

// AABB overlap 判断
fn aabb_overlap(ax i16, ay i16, aw i16, ah i16, bx i16, by i16, bw i16, bh i16) bool {
	if ax + aw - 1 < bx {
		return false
	}
	if bx + bw - 1 < ax {
		return false
	}
	if ay + ah - 1 < by {
		return false
	}
	if by + bh - 1 < ay {
		return false
	}
	return true
}

// 触发攻击: 命中时震动 + 加分 + 扣血 + 播放音效
pub fn (mut p Player) attack(attack_move PlayerMove) {
	p.input_disabled = true
	p.can_attack = false
	p.set_movement(attack_move)

	mut score_add := u32(100)
	mut ci := ci_stand_punch
	match attack_move {
		.sit_punch { ci = ci_sit_punch }
		.stand_kick { ci = ci_stand_kick }
		.sit_kick { ci = ci_sit_kick }
		.high_kick { ci = ci_high_kick; score_add = 200 }
		.up, .coming_down { ci = ci_air; score_add = 300 }
		else { ci = ci_stand_punch }
	}

	px, py, pw, ph := player_attack_box(p, ci)
	vx, vy, vw, vh := villain_hitbox()
	if aabb_overlap(px, py, pw, ph, vx, vy, vw, vh) {
		if 'collided' in game.sounds {
			r.play_sound(game.sounds['collided'])
		}
		if 'hit' in game.sprites {
			game.sprites['hit'].x = int(px)
			game.sprites['hit'].y = int(py)
		}
		game.halt_time = 0
		game.pause_movement = true
		game.score += score_add
		p.show_hit = true
	} else {
		if 'attack' in game.sounds {
			r.play_sound(game.sounds['attack'])
		}
	}
}

// 飞行踢 (跳跃中按 S 触发)
pub fn (mut p Player) flying_kick() {
	if p.is_flying_kick {
		return
	}
	if p.current_movement != .up && p.current_movement != .coming_down {
		return
	}
	if p.y > (player_jump_height + 24) {
		return
	}
	if !p.can_flying_kick {
		return
	}
	if game.pause_movement || game.show_villain_hit {
		return
	}
	if !r.is_key_down(int(r.KeyboardKey.key_s)) && !r.is_key_down(int(r.KeyboardKey.key_k))
		&& !r.is_key_down(int(r.KeyboardKey.key_down)) {
		return
	}
	p.is_flying_kick = true
	p.halt_time_jump = 0
	p.can_flying_kick = false
	// 飞行踢在空中命中
	px, py, pw, ph := player_attack_box(p, ci_air)
	vx, vy, vw, vh := villain_hitbox()
	if aabb_overlap(px, py, pw, ph, vx, vy, vw, vh) {
		if 'collided' in game.sounds {
			r.play_sound(game.sounds['collided'])
		}
		game.score += 300
		p.show_hit = true
		game.halt_time = 0
		game.pause_movement = true
	}
}

// 读取键盘输入
pub fn (mut p Player) handle_keys() {
	if game.state != .game {
		return
	}
	if game.pause_movement || game.show_villain_hit {
		// 受击硬直期间, 只允许飞行踢
		p.flying_kick()
		return
	}
	if p.input_disabled {
		// 攻击动画/跳跃期间, 仍允许飞行踢
		p.flying_kick()
		return
	}

	w_half := i16(game_width / 2)
	mut moved := false
	// 移动 / 蹲
	if r.is_key_down(int(r.KeyboardKey.key_left)) {
		if p.x > stage_boundary {
			p.set_movement(.left)
			p.x -= player_speed
		} else {
			p.set_movement(.idle)
		}
		moved = true
	} else if r.is_key_down(int(r.KeyboardKey.key_right)) {
		if p.x < (i16(game_width) - stage_boundary - w_half) {
			p.set_movement(.right)
			p.x += player_speed
		} else {
			p.set_movement(.idle_2)
		}
		moved = true
	} else if r.is_key_down(int(r.KeyboardKey.key_down)) {
		p.set_movement(.down)
		moved = true
	}
	if !moved {
		if p.current_movement == .left || p.current_movement == .right
			|| p.current_movement == .idle_2 || p.current_movement == .down {
			p.set_movement(.idle)
		}
	}

	// 跳跃
	if r.is_key_pressed(int(r.KeyboardKey.key_up)) {
		p.jump_towards = player_jump_towards_none
		if r.is_key_down(int(r.KeyboardKey.key_left)) {
			p.jump_towards = player_jump_towards_left
		}
		if r.is_key_down(int(r.KeyboardKey.key_right)) {
			p.jump_towards = player_jump_towards_right
		}
		p.set_movement(.up)
		p.input_disabled = true
		p.acceleration_speed = player_jump_accel
	}

	// 出拳 (A 或 J)
	if p.can_attack && (r.is_key_pressed(int(r.KeyboardKey.key_a))
		|| r.is_key_pressed(int(r.KeyboardKey.key_j))) {
		mut move := PlayerMove.stand_punch
		if r.is_key_down(int(r.KeyboardKey.key_down)) {
			move = .sit_punch
		}
		p.attack(move)
	}

	// 踢腿 (S 或 K), 带左右方向键时为高位踢
	if p.can_attack && (r.is_key_pressed(int(r.KeyboardKey.key_s))
		|| r.is_key_pressed(int(r.KeyboardKey.key_k))) {
		mut move := PlayerMove.stand_kick
		sideways := r.is_key_down(int(r.KeyboardKey.key_left))
			|| r.is_key_down(int(r.KeyboardKey.key_right))
		if sideways {
			move = .high_kick
		} else if r.is_key_down(int(r.KeyboardKey.key_down)) {
			move = .sit_kick
		}
		p.attack(move)
	}

	// A/S 松开: 重新启用 attack
	if (r.is_key_released(int(r.KeyboardKey.key_a)) || r.is_key_released(int(r.KeyboardKey.key_j))
		|| r.is_key_released(int(r.KeyboardKey.key_s)) || r.is_key_released(int(r.KeyboardKey.key_k)))
		&& !p.activate_attack && !p.show_hit {
		p.activate_attack = true
		p.activate_time = 0
	}
}

// 处理跳跃物理
pub fn (mut p Player) handle_jump() {
	if p.current_movement != .up && p.current_movement != .coming_down {
		return
	}
	if game.show_villain_hit || p.health == 0 {
		return
	}
	p.jump_frames_counter += 1
	denom := if p.acceleration_speed > 0 { int(p.acceleration_speed) } else { 1 }
	if p.jump_frames_counter < (target_fps / denom) {
		return
	}
	p.jump_frames_counter = 0

	w_half := i16(game_width / 2)
	// 跳跃中左右摆动
	if p.jump_towards == player_jump_towards_right {
		if p.x < (i16(game_width) - stage_boundary - w_half) {
			p.x += player_jump_speed
		} else {
			p.x = i16(game_width) - stage_boundary - w_half
			p.jump_towards = player_jump_towards_left
		}
	} else if p.jump_towards == player_jump_towards_left {
		if p.x > stage_boundary {
			p.x -= player_jump_speed
		} else {
			p.x = stage_boundary
			p.jump_towards = player_jump_towards_right
		}
	}

	if p.current_movement == .up {
		if p.y > player_jump_height {
			if p.acceleration_speed > 1 {
				p.acceleration_speed -= 1
			}
			p.y -= player_jump_speed
		} else {
			p.set_movement(.coming_down)
		}
	} else {
		if p.y < player_default_y {
			if p.acceleration_speed < player_jump_accel {
				p.acceleration_speed += 1
			}
			p.y += player_jump_speed
		} else {
			p.y = player_default_y
			p.set_movement(.idle)
			p.is_flying_kick = false
			p.input_disabled = false
			p.can_flying_kick = true
		}
	}
}

// 每帧推进 halt_time / halt_time_jump / activate_attack 等计时 (由 game.v 调用)
pub fn (mut p Player) tick_halts() {
	if p.input_disabled && p.current_movement != .up && p.current_movement != .coming_down
		&& !game.show_villain_hit {
		p.halt_time += 1
		if p.halt_time == 3 {
			p.input_disabled = false
			p.halt_time = 0
			p.show_hit = false
			p.activate_attack = true
			p.activate_time = 0
			if p.last_movement == .down && r.is_key_down(int(r.KeyboardKey.key_down)) {
				p.set_movement(.down)
			} else {
				p.set_movement(.idle)
			}
		}
	}
	if p.input_disabled && p.is_flying_kick && !game.show_villain_hit {
		p.halt_time_jump += 1
		if p.halt_time_jump == 2 {
			p.halt_time_jump = 0
			p.is_flying_kick = false
		}
	}
	if p.activate_attack {
		p.activate_time += 1
		if p.activate_time == player_can_attack_time {
			p.activate_time = 0
			p.can_attack = true
			p.activate_attack = false
		}
	}
}

// 与 villain 镜像翻转 (每帧 game.v 调用)
pub fn (mut p Player) face_villain() {
	if game.villain_end_state >= end_state_villain_lie_down {
		return
	}
	if game.villain_x < p.x && !p.is_flipped && !p.is_flying_kick {
		p.flip_all_sprites()
	}
	if p.x < game.villain_x && p.is_flipped && !p.is_flying_kick {
		p.flip_all_sprites()
	}
}