// =============================================================================
//  ui.v - HUD 文字与血条 (用 raylib DrawText/DrawRectangle 实现)
// =============================================================================
//
//  原版用 letters.png 图集拼字符串 (sprite.v 已经包含了 letters 但我们不用).
//  这里用 raylib 自带 DrawText, 字体是 raylib 默认, 256x240 渲染坐标下 8 像素高.
//
//  提供:
//    ui_draw_centered_text  - 居中绘制文字 (用于 title 屏)
//    ui_draw_game_hud       - 顶部 score / stage / version
//    ui_draw_health_bars    - 双方血条 (按 health_green/health_red 精灵切片风格)
// =============================================================================

module main

import raylib as r

// 在 256x240 渲染坐标下居中绘制文字
pub fn ui_draw_centered_text(text string, y int, font_size int, color r.Color) {
	w := r.measure_text(text, font_size)
	x := (game_width / 2) - (w / 2)
	r.draw_text(text, x, y, font_size, color)
}

// 顶部状态: ferdie / score / stage / version / life icons
pub fn ui_draw_game_hud() {
	// FERDIE 名字 (左下)
	r.draw_text('ferdie', 16, game_height - 16, 8, r.white)
	// 对手名 (右下)
	name := villain_names[game.stage - 1]
	r.draw_text(name, game_width - 48, game_height - 16, 8, r.white)

	// SCORE (左上)
	r.draw_text('score', 24, 16, 8, r.white)
	mut score_text := '${game.score}'
	for score_text.len < 6 {
		score_text = '0' + score_text
	}
	r.draw_text(score_text, 24, 24, 8, r.white)

	// STAGE (右上)
	stage_text := 'stage-${game.stage}'
	r.draw_text(stage_text, game_width - 64, 16, 8, r.white)

	// 生命图标 (在右上角, 重复画 life 精灵)
	if 'life' in game.sprites {
		mut x := game_width - 64
		for _ in 0 .. int(game.player.lives) {
			game.sprites['life'].x = x
			game.sprites['life'].y = 24
			game.sprites['life'].draw()
			x += 8
		}
	}
}

// 双方血条 (中间偏下): health_hud 精灵 + 一格一格画 health_green / health_red
pub fn ui_draw_health_bars() {
	if 'health_hud' in game.sprites {
		game.sprites['health_hud'].draw()
	}

	// 玩家血条 (左侧, 从右往左)
	if 'health_green' in game.sprites && 'health_red' in game.sprites {
		mut x := 104
		for _ in 0 .. int(game.player.health) {
			mut id := 'health_green'
			if game.player.health <= low_health {
				id = 'health_red'
			}
			game.sprites[id].x = x
			game.sprites[id].y = 210
			game.sprites[id].draw()
			x -= 8
		}
	}

	// 对手血条 (右侧, 从左往右)
	if 'health_green' in game.sprites && 'health_red' in game.sprites {
		mut x := 144
		for _ in 0 .. int(game.villain_health) {
			mut id := 'health_green'
			if game.villain_health <= low_health {
				id = 'health_red'
			}
			game.sprites[id].x = x
			game.sprites[id].y = 210
			game.sprites[id].draw()
			x += 8
		}
	}
}