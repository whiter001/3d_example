// =============================================================================
//  ui.v - HUD 与屏幕叠加层渲染
// =============================================================================
//
//  全部 UI 在 BeginMode3D / EndMode3D 之外用 2D 绘制.
//
//  draw_hud:
//    左上: 关卡名 + HP 条
//    左下: 弹药数 (大字 + 备用弹)
//    右上: 击杀数 / 关卡剩余敌人数
//    屏幕中心: 准星 (一个小十字)
//
//  draw_weapon:
//    在 BeginMode3D 之内根据相机方向计算武器的位置, 用 raylib 内置几何
//    拼出一把手枪 (枪管 + 枪身 + 握把 + 准星)
//    - 走路时叠加 Player.weapon_bob_offset 的上下 / 左右晃动
//    - 开火时叠加 kickback 后的坐力 (武器后移)
//
//  draw_hitscreen:
//    受击红屏 (damage_flash 驱动)
//    关卡过渡半透明黑屏 (state_timer 驱动)
//
//  draw_crosshair / draw_kill_markers:
//    准星 + 击中标记的小箭头
// =============================================================================

module main

import raylib as r
import math

// 在屏幕中心绘制十字准星
pub fn draw_crosshair() {
	sw := r.get_screen_width()
	sh := r.get_screen_height()
	cx := sw / 2
	cy := sh / 2
	r.draw_line(cx - 8, cy, cx + 8, cy, r.Color{255, 255, 255, 220})
	r.draw_line(cx, cy - 8, cx, cy + 8, r.Color{255, 255, 255, 220})
	r.draw_circle(cx, cy, 1.5, r.Color{255, 50, 50, 230})
}

// 左上角 HP 条 + 文字
pub fn draw_health_panel(player Player) {
	x := 20
	y := 20
	// 背景
	r.draw_rectangle(x - 5, y - 5, 240, 50, r.Color{0, 0, 0, 160})
	r.draw_rectangle_lines(x - 5, y - 5, 240, 50, r.Color{80, 80, 80, 200})
	// HP 条
	hp_ratio := f32(player.hp) / f32(player.max_hp)
	bar_w := int(220.0 * hp_ratio)
	bar_color := if hp_ratio > 0.5 {
		r.Color{0, 220, 80, 255}
	} else if hp_ratio > 0.25 {
		r.Color{255, 200, 0, 255}
	} else {
		r.Color{220, 50, 50, 255}
	}
	r.draw_rectangle(x, y, bar_w, 18, bar_color)
	r.draw_text('HP ${player.hp}/${player.max_hp}', x + 6, y + 2, 16, r.black)
	// 备用生命 (用绿色加号图标示意)
	r.draw_text('+${player.max_hp}', x + 160, y + 24, 14, r.Color{180, 255, 180, 220})

	// 第二行: 装弹状态
	if player.reload_timer > 0 {
		progress := 1.0 - player.reload_timer / player.reload_time
		r.draw_text('RELOADING...', x, y + 32, 14, r.Color{255, 220, 80, 230})
		r.draw_rectangle(x + 120, y + 36, int(80.0 * progress), 6, r.Color{255, 220, 80, 230})
	}
}

// 左下角: 弹药数
pub fn draw_ammo_panel(player Player) {
	sw := r.get_screen_width()
	text := '${player.ammo}'
	big_w := r.measure_text(text, 56)
	r.draw_text(text, sw / 2 - 100 - big_w, r.get_screen_height() - 70, 56, r.Color{255, 240, 200, 255})
	r.draw_text('/ ${player.reserve}', sw / 2 - 90, r.get_screen_height() - 40, 24, r.Color{200, 200, 200, 200})
	// 弹匣可视化: 12 个小方格
	for i in 0 .. player.max_ammo {
		color := if i < player.ammo {
			r.Color{255, 220, 100, 255}
		} else {
			r.Color{80, 80, 80, 200}
		}
		r.draw_rectangle(sw / 2 - 100 + i * 9, r.get_screen_height() - 18, 6, 12, color)
	}
}

// 右上角: 关卡名 + 击杀数 + 剩余敌人
pub fn draw_status_panel(game &Game) {
	sw := r.get_screen_width()
	text := '${game.level.name}'
	w := r.measure_text(text, 22)
	r.draw_text(text, sw - w - 20, 24, 22, r.Color{230, 230, 230, 230})

	alive_enemies := game.enemies.filter(it.state != .dead && it.state != .dying).len
	r.draw_text('KILLS  ${game.kills_total}', sw - 180, 56, 18, r.Color{255, 220, 120, 230})
	r.draw_text('LEFT   ${alive_enemies}', sw - 180, 80, 18, r.Color{255, 120, 120, 230})
	r.draw_text('LEVEL  ${game.current_level_idx + 1}', sw - 180, 104, 18, r.Color{180, 220, 255, 230})
}

// 受击红屏 (强度由 damage_flash 驱动)
pub fn draw_damage_overlay(player Player) {
	if player.damage_flash > 0 {
		alpha := u8(player.damage_flash * 180)
		// 边框红色 (经典 FPS 受伤效果)
		sw := r.get_screen_width()
		sh := r.get_screen_height()
		thick := int(40.0 + player.damage_flash * 80.0)
		r.draw_rectangle(0, 0, sw, thick, r.Color{200, 30, 30, alpha})
		r.draw_rectangle(0, sh - thick, sw, thick, r.Color{200, 30, 30, alpha})
		r.draw_rectangle(0, 0, thick, sh, r.Color{200, 30, 30, alpha})
		r.draw_rectangle(sw - thick, 0, thick, sh, r.Color{200, 30, 30, alpha})
	}
}

// 关卡过渡 / 死亡 / 胜利全屏文字
pub fn draw_state_overlay(game &Game) {
	match game.state {
		.level_transition {
			mut alpha := u8(220 - game.state_timer * 60)
			if int(alpha) < 0 {
				alpha = 0
			}
			r.draw_rectangle(0, 0, r.get_screen_width(), r.get_screen_height(),
				r.Color{0, 0, 0, alpha})
			text := 'LEVEL ${game.current_level_idx + 1}'
			w := r.measure_text(text, 64)
			r.draw_text(text, r.get_screen_width() / 2 - w / 2, r.get_screen_height() / 2 - 60, 64,
				r.Color{255, 80, 80, 255})
			sub := game.level.name
			sw := r.measure_text(sub, 28)
			r.draw_text(sub, r.get_screen_width() / 2 - sw / 2, r.get_screen_height() / 2 + 10, 28,
				r.Color{230, 230, 230, 230})
			r.draw_text('Get ready...', r.get_screen_width() / 2 - 60,
				r.get_screen_height() / 2 + 60, 18, r.Color{200, 200, 200, 200})
		}
		.dead {
			text := 'YOU DIED'
			w := r.measure_text(text, 72)
			r.draw_text(text, r.get_screen_width() / 2 - w / 2, r.get_screen_height() / 2 - 40, 72,
				r.Color{220, 30, 30, 255})
			sub := 'Total kills: ${game.kills_total}    Press R to restart'
			sw := r.measure_text(sub, 22)
			r.draw_text(sub, r.get_screen_width() / 2 - sw / 2, r.get_screen_height() / 2 + 30, 22,
				r.Color{200, 200, 200, 230})
		}
		.won {
			text := 'VICTORY'
			w := r.measure_text(text, 80)
			r.draw_text(text, r.get_screen_width() / 2 - w / 2, r.get_screen_height() / 2 - 60, 80,
				r.Color{255, 220, 60, 255})
			sub := 'All levels cleared. Total kills: ${game.kills_total}'
			sw := r.measure_text(sub, 22)
			r.draw_text(sub, r.get_screen_width() / 2 - sw / 2, r.get_screen_height() / 2 + 30, 22,
				r.Color{230, 230, 230, 230})
		}
		else {}
	}
}

// 在 3D 模式内绘制武器视图模型
//
// 位置计算思路:
//    1. 取相机的 forward / right / up 向量
//    2. 武器在视野右下角: forward + (right * 0.6) - (up * 0.4)
//    3. 加走路晃动 + 后坐力
//    4. 朝向相机正前方
pub fn draw_weapon(game &Game) {
	cam := game.camera
	// forward, right, up
	fwd := vec3_normalize(r.Vector3{
		x: cam.target.x - cam.position.x
		y: cam.target.y - cam.position.y
		z: cam.target.z - cam.position.z
	})
	right := vec3_normalize(vec3_cross(fwd, cam.up))
	up := vec3_normalize(vec3_cross(right, fwd))

	bob_x, bob_y := game.player.weapon_bob_offset()
	kick := game.player.kickback

	// 武器基位置 (相机右下)
	base := r.Vector3{
		x: cam.position.x + fwd.x * 0.6 + right.x * (0.30 + bob_x) - up.x * (0.32 - bob_y)
		y: cam.position.y + fwd.y * 0.6 + right.y * (0.30 + bob_x) - up.y * (0.32 - bob_y)
		z: cam.position.z + fwd.z * 0.6 + right.z * (0.30 + bob_x) - up.z * (0.32 - bob_y)
	}

	// 后坐力: 沿 -fwd 推一点点
	recoil := r.Vector3{
		x: base.x - fwd.x * kick * 0.08
		y: base.y - fwd.y * kick * 0.08
		z: base.z - fwd.z * kick * 0.08
	}

	// 武器主色 (深灰金属)
	body := r.Color{60, 60, 70, 255}
	dark := r.Color{30, 30, 35, 255}
	edge := r.Color{120, 120, 130, 255}

	// 枪管 (横向一根细长的深色立方体)
	r.draw_cube_v(
		r.Vector3{recoil.x + right.x * 0.10, recoil.y + right.y * 0.10, recoil.z + right.z * 0.10}
		r.Vector3{0.05, 0.05, 0.22}
		dark
	)

	// 枪身
	r.draw_cube_v(
		r.Vector3{recoil.x - right.x * 0.04, recoil.y - right.y * 0.04, recoil.z - right.z * 0.04}
		r.Vector3{0.07, 0.09, 0.18}
		body
	)

	// 握把 (向下倾斜的立方体)
	r.draw_cube_v(
		r.Vector3{recoil.x - right.x * 0.04 - up.x * 0.10, recoil.y - right.y * 0.04 - up.y * 0.10,
			recoil.z - right.z * 0.04 - up.z * 0.10}
		r.Vector3{0.05, 0.12, 0.07}
		dark
	)

	// 准星凸起 (枪管上方的红色小方块)
	r.draw_cube_v(
		r.Vector3{recoil.x + right.x * 0.12, recoil.y + right.y * 0.12 + up.x * 0.04,
			recoil.z + right.z * 0.12 + up.z * 0.04}
		r.Vector3{0.015, 0.02, 0.025}
		r.Color{200, 50, 50, 255}
	)

	// 边缘描边
	r.draw_cube_wires_v(
		r.Vector3{recoil.x - right.x * 0.04, recoil.y - right.y * 0.04, recoil.z - right.z * 0.04}
		r.Vector3{0.07, 0.09, 0.18}
		edge
	)

	// 枪口火光 (开枪瞬间显示)
	if game.player.muzzle_flash > 0 {
		flash_pos := r.Vector3{
			x: recoil.x + fwd.x * 0.12 + right.x * 0.18
			y: recoil.y + fwd.y * 0.12 + right.y * 0.18
			z: recoil.z + fwd.z * 0.12 + right.z * 0.18
		}
		r.draw_cube_v(flash_pos, r.Vector3{0.08, 0.08, 0.08}, r.Color{255, 230, 100, 255})
		r.draw_sphere(flash_pos, 0.06, r.Color{255, 200, 80, 200})
	}

	// 在 3D 世界中画一条很短的射线 (调试 / 视觉反馈)
	muzzle_pos := r.Vector3{
		x: cam.position.x + fwd.x * 0.5
		y: cam.position.y + fwd.y * 0.5
		z: cam.position.z + fwd.z * 0.5
	}
	end_pos := r.Vector3{
		x: cam.position.x + fwd.x * 1.2
		y: cam.position.y + fwd.y * 1.2
		z: cam.position.z + fwd.z * 1.2
	}
	if game.player.muzzle_flash > 0 {
		r.draw_line_3d(muzzle_pos, end_pos, r.Color{255, 240, 180, 220})
	}
}

// vec3_cross - 向量叉乘 (避开 raymath 模块, 直接内联)
fn vec3_cross(a r.Vector3, b r.Vector3) r.Vector3 {
	return r.Vector3{
		x: a.y * b.z - a.z * b.y
		y: a.z * b.x - a.x * b.z
		z: a.x * b.y - a.y * b.x
	}
}

// vec3_normalize - 向量归一化
fn vec3_normalize(v r.Vector3) r.Vector3 {
	l := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if l < 1e-6 {
		return r.Vector3{0, 0, 0}
	}
	return r.Vector3{f32(v.x / l), f32(v.y / l), f32(v.z / l)}
}

// 在屏幕中央绘制射线击中提示
pub fn draw_hit_markers(markers []HitMarker) {
	sw := r.get_screen_width()
	sh := r.get_screen_height()
	cx := f32(sw / 2)
	cy := f32(sh / 2)
	for hit in markers {
		if hit.life <= 0 {
			continue
		}
		alpha := u8(hit.life * 255)
		col := if hit.is_kill { r.Color{255, 80, 80, alpha} } else { r.Color{255, 230, 120, alpha} }
		// 在屏幕中心画一个 X (4 个小斜线)
		d := 10.0
		off := 14.0
		r.draw_line(int(cx + math.cos(hit.angle) * off - d), int(cy + math.sin(hit.angle) * off - d),
			int(cx + math.cos(hit.angle) * off + d), int(cy + math.sin(hit.angle) * off + d), col)
		r.draw_line(int(cx + math.cos(hit.angle) * off - d), int(cy + math.sin(hit.angle) * off + d),
			int(cx + math.cos(hit.angle) * off + d), int(cy + math.sin(hit.angle) * off - d), col)
	}
}

// 短暂的控制提示 (屏幕底部)
pub fn draw_controls_hint() {
	sw := r.get_screen_width()
	sh := r.get_screen_height()
	hint := 'WASD move   MOUSE look   LMB fire   R reload   ESC quit'
	w := r.measure_text(hint, 14)
	r.draw_text(hint, sw / 2 - w / 2, sh - 16, 14, r.Color{200, 200, 200, 180})
}