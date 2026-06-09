{
  config,
  lib,
  ...
}: let
  dataDir = "${config.users.users.fausto.home}/sonarr";
in {
  services.sonarr = {
    enable = true;
    user = "fausto";
    group = "users";
    inherit dataDir;
    settings.server.urlbase = "/sonarr";
  };
  # 26.05 hardened the unit with ProtectHome (https://github.com/NixOS/nixpkgs/pull/483483),
  # which would hide our /home dataDir from the service.
  systemd.services.sonarr.serviceConfig.ProtectHome = lib.mkForce false;
}
