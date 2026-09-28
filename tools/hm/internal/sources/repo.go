// SPDX-License-Identifier: GPL-3.0-or-later

package sources

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// LockPin is one multiverse.lock entry.
type LockPin struct {
	Version    string `json:"version"`
	Rev        string `json:"rev"`
	Label      string `json:"label"`
	Date       string `json:"date"`
	Constraint string `json:"constraint"`
}

// ReadLock decodes multiverse.lock.
func ReadLock(path string) (map[string]LockPin, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var lock struct {
		Version int                `json:"version"`
		Pins    map[string]LockPin `json:"pins"`
	}
	if err := json.Unmarshal(data, &lock); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if lock.Pins == nil {
		return nil, fmt.Errorf("%s: no pins", path)
	}
	return lock.Pins, nil
}

var (
	pinnedRef = regexp.MustCompile(`\bpinned\.([A-Za-z_][A-Za-z0-9_'-]*)`)
	pkgsRef   = regexp.MustCompile(`\bpkgs\.([A-Za-z_][A-Za-z0-9_'-]*(?:\.[A-Za-z_][A-Za-z0-9_'-]*)*)`)
)

// Reference is one place a Nix file names an attribute.
type Reference struct {
	File string
	Line int
}

// nixFiles lists every .nix file under dir except those in skip.
func nixFiles(dir string, skip map[string]bool) ([]string, error) {
	var files []string
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == ".git" || d.Name() == ".direnv" {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(path) == ".nix" && !skip[path] {
			files = append(files, path)
		}
		return nil
	})
	sort.Strings(files)
	return files, err
}

func scan(files []string, re *regexp.Regexp) (map[string][]Reference, error) {
	out := map[string][]Reference{}
	for _, file := range files {
		f, err := os.Open(file)
		if err != nil {
			return nil, err
		}
		sc := bufio.NewScanner(f)
		for n := 1; sc.Scan(); n++ {
			for _, m := range re.FindAllStringSubmatch(sc.Text(), -1) {
				out[m[1]] = append(out[m[1]], Reference{File: file, Line: n})
			}
		}
		if err := sc.Err(); err != nil {
			_ = f.Close()
			return nil, err
		}
		_ = f.Close()
	}
	return out, nil
}

// PinnedAttrs maps every attribute the Nix files under dir take from
// `pinned` to the places that name it.
func PinnedAttrs(dir string, skip ...string) (map[string][]Reference, error) {
	files, err := nixFiles(dir, set(skip))
	if err != nil {
		return nil, err
	}
	return scan(files, pinnedRef)
}

// PkgsAttrs maps every attribute path the Nix files under dir take from
// `pkgs` to the places that name it.
func PkgsAttrs(dir string, skip ...string) (map[string][]Reference, error) {
	files, err := nixFiles(dir, set(skip))
	if err != nil {
		return nil, err
	}
	return scan(files, pkgsRef)
}

func set(items []string) map[string]bool {
	m := map[string]bool{}
	for _, s := range items {
		m[s] = true
	}
	return m
}

// Consumers lists the places under root where a .nix file names attr as a
// whole word, skipping the given files. It is how hm checks that a pin
// has no other consumer before pruning it.
func Consumers(root, attr string, skip ...string) ([]Reference, error) {
	files, err := nixFiles(root, set(skip))
	if err != nil {
		return nil, err
	}
	re := regexp.MustCompile(`(^|[^A-Za-z0-9_'-])` + regexp.QuoteMeta(attr) + `($|[^A-Za-z0-9_'-])`)
	var refs []Reference
	for _, file := range files {
		f, err := os.Open(file)
		if err != nil {
			return nil, err
		}
		sc := bufio.NewScanner(f)
		for n := 1; sc.Scan(); n++ {
			if re.MatchString(sc.Text()) {
				refs = append(refs, Reference{File: file, Line: n})
			}
		}
		if err := sc.Err(); err != nil {
			_ = f.Close()
			return nil, err
		}
		_ = f.Close()
	}
	return refs, nil
}

// Relative renders references relative to root as file:line strings.
func Relative(root string, refs []Reference) []string {
	out := make([]string, 0, len(refs))
	for _, r := range refs {
		file := r.File
		if rel, err := filepath.Rel(root, file); err == nil && !strings.HasPrefix(rel, "..") {
			file = rel
		}
		out = append(out, fmt.Sprintf("%s:%d", file, r.Line))
	}
	return out
}
