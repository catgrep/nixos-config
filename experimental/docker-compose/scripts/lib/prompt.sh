#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

confirm() {
    if ${NO_CONFIRM:-false}; then
        return 0
    fi
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        fail "Aborted"
        exit 1
    fi
}

sensitive_input() {
    local prompt="$1"
    local input=""

    # Prompt for input without echoing to terminal
    echo -n "$prompt" >&2
    read -s input
    echo >&2 # Add newline after hidden input

    # Validate input is not empty
    if [[ -z "$input" ]]; then
        fail "Input cannot be empty"
        return 1
    fi

    # Return the input value
    echo "$input"
}
