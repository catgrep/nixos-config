#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Colors for output
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PINK='\033[35m'
RESET='\033[0m'

# Define labels
LABEL_INFO="[info]"
LABEL_DONE="[done]"
LABEL_FAIL="[FAIL]"
LABEL_WARN="[WARN]"

# Prefixed logging functions
info() { printf "${BOLD}${YELLOW}%-6s${RESET} %b\n" "${LABEL_INFO}" "$1"; }
warn() { printf "${BOLD}${PINK}%-6s${RESET} %b\n" "${LABEL_WARN}" "$1"; }
pass() { printf "${BOLD}${GREEN}%-6s${RESET} %b\n" "${LABEL_DONE}" "$1"; }
fail() { printf "${BOLD}${RED}%-6s${RESET} %b\n" "${LABEL_FAIL}" "$1" >&2; }

# Title formatting function
title() { printf "${BOLD}${BLUE}=== %b ===${RESET}\n" "$1"; }

# Formatters for individual strings
# composable literals
bold() {
    printf %b "${BOLD}$1"
}
yellow() {
    printf %b "${YELLOW}$1"
}
blue() {
    printf %b "${BLUE}$1"
}
red() {
    printf %b "${RED}$1"
}

# fmt just prints the literal
fmt() {
    printf "%b" "$1${RESET}"
}

# fmt colors
fmt_yellow() {
    fmt "$(bold "$(yellow "$1")")"
}
fmt_blue() {
    fmt "$(bold "$(blue "$1")")"
}
fmt_red() {
    fmt "$(bold "$(red "$1")")"
}
fmt_bold() {
    fmt "$(bold "$1")"
}
