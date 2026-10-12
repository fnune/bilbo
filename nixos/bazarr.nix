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
    # Bazarr fetches every language listed, so these are limited to their own audio.
    items = [
      (item 1 "en" {})
      (item 2 "es" {})
      (item 3 "ca" {audio_only_include = "True";})
      (item 4 "ja" {audio_only_include = "True";})
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
    # Takes effect on Bazarr's next restart; Caddy is the only client.
    "settings-general-ip" = "127.0.0.1";
    # Caddy reaches it from localhost, so a login is the only gate on the LAN address.
    "settings-auth-type" = "form";
    "settings-general-serie_default_enabled" = true;
    "settings-general-serie_default_profile" = profileId;
    "settings-general-movie_default_enabled" = true;
    "settings-general-movie_default_profile" = profileId;
    # A subtitle track on the disc is timed for it; count it and download nothing.
    "settings-general-use_embedded_subs" = true;
    "settings-general-ignore_pgs_subs" = false;
    "settings-general-enabled_providers" = ["opensubtitlescom" "podnapisi" "gestdown"];
    "settings-opensubtitlescom-use_hash" = true;
    # Re-time every download against the audio, whatever its score.
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

  # Subtitle syncs read whole video files; let playback and Frigate go first.
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
      bazarr() { # path [curl args...]
        local path=$1
        shift
        curl --silent --show-error --fail --header "X-API-KEY: $(yq .auth.apikey ${cfg.dataDir}/config/config.yaml)" \
          "$@" "${api}$path"
      }

      assign_profile() { # endpoint id-parameter id-field
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

      # Every series and movie gets the one profile, including those added before it existed.
      assign_profile series seriesid sonarrSeriesId
      assign_profile movies radarrid radarrId
    '';
  };
}
