// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"text/tabwriter"
)

// page renders long output through the pager when stdout is a terminal.
func (a *App) page(render func(w io.Writer) error) error {
	var buf bytes.Buffer
	if err := render(&buf); err != nil {
		return err
	}
	pager := a.pager()
	if pager == "" {
		_, err := a.out.Write(buf.Bytes())
		return err
	}
	cmd := exec.Command("sh", "-c", pager)
	cmd.Stdin = &buf
	cmd.Stdout, cmd.Stderr = a.out, a.errOut
	if err := cmd.Run(); err != nil {
		_, werr := a.out.Write(buf.Bytes())
		return werr
	}
	return nil
}

// pager returns the pager command line, or "" when output is not paged:
// --no-pager, then HM_PAGER, then PAGER, then less -FRX.
func (a *App) pager() string {
	if a.noPager || !a.terminal() {
		return ""
	}
	for _, name := range []string{"HM_PAGER", "PAGER"} {
		if v, set := lookupEnv(a.env.Getenv, name); set {
			return strings.TrimSpace(v)
		}
	}
	if _, err := exec.LookPath("less"); err != nil {
		return ""
	}
	return "less -FRX"
}

func lookupEnv(getenv func(string) string, name string) (string, bool) {
	if getenv == nil {
		return os.LookupEnv(name)
	}
	v := getenv(name)
	return v, v != ""
}

// color reports whether output may carry ANSI styling.
func (a *App) color() bool {
	return a.terminal() && a.env.Getenv("NO_COLOR") == ""
}

func (a *App) bold(s string) string {
	if a.color() {
		return "\x1b[1m" + s + "\x1b[0m"
	}
	return s
}

// table writes aligned columns.
type table struct {
	w *tabwriter.Writer
}

func newTable(w io.Writer) *table {
	return &table{w: tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)}
}

func (t *table) row(cells ...string) {
	fmt.Fprintln(t.w, strings.Join(cells, "\t"))
}

func (t *table) flush() {
	_ = t.w.Flush()
}
