#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later


# Colors for output
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PINK='\033[38;5;164;48;5;16m'
RESET='\033[0m'

# Functions for colored output
info() { echo -e "${BOLD}${YELLOW}[INFO]${RESET} $1"; }
success() { echo -e "${BOLD}${GREEN}[✓]${RESET} $1"; }
error() { echo -e "${BOLD}${RED}[ERROR]${RESET} $1" >&2; }
title() { echo -e "${BOLD}${BLUE}=== $1 ===${RESET}"; }
warning() { echo -e "${BOLD}${PINK}[WARNING]${RESET} $1"; }

# Formatters for individual strings
# composable literals
bold() {
	printf %s "${BOLD}$1"
}
yellow() {
	printf %s "${YELLOW}$1"
}
blue() {
	printf %s "${BLUE}$1"
}
red() {
	printf %s "${RED}$1"
}

# fmt just prints the literal
fmt() {
	printf "%s" "$1${RESET}"
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
