{
  config,
  lib,
  libraries,
  mkSettingsService,
  mounts,
  ...
}: let
  inherit (config.services.jellyfin) user dataDir cacheDir;
  hardwareTranscodingGroups = ["render" "video"];

  api = "http://127.0.0.1:8096/jellyfin";
  client = ''MediaBrowser Client="bilbo", Device="bilbo", DeviceId="jellyfin-settings", Version="1"'';

  jellyfinLibraries = {
    Movies = {
      collectionType = "movies";
      path = libraries.movies;
    };
    Series = {
      collectionType = "tvshows";
      path = libraries.series;
    };
  };

  userPlayback = {
    SubtitleMode = "Smart";
    SubtitleLanguagePreference = "eng";
    # Jellyfin has no "original language". Spanish here only means "no subtitles for Spanish audio";
    # PlayDefaultAudioTrack keeps the file's own audio, which is the original.
    AudioLanguagePreference = "spa";
    PlayDefaultAudioTrack = true;
    RememberAudioSelections = true;
    RememberSubtitleSelections = true;
    EnableNextEpisodeAutoPlay = false;
  };
  librarySubtitles = {
    SubtitleDownloadLanguages = [];
  };
  network = {
    KnownProxies = ["127.0.0.1"];
  };
in {
  services.jellyfin = {
    enable = true;
    group = "users";
    hardwareAcceleration = {
      enable = true;
      type = "vaapi";
      device = "/dev/dri/renderD128";
    };
    forceEncodingConfig = true;
    transcoding = {
      enableHardwareEncoding = true;
      # What this Celeron J4125 decodes in hardware, per vainfo. It can't decode AV1.
      # https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        mpeg2 = true;
        vc1 = true;
        vp8 = true;
        vp9 = true;
      };
      throttleTranscoding = true;
    };
  };

  users.users.${user}.extraGroups = hardwareTranscodingGroups;

  systemd.services.jellyfin.serviceConfig = {
    # MemoryDenyWriteExecute stays off: .NET compiles code at runtime.
    ProtectSystem = lib.mkForce "strict";
    ReadWritePaths = [dataDir cacheDir mounts.downloads-1t mounts.downloads-2t];
    ProtectHome = true;
    DeviceAllow = ["char-drm rw"];
  };

  sops.secrets = lib.genAttrs ["jellyfin-admin-username" "jellyfin-admin-password"] (_: {});

  systemd.services.jellyfin-settings = mkSettingsService {
    name = "jellyfin-settings";
    description = "Apply Jellyfin's user and library settings from this repository";
    after = ["jellyfin"];
    secrets = ["jellyfin-admin-username" "jellyfin-admin-password"];
    serviceConfig.DynamicUser = true;
    text = ''
      client=${lib.escapeShellArg client}
      admin=$(jq -n --arg name "$(credential jellyfin-admin-username)" --arg password "$(credential jellyfin-admin-password)" \
        '{Name: $name, Password: $password}')

      anonymous() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "Authorization: $client" \
          --header "Content-Type: application/json" "$@" "${api}$path"
      }

      wait_until_up ${api}/System/Info/Public

      if anonymous /System/Info/Public | jq -e '.StartupWizardCompleted | not' >/dev/null; then
        anonymous /Startup/Configuration --request POST \
          --data '{"UICulture": "en-US", "MetadataCountryCode": "DE", "PreferredMetadataLanguage": "en"}'
        anonymous /Startup/User >/dev/null
        anonymous /Startup/User --request POST --data "$admin"
        anonymous /Startup/Complete --request POST
      fi

      token=$(jq '{Username: .Name, Pw: .Password}' <<<"$admin" |
        anonymous /Users/AuthenticateByName --request POST --data @- | jq -r .AccessToken)

      jellyfin() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "Authorization: $client, Token=\"$token\"" \
          --header "Content-Type: application/json" "$@" "${api}$path"
      }

      ${lib.concatStrings (lib.mapAttrsToList (name: library: ''
          if ! jellyfin /Library/VirtualFolders | jq -e 'any(.[]; .Locations | index("${library.path}"))' >/dev/null; then
            jellyfin "/Library/VirtualFolders?name=${name}&collectionType=${library.collectionType}&paths=${library.path}&refreshLibrary=true" \
              --request POST --data '{"LibraryOptions": {}}'
          fi
        '')
        jellyfinLibraries)}

      jellyfin /Users | jq -c '.[] | {id: .Id, configuration: (.Configuration * ${builtins.toJSON userPlayback})}' |
        while read -r user; do
          jq -c .configuration <<<"$user" |
            jellyfin "/Users/Configuration?userId=$(jq -r .id <<<"$user")" --request POST --data @-
        done

      jellyfin /System/Configuration/network | jq -c '. * ${builtins.toJSON network}' |
        jellyfin /System/Configuration/network --request POST --data @-

      jellyfin /Library/VirtualFolders | jq -c '.[] | {Id: .ItemId, LibraryOptions: (.LibraryOptions * ${builtins.toJSON librarySubtitles})}' |
        while read -r library; do
          jellyfin /Library/VirtualFolders/LibraryOptions --request POST --data "$library"
        done
    '';
  };
}
