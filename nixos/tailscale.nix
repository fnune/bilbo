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
        reverse_proxy /grafana/* localhost:2342
        reverse_proxy /grafana localhost:2342

        reverse_proxy /nzbget/* localhost:6789
        reverse_proxy /nzbget localhost:6789

        reverse_proxy /radarr/* localhost:7878
        reverse_proxy /radarr localhost:7878

        reverse_proxy /sonarr/* localhost:8989
        reverse_proxy /sonarr localhost:8989

        reverse_proxy /nextcloud/* localhost:80
        reverse_proxy /nextcloud localhost:80

        reverse_proxy localhost:8096
      '';
    };
  };
}
