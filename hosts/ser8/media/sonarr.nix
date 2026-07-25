# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  services.sonarr.enable = true;

  sops.secrets = {
    "sonarr_admin_password" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };

    "sonarr_api_key" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  sops.templates."sonarr-config.xml" = {
    content = ''
      <Config>
        <LogLevel>info</LogLevel>
        <EnableSsl>False</EnableSsl>
        <Port>8989</Port>
        <SslPort>9898</SslPort>
        <UrlBase></UrlBase>
        <BindAddress>*</BindAddress>
        <LaunchBrowser>False</LaunchBrowser>
        <AuthenticationMethod>Forms</AuthenticationMethod>
        <AuthenticationRequired>Enabled</AuthenticationRequired>
        <Username>admin</Username>
        <Password>${config.sops.placeholder."sonarr_admin_password"}</Password>
        <ApiKey>${config.sops.placeholder."sonarr_api_key"}</ApiKey>
        <Branch>main</Branch>
        <InstanceName>Sonarr</InstanceName>
      </Config>
    '';
    owner = "sonarr";
    group = "sonarr";
    mode = "0600";
  };

  services.prometheus.exporters.exportarr-sonarr = {
    enable = lib.mkDefault true;
    port = 9707;
    url = "http://localhost:8989";
    apiKeyFile = config.sops.secrets.sonarr_api_key.path;
    openFirewall = true;
  };

  systemd.services.media-config = {
    before = lib.mkOrder 200 [ "sonarr.service" ];
    script = lib.mkOrder 200 (
      lib.removeSuffix "\n" ''
        # Deploy arr service configurations
        configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}
      ''
    );
  };
}
