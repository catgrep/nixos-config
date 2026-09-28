// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
)

// row is one line of hm list.
type row struct {
	Name, Version, Source, Detail string
}

// inventory is everything hm list and hm doctor read from the machine and
// the repository.
type inventory struct {
	rows         []row
	notInstalled []string
	undeclared   []row
	problems     []string
}

func (a *App) cmdList(opts options, args []string) error {
	if len(args) != 0 {
		return usage("list takes no arguments; run 'hm list --help'")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	source := opts.value("source")
	if source != "" && !validSource(source) {
		return usage("unknown source %q", source)
	}
	gen := opts.value("generation")
	if gen == "" {
		var err error
		if gen, err = a.currentGeneration(); err != nil {
			return err
		}
	}
	inv, err := a.inventory(gen)
	if err != nil {
		return err
	}
	return a.page(func(w io.Writer) error {
		t := newTable(w)
		t.row(a.bold("NAME"), a.bold("VERSION"), a.bold("SOURCE"), a.bold("DETAIL"))
		for _, r := range inv.rows {
			if source == "" || r.Source == source {
				t.row(r.Name, r.Version, r.Source, r.Detail)
			}
		}
		t.flush()
		if source == "" || source == "pinned" {
			fmt.Fprintf(w, "\n%s (%d):\n", a.bold("pinned but not in this generation"), len(inv.notInstalled))
			fmt.Fprint(w, doc.Wrap(strings.Join(inv.notInstalled, " "), doc.Width, "  "))
		}
		for _, p := range inv.problems {
			fmt.Fprintf(w, "\n%s %s\n", a.bold("note:"), p)
		}
		return nil
	})
}

func validSource(s string) bool {
	cmd, _ := doc.Lookup("list")
	for _, f := range cmd.Flags {
		if f.Name == "source" {
			for _, v := range f.Values {
				if v == s {
					return true
				}
			}
		}
	}
	return false
}

// inventory builds the rows for a generation.
func (a *App) inventory(genPath string) (*inventory, error) {
	gen, err := sources.ReadGeneration(genPath, a.nix.References)
	if err != nil {
		return nil, err
	}
	inv := &inventory{}
	if err := a.generationRows(inv, gen); err != nil {
		return nil, err
	}
	gobin := a.gobin()
	goBins := a.goRows(inv, gobin)
	cargoBins := a.toolRows(inv, "cargo", fileCargo, "@", func() (string, error) {
		out, err := a.runner.Output(cmdOf(a.toolBin("cargo"), "install", "--list"))
		return string(out), err
	}, sources.ParseCargoList)
	uvBins := a.toolRows(inv, "uv", fileUvTools, "==", func() (string, error) {
		out, err := a.runner.Output(cmdOf(a.toolBin("uv"), "tool", "list"))
		return string(out), err
	}, sources.ParseUvList)
	a.nativeRows(inv, gen, gobin, append(append(goBins, cargoBins...), uvBins...))
	sort.SliceStable(inv.rows, func(i, j int) bool {
		if inv.rows[i].Source != inv.rows[j].Source {
			return sourceOrder(inv.rows[i].Source) < sourceOrder(inv.rows[j].Source)
		}
		return inv.rows[i].Name < inv.rows[j].Name
	})
	return inv, nil
}

func sourceOrder(s string) int {
	for i, tag := range []string{"pinned", "nixpkgs", "custom", "go", "cargo", "uv", "native"} {
		if tag == s {
			return i
		}
	}
	return 99
}

// generationRows tags every store path the generation references.
func (a *App) generationRows(inv *inventory, gen *sources.Generation) error {
	lock, err := sources.ReadLock(a.path(fileLock))
	if err != nil {
		return err
	}
	pinnedList, pkgsList, err := a.declaredAttrs(inv, lock)
	if err != nil {
		return err
	}
	// Names the generation carries that no module names directly are tried
	// as nixpkgs attributes too, so Home Manager's own additions (man-db for
	// programs.man, for instance) are tagged nixpkgs rather than custom.
	for _, ref := range gen.Refs {
		pkgsList = append(pkgsList, ref.Pname)
	}
	resolved, err := a.resolve(pinnedList, pkgsList)
	if err != nil {
		return err
	}
	byBase := map[string]row{}
	for attr, path := range resolved.Pinned {
		if path != "" {
			byBase[sources.ParseStorePath(path).Base()] = row{Source: "pinned", Detail: attr + " " + lock[attr].Version}
		}
	}
	for attr, path := range resolved.Nixpkgs {
		if path == "" {
			continue
		}
		base := sources.ParseStorePath(path).Base()
		if _, ok := byBase[base]; !ok {
			byBase[base] = row{Source: "nixpkgs", Detail: attr}
		}
	}
	installedPinned := map[string]bool{}
	seen := map[string]bool{}
	for _, ref := range gen.Refs {
		base := ref.Base()
		if seen[base] {
			continue
		}
		seen[base] = true
		r := row{Name: ref.Pname, Version: ref.Version, Source: "custom", Detail: "built by this flake"}
		if tagged, ok := byBase[base]; ok {
			r.Source, r.Detail = tagged.Source, tagged.Detail
			if tagged.Source == "pinned" {
				installedPinned[strings.Fields(tagged.Detail)[0]] = true
			}
		}
		inv.rows = append(inv.rows, r)
	}
	for attr := range lock {
		if !installedPinned[attr] {
			inv.notInstalled = append(inv.notInstalled, attr)
		}
	}
	sort.Strings(inv.notInstalled)
	return nil
}

// declaredAttrs collects the attributes the home-manager modules take from
// pinned (packages.nix entries and pinned.<attr> references) and from pkgs.
func (a *App) declaredAttrs(inv *inventory, lock map[string]sources.LockPin) ([]string, []string, error) {
	pkgs, _, err := a.readList(filePackages)
	if err != nil {
		return nil, nil, err
	}
	skip := make([]string, len(ownedLists))
	for i, rel := range ownedLists {
		skip[i] = a.path(rel)
	}
	modules := a.path(dirModules)
	pinnedRefs, err := sources.PinnedAttrs(modules, skip...)
	if err != nil {
		return nil, nil, err
	}
	pkgsRefs, err := sources.PkgsAttrs(modules, skip...)
	if err != nil {
		return nil, nil, err
	}
	pinnedAttrs := map[string]bool{}
	for _, name := range pkgs.Entries() {
		pinnedAttrs[name] = true
	}
	for attr := range pinnedRefs {
		pinnedAttrs[attr] = true
	}
	var pinnedList, pkgsList []string
	for attr := range pinnedAttrs {
		if _, ok := lock[attr]; ok {
			pinnedList = append(pinnedList, attr)
		} else {
			inv.problems = append(inv.problems, fmt.Sprintf("%s is named as pinned.%s but has no pin in %s", attr, attr, fileLock))
		}
	}
	for attr := range pkgsRefs {
		pkgsList = append(pkgsList, attr)
	}
	sort.Strings(pinnedList)
	sort.Strings(pkgsList)
	return pinnedList, pkgsList, nil
}

type resolved struct {
	Pinned  map[string]string `json:"pinned"`
	Nixpkgs map[string]string `json:"nixpkgs"`
}

// resolve asks Nix for the store path of every candidate attribute, from
// the lock for pinned ones and from the flake's nixpkgs input for the
// rest, in one evaluation.
func (a *App) resolve(pinned, pkgs []string) (resolved, error) {
	var out resolved
	if len(pinned) == 0 && len(pkgs) == 0 {
		return out, nil
	}
	expr := fmt.Sprintf(`let
  flake = builtins.getFlake %q;
  system = builtins.currentSystem;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  lib = pkgs.lib;
  pinned = flake.inputs.mvs.lib.readLock { inherit system; file = %s/multiverse.lock; config.allowUnfree = true; };
  resolve = set: attr:
    let v = builtins.tryEval (lib.attrByPath (lib.splitString "." attr) null set);
    in if v.success && v.value != null && lib.isDerivation v.value then v.value.outPath else "";
in {
  pinned = lib.genAttrs %s (resolve pinned);
  nixpkgs = lib.genAttrs %s (resolve pkgs);
}`, a.flake, a.flake, nixStringList(pinned), nixStringList(pkgs))
	raw, err := a.nix.EvalExpr(expr)
	if err != nil {
		return out, fmt.Errorf("resolving attributes: %v", err)
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return out, fmt.Errorf("resolving attributes: %v", err)
	}
	return out, nil
}

func nixStringList(items []string) string {
	quoted := make([]string, 0, len(items))
	seen := map[string]bool{}
	for _, s := range items {
		if seen[s] || strings.ContainsAny(s, "\"\\$ ") {
			continue
		}
		seen[s] = true
		quoted = append(quoted, fmt.Sprintf("%q", s))
	}
	return "[ " + strings.Join(quoted, " ") + " ]"
}

// goRows lists GOBIN and returns the binary names it explained.
func (a *App) goRows(inv *inventory, gobin string) []string {
	bins, err := sources.GoBinaries(gobin)
	if err != nil {
		inv.problems = append(inv.problems, fmt.Sprintf("%s: %v", gobin, err))
		return nil
	}
	list, _, err := a.readList(fileGoTools)
	if err != nil {
		inv.problems = append(inv.problems, err.Error())
	}
	var entries []sources.GoEntry
	if list != nil {
		for _, s := range list.Entries() {
			e, err := sources.ParseGoEntry(s)
			if err != nil {
				inv.problems = append(inv.problems, fmt.Sprintf("%s: %v", fileGoTools, err))
				continue
			}
			entries = append(entries, e)
		}
	}
	var names []string
	for _, b := range bins {
		names = append(names, b.Name)
		if b.Err != nil {
			r := row{Name: b.Name, Version: "-", Source: "go", Detail: "not a Go binary; undeclared"}
			inv.rows = append(inv.rows, r)
			inv.undeclared = append(inv.undeclared, r)
			continue
		}
		r := row{Name: b.Name, Version: b.Version, Source: "go", Detail: b.Module}
		declared := false
		for _, e := range entries {
			if e.Matches(b) {
				declared = true
				if e.Version != b.Version {
					r.Detail += " (declared " + e.Version + ")"
				}
			}
		}
		if !declared {
			r.Detail += "; undeclared"
			inv.undeclared = append(inv.undeclared, r)
		}
		inv.rows = append(inv.rows, r)
	}
	return names
}

// toolRows lists one imperative installer's tools against its list and
// returns the binary names it explained.
func (a *App) toolRows(inv *inventory, kind, file, sep string, read func() (string, error), parse func(string) []sources.Tool) []string {
	declared := map[string]string{}
	list, created, err := a.readList(file)
	if err != nil {
		inv.problems = append(inv.problems, err.Error())
	} else if !created {
		for _, entry := range list.Entries() {
			name, version, _ := strings.Cut(entry, sep)
			declared[name] = version
		}
	}
	out, err := read()
	if err != nil {
		inv.problems = append(inv.problems, fmt.Sprintf("%s inventory unavailable: %v", kind, err))
		return nil
	}
	var names []string
	for _, t := range parse(out) {
		names = append(names, t.Bins...)
		r := row{Name: t.Name, Version: t.Version, Source: kind, Detail: strings.Join(t.Bins, " ")}
		if want, ok := declared[t.Name]; !ok {
			r.Detail = strings.TrimSpace(r.Detail + "; undeclared")
			inv.undeclared = append(inv.undeclared, r)
		} else if want != t.Version {
			r.Detail = strings.TrimSpace(r.Detail + " (declared " + want + ")")
		}
		inv.rows = append(inv.rows, r)
	}
	return names
}

// nativeRows lists executables in the session PATH directories that no
// other row explains. Homebrew directories are a separate layer and are
// skipped; hm doctor reports what they shadow.
func (a *App) nativeRows(inv *inventory, gen *sources.Generation, gobin string, explained []string) {
	dirs, err := gen.SessionPath()
	if err != nil {
		inv.problems = append(inv.problems, fmt.Sprintf("session path: %v", err))
		return
	}
	known := map[string]bool{}
	for _, name := range explained {
		known[name] = true
	}
	for _, dir := range dirs {
		if strings.HasPrefix(dir, "/opt/homebrew") || strings.HasPrefix(dir, "/usr/local") || dir == gobin {
			continue
		}
		xs, err := sources.Executables(dir)
		if err != nil {
			inv.problems = append(inv.problems, fmt.Sprintf("%s: %v", dir, err))
			continue
		}
		for _, x := range xs {
			if known[x.Name] || strings.Contains(x.Target, "/uv/tools/") {
				continue
			}
			version := x.VersionHint()
			if version == "" {
				version = "-"
			}
			detail := dir
			if x.Target != "" {
				detail = x.Target
			}
			inv.rows = append(inv.rows, row{Name: x.Name, Version: version, Source: "native", Detail: shortenHome(detail, a.home)})
		}
	}
}

// shortenHome replaces the home directory, as given or as its symlinks
// resolve, with ~.
func shortenHome(path, home string) string {
	candidates := []string{home}
	if real, err := filepath.EvalSymlinks(home); err == nil && real != home {
		candidates = append(candidates, real)
	}
	for _, h := range candidates {
		if h != "" && strings.HasPrefix(path, h+"/") {
			return "~/" + strings.TrimPrefix(path, h+"/")
		}
	}
	return filepath.Clean(path)
}
