{...}: let
  secrets = "/etc/nixos/secrets";

  discoveryTopic = "readwrite homeassistant/#";

  mkClient = name: acl: {
    passwordFile = "${secrets}/mosquitto-${name}-password";
    inherit acl;
  };
in {
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        users = {
          frigate = mkClient "frigate" ["readwrite frigate/#"];

          zigbee2mqtt = mkClient "zigbee2mqtt" [
            "readwrite zigbee2mqtt/#"
            discoveryTopic
          ];

          home-assistant = mkClient "home-assistant" [
            "readwrite frigate/#"
            "readwrite zigbee2mqtt/#"
            discoveryTopic
          ];
        };
      }
    ];
  };
}
