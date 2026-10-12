{
  config,
  lib,
  ...
}: let
  behindCaddy = name: {
    enable = true;
    settings = {
      server = {
        urlbase = "/${name}";
        bindaddress = "127.0.0.1";
      };
      # Caddy connects from localhost, so "no login for local addresses" would mean no login at all.
      auth = {
        method = "Forms";
        required = "Enabled";
      };
    };
  };
in {
  services = {
    radarr = behindCaddy "radarr" // {group = "users";};
    sonarr = behindCaddy "sonarr" // {group = "users";};
    prowlarr = behindCaddy "prowlarr";
  };

  _module.args = rec {
    servarrAddress = name: "127.0.0.1:${toString config.services.${name}.settings.server.port}";
    servarrUrl = name: "http://${servarrAddress name}${config.services.${name}.settings.server.urlbase}";
  };
}
