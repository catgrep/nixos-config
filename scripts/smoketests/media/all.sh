#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/services.sh
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

MEDIA_ACCOUNTS=(
	bazarr
	jellyfin
	nzbget
	radarr
	sabnzbd
	sonarr
)

info "testing primary groups for media-facing services"
for account in "${MEDIA_ACCOUNTS[@]}"; do
	primary_group=$(ssh "$user@$ipaddr" id -gn "$account")
	if [ "$primary_group" != "media" ]; then
		fail "$account primary group is $primary_group, expected media"
		exit 1
	fi
done
pass "Media-facing services use the media primary group"

info "testing completed download permissions"
if bad_path=$(ssh "$user@$ipaddr" \
	'find /mnt/media/downloads/complete /mnt/media/downloads/usenet/complete \
    \( -type d \( ! -group media -o ! -perm 2775 \) \
    -o -type f \( ! -group media -o ! -perm 0664 \) \) \
    -print -quit'); then
	if [ -n "$bad_path" ]; then
		fail "Completed download has invalid shared permissions: $bad_path"
		exit 1
	fi
else
	fail "could not check completed download permissions"
	exit 1
fi
pass "Completed downloads have shared media permissions"

info "testing media library permissions"
if bad_path=$(ssh "$user@$ipaddr" \
	'find /mnt/media/tv /mnt/media/movies -xdev \
    \( -type d \( ! -group media -o ! -perm 2775 \) \
    -o -type f \( ! -group media -o ! -perm 0664 \) \) \
    -print -quit'); then
	if [ -n "$bad_path" ]; then
		fail "Media library path has invalid shared permissions: $bad_path"
		exit 1
	fi
else
	fail "could not check media library permissions"
	exit 1
fi
pass "Media libraries have shared media permissions"

info "testing Bazarr access to media libraries"
if inaccessible_path=$(ssh "$user@$ipaddr" \
	'cd / && sudo -n -u bazarr find /mnt/media/tv /mnt/media/movies -xdev \
    \( -type d ! -writable -o -type f ! -readable \) -print -quit'); then
	if [ -n "$inaccessible_path" ]; then
		fail "Bazarr cannot access $inaccessible_path"
		exit 1
	fi
else
	fail "could not check Bazarr media library access"
	exit 1
fi
pass "Bazarr can read files and write directories in media libraries"

if ./scripts/smoketests/media/test-zfs-media.sh "$host"; then
	pass "ZFS media storage smoketest passed"
else
	fail "ZFS media storage smoketest failed"
	exit 1
fi

pass "All media services smoketests passed"
