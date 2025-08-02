#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later


cleanup() {
	ec=$?
	if [ $ec -ne 0 ]; then
		cleanup_hook || error "$0: script failed with exit code: $ec"
	fi
}
trap cleanup EXIT
