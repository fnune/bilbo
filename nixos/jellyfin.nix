{config, ...}: let
  inherit (config.services.jellyfin) user;
  hardwareTranscodingGroups = ["render" "video"];
in {
  services.jellyfin = {
    enable = true;
    group = "users";
  };

  users.users.${user}.extraGroups = hardwareTranscodingGroups;
}
