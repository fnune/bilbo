{config, ...}: {
  services.radarr = {
    enable = true;
    user = "fausto";
    dataDir = "${config.users.users.fausto.home}/radarr";
  };
  networking.firewall.allowedTCPPorts = [7878];
}
