{pkgs, ...}: let
  caddyUser = "caddy";
  host = "bilbo.taile08bf.ts.net";
in {
  services.tailscale = {
    enable = true;
    permitCertUid = caddyUser;
  };
  services.caddy = {
    enable = true;
    user = caddyUser;
    virtualHosts = {
      "jellyfin.${host}".extraConfig = ''
        reverse_proxy localhost:8096
      '';

      "nzbget.${host}".extraConfig = ''
        reverse_proxy localhost:6789
      '';

      "grafana.${host}".extraConfig = ''
        reverse_proxy localhost:2342
      '';

      "radarr.${host}".extraConfig = ''
        reverse_proxy localhost:7878
      '';

      "sonarr.${host}".extraConfig = ''
        reverse_proxy localhost:8989
      '';
    };
  };
}
