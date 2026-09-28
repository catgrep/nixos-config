// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"sort"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/completion"
	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
)

func (a *App) cmdCompletion(_ options, args []string) error {
	if len(args) != 1 {
		return usage("completion takes one shell: zsh, bash or fish")
	}
	script, err := completion.Script(args[0])
	if err != nil {
		return usage("%v", err)
	}
	_, err = fmt.Fprint(a.out, script)
	return err
}

// cmdComplete prints candidates for the word being completed. args are the
// words after "hm", the last one being the partial word (possibly empty).
// Failures are silent: a shell completion must never print an error.
func (a *App) cmdComplete(_ options, args []string) error {
	candidates := a.candidates(args)
	sort.Strings(candidates)
	for _, c := range candidates {
		fmt.Fprintln(a.out, c)
	}
	return nil
}

func (a *App) candidates(args []string) []string {
	cur := ""
	if len(args) > 0 {
		cur = args[len(args)-1]
		args = args[:len(args)-1]
	}
	globals, sub, rest, err := splitArgs(args)
	if err != nil {
		return nil
	}
	if globals.flake != "" {
		a.flake = globals.flake
	}
	if len(args) > 0 && (args[len(args)-1] == "--flake" || args[len(args)-1] == "--generation") {
		return nil
	}
	if sub == "" {
		var out []string
		for _, c := range doc.Commands() {
			if !c.Hidden {
				out = append(out, c.Name)
			}
		}
		return filterPrefix(append(out, flagNames(doc.GlobalFlags())...), cur)
	}
	cmd, ok := doc.Lookup(sub)
	if !ok {
		return nil
	}
	if len(rest) > 0 {
		if values := flagValues(cmd, rest[len(rest)-1]); values != nil {
			return filterPrefix(values, cur)
		}
	}
	if strings.HasPrefix(cur, "-") {
		return filterPrefix(append(flagNames(cmd.Flags), flagNames(doc.GlobalFlags())...), cur)
	}
	return filterPrefix(a.positional(cmd, cur), cur)
}

func flagNames(flags []doc.Flag) []string {
	out := make([]string, len(flags))
	for i, f := range flags {
		out[i] = "--" + f.Name
	}
	return out
}

func flagValues(cmd doc.Command, prev string) []string {
	for _, f := range cmd.Flags {
		if "--"+f.Name == prev && f.Arg != "" {
			if len(f.Values) > 0 {
				return f.Values
			}
			return []string{}
		}
	}
	return nil
}

func filterPrefix(items []string, prefix string) []string {
	var out []string
	for _, s := range items {
		if strings.HasPrefix(s, prefix) {
			out = append(out, s)
		}
	}
	return out
}

// positional returns the candidates for a command's argument.
func (a *App) positional(cmd doc.Command, cur string) []string {
	switch cmd.Complete {
	case doc.CompleteWords:
		return cmd.Words
	case doc.CompleteHelp:
		var out []string
		for _, c := range doc.Commands() {
			if !c.Hidden {
				out = append(out, c.Name)
			}
		}
		return out
	case doc.CompleteOwned:
		if a.requireFlake() != nil {
			return nil
		}
		var out []string
		pkgs, _, err := a.readList(filePackages)
		if err == nil {
			out = append(out, pkgs.Entries()...)
		}
		if cmd.Name == "rm" {
			for _, k := range toolKinds() {
				if list, created, err := a.readList(k.file); err == nil && !created {
					for _, e := range list.Entries() {
						out = append(out, k.entryName(e))
					}
				}
			}
		}
		return out
	case doc.CompleteAttr:
		if a.requireFlake() != nil || len(cur) == 0 {
			return nil
		}
		matches, err := a.mvs().Search(cur+"*", 50)
		if err != nil {
			return nil
		}
		var out []string
		for _, m := range matches {
			if !m.Gone {
				out = append(out, m.Attr)
			}
		}
		return out
	}
	return nil
}
