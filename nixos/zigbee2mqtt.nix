{
  config,
  lib,
  pkgs,
  ...
}: let
  mqttBroker = builtins.head config.services.mosquitto.listeners;
  mqttServer = "mqtt://${mqttBroker.address}:${toString mqttBroker.port}";

  coordinatorName = "zigbee";
  coordinatorSerialPort = "/dev/${coordinatorName}";
  coordinatorUdevRule = lib.concatStringsSep ", " [
    ''SUBSYSTEM=="tty"''
    ''ATTRS{idVendor}=="10c4"''
    ''ATTRS{idProduct}=="ea60"''
    ''ATTRS{manufacturer}=="ITead"''
    ''ATTRS{product}=="Sonoff Zigbee 3.0 USB Dongle Plus"''
    ''SYMLINK+="${coordinatorName}"''
  ];

  frontendPort = 8085;
  frontendSubpath = "/zigbee2mqtt";
in {
  services.udev.extraRules = "${coordinatorUdevRule}\n";

  system.activationScripts.applySerialUdevRules.text = ''
    ${pkgs.systemd}/bin/udevadm control --reload
    ${pkgs.systemd}/bin/udevadm trigger --subsystem-match=tty --action=change
  '';

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      availability.enabled = true;
      serial = {
        port = coordinatorSerialPort;
        adapter = "zstack";
      };
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = mqttServer;
        user = "zigbee2mqtt";
      };
      frontend = {
        enabled = true;
        host = "127.0.0.1";
        port = frontendPort;
        base_url = frontendSubpath;
      };
      devices =
        lib.mapAttrs' (_: device: lib.nameValuePair device.ieeeAddress {friendly_name = device.friendlyName;})
        (import ./zigbee-devices.nix);
      advanced = {
        log_level = "warning";
        pan_id = 60197;
        ext_pan_id = [30 37 140 153 119 11 242 160];
      };
    };
  };

  sops = {
    secrets = {
      zigbee2mqtt-frontend-auth-token = {};
      zigbee2mqtt-network-key = {};
    };
    templates."zigbee2mqtt.env".content = ''
      ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=${config.sops.placeholder.mosquitto-zigbee2mqtt-password}
      ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=${config.sops.placeholder.zigbee2mqtt-frontend-auth-token}
      ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=${config.sops.placeholder.zigbee2mqtt-network-key}
    '';
  };

  systemd.services.zigbee2mqtt.serviceConfig.EnvironmentFile = config.sops.templates."zigbee2mqtt.env".path;

  bilbo.backups.zigbee2mqtt.paths = [config.services.zigbee2mqtt.dataDir];
}
