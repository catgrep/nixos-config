#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh

title "$0"

if [ "$#" -ne 1 ]; then
  fail "Usage: $0 <host>"
  exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")
client_ipaddr=$(get_ip "ser8")
client_user=$(get_user "ser8")

info "checking Subgen service state on $host"
ssh "$user@$ipaddr" "systemctl is-active --quiet subgen.service"
pass "Subgen service is active"

info "checking Subgen status endpoint from ser8"
# shellcheck disable=SC2029
status=$(ssh "$client_user@$client_ipaddr" \
  'curl --fail --silent "http://$1:9000/status"' _ "$ipaddr")
if ! jq -e '.version | startswith("Subgen ")' <<<"$status" >/dev/null; then
  fail "Subgen status response is invalid"
  exit 1
fi
pass "Subgen status endpoint returned version metadata"
