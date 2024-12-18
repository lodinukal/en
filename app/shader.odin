package app

import "core:container/small_array"
import "core:log"
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

compile_shader :: proc(
	global_session: ^sp.IGlobalSession,
	path: cstring,
	stages: gpu.Stage_Flags,
) -> (
	result: [Shader_Stage][]u8,
	ok: bool,
) {
	using sp
	code, diagnostics: ^IBlob
	r: Result

	target_desc := TargetDesc {
		structureSize = size_of(TargetDesc),
		format        = .DXIL,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = global_session->findProfile("sm_6_0"),
	}

	compiler_option_entries := [?]CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {intValue0 = 1}},
	}
	session_desc := SessionDesc {
		structureSize            = size_of(SessionDesc),
		targets                  = &target_desc,
		targetCount              = 1,
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = 1,
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

	components: small_array.Small_Array(len(Shader_Stage) + 1, ^IComponentType)

	// compute
	if stages == {.Compute_Shader} {
		entry_point: ^IEntryPoint
		slang_check(module->findEntryPointByName("cs_main", &entry_point))
		if entry_point == nil {
			log.errorf("no compute shader entry point")
			return
		}
		small_array.append(&components, entry_point)
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

		small_array.append(&components, vs_entry_point)
		if fs_entry_point != nil {
			small_array.append(&components, fs_entry_point)
		}
	}

	linked_program: ^IComponentType
	r =
	session->createCompositeComponentType(
		raw_data(components.data[:]),
		small_array.len(components),
		&linked_program,
		&diagnostics,
	)
	diagnostics_check(diagnostics)
	slang_check(r)

	target_code: ^IBlob
	r = linked_program->getTargetCode(0, &target_code, &diagnostics)
	diagnostics_check(diagnostics)
	slang_check(r)

	code_size := target_code->getBufferSize()
	source_code := slice.bytes_from_ptr(target_code->getBufferPointer(), auto_cast code_size)


	return
}
