# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.subgen;
  stableTsWhisperlessPath = ../../packages/stable-ts-whisperless;
  stableTsWhisperless = pkgs.python312Packages.callPackage stableTsWhisperlessPath { };
  defaultPackage = pkgs.callPackage ../../packages/subgen {
    stable-ts-whisperless = stableTsWhisperless;
  };
in
{
  options.services.subgen = {
    enable = lib.mkEnableOption "native Subgen subtitle generation service";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "pkgs.callPackage packages/subgen { }";
      description = "Subgen package to run";
    };

    modelPackage = lib.mkOption {
      type = lib.types.package;
      description = "Pinned CTranslate2 Whisper model directory";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address on which Subgen listens";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "TCP port on which Subgen listens";
    };

    computeType = lib.mkOption {
      type = lib.types.str;
      default = "int8";
      description = "CTranslate2 compute type";
    };

    threads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
      description = "CPU threads used for Whisper inference";
    };

    concurrentTranscriptions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum number of concurrent transcriptions";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional Subgen environment variables";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.subgen = {
      description = "Subgen subtitle generation service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        WEBHOOK_HOST = cfg.listenAddress;
        WEBHOOK_PORT = toString cfg.port;
        WHISPER_MODEL = toString cfg.modelPackage;
        MODEL_PATH = "/var/lib/subgen/models";
        TRANSCRIBE_DEVICE = "cpu";
        COMPUTE_TYPE = cfg.computeType;
        WHISPER_THREADS = toString cfg.threads;
        CONCURRENT_TRANSCRIPTIONS = toString cfg.concurrentTranscriptions;
        PROCESS_ADDED_MEDIA = "False";
        PROCESS_MEDIA_ON_PLAY = "False";
        MONITOR = "False";
        RELOAD_SCRIPT_ON_CHANGE = "False";
        UPDATE = "False";
        DEBUG = "False";
      }
      // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "subgen";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/subgen";
        UMask = "0077";

        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        CapabilityBoundingSet = "";
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
      };
    };
  };
}
