# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  ...
}:

{
  # SOPS configuration for media services
  sops = {
    defaultSopsFile = ../../secrets/beelink-homelab.yaml;
    defaultSopsFormat = "yaml";

    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Jellyfin authentication (pbkdf2-sha512 hash)
      "jellyfin_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "jellyfin_jordan_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Sonarr authentication
      "sonarr_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Radarr authentication
      "radarr_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };

    # Templates for config files
    templates = {
      "sonarr-config.xml" = {
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
            <Branch>main</Branch>
            <InstanceName>Sonarr</InstanceName>
          </Config>
        '';
        owner = "sonarr";
        group = "sonarr";
        mode = "0600";
      };

      "radarr-config.xml" = {
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
            <Branch>master</Branch>
            <InstanceName>Radarr</InstanceName>
          </Config>
        '';
        owner = "radarr";
        group = "radarr";
        mode = "0600";
      };
    };
  };

  # SystemD services to use templated config files
  systemd.services = {
    sonarr-config = {
      description = "Deploy Sonarr configuration with secrets";
      before = [ "sonarr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Ensure config directory exists
        mkdir -p /var/lib/sonarr/.config/NzbDrone

        # Always copy templated config (simpler approach)
        cp ${config.sops.templates."sonarr-config.xml".path} /var/lib/sonarr/.config/NzbDrone/config.xml
        chown sonarr:sonarr /var/lib/sonarr/.config/NzbDrone/config.xml
        chmod 600 /var/lib/sonarr/.config/NzbDrone/config.xml
        echo "✓ Updated Sonarr configuration with secrets"
      '';
    };

    radarr-config = {
      description = "Deploy Radarr configuration with secrets";
      before = [ "radarr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Ensure config directory exists
        mkdir -p /var/lib/radarr/.config/Radarr

        # Always copy templated config (simpler approach)
        cp ${config.sops.templates."radarr-config.xml".path} /var/lib/radarr/.config/Radarr/config.xml
        chown radarr:radarr /var/lib/radarr/.config/Radarr/config.xml
        chmod 600 /var/lib/radarr/.config/Radarr/config.xml
        echo "✓ Updated Radarr configuration with secrets"
      '';
    };
  };
}
