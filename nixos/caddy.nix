{
  pkgs,
  lib,
  ...
}: let
  domain = "fnune.com";
  bilbo = "bilbo.${domain}";
  immich = "immich.${domain}";
  calibre = "calibre.${domain}";

  dnsOnlyHosts = [immich calibre];

  mkDyndns = hostname: let
    slug = lib.replaceStrings ["."] ["-"] hostname;
  in
    pkgs.writeShellApplication {
      name = "dyndns-${slug}";
      runtimeInputs = with pkgs; [curl jq];
      text = ''
        TOKEN=$(cat /etc/cloudflare/token)
        IP=$(curl -sf https://api.ipify.org)

        ZONE_ID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
          "https://api.cloudflare.com/client/v4/zones?name=${domain}" | jq -r '.result[0].id')

        RECORD=$(curl -sf -H "Authorization: Bearer $TOKEN" \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=${hostname}&type=A")

        RECORD_ID=$(echo "$RECORD" | jq -r '.result[0].id')

        if [ "$RECORD_ID" = "null" ]; then
          curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"${hostname}\",\"content\":\"$IP\",\"proxied\":false}" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"
        else
          curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            -d "{\"type\":\"A\",\"name\":\"${hostname}\",\"content\":\"$IP\",\"proxied\":false}" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID"
        fi
      '';
    };

  mkDyndnsService = hostname: let
    slug = lib.replaceStrings ["."] ["-"] hostname;
    app = mkDyndns hostname;
  in {
    name = "dyndns-${slug}";
    value = {
      description = "Update Cloudflare DNS for ${hostname} (DNS-only, no proxy)";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      startAt = "*:0/5";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${app}/bin/dyndns-${slug}";
      };
    };
  };
in {
  networking.firewall = {
    allowedTCPPorts = [443];
    interfaces = {
      "eno1" = {
        allowedTCPPorts = [80];
      };
    };
  };

  systemd.services =
    (lib.listToAttrs (map mkDyndnsService dnsOnlyHosts))
    // {
      caddy.serviceConfig.EnvironmentFile = "/etc/cloudflare/caddy-env";
    };

  services = {
    cloudflare-dyndns = {
      enable = true;
      proxied = true;
      domains = [bilbo];
      apiTokenFile = "/etc/cloudflare/token";
    };
    caddy = let
      cloudflareToken = "{$CLOUDFLARE_API_TOKEN}";
      tlsDnsCloudflare = ''
        tls {
          dns cloudflare ${cloudflareToken}
        }
      '';
      proxiesSupportingSubpath = ''
        reverse_proxy /grafana/* localhost:2342
        reverse_proxy /grafana localhost:2342

        reverse_proxy /nzbget/* localhost:6789
        reverse_proxy /nzbget localhost:6789

        reverse_proxy /radarr/* localhost:7878
        reverse_proxy /radarr localhost:7878

        reverse_proxy /sonarr/* localhost:8989
        reverse_proxy /sonarr localhost:8989

        reverse_proxy /bazarr/* 127.0.0.1:6767
        reverse_proxy /bazarr 127.0.0.1:6767

        redir /lazylibrarian /lazylibrarian/ 308
        reverse_proxy /lazylibrarian/* localhost:5299

        redir /calibre /calibre/ 308
        reverse_proxy /calibre/* 127.0.0.1:8083 {
          header_up X-Script-Name /calibre
          header_up X-Scheme {scheme}
          header_up X-Forwarded-Host {host}
        }

        reverse_proxy /filebrowser/* localhost:8080
        reverse_proxy /filebrowser localhost:8080

        reverse_proxy /jellyfin/* localhost:8096
        reverse_proxy /jellyfin localhost:8096

        reverse_proxy /pincho/* localhost:3210
        reverse_proxy /pincho localhost:3210

      '';
      rootIsHomepage = ''
        reverse_proxy /* localhost:8082
        reverse_proxy / localhost:8082
      '';
      rootIsImmich = ''
        reverse_proxy /* localhost:2283
        reverse_proxy / localhost:2283
      '';
      rootIsCalibre = ''
        reverse_proxy /* 127.0.0.1:8083 {
          header_up X-Scheme {scheme}
        }
        reverse_proxy / 127.0.0.1:8083 {
          header_up X-Scheme {scheme}
        }
      '';
      tlsOriginKey = ''
        tls /etc/cloudflare/origin-cert.pem /etc/cloudflare/origin-key.pem
      '';
    in {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
        hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
      };
      virtualHosts = {
        "${immich}".extraConfig = ''
          ${tlsDnsCloudflare}
          ${rootIsImmich}
        '';
        "${calibre}".extraConfig = ''
          ${tlsDnsCloudflare}
          ${rootIsCalibre}
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
