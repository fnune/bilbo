{...}: {
  services.immich = {
    enable = true;
    user = "fausto";
    group = "users";
    mediaLocation = "/mnt/mirrored/immich";
  };
}
