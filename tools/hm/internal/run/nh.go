// SPDX-License-Identifier: GPL-3.0-or-later

package run

import "strconv"

// Nh drives nh.
type Nh struct {
	r *Runner
}

// NewNh returns an Nh on r.
func NewNh(r *Runner) Nh {
	return Nh{r: r}
}

// HomeSwitch builds and activates the Home Manager configuration in flake.
func (n Nh) HomeSwitch(flake string) error {
	return n.r.Do(Cmd{Prog: "nh", Args: []string{"home", "switch", flake}})
}

// DarwinSwitch builds and activates the nix-darwin configuration in flake.
func (n Nh) DarwinSwitch(flake string) error {
	return n.r.Do(Cmd{Prog: "nh", Args: []string{"darwin", "switch", flake}})
}

// CleanUser removes old user generations, keeping at least keep.
func (n Nh) CleanUser(keep int) error {
	return n.r.Do(Cmd{Prog: "nh", Args: []string{"clean", "user", "--keep", strconv.Itoa(keep)}})
}
