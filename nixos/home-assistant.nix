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

  frigateAvailability = {
    availability_topic = "frigate/available";
    payload_available = "online";
    payload_not_available = "offline";
  };

  frigateReview = "https://frigate.fnune.com/review";
  mainStream = cameraName;
  restreamed = stream: "rtsp://127.0.0.1:8554/${stream}";
  cameraSwitch = "switch.indoor_camera";
  cameraEntity = "camera.indoor";
  motionEntity = "binary_sensor.indoor_motion";
  snapshotEntity = "camera.indoor_last_person";
  reviewEntity = "sensor.indoor_last_review";

  cameraMode = "input_select.camera_mode";
  alwaysOn = "On";
  alwaysOff = "Off";
  followPresence = "Auto";

  presenceDevices = [
    "device_tracker.merry"
    "device_tracker.estella"
  ];

  nobodyHome =
    if presenceDevices == []
    then "false"
    else let
      quoted = lib.concatMapStringsSep ", " (device: "'${device}'") presenceDevices;
    in "{{ [${quoted}] | reject('is_state', 'not_home') | list | count == 0 }}";

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

        lovelace.dashboards = {
          nixos-lovelace = null;
          bilbo-watchtower = {
            mode = "yaml";
            filename = "ui-lovelace.yaml";
            title = "Watchtower";
            icon = "mdi:binoculars";
            show_in_sidebar = true;
          };
        };

        input_select.camera_mode = {
          name = "Camera";
          icon = "mdi:cctv";
          options = [alwaysOn alwaysOff followPresence];
        };

        camera = [
          {
            platform = "ffmpeg";
            name = "Indoor";
            input = restreamed mainStream;
          }
        ];

        mqtt.binary_sensor = [
          ({
              name = "Indoor motion";
              unique_id = "frigate_${cameraName}_motion";
              state_topic = cameraTopic "motion";
              payload_on = "ON";
              payload_off = "OFF";
              device_class = "motion";
            }
            // frigateAvailability)
        ];

        mqtt.camera = [
          ({
              name = "Indoor last person";
              unique_id = "frigate_${cameraName}_person_snapshot";
              topic = cameraTopic "person/snapshot";
            }
            // frigateAvailability)
        ];

        mqtt.sensor = [
          ({
              name = "Indoor last review";
              unique_id = "frigate_${cameraName}_last_review";
              state_topic = "frigate/reviews";
              value_template = "{{ value_json.after.severity }}";
              json_attributes_topic = "frigate/reviews";
              json_attributes_template = "{{ value_json.after | tojson }}";
              icon = "mdi:alert-decagram";
            }
            // frigateAvailability)
        ];

        mqtt.switch = [
          ({
              name = "Indoor camera";
              unique_id = "frigate_${cameraName}_enabled";
              state_topic = cameraTopic "enabled/state";
              command_topic = cameraTopic "enabled/set";
              payload_on = "ON";
              payload_off = "OFF";
              retain = true;
              icon = "mdi:cctv";
              entity_category = "config";
            }
            // frigateAvailability)
        ];

        automation = [
          {
            alias = "Camera follows its mode";
            id = "camera-follows-its-mode";
            mode = "restart";
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

    lovelaceConfig = {
      views = [
        {
          title = "Watchtower";
          path = "home";
          type = "sections";
          max_columns = 2;
          sections = [
            {
              type = "grid";
              cards = [
                {
                  type = "picture-entity";
                  entity = cameraEntity;
                  camera_view = "live";
                  show_name = false;
                  show_state = false;
                }
                {
                  type = "entities";
                  entities = [cameraMode reviewEntity motionEntity];
                }
                {
                  type = "button";
                  name = "Review in Frigate";
                  icon = "mdi:open-in-new";
                  show_state = false;
                  tap_action = {
                    action = "url";
                    url_path = frigateReview;
                  };
                }
              ];
            }
            {
              type = "grid";
              cards = [
                {
                  type = "history-graph";
                  title = "Camera and motion";
                  hours_to_show = 48;
                  entities = [cameraSwitch motionEntity];
                }
                {
                  type = "picture-entity";
                  title = "Last person seen";
                  entity = snapshotEntity;
                  show_name = false;
                  show_state = false;
                  tap_action = {
                    action = "url";
                    url_path = frigateReview;
                  };
                }
                {
                  type = "logbook";
                  title = "Mode changes";
                  hours_to_show = 48;
                  target.entity_id = [cameraMode];
                }
              ];
            }
          ];
        }
      ];
    };
  };

  systemd.tmpfiles.settings."10-home-assistant" = uiManagedFiles;
}
