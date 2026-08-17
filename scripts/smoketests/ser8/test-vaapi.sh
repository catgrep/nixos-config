#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# AMD hardware-acceleration smoketest for ser8.
#
# Proves VAAPI transcoding by running a real hardware encode, not by observing
# that the render node exists and the units are up. A kernel bump can leave the
# device file present and root-readable while the unprivileged service users
# lose the ability to open it, or can change the driver ABI so initialisation
# fails; both states look identical to a presence check.
#
# The encode therefore runs non-interactively as each service user in turn —
# `sudo -n -u jellyfin ffmpeg ...` and `sudo -n -u frigate ffmpeg ...` — the
# same pattern scripts/smoketests/media/all.sh already uses for its bazarr
# checks. Running as the deploy user would sail straight through the exact
# failure this check exists to catch.
#
# Nothing is skipped. A missing ffmpeg, a missing render node, or a refused
# `sudo -n` fails the check. Hardware acceleration is the subsystem the kernel
# bump most directly endangers, and a pass on absent evidence here would be
# worse than having no check at all.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# AMD Radeon 780M render node
RENDER_NODE="/dev/dri/renderD128"

# The encoder Jellyfin and Frigate both drive through the VAAPI hwaccel preset
VAAPI_ENCODER="h264_vaapi"

# Service users whose access to the render node the bump can break
SERVICE_USERS=(
	jellyfin
	frigate
)

# Units that depend on that access
ACCELERATED_UNITS=(
	jellyfin
	frigate
)

# Track test results
tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	((tests_run += 1))
	if "$test_func" "$@"; then
		((tests_passed += 1))
		return 0
	fi
	warn "test failed: $test_name"
	return 1
}

# Test 1: the render node exists as a character device
test_render_node_present() {
	info "checking render node '$(fmt_bold "$RENDER_NODE")'"

	local remote_command
	local remote_args=(test -c "$RENDER_NODE")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "render node '$(fmt_bold "$RENDER_NODE")' is present"
		return 0
	fi

	fail "render node '$(fmt_bold "$RENDER_NODE")' is missing on $host"
	return 1
}

# Test 2: a real VAAPI encode completes as the given service user
#
# The source is ffmpeg's synthetic test pattern, so no media file and no camera
# stream is needed, and the output is discarded — a successful run leaves
# nothing on the host. One second of 320x240 keeps the check fast.
test_vaapi_encode() {
	local service_user="$1"
	info "running a VAAPI $VAAPI_ENCODER encode as the '$(fmt_bold "$service_user")' user"

	local remote_command
	local remote_args=(
		sudo -n -u "$service_user"
		ffmpeg
		-hide_banner
		-loglevel error
		-init_hw_device "vaapi=va:$RENDER_NODE"
		-filter_hw_device va
		-f lavfi
		-i "testsrc=size=320x240:rate=25:duration=1"
		-vf "format=nv12,hwupload"
		-c:v "$VAAPI_ENCODER"
		-f null
		-
	)
	printf -v remote_command '%q ' "${remote_args[@]}"

	local output
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if output=$(ssh "$user@$ipaddr" "$remote_command" 2>&1); then
		pass "VAAPI $VAAPI_ENCODER encode succeeded as '$(fmt_bold "$service_user")' on $RENDER_NODE"
		return 0
	fi

	fail "VAAPI $VAAPI_ENCODER encode FAILED as the '$(fmt_bold "$service_user")' user on $RENDER_NODE"
	if [ -n "$output" ]; then
		fail "  $(echo "$output" | tr '\n' ' ')"
	fi
	return 1
}

# Test 3: the units that depend on hardware acceleration are up
test_unit_active() {
	local unit="$1"
	info "checking that the '$(fmt_bold "$unit")' unit is active"

	local remote_command
	local remote_args=(systemctl is-active --quiet "$unit")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "'$(fmt_bold "$unit")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$unit")' unit is not active"
	return 1
}

# Diagnostic only — never asserted, never counted.
#
# The driver string is what to compare across a channel bump: the encode either
# works or it does not, but when it stops working this line says which driver
# and mesa version replaced the one that used to work. vainfo may be absent;
# that changes nothing about the result.
report_vaapi_driver() {
	local driver
	local remote_command
	local remote_args=(vainfo --display drm --device "$RENDER_NODE")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	driver=$(ssh "$user@$ipaddr" "$remote_command" 2>/dev/null | grep 'Driver version' || echo "")

	if [ -n "$driver" ]; then
		info "driver: $driver"
	else
		info "driver string unavailable; the encode assertions are the gate, not this line"
	fi
}

# Main test execution
echo
info "=== Render Node Tests ==="
run_test "render_node_present" test_render_node_present || true

echo
info "=== VAAPI Encode Tests (as the service users) ==="
for service_user in "${SERVICE_USERS[@]}"; do
	run_test "vaapi_encode_${service_user}" test_vaapi_encode "$service_user" || true
done

echo
info "=== Accelerated Unit Tests ==="
for unit in "${ACCELERATED_UNITS[@]}"; do
	run_test "unit_active_${unit}" test_unit_active "$unit" || true
done

echo
info "=== Driver Diagnostics (not asserted) ==="
report_vaapi_driver || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run VAAPI tests passed"
else
	fail "$tests_passed/$tests_run VAAPI tests passed"
	exit 1
fi
