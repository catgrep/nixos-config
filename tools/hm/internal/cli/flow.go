// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/catgrep/nixos-config/tools/hm/internal/nixlist"
	"github.com/catgrep/nixos-config/tools/hm/internal/sources"
	"github.com/catgrep/nixos-config/tools/hm/internal/txn"
)

func jsonUnmarshal(data []byte, v any) error {
	return json.Unmarshal(data, v)
}

// flow is one run that edits owned files and ends in a switch or a sync.
// In a dry run tx is nil and every write is printed as a diff instead.
type flow struct {
	a     *App
	tx    *txn.Txn
	files []string
	keep  bool
}

// beginFlow refuses when a file hm would own has uncommitted changes,
// takes the lock and captures the files.
func (a *App) beginFlow(files []string, keep bool) (*flow, error) {
	if err := a.refuseDirty(files...); err != nil {
		return nil, err
	}
	f := &flow{a: a, files: files, keep: keep}
	if a.dryRun {
		return f, nil
	}
	gitDir, err := a.git.Dir()
	if err != nil {
		return nil, err
	}
	tx, err := txn.Begin(a.flake, gitDir, append([]string{"hm"}, a.env.Args...), a.now)
	if err != nil {
		var locked *txn.LockedError
		var unresolved *txn.UnresolvedError
		if errors.As(err, &locked) || errors.As(err, &unresolved) {
			return nil, refuse("%v", err)
		}
		return nil, err
	}
	abs := make([]string, len(files))
	for i, rel := range files {
		abs[i] = a.path(rel)
	}
	if err := tx.Capture(abs...); err != nil {
		_ = tx.Finish(txn.OutcomeFailed, err.Error())
		return nil, err
	}
	f.tx = tx
	return f, nil
}

// refuseDirty stops a run before it reads anything when a file it would
// own has uncommitted changes, since the path-scoped commit would sweep
// them in.
func (a *App) refuseDirty(files ...string) error {
	dirty, err := a.git.Dirty(files...)
	if err != nil {
		return err
	}
	if len(dirty) > 0 {
		return refuse("uncommitted changes in %s; commit or stash them first, because hm commits these files by path", strings.Join(dirty, ", "))
	}
	return nil
}

// step records progress in the journal.
func (f *flow) step(name string) {
	if f.tx != nil {
		_ = f.tx.Step(name)
	}
}

// writeList writes a list file, or prints the diff in a dry run. A file
// that did not exist is staged so the flake evaluation can see it.
func (f *flow) writeList(rel string, l *nixlist.List, created bool) error {
	path := f.a.path(rel)
	data := l.Bytes()
	if f.a.dryRun {
		var old []byte
		if !created {
			old, _ = os.ReadFile(path)
		}
		fmt.Fprint(f.a.out, unifiedDiff(rel, old, data))
		return nil
	}
	if err := f.tx.Write(path, data); err != nil {
		var conflict *txn.ConflictError
		if errors.As(err, &conflict) {
			return refuse("%v", err)
		}
		return err
	}
	if created {
		return f.a.git.Add(rel)
	}
	return nil
}

// adopt accepts a file another program rewrote.
func (f *flow) adopt(rel string) error {
	if f.tx == nil {
		return nil
	}
	return f.tx.Adopt(f.a.path(rel))
}

// fail handles an error before a generation exists: restore the captured
// files unless --keep-on-failure was given, record the outcome, and turn
// the error into exit status 1.
func (f *flow) fail(step string, err error) error {
	var exit *exitError
	if errors.As(err, &exit) && exit.code == ExitRefused {
		if f.tx != nil {
			_ = f.tx.Finish(txn.OutcomeFailed, "refused at "+step+": "+exit.msg)
		}
		return err
	}
	if f.tx == nil {
		return fail(ExitFailed, "%s failed: %v", step, err)
	}
	if f.keep {
		_ = f.tx.Finish(txn.OutcomeKept, step+": "+err.Error())
		return fail(ExitFailed, "%s failed: %v\nhm: the edited files were kept: %s", step, err, strings.Join(f.tx.Changed(), ", "))
	}
	restored, rerr := f.tx.Restore()
	detail := step + ": " + err.Error()
	if len(restored) > 0 {
		detail += "; restored " + strings.Join(restored, ", ")
	}
	_ = f.tx.Finish(txn.OutcomeFailed, detail)
	msg := fmt.Sprintf("%s failed: %v", step, err)
	if len(restored) > 0 {
		msg += fmt.Sprintf("\nhm: restored %s", strings.Join(restored, ", "))
	}
	if rerr != nil {
		msg += fmt.Sprintf("\nhm: restore incomplete: %v", rerr)
	}
	return fail(ExitFailed, "%s", msg)
}

// finish records a successful run.
func (f *flow) finish(outcome, detail string) {
	if f.tx != nil {
		_ = f.tx.Finish(outcome, detail)
	}
}

// changed lists the files this run changed, relative to the flake.
func (f *flow) changed() []string {
	if f.tx != nil {
		return f.tx.Changed()
	}
	return f.files
}

// report prints the change set and the commit command, and runs the commit
// when asked. A commit refusal after a successful switch is exit status 4.
func (f *flow) report(subj string, commit bool) error {
	changed := f.changed()
	if len(changed) == 0 {
		f.a.say("nothing to commit")
		f.finish(txn.OutcomeOK, "no file changed")
		return nil
	}
	sort.Strings(changed)
	cmd := f.a.git.CommitCommand(subj, changed...)
	if !commit {
		f.a.say("uncommitted: %s", strings.Join(changed, " "))
		f.a.say("%s", cmd)
		f.finish(txn.OutcomeOK, "uncommitted "+strings.Join(changed, " "))
		return nil
	}
	if f.tx != nil {
		if edited := f.tx.Verify(); len(edited) > 0 {
			f.finish(txn.OutcomeCommitFailed, "edited after the switch: "+strings.Join(edited, ", "))
			return fail(ExitCommitFailed, "%s changed after the switch; not committing. Review and run:\nhm: %s", strings.Join(edited, ", "), cmd)
		}
	}
	if err := f.a.git.Commit(subj, changed...); err != nil {
		f.finish(txn.OutcomeCommitFailed, err.Error())
		return fail(ExitCommitFailed, "commit failed: %v\nhm: %s", err, cmd)
	}
	f.a.say("committed %q", subj)
	f.finish(txn.OutcomeOK, "committed "+subj)
	return nil
}

// activate switches to the new configuration, or with buildOnly builds
// the activation package and reports its path. It returns a line
// describing what happened.
func (a *App) activate(buildOnly bool) (string, error) {
	if buildOnly {
		installable := fmt.Sprintf("%s#homeConfigurations.%q.activationPackage", a.flake, a.configName())
		path, err := a.nix.Build(installable)
		if err != nil {
			return "", err
		}
		if a.dryRun {
			return "would build " + installable, nil
		}
		a.say("built %s", path)
		a.diffAgainstCurrent(path)
		a.say("not activated; run: hm switch")
		return "built " + path, nil
	}
	before, _ := a.currentGeneration()
	if err := a.nh.HomeSwitch(a.flake); err != nil {
		return "", err
	}
	if a.dryRun {
		return "would switch", nil
	}
	after, err := a.currentGeneration()
	if err != nil {
		return "", err
	}
	if after == before {
		a.say("switched %s: generation unchanged", a.configName())
		return "generation unchanged", nil
	}
	n := sources.GenerationNumber(a.home, a.env.Getenv)
	if n > 0 {
		a.say("switched %s to generation %d", a.configName(), n)
		return fmt.Sprintf("generation %d", n), nil
	}
	a.say("switched %s to %s", a.configName(), after)
	return after, nil
}

// diffAgainstCurrent shows what a built generation adds and removes
// relative to the active one, when nvd is available.
func (a *App) diffAgainstCurrent(built string) {
	current, err := a.currentGeneration()
	if err != nil || current == built {
		return
	}
	nvd := a.toolBin("nvd")
	if err := a.runner.Do(cmdOf(nvd, "diff", current, built)); err != nil {
		a.say("nvd diff unavailable: %v", err)
	}
}
