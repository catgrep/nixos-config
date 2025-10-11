#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# SystemD helper functions for media services setup

# Use CURL_BIN environment variable if set, otherwise default to $CURL_BIN
CURL_BIN="${CURL_BIN:-curl}"

# Function to configure arr services (Sonarr, Radarr, Prowlarr)
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
    *)
        echo "✗ Unknown service: $service_name"
        return 1
        ;;
    esac
    echo "✓ $service_name configuration deployed"
}

# Function to wait for API to be ready
wait_for_api() {
    local service_name="$1"
    local api_url="$2"
    local timeout="$3"

    echo "Waiting for $service_name API to be ready..."
    for _ in $(seq 1 "$timeout"); do
        if $CURL_BIN -f -s "$api_url" >/dev/null 2>&1; then
            echo "✓ $service_name API is ready"
            return 0
        fi
        sleep 2
    done
    echo "✗ $service_name API failed to become ready after $((timeout * 2)) seconds"
    return 1
}

# Function to configure qBittorrent as download client for arr services
setup_qbittorrent_client() {
    local service_name="$1"
    local service_port="$2"
    local api_key_path="$3"
    local category_field="$4"
    local category_value="$5"
    local qbittorrent_password_path="$6"

    echo "🔧 Configuring qBittorrent for $service_name..."

    # Check if already configured
    response=$($CURL_BIN -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        "http://localhost:$service_port/api/v3/downloadclient")

    if echo "$response" | grep -q '"name": "qBittorrent"'; then
        echo "✓ $service_name qBittorrent download client already configured"
        return 0
    fi

    # Configure qBittorrent download client via API
    response=$($CURL_BIN -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        -d "{
      \"enable\": true,
      \"protocol\": \"torrent\",
      \"priority\": 1,
      \"removeCompletedDownloads\": false,
      \"removeFailedDownloads\": true,
      \"name\": \"qBittorrent\",
      \"implementation\": \"QBittorrent\",
      \"implementationName\": \"qBittorrent\",
      \"configContract\": \"QBittorrentSettings\",
      \"fields\": [
        {\"name\": \"host\", \"value\": \"127.0.0.1\"},
        {\"name\": \"port\", \"value\": 8080},
        {\"name\": \"useSsl\", \"value\": false},
        {\"name\": \"urlBase\", \"value\": \"\"},
        {\"name\": \"username\", \"value\": \"admin\"},
        {\"name\": \"password\", \"value\": \"$(cat "$qbittorrent_password_path")\"},
        {\"name\": \"$category_field\", \"value\": \"$category_value\"},
        {\"name\": \"recentTvPriority\", \"value\": 0},
        {\"name\": \"olderTvPriority\", \"value\": 0},
        {\"name\": \"recentMoviePriority\", \"value\": 0},
        {\"name\": \"olderMoviePriority\", \"value\": 0},
        {\"name\": \"initialState\", \"value\": 0}
      ]
    }" \
        "http://localhost:$service_port/api/v3/downloadclient")

    # Check response
    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully configured $service_name qBittorrent download client"
    else
        echo "✗ Failed to configure $service_name download client. Response:"
        echo "$response"
        return 1
    fi
}

# Function to configure SABnzbd as download client for arr services
setup_sabnzbd_client() {
    local service_name="$1"
    local service_port="$2"
    local api_key_path="$3"
    local category_value="$4"
    local sabnzbd_api_key_path="$5"

    echo "🔧 Configuring SABnzbd for $service_name..."

    # Check if already configured
    response=$($CURL_BIN -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        "http://localhost:$service_port/api/v3/downloadclient")

    if echo "$response" | grep -q '"name": "SABnzbd"'; then
        echo "✓ $service_name SABnzbd download client already configured"
        return 0
    fi

    # Configure SABnzbd download client via API
    response=$($CURL_BIN -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        -d "{
      \"enable\": true,
      \"protocol\": \"usenet\",
      \"priority\": 1,
      \"removeCompletedDownloads\": true,
      \"removeFailedDownloads\": true,
      \"name\": \"SABnzbd\",
      \"implementation\": \"Sabnzbd\",
      \"implementationName\": \"SABnzbd\",
      \"configContract\": \"SabnzbdSettings\",
      \"fields\": [
        {\"name\": \"host\", \"value\": \"127.0.0.1\"},
        {\"name\": \"port\", \"value\": 8085},
        {\"name\": \"useSsl\", \"value\": false},
        {\"name\": \"urlBase\", \"value\": \"\"},
        {\"name\": \"apiKey\", \"value\": \"$(cat "$sabnzbd_api_key_path")\"},
        {\"name\": \"category\", \"value\": \"$category_value\"},
        {\"name\": \"recentTvPriority\", \"value\": 0},
        {\"name\": \"olderTvPriority\", \"value\": 0},
        {\"name\": \"recentMoviePriority\", \"value\": 0},
        {\"name\": \"olderMoviePriority\", \"value\": 0}
      ]
    }" \
        "http://localhost:$service_port/api/v3/downloadclient")

    # Check response
    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully configured $service_name SABnzbd download client"
    else
        echo "✗ Failed to configure $service_name download client. Response:"
        echo "$response"
        return 1
    fi
}

# Function to add arr service to Prowlarr
add_arr_application() {
    local service_name="$1"
    local service_port="$2"
    local api_key_path="$3"
    local sync_categories="$4"
    local prowlarr_api_key_path="$5"

    echo "🔗 Connecting Prowlarr to $service_name..."

    # Check if application already exists
    response=$($CURL_BIN -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        "http://localhost:9696/api/v1/applications")

    if echo "$response" | grep -q "\"name\": \"$service_name\""; then
        echo "✓ $service_name already connected to Prowlarr"
        return 0
    fi

    # Add application to Prowlarr
    local add_app_json
    add_app_json="{
        \"name\": \"$service_name\",
        \"implementation\": \"$service_name\",
        \"configContract\": \"${service_name}Settings\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://localhost:9696\"},
            {\"name\": \"baseUrl\", \"value\": \"http://localhost:$service_port\"},
            {\"name\": \"apiKey\", \"value\": \"$(cat "$api_key_path")\"},
            {\"name\": \"syncCategories\", \"value\": $sync_categories}
        ]
    }"

    response=$($CURL_BIN -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        -d "$add_app_json" \
        "http://localhost:9696/api/v1/applications")

    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully connected $service_name to Prowlarr"
    else
        echo "✗ Failed to connect $service_name to Prowlarr. Response:"
        echo "$response"
        return 1
    fi
}

# Function to add SABnzbd to Prowlarr as download client
add_sabnzbd_to_prowlarr() {
    local sabnzbd_api_key_path="$1"
    local prowlarr_api_key_path="$2"

    echo "🔗 Adding SABnzbd to Prowlarr as download client..."

    # Check if SABnzbd download client already exists in Prowlarr
    response=$($CURL_BIN -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        "http://localhost:9696/api/v1/downloadclient")

    if echo "$response" | grep -q '"name": "SABnzbd"'; then
        echo "✓ SABnzbd already configured in Prowlarr"
        return 0
    fi

    # Add SABnzbd download client to Prowlarr
    response=$($CURL_BIN -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        -d "{
      \"enable\": true,
      \"protocol\": \"usenet\",
      \"priority\": 1,
      \"name\": \"SABnzbd\",
      \"implementation\": \"Sabnzbd\",
      \"implementationName\": \"SABnzbd\",
      \"configContract\": \"SabnzbdSettings\",
      \"fields\": [
        {\"name\": \"host\", \"value\": \"127.0.0.1\"},
        {\"name\": \"port\", \"value\": 8085},
        {\"name\": \"useSsl\", \"value\": false},
        {\"name\": \"urlBase\", \"value\": \"\"},
        {\"name\": \"apiKey\", \"value\": \"$(cat "$sabnzbd_api_key_path")\"},
        {\"name\": \"categories\", \"value\": []}
      ]
    }" \
        "http://localhost:9696/api/v1/downloadclient")

    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully added SABnzbd to Prowlarr"
    else
        echo "✗ Failed to add SABnzbd to Prowlarr. Response:"
        echo "$response"
        return 1
    fi
}
