package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/debug"
import "shared:odd/flags"

Source_Code_Location :: runtime.Source_Code_Location

main :: proc() {
	debug.register_backtrace()

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

	opts := []flags.Option {
		{"C,directory", `#arg=DIR
         Change directory`, &opt.directory, flags.get_string},
		{"dry-run", `Don't apply changes`, &opt.dry_run, flags.get_bool},
		{"verbose", `Show stdout messages`, &opt.verbose, flags.get_bool},
	}

	cmds := []flags.Option {
		{"bundle", `Bundle a repository`, &opt.bundle, flags.get_bool},
		{"bundle-all", `Bundle all repositories`, &opt.bundle_all, flags.get_bool},
		{"commit", `Stage changes and commit`, &opt.commit, get_rtti_array},
		{"not-clean", `Check if any repository is not clean`, &opt.not_clean, flags.get_bool},
		{"addremove", `Stages all changes`, &opt.addremove, flags.get_bool},
		{"run", `#arg=CMD
         Runs a command in all repositories`, &opt.run, get_rtti_array},
	}

	m, ferr := flags.init(opts)
	if !ferr do return

	command: string
	command_set: bool
	has_err: bool
	for flags.has_args_left() {
		err := flags.parse(m, opts)
		switch err {
		case .Ok:
			continue
		case .Dash_Dash:
		// rest := get_args()[optind:]
		case .Help_Request:
			fmt.println("Commands:")
			flags.usage(cmds)
			fmt.println("Options:")
			flags.usage(opts)
			return
		case .Not_Opt:
			if command_set {
				has_err = true
				log.errorf("The command %q was already specified", command)
				break
			}
			for c, i in cmds {
				if c.name == flags.optopt {
					command_set = true
					command = flags.optopt
					flags.call(cmds, cast(u32)i + 1, false)
					break
				}
			}
			if !command_set {
				has_err = true
				log.errorf("%s: command does not exist", flags.optopt)
			}
		case .Error:
			has_err = true
		}
	}
	if has_err do return

	if len(opt.directory) == 0 {
		err: os.Error
		opt.directory, err = os.get_working_directory(context.temp_allocator)
		if err != nil {
			log.error(os.error_string(err))
			return
		}
	}

	ok: bool
	switch command {
	case "addremove":
		ok = addremove()
	case "commit":
		ok = commit()
	case "bundle":
		ok = bundle()
	case "bundle-all":
		ok = bundle_all()
	case "not-clean":
		ok = not_clean()
	case "run":
		ok = run()
	}

	delete(m)
	log.destroy_console_logger(context.logger)

	os.exit(cast(int)!ok)
}
