{
  config,
  lib,
  mkSettingsService,
  pkgs,
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
  languageProfile = {
    inherit profileId;
    name = "English, Spanish, and the original if Catalan or Japanese";
    items = [
      (item 1 "en" {})
      (item 2 "es" {})
      (item 3 "ca" onlyWhenAudioIsThatLanguage)
      (item 4 "ja" onlyWhenAudioIsThatLanguage)
    ];
    cutoff = null;
    mustContain = [];
    mustNotContain = [];
    originalFormat = null;
    tag = null;
  };

  settings = {
    "languages-enabled" = map (i: i.language) languageProfile.items;
    "languages-profiles" = builtins.toJSON [languageProfile];
    "settings-general-base_url" = baseUrl;
    "settings-general-ip" = "127.0.0.1";
    "settings-auth-type" = "form";
    "settings-general-serie_default_enabled" = true;
    "settings-general-serie_default_profile" = profileId;
    "settings-general-movie_default_enabled" = true;
    "settings-general-movie_default_profile" = profileId;
    "settings-general-use_embedded_subs" = true;
    "settings-general-ignore_pgs_subs" = false;
    "settings-general-enabled_providers" = ["opensubtitlescom" "podnapisi" "gestdown"];
    "settings-opensubtitlescom-use_hash" = true;
    "settings-subsync-use_subsync" = true;
    "settings-subsync-use_subsync_threshold" = false;
    "settings-subsync-use_subsync_movie_threshold" = false;
  };

  formFields = lib.concatLists (lib.mapAttrsToList (key: value:
    map (v: "--form-string ${lib.escapeShellArg "${key}=${
      if builtins.isBool v
      then lib.boolToString v
      else toString v
    }"}") (lib.toList value))
  settings);
in {
  services.bazarr = {
    enable = true;
    group = "users";
  };

  sops.secrets = {
    opensubtitles-username = {};
    opensubtitles-password = {};
    bazarr-username = {};
    bazarr-password = {};
  };

  systemd.services.bazarr.serviceConfig = {
    Nice = 10;
    IOSchedulingClass = "idle";
  };

  systemd.services.bazarr-settings = mkSettingsService {
    name = "bazarr-settings";
    description = "Apply Bazarr's settings from this repository";
    after = ["bazarr"];
    secrets = ["opensubtitles-username" "opensubtitles-password" "bazarr-username" "bazarr-password"];
    runtimeInputs = [pkgs.yq-go];
    serviceConfig = {
      User = cfg.user;
      Group = cfg.group;
    };
    text = ''
      bazarr() {
        local path=$1
        shift
        curl --silent --show-error --fail --header "X-API-KEY: $(yq .auth.apikey ${cfg.dataDir}/config/config.yaml)" \
          "$@" "${api}$path"
      }

      assign_profile() {
        local args=()
        while read -r id; do
          args+=(--data-urlencode "$2=$id" --data-urlencode "profileid=${toString profileId}")
        done < <(bazarr "/$1" | jq -r ".data[] | select(.profileId != ${toString profileId}) | .$3")
        if [ ''${#args[@]} -gt 0 ]; then
          bazarr "/$1" --request POST "''${args[@]}"
        fi
      }

      wait_until_up ${api}

      bazarr /system/settings --request POST \
        ${lib.concatStringsSep " \\\n  " formFields} \
        --form "settings-opensubtitlescom-username=<$CREDENTIALS_DIRECTORY/opensubtitles-username" \
        --form "settings-opensubtitlescom-password=<$CREDENTIALS_DIRECTORY/opensubtitles-password" \
        --form "settings-auth-username=<$CREDENTIALS_DIRECTORY/bazarr-username" \
        --form "settings-auth-password=<$CREDENTIALS_DIRECTORY/bazarr-password"

      assign_profile series seriesid sonarrSeriesId
      assign_profile movies radarrid radarrId
    '';
  };
}
