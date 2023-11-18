{...}: {
  services.jellyfin = {
    enable = true;
    user = "fausto";
  };
  networking.firewall.allowedTCPPorts = [8096];
}
