{pkgs, ...}: {
  environment.systemPackages = [pkgs.unstable.immich-cli pkgs.exiftool];
  services.postgresql = {
    enable = true;
    ensureUsers = [{name = "fausto";}];
  };
  services.immich = {
    enable = true;
    package = pkgs.unstable.immich;
    group = "users";
    mediaLocation = "/mnt/mirrored/immich";
    database = {
      user = "immich";
      name = "immich";
    };
  };
}
