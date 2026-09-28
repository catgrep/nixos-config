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
	for _, k := range toolKinds() {
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
	lockPath, pinVersion := a.path(fileLock), pin.Version
	if !pinned {
		f.step("pin")
		created, path, err := a.pinAttr(f, spec)
		if err != nil {
			return f.fail("mvs lock add", err)
		}
		if path != lockPath {
			defer os.Remove(path)
		}
		lockPath, pinVersion = path, created.Version
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
	version, note := a.installedVersion(attr, pinVersion, lockPath)
	a.say("added %s %s (%s)", attr, version, detail)
	return f.report(commitMessage{subject: subject("home", "add", attr, version), body: note}, co.commit)
}

// pinAttr runs mvs lock add and returns the pin with the lock file that
// holds it. In a dry run that is a temporary copy, so the pin it would
// create is known and nothing changes; the caller removes the copy.
func (a *App) pinAttr(f *flow, spec string) (run.Pin, string, error) {
	mvs, lock := a.mvs(), a.path(fileLock)
	if !a.dryRun {
		_, pin, err := mvs.Add(spec)
		if err != nil {
			return pin, lock, err
		}
		return pin, lock, f.adopt(fileLock)
	}
	tmp, err := copyToTemp(lock)
	if err != nil {
		return run.Pin{}, lock, err
	}
	fmt.Fprintf(a.out, "+ mvs lock add %s\n", spec)
	_, pin, err := mvs.WithLock(tmp).Add(spec)
	if err != nil {
		_ = os.Remove(tmp)
		return pin, lock, err
	}
	before, _ := os.ReadFile(lock)
	after, _ := os.ReadFile(tmp)
	fmt.Fprint(a.out, unifiedDiff(fileLock, before, after))
	return pin, tmp, nil
}

// resolvedPackage is what the flake resolves a pinned attribute to on the
// system hm runs on.
type resolvedPackage struct {
	Version string `json:"version"`
	Pname   string `json:"pname"`
	System  string `json:"system"`
}

// resolvePinned evaluates, through the flake's mvs input, the package that
// pinned.<attr> is on this system when the lock at lockPath is read. The
// lock is a parameter because a dry run pins into a temporary copy.
func (a *App) resolvePinned(attr, lockPath string) (resolvedPackage, error) {
	expr := fmt.Sprintf(`let
  flake = builtins.getFlake %q;
  lock = %q;
  attr = %q;
  system = builtins.currentSystem;
  lib = flake.inputs.nixpkgs.lib;
  pinned = flake.inputs.mvs.lib.readLock { inherit system; file = lock; config.allowUnfree = true; };
  pkg = lib.attrByPath (lib.splitString "." attr) null pinned;
in
if pkg == null then null else {
  inherit system;
  version = pkg.version or null;
  pname = pkg.pname or (builtins.parseDrvName pkg.name).name;
}`, a.flake, lockPath, attr)
	raw, err := a.nix.EvalExpr(expr)
	if err != nil {
		return resolvedPackage{}, err
	}
	var pkg *resolvedPackage
	if err := jsonUnmarshal(raw, &pkg); err != nil {
		return resolvedPackage{}, fmt.Errorf("unexpected nix eval output: %v", err)
	}
	if pkg == nil || pkg.Version == "" {
		return resolvedPackage{}, fmt.Errorf("%s is not a versioned package in the lock the flake reads", attr)
	}
	return *pkg, nil
}

// installedVersion returns the version this system installs for attr and,
// when that is not the index version the lock records, a line naming both
// for the output and the commit body. When the flake cannot tell, the
// index version stands and the reason is printed, since the generation was
// already built from that lock.
func (a *App) installedVersion(attr, index, lockPath string) (version, note string) {
	pkg, err := a.resolvePinned(attr, lockPath)
	if err != nil {
		a.say("the version this system resolves for %s could not be read; reporting the index version: %v", attr, err)
		return index, ""
	}
	if pkg.Version == index {
		return index, ""
	}
	note = fmt.Sprintf("index %s, %s resolves %s %s", index, pkg.System, pkg.Pname, pkg.Version)
	a.say("%s: %s", attr, note)
	return pkg.Version, note
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

// toolKinds returns the installers in the order hm syncs them.
func toolKinds() []toolKind {
	return []toolKind{
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
}

func toolKindByName(name string) (toolKind, bool) {
	for _, k := range toolKinds() {
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

// executable returns the program an entry installs, which names its
// commits: for go the last element of the package path, for uv and cargo
// the package or crate name.
func (k toolKind) executable(entry string) string {
	name := k.entryName(entry)
	if k.name == "go" {
		return sources.GoExecutable(name)
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
	msg := commitMessage{subject: subject("home", "add "+k.name, k.executable(entry), version), body: entry}
	for _, existing := range list.Entries() {
		if existing == entry {
			a.say("%s is already declared in %s", entry, k.file)
		} else if k.entryName(existing) == k.entryName(entry) {
			_, from, _ := strings.Cut(existing, k.sep)
			a.say("replacing %s with %s", existing, entry)
			list.Remove(existing)
			msg.subject = subject("home", "update "+k.name, k.executable(entry), from+" to "+version)
			msg.body = entry + "\nreplaces " + existing
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
	return f.report(msg, co.commit)
}

// finishNoop closes a flow that changed nothing.
func (f *flow) finishNoop() {
	f.finish(txn.OutcomeOK, "nothing to do")
}
