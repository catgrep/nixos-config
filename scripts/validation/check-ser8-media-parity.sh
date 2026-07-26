#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel)
PHASE_DIR="$PROJECT_ROOT/.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules"
PROJECTION="$PROJECT_ROOT/scripts/validation/ser8-media-projection.nix"
WARNING_BASELINE="$PHASE_DIR/08-warning-baseline.txt"

usage() {
	echo "Usage: $0 {capture BASELINE|check BASELINE|structure|run-clean COMMAND...}" >&2
	exit 2
}

evaluate_projection() {
	nix eval --json \
		--impure \
		"$PROJECT_ROOT#nixosConfigurations.ser8.config" \
		--apply "config: import $PROJECTION config"
}

normalize_projection() {
	jq -S '
    def normalize_helpers:
      walk(
        if type == "string" then
          gsub(
            "/nix/store/[a-z0-9]+-(source/hosts/ser8/)?"
            + "(systemd_helpers|deployment-helpers|orchestration-helpers)[.]sh";
               "<MEDIA_HELPER>")
          | gsub(
              "/nix/store/[a-z0-9]+-unit-script-"
              + "(media-config|servarrs-setup|download-clients-setup)-start";
                 "<MEDIA_UNIT_SCRIPT>")
        else . end
      );
    del(
      .secrets.alldebrid_api_key,
      .secrets.alldebrid_transmission_admin_password,
      .secrets.jellyfin_api_key.owner,
      .secrets.jellyfin_api_key.group,
      .secrets.jellyfin_api_key.mode,
      .secrets.jellyfin_admin_password.owner,
      .secrets.jellyfin_admin_password.group,
      .secrets.jellyfin_admin_password.mode,
      .secrets.jellyfin_jordan_password.owner,
      .secrets.jellyfin_jordan_password.group,
      .secrets.jellyfin_jordan_password.mode,
      .secrets.jellyfin_sawnia_password.owner,
      .secrets.jellyfin_sawnia_password.group,
      .secrets.jellyfin_sawnia_password.mode,
      .services.declarativeJellyfin.users.admin.mutable,
      .services.declarativeJellyfin.users.jordan.mutable,
      .services.declarativeJellyfin.users.jordan.permissions.enableRemoteAccess,
      .services.declarativeJellyfin.users.sawnia
    ) | normalize_helpers
  '
}

assert_expected_deltas() {
	local current_file=$1

	jq -e '
    (.services.declarativeJellyfin.users.sawnia // null) as $sawnia
    | .services.declarativeJellyfin.users.jordan as $jordan
    | [
        .services.declarativeJellyfin.users.admin,
        $jordan,
        $sawnia
      ] as $household_users
    | [
        .secrets.jellyfin_admin_password,
        .secrets.jellyfin_jordan_password,
        .secrets.jellyfin_sawnia_password,
        .secrets.jellyfin_api_key
      ] as $credential_secrets
    | .services.jellyfin.enable == true
    and .services.declarativeJellyfin.enable == true
    and $sawnia != null
    and ($sawnia | del(.hashedPasswordFile)) == ($jordan | del(.hashedPasswordFile))
    and ($sawnia.hashedPasswordFile | endswith("jellyfin_sawnia_password"))
    and $sawnia.permissions.enableRemoteAccess == true
    and ($household_users | all(.mutable == false))
    and ($credential_secrets | all(
      .owner == "jellyfin"
      and .group == "jellyfin"
      and .mode == "0400"
    ))
  ' "$current_file" >/dev/null || {
		echo "Unexpected Jellyfin policy:" \
			"household users must be immutable with jellyfin-readable credentials." >&2
		return 1
	}
}

capture() {
	local baseline=$1
	local temporary
	temporary=$(mktemp)

	evaluate_projection >"$temporary"
	assert_expected_deltas "$temporary"
	normalize_projection <"$temporary" >"$baseline"
	jq -e . "$baseline" >/dev/null
	rm -f "$temporary"
}

check() {
	local baseline=$1
	local current expected normalized
	current=$(mktemp)
	expected=$(mktemp)
	normalized=$(mktemp)

	jq -e . "$baseline" >/dev/null
	normalize_projection <"$baseline" >"$expected"
	evaluate_projection >"$current"
	assert_expected_deltas "$current"
	normalize_projection <"$current" >"$normalized"

	if ! diff -u "$expected" "$normalized"; then
		echo "ser8 media behavior differs from $baseline" >&2
		rm -f "$current" "$expected" "$normalized"
		return 1
	fi

	rm -f "$current" "$expected" "$normalized"
}

validate_stderr() {
	local stderr_file=$1

	if [ ! -f "$WARNING_BASELINE" ]; then
		echo "Warning baseline is missing: $WARNING_BASELINE" >&2
		return 1
	fi

	awk '
    NR == FNR { allowed[$0]++; next }
    {
      relevant = hm_warning || tolower($0) ~ /(warning|error:|fatal:|trace:)/
      if ($0 ~ /^evaluation warning: bdhill profile:/) hm_warning = 1
      if ((relevant || hm_warning) && !($0 in allowed)) {
        print "Unclassified stderr: " $0 > "/dev/stderr"
        failed = 1
      }
      if (hm_warning && $0 ~ /to your configuration[.]$/) hm_warning = 0
    }
    END { exit failed }
  ' "$WARNING_BASELINE" "$stderr_file"
}

run_clean() {
	[ "$#" -gt 0 ] || usage

	local stdout_file stderr_file status
	stdout_file=$(mktemp)
	stderr_file=$(mktemp)

	set +e
	"$@" >"$stdout_file" 2>"$stderr_file"
	status=$?
	set -e

	cat "$stdout_file"
	if [ "$status" -ne 0 ]; then
		cat "$stderr_file" >&2
		rm -f "$stdout_file" "$stderr_file"
		return "$status"
	fi

	if ! validate_stderr "$stderr_file"; then
		cat "$stderr_file" >&2
		rm -f "$stdout_file" "$stderr_file"
		return 1
	fi

	rm -f "$stdout_file" "$stderr_file"
}

structure() {
	local entrypoint="$PROJECT_ROOT/hosts/ser8/media/default.nix"
	local module_pattern
	module_pattern='^[[:space:]]+[.]/'
	module_pattern+='(sops|jellyfin|sonarr|radarr|prowlarr|qbittorrent|'
	module_pattern+='nzbget|sabnzbd|orchestration)[.]nix'

	[ -f "$entrypoint" ] || {
		echo "Missing media directory entry point: $entrypoint" >&2
		return 1
	}
	rg -q '[.][.]/media[.]nix' "$entrypoint" ||
		rg -q "$module_pattern" "$entrypoint"
	rg -q '^[[:space:]]+[.]/media$' "$PROJECT_ROOT/hosts/ser8/configuration.nix"
	! rg -q '^[[:space:]]+[.]/media[.]nix$' "$PROJECT_ROOT/hosts/ser8/configuration.nix"
}

main() {
	local command=${1:-}
	shift || true

	case "$command" in
	capture)
		[ "$#" -eq 1 ] || usage
		capture "$1"
		;;
	check)
		[ "$#" -eq 1 ] || usage
		check "$1"
		;;
	structure)
		[ "$#" -eq 0 ] || usage
		structure
		;;
	run-clean) run_clean "$@" ;;
	*) usage ;;
	esac
}

main "$@"
