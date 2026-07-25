#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Deploy a rendered configuration for an active media service.
configure_arr() {
	local service_name="$1"
	local template_path="$2"

	case "$service_name" in
	"sonarr")
		echo "Configuring Sonarr..."
		mkdir -p /var/lib/sonarr/.config/NzbDrone
		cp "$template_path" /var/lib/sonarr/.config/NzbDrone/config.xml
		chown sonarr:sonarr /var/lib/sonarr/.config/NzbDrone/config.xml
		chmod 600 /var/lib/sonarr/.config/NzbDrone/config.xml
		;;
	"radarr")
		echo "Configuring Radarr..."
		mkdir -p /var/lib/radarr/.config/Radarr
		cp "$template_path" /var/lib/radarr/.config/Radarr/config.xml
		chown radarr:radarr /var/lib/radarr/.config/Radarr/config.xml
		chmod 600 /var/lib/radarr/.config/Radarr/config.xml
		;;
	"prowlarr")
		echo "Configuring Prowlarr..."
		mkdir -p /var/lib/prowlarr
		cp "$template_path" /var/lib/prowlarr/config.xml
		chown prowlarr:prowlarr /var/lib/prowlarr/config.xml
		chmod 600 /var/lib/prowlarr/config.xml
		;;
	"sabnzbd")
		echo "Configuring SABnzbd..."
		mkdir -p /var/lib/sabnzbd
		cp "$template_path" /var/lib/sabnzbd/sabnzbd.ini
		chown sabnzbd:sabnzbd /var/lib/sabnzbd/sabnzbd.ini
		chmod 600 /var/lib/sabnzbd/sabnzbd.ini
		;;
	"nzbget")
		echo "Configuring NZBGet..."
		mkdir -p /var/lib/nzbget
		cp "$template_path" /var/lib/nzbget/nzbget.conf
		chown nzbget:nzbget /var/lib/nzbget/nzbget.conf
		chmod 600 /var/lib/nzbget/nzbget.conf
		;;
	*)
		echo "✗ Unknown service: $service_name"
		return 1
		;;
	esac
	echo "✓ $service_name configuration deployed"
}
