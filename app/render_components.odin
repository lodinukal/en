package app

import "core:container/small_array"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:math/linalg/hlsl"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "en:mercury"

import sp "external:slang/slang"

Frame_Constants :: struct #align (1) {
	view:        hlsl.float4x4,
	projection:  hlsl.float4x4,
	light_color: hlsl.float4,
	light_dir:   hlsl.float4,
}

Draw_Data :: struct {
	start_instance: u32,
	count:          u32,
	object:         Object_Data,
}

Object_Handle :: distinct u32
Object_Data :: struct #align (1) {
	transform: hlsl.float4x4,
	geometry:  Geometry_Handle,
	material:  Material_Handle,
}
Gpu_Object_Data :: struct #align (1) {
	transform: hlsl.float4x4,
	material:  Material_Handle,
}

// Transform_Handle :: distinct u32
// Transform :: struct #align (1) {
// 	transform: hlsl.float4x4,
// 	geometry: Geometry_Handle,
// 	material:  Material_Handle,
// }

Material_Handle :: distinct u32
Material :: struct #align (1) {
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

Pipeline_Layout_Handle :: distinct u32
Pipeline_Handle :: distinct u32
Stored_Pipeline :: struct {
	object:           ^mercury.Pipeline,
	desc:             Pipeline_Desc,
	source:           Shader_Source,
	layout:           Pipeline_Layout_Handle,
	compiled_shaders: [mercury.Shader_Stage][mercury.Shader_Target][]u8,
	last_write_time:  Maybe(os.File_Time),
}

INITIAL_GEOMETRY_COUNT :: 64
// INITIAL_INSTANCE_COUNT :: 256
INITIAL_MATERIAL_COUNT :: 32

// basically 5000 different geometries can be drawn
DRAW_BATCH_COUNT :: 5_000
Draw_Batch_Readback :: u32

INITIAL_IMAGE_COUNT :: 64
MAX_IMAGES :: 1 << 13
Image_Handle :: distinct u32
WHITE_IMAGE_HANDLE :: Image_Handle(0)
BLACK_IMAGE_HANDLE :: Image_Handle(1)

BUFFER_ID :: enum {
	Graphics_Constants,
	Objects,
	Vertex,
	Index,
	Material,
}

BINDING_RESOURCE_OBJECTS_INDEX :: 0
BINDING_RESOURCE_MATERIALS_INDEX :: 1
BINDING_RESOURCE_SAMPLER_INDEX :: 2
BINDING_RESOURCE_TEXTURES_INDEX :: 3

Resource_Pool :: struct {
	buffers:                  [BUFFER_ID]Ren_Buffer,
	frame_constants:          Frame_Constants,
	mapped_constants:         ^Frame_Constants,
	pipeline:                 struct {
		layouts:        [dynamic]^mercury.Pipeline_Layout,
		free_layouts:   [dynamic]uint,
		pipelines:      [dynamic]Stored_Pipeline,
		free_pipelines: [dynamic]uint,
	},
	object:                   struct {
		list: [dynamic]Object_Data,
	},
	geom:                     struct {
		list:         [dynamic]Gpu_Geometry,
		current_geom: Maybe(Geometry_Handle),
	},
	draws:                    struct {
		list:       [dynamic]Draw_Data,
		object_num: u32,
	},
	free_materials:           [dynamic]uint,
	sampler:                  ^mercury.Descriptor,
	white_texture:            Texture,
	black_texture:            Texture,
	texture_index:            uint,
	free_texture_descriptors: [dynamic]uint,
	//
	draw_constants_ds:        ^mercury.Descriptor_Set,
	resource_ds:              ^mercury.Descriptor_Set,
}

init_resource_pool :: proc(pool: ^Resource_Pool, ren: ^Renderer) -> (ok: bool = true) {
	if set, error := ren.instance->allocate_descriptor_set(
		ren.descriptor_pool,
		ren_resource_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.resource_ds = set
	}

	if set, error := ren.instance->allocate_descriptor_set(
		ren.descriptor_pool,
		ren_frame_constants_descriptor_desc(0, {.Vertex_Shader, .Fragment_Shader}),
	); error != nil {
		log.errorf("Could not allocate descriptor set: {}", error)
		ok = false
		return
	} else {
		pool.draw_constants_ds = set
	}

	// constants
	{
		pool.buffers[.Graphics_Constants].name = "Graphics constants"
		pool.buffers[.Graphics_Constants].desc.location = .Host_Upload
		pool.buffers[.Graphics_Constants].desc.usage = {.Constant_Buffer}
		pool.buffers[.Graphics_Constants].desc.size = u64(
			mem.align_forward_int(size_of(Frame_Constants), 256),
		)
		if error := init_ren_buffer(&pool.buffers[.Graphics_Constants], ren); error != nil {
			log.errorf("Could not create graphics constants buffer: {}", error)
			ok = false
			return
		}

		ren.instance->update_descriptor_ranges(
			pool.draw_constants_ds,
			0,
			{{descriptors = {pool.buffers[.Graphics_Constants].cbv}}},
		)
		mapped, error_map := ren.instance->map_buffer(
			pool.buffers[.Graphics_Constants].buffer,
			0,
			size_of(Frame_Constants),
		)
		if error_map != nil {
			log.errorf("Could not map draw buffer {}", error_map)
			ok = false
			return
		}
		pool.mapped_constants = auto_cast raw_data(mapped)
	}

	// objects
	{
		pool.buffers[.Objects].name = "Draw Objects buffer"
		pool.buffers[.Objects].desc.location = .Device
		pool.buffers[.Objects].desc.usage = {.Shader_Resource}
		pool.buffers[.Objects].desc.size = u64(
			mem.align_forward_int(DRAW_BATCH_COUNT * size_of(Gpu_Object_Data), 256),
		)
		pool.buffers[.Objects].desc.structure_stride = size_of(Gpu_Object_Data)
		if error := init_ren_buffer(&pool.buffers[.Objects], ren); error != nil {
			log.errorf("Could not create objects buffer: {}", error)
			ok = false
			return
		}

		ren.instance->update_descriptor_ranges(
			pool.resource_ds,
			BINDING_RESOURCE_OBJECTS_INDEX,
			{{descriptors = {pool.buffers[.Objects].srv}}},
		)
	}

	// vertex
	{
		pool.buffers[.Vertex].name = "Vertex buffer"
		pool.buffers[.Vertex].desc.location = .Device
		pool.buffers[.Vertex].desc.usage = {.Vertex_Buffer}
		pool.buffers[.Vertex].desc.size = 0
		if error := init_ren_buffer(&pool.buffers[.Vertex], ren); error != nil {
			log.errorf("Could not create vertex buffer: {}", error)
			ok = false
			return
		}
	}

	// index
	{
		pool.buffers[.Index].name = "Index buffer"
		pool.buffers[.Index].desc.location = .Device
		pool.buffers[.Index].desc.usage = {.Index_Buffer}
		pool.buffers[.Index].desc.size = 0
		if error := init_ren_buffer(&pool.buffers[.Index], ren); error != nil {
			log.errorf("Could not create index buffer: {}", error)
			ok = false
			return
		}
	}

	// material
	{
		pool.buffers[.Material].name = "Material buffer"
		pool.buffers[.Material].desc.location = .Device
		pool.buffers[.Material].desc.usage = {.Shader_Resource}
		pool.buffers[.Material].desc.size = size_of(Material) * INITIAL_MATERIAL_COUNT
		pool.buffers[.Material].desc.structure_stride = size_of(Material)
		if error := init_ren_buffer(&pool.buffers[.Material], ren); error != nil {
			log.errorf("Could not create material buffer: {}", error)
			ok = false
			return
		}

		ren.instance->update_descriptor_ranges(
			pool.resource_ds,
			BINDING_RESOURCE_MATERIALS_INDEX,
			{{descriptors = {pool.buffers[.Material].srv}}},
		)
	}

	reserve_dynamic_array(&pool.object.list, DRAW_BATCH_COUNT)

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
	if error_init_white_tex := init_ren_texture(&white_texture, ren); error_init_white_tex != nil {
		log.errorf("Could not init white texture: {}", error_init_white_tex)
		ok = false
		return
	}

	black_texture: Texture
	black_texture.desc = default_texture_desc
	black_texture.name = "black"
	if error_init_black_tex := init_ren_texture(&black_texture, ren); error_init_black_tex != nil {
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
		ren,
		{subresource_upload_white},
		mercury.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err_upload_white != nil {
		log.errorf("Could not upload white texture: {}", err_upload_white)
		ok = false
		return
	}

	if err_upload_black := ren_texture_upload(
		&black_texture,
		ren,
		{subresource_upload_black},
		mercury.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err_upload_black != nil {
		log.errorf("Could not upload black texture: {}", err_upload_black)
		ok = false
		return
	}

	pool.white_texture = white_texture
	pool.black_texture = black_texture

	sampler, error_sampler := ren.instance->create_sampler(ren.device, {})
	if error_sampler != nil {
		log.errorf("Could not create sampler: {}", error_sampler)
		ok = false
		return
	}
	pool.sampler = sampler

	ren.instance->update_descriptor_ranges(
		pool.resource_ds,
		BINDING_RESOURCE_SAMPLER_INDEX,
		{{descriptors = {sampler}}},
	)

	return
}

destroy_resource_pool :: proc(pool: ^Resource_Pool, ren: ^Renderer) {
	ren.instance->destroy_descriptor(ren.device, pool.sampler)
	delete(pool.free_texture_descriptors)
	deinit_ren_texture(&pool.white_texture, ren)
	deinit_ren_texture(&pool.black_texture, ren)

	for &buffer, _ in pool.buffers {
		deinit_ren_buffer(&buffer, ren)
	}

	delete(pool.free_materials)
	delete(pool.geom.list)
	delete(pool.object.list)
	delete(pool.draws.list)

	for layout in pool.pipeline.layouts {
		if layout == nil do continue
		ren.instance->destroy_pipeline_layout(layout)
	}
	delete(pool.pipeline.layouts)
	delete(pool.pipeline.free_layouts)

	for &pipeline in pool.pipeline.pipelines {
		if pipeline.object == nil do continue
		ren.instance->destroy_pipeline(pipeline.object)
		for &shader in pipeline.compiled_shaders {
			for &code in shader {
				delete(code)
			}
		}
	}
	delete(pool.pipeline.pipelines)
	delete(pool.pipeline.free_pipelines)
}

copy_frame_constants :: proc(pool: ^Resource_Pool) {
	pool.mapped_constants^ = pool.frame_constants
}

ren_bind_draw_constants_ds :: proc(
	ren: ^Renderer,
	cmd: ^mercury.Command_Buffer,
	set_index: u32 = 0,
) {
	ren.instance->cmd_set_descriptor_set(cmd, set_index, ren.resource_pool.draw_constants_ds)
}

ren_bind_resource_ds :: proc(ren: ^Renderer, cmd: ^mercury.Command_Buffer, set_index: u32 = 0) {
	ren.instance->cmd_set_descriptor_set(cmd, set_index, ren.resource_pool.resource_ds)
}

ren_frame_constants_descriptor_desc :: proc(
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

ren_resource_descriptor_desc :: proc(
	register_space: u32,
	stages: mercury.Stage_Flags,
) -> mercury.Descriptor_Set_Desc {
	return {
		register_space = register_space,
		ranges = slice.clone(
			[]mercury.Descriptor_Range_Desc {
				BINDING_RESOURCE_OBJECTS_INDEX = mercury.buffer_range(
					BINDING_RESOURCE_OBJECTS_INDEX,
					1,
					stages = stages,
				),
				BINDING_RESOURCE_MATERIALS_INDEX = mercury.buffer_range(
					BINDING_RESOURCE_MATERIALS_INDEX,
					1,
					stages = stages,
				),
				BINDING_RESOURCE_SAMPLER_INDEX = mercury.sampler_range(
					BINDING_RESOURCE_SAMPLER_INDEX,
					1,
					stages = stages,
				),
				BINDING_RESOURCE_TEXTURES_INDEX = mercury.texture_range(
					BINDING_RESOURCE_TEXTURES_INDEX,
					MAX_IMAGES,
					partial = true,
					stages = stages,
				),
			},
			context.temp_allocator,
		),
	}
}

ren_register_pipeline_layout :: proc(
	ren: ^Renderer,
	name: string,
	layout: mercury.Pipeline_Layout_Desc,
) -> (
	handle: Pipeline_Layout_Handle,
	ok: bool = true,
) {
	pool := &ren.resource_pool
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.pipeline.free_layouts); !pop_ok {
		pos = len(pool.pipeline.layouts)
		if _, append_err := append(&pool.pipeline.layouts, nil); append_err != nil {
			log.errorf("Could not append pipeline layout: {}", append_err)
			ok = false
			return
		}
	}

	error: mercury.Error
	pool.pipeline.layouts[pos], error = ren.instance->create_pipeline_layout(ren.device, layout)
	if error != nil {
		log.errorf("Could not create pipeline layout: {}", error)
		ok = false
		return
	}
	ren.instance->set_pipeline_layout_debug_name(pool.pipeline.layouts[pos], name)

	handle = Pipeline_Layout_Handle(pos)
	return
}

ren_unregister_pipeline_layout :: proc(ren: ^Renderer, handle: Pipeline_Layout_Handle) {
	pool := &ren.resource_pool
	append(&pool.pipeline.free_layouts, uint(handle))
	ren.instance->destroy_pipeline_layout(pool.pipeline.layouts[handle])
	pool.pipeline.layouts[handle] = nil
}

ren_set_pipeline_layout :: proc(
	ren: ^Renderer,
	cmd: ^mercury.Command_Buffer,
	handle: Pipeline_Layout_Handle,
) {
	ren.instance->cmd_set_pipeline_layout(cmd, ren.resource_pool.pipeline.layouts[handle])
}

Shader_Source_Kind :: enum {
	File,
	Source,
}

Shader_Source :: struct {
	kind:  Shader_Source_Kind,
	name:  string,
	data:  string,
	// only valid when kind is .File
	watch: bool,
}

Pipeline_Desc :: union {
	mercury.Graphics_Pipeline_Desc,
	mercury.Compute_Pipeline_Desc,
}

ren_register_pipeline :: proc(
	ren: ^Renderer,
	shader_source: Shader_Source,
	layout: Pipeline_Layout_Handle,
	desc: Pipeline_Desc,
) -> (
	handle: Pipeline_Handle,
	ok: bool = true,
) {
	pool := &ren.resource_pool
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.pipeline.free_pipelines); !pop_ok {
		pos = len(pool.pipeline.pipelines)
		if _, append_err := append_elem(&pool.pipeline.pipelines, Stored_Pipeline{});
		   append_err != nil {
			log.errorf("Could not append pipeline: {}", append_err)
			ok = false
			return
		}
	}
	pool.pipeline.pipelines[pos].source = shader_source
	pool.pipeline.pipelines[pos].layout = layout
	pool.pipeline.pipelines[pos].desc = desc

	if shader_source.kind == .File {
		os_error: os.Error
		pool.pipeline.pipelines[pos].last_write_time, os_error = os.last_write_time_by_name(
			shader_source.data,
		)
		if os_error != nil {
			log.errorf("Could not get last write time: {}", os_error)
			ok = false
			return
		}
	}

	layout := pool.pipeline.layouts[layout]

	stages: mercury.Stage_Flags
	// make sure no bytecode is set right now
	switch &v in pool.pipeline.pipelines[pos].desc {
	case mercury.Compute_Pipeline_Desc:
		stages = {.Compute_Shader}
		v.pipeline_layout = layout
	case mercury.Graphics_Pipeline_Desc:
		stages = {.Vertex_Shader, .Fragment_Shader}
		v.pipeline_layout = layout
	}

	target: mercury.Shader_Target
	switch ren.instance.api {
	case .D3D12:
		target = .DXIL
	case .Vulkan:
		target = .SPIRV
	}

	pool.pipeline.pipelines[pos].compiled_shaders = compile_shader(
		&ren.shader_context,
		shader_source,
		stages,
		only = target,
	) or_return

	switch &v in pool.pipeline.pipelines[pos].desc {
	case mercury.Compute_Pipeline_Desc:
		v.shader.bytecode = pool.pipeline.pipelines[pos].compiled_shaders[.Compute]
	case mercury.Graphics_Pipeline_Desc:
		v.shaders[.Vertex].bytecode = pool.pipeline.pipelines[pos].compiled_shaders[.Vertex]
		v.shaders[.Fragment].bytecode = pool.pipeline.pipelines[pos].compiled_shaders[.Fragment]
	}

	error: mercury.Error
	switch &v in pool.pipeline.pipelines[pos].desc {
	case mercury.Compute_Pipeline_Desc:
		pool.pipeline.pipelines[pos].object, error =
		ren.instance->create_compute_pipeline(ren.device, v)
	case mercury.Graphics_Pipeline_Desc:
		pool.pipeline.pipelines[pos].object, error =
		ren.instance->create_graphics_pipeline(ren.device, v)
	}
	ren.instance->set_pipeline_debug_name(pool.pipeline.pipelines[pos].object, shader_source.name)

	handle = Pipeline_Handle(pos)
	return
}

ren_unregister_pipeline :: proc(ren: ^Renderer, handle: Pipeline_Handle) {
	pool := &ren.resource_pool
	append(&pool.pipeline.free_pipelines, uint(handle))
	for &shader in pool.pipeline.pipelines[handle].compiled_shaders {
		for &code in shader {
			delete(code)
			code = nil
		}
	}
	switch &v in pool.pipeline.pipelines[handle].desc {
	case mercury.Compute_Pipeline_Desc:
		for &code in v.shader.bytecode {
			code = nil
		}
	case mercury.Graphics_Pipeline_Desc:
		for &shader in v.shaders {
			for &code in shader.bytecode {
				code = nil
			}
		}
	}
	ren.instance->destroy_pipeline(pool.pipeline.pipelines[handle].object)
	pool.pipeline.pipelines[handle].object = nil
}

ren_refresh_pipeline :: proc(ren: ^Renderer, handle: Pipeline_Handle) -> (ok: bool = true) {
	source := ren.resource_pool.pipeline.pipelines[handle].source
	desc := ren.resource_pool.pipeline.pipelines[handle].desc
	layout := ren.resource_pool.pipeline.pipelines[handle].layout
	log.infof("Refreshing pipeline: {}", source.name)
	ren_unregister_pipeline(ren, handle)
	new_handle := ren_register_pipeline(ren, source, layout, desc) or_return
	assert(new_handle == handle)
	return
}

ren_refresh_all_pipelines :: proc(ren: ^Renderer, only_changed := true) -> (ok: bool) {
	for &pipeline, i in ren.resource_pool.pipeline.pipelines {
		if pipeline.object == nil {
			continue
		}
		if only_changed {
			if pipeline.source.kind != .File {
				continue
			}
			last_write_time, os_error := os.last_write_time_by_name(pipeline.source.data)
			if os_error != nil {
				log.errorf("Could not get last write time: {}", os_error)
				return false
			}
			if last_write_time == pipeline.last_write_time {
				continue
			}
		}
		ren_refresh_pipeline(ren, Pipeline_Handle(i)) or_return
	}
	return true
}

ren_set_pipeline :: proc(ren: ^Renderer, cmd: ^mercury.Command_Buffer, handle: Pipeline_Handle) {
	ren.instance->cmd_set_pipeline(cmd, ren.resource_pool.pipeline.pipelines[handle].object)
}

ren_add_texture :: proc(
	ren: ^Renderer,
	texture: ^mercury.Descriptor,
) -> (
	handle: Image_Handle,
	ok: bool = true,
) {
	pool := &ren.resource_pool
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.free_texture_descriptors); !pop_ok {
		pos = pool.texture_index
		pool.texture_index += 1
	}

	ren.instance->update_descriptor_ranges(
		pool.resource_ds,
		BINDING_RESOURCE_TEXTURES_INDEX,
		{{descriptors = {texture}, base_descriptor = u32(pos)}},
	)
	handle = Image_Handle(pos)
	log.infof("handle: {}", handle)
	return
}

// removes a texture, sets it to the white texture
ren_remove_texture :: proc(ren: ^Renderer, handle: Image_Handle) {
	if handle == WHITE_IMAGE_HANDLE || handle == BLACK_IMAGE_HANDLE {
		return
	}

	pool := &ren.resource_pool
	append(&pool.free_texture_descriptors, uint(handle))
	ren.instance->update_descriptor_ranges(
		pool.resource_ds,
		BINDING_RESOURCE_TEXTURES_INDEX,
		{{descriptors = {pool.white_texture.srv}, base_descriptor = u32(WHITE_IMAGE_HANDLE)}},
	)
}

ren_clear_textures :: proc(ren: ^Renderer) {
	pool := &ren.resource_pool
	pool.texture_index = 0
}

ren_add_material :: proc(
	ren: ^Renderer,
	material: Material,
) -> (
	handle: Material_Handle,
	ok: bool = true,
) {
	pool := &ren.resource_pool
	material := material
	pos: uint = 0
	pop_ok: bool = false
	if pos, pop_ok = pop_safe(&pool.free_materials); !pop_ok {
		pos = uint(pool.buffers[.Material].len / size_of(Material))

		old_srv := pool.buffers[.Material].srv
		defer if pool.buffers[.Material].srv != old_srv {
			ren.instance->update_descriptor_ranges(
				pool.resource_ds,
				BINDING_RESOURCE_MATERIALS_INDEX,
				{{descriptors = {pool.buffers[.Material].srv}}},
			)
		}

		err := ren_buffer_append(
			&pool.buffers[.Material],
			slice.bytes_from_ptr(&material, size_of(Material)),
			mercury.ACCESS_STAGE_SHADER_RESOURCE,
			ren,
		)
		if err != nil {
			ok = false
			return
		}
	} else {
		ren_buffer_set(
			&pool.buffers[.Material],
			slice.bytes_from_ptr(&material, size_of(Material)),
			size_of(Material) * u64(pos),
			mercury.ACCESS_STAGE_SHADER_RESOURCE,
			ren,
		)
	}

	handle = Material_Handle(pos)
	log.infof("material handle: {}", handle)
	return
}

ren_remove_material :: proc(ren: ^Renderer, handle: Material_Handle) {
	pool := &ren.resource_pool
	append(&pool.free_materials, uint(handle))
}

ren_clear_materials :: proc(ren: ^Renderer) {
	pool := &ren.resource_pool
	pool.buffers[.Material].len = 0
}

ren_set_material :: proc(
	ren: ^Renderer,
	handle: Material_Handle,
	material: Material,
) -> (
	ok: bool = true,
) {
	pool := &ren.resource_pool
	material := material
	ren_buffer_set(
		&pool.buffers[.Material],
		slice.bytes_from_ptr(&material, size_of(Material)),
		size_of(Material) * u64(handle),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		ren,
	)

	return
}

ren_add_geometry :: proc(
	ren: ^Renderer,
	geometry: Geometry,
) -> (
	handle: Geometry_Handle,
	ok: bool = true,
) {
	pool := &ren.resource_pool
	geometry := geometry
	vertex_offset := pool.buffers[.Vertex].len / size_of(Vertex_Default)
	index_offset := pool.buffers[.Index].len / size_of(u16)

	if err_vertex := ren_buffer_append(
		&pool.buffers[.Vertex],
		slice.to_bytes(geometry.vertices),
		mercury.ACCESS_STAGE_VERTEX_BUFFER,
		ren,
	); err_vertex != nil {
		ok = false
		log.infof("Could not append vertex buffer: {}", err_vertex)
		return
	}
	if err_index := ren_buffer_append(
		&pool.buffers[.Index],
		slice.to_bytes(geometry.indices),
		mercury.ACCESS_STAGE_INDEX_BUFFER,
		ren,
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

	len := len(pool.geom.list)
	append(&pool.geom.list, gpu_geometry)
	handle = Geometry_Handle(len)
	log.infof("geometry handle: {}", handle)
	return
}

ren_clear_geometries :: proc(ren: ^Renderer) {
	pool := &ren.resource_pool
	pool.buffers[.Vertex].len = 0
	pool.buffers[.Index].len = 0
	pool.geom.current_geom = nil
	clear(&pool.geom.list)
}

ren_reset_objects :: proc(ren: ^Renderer) {
	pool := &ren.resource_pool
	clear(&pool.object.list)
	pool.buffers[.Objects].len = 0
}

Object_Add_Result :: enum {
	Ok,
	Full,
	Other,
}

ren_add_objects :: proc(
	ren: ^Renderer,
	data: ..Object_Data,
) -> (
	first_object: Object_Handle,
	result: Object_Add_Result,
) {
	data := data
	pool := &ren.resource_pool

	old_srv := pool.buffers[.Objects].srv
	defer {
		if pool.buffers[.Objects].srv != old_srv {
			ren.instance->update_descriptor_ranges(
				pool.resource_ds,
				BINDING_RESOURCE_OBJECTS_INDEX,
				{{descriptors = {pool.buffers[.Objects].srv}}},
			)
		}
	}

	temp := make([]Gpu_Object_Data, len(data), context.temp_allocator)
	for object, i in data {
		temp[i] = {
			transform = object.transform,
			material  = object.material,
		}
	}

	pos := len(pool.object.list)
	if err := ren_buffer_append(
		&pool.buffers[.Objects],
		slice.to_bytes(temp),
		mercury.ACCESS_STAGE_SHADER_RESOURCE,
		ren,
	); err != nil {
		log.errorf("Could not append draw: {}", err)
		result = .Other
		return
	}
	append_elems(&pool.object.list, ..data)
	first_object = Object_Handle(pos)
	return
}

ren_draw_objects_assume_same_primitive :: proc(
	ren: ^Renderer,
	start: Object_Handle,
	count: uint,
) -> (
	result: Object_Add_Result,
) {
	pool := &ren.resource_pool
	first_object := &pool.object.list[start]
	append(
		&pool.draws.list,
		Draw_Data {
			count = u32(count),
			start_instance = u32(start + 1),
			object = {transform = first_object.transform, material = first_object.material},
		},
	)
	pool.draws.object_num += u32(count)
	return .Ok
}

ren_draw_object :: proc(
	ren: ^Renderer,
	object_handle: Object_Handle,
) -> (
	result: Object_Add_Result,
) {
	pool := &ren.resource_pool

	object := &pool.object.list[object_handle]
	draw_index := 0
	// no current geometry set, so start a new draw
	if object.geometry != pool.geom.current_geom {
		pool.geom.current_geom = object.geometry
		append(
			&pool.draws.list,
			Draw_Data {
				count = 0,
				start_instance = pool.draws.object_num + 1,
				object = {transform = object.transform, material = object.material},
			},
		)
		draw_index = len(pool.draws.list) - 1
	}
	pool.draws.list[draw_index].count += 1
	pool.draws.object_num += 1

	return .Ok
}

ren_draw_imm :: proc(ren: ^Renderer, object: Object_Data) -> (result: Object_Add_Result) {
	_, err := append(&ren.resource_pool.draws.list, Draw_Data{object = object})
	if err != nil {
		log.errorf("Could not append draw: {}", err)
		return .Other
	}
	ren.resource_pool.draws.object_num += 1
	return .Ok
}

ren_flush_draws :: proc(ren: ^Renderer, cmd: ^mercury.Command_Buffer) {
	pool := &ren.resource_pool
	// log.infof("objects: {}", pool.draws.object_num)
	// log.infof("draws: {}", len(pool.draws.list))
	for draw in pool.draws.list {
		// log.infof("draw: {}", draw)
		ren_set_constants(
			ren,
			cmd,
			0,
			Gpu_Object_Data{transform = draw.object.transform, material = draw.object.material},
		)
		geometry := pool.geom.list[draw.object.geometry]
		ren.instance->cmd_draw_indexed(
			cmd,
			{
				index_num = geometry.index_count,
				instance_num = draw.count,
				base_index = geometry.index_offset,
				base_vertex = geometry.vertex_offset,
				base_instance = draw.start_instance,
			},
		)
	}
	clear(&pool.draws.list)
	pool.draws.object_num = 0
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

slang_check :: #force_inline proc(#any_int result: int, loc := #caller_location) -> bool {
	result := -sp.Result(result)
	if sp.FAILED(result) {
		code := sp.GET_RESULT_CODE(result)
		facility := sp.GET_RESULT_FACILITY(result)
		estr: string
		switch sp.Result(result) {
		case:
			estr = "Unknown error"
		case sp.E_NOT_IMPLEMENTED():
			estr = "E_NOT_IMPLEMENTED"
		case sp.E_NO_INTERFACE():
			estr = "E_NO_INTERFACE"
		case sp.E_ABORT():
			estr = "E_ABORT"
		case sp.E_INVALID_HANDLE():
			estr = "E_INVALID_HANDLE"
		case sp.E_INVALID_ARG():
			estr = "E_INVALID_ARG"
		case sp.E_OUT_OF_MEMORY():
			estr = "E_OUT_OF_MEMORY"
		case sp.E_BUFFER_TOO_SMALL():
			estr = "E_BUFFER_TOO_SMALL"
		case sp.E_UNINITIALIZED():
			estr = "E_UNINITIALIZED"
		case sp.E_PENDING():
			estr = "E_PENDING"
		case sp.E_CANNOT_OPEN():
			estr = "E_CANNOT_OPEN"
		case sp.E_NOT_FOUND():
			estr = "E_NOT_FOUND"
		case sp.E_INTERNAL_FAIL():
			estr = "E_INTERNAL_FAIL"
		case sp.E_NOT_AVAILABLE():
			estr = "E_NOT_AVAILABLE"
		case sp.E_TIME_OUT():
			estr = "E_TIME_OUT"
		}

		log.errorf("Failed with error: %v (%v) Facility: %v", estr, code, facility, location = loc)
		return false
	}
	return true
}

diagnostics_check :: #force_inline proc(diagnostics: ^sp.IBlob, loc := #caller_location) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(
			diagnostics->getBufferPointer(),
			int(diagnostics->getBufferSize()),
		)
		log.errorf("Diagnostics: {}", string(buffer), location = loc)
	}
}

@(private = "file")
slang_lib: struct {
	__handle:            dynlib.Library,
	createGlobalSession: proc "c" (
		apiVersion: sp.Int,
		outGlobalSession: ^^sp.IGlobalSession,
	) -> sp.Result,
	shutdown:            proc "c" (),
}

Shader_Context :: struct {
	global_session: ^sp.IGlobalSession,
	session_desc:   sp.SessionDesc,
}

create_shader_context :: proc(ctx: ^Shader_Context, debug := true) -> (ok: bool = true) {
	// attempt to load
	if slang_lib.__handle == nil {
		count := dynlib.initialize_symbols(&slang_lib, "slang", "slang_") or_return
		if count != 2 {
			log.warnf("Could only load {} symbols", count)
			return false
		}
	}
	slang_check(slang_lib.createGlobalSession(sp.API_VERSION, &ctx.global_session)) or_return
	@(static) sm_6_profile: sp.ProfileID
	if sm_6_profile == nil {
		sm_6_profile = ctx.global_session->findProfile("sm_6_3")
	}
	target_dxil_desc := sp.TargetDesc {
		structureSize = size_of(sp.TargetDesc),
		format        = .DXIL,
		flags         = {},
		profile       = sm_6_profile,
	}

	target_spirv_desc := sp.TargetDesc {
		structureSize = size_of(sp.TargetDesc),
		format        = .SPIRV,
		flags         = {},
		profile       = sm_6_profile,
	}

	target_msl_desc := sp.TargetDesc {
		structureSize = size_of(sp.TargetDesc),
		format        = .METAL,
		flags         = {},
		profile       = sm_6_profile,
	}

	@(static) targets: [3]sp.TargetDesc
	targets = [?]sp.TargetDesc{target_dxil_desc, target_spirv_desc, target_msl_desc}

	@(static) compiler_option_entries: [6]sp.CompilerOptionEntry
	compiler_option_entries = [?]sp.CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {intValue0 = 1}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 0, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 1, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 2, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 3, intValue1 = 0}},
		{
			name = .DebugInformation,
			value = {
				kind = .Int,
				intValue0 = auto_cast (sp.DebugInfoLevel.MAXIMAL if debug else sp.DebugInfoLevel.NONE),
			},
		},
	}
	ctx.session_desc = sp.SessionDesc {
		structureSize            = size_of(sp.SessionDesc),
		targets                  = raw_data(targets[:]),
		targetCount              = len(targets),
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = len(compiler_option_entries),
	}

	return
}

destroy_shader_context :: proc(ctx: ^Shader_Context) {
	if ctx == nil do return
	ctx.global_session->release()
	if slang_lib.__handle != nil {
		slang_lib.shutdown()
		dynlib.unload_library(slang_lib.__handle)
		slang_lib.__handle = nil
	}
}

@(private = "file")
MAX_LINK_COMPONENTS :: 6
@(private = "file")
Component_Small_Array :: small_array.Small_Array(MAX_LINK_COMPONENTS, ^sp.IComponentType)

compile_shader :: proc(
	ctx: ^Shader_Context,
	source: Shader_Source,
	stages: mercury.Stage_Flags,
	only: Maybe(mercury.Shader_Target) = nil,
	allocator := context.allocator,
) -> (
	result: [mercury.Shader_Stage][mercury.Shader_Target][]u8,
	ok: bool = true,
) {
	if ctx == nil {
		log.errorf("No context")
		ok = false
		return
	}
	diagnostics: ^sp.IBlob
	r: sp.Result

	session: ^sp.ISession
	slang_check(ctx.global_session->createSession(ctx.session_desc, &session)) or_return
	defer session->release()

	source_name_as_cstring, clone_cstring_name_err := strings.clone_to_cstring(
		source.name,
		context.temp_allocator,
	)
	if clone_cstring_name_err != nil {
		log.errorf("Could not clone source name: {}", clone_cstring_name_err)
		ok = false
		return
	}

	source_data_as_cstring, clone_cstring_data_err := strings.clone_to_cstring(
		source.data,
		context.temp_allocator,
	)
	if clone_cstring_data_err != nil {
		log.errorf("Could not clone source data: {}", clone_cstring_data_err)
		ok = false
		return
	}

	module: ^sp.IModule
	switch source.kind {
	case .File:
		module = session->loadModule(source_data_as_cstring, &diagnostics)
	case .Source:
		module =
		session->loadModuleFromSourceString(
			source_name_as_cstring,
			fmt.ctprintf("inline:%v", source_name_as_cstring),
			source_data_as_cstring,
			&diagnostics,
		)
	}
	diagnostics_check(diagnostics)
	if module == nil {
		log.errorf("Shader compile error: {}", source_name_as_cstring)
		ok = false
		return
	}
	defer module->release()

	components: [mercury.Shader_Stage]^sp.IComponentType

	// compute
	if stages == {.Compute_Shader} {
		entry_point: ^sp.IEntryPoint
		slang_check(module->findEntryPointByName("cs_main", &entry_point)) or_return
		if entry_point == nil {
			log.errorf("no compute shader entry point")
			return
		}
		components[.Compute] = entry_point
	} else if stages == {.Vertex_Shader, .Fragment_Shader} {
		vs_entry_point: ^sp.IEntryPoint
		fs_entry_point: ^sp.IEntryPoint
		slang_check(module->findEntryPointByName("vs_main", &vs_entry_point)) or_return
		slang_check(module->findEntryPointByName("fs_main", &fs_entry_point)) or_return

		if vs_entry_point == nil {
			log.errorf("no vertex shader entry point")
			ok = false
			return
		}

		components[.Vertex] = vs_entry_point
		components[.Fragment] = fs_entry_point
	} else {
		log.errorf("Unsupported shader stages")
		ok = false
		return
	}

	for &output_set, stage in result {
		if components[stage] == nil do continue
		composing: Component_Small_Array
		small_array.append(&composing, components[stage], module)

		composed_program: ^sp.IComponentType
		r =
		session->createCompositeComponentType(
			raw_data(small_array.slice(&composing)),
			small_array.len(composing),
			&composed_program,
			&diagnostics,
		)
		diagnostics_check(diagnostics)
		slang_check(r) or_return

		linked_program: ^sp.IComponentType
		r = composed_program->link(&linked_program, &diagnostics)
		diagnostics_check(diagnostics)
		slang_check(r) or_return

		for &output, target in output_set {
			if only != nil && only != target do continue
			target_code: ^sp.IBlob
			r = linked_program->getEntryPointCode(0, int(target), &target_code, &diagnostics)
			diagnostics_check(diagnostics)
			slang_check(r) or_return
			defer target_code->release()

			code_size := target_code->getBufferSize()
			source_code := slice.from_ptr(
				(^u8)(target_code->getBufferPointer()),
				auto_cast code_size,
			)

			error: mem.Allocator_Error
			output, error = slice.clone(source_code, allocator)
			if error != nil {
				log.errorf("Failed to allocate memory for shader code")
				ok = false
				return
			}
		}
	}


	return
}

free_shader :: proc(result: [mercury.Shader_Target][]u8, allocator := context.allocator) {
	for output in result {
		if output == nil do continue
		free(raw_data(output), allocator)
	}
}
