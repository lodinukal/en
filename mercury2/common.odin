package mercury

import "core:container/small_array"
import "core:log"
import "core:mem"
import "core:reflect"

Result :: enum {
	Ok,
	Out_Of_Memory,
	Invalid_Parameter,
	Unknown,
	Device_Removed,
}

MAX_RANGES_PER_DESCRIPTOR_SET :: 8
MAX_VERTEX_STREAMS :: 8
MAX_VERTEX_ATTRIBUTES :: 16

USE_D3D12 :: #config(USE_D3D12, ODIN_OS == .Windows)
USE_VULKAN :: #config(USE_VULKAN, ODIN_OS == .Windows || ODIN_OS == .Linux)
USE_METAL :: #config(USE_METAL, ODIN_OS == .Darwin)

MAX_FRAMES_IN_FLIGHT :: #config(MAX_FRAMES_IN_FLIGHT, 2)
