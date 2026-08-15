{
  config,
  lib,
  pkgs,
  ...
}: let
  listenAddress = "127.0.0.1";
  listenPort = 8123;

  inherit (config.services.home-assistant) configDir;

  curl = lib.getExe pkgs.curl;
  jq = lib.getExe pkgs.jq;
  base64 = "${pkgs.coreutils}/bin/base64";

  frigateUrl = "https://${config.services.frigate.hostname}";
  cameraName = builtins.head (builtins.attrNames config.services.frigate.settings.cameras);
  cameraTopic = suffix: "frigate/${cameraName}/${suffix}";

  frigateAvailability = {
    availability_topic = "frigate/available";
    payload_available = "online";
    payload_not_available = "offline";
  };

  frigateComponent = pkgs.home-assistant-custom-components.frigate.overrideAttrs (previous: {
    doCheck = false;
    doInstallCheck = false;

    postPatch =
      (previous.postPatch or "")
      + ''
        substituteInPlace custom_components/frigate/views.py \
          --replace-fail \
            'config_entry.options.get(CONF_NOTIFICATION_PROXY_ENABLE, True)' \
            'False'
      '';
  });

  frigateApi = "http://127.0.0.1:8971/api";
  frigateUser = "admin";
  frigatePasswordFile = "/etc/nixos/secrets/frigate-admin-password";
  frigatePasswordCredential = "frigate-password";

  openFrigateSession = ''
    session=$(mktemp)
    trap 'rm -f "$session"' EXIT

    ${curl} -sf -c "$session" -X POST ${frigateApi}/login \
      --header 'Content-Type: application/json' \
      --data "$(${jq} -nc --arg u ${frigateUser} \
        --arg p "$(cat "$CREDENTIALS_DIRECTORY/${frigatePasswordCredential}")" \
        '{user: $u, password: $p}')" > /dev/null

    fetch() { ${curl} -sf -b "$session" "${frigateApi}/$1"; }
  '';

  shownAlerts = 5;

  unreviewedAlerts = pkgs.writeShellScript "frigate-unreviewed-alerts" ''
    set -e
    ${openFrigateSession}

    alerts=$(fetch "review?reviewed=0&severity=alert&limit=100")
    scores=$(fetch "events?limit=40&cameras=${cameraName}&labels=person")
    total=$(echo "$alerts" | ${jq} 'length')

    items=""
    for row in $(echo "$alerts" | ${jq} -r '.[:${toString shownAlerts}][] | @base64'); do
      alert=$(echo "$row" | ${base64} -d)
      detection=$(echo "$alert" | ${jq} -r '.data.detections[0] // empty')

      thumbnail=""
      if [ -n "$detection" ]; then
        encoded=$(fetch "events/$detection/thumbnail.jpg" | ${base64} -w0 || true)
        [ -n "$encoded" ] && thumbnail="data:image/jpeg;base64,$encoded"
      fi

      score=$(echo "$scores" | ${jq} -r --arg d "$detection" \
        'map(select(.id == $d)) | first | ((.data.top_score // .data.score // 0) * 100 | round) // empty')

      items="$items$(echo "$alert" | ${jq} -c --arg t "$thumbnail" --arg s "$score" \
        '{id, start: .start_time, objects: (.data.objects // [] | join(", ")), thumbnail: $t, score: $s}')"
    done

    echo "$items" | ${jq} -sc --argjson total "$total" '{count: length, total: $total, items: .}'
  '';

  cameraEntity = "camera.indoor";
  cameraSwitch = "switch.indoor_camera";
  cameraMode = "input_select.camera_mode";

  notificationTopic = "bilbo/notify";

  neverWatch = "Disabled";
  watchWhenAway = "When away";
  alwaysWatch = "Always";

  bedroomLight = {
    id = "bedroom_light";
    name = "Bedroom light";
  };

  livingRoomLamp = {
    id = "living_room_lamp";
    name = "Living room lamp";
  };

  lights = [bedroomLight livingRoomLamp];

  lightEntity = light: "light.${light.id}";
  lightPowerSensor = light: "binary_sensor.${light.id}_power";

  simulatedLight = lightEntity livingRoomLamp;
  simulationMode = "input_select.occupancy_simulation";
  sunsetSensor = "sensor.sunset";

  neverSimulate = "Disabled";
  simulateWhenAway = "When away (${sunsetWindow}, for ${onDuration})";
  alwaysSimulate = "Always";

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

  simulating = {
    condition = "or";
    conditions = [
      {
        condition = "state";
        entity_id = simulationMode;
        state = alwaysSimulate;
      }
      {
        condition = "and";
        conditions = [
          {
            condition = "state";
            entity_id = simulationMode;
            state = simulateWhenAway;
          }
          {
            condition = "template";
            value_template = nobodyHome;
          }
        ];
      }
    ];
  };

  sunsetOffsetMinutes = -20;
  lightsOnWithin = {
    from = 0;
    to = 45;
  };
  lightsStayOnFor = {
    from = 90;
    to = 210;
  };

  waitMinutes = range: {
    delay.minutes = "{{ range(${toString range.from}, ${toString range.to}) | random }}";
  };

  clockOffset = minutes: let
    absolute =
      if minutes < 0
      then -minutes
      else minutes;
    pad = lib.fixedWidthNumber 2;
  in "${lib.optionalString (minutes < 0) "-"}${pad (absolute / 60)}:${pad (lib.mod absolute 60)}:00";

  signedMinutes = minutes:
    if minutes < 0
    then "-${toString (-minutes)}"
    else "+${toString minutes}";

  sunsetWindow = "sunset ${signedMinutes (sunsetOffsetMinutes + lightsOnWithin.from)} to ${signedMinutes (sunsetOffsetMinutes + lightsOnWithin.to)}";
  onDuration = "${toString lightsStayOnFor.from}-${toString lightsStayOnFor.to} min";

  switchCameraTo = action: [
    {
      inherit action;
      target.entity_id = cameraSwitch;
    }
  ];

  whenModeIs = mode: conditions: action: {
    conditions =
      [
        {
          condition = "state";
          entity_id = cameraMode;
          state = mode;
        }
      ]
      ++ conditions;
    sequence = switchCameraTo action;
  };

  fullWidth.grid_options.columns = "full";

  cameraCard = view:
    fullWidth
    // {
      type = "custom:advanced-camera-card";
      cameras = [{camera_entity = cameraEntity;}];
      view.default = view;
      dimensions = {
        aspect_ratio_mode = "static";
        aspect_ratio = "16:9";
      };
    };

  uiManagedDomains = {
    automation = "automations.yaml";
    scene = "scenes.yaml";
    script = "scripts.yaml";
  };

  uiManagedIncludes =
    lib.mapAttrs'
    (domain: file: lib.nameValuePair "${domain} ui" "!include ${file}")
    uiManagedDomains;

  uiManagedFiles =
    lib.mapAttrs'
    (_: file:
      lib.nameValuePair "${configDir}/${file}" {
        f = {
          user = "hass";
          group = "hass";
          mode = "0640";
          argument = "[]";
        };
      })
    uiManagedDomains;
in {
  services.home-assistant = {
    enable = true;

    customComponents = [frigateComponent];
    customLovelaceModules = [pkgs.home-assistant-custom-lovelace-modules.advanced-camera-card];

    extraComponents = [
      "command_line"
      "default_config"
      "fritz"
      "input_select"
      "met"
      "mobile_app"
      "mqtt"
      "radio_browser"
      "template"
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

        input_select = {
          camera_mode = {
            name = "Camera";
            icon = "mdi:cctv";
            options = [neverWatch watchWhenAway alwaysWatch];
          };

          occupancy_simulation = {
            name = "Occupancy simulation";
            icon = "mdi:home-lightbulb";
            options = [neverSimulate simulateWhenAway alwaysSimulate];
          };
        };

        template = [
          {
            sensor = [
              {
                name = "Sunset";
                unique_id = "sunset_clock";
                icon = "mdi:weather-sunset-down";
                state = "{{ as_timestamp(state_attr('sun.sun', 'next_setting')) | timestamp_custom('%H:%M') }}";
              }
            ];

            binary_sensor =
              map (light: {
                name = "${light.name} power";
                unique_id = "${light.id}_power";
                device_class = "connectivity";
                state = "{{ not is_state('${lightEntity light}', 'unavailable') }}";
              })
              lights;
          }
        ];

        command_line = [
          {
            sensor = {
              name = "Unreviewed alerts";
              unique_id = "frigate_unreviewed_alerts";
              command = "${unreviewedAlerts}";
              value_template = "{{ value_json.count }}";
              json_attributes = ["items" "total"];
              scan_interval = 60;
            };
          }
        ];

        mqtt.switch = [
          (frigateAvailability
            // {
              name = "Indoor camera";
              unique_id = "frigate_${cameraName}_enabled";
              state_topic = cameraTopic "enabled/state";
              command_topic = cameraTopic "enabled/set";
              payload_on = "ON";
              payload_off = "OFF";
              retain = true;
              icon = "mdi:cctv";
              entity_category = "config";
            })
        ];

        automation =
          [
            {
              alias = "Living room lamp simulates someone being in";
              id = "living-room-lamp-simulates-someone-being-in";
              mode = "restart";
              triggers = [
                {
                  trigger = "sun";
                  event = "sunset";
                  offset = clockOffset sunsetOffsetMinutes;
                }
              ];
              conditions = [simulating];
              actions = [
                (waitMinutes lightsOnWithin)
                {
                  action = "light.turn_on";
                  target.entity_id = simulatedLight;
                  data = {
                    brightness_pct = 60;
                    color_temp_kelvin = 2700;
                  };
                }
                (waitMinutes lightsStayOnFor)
                {
                  "if" = [simulating];
                  "then" = [
                    {
                      action = "light.turn_off";
                      target.entity_id = simulatedLight;
                    }
                  ];
                }
              ];
            }
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
                    (whenModeIs neverWatch [] "switch.turn_off")
                    (whenModeIs alwaysWatch [] "switch.turn_on")
                    (whenModeIs watchWhenAway [
                      {
                        condition = "template";
                        value_template = nobodyHome;
                      }
                    ] "switch.turn_on")
                  ];
                  default = switchCameraTo "switch.turn_off";
                }
              ];
            }
          ]
          ++ lib.optional (presenceDevices != []) {
            alias = "Say so when nobody is home and the camera is off";
            id = "say-so-when-nobody-is-home-and-the-camera-is-off";
            triggers = [
              {
                trigger = "state";
                entity_id = presenceDevices;
                to = "not_home";
                for = "00:15:00";
              }
            ];
            conditions = [
              {
                condition = "template";
                value_template = nobodyHome;
              }
              {
                condition = "state";
                entity_id = cameraMode;
                state = neverWatch;
              }
            ];
            actions = [
              {
                action = "mqtt.publish";
                data = {
                  topic = notificationTopic;
                  payload = builtins.toJSON {
                    topic = "infra";
                    title = "Home · nobody in, camera off";
                    body = "The camera mode is Disabled, so nothing is being recorded while you are out.";
                  };
                };
              }
            ];
          }
          ++ lib.optional (presenceDevices != []) {
            alias = "Lights go out when everyone has left";
            id = "lights-go-out-when-everyone-has-left";
            triggers = [
              {
                trigger = "state";
                entity_id = presenceDevices;
                to = "not_home";
                for = "00:05:00";
              }
            ];
            conditions = [
              {
                condition = "template";
                value_template = nobodyHome;
              }
            ];
            actions = [
              {
                action = "light.turn_off";
                target.entity_id = map lightEntity lights;
              }
            ];
          };
      }
      // uiManagedIncludes;

    lovelaceConfig.views = [
      {
        title = "Watchtower";
        path = "home";
        type = "sections";
        max_columns = 2;
        sections = [
          {
            type = "grid";
            cards = [
              (fullWidth
                // {
                  type = "entities";
                  entities =
                    [
                      cameraMode
                      simulationMode
                      sunsetSensor
                    ]
                    ++ map lightPowerSensor lights
                    ++ [
                      {type = "divider";}
                    ]
                    ++ presenceDevices
                    ++ [
                      {
                        type = "weblink";
                        url = frigateUrl;
                        name = "Open Frigate";
                        icon = "mdi:open-in-new";
                      }
                    ];
                })
              (cameraCard "live")
              (cameraCard "timeline")
            ];
          }
          {
            type = "grid";
            cards =
              [
                (fullWidth
                  // {
                    type = "history-graph";
                    title = "Camera";
                    hours_to_show = 48;
                    entities = [cameraSwitch];
                  })
              ]
              ++ lib.concatMap (light: [
                (fullWidth
                  // {
                    type = "history-graph";
                    title = light.name;
                    hours_to_show = 48;
                    entities = [(lightEntity light)];
                  })
                (fullWidth
                  // {
                    type = "tile";
                    entity = lightEntity light;
                    features_position = "bottom";
                    features = [
                      {type = "light-brightness";}
                      {type = "light-color-temp";}
                    ];
                  })
              ])
              lights
              ++ [
                (fullWidth
                  // {
                    type = "markdown";
                    title = "Unreviewed alerts";
                    content = ''
                      {% set alerts = state_attr('sensor.unreviewed_alerts', 'items') or [] %}
                      {% if alerts | count == 0 %}
                      Nothing to review.
                      {% else %}
                      <table width="100%">
                      {% for alert in alerts -%}
                      <tr>
                      <td width="118">{% if alert.thumbnail %}<a href="${frigateUrl}/review?id={{ alert.id }}"><img src="{{ alert.thumbnail }}" width="110"></a>{% endif %}</td>
                      <td><a href="${frigateUrl}/review?id={{ alert.id }}">{{ alert.start | timestamp_custom('%a %-d %b, %H:%M') }}</a><br>{{ alert.objects }}</td>
                      <td align="right" width="60"><b>{{ (alert.score ~ '%') if alert.score else '-' }}</b></td>
                      </tr>
                      {% endfor -%}
                      </table>
                      {%- set hidden = (state_attr('sensor.unreviewed_alerts', 'total') or 0) - (alerts | count) %}
                      {%- if hidden > 0 %}

                      [{{ hidden }} more waiting](${frigateUrl}/review)
                      {%- endif %}
                      {% endif %}
                    '';
                  })
              ];
          }
        ];
      }
    ];
  };

  systemd.services.home-assistant.serviceConfig.LoadCredential = [
    "${frigatePasswordCredential}:${frigatePasswordFile}"
  ];

  systemd.tmpfiles.settings."10-home-assistant" = uiManagedFiles;
}
