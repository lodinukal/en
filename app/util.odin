package app

import "core:fmt"
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

	if err := init_ren_texture(&texture, renderer); err != nil {
		ok = false
		log.infof("Could not init texture: {}", err)
		return
	}
	ren_texture_set_name(&texture, name, renderer)

	subresource: Texture_Subresource_Upload_Desc
	subresource.slices = data
	subresource.slice_num = 1
	subresource.row_pitch, subresource.slice_pitch = compute_pitch(
		.RGBA8_UNORM,
		u32(texture.desc.width),
		u32(texture.desc.height),
	)

	if err := ren_texture_upload(
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

Scene_Image :: struct {
	handle:  Image_Handle,
	texture: Texture,
}

Scene :: struct {
	images:    [dynamic]Scene_Image,
	materials: [dynamic]Material_Handle,
	meshes:    [dynamic][dynamic]Material_Geometry_Pair,
}

init_scene :: proc(scene: ^Scene, renderer: ^Renderer, name := "scene") {
}

deinit_scene :: proc(scene: ^Scene, renderer: ^Renderer) {
	for &scene_img in scene.images {
		resource_pool_remove_texture(renderer, scene_img.handle)
		deinit_ren_texture(&scene_img.texture, renderer)
	}
	delete(scene.images)

	for mat in scene.materials {
		resource_pool_remove_material(renderer, mat)
	}
	delete(scene.materials)

	for &mesh in scene.meshes {
		delete(mesh)
	}
	delete(scene.meshes)
}

import "base:runtime"

// ending with .gltf or .glb
// returns a list of meshes with their primitives
load_gltf_file_into :: proc(
	renderer: ^Renderer,
	file: string,
	scene: ^Scene,
	allocator := context.allocator,
) -> (
	ok: bool = true,
) {
	context.logger = runtime.default_logger()

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
			img_handle, add_tex_ok := resource_pool_add_texture(renderer, tex.srv)
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
		mat_handle, add_mat_ok := resource_pool_add_material(renderer, info)
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

	if reserve_dynamic_array(&scene.meshes, len(scene.meshes) + len(data.meshes)) != nil {
		log.errorf("Could not reserve memory for meshes")
		ok = false
		return
	}

	for mesh in data.meshes {
		mesh_primitives := make([dynamic]Material_Geometry_Pair, len(mesh.primitives))
		for prim_info in mesh.primitives {
			geom: Geometry
			index_accessor := prim_info.indices.(gltf2.Integer)
			geom.indices = make(
				[]u16,
				data.accessors[index_accessor].count,
				context.temp_allocator,
			)
			fmt.printfln("Index count: {}", data.accessors[index_accessor].count)
			if data.accessors[index_accessor].component_type == .Unsigned_Short {
				for it := gltf2.buf_iter_make(u16, &data.accessors[index_accessor], data);
				    it.idx < it.count;
				    it.idx += 1 {
					if it.idx == 0 do fmt.printfln("Index u16: {}", gltf2.buf_iter_elem(&it))
					geom.indices[it.idx] = gltf2.buf_iter_elem(&it)
				}
			} else {
				// assume u32
				for it := gltf2.buf_iter_make(u32, &data.accessors[index_accessor], data);
				    it.idx < it.count;
				    it.idx += 1 {
					if it.idx == 0 do fmt.printfln("Index u32: {}", gltf2.buf_iter_elem(&it))
					geom.indices[it.idx] = u16(gltf2.buf_iter_elem(&it))
				}
			}

			geom.vertices = make(
				[]Vertex_Default,
				data.accessors[prim_info.attributes["POSITION"]].count,
				context.temp_allocator,
			)
			if position_accessor, ok_position := prim_info.attributes["POSITION"]; ok_position {
				fmt.printfln("Position count: {}", data.accessors[position_accessor].count)
				for it := gltf2.buf_iter_make([3]f32, &data.accessors[position_accessor], data);
				    it.idx < it.count;
				    it.idx += 1 {
					if it.idx == 0 do fmt.printfln("Position: {}", gltf2.buf_iter_elem(&it))
					geom.vertices[it.idx].position = gltf2.buf_iter_elem(&it)
				}
			}

			if normal_accessor, ok_normal := prim_info.attributes["NORMAL"]; ok_normal {
				fmt.printfln("Normal count: {}", data.accessors[normal_accessor].count)
				for it := gltf2.buf_iter_make([3]f32, &data.accessors[normal_accessor], data);
				    it.idx < it.count;
				    it.idx += 1 {
					if it.idx == 0 do fmt.printfln("Normal: {}", gltf2.buf_iter_elem(&it))
					geom.vertices[it.idx].normal = gltf2.buf_iter_elem(&it)
				}
			}

			if texcoord_accessor, ok_texcoord := prim_info.attributes["TEXCOORD_0"]; ok_texcoord {
				fmt.printfln("Texcoord count: {}", data.accessors[texcoord_accessor].count)
				for it := gltf2.buf_iter_make([2]f32, &data.accessors[texcoord_accessor], data);
				    it.idx < it.count;
				    it.idx += 1 {
					if it.idx == 0 do fmt.printfln("Texcoord: {}", gltf2.buf_iter_elem(&it))
					geom.vertices[it.idx].texcoord = gltf2.buf_iter_elem(&it)
				}
			}

			loaded: Material_Geometry_Pair
			if handle, ok_handle := resource_pool_add_geometry(renderer, geom); !ok_handle {
				log.errorf("Could not add primitive to resource pool")
				ok = false
				return
			} else {
				loaded.handle = handle
			}

			if material, ok_material := prim_info.material.(gltf2.Integer); ok_material {
				loaded.material = scene.materials[uint(material)]
			}

			append(&mesh_primitives, loaded)
		}
		append(&scene.meshes, mesh_primitives)
	}

	return
}
