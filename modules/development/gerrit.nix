{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gerrit;
in
{
  options.services.gerrit = {
    enable = lib.mkEnableOption "Gerrit Code Review";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "*:8080";
      description = "Address and port on which Gerrit will listen";
    };

    serverId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Unique server ID for this Gerrit instance";
    };

    basePath = lib.mkOption {
      type = lib.types.str;
      default = "git";
      description = "Path where git repositories will be stored";
    };

    canonicalWebUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://gerrit.homelab.local";
      description = "Canonical URL for accessing this Gerrit instance";
    };

    jvmHeapLimit = lib.mkOption {
      type = lib.types.str;
      default = "2g";
      description = "JVM heap limit for Gerrit";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.gerrit = {
      isSystemUser = true;
      group = "gerrit";
      home = "/var/lib/gerrit";
      createHome = true;
      description = "Gerrit service user";
    };

    users.groups.gerrit = { };

    systemd.services.gerrit = {
      description = "Gerrit Code Review";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "gerrit";
        Group = "gerrit";
        WorkingDirectory = "/var/lib/gerrit";
        ExecStartPre =
          let
            gerritInit = pkgs.writeShellScript "gerrit-init" ''
              # Download Gerrit WAR if not present
              if [ ! -f /var/lib/gerrit/gerrit.war ]; then
                echo "Downloading Gerrit..."
                ${pkgs.curl}/bin/curl -L -o /var/lib/gerrit/gerrit.war \
                  https://gerrit-releases.storage.googleapis.com/gerrit-3.9.1.war
              fi

              # Initialize Gerrit site if not already done
              if [ ! -f /var/lib/gerrit/etc/gerrit.config ]; then
                echo "Initializing Gerrit site..."
                ${pkgs.jdk17}/bin/java -jar /var/lib/gerrit/gerrit.war init \
                  --batch \
                  --no-auto-start \
                  -d /var/lib/gerrit
              fi

              # Update configuration
              cat > /var/lib/gerrit/etc/gerrit.config <<EOF
              [gerrit]
                basePath = ${cfg.basePath}
                serverId = ${cfg.serverId}
                canonicalWebUrl = ${cfg.canonicalWebUrl}

              [container]
                javaOptions = "-Xmx${cfg.jvmHeapLimit}"
                user = gerrit

              [database]
                type = h2
                database = db/ReviewDB

              [index]
                type = lucene

              [auth]
                type = DEVELOPMENT_BECOME_ANY_ACCOUNT

              [receive]
                enableSignedPush = false

              [sendemail]
                smtpServer = localhost

              [sshd]
                listenAddress = *:29418

              [httpd]
                listenUrl = proxy-http://${cfg.listenAddress}

              [cache]
                directory = cache

              [plugins]
                allowRemoteAdmin = true
              EOF
            '';
          in
          "${gerritInit}";

        ExecStart = "${pkgs.jdk17}/bin/java -jar /var/lib/gerrit/gerrit.war daemon -d /var/lib/gerrit";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = "/var/lib/gerrit";
      };
    };

    # Ensure data directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/gerrit 0755 gerrit gerrit -"
      "d /var/lib/gerrit/git 0755 gerrit gerrit -"
      "d /var/lib/gerrit/etc 0755 gerrit gerrit -"
      "d /var/lib/gerrit/db 0755 gerrit gerrit -"
      "d /var/lib/gerrit/cache 0755 gerrit gerrit -"
      "d /var/lib/gerrit/logs 0755 gerrit gerrit -"
    ];

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [
      8080 # HTTP
      29418 # SSH for Git
    ];

    # Required packages
    environment.systemPackages = with pkgs; [
      git
      jdk17
    ];

    # Nginx reverse proxy configuration (optional)
    services.nginx.virtualHosts."gerrit.homelab.local" = lib.mkIf config.services.nginx.enable {
      locations."/" = {
        proxyPass = "http://localhost:8080";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Host $host;
        '';
      };
    };
  };
}
