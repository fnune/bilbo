{...}: {
  services.postgresql = {
    enable = true;
    ensureUsers = [{name = "fausto";}];
  };
  services.immich = {
    enable = true;
    group = "users";
    mediaLocation = "/mnt/mirrored/immich";
    database = {
      user = "immich";
      name = "immich";
    };
  };
}
