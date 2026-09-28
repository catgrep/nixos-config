// SPDX-License-Identifier: GPL-3.0-or-later

package sources

import (
	"debug/buildinfo"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// GoBinary is one executable in GOBIN with the module it was built from.
type GoBinary struct {
	Name      string
	Path      string
	Module    string
	Version   string
	GoVersion string
	Err       error
}

// GoBinaries reads the build information of every executable in dir. A
// file that is not a Go binary is returned with Err set, so the caller can
// report it rather than drop it.
func GoBinaries(dir string) ([]GoBinary, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []GoBinary
	for _, e := range entries {
		info, err := e.Info()
		if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
			continue
		}
		b := GoBinary{Name: e.Name()}
		bi, err := buildinfo.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			b.Err = err
		} else {
			b.Path, b.Module, b.Version, b.GoVersion = bi.Path, bi.Main.Path, bi.Main.Version, bi.GoVersion
		}
		out = append(out, b)
	}
	return out, nil
}

// GoEntry is one go-tools.nix line: a package pattern and a version.
type GoEntry struct {
	Pattern string
	Version string
}

// ParseGoEntry splits "pattern@version" and requires an explicit version,
// since "latest" would make the list unreproducible.
func ParseGoEntry(s string) (GoEntry, error) {
	at := strings.LastIndex(s, "@")
	if at <= 0 || at == len(s)-1 {
		return GoEntry{}, fmt.Errorf("%q: expected module/package@version", s)
	}
	e := GoEntry{Pattern: s[:at], Version: s[at+1:]}
	if e.Version == "latest" || !strings.HasPrefix(e.Version, "v") {
		return GoEntry{}, fmt.Errorf("%q: pin an explicit version such as v1.2.3 (go list -m -versions %s)", s, strings.TrimSuffix(e.Pattern, "/..."))
	}
	return e, nil
}

// String renders the entry as written in go-tools.nix.
func (e GoEntry) String() string {
	return e.Pattern + "@" + e.Version
}

// Name is the entry's package path without a trailing /... pattern.
func (e GoEntry) Name() string {
	return strings.TrimSuffix(e.Pattern, "/...")
}

// Matches reports whether the binary was built from the entry's package
// pattern, at any version.
func (e GoEntry) Matches(b GoBinary) bool {
	if b.Path == "" {
		return false
	}
	if strings.HasSuffix(e.Pattern, "/...") {
		root := strings.TrimSuffix(e.Pattern, "/...")
		return b.Path == root || strings.HasPrefix(b.Path, root+"/")
	}
	return b.Path == e.Pattern
}

// Tool is one installed cargo or uv tool.
type Tool struct {
	Name    string
	Version string
	Bins    []string
	Source  string
}

// ParseCargoList parses `cargo install --list`: a header per crate
// ("name vX.Y.Z:" or "name vX.Y.Z (source):") followed by indented binary
// names.
func ParseCargoList(out string) []Tool {
	var tools []Tool
	for _, line := range strings.Split(out, "\n") {
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
			if len(tools) > 0 {
				tools[len(tools)-1].Bins = append(tools[len(tools)-1].Bins, strings.TrimSpace(line))
			}
			continue
		}
		header := strings.TrimSuffix(line, ":")
		source := ""
		if i := strings.Index(header, " ("); i >= 0 {
			source = strings.TrimSuffix(header[i+2:], ")")
			header = header[:i]
		}
		name, version, _ := strings.Cut(header, " ")
		tools = append(tools, Tool{Name: name, Version: strings.TrimPrefix(version, "v"), Source: source})
	}
	return tools
}

// ParseUvList parses `uv tool list`: a header per tool ("name vX.Y.Z")
// followed by "- binary" lines.
func ParseUvList(out string) []Tool {
	var tools []Tool
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, " ")
		switch {
		case line == "":
		case strings.HasPrefix(line, "- "):
			if len(tools) > 0 {
				tools[len(tools)-1].Bins = append(tools[len(tools)-1].Bins, strings.TrimPrefix(line, "- "))
			}
		default:
			name, version, _ := strings.Cut(line, " ")
			version, _, _ = strings.Cut(version, " ")
			tools = append(tools, Tool{Name: name, Version: strings.TrimPrefix(version, "v")})
		}
	}
	return tools
}

// SplitEntry splits a "name<sep>version" list entry and requires both
// parts.
func SplitEntry(s, sep string) (string, string, error) {
	name, version, ok := strings.Cut(s, sep)
	if !ok || name == "" || version == "" {
		return "", "", fmt.Errorf("%q: expected name%sversion", s, sep)
	}
	return name, version, nil
}

// Shadow is a command whose first PATH hit is not the Nix one.
type Shadow struct {
	Name   string
	Winner string
	Nix    string
}

// Shadowed walks pathEnv and reports every command that exists in one of
// nixDirs but resolves first to a directory outside them.
func Shadowed(pathEnv string, nixDirs []string) []Shadow {
	nix := map[string]bool{}
	names := map[string]string{}
	for _, dir := range nixDirs {
		real, err := filepath.EvalSymlinks(dir)
		if err != nil {
			continue
		}
		nix[real] = true
		entries, err := os.ReadDir(real)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if _, seen := names[e.Name()]; !seen {
				names[e.Name()] = filepath.Join(dir, e.Name())
			}
		}
	}
	var out []Shadow
	for name, nixPath := range names {
		winner := firstOnPath(pathEnv, name)
		if winner == "" {
			continue
		}
		dir, err := filepath.EvalSymlinks(filepath.Dir(winner))
		if err != nil {
			dir = filepath.Dir(winner)
		}
		if nix[dir] {
			continue
		}
		if target, err := filepath.EvalSymlinks(winner); err == nil && strings.HasPrefix(target, "/nix/store/") {
			continue
		}
		out = append(out, Shadow{Name: name, Winner: winner, Nix: nixPath})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func firstOnPath(pathEnv, name string) string {
	for _, dir := range filepath.SplitList(pathEnv) {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, name)
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode().Perm()&0o111 != 0 {
			return candidate
		}
	}
	return ""
}

// Executables lists the executable files directly in dir, with the
// symlink target of each.
func Executables(dir string) ([]Executable, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []Executable
	for _, e := range entries {
		path := filepath.Join(dir, e.Name())
		info, err := os.Stat(path)
		if err != nil || info.IsDir() || info.Mode().Perm()&0o111 == 0 {
			continue
		}
		x := Executable{Name: e.Name(), Path: path}
		if target, err := filepath.EvalSymlinks(path); err == nil && target != path {
			x.Target = target
		}
		out = append(out, x)
	}
	return out, nil
}

// Executable is one file on a PATH directory.
type Executable struct {
	Name   string
	Path   string
	Target string
}

// VersionHint guesses a version from a symlink target such as
// .../versions/2.1.274/claude, or returns "".
func (x Executable) VersionHint() string {
	for _, part := range strings.Split(x.Target, "/") {
		if len(part) > 0 && part[0] >= '0' && part[0] <= '9' && strings.Contains(part, ".") {
			return part
		}
	}
	return ""
}
