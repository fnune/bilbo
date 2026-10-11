{
  config,
  lib,
  pkgs,
  ...
}: let
  migrate = import ./migrate-state.nix pkgs;
  inherit (config.services.nzbget) user group;
in {
  services.nzbget = {
    enable = true;
    group = "users";
  };

  systemd.services.nzbget.serviceConfig.ExecStartPre = lib.mkBefore [
    (migrate {
      to = "/var/lib/nzbget";
      owner = user;
      inherit group;
    })
  ];
}
