package app

import "core:log"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:slice"
import "en:mercury"

Frame_Constants :: struct {
	view:       hlsl.float4x4,
	projection: hlsl.float4x4,
	padding0:   u64,
	padding1:   u64,
	padding2:   u64,
	padding3:   u64,
}

Draw_Data :: mercury.Draw_Indexed_Desc

Object_Data :: struct #align (1) {
	transform: hlsl.float4x4,
	geometry:  Geometry_Handle,
	material:  Material_Handle,
}

// Transform_Handle :: distinct u32
// Transform :: struct #align (1) {
// 	transform: hlsl.float4x4,
// 	geometry: Geometry_Handle,
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

Geometry_Handle :: distinct u32
Gpu_Geometry :: struct {
	vertex_offset: u32,
	vertex_count:  u32,
	index_offset:  u32,
	index_count:   u32,
}
Geometry :: struct {
	vertices: []Vertex_Default,
	indices:  []u16,
}

Material_Geometry_Pair :: struct {
	handle:   Geometry_Handle,
	material: Material_Handle,
}

INITIAL_GEOMETRY_COUNT :: 64
// INITIAL_INSTANCE_COUNT :: 256
INITIAL_MATERIAL_COUNT :: 32

DRAW_BATCH_COUNT :: 500_000
Draw_Batch_Readback :: u32

INITIAL_IMAGE_COUNT :: 64
MAX_IMAGES :: 1 << 13
Image_Handle :: distinct u32
WHITE_IMAGE_HANDLE :: Image_Handle(0)
BLACK_IMAGE_HANDLE :: Image_Handle(1)

Resource_Pool :: struct {
	frame_constants:               Frame_Constants,
	constant_buffer:               Ren_Buffer,
	mapped_constants:              ^Frame_Constants,
	// size is size_of(Draw_Batch_Readback) + DRAW_BATCH_COUNT * size_of(Frame_Constants)
	draw_argument_buffer:          Ren_Buffer,
	// size if DRAW_BATCH_COUNT * size_of(Object_Data)
	draw_objects_buffer:           Ren_Buffer,
	draw_count:                    u32,
	//
	//
	// instance_buffer:               Ren_Buffer,
	// cpu_instances:                 [dynamic]Instance,
	//
	geometry_buffer:               Ren_Buffer,
	cpu_geometries:                [dynamic]Gpu_Geometry,
	vertex_buffer:                 Ren_Buffer,
	index_buffer:                  Ren_Buffer,
	//
	material_buffer:               Ren_Buffer,
	free_materials:                [dynamic]uint,
	sampler:                       ^mercury.Descriptor,
	white_texture:                 Texture,
	black_texture:                 Texture,
	texture_descriptors:           [dynamic]^mercury.Descriptor,
	free_texture_descriptors:      [dynamic]uint,
	//
	draw_constants_descriptor_set: ^mercury.Descriptor_Set,
	resource_descriptor_set:       ^mercury.Descriptor_Set,
	gpu_draw_descriptor_set:       ^mercury.Descriptor_Set,
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
		resource_pool_resource_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.resource_descriptor_set = set
	}

	if set, error := renderer.instance->allocate_descriptor_set(
		renderer.descriptor_pool,
		resource_pool_frame_constants_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.draw_constants_descriptor_set = set
	}

	if set, error := renderer.instance->allocate_descriptor_set(
		renderer.descriptor_pool,
		resource_pool_draws_descriptor_desc(0, {.Compute_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.gpu_draw_descriptor_set = set
	}

	pool.constant_buffer.name = "Draw constants"
	pool.constant_buffer.desc.location = .Host_Upload
	pool.constant_buffer.desc.usage = {.Constant_Buffer}
	pool.constant_buffer.desc.size = u64(mem.align_forward_int(size_of(Frame_Constants), 256))
	if error := init_ren_buffer(&pool.constant_buffer, renderer); error != nil {
		log.errorf("Could not create draw constants buffer: {}", error)
		ok = false
		return
	}

	renderer.instance->update_descriptor_ranges(
		pool.draw_constants_descriptor_set,
		0,
		{{descriptors = {pool.constant_buffer.cbv}}},
	)
	mapped, error_map := renderer.instance->map_buffer(
		pool.constant_buffer.buffer,
		0,
		size_of(Frame_Constants),
	)
	if error_map != nil {
		log.errorf("Could not map draw buffer {}", error_map)
		ok = false
		return
	}
	pool.mapped_constants = auto_cast raw_data(mapped)

	pool.draw_argument_buffer.name = "Draw Arguments buffer"
	pool.draw_argument_buffer.desc.location = .Device
	pool.draw_argument_buffer.desc.usage = {.Argument_Buffer, .Shader_Resource_Storage}
	pool.draw_argument_buffer.desc.size = u64(
		mem.align_forward_int(
			size_of(Draw_Batch_Readback) + DRAW_BATCH_COUNT * size_of(Frame_Constants),
			256,
		),
	)
	if error_init_draws := init_ren_buffer(&pool.draw_argument_buffer, renderer);
	   error_init_draws != nil {
		log.errorf("Could not create draws buffer: {}", error_init_draws)
		ok = false
		return
	}

	pool.draw_objects_buffer.name = "Draw Objects buffer"
	pool.draw_objects_buffer.desc.location = .Host_Upload
	pool.draw_objects_buffer.desc.usage = {.Shader_Resource}
	pool.draw_objects_buffer.desc.size = u64(
		mem.align_forward_int(DRAW_BATCH_COUNT * size_of(Object_Data), 256),
	)
	if error_init_objects := init_ren_buffer(&pool.draw_objects_buffer, renderer);
	   error_init_objects != nil {
		log.errorf("Could not create objects buffer: {}", error_init_objects)
		ok = false
		return
	}

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

	pool.geometry_buffer.name = "Geometry buffer"
	pool.geometry_buffer.desc.location = .Device
	pool.geometry_buffer.desc.usage = {.Shader_Resource}
	pool.geometry_buffer.desc.structure_stride = size_of(Gpu_Geometry)
	pool.geometry_buffer.desc.size = size_of(Gpu_Geometry) * INITIAL_GEOMETRY_COUNT
	if error_init_geometry := init_ren_buffer(&pool.geometry_buffer, renderer);
	   error_init_geometry != nil {
		log.errorf(
			"Could not create geometry buffer with {} geometrys: {}",
			INITIAL_GEOMETRY_COUNT,
			error_init_geometry,
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
		pool.gpu_draw_descriptor_set,
		0,
		{
			{descriptors = {pool.draw_argument_buffer.uav}},
			{descriptors = {pool.draw_objects_buffer.srv}},
			{descriptors = {pool.geometry_buffer.srv}},
		},
	)

	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		0,
		{
			{descriptors = {pool.draw_objects_buffer.srv}},
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
	deinit_ren_buffer(&pool.geometry_buffer, renderer)
	delete(pool.cpu_geometries)
	// deinit_ren_buffer(&pool.instance_buffer, renderer)
	// delete(pool.cpu_instances)
	deinit_ren_buffer(&pool.draw_argument_buffer, renderer)
	deinit_ren_buffer(&pool.draw_objects_buffer, renderer)
	deinit_ren_buffer(&pool.constant_buffer, renderer)
}

copy_frame_constants :: proc(pool: ^Resource_Pool) {
	pool.mapped_constants^ = pool.frame_constants
}

resource_pool_frame_constants_descriptor_desc :: proc(
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

resource_pool_resource_descriptor_desc :: proc(
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

resource_pool_draws_descriptor_desc :: proc(
	register_space: u32,
	stages: mercury.Stage_Flags,
) -> mercury.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges         = slice.clone(
			[]mercury.Descriptor_Range_Desc {
				// draws themselves
				mercury.buffer_range(0, 1, stages = stages, writable = true),
				// instances
				mercury.buffer_range(1, 1, stages = stages),
				// geometry
				mercury.buffer_range(2, 1, stages = stages),
			},
			context.temp_allocator,
		),
	}
}

resource_pool_add_texture :: proc(
	renderer: ^Renderer,
	texture: ^mercury.Descriptor,
) -> (
	handle: Image_Handle,
	ok: bool = true,
) {
	pool := &renderer.resource_pool
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
resource_pool_remove_texture :: proc(renderer: ^Renderer, handle: Image_Handle) {
	if handle == WHITE_IMAGE_HANDLE || handle == BLACK_IMAGE_HANDLE {
		return
	}

	pool := &renderer.resource_pool
	append(&pool.free_texture_descriptors, uint(handle))
	renderer.instance->update_descriptor_ranges(
		pool.resource_descriptor_set,
		3, // texture range
		{{descriptors = {pool.white_texture.srv}, base_descriptor = u32(WHITE_IMAGE_HANDLE)}},
	)
}

resource_pool_clear_textures :: proc(renderer: ^Renderer) {
	pool := &renderer.resource_pool
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
	renderer: ^Renderer,
	material: Material,
) -> (
	handle: Material_Handle,
	ok: bool = true,
) {
	pool := &renderer.resource_pool
	material := material
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.free_materials); !pop_ok {
		pos = uint(pool.material_buffer.len)

		old_srv := pool.material_buffer.srv
		defer if pool.material_buffer.srv != old_srv {
			renderer.instance->update_descriptor_ranges(
				pool.resource_descriptor_set,
				1, // material range
				{{descriptors = {pool.material_buffer.srv}}},
			)
		}

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

resource_pool_remove_material :: proc(renderer: ^Renderer, handle: Material_Handle) {
	pool := &renderer.resource_pool
	append(&pool.free_materials, uint(handle))
}

resource_pool_clear_materials :: proc(renderer: ^Renderer) {
	pool := &renderer.resource_pool
	pool.material_buffer.len = 0
}

resource_pool_set_material :: proc(
	renderer: ^Renderer,
	handle: Material_Handle,
	material: Material,
) -> (
	ok: bool = true,
) {
	pool := &renderer.resource_pool
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

resource_pool_add_geometry :: proc(
	renderer: ^Renderer,
	geometry: Geometry,
) -> (
	handle: Geometry_Handle,
	ok: bool = true,
) {
	pool := &renderer.resource_pool
	geometry := geometry
	vertex_offset := pool.vertex_buffer.len / size_of(Vertex_Default)
	index_offset := pool.index_buffer.len / size_of(u16)

	if err_vertex := ren_buffer_append(
		&pool.vertex_buffer,
		slice.to_bytes(geometry.vertices),
		mercury.ACCESS_STAGE_VERTEX_BUFFER,
		renderer,
	); err_vertex != nil {
		ok = false
		log.infof("Could not append vertex buffer: {}", err_vertex)
		return
	}
	if err_index := ren_buffer_append(
		&pool.index_buffer,
		slice.to_bytes(geometry.indices),
		mercury.ACCESS_STAGE_INDEX_BUFFER,
		renderer,
	); err_index != nil {
		ok = false
		log.infof("Could not append index buffer: {}", err_index)
		return
	}

	gpu_geometry: Gpu_Geometry
	gpu_geometry.vertex_count = u32(len(geometry.vertices))
	gpu_geometry.vertex_offset = u32(vertex_offset)
	gpu_geometry.index_count = u32(len(geometry.indices))
	gpu_geometry.index_offset = u32(index_offset)

	olf_srv := pool.geometry_buffer.srv
	defer if pool.geometry_buffer.srv != olf_srv {
		renderer.instance->update_descriptor_ranges(
			pool.gpu_draw_descriptor_set,
			2, // geometry range
			{{descriptors = {pool.geometry_buffer.srv}}},
		)
	}

	len := len(pool.cpu_geometries)
	if err := ren_buffer_append(
		&pool.geometry_buffer,
		slice.bytes_from_ptr(&gpu_geometry, size_of(Gpu_Geometry)),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	); err != nil {
		ok = false
		return
	}

	append(&pool.cpu_geometries, gpu_geometry)

	handle = Geometry_Handle(len)
	log.infof("geometry handle: {}", handle)
	return
}

resource_pool_clear_geometries :: proc(renderer: ^Renderer) {
	pool := &renderer.resource_pool
	pool.vertex_buffer.len = 0
	pool.index_buffer.len = 0
	pool.geometry_buffer.len = 0
	clear(&pool.cpu_geometries)
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
// 		&pool.geometry_buffer,
// 		slice.bytes_from_ptr(&mesh, size_of(Mesh)),
// 		size_of(mesh) * u64(handle),
// 		mercury.ACCESS_STAGE_SHADER_RESOURCE,
// 		renderer,
// 	)

// 	return
// }

resource_pool_get_object_count :: proc(renderer: ^Renderer) -> (count: u32) {
	pool := &renderer.resource_pool
	return pool.draw_count
}

resource_pool_reset_objects :: proc(renderer: ^Renderer) {
	pool := &renderer.resource_pool
	pool.draw_count = 0
	pool.draw_objects_buffer.len = 0
}

Object_Add_Result :: enum {
	Ok,
	Full,
	Other,
}

resource_pool_add_object :: proc(
	renderer: ^Renderer,
	data: ..Object_Data,
) -> (
	result: Object_Add_Result,
) {
	data := data
	pool := &renderer.resource_pool
	if pool.draw_count + u32(len(data)) > DRAW_BATCH_COUNT {
		return .Full
	}

	old_srv := pool.draw_objects_buffer.srv
	old_uav := pool.draw_objects_buffer.uav

	log.infof("data len: {}", len(slice.to_bytes(data)))

	if err := ren_buffer_append(
		&pool.draw_objects_buffer,
		slice.to_bytes(data),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	); err != nil {
		log.errorf("Could not append draw: {}", err)
		return .Other
	}
	pool.draw_count += u32(len(data))

	if pool.draw_objects_buffer.srv != old_srv {
		renderer.instance->update_descriptor_ranges(
			pool.resource_descriptor_set,
			0, // instance range
			{{descriptors = {pool.draw_objects_buffer.srv}}},
		)
	}

	if pool.draw_objects_buffer.uav != old_uav {
		renderer.instance->update_descriptor_ranges(
			pool.gpu_draw_descriptor_set,
			1, // instance range
			{{descriptors = {pool.draw_objects_buffer.uav}}},
		)
	}

	return .Ok
}

render_components_descriptor_requirements: mercury.Descriptor_Pool_Desc : {
	descriptor_set_max_num = 3,
	constant_buffer_max_num = 1,
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 5,
}

render_components_resource_requirements: mercury.Resource_Requirements : {
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 5,
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
