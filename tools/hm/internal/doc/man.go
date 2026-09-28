// SPDX-License-Identifier: GPL-3.0-or-later

package doc

import (
	"fmt"
	"strings"
)

// Man renders the hm(1) manual page in roff.
func Man(version, date string) string {
	var b strings.Builder
	fmt.Fprintf(&b, ".TH HM 1 \"%s\" \"%s %s\" \"User Commands\"\n", date, Name, roff(version))
	b.WriteString(".SH NAME\n")
	fmt.Fprintf(&b, "%s \\- %s\n", Name, roff(Summary))
	b.WriteString(".SH SYNOPSIS\n")
	fmt.Fprintf(&b, ".B %s\n[\\fB\\-\\-flake\\fR \\fIPATH\\fR] [\\fB\\-\\-dry\\-run\\fR] [\\fB\\-\\-no\\-pager\\fR]\n.I COMMAND\n[\\fIOPTIONS\\fR] [\\fIARGS\\fR]\n", Name)
	b.WriteString(".SH DESCRIPTION\n")
	for i, p := range Overview() {
		if i > 0 {
			b.WriteString(".PP\n")
		}
		b.WriteString(roffPara(p))
	}
	b.WriteString(".SH GLOBAL OPTIONS\n")
	manFlags(&b, GlobalFlags())
	b.WriteString(".SH COMMANDS\n")
	for _, c := range visibleCommands() {
		manCommand(&b, c)
	}
	b.WriteString(".SH FILES\nPaths are relative to the flake.\n")
	for _, f := range Files() {
		fmt.Fprintf(&b, ".TP\n.I %s\n%s", roff(f.Path), roffPara(f.Help))
	}
	b.WriteString(".SH ENVIRONMENT\n")
	for _, e := range Environment() {
		fmt.Fprintf(&b, ".TP\n.B %s\n%s", e.Name, roffPara(e.Help))
	}
	b.WriteString(".SH EXIT STATUS\n")
	for _, e := range ExitCodes() {
		fmt.Fprintf(&b, ".TP\n.B %d\n%s", e.Code, roffPara(e.Meaning))
	}
	b.WriteString(".SH EXAMPLES\n")
	for _, e := range WorkedExamples() {
		fmt.Fprintf(&b, ".TP\n.B %s\n%s", roff(e.Command), roffPara(e.Help))
	}
	b.WriteString(".SH SEE ALSO\n.BR nh (1),\n.BR mvs (1),\n.BR git (1),\n.BR nix (1)\n")
	return b.String()
}

func manCommand(b *strings.Builder, c Command) {
	fmt.Fprintf(b, ".SS %s\n", c.Name)
	fmt.Fprintf(b, ".B %s\n", roff(Synopsis(c)))
	fmt.Fprintf(b, ".PP\n%s", roffPara(strings.ToUpper(c.Summary[:1])+c.Summary[1:]+"."))
	for _, p := range c.Description {
		fmt.Fprintf(b, ".PP\n%s", roffPara(p))
	}
	if len(c.Flags) > 0 {
		b.WriteString(".PP\nOptions:\n.RS\n")
		manFlags(b, c.Flags)
		b.WriteString(".RE\n")
	}
	if len(c.Examples) > 0 {
		b.WriteString(".PP\nExamples:\n.RS\n")
		for _, e := range c.Examples {
			fmt.Fprintf(b, ".TP\n.B %s\n%s", roff(e.Command), roffPara(e.Help))
		}
		b.WriteString(".RE\n")
	}
}

func manFlags(b *strings.Builder, flags []Flag) {
	for _, f := range flags {
		b.WriteString(".TP\n")
		if f.Arg != "" {
			fmt.Fprintf(b, ".BI \\-\\-%s \" %s\"\n", roff(f.Name), roff(f.Arg))
		} else {
			fmt.Fprintf(b, ".B \\-\\-%s\n", roff(f.Name))
		}
		b.WriteString(roffPara(flagHelp(f)))
	}
}

// roffPara escapes a paragraph and wraps it at Width columns; roff joins
// the lines again, and a continuation line that would start with a dot or
// a quote is guarded so it is not read as a request.
func roffPara(s string) string {
	var b strings.Builder
	for _, line := range strings.Split(strings.TrimSuffix(Wrap(roff(s), Width, ""), "\n"), "\n") {
		if strings.HasPrefix(line, ".") || strings.HasPrefix(line, "'") {
			line = `\&` + line
		}
		b.WriteString(line + "\n")
	}
	return b.String()
}

// roff escapes text for the man page: backslashes, hyphens and a leading
// dot or quote, which roff would otherwise treat as a request.
func roff(s string) string {
	s = strings.ReplaceAll(s, `\`, `\e`)
	s = strings.ReplaceAll(s, "-", `\-`)
	if strings.HasPrefix(s, ".") || strings.HasPrefix(s, "'") {
		s = `\&` + s
	}
	return s
}
