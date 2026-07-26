#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

. ./scripts/lib/all.sh
. ./scripts/smoketests/lib/services.sh

title "$0"

if [ $# -lt 1 ]; then
  info "Usage: $0 <host>"
  exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# format: "service_name:domain:port:systemd_service"
MEDIA_SERVICES=(
  "Jellyfin:jellyfin.vofi:8096:jellyfin"
  "Sonarr:sonarr.vofi:8989:sonarr"
  "Radarr:radarr.vofi:7878:radarr"
  "Bazarr:bazarr.vofi:6767:bazarr"
  "qBittorrent:torrent.vofi:8080:qbittorrent"
  "Prowlarr:prowlarr.vofi:9696:prowlarr"
  "SABnzbd:sabnzbd.vofi:8085:sabnzbd"
  "NZBGet:nzbget.vofi:6789:nzbget"
)

# test each media service
for service_config in "${MEDIA_SERVICES[@]}"; do
  IFS=':' read -r service_name domain port systemd_service <<<"$service_config"
  service_args=(
    "$service_name"
    "$domain"
    "$port"
    "$systemd_service"
    "$host"
    "$ipaddr"
    "$user"
  )

  if test_media_service "${service_args[@]}"; then
    pass "$service_name smoketest passed"
  else
    fail "$service_name smoketest failed"
    exit 1
  fi
  echo
done

pass "All media services smoketests passed"
