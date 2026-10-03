// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/run"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

// homebrewKind is one of the two Homebrew lists the nix-darwin system
// installs: casks or formulae.
type homebrewKind struct {
	// name is the word in the flag, the source tag and the commit subject.
	name string
	file string
	// dir is where Homebrew keeps an installed entry, under its prefix.
	dir string
	// listVerb is the brew subcommand that names every entry Homebrew
	// knows, read from its local API data.
	listVerb string
}

func homebrewKinds() []homebrewKind {
	return []homebrewKind{
		{name: "cask", file: fileCasks, dir: "Caskroom", listVerb: "casks"},
		{name: "brew", file: fileBrews, dir: "Cellar", listVerb: "formulae"},
	}
}

// homebrewFlag returns the Homebrew kind a word list selects with --cask
// or --brew.
func homebrewFlag(words []string) (homebrewKind, bool) {
	for _, k := range homebrewKinds() {
		for _, w := range words {
			if w == "--"+k.name {
				return k, true
			}
		}
	}
	return homebrewKind{}, false
}

// validHomebrewName accepts a Homebrew token such as ghostty or node@22,
// or a tap-qualified one such as peonping/tap/peon-ping. The name is
// taken whole: the @ of a versioned formula is part of it.
func validHomebrewName(name string) error {
	parts := strings.Split(name, "/")
	if len(parts) != 1 && len(parts) != 3 {
		return fmt.Errorf("%q is neither NAME nor USER/REPO/NAME", name)
	}
	token := regexp.MustCompile(`^[a-z0-9][a-z0-9._+@-]*$`)
	for _, p := range parts {
		if !token.MatchString(p) {
			return fmt.Errorf("%q is not a Homebrew name: lower-case letters, digits and . _ + @ - only", name)
		}
	}
	return nil
}

// addHomebrew appends a cask or formula to its list and switches the
// nix-darwin system. There is no pin to record: Homebrew tracks its own
// versions.
func (a *App) addHomebrew(k homebrewKind, name string, co changeOpts) error {
	if err := validHomebrewName(name); err != nil {
		return usage("--%s expects a Homebrew %s name: %v", k.name, k.name, err)
	}
	if err := a.refuseDirty(k.file); err != nil {
		return err
	}
	list, created, err := a.readList(k.file)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{k.file}, co.keep)
	if err != nil {
		return err
	}
	if list.Add(name) {
		f.step("write")
		if err := f.writeList(k.file, list, created); err != nil {
			return f.fail("write "+k.file, err)
		}
		if err := a.validateList(k.file); err != nil && !a.dryRun {
			return f.fail("validate", err)
		}
	} else {
		a.say("%s is already in %s", name, k.file)
	}
	f.step("switch darwin")
	detail, err := a.activateDarwin(co.buildOnly)
	if err != nil {
		return f.fail("switch darwin", err)
	}
	f.step("report")
	a.say("added %s %s (%s)", k.name, name, detail)
	return f.report(commitMessage{subject: subject("darwin", "add "+k.name, name, "")}, co.commit)
}

// rmHomebrew drops a cask or formula from its list and switches. Homebrew
// keeps the package installed until hm brew cleanup --force removes it.
func (a *App) rmHomebrew(k homebrewKind, name string, co changeOpts) error {
	list, _, err := a.readList(k.file)
	if err != nil {
		return err
	}
	f, err := a.beginFlow([]string{k.file}, false)
	if err != nil {
		return err
	}
	list.Remove(name)
	f.step("write")
	if err := f.writeList(k.file, list, false); err != nil {
		return f.fail("write "+k.file, err)
	}
	if err := a.validateList(k.file); err != nil && !a.dryRun {
		return f.fail("validate", err)
	}
	f.step("switch darwin")
	detail, err := a.activateDarwin(co.buildOnly)
	if err != nil {
		return f.fail("switch darwin", err)
	}
	f.step("report")
	a.say("removed %s %s (%s); Homebrew keeps it until hm brew cleanup --force", k.name, name, detail)
	return f.report(commitMessage{subject: subject("darwin", "remove "+k.name, name, "")}, co.commit)
}

// darwinInstallable is a flake attribute of this Mac's nix-darwin system,
// named after LocalHostName the way nh darwin switch selects it.
func (a *App) darwinInstallable(attr string) string {
	return fmt.Sprintf("%s#darwinConfigurations.%q.%s", a.flake, a.hostName(), attr)
}

// activateDarwin switches the nix-darwin system, or with buildOnly builds
// it and reports its path. A switch that changed the active system, or
// left it unreadable, is reported as activated whether nh reported
// success or failure, so the edited lists are kept as its source.
func (a *App) activateDarwin(buildOnly bool) (string, error) {
	if buildOnly {
		return a.buildDarwin()
	}
	before, berr := a.darwinState()
	if err := a.nh.DarwinSwitch(a.flake); err != nil {
		return "", a.darwinSwitchFailure(before, berr, err)
	}
	if a.dryRun {
		return "would switch darwin", nil
	}
	after, err := a.darwinState()
	if err != nil {
		return "", &activatedError{cause: err, generation: "nh darwin switch succeeded; the system it activated cannot be determined"}
	}
	if after == before {
		a.say("switched darwin %s: generation unchanged", a.hostName())
		return "darwin generation unchanged", nil
	}
	detail := a.describeDarwin(after)
	a.say("switched darwin %s to %s", a.hostName(), detail)
	return detail, nil
}

// buildDarwin builds the nix-darwin system without activating it.
func (a *App) buildDarwin() (string, error) {
	installable := a.darwinInstallable("system")
	built, err := a.nix.Build(installable)
	if err != nil {
		return "", err
	}
	if a.dryRun {
		return "would build " + installable, nil
	}
	a.say("built %s", built)
	if current, err := a.darwinState(); err == nil && current != "" {
		a.diffGenerations(current, built)
	}
	a.say("not activated; run: hm switch darwin")
	return "built " + built, nil
}

func (a *App) darwinState() (string, error) {
	return sources.ReadDarwinState(a.env.Getenv)
}

// darwinSwitchFailure decides what a non-zero nh darwin exit means, with
// the same rule as switchFailure: only a failure that left the active
// system where it was may be restored from.
func (a *App) darwinSwitchFailure(before string, berr, err error) error {
	after, aerr := a.darwinState()
	switch {
	case berr != nil:
		return &activatedError{cause: err, generation: "the darwin system before the switch cannot be read: " + berr.Error()}
	case aerr != nil:
		return &activatedError{cause: err, generation: "the active darwin system cannot be read: " + aerr.Error()}
	case after != before:
		return &activatedError{cause: err, generation: a.describeDarwin(after) + " is now active"}
	}
	return err
}

// describeDarwin names the active nix-darwin generation by number when
// the system profile link carries one, else by store path.
func (a *App) describeDarwin(system string) string {
	if n := sources.DarwinGenerationNumber(a.env.Getenv); n > 0 {
		return fmt.Sprintf("darwin generation %d", n)
	}
	return system
}

func (a *App) cmdBrew(opts options, args []string) error {
	if len(args) != 1 || args[0] != "cleanup" {
		return usage("brew takes the subcommand cleanup; run 'hm brew --help'")
	}
	if err := a.requireFlake(); err != nil {
		return err
	}
	brewfile, err := a.writeBrewfile()
	if err != nil {
		return err
	}
	defer os.Remove(brewfile)
	cmd := brewCommand("bundle", "cleanup", "--file="+brewfile)
	if opts.flag("zap") {
		cmd.Args = append(cmd.Args, "--zap")
	}
	if !opts.flag("force") {
		return a.previewCleanup(cmd, brewfile)
	}
	cmd.Args = append(cmd.Args, "--force")
	f, err := a.beginFlow(nil, false)
	if err != nil {
		return err
	}
	f.step("brew cleanup")
	if err := a.runner.Do(cmd); err != nil {
		return f.fail("brew bundle cleanup", err)
	}
	f.finish(txn.OutcomeOK, "removed what the Brewfile does not declare")
	return nil
}

// brewCommand runs brew without its auto-update, as nix-darwin's
// activation does, so a cleanup neither waits on a fetch nor changes
// anything else.
func brewCommand(args ...string) run.Cmd {
	return run.Cmd{Prog: "brew", Args: args, Env: []string{"HOMEBREW_NO_AUTO_UPDATE=1"}}
}

// writeBrewfile evaluates the Brewfile the flake generates for this Mac
// into a temporary file and returns its path. The text comes from the
// homebrew.brewfile option rather than from the activated system, so the
// preview matches what the next switch would apply and works before the
// first one.
func (a *App) writeBrewfile() (string, error) {
	text, err := a.nix.EvalRaw(a.darwinInstallable("config.homebrew.brewfile"))
	if err != nil {
		return "", fmt.Errorf("evaluating the Brewfile: %v", err)
	}
	tmp, err := os.CreateTemp("", "hm-Brewfile-*")
	if err != nil {
		return "", err
	}
	if _, err := tmp.WriteString(text); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmp.Name())
		return "", err
	}
	return tmp.Name(), tmp.Close()
}

// previewCleanup prints what brew bundle cleanup would remove. brew exits
// 1 when something would be removed, which is the answer asked for here,
// not a failure; an exit 1 that listed nothing is one, and a run that asks
// for brew trust is the prerequisite that command names.
func (a *App) previewCleanup(cmd run.Cmd, brewfile string) error {
	out, err := a.runner.Output(cmd)
	text := strings.TrimSpace(string(out))
	var exit *run.ExitError
	if errors.As(err, &exit) && strings.Contains(exit.Stderr, "`brew trust ") {
		return trustPrerequisite(brewfile, exit.Stderr)
	}
	if err != nil && !(errors.As(err, &exit) && exit.Code == 1 && strings.Contains(text, "Would ")) {
		return err
	}
	if text == "" {
		a.say("nothing to remove: everything Homebrew has is in the Brewfile")
		return nil
	}
	return a.page(func(w io.Writer) error {
		_, err := fmt.Fprintf(w, "%s\nhm: hm brew cleanup --force removes them; add --zap to delete cask data too\n", text)
		return err
	})
}

// trustPrerequisite reports a cleanup that brew refused because a tap is
// not trusted yet, with the one-time command that trusts every tap the
// Brewfile declares as trusted. Homebrew applies the Brewfile's trusted
// flags only when a switch installs it, so a preview before the first
// switch meets the taps untrusted. Trusting a tap is a local Homebrew
// setting, not a change to the lists, so there is nothing to restore.
func trustPrerequisite(brewfile, stderr string) error {
	taps, err := trustedTaps(brewfile)
	if err != nil {
		return err
	}
	lines := append([]string{"brew bundle cleanup refused: a declared tap is not trusted yet"}, trustLines(stderr)...)
	if len(taps) == 0 {
		lines = append(lines, "the Brewfile declares no trusted tap; declare it with trusted = true in darwin/homebrew/default.nix")
	} else {
		lines = append(lines,
			"trust the taps the Brewfile declares once, then rerun the preview:",
			"  brew trust "+strings.Join(taps, " "),
			"trusting a tap is a one-time local Homebrew setting, not a change to darwin/homebrew/; nothing was removed")
	}
	return fail(ExitFailed, "%s", strings.Join(lines, "\nhm: "))
}

// trustedTaps lists the taps a Brewfile declares with trusted: true, in
// declaration order.
func trustedTaps(brewfile string) ([]string, error) {
	data, err := os.ReadFile(brewfile)
	if err != nil {
		return nil, err
	}
	var taps []string
	for _, m := range regexp.MustCompile(`(?m)^tap "([^"]+)".*\btrusted: true\b`).FindAllStringSubmatch(string(data), -1) {
		taps = append(taps, m[1])
	}
	return taps, nil
}

// trustLines keeps the lines of brew's stderr that explain the trust
// refusal, without the Error: and Warning: prefixes brew puts on them.
func trustLines(stderr string) []string {
	var lines []string
	for _, line := range strings.Split(stderr, "\n") {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "trust") && !strings.HasPrefix(line, "Run `brew trust") {
			lines = append(lines, strings.TrimPrefix(strings.TrimPrefix(line, "Error: "), "Warning: "))
		}
	}
	return lines
}

// homebrewPrefix is where Homebrew lives: HOMEBREW_PREFIX, else the
// Apple silicon default when it exists, else the Intel one.
func (a *App) homebrewPrefix() string {
	if p := a.env.Getenv("HOMEBREW_PREFIX"); p != "" {
		return p
	}
	if _, err := os.Stat("/opt/homebrew"); err == nil {
		return "/opt/homebrew"
	}
	return "/usr/local"
}

// homebrewRows lists the declared casks and brews with the version
// Homebrew has installed, read from its Caskroom and Cellar directories so
// no brew process runs. What Homebrew has beyond the lists is the business
// of hm brew cleanup, not of this list.
func (a *App) homebrewRows(inv *inventory) {
	prefix := a.homebrewPrefix()
	for _, k := range homebrewKinds() {
		list, created, err := a.readList(k.file)
		if err != nil {
			inv.problems = append(inv.problems, err.Error())
			continue
		}
		if created {
			continue
		}
		for _, name := range list.Entries() {
			r := row{Name: name, Version: "-", Source: k.name, Detail: k.file}
			if v := installedVersions(filepath.Join(prefix, k.dir, path.Base(name))); v != "" {
				r.Version = v
			} else {
				r.Detail += "; not installed"
			}
			inv.rows = append(inv.rows, r)
		}
	}
}

// installedVersions joins the version directories Homebrew keeps for one
// package, "" when none is installed.
func installedVersions(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	var versions []string
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			versions = append(versions, e.Name())
		}
	}
	sort.Strings(versions)
	return strings.Join(versions, " ")
}

// homebrewNames lists every cask or formula Homebrew knows, from its
// local API data, so completing a name needs no network.
func (a *App) homebrewNames(k homebrewKind) []string {
	out, err := a.runner.Output(cmdOf("brew", k.listVerb))
	if err != nil {
		return nil
	}
	return strings.Fields(string(out))
}
