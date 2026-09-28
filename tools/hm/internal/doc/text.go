// SPDX-License-Identifier: GPL-3.0-or-later

package doc

import (
	"fmt"
	"strings"
)

// Width is the column at which plain text is wrapped.
const Width = 78

// Wrap breaks text into lines no longer than width, each prefixed with
// indent.
func Wrap(text string, width int, indent string) string {
	var b strings.Builder
	line := indent
	for _, word := range strings.Fields(text) {
		if len(line) > len(indent) && len(line)+1+len(word) > width {
			b.WriteString(line)
			b.WriteByte('\n')
			line = indent
		}
		if len(line) > len(indent) {
			line += " "
		}
		line += word
	}
	if len(line) > len(indent) {
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String()
}

// Synopsis renders "hm NAME [flags] ARGS" for a command, or the synopsis
// the command spells out itself.
func Synopsis(c Command) string {
	if c.Synopsis != "" {
		return c.Synopsis
	}
	parts := []string{Name, c.Name}
	for _, f := range c.Flags {
		if f.Arg != "" {
			parts = append(parts, fmt.Sprintf("[--%s %s]", f.Name, f.Arg))
		} else {
			parts = append(parts, "[--"+f.Name+"]")
		}
	}
	if c.Args != "" {
		parts = append(parts, c.Args)
	}
	return strings.Join(parts, " ")
}

func flagLabel(f Flag) string {
	label := "--" + f.Name
	if f.Arg != "" {
		label += " " + f.Arg
	}
	return label
}

func flagHelp(f Flag) string {
	help := f.Help
	if len(f.Values) > 0 {
		help += " (" + strings.Join(f.Values, ", ") + ")"
	}
	if f.Default != "" {
		help += " [default: " + f.Default + "]"
	}
	return help
}

func renderFlags(b *strings.Builder, flags []Flag) {
	width := 0
	for _, f := range flags {
		if l := len(flagLabel(f)); l > width {
			width = l
		}
	}
	for _, f := range flags {
		label := flagLabel(f)
		indent := strings.Repeat(" ", width+6)
		text := Wrap(flagHelp(f), Width, indent)
		fmt.Fprintf(b, "  %-*s  %s", width, label, strings.TrimPrefix(text, indent))
	}
}

func renderExamples(b *strings.Builder, examples []Example) {
	width := 0
	for _, e := range examples {
		if len(e.Command) > width {
			width = len(e.Command)
		}
	}
	for _, e := range examples {
		if width <= 44 {
			fmt.Fprintf(b, "  %-*s  %s\n", width, e.Command, e.Help)
		} else {
			fmt.Fprintf(b, "  %s\n      %s\n", e.Command, e.Help)
		}
	}
}

// usage renders the Usage line, continuing long synopses on indented
// lines without splitting a bracketed group.
func usage(synopsis string) string {
	var b strings.Builder
	const prefix = "Usage: "
	line := prefix
	depth := 0
	start := 0
	var tokens []string
	for i, r := range synopsis {
		switch r {
		case '[':
			depth++
		case ']':
			depth--
		case ' ':
			if depth == 0 {
				tokens = append(tokens, synopsis[start:i])
				start = i + 1
			}
		}
	}
	tokens = append(tokens, synopsis[start:])
	for _, tok := range tokens {
		if len(line) > len(prefix) && len(line)+1+len(tok) > Width {
			b.WriteString(line + "\n")
			line = strings.Repeat(" ", len(prefix))
		}
		if len(line) > len(prefix) {
			line += " "
		}
		line += tok
	}
	return b.String() + line + "\n"
}

// Help renders `hm COMMAND --help`.
func Help(c Command) string {
	var b strings.Builder
	b.WriteString(usage(Synopsis(c)) + "\n")
	b.WriteString(strings.ToUpper(c.Summary[:1]) + c.Summary[1:] + ".\n")
	for _, p := range c.Description {
		b.WriteByte('\n')
		b.WriteString(Wrap(p, Width, ""))
	}
	if len(c.Flags) > 0 {
		b.WriteString("\nOptions:\n")
		renderFlags(&b, c.Flags)
	}
	var names []string
	for _, f := range GlobalFlags() {
		names = append(names, flagLabel(f))
	}
	b.WriteByte('\n')
	b.WriteString(Wrap("Global options: "+strings.Join(names, ", ")+" (see hm --help)", Width, ""))
	if len(c.Examples) > 0 {
		b.WriteString("\nExamples:\n")
		renderExamples(&b, c.Examples)
	}
	return b.String()
}

// TopHelp renders `hm --help`.
func TopHelp(version string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Usage: %s [--flake PATH] [--dry-run] [--no-pager] COMMAND [OPTIONS] [ARGS]\n\n", Name)
	fmt.Fprintf(&b, "%s %s: %s.\n\nCommands:\n", Name, version, Summary)
	width := 0
	visible := visibleCommands()
	for _, c := range visible {
		if l := len(c.Name + " " + c.Args); l > width {
			width = l
		}
	}
	for _, c := range visible {
		fmt.Fprintf(&b, "  %-*s  %s\n", width, strings.TrimSpace(c.Name+" "+c.Args), c.Summary)
	}
	b.WriteString("\nGlobal options:\n")
	renderFlags(&b, GlobalFlags())
	b.WriteString("\nExamples:\n")
	for _, e := range WorkedExamples() {
		fmt.Fprintf(&b, "  %s\n", e.Command)
		b.WriteString(Wrap(e.Help, Width, "      "))
	}
	fmt.Fprintf(&b, "\nRun '%s COMMAND --help' for one command, '%s help' or 'man %s' for the manual.\n", Name, Name, Name)
	return b.String()
}

func visibleCommands() []Command {
	var out []Command
	for _, c := range Commands() {
		if !c.Hidden {
			out = append(out, c)
		}
	}
	return out
}

// Manual renders the whole manual as plain text, the same content as the
// man page, for hm help and for machines without man.
func Manual(version string) string {
	var b strings.Builder
	section := func(title string) {
		fmt.Fprintf(&b, "\n%s\n", title)
	}
	fmt.Fprintf(&b, "HM(1)                        %s %s\n", Name, version)
	section("NAME")
	fmt.Fprintf(&b, "  %s - %s\n", Name, Summary)
	section("SYNOPSIS")
	fmt.Fprintf(&b, "  %s [--flake PATH] [--dry-run] [--no-pager] COMMAND [OPTIONS] [ARGS]\n", Name)
	section("DESCRIPTION")
	for i, p := range Overview() {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(Wrap(p, Width, "  "))
	}
	section("GLOBAL OPTIONS")
	renderFlags(&b, GlobalFlags())
	section("COMMANDS")
	for _, c := range visibleCommands() {
		fmt.Fprintf(&b, "\n  %s\n", Synopsis(c))
		fmt.Fprintf(&b, "    %s.\n", strings.ToUpper(c.Summary[:1])+c.Summary[1:])
		for _, p := range c.Description {
			b.WriteByte('\n')
			b.WriteString(Wrap(p, Width, "    "))
		}
		if len(c.Flags) > 0 {
			b.WriteByte('\n')
			var inner strings.Builder
			renderFlags(&inner, c.Flags)
			b.WriteString(indentBlock(inner.String(), "  "))
		}
		if len(c.Examples) > 0 {
			b.WriteString("\n    Examples:\n")
			var inner strings.Builder
			renderExamples(&inner, c.Examples)
			b.WriteString(indentBlock(inner.String(), "    "))
		}
	}
	section("FILES")
	for _, f := range Files() {
		fmt.Fprintf(&b, "  %s\n", f.Path)
		b.WriteString(Wrap(f.Help, Width, "      "))
	}
	section("ENVIRONMENT")
	for _, e := range Environment() {
		fmt.Fprintf(&b, "  %s\n", e.Name)
		b.WriteString(Wrap(e.Help, Width, "      "))
	}
	section("EXIT STATUS")
	b.WriteString(manualExitStatus())
	section("EXAMPLES")
	for _, e := range WorkedExamples() {
		fmt.Fprintf(&b, "  %s\n", e.Command)
		b.WriteString(Wrap(e.Help, Width, "      "))
	}
	section("SEE ALSO")
	b.WriteString("  nh(1), mvs(1), git(1), nix(1)\n")
	return b.String()
}

func manualExitStatus() string {
	var b strings.Builder
	for _, e := range ExitCodes() {
		text := Wrap(e.Meaning, Width, "     ")
		fmt.Fprintf(&b, "  %d  %s", e.Code, strings.TrimLeft(text, " "))
	}
	return b.String()
}

func indentBlock(text, indent string) string {
	var b strings.Builder
	for _, line := range strings.Split(strings.TrimSuffix(text, "\n"), "\n") {
		if line == "" {
			b.WriteByte('\n')
			continue
		}
		b.WriteString(indent + line + "\n")
	}
	return b.String()
}
