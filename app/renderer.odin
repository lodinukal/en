package app

import "core:c"
import "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"

import "en:mercury"
import sdl "vendor:sdl2"

FRAME_BUF_NUM :: 3

Frame :: struct {
	allocator: ^mercury.Command_Allocator,
	cmd:       ^mercury.Command_Buffer,
	texture:   ^mercury.Texture,
	srv:       ^mercury.Descriptor,
}

Renderer :: struct {
	window:           ^sdl.Window,
	window_size:      [2]c.int,
	// gpu resources
	instance:         ^mercury.Instance,
	device:           ^mercury.Device,
	// sync
	main_fence:       ^mercury.Fence,
	graphics_queue:   ^mercury.Command_Queue,
	swapchain:        ^mercury.Swapchain,
	// frame
	frame_index:      u64,
	frames:           small_array.Small_Array(FRAME_BUF_NUM, Frame),
	backbuffer_index: int,
	depth_desc:       mercury.Texture_Desc,
	depth_stencil:    Texture,
	// transfer
	transfer:         struct {
		in_progress:  bool,
		queue:        ^mercury.Command_Queue,
		allocator:    ^mercury.Command_Allocator,
		buffer:       ^mercury.Command_Buffer,
		fence:        ^mercury.Fence,
		fence_value:  u64,
		free_buffers: [dynamic]Ren_Buffer,
		eph_id:       u64,
	},
	compute:          struct {
		in_progress: bool,
		queue:       ^mercury.Command_Queue,
		allocator:   ^mercury.Command_Allocator,
		buffer:      ^mercury.Command_Buffer,
		fence:       ^mercury.Fence,
		fence_value: u64,
	},
	// descriptor
	descriptor_pool:  ^mercury.Descriptor_Pool,
	// components
	resource_pool:    Resource_Pool,
}

init_renderer :: proc(ren: ^Renderer) -> (ok: bool) {
	assert(ren != nil, "Renderer is nil")
	assert(ren.window != nil, "Window is nil")

	gpu_err: mercury.Error

	ren.instance, gpu_err = mercury.create_instance(.D3D12, true)
	check_gpu(gpu_err, "Could not create instance") or_return

	ren.device, gpu_err =
	ren.instance->create_device(
		{
			enable_validation = true,
			enable_graphics_api_validation = true,
			requirements = render_components_resource_requirements,
		},
	)
	check_gpu(gpu_err, "Could not create device") or_return
	ren.instance->set_device_debug_name(ren.device, "en device")

	ren.main_fence, gpu_err = ren.instance->create_fence(ren.device, 0)
	check_gpu(gpu_err, "Could not create fence") or_return

	desc := ren.instance->get_device_desc(ren.device)
	fmt.printfln("Adapter Name: {}", string(desc.adapter_desc.name[:]))

	ren.graphics_queue, gpu_err = ren.instance->get_command_queue(ren.device, .Graphics)
	check_gpu(gpu_err, "Could not get command queue") or_return
	ren.instance->set_command_queue_debug_name(ren.graphics_queue, "Graphics queue")

	sdl.GetWindowSize(ren.window, &ren.window_size.x, &ren.window_size.y)

	sys_info: sdl.SysWMinfo
	sdl.GetWindowWMInfo(ren.window, &sys_info)

	// inits the transfer
	ren.transfer.queue, gpu_err = ren.instance->create_command_queue(ren.device, .Graphics)
	check_gpu(gpu_err, "Could not create transfer queue") or_return
	ren.transfer.allocator, gpu_err = ren.instance->create_command_allocator(ren.transfer.queue)
	check_gpu(gpu_err, "Could not create transfer allocator") or_return
	ren.transfer.buffer, gpu_err = ren.instance->create_command_buffer(ren.transfer.allocator)
	check_gpu(gpu_err, "Could not create transfer buffer") or_return
	ren.transfer.fence, gpu_err = ren.instance->create_fence(ren.device, ren.transfer.fence_value)
	check_gpu(gpu_err, "Could not create transfer fence") or_return

	ren.instance->set_command_queue_debug_name(ren.transfer.queue, "Transfer queue")
	ren.instance->set_command_allocator_debug_name(ren.transfer.allocator, "Transfer allocator")
	ren.instance->set_command_buffer_debug_name(ren.transfer.buffer, "Transfer buffer")
	ren.instance->set_fence_debug_name(ren.transfer.fence, "Transfer fence")

	// inits the compute
	ren.compute.queue, gpu_err = ren.instance->create_command_queue(ren.device, .Compute)
	check_gpu(gpu_err, "Could not create compute queue") or_return
	ren.compute.allocator, gpu_err = ren.instance->create_command_allocator(ren.compute.queue)
	check_gpu(gpu_err, "Could not create compute allocator") or_return
	ren.compute.buffer, gpu_err = ren.instance->create_command_buffer(ren.compute.allocator)
	check_gpu(gpu_err, "Could not create compute buffer") or_return
	ren.compute.fence, gpu_err = ren.instance->create_fence(ren.device, ren.compute.fence_value)
	check_gpu(gpu_err, "Could not create compute fence") or_return

	ren.instance->set_command_queue_debug_name(ren.compute.queue, "Compute queue")
	ren.instance->set_command_allocator_debug_name(ren.compute.allocator, "Compute allocator")
	ren.instance->set_command_buffer_debug_name(ren.compute.buffer, "Compute buffer")
	ren.instance->set_fence_debug_name(ren.compute.fence, "Compute fence")

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
			immediate = true,
		},
	)
	check_gpu(gpu_err, "Could not create swapchain") or_return

	small_array.resize(&ren.frames, FRAME_BUF_NUM)
	renderer_acquire_swapchain_resources(ren)
	for &frame, index in small_array.slice(&ren.frames) {
		frame.allocator, gpu_err = ren.instance->create_command_allocator(ren.graphics_queue)
		check_gpu(gpu_err, "Could not create frame command allocator {}", index) or_return
		ren.instance->set_command_allocator_debug_name(
			frame.allocator,
			fmt.tprintf("Frame command allocator {}", index),
		)

		frame.cmd, gpu_err = ren.instance->create_command_buffer(frame.allocator)
		check_gpu(gpu_err, "Could not create frame command buffer {}", index) or_return
		ren.instance->set_command_buffer_debug_name(
			frame.cmd,
			fmt.tprintf("Frame command buffer {}", index),
		)
	}

	// descriptor pool
	ren.descriptor_pool, gpu_err =
	ren.instance->create_descriptor_pool(ren.device, render_components_descriptor_requirements)
	check_gpu(gpu_err, "Could not create descriptor pool") or_return

	// image pool
	if ok_init_resource_pool := init_resource_pool(&ren.resource_pool, ren);
	   ok_init_resource_pool == false {
		return false
	}

	return true
}

renderer_wait_idle :: proc(ren: ^Renderer) {
	// wait for the current frame to finish rendering
	ren.instance->wait_fence_now(ren.main_fence, ren.frame_index)
}

renderer_resize :: proc(ren: ^Renderer, size: [2]c.int) {
	renderer_wait_idle(ren)
	ren.window_size = size
	result := ren.instance->resize_swapchain(ren.swapchain, auto_cast size.x, auto_cast size.y)
	if result != nil {
		log.errorf("Could not resize swapchain: {}", result)
		return
	}
	renderer_acquire_swapchain_resources(ren)
}

renderer_cleanup_swapchain_resources :: proc(ren: ^Renderer) {
	for &frame in small_array.slice(&ren.frames) {
		if frame.srv != nil {
			ren.instance->destroy_descriptor(ren.device, frame.srv)
			frame.srv = nil
			frame.texture = nil
		}
	}

	if ren.depth_stencil.texture != nil {
		deinit_ren_texture(&ren.depth_stencil, ren)
	}
}

renderer_acquire_swapchain_resources :: proc(ren: ^Renderer) {
	renderer_cleanup_swapchain_resources(ren)

	textures: [FRAME_BUF_NUM]^mercury.Texture
	gpu_err: mercury.Error
	ren.instance->get_swapchain_textures(ren.swapchain, textures[:])
	for texture, index in textures {
		if texture == nil do continue
		ren.frames.data[index].srv, gpu_err =
		ren.instance->create_2d_texture_view(
			ren.device,
			{texture = texture, view_type = .Color_Attachment, format = .RGBA8_UNORM},
		)
		check_gpu(gpu_err, "Could not create srv for swapchain texture {}", index)
		ren.frames.data[index].texture = texture
	}

	ren.depth_desc = {
		type      = ._2D,
		format    = .D32_SFLOAT,
		usage     = {.Depth_Stencil_Attachment, .Shader_Resource},
		width     = u16(ren.window_size.x),
		height    = u16(ren.window_size.y),
		layer_num = 1,
		mip_num   = 1,
	}
	ren.depth_stencil.desc = ren.depth_desc
	init_ren_texture(&ren.depth_stencil, ren)
	ren_texture_set_name(&ren.depth_stencil, "depth stencil", ren)
	ren_texture_barrier(
		&ren.depth_stencil,
		mercury.ACCESS_LAYOUT_STAGE_DEPTH_STENCIL_ATTACHMENT_WRITE,
		ren,
	)
	val := end_transfer(ren)
	wait_transfer(ren, val)
}

destroy_renderer :: proc(ren: ^Renderer) {
	renderer_wait_idle(ren)

	// destroy components
	destroy_resource_pool(&ren.resource_pool, ren)

	// destroy descriptor pool
	ren.instance->destroy_descriptor_pool(ren.descriptor_pool)

	// destroy compute resources
	wait_compute(ren, ren.compute.fence_value)
	ren.instance->destroy_fence(ren.compute.fence)
	ren.instance->destroy_command_buffer(ren.compute.buffer)
	ren.instance->destroy_command_allocator(ren.compute.allocator)
	ren.instance->destroy_command_queue(ren.compute.queue)

	// destroy transfer resources
	wait_transfer(ren, ren.transfer.fence_value)
	ren.instance->destroy_fence(ren.transfer.fence)
	ren.instance->destroy_command_buffer(ren.transfer.buffer)
	ren.instance->destroy_command_allocator(ren.transfer.allocator)
	ren.instance->destroy_command_queue(ren.transfer.queue)
	for &buffer in ren.transfer.free_buffers {
		deinit_ren_buffer(&buffer, ren)
	}
	delete(ren.transfer.free_buffers)

	renderer_cleanup_swapchain_resources(ren)
	for &frame in small_array.slice(&ren.frames) {
		if frame.cmd != nil {
			ren.instance->destroy_command_buffer(frame.cmd)
		}
		if frame.allocator != nil {
			ren.instance->destroy_command_allocator(frame.allocator)
		}
	}

	ren.instance->destroy_swapchain(ren.swapchain)
	ren.instance->destroy_fence(ren.main_fence)
	ren.instance->destroy_device(ren.device)
	ren.instance->destroy()
}

get_render_frame :: proc(ren: ^Renderer) -> ^Frame {
	return small_array.get_ptr(&ren.frames, ren.backbuffer_index)
}

get_frame :: proc(ren: ^Renderer) -> ^Frame {
	return small_array.get_ptr(&ren.frames, int(ren.frame_index % FRAME_BUF_NUM))
}

begin_rendering :: proc(ren: ^Renderer) -> (cmd: ^mercury.Command_Buffer, ok: bool = true) {
	frame := small_array.get(ren.frames, int(ren.frame_index % FRAME_BUF_NUM))
	if ren.frame_index >= FRAME_BUF_NUM {
		result := ren.instance->wait_fence_now(ren.main_fence, 1 + ren.frame_index - FRAME_BUF_NUM)
		check_gpu(result, "Could not wait for fence") or_return
		ren.instance->reset_command_allocator(frame.allocator)
	}
	cmd = frame.cmd
	check_gpu(
		ren.instance->begin_command_buffer(cmd),
		"Could not begin command buffer {}",
		ren.frame_index % FRAME_BUF_NUM,
	)
	ren.instance->cmd_set_descriptor_pool(cmd, ren.descriptor_pool)
	ren.backbuffer_index = int(ren.instance->acquire_next_texture(ren.swapchain))
	return
}
// rendering logic between begin_rendering and end_rendering
// end rendering will return false if it can no longer present the swapchain, aka crash 
end_rendering :: proc(ren: ^Renderer) -> (ok: bool = true) {
	frame := small_array.get(ren.frames, int(ren.frame_index % FRAME_BUF_NUM))
	check_gpu(
		ren.instance->end_command_buffer(frame.cmd),
		"Could not end command buffer {}",
		ren.frame_index % FRAME_BUF_NUM,
	)

	ren.instance->submit(ren.graphics_queue, {frame.cmd})

	result := ren.instance->present(ren.swapchain)
	check_gpu(result, "Could not present swapchain") or_return
	ren.frame_index += 1
	result = ren.instance->signal_fence(ren.graphics_queue, ren.main_fence, ren.frame_index)
	check_gpu(result, "Could not signal fence") or_return
	return
}

UPLOAD_PAGE_SIZE :: 64 * 1024 * 1024
begin_transfer :: proc(ren: ^Renderer) -> (buf: ^mercury.Command_Buffer, ok: bool = true) {
	if ren.transfer.in_progress {
		buf = ren.transfer.buffer
		return
	}
	ren.transfer.in_progress = true
	wait_transfer(ren, ren.transfer.fence_value) or_return
	ren.instance->reset_command_allocator(ren.transfer.allocator)
	ren.instance->begin_command_buffer(ren.transfer.buffer)
	buf = ren.transfer.buffer
	return
}

end_transfer :: proc(ren: ^Renderer) -> (wait: u64) {
	wait = ren.transfer.fence_value
	if !ren.transfer.in_progress {
		return
	}
	ren.transfer.in_progress = false
	err := ren.instance->end_command_buffer(ren.transfer.buffer)
	if check_gpu(err, "Could not end command buffer") == false {
		return
	}
	ren.instance->submit(ren.transfer.queue, {ren.transfer.buffer})
	ren.transfer.fence_value += 1
	err =
	ren.instance->signal_fence(ren.transfer.queue, ren.transfer.fence, ren.transfer.fence_value)
	if check_gpu(err, "Could not signal fence") == false {
		return
	}
	wait = ren.transfer.fence_value
	return
}

wait_transfer :: proc(ren: ^Renderer, value: u64) -> (ok: bool = true) {
	err := ren.instance->wait_fence_now(ren.transfer.fence, value)
	return check_gpu(err, "Could not wait for fence")
}


begin_compute :: proc(ren: ^Renderer) -> (buf: ^mercury.Command_Buffer, ok: bool = true) {
	if ren.compute.in_progress {
		buf = ren.compute.buffer
		return
	}
	ren.compute.in_progress = true
	wait_compute(ren, ren.compute.fence_value) or_return
	ren.instance->reset_command_allocator(ren.compute.allocator)
	ren.instance->begin_command_buffer(ren.compute.buffer)
	ren.instance->cmd_set_descriptor_pool(ren.compute.buffer, ren.descriptor_pool)
	buf = ren.compute.buffer
	return
}

end_compute :: proc(ren: ^Renderer) -> (wait: u64) {
	wait = ren.compute.fence_value
	if !ren.compute.in_progress {
		return
	}
	ren.compute.in_progress = false
	err := ren.instance->end_command_buffer(ren.compute.buffer)
	if check_gpu(err, "Could not end command buffer") == false {
		return
	}
	ren.instance->submit(ren.compute.queue, {ren.compute.buffer})
	ren.compute.fence_value += 1
	err = ren.instance->signal_fence(ren.compute.queue, ren.compute.fence, ren.compute.fence_value)
	if check_gpu(err, "Could not signal fence") == false {
		return
	}
	wait = ren.compute.fence_value
	return
}

wait_compute :: proc(ren: ^Renderer, value: u64) -> (ok: bool = true) {
	err := ren.instance->wait_fence_now(ren.compute.fence, value)
	return check_gpu(err, "Could not wait for fence")
}

acquire_eph_buffer :: proc(ren: ^Renderer, size: u64) -> (buf: Ren_Buffer) {
	if (size >= UPLOAD_PAGE_SIZE) {
		#reverse for buffer, index in ren.transfer.free_buffers {
			if buffer.desc.size >= size {
				unordered_remove(&ren.transfer.free_buffers, index)
				return buffer
			}
		}
	}

	if len(ren.transfer.free_buffers) == 0 || size >= UPLOAD_PAGE_SIZE {
		new_buffer := Ren_Buffer{}
		new_buffer.desc.size = max(size, UPLOAD_PAGE_SIZE)
		new_buffer.desc.location = .Device_Upload
		if check_gpu(init_ren_buffer(&new_buffer, ren), "Could not init resizable buffer") ==
		   false {
			return
		}
		ren_buffer_set_name(
			&new_buffer,
			fmt.tprintf("ephemeral buffer {}", ren.transfer.eph_id),
			ren,
		)
		ren.transfer.eph_id += 1
		append(&ren.transfer.free_buffers, new_buffer)
	}

	buf = pop(&ren.transfer.free_buffers)
	return
}

KEEP_BUFFER_COUNT :: 3
return_eph_buffer :: proc(ren: ^Renderer, buf: Ren_Buffer) {
	buf := buf
	buf.len = 0
	// if len(ren.transfer.free_buffers) >= KEEP_BUFFER_COUNT {
	// 	deinit_ren_buffer(&buf, ren)
	// 	return
	// }
	append(&ren.transfer.free_buffers, buf)
}

@(private = "file")
check_gpu :: proc(
	error: mercury.Error,
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

Ren_Buffer :: struct {
	buffer: ^mercury.Buffer,
	cbv:    ^mercury.Descriptor,
	srv:    ^mercury.Descriptor,
	uav:    ^mercury.Descriptor,
	desc:   mercury.Buffer_Desc,
	len:    u64,
	state:  mercury.Access_Stage,
	name:   string,
}

init_ren_buffer :: proc(buffer: ^Ren_Buffer, ren: ^Renderer) -> (error: mercury.Error) {
	old_size := buffer.desc.size
	buffer.desc.size = 0
	ren_buffer_resize(buffer, old_size, ren) or_return
	return
}

deinit_ren_buffer :: proc(buffer: ^Ren_Buffer, ren: ^Renderer) {
	if buffer.buffer != nil {
		ren.instance->destroy_buffer(buffer.buffer)
	}
	if buffer.cbv != nil {
		ren.instance->destroy_descriptor(ren.device, buffer.cbv)
	}
	if buffer.srv != nil {
		ren.instance->destroy_descriptor(ren.device, buffer.srv)
	}
	if buffer.uav != nil {
		ren.instance->destroy_descriptor(ren.device, buffer.uav)
	}
	buffer^ = {}
}

ren_buffer_ensure_unsed :: proc(
	buffer: ^Ren_Buffer,
	size: u64,
	ren: ^Renderer,
) -> (
	error: mercury.Error,
) {
	unused := buffer.desc.size - buffer.len
	if unused < size {
		ren_buffer_resize(buffer, buffer.len + size - unused, ren) or_return
	}
	return
}

ren_buffer_resize :: proc(
	buffer: ^Ren_Buffer,
	new_size: u64,
	ren: ^Renderer,
) -> (
	error: mercury.Error,
) {
	if u64(buffer.desc.size) >= new_size do return

	log.infof("resize from {} to {}", buffer.desc.size, new_size)

	old_size := buffer.desc.size
	buffer.desc.size = u64(new_size)
	new_buffer := ren.instance->create_buffer(ren.device, buffer.desc) or_return
	ren.instance->set_buffer_debug_name(new_buffer, buffer.name)

	// if had one then copy over
	if buffer.buffer != nil {
		{
			cmd, begin_ok := begin_transfer(ren)
			if !begin_ok {
				ren.instance->destroy_buffer(new_buffer)
				error = .Unknown
				return
			}
			defer {
				val := end_transfer(ren)
				wait_transfer(ren, val)
			}
			ren.instance->cmd_barrier(
				cmd,
				{
					buffers = {
						{
							buffer = buffer.buffer,
							before = buffer.state,
							after = mercury.ACCESS_STAGE_COPY_SOURCE,
						},
					},
				},
			)
			ren.instance->cmd_copy_buffer(cmd, new_buffer, 0, buffer.buffer, 0, old_size)
		}
		ren.instance->destroy_buffer(buffer.buffer)
	}
	buffer.buffer = new_buffer

	format: mercury.Format = .UNKNOWN
	if ren.instance.api == .D3D12 {
		format = .R32_UINT
	}

	if .Constant_Buffer in buffer.desc.usage {
		buffer.cbv = ren.instance->create_buffer_view(
			ren.device,
			{
				buffer = buffer.buffer,
				view_type = .Constant,
				size = buffer.desc.size,
				format = format,
			},
		) or_return
		ren.instance->set_descriptor_debug_name(buffer.cbv, buffer.name)
	}
	if .Shader_Resource in buffer.desc.usage {
		buffer.srv = ren.instance->create_buffer_view(
			ren.device,
			{
				buffer = buffer.buffer,
				view_type = .Shader_Resource,
				size = buffer.desc.size,
				format = format,
			},
		) or_return
		ren.instance->set_descriptor_debug_name(buffer.srv, buffer.name)
	}
	if .Shader_Resource_Storage in buffer.desc.usage {
		buffer.uav = ren.instance->create_buffer_view(
			ren.device,
			{
				buffer = buffer.buffer,
				view_type = .Shader_Resource_Storage,
				size = buffer.desc.size,
				format = format,
			},
		) or_return
		ren.instance->set_descriptor_debug_name(buffer.uav, buffer.name)
	}
	return
}

ren_buffer_append :: proc(
	buffer: ^Ren_Buffer,
	data: []u8,
	new_stage: mercury.Access_Stage,
	ren: ^Renderer,
	execute: bool = true,
) -> (
	error: mercury.Error,
) {
	new_size := buffer.len + u64(len(data))
	if buffer.desc.size < new_size {
		ren_buffer_resize(buffer, u64(new_size), ren) or_return
	}

	old_len := buffer.len
	ren_buffer_set(buffer, data, old_len, new_stage, ren, execute)
	buffer.len += u64(len(data))
	return
}

ren_buffer_append_typed :: proc(
	buffer: ^Ren_Buffer,
	value: $T,
	new_stage: mercury.Access_Stage,
	ren: ^Renderer,
) -> (
	error: mercury.Error,
	execute: bool = true,
) {
	return ren_buffer_append(
		buffer,
		slice.reinterpret([]u8, slice.bytes_from_ptr(&value, size_of(T))),
		new_stage,
		ren,
		execute,
	)
}

ren_buffer_set :: proc(
	buffer: ^Ren_Buffer,
	data: []u8,
	offset: u64,
	new_stage: mercury.Access_Stage,
	ren: ^Renderer,
	execute: bool = true,
) {
	// requires a transfer op
	if buffer.desc.location == .Device {
		eph := acquire_eph_buffer(ren, u64(len(data)))
		defer return_eph_buffer(ren, eph)

		buffer_len_before := eph.len
		ren_buffer_append(&eph, data, new_stage, ren)

		cmd, begin_ok := begin_transfer(ren)
		if !begin_ok do return
		defer {
			val := end_transfer(ren)
			if execute do wait_transfer(ren, val)
		}

		ren_buffer_barrier(buffer, mercury.ACCESS_STAGE_COPY_DESTINATION, ren)
		defer ren_buffer_barrier(buffer, new_stage, ren)

		ren.instance->cmd_copy_buffer(
			cmd,
			buffer.buffer,
			offset,
			eph.buffer,
			buffer_len_before,
			u64(len(data)),
		)
		return
	}
	assert(offset + u64(len(data)) <= buffer.desc.size, "Buffer overflow")
	mapped, error := ren.instance->map_buffer(buffer.buffer, offset, u64(len(data)))
	if error != nil {
		panic("Could not map buffer")
	}
	copy_slice(mapped, data)
	ren.instance->unmap_buffer(buffer.buffer)
}

ren_buffer_set_typed :: proc(
	buffer: ^Ren_Buffer,
	value: $T,
	offset: u64,
	new_stage: mercury.Access_Stage,
	ren: ^Renderer,
) {
	ren_buffer_set(
		buffer,
		slice.reinterpret([]u8, slice.bytes_from_ptr(&value, size_of(T))),
		offset,
		new_stage,
		ren,
	)
}

ren_buffer_get :: proc(
	buffer: ^Ren_Buffer,
	offset: u64,
	size: u64,
	ren: ^Renderer,
	allocator := context.temp_allocator,
) -> (
	data: []u8,
	error: mercury.Error,
) {
	// requires a transfer op
	if buffer.desc.location == .Device {
		eph := acquire_eph_buffer(ren, size)
		defer return_eph_buffer(ren, eph)

		cmd, begin_ok := begin_transfer(ren)
		if !begin_ok do return
		defer {
			val := end_transfer(ren)
			wait_transfer(ren, val)
		}

		ren_buffer_barrier(buffer, mercury.ACCESS_STAGE_COPY_SOURCE, ren)
		defer ren_buffer_barrier(buffer, buffer.state, ren)

		buffer_len_before := eph.len
		ren.instance->cmd_copy_buffer(
			cmd,
			eph.buffer,
			buffer_len_before,
			buffer.buffer,
			offset,
			size,
		)
		return ren_buffer_get(&eph, buffer_len_before, size, ren, allocator)
	}

	assert(offset + size <= buffer.desc.size, "Buffer overflow")
	mapped := ren.instance->map_buffer(buffer.buffer, offset, size) or_return
	defer ren.instance->unmap_buffer(buffer.buffer)
	if result, alloc_err := slice.clone(mapped, allocator); alloc_err != nil {
		error = .Out_Of_Memory
		return
	} else {
		data = result
		return
	}
}

ren_buffer_get_typed :: proc(
	buffer: ^Ren_Buffer,
	$T: typeid,
	#any_int offset: u64,
	ren: ^Renderer,
) -> (
	value: T,
	error: mercury.Error,
) {
	data := ren_buffer_get(buffer, offset, size_of(T), ren) or_return
	if v, ok := slice.to_type(data, T); !ok {
		error = .Invalid_Parameter
		return
	} else {
		value = v
	}
	return
}

ren_buffer_barrier :: proc(
	buffer: ^Ren_Buffer,
	new_stage: mercury.Access_Stage,
	ren: ^Renderer,
	execute := false,
) {
	cmd, begin_ok := begin_transfer(ren)
	if !begin_ok {
		return
	}
	if buffer.state.access == new_stage.access && buffer.state.stages == new_stage.stages {return}
	// log.warnf("barrier({}) {} -> {}", buffer.name, buffer.state, new_stage)
	ren.instance->cmd_barrier(
		cmd,
		{buffers = {{buffer = buffer.buffer, before = buffer.state, after = new_stage}}},
	)
	buffer.state = new_stage
}

ren_buffer_set_name :: proc(buffer: ^Ren_Buffer, name: string, ren: ^Renderer) {
	if buffer.buffer != nil {
		ren.instance->set_buffer_debug_name(buffer.buffer, name)
	}
	if buffer.srv != nil {
		ren.instance->set_descriptor_debug_name(buffer.srv, name)
	}
	if buffer.uav != nil {
		ren.instance->set_descriptor_debug_name(buffer.uav, name)
	}
	buffer.name = name
}

ren_buffer_set_vertex :: proc(
	buffer: ^Ren_Buffer,
	ren: ^Renderer,
	cmd: ^mercury.Command_Buffer,
	slot: u32,
	offset: u64,
) {
	ren.instance->cmd_set_vertex_buffers(cmd, slot, {buffer.buffer}, {offset})
}

ren_buffer_set_index :: proc(
	buffer: ^Ren_Buffer,
	ren: ^Renderer,
	cmd: ^mercury.Command_Buffer,
	offset: u64,
	index_type: mercury.Index_Type,
) {
	ren.instance->cmd_set_index_buffer(cmd, buffer.buffer, offset, index_type)
}

ren_set_constants :: proc(ren: ^Renderer, cmd: ^mercury.Command_Buffer, slot: u32, data: $T) {
	data := data
	ren.instance->cmd_set_constants(
		cmd,
		slot,
		slice.reinterpret([]u32, slice.bytes_from_ptr(&data, size_of(T))),
	)
}

Texture :: struct {
	texture: ^mercury.Texture,
	srv:     ^mercury.Descriptor,
	uav:     ^mercury.Descriptor,
	dsv:     ^mercury.Descriptor,
	rtv:     ^mercury.Descriptor,
	desc:    mercury.Texture_Desc,
	state:   mercury.Access_Layout_Stage,
	name:    string,
}

init_ren_texture :: proc(texture: ^Texture, ren: ^Renderer) -> (error: mercury.Error) {
	texture.texture = ren.instance->create_texture(ren.device, texture.desc) or_return

	if .Shader_Resource in texture.desc.usage {
		switch texture.desc.type {
		case ._1D:
			texture.srv = ren.instance->create_1d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		case ._2D:
			texture.srv = ren.instance->create_2d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
					layer_num = texture.desc.layer_num,
				},
			) or_return
		case ._3D:
			texture.srv = ren.instance->create_3d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		}
	}
	if .Shader_Resource_Storage in texture.desc.usage {
		switch texture.desc.type {
		case ._1D:
			texture.uav = ren.instance->create_1d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource_Storage,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		case ._2D:
			texture.uav = ren.instance->create_2d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource_Storage,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
					layer_num = texture.desc.layer_num,
				},
			) or_return
		case ._3D:
			texture.uav = ren.instance->create_3d_texture_view(
				ren.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource_Storage,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		}
	}
	if .Depth_Stencil_Attachment in texture.desc.usage {
		assert(texture.desc.type == ._2D, "Depth stencil attachment only supports 2D textures")
		texture.dsv = ren.instance->create_2d_texture_view(
			ren.device,
			{
				texture = texture.texture,
				view_type = .Depth_Stencil_Attachment,
				format = texture.desc.format,
				mip_num = texture.desc.mip_num,
			},
		) or_return
	}
	if .Color_Attachment in texture.desc.usage {
		assert(texture.desc.type == ._2D, "Render target only supports 2D textures")
		texture.rtv = ren.instance->create_2d_texture_view(
			ren.device,
			{
				texture = texture.texture,
				view_type = .Color_Attachment,
				format = texture.desc.format,
				mip_num = texture.desc.mip_num,
			},
		) or_return
	}

	ren_texture_set_name(texture, texture.name, ren)

	return
}

deinit_ren_texture :: proc(texture: ^Texture, ren: ^Renderer) {
	if texture.srv != nil {
		ren.instance->destroy_descriptor(ren.device, texture.srv)
	}
	if texture.uav != nil {
		ren.instance->destroy_descriptor(ren.device, texture.uav)
	}
	if texture.dsv != nil {
		ren.instance->destroy_descriptor(ren.device, texture.dsv)
	}
	if texture.rtv != nil {
		ren.instance->destroy_descriptor(ren.device, texture.rtv)
	}
	if texture.texture != nil {
		ren.instance->deinit_ren_texture(texture.texture)
	}
	texture^ = {}
}

ren_texture_barrier :: proc(
	texture: ^Texture,
	new_stage: mercury.Access_Layout_Stage,
	ren: ^Renderer,
	execute: bool = false,
) {
	cmd, begin_ok := begin_transfer(ren)
	if !begin_ok {
		return
	}
	if texture.state.access == new_stage.access &&
	   texture.state.layout == new_stage.layout &&
	   texture.state.stages == new_stage.stages {return}
	// log.warnf("barrier({}) {} -> {}", texture.name, texture.state, new_stage)
	ren.instance->cmd_barrier(
		cmd,
		{textures = {{texture = texture.texture, before = texture.state, after = new_stage}}},
	)
	texture.state = new_stage
}

ren_texture_set_name :: proc(texture: ^Texture, name: string, ren: ^Renderer) {
	if texture.texture != nil {
		ren.instance->set_texture_debug_name(texture.texture, name)
	}
	if texture.srv != nil {
		ren.instance->set_descriptor_debug_name(texture.srv, name)
	}
	if texture.uav != nil {
		ren.instance->set_descriptor_debug_name(texture.uav, name)
	}
	if texture.dsv != nil {
		ren.instance->set_descriptor_debug_name(texture.dsv, name)
	}
	if texture.rtv != nil {
		ren.instance->set_descriptor_debug_name(texture.rtv, name)
	}
	texture.name = name
}

Texture_Subresource_Upload_Desc :: struct {
	slices:      [^]u8,
	slice_num:   u32,
	row_pitch:   u32,
	slice_pitch: u32,
}

ren_texture_upload :: proc(
	texture: ^Texture,
	ren: ^Renderer,
	subresources: []Texture_Subresource_Upload_Desc = {},
	after: mercury.Access_Layout_Stage = {},
	layer_offset: u32 = 0,
	mip_offset: u32 = 0,
	execute: bool = true,
) -> (
	error: mercury.Error,
) {
	desc := ren.instance->get_texture_desc(texture.texture)
	device_desc := ren.instance->get_device_desc(ren.device)
	upload_buffer_texture_row_alignment := device_desc.upload_buffer_texture_row_alignment
	upload_buffer_texture_slice_alignment := device_desc.upload_buffer_texture_slice_alignment

	for layer in layer_offset ..< u32(desc.layer_num) {
		for mip in mip_offset ..< u32(desc.mip_num) {
			subresource := &subresources[layer * u32(desc.mip_num) + mip]
			slice_row_num := subresource.slice_pitch / subresource.row_pitch
			aligned_row_pitch := mem.align_forward_uint(
				uint(subresource.row_pitch),
				uint(upload_buffer_texture_row_alignment),
			)
			aligned_slice_pitch := mem.align_forward_uint(
				uint(subresource.slice_pitch),
				uint(upload_buffer_texture_slice_alignment),
			)
			content_size := u64(u64(aligned_slice_pitch) * u64(subresource.slice_num))

			eph := acquire_eph_buffer(ren, content_size)
			defer return_eph_buffer(ren, eph)

			buffer_len_before := eph.len
			for slice in 0 ..< subresource.slice_num {
				for row in 0 ..< slice_row_num {
					// offset := uint(slice) * aligned_slice_pitch + uint(row) * aligned_row_pitch
					data := subresource.slices[slice * subresource.slice_pitch +
					row * subresource.row_pitch:][:subresource.row_pitch]
					ren_buffer_append(
						&eph,
						data,
						mercury.ACCESS_STAGE_COPY_DESTINATION,
						ren,
						false,
					) or_return
				}
			}

			data_layout: mercury.Texture_Data_Layout_Desc
			data_layout.offset = buffer_len_before
			data_layout.row_pitch = u32(aligned_row_pitch)
			data_layout.slice_pitch = u32(aligned_slice_pitch)

			dst_region: mercury.Texture_Region_Desc
			dst_region.layer_offset = mercury.dim(layer)
			dst_region.mip_offset = mercury.mip(mip)

			cmd, begin_ok := begin_transfer(ren)
			if !begin_ok do return .Unknown
			defer {
				val := end_transfer(ren)
				if execute do wait_transfer(ren, val)
			}

			ren_texture_barrier(
				texture,
				{access = {.Copy_Destination}, layout = .Copy_Destination, stages = {.Copy}},
				ren,
			)
			defer ren_texture_barrier(texture, after, ren)

			ren.instance->cmd_upload_buffer_to_texture(
				cmd,
				texture.texture,
				dst_region,
				eph.buffer,
				data_layout,
			)
		}
	}

	return
}

compute_pitch :: proc(
	format: mercury.Format,
	width, height: u32,
) -> (
	row_pitch, slice_pitch: u32,
) {
	#partial switch format {
	case .BC1_RGBA_UNORM, .BC4_R_UNORM, .BC4_R_SNORM:
		width_in_blocks := max(1, (width + 3) / 4)
		height_in_blocks := max(1, (height + 3) / 4)
		return width_in_blocks * 8, width_in_blocks * 8 * height_in_blocks
	case .BC2_RGBA_UNORM,
	     .BC3_RGBA_UNORM,
	     .BC5_RG_UNORM,
	     .BC5_RG_SNORM,
	     .BC6H_RGB_UFLOAT,
	     .BC6H_RGB_SFLOAT,
	     .BC7_RGBA_UNORM:
		width_in_blocks := max(1, (width + 3) / 4)
		height_in_blocks := max(1, (height + 3) / 4)
		return width_in_blocks * 16, width_in_blocks * 16 * height_in_blocks
	}
	bpp := int(mercury.FORMAT_PROPS[format].stride * 8)
	row_pitch = u32((int(width) * bpp + 7) / 8)
	slice_pitch = row_pitch * height
	return
}
