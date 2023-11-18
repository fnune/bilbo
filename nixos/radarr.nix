{config, ...}: {
  services.radarr = {
    enable = true;
    user = "fausto";
    openFirewall = true;
    dataDir = "${config.users.users.fausto.home}/radarr";
  };
}
