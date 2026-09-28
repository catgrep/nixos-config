// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"io"
	"path/filepath"

	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
)

func (a *App) cmdDoctor(_ options, args []string) error {
	if len(args) != 0 {
		return usage("doctor takes no arguments")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	gen, err := a.currentGeneration()
	if err != nil {
		return err
	}
	inv, err := a.inventory(gen)
	if err != nil {
		return err
	}
	shadows := sources.Shadowed(a.env.Getenv("PATH"), a.nixBinDirs())
	return a.page(func(w io.Writer) error {
		findings := 0
		fmt.Fprintln(w, a.bold("shadowed Nix binaries"))
		if len(shadows) == 0 {
			fmt.Fprintln(w, "  none: every Nix binary is the first hit on PATH")
		}
		for _, s := range shadows {
			findings++
			fmt.Fprintf(w, "  %s: %s shadows %s\n", s.Name, s.Winner, s.Nix)
		}
		fmt.Fprintln(w, a.bold("undeclared tools"))
		if len(inv.undeclared) == 0 {
			fmt.Fprintln(w, "  none: every go, cargo and uv tool is in its list")
		}
		t := newTable(w)
		for _, r := range inv.undeclared {
			findings++
			t.row("  "+r.Name, r.Version, r.Source, r.Detail)
		}
		t.flush()
		if len(inv.problems) > 0 {
			fmt.Fprintln(w, a.bold("problems"))
			for _, p := range inv.problems {
				findings++
				fmt.Fprintf(w, "  %s\n", p)
			}
		}
		if a.env.Getenv("NH_FLAKE") == "" {
			findings++
			fmt.Fprintf(w, "%s NH_FLAKE is unset; hm needs --flake until the switch that installs programs.nh\n", a.bold("note:"))
		}
		fmt.Fprintf(w, "\n%d findings\n", findings)
		return nil
	})
}

// nixBinDirs are the profile directories whose binaries should win on PATH.
func (a *App) nixBinDirs() []string {
	return []string{
		filepath.Join(a.home, ".nix-profile", "bin"),
		filepath.Join("/etc/profiles/per-user", a.env.Getenv("USER"), "bin"),
		"/run/current-system/sw/bin",
		"/nix/var/nix/profiles/default/bin",
	}
}
