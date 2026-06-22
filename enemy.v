// =============================================================================
//  enemy.v - 敌人状态机与 AI
// =============================================================================
//
//  EnemyState 枚举:
//    idle     - 待机, 玩家进入视距后切换为 chase
//    chase    - 朝玩家移动, 进入近距离后切换为 attack
//    attack   - 停下来向玩家射击, 有 attack_cooldown 间隔
//    dying    - 死亡动画, 一段时间后切到 dead
//    dead     - 不再渲染也不参与逻辑
//
//  AI 更新逻辑 (update_enemies):
//    1. 计算到玩家的水平距离
//    2. 根据状态决定移动方向 / 朝向
//    3. 与迷宫墙体做圆-矩形碰撞避免穿墙
//    4. 与玩家圆-圆碰撞触发伤害
//
//  视觉表现:
//    - 主体一个 0.8 见方的立方体
//    - 眼睛用两个更小的发光立方体表示, 朝向来袭方向旋转
//    - hit_flash > 0 时整块变白, 提示玩家打到了
//    - dying 状态下立方体逐渐缩小并下坠
// =============================================================================

module main

import raylib as r
import math

pub enum EnemyState {
	idle
	chase
	attack
	dying
	dead
}

// 一个立方体敌人 (没有动画模型, 全靠 raylib 内置几何绘制)
pub struct Enemy {
pub mut:
	pos          r.Vector3
	size         f32      // 立方体边长
	max_hp       int
	hp           int
	state        EnemyState
	speed        f32
	attack_range f32      // 进入这个距离后停下开火
	sight_range  f32      // 大于这个距离就回到 idle (否则一直追)
	attack_cd    f32
	attack_timer f32
	hit_flash    f32      // 0..1, 受击白闪
	death_timer  f32      // 死亡动画计时
	death_shrink f32      // 死亡缩放 1..0
	facing       f32      // 角度 (弧度), 用于眼睛朝向
}

pub fn new_enemy(pos r.Vector3) Enemy {
	return Enemy{
		pos:          r.Vector3{pos.x, 0.4, pos.z}
		size:         0.7
		max_hp:       30
		hp:           30
		state:        .idle
		speed:        1.8
		attack_range: 6.0
		sight_range:  20.0
		attack_cd:    1.1
		attack_timer: 0.5 + f32(r.get_random_value(0, 50)) * 0.01 // 错开首攻
		hit_flash:    0
		death_timer:  0
		death_shrink: 1.0
		facing:       0
	}
}

// 更新所有敌人
pub fn (mut game Game) update_enemies(dt f32) {
	for i in 0 .. game.enemies.len {
		mut e := &game.enemies[i]
		if e.state == .dead {
			continue
		}

		// 死亡动画: 缩小 + 下沉
		if e.state == .dying {
			e.death_timer += dt
			e.death_shrink = math.max(f32(0), 1.0 - e.death_timer * 1.5)
			if e.death_timer > 0.8 {
				e.state = .dead
			}
			continue
		}

		// 击中白闪衰减
		if e.hit_flash > 0 {
			e.hit_flash = math.max(f32(0), e.hit_flash - dt * 6.0)
		}
		if e.attack_timer > 0 {
			e.attack_timer = math.max(f32(0), e.attack_timer - dt)
		}

		// 到玩家的水平向量 (全部用 f32 保持类型一致)
		dx := game.player.pos.x - e.pos.x
		dz := game.player.pos.z - e.pos.z
		dist := math.sqrt(dx * dx + dz * dz)

		// 朝向目标
		if dist > 0.001 {
			e.facing = f32(math.atan2(dx, dz))
		}

		// 状态转移
		match e.state {
			.idle {
				if dist < e.sight_range {
					e.state = .chase
				}
			}
			.chase {
				if dist > e.sight_range * 1.3 {
					e.state = .idle
				} else if dist < e.attack_range {
					e.state = .attack
				}
			}
			.attack {
				if dist > e.attack_range * 1.5 {
					e.state = .chase
				}
			}
			else {}
		}

		// 移动 / 攻击
		match e.state {
			.chase {
				// 沿水平方向朝玩家移动
				if dist > 0.001 {
					inv_dist := f32(1.0 / dist)
					nx := dx * inv_dist
					nz := dz * inv_dist
					mut new_x := e.pos.x + nx * e.speed * dt
					mut new_z := e.pos.z + nz * e.speed * dt
					// 墙体碰撞: 试 x 方向
					if !game.is_walkable(new_x, e.pos.z, e.size * 0.5) {
						new_x = e.pos.x
					}
					if !game.is_walkable(e.pos.x, new_z, e.size * 0.5) {
						new_z = e.pos.z
					}
					e.pos.x = new_x
					e.pos.z = new_z
				}
			}
			.attack {
				// 停下, 周期性开火 (对玩家造成伤害由 Game.update_player_combat 处理)
				if e.attack_timer <= 0 && dist < e.attack_range * 1.2 {
					e.attack_timer = e.attack_cd
					game.enemy_fire_on_player(e)
				}
			}
			else {}
		}
	}
}

// 敌人对玩家造成伤害 (由 update_enemies 在 attack 状态触发)
fn (mut game Game) enemy_fire_on_player(_ &Enemy) {
	if !game.player.is_alive() {
		return
	}
	// DOOM 风格接触伤害: 命中扣 8 HP, 玩家有 0.4 秒无敌避免被围殴秒死
	game.player.hit(8)
}

// 敌人被射线击中
pub fn (mut e Enemy) take_damage(amount int) bool {
	if e.state == .dying || e.state == .dead {
		return false
	}
	e.hp -= amount
	e.hit_flash = 1.0
	if e.hp <= 0 {
		e.state = .dying
		e.death_timer = 0
		return true // 击杀
	}
	return false
}