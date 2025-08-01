#!/usr/bin/env bash

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
