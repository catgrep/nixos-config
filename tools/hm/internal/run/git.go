// SPDX-License-Identifier: GPL-3.0-or-later

package run

import (
	"strings"
)

// Git drives git in one repository.
type Git struct {
	r    *Runner
	root string
}

// NewGit returns a Git for the repository at root.
func NewGit(r *Runner, root string) Git {
	return Git{r: r, root: root}
}

func (g Git) cmd(args ...string) Cmd {
	return Cmd{Prog: "git", Args: append([]string{"-C", g.root}, args...)}
}

// Dir returns the absolute .git directory, which differs from root/.git in
// a worktree.
func (g Git) Dir() (string, error) {
	out, err := g.r.Output(g.cmd("rev-parse", "--absolute-git-dir"))
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// Dirty lists the given paths that have uncommitted changes, staged or
// not, relative to root. Untracked files count as dirty.
func (g Git) Dirty(paths ...string) ([]string, error) {
	args := append([]string{"status", "--porcelain", "--untracked-files=all", "--"}, paths...)
	out, err := g.r.Output(g.cmd(args...))
	if err != nil {
		return nil, err
	}
	var dirty []string
	for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if len(line) > 3 {
			dirty = append(dirty, strings.TrimSpace(line[3:]))
		}
	}
	return dirty, nil
}

// Add stages paths, so a file hm created is visible to a flake evaluation.
func (g Git) Add(paths ...string) error {
	return g.r.Do(g.cmd(append([]string{"add", "--"}, paths...)...))
}

// Commit commits only paths with the given subject and, when body is not
// empty, that body as a second paragraph.
func (g Git) Commit(subject, body string, paths ...string) error {
	return g.r.Do(g.commit(subject, body, paths))
}

// CommitCommand renders the commit command for the user to run by hand.
func (g Git) CommitCommand(subject, body string, paths ...string) string {
	return g.commit(subject, body, paths).String()
}

func (g Git) commit(subject, body string, paths []string) Cmd {
	args := []string{"commit", "-m", subject}
	if body != "" {
		args = append(args, "-m", body)
	}
	args = append(args, "--")
	return g.cmd(append(args, paths...)...)
}
