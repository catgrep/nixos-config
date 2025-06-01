{ config, lib, pkgs, ... }:

{
  services.transmission = {
    enable = lib.mkDefault false;
    user = "bobby";
    group = "users";

    settings = {
      download-dir = "/mnt/downloads/complete";
      incomplete-dir = "/mnt/downloads/incomplete";
      incomplete-dir-enabled = true;

      rpc-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      rpc-host-whitelist-enabled = false;

      peer-port = 51413;
      port-forwarding-enabled = true;

      encryption = 1;
      lpd-enabled = true;
      dht-enabled = true;
      pex-enabled = true;

      utp-enabled = true;

      speed-limit-down-enabled = false;
      speed-limit-up-enabled = false;

      ratio-limit-enabled = true;
      ratio-limit = 2;
    };
  };

  # Open Transmission ports when enabled
  networking.firewall = lib.mkIf config.services.transmission.enable {
    allowedTCPPorts = [ 9091 51413 ];
    allowedUDPPorts = [ 51413 ];
  };

  # Ensure download directories exist
  systemd.tmpfiles.rules = lib.mkIf config.services.transmission.enable [
    "d /mnt/downloads 0755 bobby users -"
    "d /mnt/downloads/complete 0755 bobby users -"
    "d /mnt/downloads/incomplete 0755 bobby users -"
  ];
}
