// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

// harness is a throwaway repository plus fake mvs, nix, nix-store, nh and
// go programs that record their calls, so a whole hm run can be exercised
// without touching the machine.
type harness struct {
	t       *testing.T
	repo    string
	home    string
	state   string
	store   string
	fakeDir string
	brew    string
	log     string
	env     map[string]string
}

const lockBefore = `{
  "version": 1,
  "pins": {
    "bat": {"rev": "e554", "label": "2026-09-17-e554", "version": "0.26.1", "date": "2026-09-17", "constraint": "0.26.1"},
    "charasay": {"rev": "64c0", "label": "2026-08-01-64c0", "version": "3.3.0", "date": "2026-08-01", "constraint": null},
    "jellyfin": {"rev": "2413", "label": "2026-07-19-2413", "version": "10.11.11", "date": "2026-07-19", "constraint": null},
    "ripgrep": {"rev": "d407", "label": "2026-07-05-d407", "version": "15.1.0", "date": "2026-07-05", "constraint": "15.1.0"}
  }
}
`

const packagesBefore = "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"bat\"\n  \"charasay\"\n  \"ripgrep\"\n]\n"

const emptyList = "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n]\n"

func newHarness(t *testing.T) *harness {
	t.Helper()
	root := t.TempDir()
	h := &harness{
		t:       t,
		repo:    filepath.Join(root, "repo"),
		home:    filepath.Join(root, "home"),
		state:   filepath.Join(root, "state"),
		store:   filepath.Join(root, "store"),
		fakeDir: filepath.Join(root, "fake"),
		brew:    filepath.Join(root, "brew"),
		log:     filepath.Join(root, "calls.log"),
	}
	for _, d := range []string{h.repo + "/home-manager", h.repo + "/darwin/homebrew", h.repo + "/hosts/ser8", h.home, h.state + "/home-manager/gcroots", h.state + "/nix/profiles", h.state + "/nixvar/profiles", h.store + "/gen-20/home-path/bin", h.fakeDir, h.home + "/go/bin", h.brew + "/Caskroom/ghostty/1.2.3", h.brew + "/Cellar/docker/28.3.3"} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	h.write("repo", "flake.nix", "{ }\n")
	h.write("repo", "flake.lock", "{\"version\": 7}\n")
	h.write("repo", "multiverse.lock", lockBefore)
	h.write("repo", "home-manager/packages.nix", packagesBefore)
	h.write("repo", "darwin/homebrew/casks.nix", emptyList)
	h.write("repo", "darwin/homebrew/brews.nix", emptyList)
	h.write("repo", "hosts/ser8/default.nix", "{ pinned, ... }: { services.jellyfin.package = pinned.jellyfin; }\n")
	h.write("repo", "dev.nix", "with pinned; [ bat ]\n")
	h.git("init", "-q")
	h.git("config", "user.email", "t@example.com")
	h.git("config", "user.name", "t")
	h.git("config", "commit.gpgsign", "false")
	h.git("add", ".")
	h.git("commit", "-q", "-m", "init")
	must(t, os.Symlink(filepath.Join(h.store, "gen-20"), filepath.Join(h.state, "home-manager/gcroots/current-home")))
	must(t, os.Symlink(filepath.Join(h.store, "gen-20"), filepath.Join(h.state, "nix/profiles/home-manager-20-link")))
	must(t, os.Symlink("home-manager-20-link", filepath.Join(h.state, "nix/profiles/home-manager")))
	h.write("fake", "gen-counter", "20\n")
	h.write("fake", "system-counter", "0\n")
	h.write("fake", "Brewfile", "tap \"peonping/tap\"\nbrew \"docker\"\ncask \"ghostty\"\n")
	h.write("fake", "lock-after-add.json", strings.Replace(lockBefore, `    "ripgrep":`, `    "zizmor": {"rev": "e554", "label": "2026-09-17-e554", "version": "1.30.1", "date": "2026-09-17", "constraint": null},
    "ripgrep":`, 1))
	h.write("fake", "lock-after-rm.json", strings.Replace(lockBefore, `    "charasay": {"rev": "64c0", "label": "2026-08-01-64c0", "version": "3.3.0", "date": "2026-08-01", "constraint": null},
`, "", 1))
	h.write("fake", "lock-after-update.json", strings.Replace(lockBefore, `"version": "15.1.0"`, `"version": "15.2.0"`, 1))
	h.write("fake", "lock-after-update-jellyfin.json", strings.Replace(strings.Replace(lockBefore, `"version": "15.1.0"`, `"version": "15.2.0"`, 1), `"version": "10.11.11"`, `"version": "10.11.12"`, 1))
	h.write("fake", "version-zizmor.json", `{"version":"1.30.1","pname":"zizmor","system":"aarch64-darwin"}`)
	h.write("fake", "version-ripgrep.json", `{"version":"15.1.0","pname":"ripgrep","system":"aarch64-darwin"}`)
	h.fakes()
	h.env = map[string]string{
		"HOME":            h.home,
		"XDG_STATE_HOME":  h.state,
		"NH_FLAKE":        h.repo,
		"USER":            "tester",
		"PATH":            h.fakeDir + string(os.PathListSeparator) + os.Getenv("PATH"),
		"HOMEBREW_PREFIX": h.brew,
		"NIX_STATE_DIR":   h.state + "/nixvar",
	}
	t.Setenv("PATH", h.env["PATH"])
	t.Setenv("FAKE_LOG", h.log)
	t.Setenv("FAKE_DIR", h.fakeDir)
	t.Setenv("FAKE_REPO", h.repo)
	t.Setenv("FAKE_STORE", h.store)
	t.Setenv("FAKE_STATE", h.state)
	t.Setenv("FAKE_BREW", h.brew)
	t.Setenv("FAKE_HOME", h.home)
	t.Setenv("FAKE_NH_FAIL", "")
	t.Setenv("FAKE_NH_FAIL_AFTER", "")
	t.Setenv("FAKE_NH_EDIT", "")
	t.Setenv("FAKE_BREW_FAIL", "")
	t.Setenv("FAKE_BREW_UNTRUSTED", "")
	return h
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func (h *harness) write(where, rel, content string) {
	h.t.Helper()
	base := map[string]string{"repo": h.repo, "fake": h.fakeDir, "home": h.home}[where]
	path := filepath.Join(base, rel)
	must(h.t, os.MkdirAll(filepath.Dir(path), 0o755))
	must(h.t, os.WriteFile(path, []byte(content), 0o644))
}

func (h *harness) read(rel string) string {
	h.t.Helper()
	data, err := os.ReadFile(filepath.Join(h.repo, rel))
	if err != nil {
		return "<" + err.Error() + ">"
	}
	return string(data)
}

func (h *harness) git(args ...string) string {
	h.t.Helper()
	cmd := exec.Command("git", append([]string{"-C", h.repo}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		h.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return string(out)
}

func (h *harness) script(name, body string) {
	h.t.Helper()
	path := filepath.Join(h.fakeDir, name)
	must(h.t, os.WriteFile(path, []byte("#!/bin/sh\necho \""+name+" $*\" >> \"$FAKE_LOG\"\n"+body), 0o755))
}

func (h *harness) fakes() {
	h.script("mvs", `lock=$3; shift 3
case "$1 $2" in
  "lock add")
    case "$3" in nope*) echo "mvs: nope is not in the index, so nothing can satisfy it." >&2; exit 1 ;; esac
    cp "$FAKE_DIR/lock-after-add.json" "$lock"
    echo '{"attr":"zizmor","pin":{"version":"1.30.1","label":"2026-09-17-e554","rev":"e554","date":"2026-09-17"}}' ;;
  "lock rm") cp "$FAKE_DIR/lock-after-rm.json" "$lock"; echo '{"attr":"charasay","removed":{"version":"3.3.0","label":"l"}}' ;;
  "lock update")
    if [ "$3" = jellyfin ]; then
      cp "$FAKE_DIR/lock-after-update-jellyfin.json" "$lock"
      echo '{"moved":[{"attr":"jellyfin","from":{"version":"10.11.11","label":"a"},"to":{"version":"10.11.12","label":"b"}}]}'
    else
      cp "$FAKE_DIR/lock-after-update.json" "$lock"
      echo '{"moved":[{"attr":"'"$3"'","from":{"version":"15.1.0","label":"a"},"to":{"version":"15.2.0","label":"b"}}]}'
    fi ;;
  "lock status") echo '{"pins":[]}' ;;
  "lock minimize") echo '{"before":1,"after":1,"pins":4,"moved":[],"why":""}' ;;
  "query search") echo '{"matches":[{"attr":"zizmor","version":"1.30.1","gone":false}]}' ;;
  *) echo "fake mvs: unknown $*" >&2; exit 1 ;;
esac
`)
	// An expression that binds attr asks what the flake resolves that pin
	// to on this system; the answer is version-ATTR.json, or null when no
	// such file exists. Any other expression is the list resolution.
	h.script("nix", `case "$1 $2" in
  "eval --raw") cat "$FAKE_DIR/Brewfile" ;;
  "eval --json")
    if [ "$3" = "--file" ]; then
      if grep -q BROKEN "$4"; then echo "error: undefined variable 'BROKEN'" >&2; exit 1; fi
      echo '["ok"]'
    else
      attr=$(printf '%s\n' "$5" | sed -n 's/^  attr = "\(.*\)";$/\1/p')
      if [ -z "$attr" ]; then cat "$FAKE_DIR/resolved.json"
      elif [ -f "$FAKE_DIR/version-$attr.json" ]; then cat "$FAKE_DIR/version-$attr.json"
      else echo null; fi
    fi ;;
  "build --no-link") echo "$FAKE_STORE/built-generation" ;;
  "flake update") printf '{"version": 7, "updated": true}\n' > "$FAKE_REPO/flake.lock" ;;
  "run "*) shift 2; [ "$1" = "--" ] && shift; exec "$FAKE_DIR/mvs" "$@" ;;
  *) echo "fake nix: unknown $*" >&2; exit 1 ;;
esac
`)
	h.script("nix-store", `cat "$FAKE_DIR/refs.txt"
`)
	// FAKE_NH_EDIT names a file the fake edits before anything else, as
	// another program or an editor might while the switch runs.
	// FAKE_NH_FAIL fails before a generation exists; FAKE_NH_FAIL_AFTER
	// activates the new generation and then fails.
	h.script("nh", `if [ -n "$FAKE_NH_EDIT" ]; then echo '# edited elsewhere' >> "$FAKE_NH_EDIT"; fi
if [ -n "$FAKE_NH_FAIL" ]; then echo "error: builder failed" >&2; exit 1; fi
case "$1 $2" in
  "home switch")
    n=$(cat "$FAKE_DIR/gen-counter"); n=$((n + 1)); echo "$n" > "$FAKE_DIR/gen-counter"
    mkdir -p "$FAKE_STORE/gen-$n/home-path/bin"
    ln -sfn "$FAKE_STORE/gen-$n" "$FAKE_STATE/home-manager/gcroots/current-home"
    ln -sfn "$FAKE_STORE/gen-$n" "$FAKE_STATE/nix/profiles/home-manager-$n-link"
    ln -sfn "home-manager-$n-link" "$FAKE_STATE/nix/profiles/home-manager" ;;
  "darwin switch")
    n=$(cat "$FAKE_DIR/system-counter"); n=$((n + 1)); echo "$n" > "$FAKE_DIR/system-counter"
    mkdir -p "$FAKE_STORE/system-$n"
    ln -sfn "$FAKE_STORE/system-$n" "$FAKE_STATE/nixvar/profiles/system-$n-link"
    ln -sfn "system-$n-link" "$FAKE_STATE/nixvar/profiles/system" ;;
esac
if [ -n "$FAKE_NH_FAIL_AFTER" ]; then echo "error: activation failed after linking" >&2; exit 1; fi
`)
	h.script("go", `case "$1" in
  env) printf '%s\n%s\n' "$FAKE_HOME/go/bin" "$FAKE_HOME/go" ;;
esac
`)
	h.script("nvd", "")
	// bundle cleanup copies the Brewfile it was given into the log, so a
	// test can check what hm handed to brew; the preview exits 1 the way
	// brew does when something would be removed. FAKE_BREW_UNTRUSTED makes
	// it refuse a formula from a tap Homebrew has not been told to trust,
	// with brew's own wording.
	h.script("brew", `if [ -n "$FAKE_BREW_FAIL" ]; then echo "Error: Operation not permitted @ rb_sysopen" >&2; exit 1; fi
case "$1 $2" in
  "bundle cleanup")
    for arg in "$@"; do case "$arg" in --file=*) cat "${arg#--file=}" >> "$FAKE_LOG" ;; esac; done
    if [ -n "$FAKE_BREW_UNTRUSTED" ]; then
      printf 'Error: Refusing to load formula peonping/tap/peon-ping from untrusted tap peonping/tap.\nRun \x60brew trust --formula peonping/tap/peon-ping\x60 or \x60brew trust peonping/tap\x60 to trust it.\n' >&2
      exit 1
    fi
    case " $* " in
      *" --force "*) echo "Uninstalled 2 formulae" ;;
      *) printf 'Would uninstall formulae:\ngcc\nnode@18\nRun \x60brew bundle cleanup --force\x60 to make these changes.\n'; exit 1 ;;
    esac ;;
  "casks "*) printf 'ghostty\nghostty@tip\nzed\n' ;;
  "formulae "*) printf 'dive\ndocker\n' ;;
esac
`)
}

// run invokes hm with the harness environment and returns the exit code
// and combined output.
func (h *harness) run(args ...string) (int, string) {
	h.t.Helper()
	var out bytes.Buffer
	code := Main(Env{
		Args:     args,
		Stdout:   &out,
		Stderr:   &out,
		Version:  "test",
		Getenv:   func(k string) string { return h.env[k] },
		Terminal: func() bool { return false },
	})
	return code, out.String()
}

func (h *harness) calls() string {
	data, _ := os.ReadFile(h.log)
	return string(data)
}

func (h *harness) lastJournal() *txn.Journal {
	h.t.Helper()
	j, _, err := txn.Last(filepath.Join(h.repo, ".git"))
	if err != nil || j == nil {
		h.t.Fatalf("no journal: %v", err)
	}
	return j
}

func TestAddPinsAndSwitches(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "zizmor")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"hm: pinned zizmor 1.30.1", "+ nh home switch " + h.repo, "hm: switched tester@", "to generation 21", "hm: added zizmor 1.30.1 (generation 21)", "hm: uncommitted: home-manager/packages.nix multiverse.lock", "commit -m 'home: add zizmor 1.30.1' -- home-manager/packages.nix multiverse.lock"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if got := h.read("home-manager/packages.nix"); got != "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"bat\"\n  \"charasay\"\n  \"ripgrep\"\n  \"zizmor\"\n]\n" {
		t.Errorf("packages.nix = %q", got)
	}
	if !strings.Contains(h.read("multiverse.lock"), `"zizmor"`) {
		t.Error("lock was not rewritten by mvs")
	}
	calls := h.calls()
	for _, want := range []string{"mvs --json --file " + h.repo + "/multiverse.lock lock add zizmor", "nix eval --json --file " + h.repo + "/home-manager/packages.nix", "nh home switch " + h.repo} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
	if status := h.git("status", "--porcelain"); !strings.Contains(status, " M home-manager/packages.nix") || !strings.Contains(status, " M multiverse.lock") {
		t.Errorf("git status = %q", status)
	}
	j := h.lastJournal()
	if j.Outcome != txn.OutcomeOK || j.LastStep() != "report" || !j.Resolved() {
		t.Errorf("journal = %+v", j)
	}
	if _, err := os.Stat(filepath.Join(h.repo, ".git", "hm.lock")); err == nil {
		t.Error("lock file left behind")
	}
}

func TestAddCommit(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--commit", "zizmor")
	if code != ExitOK || !strings.Contains(out, `hm: committed "home: add zizmor 1.30.1"`) {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("tree dirty after commit: %q", status)
	}
	if subj := strings.TrimSpace(h.git("log", "-1", "--format=%s")); subj != "home: add zizmor 1.30.1" {
		t.Errorf("subject = %q", subj)
	}
	if files := h.git("show", "--name-only", "--format=", "HEAD"); !strings.Contains(files, "multiverse.lock") || !strings.Contains(files, "home-manager/packages.nix") {
		t.Errorf("committed files = %q", files)
	}
}

func TestAddReusesExistingPin(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "ripgrep@15.1.0")
	if code != ExitOK || !strings.Contains(out, "reusing the pin for ripgrep 15.1.0") || !strings.Contains(out, "ripgrep is already in home-manager/packages.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.calls(), "lock add") {
		t.Error("mvs lock add ran for an existing pin")
	}
	if !strings.Contains(out, "hm: nothing to commit") {
		t.Errorf("expected nothing to commit:\n%s", out)
	}
}

func TestAddRefusesVersionOnSharedPin(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "ripgrep@16.0.0")
	if code != ExitRefused || !strings.Contains(out, "pinned at 15.1.0") || !strings.Contains(out, "hm up ripgrep") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if h.calls() != "" {
		t.Errorf("commands ran: %s", h.calls())
	}
}

func TestAddRestoresOnSwitchFailure(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL", "1")
	code, out := h.run("add", "zizmor")
	if code != ExitFailed {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"hm: switch failed", "hm: restored home-manager/packages.nix, multiverse.lock"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if h.read("home-manager/packages.nix") != packagesBefore || h.read("multiverse.lock") != lockBefore {
		t.Error("files were not restored")
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("tree dirty after restore: %q", status)
	}
	j := h.lastJournal()
	if j.Outcome != txn.OutcomeFailed || !strings.Contains(j.Detail, "restored") {
		t.Errorf("journal = %+v", j)
	}
	// The failed run is resolved, so the next one starts.
	t.Setenv("FAKE_NH_FAIL", "")
	if code, out := h.run("add", "zizmor"); code != ExitOK {
		t.Fatalf("rerun exit %d\n%s", code, out)
	}
}

// A file that something else changed while the switch ran no longer holds
// what hm wrote, so the failed run must leave it as found rather than
// overwrite the foreign edit, and must stay unresolved until acknowledged.
func TestAddLeavesForeignEditOnFailure(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL", "1")
	t.Setenv("FAKE_NH_EDIT", filepath.Join(h.repo, "home-manager/packages.nix"))
	code, out := h.run("add", "zizmor")
	if code != ExitFailed {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"hm: switch failed", "hm: restored multiverse.lock", "hm: left home-manager/packages.nix as found"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if got := h.read("home-manager/packages.nix"); !strings.Contains(got, "# edited elsewhere") || !strings.Contains(got, "zizmor") {
		t.Errorf("foreign edit did not survive: %q", got)
	}
	if h.read("multiverse.lock") != lockBefore {
		t.Error("the lock was not restored")
	}
	j := h.lastJournal()
	if j.Outcome != txn.OutcomeUnrestored || j.Resolved() || !strings.Contains(j.Detail, "home-manager/packages.nix") {
		t.Errorf("journal = %+v", j)
	}
	h.git("checkout", "--", ".")
	t.Setenv("FAKE_NH_FAIL", "")
	t.Setenv("FAKE_NH_EDIT", "")
	if code, out := h.run("add", "zizmor"); code != ExitRefused || !strings.Contains(out, "a previous run") {
		t.Fatalf("unresolved run not refused: exit %d\n%s", code, out)
	}
}

// nh can activate the new generation and still exit non-zero, for
// instance when a later activation step fails. The generation is then the
// truth and the edited files are its source, so they must not be restored.
func TestAddKeepsFilesWhenFailedSwitchActivated(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL_AFTER", "1")
	code, out := h.run("add", "zizmor")
	if code != ExitFailed {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"hm: switch failed", "generation 21", "were kept: home-manager/packages.nix, multiverse.lock"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "restored") {
		t.Errorf("files were restored after activation:\n%s", out)
	}
	if !strings.Contains(h.read("home-manager/packages.nix"), "zizmor") || !strings.Contains(h.read("multiverse.lock"), `"zizmor"`) {
		t.Error("the edits were not kept")
	}
	j := h.lastJournal()
	if j.Outcome != txn.OutcomeActivated || j.Resolved() || !strings.Contains(j.Detail, "generation 21") {
		t.Errorf("journal = %+v", j)
	}
	h.git("checkout", "--", ".")
	t.Setenv("FAKE_NH_FAIL_AFTER", "")
	if code, out := h.run("add", "zizmor"); code != ExitRefused || !strings.Contains(out, "a previous run") || !strings.Contains(out, "activated") {
		t.Fatalf("unresolved run not refused: exit %d\n%s", code, out)
	}
}

// When the generation links cannot be read after a failed switch, hm
// cannot tell whether activation happened and must keep the files.
func TestAddKeepsFilesWhenGenerationUnreadable(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL", "1")
	// A dangling profile link is neither absent nor readable.
	must(t, os.Remove(filepath.Join(h.state, "nix/profiles/home-manager")))
	must(t, os.Symlink("home-manager-99-link", filepath.Join(h.state, "nix/profiles/home-manager")))
	code, out := h.run("add", "zizmor")
	if code != ExitFailed || strings.Contains(out, "restored") || !strings.Contains(out, "cannot be read") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if !strings.Contains(h.read("home-manager/packages.nix"), "zizmor") {
		t.Error("the edit was not kept")
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeActivated || j.Resolved() {
		t.Errorf("journal = %+v", j)
	}
}

func TestAddKeepOnFailure(t *testing.T) {
	h := newHarness(t)
	t.Setenv("FAKE_NH_FAIL", "1")
	code, out := h.run("add", "--keep-on-failure", "zizmor")
	if code != ExitFailed || !strings.Contains(out, "the edited files were kept") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if !strings.Contains(h.read("home-manager/packages.nix"), "zizmor") {
		t.Error("edit was not kept")
	}
	t.Setenv("FAKE_NH_FAIL", "")
	code, out = h.run("add", "zizmor")
	if code != ExitRefused || !strings.Contains(out, "uncommitted changes") {
		t.Fatalf("dirty tree not refused: exit %d\n%s", code, out)
	}
	h.git("checkout", "--", ".")
	code, out = h.run("add", "zizmor")
	if code != ExitRefused || !strings.Contains(out, "a previous run") || !strings.Contains(out, "remove") {
		t.Fatalf("unresolved run not refused: exit %d\n%s", code, out)
	}
}

func TestAddUnknownAttribute(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "nope")
	if code != ExitFailed || !strings.Contains(out, "mvs lock add failed") || !strings.Contains(out, "not in the index") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("tree dirty: %q", status)
	}
}

func TestAddRefusesDirtyOwnedFile(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "home-manager/packages.nix", packagesBefore+"# edited\n")
	code, out := h.run("add", "zizmor")
	if code != ExitRefused || !strings.Contains(out, "uncommitted changes in home-manager/packages.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if h.calls() != "" {
		t.Errorf("commands ran: %s", h.calls())
	}
}

func TestAddDryRun(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("--dry-run", "add", "--commit", "zizmor")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"+ mvs lock add zizmor", "+++ b/multiverse.lock", `+    "zizmor"`, "+++ b/home-manager/packages.nix", `+  "zizmor"`, "+ nh home switch", "would pin zizmor 1.30.1", "+ git -C " + h.repo + " commit -m 'home: add zizmor 1.30.1'"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("dry run changed files: %q", status)
	}
	if strings.Contains(h.calls(), "nh home switch") {
		t.Error("dry run switched")
	}
	// The version is resolved from the temporary lock the dry run pinned
	// into, since the real lock does not hold the pin.
	if !strings.Contains(h.calls(), `lock = "`+os.TempDir()) || !strings.Contains(h.calls(), "hm-multiverse.lock-") {
		t.Errorf("version not resolved from the temporary lock:\n%s", h.calls())
	}
	if _, _, err := txn.Last(filepath.Join(h.repo, ".git")); err != nil {
		t.Fatal(err)
	}
}

// The success line and the commit carry the version this system installs,
// which the flake resolves from the lock and which can differ from the
// index version the lock records; both are then named.
func TestAddReportsResolvedVersion(t *testing.T) {
	h := newHarness(t)
	h.write("fake", "version-jellyfin.json", `{"version":"10.11.10","pname":"jellyfin-server","system":"aarch64-darwin"}`)
	code, out := h.run("add", "--build-only", "--commit", "jellyfin")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		"hm: reusing the pin for jellyfin 10.11.11",
		"hm: jellyfin: index 10.11.11, aarch64-darwin resolves jellyfin-server 10.11.10",
		"hm: added jellyfin 10.11.10 (built ",
		`hm: committed "home: add jellyfin 10.11.10"`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "added jellyfin 10.11.11") {
		t.Errorf("the index version was reported as installed:\n%s", out)
	}
	if body := strings.TrimSpace(h.git("log", "-1", "--format=%b")); body != "index 10.11.11, aarch64-darwin resolves jellyfin-server 10.11.10" {
		t.Errorf("commit body = %q", body)
	}
	// When the versions agree the commit has no body.
	code, out = h.run("add", "--build-only", "--commit", "zizmor")
	if code != ExitOK || !strings.Contains(out, "hm: added zizmor 1.30.1 (built ") || strings.Contains(out, "resolves") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if body := strings.TrimSpace(h.git("log", "-1", "--format=%b")); body != "" {
		t.Errorf("commit body = %q, want none", body)
	}
	// A version the flake cannot tell falls back to the index version and
	// says so, since the generation was already built from that lock.
	h.write("repo", "home-manager/packages.nix", packagesBefore)
	h.git("commit", "-q", "-m", "reset", "--", "home-manager/packages.nix")
	must(t, os.Remove(filepath.Join(h.fakeDir, "version-zizmor.json")))
	code, out = h.run("add", "--build-only", "zizmor")
	if code != ExitOK || !strings.Contains(out, "could not be read") || !strings.Contains(out, "hm: added zizmor 1.30.1 (built ") || !strings.Contains(out, "'home: add zizmor 1.30.1'") {
		t.Fatalf("exit %d\n%s", code, out)
	}
}

func TestAddBuildOnly(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--build-only", "--commit", "zizmor")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"+ nix build --no-link --print-out-paths '" + h.repo + "#homeConfigurations.\"tester@", "hm: built " + h.store + "/built-generation", "hm: not activated; run: hm switch", `hm: committed "home: add zizmor 1.30.1"`} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(h.calls(), "nh home switch") {
		t.Error("build-only switched")
	}
	realStore, _ := filepath.EvalSymlinks(h.store)
	if !strings.Contains(h.calls(), "nvd diff "+realStore+"/gen-20 "+h.store+"/built-generation") {
		t.Errorf("no nvd diff against the current generation:\n%s", h.calls())
	}
}

func TestRm(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("rm", "--commit", "bat")
	if code != ExitOK || !strings.Contains(out, `committed "home: remove bat"`) {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.read("home-manager/packages.nix"), "bat") {
		t.Error("bat still listed")
	}
	if strings.Contains(h.calls(), "lock rm") {
		t.Error("pin removed without --prune")
	}
	code, out = h.run("rm", "not-there")
	if code != ExitUsage {
		t.Fatalf("exit %d\n%s", code, out)
	}
}

func TestRmPrune(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("rm", "--prune", "bat")
	if code != ExitRefused || !strings.Contains(out, "dev.nix:1") {
		t.Fatalf("prune with a consumer: exit %d\n%s", code, out)
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("refusal changed files: %q", status)
	}
	code, out = h.run("rm", "--prune", "charasay")
	if code != ExitOK || !strings.Contains(out, "unpinned charasay (was 3.3.0)") || !strings.Contains(out, "uncommitted: home-manager/packages.nix multiverse.lock") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.read("multiverse.lock"), "charasay") {
		t.Error("pin still in the lock")
	}
}

func TestAddGoToolBuildOnly(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--go", "github.com/fatih/gomodifytags@latest")
	if code != ExitUsage || !strings.Contains(out, "explicit version") {
		t.Fatalf("latest accepted: exit %d\n%s", code, out)
	}
	code, out = h.run("add", "--go", "--build-only", "github.com/fatih/gomodifytags@v1.17.0")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"hm: not installed; run: hm sync go", "commit -m 'home: add go gomodifytags v1.17.0' -m github.com/fatih/gomodifytags@v1.17.0 -- home-manager/go-tools.nix"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if got := h.read("home-manager/go-tools.nix"); got != "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"github.com/fatih/gomodifytags@v1.17.0\"\n]\n" {
		t.Errorf("go-tools.nix = %q", got)
	}
	if status := h.git("status", "--porcelain"); !strings.Contains(status, "A  home-manager/go-tools.nix") {
		t.Errorf("new list not staged: %q", status)
	}
	h.git("commit", "-q", "-m", "home: add go gomodifytags", "--", "home-manager/go-tools.nix")
	code, out = h.run("add", "--go", "--build-only", "github.com/fatih/gomodifytags@v1.18.0")
	if code != ExitOK || !strings.Contains(out, "replacing github.com/fatih/gomodifytags@v1.17.0 with github.com/fatih/gomodifytags@v1.18.0") || !strings.Contains(out, "'home: update go gomodifytags v1.17.0 to v1.18.0' -m 'github.com/fatih/gomodifytags@v1.18.0\nreplaces github.com/fatih/gomodifytags@v1.17.0' --") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	code, out = h.run("sync", "go", "--build-only")
	if code != ExitOK || !strings.Contains(out, "would install github.com/fatih/gomodifytags@v1.18.0") || !strings.Contains(out, "go: 0 current, 1 installed") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	h.git("checkout", "--", ".")
	code, out = h.run("rm", "--build-only", "github.com/fatih/gomodifytags")
	if code != ExitOK || !strings.Contains(out, "hm: removed go github.com/fatih/gomodifytags") || !strings.Contains(out, "commit -m 'home: remove go gomodifytags' -m github.com/fatih/gomodifytags@v1.17.0 --") {
		t.Fatalf("exit %d\n%s", code, out)
	}
}

// A dry run prints the diff of the proposed list, so the install commands
// it previews must come from that same list, not from the file on disk.
func TestAddToolDryRunPreviewsInstall(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("--dry-run", "add", "--go", "example.com/tool@v1.2.3")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{`+  "example.com/tool@v1.2.3"`, "+ go install example.com/tool@v1.2.3", "go: 0 current, 1 installed"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(h.calls(), "go install") {
		t.Errorf("dry run installed:\n%s", h.calls())
	}
	if status := h.git("status", "--porcelain"); status != "" {
		t.Errorf("dry run changed files: %q", status)
	}
	// Updating an entry previews the new version, not the declared one.
	h.write("repo", "home-manager/go-tools.nix", "[\n  \"github.com/fatih/gomodifytags@v1.17.0\"\n]\n")
	h.git("add", ".")
	h.git("commit", "-q", "-m", "home: add go gomodifytags")
	code, out = h.run("--dry-run", "add", "--go", "github.com/fatih/gomodifytags@v1.18.0")
	if code != ExitOK || !strings.Contains(out, "+ go install github.com/fatih/gomodifytags@v1.18.0") || strings.Contains(out, "install github.com/fatih/gomodifytags@v1.17.0") {
		t.Fatalf("update preview: exit %d\n%s", code, out)
	}
	h.script("uv", `case "$1 $2" in "tool list") echo "par-cc-usage v0.9.1"; echo "- par-cc-usage" ;; esac`)
	code, out = h.run("--dry-run", "add", "--uv", "claude-monitor==3.1.0")
	if code != ExitOK || !strings.Contains(out, "+ uv tool install --reinstall claude-monitor==3.1.0") {
		t.Fatalf("uv preview: exit %d\n%s", code, out)
	}
}

func TestUp(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("up", "jellyfin")
	if code != ExitRefused || !strings.Contains(out, "hm up --repo jellyfin") {
		t.Fatalf("host pin: exit %d\n%s", code, out)
	}
	code, out = h.run("up", "nope")
	if code != ExitUsage {
		t.Fatalf("unknown attr: exit %d\n%s", code, out)
	}
	code, out = h.run("up", "--commit", "ripgrep")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"+ nix flake update mvs", "hm: ripgrep: 15.1.0 to 15.2.0 (b)", `committed "home: update ripgrep 15.1.0 to 15.2.0"`} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
	calls := h.calls()
	if !strings.Contains(calls, "nix run "+h.repo+"#mvs -- --json --file "+h.repo+"/multiverse.lock lock update ripgrep") {
		t.Errorf("mvs was not run through the flake:\n%s", calls)
	}
	if files := h.git("show", "--name-only", "--format=", "HEAD"); !strings.Contains(files, "flake.lock") || !strings.Contains(files, "multiverse.lock") {
		t.Errorf("committed files = %q", files)
	}
	code, out = h.run("up", "--repo", "jellyfin")
	if code != ExitOK || !strings.Contains(out, "jellyfin is consumed by hosts/ser8/default.nix:1") || !strings.Contains(out, "'multiverse: update jellyfin 10.11.11 to 10.11.12'") {
		t.Fatalf("repo pin: exit %d\n%s", code, out)
	}
}

func TestListAndDoctor(t *testing.T) {
	h := newHarness(t)
	h.write("fake", "refs.txt", strings.Join([]string{
		"/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0",
		"/nix/store/9nnfhsm7d0rmv74viba3q8w8bvgaix8n-bat-0.26.1",
		"/nix/store/9jvj0khvdmj7hnyqkk4454d715jvkf7x-man-db-2.13.1",
		"/nix/store/78dxx2mr5drizabafzha5hjwizzl9dkh-home-manager",
	}, "\n")+"\n")
	h.write("fake", "resolved.json", `{"pinned":{"bat":["/nix/store/9nnfhsm7d0rmv74viba3q8w8bvgaix8n-bat-0.26.1"],"charasay":[],"ripgrep":["/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0"]},"nixpkgs":{"man-db":["/nix/store/9jvj0khvdmj7hnyqkk4454d715jvkf7x-man-db-2.13.1"],"home-manager":[],"bat":[],"ripgrep":[]}}`)
	must(t, os.MkdirAll(filepath.Join(h.store, "gen-20/home-path/etc/profile.d"), 0o755))
	native := filepath.Join(h.home, ".local/bin")
	must(t, os.MkdirAll(filepath.Join(h.home, ".local/share/claude/versions/2.1.274"), 0o755))
	must(t, os.MkdirAll(native, 0o755))
	must(t, os.WriteFile(filepath.Join(h.home, ".local/share/claude/versions/2.1.274/claude"), []byte("#!/bin/sh\n"), 0o755))
	must(t, os.Symlink(filepath.Join(h.home, ".local/share/claude/versions/2.1.274/claude"), filepath.Join(native, "claude")))
	must(t, os.WriteFile(filepath.Join(h.store, "gen-20/home-path/etc/profile.d/hm-session-vars.sh"), []byte(`export PATH="`+native+":"+h.home+`/go/bin${PATH:+:}$PATH"`+"\n"), 0o644))
	self, err := os.Executable()
	must(t, err)
	data, err := os.ReadFile(self)
	must(t, err)
	must(t, os.WriteFile(filepath.Join(h.home, "go/bin/cli.test"), data, 0o755))
	h.script("cargo", `echo "wt v0.3.1:"; echo "    wt"`)
	h.script("uv", `echo "claude-monitor v3.1.0"; echo "- ccm"`)
	h.write("repo", "home-manager/cargo-tools.nix", "[\n  \"wt@0.3.1\"\n]\n")

	code, out := h.run("list")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{
		"ripgrep         15.1.0   pinned   ripgrep 15.1.0",
		"bat             0.26.1   pinned   bat 0.26.1",
		"man-db          2.13.1   nixpkgs  man-db",
		"home-manager             custom   built by this flake",
		"go       github.com/catgrep/nixos-config/tools/hm; undeclared",
		"wt              0.3.1    cargo    wt",
		"claude-monitor  3.1.0    uv       ccm; undeclared",
		"claude          2.1.274  native   ~/.local/share/claude/versions/2.1.274/claude",
		"pinned but not in this generation (2):\n  charasay jellyfin",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("list lacks %q:\n%s", want, out)
		}
	}
	code, out = h.run("list", "--source", "cargo")
	if code != ExitOK || strings.Contains(out, "ripgrep") || !strings.Contains(out, "wt") {
		t.Fatalf("--source cargo: exit %d\n%s", code, out)
	}
	code, out = h.run("doctor")
	if code != ExitOK {
		t.Fatalf("doctor exit %d\n%s", code, out)
	}
	for _, want := range []string{"undeclared tools", "\n  cli.test ", "\n  claude-monitor ", " findings\n"} {
		if !strings.Contains(out, want) {
			t.Errorf("doctor lacks %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "  wt ") {
		t.Errorf("declared cargo tool reported:\n%s", out)
	}
}

// Provenance is decided by the exact store path the lock resolves to, not
// by name and version: another build of ripgrep 15.1.0 is not the pinned
// one, and every output of one pinned derivation is one row.
func TestListProvenanceByStorePath(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "multiverse.lock", strings.Replace(lockBefore, `    "ripgrep":`, `    "shellcheck": {"rev": "d407", "label": "2026-07-05-d407", "version": "0.11.0", "date": "2026-07-05", "constraint": null},
    "ripgrep":`, 1))
	h.write("repo", "home-manager/packages.nix", "# SPDX-License-Identifier: GPL-3.0-or-later\n[\n  \"bat\"\n  \"charasay\"\n  \"ripgrep\"\n  \"shellcheck\"\n]\n")
	h.git("add", ".")
	h.git("commit", "-q", "-m", "home: add shellcheck")
	const pinnedRipgrep = "/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0"
	const otherRipgrep = "/nix/store/0000000000000000000000000000000a-ripgrep-15.1.0"
	const shellcheckBin = "/nix/store/1111111111111111111111111111111b-shellcheck-0.11.0-bin"
	const shellcheckMan = "/nix/store/148icihpgb90anqhbh019i7wq3czsmmd-shellcheck-0.11.0-man"
	h.write("fake", "refs.txt", strings.Join([]string{otherRipgrep, pinnedRipgrep, shellcheckMan, shellcheckBin}, "\n")+"\n")
	h.write("fake", "resolved.json", `{"pinned":{"bat":[],"charasay":[],"ripgrep":["`+pinnedRipgrep+`"],"shellcheck":["`+shellcheckBin+`","`+shellcheckMan+`"]},"nixpkgs":{"ripgrep":[],"shellcheck":[]}}`)
	must(t, os.MkdirAll(filepath.Join(h.store, "gen-20/home-path/etc/profile.d"), 0o755))
	must(t, os.WriteFile(filepath.Join(h.store, "gen-20/home-path/etc/profile.d/hm-session-vars.sh"), []byte("export PATH=\"${PATH:+:}$PATH\"\n"), 0o644))
	h.script("cargo", "")
	h.script("uv", "")

	code, out := h.run("list")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	rows := map[string]int{}
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && (fields[0] == "ripgrep" || fields[0] == "shellcheck") {
			rows[fields[0]+" "+fields[2]]++
		}
	}
	want := map[string]int{"ripgrep pinned": 1, "ripgrep custom": 1, "shellcheck pinned": 1}
	if !reflect.DeepEqual(rows, want) {
		t.Errorf("rows = %v, want %v:\n%s", rows, want, out)
	}
	if !strings.Contains(out, "pinned but not in this generation (3):\n  bat charasay jellyfin") {
		t.Errorf("not-installed list is wrong:\n%s", out)
	}
}

func TestStatus(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("status")
	if code != ExitOK {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"0 pins, 0 behind the index", "4 pins on 1 revisions, minimal", "nothing under flake.nix", "last run\n  none recorded"} {
		if !strings.Contains(out, want) {
			t.Errorf("status lacks %q:\n%s", want, out)
		}
	}
	h.run("add", "zizmor")
	code, out = h.run("status")
	if code != ExitOK || !strings.Contains(out, "hm add zizmor at") || !strings.Contains(out, "ok, reached step report") || !strings.Contains(out, "home-manager/packages.nix") {
		t.Fatalf("exit %d\n%s", code, out)
	}
}

func TestSwitchAndClean(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("switch")
	if code != ExitOK || !strings.Contains(out, "to generation 21") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	code, out = h.run("switch", "sideways")
	if code != ExitUsage {
		t.Fatalf("exit %d\n%s", code, out)
	}
	must(t, os.Symlink(filepath.Join(h.store, "gen-19"), filepath.Join(h.state, "home-manager/keep-gen19")))
	code, out = h.run("clean")
	if code != ExitRefused || !strings.Contains(out, "keep-gen19") {
		t.Fatalf("clean with the root: exit %d\n%s", code, out)
	}
	must(t, os.Remove(filepath.Join(h.state, "home-manager/keep-gen19")))
	code, out = h.run("clean", "--keep", "7")
	if code != ExitOK || !strings.Contains(h.calls(), "nh clean user --keep 7") {
		t.Fatalf("clean: exit %d\n%s\n%s", code, out, h.calls())
	}
}

// switch and a standalone sync change the machine, so they take the same
// lock as add and refuse on a held lock or an unresolved run.
func TestSwitchAndSyncTakeTheLock(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "home-manager/go-tools.nix", "[\n  \"github.com/fatih/gomodifytags@v1.17.0\"\n]\n")
	h.git("add", ".")
	h.git("commit", "-q", "-m", "home: add go gomodifytags")
	lock := filepath.Join(h.repo, ".git", "hm.lock")
	must(t, os.WriteFile(lock, []byte(strconv.Itoa(os.Getpid())+"\n"), 0o644))
	for _, args := range [][]string{{"switch"}, {"sync", "go"}, {"sync"}} {
		code, out := h.run(args...)
		if code != ExitRefused || !strings.Contains(out, "another hm (pid") {
			t.Errorf("%v with the lock held: exit %d\n%s", args, code, out)
		}
	}
	if calls := h.calls(); strings.Contains(calls, "nh home switch") || strings.Contains(calls, "go install") {
		t.Errorf("a locked run changed the machine:\n%s", calls)
	}
	must(t, os.Remove(lock))
	t.Setenv("FAKE_NH_FAIL", "1")
	if code, out := h.run("add", "--keep-on-failure", "zizmor"); code != ExitFailed {
		t.Fatalf("exit %d\n%s", code, out)
	}
	t.Setenv("FAKE_NH_FAIL", "")
	h.git("checkout", "--", ".")
	for _, args := range [][]string{{"switch"}, {"sync", "go"}} {
		code, out := h.run(args...)
		if code != ExitRefused || !strings.Contains(out, "a previous run") {
			t.Errorf("%v on an unresolved run: exit %d\n%s", args, code, out)
		}
	}
	unresolved, err := txn.Unresolved(filepath.Join(h.repo, ".git"))
	must(t, err)
	for _, path := range unresolved {
		must(t, os.Remove(path))
	}
	code, out := h.run("switch")
	if code != ExitOK || !strings.Contains(out, "to generation 21") {
		t.Fatalf("switch after acknowledging: exit %d\n%s", code, out)
	}
	if j := h.lastJournal(); j.Command[1] != "switch" || j.Outcome != txn.OutcomeOK || !j.Resolved() {
		t.Errorf("switch journal = %+v", j)
	}
	if _, err := os.Stat(lock); err == nil {
		t.Error("switch left the lock behind")
	}
	code, out = h.run("sync", "go")
	if code != ExitOK || !strings.Contains(h.calls(), "go install github.com/fatih/gomodifytags@v1.17.0") {
		t.Fatalf("sync after acknowledging: exit %d\n%s\n%s", code, out, h.calls())
	}
	if j := h.lastJournal(); j.Command[1] != "sync" || j.Outcome != txn.OutcomeOK {
		t.Errorf("sync journal = %+v", j)
	}
	if _, err := os.Stat(lock); err == nil {
		t.Error("sync left the lock behind")
	}
}

// The sync that add --go runs is part of add's own transaction, so it
// does not contend for the lock add already holds.
func TestAddGoToolInstallsInsideItsTransaction(t *testing.T) {
	h := newHarness(t)
	code, out := h.run("add", "--go", "github.com/fatih/gomodifytags@v1.17.0")
	if code != ExitOK || !strings.Contains(out, "+ go install github.com/fatih/gomodifytags@v1.17.0") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if !strings.Contains(h.calls(), "go install github.com/fatih/gomodifytags@v1.17.0") {
		t.Errorf("go install did not run:\n%s", h.calls())
	}
	if j := h.lastJournal(); j.Outcome != txn.OutcomeOK || j.LastStep() != "report" {
		t.Errorf("journal = %+v", j)
	}
}

func TestCompleteOwned(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "home-manager/go-tools.nix", "[\n  \"github.com/fatih/gomodifytags@v1.17.0\"\n]\n")
	code, out := h.run("__complete", "rm", "")
	if code != ExitOK || !strings.Contains(out, "bat\n") || !strings.Contains(out, "github.com/fatih/gomodifytags\n") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	code, out = h.run("__complete", "up", "")
	if code != ExitOK || strings.Contains(out, "gomodifytags") {
		t.Fatalf("up offered a go tool: exit %d\n%s", code, out)
	}
	code, out = h.run("__complete", "add", "zi")
	if code != ExitOK || out != "zizmor\n" {
		t.Fatalf("exit %d\n%q", code, out)
	}
}

// A tool commit is named after the executable the entry installs, so the
// sibling packages of one module get distinct subjects; a Go pseudo-version
// keeps its date and drops its hash in the subject, and the full entry is
// the commit body.
func TestToolCommitsNameTheExecutable(t *testing.T) {
	h := newHarness(t)
	const kubetest2 = "sigs.k8s.io/kubetest2/kubetest2-"
	const pseudo = "@v0.0.0-20240905095256-f6e8664cd2b1"
	want := map[string]string{
		kubetest2 + "gce" + pseudo:                                                 "home: add go kubetest2-gce v0.0.0-20240905095256",
		kubetest2 + "gke" + pseudo:                                                 "home: add go kubetest2-gke v0.0.0-20240905095256",
		kubetest2 + "kind" + pseudo:                                                "home: add go kubetest2-kind v0.0.0-20240905095256",
		kubetest2 + "noop" + pseudo:                                                "home: add go kubetest2-noop v0.0.0-20240905095256",
		kubetest2 + "tester-clusterloader2" + pseudo:                               "home: add go kubetest2-tester-clusterloader2 v0.0.0-20240905095256",
		kubetest2 + "tester-exec" + pseudo:                                         "home: add go kubetest2-tester-exec v0.0.0-20240905095256",
		kubetest2 + "tester-ginkgo" + pseudo:                                       "home: add go kubetest2-tester-ginkgo v0.0.0-20240905095256",
		kubetest2 + "tester-node" + pseudo:                                         "home: add go kubetest2-tester-node v0.0.0-20240905095256",
		"sigs.k8s.io/kubetest2" + pseudo:                                           "home: add go kubetest2 v0.0.0-20240905095256",
		"github.com/arch-go/arch-go/v2@v2.1.2":                                     "home: add go arch-go v2.1.2",
		"golang.org/x/perf/cmd/benchstat@v0.0.0-20250505210442-a54a20dddd97":       "home: add go benchstat v0.0.0-20250505210442",
		"github.com/JohannesKaufmann/html-to-markdown/v2/cli/html2markdown@v2.5.0": "home: add go html2markdown v2.5.0",
	}
	seen := map[string]string{}
	for entry, wantSubject := range want {
		code, out := h.run("add", "--go", "--build-only", "--commit", entry)
		if code != ExitOK {
			t.Fatalf("%s: exit %d\n%s", entry, code, out)
		}
		subj := strings.TrimSpace(h.git("log", "-1", "--format=%s"))
		body := strings.TrimSpace(h.git("log", "-1", "--format=%b"))
		if subj != wantSubject {
			t.Errorf("%s: subject %q, want %q", entry, subj, wantSubject)
		}
		if len(subj) > 72 {
			t.Errorf("%s: subject longer than 72: %q", entry, subj)
		}
		if body != entry {
			t.Errorf("%s: body %q, want the full entry", entry, body)
		}
		if other, dup := seen[subj]; dup {
			t.Errorf("%s and %s share the subject %q", entry, other, subj)
		}
		seen[subj] = entry
	}
	h.script("uv", `case "$1 $2" in "tool list") echo "" ;; esac`)
	code, out := h.run("add", "--uv", "--build-only", "--commit", "claude-monitor==3.1.0")
	if code != ExitOK {
		t.Fatalf("uv: exit %d\n%s", code, out)
	}
	if subj := strings.TrimSpace(h.git("log", "-1", "--format=%s")); subj != "home: add uv claude-monitor 3.1.0" {
		t.Errorf("uv subject = %q", subj)
	}
	if body := strings.TrimSpace(h.git("log", "-1", "--format=%b")); body != "claude-monitor==3.1.0" {
		t.Errorf("uv body = %q", body)
	}
}

// Reconciliation leaves an entry whose installed version matches alone, so
// a plain sync is idempotent; --force reinstalls every declared entry, which
// rebuilds the tools with the toolchain of the current generation.
func TestSyncForceReinstallsMatchingEntries(t *testing.T) {
	h := newHarness(t)
	h.write("repo", "home-manager/cargo-tools.nix", "[\n  \"wt@0.3.1\"\n  \"rustlings@6.4.0\"\n]\n")
	h.git("add", ".")
	h.git("commit", "-q", "-m", "home: add cargo tools")
	h.script("cargo", `case "$1 $2" in "install --list") echo "rustlings v6.4.0:"; echo "    rustlings"; echo "wt v0.3.1:"; echo "    wt" ;; esac`)
	code, out := h.run("sync", "cargo")
	if code != ExitOK || !strings.Contains(out, "cargo: 2 current, 0 installed") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.calls(), "cargo install --locked") {
		t.Errorf("a matching entry was reinstalled without --force:\n%s", h.calls())
	}
	code, out = h.run("sync", "cargo", "--force")
	if code != ExitOK || !strings.Contains(out, "cargo: 2 installed, forced") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	for _, want := range []string{"cargo install --locked --force rustlings --version 6.4.0", "cargo install --locked --force wt --version 0.3.1"} {
		if !strings.Contains(h.calls(), want) {
			t.Errorf("calls lack %q:\n%s", want, h.calls())
		}
	}
	must(t, os.Remove(h.log))
	code, out = h.run("sync", "cargo", "--force", "--build-only")
	if code != ExitOK || !strings.Contains(out, "cargo: would install wt@0.3.1") || !strings.Contains(out, "cargo: 2 installed, forced") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	if strings.Contains(h.calls(), "cargo install --locked") {
		t.Errorf("--build-only installed:\n%s", h.calls())
	}
}
