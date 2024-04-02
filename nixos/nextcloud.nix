{
  pkgs,
  config,
  ...
}: let
  host = "walrus-dorian.ts.net";
  packages = config.services.nextcloud.package.packages;
in {
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
      extraTrustedDomains = [host];
    };
  };
  services.nginx = {
    enable = true;
    virtualHosts = {
      "${host}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 8080;
          }
          {
            addr = "[::]";
            port = 8080;
          }
        ];
      };
    };
  };
}
