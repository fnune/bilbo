{config, ...}: let
  listenAddress = "127.0.0.1";
  listenPort = 8123;

  inherit (config.services.home-assistant) configDir;

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
      "input_boolean"
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

        input_boolean.away = {
          name = "Away";
          icon = "mdi:home-export-outline";
        };
      }
      // uiManagedIncludes;
  };

  systemd.tmpfiles.settings."10-home-assistant" = uiManagedFiles;
}
