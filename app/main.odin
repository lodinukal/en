package app

import "core:container/small_array"
@(require) import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
@(require) import "core:mem"
import "core:time"

import "en:mercury"

// import nri "en:nri"
import sdl "vendor:sdl2"

Mouse_Button :: enum u8 {
	Left   = sdl.BUTTON_LEFT,
	Middle = sdl.BUTTON_MIDDLE,
	Right  = sdl.BUTTON_RIGHT,
	X1     = sdl.BUTTON_X1,
	X2     = sdl.BUTTON_X2,
}

main :: proc() {
	logger := log.create_console_logger(ident = "en")
	defer log.destroy_console_logger(logger)
	context.logger = logger

	track: mem.Tracking_Allocator
	_ = track
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

	graphics_layout, graphics_layout_ok := ren_register_pipeline_layout(
		&ren,
		"Graphics Pipeline Layout",
		{
			constants = {{size = size_of(Gpu_Object_Data), shader_stages = {.Vertex_Shader}}},
			descriptor_sets = {
				ren_frame_constants_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
				ren_resource_descriptor_desc(1, {.Vertex_Shader, .Fragment_Shader}),
			},
			shader_stages = {.Vertex_Shader, .Fragment_Shader},
			constants_register_space = 2,
			enable_d3d12_draw_parameters_emulation = true,
		},
	)
	if !graphics_layout_ok {
		log.errorf("Could not create pipeline layout: {}", graphics_layout_ok)
		return
	}
	defer ren_unregister_pipeline_layout(&ren, graphics_layout)

	forward_pipeline, forward_ok := ren_register_pipeline(
		&ren,
		{kind = .File, name = "forward", data = "assets/forward.slang"},
		graphics_layout,
		mercury.Graphics_Pipeline_Desc {
			vertex_input = VERTEX_INPUT_DEFAULT,
			input_assembly = {topology = .Triangle_List},
			rasterization = {
				viewport_num = 1,
				fill_mode = .Solid,
				cull_mode = .Back,
				front_counter_clockwise = true,
			},
			output_merger = {
				colors = {{format = .RGBA8_UNORM, color_write_mask = mercury.Color_Write_RGBA}},
				depth = {write = true, compare_func = .Less},
				depth_stencil_format = .D32_SFLOAT,
			},
			shaders = #partial [mercury.Shader_Stage]mercury.Shader_Desc {
				.Vertex = {stage = {.Vertex_Shader}, entry_point_name = "vs_main"},
				.Fragment = {stage = {.Fragment_Shader}, entry_point_name = "fs_main"},
			},
		},
	)
	if !forward_ok {
		log.errorf("Could not create pipeline: {}", forward_pipeline)
		return
	}

	scene: Scene
	init_scene(&scene, &ren)
	defer deinit_scene(&scene, &ren)

	if scene_ok := load_gltf_file_into(&ren, "assets/Avocado/Avocado.gltf", &scene); !scene_ok {
		log.errorf("Could not load scene")
		return
	}

	if scene_ok := load_gltf_file_into(&ren, "assets/Box/Box.gltf", &scene); !scene_ok {
		log.errorf("Could not load scene")
		return
	}


	camera_position := linalg.Vector3f32{0, 0, -8}
	camera_rotation := linalg.Vector2f32{0, 0}
	camera_rotation_y_bounds := f32(80.0)
	camera_speed := f32(10.0)
	camera_sensitivity := f32(80)

	keys: #sparse[sdl.Scancode]bool
	keys_frame: #sparse[sdl.Scancode]enum {
		none,
		up,
		down,
	}
	mouse_buttons: [Mouse_Button]bool
	scroll: [2]f32
	mouse_delta: [2]f32

	start_time := time.now()
	delta := f32(0.0)

	mouse_grabbed := false

	tile :: 10

	offset := linalg.MATRIX4F32_IDENTITY
	@(static) creating_objs: small_array.Small_Array(tile * tile * tile, Object_Data)
	// draw in grid
	for i in 0 ..< tile {
		for j in 0 ..< tile {
			for k in 0 ..< tile {
				small_array.append_elem(
					&creating_objs,
					Object_Data {
						transform = linalg.matrix4_translate_f32(
							{
								(f32(i) - tile / 2) * 4,
								(f32(j) - tile / 2) * 4,
								(f32(k) - tile / 2) * 4,
							},
						) *
						offset *
						linalg.matrix4_scale_f32({10, 10, 10}),
						geometry = scene.meshes[0][0].handle,
						material = scene.materials[0],
					},
				)
			}
		}
	}
	start_object: Object_Handle
	object_count := small_array.len(creating_objs)
	if first_object, err := ren_add_objects(&ren, ..small_array.slice(&creating_objs));
	   err != .Ok {
		log.panicf("Could not add object: {}", err)
	} else {
		start_object = first_object
	}

	running := true
	is_fullscreen := false
	for running {
		defer {
			diff := time.diff(start_time, time.now())
			delta = f32(time.duration_seconds(diff))
			start_time = time.now()

			mouse_delta = {}
			keys_frame = {}
			scroll = {}
		}

		free_all(context.temp_allocator)
		for ev: sdl.Event; sdl.PollEvent(&ev); {
			#partial switch ev.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				keys[ev.key.keysym.scancode] = true
				if ev.key.keysym.sym == .F {
					sdl.SetWindowFullscreen(
						window,
						sdl.WINDOW_FULLSCREEN_DESKTOP if !is_fullscreen else {.RESIZABLE},
					)
					is_fullscreen = !is_fullscreen
				}
				keys_frame[ev.key.keysym.scancode] = .down
			case .KEYUP:
				keys[ev.key.keysym.scancode] = false
				keys_frame[ev.key.keysym.scancode] = .up
			case .WINDOWEVENT:
				#partial switch ev.window.event {
				case .RESIZED:
					w := ev.window.data1
					h := ev.window.data2

					renderer_resize(&ren, {w, h})
				case .FOCUS_LOST:
					keys = {}
				}
			case .MOUSEBUTTONDOWN:
				mouse_buttons[Mouse_Button(ev.button.button)] = true
			case .MOUSEBUTTONUP:
				mouse_buttons[Mouse_Button(ev.button.button)] = false
			case .MOUSEWHEEL:
				scroll[0] = f32(ev.wheel.x)
				scroll[1] = f32(ev.wheel.y)
			case .MOUSEMOTION:
				mouse_delta[0] = f32(ev.motion.xrel)
				mouse_delta[1] = f32(ev.motion.yrel)
			}
		}

		// if mouse right down, capture mouse, if not then release
		if mouse_buttons[.Right] {
			if !mouse_grabbed {
				sdl.SetRelativeMouseMode(true)
				mouse_grabbed = true
			}
		} else {
			if mouse_grabbed {
				sdl.SetRelativeMouseMode(false)
				mouse_grabbed = false
			}
		}

		ren_refresh_all_pipelines(&ren) or_break

		camera_projection := linalg.matrix4_perspective_f32(
			45 * math.PI / 180.0,
			f32(ren.window_size.x) / f32(ren.window_size.y),
			0.1,
			1000.0,
		)

		if mouse_buttons[.Right] {
			camera_rotation.x -= mouse_delta.x * camera_sensitivity * delta
			if camera_rotation.x >= 360.0 do camera_rotation.x -= 360.0
			if camera_rotation.x < 0.0 do camera_rotation.x += 360.0
			camera_rotation.y += mouse_delta.y * camera_sensitivity * delta
			camera_rotation.y = clamp(
				camera_rotation.y,
				-camera_rotation_y_bounds,
				camera_rotation_y_bounds,
			)
		}
		x_quat := linalg.quaternion_angle_axis_f32(
			math.to_radians_f32(camera_rotation.x),
			{0, 1, 0},
		)
		y_quat := linalg.quaternion_angle_axis_f32(
			math.to_radians_f32(camera_rotation.y),
			{1, 0, 0},
		)
		camera_quat_rotation := x_quat * y_quat

		forward := linalg.quaternion128_mul_vector3(
			camera_quat_rotation,
			linalg.Vector3f32{0, 0, 1},
		)
		right := linalg.quaternion128_mul_vector3(camera_quat_rotation, linalg.Vector3f32{1, 0, 0})
		up := linalg.quaternion128_mul_vector3(camera_quat_rotation, linalg.Vector3f32{0, 1, 0})

		speed_adjusted := camera_speed * delta * (0.35 if keys[.LSHIFT] else 1)

		if keys[.W] do camera_position += forward * speed_adjusted
		if keys[.S] do camera_position -= forward * speed_adjusted
		if keys[.D] do camera_position -= right * speed_adjusted
		if keys[.A] do camera_position += right * speed_adjusted
		if keys[.Q] do camera_position -= up * speed_adjusted
		if keys[.E] do camera_position += up * speed_adjusted

		if scroll.y != 0 {
			camera_position += forward * scroll.y
		}

		camera_view := linalg.matrix4_look_at_f32(
			camera_position,
			camera_position + forward,
			{0, 1, 0},
		)

		ren.resource_pool.frame_constants.view = camera_view
		ren.resource_pool.frame_constants.projection = camera_projection
		ren.resource_pool.frame_constants.light_color = {100, 100, 100, 1}
		ren.resource_pool.frame_constants.light_dir = {1, 1, 1, 0}
		copy_frame_constants(&ren.resource_pool)

		cmd := begin_rendering(&ren) or_break
		defer if end_rendering(&ren) == false {
			running = false
		}
		frame := get_render_frame(&ren)

		ren.instance->cmd_barrier(
			cmd,
			{
				textures = {
					{
						texture = frame.texture,
						after = mercury.ACCESS_LAYOUT_STAGE_COLOR_ATTACHMENT,
					},
				},
			},
		)
		defer ren.instance->cmd_barrier(
			cmd,
			{
				textures = {
					{
						texture = frame.texture,
						before = mercury.ACCESS_LAYOUT_STAGE_COLOR_ATTACHMENT,
						after = mercury.ACCESS_LAYOUT_STAGE_PRESENT,
					},
				},
			},
		)

		ren.instance->cmd_begin_rendering(
			cmd,
			{colors = {frame.srv}, depth_stencil = ren.depth_stencil.dsv},
		)
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
				{value = mercury.Depth_Stencil{depth = 1.0, stencil = 0}, planes = {.Depth}},
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

		ren_set_pipeline_layout(&ren, cmd, graphics_layout)
		ren_set_pipeline(&ren, cmd, forward_pipeline)
		ren_buffer_set_vertex(&ren.resource_pool.buffers[.Vertex], &ren, cmd, 0, 0)
		ren_buffer_set_index(&ren.resource_pool.buffers[.Index], &ren, cmd, 0, .Uint16)
		ren_bind_draw_constants_ds(&ren, cmd, 0)
		ren_bind_resource_ds(&ren, cmd, 1)

		ren_draw_objects_assume_same_primitive(&ren, start_object, auto_cast object_count)
		ren_flush_draws(&ren, cmd)

		// if keys_frame[.R] == .down {
		// 	tile += 1
		// 	log.infof("total: {}", tile * tile * tile)
		// }
	}

	renderer_wait_idle(&ren)
}

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
