{
  config,
  lib,
  mkSettingsService,
  ...
}: let
  cfg = config.services.bazarr;
  baseUrl = "/bazarr";
  api = "http://127.0.0.1:${toString cfg.listenPort}${baseUrl}/api";

  onlyWhenAudioIsThatLanguage = {audio_only_include = "True";};
  item = id: language: extra:
    {
      inherit id language;
      audio_exclude = "False";
      audio_only_include = "False";
      hi = "False";
      forced = "False";
    }
    // extra;
  profileId = 1;
  english = item 1 "en" {};
  languageProfile = {
    inherit profileId;
    name = "English, Spanish, and the original if Catalan or Japanese";
    items = [
      english
      (item 2 "es" {})
      (item 3 "ca" onlyWhenAudioIsThatLanguage)
      (item 4 "ja" onlyWhenAudioIsThatLanguage)
    ];
    cutoff = english.id;
    mustContain = [];
    mustNotContain = [];
    originalFormat = null;
    tag = null;
  };

  formSettings =
    arrConnection "sonarr"
    // arrConnection "radarr"
    // {
      "languages-enabled" = map (i: i.language) languageProfile.items;
      "languages-profiles" = builtins.toJSON [languageProfile];
      "settings-general-base_url" = baseUrl;
      "settings-general-use_sonarr" = true;
      "settings-general-use_radarr" = true;
      "settings-general-ip" = "127.0.0.1";
      "settings-auth-type" = "form";
      "settings-general-serie_default_enabled" = true;
      "settings-general-serie_default_profile" = profileId;
      "settings-general-movie_default_enabled" = true;
      "settings-general-movie_default_profile" = profileId;
      "settings-general-use_embedded_subs" = true;
      "settings-general-ignore_pgs_subs" = false;
      "settings-general-enabled_providers" = ["opensubtitlescom" "gestdown" "subf2m" "yifysubtitles" "subtitulamostv" "tvsubtitles"];
      "settings-opensubtitlescom-use_hash" = true;
      "settings-subsync-use_subsync" = true;
      "settings-subsync-use_subsync_threshold" = false;
      "settings-subsync-use_subsync_movie_threshold" = false;
    };

  arrConnection = name: let
    server = config.services.${name}.settings.server;
  in {
    "settings-${name}-ip" = "127.0.0.1";
    "settings-${name}-port" = server.port;
    "settings-${name}-base_url" = server.urlbase;
    "settings-${name}-ssl" = false;
  };

  secretFields = {
    settings-opensubtitlescom-username = "opensubtitles-username";
    settings-opensubtitlescom-password = "opensubtitles-password";
    settings-auth-username = "bazarr-username";
    settings-auth-password = "bazarr-password";
    settings-sonarr-apikey = "sonarr-api-key";
    settings-radarr-apikey = "radarr-api-key";
  };

  formValue = value:
    if builtins.isBool value
    then lib.boolToString value
    else toString value;
  formFields = lib.concatLists (lib.mapAttrsToList (key: value: map (item: [key (formValue item)]) (lib.toList value)) formSettings);
in {
  services.bazarr = {
    enable = true;
    group = "users";
  };

  sops.secrets = lib.genAttrs ["opensubtitles-username" "opensubtitles-password" "bazarr-username" "bazarr-password"] (_: {});

  systemd.services.bazarr.serviceConfig = {
    Nice = 10;
    IOSchedulingClass = "idle";
  };

  systemd.services.bazarr-settings = mkSettingsService {
    name = "bazarr-settings";
    description = "Apply Bazarr's settings from this repository";
    after = ["bazarr"];
    secrets = builtins.attrValues secretFields;
    serviceConfig = {
      User = cfg.user;
      Group = cfg.group;
    };
    settings = {
      inherit profileId;
      url = api;
      configFile = "${cfg.dataDir}/config/config.yaml";
      fields = formFields;
      inherit secretFields;
    };
  };

  bilbo.backups.bazarr = {
    paths = [cfg.dataDir];
    exclude = ["${cfg.dataDir}/log"];
  };
}
