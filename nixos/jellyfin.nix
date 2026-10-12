{
  config,
  lib,
  mounts,
  pkgs,
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

  applySettings = pkgs.writeShellApplication {
    name = "jellyfin-apply-settings";
    runtimeInputs = with pkgs; [curl jq];
    text = ''
      token=$(cat "$CREDENTIALS_DIRECTORY/jellyfin-api-key")
      jellyfin() {
        curl --silent --show-error --fail \
          --header "Authorization: MediaBrowser Token=\"$token\"" \
          --header "Content-Type: application/json" "$@"
      }

      for _ in $(seq 60); do
        curl --silent --fail ${api}/System/Info/Public >/dev/null && break
        sleep 2
      done

      jellyfin ${api}/Users | jq -c '.[] | {id: .Id, configuration: .Configuration}' |
        while read -r u; do
          id=$(jq -r .id <<<"$u")
          jq -c '.configuration * ${builtins.toJSON userPlayback}' <<<"$u" |
            jellyfin --request POST --data @- "${api}/Users/Configuration?userId=$id"
        done

      jellyfin ${api}/System/Configuration/network | jq -c '. * ${builtins.toJSON network}' |
        jellyfin --request POST --data @- ${api}/System/Configuration/network

      jellyfin ${api}/Library/VirtualFolders | jq -c '.[] | {Id: .ItemId, LibraryOptions: (.LibraryOptions * ${builtins.toJSON librarySubtitles})}' |
        while read -r library; do
          jellyfin --request POST --data "$library" ${api}/Library/VirtualFolders/LibraryOptions
        done
    '';
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

  systemd.services.jellyfin-settings = {
    description = "Apply Jellyfin's user and library settings from this repository";
    wantedBy = ["multi-user.target"];
    after = ["jellyfin.service"];
    requires = ["jellyfin.service"];
    restartTriggers = [applySettings];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      DynamicUser = true;
      ExecStart = lib.getExe applySettings;
      LoadCredential = ["jellyfin-api-key:${config.sops.secrets.jellyfin-api-key.path}"];
    };
  };
}
