package app

import "core:encoding/cbor"

@(require) import "core:fmt"

import "core:io"
import "core:log"
@(require) import "core:mem"
import "core:os"
import "core:time"

// import nri "en:nri"
import sdl "vendor:sdl2"

main :: proc() {
	logger := log.create_console_logger(ident = "en")
	defer log.destroy_console_logger(logger)
	context.logger = logger

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

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

	sw: time.Stopwatch
	time.stopwatch_start(&sw)
	session: Shader_Context
	slang_ok := create_shader_context(&session)
	if !slang_ok {
		log.errorf("Could not create global session")
		return
	}
	defer destroy_shader_context(&session)

	time.stopwatch_stop(&sw)

	log.infof(
		"Session created in {} ms",
		(time.duration_milliseconds(time.stopwatch_duration(sw))),
	)

	time.stopwatch_reset(&sw)
	time.stopwatch_start(&sw)
	forward_compiled, ok_forward := compile_shader(
		&session,
		"assets/forward.slang",
		{.Vertex_Shader, .Fragment_Shader},
		allocator = context.temp_allocator,
	)
	if !ok_forward {
		log.errorf("Could not compile shader")
		return
	}
	log_shader(forward_compiled)
	time.stopwatch_stop(&sw)

	log.infof(
		"Forward shader compiled in {} ms",
		(time.duration_milliseconds(time.stopwatch_duration(sw))),
	)

	encode_cbor_to_file :: proc(name: string, data: $T) {
		file, err := os.open(name, os.O_RDWR | os.O_CREATE | os.O_TRUNC)
		if err != nil {
			log.errorf("Could not open file: {}", err)
			return
		}
		defer os.close(file)
		stream := os.stream_from_handle(file)
		w := io.to_writer(stream)
		marshal_err := cbor.marshal_into_writer(w, data, flags = cbor.ENCODE_FULLY_DETERMINISTIC)
		if marshal_err != nil {
			log.errorf("Could not marshal: {}", marshal_err)
			return
		}
	}

	encode_cbor_to_file("forward.enshader", forward_compiled)

	t, t_ok := texture_from_file(&ren, "assets/Avocado_baseColor.png")
	if !t_ok {
		log.errorf("Could not load texture")
		return
	}
	defer destroy_texture(&t, &ren)

	avo_basecolor_handle, add_texture_ok := resource_pool_add_texture(
		&ren.resource_pool,
		&ren,
		t.srv,
	)
	if !add_texture_ok {
		log.errorf("Failed to add texture to resource pool")
		return
	}

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
	for code_set, stage in shaders {
		for code, target in code_set {
			if len(code) == 0 do continue
			log.infof("Shader stage: {} {} {}", target, stage, len(code))
		}
	}
}
