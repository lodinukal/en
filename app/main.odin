package app

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"

// import nri "en:nri"
import sdl "vendor:sdl2"

main :: proc() {
	logger := log.create_console_logger(ident = "en")
	defer log.destroy_console_logger(logger)
	context.logger = logger

	sdl.Init({.VIDEO})
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Hello, World!",
		x = sdl.WINDOWPOS_UNDEFINED,
		y = sdl.WINDOWPOS_UNDEFINED,
		w = 800,
		h = 600,
		flags = {.RESIZABLE, .ALLOW_HIGHDPI},
	)
	defer sdl.DestroyWindow(window)

	ren: Renderer
	ren.window = window

	if !init_renderer(&ren) do return
	defer destroy_renderer(&ren)

	session, slang_ok := create_global_session()
	if !slang_ok {
		log.errorf("Could not create global session")
		return
	}
	defer destroy_global_session(session)

	forward_compiled, ok_forward := compile_shader(
		session,
		"assets/forward.slang",
		{.Vertex_Shader, .Fragment_Shader},
		allocator = context.temp_allocator,
	)
	if !ok_forward {
		log.errorf("Could not compile shader")
		return
	}
	log_shader(forward_compiled)

	emit_draws_compiled, ok_emit_draws := compile_shader(
		session,
		"assets/emit_draws.slang",
		{.Compute_Shader},
		allocator = context.temp_allocator,
	)
	if !ok_emit_draws {
		log.errorf("Could not compile shader")
		return
	}
	log_shader(emit_draws_compiled)

	running := true
	is_fullscreen := false
	for running {
		for ev: sdl.Event; sdl.PollEvent(&ev); {
			#partial switch ev.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				if ev.key.keysym.sym == .F {
					sdl.SetWindowFullscreen(
						window,
						sdl.WINDOW_FULLSCREEN_DESKTOP if !is_fullscreen else {.RESIZABLE},
					)
					is_fullscreen = !is_fullscreen
				}
			case .WINDOWEVENT:
				#partial switch ev.window.event {
				case .RESIZED:
					w := ev.window.data1
					h := ev.window.data2

					renderer_resize(&ren, {w, h})
				}
			}
		}
		begin_rendering(&ren) or_break
		defer end_rendering(&ren)
	}
}

log_shader :: proc(shaders: [Shader_Stage][Target][]u8) {
	for target_set, stage in shaders {
		for code, target in target_set {
			if len(code) == 0 do continue
			log.infof("Shader stage: {} {} {}", target, stage, len(code))
		}
	}
}
