{config, ...}: let
  dataDir = "${config.users.users.fausto.home}/sonarr";
in {
  services.sonarr = {
    enable = true;
    user = "fausto";
    group = "users";
    inherit dataDir;
  };
  systemd.services.sonarr = {
    preStart = ''
      sed -i 's|<UrlBase>.*</UrlBase>|<UrlBase>/sonarr</UrlBase>|' ${dataDir}/config.xml
    '';
  };
}
