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
    configFile = pkgs.writeText "Caddyfile" ''
      jellyfin.${host} {
          reverse_proxy localhost:8096
      }

      nzbget.${host} {
          reverse_proxy localhost:6789
      }

      grafana.${host} {
          reverse_proxy localhost:2342
      }

      radarr.${host} {
          reverse_proxy localhost:7878
      }

      sonarr.${host} {
          reverse_proxy localhost:8989
      }
    '';
  };
}
