package main

import "base:runtime"
import "core:log"
import "core:mem"
import "shared:odd/flags"

/*
Forked a few procedures from odd/flags to support collecting any number of
arguments, even if it's an option, so they can be forwarded to git
*/

_Array :: struct {
	data:             []byte,
	elem, index:      ^runtime.Type_Info,
	count, elem_size: int,
}

get_value :: proc "contextless" () -> (string, bool) {
	arg: string
	if len(flags.optval) == 0 {
		flags.optarg = flags.get_arg(flags.optind)
		arg = flags.optarg
		flags.optind += 1
		return arg, true
	}
	arg = flags.optval
	flags.optarg = arg
	flags.optval = ""
	return arg, true
}

get_cstring :: proc(ptr: rawptr, id: typeid) -> bool {
	flags.assert_type(id, cstring)
	value, ok := get_value()
	if ok {
		if ptr != nil {(cast(^cstring)ptr)^ = cstring(raw_data(value))}
	} else {
		flags.missing_value()
	}
	return ok
}

get_string :: proc(ptr: rawptr, id: typeid) -> bool {
	flags.assert_type(id, string)
	value, ok := get_value()
	if ok {
		if ptr != nil {(cast(^string)ptr)^ = value}
	} else {
		flags.missing_value()
	}
	return ok
}

get_greedy_array :: proc(ptr: rawptr, id: typeid) -> bool {
	array: _Array

	args_count := len(flags.get_args()) - flags.optind
	final_optind := flags.optind + args_count

	slice_dyn_array :: proc(ptr: rawptr, elem_size, elem_align, count: int) -> ([]byte, bool) {
		if !runtime.__dynamic_array_resize(ptr, elem_size, elem_align, count) {
			log.error("%s: failed to reserve memory for the dynamic array", flags.optopt)
			return nil, false
		}
		dyn := cast(^runtime.Raw_Dynamic_Array)ptr
		// Don't forget the shadow header!
		// Spent a few hours to discover this
		dyn_data := rawptr(uintptr(dyn.data))
		return mem.byte_slice(dyn_data, count * elem_size), true
	}

	slice_fixed_dyn_array :: proc(ptr: rawptr, elem_size, capacity: int) -> ([]byte, bool) {
		len := cast(^int)rawptr(uintptr(ptr) + uintptr(capacity * elem_size))
		len^ = capacity
		return mem.byte_slice(ptr, capacity * elem_size), true
	}

	ti := flags.type_base(id)
	#partial switch v in ti.variant {
	case runtime.Type_Info_Dynamic_Array:
		data: []byte
		if ptr != nil {
			ok: bool
			data, ok = slice_dyn_array(ptr, v.elem_size, v.elem.align, args_count)
			if !ok {
				flags.optind = flags.optind + args_count
				return false
			}
		}
		array = {data, v.elem, nil, args_count, v.elem_size}
	case runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
		flags.too_many_args(v.capacity, args_count) or_return
		data: []byte
		if ptr != nil {
			data = slice_fixed_dyn_array(ptr, v.elem_size, args_count) or_return
		}
		array = {data, v.elem, nil, args_count, v.elem_size}
	case:
		panic("unreachable")
	}

	ok: bool
	switch array.elem.id {
	case cstring:
		values := transmute([]cstring)array.data

		count := array.count

		if array.data != nil {
			for i in 0 ..< count {
				get_cstring(&values[i], cstring) or_return
			}
		} else {
			for i in 0 ..< count {
				get_cstring(nil, cstring) or_return
			}
		}
	case string:
		values := transmute([]string)array.data

		count := array.count

		if array.data != nil {
			for i in 0 ..< count {
				get_string(&values[i], string) or_return
			}
		} else {
			for i in 0 ..< count {
				get_string(nil, string) or_return
			}
		}
	case:
		unimplemented("array")
	}
	if !ok {
		flags.optind = final_optind
	}
	return ok
}
