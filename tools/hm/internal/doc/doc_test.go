// SPDX-License-Identifier: GPL-3.0-or-later

package doc

import (
	"strings"
	"testing"
)

func TestEveryCommandIsDocumented(t *testing.T) {
	for _, c := range Commands() {
		if c.Hidden {
			continue
		}
		if c.Summary == "" || strings.HasSuffix(c.Summary, ".") || c.Summary[0] < 'a' || c.Summary[0] > 'z' {
			t.Errorf("%s: summary must be a lower-case phrase without a period: %q", c.Name, c.Summary)
		}
		if len(c.Description) == 0 {
			t.Errorf("%s: no description", c.Name)
		}
		if len(c.Examples) < 2 {
			t.Errorf("%s: %d examples, want at least two", c.Name, len(c.Examples))
		}
		for _, e := range c.Examples {
			if !strings.HasPrefix(e.Command, Name+" ") && !strings.Contains(e.Command, Name+" ") {
				t.Errorf("%s: example %q does not invoke %s", c.Name, e.Command, Name)
			}
			if e.Help == "" {
				t.Errorf("%s: example %q has no explanation", c.Name, e.Command)
			}
		}
		for _, f := range c.Flags {
			if f.Help == "" {
				t.Errorf("%s: flag --%s has no help", c.Name, f.Name)
			}
			if f.Arg == "" && f.Default != "" {
				t.Errorf("%s: boolean flag --%s has a default", c.Name, f.Name)
			}
		}
		if c.Complete == CompleteWords && len(c.Words) == 0 {
			t.Errorf("%s: word completion without words", c.Name)
		}
	}
}

func TestBuildOnlyIsOnEveryMutatingCommand(t *testing.T) {
	for _, name := range []string{"add", "rm", "up", "sync"} {
		c, ok := Lookup(name)
		if !ok {
			t.Fatalf("no command %s", name)
		}
		found := false
		for _, f := range c.Flags {
			found = found || f.Name == "build-only"
		}
		if !found {
			t.Errorf("%s lacks --build-only", name)
		}
	}
}

func TestHelpText(t *testing.T) {
	c, _ := Lookup("add")
	help := Help(c)
	for _, want := range []string{
		"Usage: hm add [--commit] [--build-only] [--keep-on-failure]\n       [--go | --uv | --cargo] NAME[@VERSION]",
		"Pin a package and install it.",
		"  --commit ",
		"  --build-only ",
		"Examples:",
		"hm add zizmor",
		"Global options: --flake PATH, --dry-run, --no-pager, --help, --version",
	} {
		if !strings.Contains(help, want) {
			t.Errorf("add --help lacks %q:\n%s", want, help)
		}
	}
	for _, line := range strings.Split(help, "\n") {
		if len(line) > Width+2 {
			t.Errorf("line longer than %d columns: %q", Width, line)
		}
	}
}

func TestTopHelp(t *testing.T) {
	help := TopHelp("0.1.0")
	for _, c := range Commands() {
		if c.Hidden {
			if strings.Contains(help, c.Name) {
				t.Errorf("hidden command %s appears in --help", c.Name)
			}
			continue
		}
		if !strings.Contains(help, "  "+c.Name) {
			t.Errorf("--help lacks command %s", c.Name)
		}
	}
	if got := strings.Count(help, "\n  hm "); got != len(WorkedExamples()) {
		t.Errorf("--help shows %d worked examples, want %d", got, len(WorkedExamples()))
	}
	if !strings.Contains(help, "hm 0.1.0") {
		t.Error("--help lacks the version")
	}
}

func TestManual(t *testing.T) {
	text := Manual("0.1.0")
	for _, section := range []string{"NAME", "SYNOPSIS", "DESCRIPTION", "GLOBAL OPTIONS", "COMMANDS", "FILES", "ENVIRONMENT", "EXIT STATUS", "EXAMPLES", "SEE ALSO"} {
		if !strings.Contains(text, "\n"+section+"\n") {
			t.Errorf("manual lacks section %s", section)
		}
	}
	for _, c := range Commands() {
		if !c.Hidden && !strings.Contains(text, "\n  "+Synopsis(c)+"\n") {
			t.Errorf("manual lacks the synopsis of %s", c.Name)
		}
	}
	for _, e := range ExitCodes() {
		if !strings.Contains(text, "  "+string(rune('0'+e.Code))+"  ") {
			t.Errorf("manual lacks exit code %d", e.Code)
		}
	}
}

func TestMan(t *testing.T) {
	page := Man("0.1.0", "2026-09-28")
	if !strings.HasPrefix(page, `.TH HM 1 "2026-09-28" "hm 0.1.0" "User Commands"`+"\n") {
		t.Errorf("man page header = %q", strings.SplitN(page, "\n", 2)[0])
	}
	for _, c := range Commands() {
		if c.Hidden {
			if strings.Contains(page, ".SS "+c.Name) {
				t.Errorf("hidden command %s appears in the man page", c.Name)
			}
			continue
		}
		if !strings.Contains(page, ".SS "+c.Name+"\n") {
			t.Errorf("man page lacks .SS %s", c.Name)
		}
	}
	for _, want := range []string{".SH FILES", ".SH ENVIRONMENT", ".SH EXIT STATUS", ".SH EXAMPLES", ".SH SEE ALSO", `.B \-\-build\-only`, `.BI \-\-flake " PATH"`, ".B NH_FLAKE"} {
		if !strings.Contains(page, want) {
			t.Errorf("man page lacks %q", want)
		}
	}
	for i, line := range strings.Split(page, "\n") {
		if i > 0 && (strings.Contains(line, " -") || strings.HasPrefix(line, "-")) {
			t.Errorf("line %d has an unescaped hyphen: %q", i+1, line)
		}
		if len(line) > Width+2 && !strings.HasPrefix(line, ".") {
			t.Errorf("line %d longer than %d bytes: %q", i+1, Width, line)
		}
	}
}

func TestRoff(t *testing.T) {
	tests := map[string]string{
		"a-b":        `a\-b`,
		`C:\dir`:     `C:\edir`,
		".hidden":    `\&.hidden`,
		"'quoted":    `\&'quoted`,
		"plain":      "plain",
		"--no-pager": `\-\-no\-pager`,
	}
	for in, want := range tests {
		if got := roff(in); got != want {
			t.Errorf("roff(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestWrap(t *testing.T) {
	got := Wrap("one two three four five six seven eight nine ten", 20, "  ")
	want := "  one two three four\n  five six seven\n  eight nine ten\n"
	if got != want {
		t.Errorf("Wrap = %q, want %q", got, want)
	}
	if got := Wrap("", 20, "  "); got != "" {
		t.Errorf("Wrap of empty = %q", got)
	}
	if got := Wrap("supercalifragilisticexpialidocious", 10, ""); got != "supercalifragilisticexpialidocious\n" {
		t.Errorf("long word = %q", got)
	}
}
