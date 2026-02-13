# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, pkgs, ... }:

{
  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "10s";
          http = {
            valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
            preferred_ip_protocol = "ip4";
            follow_redirects = true;
          };
        };
        icmp_ping = {
          prober = "icmp";
          timeout = "5s";
        };
        tls_connect = {
          prober = "http";
          timeout = "10s";
          http = {
            preferred_ip_protocol = "ip4";
            valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
          };
        };
      };
    });
  };
}
