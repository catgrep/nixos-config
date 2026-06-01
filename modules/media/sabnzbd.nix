# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  unstable,
  ...
}:

let
  cfg = config.services.sabnzbd;
in
{
  # sabnzbd 5.0.3: nixpkgs 25.11 has 4.5.5; bump via overlay until stable catches up.
  # sabctools must move 8.2.6 → 9.4.0 alongside this, which requires rebuilding
  # pythonEnv and installPhase (both are let bindings unreachable via overrideAttrs alone).
  config.nixpkgs.overlays = [
    (
      final: prev:
      let
        sabctoolsVersion = "9.4.0";
        sabctoolsHash = "sha256-JkRRtZnzp83dMKXiuqOXaTm8UOpkkhmjH2ysS8TY0DI=";
        pythonEnv = final.python3.withPackages (
          ps: with ps; [
            apprise
            babelfish
            cffi
            chardet
            cheetah3
            cheroot
            cherrypy
            configobj
            cryptography
            feedparser
            guessit
            jaraco-classes
            jaraco-collections
            jaraco-context
            jaraco-functools
            jaraco-text
            more-itertools
            notify2
            orjson
            portend
            puremagic
            pycparser
            pysocks
            python-dateutil
            pytz
            rarfile
            rebulk
            (ps.sabctools.overridePythonAttrs (_: {
              version = sabctoolsVersion;
              src = final.fetchPypi {
                pname = "sabctools";
                version = sabctoolsVersion;
                hash = sabctoolsHash;
              };
            }))
            sabyenc3
            sgmllib3k
            six
            tempora
            zc-lockfile
          ]
        );
        path = final.lib.makeBinPath [
          final.coreutils
          # SABnzbd 5.x release builds use par2cmdline-turbo 1.4; stable 25.11 has 1.3.
          unstable.par2cmdline-turbo
          final.unrar
          final.unzip
          final.p7zip
          final.util-linux
        ];
      in
      {
        sabnzbd = prev.sabnzbd.overrideAttrs (_: rec {
          version = "5.0.3";
          src = final.fetchFromGitHub {
            owner = "sabnzbd";
            repo = "sabnzbd";
            rev = version;
            hash = "sha256-UTzdBM64fCbyY8+h94G8XbTIdoXk0mDZjlnGPywRB4Q=";
          };
          buildInputs = [ pythonEnv ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -R * $out/
            mkdir $out/bin
            echo "${pythonEnv}/bin/python $out/SABnzbd.py \$*" > $out/bin/sabnzbd
            chmod +x $out/bin/sabnzbd
            wrapProgram $out/bin/sabnzbd --set PATH ${path}
            runHook postInstall
          '';
        });
      }
    )
  ];

  config = {
    # Add sabnzbd user to media group for shared file access
    users.users.sabnzbd = lib.mkIf cfg.enable {
      extraGroups = [ "media" ];
    };

    systemd.services.sabnzbd = lib.mkIf cfg.enable {
      serviceConfig = {
        ExecStart = lib.mkForce "${pkgs.sabnzbd}/bin/sabnzbd --log-all --disable-file-log -f ${cfg.configFile}";
        StandardOutput = "journal";
        StandardError = "journal";
        Type = lib.mkForce "simple";
        GuessMainPID = lib.mkForce "yes";
      };
    };
    # Open SABnzbd port when enabled
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ 8085 ];
  };
}
