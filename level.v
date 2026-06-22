// =============================================================================
//  level.v - 关卡加载与程序生成
// =============================================================================
//
//  关卡用 PNG 表示 (与 raylib_fps_in_v 保持兼容):
//    - 白色像素  -> 墙 (1x1x1 立方体)
//    - 非白像素  -> 可通行区域
//
//  关卡定义 (LevelDef):
//    - image_path: 如果非空, 从该路径加载 PNG
//    - width/height: 仅用于程序生成关卡
//    - player_spawn / enemy_spawns: 关卡内的出生点 (世界坐标)
//    - name: 关卡显示名
//
//  关卡加载流程 (new_level_from_def):
//    1. 加载或生成 Image
//    2. 用 Image 生成 3D 立方体网格并加载为 Model
//    3. 加载像素颜色数组供碰撞检测
//
//  关卡世界坐标: 地图左下角对齐到 (-16, 0, -8), 与原 FPS 示例保持一致
//
//  is_walkable / collide_with_walls:
//    把圆形 / 矩形投影到 XZ 平面, 遍历迷宫像素检查白墙碰撞
//    (复用 raylib_fps_in_v 的思路, 但只扫描玩家附近格以提速)
// =============================================================================

module main

import raylib as r
import os
import math

pub struct LevelDef {
pub:
	name           string
	image_path     string   // 为空则程序生成
	width          int
	height         int
	player_spawn   r.Vector3
	enemy_spawns   []r.Vector3
}

pub struct Level {
pub mut:
	image        r.Image
	pixels       &r.Color = unsafe { nil }
	width        int
	height       int
	texture      r.Texture2D     // 贴图图集
	model        r.Model
	loaded       bool
	map_position r.Vector3
	player_spawn r.Vector3
	enemy_spawns []r.Vector3
	name         string
}

pub fn (l Level) is_loaded() bool {
	return l.loaded
}

pub fn (mut l Level) unload() {
	if !l.loaded {
		return
	}
	unsafe {
		r.unload_image_colors(l.pixels)
	}
	r.unload_texture(l.texture)
	r.unload_model(l.model)
	r.unload_image(l.image)
	l.loaded = false
}

// 所有关卡的定义. 顺序: 第 1 关 -> 第 2 关 -> 第 3 关 -> 循环
pub fn level_definitions() []LevelDef {
	return [
		// 第 1 关: 复用 raylib_fps_in_v 的原版迷宫 (从 PNG 加载)
		LevelDef{
			name:         'E1M1: Hangar'
			image_path:   os.resource_abs_path('assets/level1.png')
			player_spawn: r.Vector3{-15.5, 0.4, 6.5}
			enemy_spawns: [
				r.Vector3{-12.0, 0.4, 0.0},
				r.Vector3{-6.0, 0.4, -4.0},
				r.Vector3{2.0, 0.4, 2.0},
				r.Vector3{8.0, 0.4, -6.0},
				r.Vector3{12.0, 0.4, 4.0},
			]
		},
		// 第 2 关: 程序生成的 "竞技场"
		LevelDef{
			name:         'E1M2: Arena'
			image_path:   ''
			width:        24
			height:       24
			player_spawn: r.Vector3{-11.5, 0.4, 11.5}
			enemy_spawns: [
				r.Vector3{0.0, 0.4, 0.0},
				r.Vector3{6.0, 0.4, -6.0},
				r.Vector3{-6.0, 0.4, -6.0},
				r.Vector3{6.0, 0.4, 6.0},
				r.Vector3{-6.0, 0.4, 6.0},
				r.Vector3{0.0, 0.4, -10.0},
				r.Vector3{10.0, 0.4, 0.0},
				r.Vector3{-10.0, 0.4, 0.0},
			]
		},
		// 第 3 关: 程序生成的 "迷宫" (更多隔墙)
		LevelDef{
			name:         'E1M3: Catacombs'
			image_path:   ''
			width:        32
			height:       32
			player_spawn: r.Vector3{-15.5, 0.4, 15.5}
			enemy_spawns: [
				r.Vector3{-12.0, 0.4, 0.0},
				r.Vector3{-4.0, 0.4, 8.0},
				r.Vector3{4.0, 0.4, -4.0},
				r.Vector3{10.0, 0.4, 12.0},
				r.Vector3{-10.0, 0.4, -10.0},
				r.Vector3{0.0, 0.4, 0.0},
				r.Vector3{8.0, 0.4, -10.0},
				r.Vector3{-8.0, 0.4, 10.0},
				r.Vector3{12.0, 0.4, -2.0},
				r.Vector3{-12.0, 0.4, -8.0},
			]
		},
	]
}

// 根据关卡定义创建一个 Level: 加载图片 / 生成图片 -> 加载模型 -> 缓存像素
pub fn new_level_from_def(def LevelDef) Level {
	mut img := r.Image{}
	if def.image_path.len > 0 {
		img = r.load_image(def.image_path)
	} else {
		img = generate_procedural_map(def.width, def.height)
	}

	mut lvl := Level{
		image:        img
		width:        img.width
		height:       img.height
		texture:      r.load_texture(os.resource_abs_path('assets/wall_atlas.png'))
		map_position: r.Vector3{-16.0, 0.0, -8.0}
		player_spawn: def.player_spawn
		enemy_spawns: def.enemy_spawns
		name:         def.name
	}
	// 注意: 这里不要 unload_image(img) —— Level.unload 会统一释放
	lvl.pixels = r.load_image_colors(img)

	// 用 Image 生成 3D 立方体网格并加载为 Model
	mesh := r.gen_mesh_cubicmap(img, r.Vector3{1.0, 1.0, 1.0})
	lvl.model = r.load_model_from_mesh(mesh)
	unsafe {
		lvl.model.materials[0].maps[r.MaterialMapIndex.material_map_albedo].texture = lvl.texture
	}

	lvl.loaded = true
	return lvl
}

// 程序生成关卡地图 (从空白 + 边界墙开始, 撒几个隔墙)
// 生成策略: 用一个位图, 边界为白墙, 内部随机加几条横/竖墙, 并用生成时刻作
// 为随机种子, 保证每次进入关卡布局一致.
fn generate_procedural_map(width int, height int) r.Image {
	mut img := r.gen_image_color(width, height, r.Color{50, 50, 50, 255})
	// 边界: 上下/左右各加一圈白墙
	r.image_draw_rectangle(&img, 0, 0, width, 1, r.Color{255, 255, 255, 255})
	r.image_draw_rectangle(&img, 0, height - 1, width, 1, r.Color{255, 255, 255, 255})
	r.image_draw_rectangle(&img, 0, 0, 1, height, r.Color{255, 255, 255, 255})
	r.image_draw_rectangle(&img, width - 1, 0, 1, height, r.Color{255, 255, 255, 255})

	// 用基于尺寸的固定种子, 保证每次进入关卡布局一致 (DOOM 风格)
	seed_val := u32(width * 31 + height * 17 + 7)
	r.set_random_seed(seed_val)

	// 在内部随机画几道隔墙, 留出走廊
	for _ in 0 .. width / 4 {
		if r.get_random_value(0, 1) == 0 {
			// 横向墙 (隔几格留一格空当作为走廊)
			y := r.get_random_value(2, height - 3)
			x0 := r.get_random_value(2, width / 3)
			mut x := x0
			for x < width - 2 {
				r.image_draw_rectangle(&img, x, y, 1, 1, r.Color{255, 255, 255, 255})
				// 隔 2 格空一格 (走廊)
				x += 3
			}
		} else {
			// 纵向墙
			x := r.get_random_value(2, width - 3)
			y0 := r.get_random_value(2, height / 3)
			mut y := y0
			for y < height - 2 {
				r.image_draw_rectangle(&img, x, y, 1, 1, r.Color{255, 255, 255, 255})
				y += 3
			}
		}
	}

	// 在 4 个角落清出开放空间 (出生点保护区)
	corners := [
		[2, 2],
		[width - 3, 2],
		[2, height - 3],
		[width - 3, height - 3],
	]
	for corner in corners {
		cx := corner[0]
		cy := corner[1]
		for dx in -1 .. 2 {
			for dy in -1 .. 2 {
				px := cx + dx
				py := cy + dy
				if px > 0 && py > 0 && px < width - 1 && py < height - 1 {
					r.image_draw_pixel(&img, px, py, r.Color{50, 50, 50, 255})
				}
			}
		}
	}
	return img
}

// (x, z) 是世界坐标, 检查以 (x, z) 为圆心 radius 为半径的圆是否完全在可通行
// 区域. 用于玩家移动碰撞 / 敌人移动碰撞.
pub fn (game &Game) is_walkable(x f32, z f32, radius f32) bool {
	if !game.level.is_loaded() {
		return false
	}
	lvl := game.level
	player_pos := r.Vector2{x, z}
	// 计算覆盖的像素范围 (在玩家附近做局部扫描, 比全图快得多)
	min_x := int(math.max(f32(0), x - radius - lvl.map_position.x + 0.5))
	max_x := int(math.min(f32(lvl.width - 1), x + radius - lvl.map_position.x + 0.5))
	min_y := int(math.max(f32(0), z - radius - lvl.map_position.z + 0.5))
	max_y := int(math.min(f32(lvl.height - 1), z + radius - lvl.map_position.z + 0.5))
	for py in min_y .. max_y + 1 {
		for px in min_x .. max_x + 1 {
			unsafe {
				if lvl.pixels[py * lvl.width + px].r == 255 {
					if r.check_collision_circle_rec(player_pos, radius, r.Rectangle{
						x: lvl.map_position.x - 0.5 + f32(px)
						y: lvl.map_position.z - 0.5 + f32(py)
						width: 1.0
						height: 1.0
					}) {
						return false
					}
				}
			}
		}
	}
	return true
}

// 把一段位移应用到 (x, z) 上, 撞墙时该方向回退. 返回最终坐标.
pub fn (game &Game) move_with_collision(x f32, z f32, dx f32, dz f32, radius f32) (f32, f32) {
	mut nx := x
	mut nz := z
	if game.is_walkable(x + dx, z, radius) {
		nx = x + dx
	}
	if game.is_walkable(nx, z + dz, radius) {
		nz = z + dz
	}
	return nx, nz
}

// 像素颜色助手: 判断 (x, z) 是否在墙内 (用于敌人 AI 避免走出迷宫)
pub fn (game &Game) pixel_is_wall(px int, py int) bool {
	if !game.level.is_loaded() {
		return true
	}
	if px < 0 || py < 0 || px >= game.level.width || py >= game.level.height {
		return true
	}
	unsafe {
		return game.level.pixels[py * game.level.width + px].r == 255
	}
}