{pkgs, ...}: let
  interface = "eno1";
in {
  systemd.services.set-ethernet-speed = {
    description = "Set Ethernet Speed to 1 Gbit/s";
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${interface} speed 1000 duplex full autoneg on";
    };
  };
}
