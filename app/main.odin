package app

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"

import gpu "en:gpu"
// import nri "en:nri"
import sdl "vendor:sdl2"

main :: proc() {
	if !init() {
		os.exit(1)
	}
}


FRAME_BUF_NUM :: 2

init :: proc() -> bool {
	logger := log.create_console_logger(ident = "en")
	defer log.destroy_console_logger(logger)
	context.logger = logger

	log.infof("en")
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

	instance, instance_err := gpu.create_instance(.D3D12, true)
	check_gpu(instance_err, "Could not create instance") or_return
	defer instance->destroy()

	device, device_err := instance->create_device(
		{enable_validation = true, enable_graphics_api_validation = true},
	)
	check_gpu(device_err, "Could not create device") or_return
	defer instance->destroy_device(device)
	instance->set_device_debug_name(device, "en device")

	fence, fence_err := instance->create_fence(device)
	check_gpu(fence_err, "Could not create fence") or_return
	defer instance->destroy_fence(fence)

	desc := instance->get_device_desc(device)
	fmt.printfln("Adapter Name: {}", string(desc.adapter_desc.name[:]))

	queue, queue_err := instance->get_command_queue(device, .Graphics)
	check_gpu(queue_err, "Could not get command queue") or_return

	descriptor_pool, descriptor_pool_err := instance->create_descriptor_pool(
		device,
		{
			descriptor_set_max_num = 10,
			sampler_max_num = 1,
			texture_max_num = 10,
			buffer_max_num = 10,
		},
	)
	check_gpu(descriptor_pool_err, "Could not create descriptor pool") or_return
	defer instance->destroy_descriptor_pool(descriptor_pool)

	descriptor_set_1_desc: gpu.Descriptor_Set_Desc = {
		register_space = 0,
		ranges         = {gpu.buffer_range()},
	}

	descriptor_set_1, descriptor_set_1_err := instance->allocate_descriptor_set(
		descriptor_pool,
		descriptor_set_1_desc,
	)
	check_gpu(descriptor_set_1_err, "Could not allocate descriptor set 1") or_return

	pipeline_layout_desc: gpu.Pipeline_Layout_Desc = {
		descriptor_sets                        = {descriptor_set_1_desc},
		shader_stages                          = {.Vertex_Shader, .Fragment_Shader},
		enable_d3d12_draw_parameters_emulation = true,
	}
	pipeline_layout, pipeline_layout_err := instance->create_pipeline_layout(
		device,
		pipeline_layout_desc,
	)
	check_gpu(pipeline_layout_err, "Could not create pipeline layout") or_return
	defer instance->destroy_pipeline_layout(pipeline_layout)

	w, h: c.int
	sdl.GetWindowSize(window, &w, &h)

	sys_info: sdl.SysWMinfo
	sdl.GetWindowWMInfo(window, &sys_info)

	swapchain, swapchain_err := instance->create_swapchain(
		device,
		{
			command_queue = queue,
			width = auto_cast w,
			height = auto_cast h,
			texture_num = FRAME_BUF_NUM,
			window = {
				windows = {hwnd = sys_info.info.win.window},
				cocoa = {ns_window = sys_info.info.cocoa.window},
				x11 = {window = rawptr(sys_info.info.x11.window)},
				wayland = {surface = sys_info.info.wl.surface},
			},
		},
	)
	check_gpu(swapchain_err, "Could not create swapchain") or_return
	defer instance->destroy_swapchain(swapchain)

	frame_index: u64 = 0
	is_fullscreen := false
	quit := false

	defer instance->wait_fence_now(fence, frame_index)

	for !quit {
		if frame_index >= FRAME_BUF_NUM {
			instance->wait_fence_now(fence, 1 + frame_index - FRAME_BUF_NUM)
		}

		for ev: sdl.Event; sdl.PollEvent(&ev); {
			#partial switch ev.type {
			case .WINDOWEVENT:
				#partial switch ev.window.event {
				case .RESIZED:
					w = ev.window.data1
					h = ev.window.data2

					instance->wait_fence_now(fence, frame_index)

					log.infof("Window Resized: {}x{}", w, h)
					instance->resize_swapchain(swapchain, auto_cast w, auto_cast h)
				}
			case .KEYDOWN:
				if ev.key.keysym.sym == .F {
					sdl.SetWindowFullscreen(
						window,
						sdl.WINDOW_FULLSCREEN_DESKTOP if !is_fullscreen else {.RESIZABLE},
					)
					is_fullscreen = !is_fullscreen
				}
			case .QUIT:
				quit = true
			}
		}

		// log.infof("backbuffer: {}", instance->acquire_next_texture(swapchain))
		instance->present(swapchain)
		frame_index += 1
		instance->signal_fence(queue, fence, frame_index)
	}
	return true
}

check_gpu :: proc(
	error: gpu.Error,
	fmt_str: string,
	args: ..any,
	loc := #caller_location,
) -> bool {
	if error != nil {
		log.errorf("{}", error, location = loc)
		log.errorf(fmt_str, ..args, location = loc)
		return false
	}
	return true
}
