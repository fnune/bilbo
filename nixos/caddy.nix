{...}: let
  domain = "fnune.com";
  bilbo = "bilbo.${domain}";
  immich = "immich.${domain}";
in {
  networking.firewall = {
    allowedTCPPorts = [443];
    interfaces = {
      "eno1" = {
        allowedTCPPorts = [80];
      };
    };
  };
  services = {
    cloudflare-dyndns = {
      enable = true;
      proxied = true;
      domains = [bilbo immich];
      apiTokenFile = "/etc/cloudflare/token";
    };
    caddy = let
      proxiesSupportingSubpath = ''
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

        reverse_proxy /filebrowser/* localhost:8080
        reverse_proxy /filebrowser localhost:8080

        reverse_proxy /jellyfin/* localhost:8096
        reverse_proxy /jellyfin localhost:8096

        redir /syncthing /syncthing/
        handle_path /syncthing/* {
          reverse_proxy localhost:8384 {
            header_up Host {upstream_hostport}
          }
        }

        redir /emulation /emulation/
        handle_path /emulation/* {
          root * /mnt/downloads-2t/Emulation/_config
          file_server browse
        }
      '';
      rootIsHomepage = ''
        reverse_proxy /* localhost:8082
        reverse_proxy / localhost:8082
      '';
      rootIsImmich = ''
        reverse_proxy /* localhost:2283
        reverse_proxy / localhost:2283
      '';
      tlsOriginKey = ''
        tls /etc/cloudflare/origin-cert.pem /etc/cloudflare/origin-key.pem
      '';
    in {
      enable = true;
      virtualHosts = {
        "${immich}".extraConfig = ''
          ${tlsOriginKey}
          ${rootIsImmich}
        '';
        "${bilbo}".extraConfig = ''
          ${tlsOriginKey}
          ${rootIsHomepage}
          ${proxiesSupportingSubpath}
        '';
        ":80".extraConfig = ''
          ${proxiesSupportingSubpath}
          ${rootIsImmich}
        '';
      };
    };
  };
}
