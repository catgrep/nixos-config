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
          coordinates = "0.233,0.209,0.003,0.253,0.004,0.996,0.999,0.99,0.997,0.111,0.773,0.088,0.436,0.076";
          objects = [
            "person"
            "car"
          ];
          inertia = 3;
        };
        motion.mask = "0,0.23,0.23,0.203,0.428,0.047,0.643,0.037,0.643,0,0.001,0";
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
          coordinates = "0.21,0.994,0.248,0.517,0.135,0,0.405,0,0.998,0,0.998,0.996";
          objects = [
            "person"
            "car"
            "dog"
            "cat"
          ];
          inertia = 3;
        };
        motion.mask = [
          "0.219,1,0.244,0.526,0.133,0,0.001,0.004,0.002,0.99"
          "0.404,0.053,0.4,0.004,0,0,0,0.043"
        ];
        review.alerts.required_zones = [ "garage_zone" ];
      };
    };

    # Tapo C120
    backyard_side_gate = {
      host = "192.168.68.52";
      frigate = {
        zones.backyard_side_gate_zone = {
          coordinates = "0.34,0.984,0.779,0.99,0.891,0.729,0.308,0.103,0.169,0.082,0.168,0.125,0.302,0.218";
          objects = [
            "person"
            "dog"
            "cat"
          ];
          inertia = 3;
        };
        motion.mask = [
          "0.136,0.984,0.283,0.988,0.273,0.238,0.058,0.097,0.001,0.148,0.006,0.694"
          "0.811,0.986,0.994,0.568,0.998,0.994"
          "0.853,0.014,0.993,0.546,0.997,0.014"
          "0.278,0,0.915,0.696,0.983,0.542,0.842,0.016"
          "0,0.045,0.402,0.049,0.405,0,0.001,0"
        ];
        review.alerts.required_zones = [ "backyard_side_gate_zone" ];
      };
    };

    # Tapo C120
    backyard_charger = {
      host = "192.168.68.58";
      frigate = {
        zones.backyard_charger_zone = {
          coordinates = "0.499,0.205,0.742,0.156,0.592,0.409,0.345,0.99,0.012,0.992,0.003,0.62,0.46,0.279";
          objects = [
            "person"
            "car"
            "cat"
            "dog"
          ];
          inertia = 3;
        };
        motion.mask = [
          "0.614,0.568,0.829,0.841,0.937,0.809,0.928,0.246,0.669,0.162,0.583,0.261"
          "0.147,0.497,0.461,0.271,0.576,0.021,0.153,0.002,0.107,0.136"
          "0,0.047,0.4,0.049,0.402,0,0.001,0.002"
          "0.354,0.99,0.596,0.405,0.937,0.805,0.905,0.99"
        ];
        review.alerts.required_zones = [ "backyard_charger_zone" ];
      };
    };

    # Tapo C200, pan-tilt. The litter box zones are drawn against a fixed
    # framing: moving the camera invalidates them, so the camera carries no
    # onvif block and gets no PTZ controls in Frigate.
    #
    # One zone per litter box, so a visit records which box was used.
    # Zone membership is judged by the bottom centre of the object's
    # bounding box, so each polygon covers the floor at its box rather
    # than the box itself; a cat sitting inside a box keeps its bounding
    # box bottom inside the polygon, where a polygon drawn on the box
    # alone would report it as having left. loitering_time keeps a cat
    # that only walks past from counting as a visit.
    indoor_hallway = {
      host = "192.168.68.54";
      frigate = {
        zones = {
          litter_box_basic = {
            coordinates = "0.628,0.148,0.611,0.658,0.849,0.683,0.876,0.177";
            objects = [ "cat" ];
            inertia = 3;
            loitering_time = 3;
          };
          litter_box_cleo = {
            coordinates = "0.274,0.346,0.621,0.345,0.635,1,0.295,1";
            objects = [ "cat" ];
            inertia = 3;
            loitering_time = 3;
          };
        };
        motion.mask = [
          "0,0.047,0.362,0.051,0.361,0.004,0,0"
          "0.154,0.552,0.248,0.072,0,0.074,0,0.998"
        ];
        review = {
          alerts.labels = [ ];
          detections = {
            labels = [ "cat" ];
            required_zones = [
              "litter_box_basic"
              "litter_box_cleo"
            ];
          };
        };
      };
    };
  };
}
