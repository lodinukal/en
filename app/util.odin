package app

import "core:log"
import "core:strings"
import "en:gpu"
import "vendor:stb/image"

texture_from_file :: proc(
	renderer: ^Renderer,
	file: string,
) -> (
	texture: Texture,
	ok: bool = true,
) {
	texture.desc.type = ._2D
	texture.desc.layer_num = 1
	texture.desc.mip_num = 1
	texture.desc.format = .RGBA8_UNORM
	texture.desc.usage = {.Shader_Resource}
	width, height: i32 = 0, 0
	channels_in_file: i32 = 0
	data := image.load(
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

	texture.desc.width = u16(width)
	texture.desc.height = u16(height)

	if err := init_texture(&texture, renderer); err != nil {
		ok = false
		log.infof("Could not init texture: {}", err)
		return
	}
	texture_set_name(&texture, file, renderer)

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
		gpu.ACCESS_LAYOUT_STAGE_SHADER_RESOURCE,
	); err != nil {
		ok = false
		log.infof("Could not upload texture: {}", err)
		return
	}

	return
}
