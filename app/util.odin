package app

import "en:gpu"

Resizable_Buffer :: struct {
	buffer: ^gpu.Buffer,
	srv:    ^gpu.Descriptor,
	uav:    ^gpu.Descriptor,
	desc:   gpu.Buffer_Desc,
	len:    u64,
	name:   string,
}

init_resizable_buffer :: proc(buffer: ^Resizable_Buffer, renderer: ^Renderer) {
	buffer.desc.size = 0
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
	transfer: ^Transfer = nil,
) -> (
	error: gpu.Error,
) {
	if u64(buffer.desc.size) >= new_size && buffer.desc.size != 0 do return

	old_size := buffer.desc.size
	buffer.desc.size = u64(new_size)
	new_buffer := renderer.instance->create_buffer(renderer.device, buffer.desc) or_return

	// if had one then copy over
	if buffer.buffer != nil && transfer != nil {
		// cmd := begin_transfer()
		// renderer.instance->copy_buffer(renderer.device, cmd, new_buffer, 0, buffer.buffer, 0, old_size)
		// transfer_wait(transfer_end())
	}
	renderer.instance->destroy_buffer(buffer.buffer)
	buffer.buffer = new_buffer

	format: gpu.Format = .UNKNOWN
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
	new_stage: gpu.Access_Stage,
	renderer: ^Renderer,
	transfer: ^Transfer = nil,
	execute: bool = true,
) -> (
	error: gpu.Error,
) {
	if buffer.buffer == nil {
		return .Invalid_Parameter
	}
	new_size := buffer.desc.size + u64(len(data))
	if buffer.desc.size < new_size {
		resize_buffer(buffer, u64(new_size), renderer, transfer) or_return
	}

	append_assume_buffer(buffer, data, new_stage, renderer, transfer, execute)
	return
}

append_assume_buffer :: proc(
	buffer: ^Resizable_Buffer,
	data: []u8,
	new_stage: gpu.Access_Stage,
	renderer: ^Renderer,
	transfer: ^Transfer = nil,
	execute: bool = true,
) {
	old_len := buffer.desc.size
	buffer_set(buffer, data, old_len, new_stage, renderer, transfer, execute)
	buffer.desc.size += u64(len(data))
}

buffer_set :: proc(
	buffer: ^Resizable_Buffer,
	data: []u8,
	offset: u64,
	new_stage: gpu.Access_Stage,
	renderer: ^Renderer,
	transfer: ^Transfer = nil,
	execute: bool = true,
) {
	// requires a transfer op
	if buffer.desc.location == .Device {
		// TODO
		panic("Not implemented")
	}
	assert(offset + u64(len(data)) <= buffer.len, "Buffer overflow")
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

Transfer :: struct {}
