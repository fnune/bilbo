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

  # Original audio, English subtitles unless it's in Spanish. Jellyfin has no
  # "original language", so Spanish as the audio preference only decides when
  # subtitles show; the file's default track (the original) is what plays.
  userPlayback = {
    SubtitleMode = "Smart";
    SubtitleLanguagePreference = "eng";
    AudioLanguagePreference = "spa";
    PlayDefaultAudioTrack = true;
    RememberAudioSelections = true;
    RememberSubtitleSelections = true;
    EnableNextEpisodeAutoPlay = false;
  };
  # Bazarr is the only subtitle downloader; Jellyfin's search piles up out-of-sync copies.
  librarySubtitles = {
    SubtitleDownloadLanguages = [];
  };
  # Caddy connects from localhost; trusting it lets Jellyfin see real client addresses.
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
    # The UI's transcoding page stops mattering: this overwrites encoding.xml on every start.
    forceEncodingConfig = true;
    transcoding = {
      enableHardwareEncoding = true;
      # The J4125 (Gemini Lake) decodes these in hardware, per vainfo; it can't decode AV1.
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

  # MemoryDenyWriteExecute stays off for the .NET JIT, and ~@resources for its runtime's affinity and priority calls.
  systemd.services.jellyfin.serviceConfig = {
    ProtectSystem = lib.mkForce "strict";
    # Jellyfin can save artwork and metadata next to the media, and delete it.
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
      jellyfin() { # path [curl args...]
        local path=$1
        shift
        curl --silent --show-error --fail --header "Authorization: MediaBrowser Token=\"$(credential jellyfin-api-key)\"" \
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
