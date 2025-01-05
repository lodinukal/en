package app

import "core:container/small_array"
import "core:dynlib"
import "core:log"
import "core:mem"
import "core:slice"
import sp "external:slang/slang"

import "en:mercury"

slang_check :: #force_inline proc(#any_int result: int, loc := #caller_location) {
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

		log.panicf("Failed with error: %v (%v) Facility: %v", estr, code, facility, location = loc)
	}
}

diagnostics_check :: #force_inline proc(diagnostics: ^sp.IBlob, loc := #caller_location) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(
			diagnostics->getBufferPointer(),
			int(diagnostics->getBufferSize()),
		)
		assert(false, string(buffer), loc)
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
	session:        ^sp.ISession,
}

create_shader_context :: proc(ctx: ^Shader_Context) -> (ok: bool = true) {
	// attempt to load
	if slang_lib.__handle == nil {
		count := dynlib.initialize_symbols(&slang_lib, "slang", "slang_") or_return
		if count != 2 {
			log.warnf("Could only load {} symbols", count)
			return false
		}
	}
	slang_check(slang_lib.createGlobalSession(sp.API_VERSION, &ctx.global_session))
	sm_6_profile := ctx.global_session->findProfile("sm_6_0")
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

	targets := [?]sp.TargetDesc{target_dxil_desc, target_spirv_desc, target_msl_desc}

	compiler_option_entries := [?]sp.CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {intValue0 = 1}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 0, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 1, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 2, intValue1 = 0}},
		{name = .VulkanBindShiftAll, value = {intValue0 = 3, intValue1 = 0}},
		{
			name = .DisableWarning,
			value = {kind = .String, stringValue0 = "profileImplicitlyUpgraded"},
		},
	}
	session_desc := sp.SessionDesc {
		structureSize            = size_of(sp.SessionDesc),
		targets                  = raw_data(targets[:]),
		targetCount              = len(targets),
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = len(compiler_option_entries),
	}
	slang_check(ctx.global_session->createSession(session_desc, &ctx.session))

	return
}

destroy_shader_context :: proc(ctx: ^Shader_Context) {
	if ctx == nil do return
	ctx.session->release()
	ctx.global_session->release()
	if slang_lib.__handle != nil {
		slang_lib.shutdown()
		dynlib.unload_library(slang_lib.__handle)
		slang_lib.__handle = nil
	}
}

Shader_Stage :: enum {
	Compute,
	Vertex,
	Fragment,
}

@(private = "file")
MAX_LINK_COMPONENTS :: 6
@(private = "file")
Component_Small_Array :: small_array.Small_Array(MAX_LINK_COMPONENTS, ^sp.IComponentType)

compile_shader :: proc(
	ctx: ^Shader_Context,
	path: cstring,
	stages: mercury.Stage_Flags,
	allocator := context.allocator,
) -> (
	result: [Shader_Stage][mercury.Shader_Target][]u8,
	ok: bool = true,
) {
	if ctx == nil {
		log.errorf("No context")
		ok = false
		return
	}
	diagnostics: ^sp.IBlob
	r: sp.Result

	module: ^sp.IModule = ctx.session->loadModule(path, &diagnostics)
	if module == nil {
		log.errorf("Shader compile error: {}", path)
	}
	diagnostics_check(diagnostics)
	defer module->release()

	components: [Shader_Stage]^sp.IComponentType

	// compute
	if stages == {.Compute_Shader} {
		entry_point: ^sp.IEntryPoint
		slang_check(module->findEntryPointByName("cs_main", &entry_point))
		if entry_point == nil {
			log.errorf("no compute shader entry point")
			return
		}
		components[.Compute] = entry_point
	} else if stages == {.Vertex_Shader, .Fragment_Shader} {
		vs_entry_point: ^sp.IEntryPoint
		fs_entry_point: ^sp.IEntryPoint
		slang_check(module->findEntryPointByName("vs_main", &vs_entry_point))
		slang_check(module->findEntryPointByName("fs_main", &fs_entry_point))

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
		ctx.session->createCompositeComponentType(
			raw_data(small_array.slice(&composing)),
			small_array.len(composing),
			&composed_program,
			&diagnostics,
		)
		diagnostics_check(diagnostics)
		slang_check(r)

		linked_program: ^sp.IComponentType
		r = composed_program->link(&linked_program, &diagnostics)
		diagnostics_check(diagnostics)
		slang_check(r)

		for &output, target in output_set {
			target_code: ^sp.IBlob
			r = linked_program->getEntryPointCode(0, int(target), &target_code, &diagnostics)
			diagnostics_check(diagnostics)
			slang_check(r)
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

free_shader :: proc(result: [Shader_Stage][]u8, allocator := context.allocator) {
	for output in result {
		if output == nil do continue
		free(raw_data(output), allocator)
	}
}
