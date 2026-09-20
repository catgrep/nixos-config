# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  services.radarr.enable = true;

  sops.secrets = {
    "radarr_admin_password" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };

    "radarr_api_key" = {
      owner = "root";
      group = "root";
      mode = "0600";
      # Consumers snapshot the key at start: exportarr loads it via
      # LoadCredential, and the setup oneshots push it into peer
      # services only when they run.
      restartUnits = [
        "prometheus-exportarr-radarr-exporter.service"
        "servarrs-setup.service"
        "download-clients-setup.service"
      ];
    };
  };

  sops.templates."radarr-config.xml" = {
    content = ''
      <Config>
        <LogLevel>info</LogLevel>
        <EnableSsl>False</EnableSsl>
        <Port>7878</Port>
        <SslPort>9898</SslPort>
        <UrlBase></UrlBase>
        <BindAddress>*</BindAddress>
        <LaunchBrowser>False</LaunchBrowser>
        <AuthenticationMethod>Forms</AuthenticationMethod>
        <AuthenticationRequired>Enabled</AuthenticationRequired>
        <Username>admin</Username>
        <Password>${config.sops.placeholder."radarr_admin_password"}</Password>
        <ApiKey>${config.sops.placeholder."radarr_api_key"}</ApiKey>
        <Branch>master</Branch>
        <InstanceName>Radarr</InstanceName>
      </Config>
    '';
    owner = "radarr";
    group = config.services.radarr.group;
    mode = "0600";
    # Without this, a re-rendered config.xml never reaches the live file:
    # media-config's cp only runs when systemd (re)starts it, and radarr
    # parses config.xml once at startup.
    restartUnits = [
      "media-config.service"
      "radarr.service"
    ];
  };

  services.prometheus.exporters.exportarr-radarr = {
    enable = lib.mkDefault true;
    port = 9708;
    url = "http://localhost:7878";
    apiKeyFile = config.sops.secrets.radarr_api_key.path;
    openFirewall = true;
  };

  homelab.monitoring.systemd.units = lib.mkMerge [
    (lib.mkIf config.services.radarr.enable {
      "radarr.service".expectedRunning = true;
    })
    (lib.mkIf config.services.prometheus.exporters.exportarr-radarr.enable {
      "prometheus-exportarr-radarr-exporter.service".expectedRunning = true;
    })
  ];

  systemd.services.media-config = {
    before = lib.mkOrder 300 [ "radarr.service" ];
    script = lib.mkOrder 300 (
      lib.removeSuffix "\n" ''
        configure_arr radarr ${config.sops.templates."radarr-config.xml".path}
      ''
    );
  };
}
