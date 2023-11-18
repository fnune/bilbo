{...}: {
  services.nzbget = {
    enable = true;
    user = "fausto";
  };
  networking.firewall.allowedTCPPorts = [6789];
}
