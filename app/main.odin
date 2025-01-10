package app

import "core:container/small_array"
import "core:encoding/cbor"
@(require) import "core:fmt"
import "core:io"
import "core:log"
import "core:math"
import "core:math/linalg"
@(require) import "core:mem"
import "core:os"
import "core:slice"
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

	session: Shader_Context
	slang_ok := create_shader_context(&session)
	if !slang_ok {
		log.errorf("Could not create global session")
		return
	}
	defer destroy_shader_context(&session)

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

	draw_dispatch, ok_dispatch := compile_shader(
		&session,
		"assets/draw_dispatch.slang",
		{.Compute_Shader},
		allocator = context.temp_allocator,
	)
	if !ok_dispatch {
		log.errorf("Could not compile shader")
		return
	}
	log_shader(draw_dispatch)

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
	encode_cbor_to_file("draw_dispatch.enshader", draw_dispatch)

	forward_pipeline_layout, forward_pipeline_layout_err := ren.instance->create_pipeline_layout(
		ren.device,
		{
			constants = {{size = size_of(Frame_Constants), shader_stages = {.Vertex_Shader}}},
			descriptor_sets = {
				resource_pool_frame_constants_descriptor_desc(
					0,
					{.Vertex_Shader, .Fragment_Shader},
				),
				resource_pool_resource_descriptor_desc(1, {.Vertex_Shader, .Fragment_Shader}),
			},
			shader_stages = {.Vertex_Shader, .Fragment_Shader},
			constants_register_space = 2,
			enable_d3d12_draw_parameters_emulation = true,
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

	// has constants for the number of draws to dispatch
	draw_dispatch_pipeline_layout, draw_dispatch_pipeline_layout_err := ren.instance->create_pipeline_layout(
		ren.device,
		{
			constants_register_space = 1,
			constants                = {{size = size_of(u32), shader_stages = {.Compute_Shader}}}, // 4 bytes
			descriptor_sets          = {resource_pool_draws_descriptor_desc(0, {.Compute_Shader})},
			shader_stages            = {.Compute_Shader},
		},
	)
	if draw_dispatch_pipeline_layout_err != nil {
		log.errorf("Could not create pipeline layout: {}", draw_dispatch_pipeline_layout_err)
		return
	}
	defer ren.instance->destroy_pipeline_layout(draw_dispatch_pipeline_layout)
	ren.instance->set_pipeline_layout_debug_name(
		draw_dispatch_pipeline_layout,
		"Draw Dispatch Pipeline Layout",
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
				cull_mode = .Back,
				front_counter_clockwise = true,
			},
			output_merger = {
				colors = {{format = .RGBA8_UNORM, color_write_mask = mercury.Color_Write_RGBA}},
				depth = {write = true, compare_func = .Less},
				depth_stencil_format = .D32_SFLOAT,
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

	draw_dispatch_pipeline, draw_dispatch_pipeline_err := ren.instance->create_compute_pipeline(
		ren.device,
		{
			pipeline_layout = draw_dispatch_pipeline_layout,
			shader = {bytecode = draw_dispatch[.Compute], entry_point_name = "cs_main"},
		},
	)
	if draw_dispatch_pipeline_err != nil {
		log.errorf("Could not create pipeline: {}", draw_dispatch_pipeline_err)
		return
	}
	defer ren.instance->destroy_pipeline(draw_dispatch_pipeline)
	ren.instance->set_pipeline_debug_name(draw_dispatch_pipeline, "Draw Dispatch Pipeline")

	scene: Scene
	init_scene(&scene, &ren)
	defer deinit_scene(&scene, &ren)

	if scene_ok := load_gltf_file_into(&ren, "assets/Box/Box.gltf", &scene); !scene_ok {
		log.errorf("Could not load scene")
		return
	}

	if scene_ok := load_gltf_file_into(&ren, "assets/Avocado/Avocado.gltf", &scene); !scene_ok {
		log.errorf("Could not load scene")
		return
	}


	// transform_0: Instance_Handle
	// {
	// 	t, transform_add_ok := resource_pool_add_instance(
	// 		&ren.resource_pool,
	// 		&ren,
	// 		{
	// 			transform = linalg.matrix4_scale_f32({10, 10, 10}),
	// 			primitive = scene.meshes[0][0].handle,
	// 			material = scene.meshes[0][0].material,
	// 		},
	// 	)
	// 	if !transform_add_ok {
	// 		log.errorf("Could not add transform")
	// 		return
	// 	}
	// 	transform_0 = t
	// }

	// transform_1: Instance_Handle
	// {
	// 	t, transform_add_ok := resource_pool_add_instance(
	// 		&ren.resource_pool,
	// 		&ren,
	// 		{
	// 			transform = linalg.matrix4_translate_f32({1, 3, 1}) *
	// 			linalg.matrix4_scale_f32({10, 10, 10}),
	// 			primitive = scene.meshes[0][0].handle,
	// 			material = scene.meshes[0][0].material,
	// 		},
	// 	)
	// 	if !transform_add_ok {
	// 		log.errorf("Could not add transform")
	// 		return
	// 	}
	// 	transform_1 = t
	// }

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

	x_size := 16
	y_size := 16

	offset := linalg.MATRIX4F32_IDENTITY
	@(static) objects: small_array.Small_Array(1600, Object_Data)
	// draw in grid
	for i in 0 ..< x_size {
		for j in 0 ..< y_size {
			small_array.append_elem(
				&objects,
				Object_Data {
					transform = linalg.matrix4_translate_f32({f32(i), 0, f32(j)}) *
					offset *
					linalg.matrix4_scale_f32({0.8, 0.8, 0.8}),
					geometry = scene.meshes[0][0].handle,
					material = scene.materials[0],
				},
			)
		}
	}
	if err := resource_pool_add_object(&ren, ..small_array.slice(&objects)); err != .Ok {
		log.panicf("Could not add object: {}", err)
	}
	small_array.clear(&objects)

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

		cmd := begin_rendering(&ren) or_break
		defer if end_rendering(&ren) == false {
			running = false
		}

		frame := get_render_frame(&ren)

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
		copy_frame_constants(&ren.resource_pool)

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

		ren.instance->cmd_set_pipeline_layout(cmd, forward_pipeline_layout)
		ren.instance->cmd_set_pipeline(cmd, forward_pipeline)
		ren.instance->cmd_set_vertex_buffers(cmd, 0, {ren.resource_pool.vertex_buffer.buffer}, {0})
		ren.instance->cmd_set_index_buffer(cmd, ren.resource_pool.index_buffer.buffer, 0, .Uint16)
		bind_descriptor_sets(&ren)

		draw_objects :: proc(
			ren: ^Renderer,
			draw_dispatch_pipeline_layout: ^mercury.Pipeline_Layout,
			draw_dispatch_pipeline: ^mercury.Pipeline,
			cmd: ^mercury.Command_Buffer,
		) -> bool {
			{
				compute_cmd := begin_compute(ren) or_return
				ren.instance->cmd_set_pipeline_layout(compute_cmd, draw_dispatch_pipeline_layout)
				ren.instance->cmd_set_pipeline(compute_cmd, draw_dispatch_pipeline)
				ren.instance->cmd_set_descriptor_set(
					compute_cmd,
					0,
					ren.resource_pool.gpu_draw_descriptor_set,
				)
				ren.instance->cmd_set_constants(compute_cmd, 0, {ren.resource_pool.draw_count})
				ren.instance->cmd_dispatch(compute_cmd, {ren.resource_pool.draw_count, 1, 1})
				val := end_compute(ren)
				wait_compute(ren, val) or_return
			}
			ren.instance->cmd_draw_indexed_indirect(
				cmd,
				buffer = ren.resource_pool.draw_argument_buffer.buffer,
				offset = size_of(Draw_Batch_Readback),
				draw_num = ren.resource_pool.draw_count,
				stride = size_of(mercury.Draw_Indexed_Emulated_Desc),
				count_buffer = ren.resource_pool.draw_argument_buffer.buffer,
				count_buffer_offset = 0,
			)
			return true
		}
		draw_objects(&ren, draw_dispatch_pipeline_layout, draw_dispatch_pipeline, cmd) or_break

		// draw indirect

		draw :: proc(
			ren: ^Renderer,
			#by_ptr scene: Scene,
			cmd: ^mercury.Command_Buffer,
			object: Object_Data,
			index: u32,
		) {
			object := object
			constants := slice.reinterpret(
				[]u32,
				slice.bytes_from_ptr(&object, size_of(Object_Data)),
			)
			ren.instance->cmd_set_constants(cmd, 0, constants)
			geom := ren.resource_pool.cpu_geometries[object.geometry]
			ren.instance->cmd_draw_indexed(
				cmd,
				{
					index_num = u32(geom.index_count),
					instance_num = 1,
					base_index = geom.index_offset,
					base_vertex = geom.vertex_offset,
					base_instance = index,
				},
			)
		}

		if keys_frame[.R] == .down {
			x_size += 1
			log.infof("total: {}", x_size * y_size)
		}

		if keys_frame[.T] == .down {
			y_size += 1
			log.infof("total: {}", x_size * y_size)
		}

		// draw in grid
		// for i in 0 ..< x_size {
		// 	for j in 0 ..< y_size {
		// 		draw(
		// 			&ren,
		// 			scene,
		// 			cmd,
		// 			{
		// 				transform = linalg.matrix4_translate_f32({f32(i), 0, f32(j)}) *
		// 				offset *
		// 				linalg.matrix4_scale_f32({10, 10, 10}),
		// 				geometry = scene.meshes[0][0].handle,
		// 				material = scene.materials[0],
		// 			},
		// 			u32(i * y_size + j),
		// 		)
		// 	}
		// }

		// draw_primitive(&ren, scene, cmd, 1)
		// draw_primitive(&ren, scene, cmd, 0)

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
