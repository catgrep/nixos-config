// SPDX-License-Identifier: GPL-3.0-or-later

// Package run executes the programs hm drives (mvs, nix, nh, git) as typed
// calls, so every subcommand shares one notion of what a dry run prints and
// how a failure is reported.
package run

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

// Cmd is one external command.
type Cmd struct {
	Prog  string
	Args  []string
	Dir   string
	Env   []string
	Stdin io.Reader
}

// String renders the command the way a shell would accept it.
func (c Cmd) String() string {
	parts := make([]string, 0, len(c.Args)+1)
	for _, a := range append([]string{c.Prog}, c.Args...) {
		parts = append(parts, quote(a))
	}
	return strings.Join(parts, " ")
}

func quote(s string) string {
	if s != "" && !strings.ContainsAny(s, " \t\n'\"\\$`&|;<>()*?[]#~") {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// ExitError reports a command that ran and failed.
type ExitError struct {
	Cmd    string
	Code   int
	Stderr string
}

func (e *ExitError) Error() string {
	msg := fmt.Sprintf("%s failed (exit %d)", e.Cmd, e.Code)
	if s := strings.TrimSpace(e.Stderr); s != "" {
		msg += ": " + lastLine(s)
	}
	return msg
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}

// Runner executes commands. Read-only commands always run; commands that
// change something are echoed to Trace and, in a dry run, not executed.
type Runner struct {
	DryRun bool
	Trace  io.Writer
	Stdout io.Writer
	Stderr io.Writer
}

func (r *Runner) build(c Cmd) *exec.Cmd {
	cmd := exec.Command(c.Prog, c.Args...)
	cmd.Dir = c.Dir
	if len(c.Env) > 0 {
		cmd.Env = append(os.Environ(), c.Env...)
	}
	cmd.Stdin = c.Stdin
	return cmd
}

func (r *Runner) trace(c Cmd) {
	if r.Trace != nil {
		fmt.Fprintf(r.Trace, "+ %s\n", c)
	}
}

// Output runs a read-only command and returns its stdout. It runs in a dry
// run too, since it changes nothing.
func (r *Runner) Output(c Cmd) ([]byte, error) {
	cmd := r.build(c)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return stdout.Bytes(), wrap(c, err, stderr.String())
	}
	return stdout.Bytes(), nil
}

// Do runs a command that changes something, with its output streamed. In a
// dry run it is echoed and skipped.
func (r *Runner) Do(c Cmd) error {
	r.trace(c)
	if r.DryRun {
		return nil
	}
	cmd := r.build(c)
	cmd.Stdout, cmd.Stderr = r.Stdout, r.Stderr
	if err := cmd.Run(); err != nil {
		return wrap(c, err, "")
	}
	return nil
}

// Stream runs a command that changes something, streaming its stderr and
// returning its stdout. In a dry run it is echoed and skipped, returning
// nil output.
func (r *Runner) Stream(c Cmd) ([]byte, error) {
	r.trace(c)
	if r.DryRun {
		return nil, nil
	}
	cmd := r.build(c)
	var stdout bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, r.Stderr
	if err := cmd.Run(); err != nil {
		return stdout.Bytes(), wrap(c, err, "")
	}
	return stdout.Bytes(), nil
}

// Interactive runs a command attached to the terminal.
func (r *Runner) Interactive(c Cmd) error {
	r.trace(c)
	if r.DryRun {
		return nil
	}
	cmd := r.build(c)
	if c.Stdin == nil {
		cmd.Stdin = os.Stdin
	}
	cmd.Stdout, cmd.Stderr = r.Stdout, r.Stderr
	if err := cmd.Run(); err != nil {
		return wrap(c, err, "")
	}
	return nil
}

func wrap(c Cmd, err error, stderr string) error {
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return &ExitError{Cmd: c.String(), Code: exit.ExitCode(), Stderr: stderr}
	}
	if errors.Is(err, exec.ErrNotFound) {
		return fmt.Errorf("%s: not found on PATH", c.Prog)
	}
	return fmt.Errorf("%s: %w", c.String(), err)
}

// Have reports whether prog resolves on PATH.
func Have(prog string) bool {
	_, err := exec.LookPath(prog)
	return err == nil
}
