// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/nixlist"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

func (a *App) cmdSync(opts options, args []string) error {
	if len(args) > 1 {
		return usage("sync takes at most one of go, uv, cargo")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	kinds := toolKinds()
	if len(args) == 1 {
		k, ok := toolKindByName(args[0])
		if !ok {
			return usage("unknown installer %q; expected go, uv or cargo", args[0])
		}
		kinds = []toolKind{k}
	}
	f, err := a.beginFlow(nil, false)
	if err != nil {
		return err
	}
	so := syncOpts{listOnly: opts.flag("build-only"), force: opts.flag("force")}
	var synced []string
	for _, k := range kinds {
		f.step("sync " + k.name)
		list, created, err := a.readList(k.file)
		if err != nil {
			return f.fail("sync "+k.name, err)
		}
		if created {
			a.say("%s: nothing declared (%s does not exist)", k.name, k.file)
			continue
		}
		if err := a.syncKind(k, list, so); err != nil {
			return f.fail("sync "+k.name, err)
		}
		synced = append(synced, k.name)
	}
	f.finish(txn.OutcomeOK, "synced "+strings.Join(synced, ", "))
	return nil
}

// syncOpts selects how syncKind reconciles a list.
type syncOpts struct {
	// listOnly prints the installs and runs none.
	listOnly bool
	// force reinstalls entries whose installed version already matches, so
	// the tools are rebuilt with the toolchain of the current generation.
	force bool
}

// syncKind installs the entries of list that are missing or at another
// version, or every entry with force. The list is passed in rather than
// read from disk, so a dry run reconciles against the proposed list whose
// diff it printed.
func (a *App) syncKind(k toolKind, list *nixlist.List, so syncOpts) error {
	installed, err := a.installed(k, list.Entries())
	if err != nil {
		return err
	}
	current, todo := 0, 0
	for _, entry := range list.Entries() {
		name, version, err := k.parse(entry)
		if err != nil {
			return fmt.Errorf("%s: %v", k.file, err)
		}
		if have, ok := installed[k.entryName(entry)]; ok && have == version && !so.force {
			current++
			continue
		}
		todo++
		if so.listOnly {
			a.say("%s: would install %s", k.name, entry)
			continue
		}
		if err := a.install(k, name, entry); err != nil {
			return err
		}
	}
	if so.force {
		a.say("%s: %d installed, forced", k.name, todo)
	} else {
		a.say("%s: %d current, %d installed", k.name, current, todo)
	}
	return nil
}

// installed maps the name of each tool this installer has on the machine
// to its version. Go binaries carry no tool name, so they are matched
// against the package patterns of the given list entries.
func (a *App) installed(k toolKind, entries []string) (map[string]string, error) {
	out := map[string]string{}
	switch k.name {
	case "go":
		bins, err := sources.GoBinaries(a.gobin())
		if err != nil {
			return nil, err
		}
		for _, entry := range entries {
			e, err := sources.ParseGoEntry(entry)
			if err != nil {
				return nil, fmt.Errorf("%s: %v", k.file, err)
			}
			for _, b := range bins {
				if e.Matches(b) {
					out[e.Name()] = b.Version
				}
			}
		}
	case "uv":
		raw, err := a.runner.Output(cmdOf(a.toolBin("uv"), "tool", "list"))
		if err != nil {
			return nil, fmt.Errorf("uv tool list: %v", err)
		}
		for _, t := range sources.ParseUvList(string(raw)) {
			out[t.Name] = t.Version
		}
	case "cargo":
		raw, err := a.runner.Output(cmdOf(a.toolBin("cargo"), "install", "--list"))
		if err != nil {
			return nil, fmt.Errorf("cargo install --list: %v", err)
		}
		for _, t := range sources.ParseCargoList(string(raw)) {
			out[t.Name] = t.Version
		}
	}
	return out, nil
}

// install runs the installer for one entry with the pinned toolchain.
func (a *App) install(k toolKind, name, entry string) error {
	switch k.name {
	case "go":
		return a.runner.Do(cmdOf(a.toolBin("go"), "install", entry))
	case "uv":
		args := []string{"tool", "install", "--reinstall", entry}
		python := a.toolBin("python3")
		if filepath.IsAbs(python) {
			args = append(args, "--python", python)
		}
		return a.runner.Do(cmdOf(a.toolBin("uv"), args...))
	default:
		return a.runner.Do(cmdOf(a.toolBin("cargo"), "install", "--locked", "--force", name, "--version", entryVersion(k, entry)))
	}
}

func entryVersion(k toolKind, entry string) string {
	_, version, _ := k.parse(entry)
	return version
}
