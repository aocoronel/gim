package main

import "base:runtime"
import "core:dynlib"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/debug"

Source_Code_Location :: runtime.Source_Code_Location

main :: proc() {
	debug.register_back_trace()

	context.allocator = context.temp_allocator

	log.Level_Headers = {
		0 ..< 10 = "debug: ",
		10 ..< 20 = "info: ",
		20 ..< 30 = "warning: ",
		30 ..< 40 = "error: ",
		40 ..< 50 = "fatal: ",
	}
	when ODIN_DEBUG {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color, .Short_File_Path, .Line}
	} else {
		LOGGER_OPT :: log.Options{.Level, .Terminal_Color}
	}
	context.logger = log.create_console_logger(opt = LOGGER_OPT)

	flags.parse_or_exit(&opt, os.args, .Odin)

	loc, ok := _main(&opt)

	when ODIN_DEBUG {
		if !ok {
			fmt.eprintfln("%v: error happened here", loc)
		}
	}

	cleanup()

	os.exit(cast(int)!ok)
}

cleanup :: proc() {
	delete(opt.args)
	log.destroy_console_logger(context.logger)
}

_main :: proc(opt: ^Option) -> (loc: Source_Code_Location, ok: bool) {
	loc = #location(exec)

	// Load this executable: requires -rdynamic
	lib := dynlib.load_library("", true) or_return
	defer dynlib.unload_library(lib)

	/*
    I usually do use switches to dispatch arguments. I wanted to do something different.
    Here we are reading the Option structure, specifically for string fields. We collect
    the field name and it's value, and we look at the binary symbols that match a procedure
    with the same field name.
    Adding new commands should be as simple as adding a field in Option, and making a procedure.
    */
	struct_info := runtime.type_info_base(type_info_of(Option)).variant.(runtime.Type_Info_Struct)
	opt_bytes := transmute([^]u8)opt
	for field, field_idx in struct_info.types[:struct_info.field_count] {
		col_idx := cast(i32)field_idx
		field_base := runtime.type_info_base(field)
		field_offs := struct_info.offsets[field_idx]
		#partial switch field_variant in field_base.variant {
		case runtime.Type_Info_String:
			name := struct_info.names[field_idx]
			if field_variant.is_cstring do continue
			value: string = (transmute(^string)&opt_bytes[field_offs])^
			if value == "" do continue
			exec(lib, name, value) or_return
		}
	}

	return {}, true
}

exec :: proc(
	lib: dynlib.Library,
	symbol_name: string,
	arg: string,
) -> (
	loc: Source_Code_Location,
	ok: bool,
) {
	loc = #location(exec)
	ptr, found := dynlib.symbol_address(lib, fmt.tprintf("%s", symbol_name))
	if !found {
		fmt.eprintln("Symbol not found:", symbol_name)
		return
	}
	cb := cast(Command)ptr
	return cb(arg)
}
