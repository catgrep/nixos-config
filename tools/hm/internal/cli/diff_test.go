// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"strings"
	"testing"
)

func TestUnifiedDiffAppend(t *testing.T) {
	a := "[\n  \"a\"\n  \"b\"\n]\n"
	b := "[\n  \"a\"\n  \"b\"\n  \"c\"\n]\n"
	want := "--- a/x.nix\n+++ b/x.nix\n@@ -1,4 +1,5 @@\n [\n   \"a\"\n   \"b\"\n+  \"c\"\n ]\n"
	if got := unifiedDiff("x.nix", []byte(a), []byte(b)); got != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
	if got := unifiedDiff("x.nix", []byte(a), []byte(a)); got != "" {
		t.Errorf("identical files produced a diff: %q", got)
	}
}

func TestUnifiedDiffHunksLimitContext(t *testing.T) {
	var a, b []string
	for i := 1; i <= 40; i++ {
		a = append(a, fmt.Sprintf("line %d", i))
	}
	b = append(b, a...)
	b[4] = "changed 5"
	b = append(b[:30], append([]string{"inserted"}, b[30:]...)...)
	got := unifiedDiff("f", []byte(strings.Join(a, "\n")+"\n"), []byte(strings.Join(b, "\n")+"\n"))
	if strings.Count(got, "@@") != 4 {
		t.Fatalf("want two hunks, got:\n%s", got)
	}
	for _, want := range []string{"@@ -2,7 +2,7 @@", "-line 5", "+changed 5", "@@ -28,6 +28,7 @@", "+inserted", " line 33"} {
		if !strings.Contains(got, want) {
			t.Errorf("diff lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "line 20") {
		t.Errorf("diff carries lines far from any change:\n%s", got)
	}
}

func TestUnifiedDiffFromEmpty(t *testing.T) {
	got := unifiedDiff("new.nix", nil, []byte("[\n]\n"))
	want := "--- a/new.nix\n+++ b/new.nix\n@@ -1,0 +1,2 @@\n+[\n+]\n"
	if got != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
}
