// =============================================================================
//  game.v - 全局常量 + Game 结构体 + 资源加载 + 主循环钩子
// =============================================================================
//
//  所有 module main 文件共享一个全局 game 实例:
//    - 全局常量: 屏幕尺寸 / 游戏尺寸 / 边界 / 血量 默认值
//    - GameState 枚举: title / view / game / game_over
//    - VillainType: 0=wang 1=tao 2=chen 3=lang 4=mu (索引到 villain_*_normal 精灵)
//    - Game 结构持有: 玩家 / 对手状态 / 资源 map / 得分 / 关卡号
//    - end_state / villain_end_state 是显式 int 常量, 对齐 Zig 原版
//
//  主循环在 main.v 调用 game.update() 和 game.render(), 这里只放数据和状态机.
// =============================================================================

module main

import raylib as r
import rand

// ===== 全局常量 =====
pub const game_width       = 256
pub const game_height      = 240
pub const screen_width     = 1024
pub const screen_height    = 768
pub const stage_boundary   = i16(15)
pub const default_health   = u8(9)
pub const low_health       = u8(4)
pub const frame_speed      = 5
pub const version_str      = '0.1.0'

// ===== 枚举 =====
pub enum GameState {
	title
	view
	game
}

// ===== EndState (玩家击败对手后的连招演出) =====
pub const end_state_start         = 0
pub const end_state_play_sound    = 1
pub const end_state_showtime      = 2
pub const end_state_showtime_hk1  = 3
pub const end_state_showtime_lk1  = 4
pub const end_state_showtime_lk2  = 5
pub const end_state_showtime_hk2  = 6
pub const end_state_showtime_p    = 7
pub const end_state_smile         = 8
pub const end_state_count_life    = 9
pub const end_state_end           = 10
pub const end_state_game_over     = 11

// ===== VillainEndState (玩家被击败后) =====
pub const end_state_villain_start     = 0
pub const end_state_villain_lie_down  = 1
pub const end_state_villain_move_feet = 2
pub const end_state_villain_end       = 3
pub const end_state_villain_game_over = 4

// ===== VillainAction =====
pub enum VillainAction {
	idle
	kick
	other
	dead
	pause
}

// ===== VillainMoveState (AI 状态机) =====
pub enum VillainMoveState {
	follow_player
	forward_with_attack
	running_left
	running_right
}

// ===== VillainType (0..4 对应 wang/tao/chen/lang/mu) =====
pub enum VillainType {
	wang
	tao
	chen
	lang
	mu
}

// 5 个对手的精灵名前缀
pub const villain_names = ['wang', 'tao', 'chen', 'lang', 'mu']
pub const max_stages    = 5

// Villain 配置: 每个对手的 (受击框, 踢攻击框, 其他攻击框)
pub struct VillainCollisionSet {
pub:
	body   CollisionInfo
	kick   CollisionInfo
	other  CollisionInfo
}

// 与 Zig 原版 collisionsInfo / collisionsKickInfo / collisionsOtherInfo 一一对应
pub const villain_collisions = [
	// wang (index 0)
	VillainCollisionSet{
		body:  CollisionInfo{ x1: 5,  x2: 6,  y: 8, width: 16, height: 32, minus_x_kick: 11 }
		kick:  CollisionInfo{ x1: 0,  x2: 44, y: 20, width: 6,  height: 4,  minus_x_kick: 0 }
		other: CollisionInfo{ x1: 0,  x2: 47, y: 26, width: 3,  height: 2,  minus_x_kick: 0 }
	},
	// tao (1)
	VillainCollisionSet{
		body:  CollisionInfo{ x1: 7,  x2: 4,  y: 8, width: 5,  height: 32, minus_x_kick: 12 }
		kick:  CollisionInfo{ x1: 0,  x2: 33, y: 20, width: 6,  height: 4,  minus_x_kick: 0 }
		other: CollisionInfo{ x1: 7,  x2: 29, y: 15, width: 3,  height: 2,  minus_x_kick: 0 }
	},
	// chen (2)
	VillainCollisionSet{
		body:  CollisionInfo{ x1: 9,  x2: 7,  y: 8, width: 16, height: 32, minus_x_kick: 8 }
		kick:  CollisionInfo{ x1: 0,  x2: 35, y: 13, width: 5,  height: 2,  minus_x_kick: 0 }
		other: CollisionInfo{ x1: 0,  x2: 37, y: 19, width: 3,  height: 3,  minus_x_kick: 0 }
	},
	// lang (3)
	VillainCollisionSet{
		body:  CollisionInfo{ x1: 7,  x2: 4,  y: 9, width: 9,  height: 31, minus_x_kick: 7 }
		kick:  CollisionInfo{ x1: 0,  x2: 25, y: 8,  width: 4,  height: 6,  minus_x_kick: 0 }
		other: CollisionInfo{ x1: 0,  x2: 23, y: 36, width: 6,  height: 3,  minus_x_kick: 0 }
	},
	// mu (4)
	VillainCollisionSet{
		body:  CollisionInfo{ x1: 12, x2: 2,  y: 8, width: 17, height: 32, minus_x_kick: 6 }
		kick:  CollisionInfo{ x1: 0,  x2: 33, y: 26, width: 6,  height: 4,  minus_x_kick: 0 }
		other: CollisionInfo{ x1: 7,  x2: 29, y: 15, width: 3,  height: 3,  minus_x_kick: 0 }
	},
]

// ===== Game 结构体 =====
pub struct Game {
pub mut:
	state                GameState = .title
	stage                int       = 1     // 1..5
	score                u32
	player               Player

	sprites              map[string]Sprite
	sounds               map[string]r.Sound
	music                r.Music
	target               r.RenderTexture2D

	// game stage 状态
	villain_x            i16 = 147
	villain_y            i16 = 152
	villain_health       u8  = default_health
	is_villain_flipped   bool
	villain_current_move VillainAction = .idle
	villain_move_state   VillainMoveState = .follow_player
	villain_random_attack int
	show_villain_hit     bool
	spinning_chain_x     i16 = 140
	spinning_chain_y     i16 = 155
	halt_time            u8
	halt_time_hit        u8
	max_halt_time        u8 = 2
	pause_movement       bool
	run_counter          u8
	villain_movement_counter u8

	// end state
	end_state            int = end_state_start
	villain_end_state    int = end_state_villain_start

	// title / view stage
	blink_enter          bool
	blink_count          int
	blink_frames_counter int
	can_enter            bool = true

	// 计时
	time_counter         u16
	time_seconds         u16
}

// 全局游戏实例 (所有 module main 文件共享)
__global (
	game Game
)

// ===== 初始化 =====
pub fn game_init() {
	game.player = new_player()
	game.state = .title
	game.stage = 1
	game.score = 0
	game.blink_enter = false
	game.blink_count = 0
	game.can_enter = true
	game.end_state = end_state_start
	game.villain_end_state = end_state_villain_start
}

// ===== 关闭 =====
pub fn game_shutdown() {
	for _, mut s in game.sprites {
		s.unload()
	}
	if 'attack' in game.sounds {
		r.unload_sound(game.sounds['attack'])
	}
	r.unload_music_stream(game.music)
	r.unload_render_texture(game.target)
}

// ===== 加载资源 =====
pub fn game_load_assets() {
	game.sprites = map[string]Sprite{}
	for id, path in sprite_files {
		tc := if id in sprite_tile_counts { sprite_tile_counts[id] } else { 1 }
		fs := if id == 'spinning_chain' { 6 } else { 5 }
		game.sprites[id] = new_sprite(path, tc, fs)
	}
	// Chen 的 normal 帧速更慢
	for name in ['wang_normal', 'tao_normal', 'lang_normal', 'mu_normal'] {
		if name in game.sprites {
			game.sprites[name].frame_speed = 3
		}
	}

	game.sounds = {
		'attack':       r.load_sound('assets/sounds/attack.wav')
		'collided':     r.load_sound('assets/sounds/collided.wav')
		'collided2':    r.load_sound('assets/sounds/collided2.wav')
		'counting':     r.load_sound('assets/sounds/counting.wav')
		'dead':         r.load_sound('assets/sounds/dead.wav')
		'feet_sound':   r.load_sound('assets/sounds/feet_sound.wav')
		'game_over':    r.load_sound('assets/sounds/game_over.wav')
		'low_health':   r.load_sound('assets/sounds/low_health.wav')
		'win':          r.load_sound('assets/sounds/win.wav')
	}

	game.music = r.load_music_stream('assets/sounds/bg.mp3')
	game.target = r.load_render_texture(game_width, game_height)
}

// ===== 标题屏 sprite 布局 =====
pub fn title_init() {
	if 'konami_logo' in game.sprites {
		kl := game.sprites['konami_logo']
		w := kl.texture.width
		game.sprites['konami_logo'].x = (game_width / 2) - (w / 2)
		game.sprites['konami_logo'].y = 35
	}
	if 'title' in game.sprites {
		t := game.sprites['title']
		w := t.texture.width
		game.sprites['title'].x = (game_width / 2) - (w / 2)
		game.sprites['title'].y = 85
	}
}

// ===== view stage 布局 (显示 STAGE N) =====
pub fn view_init() {
	// 不需要预置 sprite, view 屏用 ui.v 文字渲染
}

// ===== game stage 布局 =====
pub fn game_init_layout() {
	if 'life' in game.sprites {
		game.sprites['life'].x = 168
		game.sprites['life'].y = 48
	}
	if 'health_hud' in game.sprites {
		hh := game.sprites['health_hud']
		w := hh.texture.width
		game.sprites['health_hud'].x = (game_width / 2) - (w / 2)
		game.sprites['health_hud'].y = 208
	}
	if 'health_green' in game.sprites {
		game.sprites['health_green'].y = 210
	}
	if 'health_red' in game.sprites {
		game.sprites['health_red'].y = 210
		game.sprites['health_red'].frame_speed = 6
	}
	reset_game_stage()
}

// ===== 重置当前关卡 (新一关开始) =====
pub fn reset_game_stage() {
	game.villain_current_move = .idle
	game.villain_health = default_health
	game.pause_movement = false
	game.villain_movement_counter = 0
	game.villain_x = 147
	game.villain_y = 152
	game.show_villain_hit = false
	game.villain_end_state = end_state_villain_start
	game.end_state = end_state_start
	game.spinning_chain_x = 140
	game.spinning_chain_y = 155
	game.halt_time = 0
	game.halt_time_hit = 0
	game.max_halt_time = 2
	game.villain_move_state = .follow_player
	game.run_counter = 0
	game.player.clear()
	// 翻转回正面
	if game.is_villain_flipped {
		flip_villain_sprites()
	}
}

// ===== 对手当前受击框 =====
pub fn villain_hitbox() (i16, i16, i16, i16) {
	set := villain_collisions[game.stage - 1]
	ci := set.body
	mut vx := game.villain_x - ci.minus_x_kick
	if game.is_villain_flipped {
		vx += ci.x2
	} else {
		vx += ci.x1
	}
	vy := game.villain_y + ci.y
	return vx, vy, i16(ci.width), i16(ci.height)
}

// ===== 对手攻击框 (用于判定是否击中玩家) =====
pub fn villain_attack_box() (i16, i16, i16, i16) {
	set := villain_collisions[game.stage - 1]
	mut ci := set.body
	match game.villain_current_move {
		.kick { ci = set.kick }
		.other { ci = set.other }
		else { return 0, 0, 0, 0 }  // 不会击中
	}
	mut vx := game.villain_x - ci.minus_x_kick
	if game.is_villain_flipped {
		vx += ci.x2
	} else {
		vx += ci.x1
	}
	vy := game.villain_y + ci.y
	return vx, vy, i16(ci.width), i16(ci.height)
}

// ===== 翻转对手所有 sprite =====
pub fn flip_villain_sprites() {
	name := villain_names[game.stage - 1]
	for suffix in ['normal', 'kick', 'other', 'dead', 'hit'] {
		id := '${name}_${suffix}'
		if id in game.sprites {
			game.sprites[id].flip_horizontal()
		}
	}
	if 'spinning_chain' in game.sprites {
		game.sprites['spinning_chain'].flip_horizontal()
	}
	game.is_villain_flipped = !game.is_villain_flipped
	if game.is_villain_flipped {
		game.spinning_chain_x -= 19
	} else {
		game.spinning_chain_x += 19
	}
}

// ===== 对手 x 坐标修改 =====
pub fn villain_modify_x(amount i16, is_add bool) {
	if is_add {
		game.villain_x += amount
	} else {
		game.villain_x -= amount
	}
	if game.stage == 3 {
		if is_add {
			game.spinning_chain_x += amount
		} else {
			game.spinning_chain_x -= amount
		}
	}
}

// ===== 检查对手攻击是否打到玩家 (true 表示打中) =====
pub fn check_villain_attack_on_player() bool {
	vx, vy, vw, vh := villain_attack_box()
	if vw == 0 || vh == 0 {
		return false
	}
	ci := player_collision_info
	mut px := game.player.x
	if game.player.is_flipped {
		px += ci.x2
	} else {
		px += ci.x1
	}
	py := game.player.y + ci.y
	lower_px2 := px + i16(ci.width) - 1
	lower_py2 := py + i16(ci.height) - 1
	lower_vx2 := vx + vw - 1
	lower_vy2 := vy + vh - 1

	if lower_px2 < vx || game.player.x > lower_vx2 || lower_py2 < vy || game.player.y > lower_vy2 {
		return false
	}
	// 命中
	if 'collided2' in game.sounds {
		r.play_sound(game.sounds['collided2'])
	}
	name := villain_names[game.stage - 1]
	hit_id := '${name}_hit'
	if hit_id in game.sprites {
		game.sprites[hit_id].x = int(vx)
		game.sprites[hit_id].y = int(vy)
	}
	game.show_villain_hit = true
	game.halt_time_hit = 0
	game.player.old_x = game.player.x
	game.player.shake = true
	game.player.add_x = true
	if game.player.health > 0 {
		game.player.health -= 1
	}
	if game.player.health == low_health {
		if 'low_health' in game.sounds {
			r.play_sound(game.sounds['low_health'])
		}
	}
	if !game.is_villain_flipped {
		villain_modify_x(1, true)
	} else {
		villain_modify_x(1, false)
	}
	return true
}

// ===== 对手重置为 idle (受击后 / 攻击动画结束) =====
pub fn villain_reset_move() {
	game.villain_current_move = .idle
	game.villain_move_state = .follow_player
	name := villain_names[game.stage - 1]
	suffix := if game.villain_random_attack == 0 { 'kick' } else { 'other' }
	id := '${name}_${suffix}'
	if id in game.sprites {
		game.sprites[id].reset_current_frame()
	}
}

// ===== 取得 0..n 随机数 (用于 AI 选攻击类型) =====
pub fn rand_int(max int) int {
	if max <= 0 {
		return 0
	}
	return rand.intn(max) or { 0 }
}