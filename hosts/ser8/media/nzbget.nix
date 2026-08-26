# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  permissionNormalizer = pkgs.writeShellApplication {
    name = "nzbget-normalize-permissions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./nzbget-normalize-permissions.sh;
  };
in

{
  services.nzbget.enable = true;

  sops.templates."nzbget.conf" = {
    content = ''
      MainDir=/var/lib/nzbget
      DestDir=/mnt/downloads/complete/default
      InterDir=/mnt/downloads/incomplete
      NzbDir=/var/lib/nzbget/nzb
      QueueDir=/var/lib/nzbget/queue
      TempDir=/var/lib/nzbget/tmp
      ScriptDir=${permissionNormalizer}/bin
      LogFile=/var/lib/nzbget/nzbget.log

      ControlIP=0.0.0.0
      ControlPort=6789
      ControlUsername=admin
      ControlPassword=${config.sops.placeholder."sabnzbd_admin_password"}
      SecureControl=no
      AuthorizedIP=
      UMask=0002

      CertStore=/etc/ssl/certs/ca-certificates.crt
      CertCheck=yes

      Server1.Active=yes
      Server1.Name=${config.sops.placeholder."sabnzbd_usenet_provider"}
      Server1.Level=0
      Server1.Optional=no
      Server1.Group=0
      Server1.Host=${config.sops.placeholder."sabnzbd_usenet_provider"}
      Server1.Encryption=yes
      Server1.Port=563
      Server1.Username=${config.sops.placeholder."sabnzbd_usenet_username"}
      Server1.Password=${config.sops.placeholder."sabnzbd_usenet_password"}
      Server1.JoinGroup=no
      Server1.Cipher=
      Server1.Connections=100
      Server1.Retention=0
      Server1.CertVerification=strict
      Server1.IpVersion=auto

      Category1.Name=tv
      Category1.DestDir=/mnt/downloads/complete/tv
      Category1.Unpack=yes
      Category1.Extensions=nzbget-normalize-permissions
      Category1.Aliases=

      Category2.Name=movies
      Category2.DestDir=/mnt/downloads/complete/movies
      Category2.Unpack=yes
      Category2.Extensions=nzbget-normalize-permissions
      Category2.Aliases=

      Category3.Name=prowlarr
      Category3.DestDir=/mnt/downloads/complete/prowlarr
      Category3.Unpack=yes
      Category3.Extensions=nzbget-normalize-permissions
      Category3.Aliases=

      Category4.Name=default
      Category4.DestDir=/mnt/downloads/complete/default
      Category4.Unpack=yes
      Category4.Extensions=nzbget-normalize-permissions
      Category4.Aliases=
    '';
    owner = "nzbget";
    group = config.services.nzbget.group;
    mode = "0600";
    # Without this, a content-only change to the rendered template (e.g. a
    # download-path edit) never reaches the live nzbget.conf: media-config's
    # cp only runs when systemd decides to (re)start it, and nzbget.service
    # itself never re-reads the file on its own. Restarting media-config
    # first redeploys the copy, then restarting nzbget picks it up.
    restartUnits = [
      "media-config.service"
      "nzbget.service"
    ];
  };

  systemd.services.media-config = {
    before = lib.mkOrder 500 [ "nzbget.service" ];
    script = lib.mkOrder 500 (
      lib.removeSuffix "\n" ''
        configure_arr nzbget ${config.sops.templates."nzbget.conf".path}
      ''
    );
  };
}
