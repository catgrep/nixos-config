// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/run"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
)

func (a *App) cmdUp(opts options, args []string) error {
	if len(args) > 1 {
		return usage("up takes at most one ATTR; run 'hm up --help'")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	co := changeOpts{commit: opts.flag("commit"), buildOnly: opts.flag("build-only")}
	repo := opts.flag("repo")
	if err := a.refuseDirty(fileLock, fileFlakeLock); err != nil {
		return err
	}
	lock, err := sources.ReadLock(a.path(fileLock))
	if err != nil {
		return err
	}
	targets, err := a.upTargets(lock, args, repo)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{fileLock, fileFlakeLock}, false)
	if err != nil {
		return err
	}
	f.step("flake update")
	if err := a.nix.FlakeUpdate(a.flake, "mvs"); err != nil {
		return f.fail("nix flake update mvs", err)
	}
	if err := f.adopt(fileFlakeLock); err != nil {
		return f.fail("nix flake update mvs", err)
	}
	f.step("lock update")
	mvs := a.mvsFromFlake()
	moved, err := a.updatePins(mvs, targets)
	if err != nil {
		return f.fail("mvs lock update", err)
	}
	if err := f.adopt(fileLock); err != nil {
		return f.fail("mvs lock update", err)
	}
	if !a.dryRun {
		a.reportHeldBack(mvs, lock, targets)
	}
	layer := "home"
	if repo {
		layer = "multiverse"
	}
	if len(moved) == 0 && !a.dryRun {
		a.say("every requested pin is at the newest indexed revision")
		if len(f.changed()) == 0 {
			f.finishNoop()
			return nil
		}
		return f.report("flake: update the mvs input", co.commit)
	}
	f.step("switch")
	if _, err := a.activate(co.buildOnly); err != nil {
		return f.fail("switch", err)
	}
	f.step("report")
	return f.report(upSubject(layer, moved), co.commit)
}

// upTargets decides which pins to move: the named attribute, which must be
// in packages.nix unless --repo is given, or every pinned packages.nix
// entry.
func (a *App) upTargets(lock map[string]sources.LockPin, args []string, repo bool) ([]string, error) {
	pkgs, _, err := a.readList(filePackages)
	if err != nil {
		return nil, err
	}
	if len(args) == 0 {
		var targets []string
		for _, name := range pkgs.Entries() {
			if _, ok := lock[name]; ok {
				targets = append(targets, name)
			} else {
				a.say("%s is in %s but not pinned; skipping", name, filePackages)
			}
		}
		return targets, nil
	}
	attr := args[0]
	if _, ok := lock[attr]; !ok {
		return nil, usage("%s is not pinned in %s", attr, fileLock)
	}
	if !pkgs.Has(attr) {
		if !repo {
			return nil, refuse("%s is a host or dev-shell pin, not in %s; use hm up --repo %s", attr, filePackages, attr)
		}
		consumers, err := sources.Consumers(a.flake, attr)
		if err != nil {
			return nil, err
		}
		a.say("%s is consumed by %s", attr, strings.Join(sources.Relative(a.flake, consumers), ", "))
	}
	return []string{attr}, nil
}

// updatePins runs mvs lock update for each target and reports what moved.
func (a *App) updatePins(mvs run.Mvs, targets []string) ([]run.Moved, error) {
	var moved []run.Moved
	for _, attr := range targets {
		if a.dryRun {
			fmt.Fprintf(a.out, "+ nix run %s#mvs -- lock update %s\n", a.flake, attr)
			continue
		}
		m, err := mvs.Update(attr)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", attr, err)
		}
		moved = append(moved, m...)
	}
	for _, m := range moved {
		a.say("%s: %s to %s (%s)", m.Attr, m.From.Version, m.To.Version, m.To.Label)
	}
	return moved, nil
}

// reportHeldBack names the targets a recorded version constraint kept
// behind the index.
func (a *App) reportHeldBack(mvs run.Mvs, lock map[string]sources.LockPin, targets []string) {
	status, err := mvs.Status()
	if err != nil {
		a.say("mvs lock status unavailable: %v", err)
		return
	}
	behind := map[string]run.PinStatus{}
	for _, s := range status {
		if s.VersionsBehind > 0 {
			behind[s.Attr] = s
		}
	}
	for _, attr := range targets {
		if s, ok := behind[attr]; ok && lock[attr].Constraint != "" {
			a.say("%s stays at %s: the constraint %s holds it back from %s (mvs lock add %s@%s to change it)", attr, s.Version, lock[attr].Constraint, s.Latest, attr, s.Latest)
		}
	}
}

func upSubject(layer string, moved []run.Moved) string {
	if len(moved) == 1 {
		m := moved[0]
		return subject(layer, "update", m.Attr, m.From.Version+" to "+m.To.Version)
	}
	names := make([]string, len(moved))
	for i, m := range moved {
		names[i] = m.Attr
	}
	return subject(layer, "update pins", strings.Join(names, " "), "")
}
