#+build windows
#+private file
package mercury

import "base:runtime"
import "core:container/small_array"
import "core:log"
import "core:mem"
import "core:strings"

import win32 "core:sys/windows"
import "vendor:directx/d3d12"
import "vendor:directx/dxgi"

import d3d12ma "external:d3d12ma"

set_debug_name :: proc(obj: ^d3d12.IObject, name: string) -> (error: mem.Allocator_Error) {
	name_wide := win32.MultiByteToWideChar(win32.CP_UTF8, 0, raw_data(name), -1, nil, 0)
	name_buffer := make([]u16, name_wide, context.temp_allocator) or_return

	win32.MultiByteToWideChar(
		win32.CP_UTF8,
		0,
		raw_data(name),
		-1,
		raw_data(name_buffer),
		name_wide,
	)
	obj->SetPrivateData(
		d3d12.WKPDID_D3DDebugObjectNameW_UUID,
		u32(name_wide * 2),
		raw_data(name_buffer),
	)
	return
}

D3D12_Instance :: struct {
	using _: Instance,
	factory: ^dxgi.IFactory5,
}

@(private = "package")
create_d3d12_instance :: proc(
	enable_graphics_api_validation: bool,
) -> (
	out_instance: ^Instance,
	error: Error,
) {
	instance, error_alloc := new(D3D12_Instance)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	instance.api = .D3D12

	// fill functions
	instance.destroy = destroy_instance

	instance.create_device = create_device
	instance.destroy_device = destroy_device
	instance.get_device_desc = get_device_desc
	instance.set_device_debug_name = set_device_debug_name
	instance.get_command_queue = get_command_queue

	instance.create_buffer = create_buffer
	instance.destroy_buffer = destroy_buffer
	instance.set_buffer_debug_name = set_buffer_debug_name
	instance.map_buffer = map_buffer
	instance.unmap_buffer = unmap_buffer

	instance.create_1d_texture_view = create_1d_texture_view
	instance.create_2d_texture_view = create_2d_texture_view
	instance.create_3d_texture_view = create_3d_texture_view
	instance.create_buffer_view = create_buffer_view
	instance.create_sampler = create_sampler
	instance.destroy_descriptor = destroy_descriptor
	instance.set_descriptor_debug_name = set_descriptor_debug_name

	instance.create_command_allocator = create_command_allocator
	instance.destroy_command_allocator = destroy_command_allocator
	instance.set_command_allocator_debug_name = set_command_allocator_debug_name
	instance.reset_command_allocator = reset_command_allocator

	instance.create_command_buffer = create_command_buffer
	instance.destroy_command_buffer = destroy_command_buffer
	instance.set_command_buffer_debug_name = set_command_buffer_debug_name
	instance.begin_command_buffer = begin_command_buffer
	instance.end_command_buffer = end_command_buffer
	instance.cmd_set_viewports = cmd_set_viewports
	instance.cmd_set_scissors = cmd_set_scissors
	instance.cmd_set_depth_bounds = cmd_set_depth_bounds
	instance.cmd_set_stencil_reference = cmd_set_stencil_reference
	instance.cmd_set_sample_locations = cmd_set_sample_locations
	instance.cmd_set_blend_constants = cmd_set_blend_constants
	instance.cmd_clear_attachments = cmd_clear_attachments
	instance.cmd_clear_storage_buffer = cmd_clear_storage_buffer
	instance.cmd_clear_storage_texture = cmd_clear_storage_texture
	instance.cmd_begin_rendering = cmd_begin_rendering
	instance.cmd_end_rendering = cmd_end_rendering
	instance.cmd_set_vertex_buffers = cmd_set_vertex_buffers
	instance.cmd_set_index_buffer = cmd_set_index_buffer
	instance.cmd_set_pipeline_layout = cmd_set_pipeline_layout
	instance.cmd_set_pipeline = cmd_set_pipeline
	instance.cmd_set_descriptor_pool = cmd_set_descriptor_pool
	instance.cmd_set_descriptor_set = cmd_set_descriptor_set
	instance.cmd_set_constants = cmd_set_constants
	instance.cmd_draw = cmd_draw
	instance.cmd_draw_indexed = cmd_draw_indexed
	instance.cmd_draw_indirect = cmd_draw_indirect
	instance.cmd_draw_indexed_indirect = cmd_draw_indexed_indirect
	instance.cmd_copy_buffer = cmd_copy_buffer
	instance.cmd_copy_texture = cmd_copy_texture
	instance.cmd_resolve_texture = cmd_resolve_texture
	instance.cmd_upload_buffer_to_texture = cmd_upload_buffer_to_texture
	instance.cmd_readback_texture_to_buffer = cmd_readback_texture_to_buffer
	instance.cmd_dispatch = cmd_dispatch
	instance.cmd_dispatch_indirect = cmd_dispatch_indirect
	instance.cmd_barrier = cmd_barrier

	instance.create_command_queue = create_command_queue
	instance.destroy_command_queue = destroy_command_queue
	instance.set_command_queue_debug_name = set_command_queue_debug_name
	instance.submit = submit

	instance.create_descriptor_pool = create_descriptor_pool
	instance.destroy_descriptor_pool = destroy_descriptor_pool
	instance.set_descriptor_pool_debug_name = set_descriptor_pool_debug_name
	instance.allocate_descriptor_set = allocate_descriptor_set
	instance.reset_descriptor_pool = reset_descriptor_pool

	instance.update_descriptor_ranges = update_descriptor_ranges

	instance.create_fence = create_fence
	instance.destroy_fence = destroy_fence
	instance.set_fence_debug_name = set_fence_debug_name
	instance.get_fence_value = get_fence_value
	instance.signal_fence = signal_fence
	instance.wait_fence = wait_fence
	instance.wait_fence_now = wait_fence_now

	instance.create_graphics_pipeline = create_graphics_pipeline
	instance.destroy_pipeline = destroy_pipeline
	instance.set_pipeline_debug_name = set_pipeline_debug_name

	instance.create_pipeline_layout = create_pipeline_layout
	instance.destroy_pipeline_layout = destroy_pipeline_layout
	instance.set_pipeline_layout_debug_name = set_pipeline_layout_debug_name

	instance.create_swapchain = create_swapchain
	instance.destroy_swapchain = destroy_swapchain
	instance.set_swapchain_debug_name = set_swapchain_debug_name
	instance.get_swapchain_textures = get_swapchain_textures
	instance.acquire_next_texture = acquire_next_texture
	instance.present = present
	instance.resize_swapchain = resize_swapchain

	instance.create_texture = create_texture
	instance.destroy_texture = destroy_texture
	instance.set_texture_debug_name = set_texture_debug_name
	instance.get_texture_desc = get_texture_desc

	if enable_graphics_api_validation {
		debug_controller: ^d3d12.IDebug = nil
		if win32.SUCCEEDED(
			d3d12.GetDebugInterface(d3d12.IDebug_UUID, (^rawptr)(&debug_controller)),
		) {
			debug_controller->EnableDebugLayer()
			defer debug_controller->Release()
		} else {
			log.errorf("Could not enable debug layer")
		}
	}

	hr := dxgi.CreateDXGIFactory2(
		{.DEBUG} if enable_graphics_api_validation else {},
		dxgi.IFactory5_UUID,
		(^rawptr)(&instance.factory),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_instance = (^Instance)(instance)
	return
}

destroy_instance :: proc(instance: ^Instance) {
	instance := (^D3D12_Instance)(instance)
	instance.factory->Release()
	free(instance)
}

D3D12_Buffer :: struct {
	using _:    Buffer,
	desc:       Buffer_Desc,
	resource:   ^d3d12.IResource,
	allocation: ^d3d12ma.Allocation,
}

create_buffer :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Buffer_Desc,
) -> (
	out_buffer: ^Buffer,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	buffer, error_alloc := new(D3D12_Buffer)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	buffer.desc = desc
	resource_desc: d3d12.RESOURCE_DESC
	resource_desc.Dimension = .BUFFER
	resource_desc.Width = desc.size
	resource_desc.Height = 1
	resource_desc.DepthOrArraySize = 1
	resource_desc.MipLevels = 1
	resource_desc.SampleDesc.Count = 1
	resource_desc.Layout = .ROW_MAJOR
	if card(
		   desc.usage &
		   {.Shader_Resource_Storage, .Acceleration_Structure_Storage, .Scratch_Buffer},
	   ) >
	   0 {
		resource_desc.Flags = {.ALLOW_UNORDERED_ACCESS}
	}

	initial_state: d3d12.RESOURCE_STATES
	if desc.location == .Host_Upload {
		initial_state += d3d12.RESOURCE_STATE_GENERIC_READ
	} else if desc.location == .Host_Readback {
		initial_state += {.COPY_DEST}
	}
	if .Acceleration_Structure_Storage in desc.usage {
		initial_state += {.RAYTRACING_ACCELERATION_STRUCTURE}
	}

	alloc_info: d3d12ma.ALLOCATION_DESC
	alloc_info.HeapType = MEMORY_LOCATION_TO_HEAP_TYPE[desc.location]
	alloc_info.Flags = {.STRATEGY_MIN_MEMORY}
	alloc_info.ExtraHeapFlags = {.CREATE_NOT_ZEROED}

	hr := d3d12ma.Allocator_CreateResource(
		d.allocator,
		alloc_info,
		resource_desc,
		{},
		nil,
		&buffer.allocation,
		d3d12.IResource_UUID,
		(^rawptr)(&buffer.resource),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_buffer = (^Buffer)(buffer)
	return
}

destroy_buffer :: proc(instance: ^Instance, buffer: ^Buffer) {
	b: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
	b.resource->Release()
	d3d12ma.Allocation_Release(b.allocation)
	free(b)
}

set_buffer_debug_name :: proc(
	instance: ^Instance,
	buffer: ^Buffer,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	b: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
	return set_debug_name(b.resource, name)
}

map_buffer :: proc(
	instance: ^Instance,
	buffer: ^Buffer,
	offset: u64,
	size: u64,
) -> (
	mapped_memory: []u8,
	error: Error,
) {
	b: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
	data: [^]u8
	range := d3d12.RANGE {
		Begin = uint(offset),
		End   = uint(offset + size),
	}
	hr := b.resource->Map(0, &range, (^rawptr)(&data))
	if !win32.SUCCEEDED(hr) {
		log.errorf("Failed to map buffer %d", hr)
		error = .Unknown
		return
	}

	mapped_memory = data[offset:offset + size]
	return
}

unmap_buffer :: proc(instance: ^Instance, buffer: ^Buffer) {
	b: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
	b.resource->Unmap(0, nil)
}

D3D12_CPU_Descriptor_Handle :: bit_field u64 {
	heap_index: u32                        | 28,
	heap_type:  d3d12.DESCRIPTOR_HEAP_TYPE | 4,
	offset:     u32                        | 32,
}

D3D12_Staging_Heap :: struct {
	heap:            ^d3d12.IDescriptorHeap,
	base_descriptor: uint,
	descriptor_size: u32,
}

// once created, cannot be destroyed until the device is destroyed
create_staging_heap :: proc(
	device: ^Device,
	type: d3d12.DESCRIPTOR_HEAP_TYPE,
) -> (
	heap_index: uint,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	heap_index = len(d.heaps)
	desc: d3d12.DESCRIPTOR_HEAP_DESC
	desc.Type = type
	desc.NumDescriptors = d.staging_heap_counts[type]
	desc.Flags = {}

	heap: ^d3d12.IDescriptorHeap
	hr := d.device->CreateDescriptorHeap(&desc, d3d12.IDescriptorHeap_UUID, (^rawptr)(&heap))
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	base_descriptor: d3d12.CPU_DESCRIPTOR_HANDLE
	heap->GetCPUDescriptorHandleForHeapStart(&base_descriptor)
	descriptor_size := d.device->GetDescriptorHandleIncrementSize(type)

	free_descriptors := &d.free_descriptors[type]
	alloc_descriptors_arr := reserve(free_descriptors, desc.NumDescriptors)
	if alloc_descriptors_arr != nil {
		error = .Out_Of_Memory
		return
	}

	for i in 0 ..< desc.NumDescriptors {
		append(
			free_descriptors,
			D3D12_CPU_Descriptor_Handle {
				heap_index = u32(heap_index),
				heap_type = type,
				offset = u32(i),
			},
		)
	}

	_, error_alloc := append(
		&d.heaps,
		D3D12_Staging_Heap {
			heap = heap,
			base_descriptor = base_descriptor.ptr,
			descriptor_size = descriptor_size,
		},
	)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	return
}

allocate_cpu_descriptor :: proc(
	device: ^Device,
	type: d3d12.DESCRIPTOR_HEAP_TYPE,
) -> (
	out_handle: D3D12_CPU_Descriptor_Handle,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	descriptors: ^[dynamic]D3D12_CPU_Descriptor_Handle = &d.free_descriptors[type]

	if len(descriptors) == 0 {
		// add new heap
		_, heap_err := create_staging_heap(device, type)
		if heap_err != nil {
			error = heap_err
			return
		}
	}

	// take a free descriptor
	out_handle = pop(descriptors)
	return
}

free_cpu_descriptor :: proc(device: ^Device, handle: D3D12_CPU_Descriptor_Handle) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	type := handle.heap_type
	_, error := append(&d.free_descriptors[type], handle)
	if error != nil {
		panic("Failed to free descriptor handle")
	}
}

get_staging_descriptor_cpu_pointer :: proc(
	device: ^Device,
	handle: D3D12_CPU_Descriptor_Handle,
) -> (
	out_handle: d3d12.CPU_DESCRIPTOR_HANDLE,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	heap := d.heaps[handle.heap_index]
	out_handle.ptr = heap.base_descriptor + uint(handle.offset) * uint(heap.descriptor_size)
	return
}

D3D12_Device :: struct {
	using _:               Device,
	desc:                  Device_Desc,
	device:                ^d3d12.IDevice5,
	allocator:             ^d3d12ma.Allocator,
	adapter:               ^dxgi.IAdapter1,
	queues:                [Command_Queue_Type]^Command_Queue,
	staging_heap_counts:   [d3d12.DESCRIPTOR_HEAP_TYPE]u32,
	heaps:                 [dynamic]D3D12_Staging_Heap,
	free_descriptors:      [d3d12.DESCRIPTOR_HEAP_TYPE][dynamic]D3D12_CPU_Descriptor_Handle,
	//
	indirect_dispatch_sig: ^d3d12.ICommandSignature,
}

create_device :: proc(
	instance: ^Instance,
	#by_ptr desc: Device_Creation_Desc,
) -> (
	out_device: ^Device,
	error: Error,
) {
	d3d12_instance: ^D3D12_Instance = (^D3D12_Instance)(instance)

	device, error_alloc := new(D3D12_Device)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	requirements := desc.requirements
	resource_count: u32 = 0
	resource_count += requirements.sampler_max_num
	resource_count += requirements.texture_max_num
	resource_count += requirements.buffer_max_num
	resource_count += requirements.render_target_max_num
	resource_count += requirements.depth_stencil_target_max_num
	// means none is specified
	if resource_count == 0 {
		requirements = DEFAULT_RESOURCE_REQUIREMENTS
	}

	device.staging_heap_counts[.SAMPLER] = requirements.sampler_max_num
	device.staging_heap_counts[.CBV_SRV_UAV] =
		requirements.texture_max_num + requirements.buffer_max_num
	device.staging_heap_counts[.RTV] = requirements.render_target_max_num
	device.staging_heap_counts[.DSV] = requirements.depth_stencil_target_max_num

	hr := d3d12_instance.factory->EnumAdapters1(0, &device.adapter)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	adapter_desc: dxgi.ADAPTER_DESC
	device.adapter->GetDesc(&adapter_desc)

	device.desc.adapter_desc.luid = ((^u64)(&adapter_desc.AdapterLuid))^
	device.desc.adapter_desc.video_memory_size = u64(adapter_desc.DedicatedVideoMemory)
	device.desc.adapter_desc.system_memory_size = u64(adapter_desc.DedicatedSystemMemory)
	device.desc.adapter_desc.device_id = u32(adapter_desc.DeviceId)
	device.desc.adapter_desc.vendor = get_vendor_from_id(u32(adapter_desc.VendorId))
	// wcstombs(m_Desc.adapterDesc.name, desc.Description, GetCountOf(m_Desc.adapterDesc.name) - 1);
	win32.WideCharToMultiByte(
		win32.CP_UTF8,
		0,
		raw_data(adapter_desc.Description[:]),
		-1,
		raw_data(device.desc.adapter_desc.name[:]),
		win32.MAX_PATH,
		nil,
		nil,
	)

	// get a device
	hr = d3d12.CreateDevice(device.adapter, ._11_1, d3d12.IDevice5_UUID, (^rawptr)(&device.device))
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	if desc.enable_graphics_api_validation {
		info_queue: ^d3d12.IInfoQueue1
		hr = device.device->QueryInterface(d3d12.IInfoQueue1_UUID, (^rawptr)(&info_queue))
		if win32.SUCCEEDED(hr) {
			defer info_queue->Release()

			info_queue->SetBreakOnSeverity(.CORRUPTION, true)
			info_queue->SetBreakOnSeverity(.ERROR, true)
			// info_queue->SetBreakOnSeverity(.WARNING, true)
			disable_ids := [?]d3d12.MESSAGE_ID {
				.CLEARDEPTHSTENCILVIEW_MISMATCHINGCLEARVALUE,
				.COMMAND_LIST_STATIC_DESCRIPTOR_RESOURCE_DIMENSION_MISMATCH,
			}

			filter: d3d12.INFO_QUEUE_FILTER
			filter.DenyList.pIDList = raw_data(disable_ids[:])
			filter.DenyList.NumIDs = len(disable_ids)
			info_queue->AddStorageFilterEntries(&filter)

			info_queue->RegisterMessageCallback(
				proc "c" (
					category: d3d12.MESSAGE_CATEGORY,
					severity: d3d12.MESSAGE_SEVERITY,
					id: d3d12.MESSAGE_ID,
					msg: cstring,
					callback_cookier: rawptr,
				) {
					context = runtime.default_context()
					log.errorf("DX12: {} {} {} {}", category, severity, id, msg)
				},
				{.IGNORE_FILTERS},
				nil,
				nil,
			)
		} else {
			log.errorf("Could not create info queue")
		}
	}

	// create allocator
	allocator_desc: d3d12ma.ALLOCATOR_DESC
	allocator_desc.pDevice = device.device
	allocator_desc.pAdapter = device.adapter
	allocator_desc.pAllocationCallbacks = nil
	allocator_desc.Flags = {
		.DEFAULT_POOLS_NOT_ZEROED,
		.MSAA_TEXTURES_ALWAYS_COMMITTED,
		.DONT_PREFER_SMALL_BUFFERS_COMMITTED,
	}

	hr = d3d12ma.CreateAllocator(allocator_desc, &device.allocator)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	device.indirect_dispatch_sig = create_command_signature(
		device,
		.DISPATCH,
		nil,
		size_of(Dispatch_Desc),
		false,
	)
	if device.indirect_dispatch_sig == nil {
		error = .Unknown
		return
	}

	device.desc.upload_buffer_texture_row_alignment = d3d12.TEXTURE_DATA_PITCH_ALIGNMENT
	device.desc.upload_buffer_texture_slice_alignment = d3d12.TEXTURE_DATA_PLACEMENT_ALIGNMENT

	out_device = (^Device)(device)
	return
}

destroy_device :: proc(instance: ^Instance, device: ^Device) {
	d: ^D3D12_Device = (^D3D12_Device)(device)

	d.indirect_dispatch_sig.id3d12pageable->Release()

	for queue in d.queues {
		if queue != nil {
			instance->destroy_command_queue(queue)
		}
	}

	for heap in d.heaps {
		heap.heap->Release()
	}
	delete(d.heaps)

	for descriptors in d.free_descriptors {
		delete(descriptors)
	}

	d3d12ma.Allocator_Release(d.allocator)
	d.device->Release()
	d.adapter->Release()
	free(device)
}

get_device_desc :: proc(instance: ^Instance, device: ^Device) -> (desc: Device_Desc) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	return d.desc
}

set_device_debug_name :: proc(
	instance: ^Instance,
	device: ^Device,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	return set_debug_name(d.device, name)
}

get_command_queue :: proc(
	instance: ^Instance,
	device: ^Device,
	type: Command_Queue_Type,
) -> (
	out_queue: ^Command_Queue,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)

	if d.queues[type] == nil {
		d.queues[type] = instance->create_command_queue(device, type) or_return
	}

	out_queue = d.queues[type]
	return
}

D3D12_Command_Allocator :: struct {
	using _:   Command_Allocator,
	queue:     ^D3D12_Command_Queue,
	allocator: ^d3d12.ICommandAllocator,
	type:      d3d12.COMMAND_LIST_TYPE,
}

create_command_allocator :: proc(
	instance: ^Instance,
	queue: ^Command_Queue,
) -> (
	out_allocator: ^Command_Allocator,
	error: Error,
) {
	q: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(queue)
	d: ^D3D12_Device = (^D3D12_Device)(q.device)
	allocator, error_alloc := new(D3D12_Command_Allocator)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	allocator.queue = q

	hr := d.device->CreateCommandAllocator(
		q.type,
		d3d12.ICommandAllocator_UUID,
		(^rawptr)(&allocator.allocator),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	allocator.type = q.type
	out_allocator = (^Command_Allocator)(allocator)
	return
}

destroy_command_allocator :: proc(instance: ^Instance, allocator: ^Command_Allocator) {
	a: ^D3D12_Command_Allocator = (^D3D12_Command_Allocator)(allocator)
	a.allocator->Release()
	free(a)
}

set_command_allocator_debug_name :: proc(
	instance: ^Instance,
	allocator: ^Command_Allocator,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	a: ^D3D12_Command_Allocator = (^D3D12_Command_Allocator)(allocator)
	return set_debug_name(a.allocator, name)
}

reset_command_allocator :: proc(instance: ^Instance, allocator: ^Command_Allocator) {
	a: ^D3D12_Command_Allocator = (^D3D12_Command_Allocator)(allocator)
	a.allocator->Reset()
}

ROOT_SIGNATURE_DWORD_NUM :: 64

D3D12_Command_Buffer :: struct {
	using _:            Command_Buffer,
	allocator:          ^D3D12_Command_Allocator,
	list:               ^d3d12.IGraphicsCommandList4,
	render_targets:     small_array.Small_Array(
		d3d12.SIMULTANEOUS_RENDER_TARGET_COUNT,
		d3d12.CPU_DESCRIPTOR_HANDLE,
	),
	depth_stencil:      d3d12.CPU_DESCRIPTOR_HANDLE,
	pipeline_layout:    ^D3D12_Pipeline_Layout,
	pipeline:           ^D3D12_Pipeline,
	primitive_topology: d3d12.PRIMITIVE_TOPOLOGY,
	descriptor_sets:    small_array.Small_Array(ROOT_SIGNATURE_DWORD_NUM, ^D3D12_Descriptor_Set),
	is_graphics:        bool,
}

create_command_buffer :: proc(
	instance: ^Instance,
	allocator: ^Command_Allocator,
) -> (
	out_buffer: ^Command_Buffer,
	error: Error,
) {
	a: ^D3D12_Command_Allocator = (^D3D12_Command_Allocator)(allocator)
	buffer, error_alloc := new(D3D12_Command_Buffer)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	buffer.allocator = a

	hr := a.queue.device.device->CreateCommandList(
		0,
		a.type,
		a.allocator,
		nil,
		d3d12.IGraphicsCommandList4_UUID,
		(^rawptr)(&buffer.list),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	hr = buffer.list->Close()
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_buffer = (^Command_Buffer)(buffer)
	return
}

destroy_command_buffer :: proc(instance: ^Instance, buffer: ^Command_Buffer) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(buffer)
	b.list->Release()
	free(b)
}

set_command_buffer_debug_name :: proc(
	instance: ^Instance,
	buffer: ^Command_Buffer,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(buffer)
	return set_debug_name(b.list, name)
}

begin_command_buffer :: proc(instance: ^Instance, buffer: ^Command_Buffer) -> (error: Error) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(buffer)
	hr := b.list->Reset(b.allocator.allocator, nil)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}
	b.pipeline_layout = nil
	b.pipeline = nil
	b.is_graphics = false
	b.primitive_topology = .UNDEFINED
	b.render_targets = {}
	return
}

end_command_buffer :: proc(instance: ^Instance, buffer: ^Command_Buffer) -> (error: Error) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(buffer)
	hr := b.list->Close()
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}
	return
}

cmd_set_viewports :: proc(instance: ^Instance, cmd: ^Command_Buffer, viewports: []Viewport) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	temp: small_array.Small_Array(
		d3d12.VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE,
		d3d12.VIEWPORT,
	)
	for viewport in viewports {
		top_left := viewport.y
		height := viewport.height
		if viewport.origin_bottom_left {
			top_left += viewport.height
			height = viewport.height
		}
		small_array.append(
			&temp,
			d3d12.VIEWPORT {
				TopLeftX = viewport.x,
				TopLeftY = top_left,
				Width = viewport.width,
				Height = height,
				MinDepth = viewport.min_depth,
				MaxDepth = viewport.max_depth,
			},
		)
	}
	b.list->RSSetViewports(u32(small_array.len(temp)), raw_data(small_array.slice(&temp)))
}

cmd_set_scissors :: proc(instance: ^Instance, cmd: ^Command_Buffer, scissors: []Rect) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	temp: small_array.Small_Array(
		d3d12.VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE,
		d3d12.RECT,
	)
	for scissor in scissors {
		small_array.append(
			&temp,
			d3d12.RECT {
				left = i32(scissor.x),
				top = i32(scissor.y),
				right = i32(scissor.x + i16(scissor.width)),
				bottom = i32(scissor.y + i16(scissor.height)),
			},
		)
	}
	b.list->RSSetScissorRects(u32(small_array.len(temp)), raw_data(small_array.slice(&temp)))
}

cmd_set_depth_bounds :: proc(instance: ^Instance, cmd: ^Command_Buffer, min, max: f32) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	b.list->OMSetDepthBounds(min, max)
}

cmd_set_stencil_reference :: proc(instance: ^Instance, cmd: ^Command_Buffer, ref: u8) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	b.list->OMSetStencilRef(u32(ref))
}

cmd_set_sample_locations :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	locations: []Sample_Location,
	sample_num: sample,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	#assert(size_of(d3d12.SAMPLE_POSITION) == size_of(Sample_Location))
	pixel_num := len(locations) / int(sample_num)
	b.list->SetSamplePositions(
		u32(sample_num),
		u32(pixel_num),
		([^]d3d12.SAMPLE_POSITION)(raw_data(locations)),
	)
}

cmd_set_blend_constants :: proc(instance: ^Instance, cmd: ^Command_Buffer, constants: [4]f32) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	constants := constants
	b.list->OMSetBlendFactor(&constants)
}

// EN_SHADING_RATE_TO_D3D12 := [Shading_Rate]d3d12.SHADING_RATE {
// 	.Fragment_Size_1x1 = ._1X1,
// 	.Fragment_Size_1x2 = ._1X2,
// 	.Fragment_Size_2x1 = ._2X1,
// 	.Fragment_Size_2x2 = ._2X2,

// 	// Require "is_additional_shading_rates_supported"
// 	.Fragment_Size_2x4 = ._2X4,
// 	.Fragment_Size_4x2 = ._4X2,
// 	.Fragment_Size_4x4 = ._4X4,
// }

// agility sdk
// cmd_set_shading_rate :: proc(
// 	instance: ^Instance,
// 	cmd: ^Command_Buffer,
// 	#by_ptr desc: Shading_Rate_Desc,
// ) {
// 	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
// 	shading_rate := EN_SHADING_RATE_TO_D3D12[desc.shading_rate]

// 	b.list->RSSetShadingRate(d3d12.SHADING_RATE(desc.rate))
// }

// cmd_set_depth_bias is only for agility sdk

cmd_clear_attachments :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	clears: []Clear_Desc,
	rects: []Rect,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)

	d3d_rects: small_array.Small_Array(d3d12.SIMULTANEOUS_RENDER_TARGET_COUNT, d3d12.RECT)
	for rect in rects {
		small_array.append(
			&d3d_rects,
			d3d12.RECT {
				left = i32(rect.x),
				top = i32(rect.y),
				right = i32(rect.x + i16(rect.width)),
				bottom = i32(rect.y + i16(rect.height)),
			},
		)
	}

	d3d_rect_len := u32(small_array.len(d3d_rects))
	d3d_rect_data := raw_data(small_array.slice(&d3d_rects))

	for clear_desc in clears {
		if .Color in clear_desc.planes {
			color: Colorf = clear_desc.value.(Color).(Colorf)
			b.list->ClearRenderTargetView(
				small_array.get(b.render_targets, int(clear_desc.color_attachment_index)),
				&color,
				d3d_rect_len,
				d3d_rect_data,
			)
		} else {
			clear_flags: d3d12.CLEAR_FLAGS
			if .Depth in clear_desc.planes do clear_flags += {.DEPTH}
			if .Stencil in clear_desc.planes do clear_flags += {.STENCIL}

			ds := clear_desc.value.(Depth_Stencil)

			b.list->ClearDepthStencilView(
				b.depth_stencil,
				clear_flags,
				ds.depth,
				u8(ds.stencil),
				u32(small_array.len(d3d_rects)),
				d3d_rect_data,
			)
		}
	}
}

cmd_clear_storage_buffer :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	#by_ptr desc: Clear_Storage_Buffer_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	ds: ^D3D12_Descriptor_Set = small_array.get(b.descriptor_sets, int(desc.set_index))
	resource_view := (^D3D12_Descriptor)(desc.storage_buffer)
	clear_values := [4]u32{desc.value, desc.value, desc.value, desc.value}

	b.list->ClearUnorderedAccessViewUint(
		get_descriptor_set_gpu_pointer(ds, desc.range_index, desc.descriptor_index),
		resource_view.cpu_descriptor,
		resource_view.resource,
		&clear_values,
		0,
		nil,
	)
}

cmd_clear_storage_texture :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	#by_ptr desc: Clear_Storage_Texture_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	ds: ^D3D12_Descriptor_Set = small_array.get(b.descriptor_sets, int(desc.set_index))
	resource_view := (^D3D12_Descriptor)(desc.storage_texture)

	clear_value := desc.value.(Color)
	if resource_view.integer_format {
		b.list->ClearUnorderedAccessViewUint(
			get_descriptor_set_gpu_pointer(ds, desc.range_index, desc.descriptor_index),
			resource_view.cpu_descriptor,
			resource_view.resource,
			&clear_value.(Colorui),
			0,
			nil,
		)
	} else {
		b.list->ClearUnorderedAccessViewFloat(
			get_descriptor_set_gpu_pointer(ds, desc.range_index, desc.descriptor_index),
			resource_view.cpu_descriptor,
			resource_view.resource,
			&clear_value.(Colorf),
			0,
			nil,
		)
	}
}

cmd_begin_rendering :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	#by_ptr desc: Attachments_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	small_array.clear(&b.render_targets)

	for attachment in desc.colors {
		d: ^D3D12_Descriptor = (^D3D12_Descriptor)(attachment)
		small_array.append(&b.render_targets, d.cpu_descriptor)
	}

	if desc.depth_stencil != nil {
		d: ^D3D12_Descriptor = (^D3D12_Descriptor)(desc.depth_stencil)
		b.depth_stencil = d.cpu_descriptor
	} else do b.depth_stencil.ptr = 0

	b.list->OMSetRenderTargets(
		u32(small_array.len(b.render_targets)),
		raw_data(small_array.slice(&b.render_targets)),
		false,
		&b.depth_stencil if b.depth_stencil.ptr != 0 else nil,
	)
}

cmd_end_rendering :: proc(instance: ^Instance, cmd: ^Command_Buffer) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	small_array.clear(&b.render_targets)
}

cmd_set_vertex_buffers :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	base_slot: u32,
	buffers: []^Buffer,
	offsets: []u64,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	vertex_buffer_views: small_array.Small_Array(16, d3d12.VERTEX_BUFFER_VIEW)
	assert(b.pipeline != nil, "Pipeline must be set before setting vertex buffers")
	for buffer, i in buffers {
		if buffer != nil {
			offset := offsets[i] if len(offsets) > 0 else 0
			buf: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
			small_array.append(
				&vertex_buffer_views,
				d3d12.VERTEX_BUFFER_VIEW {
					BufferLocation = buf.resource->GetGPUVirtualAddress() + offset,
					SizeInBytes = win32.UINT(buf.desc.size - offset),
					StrideInBytes = b.pipeline.ia_strides[base_slot + u32(i)],
				},
			)
		} else {
			small_array.append(
				&vertex_buffer_views,
				d3d12.VERTEX_BUFFER_VIEW{BufferLocation = 0, SizeInBytes = 0, StrideInBytes = 0},
			)
		}
	}

	b.list->IASetVertexBuffers(
		base_slot,
		u32(small_array.len(vertex_buffer_views)),
		raw_data(small_array.slice(&vertex_buffer_views)),
	)
}

EN_INDEX_TYPE_TO_D3D12 := [Index_Type]dxgi.FORMAT {
	.Uint16 = .R16_UINT,
	.Uint32 = .R32_UINT,
}

cmd_set_index_buffer :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	buffer: ^Buffer,
	offset: u64,
	format: Index_Type,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	if buffer != nil {
		buf: ^D3D12_Buffer = (^D3D12_Buffer)(buffer)
		b.list->IASetIndexBuffer(
			&d3d12.INDEX_BUFFER_VIEW {
				BufferLocation = buf.resource->GetGPUVirtualAddress() + offset,
				SizeInBytes = win32.UINT(buf.desc.size - offset),
				Format = EN_INDEX_TYPE_TO_D3D12[format],
			},
		)
	} else {
		b.list->IASetIndexBuffer(nil)
	}
}

cmd_set_pipeline_layout :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	layout: ^Pipeline_Layout,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	l := (^D3D12_Pipeline_Layout)(layout)
	if l == b.pipeline_layout do return

	b.pipeline_layout = l
	b.is_graphics = l.is_graphics

	if b.is_graphics {
		b.list->SetGraphicsRootSignature(l.root_signature)
	} else {
		b.list->SetComputeRootSignature(l.root_signature)
	}
}

cmd_set_pipeline :: proc(instance: ^Instance, cmd: ^Command_Buffer, pipeline: ^Pipeline) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	p: ^D3D12_Pipeline = (^D3D12_Pipeline)(pipeline)
	if p == b.pipeline do return

	b.pipeline = p
	b.list->SetPipelineState(p.pipeline)
	if p.layout.is_graphics {
		b.primitive_topology = p.topology
		b.list->IASetPrimitiveTopology(p.topology)
	}
}

cmd_set_descriptor_pool :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	pool: ^Descriptor_Pool,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	p: ^D3D12_Descriptor_Pool = (^D3D12_Descriptor_Pool)(pool)

	b.list->SetDescriptorHeaps(
		u32(small_array.len(p.heap_objects)),
		raw_data(small_array.slice(&p.heap_objects)),
	)
}

cmd_set_descriptor_set :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	set_index: u32,
	set: ^Descriptor_Set,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	ds: ^D3D12_Descriptor_Set = (^D3D12_Descriptor_Set)(set)

	small_array.set(&b.descriptor_sets, int(set_index), ds)
	for _, range_i in small_array.slice(&ds.ranges) {
		gpu_ptr := get_descriptor_set_gpu_pointer(ds, u32(range_i), 0)
		root_param := small_array.get(b.pipeline_layout.sets, int(set_index))
		if b.is_graphics {
			b.list->SetGraphicsRootDescriptorTable(u32(root_param + range_i), gpu_ptr)
		} else {
			b.list->SetComputeRootDescriptorTable(u32(root_param + range_i), gpu_ptr)
		}
	}
}

cmd_set_constants :: proc(instance: ^Instance, cmd: ^Command_Buffer, index: u32, data: []u32) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)

	root_param_index := u32(b.pipeline_layout.base_root_constant) + index
	root_constant_num := len(data) / 4

	if b.is_graphics {
		b.list->SetGraphicsRoot32BitConstants(
			root_param_index,
			u32(root_constant_num),
			raw_data(data),
			0,
		)
	} else {
		b.list->SetComputeRoot32BitConstants(
			root_param_index,
			u32(root_constant_num),
			raw_data(data),
			0,
		)
	}
}

cmd_draw :: proc(instance: ^Instance, cmd: ^Command_Buffer, #by_ptr desc: Draw_Desc) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	if b.pipeline_layout != nil && b.pipeline_layout.enable_draw_parameters {
		base_vertex_instance: struct {
			base_vertex:   u32,
			base_instance: u32,
		} = {desc.base_vertex, desc.base_instance}
		b.list->SetGraphicsRoot32BitConstants(0, 2, (^u32)(&base_vertex_instance), 0)
	}
	b.list->DrawInstanced(desc.vertex_num, desc.instance_num, desc.base_vertex, desc.base_instance)
}

cmd_draw_indexed :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	#by_ptr desc: Draw_Indexed_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	if b.pipeline_layout != nil && b.pipeline_layout.enable_draw_parameters {
		base_vertex_instance: struct {
			base_vertex:   u32,
			base_instance: u32,
		} = {desc.base_vertex, desc.base_instance}
		b.list->SetGraphicsRoot32BitConstants(0, 2, (^u32)(&base_vertex_instance), 0)
	}
	b.list->DrawIndexedInstanced(
		desc.index_num,
		desc.instance_num,
		desc.base_index,
		i32(desc.base_vertex),
		desc.base_instance,
	)
}

cmd_draw_indirect :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	buffer: ^Buffer,
	offset: u64,
	draw_num: u32,
	stride: u32,
	count_buffer: ^Buffer = nil,
	count_buffer_offset: u64 = 0,
) {
	count_buffer_resource: ^d3d12.IResource
	if count_buffer != nil {
		count_buffer_resource = (^D3D12_Buffer)(count_buffer).resource
	}

	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	b.list->ExecuteIndirect(
		b.pipeline_layout.indirect_sig,
		draw_num,
		(^d3d12.IResource)((^D3D12_Buffer)(buffer).resource),
		offset,
		count_buffer_resource,
		count_buffer_offset,
	)
}

cmd_draw_indexed_indirect :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	buffer: ^Buffer,
	offset: u64,
	draw_num: u32,
	stride: u32,
	count_buffer: ^Buffer = nil,
	count_buffer_offset: u64 = 0,
) {
	count_buffer_resource: ^d3d12.IResource
	if count_buffer != nil {
		count_buffer_resource = (^D3D12_Buffer)(count_buffer).resource
	}

	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	b.list->ExecuteIndirect(
		b.pipeline_layout.indirect_indexed_sig,
		draw_num,
		(^d3d12.IResource)((^D3D12_Buffer)(buffer).resource),
		offset,
		count_buffer_resource,
		count_buffer_offset,
	)
}

cmd_copy_buffer :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	dst: ^Buffer,
	dst_offset: u64,
	src: ^Buffer,
	src_offset: u64,
	size: u64,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	size := size
	if size == WHOLE_SIZE do size = (^D3D12_Buffer)(src).desc.size

	b.list->CopyBufferRegion(
		(^d3d12.IResource)((^D3D12_Buffer)(dst).resource),
		dst_offset,
		(^d3d12.IResource)((^D3D12_Buffer)(src).resource),
		src_offset,
		size,
	)
}

cmd_copy_texture :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	dst: ^Texture,
	dst_region: ^Texture_Region_Desc,
	src: ^Texture,
	src_region: ^Texture_Region_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	d: ^D3D12_Texture = (^D3D12_Texture)(dst)
	s: ^D3D12_Texture = (^D3D12_Texture)(src)

	src_region := src_region
	dst_region := dst_region

	is_whole := src_region == nil || dst_region == nil
	if is_whole {
		b.list->CopyResource(d.resource, s.resource)
		return
	}

	whole_resource: Texture_Region_Desc
	if src_region == nil do src_region = &whole_resource
	if dst_region == nil do dst_region = &whole_resource

	dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	dst_texture_copy_location.pResource = d.resource
	dst_texture_copy_location.Type = .SUBRESOURCE_INDEX
	dst_texture_copy_location.SubresourceIndex = get_texture_subresource_index(
		d.desc,
		u32(dst_region.layer_offset),
		u32(dst_region.mip_offset),
	)

	src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	src_texture_copy_location.pResource = s.resource
	src_texture_copy_location.Type = .SUBRESOURCE_INDEX
	src_texture_copy_location.SubresourceIndex = get_texture_subresource_index(
		s.desc,
		u32(src_region.layer_offset),
		u32(src_region.mip_offset),
	)

	size: [3]u32
	size.x =
		u32(get_dimension_mip_adjusted(s.desc, 0, src_region.mip_offset)) if src_region.width == WHOLE_SIZE else u32(src_region.width)
	size.y =
		u32(get_dimension_mip_adjusted(s.desc, 1, src_region.mip_offset)) if src_region.height == WHOLE_SIZE else u32(src_region.height)
	size.z =
		u32(get_dimension_mip_adjusted(s.desc, 2, src_region.mip_offset)) if src_region.depth == WHOLE_SIZE else u32(src_region.depth)

	box: d3d12.BOX
	box.left = u32(src_region.x)
	box.top = u32(src_region.y)
	box.front = u32(src_region.z)
	box.right = u32(src_region.x + u16(size.x))
	box.bottom = u32(src_region.y + u16(size.y))
	box.back = u32(src_region.z + u16(size.z))

	b.list->CopyTextureRegion(
		&dst_texture_copy_location,
		u32(dst_region.x),
		u32(dst_region.y),
		u32(dst_region.z),
		&src_texture_copy_location,
		&box,
	)
}

cmd_resolve_texture :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	dst: ^Texture,
	dst_region: ^Texture_Region_Desc,
	src: ^Texture,
	src_region: ^Texture_Region_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	d: ^D3D12_Texture = (^D3D12_Texture)(dst)
	s: ^D3D12_Texture = (^D3D12_Texture)(src)

	src_region := src_region
	dst_region := dst_region

	is_whole := src_region == nil || dst_region == nil
	if is_whole {
		for layer in 0 ..< d.desc.layer_num {
			for mip in 0 ..< d.desc.mip_num {
				subresource := get_texture_subresource_index(d.desc, u32(layer), u32(mip))
				b.list->ResolveSubresource(
					d.resource,
					subresource,
					s.resource,
					subresource,
					EN_TO_DXGI_FORMAT_TYPED[d.desc.format],
				)
			}
		}
		return
	}

	whole_resource: Texture_Region_Desc
	if src_region == nil do src_region = &whole_resource
	if dst_region == nil do dst_region = &whole_resource

	dst_subresource := get_texture_subresource_index(
		d.desc,
		u32(dst_region.layer_offset),
		u32(dst_region.mip_offset),
	)
	src_subresource := get_texture_subresource_index(
		s.desc,
		u32(src_region.layer_offset),
		u32(src_region.mip_offset),
	)

	src_rect: d3d12.RECT
	src_rect.left = i32(src_region.x)
	src_rect.top = i32(src_region.y)
	src_rect.right = i32(src_region.x + u16(src_region.width))
	src_rect.bottom = i32(src_region.y + u16(src_region.height))

	b.list->ResolveSubresourceRegion(
		d.resource,
		dst_subresource,
		u32(dst_region.x),
		u32(dst_region.y),
		s.resource,
		src_subresource,
		&src_rect,
		EN_TO_DXGI_FORMAT_TYPED[d.desc.format],
		.AVERAGE,
	)
}

cmd_upload_buffer_to_texture :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	dst: ^Texture,
	dst_region: Texture_Region_Desc,
	src: ^Buffer,
	src_data_layout: Texture_Data_Layout_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	d: ^D3D12_Texture = (^D3D12_Texture)(dst)
	s: ^D3D12_Buffer = (^D3D12_Buffer)(src)

	dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	dst_texture_copy_location.pResource = d.resource
	dst_texture_copy_location.Type = .SUBRESOURCE_INDEX
	dst_texture_copy_location.SubresourceIndex = get_texture_subresource_index(
		d.desc,
		u32(dst_region.layer_offset),
		u32(dst_region.mip_offset),
	)

	size: [3]u32
	size.x = u32(
		get_dimension_mip_adjusted(d.desc, 0, dst_region.mip_offset) if dst_region.width == WHOLE_SIZE else dst_region.width,
	)
	size.y = u32(
		get_dimension_mip_adjusted(d.desc, 1, dst_region.mip_offset) if dst_region.height == WHOLE_SIZE else dst_region.height,
	)
	size.z = u32(
		get_dimension_mip_adjusted(d.desc, 2, dst_region.mip_offset) if dst_region.depth == WHOLE_SIZE else dst_region.depth,
	)

	src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	src_texture_copy_location.pResource = s.resource
	src_texture_copy_location.Type = .PLACED_FOOTPRINT
	src_texture_copy_location.PlacedFootprint.Offset = src_data_layout.offset
	src_texture_copy_location.PlacedFootprint.Footprint.Format =
		EN_TO_DXGI_FORMAT_TYPELESS[d.desc.format]
	src_texture_copy_location.PlacedFootprint.Footprint.Width = size.x
	src_texture_copy_location.PlacedFootprint.Footprint.Height = size.y
	src_texture_copy_location.PlacedFootprint.Footprint.Depth = size.z
	src_texture_copy_location.PlacedFootprint.Footprint.RowPitch = src_data_layout.row_pitch

	box: d3d12.BOX
	box.left = u32(dst_region.x)
	box.top = u32(dst_region.y)
	box.front = u32(dst_region.z)
	box.right = u32(dst_region.x + u16(size.x))
	box.bottom = u32(dst_region.y + u16(size.y))
	box.back = u32(dst_region.z + u16(size.z))

	b.list->CopyTextureRegion(
		&dst_texture_copy_location,
		u32(dst_region.x),
		u32(dst_region.y),
		u32(dst_region.z),
		&src_texture_copy_location,
		&box,
	)
}

cmd_readback_texture_to_buffer :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	dst_buffer: ^Buffer,
	dst_data_layout: Texture_Data_Layout_Desc,
	src_texture: ^Texture,
	src_region: Texture_Region_Desc,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	// d: ^D3D12_Buffer = (^D3D12_Buffer)(dst_buffer)
	s: ^D3D12_Texture = (^D3D12_Texture)(src_texture)

	src_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	src_texture_copy_location.pResource = (^D3D12_Texture)(src_texture).resource
	src_texture_copy_location.Type = .SUBRESOURCE_INDEX
	src_texture_copy_location.SubresourceIndex = get_texture_subresource_index(
		s.desc,
		u32(src_region.layer_offset),
		u32(src_region.mip_offset),
	)

	dst_texture_copy_location: d3d12.TEXTURE_COPY_LOCATION
	dst_texture_copy_location.pResource = (^D3D12_Buffer)(dst_buffer).resource
	dst_texture_copy_location.Type = .PLACED_FOOTPRINT
	dst_texture_copy_location.PlacedFootprint.Offset = dst_data_layout.offset
	dst_texture_copy_location.PlacedFootprint.Footprint.Format =
		EN_TO_DXGI_FORMAT_TYPELESS[s.desc.format]
	dst_texture_copy_location.PlacedFootprint.Footprint.Width = u32(src_region.width)
	dst_texture_copy_location.PlacedFootprint.Footprint.Height = u32(src_region.height)
	dst_texture_copy_location.PlacedFootprint.Footprint.Depth = u32(src_region.depth)
	dst_texture_copy_location.PlacedFootprint.Footprint.RowPitch = dst_data_layout.row_pitch

	size: [3]u32
	size.x = u32(
		get_dimension_mip_adjusted(s.desc, 0, src_region.mip_offset) if src_region.width == WHOLE_SIZE else src_region.width,
	)
	size.y = u32(
		get_dimension_mip_adjusted(s.desc, 1, src_region.mip_offset) if src_region.height == WHOLE_SIZE else src_region.height,
	)
	size.z = u32(
		get_dimension_mip_adjusted(s.desc, 2, src_region.mip_offset) if src_region.depth == WHOLE_SIZE else src_region.depth,
	)

	box: d3d12.BOX
	box.left = u32(src_region.x)
	box.top = u32(src_region.y)
	box.front = u32(src_region.z)
	box.right = u32(src_region.x + u16(size.x))
	box.bottom = u32(src_region.y + u16(size.y))
	box.back = u32(src_region.z + u16(size.z))

	b.list->CopyTextureRegion(
		&dst_texture_copy_location,
		0,
		0,
		0,
		&src_texture_copy_location,
		&box,
	)
}

cmd_dispatch :: proc(instance: ^Instance, cmd: ^Command_Buffer, groups: [3]u32) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	b.list->Dispatch(groups[0], groups[1], groups[2])
}

cmd_dispatch_indirect :: proc(
	instance: ^Instance,
	cmd: ^Command_Buffer,
	buffer: ^Buffer,
	offset: u64,
) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)

	b.list->ExecuteIndirect(
		b.allocator.queue.device.indirect_dispatch_sig,
		1,
		(^D3D12_Buffer)(buffer).resource,
		offset,
		nil,
		0,
	)
}

cmd_barrier :: proc(instance: ^Instance, cmd: ^Command_Buffer, #by_ptr desc: Barrier_Group_Desc) {
	b: ^D3D12_Command_Buffer = (^D3D12_Command_Buffer)(cmd)
	@(static) barriers: small_array.Small_Array(512, d3d12.RESOURCE_BARRIER)
	small_array.clear(&barriers)

	barrier_count := len(desc.buffers)

	for texture_barrier in desc.textures {
		t: ^D3D12_Texture = (^D3D12_Texture)(texture_barrier.texture)
		layer_num :=
			t.desc.layer_num if texture_barrier.layer_num == REMAINING_LAYERS else texture_barrier.layer_num
		mip_num :=
			t.desc.mip_num if texture_barrier.mip_num == REMAINING_MIPS else texture_barrier.mip_num

		if texture_barrier.layer_offset == 0 &&
		   layer_num == t.desc.layer_num &&
		   texture_barrier.mip_offset == 0 &&
		   mip_num == t.desc.mip_num {
			barrier_count += 1
		} else {
			barrier_count += int(layer_num * u16(mip_num))
		}
	}

	global_uav_needed := false
	for global_barrier in desc.globals {
		if .Shader_Resource_Storage in global_barrier.before.access &&
		   .Shader_Resource_Storage in global_barrier.after.access {
			global_uav_needed = true
			break
		}
	}

	if global_uav_needed do barrier_count += 1
	if barrier_count == 0 do return

	temp := make([]d3d12.RESOURCE_BARRIER, barrier_count, allocator = context.temp_allocator)
	index := 0

	for barrier in desc.buffers {
		temp[index] = resource_barrier(
			b.allocator.type,
			((^D3D12_Buffer)(barrier.buffer)).resource,
			barrier.before.access,
			barrier.after.access,
			0,
		)
		index += 1
	}

	for barrier in desc.textures {
		t: ^D3D12_Texture = (^D3D12_Texture)(barrier.texture)
		layer_num :=
			t.desc.layer_num if barrier.layer_num == REMAINING_LAYERS else barrier.layer_num
		mip_num := t.desc.mip_num if barrier.mip_num == REMAINING_MIPS else barrier.mip_num

		if barrier.layer_offset == 0 &&
		   layer_num == t.desc.layer_num &&
		   barrier.mip_offset == 0 &&
		   mip_num == t.desc.mip_num {
			temp[index] = resource_barrier(
				b.allocator.type,
				t.resource,
				barrier.before.access,
				barrier.after.access,
				d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
			)
		} else {
			for layer in 0 ..< layer_num {
				for mip in 0 ..< mip_num {
					temp[index] = resource_barrier(
						b.allocator.type,
						t.resource,
						barrier.before.access,
						barrier.after.access,
						get_texture_subresource_index(
							t.desc,
							u32(layer),
							u32(mip),
							barrier.planes,
						),
					)
					index += 1
				}
			}
		}
	}

	if global_uav_needed {
		temp[index].Type = .UAV
		temp[index].UAV.pResource = nil
	}

	b.list->ResourceBarrier(u32(barrier_count), raw_data(temp))
}

get_resource_states :: proc(
	mask: Access_Flags,
	type: d3d12.COMMAND_LIST_TYPE,
) -> (
	states: d3d12.RESOURCE_STATES,
) {
	if .Constant_Buffer in mask || .Vertex_Buffer in mask do states += {.VERTEX_AND_CONSTANT_BUFFER}
	if .Index_Buffer in mask do states += {.INDEX_BUFFER}
	if .Argument_Buffer in mask do states += {.INDIRECT_ARGUMENT}
	if .Shader_Resource_Storage in mask do states += {.UNORDERED_ACCESS}
	if .Color_Attachment in mask do states += {.RENDER_TARGET}
	if .Depth_Stencil_Attachment_Read in mask do states += {.DEPTH_READ}
	if .Depth_Stencil_Attachment_Write in mask do states += {.DEPTH_WRITE}
	if .Copy_Source in mask do states += {.COPY_SOURCE}
	if .Copy_Destination in mask do states += {.COPY_DEST}
	if .Resolve_Source in mask do states += {.RESOLVE_SOURCE}
	if .Resolve_Destination in mask do states += {.RESOLVE_DEST}
	if .Shader_Resource in mask {
		states += {.PIXEL_SHADER_RESOURCE, .NON_PIXEL_SHADER_RESOURCE}
		// if type == .DIRECT do states += {.PIXEL_SHADER_RESOURCE}
	}
	if .Acceleration_Structure_Read in mask do states += {.RAYTRACING_ACCELERATION_STRUCTURE}
	if .Acceleration_Structure_Write in mask do states += {.UNORDERED_ACCESS}
	if .Shading_Rate_Attachment in mask do states += {.SHADING_RATE_SOURCE}
	return
}

resource_barrier :: proc(
	type: d3d12.COMMAND_LIST_TYPE,
	resource: ^d3d12.IResource,
	before, after: Access_Flags,
	subresource: u32,
) -> (
	barrier: d3d12.RESOURCE_BARRIER,
) {
	state_before := get_resource_states(before, type)
	state_after := get_resource_states(after, type)

	if state_before == state_after && state_before == {.UNORDERED_ACCESS} {
		barrier.Type = .UAV
		barrier.UAV.pResource = resource
	} else {
		barrier.Type = .TRANSITION
		barrier.Transition.pResource = resource
		barrier.Transition.StateBefore = state_before
		barrier.Transition.StateAfter = state_after
		barrier.Transition.Subresource = subresource
	}
	return
}

D3D12_Command_Queue :: struct {
	using _: Command_Queue,
	device:  ^D3D12_Device,
	queue:   ^d3d12.ICommandQueue,
	type:    d3d12.COMMAND_LIST_TYPE,
	fence:   ^D3D12_Fence,
}

get_command_list_type :: proc(type: Command_Queue_Type) -> d3d12.COMMAND_LIST_TYPE {
	switch type {
	case .Graphics:
		return .DIRECT
	case .Compute:
		return .COMPUTE
	case .Copy:
		return .COPY
	case .High_Priority_Copy:
		return .COPY
	}
	unreachable()
}

create_command_queue :: proc(
	instance: ^Instance,
	device: ^Device,
	type: Command_Queue_Type,
) -> (
	out_queue: ^Command_Queue,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	queue, error_alloc := new(D3D12_Command_Queue)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	queue.device = d

	desc: d3d12.COMMAND_QUEUE_DESC
	desc.Priority = i32(
		d3d12.COMMAND_QUEUE_PRIORITY.HIGH if type == .High_Priority_Copy else d3d12.COMMAND_QUEUE_PRIORITY.NORMAL,
	)
	desc.Type = get_command_list_type(type)

	hr := d.device->CreateCommandQueue(&desc, d3d12.ICommandQueue_UUID, (^rawptr)(&queue.queue))
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	queue.type = desc.Type
	out_queue = (^Command_Queue)(queue)

	return
}

destroy_command_queue :: proc(instance: ^Instance, queue: ^Command_Queue) {
	q := (^D3D12_Command_Queue)(queue)
	q.queue->Release()
	free(q)
}

set_command_queue_debug_name :: proc(
	instance: ^Instance,
	queue: ^Command_Queue,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	q: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(queue)
	return set_debug_name(q.queue, name)
}

submit :: proc(instance: ^Instance, queue: ^Command_Queue, buffers: []^Command_Buffer) {
	queue: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(queue)

	command_lists: small_array.Small_Array(16, ^d3d12.IGraphicsCommandList)
	for buffer in buffers {
		small_array.append(&command_lists, (^D3D12_Command_Buffer)(buffer).list)
	}

	queue.queue->ExecuteCommandLists(
		u32(small_array.len(command_lists)),
		auto_cast raw_data(small_array.slice(&command_lists)),
	)
}

D3D12_Descriptor_Type :: enum {
	Resource,
	Sampler,
}

EN_TO_D3D12_DESCRIPTOR_TYPE := [Descriptor_Type]D3D12_Descriptor_Type {
	.Sampler                   = .Sampler,
	.Constant_Buffer           = .Resource,
	.Texture                   = .Resource,
	.Storage_Texture           = .Resource,
	.Buffer                    = .Resource,
	.Storage_Buffer            = .Resource,
	.Structured_Buffer         = .Resource,
	.Storage_Structured_Buffer = .Resource,
	.Acceleration_Structure    = .Resource,
}

D3D12_Descriptor :: struct {
	resource:            ^d3d12.IResource,
	buffer_gpu_location: d3d12.GPU_VIRTUAL_ADDRESS,
	// from below (see D3D12_Descriptor_Heap and D3D12_Descriptor_Pool)
	cpu_descriptor:      d3d12.CPU_DESCRIPTOR_HANDLE,
	handle:              D3D12_CPU_Descriptor_Handle,
	heap_type:           d3d12.DESCRIPTOR_HEAP_TYPE,
	buffer_view_type:    Buffer_View_Type,
	integer_format:      bool,
}

SHADER_COMPONENT_MAPPING_ALWAYS_SET_BIT_AVOIDING_ZEROMEM_MISTAKES ::
	1 << (d3d12.SHADER_COMPONENT_MAPPING_SHIFT * 4)
ENCODE_SHADER_4_COMPONENT_MAPPING :: proc(
	Src0, Src1, Src2, Src3: d3d12.SHADER_COMPONENT_MAPPING,
) -> u32 {
	return(
		(u32(Src0) & d3d12.SHADER_COMPONENT_MAPPING_MASK) |
		((u32(Src1) & d3d12.SHADER_COMPONENT_MAPPING_MASK) <<
				d3d12.SHADER_COMPONENT_MAPPING_SHIFT) |
		((u32(Src2) & d3d12.SHADER_COMPONENT_MAPPING_MASK) <<
				(d3d12.SHADER_COMPONENT_MAPPING_SHIFT * 2)) |
		((u32(Src3) & d3d12.SHADER_COMPONENT_MAPPING_MASK) <<
				(d3d12.SHADER_COMPONENT_MAPPING_SHIFT * 3)) |
		SHADER_COMPONENT_MAPPING_ALWAYS_SET_BIT_AVOIDING_ZEROMEM_MISTAKES \
	)
}
DECODE_SHADER_4_COMPONENT_MAPPING :: proc(
	ComponentToExtract, Mapping: u32,
) -> d3d12.SHADER_COMPONENT_MAPPING {
	return d3d12.SHADER_COMPONENT_MAPPING(
		Mapping >>
		(d3d12.SHADER_COMPONENT_MAPPING_SHIFT * ComponentToExtract) &
		d3d12.SHADER_COMPONENT_MAPPING_MASK,
	)
}
DEFAULT_SHADER_4_COMPONENT_MAPPING := ENCODE_SHADER_4_COMPONENT_MAPPING(
	.FROM_MEMORY_COMPONENT_0,
	.FROM_MEMORY_COMPONENT_1,
	.FROM_MEMORY_COMPONENT_2,
	.FROM_MEMORY_COMPONENT_3,
)

create_srv :: proc(
	device: ^D3D12_Device,
	descriptor: ^D3D12_Descriptor,
	resource: ^d3d12.IResource,
	desc: d3d12.SHADER_RESOURCE_VIEW_DESC,
) -> (
	error: Error,
) {
	desc := desc
	out_handle := allocate_cpu_descriptor(device, .CBV_SRV_UAV) or_return
	descriptor.handle = out_handle
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(device, out_handle)
	descriptor.resource = resource
	device.device->CreateShaderResourceView(resource, &desc, descriptor.cpu_descriptor)
	return
}

create_uav :: proc(
	device: ^D3D12_Device,
	descriptor: ^D3D12_Descriptor,
	resource: ^d3d12.IResource,
	desc: d3d12.UNORDERED_ACCESS_VIEW_DESC,
	format: Format,
) -> (
	error: Error,
) {
	desc := desc
	out_handle := allocate_cpu_descriptor(device, .CBV_SRV_UAV) or_return
	descriptor.handle = out_handle
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(device, out_handle)
	descriptor.resource = resource
	descriptor.integer_format = FORMAT_PROPS[format].is_integer
	device.device->CreateUnorderedAccessView(resource, nil, &desc, descriptor.cpu_descriptor)
	return
}

create_rtv :: proc(
	device: ^D3D12_Device,
	descriptor: ^D3D12_Descriptor,
	resource: ^d3d12.IResource,
	desc: d3d12.RENDER_TARGET_VIEW_DESC,
) -> (
	error: Error,
) {
	desc := desc
	out_handle := allocate_cpu_descriptor(device, .RTV) or_return
	descriptor.handle = out_handle
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(device, out_handle)
	descriptor.resource = resource
	device.device->CreateRenderTargetView(resource, &desc, descriptor.cpu_descriptor)
	return
}

create_dsv :: proc(
	device: ^D3D12_Device,
	descriptor: ^D3D12_Descriptor,
	resource: ^d3d12.IResource,
	desc: d3d12.DEPTH_STENCIL_VIEW_DESC,
) -> (
	error: Error,
) {
	desc := desc
	out_handle := allocate_cpu_descriptor(device, .DSV) or_return
	descriptor.handle = out_handle
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(device, out_handle)
	descriptor.resource = resource
	device.device->CreateDepthStencilView(resource, &desc, descriptor.cpu_descriptor)
	return
}

create_cbv :: proc(
	device: ^D3D12_Device,
	descriptor: ^D3D12_Descriptor,
	resource: ^d3d12.IResource,
	desc: d3d12.CONSTANT_BUFFER_VIEW_DESC,
) -> (
	error: Error,
) {
	desc := desc
	out_handle := allocate_cpu_descriptor(device, .CBV_SRV_UAV) or_return
	descriptor.handle = out_handle
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(device, out_handle)
	descriptor.resource = resource
	device.device->CreateConstantBufferView(&desc, descriptor.cpu_descriptor)
	return
}

create_1d_texture_view :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Texture_1D_View_Desc,
) -> (
	out_descriptor: ^Descriptor,
	error: Error,
) {
	// i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	d: ^D3D12_Device = (^D3D12_Device)(device)
	t: ^D3D12_Texture = (^D3D12_Texture)(desc.texture)

	descriptor, error_alloc := new(D3D12_Descriptor)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	texture_desc := t.desc
	remaining_mips :=
		(texture_desc.mip_num - desc.mip_offset) if desc.mip_num == REMAINING_MIPS else desc.mip_num
	remaining_layers :=
		(texture_desc.layer_num - desc.layer_offset) if desc.layer_num == REMAINING_LAYERS else desc.layer_num

	out_descriptor = (^Descriptor)(descriptor)
	switch desc.view_type {
	case .Shader_Resource:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		srv_desc.ViewDimension = .TEXTURE1D
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.Texture1D.MostDetailedMip = u32(desc.mip_offset)
		srv_desc.Texture1D.MipLevels = u32(remaining_mips)
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Array:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		srv_desc.ViewDimension = .TEXTURE1DARRAY
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.Texture1DArray.MostDetailedMip = u32(desc.mip_offset)
		srv_desc.Texture1DArray.MipLevels = u32(remaining_mips)
		srv_desc.Texture1DArray.FirstArraySlice = u32(desc.layer_offset)
		srv_desc.Texture1DArray.ArraySize = u32(remaining_layers)
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Storage:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		uav_desc.ViewDimension = .TEXTURE1D
		uav_desc.Texture1D.MipSlice = u32(desc.mip_offset)
		create_uav(d, descriptor, t.resource, uav_desc, texture_desc.format) or_return
		return
	case .Shader_Resource_Storage_Array:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		uav_desc.ViewDimension = .TEXTURE1DARRAY
		uav_desc.Texture1DArray.MipSlice = u32(desc.mip_offset)
		uav_desc.Texture1DArray.FirstArraySlice = u32(desc.layer_offset)
		uav_desc.Texture1DArray.ArraySize = u32(remaining_layers)
		create_uav(d, descriptor, t.resource, uav_desc, texture_desc.format) or_return
		return
	case .Color_Attachment:
		rtv_desc: d3d12.RENDER_TARGET_VIEW_DESC
		rtv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		rtv_desc.ViewDimension = .TEXTURE1D
		rtv_desc.Texture1D.MipSlice = u32(desc.mip_offset)
		create_rtv(d, descriptor, t.resource, rtv_desc) or_return
		return
	case .Depth_Stencil_Attachment,
	     .Depth_Stencil_Readonly,
	     .Depth_Attachment_Stencil_Readonly,
	     .Depth_Readonly_Stencil_Attachment:
		dsv_desc: d3d12.DEPTH_STENCIL_VIEW_DESC
		dsv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		dsv_desc.ViewDimension = .TEXTURE1DARRAY
		dsv_desc.Texture1DArray.MipSlice = u32(desc.mip_offset)
		dsv_desc.Texture1DArray.FirstArraySlice = u32(desc.layer_offset)
		dsv_desc.Texture1DArray.ArraySize = u32(remaining_layers)

		#partial switch desc.view_type {
		case .Depth_Readonly_Stencil_Attachment:
			dsv_desc.Flags = {.READ_ONLY_DEPTH}
		case .Depth_Attachment_Stencil_Readonly:
			dsv_desc.Flags = {.READ_ONLY_STENCIL}
		case .Depth_Stencil_Readonly:
			dsv_desc.Flags = {.READ_ONLY_DEPTH, .READ_ONLY_STENCIL}
		}

		create_dsv(d, descriptor, t.resource, dsv_desc) or_return
		return
	}

	error = .Unknown
	return
}

get_plane_index :: proc "contextless" (format: Format) -> u32 {
	#partial switch format {
	case .X32_G8_UINT_X24:
	case .X24_G8_UINT:
		return 1
	case:
		return 0
	}
	return 0
}

format_for_depth :: proc "contextless" (format: dxgi.FORMAT) -> dxgi.FORMAT {
	#partial switch format {
	case .D16_UNORM:
		return .R16_UNORM
	case .D24_UNORM_S8_UINT:
		return .R24_UNORM_X8_TYPELESS
	case .D32_FLOAT:
		return .R32_FLOAT
	case .D32_FLOAT_S8X24_UINT:
		return .R32_FLOAT_X8X24_TYPELESS
	}
	return format
}

create_2d_texture_view :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Texture_2D_View_Desc,
) -> (
	out_descriptor: ^Descriptor,
	error: Error,
) {
	// i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	d: ^D3D12_Device = (^D3D12_Device)(device)
	t: ^D3D12_Texture = (^D3D12_Texture)(desc.texture)

	descriptor, error_alloc := new(D3D12_Descriptor)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	texture_desc := t.desc
	remaining_mips :=
		(texture_desc.mip_num - desc.mip_offset) if desc.mip_num == REMAINING_MIPS else desc.mip_num
	remaining_layers :=
		(texture_desc.layer_num - desc.layer_offset) if desc.layer_num == REMAINING_LAYERS else desc.layer_num

	out_descriptor = (^Descriptor)(descriptor)
	switch desc.view_type {
	case .Shader_Resource:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = format_for_depth(EN_TO_DXGI_FORMAT_TYPED[texture_desc.format])
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		if texture_desc.sample_num > 1 {
			srv_desc.ViewDimension = .TEXTURE2DMS
		} else {
			srv_desc.ViewDimension = .TEXTURE2D
			srv_desc.Texture2D.MostDetailedMip = u32(desc.mip_offset)
			srv_desc.Texture2D.MipLevels = u32(remaining_mips)
			srv_desc.Texture2D.PlaneSlice = get_plane_index(texture_desc.format)
		}
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Array:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = format_for_depth(EN_TO_DXGI_FORMAT_TYPED[texture_desc.format])
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		if (texture_desc.sample_num > 1) {
			srv_desc.ViewDimension = .TEXTURE2DMSARRAY
			srv_desc.Texture2DMSArray.FirstArraySlice = u32(desc.layer_offset)
			srv_desc.Texture2DMSArray.ArraySize = u32(remaining_layers)
		} else {
			srv_desc.ViewDimension = .TEXTURE2DARRAY
			srv_desc.Texture2DArray.MostDetailedMip = u32(desc.mip_offset)
			srv_desc.Texture2DArray.MipLevels = u32(remaining_mips)
			srv_desc.Texture2DArray.FirstArraySlice = u32(desc.layer_offset)
			srv_desc.Texture2DArray.ArraySize = u32(remaining_layers)
			srv_desc.Texture2DArray.PlaneSlice = get_plane_index(desc.format)
		}
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Cube:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = format_for_depth(EN_TO_DXGI_FORMAT_TYPED[texture_desc.format])
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.ViewDimension = .TEXTURECUBE
		srv_desc.TextureCube.MostDetailedMip = u32(desc.mip_offset)
		srv_desc.TextureCube.MipLevels = u32(remaining_mips)
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Cube_Array:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = format_for_depth(EN_TO_DXGI_FORMAT_TYPED[texture_desc.format])
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.ViewDimension = .TEXTURECUBEARRAY
		srv_desc.TextureCubeArray.MostDetailedMip = u32(desc.mip_offset)
		srv_desc.TextureCubeArray.MipLevels = u32(remaining_mips)
		srv_desc.TextureCubeArray.First2DArrayFace = u32(desc.layer_offset)
		srv_desc.TextureCubeArray.NumCubes = u32(remaining_layers / 6)
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Storage:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		uav_desc.ViewDimension = .TEXTURE2D
		uav_desc.Texture2D.MipSlice = u32(desc.mip_offset)
		uav_desc.Texture2D.PlaneSlice = get_plane_index(texture_desc.format)
		create_uav(d, descriptor, t.resource, uav_desc, texture_desc.format) or_return
		return
	case .Shader_Resource_Storage_Array:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		uav_desc.ViewDimension = .TEXTURE2DARRAY
		uav_desc.Texture2DArray.MipSlice = u32(desc.mip_offset)
		uav_desc.Texture2DArray.FirstArraySlice = u32(desc.layer_offset)
		uav_desc.Texture2DArray.ArraySize = u32(remaining_layers)
		uav_desc.Texture2DArray.PlaneSlice = get_plane_index(texture_desc.format)
		create_uav(d, descriptor, t.resource, uav_desc, texture_desc.format) or_return
		return
	case .Color_Attachment:
		rtv_desc: d3d12.RENDER_TARGET_VIEW_DESC
		rtv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		rtv_desc.ViewDimension = .TEXTURE2DARRAY
		rtv_desc.Texture2DArray.MipSlice = u32(desc.mip_offset)
		rtv_desc.Texture2DArray.FirstArraySlice = u32(desc.layer_offset)
		rtv_desc.Texture2DArray.ArraySize = u32(remaining_layers)
		rtv_desc.Texture2DArray.PlaneSlice = get_plane_index(texture_desc.format)
		create_rtv(d, descriptor, t.resource, rtv_desc) or_return
		return
	case .Depth_Stencil_Attachment,
	     .Depth_Stencil_Readonly,
	     .Depth_Attachment_Stencil_Readonly,
	     .Depth_Readonly_Stencil_Attachment:
		dsv_desc: d3d12.DEPTH_STENCIL_VIEW_DESC
		dsv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		dsv_desc.ViewDimension = .TEXTURE2DARRAY
		dsv_desc.Texture2DArray.MipSlice = u32(desc.mip_offset)
		dsv_desc.Texture2DArray.FirstArraySlice = u32(desc.layer_offset)
		dsv_desc.Texture2DArray.ArraySize = u32(remaining_layers)

		#partial switch desc.view_type {
		case .Depth_Readonly_Stencil_Attachment:
			dsv_desc.Flags = {.READ_ONLY_DEPTH}
		case .Depth_Attachment_Stencil_Readonly:
			dsv_desc.Flags = {.READ_ONLY_STENCIL}
		case .Depth_Stencil_Readonly:
			dsv_desc.Flags = {.READ_ONLY_DEPTH, .READ_ONLY_STENCIL}
		}

		create_dsv(d, descriptor, t.resource, dsv_desc) or_return
		return
	case .Shading_Rate_Attachment:
		descriptor.resource = t.resource
		return
	}

	error = .Unknown
	return
}

create_3d_texture_view :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Texture_3D_View_Desc,
) -> (
	out_descriptor: ^Descriptor,
	error: Error,
) {
	// i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	d: ^D3D12_Device = (^D3D12_Device)(device)
	t: ^D3D12_Texture = (^D3D12_Texture)(desc.texture)

	descriptor, error_alloc := new(D3D12_Descriptor)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	texture_desc := t.desc
	remaining_mips :=
		(texture_desc.mip_num - desc.mip_offset) if desc.mip_num == REMAINING_MIPS else desc.mip_num

	out_descriptor = (^Descriptor)(descriptor)
	switch desc.view_type {
	case .Shader_Resource:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		srv_desc.ViewDimension = .TEXTURE3D
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.Texture3D.MostDetailedMip = u32(desc.mip_offset)
		srv_desc.Texture3D.MipLevels = u32(remaining_mips)
		create_srv(d, descriptor, t.resource, srv_desc) or_return
		return
	case .Shader_Resource_Storage:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		uav_desc.ViewDimension = .TEXTURE3D
		uav_desc.Texture3D.MipSlice = u32(desc.mip_offset)
		uav_desc.Texture3D.FirstWSlice = u32(desc.slice_offset)
		uav_desc.Texture3D.WSize = u32(desc.slice_num)
		create_uav(d, descriptor, t.resource, uav_desc, texture_desc.format) or_return
		return
	case .Color_Attachment:
		rtv_desc: d3d12.RENDER_TARGET_VIEW_DESC
		rtv_desc.Format = EN_TO_DXGI_FORMAT_TYPED[texture_desc.format]
		rtv_desc.ViewDimension = .TEXTURE3D
		rtv_desc.Texture3D.MipSlice = u32(desc.mip_offset)
		rtv_desc.Texture3D.FirstWSlice = u32(desc.slice_offset)
		rtv_desc.Texture3D.WSize = u32(desc.slice_num)
		create_rtv(d, descriptor, t.resource, rtv_desc) or_return
		return
	}
	return
}

create_buffer_view :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Buffer_View_Desc,
) -> (
	out_descriptor: ^Descriptor,
	error: Error,
) {
	// i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	d: ^D3D12_Device = (^D3D12_Device)(device)
	b: ^D3D12_Buffer = (^D3D12_Buffer)(desc.buffer)

	descriptor, error_alloc := new(D3D12_Descriptor)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	buffer_desc := b.desc
	size := buffer_desc.size if desc.size == WHOLE_SIZE else desc.size

	format := EN_TO_DXGI_FORMAT_TYPED[desc.format]
	props := FORMAT_PROPS[desc.format]
	element_size :=
		buffer_desc.structure_stride if buffer_desc.structure_stride > 0 else u32(props.stride)
	element_offset := u32(desc.offset / u64(element_size))
	element_num := u32(size / u64(element_size))

	descriptor.buffer_gpu_location = b.resource->GetGPUVirtualAddress() + desc.offset
	descriptor.buffer_view_type = desc.view_type

	out_descriptor = (^Descriptor)(descriptor)
	switch desc.view_type {
	case .Shader_Resource:
		srv_desc: d3d12.SHADER_RESOURCE_VIEW_DESC
		srv_desc.Format = format if buffer_desc.structure_stride == 0 else .UNKNOWN
		srv_desc.Shader4ComponentMapping = DEFAULT_SHADER_4_COMPONENT_MAPPING
		srv_desc.ViewDimension = .BUFFER
		srv_desc.Buffer.FirstElement = u64(element_offset)
		srv_desc.Buffer.NumElements = element_num
		srv_desc.Buffer.StructureByteStride = buffer_desc.structure_stride
		create_srv(d, descriptor, b.resource, srv_desc) or_return
		return
	case .Shader_Resource_Storage:
		uav_desc: d3d12.UNORDERED_ACCESS_VIEW_DESC
		uav_desc.Format = format
		uav_desc.ViewDimension = .BUFFER
		uav_desc.Buffer.FirstElement = u64(element_offset)
		uav_desc.Buffer.NumElements = element_num
		uav_desc.Buffer.StructureByteStride = buffer_desc.structure_stride
		uav_desc.Buffer.CounterOffsetInBytes = 0
		create_uav(d, descriptor, b.resource, uav_desc, desc.format) or_return
		return
	case .Constant:
		cbv_desc: d3d12.CONSTANT_BUFFER_VIEW_DESC
		cbv_desc.BufferLocation = descriptor.buffer_gpu_location
		cbv_desc.SizeInBytes = u32(size)

		create_cbv(d, descriptor, b.resource, cbv_desc) or_return
		return
	}

	error = .Unknown
	return
}

get_filter_anisotropic :: proc "contextless" (
	ext: Filter_Ext,
	use_comparison: bool,
) -> d3d12.FILTER {
	if ext == .Min do return .MINIMUM_ANISOTROPIC
	if ext == .Max do return .MAXIMUM_ANISOTROPIC
	if use_comparison do return .COMPARISON_ANISOTROPIC
	return .ANISOTROPIC
}

get_filter_isotropic :: proc "contextless" (
	mip: Filter,
	mag: Filter,
	min: Filter,
	ext: Filter_Ext,
	use_comparison: bool,
) -> d3d12.FILTER {
	combined_mask: u32 = 0
	combined_mask |= 0x1 if mip == .Nearest else 0
	combined_mask |= 0x4 if mag == .Linear else 0
	combined_mask |= 0x10 if min == .Linear else 0

	if use_comparison do combined_mask |= 0x80
	else if ext == .Min do combined_mask |= 0x100
	else if ext == .Max do combined_mask |= 0x180

	return d3d12.FILTER(combined_mask)
}

EN_ADDRESS_MODE_TO_D3D12 := [Address_Mode]d3d12.TEXTURE_ADDRESS_MODE {
	.Repeat               = .WRAP,
	.Mirrored_Repeat      = .MIRROR,
	.Clamp_To_Edge        = .CLAMP,
	.Clamp_To_Border      = .BORDER,
	.Mirror_Clamp_To_Edge = .MIRROR_ONCE,
}

EN_TO_D3D12_COMPARISON_FUNC := [Compare_Func]d3d12.COMPARISON_FUNC {
	.None          = .NEVER,
	.Always        = .ALWAYS,
	.Never         = .NEVER,
	.Equal         = .EQUAL,
	.Not_Equal     = .NOT_EQUAL,
	.Less          = .LESS,
	.Less_Equal    = .LESS_EQUAL,
	.Greater       = .GREATER,
	.Greater_Equal = .GREATER_EQUAL,
}

create_sampler :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Sampler_Desc,
) -> (
	out_sampler: ^Descriptor,
	error: Error,
) {
	// i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	d: ^D3D12_Device = (^D3D12_Device)(device)

	descriptor, error_alloc := new(D3D12_Descriptor)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	descriptor.handle = allocate_cpu_descriptor(d, .SAMPLER) or_return
	descriptor.cpu_descriptor = get_staging_descriptor_cpu_pointer(d, descriptor.handle)

	use_anisotropy := desc.anisotropy > 1
	use_comparison := desc.compare_func != .None
	anisotropy_filter := get_filter_anisotropic(desc.filters.ext, use_comparison)
	isotropy_filter := get_filter_isotropic(
		desc.filters.mip,
		desc.filters.mag,
		desc.filters.min,
		desc.filters.ext,
		use_comparison,
	)
	filter := anisotropy_filter if use_anisotropy else isotropy_filter

	sampler_desc: d3d12.SAMPLER_DESC
	sampler_desc.Filter = filter
	sampler_desc.AddressU = EN_ADDRESS_MODE_TO_D3D12[desc.address_modes.u]
	sampler_desc.AddressV = EN_ADDRESS_MODE_TO_D3D12[desc.address_modes.v]
	sampler_desc.AddressW = EN_ADDRESS_MODE_TO_D3D12[desc.address_modes.w]
	sampler_desc.MipLODBias = desc.mip_bias
	sampler_desc.MaxAnisotropy = u32(desc.anisotropy)
	sampler_desc.ComparisonFunc = EN_TO_D3D12_COMPARISON_FUNC[desc.compare_func]
	sampler_desc.MinLOD = desc.mip_min
	sampler_desc.MaxLOD = desc.mip_max

	if (!desc.is_integer) {
		colorf := desc.border_color.(Colorf)
		sampler_desc.BorderColor[0] = colorf.r
		sampler_desc.BorderColor[1] = colorf.g
		sampler_desc.BorderColor[2] = colorf.b
		sampler_desc.BorderColor[3] = colorf.a
	}

	d.device->CreateSampler(&sampler_desc, descriptor.cpu_descriptor)

	out_sampler = (^Descriptor)(descriptor)
	return
}

destroy_descriptor :: proc(instance: ^Instance, device: ^Device, descriptor: ^Descriptor) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	d3d12_descriptor: ^D3D12_Descriptor = (^D3D12_Descriptor)(descriptor)
	free_cpu_descriptor(d, d3d12_descriptor.handle)
	free(d3d12_descriptor)
}

set_descriptor_debug_name :: proc(
	instance: ^Instance,
	descriptor: ^Descriptor,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	// unused
	return
}

D3D12_Descriptor_Heap :: struct {
	heap:                  ^d3d12.IDescriptorHeap,
	base_cpu_descriptor:   d3d12.CPU_DESCRIPTOR_HANDLE,
	base_gpu_descriptor:   d3d12.GPU_DESCRIPTOR_HANDLE,
	descriptor_size:       u32,
	num_descriptors:       u32,
	allocated_descriptors: u32,
}

D3D12_Descriptor_Pool :: struct {
	using _:              Descriptor_Pool,
	device:               ^D3D12_Device,
	// CBV/SRV/UAV and Sampler heaps
	heap_info:            [D3D12_Descriptor_Type]D3D12_Descriptor_Heap,
	heap_objects:         small_array.Small_Array(2, ^d3d12.IDescriptorHeap),
	descriptor_sets:      []D3D12_Descriptor_Set,
	used_descriptor_sets: uint,
}

create_descriptor_pool :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Descriptor_Pool_Desc,
) -> (
	out_pool: ^Descriptor_Pool,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	pool, error_alloc := new(D3D12_Descriptor_Pool)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	pool.device = d
	heap_sizes: [D3D12_Descriptor_Type]u32
	heap_sizes[.Resource] += desc.constant_buffer_max_num
	heap_sizes[.Resource] += desc.texture_max_num
	heap_sizes[.Resource] += desc.storage_texture_max_num
	heap_sizes[.Resource] += desc.buffer_max_num
	heap_sizes[.Resource] += desc.storage_buffer_max_num
	heap_sizes[.Resource] += desc.structured_buffer_max_num
	heap_sizes[.Resource] += desc.storage_structured_buffer_max_num
	heap_sizes[.Resource] += desc.acceleration_structure_max_num
	heap_sizes[.Sampler] += desc.sampler_max_num

	for num, type in heap_sizes {
		info := &pool.heap_info[type]
		info.num_descriptors = num

		if num == 0 do continue

		desc: d3d12.DESCRIPTOR_HEAP_DESC
		desc.Type = .CBV_SRV_UAV if type == .Resource else .SAMPLER
		desc.NumDescriptors = num
		desc.Flags = {.SHADER_VISIBLE}

		hr := d.device->CreateDescriptorHeap(
			&desc,
			d3d12.IDescriptorHeap_UUID,
			(^rawptr)(&info.heap),
		)
		if !win32.SUCCEEDED(hr) {
			error = .Unknown
			return
		}

		info.heap->GetCPUDescriptorHandleForHeapStart(&info.base_cpu_descriptor)
		info.heap->GetGPUDescriptorHandleForHeapStart(&info.base_gpu_descriptor)
		info.descriptor_size = d.device->GetDescriptorHandleIncrementSize(desc.Type)

		small_array.append(&pool.heap_objects, info.heap)
	}

	pool.descriptor_sets = make([]D3D12_Descriptor_Set, desc.descriptor_set_max_num)

	out_pool = (^Descriptor_Pool)(pool)
	return
}

destroy_descriptor_pool :: proc(instance: ^Instance, pool: ^Descriptor_Pool) {
	p: ^D3D12_Descriptor_Pool = (^D3D12_Descriptor_Pool)(pool)
	for heap in small_array.slice(&p.heap_objects) {
		if heap != nil {
			heap->Release()
		}
	}
	delete(p.descriptor_sets)

	free(p)
}

set_descriptor_pool_debug_name :: proc(
	instance: ^Instance,
	pool: ^Descriptor_Pool,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	p: ^D3D12_Descriptor_Pool = (^D3D12_Descriptor_Pool)(pool)
	for &heap in small_array.slice(&p.heap_objects) {
		if heap != nil {
			set_debug_name(heap, name)
		}
	}

	return
}

allocate_descriptors_from_descriptor_pool :: proc(
	pool: ^D3D12_Descriptor_Pool,
	type: D3D12_Descriptor_Type,
	num: u32,
) -> (
	index: u32,
	err: Error,
) {
	info := &pool.heap_info[type]
	if info.allocated_descriptors + num > info.num_descriptors {
		err = .Out_Of_Memory
		return
	}

	index = info.allocated_descriptors
	info.allocated_descriptors += num
	return
}

get_cpu_pointer_from_descriptor_pool :: proc(
	pool: ^D3D12_Descriptor_Pool,
	type: D3D12_Descriptor_Type,
	index: u32,
) -> (
	out_handle: d3d12.CPU_DESCRIPTOR_HANDLE,
) {
	info := &pool.heap_info[type]
	out_handle.ptr = info.base_cpu_descriptor.ptr + uint(index * info.descriptor_size)
	return
}

get_gpu_pointer_from_descriptor_pool :: proc(
	pool: ^D3D12_Descriptor_Pool,
	type: D3D12_Descriptor_Type,
	index: u32,
) -> (
	out_handle: d3d12.GPU_DESCRIPTOR_HANDLE,
) {
	info := &pool.heap_info[type]
	out_handle.ptr = info.base_gpu_descriptor.ptr + u64(index * info.descriptor_size)
	return
}

allocate_descriptor_set :: proc(
	instance: ^Instance,
	pool: ^Descriptor_Pool,
	#by_ptr desc: Descriptor_Set_Desc,
) -> (
	out_set: ^Descriptor_Set,
	error: Error,
) {
	p: ^D3D12_Descriptor_Pool = (^D3D12_Descriptor_Pool)(pool)
	if len(p.descriptor_sets) == int(p.used_descriptor_sets) {
		log.debugf(
			"Descriptor set pool is full, %d, %d",
			p.used_descriptor_sets,
			len(p.descriptor_sets),
		)
		error = .Out_Of_Memory
		return
	}
	set := D3D12_Descriptor_Set{}
	set.pool = p

	assert(len(desc.ranges) <= MAX_RANGES_PER_DESCRIPTOR_SET)
	for range_desc in desc.ranges {
		type := EN_TO_D3D12_DESCRIPTOR_TYPE[range_desc.descriptor_type]
		index, err := allocate_descriptors_from_descriptor_pool(p, type, range_desc.descriptor_num)
		if err != nil {
			log.debugf(
				"Failed to allocate descriptors from pool {} {}",
				range_desc.descriptor_type,
				err,
			)
			error = .Out_Of_Memory
			return
		}
		small_array.append(
			&set.ranges,
			D3D12_Descriptor_Range{range = range_desc, heap_type = type, heap_offset = index},
		)
	}

	index := p.used_descriptor_sets
	p.used_descriptor_sets += 1
	p.descriptor_sets[index] = set
	out_set = (^Descriptor_Set)(&p.descriptor_sets[index])

	return
}

reset_descriptor_pool :: proc(instance: ^Instance, pool: ^Descriptor_Pool) {
	p: ^D3D12_Descriptor_Pool = (^D3D12_Descriptor_Pool)(pool)
	for &info in p.heap_info {
		info.allocated_descriptors = 0
	}
	p.used_descriptor_sets = 0
}

D3D12_Descriptor_Range :: struct {
	range:       Descriptor_Range_Desc,
	heap_type:   D3D12_Descriptor_Type,
	heap_offset: u32,
}

D3D12_Descriptor_Set :: struct {
	pool:   ^D3D12_Descriptor_Pool,
	ranges: small_array.Small_Array(MAX_RANGES_PER_DESCRIPTOR_SET, D3D12_Descriptor_Range),
}

get_descriptor_set_cpu_pointer :: proc(
	set: ^D3D12_Descriptor_Set,
	index, offset: u32,
) -> d3d12.CPU_DESCRIPTOR_HANDLE {
	range := small_array.get(set.ranges, int(index))
	heap_offset := offset + range.heap_offset
	return get_cpu_pointer_from_descriptor_pool(set.pool, range.heap_type, heap_offset)
}

get_descriptor_set_gpu_pointer :: proc(
	set: ^D3D12_Descriptor_Set,
	index, offset: u32,
) -> d3d12.GPU_DESCRIPTOR_HANDLE {
	range := small_array.get(set.ranges, int(index))
	heap_offset := offset + range.heap_offset
	return get_gpu_pointer_from_descriptor_pool(set.pool, range.heap_type, heap_offset)
}

update_descriptor_ranges :: proc(
	instance: ^Instance,
	set: ^Descriptor_Set,
	base_range: u32,
	ranges: []Descriptor_Range_Update_Desc,
) {
	ds: ^D3D12_Descriptor_Set = (^D3D12_Descriptor_Set)(set)
	p: ^D3D12_Descriptor_Pool = ds.pool
	d3d12_ranges := small_array.slice(&ds.ranges)
	for range, i in ranges {
		d3d12_range := d3d12_ranges[int(base_range) + i]
		offset := range.base_descriptor + d3d12_range.heap_offset

		for descriptor_index in 0 ..< len(range.descriptors) {
			dst := get_cpu_pointer_from_descriptor_pool(
				p,
				d3d12_range.heap_type,
				offset + u32(descriptor_index),
			)
			descriptor := (^D3D12_Descriptor)(range.descriptors[descriptor_index])
			assert(descriptor != nil, "passed descriptor is nil")
			src := descriptor.cpu_descriptor
			p.device.device->CopyDescriptorsSimple(
				1,
				dst,
				src,
				d3d12.DESCRIPTOR_HEAP_TYPE(d3d12_range.heap_type),
			)
		}
	}
}

D3D12_Fence :: struct {
	using _: Fence,
	fence:   ^d3d12.IFence,
	event:   win32.HANDLE,
}

create_fence :: proc(
	instance: ^Instance,
	device: ^Device,
	initial_value: u64,
) -> (
	out_fence: ^Fence,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	fence, error_alloc := new(D3D12_Fence)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}

	hr := d->device->CreateFence(initial_value, {}, d3d12.IFence_UUID, (^rawptr)(&fence.fence))
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_fence = (^Fence)(fence)
	return
}

destroy_fence :: proc(instance: ^Instance, fence: ^Fence) {
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)
	f.fence->Release()
	free(f)
}

set_fence_debug_name :: proc(
	instance: ^Instance,
	fence: ^Fence,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)
	return set_debug_name(f.fence, name)
}

get_fence_value :: proc(instance: ^Instance, fence: ^Fence) -> (value: u64) {
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)
	return f.fence->GetCompletedValue()
}

signal_fence :: proc(
	instance: ^Instance,
	queue: ^Command_Queue,
	fence: ^Fence,
	value: u64,
) -> Error {
	q: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(queue)
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)
	hr := q.queue->Signal(f.fence, value)
	if !win32.SUCCEEDED(hr) {
		return .Unknown
	}
	return .Success
}

wait_fence :: proc(
	instance: ^Instance,
	queue: ^Command_Queue,
	fence: ^Fence,
	value: u64,
) -> Error {
	q: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(queue)
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)
	hr := q.queue->Wait(f.fence, value)
	if !win32.SUCCEEDED(hr) {
		return .Unknown
	}
	return .Success
}

wait_fence_now :: proc(instance: ^Instance, fence: ^Fence, value: u64) -> Error {
	f: ^D3D12_Fence = (^D3D12_Fence)(fence)

	if f.event == nil || f.event == win32.INVALID_HANDLE_VALUE {
		for f.fence->GetCompletedValue() < value {}
	} else if f.fence->GetCompletedValue() < value {
		hr := f.fence->SetEventOnCompletion(value, f.event)
		if !win32.SUCCEEDED(hr) {
			return .Unknown
		}

		if win32.WaitForSingleObject(f.event, win32.INFINITE) != win32.WAIT_OBJECT_0 {
			return .Unknown
		}
	}

	return .Success
}

D3D12_Pipeline :: struct {
	using _:    Pipeline,
	layout:     ^D3D12_Pipeline_Layout,
	pipeline:   ^d3d12.IPipelineState,
	// array of streams and their strides
	ia_strides: [MAX_VERTEX_STREAMS]u32,
	topology:   d3d12.PRIMITIVE_TOPOLOGY,
}

EN_TOPOLOGY_TO_D3D12 := [Topology]d3d12.PRIMITIVE_TOPOLOGY {
	.Point_List                    = .POINTLIST,
	.Line_List                     = .LINELIST,
	.Line_Strip                    = .LINESTRIP,
	.Triangle_List                 = .TRIANGLELIST,
	.Triangle_Strip                = .TRIANGLESTRIP,
	.Line_List_With_Adjacency      = .LINELIST_ADJ,
	.Line_Strip_With_Adjacency     = .LINESTRIP_ADJ,
	.Triangle_List_With_Adjacency  = .TRIANGLELIST_ADJ,
	.Triangle_Strip_With_Adjacency = .TRIANGLESTRIP_ADJ,
	// note this cannot be used by itself unless the num of control points is specified
	.Patch_List                    = ._1_CONTROL_POINT_PATCHLIST,
}

EN_TOPOLOGY_TO_D3D12_TYPE := [Topology]d3d12.PRIMITIVE_TOPOLOGY_TYPE {
	.Point_List                    = .POINT,
	.Line_List                     = .LINE,
	.Line_Strip                    = .LINE,
	.Triangle_List                 = .TRIANGLE,
	.Triangle_Strip                = .TRIANGLE,
	.Line_List_With_Adjacency      = .LINE,
	.Line_Strip_With_Adjacency     = .LINE,
	.Triangle_List_With_Adjacency  = .TRIANGLE,
	.Triangle_Strip_With_Adjacency = .TRIANGLE,
	.Patch_List                    = .PATCH,
}

EN_FILL_MODE_TO_D3D12 := [Fill_Mode]d3d12.FILL_MODE {
	.Solid     = .SOLID,
	.Wireframe = .WIREFRAME,
}

EN_CULL_MODE_TO_D3D12 := [Cull_Mode]d3d12.CULL_MODE {
	.None  = .NONE,
	.Front = .FRONT,
	.Back  = .BACK,
}

EN_COMPARE_FUNC_TO_D3D12 := [Compare_Func]d3d12.COMPARISON_FUNC {
	.None          = d3d12.COMPARISON_FUNC(0),
	.Never         = .NEVER,
	.Less          = .LESS,
	.Equal         = .EQUAL,
	.Less_Equal    = .LESS_EQUAL,
	.Greater       = .GREATER,
	.Not_Equal     = .NOT_EQUAL,
	.Greater_Equal = .GREATER_EQUAL,
	.Always        = .ALWAYS,
}

EN_STENCIL_OP_TO_D3D12 := [Stencil_Func]d3d12.STENCIL_OP {
	.Keep            = .KEEP,
	.Zero            = .ZERO,
	.Replace         = .REPLACE,
	.Increment_Clamp = .INCR_SAT,
	.Decrement_Clamp = .DECR_SAT,
	.Invert          = .INVERT,
	.Increment_Wrap  = .INCR,
	.Decrement_Wrap  = .DECR,
}

EN_LOGIC_OP_TO_D3D12 := [Logic_Func]d3d12.LOGIC_OP {
	.None          = .NOOP,
	.Clear         = .CLEAR,
	.And           = .AND,
	.And_Reverse   = .AND_REVERSE,
	.Copy          = .COPY,
	.And_Inverted  = .AND_INVERTED,
	.Xor           = .XOR,
	.Or            = .OR,
	.Nor           = .NOR,
	.Equivalent    = .EQUIV,
	.Invert        = .INVERT,
	.Or_Reverse    = .OR_REVERSE,
	.Copy_Inverted = .COPY_INVERTED,
	.Or_Inverted   = .OR_INVERTED,
	.Nand          = .NAND,
	.Set           = .SET,
}

EN_BLEND_FACTOR_TO_D3D12 := [Blend_Factor]d3d12.BLEND {
	.Zero                     = .ZERO,
	.One                      = .ONE,
	.Src_Color                = .SRC_COLOR,
	.One_Minus_Src_Color      = .INV_SRC_COLOR,
	.Dst_Color                = .DEST_COLOR,
	.One_Minus_Dst_Color      = .INV_DEST_COLOR,
	.Src_Alpha                = .SRC_ALPHA,
	.One_Minus_Src_Alpha      = .INV_SRC_ALPHA,
	.Dst_Alpha                = .DEST_ALPHA,
	.One_Minus_Dst_Alpha      = .INV_DEST_ALPHA,
	.Constant_Color           = .BLEND_FACTOR,
	.One_Minus_Constant_Color = .INV_BLEND_FACTOR,
	.Constant_Alpha           = .BLEND_FACTOR,
	.One_Minus_Constant_Alpha = .INV_BLEND_FACTOR,
	.Src_Alpha_Saturate       = .SRC_ALPHA_SAT,
	.Src1_Color               = .SRC1_COLOR,
	.One_Minus_Src1_Color     = .INV_SRC1_COLOR,
	.Src1_Alpha               = .SRC1_ALPHA,
	.One_Minus_Src1_Alpha     = .INV_SRC1_ALPHA,
}

EN_BLEND_OP_TO_D3D12 := [Blend_Func]d3d12.BLEND_OP {
	.Add              = .ADD,
	.Subtract         = .SUBTRACT,
	.Reverse_Subtract = .REV_SUBTRACT,
	.Min              = .MIN,
	.Max              = .MAX,
}

create_graphics_pipeline :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Graphics_Pipeline_Desc,
) -> (
	out_pipeline: ^Pipeline,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	layout: ^D3D12_Pipeline_Layout = (^D3D12_Pipeline_Layout)(desc.pipeline_layout)
	pipeline, error_alloc := new(D3D12_Pipeline)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	pipeline.layout = layout

	pso_desc: d3d12.GRAPHICS_PIPELINE_STATE_DESC
	pso_desc.pRootSignature = layout.root_signature

	// shaders
	for shader in desc.shaders {
		assert(card(shader.stage) == 1, "Only one shader per stage is supported")
		if shader.stage == {.Vertex_Shader} {
			pso_desc.VS.pShaderBytecode = raw_data(shader.bytecode[.DXIL])
			pso_desc.VS.BytecodeLength = len(shader.bytecode[.DXIL])
		} else if shader.stage == {.Tess_Control_Shader} {
			pso_desc.HS.pShaderBytecode = raw_data(shader.bytecode[.DXIL])
			pso_desc.HS.BytecodeLength = len(shader.bytecode[.DXIL])
		} else if shader.stage == {.Tess_Evaluation_Shader} {
			pso_desc.DS.pShaderBytecode = raw_data(shader.bytecode[.DXIL])
			pso_desc.DS.BytecodeLength = len(shader.bytecode[.DXIL])
		} else if shader.stage == {.Geometry_Shader} {
			pso_desc.GS.pShaderBytecode = raw_data(shader.bytecode[.DXIL])
			pso_desc.GS.BytecodeLength = len(shader.bytecode[.DXIL])
		} else if shader.stage == {.Fragment_Shader} {
			pso_desc.PS.pShaderBytecode = raw_data(shader.bytecode[.DXIL])
			pso_desc.PS.BytecodeLength = len(shader.bytecode[.DXIL])
		} else {
			error = .Unknown
			return
		}
	}

	// vertex input
	attribute_num := len(desc.vertex_input.attributes)
	elements: small_array.Small_Array(MAX_VERTEX_ATTRIBUTES, d3d12.INPUT_ELEMENT_DESC)
	pso_desc.InputLayout.pInputElementDescs = raw_data(small_array.slice(&elements))
	pso_desc.InputLayout.NumElements = u32(attribute_num)
	for attr in desc.vertex_input.attributes {
		element: d3d12.INPUT_ELEMENT_DESC
		stream := desc.vertex_input.streams[attr.stream_index]
		is_per_vertex := stream.step_rate == .Per_Vertex
		semantic_name := strings.clone_to_cstring(
			attr.d3d_semantic,
			allocator = context.temp_allocator,
		)
		log.infof("semantic: {}", attr.d3d_semantic)
		element.SemanticName = semantic_name
		element.SemanticIndex = 0
		element.Format = EN_TO_DXGI_FORMAT_TYPED[attr.format]
		element.InputSlot = u32(stream.binding_slot)
		element.AlignedByteOffset = u32(attr.offset)
		element.InputSlotClass = .PER_VERTEX_DATA if is_per_vertex else .PER_INSTANCE_DATA
		element.InstanceDataStepRate = 0 if is_per_vertex else 1
		small_array.append(&elements, element)
	}

	for stream in desc.vertex_input.streams {
		assert(
			stream.binding_slot < MAX_VERTEX_STREAMS,
			"Vertex stream binding slot is out of range",
		)
		pipeline.ia_strides[stream.binding_slot] = u32(stream.stride)
	}

	// IA
	if desc.input_assembly.topology == .Patch_List {
		pipeline.topology = d3d12.PRIMITIVE_TOPOLOGY(
			u8(d3d12.PRIMITIVE_TOPOLOGY.TRIANGLESTRIP_ADJ) +
			desc.input_assembly.tess_control_point_num -
			1,
		)
	} else do pipeline.topology = EN_TOPOLOGY_TO_D3D12[desc.input_assembly.topology]
	pso_desc.PrimitiveTopologyType = EN_TOPOLOGY_TO_D3D12_TYPE[desc.input_assembly.topology]
	pso_desc.IBStripCutValue = d3d12.INDEX_BUFFER_STRIP_CUT_VALUE(
		desc.input_assembly.primitive_restart,
	)

	// MS
	if (!desc.multisample.enabled) {
		pso_desc.SampleDesc.Count = 1
		pso_desc.SampleMask = 0xFFFFFFFF
	} else {
		pso_desc.SampleDesc.Count = u32(desc.multisample.sample_num)
		pso_desc.SampleDesc.Quality = 0
		pso_desc.SampleMask =
			desc.multisample.sample_mask if desc.multisample.sample_mask != 0 else 0xFFFFFFFF
	}

	// RS
	pso_desc.RasterizerState.FillMode = EN_FILL_MODE_TO_D3D12[desc.rasterization.fill_mode]
	pso_desc.RasterizerState.CullMode = EN_CULL_MODE_TO_D3D12[desc.rasterization.cull_mode]
	pso_desc.RasterizerState.FrontCounterClockwise = d3d12.BOOL(
		desc.rasterization.front_counter_clockwise,
	)
	pso_desc.RasterizerState.DepthBias = i32(desc.rasterization.depth_bias.constant)
	pso_desc.RasterizerState.DepthBiasClamp = desc.rasterization.depth_bias.clamp
	pso_desc.RasterizerState.SlopeScaledDepthBias = desc.rasterization.depth_bias.slope
	pso_desc.RasterizerState.DepthClipEnable = d3d12.BOOL(desc.rasterization.depth_clamp)
	pso_desc.RasterizerState.AntialiasedLineEnable = d3d12.BOOL(desc.rasterization.line_smoothing)
	pso_desc.RasterizerState.ConservativeRaster =
		.ON if desc.rasterization.conservative_raster else .OFF

	if (desc.multisample.enabled) {
		pso_desc.RasterizerState.MultisampleEnable = desc.multisample.sample_num > 1
		pso_desc.RasterizerState.ForcedSampleCount =
			u32(desc.multisample.sample_num) if desc.multisample.sample_num > 1 else 0
	}

	// DS
	pso_desc.DepthStencilState.DepthEnable = desc.output_merger.depth.compare_func != .None
	pso_desc.DepthStencilState.DepthWriteMask = .ALL if desc.output_merger.depth.write else .ZERO
	pso_desc.DepthStencilState.DepthFunc =
		EN_COMPARE_FUNC_TO_D3D12[desc.output_merger.depth.compare_func]
	pso_desc.DepthStencilState.StencilEnable =
	!(desc.output_merger.stencil.front.compare_func == .None &&
		desc.output_merger.stencil.back.compare_func == .None)
	pso_desc.DepthStencilState.StencilReadMask = desc.output_merger.stencil.front.compare_mask
	pso_desc.DepthStencilState.StencilWriteMask = desc.output_merger.stencil.front.write_mask
	pso_desc.DepthStencilState.FrontFace.StencilFailOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.front.fail]
	pso_desc.DepthStencilState.FrontFace.StencilDepthFailOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.front.depth_fail]
	pso_desc.DepthStencilState.FrontFace.StencilPassOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.front.pass]
	pso_desc.DepthStencilState.FrontFace.StencilFunc =
		EN_COMPARE_FUNC_TO_D3D12[desc.output_merger.stencil.front.compare_func]
	pso_desc.DepthStencilState.BackFace.StencilFailOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.back.fail]
	pso_desc.DepthStencilState.BackFace.StencilDepthFailOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.back.depth_fail]
	pso_desc.DepthStencilState.BackFace.StencilPassOp =
		EN_STENCIL_OP_TO_D3D12[desc.output_merger.stencil.back.pass]
	pso_desc.DepthStencilState.BackFace.StencilFunc =
		EN_COMPARE_FUNC_TO_D3D12[desc.output_merger.stencil.back.compare_func]
	pso_desc.DSVFormat = EN_TO_DXGI_FORMAT_TYPED[desc.output_merger.depth_stencil_format]

	// blend
	pso_desc.BlendState.AlphaToCoverageEnable = d3d12.BOOL(
		desc.multisample.enabled && desc.multisample.alpha_to_coverage,
	)
	pso_desc.BlendState.IndependentBlendEnable = true

	for color, i in desc.output_merger.colors {
		rt := &pso_desc.BlendState.RenderTarget[i]
		rt.BlendEnable = d3d12.BOOL(color.blend_enabled)
		rt.RenderTargetWriteMask = transmute(u8)(color.color_write_mask)

		if color.blend_enabled {
			rt.LogicOp = EN_LOGIC_OP_TO_D3D12[desc.output_merger.logic_func]
			rt.LogicOpEnable = desc.output_merger.logic_func != .None
			rt.SrcBlend = EN_BLEND_FACTOR_TO_D3D12[color.color_blend.src_factor]
			rt.DestBlend = EN_BLEND_FACTOR_TO_D3D12[color.color_blend.dst_factor]
			rt.BlendOp = EN_BLEND_OP_TO_D3D12[color.color_blend.func]
			rt.SrcBlendAlpha = EN_BLEND_FACTOR_TO_D3D12[color.alpha_blend.src_factor]
			rt.DestBlendAlpha = EN_BLEND_FACTOR_TO_D3D12[color.alpha_blend.dst_factor]
			rt.BlendOpAlpha = EN_BLEND_OP_TO_D3D12[color.alpha_blend.func]
		}
	}

	// rts
	pso_desc.NumRenderTargets = u32(len(desc.output_merger.colors))
	zipped := soa_zip(
		color = desc.output_merger.colors,
		format = pso_desc.RTVFormats[:pso_desc.NumRenderTargets],
	)
	for &s in zipped {
		s.format = EN_TO_DXGI_FORMAT_TYPED[s.color.format]
	}

	hr := d.device->CreateGraphicsPipelineState(
		&pso_desc,
		d3d12.IPipelineState_UUID,
		(^rawptr)(&pipeline.pipeline),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_pipeline = (^Pipeline)(pipeline)
	return
}

destroy_pipeline :: proc(instance: ^Instance, pipeline: ^Pipeline) {
	p: ^D3D12_Pipeline = (^D3D12_Pipeline)(pipeline)
	p.pipeline->Release()
	free(p)
}

set_pipeline_debug_name :: proc(
	instance: ^Instance,
	pipeline: ^Pipeline,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	p: ^D3D12_Pipeline = (^D3D12_Pipeline)(pipeline)
	return set_debug_name(p.pipeline, name)
}

D3D12_Pipeline_Layout :: struct {
	using _:                Pipeline_Layout,
	root_signature:         ^d3d12.IRootSignature,
	indirect_indexed_sig:   ^d3d12.ICommandSignature,
	indirect_sig:           ^d3d12.ICommandSignature,
	ranges:                 small_array.Small_Array(
		ROOT_SIGNATURE_DWORD_NUM,
		d3d12.DESCRIPTOR_RANGE1,
	),
	root_params:            small_array.Small_Array(
		ROOT_SIGNATURE_DWORD_NUM,
		d3d12.ROOT_PARAMETER1,
	),
	// indexes into the above array
	sets:                   small_array.Small_Array(ROOT_SIGNATURE_DWORD_NUM, int),
	// also indexes into the above above array
	base_root_constant:     int,
	enable_draw_parameters: bool,
	is_graphics:            bool,
}

EN_TO_D3D12_DESCRIPTOR_RANGE_TYPE := [Descriptor_Type]d3d12.DESCRIPTOR_RANGE_TYPE {
	.Sampler                   = .SAMPLER,
	.Constant_Buffer           = .CBV,
	.Texture                   = .SRV,
	.Storage_Texture           = .UAV,
	.Buffer                    = .SRV,
	.Storage_Buffer            = .UAV,
	.Structured_Buffer         = .SRV,
	.Storage_Structured_Buffer = .UAV,
	.Acceleration_Structure    = .SRV,
}

shader_stages_to_visibility :: proc(stages: Stage_Flags) -> d3d12.SHADER_VISIBILITY {
	if card(stages & {.Vertex_Shader, .Fragment_Shader}) > 0 ||
	   .Compute_Shader in stages ||
	   card(stages & Ray_Tracing_Stages) > 0 {
		return .ALL
	}
	if .Vertex_Shader in stages {
		return .VERTEX
	}
	if .Tess_Control_Shader in stages {
		return .HULL
	}
	if .Tess_Evaluation_Shader in stages {
		return .DOMAIN
	}
	if .Geometry_Shader in stages {
		return .GEOMETRY
	}
	if .Fragment_Shader in stages {
		return .PIXEL
	}
	return .ALL
}

create_command_signature :: proc(
	device: ^D3D12_Device,
	type: d3d12.INDIRECT_ARGUMENT_TYPE,
	root_sig: ^d3d12.IRootSignature,
	stride: u32,
	enable_draw_parameters: bool,
) -> ^d3d12.ICommandSignature {
	is_draw_arg := enable_draw_parameters && (type == .DRAW || type == .DRAW_INDEXED)
	arg_descs: [2]d3d12.INDIRECT_ARGUMENT_DESC
	if is_draw_arg {
		arg_descs[0].Type = .CONSTANT
		arg_descs[0].Constant.RootParameterIndex = 0
		arg_descs[0].Constant.DestOffsetIn32BitValues = 0
		arg_descs[0].Constant.Num32BitValuesToSet = 2

		arg_descs[1].Type = type
	} else {
		arg_descs[0].Type = type
	}

	sig_desc: d3d12.COMMAND_SIGNATURE_DESC
	sig_desc.ByteStride = stride
	sig_desc.NumArgumentDescs = 2 if is_draw_arg else 1
	sig_desc.pArgumentDescs = raw_data(arg_descs[:])

	sig: ^d3d12.ICommandSignature
	hr := device.device->CreateCommandSignature(
		&sig_desc,
		root_sig,
		d3d12.ICommandSignature_UUID,
		(^rawptr)(&sig),
	)
	if !win32.SUCCEEDED(hr) {
		log.errorf("Failed to create command signature (%X)", hr)
		return nil
	}

	return sig
}

create_pipeline_layout :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Pipeline_Layout_Desc,
) -> (
	out_pipeline_layout: ^Pipeline_Layout,
	error: Error,
) {
	d: ^D3D12_Device = (^D3D12_Device)(device)
	layout, error_alloc := new(D3D12_Pipeline_Layout)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	layout.is_graphics = card(desc.shader_stages & {.Vertex_Shader, .Fragment_Shader}) > 0

	if desc.enable_d3d12_draw_parameters_emulation {
		local_root_param: d3d12.ROOT_PARAMETER1
		local_root_param.ParameterType = ._32BIT_CONSTANTS
		local_root_param.ShaderVisibility = .VERTEX
		local_root_param.Constants.ShaderRegister = 0
		local_root_param.Constants.RegisterSpace = 999
		local_root_param.Constants.Num32BitValues = 2
		small_array.append(&layout.root_params, local_root_param)
	}

	for set_desc, set_index in desc.descriptor_sets {
		small_array.set(&layout.sets, set_index, small_array.len(layout.root_params))
		for range_desc in set_desc.ranges {
			local_root_param: d3d12.ROOT_PARAMETER1
			local_root_param.ParameterType = .DESCRIPTOR_TABLE
			local_root_param.ShaderVisibility = .ALL
			local_root_param.DescriptorTable.NumDescriptorRanges = 1

			range_start := small_array.len(layout.ranges)
			d3d_range: d3d12.DESCRIPTOR_RANGE1
			d3d_range.RangeType = EN_TO_D3D12_DESCRIPTOR_RANGE_TYPE[range_desc.descriptor_type]
			d3d_range.NumDescriptors = range_desc.descriptor_num
			d3d_range.BaseShaderRegister = range_desc.base_register_index
			d3d_range.RegisterSpace = set_desc.register_space
			d3d_range.OffsetInDescriptorsFromTableStart = d3d12.DESCRIPTOR_RANGE_OFFSET_APPEND

			if .Partially_Bound in range_desc.flags {
				d3d_range.Flags += {.DESCRIPTORS_VOLATILE}
				if range_desc.descriptor_type != .Sampler {
					d3d_range.Flags += {.DATA_VOLATILE}
				}
			}

			small_array.append(&layout.ranges, d3d_range)
			local_root_param.DescriptorTable.pDescriptorRanges = raw_data(
				small_array.slice(&layout.ranges)[range_start:][:1],
			)

			small_array.append(&layout.root_params, local_root_param)
		}
	}

	layout.base_root_constant = small_array.len(layout.root_params)
	for root_constant_desc in desc.constants {
		local_root_param: d3d12.ROOT_PARAMETER1
		local_root_param.ParameterType = ._32BIT_CONSTANTS
		local_root_param.ShaderVisibility = shader_stages_to_visibility(
			root_constant_desc.shader_stages,
		)
		local_root_param.Constants.ShaderRegister = root_constant_desc.register_index
		local_root_param.Constants.RegisterSpace = desc.constants_register_space
		local_root_param.Constants.Num32BitValues = root_constant_desc.size / 4
		small_array.append(&layout.root_params, local_root_param)
	}

	root_sig_desc: d3d12.VERSIONED_ROOT_SIGNATURE_DESC
	root_sig_desc.Version = ._1_1
	root_sig_desc.Desc_1_1.NumParameters = u32(small_array.len(layout.root_params))
	root_sig_desc.Desc_1_1.pParameters = raw_data(small_array.slice(&layout.root_params))

	if .Vertex_Shader in desc.shader_stages {
		root_sig_desc.Desc_1_1.Flags += {.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT}
	} else {
		root_sig_desc.Desc_1_1.Flags += {.DENY_VERTEX_SHADER_ROOT_ACCESS}
	}
	if .Tess_Control_Shader not_in desc.shader_stages {
		root_sig_desc.Desc_1_1.Flags += {.DENY_HULL_SHADER_ROOT_ACCESS}
	}
	if .Tess_Evaluation_Shader not_in desc.shader_stages {
		root_sig_desc.Desc_1_1.Flags += {.DENY_DOMAIN_SHADER_ROOT_ACCESS}
	}
	if .Geometry_Shader not_in desc.shader_stages {
		root_sig_desc.Desc_1_1.Flags += {.DENY_GEOMETRY_SHADER_ROOT_ACCESS}
	}
	if .Fragment_Shader not_in desc.shader_stages {
		root_sig_desc.Desc_1_1.Flags += {.DENY_PIXEL_SHADER_ROOT_ACCESS}
	}

	root_sig_blob: ^d3d12.IBlob
	error_blob: ^d3d12.IBlob
	hr := d3d12.SerializeVersionedRootSignature(&root_sig_desc, &root_sig_blob, &error_blob)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		log.errorf(
			"Failed to serialize root signature (%X): %s",
			hr,
			(cstring)(error_blob->GetBufferPointer()),
		)
		return
	}

	hr =
	d->device->CreateRootSignature(
		0,
		root_sig_blob->GetBufferPointer(),
		root_sig_blob->GetBufferSize(),
		d3d12.IRootSignature_UUID,
		(^rawptr)(&layout.root_signature),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		log.errorf("Failed to create root signature (%X)", hr)
		return
	}

	if desc.enable_d3d12_draw_parameters_emulation {
		draw_stride :=
			size_of(Draw_Emulated_Desc) if desc.enable_d3d12_draw_parameters_emulation else size_of(Draw_Desc)
		draw_indexed_stride :=
			size_of(Draw_Indexed_Emulated_Desc) if desc.enable_d3d12_draw_parameters_emulation else size_of(Draw_Indexed_Desc)

		layout.indirect_sig = create_command_signature(
			d,
			.DRAW,
			layout.root_signature,
			u32(draw_stride),
			desc.enable_d3d12_draw_parameters_emulation,
		)
		layout.indirect_indexed_sig = create_command_signature(
			d,
			.DRAW_INDEXED,
			layout.root_signature,
			u32(draw_indexed_stride),
			desc.enable_d3d12_draw_parameters_emulation,
		)
	}
	layout.enable_draw_parameters = desc.enable_d3d12_draw_parameters_emulation

	out_pipeline_layout = (^Pipeline_Layout)(layout)
	return
}

destroy_pipeline_layout :: proc(instance: ^Instance, layout: ^Pipeline_Layout) {
	l: ^D3D12_Pipeline_Layout = (^D3D12_Pipeline_Layout)(layout)
	l.root_signature->Release()
	if l.indirect_sig != nil {
		l.indirect_sig.id3d12pageable->Release()
	}
	if l.indirect_indexed_sig != nil {
		l.indirect_indexed_sig.id3d12pageable->Release()
	}
	free(l)
}

set_pipeline_layout_debug_name :: proc(
	instance: ^Instance,
	layout: ^Pipeline_Layout,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	l: ^D3D12_Pipeline_Layout = (^D3D12_Pipeline_Layout)(layout)
	return set_debug_name(l.root_signature, name)
}

D3D12_Swapchain :: struct {
	using _:       Swapchain,
	swap_chain:    ^dxgi.ISwapChain3,
	desc:          Swapchain_Desc,
	textures:      small_array.Small_Array(MAX_SWAPCHAIN_TEXTURES, ^Texture),
	create_flags:  dxgi.SWAP_CHAIN,
	sync_interval: u32,
	present_flags: dxgi.PRESENT,
}

SWAPCHAIN_FORMAT := [Swapchain_Format]dxgi.FORMAT {
	.BT709_G22_8BIT     = .R8G8B8A8_UNORM,
	.BT709_G10_16BIT    = .R16G16B16A16_UNORM,
	.BT709_G22_10BIT    = .R10G10B10A2_UNORM,
	.BT2020_G2084_10BIT = .R10G10B10A2_UNORM,
}

create_swapchain :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Swapchain_Desc,
) -> (
	out_swapchain: ^Swapchain,
	error: Error,
) {
	i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	// d: ^D3D12_Device = (^D3D12_Device)(device)
	queue: ^D3D12_Command_Queue = (^D3D12_Command_Queue)(desc.command_queue)

	if queue == nil {
		error = .Invalid_Parameter
		return
	}

	swapchain, error_alloc := new(D3D12_Swapchain)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	swapchain.desc = desc

	tearing_support: win32.BOOL = false
	hr := i.factory->CheckFeatureSupport(
		.PRESENT_ALLOW_TEARING,
		&tearing_support,
		u32(size_of(tearing_support)),
	)
	if !win32.SUCCEEDED(hr) {
		tearing_support = false
	}

	swap_chain_desc: dxgi.SWAP_CHAIN_DESC1
	swap_chain_desc.Width = u32(desc.size.x)
	swap_chain_desc.Height = u32(desc.size.y)
	swap_chain_desc.Format = SWAPCHAIN_FORMAT[desc.format]
	swap_chain_desc.Stereo = false
	swap_chain_desc.SampleDesc.Count = 1
	swap_chain_desc.BufferUsage = {.RENDER_TARGET_OUTPUT}
	swap_chain_desc.BufferCount = u32(desc.texture_num)
	swap_chain_desc.Scaling = .NONE
	swap_chain_desc.SwapEffect = .FLIP_DISCARD
	swap_chain_desc.AlphaMode = .IGNORE

	if tearing_support {
		swap_chain_desc.Flags += {.ALLOW_TEARING}
	}
	swapchain.sync_interval = 0 if desc.immediate else 1
	if desc.immediate && tearing_support {
		swapchain.present_flags += {.ALLOW_TEARING}
	}

	swapchain.create_flags = swap_chain_desc.Flags

	hwnd := win32.HWND(desc.window.windows.hwnd)
	if hwnd == nil {
		error = .Invalid_Parameter
		return
	}

	hr =
	i.factory->CreateSwapChainForHwnd(
		queue.queue,
		hwnd,
		&swap_chain_desc,
		nil,
		nil,
		(^^dxgi.ISwapChain1)(&swapchain.swap_chain),
	)
	if !win32.SUCCEEDED(hr) {
		log.errorf("Failed to create swapchain for hwnd %s", hr)
		error = .Unknown
		return
	}

	assert(desc.texture_num <= MAX_SWAPCHAIN_TEXTURES)
	acquire_swapchain_textures(i, swapchain)

	out_swapchain = (^Swapchain)(swapchain)
	return
}

acquire_swapchain_textures :: proc(
	instance: ^D3D12_Instance,
	swapchain: ^D3D12_Swapchain,
) -> (
	error: Error,
) {

	small_array.resize(&swapchain.textures, int(swapchain.desc.texture_num))
	for &texture, index in small_array.slice(&swapchain.textures) {
		resource: ^d3d12.IResource
		hr := swapchain.swap_chain->GetBuffer(
			u32(index),
			d3d12.IResource_UUID,
			(^rawptr)(&resource),
		)
		if !win32.SUCCEEDED(hr) {
			error = .Unknown
			log.errorf("Failed to get swapchain buffer %d", hr)
			return
		}
		texture = texture_from_resource(resource)
	}

	return
}

release_swapchain_textures :: proc(instance: ^D3D12_Instance, swapchain: ^D3D12_Swapchain) {
	s: ^D3D12_Swapchain = swapchain
	for texture in small_array.slice(&s.textures) {
		instance->destroy_texture(texture)
	}
}

destroy_swapchain :: proc(instance: ^Instance, swapchain: ^Swapchain) {
	i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	release_swapchain_textures(i, s)

	s.swap_chain->Release()
	free(s)
}

set_swapchain_debug_name :: proc(
	instance: ^Instance,
	swapchain: ^Swapchain,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	return set_debug_name((^d3d12.IObject)(s.swap_chain), name)
}

get_swapchain_textures :: proc(
	instance: ^Instance,
	swapchain: ^Swapchain,
	out_textures: []^Texture,
) {
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	for &texture, i in small_array.slice(&s.textures) {
		if i >= len(out_textures) do break
		out_textures[i] = texture
	}
}

acquire_next_texture :: proc(instance: ^Instance, swapchain: ^Swapchain) -> u32 {
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	return s.swap_chain->GetCurrentBackBufferIndex()
}

present :: proc(instance: ^Instance, swapchain: ^Swapchain) -> (error: Error) {
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	hr := s.swap_chain->Present(s.sync_interval, s.present_flags)
	if !win32.SUCCEEDED(hr) {
		log.errorf("Failed to present swapchain %d", hr)
		error = .Unknown
	}
	return
}

resize_swapchain :: proc(
	instance: ^Instance,
	swapchain: ^Swapchain,
	width: dim,
	height: dim,
) -> Error {
	i: ^D3D12_Instance = (^D3D12_Instance)(instance)
	s: ^D3D12_Swapchain = (^D3D12_Swapchain)(swapchain)
	release_swapchain_textures(i, s)
	hr := s.swap_chain->ResizeBuffers(
		0,
		u32(width),
		u32(height),
		SWAPCHAIN_FORMAT[s.desc.format],
		s.create_flags,
	)
	if !win32.SUCCEEDED(hr) {
		log.errorf("Failed to resize swapchain %d", hr)
		return .Unknown
	}
	acquire_swapchain_textures(i, s)
	return .Success
}

D3D12_Texture :: struct {
	using _:    Texture,
	allocation: ^d3d12ma.Allocation,
	resource:   ^d3d12.IResource,
	desc:       Texture_Desc,
}

DXGI_TO_EN_FORMAT := #sparse[dxgi.FORMAT]Format {
	.UNKNOWN                                 = .UNKNOWN, // DXGI_FORMAT_UNKNOWN = 0
	.R32G32B32A32_TYPELESS                   = .UNKNOWN, // DXGI_FORMAT_R32G32B32A32_TYPELESS = 1
	.R32G32B32A32_FLOAT                      = .RGBA32_SFLOAT, // DXGI_FORMAT_R32G32B32A32_FLOAT = 2
	.R32G32B32A32_UINT                       = .RGBA32_UINT, // DXGI_FORMAT_R32G32B32A32_UINT = 3
	.R32G32B32A32_SINT                       = .RGBA32_SINT, // DXGI_FORMAT_R32G32B32A32_SINT = 4
	.R32G32B32_TYPELESS                      = .UNKNOWN, // DXGI_FORMAT_R32G32B32_TYPELESS = 5
	.R32G32B32_FLOAT                         = .RGB32_SFLOAT, // DXGI_FORMAT_R32G32B32_FLOAT = 6
	.R32G32B32_UINT                          = .RGB32_UINT, // DXGI_FORMAT_R32G32B32_UINT = 7
	.R32G32B32_SINT                          = .RGB32_SINT, // DXGI_FORMAT_R32G32B32_SINT = 8
	.R16G16B16A16_TYPELESS                   = .UNKNOWN, // DXGI_FORMAT_R16G16B16A16_TYPELESS = 9
	.R16G16B16A16_FLOAT                      = .RGBA16_SFLOAT, // DXGI_FORMAT_R16G16B16A16_FLOAT = 10
	.R16G16B16A16_UNORM                      = .RGBA16_UNORM, // DXGI_FORMAT_R16G16B16A16_UNORM = 11
	.R16G16B16A16_UINT                       = .RGBA16_UINT, // DXGI_FORMAT_R16G16B16A16_UINT = 12
	.R16G16B16A16_SNORM                      = .RGBA16_SNORM, // DXGI_FORMAT_R16G16B16A16_SNORM = 13
	.R16G16B16A16_SINT                       = .RGBA16_SINT, // DXGI_FORMAT_R16G16B16A16_SINT = 14
	.R32G32_TYPELESS                         = .UNKNOWN, // DXGI_FORMAT_R32G32_TYPELESS = 15
	.R32G32_FLOAT                            = .RG32_SFLOAT, // DXGI_FORMAT_R32G32_FLOAT = 16
	.R32G32_UINT                             = .RG32_UINT, // DXGI_FORMAT_R32G32_UINT = 17
	.R32G32_SINT                             = .RG32_SINT, // DXGI_FORMAT_R32G32_SINT = 18
	.R32G8X24_TYPELESS                       = .UNKNOWN, // DXGI_FORMAT_R32G8X24_TYPELESS = 19
	.D32_FLOAT_S8X24_UINT                    = .D32_SFLOAT_S8_UINT_X24, // DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20
	.R32_FLOAT_X8X24_TYPELESS                = .R32_SFLOAT_X8_X24, // DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS = 21
	.X32_TYPELESS_G8X24_UINT                 = .X32_G8_UINT_X24, // DXGI_FORMAT_X32_TYPELESS_G8X24_UINT = 22
	.R10G10B10A2_TYPELESS                    = .UNKNOWN, // DXGI_FORMAT_R10G10B10A2_TYPELESS = 23
	.R10G10B10A2_UNORM                       = .R10_G10_B10_A2_UNORM, // DXGI_FORMAT_R10G10B10A2_UNORM = 24
	.R10G10B10A2_UINT                        = .R10_G10_B10_A2_UINT, // DXGI_FORMAT_R10G10B10A2_UINT = 25
	.R11G11B10_FLOAT                         = .R11_G11_B10_UFLOAT, // DXGI_FORMAT_R11G11B10_FLOAT = 26
	.R8G8B8A8_TYPELESS                       = .UNKNOWN, // DXGI_FORMAT_R8G8B8A8_TYPELESS = 27
	.R8G8B8A8_UNORM                          = .RGBA8_UNORM, // DXGI_FORMAT_R8G8B8A8_UNORM = 28
	.R8G8B8A8_UNORM_SRGB                     = .RGBA8_SRGB, // DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29
	.R8G8B8A8_UINT                           = .RGBA8_UINT, // DXGI_FORMAT_R8G8B8A8_UINT = 30
	.R8G8B8A8_SNORM                          = .RGBA8_SNORM, // DXGI_FORMAT_R8G8B8A8_SNORM = 31
	.R8G8B8A8_SINT                           = .RGBA8_SINT, // DXGI_FORMAT_R8G8B8A8_SINT = 32
	.R16G16_TYPELESS                         = .UNKNOWN, // DXGI_FORMAT_R16G16_TYPELESS = 33
	.R16G16_FLOAT                            = .RG16_SFLOAT, // DXGI_FORMAT_R16G16_FLOAT = 34
	.R16G16_UNORM                            = .RG16_UNORM, // DXGI_FORMAT_R16G16_UNORM = 35
	.R16G16_UINT                             = .RG16_UINT, // DXGI_FORMAT_R16G16_UINT = 36
	.R16G16_SNORM                            = .RG16_SNORM, // DXGI_FORMAT_R16G16_SNORM = 37
	.R16G16_SINT                             = .RG16_SINT, // DXGI_FORMAT_R16G16_SINT = 38
	.R32_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_R32_TYPELESS = 39
	.D32_FLOAT                               = .D32_SFLOAT, // DXGI_FORMAT_D32_FLOAT = 40
	.R32_FLOAT                               = .R32_SFLOAT, // DXGI_FORMAT_R32_FLOAT = 41
	.R32_UINT                                = .R32_UINT, // DXGI_FORMAT_R32_UINT = 42
	.R32_SINT                                = .R32_SINT, // DXGI_FORMAT_R32_SINT = 43
	.R24G8_TYPELESS                          = .UNKNOWN, // DXGI_FORMAT_R24G8_TYPELESS = 44
	.D24_UNORM_S8_UINT                       = .D24_UNORM_S8_UINT, // DXGI_FORMAT_D24_UNORM_S8_UINT = 45
	.R24_UNORM_X8_TYPELESS                   = .R24_UNORM_X8, // DXGI_FORMAT_R24_UNORM_X8_TYPELESS = 46
	.X24_TYPELESS_G8_UINT                    = .X24_G8_UINT, // DXGI_FORMAT_X24_TYPELESS_G8_UINT = 47
	.R8G8_TYPELESS                           = .UNKNOWN, // DXGI_FORMAT_R8G8_TYPELESS = 48
	.R8G8_UNORM                              = .RG8_UNORM, // DXGI_FORMAT_R8G8_UNORM = 49
	.R8G8_UINT                               = .RG8_UINT, // DXGI_FORMAT_R8G8_UINT = 50
	.R8G8_SNORM                              = .RG8_SNORM, // DXGI_FORMAT_R8G8_SNORM = 51
	.R8G8_SINT                               = .RG8_SINT, // DXGI_FORMAT_R8G8_SINT = 52
	.R16_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_R16_TYPELESS = 53
	.R16_FLOAT                               = .R16_SFLOAT, // DXGI_FORMAT_R16_FLOAT = 54
	.D16_UNORM                               = .D16_UNORM, // DXGI_FORMAT_D16_UNORM = 55
	.R16_UNORM                               = .R16_UNORM, // DXGI_FORMAT_R16_UNORM = 56
	.R16_UINT                                = .R16_UINT, // DXGI_FORMAT_R16_UINT = 57
	.R16_SNORM                               = .R16_SNORM, // DXGI_FORMAT_R16_SNORM = 58
	.R16_SINT                                = .R16_SINT, // DXGI_FORMAT_R16_SINT = 59
	.R8_TYPELESS                             = .UNKNOWN, // DXGI_FORMAT_R8_TYPELESS = 60
	.R8_UNORM                                = .R8_UNORM, // DXGI_FORMAT_R8_UNORM = 61
	.R8_UINT                                 = .R8_UINT, // DXGI_FORMAT_R8_UINT = 62
	.R8_SNORM                                = .R8_SNORM, // DXGI_FORMAT_R8_SNORM = 63
	.R8_SINT                                 = .R8_SINT, // DXGI_FORMAT_R8_SINT = 64
	.A8_UNORM                                = .UNKNOWN, // DXGI_FORMAT_A8_UNORM = 65
	.R1_UNORM                                = .UNKNOWN, // DXGI_FORMAT_R1_UNORM = 66
	.R9G9B9E5_SHAREDEXP                      = .R9_G9_B9_E5_UFLOAT, // DXGI_FORMAT_R9G9B9E5_SHAREDEXP = 67
	.R8G8_B8G8_UNORM                         = .UNKNOWN, // DXGI_FORMAT_R8G8_B8G8_UNORM = 68
	.G8R8_G8B8_UNORM                         = .UNKNOWN, // DXGI_FORMAT_G8R8_G8B8_UNORM = 69
	.BC1_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC1_TYPELESS = 70
	.BC1_UNORM                               = .BC1_RGBA_UNORM, // DXGI_FORMAT_BC1_UNORM = 71
	.BC1_UNORM_SRGB                          = .BC1_RGBA_SRGB, // DXGI_FORMAT_BC1_UNORM_SRGB = 72
	.BC2_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC2_TYPELESS = 73
	.BC2_UNORM                               = .BC2_RGBA_UNORM, // DXGI_FORMAT_BC2_UNORM = 74
	.BC2_UNORM_SRGB                          = .BC2_RGBA_SRGB, // DXGI_FORMAT_BC2_UNORM_SRGB = 75
	.BC3_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC3_TYPELESS = 76
	.BC3_UNORM                               = .BC3_RGBA_UNORM, // DXGI_FORMAT_BC3_UNORM = 77
	.BC3_UNORM_SRGB                          = .BC3_RGBA_SRGB, // DXGI_FORMAT_BC3_UNORM_SRGB = 78
	.BC4_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC4_TYPELESS = 79
	.BC4_UNORM                               = .BC4_R_UNORM, // DXGI_FORMAT_BC4_UNORM = 80
	.BC4_SNORM                               = .BC4_R_SNORM, // DXGI_FORMAT_BC4_SNORM = 81
	.BC5_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC5_TYPELESS = 82
	.BC5_UNORM                               = .BC5_RG_UNORM, // DXGI_FORMAT_BC5_UNORM = 83
	.BC5_SNORM                               = .BC5_RG_SNORM, // DXGI_FORMAT_BC5_SNORM = 84
	.B5G6R5_UNORM                            = .B5_G6_R5_UNORM, // DXGI_FORMAT_B5G6R5_UNORM = 85
	.B5G5R5A1_UNORM                          = .B5_G5_R5_A1_UNORM, // DXGI_FORMAT_B5G5R5A1_UNORM = 86
	.B8G8R8A8_UNORM                          = .BGRA8_UNORM, // DXGI_FORMAT_B8G8R8A8_UNORM = 87
	.B8G8R8X8_UNORM                          = .UNKNOWN, // DXGI_FORMAT_B8G8R8X8_UNORM = 88
	.R10G10B10_XR_BIAS_A2_UNORM              = .UNKNOWN, // DXGI_FORMAT_R10G10B10_XR_BIAS_A2_UNORM = 89
	.B8G8R8A8_TYPELESS                       = .UNKNOWN, // DXGI_FORMAT_B8G8R8A8_TYPELESS = 90
	.B8G8R8A8_UNORM_SRGB                     = .BGRA8_SRGB, // DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91
	.B8G8R8X8_TYPELESS                       = .UNKNOWN, // DXGI_FORMAT_B8G8R8X8_TYPELESS = 92
	.B8G8R8X8_UNORM_SRGB                     = .UNKNOWN, // DXGI_FORMAT_B8G8R8X8_UNORM_SRGB = 93
	.BC6H_TYPELESS                           = .UNKNOWN, // DXGI_FORMAT_BC6H_TYPELESS = 94
	.BC6H_UF16                               = .BC6H_RGB_UFLOAT, // DXGI_FORMAT_BC6H_UF16 = 95
	.BC6H_SF16                               = .BC6H_RGB_SFLOAT, // DXGI_FORMAT_BC6H_SF16 = 96
	.BC7_TYPELESS                            = .UNKNOWN, // DXGI_FORMAT_BC7_TYPELESS = 97
	.BC7_UNORM                               = .BC7_RGBA_UNORM, // DXGI_FORMAT_BC7_UNORM = 98
	.BC7_UNORM_SRGB                          = .BC7_RGBA_SRGB, // DXGI_FORMAT_BC7_UNORM_SRGB = 99
	.AYUV                                    = .UNKNOWN, // DXGI_FORMAT_AYUV = 100
	.Y410                                    = .UNKNOWN, // DXGI_FORMAT_Y410 = 101
	.Y416                                    = .UNKNOWN, // DXGI_FORMAT_Y416 = 102
	.NV12                                    = .UNKNOWN, // DXGI_FORMAT_NV12 = 103
	.P010                                    = .UNKNOWN, // DXGI_FORMAT_P010 = 104
	.P016                                    = .UNKNOWN, // DXGI_FORMAT_P016 = 105
	._420_OPAQUE                             = .UNKNOWN, // DXGI_FORMAT_420_OPAQUE = 106
	.YUY2                                    = .UNKNOWN, // DXGI_FORMAT_YUY2 = 107
	.Y210                                    = .UNKNOWN, // DXGI_FORMAT_Y210 = 108
	.Y216                                    = .UNKNOWN, // DXGI_FORMAT_Y216 = 109
	.NV11                                    = .UNKNOWN, // DXGI_FORMAT_NV11 = 110
	.AI44                                    = .UNKNOWN, // DXGI_FORMAT_AI44 = 111
	.IA44                                    = .UNKNOWN, // DXGI_FORMAT_IA44 = 112
	.P8                                      = .UNKNOWN, // DXGI_FORMAT_P8 = 113
	.A8P8                                    = .UNKNOWN, // DXGI_FORMAT_A8P8 = 114
	.B4G4R4A4_UNORM                          = .B4_G4_R4_A4_UNORM, // DXGI_FORMAT_B4G4R4A4_UNORM = 115
	.P208                                    = .UNKNOWN, // DXGI_FORMAT_P208 = 116
	.V208                                    = .UNKNOWN, // DXGI_FORMAT_V208 = 117
	.V408                                    = .UNKNOWN, // DXGI_FORMAT_V408 = 118
	.SAMPLER_FEEDBACK_MIN_MIP_OPAQUE         = .UNKNOWN, // DXGI_FORMAT_SAMPLER_FEEDBACK_MIN_MIP_OPAQUE = 119
	.SAMPLER_FEEDBACK_MIP_REGION_USED_OPAQUE = .UNKNOWN, // DXGI_FORMAT_SAMPLER_FEEDBACK_MIP_REGION_USED_OPAQUE = 120
	.FORCE_UINT                              = .UNKNOWN, // DXGI_FORMAT_FORCE_UINT = 0xffffffff
}

EN_TO_DXGI_FORMAT_TYPED := [Format]dxgi.FORMAT {
	.UNKNOWN                = .UNKNOWN, // DXGI_FORMAT_UNKNOWN = 0
	.RGBA32_SFLOAT          = .R32G32B32A32_FLOAT, // DXGI_FORMAT_R32G32B32A32_FLOAT = 2
	.RGBA32_UINT            = .R32G32B32A32_UINT, // DXGI_FORMAT_R32G32B32A32_UINT = 3
	.RGBA32_SINT            = .R32G32B32A32_SINT, // DXGI_FORMAT_R32G32B32A32_SINT = 4
	.RGB32_SFLOAT           = .R32G32B32_FLOAT, // DXGI_FORMAT_R32G32B32_FLOAT = 6
	.RGB32_UINT             = .R32G32B32_UINT, // DXGI_FORMAT_R32G32B32_UINT = 7
	.RGB32_SINT             = .R32G32B32_SINT, // DXGI_FORMAT_R32G32B32_SINT = 8
	.RGBA16_SFLOAT          = .R16G16B16A16_FLOAT, // DXGI_FORMAT_R16G16B16A16_FLOAT = 10
	.RGBA16_UNORM           = .R16G16B16A16_UNORM, // DXGI_FORMAT_R16G16B16A16_UNORM = 11
	.RGBA16_UINT            = .R16G16B16A16_UINT, // DXGI_FORMAT_R16G16B16A16_UINT = 12
	.RGBA16_SNORM           = .R16G16B16A16_SNORM, // DXGI_FORMAT_R16G16B16A16_SNORM = 13
	.RGBA16_SINT            = .R16G16B16A16_SINT, // DXGI_FORMAT_R16G16B16A16_SINT = 14
	.RG32_SFLOAT            = .R32G32_FLOAT, // DXGI_FORMAT_R32G32_FLOAT = 16
	.RG32_UINT              = .R32G32_UINT, // DXGI_FORMAT_R32G32_UINT = 17
	.RG32_SINT              = .R32G32_SINT, // DXGI_FORMAT_R32G32_SINT = 18
	.D32_SFLOAT_S8_UINT_X24 = .D32_FLOAT_S8X24_UINT, // DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20
	.R32_SFLOAT_X8_X24      = .R32_FLOAT_X8X24_TYPELESS, // DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS = 21
	.X32_G8_UINT_X24        = .X32_TYPELESS_G8X24_UINT, // DXGI_FORMAT_X32_TYPELESS_G8X24_UINT = 22
	.R10_G10_B10_A2_UNORM   = .R10G10B10A2_UNORM, // DXGI_FORMAT_R10G10B10A2_UNORM = 24
	.R10_G10_B10_A2_UINT    = .R10G10B10A2_UINT, // DXGI_FORMAT_R10G10B10A2_UINT = 25
	.R11_G11_B10_UFLOAT     = .R11G11B10_FLOAT, // DXGI_FORMAT_R11G11B10_FLOAT = 26
	.RGBA8_UNORM            = .R8G8B8A8_UNORM, // DXGI_FORMAT_R8G8B8A8_UNORM = 28
	.RGBA8_SRGB             = .R8G8B8A8_UNORM_SRGB, // DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29
	.RGBA8_UINT             = .R8G8B8A8_UINT, // DXGI_FORMAT_R8G8B8A8_UINT = 30
	.RGBA8_SNORM            = .R8G8B8A8_SNORM, // DXGI_FORMAT_R8G8B8A8_SNORM = 31
	.RGBA8_SINT             = .R8G8B8A8_SINT, // DXGI_FORMAT_R8G8B8A8_SINT = 32
	.RG16_SFLOAT            = .R16G16_FLOAT, // DXGI_FORMAT_R16G16_FLOAT = 34
	.RG16_UNORM             = .R16G16_UNORM, // DXGI_FORMAT_R16G16_UNORM = 35
	.RG16_UINT              = .R16G16_UINT, // DXGI_FORMAT_R16G16_UINT = 36
	.RG16_SNORM             = .R16G16_SNORM, // DXGI_FORMAT_R16G16_SNORM = 37
	.RG16_SINT              = .R16G16_SINT, // DXGI_FORMAT_R16G16_SINT = 38
	.D32_SFLOAT             = .D32_FLOAT, // DXGI_FORMAT_D32_FLOAT = 40
	.R32_SFLOAT             = .R32_FLOAT, // DXGI_FORMAT_R32_FLOAT = 41
	.R32_UINT               = .R32_UINT, // DXGI_FORMAT_R32_UINT = 42
	.R32_SINT               = .R32_SINT, // DXGI_FORMAT_R32_SINT = 43
	.D24_UNORM_S8_UINT      = .D24_UNORM_S8_UINT, // DXGI_FORMAT_D24_UNORM_S8_UINT = 45
	.R24_UNORM_X8           = .R24_UNORM_X8_TYPELESS, // DXGI_FORMAT_R24_UNORM_X8_TYPELESS = 46
	.X24_G8_UINT            = .X24_TYPELESS_G8_UINT, // DXGI_FORMAT_X24_TYPELESS_G8_UINT = 47
	.RG8_UNORM              = .R8G8_UNORM, // DXGI_FORMAT_R8G8_UNORM = 49
	.RG8_UINT               = .R8G8_UINT, // DXGI_FORMAT_R8G8_UINT = 50
	.RG8_SNORM              = .R8G8_SNORM, // DXGI_FORMAT_R8G8_SNORM = 51
	.RG8_SINT               = .R8G8_SINT, // DXGI_FORMAT_R8G8_SINT = 52
	.R16_SFLOAT             = .R16_FLOAT, // DXGI_FORMAT_R16_FLOAT = 54
	.D16_UNORM              = .D16_UNORM, // DXGI_FORMAT_D16_UNORM = 55
	.R16_UNORM              = .R16_UNORM, // DXGI_FORMAT_R16_UNORM = 56
	.R16_UINT               = .R16_UINT, // DXGI_FORMAT_R16_UINT = 57
	.R16_SNORM              = .R16_SNORM, // DXGI_FORMAT_R16_SNORM = 58
	.R16_SINT               = .R16_SINT, // DXGI_FORMAT_R16_SINT = 59
	.R8_UNORM               = .R8_UNORM, // DXGI_FORMAT_R8_UNORM = 61
	.R8_UINT                = .R8_UINT, // DXGI_FORMAT_R8_UINT = 62
	.R8_SNORM               = .R8_SNORM, // DXGI_FORMAT_R8_SNORM = 63
	.R8_SINT                = .R8_SINT, // DXGI_FORMAT_R8_SINT = 64
	.R9_G9_B9_E5_UFLOAT     = .R9G9B9E5_SHAREDEXP, // DXGI_FORMAT_R9G9B9E5_SHAREDEXP = 67
	.BC1_RGBA_UNORM         = .BC1_UNORM, // DXGI_FORMAT_BC1_UNORM = 71
	.BC1_RGBA_SRGB          = .BC1_UNORM_SRGB, // DXGI_FORMAT_BC1_UNORM_SRGB = 72
	.BC2_RGBA_UNORM         = .BC2_UNORM, // DXGI_FORMAT_BC2_UNORM = 74
	.BC2_RGBA_SRGB          = .BC2_UNORM_SRGB, // DXGI_FORMAT_BC2_UNORM_SRGB = 75
	.BC3_RGBA_UNORM         = .BC3_UNORM, // DXGI_FORMAT_BC3_UNORM = 77
	.BC3_RGBA_SRGB          = .BC3_UNORM_SRGB, // DXGI_FORMAT_BC3_UNORM_SRGB = 78
	.BC4_R_UNORM            = .BC4_UNORM, // DXGI_FORMAT_BC4_UNORM = 80
	.BC4_R_SNORM            = .BC4_SNORM, // DXGI_FORMAT_BC4_SNORM = 81
	.BC5_RG_UNORM           = .BC5_UNORM, // DXGI_FORMAT_BC5_UNORM = 83
	.BC5_RG_SNORM           = .BC5_SNORM, // DXGI_FORMAT_BC5_SNORM = 84
	.B5_G6_R5_UNORM         = .B5G6R5_UNORM, // DXGI_FORMAT_B5G6R5_UNORM = 85
	.B5_G5_R5_A1_UNORM      = .B5G5R5A1_UNORM, // DXGI_FORMAT_B5G5R5A1_UNORM = 86
	.BGRA8_UNORM            = .B8G8R8A8_UNORM, // DXGI_FORMAT_B8G8R8A8_UNORM = 87
	.BGRA8_SRGB             = .B8G8R8A8_UNORM_SRGB, // DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91
	.BC6H_RGB_UFLOAT        = .BC6H_UF16, // DXGI_FORMAT_BC6H_UF16 = 95
	.BC6H_RGB_SFLOAT        = .BC6H_SF16, // DXGI_FORMAT_BC6H_SF16 = 96
	.BC7_RGBA_UNORM         = .BC7_UNORM, // DXGI_FORMAT_BC7_UNORM = 98
	.BC7_RGBA_SRGB          = .BC7_UNORM_SRGB, // DXGI_FORMAT_BC7_UNORM_SRGB = 99
	.B4_G4_R4_A4_UNORM      = .B4G4R4A4_UNORM, // DXGI_FORMAT_B4G4R4A4_UNORM = 115
}

EN_TO_DXGI_FORMAT_TYPELESS := [Format]dxgi.FORMAT {
	.UNKNOWN                = .UNKNOWN, // DXGI_FORMAT_UNKNOWN = 0
	.RGBA32_SFLOAT          = .R32G32B32A32_TYPELESS, // DXGI_FORMAT_R32G32B32A32_FLOAT = 2
	.RGBA32_UINT            = .R32G32B32A32_TYPELESS, // DXGI_FORMAT_R32G32B32A32_UINT = 3
	.RGBA32_SINT            = .R32G32B32A32_TYPELESS, // DXGI_FORMAT_R32G32B32A32_SINT = 4
	.RGB32_SFLOAT           = .R32G32B32_TYPELESS, // DXGI_FORMAT_R32G32B32_FLOAT = 6
	.RGB32_UINT             = .R32G32B32_TYPELESS, // DXGI_FORMAT_R32G32B32_UINT = 7
	.RGB32_SINT             = .R32G32B32_TYPELESS, // DXGI_FORMAT_R32G32B32_SINT = 8
	.RGBA16_SFLOAT          = .R16G16B16A16_TYPELESS, // DXGI_FORMAT_R16G16B16A16_FLOAT = 10
	.RGBA16_UNORM           = .R16G16B16A16_TYPELESS, // DXGI_FORMAT_R16G16B16A16_UNORM = 11
	.RGBA16_UINT            = .R16G16B16A16_TYPELESS, // DXGI_FORMAT_R16G16B16A16_UINT = 12
	.RGBA16_SNORM           = .R16G16B16A16_TYPELESS, // DXGI_FORMAT_R16G16B16A16_SNORM = 13
	.RGBA16_SINT            = .R16G16B16A16_TYPELESS, // DXGI_FORMAT_R16G16B16A16_SINT = 14
	.RG32_SFLOAT            = .R32G32_TYPELESS, // DXGI_FORMAT_R32G32_FLOAT = 16
	.RG32_UINT              = .R32G32_TYPELESS, // DXGI_FORMAT_R32G32_UINT = 17
	.RG32_SINT              = .R32G32_TYPELESS, // DXGI_FORMAT_R32G32_SINT = 18
	.D32_SFLOAT_S8_UINT_X24 = .R32G8X24_TYPELESS, // DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20
	.R32_SFLOAT_X8_X24      = .R32_FLOAT_X8X24_TYPELESS, // DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS = 21
	.X32_G8_UINT_X24        = .R32G8X24_TYPELESS, // DXGI_FORMAT_X32_TYPELESS_G8X24_UINT = 22
	.R10_G10_B10_A2_UNORM   = .R10G10B10A2_TYPELESS, // DXGI_FORMAT_R10G10B10A2_UNORM = 24
	.R10_G10_B10_A2_UINT    = .R10G10B10A2_TYPELESS, // DXGI_FORMAT_R10G10B10A2_UINT = 25
	.R11_G11_B10_UFLOAT     = .R11G11B10_FLOAT, // DXGI_FORMAT_R11G11B10_FLOAT = 26
	.RGBA8_UNORM            = .R8G8B8A8_TYPELESS, // DXGI_FORMAT_R8G8B8A8_UNORM = 28
	.RGBA8_SRGB             = .R8G8B8A8_UNORM_SRGB, // DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29
	.RGBA8_UINT             = .R8G8B8A8_TYPELESS, // DXGI_FORMAT_R8G8B8A8_UINT = 30
	.RGBA8_SNORM            = .R8G8B8A8_TYPELESS, // DXGI_FORMAT_R8G8B8A8_SNORM = 31
	.RGBA8_SINT             = .R8G8B8A8_TYPELESS, // DXGI_FORMAT_R8G8B8A8_SINT = 32
	.RG16_SFLOAT            = .R16G16_TYPELESS, // DXGI_FORMAT_R16G16_FLOAT = 34
	.RG16_UNORM             = .R16G16_TYPELESS, // DXGI_FORMAT_R16G16_UNORM = 35
	.RG16_UINT              = .R16G16_TYPELESS, // DXGI_FORMAT_R16G16_UINT = 36
	.RG16_SNORM             = .R16G16_TYPELESS, // DXGI_FORMAT_R16G16_SNORM = 37
	.RG16_SINT              = .R16G16_TYPELESS, // DXGI_FORMAT_R16G16_SINT = 38
	.D32_SFLOAT             = .R32_TYPELESS, // DXGI_FORMAT_D32_FLOAT = 40
	.R32_SFLOAT             = .R32_TYPELESS, // DXGI_FORMAT_R32_FLOAT = 41
	.R32_UINT               = .R32_TYPELESS, // DXGI_FORMAT_R32_UINT = 42
	.R32_SINT               = .R32_TYPELESS, // DXGI_FORMAT_R32_SINT = 43
	.D24_UNORM_S8_UINT      = .R24G8_TYPELESS, // DXGI_FORMAT_D24_UNORM_S8_UINT = 45
	.R24_UNORM_X8           = .R24_UNORM_X8_TYPELESS, // DXGI_FORMAT_R24_UNORM_X8_TYPELESS = 46
	.X24_G8_UINT            = .R24G8_TYPELESS, // DXGI_FORMAT_X24_TYPELESS_G8_UINT = 47
	.RG8_UNORM              = .R8G8_TYPELESS, // DXGI_FORMAT_R8G8_UNORM = 49
	.RG8_UINT               = .R8G8_TYPELESS, // DXGI_FORMAT_R8G8_UINT = 50
	.RG8_SNORM              = .R8G8_TYPELESS, // DXGI_FORMAT_R8G8_SNORM = 51
	.RG8_SINT               = .R8G8_TYPELESS, // DXGI_FORMAT_R8G8_SINT = 52
	.R16_SFLOAT             = .R16_TYPELESS, // DXGI_FORMAT_R16_FLOAT = 54
	.D16_UNORM              = .R16_TYPELESS, // DXGI_FORMAT_D16_UNORM = 55
	.R16_UNORM              = .R16_TYPELESS, // DXGI_FORMAT_R16_UNORM = 56
	.R16_UINT               = .R16_TYPELESS, // DXGI_FORMAT_R16_UINT = 57
	.R16_SNORM              = .R16_TYPELESS, // DXGI_FORMAT_R16_SNORM = 58
	.R16_SINT               = .R16_TYPELESS, // DXGI_FORMAT_R16_SINT = 59
	.R8_UNORM               = .R8_TYPELESS, // DXGI_FORMAT_R8_UNORM = 61
	.R8_UINT                = .R8_TYPELESS, // DXGI_FORMAT_R8_UINT = 62
	.R8_SNORM               = .R8_TYPELESS, // DXGI_FORMAT_R8_SNORM = 63
	.R8_SINT                = .R8_TYPELESS, // DXGI_FORMAT_R8_SINT = 64
	.R9_G9_B9_E5_UFLOAT     = .R9G9B9E5_SHAREDEXP, // DXGI_FORMAT_R9G9B9E5_SHAREDEXP = 67
	.BC1_RGBA_UNORM         = .BC1_TYPELESS, // DXGI_FORMAT_BC1_UNORM = 71
	.BC1_RGBA_SRGB          = .BC1_UNORM_SRGB, // DXGI_FORMAT_BC1_UNORM_SRGB = 72
	.BC2_RGBA_UNORM         = .BC2_TYPELESS, // DXGI_FORMAT_BC2_UNORM = 74
	.BC2_RGBA_SRGB          = .BC2_UNORM_SRGB, // DXGI_FORMAT_BC2_UNORM_SRGB = 75
	.BC3_RGBA_UNORM         = .BC3_TYPELESS, // DXGI_FORMAT_BC3_UNORM = 77
	.BC3_RGBA_SRGB          = .BC3_UNORM_SRGB, // DXGI_FORMAT_BC3_UNORM_SRGB = 78
	.BC4_R_UNORM            = .BC4_TYPELESS, // DXGI_FORMAT_BC4_UNORM = 80
	.BC4_R_SNORM            = .BC4_TYPELESS, // DXGI_FORMAT_BC4_SNORM = 81
	.BC5_RG_UNORM           = .BC5_TYPELESS, // DXGI_FORMAT_BC5_UNORM = 83
	.BC5_RG_SNORM           = .BC5_TYPELESS, // DXGI_FORMAT_BC5_SNORM = 84
	.B5_G6_R5_UNORM         = .B5G6R5_UNORM, // DXGI_FORMAT_B5G6R5_UNORM = 85
	.B5_G5_R5_A1_UNORM      = .B5G5R5A1_UNORM, // DXGI_FORMAT_B5G5R5A1_UNORM = 86
	.BGRA8_UNORM            = .B8G8R8A8_TYPELESS, // DXGI_FORMAT_B8G8R8A8_UNORM = 87
	.BGRA8_SRGB             = .B8G8R8A8_TYPELESS, // DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91
	.BC6H_RGB_UFLOAT        = .BC6H_UF16, // DXGI_FORMAT_BC6H_UF16 = 95
	.BC6H_RGB_SFLOAT        = .BC6H_SF16, // DXGI_FORMAT_BC6H_SF16 = 96
	.BC7_RGBA_UNORM         = .BC7_TYPELESS, // DXGI_FORMAT_BC7_UNORM = 98
	.BC7_RGBA_SRGB          = .BC7_TYPELESS, // DXGI_FORMAT_BC7_UNORM_SRGB = 99
	.B4_G4_R4_A4_UNORM      = .B4G4R4A4_UNORM, // DXGI_FORMAT_B4G4R4A4_UNORM = 115
}

TEXTURE_TYPE_TO_RESOURCE_DIMENSION := #sparse[Texture_Type]d3d12.RESOURCE_DIMENSION {
	._1D = .TEXTURE1D,
	._2D = .TEXTURE2D,
	._3D = .TEXTURE3D,
}

MEMORY_LOCATION_TO_HEAP_TYPE := #sparse[Memory_Location]d3d12.HEAP_TYPE {
	.Device        = .DEFAULT,
	.Device_Upload = .UPLOAD,
	.Host_Upload   = .UPLOAD,
	.Host_Readback = .READBACK,
}

create_texture :: proc(
	instance: ^Instance,
	device: ^Device,
	#by_ptr desc: Texture_Desc,
) -> (
	out_texture: ^Texture,
	error: Error,
) {
	desc := desc
	d: ^D3D12_Device = (^D3D12_Device)(device)
	texture, error_alloc := new(D3D12_Texture)
	if error_alloc != nil {
		error = .Out_Of_Memory
		return
	}
	fix_texture_desc(&desc)
	texture.desc = desc

	flags: d3d12.RESOURCE_FLAGS
	if .Shader_Resource_Storage in desc.usage {
		flags += {.ALLOW_UNORDERED_ACCESS}
	}
	if .Color_Attachment in desc.usage {
		flags += {.ALLOW_RENDER_TARGET}
	}
	if .Depth_Stencil_Attachment in desc.usage {
		flags += {.ALLOW_DEPTH_STENCIL}
		if .Shader_Resource not_in desc.usage {
			flags += {.DENY_SHADER_RESOURCE}
		}
	}

	format_info := FORMAT_PROPS[desc.format]
	block_width := format_info.block_width
	block_height := format_info.block_height

	resource_desc: d3d12.RESOURCE_DESC
	resource_desc.Dimension = TEXTURE_TYPE_TO_RESOURCE_DIMENSION[desc.type]
	resource_desc.Width = u64(
		uint(desc.width) if block_width == 0 else mem.align_forward_uint(uint(desc.width), uint(block_width)),
	)
	resource_desc.Height = u32(
		uint(desc.height) if block_height == 0 else mem.align_forward_uint(uint(desc.height), uint(block_height)),
	)
	resource_desc.DepthOrArraySize = desc.depth if desc.type == ._3D else desc.layer_num
	resource_desc.MipLevels = u16(desc.mip_num)
	resource_desc.Format = EN_TO_DXGI_FORMAT_TYPELESS[desc.format]
	resource_desc.SampleDesc.Count = u32(desc.sample_num)
	resource_desc.Layout = .UNKNOWN
	resource_desc.Flags = flags

	alloc_info: d3d12ma.ALLOCATION_DESC
	alloc_info.HeapType = MEMORY_LOCATION_TO_HEAP_TYPE[desc.location]
	alloc_info.Flags = {.STRATEGY_MIN_MEMORY}
	alloc_info.ExtraHeapFlags = {.CREATE_NOT_ZEROED}


	hr := d3d12ma.Allocator_CreateResource(
		d.allocator,
		alloc_info,
		resource_desc,
		{},
		{},
		&texture.allocation,
		d3d12.IResource_UUID,
		(^rawptr)(&texture.resource),
	)
	if !win32.SUCCEEDED(hr) {
		error = .Unknown
		return
	}

	out_texture = (^Texture)(texture)
	return
}

texture_desc_from_resource :: proc(resource: ^d3d12.IResource) -> (out: Texture_Desc) {
	if resource == nil {
		return
	}

	desc_store: d3d12.RESOURCE_DESC
	desc := resource->GetDesc(&desc_store)
	#partial switch desc.Dimension {
	case .TEXTURE1D:
		out.type = ._1D
	case .TEXTURE2D:
		out.type = ._2D
	case .TEXTURE3D:
		out.type = ._3D
	case:
		panic("Unknown texture dimension")
	}
	out.format = DXGI_TO_EN_FORMAT[desc_store.Format]
	out.width = dim(desc.Width)
	out.height = dim(desc.Height)
	out.depth = dim(desc.DepthOrArraySize) if out.type == ._3D else 1
	out.mip_num = mip(desc.MipLevels)
	out.layer_num = desc.DepthOrArraySize if out.type != ._3D else 1
	out.sample_num = sample(desc.SampleDesc.Count)

	if .ALLOW_RENDER_TARGET in desc.Flags {
		out.usage += {.Color_Attachment}
	}
	if .ALLOW_DEPTH_STENCIL in desc.Flags {
		out.usage += {.Depth_Stencil_Attachment}
	}
	if .ALLOW_UNORDERED_ACCESS not_in desc.Flags {
		out.usage += {.Shader_Resource}
	}
	if .ALLOW_UNORDERED_ACCESS in desc.Flags {
		out.usage += {.Shader_Resource_Storage}
	}

	return
}

texture_from_resource :: proc(resource: ^d3d12.IResource) -> ^Texture {
	t, error_alloc := new(D3D12_Texture)
	if error_alloc != nil {
		panic("Out of memory")
	}
	t.desc = texture_desc_from_resource(resource)
	t.resource = resource
	return t
}

destroy_texture :: proc(instance: ^Instance, texture: ^Texture) {
	t: ^D3D12_Texture = (^D3D12_Texture)(texture)
	if t.allocation != nil {
		d3d12ma.Allocation_Release(t.allocation)
	}
	if t.resource != nil {
		t.resource->Release()
	}
	free(t)
}

set_texture_debug_name :: proc(
	instance: ^Instance,
	texture: ^Texture,
	name: string,
) -> (
	error: mem.Allocator_Error,
) {
	t: ^D3D12_Texture = (^D3D12_Texture)(texture)
	return set_debug_name(t.resource, name)
}

get_texture_desc :: proc(instance: ^Instance, texture: ^Texture) -> Texture_Desc {
	t: ^D3D12_Texture = (^D3D12_Texture)(texture)
	return t.desc
}

get_texture_subresource_index :: proc(
	desc: Texture_Desc,
	layer_offset, mip_offset: u32,
	planes: Plane_Flags = Plane_All,
) -> u32 {
	plane_index: u32
	if planes != Plane_All {
		if .Depth in planes {
			plane_index = 0
		} else if .Stencil in planes {
			plane_index = 1
		} else {
			panic("Invalid plane flags")
		}
	}

	return mip_offset + (layer_offset + plane_index * u32(desc.layer_num)) * u32(desc.mip_num)
}
