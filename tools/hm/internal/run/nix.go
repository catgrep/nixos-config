// SPDX-License-Identifier: GPL-3.0-or-later

package run

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Nix drives the nix and nix-store commands.
type Nix struct {
	r *Runner
}

// NewNix returns a Nix on r.
func NewNix(r *Runner) Nix {
	return Nix{r: r}
}

// EvalFile evaluates a Nix file to JSON.
func (n Nix) EvalFile(path string) (json.RawMessage, error) {
	return n.r.Output(Cmd{Prog: "nix", Args: []string{"eval", "--json", "--file", path}})
}

// EvalExpr evaluates an impure expression to JSON.
func (n Nix) EvalExpr(expr string) (json.RawMessage, error) {
	return n.r.Output(Cmd{Prog: "nix", Args: []string{"eval", "--json", "--impure", "--expr", expr}})
}

// EvalRaw evaluates an installable's attribute to its string value.
func (n Nix) EvalRaw(installable string) (string, error) {
	out, err := n.r.Output(Cmd{Prog: "nix", Args: []string{"eval", "--raw", installable}})
	return string(out), err
}

// Build builds an installable without a result link and returns its output
// path. Build progress streams to stderr.
func (n Nix) Build(installable string) (string, error) {
	out, err := n.r.Stream(Cmd{Prog: "nix", Args: []string{"build", "--no-link", "--print-out-paths", installable}})
	if err != nil {
		return "", err
	}
	if n.r.DryRun {
		return "", nil
	}
	path := strings.TrimSpace(string(out))
	if path == "" {
		return "", fmt.Errorf("nix build %s printed no output path", installable)
	}
	return path, nil
}

// FlakeUpdate refreshes one input of the flake at dir.
func (n Nix) FlakeUpdate(dir, input string) error {
	return n.r.Do(Cmd{Prog: "nix", Args: []string{"flake", "update", input}, Dir: dir})
}

// References lists the direct store references of a store path.
func (n Nix) References(storePath string) ([]string, error) {
	out, err := n.r.Output(Cmd{Prog: "nix-store", Args: []string{"-q", "--references", storePath}})
	if err != nil {
		return nil, err
	}
	return strings.Fields(string(out)), nil
}

// Shell runs `nix shell installable`, with command when given, attached to
// the terminal.
func (n Nix) Shell(installable string, command []string) error {
	args := []string{"shell", installable}
	if len(command) > 0 {
		args = append(args, "--command")
		args = append(args, command...)
	}
	return n.r.Interactive(Cmd{Prog: "nix", Args: args})
}
