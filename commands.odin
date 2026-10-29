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
	args:      [dynamic]string,
	arg:       string,
	directory: string,
	dry_run:   bool,
	force:     bool,
	verbose:   bool,
}

opt: Option

all :: proc(procedure: proc() -> bool) -> bool {
	if !os.is_dir(opt.directory) {
		log.error("expected a directory")
		return false
	}

	files, err := os.read_directory_by_path(opt.directory, -1, context.allocator)

	if err != nil {
		log.error(os.error_string(err))
		return false
	}

	err_count: int
	for file in files {
		if file.type != .Directory do continue
		opt.directory = file.fullpath
		cd(opt.directory) or_return
		fmt.printfln(">> %s", file.name)
		if !procedure() do err_count += 1
	}

	if err_count > 0 {
		log.errorf("%d errors happened", err_count)
		return false
	}

	return true
}

push_today :: proc() -> bool {
	p: Pipe
	sh({"git", "log", "--since", "today"}, &p) or_return
	if len(p.stdout) == 0 {
		fmt.println("Nothing to do")
		return true
	}
	return sh({"git", "push"})
}

bundle :: proc() -> bool {
	return sh(
		{"git", "bundle", "create", fmt.tprintf("%s.bundle", os.base(opt.directory)), "--all"},
	)
}

not_clean :: proc() -> bool {
	p: Pipe
	ok := sh({"git", "status", "--porcelain"}, &p)
	if len(p.stdout) > 0 {
		fmt.printfln(">> %s", os.base(opt.directory))
		if opt.verbose {
			fmt.eprintln(string(p.stdout))
		}
	}
	if len(p.stderr) > 0 {
		fmt.eprintln(string(p.stderr))
	}
	return ok
}

bulk :: proc() -> bool {
	if !os.is_dir(opt.directory) {
		log.error("expected a directory")
		return false
	}

	files, err := os.read_directory_by_path(opt.directory, -1, context.allocator)

	if err != nil {
		log.error(os.error_string(err))
		return false
	}

	REPO_IDX :: 2
	splitten_cmd := opt.args[:]
	cmds: [dynamic]string

	append(&cmds, "git", "-C", "")
	for cmd in splitten_cmd {
		append(&cmds, cmd)
	}

	err_count: int
	for file in files {
		if file.type != .Directory do continue

		cmds[REPO_IDX] = file.fullpath
		p: pipe.Pipe
		ok := sh(cmds[:], &p)
		fmt.eprintln(string(p.stderr))
		if opt.verbose || !ok {
			fmt.eprintln(string(p.stdout))
		}

		if !ok do err_count += 1
	}

	if err_count > 0 {
		log.errorf("%d errors happened", err_count)
		return false
	}

	return true
}

addremove :: proc() -> bool {
	return sh({"git", "add", "--all", "--dry-run" if opt.dry_run else ""})
}

commit :: proc() -> bool {
	sh({"git", "pull"}) or_return

	sh({"git", "add", "-u", "--dry-run" if opt.dry_run else ""}) or_return

	splitten_cmd := opt.args[:]

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

news :: proc() -> bool {
	return sh({"git", "log", "--since", opt.arg})
}

clean :: proc() -> bool {
	sh({"git", "reset", "--hard"}) or_return
	return sh({"git", "clean", "-fdx", "-n" if opt.dry_run else ""})
}

update :: proc() -> (ok: bool) {
	sh({"git", "stash", "save", "--all"}, stdout = os.stdout if opt.verbose else nil) or_return
	ok = sh({"git", "pull"})
	sh({"git", "stash", "pop"}, stdout = os.stdout if opt.verbose else nil) or_return
	return
}

open :: proc() -> bool {
	if len(opt.args) == 0 {
		log.errorf("missing arguments")
		return false
	}

	branch: string
	splitten_cmd := opt.args[1:]

	if len(opt.args) > 1 && opt.args[1][0] != '-' {
		branch = opt.args[1]
		splitten_cmd = opt.args[2:]
	} else {
		branch = "main"
	}

	cmds: [dynamic]string

	append(&cmds, "git", "worktree", "add", opt.args[0], branch)
	for cmd in splitten_cmd {
		if cmd == "-B" {
			// The directory name is the branch name
			append(&cmds, "-B", os.base(opt.args[0]))
		} else {
			append(&cmds, cmd)
		}
	}

	return sh(cmds[:])
}

close :: proc() -> (ok: bool) {
	p: Pipe
	sh({"git", "status", "--porcelain"}, &p)
	if len(p.stdout) > 0 && !opt.force {
		log.errorf(
			"%q contains modified or untracked files, use --force to delete it",
			opt.directory,
		)
		return true
	}

	git_file := fmt.tprintf("%s/.git", opt.directory)
	content, err := os.read_entire_file(git_file, context.temp_allocator)
	if err != nil {
		log.errorf("not in a git repository")
		return
	}

	s := strings.trim_right(string(content), "\n")
	is_valid := strings.starts_with(s, "gitdir: ")
	if !is_valid {
		log.errorf("not in a git repository")
		return
	}

	worktree := s[len("gitdir: "):]

	err = os.remove_all(worktree)
	if err != nil {
		log.errorf("%s: %s", worktree, os.error_string(err))
	}

	files: []os.File_Info
	files, err = os.read_directory_by_path(opt.directory, -1, context.allocator)
	if err != nil {
		log.errorf("%s: %s", opt.directory, os.error_string(err))
		return false
	}

	err_count: int
	for file in files {
		err: os.Error
		#partial switch file.type {
		case .Directory:
			err = os.remove_all(file.fullpath)
		case:
			err = os.remove(file.fullpath)
		}
		if err != nil {
			log.errorf("%s: %s", file.fullpath, os.error_string(err))
			return false
		}
	}

	return ok
}
