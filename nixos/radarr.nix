{config, ...}: {
  services.radarr = {
    enable = true;
    user = "fausto";
    group = "users";
    openFirewall = true;
    dataDir = "${config.users.users.fausto.home}/radarr";
  };
}
