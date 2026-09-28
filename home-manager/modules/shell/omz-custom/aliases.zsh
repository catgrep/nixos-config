# Functions and aliases loaded by oh-my-zsh from the custom directory.
# Environment variables and PATH entries live in the Home Manager modules.

# Attach to (or start) tmux on a remote host over mosh.
tmosh() {
    mosh "$1" -- sh -c "tmux attach || tmux new"
}

# Trace what a running process writes to stdout (macOS dtrace).
capture() {
    sudo dtrace -p "$1" -qn '
        syscall::write*:entry
        /pid == $target && arg0 == 1/ {
            printf("%s", copyinstr(arg1, arg2));
        }
    '
}

# Pick a command with fzf and open its man page.
fman() {
    local cmd
    cmd="$(print -rl -- ${(k)commands} ${(k)builtins} | sort -u | fzf)" || return
    man -- "$cmd"
}

# Run claude, updating it first when the npm registry has a newer release.
ccode() {
    LATEST=$(curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | jq -r '.version')
    LOCAL=$(claude --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

    verlte() { [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]; }

    if ! verlte "$LATEST" "$LOCAL"; then
        claude update
    fi

    claude "$@"
}

alias gtop="asitop"

# pretty print json
alias jpr="jq -r ."
