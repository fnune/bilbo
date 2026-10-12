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

  libraryCollections = {
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
  libraryOptions = {
    SubtitleDownloadLanguages = [];
  };
  network = {
    KnownProxies = ["127.0.0.1"];
  };
  startup = {
    UICulture = "en-US";
    MetadataCountryCode = "DE";
    PreferredMetadataLanguage = "en";
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
    settings = {
      url = "http://127.0.0.1:8096/jellyfin";
      client = ''MediaBrowser Client="bilbo", Device="bilbo", DeviceId="jellyfin-settings", Version="1"'';
      libraries = libraryCollections;
      inherit userPlayback libraryOptions network startup;
    };
  };
}
