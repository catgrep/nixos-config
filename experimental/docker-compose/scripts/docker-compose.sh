#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Docker Compose Remote Builder Management
# Simple wrapper for managing Docker containers used as Nix remote builders

. ./scripts/lib/all.sh

set -euo pipefail

export USER_ID=$(id -u "$USER")
export GROUP_ID=$(id -g "$USER")

usage() {
    title "Usage: $0 {up|down|status}"
    echo ""
    echo "Commands:"
    echo "  up       - Start Docker builder containers"
    echo "  down     - Stop Docker builder containers"
    echo "  status   - Show container status"
    echo ""
    echo "Environment variables:"
    echo "  KEEP_BUILDERS=1  - Prevent auto-shutdown of containers"
}

ensure_volume() {
    if ! docker volume inspect nix-store-cache >/dev/null 2>&1; then
        info "Creating Docker volume: nix-store-cache"
        docker volume create nix-store-cache
    fi
}

case "${1:-}" in
up)
    ensure_volume
    info "Starting Docker builder containers..."
    docker-compose up -d
    pass "Docker builders started"
    ;;
down)
    info "Stopping Docker builder containers..."
    docker-compose down
    pass "Docker builders stopped"
    ;;
status)
    docker-compose ps
    ;;
"" | help | -h | --help)
    usage
    ;;
*)
    fail "Unknown command: $1"
    usage
    exit 1
    ;;
esac
