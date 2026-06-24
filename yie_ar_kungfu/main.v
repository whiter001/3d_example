// =============================================================================
//  main.v - 程序入口与主循环
// =============================================================================
//
//  启动流程:
//    1. raylib 初始化窗口 (1024x768) + 音频
//    2. 加载所有素材 (45 张 PNG + 9 个 WAV + 背景乐 + RenderTexture)
//    3. 进入主循环
//    4. 退出时释放资源
//
//  主循环每帧:
//    1. 处理 ESC 退出
//    2. stage_handle_keys()   按 state 派发到 title/view/game 的键盘
//    3. stage_update()        推进时间相关状态
//    4. game_tick()           60Hz 推进玩家 halt / 对手 AI tick
//    5. stage_draw()          在 RenderTexture 上按 state 渲染
//    6. blit_target_to_screen()  拉伸到屏幕
//
//  资源:
//    所有 .v 文件 module main 共享同一个 game 实例 (pub mut game Game)
// =============================================================================

module main

import raylib as r

fn main() {
	r.set_trace_log_level(int(r.TraceLogLevel.log_error))
	r.init_window(screen_width, screen_height, 'Yie Ar Kung-Fu (V/raylib)')
	r.init_audio_device()
	r.set_target_fps(60)
	r.hide_cursor()

	game_init()
	game_load_assets()
	title_init()

	for !r.window_should_close() {
		if r.is_key_down(int(r.KeyboardKey.key_escape)) {
			break
		}

		stage_handle_keys()
		stage_update()
		game_tick()

		stage_draw()
		blit_target_to_screen()
	}

	game_shutdown()
	r.close_audio_device()
	r.close_window()
}