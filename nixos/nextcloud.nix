{
  pkgs,
  config,
  ...
}: let
  host = "walrus-dorian.ts.net";
  packages = config.services.nextcloud.package.packages;
in {
  services.nginx.enable = false;
  services.nextcloud = {
    enable = true;
    home = "/mnt/mirrored/nextcloud";
    hostName = host;
    package = pkgs.nextcloud28;
    extraApps = {
      inherit (packages.apps) memories;
    };
    extraAppsEnable = true;
    configureRedis = true;
    config = {
      adminpassFile = "/mnt/mirrored/nextcloud/nextcloud.apf";
    };
  };
}
