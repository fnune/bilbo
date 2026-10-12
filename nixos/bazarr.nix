{
  config,
  lib,
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

  applySettings = pkgs.writeShellApplication {
    name = "bazarr-apply-settings";
    runtimeInputs = with pkgs; [curl jq yq-go];
    text = ''
      key=$(yq '.auth.apikey' ${cfg.dataDir}/config/config.yaml)
      bazarr() { curl --silent --show-error --fail --header "X-API-KEY: $key" "$@"; }

      for _ in $(seq 60); do
        bazarr ${api}/system/status >/dev/null 2>&1 && break
        sleep 2
      done

      bazarr --request POST ${api}/system/settings \
        ${lib.concatStringsSep " \\\n  " formFields} \
        --form "settings-opensubtitlescom-username=<$CREDENTIALS_DIRECTORY/opensubtitles-username" \
        --form "settings-opensubtitlescom-password=<$CREDENTIALS_DIRECTORY/opensubtitles-password"

      # Every series and movie gets the one profile, including those added before it existed.
      for kind in series:seriesid:sonarrSeriesId movies:radarrid:radarrId; do
        IFS=: read -r endpoint idField jsonId <<<"$kind"
        args=()
        while read -r id; do
          args+=(--data-urlencode "$idField=$id" --data-urlencode "profileid=${toString profileId}")
        done < <(bazarr "${api}/$endpoint" | jq -r ".data[] | select(.profileId != ${toString profileId}) | .$jsonId")
        if [ ''${#args[@]} -gt 0 ]; then
          bazarr --request POST "${api}/$endpoint" "''${args[@]}"
        fi
      done
    '';
  };
in {
  services.bazarr = {
    enable = true;
    group = "users";
  };

  sops.secrets = {
    opensubtitles-username = {};
    opensubtitles-password = {};
  };

  systemd.services.bazarr-settings = {
    description = "Apply Bazarr's settings from this repository";
    wantedBy = ["multi-user.target"];
    after = ["bazarr.service"];
    requires = ["bazarr.service"];
    restartTriggers = [applySettings];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = cfg.user;
      Group = cfg.group;
      ExecStart = lib.getExe applySettings;
      LoadCredential = [
        "opensubtitles-username:${config.sops.secrets.opensubtitles-username.path}"
        "opensubtitles-password:${config.sops.secrets.opensubtitles-password.path}"
      ];
    };
  };
}
