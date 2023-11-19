{...}: let
  host = "fnune.com";
in {
  networking.firewall.allowedTCPPorts = [80 443];
  services.tailscale.enable = true;
  services.caddy = {
    enable = true;
    # To set things up:
    # - https://dash.cloudflare.com
    # - https://login.tailscale.com
    virtualHosts = {
      # Eventually make this point to a dashboard:
      "bilbo.${host}".extraConfig = ''
        reverse_proxy localhost:8096
      '';

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
