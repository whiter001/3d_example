// =============================================================================
//  main.v - 程序入口 + 主循环
// =============================================================================
//
//  启动流程:
//    1. raylib 初始化窗口 (1024x720)
//    2. context_init() 创建 Config + 空 Buffer + 注册键位
//    3. 加载 TTF 字体 (Liberation Mono Regular)
//    4. 主循环: handle_key_events -> render -> end_drawing
//    5. 退出时释放资源
//
//  退出条件: ESC / ctrl+q / :q / 窗口关闭
// =============================================================================

module main

import raylib as r

fn main() {
	r.set_trace_log_level(int(r.TraceLogLevel.log_error))
	r.init_window(1024, 720, 'preditor_v (V/raylib)')
	r.set_target_fps(60)

	context_init()
	context_load_font()

	for !r.window_should_close() && !context.should_quit {
		handle_key_events(mut context)
		context.sync_viewport()
		r.begin_drawing()
		render(&context)
		r.end_drawing()
	}

	context_shutdown()
	r.close_window()
}