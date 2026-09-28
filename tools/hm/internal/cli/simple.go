// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

func (a *App) cmdSwitch(_ options, args []string) error {
	if len(args) > 1 {
		return usage("switch takes at most one of home, darwin, all")
	}
	layer := "home"
	if len(args) == 1 {
		layer = args[0]
	}
	if layer != "home" && layer != "darwin" && layer != "all" {
		return usage("unknown layer %q; expected home, darwin or all", layer)
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	f, err := a.beginFlow(nil, false)
	if err != nil {
		return err
	}
	var details []string
	if layer != "darwin" {
		f.step("switch")
		detail, err := a.activate(false)
		if err != nil {
			return f.fail("switch", err)
		}
		details = append(details, detail)
	}
	if layer != "home" {
		f.step("switch darwin")
		detail, err := a.activateDarwin(false)
		if err != nil {
			return f.fail("switch darwin", err)
		}
		details = append(details, detail)
	}
	f.finish(txn.OutcomeOK, strings.Join(details, "; "))
	return nil
}

func (a *App) cmdTry(_ options, args []string) error {
	if len(args) == 0 || args[0] == "--" {
		return usage("try needs an attribute; run 'hm try --help'")
	}
	attr := args[0]
	var command []string
	if len(args) > 1 {
		command = args[1:]
		if command[0] == "--" {
			command = command[1:]
		}
	}
	return a.nix.Shell("nixpkgs#"+attr, command)
}

func (a *App) cmdClean(opts options, _ []string) error {
	keep := 5
	if v := opts.value("keep"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return usage("--keep expects a positive number, got %q", v)
		}
		keep = n
	}
	root := filepath.Join(sources.StateDir(a.home, a.env.Getenv), "home-manager", "keep-gen19")
	if _, err := os.Lstat(root); err == nil {
		return refuse("%s still protects generation 19 for the migration; exercise the rollback and remove it before cleaning", root)
	}
	return a.nh.CleanUser(keep)
}

func (a *App) cmdHelp(_ options, args []string) error {
	if len(args) > 1 {
		return usage("help takes at most one command name")
	}
	if len(args) == 1 {
		cmd, ok := doc.Lookup(args[0])
		if !ok || cmd.Hidden {
			return usage("unknown command %q", args[0])
		}
		fmt.Fprint(a.out, doc.Help(cmd))
		return nil
	}
	return a.page(func(w io.Writer) error {
		_, err := io.WriteString(w, doc.Manual(a.env.Version))
		return err
	})
}
