// SPDX-License-Identifier: GPL-3.0-or-later

package nixlist

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func golden(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func parseGolden(t *testing.T, name string) *List {
	t.Helper()
	l, err := Parse(name, golden(t, name))
	if err != nil {
		t.Fatalf("parse %s: %v", name, err)
	}
	return l
}

func TestRoundTrip(t *testing.T) {
	for _, name := range []string{"packages.nix", "comments.nix", "empty.nix", "go-tools.nix", "casks.nix", "brews.nix"} {
		t.Run(name, func(t *testing.T) {
			in := golden(t, name)
			l, err := Parse(name, in)
			if err != nil {
				t.Fatal(err)
			}
			if got := l.Bytes(); string(got) != string(in) {
				t.Errorf("round trip changed the file:\n%s", got)
			}
		})
	}
}

func TestParseEntries(t *testing.T) {
	tests := []struct {
		file string
		want []string
	}{
		{"packages.nix", []string{"addlicense", "bat", "ripgrep"}},
		{"comments.nix", []string{"a", "go-tools", "zizmor"}},
		{"empty.nix", nil},
		{"empty-inline.nix", nil},
		{"go-tools.nix", []string{
			"github.com/fatih/gomodifytags@v1.17.0",
			"sigs.k8s.io/kubetest2/...@v0.0.0-20240905095256-f6e8664cd2b1",
		}},
		{"casks.nix", []string{"anaconda", "ghostty", "stacktower", "syncthing-app"}},
		{"brews.nix", []string{"docker", "lld", "node@22", "peon-ping"}},
	}
	for _, tc := range tests {
		t.Run(tc.file, func(t *testing.T) {
			l := parseGolden(t, tc.file)
			if got := l.Entries(); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("entries = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestInlineEmptyIsRewrittenCanonically(t *testing.T) {
	l := parseGolden(t, "empty-inline.nix")
	if got, want := l.Bytes(), golden(t, "empty.nix"); string(got) != string(want) {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
}

func TestAdd(t *testing.T) {
	tests := []struct {
		file, value, want string
	}{
		{"comments.nix", "gnupg", "comments-add-gnupg.nix"},
		{"comments.nix", "zebra", "comments-add-zebra.nix"},
		{"comments.nix", "zzz", "comments-add-zzz.nix"},
		{"empty.nix", "zizmor", "empty-add-zizmor.nix"},
	}
	for _, tc := range tests {
		t.Run(tc.want, func(t *testing.T) {
			l := parseGolden(t, tc.file)
			if !l.Add(tc.value) {
				t.Fatalf("Add(%q) reported the value as present", tc.value)
			}
			if got, want := l.Bytes(), golden(t, tc.want); string(got) != string(want) {
				t.Errorf("got\n%s\nwant\n%s", got, want)
			}
			if l.Add(tc.value) {
				t.Errorf("second Add(%q) succeeded", tc.value)
			}
		})
	}
}

func TestRemove(t *testing.T) {
	l := parseGolden(t, "comments.nix")
	if !l.Remove("go-tools") {
		t.Fatal("Remove reported go-tools absent")
	}
	if got, want := l.Bytes(), golden(t, "comments-remove-go-tools.nix"); string(got) != string(want) {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
	if l.Remove("go-tools") {
		t.Error("second Remove succeeded")
	}
	if l.Has("go-tools") {
		t.Error("Has reports a removed entry")
	}
}

func TestEmptyHeader(t *testing.T) {
	l := Empty("# SPDX-License-Identifier: GPL-3.0-or-later")
	if got, want := l.Bytes(), golden(t, "empty.nix"); string(got) != string(want) {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
}

func TestSorted(t *testing.T) {
	if !parseGolden(t, "packages.nix").Sorted() {
		t.Error("packages.nix reported unsorted")
	}
	l, err := Parse("x", []byte("[\n  \"b\"\n  \"a\"\n]\n"))
	if err != nil {
		t.Fatal(err)
	}
	if l.Sorted() {
		t.Error("unsorted list reported sorted")
	}
}

func TestParseErrors(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"bare word", "[\n  \"a\"\n  b\n]\n", `x:3: expected a quoted string, a comment or the closing "]"`},
		{"missing close", "[\n  \"a\"\n", `x:3: missing closing "]"`},
		{"trailing content", "[\n  \"a\"\n]\n{ }\n", `x:4: unexpected content after the closing "]"`},
		{"duplicate", "[\n  \"a\"\n  \"a\"\n]\n", `x:3: duplicate entry "a"`},
		{"interpolation", "[\n  \"${a}\"\n]\n", `x:2: entry "${a}" contains '$', which hm does not write`},
		{"empty string", "[\n  \"\"\n]\n", `x:2: empty entry`},
		{"attrset", "{ a = 1; }\n", `x:1: expected a comment or the opening "["`},
		{"empty file", "", `x:1: missing closing "]"`},
		{"two per line", "[\n  \"a\" \"b\"\n]\n", `x:2: entry "a\" \"b" contains '"', which hm does not write`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse("x", []byte(tc.input))
			if err == nil {
				t.Fatal("expected an error")
			}
			if err.Error() != tc.want {
				t.Errorf("error = %q, want %q", err.Error(), tc.want)
			}
		})
	}
}
