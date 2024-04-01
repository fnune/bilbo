{
  pkgs,
  config,
  ...
}: let
  packages = config.services.nextcloud.package.packages;
in {
  services.nextcloud = {
    enable = true;
    home = "/mnt/mirrored/nextcloud";
    package = pkgs.nextcloud28;
    extraApps = {
      inherit (packages.apps) memories;
    };
    extraAppsEnable = true;
    configureRedis = true;
  };
}
