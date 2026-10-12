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

  # Everything plays in its original audio, so English subtitles always show.
  userSubtitles = {
    SubtitleLanguagePreference = "eng";
    SubtitleMode = "Always";
  };
  # Bazarr is the only subtitle downloader; Jellyfin's search piles up out-of-sync copies.
  librarySubtitles = {
    SubtitleDownloadLanguages = [];
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
          jq -c '.configuration * ${builtins.toJSON userSubtitles}' <<<"$u" |
            jellyfin --request POST --data @- "${api}/Users/Configuration?userId=$id"
        done

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
