{
  config,
  lib,
  pkgs,
  ...
}: let
  migrate = import ./migrate-state.nix pkgs;
  inherit (config.services.bazarr) user group dataDir;
in {
  services.bazarr = {
    enable = true;
    group = "users";
  };

  systemd.services.bazarr.serviceConfig.ExecStartPre = lib.mkBefore [
    (migrate {
      to = dataDir;
      owner = user;
      inherit group;
    })
  ];
}
