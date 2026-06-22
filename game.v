// =============================================================================
//  game.v - 全局游戏状态与初始化
// =============================================================================
//
//  Game 结构体集中持有所有运行时数据:
//    - 相机 (第一人称, 由 raylib 控制移动 / 转向)
//    - 玩家 (血量、弹药、武器状态)
//    - 敌人列表 (AI + 渲染 + 命中检测)
//    - 当前关卡 (迷宫几何 + 像素数据 + 模型)
//    - 全局 HUD 计数 (击杀数、当前关卡)
//
//  初始化顺序 (init_game):
//    1. 创建玩家 (满血满弹药, 默认武器为手枪)
//    2. 加载关卡 1 并把玩家放置在关卡出生点
//    3. 在关卡中预定的几个出生点放置敌人
//
//  主循环由 main.v 驱动:
//    每帧调用 update_game (处理输入、AI、开火、物理)
//             和 draw_game  (3D 渲染 + HUD)
// =============================================================================

module main

import raylib as r

pub enum GameState {
	playing
	level_transition
	dead
	won
}

pub struct Game {
pub mut:
	camera            r.Camera
	player            Player
	enemies           []Enemy
	level             Level
	current_level_idx int
	state             GameState
	state_timer       f32   // 用于关卡过渡、死亡动画计时
	kills_total       int
	level_kills       int   // 本关已击杀
	hits_display      []HitMarker
}

// HitMarker - 击中敌人时的短暂视觉标记 (屏幕中心的红点 + 朝向被击中方向的箭头)
pub struct HitMarker {
pub mut:
	angle    f32   // 与视线的偏角 (用于绘制屏幕中央的指示)
	life     f32   // 剩余显示时间
	is_kill  bool  // 是否击杀
	pos_3d   r.Vector3 // 击中点 (可选, 用于在 3D 中绘制小火花)
}

// 初始化整个游戏 (在 main 中只调用一次)
pub fn (mut game Game) init() {
	game.player = new_player()
	game.camera = new_camera()
	game.current_level_idx = 0
	game.kills_total = 0
	game.level_kills = 0
	game.state = .playing
	game.state_timer = 0
	game.load_level(0)
}

// 加载第 idx 关, 同时把玩家放到出生点、布置敌人、卸载旧关卡资源
pub fn (mut game Game) load_level(idx int) {
	// 先释放上一关的资源
	if game.level.is_loaded() {
		game.level.unload()
	}

	level_def := level_definitions()[idx]
	game.level = new_level_from_def(level_def)
	game.current_level_idx = idx

	// 重置玩家状态
	game.player.hp = game.player.max_hp
	game.player.ammo = game.player.max_ammo
	game.player.pos = game.level.player_spawn
	game.camera.position = game.level.player_spawn
	// 朝向关卡中心 (大致)
	target := r.Vector3{
		x: game.level.player_spawn.x
		y: 0.4
		z: game.level.player_spawn.z - 1.0
	}
	game.camera.target = target
	game.level_kills = 0

	// 生成敌人
	game.enemies = []
	for spawn_pos in game.level.enemy_spawns {
		game.enemies << new_enemy(spawn_pos)
	}

	game.state = .level_transition
	game.state_timer = 0
}

// 释放所有关卡和游戏资源
pub fn (mut game Game) shutdown() {
	if game.level.is_loaded() {
		game.level.unload()
	}
}