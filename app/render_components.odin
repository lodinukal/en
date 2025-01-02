package app

import "core:log"
import "core:math/linalg/hlsl"
import "core:slice"
import "en:gpu"

Draw_Constants :: struct {
	material_index:  u32,
	transform_index: u32,
	vertex_offset:   u32,
}

Transform_Handle :: distinct u32
Transform :: hlsl.float4x4

Material_Handle :: distinct u32
Material :: struct {
	base_color:         hlsl.float4,
	albedo:             Image_Handle,
	normal:             Image_Handle,
	metallic_roughness: Image_Handle,
	emissive:           Image_Handle,
}

INITIAL_TRANSFORM_COUNT :: 256
INITIAL_MATERIAL_COUNT :: 32

INITIAL_IMAGE_COUNT :: 64
MAX_IMAGES :: 1 << 13
Image_Handle :: distinct u32
WHITE_IMAGE_HANDLE :: Image_Handle(0)
BLACK_IMAGE_HANDLE :: Image_Handle(1)

Resource_Pool :: struct {
	draw_buffer:             Resizable_Buffer,
	//
	transform_buffer:        Resizable_Buffer,
	material_buffer:         Resizable_Buffer,
	sampler:                 ^gpu.Descriptor,
	white_texture:           Texture,
	black_texture:           Texture,
	texture_descriptors:     [dynamic]^gpu.Descriptor,
	//
	graphics_descriptor_set: ^gpu.Descriptor_Set,
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
		pool.graphics_descriptor_set = set
	}

	pool.draw_buffer.name = "Draw constants"
	pool.draw_buffer.desc.location = .Host_Upload
	pool.draw_buffer.desc.usage = {.Shader_Resource, .Constant_Buffer}
	if error := init_resizable_buffer(&pool.draw_buffer, renderer); error != nil {
		log.errorf("Could not create draw constants buffer: {}", error)
		ok = false
		return
	}

	pool.transform_buffer.name = "Transform buffer"
	pool.transform_buffer.desc.location = .Device
	pool.transform_buffer.desc.usage = {.Shader_Resource}
	pool.transform_buffer.desc.structure_stride = size_of(Transform)
	pool.transform_buffer.desc.size = size_of(Transform) * INITIAL_TRANSFORM_COUNT
	if error := init_resizable_buffer(&pool.transform_buffer, renderer); error != nil {
		log.errorf(
			"Could not create transform buffer with {} transforms: {}",
			INITIAL_TRANSFORM_COUNT,
			error,
		)
		ok = false
		return
	}

	pool.material_buffer.name = "Material buffer"
	pool.material_buffer.desc.location = .Device
	pool.material_buffer.desc.usage = {.Shader_Resource}
	pool.material_buffer.desc.structure_stride = size_of(Material)
	pool.material_buffer.desc.size = size_of(Material) * INITIAL_MATERIAL_COUNT
	if error := init_resizable_buffer(&pool.material_buffer, renderer); error != nil {
		log.errorf(
			"Could not create material buffer with {} materials: {}",
			INITIAL_MATERIAL_COUNT,
			error,
		)
		ok = false
		return
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

	append(&pool.texture_descriptors, white_texture.srv)
	append(&pool.texture_descriptors, black_texture.srv)

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
		{
			{descriptors = {pool.transform_buffer.srv}},
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
	destroy_texture(&pool.white_texture, renderer)
	destroy_texture(&pool.black_texture, renderer)
	destroy_resizable_buffer(&pool.material_buffer, renderer)
	destroy_resizable_buffer(&pool.transform_buffer, renderer)
}

resource_pool_bind :: proc(pool: ^Resource_Pool, renderer: ^Renderer) {

}

resource_pool_descriptor_desc :: proc(
	register_space: u32,
	stages: gpu.Stage_Flags,
) -> gpu.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges = {
			gpu.buffer_range(0, 1, stages = stages),
			gpu.buffer_range(1, 1, stages = stages),
			gpu.sampler_range(2, 1, stages = stages),
			gpu.buffer_range(3, MAX_IMAGES, partial = true, stages = stages),
		},
	}
}

resource_pool_add_texture :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	texture: ^gpu.Descriptor,
) -> (
	handle: Image_Handle,
	ok: bool = true,
) {
	len := len(pool.texture_descriptors)
	_, err := append(&pool.texture_descriptors, texture)
	if err != nil {
		ok = false
		return
	}

	renderer.instance->update_descriptor_ranges(
		pool.graphics_descriptor_set,
		3, // texture range
		{{descriptors = {texture}, base_descriptor = u32(len)}},
	)
	handle = Image_Handle(len)
	log.infof("handle: {}", handle)
	return
}

resource_pool_clear_textures :: proc(pool: ^Resource_Pool, renderer: ^Renderer) {
	for &d in pool.texture_descriptors {
		d = nil
	}
	renderer.instance->update_descriptor_ranges(
		pool.graphics_descriptor_set,
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
	len := pool.material_buffer.len
	err := append_buffer(
		&pool.material_buffer,
		slice.bytes_from_ptr(&material, size_of(Material)),
		gpu.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	)
	if err != nil {
		ok = false
		return
	}

	handle = Material_Handle(len)
	log.infof("material handle: {}", handle)
	return
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
	buffer_set(
		&pool.material_buffer,
		slice.bytes_from_ptr(&material, size_of(Material)),
		size_of(Material) * u64(handle),
		gpu.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	)

	return
}

resource_pool_add_transform :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	transform: Transform,
) -> (
	handle: Transform_Handle,
	ok: bool = true,
) {
	transform := transform
	len := pool.transform_buffer.len
	err := append_buffer(
		&pool.transform_buffer,
		slice.bytes_from_ptr(&transform, size_of(Transform)),
		gpu.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	)
	if err != nil {
		ok = false
		return
	}

	handle = Transform_Handle(len)
	log.infof("transform handle: {}", handle)
	return
}

resource_pool_clear_transforms :: proc(pool: ^Resource_Pool) {
	pool.transform_buffer.len = 0
}

resource_pool_set_transform :: proc(
	pool: ^Resource_Pool,
	renderer: ^Renderer,
	handle: Transform_Handle,
	transform: Transform,
) -> (
	ok: bool = true,
) {
	transform := transform
	buffer_set(
		&pool.transform_buffer,
		slice.bytes_from_ptr(&transform, size_of(Transform)),
		size_of(Transform) * u64(handle),
		gpu.ACCESS_STAGE_SHADER_RESOURCE,
		renderer,
	)

	return
}

render_components_descriptor_requirements: gpu.Descriptor_Pool_Desc : {
	descriptor_set_max_num = 1,
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 2,
}

render_components_resource_requirements: gpu.Resource_Requirements : {
	sampler_max_num = 1,
	texture_max_num = MAX_IMAGES,
	buffer_max_num = 2,
}
