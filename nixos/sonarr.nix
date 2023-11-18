{config, ...}: {
  services.sonarr = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
    dataDir = "${config.users.users.fausto.home}/sonarr";
  };
}
