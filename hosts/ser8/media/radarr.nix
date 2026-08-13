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
  };

  services.prometheus.exporters.exportarr-radarr = {
    enable = lib.mkDefault true;
    port = 9708;
    url = "http://localhost:7878";
    apiKeyFile = config.sops.secrets.radarr_api_key.path;
    openFirewall = true;
  };

  systemd.services.media-config = {
    before = lib.mkOrder 300 [ "radarr.service" ];
    script = lib.mkOrder 300 (
      lib.removeSuffix "\n" ''
        configure_arr radarr ${config.sops.templates."radarr-config.xml".path}
      ''
    );
  };
}
