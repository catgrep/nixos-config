// SPDX-License-Identifier: GPL-3.0-or-later

// Package txn makes one hm run a transaction around one switch.
//
// A run takes an exclusive lock file, captures the bytes and hash of every
// file it may change, writes each file only after confirming nothing else
// changed it in the meantime (a temporary file renamed into place, so a
// crash leaves the old file intact), restores the captured files that still
// hold what it wrote when a step fails before a generation exists, and
// records what happened in a JSON journal under the repository's .git
// directory.
package txn

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Outcomes recorded in the journal.
const (
	OutcomeOK           = "ok"
	OutcomeFailed       = "failed"
	OutcomeKept         = "kept"
	OutcomeUnrestored   = "unrestored"
	OutcomeCommitFailed = "commit-failed"
)

// Journal is the record of one run, written after every step.
type Journal struct {
	Command  []string          `json:"command"`
	Started  time.Time         `json:"started"`
	Root     string            `json:"root"`
	Files    map[string]string `json:"files"`
	Steps    []Step            `json:"steps"`
	Outcome  string            `json:"outcome,omitempty"`
	Detail   string            `json:"detail,omitempty"`
	Finished *time.Time        `json:"finished,omitempty"`
}

// Step is a named point the run reached.
type Step struct {
	Name string    `json:"name"`
	At   time.Time `json:"at"`
}

// Resolved reports whether the run ended in a state that needs no attention:
// it finished, and every file it captured is back to what it was or was
// deliberately kept for a generation that exists.
func (j *Journal) Resolved() bool {
	return j.Finished != nil && j.Outcome != OutcomeKept && j.Outcome != OutcomeUnrestored
}

// LastStep returns the name of the last step reached, or "start".
func (j *Journal) LastStep() string {
	if len(j.Steps) == 0 {
		return "start"
	}
	return j.Steps[len(j.Steps)-1].Name
}

// LockedError reports that another hm holds the lock.
type LockedError struct {
	Path string
	PID  int
}

func (e *LockedError) Error() string {
	return fmt.Sprintf("another hm (pid %d) holds %s", e.PID, e.Path)
}

// UnresolvedError reports a previous run that finished badly or not at all.
type UnresolvedError struct {
	Path    string
	Journal *Journal
}

func (e *UnresolvedError) Error() string {
	j := e.Journal
	state := "did not finish"
	switch {
	case j.Finished == nil:
	case j.Outcome == OutcomeUnrestored:
		state = "could not restore every file"
	default:
		state = "left edited files behind"
	}
	return fmt.Sprintf("a previous run (%s, %s) %s at step %s; check the files it lists and remove %s to acknowledge",
		strings.Join(j.Command, " "), j.Started.Format(time.RFC3339), state, j.LastStep(), e.Path)
}

// ConflictError reports that a captured file changed under hm.
type ConflictError struct {
	Path string
}

func (e *ConflictError) Error() string {
	return fmt.Sprintf("%s changed while hm was running; nothing was written", e.Path)
}

type captured struct {
	orig    []byte
	existed bool
	mode    os.FileMode
	current string
}

// start is the hash the file had when it was captured, "" when it did not
// exist.
func (c *captured) start() string {
	if !c.existed {
		return ""
	}
	return Hash(c.orig)
}

// restore puts the file back to its captured content, removing it when it
// did not exist.
func (c *captured) restore(path string) error {
	if !c.existed {
		return os.Remove(path)
	}
	return writeAtomic(path, c.orig, c.mode)
}

// Txn is one run.
type Txn struct {
	root        string
	lockPath    string
	journalPath string
	journal     *Journal
	files       map[string]*captured
	now         func() time.Time
}

// Begin takes the lock under gitDir, refuses to start on top of an
// unresolved run, and opens the journal.
func Begin(root, gitDir string, command []string, now func() time.Time) (*Txn, error) {
	if now == nil {
		now = time.Now
	}
	lockPath := filepath.Join(gitDir, "hm.lock")
	if err := acquire(lockPath); err != nil {
		return nil, err
	}
	release := func() { _ = os.Remove(lockPath) }
	if unresolved, err := Unresolved(gitDir); err != nil {
		release()
		return nil, err
	} else if len(unresolved) > 0 {
		release()
		path := unresolved[0]
		j, err := ReadJournal(path)
		if err != nil {
			return nil, err
		}
		return nil, &UnresolvedError{Path: path, Journal: j}
	}
	t := &Txn{
		root:     root,
		lockPath: lockPath,
		files:    map[string]*captured{},
		now:      now,
		journal: &Journal{
			Command: command,
			Started: now().UTC(),
			Root:    root,
			Files:   map[string]string{},
		},
	}
	dir := filepath.Join(gitDir, "hm")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.release()
		return nil, err
	}
	t.journalPath = filepath.Join(dir, fmt.Sprintf("%s-%d.json", t.journal.Started.Format("20060102T150405Z"), os.Getpid()))
	if err := t.flush(); err != nil {
		t.release()
		return nil, err
	}
	return t, nil
}

func acquire(lockPath string) error {
	for attempt := 0; attempt < 2; attempt++ {
		f, err := os.OpenFile(lockPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
		if err == nil {
			_, werr := fmt.Fprintf(f, "%d\n", os.Getpid())
			return errors.Join(werr, f.Close())
		}
		if !errors.Is(err, os.ErrExist) {
			return err
		}
		pid, alive := lockHolder(lockPath)
		if alive {
			return &LockedError{Path: lockPath, PID: pid}
		}
		if err := os.Remove(lockPath); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return &LockedError{Path: lockPath}
}

// lockHolder reads the pid in the lock file and reports whether that
// process still exists. An unreadable pid counts as alive, so a lock is
// never removed on a guess.
func lockHolder(lockPath string) (int, bool) {
	data, err := os.ReadFile(lockPath)
	if err != nil {
		return 0, true
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid <= 0 {
		return 0, true
	}
	err = syscall.Kill(pid, 0)
	return pid, err == nil || errors.Is(err, syscall.EPERM)
}

func (t *Txn) release() {
	_ = os.Remove(t.lockPath)
}

// JournalPath is where this run's journal is written.
func (t *Txn) JournalPath() string {
	return t.journalPath
}

func (t *Txn) rel(path string) string {
	if r, err := filepath.Rel(t.root, path); err == nil && !strings.HasPrefix(r, "..") {
		return r
	}
	return path
}

func (t *Txn) flush() error {
	data, err := json.MarshalIndent(t.journal, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(t.journalPath, append(data, '\n'), 0o644)
}

// Capture records the current content of each path. A path that does not
// exist yet is captured as absent and removed again on restore.
func (t *Txn) Capture(paths ...string) error {
	for _, path := range paths {
		if _, done := t.files[path]; done {
			continue
		}
		c := &captured{mode: 0o644}
		data, err := os.ReadFile(path)
		switch {
		case err == nil:
			info, serr := os.Stat(path)
			if serr != nil {
				return serr
			}
			c.orig, c.existed, c.mode = data, true, info.Mode().Perm()
			c.current = Hash(data)
		case errors.Is(err, os.ErrNotExist):
		default:
			return err
		}
		t.files[path] = c
		t.journal.Files[t.rel(path)] = c.current
	}
	return t.flush()
}

// Write replaces path with data after checking that its content is still
// what hm last saw.
func (t *Txn) Write(path string, data []byte) error {
	c, ok := t.files[path]
	if !ok {
		return fmt.Errorf("%s was not captured before writing", path)
	}
	if err := t.check(path, c); err != nil {
		return err
	}
	if err := writeAtomic(path, data, c.mode); err != nil {
		return err
	}
	c.current = Hash(data)
	return nil
}

// Adopt accepts the current content of path as hm's own, for a file that a
// program hm ran (mvs, nix) rewrote in place.
func (t *Txn) Adopt(path string) error {
	c, ok := t.files[path]
	if !ok {
		return fmt.Errorf("%s was not captured before adopting", path)
	}
	c.current = hashFile(path)
	return nil
}

func (t *Txn) check(path string, c *captured) error {
	if hashFile(path) != c.current {
		return &ConflictError{Path: t.rel(path)}
	}
	return nil
}

// Restore puts every captured file that still holds what hm last wrote,
// or last saw, back to its starting content. A file whose content is
// neither was changed by something else since; it is left as found and
// returned in kept, so the caller can name it and leave the run
// unresolved. Both lists are relative to the repository root.
func (t *Txn) Restore() (restored, kept []string, err error) {
	var errs []error
	for _, path := range t.paths() {
		c := t.files[path]
		now := hashFile(path)
		if now != c.current {
			kept = append(kept, t.rel(path))
			continue
		}
		if now == c.start() {
			continue
		}
		if err := c.restore(path); err != nil {
			errs = append(errs, err)
			continue
		}
		c.current = c.start()
		restored = append(restored, t.rel(path))
	}
	return restored, kept, errors.Join(errs...)
}

// Changed lists the captured files whose content differs from the start of
// the run, relative to the repository root.
func (t *Txn) Changed() []string {
	var out []string
	for _, path := range t.paths() {
		if hashFile(path) != t.files[path].start() {
			out = append(out, t.rel(path))
		}
	}
	return out
}

// Verify lists the captured files whose content differs from what hm last
// wrote or adopted, relative to the repository root.
func (t *Txn) Verify() []string {
	var out []string
	for _, path := range t.paths() {
		if hashFile(path) != t.files[path].current {
			out = append(out, t.rel(path))
		}
	}
	return out
}

func (t *Txn) paths() []string {
	paths := make([]string, 0, len(t.files))
	for p := range t.files {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	return paths
}

// Step records that the run reached a named point.
func (t *Txn) Step(name string) error {
	t.journal.Steps = append(t.journal.Steps, Step{Name: name, At: t.now().UTC()})
	return t.flush()
}

// Finish records the outcome, writes the journal and releases the lock.
func (t *Txn) Finish(outcome, detail string) error {
	finished := t.now().UTC()
	t.journal.Outcome = outcome
	t.journal.Detail = detail
	t.journal.Finished = &finished
	err := t.flush()
	t.release()
	return err
}

// Hash returns the hex SHA-256 of data.
func Hash(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// hashFile returns the hash of the file, or "" when it does not exist.
func hashFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return Hash(data)
}

// writeAtomic writes data to a temporary file next to path and renames it
// into place.
func writeAtomic(path string, data []byte, mode os.FileMode) error {
	dir, base := filepath.Split(path)
	if dir == "" {
		dir = "."
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, "."+base+".hm-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	cleanup := func(err error) error {
		_ = os.Remove(tmp)
		return err
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		return cleanup(err)
	}
	if err := f.Chmod(mode); err != nil {
		_ = f.Close()
		return cleanup(err)
	}
	if err := f.Close(); err != nil {
		return cleanup(err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return cleanup(err)
	}
	return nil
}

// ReadJournal decodes one journal file.
func ReadJournal(path string) (*Journal, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var j Journal
	if err := json.Unmarshal(data, &j); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return &j, nil
}

// Journals lists the journal files under gitDir, oldest first.
func Journals(gitDir string) ([]string, error) {
	entries, err := filepath.Glob(filepath.Join(gitDir, "hm", "*.json"))
	if err != nil {
		return nil, err
	}
	sort.Strings(entries)
	return entries, nil
}

// Unresolved lists the journals of runs that did not finish or left edited
// files behind.
func Unresolved(gitDir string) ([]string, error) {
	paths, err := Journals(gitDir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, path := range paths {
		j, err := ReadJournal(path)
		if err != nil {
			return nil, err
		}
		if !j.Resolved() {
			out = append(out, path)
		}
	}
	return out, nil
}

// Last returns the most recent journal and its path, or nil when there is
// none.
func Last(gitDir string) (*Journal, string, error) {
	paths, err := Journals(gitDir)
	if err != nil || len(paths) == 0 {
		return nil, "", err
	}
	path := paths[len(paths)-1]
	j, err := ReadJournal(path)
	return j, path, err
}
