# SPDX-License-Identifier: GPL-3.0-or-later

# Drops the distrusted roots from /etc/ssl and points every client at that
# bundle. nixpkgs' certifi reads NIX_SSL_CERT_FILE and otherwise falls back
# to the bundle it was built with, and requests installed outside nixpkgs
# reads REQUESTS_CA_BUNDLE, so services get both through the systemd
# environment as well as shells.
let
  bundle = "/etc/ssl/certs/ca-certificates.crt";
  variables = {
    NIX_SSL_CERT_FILE = bundle;
    REQUESTS_CA_BUNDLE = bundle;
  };
in
{
  security.pki.caCertificateBlacklist = import ../../lib/distrusted-cas.nix;
  environment.variables = variables;
  systemd.globalEnvironment = variables;
}
