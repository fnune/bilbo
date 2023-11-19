{config, ...}: let
  host = "fnune.com";
in {
  age.secrets.cloudflare-api-token.file = ../secrets/cloudflare-api-token.age;
  systemd.services.caddy.serviceConfig = {
    LoadCredential = "CF_API_TOKEN:${config.age.secrets.cloudflare-api-token.path}";
  };

  networking.firewall.allowedTCPPorts = [80 443];
  services.tailscale.enable = true;
  services.caddy = {
    enable = true;
    globalConfig = ''
      acme_dns cloudflare {env.CF_API_TOKEN}
    '';
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
