// =============================================================================
//  main.v - 程序入口与主循环
// =============================================================================
//
//  启动流程:
//    1. raylib 初始化窗口 + 隐藏鼠标 (FPS 风格)
//    2. 创建一个 Game 并 init (加载第 1 关, 放置玩家 + 敌人)
//    3. 进入主循环
//    4. 退出时释放资源
//
//  主循环每帧:
//    1. 计算 dt (上一帧到现在的时间)
//    2. update_game  (玩家输入 / AI / 开火 / 物理 / 关卡过渡)
//    3. draw_game    (3D 渲染 / 武器视图模型 / HUD / 状态覆盖层)
//
//  关卡过渡:
//    玩家消灭一关所有敌人 -> 进入 level_transition 状态, 显示标题, 1.5s 后
//    自动切到下一关 (或胜利).
//
//  死亡:
//    HP 归零 -> 进入 dead 状态, 显示 YOU DIED 提示, 按 R 重启当前关.
// =============================================================================

module main

import raylib as r
import math

const ground_y = f32(0.4)
const jump_speed = f32(4.5)
const gravity = f32(12.0)

fn main() {
	r.set_trace_log_level(int(r.TraceLogLevel.log_error))
	r.init_window(1280, 720, 'raylib_doom - DOOM-style FPS in V')
	r.disable_cursor()
	r.set_target_fps(60)

	mut game := &Game{}
	game.init()

	for !r.window_should_close() {
		dt := r.get_frame_time()
		update_game(mut game, dt)
		draw_game(game)
	}

	game.shutdown()
	r.close_window()
}

// 创建相机 (第一人称, 与 raylib_fps_in_v 相同设定)
fn new_camera() r.Camera {
	return r.Camera{
		position:   r.Vector3{0.2, 0.4, 0.2}
		target:     r.Vector3{0.185, 0.4, 0.0}
		up:         r.Vector3{0.0, 1.0, 0.0}
		fovy:       60.0
		projection: 0 // CAMERA_PERSPECTIVE
	}
}

// 主更新: 处理输入 / 物理 / AI / 关卡过渡
fn update_game(mut game Game, dt f32) {
	match game.state {
		.playing {
			// 由 raylib 处理 WASD / Shift / Ctrl / 鼠标 转向
			// Space 我们自己处理, 实现有重力的跳跃
			old_pos := game.camera.position
			r.update_camera(&game.camera, int(r.CameraMode.camera_first_person))

			// raylib 同时修改了 position 和 target;我们保留它的朝向,
			// 但用自己的碰撞与跳跃物理覆盖位置
			raylib_pos := game.camera.position
			raylib_target := game.camera.target

			// 水平方向碰撞
			new_x, new_z := game.move_with_collision(old_pos.x, old_pos.z,
				raylib_pos.x - old_pos.x, raylib_pos.z - old_pos.z, 0.25)

			// 跳跃 / 重力
			on_ground := game.player.pos.y <= ground_y + 0.01
			if r.is_key_pressed(int(r.KeyboardKey.key_space)) && on_ground {
				game.player.velocity_y = jump_speed
			}
			game.player.velocity_y -= gravity * dt
			mut new_y := old_pos.y + game.player.velocity_y * dt
			if new_y < ground_y {
				new_y = ground_y
				game.player.velocity_y = 0
			}

			game.camera.position = r.Vector3{new_x, new_y, new_z}
			game.player.pos = game.camera.position

			// 让 target 跟随 position 的修正, 保持视线方向稳定
			game.camera.target.x = raylib_target.x + (new_x - raylib_pos.x)
			game.camera.target.y = raylib_target.y + (new_y - raylib_pos.y)
			game.camera.target.z = raylib_target.z + (new_z - raylib_pos.z)

			// 输入: 开火
			if r.is_mouse_button_down(int(r.MouseButton.mouse_button_left)) {
				if game.player.try_fire() {
					perform_player_fire(mut game)
				}
			}

			// 输入: 装弹
			if r.is_key_pressed(int(r.KeyboardKey.key_r)) {
				game.player.try_reload()
			}

			// 更新玩家计时器
			game.player.update(dt, is_player_moving(game))
			game.player.tick_invuln(dt)

			// 更新敌人
			game.update_enemies(dt)

			// 推进击中标记
			for i in 0 .. game.hits_display.len {
				mut h := &game.hits_display[i]
				h.life -= dt * 2.5
			}
			// 清理过期标记
			game.hits_display = game.hits_display.filter(it.life > 0)

			// 更新命中粒子
			game.update_particles(dt)

			// 检查关卡完成
			mut alive := 0
			for e in game.enemies {
				if e.state != .dead && e.state != .dying {
					alive++
				}
			}
			if alive == 0 && game.enemies.len > 0 {
				game.state = .level_transition
				game.state_timer = 0
			}

			// 检查死亡
			if !game.player.is_alive() {
				game.state = .dead
				game.state_timer = 0
			}
		}
		.level_transition {
			game.state_timer += dt
			if game.state_timer > 1.6 {
				next := game.current_level_idx + 1
				if next >= level_definitions().len {
					game.state = .won
					game.state_timer = 0
				} else {
					game.load_level(next)
				}
			}
		}
		.dead {
			game.state_timer += dt
			if r.is_key_pressed(int(r.KeyboardKey.key_r)) {
				game.load_level(game.current_level_idx)
			}
		}
		.won {
			if r.is_key_pressed(int(r.KeyboardKey.key_r)) {
				game.kills_total = 0
				game.load_level(0)
			}
		}
	}
}

// 玩家开火 -> 计算射线 -> 检测命中敌人或墙体
fn perform_player_fire(mut game Game) {
	// 从屏幕中心发射一条射线
	screen_center := r.Vector2{
		x: f32(r.get_screen_width()) / 2.0
		y: f32(r.get_screen_height()) / 2.0
	}
	ray := r.get_screen_to_world_ray(screen_center, game.camera)

	// 遍历敌人, 检查射线与敌人包围盒的交点, 取最近一个
	mut best_dist := f32(math.max_f32)
	mut hit_index := -1
	mut hit_point := r.Vector3{}
	mut hit_normal := r.Vector3{}
	for i in 0 .. game.enemies.len {
		e := game.enemies[i]
		if e.state == .dead || e.state == .dying {
			continue
		}
		// 忽略被墙体遮挡的敌人, 避免穿墙命中
		if !game.has_line_of_sight(game.player.pos, e.pos) {
			continue
		}
		half := e.size / 2.0
		bbox := r.BoundingBox{
			min: r.Vector3{e.pos.x - half, e.pos.y - half, e.pos.z - half}
			max: r.Vector3{e.pos.x + half, e.pos.y + half, e.pos.z + half}
		}
		col := r.get_ray_collision_box(ray, bbox)
		if col.hit && col.distance < best_dist {
			best_dist = col.distance
			hit_index = i
			hit_point = col.point
			hit_normal = col.normal
		}
	}

	if hit_index >= 0 {
		killed := game.enemies[hit_index].take_damage(25)
		if killed {
			game.kills_total++
			game.level_kills++
			// 敌人死亡时产生爆炸粒子
			spawn_death_particles(mut game, game.enemies[hit_index].pos)
		}
		// 添加屏幕上的击中标记
		game.hits_display << HitMarker{
			angle: 0 // 屏幕中央 (射线一定从中心射出)
			life: 1.0
			is_kill: killed
			pos_3d: hit_point
		}

		// 在命中点迸发粒子
		spawn_hit_particles(mut game, hit_point, hit_normal)
	}
}

// 玩家是否在移动 (用于触发武器晃动)
fn is_player_moving(_ Game) bool {
	return r.is_key_down(int(r.KeyboardKey.key_w)) || r.is_key_down(int(r.KeyboardKey.key_a))
		|| r.is_key_down(int(r.KeyboardKey.key_s)) || r.is_key_down(int(r.KeyboardKey.key_d))
}

// 主渲染: 3D 场景 + 武器 + HUD + 状态覆盖
fn draw_game(game &Game) {
	r.begin_drawing()
	{
		r.clear_background(r.Color{20, 20, 30, 255})

		r.begin_mode_3d(game.camera)
		{
			// 绘制迷宫
			if game.level.is_loaded() {
				r.draw_model(game.level.model, game.level.map_position, 1.0, r.white)
			}

			// 绘制敌人 (按状态着色)
			for e in game.enemies {
				if e.state == .dead {
					continue
				}
				if e.state == .dying {
					// 死亡时缩小变暗
					s := e.death_shrink * e.size
					r.draw_cube_v(e.pos, r.Vector3{s, s, s}, r.Color{90, 30, 30, 200})
					continue
				}
				body_col := if e.hit_flash > 0.1 {
					r.Color{255, 255, 255, 255}
				} else if e.state == .attack {
					r.Color{220, 80, 80, 255} // 攻击状态偏红
				} else {
					r.Color{130, 60, 200, 255} // 紫色身体
				}
				r.draw_cube_v(e.pos, r.Vector3{e.size, e.size, e.size}, body_col)
				// 眼睛: 两个朝向玩家方向的小方块
				eye_offset_x := f32(math.sin(e.facing)) * (e.size * 0.18)
				eye_offset_z := f32(math.cos(e.facing)) * (e.size * 0.18)
				eye_y := e.pos.y + e.size * 0.2
				r.draw_cube_v(r.Vector3{e.pos.x + eye_offset_x, eye_y, e.pos.z + eye_offset_z},
					r.Vector3{0.12, 0.08, 0.08}, r.Color{255, 230, 60, 255})
				// 描边
				r.draw_cube_wires_v(e.pos, r.Vector3{e.size, e.size, e.size},
					r.Color{20, 20, 20, 255})
			}

			// 绘制命中粒子
			draw_particles(game)

			// 绘制武器视图模型
			if game.state == .playing || game.state == .level_transition {
				draw_weapon(game)
			}
		}
		r.end_mode_3d()

		// 敌人头顶血条 (2D 屏幕空间)
		draw_enemy_health_bars(game)

		// HUD (2D)
		draw_health_panel(game.player)
		draw_ammo_panel(game.player)
		draw_status_panel(game)
		draw_hit_markers(game.hits_display)
		draw_damage_overlay(game.player)
		draw_crosshair()
		draw_controls_hint()

		// 状态覆盖
		draw_state_overlay(game)
	}
	r.end_drawing()
}