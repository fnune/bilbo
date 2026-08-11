{config, ...}: let
  mqttBroker = builtins.head config.services.mosquitto.listeners;
  mqttServer = "mqtt://${mqttBroker.address}:${toString mqttBroker.port}";

  coordinatorSerialPort = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_REPLACE_WITH_DONGLE_SERIAL-if00-port0";

  frontendPort = 8085;
  frontendSubpath = "/zigbee2mqtt";
in {
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      permit_join = false;
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
      advanced = {
        log_level = "warning";
        network_key = "GENERATE";
        pan_id = "GENERATE";
        ext_pan_id = "GENERATE";
      };
    };
  };

  systemd.services.zigbee2mqtt.serviceConfig.EnvironmentFile = "/etc/nixos/secrets/zigbee2mqtt.env";
}
