// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"path/filepath"
	"strings"

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
	kinds := toolKinds
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
	var synced []string
	for _, k := range kinds {
		f.step("sync " + k.name)
		if err := a.syncKind(k, opts.flag("build-only")); err != nil {
			return f.fail("sync "+k.name, err)
		}
		synced = append(synced, k.name)
	}
	f.finish(txn.OutcomeOK, "synced "+strings.Join(synced, ", "))
	return nil
}

// syncKind installs the entries of one list that are missing or at another
// version. With listOnly it prints the installs and runs none.
func (a *App) syncKind(k toolKind, listOnly bool) error {
	list, created, err := a.readList(k.file)
	if err != nil {
		return err
	}
	if created {
		a.say("%s: nothing declared (%s does not exist)", k.name, k.file)
		return nil
	}
	installed, err := a.installed(k)
	if err != nil {
		return err
	}
	current, todo := 0, 0
	for _, entry := range list.Entries() {
		name, version, err := k.parse(entry)
		if err != nil {
			return fmt.Errorf("%s: %v", k.file, err)
		}
		if have, ok := installed[k.entryName(entry)]; ok && have == version {
			current++
			continue
		}
		todo++
		if listOnly {
			a.say("%s: would install %s", k.name, entry)
			continue
		}
		if err := a.install(k, name, entry); err != nil {
			return err
		}
	}
	a.say("%s: %d current, %d installed", k.name, current, todo)
	return nil
}

// installed maps the name of each tool this installer has on the machine
// to its version.
func (a *App) installed(k toolKind) (map[string]string, error) {
	out := map[string]string{}
	switch k.name {
	case "go":
		bins, err := sources.GoBinaries(a.gobin())
		if err != nil {
			return nil, err
		}
		list, _, err := a.readList(k.file)
		if err != nil {
			return nil, err
		}
		for _, entry := range list.Entries() {
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
