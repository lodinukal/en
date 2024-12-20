package roassets

Mesh_Version :: enum i32 {
	_1,
	_2,
	_3,
	_4,
	_5,
	_6,
}

Mesh :: struct {}

Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
	tangent:  [4]f32,
	color:    [4]f32,
}

Envelope :: struct {
	bones:   [4]u32,
	weights: [4]f32,
}

Face :: [3]u32
LOD :: [dynamic]u32
