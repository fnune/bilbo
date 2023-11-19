{...}: let
  host = "walrus-dorian.ts.net";
in {
  networking.firewall.allowedTCPPorts = [80 443];
  services.tailscale = {
    enable = true;
    permitCertUid = "caddy";
  };
  services.caddy = {
    enable = true;
    virtualHosts = {
      "bilbo.${host}".extraConfig = ''
        handle /grafana* {
          reverse_proxy localhost:2342
        }

        reverse_proxy localhost:8096
      '';
    };
  };
}
