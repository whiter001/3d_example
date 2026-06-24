// =============================================================================
//  sprite.v - 精灵帧动画系统
// =============================================================================
//
//  Sprite 结构集中管理一帧多帧的水平切片 PNG:
//    - tile_count 把 texture 横向等分成 N 帧
//    - frame_speed 控制每秒推进多少帧 (default = 5)
//    - play() 推进 current_frame 并绘制, 走到末尾时返回 true
//    - flip_horizontal() 把 frame_rect.width 取负, 整张图左右翻转
//    - reset_current_frame() 回到第 0 帧
//
//  资源 ID 用字符串 key (与 Zig 原版一致), sprite_files 和 sprite_tile_counts
//  是两张查找表, game.v 在 init 时按这两张表批量 LoadTexture.
// =============================================================================

module main

import raylib as r

pub const target_fps = 60
pub const frame_speed_default = 5

// 资源 ID -> PNG 路径 (从 Zig 原版 SpriteImages 数组映射)
pub const sprite_files = {
	'title':              'assets/images/title.png'
	'konami_logo':        'assets/images/konami_logo.png'
	'letters':            'assets/images/letters.png'
	'game_bg':            'assets/images/game_bg.png'
	'player_normal':      'assets/images/player_normal.png'
	'player_down':        'assets/images/player_down.png'
	'player_stand_punch': 'assets/images/player_stand_punch.png'
	'player_sit_punch':   'assets/images/player_sit_punch.png'
	'player_stand_kick':  'assets/images/player_stand_kick.png'
	'player_sit_kick':    'assets/images/player_sit_kick.png'
	'player_high_kick':   'assets/images/player_high_kick.png'
	'player_flying_kick': 'assets/images/player_flying_kick.png'
	'player_smile':       'assets/images/player_smile.png'
	'player_dead':        'assets/images/player_dead.png'
	'life':               'assets/images/life.png'
	'health_hud':         'assets/images/health_hud.png'
	'health_green':       'assets/images/health_green.png'
	'health_red':         'assets/images/health_red.png'
	'wang_normal':        'assets/images/wang_normal.png'
	'wang_kick':          'assets/images/wang_kick.png'
	'wang_other':         'assets/images/wang_other.png'
	'wang_dead':          'assets/images/wang_dead.png'
	'wang_hit':           'assets/images/wang_hit.png'
	'tao_normal':         'assets/images/tao_normal.png'
	'tao_kick':           'assets/images/tao_kick.png'
	'tao_other':          'assets/images/tao_other.png'
	'tao_dead':           'assets/images/tao_dead.png'
	'tao_hit':            'assets/images/tao_hit.png'
	'chen_normal':        'assets/images/chen_normal.png'
	'chen_kick':          'assets/images/chen_kick.png'
	'chen_other':         'assets/images/chen_other.png'
	'chen_dead':          'assets/images/chen_dead.png'
	'chen_hit':           'assets/images/chen_hit.png'
	'lang_normal':        'assets/images/lang_normal.png'
	'lang_kick':          'assets/images/lang_kick.png'
	'lang_other':         'assets/images/lang_other.png'
	'lang_dead':          'assets/images/lang_dead.png'
	'lang_hit':           'assets/images/lang_hit.png'
	'mu_normal':          'assets/images/mu_normal.png'
	'mu_kick':            'assets/images/mu_kick.png'
	'mu_other':           'assets/images/mu_other.png'
	'mu_dead':            'assets/images/mu_dead.png'
	'mu_hit':             'assets/images/mu_hit.png'
	'spinning_chain':     'assets/images/spinning_chain.png'
	'hit':                'assets/images/hit.png'
}

// 资源 ID -> 横向切片数 (1 表示不切)
pub const sprite_tile_counts = {
	'letters':        36
	'player_normal':  2
	'wang_normal':    2
	'tao_normal':     2
	'chen_normal':    4
	'lang_normal':    2
	'mu_normal':      2
	'spinning_chain': 8
	'wang_kick':      2
	'tao_kick':       2
	'chen_kick':      2
	'lang_kick':      2
	'mu_kick':        2
	'wang_other':     2
	'tao_other':      2
	'chen_other':     2
	'lang_other':     2
	'mu_other':       2
	'player_dead':    2
}

pub struct Sprite {
pub mut:
	texture         r.Texture2D
	tile_count      int          // 横向帧数
	x               int
	y               int
	frame_rect      r.Rectangle  // 当前帧的源矩形 (width 为负时表示已翻转)
	frame_speed     int          // 每秒帧数
	current_frame   int
	frames_counter  int
	paused          bool
}

// 加载一个精灵: 从 png 读取 texture, 用 tile_count 切片 (默认 1 = 单帧)
pub fn new_sprite(path string, tile_count int, frame_speed int) Sprite {
	txt := r.load_texture(path)
	tc := if tile_count > 0 { tile_count } else { 1 }
	rect := r.Rectangle{
		x:      0
		y:      0
		width:  f32(txt.width) / f32(tc)
		height: f32(txt.height)
	}
	return Sprite{
		texture:        txt
		tile_count:     tc
		x:              0
		y:              0
		frame_rect:     rect
		frame_speed:    frame_speed
		current_frame:  0
		frames_counter: 0
		paused:         false
	}
}

// 释放 texture
pub fn (mut s Sprite) unload() {
	r.unload_texture(s.texture)
}

// 单帧绘制 (用 frame_rect)
pub fn (s Sprite) draw() {
	pos := r.Vector2{f32(s.x), f32(s.y)}
	r.draw_texture_rec(s.texture, s.frame_rect, pos, r.white)
}

// 按索引绘制单帧 (不改变 current_frame)
pub fn (mut s Sprite) draw_by_index(idx int) {
	if s.tile_count <= 0 {
		s.draw()
		return
	}
	mut copy := s.frame_rect
	copy.x = f32(idx) * f32(s.texture.width) / f32(s.tile_count)
	pos := r.Vector2{f32(s.x), f32(s.y)}
	r.draw_texture_rec(s.texture, copy, pos, r.white)
}

// 推进 1 帧, 同时绘制; 走到末尾返回 true
pub fn (mut s Sprite) play() bool {
	mut is_last := false
	s.frames_counter += 1
	if s.frames_counter >= (target_fps / if s.frame_speed > 0 { s.frame_speed } else { 1 }) {
		s.frames_counter = 0
		if !s.paused {
			s.current_frame += 1
		}
		if s.current_frame > (s.tile_count - 1) {
			s.current_frame = 0
			is_last = true
		}
		s.frame_rect.x = f32(s.current_frame) * f32(s.texture.width) / f32(s.tile_count)
	}
	s.draw()
	return is_last
}

// 水平翻转 (通过把 frame_rect.width 取负)
pub fn (mut s Sprite) flip_horizontal() {
	s.frame_rect.width = -s.frame_rect.width
}

// 重置到第 0 帧
pub fn (mut s Sprite) reset_current_frame() {
	s.current_frame = 0
	s.frames_counter = 0
	s.frame_rect.x = 0
}

// 重新设置切片数 (用于没有在 sprite_tile_counts 中列出的精灵)
pub fn (mut s Sprite) set_tile_count(n int) {
	s.tile_count = if n > 0 { n } else { 1 }
	s.frame_rect = r.Rectangle{
		x:      s.frame_rect.x
		y:      s.frame_rect.y
		width:  f32(s.texture.width) / f32(s.tile_count)
		height: f32(s.texture.height)
	}
}