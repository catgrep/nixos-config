// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/nixlist"
	"github.com/catgrep/nixos-config/tools/hm/internal/run"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
)

// Files hm reads and writes, relative to the flake.
const (
	fileLock      = "multiverse.lock"
	fileFlakeLock = "flake.lock"
	filePackages  = "home-manager/packages.nix"
	fileGoTools   = "home-manager/go-tools.nix"
	fileUvTools   = "home-manager/uv-tools.nix"
	fileCargo     = "home-manager/cargo-tools.nix"
	fileCasks     = "darwin/homebrew/casks.nix"
	fileBrews     = "darwin/homebrew/brews.nix"
	dirModules    = "home-manager"
	dirDarwin     = "darwin"
)

// spdxHeader is the first line of every list hm creates.
const spdxHeader = "# SPDX-License-Identifier: GPL-3.0-or-later"

// ownedLists returns the data files hm parses and writes.
func ownedLists() []string {
	return []string{filePackages, fileGoTools, fileUvTools, fileCargo, fileCasks, fileBrews}
}

// readList parses an owned list, returning an empty list and created=true
// when the file does not exist yet.
func (a *App) readList(rel string) (*nixlist.List, bool, error) {
	l, err := nixlist.Read(a.path(rel))
	if errors.Is(err, os.ErrNotExist) {
		return nixlist.Empty(spdxHeader), true, nil
	}
	if err != nil {
		return nil, false, fail(ExitFailed, "%v", err)
	}
	return l, false, nil
}

// mvs returns the mvs on PATH bound to the flake's lock.
func (a *App) mvs() run.Mvs {
	return run.NewMvs(a.runner, []string{"mvs"}, a.path(fileLock))
}

// mvsFromFlake returns the mvs the flake's refreshed input builds, for use
// after nix flake update mvs when the one on PATH is still the previous
// generation's.
func (a *App) mvsFromFlake() run.Mvs {
	return run.NewMvs(a.runner, []string{"nix", "run", a.flake + "#mvs", "--"}, a.path(fileLock))
}

// configName is the homeConfigurations attribute nh selects: user@host.
func (a *App) configName() string {
	name := a.env.Getenv("USER")
	if name == "" {
		if u, err := user.Current(); err == nil {
			name = u.Username
		}
	}
	return name + "@" + a.hostName()
}

// hostName is the host part nh uses to select a configuration:
// LocalHostName on macOS, else the short hostname. It also names the
// darwinConfigurations attribute.
func (a *App) hostName() string {
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("scutil", "--get", "LocalHostName").Output(); err == nil {
			if host := strings.TrimSpace(string(out)); host != "" {
				return host
			}
		}
	}
	h, _ := os.Hostname()
	host, _, _ := strings.Cut(h, ".")
	return host
}

// currentGeneration returns the active generation's store path.
func (a *App) currentGeneration() (string, error) {
	return sources.CurrentGeneration(a.home, a.env.Getenv)
}

// toolBin resolves a toolchain program, preferring the copy in the active
// generation so hm sync uses the pinned toolchain even when PATH still
// lists another one first.
func (a *App) toolBin(name string) string {
	if gen, err := a.currentGeneration(); err == nil {
		candidate := filepath.Join(gen, "home-path", "bin", name)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return name
}

// gobin returns where go install puts binaries: GOBIN, else GOPATH/bin,
// else ~/go/bin, read from the toolchain so the go env file counts.
func (a *App) gobin() string {
	out, err := a.runner.Output(run.Cmd{Prog: a.toolBin("go"), Args: []string{"env", "GOBIN", "GOPATH"}})
	if err == nil {
		fields := strings.Split(strings.TrimRight(string(out), "\n"), "\n")
		if len(fields) == 2 {
			if fields[0] != "" {
				return fields[0]
			}
			if fields[1] != "" {
				return filepath.Join(strings.Split(fields[1], string(os.PathListSeparator))[0], "bin")
			}
		}
	}
	return filepath.Join(a.home, "go", "bin")
}

// subject renders a commit subject from the template layer: verb name
// version, at most 72 characters with the version kept. A Go pseudo-version
// is written with its date and without its commit hash, since the commit
// body carries the full entry; only a name that still does not fit is cut.
func subject(layer, verb, name, version string) string {
	const limit = 72
	words := strings.Fields(version)
	for i, w := range words {
		words[i] = shortPseudoVersion(w)
	}
	tail := ""
	if len(words) > 0 {
		tail = " " + strings.Join(words, " ")
	}
	head := layer + ": " + verb + " "
	if len(head)+len(name)+len(tail) <= limit {
		return head + name + tail
	}
	room := limit - len(head) - len(tail)
	if room < 1 {
		room = 1
	}
	return head + name[:room] + tail
}

// shortPseudoVersion drops the commit hash from a Go pseudo-version such as
// v0.0.0-20240905095256-f6e8664cd2b1, keeping the timestamp, and returns
// any other version unchanged.
func shortPseudoVersion(v string) string {
	i := strings.LastIndex(v, "-")
	if i < 0 || !allOf(v[i+1:], 12, "0123456789abcdef") {
		return v
	}
	j := strings.LastIndex(v[:i], "-")
	if j < 0 || !allOf(v[j+1:i], 14, "0123456789") {
		return v
	}
	return v[:i]
}

// allOf reports whether s has exactly n characters, all from alphabet.
func allOf(s string, n int, alphabet string) bool {
	if len(s) != n {
		return false
	}
	for _, c := range s {
		if !strings.ContainsRune(alphabet, c) {
			return false
		}
	}
	return true
}

// validateList runs nix eval on a written list and checks that it is a
// list of strings, so a malformed edit stops before nh sees it.
func (a *App) validateList(rel string) error {
	raw, err := a.nix.EvalFile(a.path(rel))
	if err != nil {
		return fmt.Errorf("%s does not evaluate: %v", rel, err)
	}
	var values []string
	if err := jsonUnmarshal(raw, &values); err != nil {
		return fmt.Errorf("%s does not evaluate to a list of strings", rel)
	}
	return nil
}
