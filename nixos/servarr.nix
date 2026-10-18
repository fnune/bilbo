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

  bilbo.backups = let
    rebuildingLogsAndCovers = name: let
      inherit (config.services.${name}) dataDir;
    in {
      paths = [dataDir];
      exclude = ["${dataDir}/logs" "${dataDir}/MediaCover"];
    };
  in {
    radarr = rebuildingLogsAndCovers "radarr";
    sonarr = rebuildingLogsAndCovers "sonarr";
    prowlarr = {
      # Prowlarr uses DynamicUser, so /var/lib/prowlarr is a symlink, which Borg would back up as just a link.
      # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#DynamicUser=
      paths = ["/var/lib/private/prowlarr"];
      exclude = ["/var/lib/private/prowlarr/logs"];
    };
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
