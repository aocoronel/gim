package main
import "core:strconv"
import "core:strings"

import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/pipe"

Pipe :: pipe.Pipe
sh :: pipe.run_command

Command :: #type proc(arg: string) -> (Source_Code_Location, bool)

Option :: struct {
	bundle:     string `usage:"
    Bundle a repository.
    Takes a name to generate the repo.bundle."`,
	bundle_all: string `usage:"
    Bundle all repositories.
    Takes a path to the root of all repositories."`,
	not_clean:  string `usage:"
    Check if any repository is not clean.
    Takes a path to the root of all repositories."`,
	verbose:    bool `usage:"
    Show stdout messages"`,
	run:        string `usage:"
    Runs a command in all repositories.
    Takes a path to the root of all repositories.
    Requires -args"`,
	args:       cstring `usage:"
    Extra arguments.
    Used in: run"`,
}

opt: Option

Iterate_Dir_Callback :: #type proc(ctx: rawptr, file: os.File_Info) -> bool

iterate_dir :: proc(
	dir: string,
	procedure: Iterate_Dir_Callback,
	ctx: rawptr = nil,
) -> (
	ok: bool,
) {
	if !os.is_dir(dir) {
		log.error("expected a directory")
		return
	}

	files, err := os.read_directory_by_path(dir, -1, context.allocator)

	if err != nil {
		log.error(os.error_string(err))
		return
	}

	err_count: int
	for file in files {
		if file.type != .Directory do continue
		if !procedure(ctx, file) do err_count += 1
	}

	if err_count > 0 {
		log.errorf("Failed to bundle %d repositories", err_count)
		return
	}

	return true
}

@(export)
bundle :: proc(repo: string) -> (loc: Source_Code_Location, ok: bool) {
	loc = #location(bundle)
	ok = sh(
		{"git", "bundle", "create", fmt.tprintf("%s.bundle", repo), "--all"},
		stdout = os.stdout if opt.verbose else nil,
	)
	return loc if !ok else {}, ok
}

@(export)
bundle_all :: proc(dir: string) -> (loc: Source_Code_Location, ok: bool) {
	loc = #location(bundle_all)

	procedure :: proc(ctx: rawptr, file: os.File_Info) -> bool {
		if file.type != .Directory do return true
		return sh(
			{
				"git",
				"-C",
				file.fullpath,
				"bundle",
				"create",
				fmt.tprintf("%s.bundle", file.name),
				"--all",
			},
			stdout = os.stdout if opt.verbose else nil,
		)
	}

	iterate_dir(dir, procedure) or_return
	return {}, true
}

@(export)
not_clean :: proc(dir: string) -> (loc: Source_Code_Location, ok: bool) {
	loc = #location(not_clean)

	procedure :: proc(ctx: rawptr, file: os.File_Info) -> bool {
		if file.type != .Directory do return true
		p: Pipe
		ok := sh({"git", "-C", file.fullpath, "status", "--porcelain"}, &p)
		if len(p.stdout) > 0 {
			fmt.printfln(">> %s", file.name)
			if opt.verbose {
				fmt.eprintln(string(p.stdout))
			}
		}
		if len(p.stderr) > 0 {
			fmt.eprintln(string(p.stderr))
		}
		return ok
	}

	iterate_dir(dir, procedure) or_return
	return {}, true
}

@(export)
run :: proc(dir: string) -> (loc: Source_Code_Location, ok: bool) {
	loc = #location(run)

	if opt.args == nil {
		log.error("-args not set")
		return
	}

	splitten_cmd, err := strings.split(string(opt.args), " ")
	if err != nil {
		log.error(os.error_string(err))
		return
	}

	cmds: [dynamic]string

	REPO_IDX :: 2

	append(&cmds, "git", "-C", "")
	for cmd in splitten_cmd {
		append(&cmds, cmd)
	}

	procedure :: proc(ctx: rawptr, file: os.File_Info) -> bool {
		if file.type != .Directory do return true
		cmd := (cast(^[dynamic]string)ctx)^
		cmd[REPO_IDX] = file.fullpath
		ok := sh(cmd[:], stdout = os.stdout if opt.verbose else nil)
		return ok
	}

	iterate_dir(dir, procedure, &cmds) or_return

	return {}, true
}
