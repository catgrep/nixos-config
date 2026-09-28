// SPDX-License-Identifier: GPL-3.0-or-later

package completion

import (
	"os/exec"
	"strings"
	"testing"

	"github.com/catgrep/nixos-config/tools/hm/internal/doc"
)

func TestScriptsMentionEveryCommandAndFlag(t *testing.T) {
	for _, shell := range Shells() {
		script, err := Script(shell)
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range doc.Commands() {
			if c.Hidden {
				if strings.Contains(script, c.Name+")") || strings.Contains(script, "-a "+c.Name+" ") {
					t.Errorf("%s: hidden command %s is offered", shell, c.Name)
				}
				continue
			}
			if !strings.Contains(script, c.Name) {
				t.Errorf("%s: command %s missing", shell, c.Name)
			}
			for _, f := range c.Flags {
				if !strings.Contains(script, "--"+f.Name) && !strings.Contains(script, "-l "+f.Name) {
					t.Errorf("%s: flag --%s of %s missing", shell, f.Name, c.Name)
				}
			}
		}
		if !strings.Contains(script, "hm __complete") {
			t.Errorf("%s: no dynamic completion call", shell)
		}
	}
	if _, err := Script("tcsh"); err == nil {
		t.Error("unknown shell accepted")
	}
}

func TestBashScriptParses(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	cmd := exec.Command(bash, "-n")
	cmd.Stdin = strings.NewReader(Bash())
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("bash -n: %v\n%s", err, out)
	}
}

func TestZshScriptParses(t *testing.T) {
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("no zsh")
	}
	cmd := exec.Command(zsh, "-n")
	cmd.Stdin = strings.NewReader(Zsh())
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("zsh -n: %v\n%s", err, out)
	}
}

func TestFishScriptParses(t *testing.T) {
	fish, err := exec.LookPath("fish")
	if err != nil {
		t.Skip("no fish")
	}
	cmd := exec.Command(fish, "--no-execute")
	cmd.Stdin = strings.NewReader(Fish())
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("fish --no-execute: %v\n%s", err, out)
	}
}

func TestShellsIsFreshPerCall(t *testing.T) {
	first := Shells()
	first[0] = "tcsh"
	if got := Shells(); got[0] != "zsh" {
		t.Errorf("Shells() shares its backing array: %v", got)
	}
}
