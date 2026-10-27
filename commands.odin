package main

import "core:fmt"
import "core:log"
import "core:os"
import "shared:odd/pipe"

Pipe :: pipe.Pipe
sh :: pipe.run_command

Command :: #type proc(arg: string) -> (Source_Code_Location, bool)

Option :: struct {
	run:        [dynamic]string,
	commit:     [dynamic]string,
	directory:  string,
	addremove:  bool,
	bundle:     bool,
	bundle_all: bool,
	not_clean:  bool,
	verbose:    bool,
	dry_run:    bool,
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
		log.errorf("%d errors happened", err_count)
		return
	}

	return true
}

bundle :: proc() -> (ok: bool) {
	ok = sh(
		{"git", "bundle", "create", fmt.tprintf("%s.bundle", opt.directory), "--all"},
		stdout = os.stdout if opt.verbose else nil,
	)
	return ok
}

bundle_all :: proc() -> (ok: bool) {
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

	iterate_dir(opt.directory, procedure) or_return
	return true
}

not_clean :: proc() -> (ok: bool) {
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

	iterate_dir(opt.directory, procedure) or_return
	return true
}

run :: proc() -> (ok: bool) {
	splitten_cmd := opt.run[:]

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
		p: pipe.Pipe
		ok := sh(cmd[:], &p)
		fmt.eprintln(string(p.stderr))
		if opt.verbose || !ok {
			fmt.eprintln(string(p.stdout))
		}
		return ok
	}

	iterate_dir(opt.directory, procedure, &cmds) or_return

	return true
}

addremove :: proc() -> (ok: bool) {
	if opt.dry_run {
		return sh({"git", "-C", opt.directory, "add", "--all", "--dry-run"})
	} else {
		return sh({"git", "-C", opt.directory, "add", "--all"})
	}
}

commit :: proc() -> (ok: bool) {
	sh({"git", "-C", opt.directory, "pull"}) or_return

	if opt.dry_run {
		sh({"git", "-C", opt.directory, "add", "-u", "--dry-run"}) or_return
	} else {
		sh({"git", "-C", opt.directory, "add", "-u"}) or_return
	}

	splitten_cmd := opt.commit[:]

	cmds: [dynamic]string

	append(&cmds, "git", "-C", opt.directory, "commit")
	if opt.dry_run {
		append(&cmds, "--dry-run")
	}
	for cmd in splitten_cmd {
		append(&cmds, cmd)
	}

	return sh(cmds[:])
}
