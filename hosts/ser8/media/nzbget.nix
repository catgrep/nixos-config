# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

{
  services.nzbget.enable = true;

  sops.templates."nzbget.conf" = {
    content = ''
      MainDir=/var/lib/nzbget
      DestDir=/mnt/media/downloads/usenet/complete/default
      InterDir=/mnt/media/downloads/usenet/incomplete
      NzbDir=/var/lib/nzbget/nzb
      QueueDir=/var/lib/nzbget/queue
      TempDir=/var/lib/nzbget/tmp
      ScriptDir=/var/lib/nzbget/scripts
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
      Category1.DestDir=/mnt/media/downloads/usenet/complete/tv
      Category1.Unpack=yes
      Category1.Extensions=
      Category1.Aliases=

      Category2.Name=movies
      Category2.DestDir=/mnt/media/downloads/usenet/complete/movies
      Category2.Unpack=yes
      Category2.Extensions=
      Category2.Aliases=

      Category3.Name=prowlarr
      Category3.DestDir=/mnt/media/downloads/usenet/complete/prowlarr
      Category3.Unpack=yes
      Category3.Extensions=
      Category3.Aliases=

      Category4.Name=default
      Category4.DestDir=/mnt/media/downloads/usenet/complete/default
      Category4.Unpack=yes
      Category4.Extensions=
      Category4.Aliases=
    '';
    owner = "nzbget";
    group = "nzbget";
    mode = "0600";
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
