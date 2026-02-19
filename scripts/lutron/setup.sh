#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Pairs with a Lutron Caseta Smart Bridge using lap-pair (pylutron-caseta) and
# prints the generated certificate files formatted as SOPS-ready YAML block scalars.
#
# Usage: ./scripts/lutron/setup.sh <bridge-ip>
# Or via Makefile: make lutron-setup BRIDGE_IP=192.168.68.x

. ./scripts/lib/all.sh

set -euo pipefail

title "Lutron Caseta Bridge Pairing"

usage() {
    echo ""
    echo "Usage: $0 <bridge-ip>"
    echo ""
    echo "Pairs with a Lutron Caseta Smart Bridge and generates TLS certificate files"
    echo "required for the Home Assistant lutron_caseta YAML integration."
    echo ""
    echo "Arguments:"
    echo "  bridge-ip    IP address of the Lutron Smart Bridge (e.g. 192.168.68.100)"
    echo ""
    echo "The pairing process requires physical access to the bridge:"
    echo "  Press the small black button on the back when prompted by lap-pair."
    echo ""
    echo "Output files (~/.config/pylutron_caseta/):"
    echo "  <ip>-bridge.crt   Bridge CA certificate   ->  SOPS key: lutron_bridge_crt"
    echo "  <ip>.crt          Client certificate      ->  SOPS key: lutron_caseta_crt"
    echo "  <ip>.key          Client private key      ->  SOPS key: lutron_caseta_key"
    echo ""
    echo "After adding to SOPS, deploy with: make switch-ser8"
}

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

bridge_ip="$1"

# Basic IP format validation
if ! [[ "$bridge_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    fail "Invalid IP address: $(fmt_red "$bridge_ip")"
    exit 1
fi

cert_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pylutron_caseta"
key_file="$cert_dir/$bridge_ip.key"
crt_file="$cert_dir/$bridge_ip.crt"
bridge_crt_file="$cert_dir/$bridge_ip-bridge.crt"

info "Bridge IP:   $(fmt_blue "$bridge_ip")"
info "Cert output: $(fmt_blue "$cert_dir")"
echo ""
warn "Have the Smart Bridge nearby."
warn "Press the small black button on the back when lap-pair prompts you."
echo ""
confirm

info "Starting lap-pair via nix-shell (first run may fetch packages)..."
echo ""
nix-shell -p python3Packages.pylutron-caseta --run "lap-pair $bridge_ip"
echo ""

# Verify all three output files were created
missing=0
for f in "$key_file" "$crt_file" "$bridge_crt_file"; do
    if [ ! -f "$f" ]; then
        fail "Expected output file not found: $f"
        missing=1
    fi
done
if [ "$missing" -eq 1 ]; then
    fail "Pairing may have failed. Check lap-pair output above."
    exit 1
fi

pass "Certificate files generated:"
echo "  $key_file"
echo "  $crt_file"
echo "  $bridge_crt_file"
echo ""

title "Next: Add to SOPS"
info "Run $(fmt_blue "make sops-edit-ser8") and add the following entries:"
echo ""
echo "lutron_caseta_key: |"
sed 's/^/  /' "$key_file"
echo ""
echo "lutron_caseta_crt: |"
sed 's/^/  /' "$crt_file"
echo ""
echo "lutron_bridge_crt: |"
sed 's/^/  /' "$bridge_crt_file"
echo ""
info "Then deploy: $(fmt_blue "make switch-ser8")"
