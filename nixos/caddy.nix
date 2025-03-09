{...}: let
  host = "bilbo.fnune.com";
  local = "192.168.178.36";
in {
  networking.firewall.allowedTCPPorts = [80 443];
  services = {
    cloudflare-dyndns = {
      enable = false;
      domains = [host];
    };
    caddy = let
      proxies = ''
        reverse_proxy /grafana/* localhost:2342
        reverse_proxy /grafana localhost:2342

        reverse_proxy /nzbget/* localhost:6789
        reverse_proxy /nzbget localhost:6789

        reverse_proxy /radarr/* localhost:7878
        reverse_proxy /radarr localhost:7878

        reverse_proxy /sonarr/* localhost:8989
        reverse_proxy /sonarr localhost:8989

        reverse_proxy /bazarr/* localhost:6767
        reverse_proxy /bazarr localhost:6767

        reverse_proxy /readarr/* localhost:8787
        reverse_proxy /readarr localhost:8787

        reverse_proxy /jellyfin/* localhost:8096
        reverse_proxy /jellyfin localhost:8096
      '';
    in {
      enable = true;
      virtualHosts = {
        "${host}".extraConfig = proxies;
        "${local}" = {
          listenAddresses = ["${local}:80"];
          extraConfig = ''
            auto_https off

            ${proxies}
          '';
        };
      };
    };
  };
}
