{
  config,
  lib,
  pkgs,
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

  cameraSwitch = "switch.indoor_camera";
  cameraEntity = "camera.indoor";

  frigateComponent = pkgs.home-assistant-custom-components.frigate.overrideAttrs (previous: {
    doCheck = false;
    doInstallCheck = false;

    postPatch =
      (previous.postPatch or "")
      + ''
        substituteInPlace custom_components/frigate/views.py \
          --replace-fail \
            'config_entry.options.get(CONF_NOTIFICATION_PROXY_ENABLE, True)' \
            'config_entry.options.get(CONF_NOTIFICATION_PROXY_ENABLE, False)'
      '';
  });
  frigateUrl = "https://frigate.fnune.com";

  frigateApi = "http://127.0.0.1:8971/api";
  frigateUser = "admin";
  alertLimit = 5;
  frigatePasswordFile = "/etc/nixos/secrets/frigate-admin-password";
  frigatePasswordCredential = "frigate-password";

  asFrigateUser = query:
    pkgs.writeShellScript "frigate-query" ''
      set -e

      session=$(mktemp)
      trap 'rm -f "$session"' EXIT

      ${pkgs.curl}/bin/curl -sf -c "$session" -X POST ${frigateApi}/login \
        --header 'Content-Type: application/json' \
        --data "$(${pkgs.jq}/bin/jq -nc --arg u ${frigateUser} \
          --arg p "$(cat "$CREDENTIALS_DIRECTORY/${frigatePasswordCredential}")" '{user: $u, password: $p}')" > /dev/null

      ${pkgs.curl}/bin/curl -sf -b "$session" "${frigateApi}/${query}"
    '';

  unreviewedWithThumbnails = pkgs.writeShellScript "frigate-unreviewed-alerts" ''
    set -e

    session=$(mktemp)
    trap 'rm -f "$session"' EXIT

    ${pkgs.curl}/bin/curl -sf -c "$session" -X POST ${frigateApi}/login \
      --header 'Content-Type: application/json' \
      --data "$(${pkgs.jq}/bin/jq -nc --arg u ${frigateUser} \
        --arg p "$(cat "$CREDENTIALS_DIRECTORY/${frigatePasswordCredential}")" '{user: $u, password: $p}')" > /dev/null

    fetch() {
      ${pkgs.curl}/bin/curl -sf -b "$session" "${frigateApi}/$1"
    }

    alerts=$(fetch "review?reviewed=0&severity=alert&limit=${toString alertLimit}")
    scores=$(fetch "events?limit=40&cameras=${cameraName}&labels=person")

    items=""
    for row in $(echo "$alerts" | ${pkgs.jq}/bin/jq -r '.[] | @base64'); do
      alert=$(echo "$row" | ${pkgs.coreutils}/bin/base64 -d)
      detection=$(echo "$alert" | ${pkgs.jq}/bin/jq -r '.data.detections[0] // empty')

      thumbnail=""
      if [ -n "$detection" ]; then
        encoded=$(fetch "events/$detection/thumbnail.jpg" | ${pkgs.coreutils}/bin/base64 -w0 || true)
        [ -n "$encoded" ] && thumbnail="data:image/jpeg;base64,$encoded"
      fi

      score=$(echo "$scores" | ${pkgs.jq}/bin/jq -r --arg d "$detection" \
        'map(select(.id == $d)) | first | ((.data.top_score // .data.score // 0) * 100 | round) // empty')

      items="$items$(echo "$alert" | ${pkgs.jq}/bin/jq -c \
        --arg t "$thumbnail" --arg s "$score" \
        '{id: .id, start: .start_time, objects: (.data.objects // [] | join(", ")), thumbnail: $t, score: $s}')"
    done

    echo "$items" | ${pkgs.jq}/bin/jq -sc '{count: length, items: .}'
  '';

  unreviewedAlerts = pkgs.writeShellScript "frigate-unreviewed-alerts" ''
    ${asFrigateUser "review?reviewed=0&severity=alert&limit=10"} \
      | ${pkgs.jq}/bin/jq -c '{
          count: length,
          items: [ .[] | {
            id: .id,
            start: .start_time,
            objects: (.data.objects // [] | join(", ")),
            detection: (.data.detections // [] | first)
          } ]
        }'
  '';

  cameraCard = view: {
    type = "custom:advanced-camera-card";
    cameras = [{camera_entity = cameraEntity;}];
    view.default = view;
    dimensions = {
      aspect_ratio_mode = "static";
      aspect_ratio = "16:9";
    };
    grid_options.columns = "full";
  };

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

    customComponents = [frigateComponent];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      advanced-camera-card
      card-mod
    ];

    extraComponents = [
      "default_config"
      "fritz"
      "input_select"
      "met"
      "mobile_app"
      "command_line"
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

        command_line = [
          {
            sensor = {
              name = "Unreviewed alerts";
              unique_id = "frigate_unreviewed_alerts";
              command = "${unreviewedWithThumbnails}";
              value_template = "{{ value_json.count }}";
              json_attributes = ["items"];
              scan_interval = 60;
            };
          }
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
                  type = "entities";
                  entities = [
                    cameraMode
                    {
                      type = "weblink";
                      url = frigateUrl;
                      name = "Open Frigate";
                      icon = "mdi:open-in-new";
                    }
                  ];
                  grid_options.columns = "full";
                }
                (cameraCard "live")
                (cameraCard "timeline")
                {
                  type = "history-graph";
                  title = "Camera";
                  hours_to_show = 48;
                  entities = [cameraSwitch];
                  grid_options.columns = "full";
                }
              ];
            }
            {
              type = "grid";
              cards = [
                {
                  type = "markdown";
                  title = "Unreviewed alerts";
                  content = ''
                    {% set alerts = state_attr('sensor.unreviewed_alerts', 'items') or [] %}
                    {% if alerts | count == 0 %}
                    Nothing to review.
                    {% else %}
                    {% for alert in alerts -%}
                    <a href="${frigateUrl}/review?id={{ alert.id }}">{% if alert.thumbnail %}<img src="{{ alert.thumbnail }}">{% endif %}<span>{{ alert.start | timestamp_custom('%a %-d %b, %H:%M') }} <small>· {{ alert.objects }}</small></span><b>{{ (alert.score ~ '%') if alert.score else '-' }}</b></a>
                    {% endfor -%}
                    {% endif %}
                  '';
                  card_mod.style = {
                    "." = ''
                      ha-card .card-header {
                        font-size: 16px;
                        font-weight: 500;
                        line-height: 1.2;
                        padding: 12px 16px 0;
                      }
                    '';
                    "ha-markdown$" = ''
                      a {
                        display: flex;
                        align-items: center;
                        gap: 14px;
                        padding: 10px 4px;
                        border-bottom: 1px solid var(--divider-color);
                        color: var(--primary-text-color);
                        text-decoration: none;
                      }
                      a:last-of-type { border-bottom: none; }
                      br { display: none; }
                      a img {
                        width: 104px;
                        height: 58px;
                        object-fit: cover;
                        border-radius: 8px;
                        flex: 0 0 auto;
                      }
                      a span { flex: 1 1 auto; line-height: 1.35; }
                      a small { opacity: 0.6; }
                      a b {
                        flex: 0 0 auto;
                        font-variant-numeric: tabular-nums;
                        font-weight: 500;
                      }
                    '';
                  };
                  grid_options.columns = "full";
                }
              ];
            }
          ];
        }
      ];
    };
  };

  systemd.services.home-assistant.serviceConfig.LoadCredential = [
    "${frigatePasswordCredential}:${frigatePasswordFile}"
  ];

  systemd.tmpfiles.settings."10-home-assistant" = uiManagedFiles;
}
