{
  config,
  lib,
  mounts,
  ...
}: let
  inherit (config.services.jellyfin) user dataDir cacheDir;
  hardwareTranscodingGroups = ["render" "video"];
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
}
