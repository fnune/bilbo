{config, ...}: let
  clients = ["frigate" "zigbee2mqtt" "home-assistant"];
  passwordSecret = name: "mosquitto-${name}-password";

  discoveryTopic = "readwrite homeassistant/#";

  mkClient = name: acl: {
    passwordFile = config.sops.secrets.${passwordSecret name}.path;
    inherit acl;
  };
in {
  sops.secrets = builtins.listToAttrs (map (name: {
      name = passwordSecret name;
      value = {};
    })
    clients);

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
