// SPDX-License-Identifier: GPL-3.0-or-later

package run

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
)

// Mvs drives `mvs lock` and `mvs query` against one lock file.
type Mvs struct {
	r    *Runner
	bin  []string
	lock string
}

// NewMvs returns an Mvs that runs bin (the program and any leading
// arguments, such as `nix run flake#mvs --`) against the lock file.
func NewMvs(r *Runner, bin []string, lock string) Mvs {
	return Mvs{r: r, bin: bin, lock: lock}
}

// WithLock returns a copy that operates on another lock file.
func (m Mvs) WithLock(path string) Mvs {
	m.lock = path
	return m
}

func (m Mvs) cmd(args ...string) Cmd {
	all := append([]string{}, m.bin[1:]...)
	all = append(all, "--json", "--file", m.lock)
	all = append(all, args...)
	return Cmd{Prog: m.bin[0], Args: all}
}

func (m Mvs) json(v any, args ...string) error {
	out, err := m.r.Output(m.cmd(args...))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(out, v); err != nil {
		return fmt.Errorf("mvs %s: unexpected output: %w", args[0], err)
	}
	return nil
}

// Pin is one lock entry.
type Pin struct {
	Version    string `json:"version"`
	Rev        string `json:"rev"`
	Label      string `json:"label"`
	Date       string `json:"date"`
	Constraint string `json:"constraint"`
}

// Add pins spec (ATTR or ATTR@VERSION) and returns the attribute and pin.
func (m Mvs) Add(spec string) (string, Pin, error) {
	var out struct {
		Attr string `json:"attr"`
		Pin  Pin    `json:"pin"`
	}
	err := m.json(&out, "lock", "add", spec)
	return out.Attr, out.Pin, err
}

// Rm removes the pin for attr and returns what it was.
func (m Mvs) Rm(attr string) (Pin, error) {
	var out struct {
		Removed Pin `json:"removed"`
	}
	err := m.json(&out, "lock", "rm", attr)
	return out.Removed, err
}

// Moved is one pin that `mvs lock update` advanced.
type Moved struct {
	Attr string `json:"attr"`
	From struct {
		Version string `json:"version"`
		Label   string `json:"label"`
	} `json:"from"`
	To struct {
		Version string `json:"version"`
		Label   string `json:"label"`
	} `json:"to"`
}

// Update moves attr to the newest indexed revision its constraint allows.
func (m Mvs) Update(attr string) ([]Moved, error) {
	var out struct {
		Moved []Moved `json:"moved"`
	}
	err := m.json(&out, "lock", "update", attr)
	return out.Moved, err
}

// PinStatus is one row of `mvs lock status`.
type PinStatus struct {
	Attr           string `json:"attr"`
	Version        string `json:"version"`
	Latest         string `json:"latest"`
	LatestLabel    string `json:"latest_label"`
	Date           string `json:"date"`
	VersionsBehind int    `json:"versions_behind"`
	DaysBehind     int    `json:"days_behind"`
}

// Status reports how far behind each pin is.
func (m Mvs) Status() ([]PinStatus, error) {
	var out struct {
		Pins []PinStatus `json:"pins"`
	}
	err := m.json(&out, "lock", "status")
	return out.Pins, err
}

// Minimize is the result of `mvs lock minimize --check`.
type Minimize struct {
	Before int               `json:"before"`
	After  int               `json:"after"`
	Pins   int               `json:"pins"`
	Moved  []json.RawMessage `json:"moved"`
	Why    string            `json:"why"`
}

// MinimizeCheck reports whether the pins could share fewer revisions. mvs
// exits non-zero when they could, so that exit is not an error here.
func (m Mvs) MinimizeCheck() (Minimize, error) {
	var out Minimize
	raw, err := m.r.Output(m.cmd("lock", "minimize", "--check"))
	var exit *ExitError
	if err != nil && !(errors.As(err, &exit) && exit.Code == 1 && len(raw) > 0) {
		return out, err
	}
	if jerr := json.Unmarshal(raw, &out); jerr != nil {
		return out, fmt.Errorf("mvs lock minimize: unexpected output: %w", jerr)
	}
	return out, nil
}

// Match is one row of `mvs query search`.
type Match struct {
	Attr    string `json:"attr"`
	Version string `json:"version"`
	Date    string `json:"date"`
	Label   string `json:"label"`
	Gone    bool   `json:"gone"`
}

// Search lists attributes matching pattern (a substring or glob).
func (m Mvs) Search(pattern string, limit int) ([]Match, error) {
	var out struct {
		Matches []Match `json:"matches"`
	}
	err := m.json(&out, "query", "search", "--limit", strconv.Itoa(limit), pattern)
	return out.Matches, err
}
