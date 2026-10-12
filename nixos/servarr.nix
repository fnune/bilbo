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
  # The key in sops is the source of truth, so a fresh install gets the same key the other services use.
  apiKeyFromSops = name: {
    environmentFiles = [config.sops.templates."${name}-api-key.env".path];
  };
  apiKeyEnv = name: {
    "${name}-api-key.env".content = "${lib.toUpper name}__AUTH__APIKEY=${config.sops.placeholder."${name}-api-key"}";
  };
in {
  services = {
    radarr = behindCaddy "radarr" // apiKeyFromSops "radarr" // {group = "users";};
    sonarr = behindCaddy "sonarr" // apiKeyFromSops "sonarr" // {group = "users";};
    prowlarr = behindCaddy "prowlarr";
  };

  sops = {
    secrets = {
      radarr-api-key = {};
      sonarr-api-key = {};
    };
    templates = apiKeyEnv "radarr" // apiKeyEnv "sonarr";
  };

  _module.args = rec {
    servarrAddress = name: "127.0.0.1:${toString config.services.${name}.settings.server.port}";
    servarrUrl = name: "http://${servarrAddress name}${config.services.${name}.settings.server.urlbase}";
  };
}
