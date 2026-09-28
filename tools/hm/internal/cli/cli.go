// SPDX-License-Identifier: GPL-3.0-or-later

// Package cli parses the command line and runs the subcommands.
package cli

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
	"github.com/catgrep/nixos-config/tools/hm/internal/run"
)

// Exit codes, documented in hm(1) and stable.
const (
	ExitOK           = 0
	ExitFailed       = 1
	ExitUsage        = 2
	ExitRefused      = 3
	ExitCommitFailed = 4
)

// Env is everything Main takes from the process.
type Env struct {
	Args     []string
	Stdin    io.Reader
	Stdout   io.Writer
	Stderr   io.Writer
	Getenv   func(string) string
	Version  string
	Now      func() time.Time
	Terminal func() bool
}

// exitError carries an exit code and a message for the user.
type exitError struct {
	code int
	msg  string
}

func (e *exitError) Error() string {
	return e.msg
}

func fail(code int, format string, args ...any) error {
	return &exitError{code: code, msg: fmt.Sprintf(format, args...)}
}

func usage(format string, args ...any) error {
	return fail(ExitUsage, format, args...)
}

func refuse(format string, args ...any) error {
	return fail(ExitRefused, format, args...)
}

// App is the state one invocation shares between subcommands.
type App struct {
	env      Env
	out      io.Writer
	errOut   io.Writer
	flake    string
	dryRun   bool
	noPager  bool
	runner   *run.Runner
	nix      run.Nix
	nh       run.Nh
	git      run.Git
	home     string
	now      func() time.Time
	terminal func() bool
}

// Main runs hm and returns its exit code.
func Main(env Env) int {
	err := runMain(env)
	if err == nil {
		return ExitOK
	}
	var exit *exitError
	if errors.As(err, &exit) {
		if exit.msg != "" {
			fmt.Fprintf(env.Stderr, "hm: %s\n", exit.msg)
		}
		return exit.code
	}
	fmt.Fprintf(env.Stderr, "hm: %v\n", err)
	return ExitFailed
}

func runMain(env Env) error {
	if env.Getenv == nil {
		env.Getenv = os.Getenv
	}
	if env.Now == nil {
		env.Now = time.Now
	}
	a := &App{env: env, out: env.Stdout, errOut: env.Stderr, now: env.Now, terminal: env.Terminal}
	if a.terminal == nil {
		a.terminal = func() bool { return isTerminal(env.Stdout) }
	}
	a.home = env.Getenv("HOME")
	globals, sub, rest, err := splitArgs(env.Args)
	if err != nil {
		return err
	}
	switch {
	case globals.version:
		fmt.Fprintf(a.out, "hm %s\n", env.Version)
		return nil
	case globals.help && sub == "":
		fmt.Fprint(a.out, doc.TopHelp(env.Version))
		return nil
	case sub == "":
		fmt.Fprint(a.errOut, doc.TopHelp(env.Version))
		return fail(ExitUsage, "")
	}
	a.dryRun, a.noPager = globals.dryRun, globals.noPager
	a.runner = &run.Runner{DryRun: a.dryRun, Trace: a.out, Stdout: a.out, Stderr: a.errOut}
	a.nix, a.nh = run.NewNix(a.runner), run.NewNh(a.runner)
	if globals.flake != "" {
		a.flake = globals.flake
	} else {
		a.flake = env.Getenv("NH_FLAKE")
	}
	cmd, ok := doc.Lookup(sub)
	if !ok {
		return usage("unknown command %q; run 'hm --help'", sub)
	}
	if globals.help {
		rest = append([]string{"--help"}, rest...)
	}
	return a.dispatch(cmd, rest)
}

type globalFlags struct {
	flake           string
	dryRun, noPager bool
	help, version   bool
}

// splitArgs separates the global flags, which may appear before or after
// the subcommand, from the subcommand name and its own arguments.
func splitArgs(args []string) (globalFlags, string, []string, error) {
	var g globalFlags
	var sub string
	var rest []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--" {
			rest = append(rest, args[i:]...)
			break
		}
		name, value, hasValue := strings.Cut(arg, "=")
		switch name {
		case "--flake":
			if !hasValue {
				if i+1 >= len(args) {
					return g, "", nil, usage("--flake needs a path")
				}
				i++
				value = args[i]
			}
			g.flake = value
		case "--dry-run":
			g.dryRun = true
		case "--no-pager":
			g.noPager = true
		case "--help", "-h":
			g.help = true
		case "--version", "-V":
			g.version = true
		default:
			if sub == "" && !strings.HasPrefix(arg, "-") {
				sub = arg
			} else {
				rest = append(rest, arg)
			}
		}
	}
	return g, sub, rest, nil
}

// dispatch parses the subcommand's flags and runs it. The hidden
// __complete command receives its arguments untouched, since they are the
// words of another command line.
func (a *App) dispatch(cmd doc.Command, args []string) error {
	if cmd.Name == "__complete" {
		return a.cmdComplete(options{}, args)
	}
	for _, arg := range args {
		if arg == "--" {
			break
		}
		if arg == "--help" || arg == "-h" {
			fmt.Fprint(a.out, doc.Help(cmd))
			return nil
		}
	}
	fs := flag.NewFlagSet(cmd.Name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	values := map[string]any{}
	takesValue := map[string]bool{}
	for _, f := range cmd.Flags {
		if f.Arg != "" {
			values[f.Name] = fs.String(f.Name, "", f.Help)
			takesValue[f.Name] = true
		} else {
			values[f.Name] = fs.Bool(f.Name, false, f.Help)
		}
	}
	if err := fs.Parse(permute(args, takesValue)); err != nil {
		return usage("%s: %v; run 'hm %s --help'", cmd.Name, err, cmd.Name)
	}
	opts := options{values: values}
	positional := fs.Args()
	handlers := map[string]func(options, []string) error{
		"add":        a.cmdAdd,
		"rm":         a.cmdRm,
		"up":         a.cmdUp,
		"sync":       a.cmdSync,
		"switch":     a.cmdSwitch,
		"brew":       a.cmdBrew,
		"list":       a.cmdList,
		"status":     a.cmdStatus,
		"doctor":     a.cmdDoctor,
		"try":        a.cmdTry,
		"clean":      a.cmdClean,
		"help":       a.cmdHelp,
		"completion": a.cmdCompletion,
	}
	handler, ok := handlers[cmd.Name]
	if !ok {
		return usage("%s is not implemented", cmd.Name)
	}
	return handler(opts, positional)
}

// permute moves flags in front of positional arguments, so `hm add zizmor
// --commit` parses like `hm add --commit zizmor`. Everything after "--" is
// left in place.
func permute(args []string, takesValue map[string]bool) []string {
	var flags, positional []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--" {
			positional = append(positional, args[i:]...)
			break
		}
		if !strings.HasPrefix(arg, "-") || arg == "-" {
			positional = append(positional, arg)
			continue
		}
		flags = append(flags, arg)
		name := strings.TrimLeft(arg, "-")
		if takesValue[name] && !strings.Contains(arg, "=") && i+1 < len(args) {
			i++
			flags = append(flags, args[i])
		}
	}
	return append(flags, positional...)
}

// options gives typed access to parsed flags.
type options struct {
	values map[string]any
}

func (o options) flag(name string) bool {
	if v, ok := o.values[name].(*bool); ok {
		return *v
	}
	return false
}

func (o options) value(name string) string {
	if v, ok := o.values[name].(*string); ok {
		return *v
	}
	return ""
}

func isTerminal(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	info, err := f.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

// requireFlake resolves the flake directory and prepares the git wrapper.
func (a *App) requireFlake() error {
	if a.flake == "" {
		return usage("no flake: set NH_FLAKE (programs.nh.flake) or pass --flake PATH")
	}
	abs, err := filepath.Abs(a.flake)
	if err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(abs, "flake.nix")); err != nil {
		return usage("%s has no flake.nix", abs)
	}
	a.flake = abs
	a.git = run.NewGit(a.runner, abs)
	return nil
}

// path returns an absolute path inside the flake.
func (a *App) path(rel string) string {
	return filepath.Join(a.flake, rel)
}

// say prints one informational line for the user.
func (a *App) say(format string, args ...any) {
	fmt.Fprintf(a.out, "hm: "+format+"\n", args...)
}
