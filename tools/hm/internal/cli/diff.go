// SPDX-License-Identifier: GPL-3.0-or-later

package cli

import (
	"fmt"
	"strings"
)

// contextLines is how many unchanged lines surround each hunk.
const contextLines = 3

type editOp struct {
	kind byte // ' ', '-', '+'
	text string
}

// unifiedDiff renders the change from a to b as a unified diff with three
// lines of context per hunk. The files hm owns are short, so the quadratic
// longest-common-subsequence is fine.
func unifiedDiff(name string, a, b []byte) string {
	if string(a) == string(b) {
		return ""
	}
	ops := editScript(lines(a), lines(b))
	var out strings.Builder
	fmt.Fprintf(&out, "--- a/%s\n+++ b/%s\n", name, name)
	oldLine, newLine := 1, 1
	for i := 0; i < len(ops); {
		if ops[i].kind == ' ' {
			oldLine++
			newLine++
			i++
			continue
		}
		start := max(i-contextLines, 0)
		end := i
		for end < len(ops) {
			if ops[end].kind != ' ' {
				end++
				continue
			}
			run := end
			for run < len(ops) && ops[run].kind == ' ' {
				run++
			}
			if run-end > 2*contextLines && run < len(ops) {
				end += contextLines
				break
			}
			if run == len(ops) {
				end = min(end+contextLines, len(ops))
				break
			}
			end = run
		}
		hunkOldStart, hunkNewStart := oldLine-(i-start), newLine-(i-start)
		oldCount, newCount := 0, 0
		var body strings.Builder
		for _, op := range ops[start:end] {
			body.WriteByte(op.kind)
			body.WriteString(op.text)
			body.WriteByte('\n')
			if op.kind != '+' {
				oldCount++
			}
			if op.kind != '-' {
				newCount++
			}
		}
		fmt.Fprintf(&out, "@@ -%d,%d +%d,%d @@\n%s", hunkOldStart, oldCount, hunkNewStart, newCount, body.String())
		for _, op := range ops[i:end] {
			if op.kind != '+' {
				oldLine++
			}
			if op.kind != '-' {
				newLine++
			}
		}
		i = end
	}
	return out.String()
}

// editScript returns the line operations that turn al into bl.
func editScript(al, bl []string) []editOp {
	n, m := len(al), len(bl)
	lcs := make([][]int, n+1)
	for i := range lcs {
		lcs[i] = make([]int, m+1)
	}
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if al[i] == bl[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else {
				lcs[i][j] = max(lcs[i+1][j], lcs[i][j+1])
			}
		}
	}
	var ops []editOp
	i, j := 0, 0
	for i < n || j < m {
		switch {
		case i < n && j < m && al[i] == bl[j]:
			ops = append(ops, editOp{' ', al[i]})
			i++
			j++
		case j < m && (i == n || lcs[i][j+1] >= lcs[i+1][j]):
			ops = append(ops, editOp{'+', bl[j]})
			j++
		default:
			ops = append(ops, editOp{'-', al[i]})
			i++
		}
	}
	return ops
}

func lines(data []byte) []string {
	s := strings.TrimSuffix(string(data), "\n")
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
