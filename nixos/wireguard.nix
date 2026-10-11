{config, ...}: let
  subnet = "10.100.0";
  bilbo = "${subnet}.1";
  listenPort = 51820;

  devices = {
    merry = {
      address = "${subnet}.2";
      publicKey = "/tHwUVsCa6m6A7tzSCK2yJItihOQml8ZF7F5ZiIMFSQ=";
    };
    melian = {
      address = "${subnet}.3";
      publicKey = "2q6yye63F7NyNPwNNheo7MhY0Gw52MdV2+oYvZYed04=";
    };
    estella = {
      address = "${subnet}.5";
      publicKey = "dl7U16OFsj5wziRM/pR60aFhQL1Z1cVDXMIdxi//0mo=";
    };
  };

  peer = _: device: {
    inherit (device) publicKey;
    allowedIPs = ["${device.address}/32"];
  };
in {
  sops.secrets.wireguard-private-key = {};

  networking.wireguard.interfaces.wg0 = {
    ips = ["${bilbo}/24"];
    inherit listenPort;
    privateKeyFile = config.sops.secrets.wireguard-private-key.path;
    peers = builtins.attrValues (builtins.mapAttrs peer devices);
  };

  networking.firewall = {
    allowedUDPPorts = [listenPort];
    interfaces.wg0.allowedTCPPorts = [80 443];
  };
}
