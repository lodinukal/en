package app

import "core:log"
import "core:strings"
import "en:mercury"

import "external:gltf2"
import stbi "vendor:stb/image"

texture_from_data :: proc(
	renderer: ^Renderer,
	data: [^]u8,
	height: u16,
	width: u16,
	name: string = "texture",
) -> (
	texture: Texture,
	ok: bool = true,
) {
	texture.desc.type = ._2D
	texture.desc.layer_num = 1
	texture.desc.mip_num = 1
	texture.desc.format = .RGBA8_UNORM
	texture.desc.usage = {.Shader_Resource}
	texture.desc.width = u16(width)
	texture.desc.height = u16(height)

	if err := init_texture(&texture, renderer); err != nil {
		ok = false
		log.infof("Could not init texture: {}", err)
		return
	}
	texture_set_name(&texture, name, renderer)

	subresource: Texture_Subresource_Upload_Desc
	subresource.slices = data
	subresource.slice_num = 1
	subresource.row_pitch, subresource.slice_pitch = compute_pitch(
		.RGBA8_UNORM,
		u32(texture.desc.width),
		u32(texture.desc.height),
	)

	if err := texture_upload(
		&texture,
		renderer,
		{subresource},
		mercury.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err != nil {
		ok = false
		log.infof("Could not upload texture: {}", err)
		return
	}

	return
}

// from a format such as png or jpeg or whatever stb supports
texture_from_buffer :: proc(
	renderer: ^Renderer,
	buffer: []u8,
	name: string = "texture",
) -> (
	texture: Texture,
	ok: bool = true,
) {
	height, width: i32 = 0, 0
	data := stbi.load_from_memory(raw_data(buffer), i32(len(buffer)), &width, &height, nil, 4)
	return texture_from_data(renderer, data, u16(height), u16(width), name)
}

texture_from_file :: proc(
	renderer: ^Renderer,
	file: string,
) -> (
	texture: Texture,
	ok: bool = true,
) {
	width, height: i32 = 0, 0
	channels_in_file: i32 = 0
	data := stbi.load(
		strings.clone_to_cstring(file, context.temp_allocator),
		&width,
		&height,
		&channels_in_file,
		4,
	)
	if data == nil {
		ok = false
		log.infof("Could not load image: {}", file)
		return
	}
	return texture_from_data(renderer, data, u16(height), u16(width), file)
}

Buffer_View :: struct {
	buffer: uint,
	offset: u64,
	size:   u64,
}

Primitive :: struct {
	positions: Buffer_View,
	normals:   Buffer_View,
	tangents:  Buffer_View,
	texcoords: Buffer_View,
	indices:   Buffer_View,
	material:  Material_Handle,
}

Scene_Image :: struct {
	handle:  Image_Handle,
	texture: Texture,
}

Mesh :: struct {
	primitives: [dynamic]Primitive,
}

Scene :: struct {
	images:    [dynamic]Scene_Image,
	materials: [dynamic]Material_Handle,
	buffers:   [dynamic]Resizable_Buffer,
	meshes:    [dynamic]Mesh,
}

// ending with .gltf or .glb
load_gltf_file :: proc(
	renderer: ^Renderer,
	file: string,
	allocator := context.allocator,
) -> (
	scene: Scene,
	ok: bool = true,
) {
	data, error := gltf2.load_from_file(file, context.temp_allocator)
	switch err in error {
	case gltf2.JSON_Error:
		log.errorf("Could not load gltf file: {}", err)
		ok = false
		return
	case gltf2.GLTF_Error:
		log.errorf("Could not parse gltf file: {}", err)
		ok = false
		return
	}
	defer gltf2.unload(data, context.temp_allocator)

	for img in data.images {
		switch uri in img.uri {
		case string:
			log.warnf("Could not load image: {}", uri)
			ok = false
			return
		case []u8:
			tex, tex_ok := texture_from_buffer(renderer, uri, img.name.(string) or_else "unnamed")
			if !tex_ok {
				log.errorf("Could not load texture")
				ok = false
				return
			}
			img_handle, add_tex_ok := resource_pool_add_texture(
				&renderer.resource_pool,
				renderer,
				tex.srv,
			)
			if !add_tex_ok {
				log.errorf("Failed to add texture to resource pool")
				ok = false
				return
			}
			_, append_err := append(&scene.images, Scene_Image{handle = img_handle, texture = tex})
			if append_err != nil {
				log.errorf("Could not append image handle: {}", append_err)
				ok = false
				return
			}
			log.infof("Loaded image: {}", img.name)
		}
	}

	temp_texture_mapping := make(map[gltf2.Integer]uint, context.temp_allocator)
	for tex, tex_i in data.textures {
		switch s in tex.source {
		case gltf2.Integer:
			temp_texture_mapping[u32(tex_i)] = uint(s)
			log.infof("Mapping texture: {}", s)
		case:
			log.warnf("Could not load texture: {}", s)
		}
	}

	for mat in data.materials {
		info: Material
		info.base_color = [4]f32{1.0, 1.0, 1.0, 1.0}
		#partial switch mr in mat.metallic_roughness {
		case gltf2.Material_Metallic_Roughness:
			#partial switch base_color_tex in mr.base_color_texture {
			case gltf2.Texture_Info:
				info.albedo = scene.images[temp_texture_mapping[base_color_tex.index]].handle
			}
			#partial switch metallic_roughness_tex in mr.metallic_roughness_texture {
			case gltf2.Texture_Info:
				info.metallic_roughness =
					scene.images[temp_texture_mapping[metallic_roughness_tex.index]].handle
			}
		}
		#partial switch normal_tex in mat.normal_texture {
		case gltf2.Material_Normal_Texture_Info:
			info.normal = scene.images[temp_texture_mapping[normal_tex.index]].handle
		}
		#partial switch emissive_tex in mat.emissive_texture {
		case gltf2.Texture_Info:
			info.emissive = scene.images[temp_texture_mapping[emissive_tex.index]].handle
		}
		mat_handle, add_mat_ok := resource_pool_add_material(
			&renderer.resource_pool,
			renderer,
			info,
		)
		if !add_mat_ok {
			log.errorf("Failed to add material to resource pool")
			ok = false
			return
		}
		_, append_err := append(&scene.materials, mat_handle)
		if append_err != nil {
			log.errorf("Could not append material handle: {}", append_err)
			ok = false
			return
		}
		log.infof("Loaded material: {}", mat.name)
	}

	reserve(&scene.buffers, len(data.buffers))
	for buffer in data.buffers {
		info: Resizable_Buffer
		info.desc.location = .Device
		info.desc.size = u64(buffer.byte_length)
		info.desc.usage = {.Vertex_Buffer, .Index_Buffer}
		data: []u8
		switch uri in buffer.uri {
		case string:
			log.warnf("Could not load buffer: {}", uri)
			ok = false
			return
		case []u8:
			data = uri
		}
		if err := init_resizable_buffer(&info, renderer); err != nil {
			log.errorf("Could not init buffer: {}", err)
			ok = false
			return
		}
		append_assume_buffer(&info, data, mercury.ACCESS_STAGE_SHADER_RESOURCE, renderer)
		_, append_err := append(&scene.buffers, info)
		if append_err != nil {
			log.errorf("Could not append buffer: {}", append_err)
			ok = false
			return
		}
		log.infof("Loaded buffer: {}", buffer.name)
	}

	temp_buffer_views := make(
		[]Buffer_View,
		len(data.buffer_views),
		allocator = context.temp_allocator,
	)
	for buf_view, buf_view_i in data.buffer_views {
		temp_buffer_views[u32(buf_view_i)] = {
			buffer = uint(buf_view.buffer),
			offset = u64(buf_view.byte_offset),
			size   = u64(buf_view.byte_length),
		}
	}

	for mesh in data.meshes {
		primitives, append_err := make([dynamic]Primitive, len = 0, cap = len(mesh.primitives))
		info: Mesh = {
			primitives = primitives,
		}
		for prim_info in mesh.primitives {
			prim: Primitive
			if indices, ok_indices := prim_info.indices.(gltf2.Integer); ok_indices {
				prim.indices = temp_buffer_views[indices]
			}
			if positions, ok_positions := prim_info.attributes["POSITION"]; ok_positions {
				prim.positions = temp_buffer_views[positions]
			}
			if normals, ok_normals := prim_info.attributes["NORMAL"]; ok_normals {
				prim.normals = temp_buffer_views[normals]
			}
			if tangents, ok_tangents := prim_info.attributes["TANGENT"]; ok_tangents {
				prim.tangents = temp_buffer_views[tangents]
			}
			if texcoords, ok_texcoords := prim_info.attributes["TEXCOORD_0"]; ok_texcoords {
				prim.texcoords = temp_buffer_views[texcoords]
			}
			if material, ok_material := prim_info.material.(gltf2.Integer); ok_material {
				prim.material = scene.materials[material]
			}
			append(&info.primitives, prim)
		}
		_, append_err = append(&scene.meshes, info)
		if append_err != nil {
			log.errorf("Could not append mesh: {}", append_err)
			ok = false
			return
		}
		log.infof("Loaded mesh: {}", mesh.name)
	}

	return
}

unload_scene :: proc(renderer: ^Renderer, scene: ^Scene) {
	for &scene_img in scene.images {
		resource_pool_remove_texture(&renderer.resource_pool, renderer, scene_img.handle)
		destroy_texture(&scene_img.texture, renderer)
	}
	delete(scene.images)

	for mat in scene.materials {
		resource_pool_remove_material(&renderer.resource_pool, renderer, mat)
	}
	delete(scene.materials)

	for &buf in scene.buffers {
		destroy_resizable_buffer(&buf, renderer)
	}
	delete(scene.buffers)

	for &mesh in scene.meshes {
		delete(mesh.primitives)
	}
	delete(scene.meshes)
	// destroy_resizable_buffer(&mesh.buffer, renderer)
}
