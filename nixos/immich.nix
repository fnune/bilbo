{pkgs, ...}: {
  environment.systemPackages = with pkgs; [immich-cli exiftool];
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
