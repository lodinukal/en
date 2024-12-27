package app

import "core:log"
import "core:math/linalg/hlsl"
import "en:gpu"

Instance_Handle :: distinct u32
Instance :: struct {
	transform: hlsl.float4x4,
	mesh:      Mesh_Handle,
	material:  Material_Handle,
}

Mesh_Handle :: distinct u32
Mesh :: struct {
	base_vertex:  u32,
	vertex_count: u32,
	base_index:   u32,
	index_count:  u32,
}

Material_Handle :: distinct u32
Material :: struct {
	base_color:         hlsl.float4,
	albedo:             Image_Handle,
	normal:             Image_Handle,
	metallic_roughness: Image_Handle,
	emissive:           Image_Handle,
}

MAX_IMAGES :: 1 << 12
Image_Handle :: distinct u32
WHITE_IMAGE_HANDLE :: 0
BLACK_IMAGE_HANDLE :: 1

Image_Pool :: struct {
	white_texture:           Texture,
	black_texture:           Texture,
	descriptors:             [dynamic]^gpu.Descriptor,
	sampler:                 ^gpu.Descriptor,
	graphics_descriptor_set: ^gpu.Descriptor_Set,
}

init_image_pool :: proc(pool: ^Image_Pool, renderer: ^Renderer) -> (ok: bool = true) {
	reserve_err := reserve(&pool.descriptors, 3)
	if reserve_err != nil {
		log.errorf("Could not reserve descriptors: {}", reserve_err)
		ok = false
		return
	}

	if set, error := renderer.instance->allocate_descriptor_set(
		renderer.descriptor_pool,
		image_pool_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.graphics_descriptor_set = set
	}

	default_texture_desc: gpu.Texture_Desc
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
	if err := init_texture(&white_texture, renderer); err != nil {
		log.errorf("Could not init white texture: {}", err)
		ok = false
		return
	}

	black_texture: Texture
	black_texture.desc = default_texture_desc
	black_texture.name = "black"
	if err := init_texture(&black_texture, renderer); err != nil {
		log.errorf("Could not init black texture: {}", err)
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

	if err := texture_upload(
		&white_texture,
		renderer,
		{subresource_upload_white},
		gpu.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err != nil {
		log.errorf("Could not upload white texture: {}", err)
		ok = false
		return
	}

	if err := texture_upload(
		&black_texture,
		renderer,
		{subresource_upload_black},
		gpu.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err != nil {
		log.errorf("Could not upload black texture: {}", err)
		ok = false
		return
	}

	pool.white_texture = white_texture
	pool.black_texture = black_texture

	append(&pool.descriptors, white_texture.srv)
	append(&pool.descriptors, black_texture.srv)

	sampler, sampler_err := renderer.instance->create_sampler(renderer.device, {})
	if sampler_err != nil {
		log.errorf("Could not create sampler: {}", sampler_err)
		ok = false
		return
	}
	pool.sampler = sampler

	renderer.instance->update_descriptor_ranges(
		pool.graphics_descriptor_set,
		0,
		{{descriptors = {sampler}}, {descriptors = pool.descriptors[:]}},
	)

	return
}

destroy_image_pool :: proc(pool: ^Image_Pool, renderer: ^Renderer) {
	renderer.instance->destroy_descriptor(renderer.device, pool.sampler)
	delete(pool.descriptors)
	destroy_texture(&pool.white_texture, renderer)
	destroy_texture(&pool.black_texture, renderer)
}

image_pool_descriptor_desc :: proc(
	register_space: u32,
	stages: gpu.Stage_Flags,
) -> gpu.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges = {
			gpu.sampler_range(stages = stages),
			gpu.buffer_range(1, MAX_IMAGES, partial = true, stages = stages),
		},
	}
}

image_pool_descriptor_requirements: gpu.Descriptor_Pool_Desc : {
	descriptor_set_max_num = 1,
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
}

render_components_descriptor_requirements :: proc() -> gpu.Descriptor_Pool_Desc {
	accumulating: gpu.Descriptor_Pool_Desc
	accumulating = combine_pool_descs(accumulating, image_pool_descriptor_requirements)
	return accumulating
}

combine_pool_descs :: proc(a, b: gpu.Descriptor_Pool_Desc) -> gpu.Descriptor_Pool_Desc {
	return {
		descriptor_set_max_num = a.descriptor_set_max_num + b.descriptor_set_max_num,
		sampler_max_num = a.sampler_max_num + b.sampler_max_num,
		constant_buffer_max_num = a.constant_buffer_max_num + b.constant_buffer_max_num,
		texture_max_num = a.texture_max_num + b.texture_max_num,
		storage_texture_max_num = a.storage_texture_max_num + b.storage_texture_max_num,
		buffer_max_num = a.buffer_max_num + b.buffer_max_num,
		storage_buffer_max_num = a.storage_buffer_max_num + b.storage_buffer_max_num,
		structured_buffer_max_num = a.structured_buffer_max_num + b.structured_buffer_max_num,
		storage_structured_buffer_max_num = a.storage_structured_buffer_max_num +
		b.storage_structured_buffer_max_num,
		acceleration_structure_max_num = a.acceleration_structure_max_num +
		b.acceleration_structure_max_num,
	}
}
