{...}: {
  networking.firewall.allowedTCPPorts = [3000];
  services.invidious = {
    enable = true;
    settings = {
      db = {
        user = "invidious";
      };
    };
  };
}
