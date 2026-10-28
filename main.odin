package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/debug"
import "shared:odd/flags"

Source_Code_Location :: runtime.Source_Code_Location

main :: proc() {ok := _main(); os.exit(cast(int)!ok)}

_main :: proc() -> bool {
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
	defer log.destroy_console_logger(context.logger)

	opts := []flags.Option {
		{
			name = "C,directory",
			help = `#arg=DIR
 Change directory`,
			var = &opt.directory,
			fn = flags.get_string,
		},
		{name = "dry-run", help = `Don't apply changes`, var = &opt.dry_run, fn = flags.get_bool},
		{name = "verbose", help = `Show stdout messages`, var = &opt.verbose, fn = flags.get_bool},
		{
			name = "force",
			help = `Ignore destructive warnings`,
			var = &opt.force,
			fn = flags.get_bool,
		},
	}

	cmds := []flags.Option {
		{name = "clean", help = `Clean working tree`, var = &opt.clean, fn = flags.get_bool},
		{
			name = "close",
			help = `#arg=path
 Remove worktree`,
			var = &opt.close,
			fn = flags.get_bool,
		},
		{
			name = "open",
			help = `#arg=path [commit-ish] [git-option],force
 Create worktree`,
			var = &opt.open,
			fn = get_greedy_array,
		},
		{name = "bundle", help = `Bundle a repository`, var = &opt.bundle, fn = flags.get_bool},
		{
			name = "bundle-all",
			help = `
 Bundle all repositories.
 Must be ran from a root of git repos`,
			var = &opt.bundle_all,
			fn = flags.get_bool,
		},
		{
			name = "commit",
			help = `#arg=git-option
 Stage changes and commit`,
			var = &opt.commit,
			fn = get_greedy_array,
		},
		{
			name = "not-clean",
			help = `
 Check if any repository is not clean.
 Must be ran from a root of git repos`,
			var = &opt.not_clean,
			fn = flags.get_bool,
		},
		{
			name = "addremove",
			help = `Stages everything`,
			var = &opt.addremove,
			fn = flags.get_bool,
		},
		{
			name = "all",
			help = `#arg=CMD
 Runs a command in all repositories.
 Must be ran from a root of git repos

 Pass --dry-run afterwards, if the command supports it`,
			var = &opt.all,
			fn = get_greedy_array,
		},
	}

	m := flags.init(opts) or_return
	defer delete(m)

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
			fmt.println("Usage:", flags.get_args()[0], "[option]", "command")
			fmt.println("Commands:")
			flags.usage(cmds)
			fmt.println("Options:")
			flags.usage(opts)
			return true
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
	if has_err do return false

	if len(opt.directory) == 0 {
		err: os.Error
		opt.directory, err = os.get_working_directory(context.temp_allocator)
		if err != nil {
			log.error(os.error_string(err))
			return false
		}
	}

	{
		err := os.change_directory(opt.directory)
		if err != nil {
			log.errorf("%s: %s", opt.directory, os.error_string(err))
			return false
		}
	}

	ok := run_cmd(command)

	return ok
}

run_cmd :: proc(command: string) -> bool {
	switch command {
    // odinfmt: disable
	case "addremove":  return addremove()
	case "all":        return all()
	case "bundle":     return bundle()
	// TBD: port _all commands to all
	case "bundle-all": return bundle_all()
	case "clean":      return clean()
	case "close":      return close()
	case "commit":     return commit()
	case "not-clean":  return not_clean()
	case "open":       return open()
    // odinfmt: enable
	}
	return false
}
