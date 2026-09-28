// SPDX-License-Identifier: GPL-3.0-or-later

package txn

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"
)

type repo struct {
	root, gitDir string
}

func newRepo(t *testing.T) repo {
	t.Helper()
	root := t.TempDir()
	gitDir := filepath.Join(root, ".git")
	if err := os.MkdirAll(gitDir, 0o755); err != nil {
		t.Fatal(err)
	}
	return repo{root, gitDir}
}

func (r repo) file(name string) string {
	return filepath.Join(r.root, name)
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func begin(t *testing.T, r repo) *Txn {
	t.Helper()
	tx, err := Begin(r.root, r.gitDir, []string{"hm", "add", "x"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	return tx
}

func TestWriteAndFinish(t *testing.T) {
	r := newRepo(t)
	write(t, r.file("list.nix"), "[\n]\n")
	tx := begin(t, r)
	if err := tx.Capture(r.file("list.nix"), r.file("new.nix")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Write(r.file("list.nix"), []byte("[\n  \"a\"\n]\n")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Write(r.file("new.nix"), []byte("[\n]\n")); err != nil {
		t.Fatal(err)
	}
	if got := tx.Changed(); !reflect.DeepEqual(got, []string{"list.nix", "new.nix"}) {
		t.Errorf("Changed = %v", got)
	}
	if got := tx.Verify(); len(got) != 0 {
		t.Errorf("Verify = %v, want none", got)
	}
	if err := tx.Step("switch"); err != nil {
		t.Fatal(err)
	}
	if err := tx.Finish(OutcomeOK, "generation 21"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(r.gitDir, "hm.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Error("lock file survived Finish")
	}
	j, path, err := Last(r.gitDir)
	if err != nil {
		t.Fatal(err)
	}
	if path != tx.JournalPath() {
		t.Errorf("Last path = %s, want %s", path, tx.JournalPath())
	}
	if j.Outcome != OutcomeOK || j.LastStep() != "switch" || !j.Resolved() {
		t.Errorf("journal = %+v", j)
	}
	if got := j.Files["new.nix"]; got != "" {
		t.Errorf("absent file captured with hash %q", got)
	}
	if got := j.Files["list.nix"]; got != Hash([]byte("[\n]\n")) {
		t.Errorf("list.nix hash = %q", got)
	}
	if got := read(t, r.file("list.nix")); got != "[\n  \"a\"\n]\n" {
		t.Errorf("list.nix = %q", got)
	}
}

func TestWriteDetectsConcurrentChange(t *testing.T) {
	r := newRepo(t)
	write(t, r.file("list.nix"), "[\n]\n")
	tx := begin(t, r)
	defer func() { _ = tx.Finish(OutcomeFailed, "") }()
	if err := tx.Capture(r.file("list.nix")); err != nil {
		t.Fatal(err)
	}
	write(t, r.file("list.nix"), "[\n  \"someone-else\"\n]\n")
	err := tx.Write(r.file("list.nix"), []byte("[\n  \"a\"\n]\n"))
	var conflict *ConflictError
	if !errors.As(err, &conflict) || conflict.Path != "list.nix" {
		t.Fatalf("err = %v, want ConflictError for list.nix", err)
	}
	if got := read(t, r.file("list.nix")); got != "[\n  \"someone-else\"\n]\n" {
		t.Errorf("conflicting write went through: %q", got)
	}
}

func TestRestore(t *testing.T) {
	r := newRepo(t)
	write(t, r.file("list.nix"), "[\n]\n")
	write(t, r.file("lock.json"), "{}\n")
	tx := begin(t, r)
	if err := tx.Capture(r.file("list.nix"), r.file("lock.json"), r.file("created.nix")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Write(r.file("list.nix"), []byte("[\n  \"a\"\n]\n")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Write(r.file("created.nix"), []byte("[\n]\n")); err != nil {
		t.Fatal(err)
	}
	// lock.json is rewritten by another program, as mvs does.
	write(t, r.file("lock.json"), "{\"pins\":1}\n")
	if err := tx.Adopt(r.file("lock.json")); err != nil {
		t.Fatal(err)
	}
	if got := tx.Verify(); len(got) != 0 {
		t.Errorf("Verify after Adopt = %v", got)
	}
	restored, err := tx.Restore()
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"created.nix", "list.nix", "lock.json"}; !reflect.DeepEqual(restored, want) {
		t.Errorf("restored = %v, want %v", restored, want)
	}
	if got := read(t, r.file("list.nix")); got != "[\n]\n" {
		t.Errorf("list.nix = %q after restore", got)
	}
	if got := read(t, r.file("lock.json")); got != "{}\n" {
		t.Errorf("lock.json = %q after restore", got)
	}
	if _, err := os.Stat(r.file("created.nix")); !errors.Is(err, os.ErrNotExist) {
		t.Error("created file survived restore")
	}
	if got := tx.Changed(); len(got) != 0 {
		t.Errorf("Changed after restore = %v", got)
	}
	if err := tx.Finish(OutcomeFailed, "build failed"); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyReportsEditAfterWrite(t *testing.T) {
	r := newRepo(t)
	write(t, r.file("list.nix"), "[\n]\n")
	tx := begin(t, r)
	defer func() { _ = tx.Finish(OutcomeOK, "") }()
	if err := tx.Capture(r.file("list.nix")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Write(r.file("list.nix"), []byte("[\n  \"a\"\n]\n")); err != nil {
		t.Fatal(err)
	}
	write(t, r.file("list.nix"), "[\n  \"a\"\n  \"b\"\n]\n")
	if got := tx.Verify(); !reflect.DeepEqual(got, []string{"list.nix"}) {
		t.Errorf("Verify = %v", got)
	}
}

func TestLockHeld(t *testing.T) {
	r := newRepo(t)
	tx := begin(t, r)
	defer func() { _ = tx.Finish(OutcomeOK, "") }()
	_, err := Begin(r.root, r.gitDir, []string{"hm"}, nil)
	var locked *LockedError
	if !errors.As(err, &locked) || locked.PID != os.Getpid() {
		t.Fatalf("err = %v, want LockedError for pid %d", err, os.Getpid())
	}
}

func TestStaleLockIsReclaimed(t *testing.T) {
	r := newRepo(t)
	// A pid that cannot be running: the maximum allowed by the kernel plus one.
	write(t, filepath.Join(r.gitDir, "hm.lock"), strconv.Itoa(1<<22+7)+"\n")
	tx := begin(t, r)
	if err := tx.Finish(OutcomeOK, ""); err != nil {
		t.Fatal(err)
	}
}

func TestUnreadableLockIsNotReclaimed(t *testing.T) {
	r := newRepo(t)
	write(t, filepath.Join(r.gitDir, "hm.lock"), "not a pid\n")
	_, err := Begin(r.root, r.gitDir, []string{"hm"}, nil)
	var locked *LockedError
	if !errors.As(err, &locked) {
		t.Fatalf("err = %v, want LockedError", err)
	}
}

func TestUnresolvedRunBlocksTheNext(t *testing.T) {
	r := newRepo(t)
	write(t, r.file("list.nix"), "[\n]\n")
	clock := time.Date(2026, 9, 28, 3, 0, 0, 0, time.UTC)
	tx, err := Begin(r.root, r.gitDir, []string{"hm", "add", "x"}, func() time.Time { return clock })
	if err != nil {
		t.Fatal(err)
	}
	if err := tx.Capture(r.file("list.nix")); err != nil {
		t.Fatal(err)
	}
	if err := tx.Step("write"); err != nil {
		t.Fatal(err)
	}
	// Simulate a crash: the lock stays, the journal has no outcome.
	unresolved, err := Unresolved(r.gitDir)
	if err != nil || len(unresolved) != 1 {
		t.Fatalf("Unresolved = %v, %v", unresolved, err)
	}
	write(t, filepath.Join(r.gitDir, "hm.lock"), strconv.Itoa(1<<22+7)+"\n")
	_, err = Begin(r.root, r.gitDir, []string{"hm", "add", "y"}, nil)
	var unres *UnresolvedError
	if !errors.As(err, &unres) || unres.Journal.LastStep() != "write" {
		t.Fatalf("err = %v, want UnresolvedError at step write", err)
	}
	if _, err := os.Stat(filepath.Join(r.gitDir, "hm.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Error("refused Begin left the lock behind")
	}
	// Acknowledging by removing the journal lets the next run start.
	if err := os.Remove(unresolved[0]); err != nil {
		t.Fatal(err)
	}
	next := begin(t, r)
	if err := next.Finish(OutcomeOK, ""); err != nil {
		t.Fatal(err)
	}
}

func TestKeptOutcomeIsUnresolved(t *testing.T) {
	r := newRepo(t)
	tx := begin(t, r)
	if err := tx.Finish(OutcomeKept, "build failed; files kept"); err != nil {
		t.Fatal(err)
	}
	_, err := Begin(r.root, r.gitDir, []string{"hm"}, nil)
	var unres *UnresolvedError
	if !errors.As(err, &unres) {
		t.Fatalf("err = %v, want UnresolvedError", err)
	}
}

func TestWriteRequiresCapture(t *testing.T) {
	r := newRepo(t)
	tx := begin(t, r)
	defer func() { _ = tx.Finish(OutcomeOK, "") }()
	if err := tx.Write(r.file("list.nix"), []byte("[\n]\n")); err == nil {
		t.Fatal("Write of an uncaptured file succeeded")
	}
}
