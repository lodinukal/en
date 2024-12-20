package app

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"

import gpu "en:gpu"
import sdl "vendor:sdl2"

FRAME_BUF_NUM :: 3

Renderer :: struct {
	window:           ^sdl.Window,
	window_size:      [2]c.int,
	// gpu resources
	instance:         ^gpu.Instance,
	device:           ^gpu.Device,
	// sync
	main_fence:       ^gpu.Fence,
	main_fence_value: u64,
	graphics_queue:   ^gpu.Command_Queue,
	swapchain:        ^gpu.Swapchain,
	// frame
	frame_index:      u64,
}

init_renderer :: proc(ren: ^Renderer) -> (ok: bool) {
	assert(ren != nil, "Renderer is nil")
	assert(ren.window != nil, "Window is nil")

	gpu_err: gpu.Error

	ren.instance, gpu_err = gpu.create_instance(.D3D12, true)
	check_gpu(gpu_err, "Could not create instance") or_return

	ren.device, gpu_err =
	ren.instance->create_device({enable_validation = true, enable_graphics_api_validation = true})
	check_gpu(gpu_err, "Could not create device") or_return
	ren.instance->set_device_debug_name(ren.device, "en device")

	ren.main_fence, gpu_err = ren.instance->create_fence(ren.device)
	check_gpu(gpu_err, "Could not create fence") or_return

	desc := ren.instance->get_device_desc(ren.device)
	fmt.printfln("Adapter Name: {}", string(desc.adapter_desc.name[:]))

	ren.graphics_queue, gpu_err = ren.instance->get_command_queue(ren.device, .Graphics)
	check_gpu(gpu_err, "Could not get command queue") or_return

	sdl.GetWindowSize(ren.window, &ren.window_size.x, &ren.window_size.y)

	sys_info: sdl.SysWMinfo
	sdl.GetWindowWMInfo(ren.window, &sys_info)

	ren.swapchain, gpu_err =
	ren.instance->create_swapchain(
		ren.device,
		{
			command_queue = ren.graphics_queue,
			size = {auto_cast ren.window_size.x, auto_cast ren.window_size.y},
			texture_num = FRAME_BUF_NUM,
			window = {
				windows = {hwnd = sys_info.info.win.window},
				cocoa = {ns_window = sys_info.info.cocoa.window},
				x11 = {window = rawptr(sys_info.info.x11.window)},
				wayland = {surface = sys_info.info.wl.surface},
			},
			vsync_interval = 0,
		},
	)
	check_gpu(gpu_err, "Could not create swapchain") or_return

	return true
}

renderer_wait_idle :: proc(ren: ^Renderer) {
	// wait for the current frame to finish rendering
	ren.instance->wait_fence_now(ren.main_fence, ren.main_fence_value)
}

renderer_resize :: proc(ren: ^Renderer, size: [2]c.int) {
	renderer_wait_idle(ren)
	ren.window_size = size
	ren.instance->resize_swapchain(ren.swapchain, auto_cast size.x, auto_cast size.y)
}

destroy_renderer :: proc(ren: ^Renderer) {
	renderer_wait_idle(ren)
	ren.instance->destroy_swapchain(ren.swapchain)
	ren.instance->destroy_fence(ren.main_fence)
	ren.instance->destroy_device(ren.device)
	ren.instance->destroy()
}

begin_rendering :: proc(ren: ^Renderer) {
	if ren.frame_index >= FRAME_BUF_NUM {
		ren.instance->wait_fence_now(ren.main_fence, 1 + ren.frame_index - FRAME_BUF_NUM)
	}
}
// rendering logic between begin_rendering and end_rendering
end_rendering :: proc(ren: ^Renderer) {
	ren.instance->present(ren.swapchain)
	ren.frame_index += 1
	ren.instance->signal_fence(ren.graphics_queue, ren.main_fence, ren.frame_index)
}

@(private = "file")
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
