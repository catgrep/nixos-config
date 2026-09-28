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

// commitMessage is the generated commit for a run: a subject of at most 72
// characters and an optional body carrying what the subject abbreviates,
// such as the full module path of a tool entry.
type commitMessage struct {
	subject string
	body    string
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
// takes the lock and captures the files. A run that edits nothing, such
// as switch or a standalone sync, still takes the lock so it cannot
// interleave with a run that does.
func (a *App) beginFlow(files []string, keep bool) (*flow, error) {
	if len(files) > 0 {
		if err := a.refuseDirty(files...); err != nil {
			return nil, err
		}
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
	var activated *activatedError
	if errors.As(err, &activated) {
		return f.keepActivated(step, activated)
	}
	if f.keep {
		_ = f.tx.Finish(txn.OutcomeKept, step+": "+err.Error())
		return fail(ExitFailed, "%s failed: %v\nhm: the edited files were kept: %s", step, err, strings.Join(f.tx.Changed(), ", "))
	}
	return f.restore(step, err)
}

// restore puts the captured files back and reports the ones it could not:
// a file that no longer holds what hm wrote is left as found, and the run
// stays unresolved until the user has looked at it.
func (f *flow) restore(step string, err error) error {
	restored, kept, rerr := f.tx.Restore()
	detail := step + ": " + err.Error()
	msg := fmt.Sprintf("%s failed: %v", step, err)
	if len(restored) > 0 {
		detail += "; restored " + strings.Join(restored, ", ")
		msg += "\nhm: restored " + strings.Join(restored, ", ")
	}
	if rerr != nil {
		detail += "; restore incomplete: " + rerr.Error()
		msg += fmt.Sprintf("\nhm: restore incomplete: %v", rerr)
	}
	if len(kept) > 0 {
		detail += "; left as found: " + strings.Join(kept, ", ")
		msg += fmt.Sprintf("\nhm: left %s as found: the content is not what hm last wrote; reconcile it and remove %s to acknowledge", strings.Join(kept, ", "), f.tx.JournalPath())
	}
	outcome := txn.OutcomeFailed
	if len(kept) > 0 || rerr != nil {
		outcome = txn.OutcomeUnrestored
	}
	_ = f.tx.Finish(outcome, detail)
	return fail(ExitFailed, "%s", msg)
}

// keepActivated records a switch that failed after the generation changed:
// nothing is restored, the edited files are the source of what is now
// active, and the run stays unresolved until the user has looked at them.
func (f *flow) keepActivated(step string, e *activatedError) error {
	changed := f.tx.Changed()
	msg := fmt.Sprintf("%s failed: %v\nhm: %s", step, e.cause, e.generation)
	detail := fmt.Sprintf("%s: %v; %s", step, e.cause, e.generation)
	if len(changed) == 0 {
		_ = f.tx.Finish(txn.OutcomeFailed, detail)
		return fail(ExitFailed, "%s", msg)
	}
	detail += "; kept " + strings.Join(changed, ", ")
	msg += fmt.Sprintf("; the edited files are its source and were kept: %s\nhm: review and commit them, then remove %s to acknowledge", strings.Join(changed, ", "), f.tx.JournalPath())
	_ = f.tx.Finish(txn.OutcomeActivated, detail)
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
func (f *flow) report(msg commitMessage, commit bool) error {
	changed := f.changed()
	if len(changed) == 0 {
		f.a.say("nothing to commit")
		f.finish(txn.OutcomeOK, "no file changed")
		return nil
	}
	sort.Strings(changed)
	cmd := f.a.git.CommitCommand(msg.subject, msg.body, changed...)
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
	if err := f.a.git.Commit(msg.subject, msg.body, changed...); err != nil {
		f.finish(txn.OutcomeCommitFailed, err.Error())
		return fail(ExitCommitFailed, "commit failed: %v\nhm: %s", err, cmd)
	}
	f.a.say("committed %q", msg.subject)
	f.finish(txn.OutcomeOK, "committed "+msg.subject)
	return nil
}

// activatedError is a switch that reported failure after the active
// generation changed, or while it cannot be determined. The generation is
// the truth from then on and the edited files are its source, so the
// caller must keep them rather than restore them.
type activatedError struct {
	cause      error
	generation string
}

func (e *activatedError) Error() string {
	return e.cause.Error()
}

func (e *activatedError) Unwrap() error {
	return e.cause
}

// activate switches to the new configuration, or with buildOnly builds
// the activation package and reports its path. It returns a line
// describing what happened.
func (a *App) activate(buildOnly bool) (string, error) {
	if buildOnly {
		return a.buildOnly()
	}
	before, berr := a.generationState()
	if err := a.nh.HomeSwitch(a.flake); err != nil {
		return "", a.switchFailure(before, berr, err)
	}
	if a.dryRun {
		return "would switch", nil
	}
	after, err := a.generationState()
	if err != nil {
		return "", err
	}
	if after == before {
		a.say("switched %s: generation unchanged", a.configName())
		return "generation unchanged", nil
	}
	detail := a.describeGeneration(after)
	a.say("switched %s to %s", a.configName(), detail)
	return detail, nil
}

// buildOnly builds the activation package without activating it.
func (a *App) buildOnly() (string, error) {
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

func (a *App) generationState() (sources.GenerationState, error) {
	return sources.ReadGenerationState(a.home, a.env.Getenv)
}

// switchFailure decides what a non-zero nh exit means. Only a failure
// that left the active generation where it was is a plain failure the
// caller may restore from; a changed or unreadable generation is reported
// as activated, so the edited files are kept as its source.
func (a *App) switchFailure(before sources.GenerationState, berr, err error) error {
	after, aerr := a.generationState()
	switch {
	case berr != nil:
		return &activatedError{cause: err, generation: "the generation before the switch cannot be read: " + berr.Error()}
	case aerr != nil:
		return &activatedError{cause: err, generation: "the active generation cannot be read: " + aerr.Error()}
	case after != before:
		return &activatedError{cause: err, generation: a.describeGeneration(after) + " is now active"}
	}
	return err
}

// describeGeneration names a generation by number when the profile link
// carries one, else by store path.
func (a *App) describeGeneration(s sources.GenerationState) string {
	if n := sources.GenerationNumber(a.home, a.env.Getenv); n > 0 {
		return fmt.Sprintf("generation %d", n)
	}
	if s.Current != "" {
		return s.Current
	}
	return s.Profile
}

// diffAgainstCurrent shows what a built generation adds and removes
// relative to the active one.
func (a *App) diffAgainstCurrent(built string) {
	current, err := a.currentGeneration()
	if err != nil {
		return
	}
	a.diffGenerations(current, built)
}

// diffGenerations shows what built adds and removes relative to current,
// when nvd is available.
func (a *App) diffGenerations(current, built string) {
	if current == built {
		return
	}
	nvd := a.toolBin("nvd")
	if err := a.runner.Do(cmdOf(nvd, "diff", current, built)); err != nil {
		a.say("nvd diff unavailable: %v", err)
	}
}
