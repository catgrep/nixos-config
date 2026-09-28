// SPDX-License-Identifier: GPL-3.0-or-later

// Command hm manages the packages of this repository's Home Manager
// configuration: it pins nixpkgs attributes through multiverse.lock, edits
// the list files it owns, switches with nh and keeps go, uv and cargo tools
// in step with their declared versions.
package main

import (
	"os"

	"github.com/catgrep/nixos-config/tools/hm/internal/cli"
)

// version is set at build time through -ldflags "-X main.version=...".
var version = "dev"

func main() {
	os.Exit(cli.Main(cli.Env{
		Args:    os.Args[1:],
		Stdin:   os.Stdin,
		Stdout:  os.Stdout,
		Stderr:  os.Stderr,
		Getenv:  os.Getenv,
		Version: version,
	}))
}
