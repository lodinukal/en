package en_gpu

import "base:builtin"
import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:mem"
import "core:reflect"

import "core:encoding/cbor"

Error :: enum {
	Success,
	Out_Of_Memory,
	Invalid_Parameter,
	Unknown,
}

MAX_RANGES_PER_DESCRIPTOR_SET :: 8
MAX_VERTEX_STREAMS :: 8
MAX_VERTEX_ATTRIBUTES :: 16

create_instance :: proc(
	api: Graphics_API,
	enable_graphics_api_validation: bool = true,
) -> (
	instance: ^Instance,
	error: Error,
) {
	switch api {
	case .D3D12:
		instance, error = create_d3d12_instance(enable_graphics_api_validation)
		error = validate_instance(instance)
		return
	case .Vulkan:
		log.errorf("Vulkan is not supported yet")
	}
	error = .Invalid_Parameter
	return
}

validate_instance :: proc(instance: ^Instance) -> Error {
	if instance == nil do return .Invalid_Parameter
	ti := runtime.type_info_base(type_info_of(Instance))
	fields := reflect.struct_fields_zipped(ti.id)
	for field in fields {
		as_proc, ok := field.type.variant.(runtime.Type_Info_Procedure)
		if ok {
			ptr := ((^u64)(uintptr(instance) + field.offset))^
			if ptr == 0 {
				log.errorf("Instance interface %s is nil", field.name)
				return .Invalid_Parameter
			}
		}
	}
	return .Success
}

Instance :: struct {
	api:                              Graphics_API,

	// instance
	destroy:                          proc(instance: ^Instance),

	// device
	create_device:                    proc(
		instance: ^Instance,
		#by_ptr desc: Device_Creation_Desc,
	) -> (
		device: ^Device,
		error: Error,
	),
	destroy_device:                   proc(instance: ^Instance, device: ^Device),
	get_device_desc:                  proc(instance: ^Instance, device: ^Device) -> Device_Desc,
	set_device_debug_name:            proc(
		instance: ^Instance,
		device: ^Device,
		name: string,
	) -> mem.Allocator_Error,
	get_command_queue:                proc(
		instance: ^Instance,
		device: ^Device,
		type: Command_Queue_Type,
	) -> (
		queue: ^Command_Queue,
		error: Error,
	),

	// buffer
	create_buffer:                    proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Buffer_Desc,
	) -> (
		buffer: ^Buffer,
		error: Error,
	),
	destroy_buffer:                   proc(instance: ^Instance, buffer: ^Buffer),
	set_buffer_debug_name:            proc(
		instance: ^Instance,
		buffer: ^Buffer,
		name: string,
	) -> mem.Allocator_Error,
	map_buffer:                       proc(
		instance: ^Instance,
		buffer: ^Buffer,
		offset: u64,
		size: u64,
	) -> (
		mapped_memory: []u8,
		error: Error,
	),
	unmap_buffer:                     proc(instance: ^Instance, buffer: ^Buffer),

	// command allocator
	create_command_allocator:         proc(
		instance: ^Instance,
		queue: ^Command_Queue,
	) -> (
		allocator: ^Command_Allocator,
		error: Error,
	),
	destroy_command_allocator:        proc(instance: ^Instance, allocator: ^Command_Allocator),
	set_command_allocator_debug_name: proc(
		instance: ^Instance,
		allocator: ^Command_Allocator,
		name: string,
	) -> mem.Allocator_Error,
	reset_command_allocator:          proc(instance: ^Instance, allocator: ^Command_Allocator),

	// command buffer
	create_command_buffer:            proc(
		instance: ^Instance,
		allocator: ^Command_Allocator,
	) -> (
		buffer: ^Command_Buffer,
		error: Error,
	),
	destroy_command_buffer:           proc(instance: ^Instance, buffer: ^Command_Buffer),
	set_command_buffer_debug_name:    proc(
		instance: ^Instance,
		buffer: ^Command_Buffer,
		name: string,
	) -> mem.Allocator_Error,
	begin_command_buffer:             proc(
		instance: ^Instance,
		buffer: ^Command_Buffer,
	) -> (
		error: Error
	),
	end_command_buffer:               proc(
		instance: ^Instance,
		buffer: ^Command_Buffer,
	) -> (
		error: Error
	),
	cmd_set_viewports:                proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		viewports: []Viewport,
	),
	cmd_set_scissors:                 proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		scissors: []Rect,
	),
	cmd_set_depth_bounds:             proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		min, max: f32,
	),
	cmd_set_stencil_reference:        proc(instance: ^Instance, cmd: ^Command_Buffer, ref: u8),
	cmd_set_sample_locations:         proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		locations: []Sample_Location,
		sample_num: sample,
	),
	cmd_set_blend_constants:          proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		constants: [4]f32,
	),
	cmd_clear_attachments:            proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		clears: []Clear_Desc,
		rects: []Rect,
	),
	cmd_clear_storage_buffer:         proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Clear_Storage_Buffer_Desc,
	),
	cmd_clear_storage_texture:        proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Clear_Storage_Texture_Desc,
	),
	cmd_begin_rendering:              proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Attachments_Desc,
	),
	cmd_end_rendering:                proc(instance: ^Instance, cmd: ^Command_Buffer),
	cmd_set_vertex_buffers:           proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		base_slot: u32,
		buffers: []^Buffer,
		offsets: []u64,
	),
	cmd_set_index_buffer:             proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		buffer: ^Buffer,
		offset: u64,
		format: Index_Type,
	),
	cmd_set_pipeline_layout:          proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		layout: ^Pipeline_Layout,
	),
	cmd_set_pipeline:                 proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		pipeline: ^Pipeline,
	),
	cmd_set_descriptor_pool:          proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		pool: ^Descriptor_Pool,
	),
	cmd_set_descriptor_set:           proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		set_index: u32,
		set: ^Descriptor_Set,
	),
	cmd_set_constants:                proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		index: u32,
		data: []u32,
	),
	cmd_draw:                         proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Draw_Desc,
	),
	cmd_draw_indexed:                 proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Draw_Indexed_Desc,
	),
	cmd_draw_indirect:                proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		buffer: ^Buffer,
		offset: u64,
		draw_num: u32,
		stride: u32,
		count_buffer: ^Buffer = nil,
		count_buffer_offset: u64 = 0,
	),
	cmd_draw_indexed_indirect:        proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		buffer: ^Buffer,
		offset: u64,
		draw_num: u32,
		stride: u32,
		count_buffer: ^Buffer = nil,
		count_buffer_offset: u64 = 0,
	),
	cmd_copy_buffer:                  proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		dst: ^Buffer,
		dst_offset: u64,
		src: ^Buffer,
		src_offset: u64,
		size: u64,
	),
	cmd_copy_texture:                 proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		dst: ^Texture,
		dst_region: ^Texture_Region_Desc,
		src: ^Texture,
		src_region: ^Texture_Region_Desc,
	),
	cmd_resolve_texture:              proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		dst: ^Texture,
		dst_region: ^Texture_Region_Desc,
		src: ^Texture,
		src_region: ^Texture_Region_Desc,
	),
	cmd_upload_buffer_to_texture:     proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		dst: ^Texture,
		dst_region: Texture_Region_Desc,
		src: ^Buffer,
		src_data_layout: Texture_Data_Layout_Desc,
	),
	cmd_readback_texture_to_buffer:   proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		dst_buffer: ^Buffer,
		dst_data_layout: Texture_Data_Layout_Desc,
		src_texture: ^Texture,
		src_region: Texture_Region_Desc,
	),
	cmd_dispatch:                     proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		groups: [3]u32,
	),
	cmd_dispatch_indirect:            proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		buffer: ^Buffer,
		offset: u64,
	),
	cmd_barrier:                      proc(
		instance: ^Instance,
		cmd: ^Command_Buffer,
		#by_ptr desc: Barrier_Group_Desc,
	),

	// command queue
	create_command_queue:             proc(
		instance: ^Instance,
		device: ^Device,
		type: Command_Queue_Type,
	) -> (
		queue: ^Command_Queue,
		error: Error,
	),
	destroy_command_queue:            proc(instance: ^Instance, queue: ^Command_Queue),
	set_command_queue_debug_name:     proc(
		instance: ^Instance,
		queue: ^Command_Queue,
		name: string,
	) -> mem.Allocator_Error,
	submit:                           proc(
		instance: ^Instance,
		queue: ^Command_Queue,
		buffers: []^Command_Buffer,
	),

	// descriptor
	create_1d_texture_view:           proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Texture_1D_View_Desc,
	) -> (
		out_descriptor: ^Descriptor,
		error: Error,
	),
	create_2d_texture_view:           proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Texture_2D_View_Desc,
	) -> (
		out_descriptor: ^Descriptor,
		error: Error,
	),
	create_3d_texture_view:           proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Texture_3D_View_Desc,
	) -> (
		out_descriptor: ^Descriptor,
		error: Error,
	),
	create_buffer_view:               proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Buffer_View_Desc,
	) -> (
		out_descriptor: ^Descriptor,
		error: Error,
	),
	create_sampler:                   proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Sampler_Desc,
	) -> (
		out_descriptor: ^Descriptor,
		error: Error,
	),
	destroy_descriptor:               proc(
		instance: ^Instance,
		device: ^Device,
		descriptor: ^Descriptor,
	),
	set_descriptor_debug_name:        proc(
		instance: ^Instance,
		descriptor: ^Descriptor,
		name: string,
	) -> mem.Allocator_Error,

	// descriptor pool
	create_descriptor_pool:           proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Descriptor_Pool_Desc,
	) -> (
		pool: ^Descriptor_Pool,
		error: Error,
	),
	destroy_descriptor_pool:          proc(instance: ^Instance, pool: ^Descriptor_Pool),
	set_descriptor_pool_debug_name:   proc(
		instance: ^Instance,
		pool: ^Descriptor_Pool,
		name: string,
	) -> mem.Allocator_Error,
	allocate_descriptor_set:          proc(
		instance: ^Instance,
		pool: ^Descriptor_Pool,
		#by_ptr desc: Descriptor_Set_Desc,
	) -> (
		set: ^Descriptor_Set,
		error: Error,
	),
	reset_descriptor_pool:            proc(instance: ^Instance, pool: ^Descriptor_Pool),

	// descriptor set
	update_descriptor_ranges:         proc(
		instance: ^Instance,
		set: ^Descriptor_Set,
		base_range: u32,
		ranges: []Descriptor_Range_Update_Desc,
	),

	// fence
	create_fence:                     proc(
		instance: ^Instance,
		device: ^Device,
		initial_value: u64 = 0,
	) -> (
		fence: ^Fence,
		error: Error,
	),
	destroy_fence:                    proc(instance: ^Instance, fence: ^Fence),
	set_fence_debug_name:             proc(
		instance: ^Instance,
		fence: ^Fence,
		name: string,
	) -> mem.Allocator_Error,
	get_fence_value:                  proc(instance: ^Instance, fence: ^Fence) -> u64,
	signal_fence:                     proc(
		instance: ^Instance,
		queue: ^Command_Queue,
		fence: ^Fence,
		value: u64,
	) -> Error,
	wait_fence:                       proc(
		instance: ^Instance,
		queue: ^Command_Queue,
		fence: ^Fence,
		value: u64,
	) -> Error,
	wait_fence_now:                   proc(
		instance: ^Instance,
		fence: ^Fence,
		value: u64,
	) -> Error,

	// pipeline
	create_graphics_pipeline:         proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Graphics_Pipeline_Desc,
	) -> (
		pipeline: ^Pipeline,
		error: Error,
	),
	destroy_pipeline:                 proc(instance: ^Instance, pipeline: ^Pipeline),
	set_pipeline_debug_name:          proc(
		instance: ^Instance,
		pipeline: ^Pipeline,
		name: string,
	) -> mem.Allocator_Error,


	// pipeline layout
	create_pipeline_layout:           proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Pipeline_Layout_Desc,
	) -> (
		pipeline_layout: ^Pipeline_Layout,
		error: Error,
	),
	destroy_pipeline_layout:          proc(instance: ^Instance, pipeline_layout: ^Pipeline_Layout),
	set_pipeline_layout_debug_name:   proc(
		instance: ^Instance,
		pipeline_layout: ^Pipeline_Layout,
		name: string,
	) -> mem.Allocator_Error,

	// swapchain
	create_swapchain:                 proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Swapchain_Desc,
	) -> (
		swapchain: ^Swapchain,
		error: Error,
	),
	destroy_swapchain:                proc(instance: ^Instance, swapchain: ^Swapchain),
	set_swapchain_debug_name:         proc(
		instance: ^Instance,
		swapchain: ^Swapchain,
		name: string,
	) -> mem.Allocator_Error,
	get_swapchain_textures:           proc(
		instance: ^Instance,
		swapchain: ^Swapchain,
		out_textures: []^Texture,
	),
	acquire_next_texture:             proc(instance: ^Instance, swapchain: ^Swapchain) -> u32,
	present:                          proc(instance: ^Instance, swapchain: ^Swapchain) -> Error,
	resize_swapchain:                 proc(
		instance: ^Instance,
		swapchain: ^Swapchain,
		width, height: dim,
	) -> Error,

	// texture
	create_texture:                   proc(
		instance: ^Instance,
		device: ^Device,
		#by_ptr desc: Texture_Desc,
	) -> (
		texture: ^Texture,
		error: Error,
	),
	destroy_texture:                  proc(instance: ^Instance, texture: ^Texture),
	set_texture_debug_name:           proc(
		instance: ^Instance,
		texture: ^Texture,
		name: string,
	) -> mem.Allocator_Error,
	get_texture_desc:                 proc(instance: ^Instance, texture: ^Texture) -> Texture_Desc,
}

Fence :: struct {}
Memory :: struct {}
Buffer :: struct {}
Device :: struct {}
Texture :: struct {}
Pipeline :: struct {}
Query_Pool :: struct {}
Descriptor :: struct {}
Command_Queue :: struct {}
Command_Buffer :: struct {}
Descriptor_Set :: struct {}
Descriptor_Pool :: struct {}
Pipeline_Layout :: struct {}
Command_Allocator :: struct {}

mip :: u8
sample :: u8
dim :: u16
memory_type :: u32

ALL_SAMPLES :: 0
ONE_VIEWPORT :: 0
WHOLE_SIZE :: 0
REMAINING_MIPS :: 0
REMAINING_LAYERS :: 0

Graphics_API :: enum {
	D3D12,
	Vulkan,
}

Format :: enum u8 {
	UNKNOWN, // -  -  -  -  -  -  -  -  -  -

	// Plain: 8 bits per channel
	R8_UNORM, // +  +  +  -  +  -  +  +  +  -
	R8_SNORM, // +  +  +  -  +  -  +  +  +  -
	R8_UINT, // +  +  +  -  -  -  +  +  +  - // SHADING_RATE compatible, see NRI_SHADING_RATE macro
	R8_SINT, // +  +  +  -  -  -  +  +  +  -
	RG8_UNORM, // +  +  +  -  +  -  +  +  +  -
	RG8_SNORM, // +  +  +  -  +  -  +  +  +  -
	RG8_UINT, // +  +  +  -  -  -  +  +  +  -
	RG8_SINT, // +  +  +  -  -  -  +  +  +  -
	BGRA8_UNORM, // +  +  +  -  +  -  +  +  +  -
	BGRA8_SRGB, // +  -  +  -  +  -  -  -  -  -
	RGBA8_UNORM, // +  +  +  -  +  -  +  +  +  -
	RGBA8_SRGB, // +  -  +  -  +  -  -  -  -  -
	RGBA8_SNORM, // +  +  +  -  +  -  +  +  +  -
	RGBA8_UINT, // +  +  +  -  -  -  +  +  +  -
	RGBA8_SINT, // +  +  +  -  -  -  +  +  +  -

	// Plain: 16 bits per channel
	R16_UNORM, // +  +  +  -  +  -  +  +  +  -
	R16_SNORM, // +  +  +  -  +  -  +  +  +  -
	R16_UINT, // +  +  +  -  -  -  +  +  +  -
	R16_SINT, // +  +  +  -  -  -  +  +  +  -
	R16_SFLOAT, // +  +  +  -  +  -  +  +  +  -
	RG16_UNORM, // +  +  +  -  +  -  +  +  +  -
	RG16_SNORM, // +  +  +  -  +  -  +  +  +  -
	RG16_UINT, // +  +  +  -  -  -  +  +  +  -
	RG16_SINT, // +  +  +  -  -  -  +  +  +  -
	RG16_SFLOAT, // +  +  +  -  +  -  +  +  +  -
	RGBA16_UNORM, // +  +  +  -  +  -  +  +  +  -
	RGBA16_SNORM, // +  +  +  -  +  -  +  +  +  -
	RGBA16_UINT, // +  +  +  -  -  -  +  +  +  -
	RGBA16_SINT, // +  +  +  -  -  -  +  +  +  -
	RGBA16_SFLOAT, // +  +  +  -  +  -  +  +  +  -

	// Plain: 32 bits per channel
	R32_UINT, // +  +  +  -  -  +  +  +  +  +
	R32_SINT, // +  +  +  -  -  +  +  +  +  +
	R32_SFLOAT, // +  +  +  -  +  +  +  +  +  +
	RG32_UINT, // +  +  +  -  -  -  +  +  +  -
	RG32_SINT, // +  +  +  -  -  -  +  +  +  -
	RG32_SFLOAT, // +  +  +  -  +  -  +  +  +  -
	RGB32_UINT, // +  -  -  -  -  -  +  -  +  -
	RGB32_SINT, // +  -  -  -  -  -  +  -  +  -
	RGB32_SFLOAT, // +  -  -  -  -  -  +  -  +  -
	RGBA32_UINT, // +  +  +  -  -  -  +  +  +  -
	RGBA32_SINT, // +  +  +  -  -  -  +  +  +  -
	RGBA32_SFLOAT, // +  +  +  -  +  -  +  +  +  -

	// Packed: 16 bits per pixel
	B5_G6_R5_UNORM, // +  -  +  -  +  -  -  -  -  -
	B5_G5_R5_A1_UNORM, // +  -  +  -  +  -  -  -  -  -
	B4_G4_R4_A4_UNORM, // +  -  +  -  +  -  -  -  -  -

	// Packed: 32 bits per pixel
	R10_G10_B10_A2_UNORM, // +  +  +  -  +  -  +  +  +  -
	R10_G10_B10_A2_UINT, // +  +  +  -  -  -  +  +  +  -
	R11_G11_B10_UFLOAT, // +  +  +  -  +  -  +  +  +  -
	R9_G9_B9_E5_UFLOAT, // +  -  -  -  -  -  -  -  -  -

	// Block-compressed
	BC1_RGBA_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC1_RGBA_SRGB, // +  -  -  -  -  -  -  -  -  -
	BC2_RGBA_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC2_RGBA_SRGB, // +  -  -  -  -  -  -  -  -  -
	BC3_RGBA_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC3_RGBA_SRGB, // +  -  -  -  -  -  -  -  -  -
	BC4_R_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC4_R_SNORM, // +  -  -  -  -  -  -  -  -  -
	BC5_RG_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC5_RG_SNORM, // +  -  -  -  -  -  -  -  -  -
	BC6H_RGB_UFLOAT, // +  -  -  -  -  -  -  -  -  -
	BC6H_RGB_SFLOAT, // +  -  -  -  -  -  -  -  -  -
	BC7_RGBA_UNORM, // +  -  -  -  -  -  -  -  -  -
	BC7_RGBA_SRGB, // +  -  -  -  -  -  -  -  -  -

	// Depth-stencil
	D16_UNORM, // -  -  -  +  -  -  -  -  -  -
	D24_UNORM_S8_UINT, // -  -  -  +  -  -  -  -  -  -
	D32_SFLOAT, // -  -  -  +  -  -  -  -  -  -
	D32_SFLOAT_S8_UINT_X24, // -  -  -  +  -  -  -  -  -  -

	// Depth-stencil (SHADER_RESOURCE)
	R24_UNORM_X8, // .x - depth    // +  -  -  -  -  -  -  -  -  -
	X24_G8_UINT, // .y - stencil  // +  -  -  -  -  -  -  -  -  -
	R32_SFLOAT_X8_X24, // .x - depth    // +  -  -  -  -  -  -  -  -  -
	X32_G8_UINT_X24, // .y - stencil  // +  -  -  -  -  -  -  -  -  - 
}

Plane_Bits :: enum u8 {
	Color,
	Depth,
	Stencil,
}
Plane_Flags :: bit_set[Plane_Bits;u32]
Plane_All: Plane_Flags : {.Color, .Depth, .Stencil}

Format_Support_Bits :: enum u8 {
	// Texture
	Texture,
	Storage_Texture,
	Color_Attachment,
	Depth_Stencil_Attachment,
	Blend,
	Storage_Texture_Atomics, // other than Load / Store

	// Buffer
	Buffer,
	Storage_Buffer,
	Vertex_Buffer,
	Storage_Buffer_Atomics, // other than Load / Store
}
Format_Support_Flags :: bit_set[Format_Support_Bits;u32]

Stage_Bits :: enum u8 {
	// Graphics
	Index_Input,
	Vertex_Shader,
	Tess_Control_Shader,
	Tess_Evaluation_Shader,
	Geometry_Shader,
	Fragment_Shader,
	Depth_Stencil_Attachment,
	Color_Attachment,

	// Compute                                
	Compute_Shader,

	// Ray tracing
	Raygen_Shader,
	Miss_Shader,
	Intersection_Shader,
	Closest_Hit_Shader,
	Any_Hit_Shader,
	Callable_Shader,
	Acceleration_Structure,

	// Copy
	Copy,
	Clear_Storage,
	Resolve,

	// Modifiers
	Indirect,
}
Stage_Flags :: bit_set[Stage_Bits;u32]
Ray_Tracing_Stages: Stage_Flags : {
	.Raygen_Shader,
	.Miss_Shader,
	.Intersection_Shader,
	.Closest_Hit_Shader,
	.Any_Hit_Shader,
	.Callable_Shader,
}

Viewport :: struct {
	x, y, width, height, min_depth, max_depth: f32,
	origin_bottom_left:                        bool,
}

Rect :: struct {
	x, y:          i16,
	width, height: dim,
}

Colorf :: [4]f32
Colorui :: [4]u32
Colori :: [4]i32

Color :: union #no_nil {
	Colorf,
	Colorui,
	Colori,
}

Depth_Stencil :: struct {
	depth:   f32,
	stencil: u8,
}

Clear_Value :: union {
	Color,
	Depth_Stencil,
}

Sample_Location :: struct {
	x, y: i8,
}

Command_Queue_Type :: enum u8 {
	Graphics,
	Compute,
	Copy,
	High_Priority_Copy,
}

Memory_Location :: enum u8 {
	Device,
	Device_Upload, // soft fallback to HOST_UPLOAD
	Host_Upload,
	Host_Readback,
}

Texture_Type :: enum u8 {
	_1D,
	_2D,
	_3D,
}

Texture_1D_View_Type :: enum u8 {
	Shader_Resource,
	Shader_Resource_Array,
	Shader_Resource_Storage,
	Shader_Resource_Storage_Array,
	Color_Attachment,
	Depth_Stencil_Attachment,
	Depth_Readonly_Stencil_Attachment,
	Depth_Attachment_Stencil_Readonly,
	Depth_Stencil_Readonly,
}

Texture_2D_View_Type :: enum u8 {
	Shader_Resource,
	Shader_Resource_Array,
	Shader_Resource_Cube,
	Shader_Resource_Cube_Array,
	Shader_Resource_Storage,
	Shader_Resource_Storage_Array,
	Color_Attachment,
	Depth_Stencil_Attachment,
	Depth_Readonly_Stencil_Attachment,
	Depth_Attachment_Stencil_Readonly,
	Depth_Stencil_Readonly,
	Shading_Rate_Attachment,
}

Texture_3D_View_Type :: enum u8 {
	Shader_Resource,
	Shader_Resource_Storage,
	Color_Attachment,
}

Buffer_View_Type :: enum u8 {
	Shader_Resource,
	Shader_Resource_Storage,
	Constant,
}

Descriptor_Type :: enum u8 {
	Sampler,
	Constant_Buffer,
	Texture,
	Storage_Texture,
	Buffer,
	Storage_Buffer,
	Structured_Buffer,
	Storage_Structured_Buffer,
	Acceleration_Structure,
}

Texture_Usage_Bits :: enum u8 {
	Shader_Resource,
	Shader_Resource_Storage,
	Color_Attachment,
	Depth_Stencil_Attachment,
	Shading_Rate_Attachment,
}
Texture_Usage_Flags :: bit_set[Texture_Usage_Bits;u32]

Buffer_Usage_Bits :: enum u8 {
	Shader_Resource,
	Shader_Resource_Storage,
	Vertex_Buffer,
	Index_Buffer,
	Constant_Buffer,
	Argument_Buffer,
	Scratch_Buffer,
	Shader_Binding_Table,
	Acceleration_Structure_Build_Input,
	Acceleration_Structure_Storage,
}
Buffer_Usage_Flags :: bit_set[Buffer_Usage_Bits;u32]

Texture_Desc :: struct {
	type:       Texture_Type,
	usage:      Texture_Usage_Flags,
	location:   Memory_Location,
	format:     Format,
	width:      dim,
	height:     dim,
	depth:      dim,
	mip_num:    u8,
	layer_num:  u16,
	sample_num: u8,
}
fix_texture_desc :: proc(desc: ^Texture_Desc) {
	if desc.height == 0 do desc.height = 1
	if desc.depth == 0 do desc.depth = 1
	if desc.mip_num == 0 do desc.mip_num = 1
	if desc.layer_num == 0 do desc.layer_num = 1
	if desc.sample_num == 0 do desc.sample_num = 1
}

Buffer_Desc :: struct {
	usage:            Buffer_Usage_Flags,
	location:         Memory_Location,
	size:             u64,
	structure_stride: u32,
}

Texture_1D_View_Desc :: struct {
	texture:      ^Texture,
	view_type:    Texture_1D_View_Type,
	format:       Format,
	mip_offset:   mip,
	mip_num:      mip,
	layer_offset: u16,
	layer_num:    u16,
}

Texture_2D_View_Desc :: struct {
	texture:      ^Texture,
	view_type:    Texture_2D_View_Type,
	format:       Format,
	mip_offset:   mip,
	mip_num:      mip,
	layer_offset: u16,
	layer_num:    u16,
}

Texture_3D_View_Desc :: struct {
	texture:      ^Texture,
	view_type:    Texture_3D_View_Type,
	format:       Format,
	mip_offset:   mip,
	mip_num:      mip,
	slice_offset: u16,
	slice_num:    u16,
}

Buffer_View_Desc :: struct {
	buffer:    ^Buffer,
	view_type: Buffer_View_Type,
	format:    Format,
	offset:    u64,
	size:      u64,
}

Descriptor_Pool_Desc :: struct {
	descriptor_set_max_num:            u32,
	sampler_max_num:                   u32,
	constant_buffer_max_num:           u32,
	texture_max_num:                   u32,
	storage_texture_max_num:           u32,
	buffer_max_num:                    u32,
	storage_buffer_max_num:            u32,
	structured_buffer_max_num:         u32,
	storage_structured_buffer_max_num: u32,
	acceleration_structure_max_num:    u32,
}

Descriptor_Range_Bits :: enum u8 {
	Partially_Bound,
	Array,
	Variable_Sized_Array,
}
Descriptor_Range_Flags :: bit_set[Descriptor_Range_Bits;u32]

Descriptor_Range_Desc :: struct {
	base_register_index, descriptor_num: u32,
	descriptor_type:                     Descriptor_Type,
	shader_stages:                       Stage_Flags,
	flags:                               Descriptor_Range_Flags,
}

texture_range :: proc(
	register: u32 = 0,
	num: u32 = 1,
	partial: bool = false,
	stages: Stage_Flags = {},
	writable: bool = false,
) -> Descriptor_Range_Desc {
	flags := Descriptor_Range_Flags{}
	if partial do flags += {.Partially_Bound}
	if num > 1 do flags += {.Array}
	return Descriptor_Range_Desc {
		base_register_index = register,
		descriptor_num = num,
		descriptor_type = .Storage_Texture if writable else .Texture,
		shader_stages = stages,
		flags = flags,
	}
}

buffer_range :: proc(
	register: u32 = 0,
	num: u32 = 1,
	partial: bool = false,
	stages: Stage_Flags = {},
	writable: bool = false,
) -> Descriptor_Range_Desc {
	flags := Descriptor_Range_Flags{}
	if partial do flags += {.Partially_Bound}
	if num > 1 do flags += {.Array}
	return Descriptor_Range_Desc {
		base_register_index = register,
		descriptor_num = num,
		descriptor_type = .Storage_Buffer if writable else .Buffer,
		shader_stages = stages,
		flags = flags,
	}
}

structured_buffer_range :: proc(
	register: u32 = 0,
	num: u32 = 1,
	partial: bool = false,
	stages: Stage_Flags = {},
	writable: bool = false,
) -> Descriptor_Range_Desc {
	flags := Descriptor_Range_Flags{}
	if partial do flags += {.Partially_Bound}
	if num > 1 do flags += {.Array}
	return Descriptor_Range_Desc {
		base_register_index = register,
		descriptor_num = num,
		descriptor_type = .Storage_Structured_Buffer if writable else .Structured_Buffer,
		shader_stages = stages,
		flags = flags,
	}
}

constant_buffer :: proc(register: u32 = 0, stages: Stage_Flags = {}) -> Descriptor_Range_Desc {
	return Descriptor_Range_Desc {
		base_register_index = register,
		descriptor_num = 1,
		descriptor_type = .Constant_Buffer,
		shader_stages = stages,
	}
}

sampler_range :: proc(
	register: u32 = 0,
	num: u32 = 1,
	partial: bool = false,
	stages: Stage_Flags = {},
) -> Descriptor_Range_Desc {
	flags := Descriptor_Range_Flags{}
	if partial do flags += {.Partially_Bound}
	if num > 1 do flags += {.Array}
	return Descriptor_Range_Desc {
		base_register_index = register,
		descriptor_num = num,
		descriptor_type = .Sampler,
		shader_stages = stages,
		flags = flags,
	}
}

Descriptor_Set_Desc :: struct {
	register_space: u32,
	ranges:         []Descriptor_Range_Desc,
}

Constant_Desc :: struct {
	register_index, size: u32,
	shader_stages:        Stage_Flags,
}

Pipeline_Layout_Desc :: struct {
	constants_register_space:               u32,
	constants:                              []Constant_Desc,
	descriptor_sets:                        []Descriptor_Set_Desc,
	shader_stages:                          Stage_Flags,
	ignore_global_spirv_offsets:            bool,
	enable_d3d12_draw_parameters_emulation: bool,
}

Descriptor_Range_Update_Desc :: struct {
	descriptors:     []^Descriptor,
	base_descriptor: u32,
}

Descriptor_Set_Copy_Desc :: struct {
	src_descriptor_set:                        ^Descriptor_Set,
	src_base_range, dst_base_range, range_num: u32,
	src_base_dynamic_constant_buffer:          u32,
	dst_base_dynamic_constant_buffer:          u32,
	dynamic_constant_buffer_num:               u32,
}

Vertex_Stream_Step_Rate :: enum u8 {
	Per_Vertex,
	Per_Instance,
}

Index_Type :: enum u8 {
	Uint16,
	Uint32,
}

Primitive_Restart :: enum u8 {
	Disabled,
	Indices_Uint16,
	Indices_Uint32,
}

Topology :: enum u8 {
	Point_List,
	Line_List,
	Line_Strip,
	Triangle_List,
	Triangle_Strip,
	Line_List_With_Adjacency,
	Line_Strip_With_Adjacency,
	Triangle_List_With_Adjacency,
	Triangle_Strip_With_Adjacency,
	Patch_List,
}

Input_Assembly_Desc :: struct {
	topology:               Topology,
	tess_control_point_num: u8,
	primitive_restart:      Primitive_Restart,
}

Vertex_Attribute_D3D :: struct {
	semantic_name:  string,
	semantic_index: u32,
}

Vertex_Attribute_VK :: struct {
	location: u32,
}

Vertex_Attribute_Desc :: struct {
	d3d:          Vertex_Attribute_D3D,
	vk:           Vertex_Attribute_VK,
	offset:       u32,
	format:       Format,
	stream_index: u16,
}

Vertex_Stream_Desc :: struct {
	stride:       u16,
	binding_slot: u16,
	step_rate:    Vertex_Stream_Step_Rate,
}

Vertex_Input_Desc :: struct {
	attributes: []Vertex_Attribute_Desc,
	streams:    []Vertex_Stream_Desc,
}

Fill_Mode :: enum u8 {
	Solid,
	Wireframe,
}

Cull_Mode :: enum u8 {
	None,
	Front,
	Back,
}

Shading_Rate :: enum u8 {
	Fragment_Size_1x1,
	Fragment_Size_1x2,
	Fragment_Size_2x1,
	Fragment_Size_2x2,

	// Require "is_additional_shading_rates_supported"
	Fragment_Size_2x4,
	Fragment_Size_4x2,
	Fragment_Size_4x4,
}

Shading_Rate_Combiner :: enum u8 {
	Replace,
	Keep,
	Min,
	Max,
	Sum,
}

/*
R - minimum resolvable difference
S - maximum slope

bias = constant * R + slopeFactor * S
if (clamp > 0)
    bias = min(bias, clamp)
else if (clamp < 0)
    bias = max(bias, clamp)

enabled if constant != 0 or slope != 0
*/
Depth_Bias_Desc :: struct {
	constant, clamp, slope: f32,
}

Rasterization_Desc :: struct {
	viewport_num:            u32,
	depth_bias:              Depth_Bias_Desc,
	fill_mode:               Fill_Mode,
	cull_mode:               Cull_Mode,
	front_counter_clockwise: bool,
	depth_clamp:             bool,
	line_smoothing:          bool,
	conservative_raster:     bool,
	shading_rate:            bool,
}

Multisample_Desc :: struct {
	enabled:                             bool,
	sample_mask:                         u32,
	sample_num:                          sample,
	alpha_to_coverage, sample_locations: bool,
}

Shading_Rate_Desc :: struct {
	shading_rate:                            Shading_Rate,
	primitive_combiner, attachment_combiner: Shading_Rate_Combiner,
}

// S - source color 0
// D - destination color
Logic_Func :: enum u8 {
	None,
	// 0
	Clear,
	// S & D
	And,
	// S & ~D
	And_Reverse,
	// S
	Copy,
	// ~S & D
	And_Inverted,
	// S ^ D
	Xor,
	// S | D
	Or,
	// ~(S | D)
	Nor,
	// ~(S ^ D)
	Equivalent,
	// ~D
	Invert,
	// S | ~D
	Or_Reverse,
	// ~S
	Copy_Inverted,
	// ~S | D
	Or_Inverted,
	// ~(S & D)
	Nand,
	// 1
	Set,
}


// R - fragment's depth or stencil reference
// D - depth or stencil buffer
Compare_Func :: enum u8 {
	// test is disabled
	None,
	// true
	Always,
	// false
	Never,
	// R == D
	Equal,
	// R != D
	Not_Equal,
	// R < D
	Less,
	// R <= D
	Less_Equal,
	// R > D
	Greater,
	// R >= D
	Greater_Equal,
}

// R - reference, set by "CmdSetStencilReference"
// D - stencil buffer
Stencil_Func :: enum u8 {
	// D = D
	Keep,
	// D = 0
	Zero,
	// D = R
	Replace,
	// D = min(D++, 255)
	Increment_Clamp,
	// D = max(D--, 0)
	Decrement_Clamp,
	// D = ~D
	Invert,
	// D++
	Increment_Wrap,
	// D--
	Decrement_Wrap,
}

// S0 - source color 0
// S1 - source color 1
// D - destination color
// C - blend constants, set by "CmdSetBlendConstants"
Blend_Factor :: enum u8 {
	// 0
	Zero,
	// 1
	One,
	// S0.r, S0.g, S0.b
	Src_Color,
	// 1 - S0.r, 1 - S0.g, 1 - S0.b
	One_Minus_Src_Color,
	// D.r, D.g, D.b
	Dst_Color,
	// 1 - D.r, 1 - D.g, 1 - D.b
	One_Minus_Dst_Color,
	// S0.a
	Src_Alpha,
	// 1 - S0.a
	One_Minus_Src_Alpha,
	// D.a
	Dst_Alpha,
	// 1 - D.a
	One_Minus_Dst_Alpha,
	// C.r, C.g, C.b
	Constant_Color,
	// 1 - C.r, 1 - C.g, 1 - C.b
	One_Minus_Constant_Color,
	// C.a
	Constant_Alpha,
	// 1 - C.a
	One_Minus_Constant_Alpha,
	// min(S0.a, 1 - D.a)
	Src_Alpha_Saturate,
	// S1.r, S1.g, S1.b
	Src1_Color,
	// 1 - S1.r, 1 - S1.g, 1 - S1.b
	One_Minus_Src1_Color,
	// S1.a
	Src1_Alpha,
	// 1 - S1.a
	One_Minus_Src1_Alpha,
}

// S - source color
// D - destination color
// Sf - source factor, produced by "BlendFactor"
// Df - destination factor, produced by "BlendFactor"
Blend_Func :: enum u8 {
	// S * Sf + D * Df
	Add,
	// S * Sf - D * Df
	Subtract,
	// D * Df - S * Sf
	Reverse_Subtract,
	// min(S, D)
	Min,
	// max(S, D)
	Max,
}

Color_Write_Bits :: enum u8 {
	R,
	G,
	B,
	A,
}
Color_Write_Flags :: bit_set[Color_Write_Bits;u8]
Color_Write_RGBA: Color_Write_Flags : {.R, .G, .B, .A}
Color_Write_RGB: Color_Write_Flags : {.R, .G, .B}

Clear_Desc :: struct {
	value:                  Clear_Value,
	planes:                 Plane_Flags,
	color_attachment_index: u32,
}

Stencil_Desc :: struct {
	compare_func:             Compare_Func,
	fail:                     Stencil_Func,
	pass:                     Stencil_Func,
	depth_fail:               Stencil_Func,
	write_mask, compare_mask: u8,
}

Blending_Desc :: struct {
	src_factor, dst_factor: Blend_Factor,
	func:                   Blend_Func,
}

Color_Attachment_Desc :: struct {
	format:                   Format,
	color_blend, alpha_blend: Blending_Desc,
	color_write_mask:         Color_Write_Flags,
	blend_enabled:            bool,
}

Depth_Attachment_Desc :: struct {
	compare_func:       Compare_Func,
	write, bounds_test: bool,
}

Stencil_Attachment_Desc :: struct {
	front, back: Stencil_Desc,
}

Output_Merger_Desc :: struct {
	colors:               []Color_Attachment_Desc,
	depth:                Depth_Attachment_Desc,
	stencil:              Stencil_Attachment_Desc,
	depth_stencil_format: Format,
	logic_func:           Logic_Func,
}

Attachments_Desc :: struct {
	depth_stencil, shading_rate: ^Descriptor,
	colors:                      []^Descriptor,
}

Filter :: enum u8 {
	Nearest,
	Linear,
}

Filter_Ext :: enum u8 {
	None,
	Min,
	Max,
}

Address_Mode :: enum u8 {
	Repeat,
	Mirrored_Repeat,
	Clamp_To_Edge,
	Clamp_To_Border,
	Mirror_Clamp_To_Edge,
}

Address_Modes :: struct {
	u, v, w: Address_Mode,
}

Filters :: struct {
	min, mag, mip: Filter,
	ext:           Filter_Ext,
}

Sampler_Desc :: struct {
	filters:                    Filters,
	anisotropy:                 u8,
	mip_bias, mip_min, mip_max: f32,
	address_modes:              Address_Modes,
	compare_func:               Compare_Func,
	border_color:               Color,
	is_integer:                 bool,
}

Shader_Desc :: struct {
	stage:            Stage_Flags,
	bytecode:         []u8,
	entry_point_name: string,
}

Graphics_Pipeline_Desc :: struct {
	pipeline_layout: ^Pipeline_Layout,
	vertex_input:    Vertex_Input_Desc,
	input_assembly:  Input_Assembly_Desc,
	rasterization:   Rasterization_Desc,
	// optional
	multisample:     Multisample_Desc,
	output_merger:   Output_Merger_Desc,
	shaders:         []Shader_Desc,
}

Compute_Pipeline_Desc :: struct {
	pipeline_layout: ^Pipeline_Layout,
	shader:          Shader_Desc,
}

Access_Bits :: enum u16 {
	Unknown,
	Index_Buffer, // INDEX_INPUT
	Vertex_Buffer, // VERTEX_SHADER
	Constant_Buffer, // GRAPHICS_SHADERS, COMPUTE_SHADER, RAY_TRACING_SHADERS
	Shader_Resource, // GRAPHICS_SHADERS, COMPUTE_SHADER, RAY_TRACING_SHADERS
	Shader_Resource_Storage, // GRAPHICS_SHADERS, COMPUTE_SHADER, RAY_TRACING_SHADERS, CLEAR_STORAGE
	Argument_Buffer, // INDIRECT
	Color_Attachment, // COLOR_ATTACHMENT
	Depth_Stencil_Attachment_Write, // DEPTH_STENCIL_ATTACHMENT
	Depth_Stencil_Attachment_Read, // DEPTH_STENCIL_ATTACHMENT
	Copy_Source, // COPY
	Copy_Destination, // COPY
	Resolve_Source, // RESOLVE
	Resolve_Destination, // RESOLVE
	Acceleration_Structure_Read, // COMPUTE_SHADER, RAY_TRACING_SHADERS, ACCELERATION_STRUCTURE
	Acceleration_Structure_Write, // COMPUTE_SHADER, RAY_TRACING_SHADERS, ACCELERATION_STRUCTURE
	Shading_Rate_Attachment, // FRAGMENT_SHADER
}
Access_Flags :: bit_set[Access_Bits;u32]

Layout :: enum u8 {
	Unknown,
	Color_Attachment, // COLOR_ATTACHMENT
	Depth_Stencil_Attachment, // DEPTH_STENCIL_ATTACHMENT_WRITE
	Depth_Stencil_Readonly, // DEPTH_STENCIL_ATTACHMENT_READ, SHADER_RESOURCE
	Shader_Resource, // SHADER_RESOURCE
	Shader_Resource_Storage, // SHADER_RESOURCE_STORAGE
	Copy_Source, // COPY_SOURCE
	Copy_Destination, // COPY_DESTINATION
	Resolve_Source, // RESOLVE_SOURCE
	Resolve_Destination, // RESOLVE_DESTINATION
	Present, // UNKNOWN
	Shading_Rate_Attachment, // SHADING_RATE_ATTACHMENT
}

Access_Stage :: struct {
	access: Access_Flags,
	stages: Stage_Flags,
}

ACCESS_STAGE_SHADER_RESOURCE: Access_Stage : {access = {.Shader_Resource}}
ACCESS_STAGE_SHADER_RESOURCE_STORAGE: Access_Stage : {access = {.Shader_Resource_Storage}}
ACCESS_STAGE_COPY_SOURCE: Access_Stage : {access = {.Copy_Source}, stages = {.Copy}}
ACCESS_STAGE_COPY_DESTINATION: Access_Stage : {access = {.Copy_Destination}, stages = {.Copy}}
ACCESS_STAGE_VERTEX_BUFFER: Access_Stage : {access = {.Vertex_Buffer}, stages = {.Vertex_Shader}}
ACCESS_STAGE_INDEX_BUFFER: Access_Stage : {
	access = {.Index_Buffer},
	stages = {.Vertex_Shader, .Index_Input},
}

Access_Layout_Stage :: struct {
	access: Access_Flags,
	layout: Layout,
	stages: Stage_Flags,
}

ACCESS_LAYOUT_STAGE_COLOR_ATTACHMENT: Access_Layout_Stage : {
	access = {.Color_Attachment},
	layout = .Color_Attachment,
}

ACCESS_LAYOUT_STAGE_DEPTH_STENCIL_ATTACHMENT_WRITE: Access_Layout_Stage : {
	access = {.Depth_Stencil_Attachment_Write},
	layout = .Depth_Stencil_Attachment,
}

ACCESS_LAYOUT_STAGE_DEPTH_STENCIL_ATTACHMENT_READ: Access_Layout_Stage : {
	access = {.Depth_Stencil_Attachment_Read},
	layout = .Depth_Stencil_Readonly,
}

ACCESS_LAYOUT_STAGE_SHADER_RESOURCE: Access_Layout_Stage : {
	access = {.Shader_Resource},
	layout = .Shader_Resource,
}

ACCESS_LAYOUT_STAGE_PRESENT: Access_Layout_Stage : {layout = .Present}

Global_Barrier_Desc :: struct {
	before, after: Access_Stage,
}

Buffer_Barrier_Desc :: struct {
	buffer:        ^Buffer,
	before, after: Access_Stage,
}

Texture_Barrier_Desc :: struct {
	texture:                 ^Texture,
	before, after:           Access_Layout_Stage,
	mip_offset, mip_num:     mip,
	layer_offset, layer_num: dim,
	planes:                  Plane_Flags,
}

Barrier_Group_Desc :: struct {
	globals:  []Global_Barrier_Desc,
	buffers:  []Buffer_Barrier_Desc,
	textures: []Texture_Barrier_Desc,
}

Texture_Region_Desc :: struct {
	x, y, z:              u16,
	width, height, depth: dim,
	mip_offset:           mip,
	layer_offset:         dim,
}

Texture_Data_Layout_Desc :: struct {
	offset:      u64,
	row_pitch:   u32,
	slice_pitch: u32,
}

Memory_Desc :: struct {
	size, alignment:   u64,
	type:              memory_type,
	must_be_dedicated: bool,
}

Allocate_Memory_Desc :: struct {
	size:     u64,
	type:     memory_type,
	priority: f32,
}

Buffer_Memory_Binding_Desc :: struct {
	memory: ^Memory,
	buffer: ^Buffer,
	offset: u64,
}

Texture_Memory_Binding_Desc :: struct {
	memory:  ^Memory,
	texture: ^Texture,
	offset:  u64,
}

Clear_Storage_Buffer_Desc :: struct {
	storage_buffer:                           ^Descriptor,
	value:                                    u32,
	set_index, range_index, descriptor_index: u32,
}

Clear_Storage_Texture_Desc :: struct {
	storage_texture:                          ^Descriptor,
	value:                                    Clear_Value,
	set_index, range_index, descriptor_index: u32,
}

Draw_Desc :: struct {
	vertex_num:    u32,
	instance_num:  u32,
	base_vertex:   u32,
	base_instance: u32,
}

Draw_Indexed_Desc :: struct {
	index_num:     u32,
	instance_num:  u32,
	base_index:    u32,
	base_vertex:   u32,
	base_instance: u32,
}

Dispatch_Desc :: struct {
	x, y, z: u32,
}

Draw_Emulated_Desc :: struct {
	shader_emulated_base_vertex:   u32,
	shader_emulated_base_instance: u32,
	vertex_num:                    u32,
	instance_num:                  u32,
	base_vertex:                   u32,
	base_instance:                 u32,
}

Draw_Indexed_Emulated_Desc :: struct {
	shader_emulated_base_vertex:   u32,
	shader_emulated_base_instance: u32,
	index_num:                     u32,
	instance_num:                  u32,
	base_index:                    u32,
	base_vertex:                   u32,
	base_instance:                 u32,
}

Query_Type :: enum u8 {
	Timestamp,
	Timestamp_Copy_Queue,
	Occlusion,
	Pipeline_Statistics,
	Acceleration_Structure_Compacted_Size,
}

Query_Pool_Desc :: struct {
	query_type: Query_Type,
	capacity:   u32,
}

Pipeline_Statistics_Desc :: struct {
	input_vertex_num:                      u64,
	input_primitive_num:                   u64,
	vertex_shader_invocation_num:          u64,
	geometry_shader_invocation_num:        u64,
	geometry_shader_primitive_num:         u64,
	rasterizer_in_primitive_num:           u64,
	rasterizer_out_primitive_num:          u64,
	fragment_shader_invocation_num:        u64,
	tess_control_shader_invocation_num:    u64,
	tess_evaluation_shader_invocation_num: u64,
	compute_shader_invocation_num:         u64,
	mesh_control_shader_invocation_num:    u64,
	mesh_evaluation_shader_invocation_num: u64,
	mesh_evaluation_shader_primitive_num:  u64,
}

Vendor :: enum u8 {
	UNKNOWN,
	NVIDIA,
	AMD,
	INTEL,
}

Adapter_Desc :: struct {
	name:                                        [256]u8,
	luid, video_memory_size, system_memory_size: u64,
	device_id:                                   u32,
	vendor:                                      Vendor,
}

Device_Desc :: struct {
	adapter_desc:                                                                          Adapter_Desc,
	graphics_api:                                                                          Graphics_API,
	viewport_max_num:                                                                      u32,
	viewport_bounds_range:                                                                 [2]i32,
	attachment_max_dim, attachment_layer_max_num, color_attachment_max_num:                dim,
	color_sample_max_num:                                                                  sample,
	depth_sample_max_num:                                                                  sample,
	stencil_sample_max_num:                                                                sample,
	zero_attachments_sample_max_num:                                                       sample,
	texture_color_sample_max_num:                                                          sample,
	texture_integer_sample_max_num:                                                        sample,
	texture_depth_sample_max_num:                                                          sample,
	texture_stencil_sample_max_num:                                                        sample,
	storage_texture_sample_max_num:                                                        sample,
	texture_1d_max_dim:                                                                    dim,
	texture_2d_max_dim:                                                                    dim,
	texture_3d_max_dim:                                                                    dim,
	texture_array_layer_max_num:                                                           dim,
	typed_buffer_max_dim:                                                                  u32,
	device_upload_heap_size:                                                               u64,
	memory_allocation_max_num:                                                             u32,
	sampler_allocation_max_num:                                                            u32,
	constant_buffer_max_range:                                                             u32,
	storage_buffer_max_range:                                                              u32,
	buffer_texture_granularity:                                                            u32,
	buffer_max_size:                                                                       u64,
	upload_buffer_texture_row_alignment:                                                   u32,
	upload_buffer_texture_slice_alignment:                                                 u32,
	buffer_shader_resource_offset_alignment:                                               u32,
	constant_buffer_offset_alignment:                                                      u32,
	scratch_buffer_offset_alignment:                                                       u32,
	shader_binding_table_alignment:                                                        u32,
	pipeline_layout_descriptor_set_max_num:                                                u32,
	pipeline_layout_constant_max_size:                                                     u32,
	descriptor_set_sampler_max_num:                                                        u32,
	descriptor_set_constant_buffer_max_num:                                                u32,
	descriptor_set_storage_buffer_max_num:                                                 u32,
	descriptor_set_texture_max_num:                                                        u32,
	descriptor_set_storage_texture_max_num:                                                u32,
	per_stage_descriptor_sampler_max_num:                                                  u32,
	per_stage_descriptor_constant_buffer_max_num:                                          u32,
	per_stage_descriptor_storage_buffer_max_num:                                           u32,
	per_stage_descriptor_texture_max_num:                                                  u32,
	per_stage_descriptor_storage_texture_max_num:                                          u32,
	per_stage_resource_max_num:                                                            u32,
	vertex_shader_attribute_max_num:                                                       u32,
	vertex_shader_stream_max_num:                                                          u32,
	vertex_shader_output_component_max_num:                                                u32,
	tess_control_shader_generation_max_level:                                              f32,
	tess_control_shader_patch_point_max_num:                                               u32,
	tess_control_shader_per_vertex_input_component_max_num:                                u32,
	tess_control_shader_per_vertex_output_component_max_num:                               u32,
	tess_control_shader_per_patch_output_component_max_num:                                u32,
	tess_control_shader_total_output_component_max_num:                                    u32,
	tess_evaluation_shader_input_component_max_num:                                        u32,
	tess_evaluation_shader_output_component_max_num:                                       u32,
	geometry_shader_invocation_max_num:                                                    u32,
	geometry_shader_input_component_max_num:                                               u32,
	geometry_shader_output_component_max_num:                                              u32,
	geometry_shader_output_vertex_max_num:                                                 u32,
	geometry_shader_total_output_component_max_num:                                        u32,
	fragment_shader_input_component_max_num:                                               u32,
	fragment_shader_output_attachment_max_num:                                             u32,
	fragment_shader_dual_source_attachment_max_num:                                        u32,
	compute_shader_shared_memory_max_size, compute_shader_work_group_max_num:              [3]u32,
	compute_shader_work_group_invocation_max_num, compute_shader_work_group_max_dim:       [3]u32,
	ray_tracing_shader_group_identifier_size:                                              u32,
	ray_tracing_shader_table_max_stride:                                                   u32,
	ray_tracing_shader_recursion_max_depth:                                                u32,
	ray_tracing_geometry_object_max_num:                                                   u32,
	mesh_control_shared_memory_max_size:                                                   u32,
	mesh_control_work_group_invocation_max_num:                                            u32,
	mesh_control_payload_max_size:                                                         u32,
	mesh_evaluation_output_vertices_max_num:                                               u32,
	mesh_evaluation_output_primitive_max_num:                                              u32,
	mesh_evaluation_output_component_max_num:                                              u32,
	mesh_evaluation_shared_memory_max_size:                                                u32,
	mesh_evaluation_work_group_invocation_max_num:                                         u32,
	viewport_precision_bits:                                                               u32,
	sub_pixel_precision_bits:                                                              u32,
	sub_texel_precision_bits:                                                              u32,
	mipmap_precision_bits:                                                                 u32,
	timestamp_frequency_hz:                                                                u64,
	draw_indirect_max_num:                                                                 u32,
	sampler_lod_bias_min, sampler_lod_bias_max, sampler_anisotropy_max:                    f32,
	texel_offset_min, texel_offset_max, texel_gather_offset_min, texel_gather_offset_max:  i32,
	clip_distance_max_num, cull_distance_max_num, combined_clip_and_cull_distance_max_num: u32,
	shading_rate_attachment_tile_size, shader_model:                                       u8,
	conservative_raster_tier:                                                              u8,
	sample_locations_tier:                                                                 u8,
	ray_tracing_tier:                                                                      u8,
	shading_rate_tier:                                                                     u8,
	bindless_tier:                                                                         u8,
	is_compute_queue_supported:                                                            bool,
	is_copy_queue_supported:                                                               bool,
	is_texture_filter_min_max_supported:                                                   bool,
	is_logic_func_supported:                                                               bool,
	is_depth_bounds_test_supported:                                                        bool,
	is_draw_indirect_count_supported:                                                      bool,
	is_independent_front_and_back_stencil_reference_and_masks_supported:                   bool,
	is_line_smoothing_supported:                                                           bool,
	is_copy_queue_timestamp_supported:                                                     bool,
	is_mesh_shader_pipeline_stats_supported:                                               bool,
	is_enchanced_barrier_supported:                                                        bool,
	is_memory_tier2_supported:                                                             bool,
	is_dynamic_depth_bias_supported:                                                       bool,
	is_additional_shading_rates_supported:                                                 bool,
	is_viewport_origin_bottom_left_supported:                                              bool,
	is_region_resolve_supported:                                                           bool,
	is_shader_native_i16_supported:                                                        bool,
	is_shader_native_f16_supported:                                                        bool,
	is_shader_native_i32_supported:                                                        bool,
	is_shader_native_f32_supported:                                                        bool,
	is_shader_native_i64_supported:                                                        bool,
	is_shader_native_f64_supported:                                                        bool,
	is_shader_atomics_i16_supported:                                                       bool,
	is_shader_atomics_f16_supported:                                                       bool,
	is_shader_atomics_i32_supported:                                                       bool,
	is_shader_atomics_f32_supported:                                                       bool,
	is_shader_atomics_i64_supported:                                                       bool,
	is_shader_atomics_f64_supported:                                                       bool,
	is_draw_parameters_emulation_enabled:                                                  bool,
	is_swapchain_supported:                                                                bool,
	is_ray_tracing_supported:                                                              bool,
	is_mesh_shader_supported:                                                              bool,
	is_low_latency_supported:                                                              bool,
}


Message :: enum u8 {
	Info,
	Warning,
	Error,
}

Allocation_Callbacks :: struct {
	Allocate:   proc "c" (user_data: rawptr, size: u64, alignment: u64) -> rawptr,
	Reallocate: proc "c" (user_data: rawptr, ptr: rawptr, size: u64, alignment: u64) -> rawptr,
	Free:       proc "c" (user_data: rawptr, ptr: rawptr),
	user_arg:   rawptr,
}

Callback_Interface :: struct {
	MessageCallback: proc "c" (
		level: Message,
		file: cstring,
		line: u32,
		message: cstring,
		user_data: rawptr,
	),
	AbortExecution:  proc "c" (user_data: rawptr),
	user_arg:        rawptr,
}

SPIRV_Binding_Offsets :: struct {
	sampler_offset:                    u32,
	texture_offset:                    u32,
	constant_buffer_offset:            u32,
	storage_texture_and_buffer_offset: u32,
}

VK_Extensions :: struct {
	instance_extensions: []cstring,
	device_extensions:   []cstring,
}

Device_Creation_Desc :: struct {
	adapter_desc:                           ^Adapter_Desc,
	callback_interface:                     ^Callback_Interface,
	allocation_callbacks:                   ^Allocation_Callbacks,
	spirv_binding_offsets:                  SPIRV_Binding_Offsets,
	vk_extensions:                          VK_Extensions,
	graphics_api:                           Graphics_API,
	shader_ext_register:                    u32,
	shader_ext_space:                       u32,
	enable_validation:                      bool,
	enable_graphics_api_validation:         bool,
	enable_d3d12_draw_parameters_emulation: bool,
	enable_d3d11_command_buffer_emulation:  bool,
	disable_vk_ray_tracing:                 bool,
	disable3rd_party_allocation_callbacks:  bool,
}

Swapchain_Format :: enum u8 {
	BT709_G22_8BIT,
	BT709_G10_16BIT,
	BT709_G22_10BIT,
	BT2020_G2084_10BIT,
}

Windows_Window :: struct {
	hwnd: rawptr,
}

X11_Window :: struct {
	display: rawptr,
	window:  rawptr,
}

Wayland_Window :: struct {
	display: rawptr,
	surface: rawptr,
}

Cocoa_Window :: struct {
	ns_window: rawptr,
}

Window :: struct {
	windows: Windows_Window,
	x11:     X11_Window,
	wayland: Wayland_Window,
	cocoa:   Cocoa_Window,
}

Swapchain_Desc :: struct {
	window:        Window,
	command_queue: ^Command_Queue,
	size:          [2]dim,
	texture_num:   u8,
	format:        Swapchain_Format,
	// whether images are immediately presented
	immediate:     bool,
}

MAX_SWAPCHAIN_TEXTURES :: 3

Chromaticity_Coords :: struct {
	x, y: f32,
}

Display_Desc :: struct {
	red_primary:                  Chromaticity_Coords,
	green_primary:                Chromaticity_Coords,
	blue_primary:                 Chromaticity_Coords,
	white_point:                  Chromaticity_Coords,
	max_luminance, min_luminance: f32,
	max_full_frame_luminance:     f32,
	sdr_luminance:                f32,
	is_hdr:                       bool,
}

Swapchain :: struct {}

Swapchain_Interface :: struct {}

Format_Bits :: bit_field u64 {
	stride:        u8   | 6,
	block_width:   u8   | 4,
	block_height:  u8   | 4,
	is_bgr:        bool | 1,
	is_compressed: bool | 1,
	is_depth:      bool | 1,
	is_exp_shared: bool | 1,
	is_float:      bool | 1,
	is_packed:     bool | 1,
	is_integer:    bool | 1,
	is_norm:       bool | 1,
	is_signed:     bool | 1,
	is_srgb:       bool | 1,
	is_stencil:    bool | 1,
}

Format_Props :: struct {
	name:       string,
	format:     Format,
	red_bits:   u8,
	green_bits: u8,
	blue_bits:  u8,
	alpha_bits: u8,
	using _:    Format_Bits,
}

get_vendor_from_id :: proc(id: u32) -> Vendor {
	switch id {
	case 0x10DE:
		return .NVIDIA
	case 0x1002:
		return .AMD
	case 0x8086:
		return .INTEL
	case:
		return Vendor.UNKNOWN
	}
}

get_dimension_mip_adjusted :: proc(
	#by_ptr desc: Texture_Desc,
	dimension_index: u8,
	mip: mip,
) -> dim {
	dimension: dim = 0
	switch dimension_index {
	case 0:
		dimension = desc.width
	case 1:
		dimension = desc.height
	case 2:
		dimension = desc.depth
	}

	dimension = max(1, dimension >> mip)

	if dimension_index < 2 {
		block_width := FORMAT_PROPS[desc.format].block_width
		dimension = dim(mem.align_forward_int(int(dimension), int(block_width)))
	}

	return dimension
}
