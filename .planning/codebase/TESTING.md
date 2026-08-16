# Testing Patterns

**Analysis Date:** 2026-08-17

## Test Framework

This is a NixOS infrastructure repository, not an application codebase. There is no unit-test framework (no Jest/pytest/etc). Testing takes three forms:

1. **Nix evaluation checks** — `nix flake check`, `statix check`, and dry-run builds of every host's `toplevel` derivation.
2. **Validation scripts** — one-off Bash scripts under `scripts/validation/` that assert specific Nix module/option behavior via `nix eval --json`.
3. **Smoketests** — Bash scripts under `scripts/smoketests/` that SSH into a live, already-deployed host and assert real runtime behavior (services up, hardware acceleration works, network isolation holds, DNS resolves).

**Runner:** Plain Bash (`#!/usr/bin/env bash`, `set -euo pipefail`). No test framework dependency.

**Run Commands:**
```bash
make check                     # nix flake check + statix + validation scripts + dry-run builds of every host
make smoketests-ser8           # run the full ser8 smoketest suite over SSH
make smoketests-HOST           # generic form, HOST from deploy.yaml
./scripts/validation/test-actual-module.sh   # run a single validation script directly
./scripts/smoketests/ser8/test-vaapi.sh ser8 # run a single smoketest directly (host arg required)
```

`make check` is the main repo-wide gate and is defined in `Makefile`:
```makefile
check:
	@nix flake check
	@statix check
	@./scripts/validation/test-nzbget-permissions.sh
	@./scripts/validation/test-actual-module.sh
	@./scripts/validation/test-pi-bootloader.sh
	@$(call success_msg,"✓ Flake check passed")
	@$(call info_msg,"Testing host configurations..."); \
	set -e; \
	for host in $(HOSTS); do \
		nix build .#nixosConfigurations."$$host".config.system.build.toplevel --dry-run; \
	done; \
	$(call success_msg,"✓ All host configurations are valid")
```

## Test File Organization

**Validation scripts** (`scripts/validation/`): standalone, non-suite scripts that gate specific Nix evaluation invariants. Run individually inside `make check`, not through a fan-out helper. Examples:
- `scripts/validation/test-actual-module.sh` — asserts the flake resolves a specific upstream NixOS module version by checking option existence/type, not option value.
- `scripts/validation/test-nzbget-permissions.sh`, `scripts/validation/test-pi-bootloader.sh`.

**Smoketests** (`scripts/smoketests/`): organized by host or subsystem, each directory containing individual `test-*.sh` checks plus one `all.sh` entry point:
```
scripts/smoketests/
├── lib/                     # shared fan-out and service-check helpers
│   ├── fanout.sh
│   └── services.sh
├── ser8/
│   ├── test-frigate.sh
│   ├── test-home-assistant.sh
│   ├── test-zfs-health.sh
│   ├── test-vaapi.sh
│   └── all.sh               # fans out to media/all.sh, nordvpn/all.sh, and the ser8 test-*.sh files
├── media/
│   └── all.sh
├── nordvpn/
│   ├── test-qbittorrent-confinement.sh
│   ├── test-forwarding.sh
│   ├── test-veth-interfaces.sh
│   ├── test-anonymity.sh
│   ├── test-netns.sh
│   ├── test-qbittorrent.sh
│   ├── all.sh
│   └── disruptive.sh        # kill-switch tests; deliberately excluded from all.sh / the deploy path
├── gateway/
│   ├── test-subgen.sh
│   ├── test-tailscale.sh
│   ├── test-caddy.sh
│   └── all.sh
└── subgen/
```

**Naming:** `test-<subject>.sh` for individual checks. `all.sh` reserved exclusively for suite entry points referenced by `deploy.yaml` — never rename or duplicate this filename casually, since `deploy.yaml` is the single source of truth for which script runs per host/tag.

## Test Structure

**Suite entry point pattern** — every `all.sh` follows the same shape (`scripts/smoketests/ser8/all.sh`):
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="ser8"
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
	./scripts/smoketests/ser8/test-vaapi.sh
	./scripts/smoketests/ser8/test-frigate.sh
	./scripts/smoketests/ser8/test-home-assistant.sh
)

run_suite "$@"
```
New suites: declare `SUITE_NAME`, populate a `TESTS` array of script paths (individual tests or nested `all.sh` suites), then call `run_suite "$@"` — never hand-roll a `for` loop, because a loop's exit status reflects only its last iteration and can silently certify a broken activation (explicitly called out in the header comment of `scripts/smoketests/ser8/all.sh`).

**Individual test-script pattern** — each `test-*.sh` accepts the host as `$1`, resolves its IP/user, defines one or more `test_*` predicate functions, invokes them through a local `run_test` counter helper, and prints a final pass/fail summary (`scripts/smoketests/ser8/test-vaapi.sh`):
```bash
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
```
Every check runs even after a prior one fails (`run_test ... || true`), so a single script surfaces every broken assertion rather than stopping at the first.

**Suite fan-out helper** (`scripts/smoketests/lib/fanout.sh`) — `run_suite` runs every entry in `TESTS`, tallies pass/fail, and returns non-zero if any failed:
```bash
run_suite() {
	local suite="${SUITE_NAME:-smoketest}"
	local tests_run=0
	local tests_passed=0
	local failed=()
	local test

	if [ "${#TESTS[@]}" -eq 0 ]; then
		fail "suite '$suite' defines no tests"
		return 1
	fi

	for test in "${TESTS[@]}"; do
		tests_run=$((tests_run + 1))
		if "$test" "$@"; then
			tests_passed=$((tests_passed + 1))
		else
			failed+=("$test")
		fi
	done
	...
}
```

## Mocking

There is no mocking framework. Smoketests deliberately avoid mocking and instead exercise real subsystems on a live, already-deployed host over SSH:
- Hardware acceleration is proven by running an actual `ffmpeg` VAAPI encode as the real service user (`sudo -n -u jellyfin ffmpeg ...`), not by checking that the render node file exists (`scripts/smoketests/ser8/test-vaapi.sh`). The header comment explicitly rejects the "presence check" as insufficient because permission and driver-ABI failures look identical to a passing presence check.
- Network connectivity checks hit real HTTPS/HTTP endpoints with `curl`, trying a Host-header fallback path when DNS resolution isn't available (`scripts/smoketests/lib/services.sh`).
- Validation scripts call real `nix eval --json` against the actual flake outputs rather than stubbing evaluation.

**What NOT to mock:** service credentials, hardware device access, and Nix evaluation are always exercised for real. If a check can't reach the real target (SSH refused, hardware absent), it fails — it is never skipped or short-circuited to a pass. This is stated explicitly in `scripts/smoketests/ser8/test-vaapi.sh`: "Nothing is skipped. A missing ffmpeg, a missing render node, or a refused `sudo -n` fails the check."

## Fixtures and Factories

No fixture/factory framework. Test inputs are inline constants at the top of each script, e.g.:
```bash
RENDER_NODE="/dev/dri/renderD128"
VAAPI_ENCODER="h264_vaapi"
SERVICE_USERS=( jellyfin frigate )
ACCELERATED_UNITS=( jellyfin frigate )
```
Synthetic test input is generated on the fly rather than stored as a fixture file, e.g. `ffmpeg`'s `-f lavfi -i "testsrc=size=320x240:rate=25:duration=1"` in the VAAPI encode test avoids needing any media fixture on disk.

## Coverage

No coverage tooling or enforced coverage target. Coverage is reasoned about qualitatively per subsystem: add or update a smoketest whenever changing deployed services, networking, DNS, gateway behavior, monitoring, or media automation (per project CLAUDE.md Testing Expectations).

## Test Types

**Nix evaluation / build checks:**
- Scope: flake-level correctness (`nix flake check`), lint (`statix check`), and that every host's system closure evaluates and dry-run builds.
- Approach: `make check`; run at the affected-host/file level first when practical, then repo-wide.

**Validation scripts (`scripts/validation/`):**
- Scope: narrow, targeted assertions about Nix module/option resolution — e.g. proving a specific upstream module version is in the resolved closure by checking option *type*, not value, since a stale module might not even expose the option (`scripts/validation/test-actual-module.sh`).
- Approach: `nix eval --json <expr>` against `.#nixosConfigurations.<host>.options...` / `.config...`, compared with a hardcoded expected value; failures accumulate into a counter and the script exits non-zero if any failed. Evaluation errors are never caught/suppressed — they must propagate so a broken gate is loud.

**Smoketests (`scripts/smoketests/`):**
- Scope: runtime behavior of already-deployed hosts, reached over SSH — service HTTP reachability, hardware acceleration, VPN network-namespace isolation, DNS resolution, ZFS pool health.
- Approach: `make smoketests-HOST` after `make test-HOST`/`make switch-HOST`; disruptive suites (e.g. NordVPN kill-switch, `scripts/smoketests/nordvpn/disruptive.sh`) are intentionally excluded from the deploy-path `all.sh` and must be run manually.

**E2E tests:** Not applicable in the traditional sense — smoketests against live hosts serve this role for infrastructure.

## Common Patterns

**Remote command execution (SSH):**
```bash
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
```
Always build the remote argv as an array and shell-quote it with `printf -v ... '%q '` before interpolating into the `ssh` command string — never interpolate raw variables directly into the SSH command.

**HTTP connectivity checks with fallback:**
```bash
if response=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
	if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
		pass "$service_name HTTPS responded with HTTP $response (via Host header)"
		return 0
	fi
fi
```
Accept `200|301|302|404` as "service is up" (404 counts because it still proves the service answered), always set `--connect-timeout` and `--max-time` explicitly.

**Nix eval assertion:**
```bash
check_eval() {
	local label=$1 expr=$2 expected=$3 actual
	actual=$(nix eval --json "$expr")
	if [ "$actual" != "$expected" ]; then
		echo "FAIL: $label is $actual, expected $expected" >&2
		failures=$((failures + 1))
		return
	fi
	echo "ok: $label = $actual"
}
```

**Diagnostic-only steps (never assert, always report):**
```bash
report_vaapi_driver() {
	...
	if [ -n "$driver" ]; then
		info "driver: $driver"
	else
		info "driver string unavailable; the encode assertions are the gate, not this line"
	fi
}
...
report_vaapi_driver || true
```
Use this pattern for informational output (version strings, driver names) that should never affect pass/fail — keep it clearly separated from asserted checks with a comment.

---

*Testing analysis: 2026-08-17*
