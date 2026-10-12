{
  config,
  lib,
  libraries,
  mkSettingsService,
  servarrUrl,
  ...
}: let
  inherit (config.services) seerr;

  arr = name: implementation: extra:
    {
      inherit implementation;
      url = servarrUrl name;
      host = "127.0.0.1";
      inherit (config.services.${name}.settings.server) port;
      urlBase = config.services.${name}.settings.server.urlbase;
    }
    // extra;

  secrets = [
    "radarr-api-key"
    "sonarr-api-key"
    "servarr-username"
    "servarr-password"
    "nzbget-username"
    "nzbget-password"
    "nzbgeek-api-key"
    "jellyfin-admin-username"
    "jellyfin-admin-password"
  ];
in {
  sops.secrets = lib.genAttrs ["nzbgeek-api-key" "servarr-username" "servarr-password"] (_: {});

  systemd.services.arr-settings = mkSettingsService {
    name = "arr-settings";
    description = "Apply Radarr, Sonarr, Prowlarr and Seerr settings from this repository";
    after = ["radarr" "sonarr" "prowlarr" "seerr" "nzbget" "ntfy-sh"];
    softAfter = ["recyclarr-on-change" "jellyfin-settings"];
    inherit secrets;
    settings = {
      arrs = {
        radarr = arr "radarr" "Radarr" {
          rootFolder = libraries.movies;
          categoryField = "movieCategory";
          category = "Movies";
          seerrServer.minimumAvailability = "released";
        };
        sonarr = arr "sonarr" "Sonarr" {
          rootFolder = libraries.series;
          categoryField = "tvCategory";
          category = "Series";
          seerrServer.enableSeasonFolders = true;
        };
      };
      nzbget = {
        host = "127.0.0.1";
        port = 6789;
      };
      ntfy = {
        url = "http://${config.services.ntfy-sh.settings.listen-http}";
        topic = "bilbo";
      };
      prowlarr = {
        url = servarrUrl "prowlarr";
        configFile = "/var/lib/private/prowlarr/config.xml";
        indexer = "NZBgeek";
      };
      seerr = {
        url = "http://127.0.0.1:${toString seerr.port}/api/v1";
        settingsFile = "${seerr.configDir}/settings.json";
        profile = "1080p, then 720p";
        jellyfin = {
          hostname = "127.0.0.1";
          port = 8096;
          urlBase = "/jellyfin";
          useSsl = false;
        };
        main = {
          applicationUrl = "https://requests.fnune.com";
          localLogin = false;
        };
      };
    };
  };
}
