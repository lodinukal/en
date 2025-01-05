package app

import "core:encoding/cbor"

@(require) import "core:fmt"

import "core:io"
import "core:log"
@(require) import "core:mem"
import "core:os"
import "core:time"

import "en:mercury"

// import nri "en:nri"
import sdl "vendor:sdl2"

main :: proc() {
	logger := log.create_console_logger(ident = "en")
	defer log.destroy_console_logger(logger)
	context.logger = logger

	track: mem.Tracking_Allocator
	when ODIN_DEBUG {
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


	forward_pipeline_layout, forward_pipeline_layout_err := ren.instance->create_pipeline_layout(
		ren.device,
		{
			descriptor_sets = {
				resource_pool_draws_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
				resource_pool_descriptor_desc(1, {.Vertex_Shader, .Fragment_Shader}),
			},
			shader_stages = {.Vertex_Shader, .Fragment_Shader},
		},
	)
	if forward_pipeline_layout_err != nil {
		log.errorf("Could not create pipeline layout: {}", forward_pipeline_layout_err)
		return
	}
	defer ren.instance->destroy_pipeline_layout(forward_pipeline_layout)
	ren.instance->set_pipeline_layout_debug_name(
		forward_pipeline_layout,
		"Forward Pipeline Layout",
	)

	forward_pipeline, forward_pipeline_err := ren.instance->create_graphics_pipeline(
		ren.device,
		{
			pipeline_layout = forward_pipeline_layout,
			vertex_input = VERTEX_INPUT_DEFAULT,
			input_assembly = {topology = .Triangle_List},
			rasterization = {
				viewport_num = 1,
				fill_mode = .Solid,
				cull_mode = .None,
				front_counter_clockwise = true,
			},
			output_merger = {
				colors = {{format = .RGBA8_UNORM, color_write_mask = mercury.Color_Write_RGBA}},
			},
			shaders = {
				{
					stage = {.Vertex_Shader},
					bytecode = forward_compiled[.Vertex],
					entry_point_name = "vs_main",
				},
				{
					stage = {.Fragment_Shader},
					bytecode = forward_compiled[.Fragment],
					entry_point_name = "fs_main",
				},
			},
		},
	)
	if forward_pipeline_err != nil {
		log.errorf("Could not create pipeline: {}", forward_pipeline_err)
		return
	}
	defer ren.instance->destroy_pipeline(forward_pipeline)
	ren.instance->set_pipeline_debug_name(forward_pipeline, "Forward Pipeline")

	scene, scene_ok := load_gltf_file(&ren, "assets/Avocado/Avocado.gltf")
	if !scene_ok {
		log.errorf("Could not load scene")
		return
	}
	defer unload_scene(&ren, &scene)

	running := true
	is_fullscreen := false
	for running {
		free_all(context.temp_allocator)
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
		cmd := begin_rendering(&ren) or_break
		defer end_rendering(&ren)

		frame := get_render_frame(&ren)

		tex_barrier(
			&ren,
			{texture = frame.texture, after = mercury.ACCESS_LAYOUT_STAGE_COLOR_ATTACHMENT},
		)
		defer tex_barrier(
			&ren,
			{
				texture = frame.texture,
				before = mercury.ACCESS_LAYOUT_STAGE_COLOR_ATTACHMENT,
				after = mercury.ACCESS_LAYOUT_STAGE_PRESENT,
			},
		)

		ren.instance->cmd_begin_rendering(cmd, {colors = {frame.srv}})
		defer ren.instance->cmd_end_rendering(cmd)

		ren.instance->cmd_clear_attachments(
			cmd,
			{
				{
					value = (mercury.Color)(
						[4]f32{f32(0x06) / 255.0, f32(0x06) / 255.0, f32(0x06) / 255.0, 1},
					),
					planes = {.Color},
					color_attachment_index = 0,
				},
			},
			{{x = 0, y = 0, width = u16(ren.window_size.x), height = u16(ren.window_size.y)}},
		)
		ren.instance->cmd_set_viewports(
			cmd,
			{
				{
					x = 0,
					y = 0,
					width = auto_cast ren.window_size.x,
					height = auto_cast ren.window_size.y,
					min_depth = 0,
					max_depth = 1,
				},
			},
		)

		ren.instance->cmd_set_scissors(
			cmd,
			{
				{
					x = 0,
					y = 0,
					width = auto_cast ren.window_size.x,
					height = auto_cast ren.window_size.y,
				},
			},
		)

		ren.instance->cmd_set_pipeline_layout(cmd, forward_pipeline_layout)
		ren.instance->cmd_set_pipeline(cmd, forward_pipeline)
		bind_descriptor_sets(&ren)
		for mesh in scene.meshes {
			for prim in mesh.primitives {
				ren.resource_pool.draws.material_index = prim.material
				copy_draw_data(&ren.resource_pool)

				position_buffer := scene.buffers[prim.positions.buffer]
				normal_buffer := scene.buffers[prim.normals.buffer]
				texcoord_buffer := scene.buffers[prim.texcoords.buffer]
				ren.instance->cmd_set_vertex_buffers(
					cmd,
					0,
					{position_buffer.buffer, normal_buffer.buffer, texcoord_buffer.buffer},
					{prim.positions.offset, prim.normals.offset, prim.texcoords.offset},
				)

				index_buffer := scene.buffers[prim.indices.buffer]
				ren.instance->cmd_set_index_buffer(
					cmd,
					index_buffer.buffer,
					prim.indices.offset,
					.Uint16,
				)

				ren.instance->cmd_draw_indexed(
					cmd,
					{
						index_num = u32(prim.indices.size / 2),
						instance_num = 1,
						base_index = 0,
						base_vertex = 0,
						base_instance = 0,
					},
				)
			}
		}

		// count := 0
		// for k, v in track.allocation_map do count += 1
	}

	renderer_wait_idle(&ren)
}

log_shader :: proc(shaders: [Shader_Stage][mercury.Shader_Target][]u8) {
	for code_set, stage in shaders {
		for code, target in code_set {
			if len(code) == 0 do continue
			log.infof("Shader stage: {} {} {}", target, stage, len(code))
		}
	}
}
