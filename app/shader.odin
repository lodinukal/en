package app

import "core:container/small_array"
import "core:log"
import "core:mem"
import "core:slice"
import sp "external:slang/slang"

import "en:gpu"

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

create_global_session :: proc() -> ^sp.IGlobalSession {
	using sp
	session: ^IGlobalSession
	slang_check(sp.createGlobalSession(sp.API_VERSION, &session))
	return session
}

destroy_global_session :: proc(global_session: ^sp.IGlobalSession) {
	global_session->release()
}

Shader_Stage :: enum {
	Compute,
	Vertex,
	Fragment,
}

Target :: enum u8 {
	DXIL  = 0,
	SPIRV = 1,
}

compile_shader :: proc(
	global_session: ^sp.IGlobalSession,
	path: cstring,
	stages: gpu.Stage_Flags,
	target: Target = .DXIL,
	allocator := context.allocator,
) -> (
	result: [Shader_Stage][]u8,
	ok: bool = true,
) {
	using sp
	code, diagnostics: ^IBlob
	r: Result

	target_dxil_desc := TargetDesc {
		structureSize = size_of(TargetDesc),
		format        = .DXIL,
		flags         = {},
		profile       = global_session->findProfile("sm_6_0"),
	}

	target_spirv_desc := TargetDesc {
		structureSize = size_of(TargetDesc),
		format        = .SPIRV,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = global_session->findProfile("sm_6_0"),
	}

	targets := [?]TargetDesc{target_dxil_desc, target_spirv_desc}

	compiler_option_entries := [?]CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {intValue0 = 1}},
	}
	session_desc := SessionDesc {
		structureSize            = size_of(SessionDesc),
		targets                  = raw_data(targets[:]),
		targetCount              = len(targets),
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = len(compiler_option_entries),
	}
	session: ^ISession
	slang_check(global_session->createSession(session_desc, &session))
	defer session->release()

	module: ^IModule = session->loadModule(path, &diagnostics)
	if module == nil {
		log.errorf("Shader compile error: {}", path)
	}
	diagnostics_check(diagnostics)
	defer module->release()

	components: [Shader_Stage]^IComponentType

	// compute
	if stages == {.Compute_Shader} {
		entry_point: ^IEntryPoint
		slang_check(module->findEntryPointByName("cs_main", &entry_point))
		if entry_point == nil {
			log.errorf("no compute shader entry point")
			return
		}
		components[.Compute] = entry_point
	} else if stages == {.Vertex_Shader, .Fragment_Shader} {
		vs_entry_point: ^IEntryPoint
		fs_entry_point: ^IEntryPoint
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

	for &output, stage in result {
		if components[stage] == nil do continue
		link_components := [2]^IComponentType{components[stage], module}

		linked_program: ^IComponentType
		r =
		session->createCompositeComponentType(
			raw_data(link_components[:]),
			2,
			&linked_program,
			&diagnostics,
		)
		diagnostics_check(diagnostics)
		slang_check(r)

		target_code: ^IBlob
		r = linked_program->getTargetCode(int(target), &target_code, &diagnostics)
		diagnostics_check(diagnostics)
		slang_check(r)

		code_size := target_code->getBufferSize()
		source_code := slice.from_ptr((^u8)(target_code->getBufferPointer()), auto_cast code_size)

		error: mem.Allocator_Error
		output, error = make([]u8, code_size, allocator)
		if error != nil {
			log.errorf("Failed to allocate memory for shader code")
			ok = false
			return
		}

		copy_slice(output, source_code)
	}


	return
}

free_shader :: proc(result: [Shader_Stage][]u8, allocator := context.allocator) {
	for output in result {
		if output == nil do continue
		free(raw_data(output), allocator)
	}
}