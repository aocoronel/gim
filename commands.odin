package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "shared:odd/pipe"

Pipe :: pipe.Pipe
sh :: pipe.run_command

Command :: #type proc(arg: string) -> (Source_Code_Location, bool)

Option :: struct {
	all:        [dynamic]string,
	commit:     [dynamic]string,
	open:       [dynamic]string,
	clean:      bool,
	close:      bool,
	directory:  string,
	addremove:  bool,
	bundle:     bool,
	bundle_all: bool,
	not_clean:  bool,
	verbose:    bool,
	force:      bool,
	dry_run:    bool,
	update:     bool,
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
		if !procedure(ctx, file) do err_count += 1
	}

	if err_count > 0 {
		log.errorf("%d errors happened", err_count)
		return
	}

	return true
}

bundle :: proc() -> (ok: bool) {
	ok = sh({"git", "bundle", "create", fmt.tprintf("%s.bundle", os.base(opt.directory)), "--all"})
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

all :: proc() -> (ok: bool) {
	splitten_cmd := opt.all[:]

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
		return sh({"git", "add", "--all", "--dry-run"})
	} else {
		return sh({"git", "add", "--all"})
	}
}

commit :: proc() -> (ok: bool) {
	sh({"git", "pull"}) or_return

	if opt.dry_run {
		sh({"git", "add", "-u", "--dry-run"}) or_return
	} else {
		sh({"git", "add", "-u"}) or_return
	}

	splitten_cmd := opt.commit[:]

	cmds: [dynamic]string

	append(&cmds, "git", "commit")
	if opt.dry_run {
		append(&cmds, "--dry-run")
	}
	for cmd in splitten_cmd {
		append(&cmds, cmd)
	}

	sh(cmds[:]) or_return

	return sh({"git", "push"})
}

clean :: proc() -> (ok: bool) {
	sh({"git", "reset", "--hard"}) or_return
	return sh({"git", "clean", "-fdx", "-n" if opt.dry_run else ""})
}

update :: proc() -> (ok: bool) {
	sh({"git", "stash", "save", "--all"}, stdout = nil) or_return
	ok = sh({"git", "pull"})
	sh({"git", "stash", "pop"}, stdout = nil) or_return
	return ok
}

open :: proc() -> (ok: bool) {
	if len(opt.open) == 0 {
		log.errorf("missing arguments")
		return false
	}

	branch: string
	splitten_cmd := opt.open[1:]

	if len(opt.open) > 1 && opt.open[1][0] != '-' {
		branch = opt.open[1]
		splitten_cmd = opt.open[2:]
	} else {
		branch = "main"
	}

	cmds: [dynamic]string

	append(&cmds, "git", "worktree", "add", opt.open[0], branch)
	for cmd in splitten_cmd {
		if cmd == "-B" {
			// The directory name is the branch name
			append(&cmds, "-B", opt.open[0])
		} else {
			append(&cmds, cmd)
		}
	}

	return sh(cmds[:])
}

close :: proc() -> (ok: bool) {
	ok = true
	p: Pipe
	sh({"git", "status", "--porcelain"}, &p)
	if len(p.stdout) > 0 && !opt.force {
		log.errorf(
			"%q contains modified or untracked files, use --force to delete it",
			opt.directory,
		)
		return ok
	}

	content, err := os.read_entire_file(
		fmt.tprintf("%s/.git", opt.directory),
		context.temp_allocator,
	)
	if err != nil {
		log.errorf("not in a git repository")
		return false
	}

	s := strings.trim_right(string(content), "\n")
	is_valid := strings.starts_with(s, "gitdir: ")
	if !is_valid {
		log.errorf("not in a git repository")
		return false
	}

	worktree := s[len("gitdir: "):]

	err = os.remove_all(worktree)
	if err != nil {
		log.errorf("%s: %s", worktree, os.error_string(err))
		ok = false
	}

	procedure :: proc(ctx: rawptr, file: os.File_Info) -> bool {
		err: os.Error

		#partial switch file.type {
		case .Directory:
			err = os.remove_all(file.fullpath)
		case .Regular, .Symlink:
			err = os.remove(file.fullpath)
		case:
			log.errorf("%s: cannot remove", file.fullpath)
			return false
		}

		if err != nil {
			log.errorf("%s: %s", file.fullpath, os.error_string(err))
			return false
		}

		return true
	}

	iterate_dir(opt.directory, procedure) or_return

	return ok
}
