// SPDX-License-Identifier: GPL-3.0-or-later

package sources

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseStorePath(t *testing.T) {
	tests := []struct {
		path                   string
		pname, version, output string
	}{
		{"/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0", "ripgrep", "15.1.0", ""},
		{"/nix/store/148icihpgb90anqhbh019i7wq3czsmmd-shellcheck-0.11.0-man", "shellcheck", "0.11.0", "man"},
		{"/nix/store/bvd9jw9h28g6v6nzasc8p2zkjdgkg7l1-python3.14-gitingest-0.3.1", "python3.14-gitingest", "0.3.1", ""},
		{"/nix/store/78dxx2mr5drizabafzha5hjwizzl9dkh-home-manager", "home-manager", "", ""},
		{"/nix/store/id8cbza5bqlpsmvx82yi8g7ibp81jf4h-hm-session-vars.sh", "hm-session-vars.sh", "", ""},
		{"/nix/store/p7ap9sijfgyjazj4gmalpwzj51xwx178-nil-2025-06-13", "nil", "2025-06-13", ""},
		{"/nix/store/7x1qd3vzv370gq5byaf9i5j3yc8fl0b1-openssl-3.6.3-bin", "openssl", "3.6.3", "bin"},
		{"/nix/store/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-rust-default-1.98.1", "rust-default", "1.98.1", ""},
	}
	for _, tc := range tests {
		got := ParseStorePath(tc.path)
		if got.Path != tc.path || got.Pname != tc.pname || got.Version != tc.version || got.Output != tc.output {
			t.Errorf("%s: got %+v", tc.path, got)
		}
	}
}

func TestParsePathExport(t *testing.T) {
	line := `export PATH="/Users/bobby/.local/bin:/Users/bobby/go/bin:/opt/homebrew/bin${PATH:+:}$PATH"`
	dirs, ok := parsePathExport(line)
	want := []string{"/Users/bobby/.local/bin", "/Users/bobby/go/bin", "/opt/homebrew/bin"}
	if !ok || !reflect.DeepEqual(dirs, want) {
		t.Errorf("parsePathExport = %v, %v", dirs, ok)
	}
	if _, ok := parsePathExport(`export EDITOR="vim"`); ok {
		t.Error("non-PATH export matched")
	}
}

func TestReadGeneration(t *testing.T) {
	dir := t.TempDir()
	homePath := filepath.Join(dir, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-home-manager-path")
	if err := os.MkdirAll(filepath.Join(homePath, "etc", "profile.d"), 0o755); err != nil {
		t.Fatal(err)
	}
	vars := "export FOO=1\nexport PATH=\"/home/x/.local/bin:/home/x/go/bin${PATH:+:}$PATH\"\n"
	if err := os.WriteFile(filepath.Join(homePath, "etc", "profile.d", "hm-session-vars.sh"), []byte(vars), 0o644); err != nil {
		t.Fatal(err)
	}
	gen := filepath.Join(dir, "gen")
	if err := os.MkdirAll(gen, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(homePath, filepath.Join(gen, "home-path")); err != nil {
		t.Fatal(err)
	}
	refs := func(p string) ([]string, error) {
		return []string{p, "/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0"}, nil
	}
	g, err := ReadGeneration(gen, refs)
	if err != nil {
		t.Fatal(err)
	}
	if len(g.Refs) != 1 || g.Refs[0].Pname != "ripgrep" {
		t.Errorf("refs = %+v", g.Refs)
	}
	dirs, err := g.SessionPath()
	if err != nil || !reflect.DeepEqual(dirs, []string{"/home/x/.local/bin", "/home/x/go/bin"}) {
		t.Errorf("SessionPath = %v, %v", dirs, err)
	}
	if _, err := ReadGeneration(dir, refs); err == nil {
		t.Error("a directory without home-path was accepted")
	}
}

func TestReadGenerationState(t *testing.T) {
	home := t.TempDir()
	state := filepath.Join(home, ".local", "state")
	getenv := func(string) string { return "" }
	got, err := ReadGenerationState(home, getenv)
	if err != nil || got != (GenerationState{}) {
		t.Fatalf("no links: %+v, %v", got, err)
	}
	profiles := filepath.Join(state, "nix", "profiles")
	gcroots := filepath.Join(state, "home-manager", "gcroots")
	gen := filepath.Join(home, "store", "gen-21")
	for _, d := range []string{profiles, gcroots, gen} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(gen, filepath.Join(profiles, "home-manager-21-link")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("home-manager-21-link", filepath.Join(profiles, "home-manager")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(gen, filepath.Join(gcroots, "current-home")); err != nil {
		t.Fatal(err)
	}
	// EvalSymlinks also resolves the temporary directory itself.
	realGen, err := filepath.EvalSymlinks(gen)
	if err != nil {
		t.Fatal(err)
	}
	got, err = ReadGenerationState(home, getenv)
	if err != nil || got.Profile != realGen || got.Current != realGen {
		t.Fatalf("with links: %+v, %v", got, err)
	}
	if n := GenerationNumber(home, getenv); n != 21 {
		t.Errorf("GenerationNumber = %d", n)
	}
	// A dangling link is an error, not an absent generation.
	if err := os.Remove(filepath.Join(profiles, "home-manager-21-link")); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadGenerationState(home, getenv); err == nil {
		t.Error("dangling profile link read as a state")
	}
}

func TestReadLock(t *testing.T) {
	path := filepath.Join(t.TempDir(), "multiverse.lock")
	content := `{"version":1,"pins":{"ripgrep":{"rev":"d407","label":"2026-08-01-d407","version":"15.1.0","date":"2026-08-01","constraint":"15.1.0"},"nh":{"rev":"e554","label":"l","version":"4.4.2","date":"2026-09-17","constraint":null}}}`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	pins, err := ReadLock(path)
	if err != nil {
		t.Fatal(err)
	}
	if pins["ripgrep"].Version != "15.1.0" || pins["ripgrep"].Constraint != "15.1.0" || pins["nh"].Constraint != "" {
		t.Errorf("pins = %+v", pins)
	}
	if err := os.WriteFile(path, []byte(`{"version":1}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadLock(path); err == nil {
		t.Error("lock without pins accepted")
	}
}

func writeTree(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for name, content := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestPinnedAndPkgsAttrs(t *testing.T) {
	root := writeTree(t, map[string]string{
		"modules/git.nix":  "{ pinned, pkgs, ... }:\n{ package = pinned.git; lfs.package = pinned.git-lfs;\n  x = pkgs.darwin.trash; y = pkgs.callPackage ./a { }; }\n",
		"modules/rust.nix": "{ pkgs, ... }: pkgs.lib.mkIf true { a = pinned.go_1_27; }\n",
		"packages.nix":     "[\n  \"pinned.notme\"\n]\n",
		"README.md":        "pinned.readme pkgs.readme\n",
	})
	skip := filepath.Join(root, "packages.nix")
	pinned, err := PinnedAttrs(root, skip)
	if err != nil {
		t.Fatal(err)
	}
	got := keys(pinned)
	if want := []string{"git", "git-lfs", "go_1_27"}; !reflect.DeepEqual(got, want) {
		t.Errorf("PinnedAttrs = %v, want %v", got, want)
	}
	if refs := Relative(root, pinned["git"]); !reflect.DeepEqual(refs, []string{"modules/git.nix:2"}) {
		t.Errorf("git refs = %v", refs)
	}
	pkgs, err := PkgsAttrs(root)
	if err != nil {
		t.Fatal(err)
	}
	if got := keys(pkgs); !reflect.DeepEqual(got, []string{"callPackage", "darwin.trash", "lib.mkIf"}) {
		t.Errorf("PkgsAttrs = %v", got)
	}
}

func TestConsumers(t *testing.T) {
	root := writeTree(t, map[string]string{
		"dev.nix":                   "with pinned; [ nixfmt git jq ]\n",
		"home-manager/packages.nix": "[\n  \"jq\"\n]\n",
		"hosts/ser8/default.nix":    "{ a = pinned.jq-go; b = pinned.jq; }\n",
		"modules/x.nix":             "# jq_extra is different\n",
		"experimental/notes.md":     "jq\n",
		// Parser fixtures and hm's own tree mention names without consuming
		// the pin.
		"tools/hm/internal/nixlist/testdata/packages.nix": "[\n  \"jq\"\n]\n",
		"tools/hm/default.nix":                            "{ jq }: jq\n",
		"modules/testdata/fixture.nix":                    "{ inherit jq; }\n",
	})
	refs, err := Consumers(root, "jq", filepath.Join(root, "home-manager/packages.nix"))
	if err != nil {
		t.Fatal(err)
	}
	got := Relative(root, refs)
	if want := []string{"dev.nix:1", "hosts/ser8/default.nix:1"}; !reflect.DeepEqual(got, want) {
		t.Errorf("Consumers = %v, want %v", got, want)
	}
	refs, err = Consumers(root, "jq-go")
	if err != nil || len(refs) != 1 {
		t.Errorf("Consumers(jq-go) = %v, %v", refs, err)
	}
}

func keys(m map[string][]Reference) []string {
	var out []string
	for k := range m {
		out = append(out, k)
	}
	sortStrings(out)
	return out
}

func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}

func TestGoBinaries(t *testing.T) {
	dir := t.TempDir()
	self, err := os.Executable()
	if err != nil {
		t.Skip(err)
	}
	data, err := os.ReadFile(self)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sources.test"), data, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "script"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	bins, err := GoBinaries(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(bins) != 2 {
		t.Fatalf("bins = %+v", bins)
	}
	byName := map[string]GoBinary{}
	for _, b := range bins {
		byName[b.Name] = b
	}
	if b := byName["sources.test"]; b.Err != nil || !strings.HasSuffix(b.Module, "tools/hm") || b.GoVersion == "" {
		t.Errorf("test binary info = %+v", b)
	}
	if b := byName["script"]; b.Err == nil {
		t.Error("shell script parsed as a Go binary")
	}
	if got, err := GoBinaries(filepath.Join(dir, "missing")); err != nil || got != nil {
		t.Errorf("missing dir = %v, %v", got, err)
	}
}

func TestGoEntry(t *testing.T) {
	e, err := ParseGoEntry("github.com/fatih/gomodifytags@v1.17.0")
	if err != nil || e.Pattern != "github.com/fatih/gomodifytags" || e.Version != "v1.17.0" || e.String() != "github.com/fatih/gomodifytags@v1.17.0" {
		t.Errorf("entry = %+v, %v", e, err)
	}
	if !e.Matches(GoBinary{Path: "github.com/fatih/gomodifytags"}) || e.Matches(GoBinary{Path: "github.com/fatih/gomodifytags/cmd"}) {
		t.Error("exact pattern matching is wrong")
	}
	all, err := ParseGoEntry("sigs.k8s.io/kubetest2/...@v0.0.0-20240905095256-f6e8664cd2b1")
	if err != nil || all.Name() != "sigs.k8s.io/kubetest2" {
		t.Fatalf("entry = %+v, %v", all, err)
	}
	for _, path := range []string{"sigs.k8s.io/kubetest2", "sigs.k8s.io/kubetest2/kubetest2-gke"} {
		if !all.Matches(GoBinary{Path: path}) {
			t.Errorf("%s did not match /... pattern", path)
		}
	}
	if all.Matches(GoBinary{Path: "sigs.k8s.io/kubetest2-other"}) {
		t.Error("/... pattern matched a sibling path")
	}
	for _, bad := range []string{"gomodifytags", "gomodifytags@", "@v1", "x@latest", "x@1.2.3"} {
		if _, err := ParseGoEntry(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestParseCargoList(t *testing.T) {
	out := "cargo-audit v0.22.2:\n    cargo-audit\nwt v0.3.1 (/Users/bobby/src/wt):\n    wt\nrustlings v6.5.0:\n    rustlings\n"
	tools := ParseCargoList(out)
	if len(tools) != 3 {
		t.Fatalf("tools = %+v", tools)
	}
	if tools[0].Name != "cargo-audit" || tools[0].Version != "0.22.2" || tools[0].Bins[0] != "cargo-audit" {
		t.Errorf("first = %+v", tools[0])
	}
	if tools[1].Source != "/Users/bobby/src/wt" || tools[1].Version != "0.3.1" {
		t.Errorf("second = %+v", tools[1])
	}
	if got := ParseCargoList(""); len(got) != 0 {
		t.Errorf("empty = %+v", got)
	}
}

func TestParseUvList(t *testing.T) {
	out := "claude-monitor v3.1.0\n- ccm\n- ccmonitor\npar-cc-usage v0.9.1 [required: ==0.9.1]\n- par-cc-usage\n"
	tools := ParseUvList(out)
	if len(tools) != 2 || tools[0].Name != "claude-monitor" || tools[0].Version != "3.1.0" || len(tools[0].Bins) != 2 {
		t.Errorf("tools = %+v", tools)
	}
	if tools[1].Version != "0.9.1" {
		t.Errorf("second = %+v", tools[1])
	}
}

func TestSplitEntry(t *testing.T) {
	name, version, err := SplitEntry("claude-monitor==3.1.0", "==")
	if err != nil || name != "claude-monitor" || version != "3.1.0" {
		t.Errorf("got %q %q %v", name, version, err)
	}
	for _, bad := range []string{"claude-monitor", "==1", "x=="} {
		if _, _, err := SplitEntry(bad, "=="); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestShadowed(t *testing.T) {
	root := t.TempDir()
	nixBin := filepath.Join(root, "nix-profile", "bin")
	brewBin := filepath.Join(root, "brew", "bin")
	store := filepath.Join(root, "store", "rg")
	for _, d := range []string{nixBin, brewBin, filepath.Dir(store)} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	touch := func(path string) {
		if err := os.WriteFile(path, []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	touch(store)
	touch(filepath.Join(brewBin, "rg"))
	touch(filepath.Join(brewBin, "fd"))
	touch(filepath.Join(nixBin, "fd"))
	touch(filepath.Join(nixBin, "jq"))
	if err := os.Symlink(store, filepath.Join(nixBin, "rg")); err != nil {
		t.Fatal(err)
	}
	// rg and fd are shadowed by brew; jq is only in nix.
	got := Shadowed(brewBin+":"+nixBin, []string{nixBin})
	if len(got) != 2 || got[0].Name != "fd" || got[1].Name != "rg" || got[1].Winner != filepath.Join(brewBin, "rg") {
		t.Errorf("Shadowed = %+v", got)
	}
	// With nix first nothing is shadowed.
	if got := Shadowed(nixBin+":"+brewBin, []string{nixBin}); len(got) != 0 {
		t.Errorf("Shadowed with nix first = %+v", got)
	}
}

func TestExecutables(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "versions", "2.1.274", "claude")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(bin, "claude")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "isocule"), []byte("x"), 0o755); err != nil {
		t.Fatal(err)
	}
	xs, err := Executables(bin)
	if err != nil || len(xs) != 2 {
		t.Fatalf("Executables = %+v, %v", xs, err)
	}
	if xs[0].Name != "claude" || xs[0].VersionHint() != "2.1.274" || xs[1].VersionHint() != "" {
		t.Errorf("Executables = %+v", xs)
	}
}
