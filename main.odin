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
			help = `#arg=dir
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

	COMMIT :: ```
#arg=git-option
Stage changes and commit
```

	OPEN :: ```
#arg=path [commit-ish] [git-option],force
Create worktree

When using -B flag, omit the branch name
```

	ALL :: ```
#arg=gim-command
Runs a gim command in all repositories. Must be ran from a root of git repos
```

	BULK :: ```
#arg=git-command
Runs a git command in all repositories. Must be ran from a root of git repos

Pass --dry-run afterwards, if the command supports it
```

	cmds := []flags.Option {
		{name = "addremove", help = `Stages everything`},
		{name = "all", help = ALL},
		{name = "bulk", help = BULK, var = &opt.args, fn = get_greedy_array},
		{name = "bundle", help = `Bundle a repository`},
		{name = "clean", help = `Clean working tree`},
		{name = "close", help = `Remove worktree`},
		{name = "commit", help = COMMIT, var = &opt.args, fn = get_greedy_array},
		{name = "news", help = `Displays commits since`, var = &opt.arg, fn = flags.get_string},
		{name = "not-clean", help = `Check if any repository is not clean`},
		{name = "open", help = OPEN, var = &opt.args, fn = get_greedy_array},
		{name = "up", help = `#hidden`},
		{name = "push-today", help = `Push changes, if there`},
		{name = "update", help = `Update current checkout`},
	}

	m := flags.init(opts) or_return
	defer delete(m)

	command: string
	all_command, command_set: bool
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
			if flags.optopt == "all" {
				all_command = true
				break
			}
			if command_set {
				has_err = true
				log.errorf("The command %q was already specified", command)
				break
			}
			for c, i in cmds {
				if c.name == flags.optopt {
					command_set = true
					command = flags.optopt
					if c.fn != nil {
						flags.call(cmds, cast(u32)i + 1, false)
					}
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

	err: os.Error

	if len(opt.directory) == 0 {
		opt.directory, err = os.get_working_directory(context.allocator)
	} else {
		opt.directory, err = os.get_absolute_path(opt.directory, context.allocator)
	}

	if err != nil {
		log.error(os.error_string(err))
		return false
	}

	cd(opt.directory) or_return

	procedure := get_cmd(command)
	if procedure == nil do return false

	if all_command {
		if command == "bulk" {
			log.errorf("all command cannot be used with \"bulk\"")
			return false
		}
		return all(procedure)
	}

	return procedure()
}

cd :: proc(dir: string) -> bool {
	err := os.change_directory(opt.directory)
	if err != nil {
		log.errorf("%s: %s", opt.directory, os.error_string(err))
		return false
	}
	return true
}

get_cmd :: proc(command: string) -> #type proc() -> bool {
	switch command {
    // odinfmt: disable
	case "addremove":     return addremove
	case "bundle":        return bundle
    case "bulk":          return bulk
	case "clean":         return clean
	case "close":         return close
	case "commit":        return commit
	case "news":          return news
	case "not-clean":     return not_clean
	case "open":          return open
	case "push-today":    return push_today
	case "update", "up":  return update
    // odinfmt: enable
	}

	return nil
}
