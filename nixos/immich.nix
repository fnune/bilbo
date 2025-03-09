{...}: {
  services.postgresql = {
    enable = true;
    ensureUsers = [{name = "fausto";}];
  };
  services.immich = {
    enable = true;
    user = "fausto";
    group = "users";
    mediaLocation = "/mnt/mirrored/immich";
  };
}
