#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Smart SSH host resolution with Tailscale fallback
# Uses .use_tailscale file as a sticky cache to avoid repeated timeout delays

USE_TAILSCALE_FILE=".use_tailscale"

# Get the appropriate host for SSH (local IP or Tailscale)
# Usage: resolve_ssh_host <hostname>
# Returns: IP address or Tailscale hostname
resolve_ssh_host() {
    local host="$1"
    local local_ip tailscale_host tailscale_domain user

    local_ip="$(get_ip "$host")"
    user="$(get_user "$host")"
    tailscale_domain="$(get_tailscale_domain)"
    tailscale_host="${host}.${tailscale_domain}"

    # Check cached preference first (avoids repeated timeout delays)
    if [ -f "$USE_TAILSCALE_FILE" ]; then
        # Log to stderr so stdout only contains the host
        echo "[tailscale] Using Tailscale (cached in $USE_TAILSCALE_FILE)" >&2
        echo "$tailscale_host"
        return 0
    fi

    # Try local IP with short timeout (use correct user from deploy.yaml)
    if ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no "${user}@${local_ip}" true 2>/dev/null; then
        echo "$local_ip"
    else
        echo "[tailscale] Local IP unreachable, switching to Tailscale" >&2
        echo "tailscale" > "$USE_TAILSCALE_FILE"
        echo "[tailscale] Created $USE_TAILSCALE_FILE (remove when back on local network)" >&2
        echo "$tailscale_host"
    fi
}
