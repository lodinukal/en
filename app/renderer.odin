package app

import "core:c"
import "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:mem"

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
	main_fence_value: u64,
	graphics_queue:   ^mercury.Command_Queue,
	swapchain:        ^mercury.Swapchain,
	// frame
	frame_index:      u64,
	frames:           small_array.Small_Array(FRAME_BUF_NUM, Frame),
	backbuffer_index: int,
	// transfer
	transfer:         struct {
		in_progress:  bool,
		queue:        ^mercury.Command_Queue,
		allocator:    ^mercury.Command_Allocator,
		buffer:       ^mercury.Command_Buffer,
		fence:        ^mercury.Fence,
		fence_value:  u64,
		free_buffers: [dynamic]Resizable_Buffer,
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

	ren.main_fence, gpu_err = ren.instance->create_fence(ren.device, ren.main_fence_value)
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
			immediate = true,
		},
	)
	check_gpu(gpu_err, "Could not create swapchain") or_return

	small_array.resize(&ren.frames, FRAME_BUF_NUM)
	renderer_acquire_swapchain_resources(ren)
	for &frame, index in small_array.slice(&ren.frames) {
		frame.allocator, gpu_err = ren.instance->create_command_allocator(ren.graphics_queue)
		check_gpu(gpu_err, "Could not create frame command allocator {}", index) or_return
		ren.instance->set_command_allocator_debug_name(frame.allocator, "Frame allocator")

		frame.cmd, gpu_err = ren.instance->create_command_buffer(frame.allocator)
		check_gpu(gpu_err, "Could not create frame command buffer {}", index) or_return
		ren.instance->set_command_buffer_debug_name(frame.cmd, "Frame buffer")
	}

	// inits the transfer
	ren.transfer.queue, gpu_err = ren.instance->create_command_queue(ren.device, .Graphics)
	check_gpu(gpu_err, "Could not create transfer queue") or_return
	ren.transfer.allocator, gpu_err = ren.instance->create_command_allocator(ren.transfer.queue)
	check_gpu(gpu_err, "Could not create transfer allocator") or_return
	ren.transfer.buffer, gpu_err = ren.instance->create_command_buffer(ren.transfer.allocator)
	check_gpu(gpu_err, "Could not create transfer buffer") or_return
	ren.transfer.fence, gpu_err = ren.instance->create_fence(ren.device, ren.transfer.fence_value)
	check_gpu(gpu_err, "Could not create transfer fence") or_return

	// descriptor pool
	ren.descriptor_pool, gpu_err =
	ren.instance->create_descriptor_pool(ren.device, render_components_descriptor_requirements)
	check_gpu(gpu_err, "Could not create descriptor pool") or_return

	// image pool
	if ok := init_resource_pool(&ren.resource_pool, ren); ok == false {
		return false
	}

	return true
}

renderer_wait_idle :: proc(ren: ^Renderer) {
	// wait for the current frame to finish rendering
	ren.instance->wait_fence_now(ren.main_fence, ren.main_fence_value)
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
	for &frame, index in small_array.slice(&ren.frames) {
		if frame.srv != nil {
			ren.instance->destroy_descriptor(ren.device, frame.srv)
			frame.srv = nil
			frame.texture = nil
		}
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
}

destroy_renderer :: proc(ren: ^Renderer) {
	renderer_wait_idle(ren)

	// destroy components
	destroy_resource_pool(&ren.resource_pool, ren)

	// destroy descriptor pool
	ren.instance->destroy_descriptor_pool(ren.descriptor_pool)

	// destroy transfer resources
	wait_transfer(ren, ren.transfer.fence_value)
	ren.instance->destroy_fence(ren.transfer.fence)
	ren.instance->destroy_command_buffer(ren.transfer.buffer)
	ren.instance->destroy_command_allocator(ren.transfer.allocator)
	ren.instance->destroy_command_queue(ren.transfer.queue)
	for &buffer in ren.transfer.free_buffers {
		destroy_resizable_buffer(&buffer, ren)
	}
	delete(ren.transfer.free_buffers)

	renderer_cleanup_swapchain_resources(ren)
	for &frame, index in small_array.slice(&ren.frames) {
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
begin_transfer :: proc(ren: ^Renderer) -> (buf: ^mercury.Command_Buffer) {
	if ren.transfer.in_progress {
		buf = ren.transfer.buffer
		return
	}
	ren.transfer.in_progress = true
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

tex_barrier :: proc(ren: ^Renderer, barrier: mercury.Texture_Barrier_Desc) {
	ren.instance->cmd_barrier(get_frame(ren).cmd, {textures = {barrier}})
}

buf_barrier :: proc(ren: ^Renderer, barrier: mercury.Buffer_Barrier_Desc) {
	ren.instance->cmd_barrier(get_frame(ren).cmd, {buffers = {barrier}})
}

acquire_eph_buffer :: proc(ren: ^Renderer, size: u64) -> (buf: Resizable_Buffer) {
	if (size >= UPLOAD_PAGE_SIZE) {
		#reverse for buffer, index in ren.transfer.free_buffers {
			if buffer.desc.size >= size {
				unordered_remove(&ren.transfer.free_buffers, index)
				return buffer
			}
		}
	}

	if len(ren.transfer.free_buffers) == 0 || size >= UPLOAD_PAGE_SIZE {
		new_buffer := Resizable_Buffer{}
		new_buffer.desc.size = max(size, UPLOAD_PAGE_SIZE)
		new_buffer.desc.location = .Device_Upload
		if check_gpu(init_resizable_buffer(&new_buffer, ren), "Could not init resizable buffer") ==
		   false {
			return
		}
		buffer_set_name(&new_buffer, "ephemeral buffer", ren)
		append(&ren.transfer.free_buffers, new_buffer)
	}

	buf = pop(&ren.transfer.free_buffers)
	return
}

KEEP_BUFFER_COUNT :: 3
return_eph_buffer :: proc(ren: ^Renderer, buf: Resizable_Buffer) {
	buf := buf
	buf.len = 0
	if len(ren.transfer.free_buffers) >= KEEP_BUFFER_COUNT {
		destroy_resizable_buffer(&buf, ren)
		return
	}
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

Resizable_Buffer :: struct {
	buffer: ^mercury.Buffer,
	srv:    ^mercury.Descriptor,
	uav:    ^mercury.Descriptor,
	desc:   mercury.Buffer_Desc,
	len:    u64,
	name:   string,
}

init_resizable_buffer :: proc(
	buffer: ^Resizable_Buffer,
	renderer: ^Renderer,
) -> (
	error: mercury.Error,
) {
	old_size := buffer.desc.size
	buffer.desc.size = 0
	resize_buffer(buffer, old_size, renderer) or_return
	return
}

destroy_resizable_buffer :: proc(buffer: ^Resizable_Buffer, renderer: ^Renderer) {
	if buffer.buffer != nil {
		renderer.instance->destroy_buffer(buffer.buffer)
	}
	if buffer.srv != nil {
		renderer.instance->destroy_descriptor(renderer.device, buffer.srv)
	}
	if buffer.uav != nil {
		renderer.instance->destroy_descriptor(renderer.device, buffer.uav)
	}
	buffer^ = {}
}

resize_buffer :: proc(
	buffer: ^Resizable_Buffer,
	new_size: u64,
	renderer: ^Renderer,
) -> (
	error: mercury.Error,
) {
	if u64(buffer.desc.size) >= new_size || buffer.desc.size != 0 do return

	old_size := buffer.desc.size
	buffer.desc.size = u64(new_size)
	new_buffer := renderer.instance->create_buffer(renderer.device, buffer.desc) or_return

	// if had one then copy over
	if buffer.buffer != nil {
		{
			cmd := begin_transfer(renderer)
			defer {
				val := end_transfer(renderer)
				wait_transfer(renderer, val)
			}
			renderer.instance->cmd_copy_buffer(cmd, new_buffer, 0, buffer.buffer, 0, old_size)
		}
		renderer.instance->destroy_buffer(buffer.buffer)
	}
	buffer.buffer = new_buffer

	format: mercury.Format = .UNKNOWN
	if buffer.desc.structure_stride > 0 && renderer.instance.api == .D3D12 {
		format = .R32_UINT
	}

	if .Shader_Resource in buffer.desc.usage {
		buffer.srv = renderer.instance->create_buffer_view(
			renderer.device,
			{
				buffer = buffer.buffer,
				view_type = .Shader_Resource,
				size = buffer.desc.size,
				format = format,
			},
		) or_return
		renderer.instance->set_descriptor_debug_name(buffer.srv, buffer.name)
	}
	if .Shader_Resource_Storage in buffer.desc.usage {
		buffer.uav = renderer.instance->create_buffer_view(
			renderer.device,
			{
				buffer = buffer.buffer,
				view_type = .Shader_Resource_Storage,
				size = buffer.desc.size,
				format = format,
			},
		) or_return
		renderer.instance->set_descriptor_debug_name(buffer.uav, buffer.name)
	}
	renderer.instance->set_buffer_debug_name(buffer.buffer, buffer.name)
	return
}

append_buffer :: proc(
	buffer: ^Resizable_Buffer,
	data: []u8,
	new_stage: mercury.Access_Stage,
	renderer: ^Renderer,
	execute: bool = true,
) -> (
	error: mercury.Error,
) {
	if buffer.buffer == nil {
		return .Invalid_Parameter
	}
	new_size := buffer.len + u64(len(data))
	if buffer.desc.size < new_size {
		resize_buffer(buffer, u64(new_size), renderer) or_return
	}

	append_assume_buffer(buffer, data, new_stage, renderer, execute)
	return
}

append_assume_buffer :: proc(
	buffer: ^Resizable_Buffer,
	data: []u8,
	new_stage: mercury.Access_Stage,
	renderer: ^Renderer,
	execute: bool = true,
) {
	old_len := buffer.len
	buffer_set(buffer, data, old_len, new_stage, renderer, execute)
	buffer.len += u64(len(data))
}

buffer_set :: proc(
	buffer: ^Resizable_Buffer,
	data: []u8,
	offset: u64,
	new_stage: mercury.Access_Stage,
	renderer: ^Renderer,
	execute: bool = true,
) {
	// requires a transfer op
	if buffer.desc.location == .Device {
		eph := acquire_eph_buffer(renderer, u64(len(data)))
		defer return_eph_buffer(renderer, eph)

		buffer_len_before := buffer.len
		append_assume_buffer(&eph, data, new_stage, renderer)

		cmd := begin_transfer(renderer)
		defer {
			val := end_transfer(renderer)
			if execute do wait_transfer(renderer, val)
		}

		renderer.instance->cmd_barrier(
			cmd,
			{buffers = {{buffer = buffer.buffer, after = mercury.ACCESS_STAGE_COPY_DESTINATION}}},
		)

		renderer.instance->cmd_copy_buffer(
			cmd,
			buffer.buffer,
			offset,
			eph.buffer,
			buffer_len_before,
			u64(len(data)),
		)

		renderer.instance->cmd_barrier(
			cmd,
			{
				buffers = {
					{
						buffer = buffer.buffer,
						before = mercury.ACCESS_STAGE_COPY_DESTINATION,
						after = new_stage,
					},
				},
			},
		)
	}
	assert(offset + u64(len(data)) <= buffer.desc.size, "Buffer overflow")
	mapped, error := renderer.instance->map_buffer(buffer.buffer, offset, u64(len(data)))
	if error != nil {
		panic("Could not map buffer")
	}
	copy_slice(mapped, data)
	renderer.instance->unmap_buffer(buffer.buffer)
}

buffer_set_name :: proc(buffer: ^Resizable_Buffer, name: string, renderer: ^Renderer) {
	if buffer.buffer != nil {
		renderer.instance->set_buffer_debug_name(buffer.buffer, name)
	}
	if buffer.srv != nil {
		renderer.instance->set_descriptor_debug_name(buffer.srv, name)
	}
	if buffer.uav != nil {
		renderer.instance->set_descriptor_debug_name(buffer.uav, name)
	}
	buffer.name = name
}

Texture :: struct {
	texture: ^mercury.Texture,
	srv:     ^mercury.Descriptor,
	uav:     ^mercury.Descriptor,
	dsv:     ^mercury.Descriptor,
	rtv:     ^mercury.Descriptor,
	desc:    mercury.Texture_Desc,
	name:    string,
}

init_texture :: proc(texture: ^Texture, renderer: ^Renderer) -> (error: mercury.Error) {
	texture.texture = renderer.instance->create_texture(renderer.device, texture.desc) or_return

	if .Shader_Resource in texture.desc.usage {
		switch texture.desc.type {
		case ._1D:
			texture.srv = renderer.instance->create_1d_texture_view(
				renderer.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		case ._2D:
			texture.srv = renderer.instance->create_2d_texture_view(
				renderer.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
					layer_num = texture.desc.layer_num,
				},
			) or_return
		case ._3D:
			texture.srv = renderer.instance->create_3d_texture_view(
				renderer.device,
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
			texture.uav = renderer.instance->create_1d_texture_view(
				renderer.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource_Storage,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
				},
			) or_return
		case ._2D:
			texture.uav = renderer.instance->create_2d_texture_view(
				renderer.device,
				{
					texture = texture.texture,
					view_type = .Shader_Resource_Storage,
					format = texture.desc.format,
					mip_num = texture.desc.mip_num,
					layer_num = texture.desc.layer_num,
				},
			) or_return
		case ._3D:
			texture.uav = renderer.instance->create_3d_texture_view(
				renderer.device,
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
		texture.dsv = renderer.instance->create_2d_texture_view(
			renderer.device,
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
		texture.rtv = renderer.instance->create_2d_texture_view(
			renderer.device,
			{
				texture = texture.texture,
				view_type = .Color_Attachment,
				format = texture.desc.format,
				mip_num = texture.desc.mip_num,
			},
		) or_return
	}

	texture_set_name(texture, texture.name, renderer)

	return
}

destroy_texture :: proc(texture: ^Texture, renderer: ^Renderer) {
	if texture.srv != nil {
		renderer.instance->destroy_descriptor(renderer.device, texture.srv)
	}
	if texture.uav != nil {
		renderer.instance->destroy_descriptor(renderer.device, texture.uav)
	}
	if texture.dsv != nil {
		renderer.instance->destroy_descriptor(renderer.device, texture.dsv)
	}
	if texture.rtv != nil {
		renderer.instance->destroy_descriptor(renderer.device, texture.rtv)
	}
	if texture.texture != nil {
		renderer.instance->destroy_texture(texture.texture)
	}
	texture^ = {}
}

texture_set_name :: proc(texture: ^Texture, name: string, renderer: ^Renderer) {
	if texture.texture != nil {
		renderer.instance->set_texture_debug_name(texture.texture, name)
	}
	if texture.srv != nil {
		renderer.instance->set_descriptor_debug_name(texture.srv, name)
	}
	if texture.uav != nil {
		renderer.instance->set_descriptor_debug_name(texture.uav, name)
	}
	if texture.dsv != nil {
		renderer.instance->set_descriptor_debug_name(texture.dsv, name)
	}
	if texture.rtv != nil {
		renderer.instance->set_descriptor_debug_name(texture.rtv, name)
	}
	texture.name = name
}

Texture_Subresource_Upload_Desc :: struct {
	slices:      [^]u8,
	slice_num:   u32,
	row_pitch:   u32,
	slice_pitch: u32,
}

texture_upload :: proc(
	texture: ^Texture,
	renderer: ^Renderer,
	subresources: []Texture_Subresource_Upload_Desc = {},
	after: mercury.Access_Layout_Stage = {},
	layer_offset: u32 = 0,
	mip_offset: u32 = 0,
	execute: bool = true,
) -> (
	error: mercury.Error,
) {
	desc := renderer.instance->get_texture_desc(texture.texture)
	device_desc := renderer.instance->get_device_desc(renderer.device)
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

			eph := acquire_eph_buffer(renderer, content_size)
			defer return_eph_buffer(renderer, eph)

			buffer_len_before := eph.len
			for slice in 0 ..< subresource.slice_num {
				for row in 0 ..< slice_row_num {
					offset := uint(slice) * aligned_slice_pitch + uint(row) * aligned_row_pitch
					data := subresource.slices[slice * subresource.slice_pitch +
					row * subresource.row_pitch:][:subresource.row_pitch]
					append_buffer(
						&eph,
						data,
						mercury.ACCESS_STAGE_COPY_DESTINATION,
						renderer,
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

			cmd := begin_transfer(renderer)
			defer {
				val := end_transfer(renderer)
				if execute do wait_transfer(renderer, val)
			}

			renderer.instance->cmd_barrier(
				cmd,
				{
					textures = {
						{
							texture = texture.texture,
							after = {
								access = {.Copy_Destination},
								layout = .Copy_Destination,
								stages = {.Copy},
							},
						},
					},
				},
			)

			renderer.instance->cmd_upload_buffer_to_texture(
				cmd,
				texture.texture,
				dst_region,
				eph.buffer,
				data_layout,
			)

			renderer.instance->cmd_barrier(
				cmd,
				{
					textures = {
						{
							texture = texture.texture,
							before = {
								access = {.Copy_Destination},
								layout = .Copy_Destination,
								stages = {.Copy},
							},
							after = after,
						},
					},
				},
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
