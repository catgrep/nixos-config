{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking = {
    # Enable networkd for consistent networking across hosts
    useNetworkd = lib.mkDefault true;
    useDHCP = false;

    # Firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # HTTP
        443 # HTTPS
      ];
      allowedUDPPortRanges = [
        {
          # Mosh default port range
          from = 60000;
          to = 61000;
        }
      ];
    };

    # DNS fallback
    nameservers = lib.mkDefault [
      "1.1.1.1"
      "1.0.0.1"
    ];
  };

  # Enable mDNS for .local domain resolution
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };
}
