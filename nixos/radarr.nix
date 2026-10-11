{
  config,
  lib,
  pkgs,
  ...
}: let
  migrate = import ./migrate-state.nix pkgs;
  inherit (config.services.radarr) user group dataDir;
in {
  services.radarr = {
    enable = true;
    group = "users";
    settings.server.urlbase = "/radarr";
  };

  systemd.services.radarr.serviceConfig.ExecStartPre = lib.mkBefore [
    (migrate {
      from = "/home/fausto/radarr";
      to = dataDir;
      owner = user;
      inherit group;
    })
  ];
}
