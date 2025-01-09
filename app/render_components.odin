package app

import "core:log"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:slice"
import "en:mercury"

Draw_Data :: struct {
	view:       hlsl.float4x4,
	projection: hlsl.float4x4,
	padding0:   u64,
	padding1:   u64,
	padding2:   u64,
	padding3:   u64,
}

Object_Data :: struct #align (1) {
	transform: hlsl.float4x4,
	primitive: Primitive_Handle,
	material:  Material_Handle,
}

// Transform_Handle :: distinct u32
// Transform :: struct #align (1) {
// 	transform: hlsl.float4x4,
// 	primitive: Primitive_Handle,
// 	material:  Material_Handle,
// }

Material_Handle :: distinct u32
Material :: struct {
	base_color:         hlsl.float4,
	albedo:             Image_Handle,
	normal:             Image_Handle,
	metallic_roughness: Image_Handle,
	emissive:           Image_Handle,
}

Primitive_Handle :: distinct u32
Gpu_Primitive :: struct {
	index_count:   u32,
	index_offset:  u32,
	vertex_count:  u32,
	vertex_offset: u32,
}
Primitive :: struct {
	vertices: []Vertex_Default,
	indices:  []u16,
}

Geometry :: struct {
	handle:   Primitive_Handle,
	material: Material_Handle,
}

INITIAL_PRIMITIVE_COUNT :: 64
// INITIAL_INSTANCE_COUNT :: 256
INITIAL_MATERIAL_COUNT :: 32

INITIAL_IMAGE_COUNT :: 64
MAX_IMAGES :: 1 << 13
Image_Handle :: distinct u32
WHITE_IMAGE_HANDLE :: Image_Handle(0)
BLACK_IMAGE_HANDLE :: Image_Handle(1)

Resource_Pool :: struct {
	draws:                         Draw_Data,
	draw_buffer:                   Resizable_Buffer,
	draw_mapped:                   ^Draw_Data,
	//
	// instance_buffer:               Resizable_Buffer,
	// cpu_instances:                 [dynamic]Instance,
	//
	primitive_buffer:              Resizable_Buffer,
	cpu_primitives:                [dynamic]Gpu_Primitive,
	vertex_buffer:                 Resizable_Buffer,
	index_buffer:                  Resizable_Buffer,
	//
	material_buffer:               Resizable_Buffer,
	free_materials:                [dynamic]uint,
	sampler:                       ^mercury.Descriptor,
	white_texture:                 Texture,
	black_texture:                 Texture,
	texture_descriptors:           [dynamic]^mercury.Descriptor,
	free_texture_descriptors:      [dynamic]uint,
	//
	draw_constants_descriptor_set: ^mercury.Descriptor_Set,
	resource_descriptor_set:       ^mercury.Descriptor_Set,
}

init_resource_pool :: proc(pool: ^Resource_Pool, renderer: ^Renderer) -> (ok: bool = true) {
	reserve_err := reserve(&pool.texture_descriptors, INITIAL_IMAGE_COUNT)
	if reserve_err != nil {
		log.errorf("Could not reserve texture descriptors: {}", reserve_err)
		ok = false
		return
	}

	if set, error := renderer.instance->allocate_descriptor_set(
		renderer.descriptor_pool,
		resource_pool_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.resource_descriptor_set = set
	}

	if set, error := renderer.instance->allocate_descriptor_set(
		renderer.descriptor_pool,
		resource_pool_draws_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.draw_constants_descriptor_set = set
	}

	pool.draw_buffer.name = "Draw constants"
	pool.draw_buffer.desc.location = .Host_Upload
	pool.draw_buffer.desc.usage = {.Constant_Buffer}
	pool.draw_buffer.desc.size = u64(mem.align_forward_int(size_of(Draw_Data), 256))
	if error := init_ren_buffer(&pool.draw_buffer, renderer); error != nil {
		log.errorf("Could not create draw constants buffer: {}", error)
		ok = false
		return
	}

	renderer.instance->update_descriptor_ranges(
		pool.draw_constants_descriptor_set,
		0,
		{{descriptors = {pool.draw_buffer.cbv}}},
	)
	mapped, error_map := renderer.instance->map_buffer(
		pool.draw_buffer.buffer,
		0,
		size_of(Draw_Data),
	)
	if error_map != nil {
		log.errorf("Could not map draw buffer {}", error_map)
		ok = false
		return
	}
	pool.draw_mapped = auto_cast raw_data(mapped)

	// pool.instance_buffer.name = "Instance buffer"
	// pool.instance_buffer.desc.location = .Device
	// pool.instance_buffer.desc.usage = {.Shader_Resource}
	// pool.instance_buffer.desc.structure_stride = size_of(Instance)
	// pool.instance_buffer.desc.size = size_of(Instance) * INITIAL_INSTANCE_COUNT
	// if error_init_instance := init_ren_buffer(&pool.instance_buffer, renderer);
	//    error_init_instance != nil {
	// 	log.errorf(
	// 		"Could not create instance buffer with {} instances: {}",
	// 		INITIAL_INSTANCE_COUNT,
	// 		error_init_instance,
	// 	)
	// 	ok = false
	// 	return
	// }

	pool.primitive_buffer.name = "Primitive buffer"
	pool.primitive_buffer.desc.location = .Device
	pool.primitive_buffer.desc.usage = {.Shader_Resource}
	pool.primitive_buffer.desc.structure_stride = size_of(Gpu_Primitive)
	pool.primitive_buffer.desc.size = size_of(Gpu_Primitive) * INITIAL_PRIMITIVE_COUNT
	if error_init_primitive := init_ren_buffer(&pool.primitive_buffer, renderer);
	   error_init_primitive != nil {
		log.errorf(
			"Could not create primitive buffer with {} primitives: {}",
			INITIAL_PRIMITIVE_COUNT,
			error_init_primitive,
		)
		ok = false
		return
	}

	pool.vertex_buffer.name = "Vertex buffer"
	pool.vertex_buffer.desc.location = .Device
	pool.vertex_buffer.desc.usage = {.Vertex_Buffer}
	pool.vertex_buffer.desc.size = 0
	if error_init_vertex := init_ren_buffer(&pool.vertex_buffer, renderer);
	   error_init_vertex != nil {
		log.errorf("Could not create vertex buffer: {}", error_init_vertex)
		ok = false
		return
	}

	pool.index_buffer.name = "Index buffer"
	pool.index_buffer.desc.location = .Device
	pool.index_buffer.desc.usage = {.Index_Buffer}
	pool.index_buffer.desc.size = 0
	if error_init_index := init_ren_buffer(&pool.index_buffer, renderer); error_init_index != nil {
		log.errorf("Could not create index buffer: {}", error_init_index)
		ok = false
		return
	}

	pool.material_buffer.name = "Material buffer"
	pool.material_buffer.desc.location = .Device
	pool.material_buffer.desc.usage = {.Shader_Resource}
	pool.material_buffer.desc.structure_stride = size_of(Material)
	pool.material_buffer.desc.size = size_of(Material) * INITIAL_MATERIAL_COUNT
	if error_init_material := init_ren_buffer(&pool.material_buffer, renderer);
	   error_init_material != nil {
		log.errorf(
			"Could not create material buffer with {} materials: {}",
			INITIAL_MATERIAL_COUNT,
			error_init_material,
		)
		ok = false
		return
	}

	default_texture_desc: mercury.Texture_Desc
	default_texture_desc.type = ._2D
	default_texture_desc.layer_num = 1
	default_texture_desc.mip_num = 1
	default_texture_desc.format = .RGBA8_UNORM
	default_texture_desc.usage = {.Shader_Resource}
	default_texture_desc.width = 1
	default_texture_desc.height = 1

	white_texture: Texture
	white_texture.desc = default_texture_desc
	white_texture.name = "white"
	if error_init_white_tex := init_ren_texture(&white_texture, renderer);
	   error_init_white_tex != nil {
		log.errorf("Could not init white texture: {}", error_init_white_tex)
		ok = false
		return
	}

	black_texture: Texture
	black_texture.desc = default_texture_desc
	black_texture.name = "black"
	if error_init_black_tex := init_ren_texture(&black_texture, renderer);
	   error_init_black_tex != nil {
		log.errorf("Could not init black texture: {}", error_init_black_tex)
		ok = false
		return
	}

	white_data: [4]u8 = {255, 255, 255, 255}
	black_data: [4]u8 = {0, 0, 0, 255}
	row_pitch, slice_pitch := compute_pitch(
		.RGBA8_UNORM,
		u32(default_texture_desc.width),
		u32(default_texture_desc.height),
	)

	subresource_upload_white: Texture_Subresource_Upload_Desc
	subresource_upload_white.slices = auto_cast &white_data
	subresource_upload_white.slice_num = 1
	subresource_upload_white.row_pitch = row_pitch
	subresource_upload_white.slice_pitch = slice_pitch

	subresource_upload_black: Texture_Subresource_Upload_Desc
	subresource_upload_black.slices = auto_cast &black_data
	subresource_upload_black.slice_num = 1
	subresource_upload_black.row_pitch = row_pitch
	subresource_upload_black.slice_pitch = slice_pitch

	if err_upload_white := ren_texture_upload(
		&white_texture,
		renderer,
		{subresource_upload_white},
		mercury.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err_upload_white != nil {
		log.errorf("Could not upload white texture: {}", err_upload_white)
		ok = false
		return
	}

	if err_upload_black := ren_texture_upload(
		&black_texture,
		renderer,
		{subresource_upload_black},
		mercury.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err_upload_black != nil {
		log.errorf("Could not upload black texture: {}", err_upload_black)
		ok = false
		return
	}

	pool.white_texture = white_texture
	pool.black_texture = black_texture

	append(&pool.texture_descriptors, white_texture.srv)
	append(&pool.texture_descriptors, black_texture.srv)

	sampler, error_sampler := renderer.instance->create_sampler(renderer.device, {})
	if error_sampler != nil {
		log.errorf("Could not create sampler: {}", error_sampler)
		ok = false
		return
	}
	pool.sampler = sampler

	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		0,
		{
			// {descriptors = {pool.instance_buffer.srv}},
			{descriptors = {pool.primitive_buffer.srv}},
			{descriptors = {pool.material_buffer.srv}},
			{descriptors = {sampler}},
			{descriptors = pool.texture_descriptors[:]},
		},
	)

	return
}

destroy_resource_pool :: proc(pool: ^Resource_Pool, renderer: ^Renderer) {
	renderer.instance->destroy_descriptor(renderer.device, pool.sampler)
	delete(pool.texture_descriptors)
	delete(pool.free_texture_descriptors)
	deinit_ren_texture(&pool.white_texture, renderer)
	deinit_ren_texture(&pool.black_texture, renderer)
	deinit_ren_buffer(&pool.material_buffer, renderer)
	delete(pool.free_materials)
	deinit_ren_buffer(&pool.index_buffer, renderer)
	deinit_ren_buffer(&pool.vertex_buffer, renderer)
	deinit_ren_buffer(&pool.primitive_buffer, renderer)
	delete(pool.cpu_primitives)
	// deinit_ren_buffer(&pool.instance_buffer, renderer)
	// delete(pool.cpu_instances)
	deinit_ren_buffer(&pool.draw_buffer, renderer)
}

copy_draw_data :: proc(pool: ^Resource_Pool) {
	pool.draw_mapped^ = pool.draws
}

resource_pool_draws_descriptor_desc :: proc(
	register_space: u32,
	stages: mercury.Stage_Flags,
) -> mercury.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges = slice.clone(
			[]mercury.Descriptor_Range_Desc{mercury.constant_buffer(0, stages = stages)},
			context.temp_allocator,
		),
	}
}

resource_pool_descriptor_desc :: proc(
	register_space: u32,
	stages: mercury.Stage_Flags,
) -> mercury.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges = slice.clone(
			[]mercury.Descriptor_Range_Desc {
				mercury.buffer_range(0, 1, stages = stages),
				mercury.buffer_range(1, 1, stages = stages),
				mercury.sampler_range(2, 1, stages = stages),
				mercury.texture_range(3, MAX_IMAGES, partial = true, stages = stages),
			},
			context.temp_allocator,
		),
	}
}

resource_pool_add_texture :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	texture: ^mercury.Descriptor,
) -> (
	handle: Image_Handle,
	ok: bool = true,
) {
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.free_texture_descriptors); !pop_ok {
		pos = len(pool.texture_descriptors)
		_, err := append(&pool.texture_descriptors, texture)
		if err != nil {
			ok = false
			return
		}
	}

	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		3, // texture range
		{{descriptors = {texture}, base_descriptor = u32(pos)}},
	)
	handle = Image_Handle(pos)
	log.infof("handle: {}", handle)
	return
}

// removes a texture, sets it to the white texture
resource_pool_remove_texture :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	handle: Image_Handle,
) {
	if handle == WHITE_IMAGE_HANDLE || handle == BLACK_IMAGE_HANDLE {
		return
	}

	append(&pool.free_texture_descriptors, uint(handle))
	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		3, // texture range
		{{descriptors = {pool.white_texture.srv}, base_descriptor = u32(WHITE_IMAGE_HANDLE)}},
	)
}

resource_pool_clear_textures :: proc(pool: ^Resource_Pool, renderer: ^Renderer) {
	for &d in pool.texture_descriptors {
		d = nil
	}
	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		3, // texture range
		{{descriptors = pool.texture_descriptors[:]}},
	)
	clear(&pool.texture_descriptors)
}

resource_pool_add_material :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	material: Material,
) -> (
	handle: Material_Handle,
	ok: bool = true,
) {
	material := material
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.free_materials); !pop_ok {
		pos = uint(pool.material_buffer.len)
		err := ren_buffer_append(
			&pool.material_buffer,
			slice.bytes_from_ptr(&material, size_of(Material)),
			mercury.ACCESS_STAGE_SHADER_RESOURCE,
			renderer,
		)
		if err != nil {
			ok = false
			return
		}
	} else {
		ren_buffer_set(
			&pool.material_buffer,
			slice.bytes_from_ptr(&material, size_of(Material)),
			size_of(Material) * u64(pos),
			mercury.ACCESS_STAGE_SHADER_RESOURCE,
			renderer,
		)
	}

	handle = Material_Handle(pos)
	log.infof("material handle: {}", handle)
	return
}

resource_pool_remove_material :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	handle: Material_Handle,
) {
	append(&pool.free_materials, uint(handle))
}

resource_pool_clear_materials :: proc(pool: ^Resource_Pool) {
	pool.material_buffer.len = 0
}

resource_pool_set_material :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	handle: Material_Handle,
	material: Material,
) -> (
	ok: bool = true,
) {
	material := material
	ren_buffer_set(
		&pool.material_buffer,
		slice.bytes_from_ptr(&material, size_of(Material)),
		size_of(Material) * u64(handle),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	)

	return
}

// resource_pool_add_instance :: proc(
// 	pool: ^Resource_Pool,
// 	renderer: ^Renderer,
// 	instance: Instance,
// ) -> (
// 	handle: Instance_Handle,
// 	ok: bool = true,
// ) {
// 	instance := instance
// 	len := len(pool.cpu_instances)
// 	err := ren_buffer_append(
// 		&pool.instance_buffer,
// 		slice.bytes_from_ptr(&instance, size_of(Instance)),
// 		mercury.ACCESS_STAGE_SHADER_RESOURCE,
// 		renderer,
// 	)
// 	if err != nil {
// 		ok = false
// 		return
// 	}

// 	append(&pool.cpu_instances, instance)

// 	handle = Instance_Handle(len)
// 	log.infof("instance handle: {}", handle)
// 	return
// }

// resource_pool_clear_instances :: proc(pool: ^Resource_Pool) {
// 	pool.instance_buffer.len = 0
// 	clear(&pool.cpu_instances)
// }

// resource_pool_set_instance :: proc(
// 	pool: ^Resource_Pool,
// 	renderer: ^Renderer,
// 	handle: Instance_Handle,
// 	instance: Instance,
// ) -> (
// 	ok: bool = true,
// ) {
// 	instance := instance
// 	ren_buffer_set(
// 		&pool.instance_buffer,
// 		slice.bytes_from_ptr(&instance, size_of(Instance)),
// 		size_of(instance) * u64(handle),
// 		mercury.ACCESS_STAGE_SHADER_RESOURCE,
// 		renderer,
// 	)

// 	return
// }

resource_pool_add_primitive :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	primitive: Primitive,
) -> (
	handle: Primitive_Handle,
	ok: bool = true,
) {
	primitive := primitive
	vertex_offset := pool.vertex_buffer.len / size_of(Vertex_Default)
	index_offset := pool.index_buffer.len / size_of(u16)

	if err_vertex := ren_buffer_append(
		&pool.vertex_buffer,
		slice.to_bytes(primitive.vertices),
		mercury.ACCESS_STAGE_VERTEX_BUFFER,
		renderer,
	); err_vertex != nil {
		ok = false
		log.infof("Could not append vertex buffer: {}", err_vertex)
		return
	}
	if err_index := ren_buffer_append(
		&pool.index_buffer,
		slice.to_bytes(primitive.indices),
		mercury.ACCESS_STAGE_INDEX_BUFFER,
		renderer,
	); err_index != nil {
		ok = false
		log.infof("Could not append index buffer: {}", err_index)
		return
	}

	gpu_primitive: Gpu_Primitive
	gpu_primitive.vertex_count = u32(len(primitive.vertices))
	gpu_primitive.vertex_offset = u32(vertex_offset)
	gpu_primitive.index_count = u32(len(primitive.indices))
	gpu_primitive.index_offset = u32(index_offset)

	len := len(pool.cpu_primitives)
	if err := ren_buffer_append(
		&pool.primitive_buffer,
		slice.bytes_from_ptr(&gpu_primitive, size_of(Gpu_Primitive)),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	); err != nil {
		ok = false
		return
	}

	append(&pool.cpu_primitives, gpu_primitive)

	handle = Primitive_Handle(len)
	log.infof("primitive handle: {}", handle)
	return
}

resource_pool_clear_primitives :: proc(pool: ^Resource_Pool) {
	pool.vertex_buffer.len = 0
	pool.index_buffer.len = 0
	pool.primitive_buffer.len = 0
	clear(&pool.cpu_primitives)
}

// resource_pool_set_mesh :: proc(
// 	pool: ^Resource_Pool,
// 	renderer: ^Renderer,
// 	handle: Mesh_Handle,
// 	mesh: Mesh,
// ) -> (
// 	ok: bool = true,
// ) {
// 	mesh := mesh
// 	ren_buffer_set(
// 		&pool.primitive_buffer,
// 		slice.bytes_from_ptr(&mesh, size_of(Mesh)),
// 		size_of(mesh) * u64(handle),
// 		mercury.ACCESS_STAGE_SHADER_RESOURCE,
// 		renderer,
// 	)

// 	return
// }

render_components_descriptor_requirements: mercury.Descriptor_Pool_Desc : {
	descriptor_set_max_num = 2,
	constant_buffer_max_num = 1,
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 3,
}

render_components_resource_requirements: mercury.Resource_Requirements : {
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 4,
	render_target_max_num = 4,
	depth_stencil_target_max_num = 4,
}

Vertex_Default :: struct {
	position: hlsl.float3,
	normal:   hlsl.float3,
	texcoord: hlsl.float2,
}

VERTEX_INPUT_DEFAULT := mercury.Vertex_Input_Desc {
	attributes = {
		{
			d3d_semantic = "POSITION",
			vk_location = 0,
			offset = u32(offset_of(Vertex_Default, position)),
			format = .RGB32_SFLOAT,
			stream_index = 0,
		},
		{
			d3d_semantic = "NORMAL",
			vk_location = 1,
			offset = u32(offset_of(Vertex_Default, normal)),
			format = .RGB32_SFLOAT,
			stream_index = 0,
		},
		{
			d3d_semantic = "TEXCOORD",
			vk_location = 2,
			offset = u32(offset_of(Vertex_Default, texcoord)),
			format = .RG32_SFLOAT,
			stream_index = 0,
		},
	},
	streams    = {{stride = size_of(Vertex_Default), binding_slot = 0, step_rate = .Per_Vertex}},
}
