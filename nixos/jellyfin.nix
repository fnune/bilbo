{
  config,
  lib,
  pkgs,
  ...
}: let
  migrate = import ./migrate-state.nix pkgs;
  inherit (config.services.jellyfin) user group dataDir cacheDir;
  hardwareTranscodingGroups = ["render" "video"];
in {
  services.jellyfin = {
    enable = true;
    group = "users";
  };

  users.users.${user}.extraGroups = hardwareTranscodingGroups;

  systemd.services.jellyfin.serviceConfig.ExecStartPre = lib.mkBefore [
    (migrate {
      to = dataDir;
      owner = user;
      inherit group;
    })
    (migrate {
      to = cacheDir;
      owner = user;
      inherit group;
    })
  ];
}
