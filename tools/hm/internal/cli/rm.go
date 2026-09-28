// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
)

func (a *App) cmdRm(opts options, args []string) error {
	if len(args) != 1 {
		return usage("rm takes exactly one NAME; run 'hm rm --help'")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	co := changeOpts{commit: opts.flag("commit"), buildOnly: opts.flag("build-only")}
	name := args[0]
	if err := a.refuseDirty(ownedLists()...); err != nil {
		return err
	}
	pkgs, _, err := a.readList(filePackages)
	if err != nil {
		return err
	}
	if pkgs.Has(name) {
		return a.rmAttr(name, opts.flag("prune"), co)
	}
	for _, k := range toolKinds() {
		list, created, err := a.readList(k.file)
		if err != nil {
			return err
		}
		if created {
			continue
		}
		for _, entry := range list.Entries() {
			if entry == name || k.entryName(entry) == name {
				return a.rmTool(k, entry, co)
			}
		}
	}
	return usage("%s is not in %s or any tool list", name, filePackages)
}

// rmAttr drops an attribute from packages.nix and switches; with prune it
// also drops a pin nothing else in the repository names.
func (a *App) rmAttr(attr string, prune bool, co changeOpts) error {
	files := []string{filePackages}
	if prune {
		consumers, err := sources.Consumers(a.flake, attr, a.path(filePackages))
		if err != nil {
			return err
		}
		if len(consumers) > 0 {
			return refuse("%s is still named by %s; run without --prune to keep the pin", attr, strings.Join(sources.Relative(a.flake, consumers), ", "))
		}
		files = append(files, fileLock)
	}
	pkgs, _, err := a.readList(filePackages)
	if err != nil {
		return err
	}
	f, err := a.beginFlow(files, false)
	if err != nil {
		return err
	}
	pkgs.Remove(attr)
	f.step("write")
	if err := f.writeList(filePackages, pkgs, false); err != nil {
		return f.fail("write "+filePackages, err)
	}
	if err := a.validateList(filePackages); err != nil && !a.dryRun {
		return f.fail("validate", err)
	}
	if prune {
		f.step("prune")
		if a.dryRun {
			a.say("+ mvs lock rm %s", attr)
		} else {
			removed, err := a.mvs().Rm(attr)
			if err != nil {
				return f.fail("mvs lock rm", err)
			}
			if err := f.adopt(fileLock); err != nil {
				return f.fail("mvs lock rm", err)
			}
			a.say("unpinned %s (was %s)", attr, removed.Version)
		}
	}
	f.step("switch")
	detail, err := a.activate(co.buildOnly)
	if err != nil {
		return f.fail("switch", err)
	}
	f.step("report")
	a.say("removed %s (%s)", attr, detail)
	return f.report(commitMessage{subject: subject("home", "remove", attr, "")}, co.commit)
}

// rmTool drops an entry from a tool list and uninstalls what it declared.
func (a *App) rmTool(k toolKind, entry string, co changeOpts) error {
	list, _, err := a.readList(k.file)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{k.file}, false)
	if err != nil {
		return err
	}
	list.Remove(entry)
	f.step("write")
	if err := f.writeList(k.file, list, false); err != nil {
		return f.fail("write "+k.file, err)
	}
	if err := a.validateList(k.file); err != nil && !a.dryRun {
		return f.fail("validate", err)
	}
	f.step("uninstall")
	if co.buildOnly {
		a.say("not uninstalled; run: %s", a.uninstallCommand(k, entry))
	} else if err := a.uninstall(k, entry); err != nil {
		return f.fail("uninstall", err)
	}
	f.step("report")
	a.say("removed %s %s", k.name, k.entryName(entry))
	return f.report(commitMessage{subject: subject("home", "remove "+k.name, k.executable(entry), ""), body: entry}, co.commit)
}

func (a *App) uninstallCommand(k toolKind, entry string) string {
	name := k.entryName(entry)
	switch k.name {
	case "uv":
		return "uv tool uninstall " + name
	case "cargo":
		return "cargo uninstall " + name
	default:
		return "rm the binaries built from " + name + " in " + a.gobin()
	}
}

// uninstall removes what a tool entry installed: go binaries whose build
// information names the package, or the uv or cargo tool by name.
func (a *App) uninstall(k toolKind, entry string) error {
	name := k.entryName(entry)
	switch k.name {
	case "uv":
		return a.runner.Do(cmdOf(a.toolBin("uv"), "tool", "uninstall", name))
	case "cargo":
		return a.runner.Do(cmdOf(a.toolBin("cargo"), "uninstall", name))
	}
	e, err := sources.ParseGoEntry(entry)
	if err != nil {
		return err
	}
	gobin := a.gobin()
	bins, err := sources.GoBinaries(gobin)
	if err != nil {
		return err
	}
	for _, b := range bins {
		if !e.Matches(b) {
			continue
		}
		path := filepath.Join(gobin, b.Name)
		if a.dryRun {
			a.say("+ rm %s", path)
			continue
		}
		if err := os.Remove(path); err != nil {
			return err
		}
		a.say("removed %s", path)
	}
	return nil
}
