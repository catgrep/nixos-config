// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
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
		log:     filepath.Join(root, "calls.log"),
	}
	for _, d := range []string{h.repo + "/home-manager", h.repo + "/hosts/ser8", h.home, h.state + "/home-manager/gcroots", h.state + "/nix/profiles", h.store + "/gen-20/home-path/bin", h.fakeDir, h.home + "/go/bin"} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	h.write("repo", "flake.nix", "{ }\n")
	h.write("repo", "flake.lock", "{\"version\": 7}\n")
	h.write("repo", "multiverse.lock", lockBefore)
	h.write("repo", "home-manager/packages.nix", packagesBefore)
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
	h.write("fake", "lock-after-add.json", strings.Replace(lockBefore, `    "ripgrep":`, `    "zizmor": {"rev": "e554", "label": "2026-09-17-e554", "version": "1.30.1", "date": "2026-09-17", "constraint": null},
    "ripgrep":`, 1))
	h.write("fake", "lock-after-rm.json", strings.Replace(lockBefore, `    "charasay": {"rev": "64c0", "label": "2026-08-01-64c0", "version": "3.3.0", "date": "2026-08-01", "constraint": null},
`, "", 1))
	h.write("fake", "lock-after-update.json", strings.Replace(lockBefore, `"version": "15.1.0"`, `"version": "15.2.0"`, 1))
	h.write("fake", "lock-after-update-jellyfin.json", strings.Replace(strings.Replace(lockBefore, `"version": "15.1.0"`, `"version": "15.2.0"`, 1), `"version": "10.11.11"`, `"version": "10.11.12"`, 1))
	h.fakes()
	h.env = map[string]string{
		"HOME":           h.home,
		"XDG_STATE_HOME": h.state,
		"NH_FLAKE":       h.repo,
		"USER":           "tester",
		"PATH":           h.fakeDir + string(os.PathListSeparator) + os.Getenv("PATH"),
	}
	t.Setenv("PATH", h.env["PATH"])
	t.Setenv("FAKE_LOG", h.log)
	t.Setenv("FAKE_DIR", h.fakeDir)
	t.Setenv("FAKE_REPO", h.repo)
	t.Setenv("FAKE_STORE", h.store)
	t.Setenv("FAKE_STATE", h.state)
	t.Setenv("FAKE_HOME", h.home)
	t.Setenv("FAKE_NH_FAIL", "")
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
	h.script("nix", `case "$1 $2" in
  "eval --json")
    if [ "$3" = "--file" ]; then
      if grep -q BROKEN "$4"; then echo "error: undefined variable 'BROKEN'" >&2; exit 1; fi
      echo '["ok"]'
    else
      cat "$FAKE_DIR/resolved.json"
    fi ;;
  "build --no-link") echo "$FAKE_STORE/built-generation" ;;
  "flake update") printf '{"version": 7, "updated": true}\n' > "$FAKE_REPO/flake.lock" ;;
  "run "*) shift 2; [ "$1" = "--" ] && shift; exec "$FAKE_DIR/mvs" "$@" ;;
  *) echo "fake nix: unknown $*" >&2; exit 1 ;;
esac
`)
	h.script("nix-store", `cat "$FAKE_DIR/refs.txt"
`)
	h.script("nh", `if [ -n "$FAKE_NH_FAIL" ]; then echo "error: builder failed" >&2; exit 1; fi
case "$1 $2" in
  "home switch")
    n=$(cat "$FAKE_DIR/gen-counter"); n=$((n + 1)); echo "$n" > "$FAKE_DIR/gen-counter"
    mkdir -p "$FAKE_STORE/gen-$n/home-path/bin"
    ln -sfn "$FAKE_STORE/gen-$n" "$FAKE_STATE/home-manager/gcroots/current-home"
    ln -sfn "$FAKE_STORE/gen-$n" "$FAKE_STATE/nix/profiles/home-manager-$n-link"
    ln -sfn "home-manager-$n-link" "$FAKE_STATE/nix/profiles/home-manager" ;;
esac
`)
	h.script("go", `case "$1" in
  env) printf '%s\n%s\n' "$FAKE_HOME/go/bin" "$FAKE_HOME/go" ;;
esac
`)
	h.script("nvd", "")
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
	if _, _, err := txn.Last(filepath.Join(h.repo, ".git")); err != nil {
		t.Fatal(err)
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
	for _, want := range []string{"hm: not installed; run: hm sync go", "commit -m 'home: add go github.com/fatih/gomodifytags v1.17.0' -- home-manager/go-tools.nix"} {
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
	if code != ExitOK || !strings.Contains(out, "replacing github.com/fatih/gomodifytags@v1.17.0 with github.com/fatih/gomodifytags@v1.18.0") || !strings.Contains(out, "'home: update go github.com/fatih/gomodifytags v1.17.0 to v1.18.0'") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	code, out = h.run("sync", "go", "--build-only")
	if code != ExitOK || !strings.Contains(out, "would install github.com/fatih/gomodifytags@v1.18.0") || !strings.Contains(out, "go: 0 current, 1 installed") {
		t.Fatalf("exit %d\n%s", code, out)
	}
	h.git("checkout", "--", ".")
	code, out = h.run("rm", "--build-only", "github.com/fatih/gomodifytags")
	if code != ExitOK || !strings.Contains(out, "remove go github.com/fatih/gomodifytags") {
		t.Fatalf("exit %d\n%s", code, out)
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
	h.write("fake", "resolved.json", `{"pinned":{"bat":"/nix/store/9nnfhsm7d0rmv74viba3q8w8bvgaix8n-bat-0.26.1","charasay":"","ripgrep":"/nix/store/h5fzp9vb16p8z3ha51hhx37rqjh4l81z-ripgrep-15.1.0"},"nixpkgs":{"man-db":"/nix/store/9jvj0khvdmj7hnyqkk4454d715jvkf7x-man-db-2.13.1","home-manager":"","bat":"","ripgrep":""}}`)
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
