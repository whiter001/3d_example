// =============================================================================
//  player.v - 玩家状态与武器系统
// =============================================================================
//
//  玩家数据集中在 Player 结构体里:
//    - pos / hp / ammo: 当前血量、弹药
//    - 各种 *_timer: 用于开火冷却、装弹、击中反馈等时间相关状态
//    - bob_phase: 走路时的武器晃动相位
//
//  new_player: 默认满血满弹药
//  update_player: 处理弹药耗尽自动装弹、击中红屏衰减、走路晃动相位推进
//  take_damage: 受伤并触发红色全屏闪
//
//  武器模型是一个简单拼接的"手枪"组合体, 在 draw_weapon 中用 raylib
//  自带的 DrawCube / DrawCubeWires 拼出来, 不需要外部资源.
// =============================================================================

module main

import raylib as r
import math

pub struct Player {
pub mut:
	pos                  r.Vector3
	max_hp               int
	hp                   int
	max_ammo             int
	ammo                 int
	max_reserve          int     // 备用弹匣容量
	reserve              int     // 当前备用弹数
	fire_cooldown        f32     // 两次开火之间的冷却
	fire_timer           f32     // 当前冷却倒计时
	reload_time          f32     // 装弹耗时
	reload_timer         f32     // 当前装弹倒计时 (0 表示没在装弹)
	muzzle_flash         f32     // 枪口火光剩余时间
	kickback             f32     // 武器后坐力动画 0..1
	damage_flash         f32     // 受伤红屏 0..1
	bob_phase            f32     // 走路晃动相位
	was_moving           bool
	invulnerable         f32     // 受击后的无敌时间
	velocity_y           f32     // 垂直速度 (跳跃重力)
}

// 推进无敌倒计时
pub fn (mut p Player) tick_invuln(dt f32) {
	if p.invulnerable > 0 {
		p.invulnerable = math.max(f32(0), p.invulnerable - dt)
	}
}

// 受击时调用: 应用伤害 + 设定无敌 (避免连续帧多次判定)
pub fn (mut p Player) hit(amount int) {
	if p.invulnerable > 0 {
		return
	}
	p.take_damage(amount)
	p.invulnerable = 0.4
}

pub fn new_player() Player {
	return Player{
		pos:           r.Vector3{0.2, 0.4, 0.2}
		max_hp:        100
		hp:            100
		max_ammo:      12            // 一个弹匣 12 发
		ammo:          12
		max_reserve:   60            // 备用 60 发
		reserve:       36
		fire_cooldown: 0.18          // 约 5.5 发/秒
		fire_timer:    0
		reload_time:   1.2
		reload_timer:  0
		muzzle_flash:  0
		kickback:      0
		damage_flash:  0
		bob_phase:     0
		was_moving:    false
		velocity_y:    0
	}
}

// 每帧推进玩家状态机
pub fn (mut p Player) update(dt f32, is_moving bool) {
	// 走路晃动相位: 移动时推进, 静止时缓慢归零
	if is_moving {
		p.bob_phase += dt * 8.0
		p.was_moving = true
	} else {
		// 静止时让相位回正, 但保持连续避免武器跳
		if p.was_moving {
			p.was_moving = false
		}
	}

	// 冷却计时
	if p.fire_timer > 0 {
		p.fire_timer = math.max(f32(0), p.fire_timer - dt)
	}
	if p.muzzle_flash > 0 {
		p.muzzle_flash = math.max(f32(0), p.muzzle_flash - dt)
	}
	if p.damage_flash > 0 {
		p.damage_flash = math.max(f32(0), p.damage_flash - dt * 1.5)
	}
	if p.kickback > 0 {
		p.kickback = math.max(f32(0), p.kickback - dt * 4.0)
	}

	// 装弹逻辑
	if p.reload_timer > 0 {
		p.reload_timer -= dt
		if p.reload_timer <= 0 {
			// 装填完毕
			need := p.max_ammo - p.ammo
			take := math.min(need, p.reserve)
			p.ammo += take
			p.reserve -= take
			p.reload_timer = 0
		}
	}
}

// 尝试开始装弹 (弹匣不满 + 还有备用弹 + 当前没在装)
pub fn (mut p Player) try_reload() {
	if p.reload_timer > 0 {
		return
	}
	if p.ammo >= p.max_ammo {
		return
	}
	if p.reserve <= 0 {
		return
	}
	p.reload_timer = p.reload_time
}

// 尝试开火, 返回是否成功 (true = 发射了一发)
pub fn (mut p Player) try_fire() bool {
	if p.fire_timer > 0 {
		return false
	}
	if p.reload_timer > 0 {
		return false
	}
	if p.ammo <= 0 {
		// 弹匣空, 自动触发装弹
		p.try_reload()
		return false
	}
	p.ammo -= 1
	p.fire_timer = p.fire_cooldown
	p.muzzle_flash = 0.06
	p.kickback = 1.0
	return true
}

// 玩家受到伤害 (带 0.4 秒无敌时间由调用方控制, 这里只负责扣血和触发闪屏)
pub fn (mut p Player) take_damage(amount int) {
	p.hp -= amount
	if p.hp < 0 {
		p.hp = 0
	}
	p.damage_flash = 1.0
}

// 添加弹药 (敌人掉落或关卡奖励)
pub fn (mut p Player) add_ammo(amount int) {
	p.reserve += amount
	if p.reserve > p.max_reserve {
		p.reserve = p.max_reserve
	}
}

// 玩家是否还活着
pub fn (p Player) is_alive() bool {
	return p.hp > 0
}

// 走路晃动偏移, 给武器视图模型使用
pub fn (p Player) weapon_bob_offset() (f32, f32) {
	return f32(math.sin(p.bob_phase)) * 0.015, f32(math.abs(math.cos(p.bob_phase))) * 0.025
}