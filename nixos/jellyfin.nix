{
  config,
  lib,
  mkSettingsService,
  mounts,
  ...
}: let
  inherit (config.services.jellyfin) user dataDir cacheDir;
  hardwareTranscodingGroups = ["render" "video"];

  api = "http://127.0.0.1:8096/jellyfin";

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

  sops.secrets.jellyfin-api-key = {};

  systemd.services.jellyfin-settings = mkSettingsService {
    name = "jellyfin-settings";
    description = "Apply Jellyfin's user and library settings from this repository";
    after = ["jellyfin"];
    secrets = ["jellyfin-api-key"];
    serviceConfig.DynamicUser = true;
    text = ''
      jellyfin() {
        local path=$1
        shift
        curl --silent --show-error --fail-with-body --header "Authorization: MediaBrowser Token=\"$(credential jellyfin-api-key)\"" \
          --header "Content-Type: application/json" "$@" "${api}$path"
      }

      wait_until_up ${api}/System/Info/Public

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
