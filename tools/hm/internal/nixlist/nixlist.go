// SPDX-License-Identifier: GPL-3.0-or-later

// Package nixlist reads and writes the Nix list files hm owns.
//
// The grammar is deliberately small: optional comment lines, an opening
// bracket on its own line, one double-quoted string per line, comments and
// blank lines between entries, and a closing bracket on its own line.
// Anything else is an error that names the line, so a hand edit that hm
// could not reproduce is rejected before Nix ever sees the file.
package nixlist

import (
	"bytes"
	"fmt"
	"os"
	"sort"
	"strings"
)

type itemKind int

const (
	kindEntry itemKind = iota
	kindComment
	kindBlank
)

type item struct {
	kind itemKind
	text string
}

// List is a parsed list file: the comment lines above the opening bracket
// and the entries, comments and blank lines between the brackets.
type List struct {
	header []string
	items  []item
}

// Error is a parse error carrying the file name and line number.
type Error struct {
	Name string
	Line int
	Msg  string
}

func (e *Error) Error() string {
	return fmt.Sprintf("%s:%d: %s", e.Name, e.Line, e.Msg)
}

// Empty returns a list with no entries and the given header comment lines.
func Empty(header ...string) *List {
	return &List{header: append([]string(nil), header...)}
}

// Read parses the file at path.
func Read(path string) (*List, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(path, data)
}

// Parse parses data, using name in error messages.
func Parse(name string, data []byte) (*List, error) {
	p := parser{name: name, list: &List{}}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(data) == 0 {
		lines = nil
	}
	for i, raw := range lines {
		if err := p.line(i+1, raw); err != nil {
			return nil, err
		}
	}
	if p.state != stateDone {
		return nil, &Error{name, len(lines) + 1, `missing closing "]"`}
	}
	return p.list, nil
}

type parseState int

const (
	stateHeader parseState = iota
	stateBody
	stateDone
)

type parser struct {
	name  string
	state parseState
	list  *List
	seen  map[string]bool
}

func (p *parser) fail(line int, msg string) error {
	return &Error{p.name, line, msg}
}

func (p *parser) line(n int, raw string) error {
	text := strings.TrimSpace(raw)
	switch p.state {
	case stateHeader:
		return p.headerLine(n, text)
	case stateBody:
		return p.bodyLine(n, text)
	default:
		if text != "" {
			return p.fail(n, `unexpected content after the closing "]"`)
		}
		return nil
	}
}

func (p *parser) headerLine(n int, text string) error {
	switch {
	case text == "" || strings.HasPrefix(text, "#"):
		p.list.header = append(p.list.header, text)
	case text == "[":
		p.state = stateBody
	case text == "[ ]" || text == "[]":
		p.state = stateDone
	default:
		return p.fail(n, `expected a comment or the opening "["`)
	}
	return nil
}

func (p *parser) bodyLine(n int, text string) error {
	switch {
	case text == "":
		p.list.items = append(p.list.items, item{kind: kindBlank})
	case strings.HasPrefix(text, "#"):
		p.list.items = append(p.list.items, item{kind: kindComment, text: text})
	case text == "]":
		p.state = stateDone
	case len(text) >= 2 && text[0] == '"' && text[len(text)-1] == '"':
		value := text[1 : len(text)-1]
		if err := Validate(value); err != nil {
			return p.fail(n, err.Error())
		}
		if p.seen[value] {
			return p.fail(n, fmt.Sprintf("duplicate entry %q", value))
		}
		if p.seen == nil {
			p.seen = map[string]bool{}
		}
		p.seen[value] = true
		p.list.items = append(p.list.items, item{kind: kindEntry, text: value})
	default:
		return p.fail(n, `expected a quoted string, a comment or the closing "]"`)
	}
	return nil
}

// Validate reports whether value can be written as an entry: non-empty,
// and free of the characters that would change how Nix reads the string.
func Validate(value string) error {
	if value == "" {
		return fmt.Errorf("empty entry")
	}
	if i := strings.IndexAny(value, "\"\\$\n\t "); i >= 0 {
		return fmt.Errorf("entry %q contains %q, which hm does not write", value, value[i])
	}
	return nil
}

// Entries returns the entries in file order.
func (l *List) Entries() []string {
	var out []string
	for _, it := range l.items {
		if it.kind == kindEntry {
			out = append(out, it.text)
		}
	}
	return out
}

// Has reports whether value is an entry.
func (l *List) Has(value string) bool {
	for _, it := range l.items {
		if it.kind == kindEntry && it.text == value {
			return true
		}
	}
	return false
}

// Add inserts value before the first entry that sorts after it, keeping a
// comment block that introduces that entry attached to it. It reports
// false when value is already present.
func (l *List) Add(value string) bool {
	if l.Has(value) {
		return false
	}
	at := len(l.items)
	for i, it := range l.items {
		if it.kind == kindEntry && it.text > value {
			at = i
			for at > 0 && l.items[at-1].kind == kindComment {
				at--
			}
			break
		}
	}
	entry := item{kind: kindEntry, text: value}
	l.items = append(l.items[:at], append([]item{entry}, l.items[at:]...)...)
	return true
}

// Remove deletes value and reports whether it was present.
func (l *List) Remove(value string) bool {
	for i, it := range l.items {
		if it.kind == kindEntry && it.text == value {
			l.items = append(l.items[:i], l.items[i+1:]...)
			return true
		}
	}
	return false
}

// Sorted reports whether the entries are in lexical order.
func (l *List) Sorted() bool {
	return sort.StringsAreSorted(l.Entries())
}

// Bytes renders the list in the canonical layout hm writes.
func (l *List) Bytes() []byte {
	var b bytes.Buffer
	for _, h := range l.header {
		b.WriteString(h)
		b.WriteByte('\n')
	}
	b.WriteString("[\n")
	for _, it := range l.items {
		switch it.kind {
		case kindEntry:
			fmt.Fprintf(&b, "  \"%s\"\n", it.text)
		case kindComment:
			fmt.Fprintf(&b, "  %s\n", it.text)
		default:
			b.WriteByte('\n')
		}
	}
	b.WriteString("]\n")
	return b.Bytes()
}
