// SPDX-License-Identifier: GPL-3.0-or-later

// Package sources reads the inventories hm reports on: the Home Manager
// generation, multiverse.lock, the attributes the modules name, the
// binaries left behind by go install, cargo install and uv tool install,
// and the PATH.
package sources

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// StorePath is one store path with its name split the way nixpkgs'
// parseDrvName does: the version starts at the first dash that is followed
// by a digit.
type StorePath struct {
	Path    string
	Name    string
	Pname   string
	Version string
	Output  string
}

var outputSuffixes = []string{"bin", "man", "doc", "dev", "lib", "info", "devdoc", "debug", "static", "cli", "out", "lib", "dist"}

// ParseStorePath splits a /nix/store path into its parts.
func ParseStorePath(path string) StorePath {
	s := StorePath{Path: path}
	base := filepath.Base(path)
	if i := strings.IndexByte(base, '-'); i == 32 {
		base = base[i+1:]
	}
	s.Name = base
	s.Pname, s.Version = splitDrvName(base)
	for _, suffix := range outputSuffixes {
		if strings.HasSuffix(s.Version, "-"+suffix) {
			s.Version = strings.TrimSuffix(s.Version, "-"+suffix)
			s.Output = suffix
			break
		}
	}
	return s
}

func splitDrvName(name string) (string, string) {
	for i := 0; i+1 < len(name); i++ {
		if name[i] == '-' && name[i+1] >= '0' && name[i+1] <= '9' {
			return name[:i], name[i+1:]
		}
	}
	return name, ""
}

// Base is the name without hash and output suffix, shared by every output
// of one derivation.
func (s StorePath) Base() string {
	if s.Version == "" {
		return s.Pname
	}
	return s.Pname + "-" + s.Version
}

// Generation is a built Home Manager generation.
type Generation struct {
	Path     string
	HomePath string
	Refs     []StorePath
}

// ReadGeneration resolves a generation's home-path and lists what it
// references, using refs to query the store.
func ReadGeneration(path string, refs func(string) ([]string, error)) (*Generation, error) {
	homePath, err := filepath.EvalSymlinks(filepath.Join(path, "home-path"))
	if err != nil {
		return nil, fmt.Errorf("%s is not a Home Manager generation: %w", path, err)
	}
	paths, err := refs(homePath)
	if err != nil {
		return nil, err
	}
	g := &Generation{Path: path, HomePath: homePath}
	for _, p := range paths {
		if p == homePath {
			continue
		}
		g.Refs = append(g.Refs, ParseStorePath(p))
	}
	return g, nil
}

// SessionPath returns the directories home.sessionPath adds, read from the
// generation's hm-session-vars.sh.
func (g *Generation) SessionPath() ([]string, error) {
	f, err := os.Open(filepath.Join(g.HomePath, "etc", "profile.d", "hm-session-vars.sh"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if dirs, ok := parsePathExport(sc.Text()); ok {
			return dirs, nil
		}
	}
	return nil, sc.Err()
}

func parsePathExport(line string) ([]string, bool) {
	const prefix = `export PATH="`
	if !strings.HasPrefix(line, prefix) {
		return nil, false
	}
	value := strings.TrimPrefix(line, prefix)
	if i := strings.Index(value, "${PATH:+:}"); i >= 0 {
		value = value[:i]
	}
	value = strings.TrimSuffix(value, `"`)
	var dirs []string
	for _, d := range strings.Split(value, ":") {
		if d != "" && !strings.Contains(d, "$") {
			dirs = append(dirs, d)
		}
	}
	return dirs, true
}

// StateDir returns the Home Manager state directory: $XDG_STATE_HOME or
// ~/.local/state.
func StateDir(home string, getenv func(string) string) string {
	if s := getenv("XDG_STATE_HOME"); s != "" {
		return s
	}
	return filepath.Join(home, ".local", "state")
}

// CurrentGeneration returns the store path of the active generation.
func CurrentGeneration(home string, getenv func(string) string) (string, error) {
	link := filepath.Join(StateDir(home, getenv), "home-manager", "gcroots", "current-home")
	target, err := filepath.EvalSymlinks(link)
	if err != nil {
		return "", fmt.Errorf("no active Home Manager generation at %s: %w", link, err)
	}
	return target, nil
}

// GenerationNumber returns the number of the active generation from the
// home-manager profile link, or 0 when there is none.
func GenerationNumber(home string, getenv func(string) string) int {
	candidates := []string{
		filepath.Join(StateDir(home, getenv), "nix", "profiles", "home-manager"),
		filepath.Join("/nix/var/nix/profiles/per-user", filepath.Base(home), "home-manager"),
	}
	re := regexp.MustCompile(`home-manager-(\d+)-link$`)
	for _, link := range candidates {
		target, err := os.Readlink(link)
		if err != nil {
			continue
		}
		if m := re.FindStringSubmatch(target); m != nil {
			n, _ := strconv.Atoi(m[1])
			return n
		}
	}
	return 0
}
