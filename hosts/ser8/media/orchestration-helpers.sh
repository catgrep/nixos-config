#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Orchestration helper functions for cross-service media setup

# Use CURL_BIN environment variable if set, otherwise default to $CURL_BIN
CURL_BIN="${CURL_BIN:-curl}"
JQ_BIN="${JQ_BIN:-jq}"

# Sanitize API keys from strings (URLs, commands, responses)
# Supports multiple patterns:
# - Query parameters: apikey=VALUE, api_key=VALUE, apiKey=VALUE
# - HTTP headers: X-Api-Key: VALUE
# - JSON fields: "apiKey": "VALUE", "api_key": "VALUE"
sanitize_api_key() {
	local input="$1"
	# Sanitize query parameters (case-insensitive)
	input=$(echo "$input" | sed -E 's/(api[_-]?key)=[^&[:space:]\"'\'')]*/\1=***REDACTED***/gi')
	input=$(echo "$input" | sed -E 's/(password)=[^&[:space:]\"'\'')]*/\1=***REDACTED***/gi')
	input=$(echo "$input" | sed -E 's#(https?://[^:/[:space:]]+:)[^@/[:space:]]+@#\1***REDACTED***@#g')
	# Sanitize HTTP headers
	input=$(echo "$input" | sed -E 's/(X-Api-Key[[:space:]]*:[[:space:]]*)[^'\''\"[:space:]]*/\1***REDACTED***/gi')
	# Sanitize JSON fields
	input=$(echo "$input" | sed -E 's/("api[_-]?[Kk]ey"[[:space:]]*:[[:space:]]*")[^"]*"/\1***REDACTED***"/g')
	input=$(echo "$input" | sed -E 's/("[Pp]assword"[[:space:]]*:[[:space:]]*")[^"]*"/\1***REDACTED***"/g')
	echo "$input"
}

# Wrapper for curl that sanitizes API keys in logs
# Usage: curl_safe [curl arguments...]
curl_safe() {
	local command="$CURL_BIN $*"
	local sanitized_command
	sanitized_command=$(sanitize_api_key "$command")
	echo "Executing: $sanitized_command" >&2

	# Execute curl with original (unsanitized) arguments. Keep stderr out of
	# command substitutions so JSON API responses remain parseable by jq.
	local output
	local stderr_file
	local exit_code
	stderr_file=$(mktemp)

	if output=$("$CURL_BIN" -sS "$@" 2>"$stderr_file"); then
		exit_code=0
	else
		exit_code=$?
	fi

	if [ "$exit_code" -ne 0 ]; then
		echo "curl failed with exit code $exit_code" >&2
		sanitize_api_key "$(cat "$stderr_file")" >&2
	fi

	rm -f "$stderr_file"

	# Sanitize output before returning
	sanitize_api_key "$output"

	return $exit_code
}

download_client_id() {
	local response="$1"
	local client_name="$2"

	# shellcheck disable=SC2016 # $name is a jq variable supplied by --arg.
	printf '%s' "$response" | "$JQ_BIN" -r --arg name "$client_name" 'first(.[] | select(.name == $name) | .id) // empty'
}

upsert_arr_download_client() {
	local service_name="$1"
	local service_port="$2"
	local api_key_path="$3"
	local client_name="$4"
	local payload="$5"

	local response
	response=$(curl_safe -X GET \
		-H "Content-Type: application/json" \
		-H "X-Api-Key: $(cat "$api_key_path")" \
		"http://localhost:$service_port/api/v3/downloadclient")

	local client_id
	client_id=$(download_client_id "$response" "$client_name")

	local method="POST"
	local url="http://localhost:$service_port/api/v3/downloadclient"
	local action="configured"

	if [ -n "$client_id" ] && [ "$client_id" != "null" ]; then
		method="PUT"
		url="$url/$client_id"
		action="updated"
		# shellcheck disable=SC2016 # $id is a jq variable supplied by --argjson.
		payload=$(printf '%s' "$payload" | "$JQ_BIN" --argjson id "$client_id" '. + {id: $id}')
	fi

	response=$(curl_safe -X "$method" \
		-H "Content-Type: application/json" \
		-H "X-Api-Key: $(cat "$api_key_path")" \
		-d "$payload" \
		"$url")

	if printf '%s' "$response" | "$JQ_BIN" -e '.id' >/dev/null 2>&1; then
		echo "✓ Successfully $action $service_name $client_name download client"
	else
		local sanitized_response
		sanitized_response=$(sanitize_api_key "$response")
		echo "✗ Failed to configure $service_name $client_name download client. Response:"
		echo "$sanitized_response"
		return 1
	fi
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

wait_for_api_basic_auth() {
	local service_name="$1"
	local api_url="$2"
	local timeout="$3"
	local username="$4"
	local password_path="$5"

	echo "Waiting for $service_name API to be ready at $api_url..."

	for _ in $(seq 1 "$timeout"); do
		if $CURL_BIN -f -s -u "$username:$(cat "$password_path")" "$api_url" >/dev/null 2>&1; then
			echo "✓ $service_name API is ready"
			return 0
		fi
		sleep 2
	done
	echo "✗ $service_name API failed to become ready after $((timeout * 2)) seconds"
	return 1
}

# Function to configure SABnzbd as download client for arr services
setup_sabnzbd_client() {
	local service_name="$1"
	local service_port="$2"
	local api_key_path="$3"
	local category_field="$4"
	local category_value="$5"
	local sabnzbd_api_key_path="$6"
	local client_priority="${7:-2}"

	echo "🔧 Configuring SABnzbd for $service_name..."

	local payload
	# shellcheck disable=SC2016 # Dollar variables in this single-quoted program belong to jq.
	payload=$("$JQ_BIN" -n \
		--arg apiKey "$(cat "$sabnzbd_api_key_path")" \
		--arg categoryField "$category_field" \
		--arg categoryValue "$category_value" \
		--argjson clientPriority "$client_priority" \
		'{
          enable: true,
          protocol: "usenet",
          priority: $clientPriority,
          removeCompletedDownloads: true,
          removeFailedDownloads: true,
          name: "SABnzbd",
          implementation: "Sabnzbd",
          implementationName: "SABnzbd",
          configContract: "SabnzbdSettings",
          fields: [
            {name: "host", value: "127.0.0.1"},
            {name: "port", value: 8085},
            {name: "useSsl", value: false},
            {name: "urlBase", value: ""},
            {name: "apiKey", value: $apiKey},
            {name: $categoryField, value: $categoryValue},
            {name: "recentTvPriority", value: 0},
            {name: "olderTvPriority", value: 0},
            {name: "recentMoviePriority", value: 0},
            {name: "olderMoviePriority", value: 0}
          ]
        }')

	upsert_arr_download_client "$service_name" "$service_port" "$api_key_path" "SABnzbd" "$payload"
}

# Function to configure NZBGet as download client for arr services
setup_nzbget_client() {
	local service_name="$1"
	local service_port="$2"
	local api_key_path="$3"
	local category_field="$4"
	local category_value="$5"
	local nzbget_password_path="$6"
	local client_priority="${7:-1}"

	echo "🔧 Configuring NZBGet for $service_name..."

	local payload
	# shellcheck disable=SC2016 # Dollar variables in this single-quoted program belong to jq.
	payload=$("$JQ_BIN" -n \
		--arg categoryField "$category_field" \
		--arg categoryValue "$category_value" \
		--arg password "$(cat "$nzbget_password_path")" \
		--argjson clientPriority "$client_priority" \
		'{
          enable: true,
          protocol: "usenet",
          priority: $clientPriority,
          removeCompletedDownloads: true,
          removeFailedDownloads: true,
          name: "NZBGet",
          implementation: "Nzbget",
          implementationName: "NZBGet",
          configContract: "NzbgetSettings",
          fields: [
            {name: "host", value: "127.0.0.1"},
            {name: "port", value: 6789},
            {name: "useSsl", value: false},
            {name: "urlBase", value: ""},
            {name: "username", value: "admin"},
            {name: "password", value: $password},
            {name: $categoryField, value: $categoryValue},
            {name: "recentTvPriority", value: 0},
            {name: "olderTvPriority", value: 0},
            {name: "recentMoviePriority", value: 0},
            {name: "olderMoviePriority", value: 0},
            {name: "addPaused", value: false}
          ]
        }')

	upsert_arr_download_client "$service_name" "$service_port" "$api_key_path" "NZBGet" "$payload"
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

upsert_prowlarr_download_client() {
	local client_name="$1"
	local prowlarr_api_key_path="$2"
	local payload="$3"

	local response
	response=$(curl_safe -X GET \
		-H "Content-Type: application/json" \
		-H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
		"http://localhost:9696/api/v1/downloadclient")

	local client_id
	client_id=$(download_client_id "$response" "$client_name")

	local method="POST"
	local url="http://localhost:9696/api/v1/downloadclient"
	local action="added"

	if [ -n "$client_id" ] && [ "$client_id" != "null" ]; then
		method="PUT"
		url="$url/$client_id"
		action="updated"
		# shellcheck disable=SC2016 # $id is a jq variable supplied by --argjson.
		payload=$(printf '%s' "$payload" | "$JQ_BIN" --argjson id "$client_id" '. + {id: $id}')
	fi

	response=$(curl_safe -X "$method" \
		-H "Content-Type: application/json" \
		-H "X-Api-Key: $(cat "$prowlarr_api_key_path")" \
		-d "$payload" \
		"$url")

	if printf '%s' "$response" | "$JQ_BIN" -e '.id' >/dev/null 2>&1; then
		echo "✓ Successfully $action $client_name to Prowlarr"
	else
		local sanitized_response
		sanitized_response=$(sanitize_api_key "$response")
		echo "✗ Failed to add $client_name to Prowlarr. Response:"
		echo "$sanitized_response"
		return 1
	fi
}

# Function to add SABnzbd to Prowlarr as download client
add_sabnzbd_to_prowlarr() {
	local sabnzbd_api_key_path="$1"
	local prowlarr_api_key_path="$2"
	local client_priority="${3:-2}"

	echo "🔗 Adding SABnzbd to Prowlarr as download client..."

	local payload
	# shellcheck disable=SC2016 # Dollar variables in this single-quoted program belong to jq.
	payload=$("$JQ_BIN" -n \
		--arg apiKey "$(cat "$sabnzbd_api_key_path")" \
		--argjson clientPriority "$client_priority" \
		'{
          enable: true,
          protocol: "usenet",
          priority: $clientPriority,
          name: "SABnzbd",
          implementation: "Sabnzbd",
          implementationName: "SABnzbd",
          configContract: "SabnzbdSettings",
          fields: [
            {order: 0, name: "host", value: "127.0.0.1", type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 1, name: "port", value: 8085, type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 2, name: "useSsl", value: false, type: "checkbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 3, name: "urlBase", value: "", type: "textbox", advanced: true, privacy: "normal", isFloat: false},
            {order: 4, name: "apiKey", value: $apiKey, type: "textbox", advanced: false, privacy: "apiKey", isFloat: false},
            {order: 5, name: "username", value: "", type: "textbox", advanced: false, privacy: "userName", isFloat: false},
            {order: 6, name: "password", value: "", type: "password", advanced: false, privacy: "password", isFloat: false},
            {order: 7, name: "category", value: "prowlarr", type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 8, name: "priority", value: -100, type: "select", advanced: false, privacy: "normal", isFloat: false}
          ],
          categories: [],
          supportsCategories: true,
          infoLink: "https://wiki.servarr.com/prowlarr/supported#sabnzbd"
        }')

	upsert_prowlarr_download_client "SABnzbd" "$prowlarr_api_key_path" "$payload"
}

# Function to add NZBGet to Prowlarr as download client
add_nzbget_to_prowlarr() {
	local nzbget_password_path="$1"
	local prowlarr_api_key_path="$2"
	local client_priority="${3:-1}"

	echo "🔗 Adding NZBGet to Prowlarr as download client..."

	local payload
	# shellcheck disable=SC2016 # Dollar variables in this single-quoted program belong to jq.
	payload=$("$JQ_BIN" -n \
		--arg password "$(cat "$nzbget_password_path")" \
		--argjson clientPriority "$client_priority" \
		'{
          enable: true,
          protocol: "usenet",
          priority: $clientPriority,
          name: "NZBGet",
          implementation: "Nzbget",
          implementationName: "NZBGet",
          configContract: "NzbgetSettings",
          fields: [
            {order: 0, name: "host", value: "127.0.0.1", type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 1, name: "port", value: 6789, type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 2, name: "useSsl", value: false, type: "checkbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 3, name: "urlBase", value: "", type: "textbox", advanced: true, privacy: "normal", isFloat: false},
            {order: 4, name: "username", value: "admin", type: "textbox", advanced: false, privacy: "userName", isFloat: false},
            {order: 5, name: "password", value: $password, type: "password", advanced: false, privacy: "password", isFloat: false},
            {order: 6, name: "category", value: "prowlarr", type: "textbox", advanced: false, privacy: "normal", isFloat: false},
            {order: 7, name: "priority", value: 0, type: "select", advanced: false, privacy: "normal", isFloat: false},
            {order: 8, name: "addPaused", value: false, type: "checkbox", advanced: false, privacy: "normal", isFloat: false}
          ],
          categories: [],
          supportsCategories: true,
          infoLink: "https://wiki.servarr.com/prowlarr/supported#nzbget"
        }')

	upsert_prowlarr_download_client "NZBGet" "$prowlarr_api_key_path" "$payload"
}
