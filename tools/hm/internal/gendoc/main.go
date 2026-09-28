// SPDX-License-Identifier: GPL-3.0-or-later

// Command gendoc renders the hm(1) man page from the internal/doc structs.
// The Nix package runs it in postBuild, so the page can never drift from
// --help.
package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
)

func main() {
	out := flag.String("o", "", "write the page to this file instead of stdout")
	version := flag.String("version", "dev", "version printed in the page footer")
	date := flag.String("date", time.Now().UTC().Format("2006-01-02"), "date printed in the page footer")
	flag.Parse()
	page := doc.Man(*version, *date)
	if *out == "" {
		fmt.Print(page)
		return
	}
	if err := os.WriteFile(*out, []byte(page), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "gendoc:", err)
		os.Exit(1)
	}
}
