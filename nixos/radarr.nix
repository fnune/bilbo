{config, ...}: let
  dataDir = "${config.users.users.fausto.home}/radarr";
in {
  services.radarr = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
    inherit dataDir;
  };
  systemd.services.radarr = {
    preStart = ''
      sed -i 's|<UrlBase>.*</UrlBase>|<UrlBase>/radarr</UrlBase>|' ${dataDir}/config.xml
    '';
  };
}
