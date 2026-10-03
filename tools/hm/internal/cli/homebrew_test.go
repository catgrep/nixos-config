// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

const casksWithGhostty = "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"ghostty\"\n]\n"

// A cask add with --build-only writes the list, builds the nix-darwin
// system named after this Mac and commits, but never switches; the
// darwin layer has no active generation to diff against here.
func TestAddCaskBuildOnly(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--cask", "--build-only", "--commit", "ghostty")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		"+ nix build --no-link --print-out-paths '" + h.repo + "#darwinConfigurations.\"",
		".system'",
		"hm: built " + h.store + "/built-generation",
		"hm: not activated; run: hm switch darwin",
		`hm: committed "darwin: add cask ghostty"`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if got := h.read("darwin/homebrew/casks.nix"); got != casksWithGhostty {
		t.Errorf("casks.nix = %q", got)
	}
	if calls := h.calls(); strings.Contains(calls, "nh darwin switch") || strings.Contains(calls, "nvd diff") || strings.Contains(calls, "mvs ") {
		t.Errorf("build-only switched, diffed or pinned:\n%s", calls)
	}
	if files := h.git("show", "--name-only", "--format=", "HEAD"); strings.TrimSpace(files) != "darwin/homebrew/casks.nix" {
		t.Errorf("committed files = %q", files)
	}
	code, out = h.run("add", "--cask", "--build-only", "ghostty")
	if code != ExitOK || !strings.Contains(out, "ghostty is already in darwin/homebrew/casks.nix") || !strings.Contains(out, "hm: nothing to commit") {
		t.Fatalf("second add: exit %d\n%s", code, out)
	}
}

// A formula name is taken whole: the @ of node@22 is not a version, and
// no pin is consulted or created.
func TestAddBrewSwitchesDarwin(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--brew", "node@22")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		"+ nh darwin switch " + h.repo,
		" to darwin generation 1",
		"hm: added brew node@22 (darwin generation 1)",
		"hm: uncommitted: darwin/homebrew/brews.nix",
		"darwin: add brew node@22",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if !strings.Contains(h.read("darwin/homebrew/brews.nix"), "  \"node@22\"\n") {
		t.Errorf("brews.nix = %q", h.read("darwin/homebrew/brews.nix"))
	}
	if calls := h.calls(); strings.Contains(calls, "nix build") || strings.Contains(calls, "mvs ") || strings.Contains(calls, "nh home switch") {
		t.Errorf("unexpected commands:\n%s", calls)
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeOK || j.LastStep() != "report" {
		t.Errorf("journal = %+v", j)
	}
}

func TestAddHomebrewRejectsBadNames(t *testing.T) {
	h := newHarness(t)
	for _, args := range [][]string{
		{"add", "--cask", "Ghostty"},
		{"add", "--brew", "../docker"},
		{"add", "--brew", "user/docker"},
		{"add", "--cask", "--brew", "ghostty"},
		{"add", "--cask", "--go", "ghostty"},
	} {
		if code, out := h.run(args...); code != ExitUsage {
			t.Errorf("%v: exit %d\n%s", args, code, out)
		}
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("a refused add changed files: %q", status)
	}
	if calls := h.calls(); strings.Contains(calls, "nh ") || strings.Contains(calls, "nix build") {
		t.Errorf("a refused add ran commands:\n%s", calls)
	}
}

// The darwin switch follows the same rule as the home one: a failure
// before the system profile moved restores the list, a failure after it
// moved keeps the list as the source of what is now active.
func TestAddCaskFailedSwitch(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL", "1")
	code, out := h.run("add", "--cask", "ghostty")
	if code != ExitFailed || !strings.Contains(out, "hm: restored darwin/homebrew/casks.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if got := h.read("darwin/homebrew/casks.nix"); got != emptyList {
		t.Errorf("casks.nix not restored: %q", got)
	}
	t.Setenv("FAKE_NH_FAIL", "")
	t.Setenv("FAKE_NH_FAIL_AFTER", "1")
	code, out = h.run("add", "--cask", "ghostty")
	if code != ExitFailed || !strings.Contains(out, "darwin generation 1 is now active") || !strings.Contains(out, "were kept: darwin/homebrew/casks.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if got := h.read("darwin/homebrew/casks.nix"); got != casksWithGhostty {
		t.Errorf("casks.nix was restored after activation: %q", got)
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeActivated || j.Resolved() {
		t.Errorf("journal = %+v", j)
	}
}

// nh darwin switch can report success and still leave the system profile
// unreadable. hm then cannot tell what is active, so the list is kept as
// the source of the switched system and the run stays unresolved, as
// after a failed switch that moved the profile.
func TestAddCaskKeepsListWhenStateAfterSwitchUnreadable(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_DANGLE", "1")
	code, out := h.run("add", "--cask", "ghostty")
	if code != ExitFailed || strings.Contains(out, "restored") || !strings.Contains(out, "cannot be read") || !strings.Contains(out, "were kept: darwin/homebrew/casks.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if got := h.read("darwin/homebrew/casks.nix"); got != casksWithGhostty {
		t.Errorf("casks.nix was restored: %q", got)
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeActivated || j.Resolved() || !strings.Contains(j.Detail, "cannot be read") {
		t.Errorf("journal = %+v", j)
	}
}

func TestRmCask(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "darwin/homebrew/casks.nix", casksWithGhostty)
	h.git("add", ".")
	h.git("commit", "-q", "-m", "darwin: add cask ghostty")
	code, out := h.run("rm", "--commit", "ghostty")
	if code != ExitOK || !strings.Contains(out, `committed "darwin: remove cask ghostty"`) || !strings.Contains(out, "Homebrew keeps it until hm brew cleanup --force") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if got := h.read("darwin/homebrew/casks.nix"); got != emptyList {
		t.Errorf("casks.nix = %q", got)
	}
	if calls := h.calls(); !strings.Contains(calls, "nh darwin switch") || strings.Contains(calls, "nh home switch") {
		t.Errorf("wrong switch:\n%s", calls)
	}
	if code, out := h.run("rm", "ghostty"); code != ExitUsage || !strings.Contains(out, "casks.nix") {
		t.Fatalf("rm of an absent cask: exit %d\n%s", code, out)
	}
}

// The preview hands brew the Brewfile the flake evaluates and shows what
// brew would remove; brew's exit status 1 for "something to remove" is not
// a failure. The removal takes the run lock.
func TestBrewCleanup(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("brew", "cleanup")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"Would uninstall formulae:", "gcc", "hm: hm brew cleanup --force removes them"} {
		if !strings.Contains(out, want) {
			t.Errorf("preview lacks %q:\n%s", want, out)
		}
	}
	calls := h.calls()
	for _, want := range []string{"nix eval --raw " + h.repo + "#darwinConfigurations.\"", ".config.homebrew.brewfile", "brew bundle cleanup --file=", "cask \"ghostty\""} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
	if strings.Contains(calls, "--force") {
		t.Errorf("the preview passed --force:\n%s", calls)
	}
	lock := filepath.Join(h.repo, ".git", "hm.lock")
	must(t, os.WriteFile(lock, []byte(strconv.Itoa(os.Getpid())+"\n"), 0o644))
	if code, out := h.run("brew", "cleanup", "--force"); code != ExitRefused || !strings.Contains(out, "another hm (pid") {
		t.Fatalf("--force with the lock held: exit %d\n%s", code, out)
	}
	must(t, os.Remove(lock))
	code, out = h.run("brew", "cleanup", "--force", "--zap")
	if code != ExitOK || !strings.Contains(out, "Uninstalled 2 formulae") {
		t.Fatalf("--force: exit %d\n%s", code, out)
	}
	if !strings.Contains(h.calls(), "--zap --force") {
		t.Errorf("--force --zap not passed on:\n%s", h.calls())
	}
	if j := h.lastJournal(); j.Command[1] != "brew" || j.Outcome != txn.OutcomeOK {
		t.Errorf("journal = %+v", j)
	}
	if code, _ := h.run("brew", "prune"); code != ExitUsage {
		t.Errorf("brew prune: exit %d", code)
	}
	t.Setenv("FAKE_BREW_FAIL", "1")
	if code, out := h.run("brew", "cleanup"); code != ExitFailed || !strings.Contains(out, "rb_sysopen") || strings.Contains(out, "nothing to remove") {
		t.Errorf("a failed preview was not reported: exit %d\n%s", code, out)
	}
}

// Homebrew applies the Brewfile's trusted flags only when a switch
// installs it, so before the first switch brew bundle cleanup refuses a
// formula from a declared tap. The preview then names the one-time brew
// trust command for every trusted tap the Brewfile declares and stops
// without running anything else.
func TestBrewCleanupNamesTrustPrerequisite(t *testing.T) {
	h := newHarness(t)
	h.write("fake", "Brewfile", "tap \"peonping/tap\", trusted: true\ntap \"stacktower-io/tap\", trusted: true\nbrew \"peon-ping\", trusted: true\n")
	t.Setenv("FAKE_BREW_UNTRUSTED", "1")
	code, out := h.run("brew", "cleanup")
	if code != ExitFailed {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		"Refusing to load formula peonping/tap/peon-ping from untrusted tap peonping/tap",
		"hm:   brew trust peonping/tap stacktower-io/tap\n",
		"trusting a tap is a one-time local Homebrew setting, not a change to darwin/homebrew/",
		"nothing was removed",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "nothing to remove") || strings.Contains(out, "--force removes them") {
		t.Errorf("the refusal was reported as a preview:\n%s", out)
	}
	calls := h.calls()
	if strings.Count(calls, "brew bundle cleanup") != 1 || strings.Contains(calls, "--force") || strings.Contains(calls, "brew trust") {
		t.Errorf("the preview ran more than the cleanup preview:\n%s", calls)
	}
}

func TestListShowsCasksAndBrews(t *testing.T) {
	h := newHarness(t)
	h.write("fake", "refs.txt", "/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0\n")
	h.write("fake", "resolved.json", `{"pinned":{"bat":[],"charasay":[],"ripgrep":["/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0"]},"nixpkgs":{"ripgrep":[]}}`)
	h.write("repo", "darwin/homebrew/casks.nix", "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"ghostty\"\n  \"zed\"\n]\n")
	h.write("repo", "darwin/homebrew/brews.nix", "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"docker\"\n  \"peonping/tap/peon-ping\"\n]\n")
	h.script("cargo", "")
	h.script("uv", "")
	h.write("home", "../store/gen-20/home-path/etc/profile.d/hm-session-vars.sh", "export PATH=\"$PATH\"\n")
	code, out := h.run("list")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		`ghostty\s+1\.2\.3\s+cask\s+darwin/homebrew/casks\.nix\n`,
		`zed\s+-\s+cask\s+darwin/homebrew/casks\.nix; not installed\n`,
		`docker\s+28\.3\.3\s+brew\s+darwin/homebrew/brews\.nix\n`,
		`peonping/tap/peon-ping\s+-\s+brew\s+darwin/homebrew/brews\.nix; not installed\n`,
	} {
		if !regexp.MustCompile(want).MatchString(out) {
			t.Errorf("list lacks %q:\n%s", want, out)
		}
	}
	if pinned, cask := strings.Index(out, " pinned "), strings.Index(out, " cask "); pinned < 0 || cask < pinned {
		t.Errorf("cask rows should follow the Nix rows:\n%s", out)
	}
	code, out = h.run("list", "--source", "brew")
	if code != ExitOK || !strings.Contains(out, "docker") || strings.Contains(out, "ghostty") || strings.Contains(out, "ripgrep") {
		t.Fatalf("--source brew: exit %d\n%s", code, out)
	}
}

func TestCompleteHomebrew(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "darwin/homebrew/casks.nix", casksWithGhostty)
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"__complete", "add", "--cask", "gh"}, "ghostty\nghostty@tip\n"},
		{[]string{"__complete", "add", "--brew", "d"}, "dive\ndocker\n"},
		{[]string{"__complete", "add", "--cask", ""}, ""},
		{[]string{"__complete", "add", "zi"}, "zizmor\n"},
		{[]string{"__complete", "rm", "gh"}, "ghostty\n"},
	} {
		code, out := h.run(tc.args...)
		if code != ExitOK || out != tc.want {
			t.Errorf("%v: exit %d, out %q, want %q", tc.args, code, out, tc.want)
		}
	}
}

func TestSwitchDarwin(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("switch", "darwin")
	if code != ExitOK || !strings.Contains(out, " to darwin generation 1") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.calls(), "nh home switch") {
		t.Errorf("switch darwin switched home:\n%s", h.calls())
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeOK || j.Detail != "darwin generation 1" {
		t.Errorf("journal = %+v", j)
	}
	code, out = h.run("switch", "all")
	if code != ExitOK || !strings.Contains(out, "to generation 21") || !strings.Contains(out, " to darwin generation 2") {
		t.Fatalf("switch all: exit %d\n%s", code, out)
	}
}
