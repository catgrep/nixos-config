// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"bytes"
	"reflect"
	"strings"
	"testing"
)

func TestSplitArgs(t *testing.T) {
	tests := []struct {
		args    []string
		flake   string
		dry     bool
		noPager bool
		help    bool
		sub     string
		rest    []string
	}{
		{[]string{"add", "zizmor"}, "", false, false, false, "add", []string{"zizmor"}},
		{[]string{"--flake", "/r", "add", "--commit", "zizmor"}, "/r", false, false, false, "add", []string{"--commit", "zizmor"}},
		{[]string{"add", "zizmor", "--dry-run", "--flake=/r"}, "/r", true, false, false, "add", []string{"zizmor"}},
		{[]string{"--no-pager", "list"}, "", false, true, false, "list", nil},
		{[]string{"add", "--help"}, "", false, false, true, "add", nil},
		{[]string{"try", "hyperfine", "--", "--dry-run"}, "", false, false, false, "try", []string{"hyperfine", "--", "--dry-run"}},
		{[]string{"-h"}, "", false, false, true, "", nil},
	}
	for _, tc := range tests {
		g, sub, rest, err := splitArgs(tc.args)
		if err != nil {
			t.Fatalf("%v: %v", tc.args, err)
		}
		if g.flake != tc.flake || g.dryRun != tc.dry || g.noPager != tc.noPager || g.help != tc.help || sub != tc.sub || !reflect.DeepEqual(rest, tc.rest) {
			t.Errorf("%v: got %+v %q %v", tc.args, g, sub, rest)
		}
	}
	if _, _, _, err := splitArgs([]string{"add", "--flake"}); err == nil {
		t.Error("--flake without a value accepted")
	}
}

func TestPermute(t *testing.T) {
	takes := map[string]bool{"source": true}
	got := permute([]string{"zizmor", "--commit", "--source", "go", "x", "--", "--not-a-flag"}, takes)
	want := []string{"--commit", "--source", "go", "zizmor", "x", "--", "--not-a-flag"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("permute = %v, want %v", got, want)
	}
}

func TestSubject(t *testing.T) {
	tests := []struct {
		layer, verb, name, version, want string
	}{
		{"home", "add", "zizmor", "1.30.1", "home: add zizmor 1.30.1"},
		{"home", "remove", "charasay", "", "home: remove charasay"},
		{"home", "update", "ripgrep", "15.1.0 to 15.2.0", "home: update ripgrep 15.1.0 to 15.2.0"},
		{"home", "add go", "sigs.k8s.io/kubetest2", "v0.0.0-20240905095256-f6e8664cd2b1", "home: add go sigs.k8s.io/kubetest2 v0.0.0-20240905095256-f6e8664cd2b1"},
		{"home", "add go", strings.Repeat("x", 80), "v1.2.3", "home: add go " + strings.Repeat("x", 52) + " v1.2.3"},
	}
	for _, tc := range tests {
		got := subject(tc.layer, tc.verb, tc.name, tc.version)
		if got != tc.want {
			t.Errorf("subject = %q, want %q", got, tc.want)
		}
		if len(got) > 72 {
			t.Errorf("subject longer than 72: %q", got)
		}
	}
}

func TestMainHelpAndUsage(t *testing.T) {
	var out, errOut bytes.Buffer
	code := Main(Env{Args: []string{"--help"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitOK || !strings.Contains(out.String(), "Commands:") {
		t.Errorf("--help: code %d, out %q", code, out.String())
	}
	out.Reset()
	code = Main(Env{Args: []string{"add", "--help"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitOK || !strings.HasPrefix(out.String(), "Usage: hm add") {
		t.Errorf("add --help: code %d, out %q", code, out.String())
	}
	out.Reset()
	code = Main(Env{Args: []string{"bogus"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitUsage || !strings.Contains(errOut.String(), "unknown command") {
		t.Errorf("bogus: code %d, err %q", code, errOut.String())
	}
	errOut.Reset()
	code = Main(Env{Args: []string{"add", "--bogus", "x"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitUsage || !strings.Contains(errOut.String(), "flag provided but not defined") {
		t.Errorf("unknown flag: code %d, err %q", code, errOut.String())
	}
	errOut.Reset()
	code = Main(Env{Args: []string{"add", "zizmor"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitUsage || !strings.Contains(errOut.String(), "NH_FLAKE") {
		t.Errorf("no flake: code %d, err %q", code, errOut.String())
	}
	out.Reset()
	code = Main(Env{Args: []string{"--version"}, Stdout: &out, Stderr: &errOut, Version: "0.1.0", Getenv: func(string) string { return "" }})
	if code != ExitOK || out.String() != "hm 0.1.0\n" {
		t.Errorf("--version: code %d, out %q", code, out.String())
	}
	out.Reset()
	code = Main(Env{Args: []string{"completion", "zsh"}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitOK || !strings.HasPrefix(out.String(), "#compdef hm") {
		t.Errorf("completion zsh: code %d", code)
	}
	out.Reset()
	code = Main(Env{Args: []string{"__complete", "list", "--source", ""}, Stdout: &out, Stderr: &errOut, Version: "t", Getenv: func(string) string { return "" }})
	if code != ExitOK || !strings.Contains(out.String(), "pinned\n") {
		t.Errorf("__complete list --source: code %d, out %q", code, out.String())
	}
}
