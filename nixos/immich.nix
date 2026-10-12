{pkgs, ...}: {
  environment.systemPackages = [pkgs.unstable.immich-cli pkgs.exiftool];
  services.postgresql.enable = true;
  services.immich = {
    enable = true;
    package = pkgs.unstable.immich;
    group = "users";
    mediaLocation = "/mnt/mirrored/immich";
    database = {
      user = "immich";
      name = "immich";
    };
    # Only what differs from Immich's defaults. This makes the admin settings page read-only.
    settings = {
      # Share links are built from this; photos.fnune.com is the public proxy.
      server.externalDomain = "https://photos.fnune.com";
      storageTemplate.enabled = true;
    };
  };
}
