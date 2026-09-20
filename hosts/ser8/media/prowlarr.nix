# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  services.prowlarr = {
    enable = true;
    useVpnNamespace = false; # Keep on regular network to avoid tracker bans
  };

  sops.secrets = {
    "prowlarr_api_key" = {
      owner = "root";
      group = "root";
      mode = "0600";
      # Consumers snapshot the key at start: exportarr loads it via
      # LoadCredential, and the setup oneshots push it into peer
      # services only when they run.
      restartUnits = [
        "prometheus-exportarr-prowlarr-exporter.service"
        "servarrs-setup.service"
        "download-clients-setup.service"
      ];
    };

    "prowlarr_admin_password" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  sops.templates."prowlarr-config.xml" = {
    content = ''
      <Config>
        <LogLevel>info</LogLevel>
        <EnableSsl>False</EnableSsl>
        <Port>9696</Port>
        <SslPort>9898</SslPort>
        <UrlBase></UrlBase>
        <BindAddress>*</BindAddress>
        <LaunchBrowser>False</LaunchBrowser>
        <AuthenticationMethod>Forms</AuthenticationMethod>
        <AuthenticationRequired>Enabled</AuthenticationRequired>
        <ApiKey>${config.sops.placeholder."prowlarr_api_key"}</ApiKey>
        <Branch>master</Branch>
        <InstanceName>Prowlarr</InstanceName>
        <SslCertPath></SslCertPath>
        <SslCertPassword></SslCertPassword>
      </Config>
    '';
    owner = "prowlarr";
    group = "prowlarr";
    mode = "0600";
    # Without this, a re-rendered config.xml never reaches the live file:
    # media-config's cp only runs when systemd (re)starts it, and prowlarr
    # parses config.xml once at startup.
    restartUnits = [
      "media-config.service"
      "prowlarr.service"
    ];
  };

  services.prometheus.exporters.exportarr-prowlarr = {
    enable = lib.mkDefault true;
    port = 9709;
    url = "http://localhost:9696";
    apiKeyFile = config.sops.secrets.prowlarr_api_key.path;
    openFirewall = true;
  };

  homelab.monitoring.systemd.units = lib.mkMerge [
    (lib.mkIf config.services.prowlarr.enable {
      "prowlarr.service".expectedRunning = true;
    })
    (lib.mkIf config.services.prometheus.exporters.exportarr-prowlarr.enable {
      "prometheus-exportarr-prowlarr-exporter.service".expectedRunning = true;
    })
  ];

  systemd.services.media-config = {
    before = lib.mkOrder 400 [ "prowlarr.service" ];
    script = lib.mkOrder 400 (
      lib.removeSuffix "\n" ''
        configure_arr prowlarr ${config.sops.templates."prowlarr-config.xml".path}
      ''
    );
  };
}
