# SPDX-License-Identifier: GPL-3.0-or-later

config:

let
  inherit (builtins) listToAttrs map mapAttrs;

  select =
    names: attrs:
    listToAttrs (
      map (name: {
        inherit name;
        value = attrs.${name};
      }) names
    );

  mediaSecretNames = [
    "jellyfin_admin_password"
    "jellyfin_jordan_password"
    "jellyfin_sawnia_password"
    "jellyfin_api_key"
    "sonarr_admin_password"
    "sonarr_api_key"
    "radarr_admin_password"
    "radarr_api_key"
    "prowlarr_admin_password"
    "prowlarr_api_key"
    "qbittorrent_admin_password"
    "qbittorrent_admin_password_hash"
    "alldebrid_api_key"
    "alldebrid_transmission_admin_password"
    "sabnzbd_admin_password"
    "sabnzbd_api_key"
    "sabnzbd_nzb_key"
    "sabnzbd_usenet_username"
    "sabnzbd_usenet_password"
    "sabnzbd_usenet_provider"
  ];

  mediaTemplateNames = [
    "sonarr-config.xml"
    "radarr-config.xml"
    "prowlarr-config.xml"
    "qbittorrent.conf"
    "sabnzbd.ini"
    "nzbget.conf"
  ];

  secretMetadata = value: {
    inherit (value)
      owner
      group
      mode
      path
      ;
  };

  templateContract = value: {
    inherit (value)
      content
      owner
      group
      mode
      path
      ;
  };

  serviceContract = name: fields: select fields config.services.${name};

  exporterContract =
    name:
    select [
      "enable"
      "port"
      "url"
      "apiKeyFile"
      "openFirewall"
    ] config.services.prometheus.exporters.${name};

  unitContract =
    name:
    select [
      "description"
      "after"
      "before"
      "requires"
      "wantedBy"
      "wants"
      "script"
      "serviceConfig"
    ] config.systemd.services.${name};

  accountContract =
    name:
    select [
      "description"
      "extraGroups"
      "group"
      "home"
      "isSystemUser"
    ] config.users.users.${name};

  qBittorrentLocation = mapAttrs (_: location: {
    inherit (location) proxyPass proxyWebsockets extraConfig;
  }) config.services.nginx.virtualHosts.qbittorrent.locations;
in
{
  services = {
    jellyfin = serviceContract "jellyfin" [
      "enable"
      "user"
      "group"
      "openFirewall"
    ];
    declarativeJellyfin = select [
      "enable"
      "user"
      "group"
      "openFirewall"
      "network"
      "users"
      "apikeys"
    ] config.services.declarative-jellyfin;
    sonarr = serviceContract "sonarr" [
      "enable"
      "user"
      "group"
      "dataDir"
      "openFirewall"
      "settings"
    ];
    radarr = serviceContract "radarr" [
      "enable"
      "user"
      "group"
      "dataDir"
      "openFirewall"
      "settings"
    ];
    prowlarr = serviceContract "prowlarr" [
      "enable"
      "dataDir"
      "openFirewall"
      "settings"
      "useVpnNamespace"
    ];
    qbittorrent = serviceContract "qbittorrent" [
      "enable"
      "user"
      "group"
      "profileDir"
      "serverConfig"
      "torrentingPort"
      "webuiPort"
      "openFirewall"
      "extraArgs"
    ];
    nzbget = serviceContract "nzbget" [
      "enable"
      "user"
      "group"
      "settings"
    ];
    sabnzbd = serviceContract "sabnzbd" [
      "enable"
      "user"
      "group"
      "openFirewall"
      "configFile"
    ];
  };

  secrets = mapAttrs (_: secretMetadata) (select mediaSecretNames config.sops.secrets);
  templates = mapAttrs (_: templateContract) (select mediaTemplateNames config.sops.templates);

  exporters = {
    sonarr = exporterContract "exportarr-sonarr";
    radarr = exporterContract "exportarr-radarr";
    prowlarr = exporterContract "exportarr-prowlarr";
    jellyfin = unitContract "jellyfin-exporter";
  };

  nginx.qbittorrent = {
    inherit (config.services.nginx.virtualHosts.qbittorrent) serverName forceSSL enableACME;
    locations = qBittorrentLocation;
  };

  accounts = listToAttrs (
    map
      (name: {
        inherit name;
        value = accountContract name;
      })
      [
        "jellyfin"
        "sonarr"
        "radarr"
        "prowlarr"
        "qbittorrent"
        "nzbget"
        "sabnzbd"
      ]
  );

  firewall = {
    inherit (config.networking.firewall) allowedTCPPorts allowedUDPPorts;
  };

  units = {
    mediaConfig = unitContract "media-config";
    servarrsSetup = unitContract "servarrs-setup";
    downloadClientsSetup = unitContract "download-clients-setup";
    mediaTarget = select [
      "description"
      "after"
      "before"
      "requires"
      "wantedBy"
      "wants"
    ] config.systemd.targets.media-setup;
  };

  generatedScripts = {
    mediaConfig = config.systemd.services.media-config.script;
    servarrsSetup = config.systemd.services.servarrs-setup.script;
    downloadClientsSetup = config.systemd.services.download-clients-setup.script;
    jellyfinExporter = config.systemd.services.jellyfin-exporter.serviceConfig.ExecStart;
  };
}
