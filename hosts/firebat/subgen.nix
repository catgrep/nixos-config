# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  services.subgen = {
    enable = true;
    modelPackage = pkgs.callPackage ../../packages/faster-whisper-medium { };
    listenAddress = "192.168.68.63";
    threads = 6;
    concurrentTranscriptions = 1;
  };

  systemd.services.subgen.serviceConfig = {
    CPUWeight = 25;
    MemoryMax = "8G";
    Nice = 10;
  };

  networking.firewall = {
    extraCommands = ''
      iptables -A nixos-fw -i eno1 -p tcp \
        -s 192.168.68.65/32 -d 192.168.68.63/32 --dport 9000 \
        -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -i eno1 -p tcp \
        -s 192.168.68.65/32 -d 192.168.68.63/32 --dport 9000 \
        -j nixos-fw-accept 2>/dev/null || true
    '';
  };
}
