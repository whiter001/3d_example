// =============================================================================
//  particle.v - 命中粒子效果
// =============================================================================
//
//  敌人在 3D 世界中被命中时,在命中点迸发出若干个小立方体粒子.
//  粒子沿命中法线方向随机散开,并在短时间内淡出、缩小.
//
//  使用方式:
//    - perform_player_fire 中命中敌人后调用 spawn_hit_particles
//    - update_game 每帧调用 game.update_particles(dt)
//    - draw_game 在 3D 模式内调用 draw_particles
// =============================================================================

module main

import raylib as r

pub struct Particle {
pub mut:
	pos      r.Vector3
	vel      r.Vector3
	life     f32
	max_life f32
	size     f32
	color    r.Color
}

// 在 pos 处沿 normal 方向迸射出一组命中粒子
pub fn spawn_hit_particles(mut game Game, pos r.Vector3, normal r.Vector3) {
	count := 10
	for _ in 0 .. count {
		// 在法线方向上加随机扩散,形成锥形喷射
		rx := f32(r.get_random_value(-80, 80)) * 0.01
		ry := f32(r.get_random_value(-80, 80)) * 0.01
		rz := f32(r.get_random_value(-80, 80)) * 0.01
		dir := vec3_normalize(r.Vector3{
			x: normal.x + rx
			y: normal.y + ry
			z: normal.z + rz
		})
		speed := f32(r.get_random_value(60, 160)) * 0.01
		game.particles << Particle{
			pos:      pos
			vel:      r.Vector3{dir.x * speed, dir.y * speed, dir.z * speed}
			life:     0.35
			max_life: 0.35
			size:     f32(r.get_random_value(4, 10)) * 0.01
			color:    r.Color{255, 70, 60, 255}
		}
	}
}

// 敌人死亡时迸发出爆炸状粒子 (数量更多、带向上飘动、颜色偏橙黄)
pub fn spawn_death_particles(mut game Game, pos r.Vector3) {
	count := 28
	for _ in 0 .. count {
		// 以向上方向为主, 四周随机扩散
		rx := f32(r.get_random_value(-90, 90)) * 0.01
		ry := f32(r.get_random_value(0, 90)) * 0.01
		rz := f32(r.get_random_value(-90, 90)) * 0.01
		dir := vec3_normalize(r.Vector3{
			x: rx
			y: 1.0 + ry
			z: rz
		})
		speed := f32(r.get_random_value(100, 280)) * 0.01
		g := u8(100 + r.get_random_value(0, 120))
		game.particles << Particle{
			pos:      pos
			vel:      r.Vector3{dir.x * speed, dir.y * speed, dir.z * speed}
			life:     0.55
			max_life: 0.55
			size:     f32(r.get_random_value(8, 18)) * 0.01
			color:    r.Color{255, g, 40, 255}
		}
	}
}

// 推进所有粒子: 位置 += 速度 * dt, 生命值衰减, 清掉过期的
pub fn (mut game Game) update_particles(dt f32) {
	for i in 0 .. game.particles.len {
		mut p := &game.particles[i]
		p.pos.x += p.vel.x * dt
		p.pos.y += p.vel.y * dt
		p.pos.z += p.vel.z * dt
		p.life -= dt
	}
	game.particles = game.particles.filter(it.life > 0)
}

// 在 3D 世界中绘制所有存活粒子
pub fn draw_particles(game &Game) {
	for p in game.particles {
		if p.life <= 0 {
			continue
		}
		ratio := p.life / p.max_life
		alpha := u8(ratio * 255)
		s := p.size * ratio
		col := r.Color{p.color.r, p.color.g, p.color.b, alpha}
		r.draw_cube_v(p.pos, r.Vector3{s, s, s}, col)
	}
}
