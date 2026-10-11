{
  config,
  lib,
  pkgs,
  ...
}: let
  migrate = import ./migrate-state.nix pkgs;
  inherit (config.services.sonarr) user group dataDir;
in {
  services.sonarr = {
    enable = true;
    group = "users";
    settings.server.urlbase = "/sonarr";
  };

  systemd.services.sonarr.serviceConfig.ExecStartPre = lib.mkBefore [
    (migrate {
      from = "/home/fausto/sonarr";
      to = dataDir;
      owner = user;
      inherit group;
    })
  ];
}
