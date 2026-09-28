// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

func (a *App) cmdStatus(_ options, args []string) error {
	if len(args) != 0 {
		return usage("status takes no arguments")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	return a.page(func(w io.Writer) error {
		a.statusPins(w)
		a.statusFiles(w)
		return a.statusJournal(w)
	})
}

func (a *App) statusPins(w io.Writer) {
	mvs := a.mvs()
	status, err := mvs.Status()
	fmt.Fprintln(w, a.bold("pins"))
	if err != nil {
		fmt.Fprintf(w, "  mvs lock status unavailable: %v\n", err)
	} else {
		behind := 0
		t := newTable(w)
		for _, s := range status {
			if s.VersionsBehind > 0 {
				behind++
				t.row("  "+s.Attr, s.Version, "behind", fmt.Sprintf("%s (%d versions, %d days)", s.Latest, s.VersionsBehind, s.DaysBehind))
			}
		}
		t.flush()
		fmt.Fprintf(w, "  %d pins, %d behind the index\n", len(status), behind)
	}
	min, err := mvs.MinimizeCheck()
	switch {
	case err != nil:
		fmt.Fprintf(w, "  mvs lock minimize --check unavailable: %v\n", err)
	case len(min.Moved) == 0:
		fmt.Fprintf(w, "  %d pins on %d revisions, minimal\n", min.Pins, min.Before)
	default:
		fmt.Fprintf(w, "  mvs lock minimize would move %d pins from %d onto %d revisions\n", len(min.Moved), min.Before, min.After)
	}
}

func (a *App) statusFiles(w io.Writer) {
	fmt.Fprintln(w, a.bold("uncommitted"))
	dirty, err := a.git.Dirty("flake.nix", fileFlakeLock, fileLock, dirModules, dirDarwin)
	switch {
	case err != nil:
		fmt.Fprintf(w, "  git status unavailable: %v\n", err)
	case len(dirty) == 0:
		fmt.Fprintln(w, "  nothing under flake.nix, flake.lock, multiverse.lock, home-manager/ or darwin/")
	default:
		for _, f := range dirty {
			fmt.Fprintf(w, "  %s\n", f)
		}
	}
}

func (a *App) statusJournal(w io.Writer) error {
	gitDir, err := a.git.Dir()
	if err != nil {
		return err
	}
	fmt.Fprintln(w, a.bold("last run"))
	j, path, err := txn.Last(gitDir)
	if err != nil {
		return err
	}
	if j == nil {
		fmt.Fprintln(w, "  none recorded")
		return nil
	}
	outcome := j.Outcome
	if j.Finished == nil {
		outcome = "unfinished"
	}
	fmt.Fprintf(w, "  %s at %s: %s, reached step %s\n", strings.Join(j.Command, " "), j.Started.Local().Format(time.RFC3339), outcome, j.LastStep())
	if j.Detail != "" {
		fmt.Fprintf(w, "  %s\n", j.Detail)
	}
	if !j.Resolved() {
		fmt.Fprintf(w, "  unresolved: check the files above and remove %s to acknowledge\n", path)
	}
	if _, err := os.Stat(filepath.Join(gitDir, "hm.lock")); err == nil {
		fmt.Fprintf(w, "  %s exists: a run is in progress or crashed\n", filepath.Join(gitDir, "hm.lock"))
	}
	if root := filepath.Join(sources.StateDir(a.home, a.env.Getenv), "home-manager", "keep-gen19"); exists(root) {
		fmt.Fprintf(w, "  %s protects generation 19; hm clean is refused while it exists\n", root)
	}
	return nil
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}
