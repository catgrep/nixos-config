// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/run"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

func cmdOf(prog string, args ...string) run.Cmd {
	return run.Cmd{Prog: prog, Args: args}
}

// changeOpts are the flags add, rm and up share.
type changeOpts struct {
	commit    bool
	buildOnly bool
	keep      bool
}

func (a *App) cmdAdd(opts options, args []string) error {
	if len(args) != 1 {
		return usage("add takes exactly one NAME[@VERSION]; run 'hm add --help'")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	co := changeOpts{commit: opts.flag("commit"), buildOnly: opts.flag("build-only"), keep: opts.flag("keep-on-failure")}
	var kinds []toolKind
	for _, k := range toolKinds {
		if opts.flag(k.flag) {
			kinds = append(kinds, k)
		}
	}
	switch len(kinds) {
	case 0:
		return a.addAttr(args[0], co)
	case 1:
		return a.addTool(kinds[0], args[0], co)
	default:
		return usage("--go, --uv and --cargo exclude each other")
	}
}

// addAttr pins a nixpkgs attribute, records it in packages.nix and
// switches.
func (a *App) addAttr(spec string, co changeOpts) error {
	attr, version, _ := strings.Cut(spec, "@")
	if attr == "" {
		return usage("empty attribute name")
	}
	if err := a.refuseDirty(filePackages, fileLock); err != nil {
		return err
	}
	lock, err := sources.ReadLock(a.path(fileLock))
	if err != nil {
		return err
	}
	pin, pinned := lock[attr]
	if pinned && version != "" && version != pin.Version {
		return refuse("%s is pinned at %s and shared with the hosts; changing a pin is hm up %s", attr, pin.Version, attr)
	}
	pkgs, _, err := a.readList(filePackages)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{filePackages, fileLock}, co.keep)
	if err != nil {
		return err
	}
	pinVersion := pin.Version
	if !pinned {
		f.step("pin")
		created, err := a.pinAttr(f, spec)
		if err != nil {
			return f.fail("mvs lock add", err)
		}
		pinVersion = created.Version
		if a.dryRun {
			a.say("would pin %s %s at %s", attr, created.Version, created.Label)
		} else {
			a.say("pinned %s %s at %s", attr, created.Version, created.Label)
		}
	} else {
		a.say("reusing the pin for %s %s", attr, pinVersion)
	}
	if pkgs.Add(attr) {
		f.step("write")
		if err := f.writeList(filePackages, pkgs, false); err != nil {
			return f.fail("write "+filePackages, err)
		}
		if err := a.validateList(filePackages); err != nil && !a.dryRun {
			return f.fail("validate", err)
		}
	} else {
		a.say("%s is already in %s", attr, filePackages)
	}
	f.step("switch")
	detail, err := a.activate(co.buildOnly)
	if err != nil {
		return f.fail("switch", err)
	}
	f.step("report")
	a.say("added %s %s (%s)", attr, pinVersion, detail)
	return f.report(subject("home", "add", attr, pinVersion), co.commit)
}

// pinAttr runs mvs lock add. In a dry run it runs against a copy of the
// lock, so the pin it would create is known and nothing changes.
func (a *App) pinAttr(f *flow, spec string) (run.Pin, error) {
	mvs := a.mvs()
	if a.dryRun {
		tmp, err := copyToTemp(a.path(fileLock))
		if err != nil {
			return run.Pin{}, err
		}
		defer os.Remove(tmp)
		fmt.Fprintf(a.out, "+ mvs lock add %s\n", spec)
		_, pin, err := mvs.WithLock(tmp).Add(spec)
		if err != nil {
			return pin, err
		}
		before, _ := os.ReadFile(a.path(fileLock))
		after, _ := os.ReadFile(tmp)
		fmt.Fprint(a.out, unifiedDiff(fileLock, before, after))
		return pin, nil
	}
	_, pin, err := mvs.Add(spec)
	if err != nil {
		return pin, err
	}
	return pin, f.adopt(fileLock)
}

func copyToTemp(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp("", "hm-"+filepath.Base(path)+"-*")
	if err != nil {
		return "", err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmp.Name())
		return "", err
	}
	return tmp.Name(), tmp.Close()
}

// toolKind describes one of the imperative installers hm reconciles.
type toolKind struct {
	name  string
	flag  string
	file  string
	sep   string
	usage string
	parse func(string) (name, version string, err error)
}

var toolKinds = []toolKind{
	{name: "go", flag: "go", file: fileGoTools, sep: "@", usage: "module/package@vX.Y.Z", parse: func(s string) (string, string, error) {
		e, err := sources.ParseGoEntry(s)
		return e.Pattern, e.Version, err
	}},
	{name: "uv", flag: "uv", file: fileUvTools, sep: "==", usage: "package==X.Y.Z", parse: func(s string) (string, string, error) {
		return sources.SplitEntry(s, "==")
	}},
	{name: "cargo", flag: "cargo", file: fileCargo, sep: "@", usage: "crate@X.Y.Z", parse: func(s string) (string, string, error) {
		return sources.SplitEntry(s, "@")
	}},
}

func toolKindByName(name string) (toolKind, bool) {
	for _, k := range toolKinds {
		if k.name == name {
			return k, true
		}
	}
	return toolKind{}, false
}

// entryName returns the name part of a list entry of this kind.
func (k toolKind) entryName(entry string) string {
	name, _, _ := strings.Cut(entry, k.sep)
	if k.name == "go" {
		name = strings.TrimSuffix(name, "/...")
	}
	return name
}

// addTool appends an entry to a tool list and syncs that installer.
func (a *App) addTool(k toolKind, entry string, co changeOpts) error {
	_, version, err := k.parse(entry)
	if err != nil {
		return usage("--%s expects %s: %v", k.flag, k.usage, err)
	}
	if err := a.refuseDirty(k.file); err != nil {
		return err
	}
	list, created, err := a.readList(k.file)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{k.file}, co.keep)
	if err != nil {
		return err
	}
	verb, from := "add", ""
	for _, existing := range list.Entries() {
		if existing == entry {
			a.say("%s is already declared in %s", entry, k.file)
		} else if k.entryName(existing) == k.entryName(entry) {
			_, from, _ = strings.Cut(existing, k.sep)
			a.say("replacing %s with %s", existing, entry)
			list.Remove(existing)
			verb = "update"
		}
	}
	if list.Add(entry) {
		f.step("write")
		if err := f.writeList(k.file, list, created); err != nil {
			return f.fail("write "+k.file, err)
		}
		if err := a.validateList(k.file); err != nil && !a.dryRun {
			return f.fail("validate", err)
		}
	}
	f.step("sync")
	if co.buildOnly {
		a.say("not installed; run: hm sync %s", k.name)
	} else if err := a.syncKind(k, list, false); err != nil {
		return f.fail("hm sync "+k.name, err)
	}
	f.step("report")
	subj := subject("home", verb+" "+k.name, k.entryName(entry), version)
	if verb == "update" {
		subj = subject("home", "update "+k.name, k.entryName(entry), from+" to "+version)
	}
	return f.report(subj, co.commit)
}

// finishNoop closes a flow that changed nothing.
func (f *flow) finishNoop() {
	f.finish(txn.OutcomeOK, "nothing to do")
}
