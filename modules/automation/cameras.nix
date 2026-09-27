# SPDX-License-Identifier: GPL-3.0-or-later

# Camera inventory shared by the Frigate, go2rtc, HomeKit, and Home Assistant
# modules. Each entry is one physical camera, keyed by the name that every
# derived identifier is built from: the go2rtc restreams, the Frigate camera,
# the HomeKit accessory, the Home Assistant entities, and the Lovelace cards
# and notification subviews. Renaming an entry renames all of them.
#
# All cameras are TP-Link Tapo models and expose the same RTSP layout:
#   stream1 - main stream (1080p or 2K depending on model), record and live
#   stream2 - 640x360 sub stream, detection
# Frigate-side wiring that follows from that layout is generated in
# frigate.nix. Only what is genuinely camera-specific lives here: the
# address, and the Frigate zones, motion masks, and review policy that are
# drawn against each camera's own framing.
{ lib, ... }:

let
  # "backyard_side_gate" -> "Backyard Side Gate"
  titleCase = name: lib.concatMapStringsSep " " lib.toSentenceCase (lib.splitString "_" name);

  cameraModule =
    { name, ... }:
    {
      options = {
        host = lib.mkOption {
          type = lib.types.str;
          description = "LAN address of the camera.";
        };

        displayName = lib.mkOption {
          type = lib.types.str;
          default = titleCase name;
          defaultText = lib.literalExpression "titleCase name";
          description = "Name shown for the camera in HomeKit and Home Assistant.";
        };

        frigate = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            Camera-level Frigate settings merged over the generated camera
            block: zones, motion masks, and review policy. Zone and mask
            polygons are drawn in the Frigate UI and copied here.
          '';
        };
      };
    };
in
{
  options.homelab.cameras = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule cameraModule);
    default = { };
    description = "Physical cameras, keyed by the name all derived identifiers use.";
  };

  config.homelab.cameras = {
    # Tapo C120
    driveway = {
      host = "192.168.68.88";
      frigate = {
        zones.driveway_zone = {
          coordinates = "0.079,0.027,0.989,0.033,1,0.611,0.292,1";
          objects = [
            "person"
            "car"
          ];
          inertia = 3;
        };
        motion.mask = "0.025,0.163,0.118,0.118,0.207,0.183,0.313,0.12,0.325,0.012,0.005,0.006";
        review.alerts.required_zones = [ "driveway_zone" ];
      };
    };

    # Tapo C120
    front_door = {
      host = "192.168.68.64";
      frigate = {
        zones.front_door_zone = {
          coordinates = "0.013,0.189,0.919,0.034,0.97,0.835,0.105,0.988";
          objects = [
            "person"
            "dog"
            "cat"
          ];
          inertia = 3;
        };
        review.alerts.required_zones = [ "front_door_zone" ];
      };
    };

    # Tapo C120
    garage = {
      host = "192.168.68.66";
      frigate = {
        zones.garage_zone = {
          coordinates = "0.144,0,1,0,1,1,0.158,1";
          objects = [
            "person"
            "car"
            "dog"
            "cat"
          ];
          inertia = 3;
        };
        review.alerts.required_zones = [ "garage_zone" ];
      };
    };

    # Tapo C120
    backyard_side_gate = {
      host = "192.168.68.52";
      frigate = {
        zones.backyard_side_gate_zone = {
          coordinates = "0.053,0.023,0.953,0.023,0.833,0.829,0.428,0.982,0.114,0.361";
          objects = [
            "person"
            "dog"
            "cat"
          ];
          inertia = 3;
        };
        motion.mask = [
          "0.181,0.157,0.258,0.253,0.288,0.452,0.281,0.974,0.097,0.959,0.013,0.495"
          "0.811,0.986,0.994,0.568,0.998,0.994"
          "0.853,0.014,0.993,0.546,0.997,0.014"
        ];
        review.alerts.required_zones = [ "backyard_side_gate_zone" ];
      };
    };

    # Tapo C120
    backyard_charger = {
      host = "192.168.68.58";
      frigate = {
        zones.backyard_charger_zone = {
          coordinates = "0.336,0.011,0.819,0.035,0.671,0.932,0.195,0.915";
          objects = [
            "person"
            "car"
            "cat"
            "dog"
          ];
          inertia = 3;
        };
        motion.mask = "0.717,0.874,0.829,0.841,0.937,0.809,0.935,0.301,0.782,0.254,0.689,0.446";
        review.alerts.required_zones = [ "backyard_charger_zone" ];
      };
    };

    # Tapo C200, pan-tilt. The litter_box zone is drawn against a fixed
    # framing: moving the camera invalidates it, so the camera carries no
    # onvif block and gets no PTZ controls in Frigate.
    #
    # Zone membership is judged by the bottom centre of the object's
    # bounding box, so the polygon covers the floor at the box entrance
    # rather than the box itself. loitering_time keeps a cat that only
    # walks past from counting as a visit.
    indoor_hallway = {
      host = "192.168.68.54";
      frigate = {
        zones.litter_box = {
          coordinates = "0.271,0.34,0.932,0.047,0.784,0.944,0.308,0.927";
          objects = [ "cat" ];
          inertia = 3;
          loitering_time = 5;
        };
        motion.mask = "0,0.006,0.245,0.006,0.308,0.933,0.044,0.795";
        review = {
          alerts.labels = [ ];
          detections = {
            labels = [ "cat" ];
            required_zones = [ "litter_box" ];
          };
        };
      };
    };
  };
}
