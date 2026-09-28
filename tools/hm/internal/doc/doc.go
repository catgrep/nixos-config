// SPDX-License-Identifier: GPL-3.0-or-later

// Package doc describes every hm subcommand once. The --help text, the
// hm(1) man page and the shell completion scripts are all rendered from
// these structs, so they cannot disagree.
package doc

// Flag is one option of a command.
type Flag struct {
	Name    string
	Arg     string
	Default string
	Help    string
	Values  []string
}

// Example is one command line with the effect it has.
type Example struct {
	Command string
	Help    string
}

// Completion names how a command's positional argument is completed.
type Completion string

// Completion kinds.
const (
	CompleteNone  Completion = ""
	CompleteAttr  Completion = "attr"
	CompleteOwned Completion = "owned"
	CompleteWords Completion = "words"
	CompleteFile  Completion = "file"
	CompleteHelp  Completion = "command"
)

// Command is one subcommand.
type Command struct {
	Name        string
	Args        string
	Synopsis    string
	Summary     string
	Description []string
	Flags       []Flag
	Examples    []Example
	Complete    Completion
	Words       []string
	Hidden      bool
}

// EnvVar is one environment variable hm reads.
type EnvVar struct {
	Name string
	Help string
}

// ExitCode is one documented exit status.
type ExitCode struct {
	Code    int
	Meaning string
}

// File is one file hm reads or writes.
type File struct {
	Path string
	Help string
}

// Name is the program name.
const Name = "hm"

// Summary is the one-line description.
const Summary = "manage the packages of the Home Manager configuration"

// buildOnlyFlag is the --build-only flag add, rm, up and sync share.
func buildOnlyFlag() Flag {
	return Flag{Name: "build-only", Help: "do every step except the one that changes the machine: build the new generation with nix build and print its store path instead of activating it, or write and validate a tool list and print the hm sync command instead of running it; --commit is still allowed because the build proved the configuration"}
}

// commitFlag is the --commit flag add, rm and up share.
func commitFlag() Flag {
	return Flag{Name: "commit", Help: "commit the files hm changed with a generated subject such as \"home: add zizmor 1.30.1\""}
}

// GlobalFlags are accepted before or after the subcommand name.
func GlobalFlags() []Flag {
	return []Flag{
		{Name: "flake", Arg: "PATH", Default: "$NH_FLAKE", Help: "the repository that holds the flake and the lists hm owns"},
		{Name: "dry-run", Help: "print the commands hm would run and the diff it would write, and change nothing"},
		{Name: "no-pager", Help: "write long output straight to stdout"},
		{Name: "help", Help: "show help and exit"},
		{Name: "version", Help: "print the version and exit"},
	}
}

// Overview is the description of the program.
func Overview() []string {
	return []string{
		"hm adds, removes and updates the packages of this repository's Home Manager configuration in one command each. A nixpkgs attribute is pinned through multiverse.lock with mvs, recorded in home-manager/packages.nix and installed with nh home switch. Tools that nixpkgs lacks and that go install, uv tool install or cargo install build are recorded in go-tools.nix, uv-tools.nix and cargo-tools.nix and installed by hm sync with the pinned toolchains.",
		"Every run that edits files or changes the machine is a transaction: hm takes a lock under .git/hm.lock, captures the files it may change, writes each one only after checking that nothing else changed it, restores every file that still holds what it wrote if a step fails before a generation exists, leaves a file something else changed meanwhile as found and names it, and records the run in .git/hm/. Once a generation exists nothing is reverted.",
		"hm never commits on its own. After a switch it prints the files it changed and a git commit command scoped to those files; --commit runs that exact command. hm refuses to start when a file it would edit has uncommitted changes, because a path-scoped commit would sweep them in.",
		"Long output (list, status, doctor, help) goes through a pager when stdout is a terminal: --no-pager disables it, then HM_PAGER, then PAGER, then less -FRX. Output to a pipe is never paged or colored; NO_COLOR also disables color.",
	}
}

// Commands lists every subcommand in the order they are documented.
func Commands() []Command {
	return []Command{
		addCommand(),
		rmCommand(),
		upCommand(),
		syncCommand(),
		switchCommand(),
		listCommand(),
		statusCommand(),
		doctorCommand(),
		tryCommand(),
		cleanCommand(),
		helpCommand(),
		completionCommand(),
		completeCommand(),
	}
}

func addCommand() Command {
	return Command{
		Name:     "add",
		Args:     "NAME[@VERSION]",
		Synopsis: "hm add [--commit] [--build-only] [--keep-on-failure] [--go | --uv | --cargo] NAME[@VERSION]",
		Summary:  "pin a package and install it",
		Description: []string{
			"Without a source flag NAME is a nixpkgs attribute. hm reuses the pin in multiverse.lock when one exists and otherwise runs mvs lock add NAME[@VERSION]; it then inserts NAME into home-manager/packages.nix in sorted order, validates the file with nix eval, and switches with nh home switch. A version given for an attribute that is already pinned is refused, because the lock is shared with the hosts: changing a shared pin is hm up.",
			"With --go, --uv or --cargo the argument is appended to go-tools.nix (module/package@vX.Y.Z, /... patterns allowed), uv-tools.nix (package==X.Y.Z) or cargo-tools.nix (crate@X.Y.Z) and the matching hm sync runs. An explicit version is required so the list stays reproducible.",
			"Re-running the same command after a failure is safe: an existing pin is reused, a name already in the list is left alone, and only the switch and the commit happen.",
		},
		Flags: []Flag{
			commitFlag(),
			buildOnlyFlag(),
			{Name: "keep-on-failure", Help: "leave the edited files in place when a step fails, to inspect a build error against them"},
			{Name: "go", Help: "add a go install target instead of a nixpkgs attribute"},
			{Name: "uv", Help: "add a uv tool instead of a nixpkgs attribute"},
			{Name: "cargo", Help: "add a cargo install crate instead of a nixpkgs attribute"},
		},
		Examples: []Example{
			{"hm add zizmor", "pin the newest indexed zizmor and switch"},
			{"hm add --commit ripgrep@15.1.0", "pin that version, switch and commit"},
			{"hm add --build-only --commit zizmor", "build the new generation and commit, activate later with hm switch"},
			{"hm add --go github.com/fatih/gomodifytags@v1.17.0", "declare a go install tool and install it"},
			{"hm add --uv claude-monitor==3.1.0", "declare a uv tool and install it"},
			{"hm add --cargo wt@0.3.1", "declare a cargo install crate and build it"},
		},
		Complete: CompleteAttr,
	}
}

func rmCommand() Command {
	return Command{
		Name:    "rm",
		Args:    "NAME",
		Summary: "remove a package from the list that holds it",
		Description: []string{
			"NAME is looked up in packages.nix, go-tools.nix (by package path), uv-tools.nix and cargo-tools.nix. A nixpkgs attribute is removed from packages.nix and hm switches. Its pin stays in multiverse.lock unless --prune is given and no other Nix file in the repository names the attribute, in which case hm also runs mvs lock rm; when another file does name it, hm refuses and lists the consumers.",
			"A go entry is removed from its list and the binaries in GOBIN whose build information names that package are deleted; a uv or cargo entry is removed and uv tool uninstall or cargo uninstall runs.",
		},
		Flags: []Flag{
			{Name: "prune", Help: "also remove the pin from multiverse.lock when nothing else in the repository names it"},
			commitFlag(),
			buildOnlyFlag(),
		},
		Examples: []Example{
			{"hm rm charasay", "drop it from packages.nix and switch; the pin stays"},
			{"hm rm --prune --commit charasay", "also drop the pin, then commit both files"},
			{"hm rm github.com/fatih/gomodifytags", "remove a go tool and its binary"},
		},
		Complete: CompleteOwned,
	}
}

func upCommand() Command {
	return Command{
		Name:    "up",
		Args:    "[ATTR]",
		Summary: "move pins to the newest indexed revision",
		Description: []string{
			"hm runs nix flake update mvs so the index is current, then mvs lock update through the refreshed mvs (nix run FLAKE#mvs) for ATTR, or for every attribute in packages.nix when ATTR is omitted. It never passes --all. ATTR must be in packages.nix; a host or dev-shell pin needs --repo, and hm prints the files that consume it before moving it. A pin held back by the version constraint recorded in the lock is reported as such.",
			"When a pin moved hm switches; flake.lock and multiverse.lock are both in the change set when they changed. When nothing moved only flake.lock may have changed and hm suggests a flake: commit.",
		},
		Flags: []Flag{
			{Name: "repo", Help: "allow an attribute that packages.nix does not list, such as a host service"},
			commitFlag(),
			buildOnlyFlag(),
		},
		Examples: []Example{
			{"hm up", "update every packages.nix pin and switch"},
			{"hm up ripgrep", "update one pin"},
			{"hm up --repo --commit jellyfin", "update a host pin after seeing who consumes it"},
		},
		Complete: CompleteOwned,
	}
}

func syncCommand() Command {
	return Command{
		Name:    "sync",
		Args:    "[go|uv|cargo]",
		Summary: "install the go, uv and cargo tools their lists declare",
		Description: []string{
			"For every entry of go-tools.nix hm reads the build information of the binaries in GOBIN and runs go install for entries that are missing or at another version, using the go of the current generation. uv-tools.nix is compared with uv tool list and installed with uv tool install --python pointing at the generation's python3; cargo-tools.nix is compared with cargo install --list and installed with cargo install --locked. Entries already at the declared version are left alone. With no argument all three lists are synced. A standalone sync takes the run lock like switch; the sync that add --go, --uv or --cargo runs is part of that add's own transaction.",
		},
		Flags: []Flag{
			{Name: "build-only", Help: "print the installs hm would run and run none of them"},
		},
		Examples: []Example{
			{"hm sync go", "install the go tools that are missing or at another version"},
			{"hm sync", "reconcile all three lists"},
		},
		Complete: CompleteWords,
		Words:    []string{"go", "uv", "cargo"},
	}
}

func switchCommand() Command {
	return Command{
		Name:    "switch",
		Args:    "[home|darwin|all]",
		Summary: "run nh home switch, nh darwin switch or both",
		Description: []string{
			"Works from any directory because the flake comes from NH_FLAKE or --flake. The default is home. The run takes the same lock as add, rm and up and is refused while another hm holds it or a previous run is unresolved, so a switch never activates another run's half-edited lists.",
		},
		Examples: []Example{
			{"hm switch", "nh home switch"},
			{"hm switch all", "the home layer, then the nix-darwin layer"},
		},
		Complete: CompleteWords,
		Words:    []string{"home", "darwin", "all"},
	}
}

func listCommand() Command {
	return Command{
		Name:    "list",
		Args:    "",
		Summary: "show every installed package with where it came from",
		Description: []string{
			"hm reads the Home Manager generation, not the lock, so the rows are what is installed. Each row carries a source tag: pinned (an attribute in multiverse.lock installed through packages.nix or a programs.* module, resolved to the same store path), nixpkgs (an attribute a module takes from the flake's nixpkgs input, which the lock cannot hold), custom (built by this flake: hm, the sagent tools, Home Manager's own activation files), go (every binary in GOBIN with the module and version from its build information), cargo (cargo install --list), uv (uv tool list) and native (executables in the home.sessionPath directories that no other row explains, such as claude). A go, uv or cargo row that its list does not declare is marked undeclared.",
			"The lock pins that are not in the generation are listed at the end, so hm list and hm status together answer what is pinned but not installed and what is installed but not pinned.",
		},
		Flags: []Flag{
			{Name: "source", Arg: "TAG", Help: "show only rows with this source tag", Values: []string{"pinned", "nixpkgs", "custom", "go", "cargo", "uv", "native"}},
			{Name: "generation", Arg: "PATH", Default: "the active generation", Help: "read a built generation instead, such as the path hm add --build-only printed"},
		},
		Examples: []Example{
			{"hm list", "every row"},
			{"hm list --source go", "only the go install binaries"},
			{"hm list --generation /nix/store/...-home-manager-generation", "what a built but not yet activated generation contains"},
		},
	}
}

func statusCommand() Command {
	return Command{
		Name:    "status",
		Summary: "report pin drift, lock minimality, uncommitted files and the last run",
		Description: []string{
			"hm prints the pins that mvs lock status reports behind the index, whether mvs lock minimize --check would move any pin onto a shared revision, the uncommitted files under flake.nix, flake.lock, multiverse.lock and home-manager/, and the outcome of the last run recorded in .git/hm/.",
		},
		Examples: []Example{
			{"hm status", "the full report"},
			{"hm status --no-pager | grep behind", "just the pins that fell behind"},
		},
	}
}

func doctorCommand() Command {
	return Command{
		Name:    "doctor",
		Summary: "find binaries that shadow Nix ones and tools no list declares",
		Description: []string{
			"hm walks PATH and reports every command that exists in a Nix profile but resolves first to another directory, such as a Homebrew copy. It then lists the binaries in GOBIN, the cargo installs and the uv tools that go-tools.nix, cargo-tools.nix and uv-tools.nix do not declare, files in GOBIN that are not Go binaries, and any list that fails to parse.",
		},
		Examples: []Example{
			{"hm doctor", "the full report"},
			{"hm doctor --no-pager", "the report without a pager, for a log"},
		},
	}
}

func tryCommand() Command {
	return Command{
		Name:    "try",
		Args:    "ATTR [-- COMMAND...]",
		Summary: "run a nixpkgs package once without installing it",
		Description: []string{
			"nix shell nixpkgs#ATTR opens a shell with the package on PATH, or runs COMMAND in it when given. Nothing is pinned or installed.",
		},
		Examples: []Example{
			{"hm try hyperfine", "a shell with hyperfine"},
			{"hm try hyperfine -- hyperfine --version", "run one command and return"},
		},
		Complete: CompleteAttr,
	}
}

func cleanCommand() Command {
	return Command{
		Name:    "clean",
		Summary: "remove old Home Manager generations with nh clean user",
		Description: []string{
			"Refused while the rollback root ~/.local/state/home-manager/keep-gen19 exists: the migration keeps generation 19 reachable until a rollback has been exercised, and nh clean would collect everything else.",
		},
		Flags: []Flag{
			{Name: "keep", Arg: "N", Default: "5", Help: "keep at least this many generations"},
		},
		Examples: []Example{
			{"hm clean", "keep the five newest generations"},
			{"hm clean --keep 10", "keep ten"},
		},
	}
}

func helpCommand() Command {
	return Command{
		Name:    "help",
		Args:    "[COMMAND]",
		Summary: "show the manual, or one command's help",
		Description: []string{
			"With no argument hm help prints the whole manual, the same text as man hm, through the pager. With a command name it is the same as hm COMMAND --help.",
		},
		Examples: []Example{
			{"hm help", "the manual"},
			{"hm help add", "the help for add"},
		},
		Complete: CompleteHelp,
	}
}

func completionCommand() Command {
	return Command{
		Name:    "completion",
		Args:    "zsh|bash|fish",
		Summary: "print the shell completion script",
		Description: []string{
			"The script completes subcommands, flags and flag values from this documentation, and asks a hidden hm __complete call for names that depend on state: owned list entries for rm and up, and multiverse index attributes for add and try. The Nix package installs the scripts under share/, so completion works after the first switch without sourcing anything.",
		},
		Examples: []Example{
			{"hm completion zsh > ~/.config/zsh/completions/_hm", "install by hand where the package is not used"},
			{"source <(hm completion bash)", "load into the current bash"},
		},
		Complete: CompleteWords,
		Words:    []string{"zsh", "bash", "fish"},
	}
}

func completeCommand() Command {
	return Command{
		Name:    "__complete",
		Args:    "ARGS...",
		Summary: "print completion candidates for the shell scripts",
		Hidden:  true,
	}
}

// Lookup returns the command with the given name.
func Lookup(name string) (Command, bool) {
	for _, c := range Commands() {
		if c.Name == name {
			return c, true
		}
	}
	return Command{}, false
}

// Environment lists the variables hm reads.
func Environment() []EnvVar {
	return []EnvVar{
		{"NH_FLAKE", "the repository hm operates on when --flake is not given; programs.nh.flake sets it"},
		{"HM_PAGER", "the pager for long output, before PAGER"},
		{"PAGER", "the pager for long output when HM_PAGER is unset; the default is less -FRX"},
		{"NO_COLOR", "when set, output is never colored"},
	}
}

// ExitCodes lists the documented exit statuses.
func ExitCodes() []ExitCode {
	return []ExitCode{
		{0, "success"},
		{1, "the operation failed; every file hm had changed was restored, except one that no longer held what hm wrote, which is left as found and named"},
		{2, "usage error"},
		{3, "refused: a file hm would edit has uncommitted changes, another hm holds the lock, a previous run is unresolved, or the request breaks a rule such as versioning a shared pin"},
		{4, "the switch succeeded but the commit did not"},
	}
}

// Files lists the files hm reads and writes, relative to the flake.
func Files() []File {
	return []File{
		{"home-manager/packages.nix", "the nixpkgs attributes installed through multiverse.lock; a Nix list of strings, one per line, sorted, comments allowed between entries"},
		{"home-manager/go-tools.nix", "go install targets as module/package@version"},
		{"home-manager/uv-tools.nix", "uv tools as package==version"},
		{"home-manager/cargo-tools.nix", "cargo install crates as crate@version"},
		{"multiverse.lock", "the shared pins, written by mvs and captured and restored like the lists"},
		{"flake.lock", "rewritten by nix flake update mvs during hm up"},
		{".git/hm.lock", "the exclusive lock one run holds, containing its pid"},
		{".git/hm/*.json", "one journal per run: the command, the captured hashes, the steps reached and the outcome"},
	}
}

// WorkedExamples are the examples printed by hm --help.
func WorkedExamples() []Example {
	return []Example{
		{"hm add --commit zizmor", "pin zizmor, add it to packages.nix, switch, and commit \"home: add zizmor 1.30.1\""},
		{"hm up ripgrep && hm status", "move one pin forward, switch, then see what else fell behind"},
		{"hm add --go github.com/fatih/gomodifytags@v1.17.0 && hm doctor", "declare and install a go tool, then check nothing in GOBIN is undeclared"},
	}
}
