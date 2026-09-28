// SPDX-License-Identifier: GPL-3.0-or-later

package run

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCmdString(t *testing.T) {
	c := Cmd{Prog: "git", Args: []string{"commit", "-m", "home: add zizmor 1.30.1", "--", "a b", "c'd", ""}}
	want := `git commit -m 'home: add zizmor 1.30.1' -- 'a b' 'c'\''d' ''`
	if got := c.String(); got != want {
		t.Errorf("String() = %s, want %s", got, want)
	}
}

func TestOutputRunsInDryRun(t *testing.T) {
	var trace bytes.Buffer
	r := &Runner{DryRun: true, Trace: &trace}
	out, err := r.Output(Cmd{Prog: "sh", Args: []string{"-c", "echo hi"}})
	if err != nil || string(out) != "hi\n" {
		t.Fatalf("Output = %q, %v", out, err)
	}
	if trace.Len() != 0 {
		t.Errorf("read-only command was traced: %q", trace.String())
	}
}

func TestOutputErrorCarriesStderr(t *testing.T) {
	r := &Runner{}
	_, err := r.Output(Cmd{Prog: "sh", Args: []string{"-c", "echo 'mvs: zizmor is not in the index' >&2; exit 1"}})
	var exit *ExitError
	if !errors.As(err, &exit) || exit.Code != 1 {
		t.Fatalf("err = %v", err)
	}
	if !strings.Contains(err.Error(), "zizmor is not in the index") || !strings.Contains(err.Error(), "exit 1") {
		t.Errorf("error message = %q", err)
	}
}

func TestDoIsSkippedInDryRun(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "ran")
	var trace bytes.Buffer
	r := &Runner{DryRun: true, Trace: &trace}
	if err := r.Do(Cmd{Prog: "touch", Args: []string{marker}}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err == nil {
		t.Error("dry run executed the command")
	}
	if got := trace.String(); got != "+ touch "+marker+"\n" {
		t.Errorf("trace = %q", got)
	}
	r.DryRun = false
	if err := r.Do(Cmd{Prog: "touch", Args: []string{marker}}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Error("real run did not execute the command")
	}
}

func TestMissingProgram(t *testing.T) {
	r := &Runner{}
	_, err := r.Output(Cmd{Prog: "hm-definitely-missing-program"})
	if err == nil || !strings.Contains(err.Error(), "not found on PATH") {
		t.Errorf("err = %v", err)
	}
}

// fakeMvs writes a script that prints canned JSON for each mvs verb and
// records its arguments.
func fakeMvs(t *testing.T) (bin string, argsFile string) {
	t.Helper()
	dir := t.TempDir()
	argsFile = filepath.Join(dir, "args")
	script := `#!/bin/sh
echo "$@" >> ` + argsFile + `
case "$*" in
  *"lock add"*) echo '{"attr":"zizmor","pin":{"date":"2026-09-17","label":"2026-09-17-e554fab72f81","rev":"e554fab","version":"1.30.1"}}' ;;
  *"lock rm"*) echo '{"attr":"zizmor","removed":{"version":"1.30.1","label":"l"}}' ;;
  *"lock update"*) echo '{"moved":[{"attr":"zizmor","from":{"version":"1.30.0","label":"a"},"to":{"version":"1.30.1","label":"b"}}]}' ;;
  *"lock status"*) echo '{"pins":[{"attr":"acl","version":"2.4.0","latest":"2.4.0","versions_behind":0,"days_behind":0}]}' ;;
  *"lock minimize"*) echo '{"after":4,"before":5,"moved":[{}],"pins":139,"why":"x"}'; exit 1 ;;
  *"query search"*) echo '{"matches":[{"attr":"zizmor","version":"1.30.1","gone":false}],"pattern":"ziz*","truncated":false}' ;;
  *) echo "mvs: unknown $*" >&2; exit 2 ;;
esac
`
	bin = filepath.Join(dir, "mvs")
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return bin, argsFile
}

func TestMvs(t *testing.T) {
	bin, argsFile := fakeMvs(t)
	m := NewMvs(&Runner{}, []string{bin}, "/repo/multiverse.lock")

	attr, pin, err := m.Add("zizmor")
	if err != nil || attr != "zizmor" || pin.Version != "1.30.1" || pin.Label != "2026-09-17-e554fab72f81" {
		t.Errorf("Add = %q %+v %v", attr, pin, err)
	}
	if removed, err := m.Rm("zizmor"); err != nil || removed.Version != "1.30.1" {
		t.Errorf("Rm = %+v %v", removed, err)
	}
	moved, err := m.Update("zizmor")
	if err != nil || len(moved) != 1 || moved[0].From.Version != "1.30.0" || moved[0].To.Version != "1.30.1" {
		t.Errorf("Update = %+v %v", moved, err)
	}
	if status, err := m.Status(); err != nil || len(status) != 1 || status[0].Attr != "acl" {
		t.Errorf("Status = %+v %v", status, err)
	}
	min, err := m.MinimizeCheck()
	if err != nil || min.Before != 5 || min.After != 4 || len(min.Moved) != 1 {
		t.Errorf("MinimizeCheck = %+v %v", min, err)
	}
	if matches, err := m.Search("ziz*", 10); err != nil || len(matches) != 1 || matches[0].Attr != "zizmor" {
		t.Errorf("Search = %+v %v", matches, err)
	}
	args, _ := os.ReadFile(argsFile)
	first := strings.Split(string(args), "\n")[0]
	if want := "--json --file /repo/multiverse.lock lock add zizmor"; first != want {
		t.Errorf("first call = %q, want %q", first, want)
	}
	if !strings.Contains(string(args), "--file /tmp/other.lock") {
		other := m.WithLock("/tmp/other.lock")
		if _, _, err := other.Add("zizmor"); err != nil {
			t.Fatal(err)
		}
		args, _ = os.ReadFile(argsFile)
		if !strings.Contains(string(args), "--file /tmp/other.lock lock add zizmor") {
			t.Errorf("WithLock did not change the lock path: %s", args)
		}
	}
}

func TestMvsViaLeadingArguments(t *testing.T) {
	bin, argsFile := fakeMvs(t)
	m := NewMvs(&Runner{}, []string{"sh", bin}, "/repo/multiverse.lock")
	if _, _, err := m.Add("zizmor"); err != nil {
		t.Fatal(err)
	}
	args, _ := os.ReadFile(argsFile)
	if !strings.HasPrefix(string(args), "--json --file /repo/multiverse.lock lock add zizmor") {
		t.Errorf("args = %q", args)
	}
}

func TestGitDirty(t *testing.T) {
	root := t.TempDir()
	r := &Runner{}
	git := NewGit(r, root)
	for _, args := range [][]string{{"init", "-q"}, {"config", "user.email", "t@example.com"}, {"config", "user.name", "t"}, {"config", "commit.gpgsign", "false"}} {
		if _, err := r.Output(Cmd{Prog: "git", Args: append([]string{"-C", root}, args...)}); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "a.nix"), []byte("[\n]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := git.Add("a.nix"); err != nil {
		t.Fatal(err)
	}
	if err := git.Commit("home: add a", "the body", "a.nix"); err != nil {
		t.Fatal(err)
	}
	if out, err := r.Output(Cmd{Prog: "git", Args: []string{"-C", root, "log", "-1", "--format=%s%n%n%b"}}); err != nil || !strings.HasPrefix(string(out), "home: add a\n\nthe body\n") {
		t.Errorf("commit message = %q, %v", out, err)
	}
	dirty, err := git.Dirty("a.nix", "b.nix")
	if err != nil || len(dirty) != 0 {
		t.Fatalf("Dirty = %v, %v", dirty, err)
	}
	if err := os.WriteFile(filepath.Join(root, "a.nix"), []byte("[\n  \"x\"\n]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "b.nix"), []byte("[\n]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirty, err = git.Dirty("a.nix", "b.nix")
	if err != nil || strings.Join(dirty, ",") != "a.nix,b.nix" {
		t.Errorf("Dirty = %v, %v", dirty, err)
	}
	dir, err := git.Dir()
	if err != nil || filepath.Base(dir) != ".git" {
		t.Errorf("Dir = %q, %v", dir, err)
	}
	if got := git.CommitCommand("home: add x", "", "a.nix"); got != "git -C "+root+" commit -m 'home: add x' -- a.nix" {
		t.Errorf("CommitCommand = %q", got)
	}
	if got := git.CommitCommand("home: add go x", "example.com/x@v1.0.0", "a.nix"); got != "git -C "+root+" commit -m 'home: add go x' -m example.com/x@v1.0.0 -- a.nix" {
		t.Errorf("CommitCommand with a body = %q", got)
	}
}
