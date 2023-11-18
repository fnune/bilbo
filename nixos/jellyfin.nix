{...}: {
  services.jellyfin = {
    enable = true;
    user = "fausto";
    group = "users";
  };
  networking.firewall.allowedTCPPorts = [8096];
}
