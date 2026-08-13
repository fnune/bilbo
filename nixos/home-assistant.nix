{
  config,
  lib,
  ...
}: let
  listenAddress = "127.0.0.1";
  listenPort = 8123;

  inherit (config.services.home-assistant) configDir;

  cameraName = "indoor";
  cameraTopic = suffix: "frigate/${cameraName}/${suffix}";
  cameraSwitch = "switch.indoor_camera";

  cameraMode = "input_select.camera_mode";
  alwaysOn = "On";
  alwaysOff = "Off";
  followPresence = "Auto";

  presenceDevices = [];

  nobodyHome =
    if presenceDevices == []
    then "false"
    else let
      quoted = lib.concatMapStringsSep ", " (device: "'${device}'") presenceDevices;
    in "{{ [${quoted}] | select('is_state', 'home') | list | count == 0 }}";

  switchCameraTo = action: [
    {
      inherit action;
      target.entity_id = cameraSwitch;
    }
  ];

  whenModeIs = mode: extraConditions: {
    conditions =
      [
        {
          condition = "state";
          entity_id = cameraMode;
          state = mode;
        }
      ]
      ++ extraConditions;
  };

  uiManagedDomains = {
    automation = "automations.yaml";
    scene = "scenes.yaml";
    script = "scripts.yaml";
  };

  uiManagedIncludes =
    builtins.listToAttrs
    (builtins.attrValues (builtins.mapAttrs (domain: file: {
        name = "${domain} ui";
        value = "!include ${file}";
      })
      uiManagedDomains));

  uiManagedFiles =
    builtins.listToAttrs
    (map (file: {
        name = "${configDir}/${file}";
        value.f = {
          user = "hass";
          group = "hass";
          mode = "0640";
          argument = "[]";
        };
      })
      (builtins.attrValues uiManagedDomains));
in {
  services.home-assistant = {
    enable = true;

    extraComponents = [
      "default_config"
      "fritz"
      "input_select"
      "met"
      "mobile_app"
      "mqtt"
      "radio_browser"
    ];

    config =
      {
        homeassistant = {
          name = "Bilbo";
          latitude = 52.52;
          longitude = 13.405;
          elevation = 34;
          unit_system = "metric";
          time_zone = config.time.timeZone;
        };

        default_config = {};

        http = {
          server_host = [listenAddress];
          server_port = listenPort;
          use_x_forwarded_for = true;
          trusted_proxies = ["127.0.0.1" "::1"];
        };

        input_select.camera_mode = {
          name = "Camera";
          icon = "mdi:cctv";
          options = [alwaysOn alwaysOff followPresence];
        };

        mqtt.switch = [
          {
            name = "Indoor camera";
            unique_id = "frigate_${cameraName}_enabled";
            state_topic = cameraTopic "enabled/state";
            command_topic = cameraTopic "enabled/set";
            payload_on = "ON";
            payload_off = "OFF";
            retain = true;
            icon = "mdi:cctv";
          }
        ];

        automation = [
          {
            alias = "Camera follows its mode";
            id = "camera-follows-its-mode";
            mode = "single";
            triggers =
              [
                {
                  trigger = "state";
                  entity_id = cameraMode;
                }
                {
                  trigger = "homeassistant";
                  event = "start";
                }
                {
                  trigger = "state";
                  entity_id = cameraSwitch;
                  to = ["on" "off"];
                }
              ]
              ++ lib.optional (presenceDevices != []) {
                trigger = "state";
                entity_id = presenceDevices;
              };
            actions = [
              {
                choose = [
                  (whenModeIs alwaysOn []
                    // {sequence = switchCameraTo "switch.turn_on";})
                  (whenModeIs alwaysOff []
                    // {sequence = switchCameraTo "switch.turn_off";})
                  (whenModeIs followPresence [
                      {
                        condition = "template";
                        value_template = nobodyHome;
                      }
                    ]
                    // {sequence = switchCameraTo "switch.turn_on";})
                ];
                default = switchCameraTo "switch.turn_off";
              }
            ];
          }
        ];
      }
      // uiManagedIncludes;
  };

  systemd.tmpfiles.settings."10-home-assistant" = uiManagedFiles;
}
