# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = pkgs.writeText "blackbox.yml" (
      builtins.toJSON {
        modules = {
          http_2xx = {
            prober = "http";
            timeout = "10s";
            http = {
              valid_http_versions = [
                "HTTP/1.1"
                "HTTP/2.0"
              ];
              preferred_ip_protocol = "ip4";
              follow_redirects = true;
            };
          };
          # For services whose web UI demands credentials on every request.
          # An unauthenticated probe against such a service gets 401, which is
          # the strongest liveness signal available without shipping the
          # credential to the prober: the listener accepted the connection and
          # the application answered. 200 stays valid so the probe keeps
          # passing if authentication is ever removed.
          http_2xx_401 = {
            prober = "http";
            timeout = "10s";
            http = {
              valid_http_versions = [
                "HTTP/1.1"
                "HTTP/2.0"
              ];
              preferred_ip_protocol = "ip4";
              follow_redirects = true;
              valid_status_codes = [
                200
                401
              ];
            };
          };
          icmp_ping = {
            prober = "icmp";
            timeout = "5s";
          };
          # TCP with TLS rather than an HTTP probe. This module exists to read
          # certificate expiry, and a handshake is all that takes. An HTTP
          # prober would also demand a 2xx body, which an auth-gated service
          # (401) or one that rejects the proxied hostname (403) never
          # returns, failing the probe while the certificate is fine.
          tls_connect = {
            prober = "tcp";
            timeout = "10s";
            tcp = {
              preferred_ip_protocol = "ip4";
              tls = true;
            };
          };
        };
      }
    );
  };
}
