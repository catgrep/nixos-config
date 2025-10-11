#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# SystemD helper functions for media services setup

# Use CURL_BIN environment variable if set, otherwise default to $CURL_BIN
CURL_BIN="${CURL_BIN:-curl}"

# Sanitize API keys from strings (URLs, commands, responses)
# Supports multiple patterns:
# - Query parameters: apikey=VALUE, api_key=VALUE, apiKey=VALUE
# - HTTP headers: X-Api-Key: VALUE
# - JSON fields: "apiKey": "VALUE", "api_key": "VALUE"
sanitize_api_key() {
    local input="$1"
    # Sanitize query parameters (case-insensitive)
    input=$(echo "$input" | sed -E 's/(api[_-]?key)=[^&[:space:]\"'\'')]*/\1=***REDACTED***/gi')
    # Sanitize HTTP headers
    input=$(echo "$input" | sed -E 's/(X-Api-Key[[:space:]]*:[[:space:]]*)[^'\''\"[:space:]]*/\1***REDACTED***/gi')
    # Sanitize JSON fields
    input=$(echo "$input" | sed -E 's/("api[_-]?[Kk]ey"[[:space:]]*:[[:space:]]*")[^"]*"/\1***REDACTED***"/g')
    echo "$input"
}

# Wrapper for curl that sanitizes API keys in logs
# Usage: curl_safe [curl arguments...]
curl_safe() {
    local command="$CURL_BIN $*"
    local sanitized_command
    sanitized_command=$(sanitize_api_key "$command")
    echo "Executing: $sanitized_command"

    # Execute curl with original (unsanitized) arguments and capture output
    local output
    local exit_code
    output=$("$CURL_BIN" "$@" 2>&1)
    exit_code=$?

    # Sanitize output before returning
    sanitize_api_key "$output"

    return $exit_code
}

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
    "sabnzbd")
        echo "Configuring SABnzbd..."
        mkdir -p /var/lib/sabnzbd
        cp "$template_path" /var/lib/sabnzbd/sabnzbd.ini
        chown sabnzbd:sabnzbd /var/lib/sabnzbd/sabnzbd.ini
        chmod 600 /var/lib/sabnzbd/sabnzbd.ini
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

    local sanitized_url
    sanitized_url=$(sanitize_api_key "$api_url")
    echo "Waiting for $service_name API to be ready at $sanitized_url..."

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
    response=$(curl_safe -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        "http://localhost:$service_port/api/v3/downloadclient")

    if echo "$response" | grep -q '"name": "qBittorrent"'; then
        echo "✓ $service_name qBittorrent download client already configured"
        return 0
    fi

    # Configure qBittorrent download client via API
    response=$(curl_safe -X POST \
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
        local sanitized_response
        sanitized_response=$(sanitize_api_key "$response")
        echo "✗ Failed to configure $service_name download client. Response:"
        echo "$sanitized_response"
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
    response=$(curl_safe -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$api_key_path")" \
        "http://localhost:$service_port/api/v3/downloadclient")

    if echo "$response" | grep -q '"name": "SABnzbd"'; then
        echo "✓ $service_name SABnzbd download client already configured"
        return 0
    fi

    # Configure SABnzbd download client via API
    response=$(curl_safe -X POST \
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
        local sanitized_response
        sanitized_response=$(sanitize_api_key "$response")
        echo "✗ Failed to configure $service_name download client. Response:"
        echo "$sanitized_response"
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
    response=$(curl_safe -X GET \
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

    response=$(curl_safe -X POST \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        -d "$add_app_json" \
        "http://localhost:9696/api/v1/applications")

    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully connected $service_name to Prowlarr"
    else
        local sanitized_response
        sanitized_response=$(sanitize_api_key "$response")
        echo "✗ Failed to connect $service_name to Prowlarr. Response:"
        echo "$sanitized_response"
        return 1
    fi
}

# Function to add SABnzbd to Prowlarr as download client
add_sabnzbd_to_prowlarr() {
    local sabnzbd_api_key_path="$1"
    local prowlarr_api_key_path="$2"

    echo "🔗 Adding SABnzbd to Prowlarr as download client..."

    # Check if SABnzbd download client already exists in Prowlarr
    response=$(curl_safe -X GET \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
        "http://localhost:9696/api/v1/downloadclient")

    if echo "$response" | grep -q '"name": "SABnzbd"'; then
        echo "✓ SABnzbd already configured in Prowlarr"
        return 0
    fi

    # Add SABnzbd download client to Prowlarr
    response=$(
        curl_safe -X POST \
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
            {\"order\":0,\"name\":\"host\",\"value\":\"127.0.0.1\",\"type\":\"textbox\",\"advanced\":false,\"privacy\":\"normal\",\"isFloat\":false},
            {\"order\":1,\"name\":\"port\",\"value\":8085,\"type\":\"textbox\",\"advanced\":false,\"privacy\":\"normal\",\"isFloat\":false},
            {\"order\":2,\"name\":\"useSsl\",\"value\":false,\"type\":\"checkbox\",\"advanced\":false,\"privacy\":\"normal\",\"isFloat\":false},
            {\"order\":3,\"name\":\"urlBase\",\"value\":\"\",\"type\":\"textbox\",\"advanced\":true,\"privacy\":\"normal\",\"isFloat\":false},
            {\"order\":4,\"name\":\"apiKey\",\"value\":\"$(cat "$sabnzbd_api_key_path")\",\"type\":\"textbox\",\"advanced\":false,\"privacy\":\"apiKey\",\"isFloat\":false},
            {\"order\":5,\"name\":\"username\",\"value\":\"\",\"type\":\"textbox\",\"advanced\":false,\"privacy\":\"userName\",\"isFloat\":false},
            {\"order\":6,\"name\":\"password\",\"value\":\"\",\"type\":\"password\",\"advanced\":false,\"privacy\":\"password\",\"isFloat\":false},
            {\"order\":7,\"name\":\"category\",\"value\":\"prowlarr\",\"type\":\"textbox\",\"advanced\":false,\"privacy\":\"normal\",\"isFloat\":false},
            {\"order\":8,\"name\":\"priority\",\"value\":-100,\"type\":\"select\",\"advanced\":false,\"privacy\":\"normal\",\"isFloat\":false}
        ],
        \"categories\": [],
        \"supportsCategories\": true,
        \"infoLink\": \"https://wiki.servarr.com/prowlarr/supported#sabnzbd\"
    }" \
            "http://localhost:9696/api/v1/downloadclient"
    )

    if echo "$response" | grep -q '"id":'; then
        echo "✓ Successfully added SABnzbd to Prowlarr"
    else
        local sanitized_response
        sanitized_response=$(sanitize_api_key "$response")
        echo "✗ Failed to add SABnzbd to Prowlarr. Response:"
        echo "$sanitized_response"
        return 1
    fi
}
