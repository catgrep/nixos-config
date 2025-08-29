#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

cleanup() {
    ec=$?
    if [ $ec -ne 0 ]; then
        # call "cleanup_hook" if dependent script defines it
        if command -v cleanup_hook >/dev/null 2>&1; then
            cleanup_hook
        else
            fail "script '$(fmt_blue "$0")' failed with exit code: $ec"
        fi
    fi
}
trap cleanup EXIT
